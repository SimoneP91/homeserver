# 2. Installare Debian 13

Debian 13 "trixie" è la versione stabile attuale. Si installa il minimo: niente desktop, solo il
server SSH. Tutto il resto lo aggiunge `bootstrap.sh` nel capitolo successivo.

**L'installazione cancella tutto il disco, Windows compreso.** Hai salvato i tuoi dati
([capitolo 1](01-prima-dell-installazione.md#salvare-i-dati-personali))?

## Avvio dalla chiavetta

1. Collega l'alimentatore, inserisci la chiavetta, accendi e premi il tasto del **menu di avvio**
   (sugli HP `F9`, oppure `Esc` e poi `F9`; vedi
   [capitolo 1](01-prima-dell-installazione.md#il-modello-e-i-tasti-del-bios-hp)).
2. Scegli la voce UEFI della chiavetta, poi **Graphical install** (o *Install*, la versione testuale:
   stesse domande; si naviga con frecce, `Tab`, `Spazio` per spuntare e `Invio`).

## Rete: cavo o Wi-Fi

L'immagine *netinst* scarica i pacchetti dalla rete, quindi la rete serve già durante
l'installazione.

- **Cavo** (porta di rete del portatile o adattatore USB-Ethernet, collegato **prima** di accendere):
  quando l'installer chiede l'interfaccia principale scegli quella cablata, con un nome tipo
  `enp1s0`, `eno1` o, per un adattatore USB, `enx` seguito dal MAC (`enx00e04c680001`). La rete
  si configura da sola via DHCP.
- **Solo Wi-Fi**: scegli l'interfaccia wireless (`wlp…` o `wlan0`). L'installer chiede il **nome
  della rete** (*ESSID*), il tipo di protezione (**WPA/WPA2 PSK**) e la **password**, poi ottiene
  l'indirizzo via DHCP. Da Debian 12 le immagini ufficiali contengono anche il firmware non libero
  delle schede Wi-Fi: l'installer lo carica da solo e lo installa anche sul sistema, con gli
  aggiornamenti (sezione `non-free-firmware` di APT). Se non riesce a collegarsi a una rete solo
  WPA3, per l'installazione attiva sul router la modalità mista WPA2/WPA3, oppure usa il cavo.

Senza desktop, l'installer configura la rete con **ifupdown** (il file `/etc/network/interfaces`)
e, per il Wi-Fi, **wpa_supplicant**: la nostra scelta è tenere questa configurazione
([3b](03b-portatile-come-server.md#rete-cavo-adattatore-usb-o-wi-fi) spiega perché e come
cambiare rete in seguito).

## Le domande dell'installer

| Schermata | Scelta consigliata |
| --- | --- |
| Language | **English** (i messaggi di errore in inglese si cercano meglio online) oppure Italiano: va bene comunque, il bootstrap genera entrambe le lingue |
| Location | *other* → *Europe* → **Italy** |
| Locale | `en_US.UTF-8` (se hai scelto inglese) |
| Keyboard | **Italian** |
| Network interface | il **cavo** se c'è, altrimenti il Wi-Fi: [sopra](#rete-cavo-o-wi-fi) |
| Hostname | **`casa`** (o un altro nome corto, minuscolo, senza spazi). Diventa `casa.local` in rete. **Non** usare `localclima`, `status` o `dockge`: sono i nomi delle app |
| Domain name | **vuoto** (non scrivere `local`) |
| Root password | **vuota**: l'account root resta disattivato e il tuo utente riceve i permessi `sudo` |
| Full name / Username | il tuo nome e un nome utente minuscolo (per esempio le tue iniziali) |
| Password | una password robusta: serve per `sudo` (gli accessi SSH useranno la chiave) |
| Partitioning method | **Guided – use entire disk** |
| Disk | il **disco interno** del computer, riconoscibile dalla dimensione (per esempio 128 GB): **non** la chiavetta. Un eMMC si chiama `mmcblk0` (*MMC/SD card*); se accanto compaiono `mmcblk0boot0`/`boot1` di pochi MB, non sceglierli |
| Partitioning scheme | **All files in one partition** |
| Conferma | *Finish partitioning and write changes* → **Yes** |
| Mirror | *Italy* → `deb.debian.org`, proxy vuoto |
| Popularity contest | a piacere (No va benissimo) |
| **Software selection** | togli la spunta a **Debian desktop environment** e a **GNOME** (e a ogni altro desktop); lascia **SSH server** e **standard system utilities** |
| GRUB | in UEFI viene installato da solo; se chiede, sul disco principale |

Alla fine: *Continue*, togli la chiavetta, il PC si riavvia.

### Se dopo l'installazione non parte Debian

Alcuni firmware (anche di qualche HP) ignorano la voce di avvio creata da Debian e cercano solo il
percorso "di riserva" `EFI/BOOT/BOOTX64.EFI`: al riavvio compare *No bootable device* o riparte
l'installer. Rimedio:

1. avvia Debian una volta a mano: `F9` → *Boot From EFI File* (se c'è) → il disco →
   `EFI` → `debian` → `shimx64.efi`; oppure avvia la chiavetta e scegli
   *Advanced options → Rescue mode*, poi una shell nel sistema installato;
2. copia GRUB anche nel percorso di riserva:

   ```sh
   sudo dpkg-reconfigure grub-efi-amd64
   ```

   rispondi alle domande lasciando i valori proposti, ma **Yes** a *Force extra installation to
   the EFI removable media path*. La scelta viene ricordata anche per gli aggiornamenti di GRUB.

## Primo accesso (dalla console)

Al prompt `casa login:` entra con il tuo utente, poi:

```sh
ip -4 addr show            # l'indirizzo IP del server, per esempio 192.168.1.23
sudo -v                    # deve chiedere la password e non dare errori: sudo funziona
sudo apt update && sudo apt install -y avahi-daemon
```

`avahi-daemon` annuncia subito il nome **`casa.local`** in rete, così dal PC Windows puoi già
collegarti per nome (il bootstrap poi lo configura del tutto). Prova da PowerShell sul PC:

```powershell
ping casa.local
```

Se risponde, il resto si fa da Windows. Tieni schermo e tastiera a portata di mano (su un
portatile ci sono già; su un desktop restano collegati) finché il capitolo 3 non è finito e
l'accesso SSH con la chiave funziona; poi il server può vivere da solo.

**Su un portatile, finché non hai lanciato il bootstrap, non chiudere il coperchio**: Debian lo
mette in sospensione e il server sparisce dalla rete. Il bootstrap lo impedisce
([3b](03b-portatile-come-server.md#coperchio-chiuso)).

Avanti: [3. Primo avvio](03-primo-avvio.md).
