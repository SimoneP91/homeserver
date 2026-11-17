# 1. Prima dell'installazione

Obiettivo: salvare i dati che stanno sul computer, controllare l'hardware, sistemare il BIOS e
preparare la chiavetta USB con Debian. Tutto da Windows.

Il server è un computer qualsiasi a 64 bit (x86_64) che resterà acceso giorno e notte: nel nostro
caso un **portatile HP di qualche anno** (Intel Celeron N4020 a 2 core, 8 GB di RAM, disco da
128 GB), ma le guide valgono anche per un mini PC o un desktop. Quello che cambia su un portatile
(coperchio, batteria, Wi-Fi, temperature) è nel capitolo
[3b. Un portatile come server](03b-portatile-come-server.md).

## Salvare i dati personali

**L'installazione di Debian cancella tutto il disco, Windows compreso.** Prima di cominciare
copia altrove (disco esterno, OneDrive, un altro PC) tutto quello che vuoi tenere:

- documenti, foto, download, desktop, e tutto ciò che non è già sincronizzato con OneDrive;
- preferiti e password dei browser (di solito già sincronizzati con l'account Google o Microsoft:
  controlla);
- chiavi di licenza dei programmi che ti servono altrove.

## Il modello e i tasti del BIOS (HP)

Il modello esatto serve per cercare manuali e driver: è sull'**etichetta sotto il portatile**
(nome del modello e *Product number*/*P/N*), nella schermata *System Information* del BIOS (`F1`,
sotto) e in Windows (su molti HP `Fn+Esc` apre *HP System Information*), oppure da PowerShell:

```powershell
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, SystemSKUNumber
```

Sui portatili HP consumer, all'accensione:

| Tasto | Cosa apre |
| --- | --- |
| `Esc` (premuto ripetutamente appena acceso) | il *Startup Menu*, da cui scegliere gli altri |
| `F10` | il BIOS (*Computer Setup* / *BIOS Setup*) |
| `F9` | il menu di avvio (*Boot Device Options*): da qui si avvia la chiavetta |
| `F1` | *System Information*: modello, numero di serie, versione del BIOS |
| `F2` | *HP PC Hardware Diagnostics*: test di memoria e disco, senza Windows |

Su altre marche i tasti cambiano (spesso `Canc`/`F2` per il BIOS e `F7`/`F11`/`F12`/`Esc` per il
menu di avvio): compaiono per un attimo all'accensione.

## Controllare l'hardware

Prima di cancellare Windows, usalo per controllare che sia tutto a posto. Il portatile resterà
acceso giorno e notte: meglio scoprire adesso un disco o una RAM difettosi.

| Cosa | Come | Cosa aspettarsi |
| --- | --- | --- |
| CPU e RAM | Gestione attività → Prestazioni | quello che dice l'etichetta (es. Celeron N4020, 8 GB) |
| Tipo di disco | PowerShell (sotto), colonne `MediaType` e `BusType` | SSD (`SATA`/`NVMe`) o eMMC (`MMC`/`SD`), vedi [3b](03b-portatile-come-server.md#disco-piccolo-o-emmc) |
| RAM senza errori | `mdsched.exe` → *Riavvia ora e verifica*, oppure `F2` all'accensione (HP) | "nessun errore" |
| Salute del disco | PowerShell (sotto) o [CrystalDiskInfo](https://crystalmark.info/) (`winget install CrystalDewWorld.CrystalDiskInfo`), oppure il test del disco di `F2` (HP) | stato "Buono", usura bassa. Un eMMC spesso non riporta questi dati: lo si controlla da Linux |
| Batteria | `powercfg /batteryreport`, poi apri il file `battery-report.html` | *Full charge capacity* non troppo sotto la *Design capacity*; batteria non gonfia (fondo o tastiera sollevati) |
| Temperature e ventola | un test sotto carico di 20–30 minuti (per esempio OCCT o Prime95) guardando le temperature con HWiNFO | niente spegnimenti, ventola sopportabile: resterà acceso giorno e notte |
| Rete | PowerShell: `Get-NetAdapter` | la scheda Ethernet (o l'adattatore USB-Ethernet) e la Wi-Fi |

```powershell
Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, Size
Get-PhysicalDisk | Get-StorageReliabilityCounter |
  Select-Object DeviceId, Temperature, Wear, PowerOnHours, ReadErrorsTotal, WriteErrorsTotal
```

## Rete: meglio il cavo

Il server lavora meglio **collegato al router con un cavo**: più veloce, più stabile, e mDNS (i
nomi `.local`) non risente dei capricci del Wi-Fi. Molti portatili sottili, compresi parecchi HP
con Celeron N4020, non hanno la porta di rete (RJ45): in quel caso compra un **adattatore da USB 3
a Gigabit Ethernet**. Quelli con chip **Realtek RTL8153** (i più diffusi, pochi euro) funzionano
su Debian senza installare nulla. Collegalo a una porta USB 3 (spesso blu, o con il simbolo *SS*).

Se proprio non si può usare il cavo, il **Wi-Fi** va bene lo stesso: l'installer di Debian lo
configura ([capitolo 2](02-installare-debian.md#rete-cavo-o-wi-fi)), il bootstrap ne spegne il
risparmio energetico ([3b](03b-portatile-come-server.md#rete-cavo-adattatore-usb-o-wi-fi)).

## Impostazioni del BIOS (UEFI)

Sugli HP consumer: `F10` all'accensione; le voci di avvio sono in *System Configuration* (o
*Configuration*) → *Boot Options*. Si salva con `F10` (*Save Changes and Exit*). Su altre marche i
nomi cambiano: cerca voci simili.

| Impostazione | Valore | Perché |
| --- | --- | --- |
| Boot mode: *Legacy Support* / CSM | **disattivato** (solo UEFI) | installazione moderna, quella che Debian si aspetta |
| *USB Boot* | **attivo** | per avviare l'installer dalla chiavetta |
| *Secure Boot* | può restare **attivo** | Debian è firmato e si avvia anche con Secure Boot (vedi sotto se serve spegnerlo) |
| Ordine di avvio (*UEFI Boot Order*) | lascialo com'è e usa `F9` | dopo l'installazione deve partire Debian dal disco |
| *Fast Boot* (se c'è) | disattivato, almeno durante l'installazione | altrimenti la chiavetta e il BIOS sono difficili da raggiungere |
| *Fan Always On* (HP, se c'è) | a piacere | ventola sempre accesa: più rumore, temperature più basse a coperchio chiuso |
| Limite di carica della batteria (*Adaptive Battery Optimizer*, *Battery Health Manager*, *Battery Charge Limit*…) | **attivo**, se c'è | un portatile sempre in carica consuma meno la batteria se non resta al 100%: [3b](03b-portatile-come-server.md#batteria) |
| Accensione al ritorno della corrente: sui desktop e mini PC *Restore on AC Power Loss* (*State After G3*, *AC Back*); sui portatili, se c'è, *Power On When AC Detected* / *Wake on AC* | **Power On** / attivo | dopo un blackout lungo il server si riaccende da solo ([3b](03b-portatile-come-server.md#blackout)) |
| Avvio senza tastiera / *Halt on errors* (desktop) | consentito / *No errors* | deve avviarsi senza tastiera né monitor |

Non serve aggiornare il BIOS se tutto funziona.

**Se serve spegnere Secure Boot** (normalmente no: solo se l'avvio della chiavetta viene
rifiutato): `F10` → *System Configuration* → *Boot Options* → *Secure Boot* → **Disabled**, poi
`F10` per salvare. Al riavvio molti HP chiedono di confermare la modifica digitando un codice di 4
cifre mostrato sullo schermo, poi `Invio`.

**Per avviare la chiavetta**: inserisci la chiavetta, accendi, premi `Esc` e poi `F9` (o `F9`
direttamente) e scegli la voce della chiavetta (*USB Hard Drive (UEFI)* o con il nome della
chiavetta). Se non compare, controlla che *USB Boot* sia attivo e *Legacy Support* spento.

## Funzionamento "headless" (senza monitor)

Dopo l'installazione il server vivrà **senza monitor né tastiera esterni**: lo userai solo via SSH
e dal browser. Un portatile ha già **schermo e tastiera propri**: servono per l'installazione e il
primo avvio, e restano la via di recupero se un giorno SSH non risponde
([problemi comuni](09-problemi-comuni.md#il-server-non-risponde-più-in-ssh)). Il bootstrap spegne
lo schermo quando nessuno lo usa ([3b](03b-portatile-come-server.md#schermo-spento)).

Su un desktop o un mini PC collega monitor e tastiera per installazione e primo avvio, finché `ssh`
non funziona ([capitolo 3](03-primo-avvio.md)). Quasi tutti si avviano anche senza monitor; se il
tuo non lo fa, un adattatore "HDMI dummy plug" da pochi euro risolve.

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

- [ ] dati personali salvati altrove: il disco verrà cancellato
- [ ] hardware controllato, nessun errore di RAM o disco; annotato il tipo di disco (SSD o eMMC)
- [ ] BIOS: UEFI, avvio da USB possibile; limite di carica e accensione con la corrente, se ci sono
- [ ] collegato al router **col cavo** (anche tramite adattatore USB), oppure nome e password del
      Wi-Fi a portata di mano: l'installer scarica i pacchetti dalla rete
- [ ] portatile collegato all'alimentatore (su un desktop: monitor e tastiera collegati)
- [ ] chiavetta pronta

Avanti: [2. Installare Debian](02-installare-debian.md).
