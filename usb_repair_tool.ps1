#requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Choice {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [Parameter(Mandatory=$true)][string[]]$Allowed
    )

    $allowedSet = @{}
    foreach ($a in $Allowed) { $allowedSet[$a.ToUpperInvariant()] = $true }

    while ($true) {
        $v = Read-Host $Prompt
        if ($null -eq $v) { continue }
        $t = $v.Trim().ToUpperInvariant()
        if ($allowedSet.ContainsKey($t)) { return $t }
        Write-Host ("Invalid choice. Options: {0}" -f ($Allowed -join ', ')) -ForegroundColor Yellow
    }
}

function Read-IntInRange {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [Parameter(Mandatory=$true)][int]$Min,
        [Parameter(Mandatory=$true)][int]$Max
    )
    while ($true) {
        $v = Read-Host $Prompt
        if ($null -eq $v) { continue }
        $t = $v.Trim()
        if ($t -match '^\d+$') {
            $n = [int]$t
            if ($n -ge $Min -and $n -le $Max) { return $n }
        }
        Write-Host ("Invalid value (expected: integer between {0} and {1})." -f $Min, $Max) -ForegroundColor Yellow
    }
}

function Assert-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run as Administrator."
    }
}

function Get-RemovableDisks {
    Get-Disk |
        Where-Object { $_.BusType -in @('USB', 'SD') -or $_.FriendlyName -match 'USB' -or $_.Location -match 'USB' } |
        Sort-Object Number
}

