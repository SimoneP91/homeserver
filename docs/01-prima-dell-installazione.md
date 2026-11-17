# 1. Prima dell'installazione

Obiettivo: verificare il mini PC finché si può ancora restituire, sistemare il BIOS e preparare la
chiavetta USB con Debian. Tutto da Windows.

## Provare l'hardware con Windows (nel periodo di reso)

Il Windows 11 preinstallato verrà cancellato: usalo prima per controllare che sia tutto a posto.
Collega monitor, tastiera e il **cavo di rete**.

| Cosa | Come | Cosa aspettarsi |
| --- | --- | --- |
| CPU e RAM | Gestione attività → Prestazioni | Core i9-10980HK (8 core, 16 thread), 8 GB |
| RAM senza errori | `mdsched.exe` → *Riavvia ora e verifica* | al riavvio successivo: "nessun errore" |
| Salute dell'SSD | PowerShell (sotto) o [CrystalDiskInfo](https://crystalmark.info/) (`winget install CrystalDewWorld.CrystalDiskInfo`) | stato "Buono", poche ore di accensione, usura bassa |
| Rete cablata | PowerShell: `Get-NetAdapter` | la scheda Ethernet con `LinkSpeed` 1 Gbps |
| Temperature e ventola | un test sotto carico di 20–30 minuti (per esempio OCCT o Prime95) guardando le temperature con HWiNFO | niente spegnimenti, ventola sopportabile: resterà acceso giorno e notte |

```powershell
Get-PhysicalDisk | Get-StorageReliabilityCounter |
  Select-Object DeviceId, Temperature, Wear, PowerOnHours, ReadErrorsTotal, WriteErrorsTotal
```

Annota anche il **tasto per entrare nel BIOS** e quello del **menu di avvio** (compaiono
all'accensione; spesso `Canc`/`F2` e `F7`/`F11`/`F12`/`Esc`).

## Impostazioni del BIOS (UEFI)

I nomi cambiano da produttore a produttore: cerca voci simili.

| Impostazione | Valore | Perché |
| --- | --- | --- |
| **Restore on AC Power Loss** (anche *State After G3*, *Power On After Power Fail*, *AC Back*) | **Power On** | dopo un blackout il server si riaccende da solo |
| Boot mode | **UEFI** (CSM/Legacy disattivato) | installazione moderna, quella che Debian si aspetta |
| Secure Boot | può restare **attivo** | Debian è firmato e si avvia anche con Secure Boot |
| Fast Boot | disattivato, almeno durante l'installazione | altrimenti la chiavetta e il BIOS sono difficili da raggiungere |
| Halt on errors / avvio senza tastiera | *No errors* / consentito | deve avviarsi senza tastiera né monitor |
| Wake on LAN (*PME*, *Power On by PCI-E*) | facoltativo, attivo | per accenderlo dalla rete se un giorno serve |
| Ordine di avvio | la chiavetta USB prima del disco, oppure usa il menu di avvio | per partire dall'installer |

Non serve aggiornare il BIOS se tutto funziona.

## Funzionamento "headless" (senza monitor)

Dopo l'installazione il server vivrà **senza monitor né tastiera**: lo userai solo via SSH e dal
browser. Tieni però monitor e tastiera collegati per l'installazione e il **primo avvio**, finché
non hai verificato che `ssh` funziona ([capitolo 3](03-primo-avvio.md)). Conservali a portata di
mano: se un giorno SSH non risponde, sono la via di recupero
([problemi comuni](09-problemi-comuni.md#il-server-non-risponde-più-in-ssh)).

Quasi tutti i mini PC si avviano senza monitor collegato; se il tuo non lo fa, un adattatore
"HDMI dummy plug" da pochi euro risolve.

## Creare la chiavetta di installazione

Serve una chiavetta da almeno 1 GB, che verrà **cancellata**.

1. **Scarica** l'immagine *netinst* per **amd64** da <https://www.debian.org/download> (un file
   `debian-13.x.y-amd64-netinst.iso` di meno di 1 GB: scarica il resto dalla rete durante
   l'installazione). Dalla stessa cartella
   (<https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/>) scarica anche `SHA512SUMS`.
2. **Verifica** che il file sia integro, in PowerShell nella cartella dei download:

   ```powershell
   (Get-FileHash .\debian-13.*-amd64-netinst.iso -Algorithm SHA512).Hash.ToLower()
   Select-String netinst .\SHA512SUMS
   ```

   Le due stringhe devono essere identiche.
3. **Scrivi la chiavetta** con uno dei due:
   - **Rufus** (`winget install Rufus.Rufus`): scegli la chiavetta e l'ISO, *Schema partizione*
     **GPT**, *Sistema di destinazione* **UEFI (non CSM)**, poi *Avvia*. Se chiede se scrivere in
     modalità ISO o **DD**, scegli **DD**: Debian raccomanda di copiare l'immagine così com'è.
   - **Ventoy** (<https://www.ventoy.net>): installalo sulla chiavetta una volta, poi basta copiarci
     il file `.iso`; utile se vuoi tenere più immagini sulla stessa chiavetta.

## Prima di passare al capitolo 2

- [ ] hardware provato, nessun errore di RAM o SSD
- [ ] BIOS: *Power On* dopo un blackout, UEFI, avvio da USB possibile
- [ ] mini PC collegato al router **col cavo** (l'installer scarica i pacchetti dalla rete)
- [ ] monitor e tastiera collegati
- [ ] chiavetta pronta

Avanti: [2. Installare Debian](02-installare-debian.md).
