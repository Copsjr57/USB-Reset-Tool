# USB Repair Tool (DiskPart) / Outil de réparation USB (DiskPart)

- [English version](#english-version)
- [Version française](#version-française)

---

## English version

### What this does

This PowerShell script helps you **wipe and re-create** a USB drive partition using **DiskPart**.

It is meant for cases where Windows cannot format the drive normally, or when partitions are corrupted.

### Warning

This tool is **destructive**.

- It will **erase all data** on the selected disk.
- If you select the wrong disk, you can wipe the wrong drive.

### Requirements

- Windows 10/11
- Run PowerShell **as Administrator**

### How to run

From a PowerShell terminal:

```powershell
powershell -ExecutionPolicy Bypass -File ".\usb_repair_tool.ps1"
```

### Modes

- **CLEAN**: Quick wipe (can hang on failing USB sticks)
- **CLEAN_ALL**: Full wipe (very long; often hangs if the stick is unstable)
- **DELETE_PARTITIONS**: More aggressive partition deletion (uses `delete partition override`)

### Notes / Troubleshooting

If DiskPart fails with errors like **"The semaphore timeout period has expired"**, it usually indicates a **hardware / I/O problem** (unstable USB controller, dying flash memory, bad port/hub).

Try:

- another USB port (avoid hubs)
- another PC
- a shorter cable / direct port

---

## Version française

### Ce que fait ce script

Ce script PowerShell aide à **effacer et recréer** la partition d’une clé USB via **DiskPart**.

Il est utile quand Windows ne peut plus formater la clé normalement ou quand les partitions sont corrompues.

### Avertissement

Cet outil est **destructif**.

- Il **efface toutes les données** du disque sélectionné.
- Si tu choisis le mauvais disque, tu peux effacer un autre support.

### Prérequis

- Windows 10/11
- Lancer PowerShell **en Administrateur**

### Lancer le script

Depuis un terminal PowerShell :

```powershell
powershell -ExecutionPolicy Bypass -File ".\usb_repair_tool.ps1"
```

### Modes

- **CLEAN** : Effacement rapide (peut se bloquer sur une clé défectueuse)
- **CLEAN_ALL** : Effacement complet (très long ; se bloque souvent si la clé est instable)
- **DELETE_PARTITIONS** : Suppression plus agressive des partitions (utilise `delete partition override`)

### Notes / Dépannage

Si DiskPart échoue avec **"Le délai de temporisation de sémaphore a expiré"**, c’est généralement un **problème matériel / I/O** (contrôleur instable, mémoire flash en fin de vie, port/hub).

Essaie :

- un autre port USB (éviter les hubs)
- un autre PC
- connexion directe (sans rallonge)
