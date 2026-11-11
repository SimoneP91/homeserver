# 2. Installare Debian 13

Debian 13 "trixie" è la versione stabile attuale. Si installa il minimo: niente desktop, solo il
server SSH. Tutto il resto lo aggiunge `bootstrap.sh` nel capitolo successivo.

**L'installazione cancella tutto il disco, Windows compreso.**

## Avvio dalla chiavetta

1. Inserisci la chiavetta, accendi e premi il tasto del **menu di avvio** (o imposta la chiavetta
   come primo dispositivo nel BIOS).
2. Scegli la voce UEFI della chiavetta, poi **Graphical install** (o *Install*, la versione testuale:
   stesse domande; si naviga con frecce, `Tab`, `Spazio` per spuntare e `Invio`).

## Le domande dell'installer

| Schermata | Scelta consigliata |
| --- | --- |
| Language | **English** (i messaggi di errore in inglese si cercano meglio online) oppure Italiano: va bene comunque, il bootstrap genera entrambe le lingue |
| Location | *other* → *Europe* → **Italy** |
| Locale | `en_US.UTF-8` (se hai scelto inglese) |
| Keyboard | **Italian** |
| Network interface | quella **cablata** (nome tipo `enp1s0` o `eno1`), non la Wi-Fi (`wlp…`): la rete si configura da sola via DHCP |
| Hostname | **`casa`** (o un altro nome corto, minuscolo, senza spazi). Diventa `casa.local` in rete. **Non** usare `localclima`, `status` o `dockge`: sono i nomi delle app |
| Domain name | **vuoto** (non scrivere `local`) |
| Root password | **vuota**: l'account root resta disattivato e il tuo utente riceve i permessi `sudo` |
| Full name / Username | il tuo nome e un nome utente minuscolo (per esempio le tue iniziali) |
| Password | una password robusta: serve per `sudo` (gli accessi SSH useranno la chiave) |
| Partitioning method | **Guided – use entire disk** |
| Disk | l'SSD da 256 GB (non la chiavetta!) |
| Partitioning scheme | **All files in one partition** |
| Conferma | *Finish partitioning and write changes* → **Yes** |
| Mirror | *Italy* → `deb.debian.org`, proxy vuoto |
| Popularity contest | a piacere (No va benissimo) |
| **Software selection** | togli la spunta a **Debian desktop environment** e a **GNOME** (e a ogni altro desktop); lascia **SSH server** e **standard system utilities** |
| GRUB | in UEFI viene installato da solo; se chiede, sul disco principale |

Alla fine: *Continue*, togli la chiavetta, il PC si riavvia.

## Primo accesso (ancora con monitor e tastiera)

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

Se risponde, il resto si fa da Windows. Monitor e tastiera restano collegati finché il capitolo 3
non è finito e l'accesso SSH con la chiave funziona; poi il server può vivere da solo.

Avanti: [3. Primo avvio](03-primo-avvio.md).