function Show-Disks($disks) {
    if (-not $disks -or $disks.Count -eq 0) {
        Write-Host 'No USB disk detected. Plug in the drive, wait 5 seconds, then run again.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host 'Detected disks (USB candidates):' -ForegroundColor Cyan
    $disks | ForEach-Object {
        $sizeGb = [Math]::Round($_.Size / 1GB, 2)
        $isSystem = $_.IsSystem
        $isBoot = $_.IsBoot
        $isReadOnly = $_.IsReadOnly
        $isOffline = $_.IsOffline
        Write-Host ("- Disk {0}: {1} | {2} GB | BusType={3} | System={4} Boot={5} ReadOnly={6} Offline={7}" -f $_.Number, $_.FriendlyName, $sizeGb, $_.BusType, $isSystem, $isBoot, $isReadOnly, $isOffline)
    }
    Write-Host ''
}

function Read-NonEmpty($prompt) {
    while ($true) {
        $v = Read-Host $prompt
        if ($null -ne $v -and $v.Trim().Length -gt 0) { return $v.Trim() }
    }
}

function Confirm-Destructive($diskNumber) {
    Write-Host '*** DANGER ***' -ForegroundColor Red
    Write-Host ("You selected Disk {0}. This operation WILL ERASE EVERYTHING on this disk." -f $diskNumber) -ForegroundColor Red
    Write-Host 'To continue, you must confirm twice.' -ForegroundColor Yellow

    $c1 = Read-NonEmpty "Type exactly: WIPE-DISK-$diskNumber"
    if ($c1 -ne "WIPE-DISK-$diskNumber") { throw 'Confirmation #1 failed. Aborting.' }

    $c2 = Read-NonEmpty "Retype exactly: WIPE-DISK-$diskNumber"
    if ($c2 -ne "WIPE-DISK-$diskNumber") { throw 'Confirmation #2 failed. Aborting.' }
}

function Invoke-Diskpart {
    param(
        [Parameter(Mandatory=$true)][string[]]$ScriptLines,
        [Parameter(Mandatory=$true)][int]$TimeoutSeconds
    )

    $temp = [IO.Path]::Combine($env:TEMP, "diskpart_usb_repair_{0}.txt" -f ([Guid]::NewGuid().ToString('N')))
    try {
        [IO.File]::WriteAllLines($temp, $ScriptLines)
        $p = Start-Process -FilePath 'diskpart.exe' -ArgumentList "/s `"$temp`"" -NoNewWindow -PassThru
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
            throw "DiskPart hung (timeout ${TimeoutSeconds}s)."
        }
        if ($p.ExitCode -ne 0) {
            throw "DiskPart failed (ExitCode=$($p.ExitCode))."
        }
    } finally {
        if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Run-DiskpartWipeAndFormat {
    param(
        [Parameter(Mandatory=$true)][int]$DiskNumber,
        [Parameter(Mandatory=$true)][ValidateSet('exFAT','FAT32','NTFS')][string]$FileSystem,
        [Parameter(Mandatory=$true)][string]$VolumeLabel,
        [Parameter(Mandatory=$true)][ValidateSet('CLEAN','CLEAN_ALL','DELETE_PARTITIONS')][string]$ResetMode,
        [Parameter(Mandatory=$true)][int]$TimeoutSeconds
    )

    $prelude = @(
        "select disk $DiskNumber",
        'attributes disk clear readonly',
        'online disk noerr'
    )

    $wipeLine = $null
    if ($ResetMode -eq 'CLEAN') { $wipeLine = 'clean' }
    if ($ResetMode -eq 'CLEAN_ALL') { $wipeLine = 'clean all' }

    if ($ResetMode -in @('CLEAN','CLEAN_ALL')) {
        $dpScript = @(
            $prelude + @(
                $wipeLine,
                'convert mbr noerr',
                'create partition primary',
                'select partition 1',
                "format fs=$FileSystem quick label=`"$VolumeLabel`"",
                'assign',
                'exit'
            )
        )

        Write-Host ("Running DiskPart ({0})..." -f $ResetMode) -ForegroundColor Cyan
        Invoke-Diskpart -ScriptLines $dpScript -TimeoutSeconds $TimeoutSeconds
        return
    }

    if ($ResetMode -eq 'DELETE_PARTITIONS') {
        $deleteLines = @('list partition')
        $parts = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Sort-Object PartitionNumber)
        foreach ($p in $parts) {
            $deleteLines += ("select partition {0}" -f $p.PartitionNumber)
            $deleteLines += 'delete partition override'
        }

        $dpScript = @(
            $prelude + $deleteLines + @(
                'create partition primary',
                'select partition 1',
                "format fs=$FileSystem quick label=`"$VolumeLabel`"",
                'assign',
                'exit'
            )
        )

        Write-Host 'Running DiskPart (forced partition deletion)...' -ForegroundColor Cyan
        Invoke-Diskpart -ScriptLines $dpScript -TimeoutSeconds $TimeoutSeconds
        return
    }

    throw 'Unknown reset mode.'
}

function Main {
    Assert-Admin

    Write-Host '=== USB Reset Tool (WIPES EVERYTHING) ===' -ForegroundColor Cyan

    $disks = @(Get-RemovableDisks)
    Show-Disks $disks

    if (-not $disks -or $disks.Count -eq 0) { return }

    $diskNumberStr = Read-NonEmpty 'Enter disk number (e.g. 2)'
    if (-not ($diskNumberStr -match '^\d+$')) { throw 'Invalid disk number.' }
    $diskNumber = [int]$diskNumberStr

    $disk = Get-Disk -Number $diskNumber -ErrorAction Stop

    if ($disk.IsSystem -or $disk.IsBoot) {
        throw 'Safety check: selected disk is System/Boot. Aborting.'
    }

    Confirm-Destructive $diskNumber

    Write-Host ''
    Write-Host 'Reset mode:' -ForegroundColor Cyan
    Write-Host '- CLEAN: quick (can hang on failing USB sticks)' -ForegroundColor Cyan
    Write-Host '- CLEAN_ALL: full wipe (very long; often hangs if the stick is unstable)' -ForegroundColor Cyan
    Write-Host '- DELETE_PARTITIONS: more aggressive if clean/clean all hang (deletes partitions with override)' -ForegroundColor Cyan

    $resetMode = Read-Choice 'Choose mode (CLEAN, CLEAN_ALL, DELETE_PARTITIONS)' @('CLEAN','CLEAN_ALL','DELETE_PARTITIONS')
    $timeout = Read-IntInRange 'DiskPart timeout in seconds (e.g. 120, 600, 1800)' 30 21600

    $fs = Read-NonEmpty 'File system (exFAT, FAT32, NTFS)'
    $fs = $fs.ToUpperInvariant()
    switch ($fs) {
        'EXFAT' { $fs = 'exFAT' }
        'FAT32' { $fs = 'FAT32' }
        'NTFS' { $fs = 'NTFS' }
        default { throw 'Invalid file system. Choose exFAT, FAT32, or NTFS.' }
    }

    $label = Read-NonEmpty 'Volume label (e.g. USB)'

    if ($disk.IsReadOnly) {
        Write-Host "Disk is read-only. Trying to clear ReadOnly attribute..." -ForegroundColor Yellow
        Set-Disk -Number $diskNumber -IsReadOnly $false -ErrorAction SilentlyContinue
    }

    if ($disk.IsOffline) {
        Write-Host 'Disk is Offline. Trying to bring it Online...' -ForegroundColor Yellow
        Set-Disk -Number $diskNumber -IsOffline $false -ErrorAction SilentlyContinue
    }

    try {
        Run-DiskpartWipeAndFormat -DiskNumber $diskNumber -FileSystem $fs -VolumeLabel $label -ResetMode $resetMode -TimeoutSeconds $timeout
    } catch {
        Write-Error "Unexpected DiskPart error: $($_.Exception.Message)"
        if ($resetMode -in @('CLEAN','CLEAN_ALL')) {
            Write-Host ''
            Write-Host 'CLEAN/CLEAN_ALL failed or got stuck.' -ForegroundColor Yellow
            Write-Host 'Automatic fallback: DELETE_PARTITIONS (override)...' -ForegroundColor Yellow
            Run-DiskpartWipeAndFormat -DiskNumber $diskNumber -FileSystem $fs -VolumeLabel $label -ResetMode 'DELETE_PARTITIONS' -TimeoutSeconds $timeout
        } else {
            throw
        }
    }

    Write-Host ''
    Write-Host 'Done. The drive should reappear in File Explorer.' -ForegroundColor Green
    Write-Host 'If Windows still asks to format after this, the drive is likely physically failing.' -ForegroundColor Yellow
}

Main

