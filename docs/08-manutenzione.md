# 8. Manutenzione

## Calendario

| Quando | Cosa |
| --- | --- |
| da solo, ogni giorno | aggiornamenti di sicurezza di Debian; backup alle 3 (la domenica anche la pulizia delle immagini Docker) |
| quando ti avvisa Uptime Kuma | guarda cosa non risponde ([problemi comuni](09-problemi-comuni.md)) |
| una volta al mese | aggiornare sistema e infrastruttura (sotto), `make test-restore`, spazio su disco, temperature |
| quando cambi il codice di un'app | aggiornare l'app |

## Aggiornare il sistema

```sh
sudo apt update && sudo apt full-upgrade      # comprende Docker e gli altri repository esterni
cat /var/run/reboot-required 2>/dev/null && sudo reboot
```

Un aggiornamento di Docker riavvia i container: ripartono da soli (`restart: unless-stopped`).

Le versioni maggiori di Debian (14 "forky", attesa nel 2027) non arrivano da sole: Debian 13 riceve
aggiornamenti di sicurezza per anni, l'aggiornamento di versione si fa a mano seguendo le note di
rilascio, dopo un backup.

## Aggiornare questo repository e l'infrastruttura

```sh
cd /srv/homeserver
git pull
sudo bash scripts/bootstrap.sh     # solo se sono cambiati script, servizi o firewall: è idempotente
make update                        # scarica le nuove versioni di Caddy, Dockge, Uptime Kuma e le riavvia
```

Le immagini sono fissate alla **versione maggiore** (`caddy:2`, `louislam/dockge:1`,
`louislam/uptime-kuma:2`): `make update` porta correzioni e funzioni nuove, mai cambiamenti
incompatibili. Il passaggio a una versione maggiore nuova (per esempio Uptime Kuma 3) si fa a mano:
leggi le note di rilascio, fai un backup, cambia il tag in [infra/compose.yaml](../infra/compose.yaml)
e committa. `docker compose -f infra/compose.yaml images` mostra le versioni in uso.

## Aggiornare un'app

```sh
cd /srv/apps/localclima
git pull
docker compose up -d --build
docker image prune -f
```

## Log

| Cosa | Comando |
| --- | --- |
| un'app | `cd /srv/apps/<app> && docker compose logs -f --tail=100` |
| infrastruttura | `cd /srv/homeserver && make logs` (o `make logs S=caddy`) |
| nomi mDNS | `journalctl -u homeserver-mdns-aliases -n 50` |
| backup | `journalctl -u homeserver-backup -n 50` |
| errori di sistema dall'ultimo avvio | `journalctl -p warning -b` |
| aggiornamenti automatici | `less /var/log/unattended-upgrades/unattended-upgrades.log` |

In `journalctl` e `less`: `G` va in fondo, `/parola` cerca, `q` esce. `-f` segue dal vivo.

## Spazio su disco e salute del disco

```sh
df -h /                                  # spazio libero sul disco di sistema
docker system df                         # quanto occupano immagini, container, volumi, cache di build
docker image prune -f                    # immagini non più usate (lo fa anche il timer della domenica)
docker builder prune -f                  # cache di build (si riforma alla prossima build)
journalctl --disk-usage                  # il journal è limitato a 500 MB
sudo ncdu /                              # chi occupa spazio, cartella per cartella (q per uscire)
lsblk -d -o NAME,MODEL,SIZE,ROTA,TRAN    # che disco è
sudo smartctl -a /dev/sda                # salute di un SSD SATA (NVMe: /dev/nvme0n1)
cat /sys/block/mmcblk0/device/life_time  # usura di un eMMC (smartctl non lo legge)
```

Su un disco piccolo o un eMMC: [3b](03b-portatile-come-server.md#disco-piccolo-o-emmc).

## Temperature e batteria

```sh
sensors                                                  # temperature di CPU e scheda
/srv/homeserver/scripts/battery-limit.sh --check         # portatile: limite di carica
cat /sys/class/power_supply/BAT0/{status,capacity}       # portatile: stato e carica in %
```

Ogni qualche mese, su un portatile, guarda anche la batteria: se si gonfia (fondo o touchpad
sollevati) va sostituita ([3b](03b-portatile-come-server.md#batteria)). Una volta l'anno togli
la polvere dalle prese d'aria.

## Dopo un blackout

Un **portatile** supera i blackout brevi con la batteria. In un blackout lungo si spegne quando la
batteria si scarica e, al ritorno della corrente, si riaccende da solo solo se il BIOS ha *Power
On When AC Detected* o simili; altrimenti premi il tasto di accensione
([3b](03b-portatile-come-server.md#blackout)). Un **desktop o mini PC** con *Restore on AC Power
Loss → Power On* nel BIOS si riaccende da solo.

All'avvio ripartono avahi, i nomi delle app e tutti i container. Controlla dopo qualche minuto:

```sh
cd /srv/homeserver
make ps                # tutti "Up"
make aliases           # i nomi rispondono con l'IP nuovo
findmnt /mnt/backup    # il disco di backup è montato
```

Il backup saltato durante il blackout parte da solo all'avvio.

## Spegnere e riavviare

```sh
sudo reboot
sudo poweroff          # per spostarlo o pulirlo dalla polvere (il tasto di accensione fa lo stesso)
```

## Cambiare nome al server

```sh
sudo hostnamectl set-hostname nuovonome
sudo sed -i 's/\bcasa\b/nuovonome/' /etc/hosts
sudo systemctl restart avahi-daemon
```

Poi aggiorna `HostName` in `C:\Users\<te>\.ssh\config`.

## Reinstallare da zero

Questo repository più il backup bastano a ricostruire tutto:

1. [installa Debian](02-installare-debian.md) e fai il [primo avvio](03-primo-avvio.md), con il
   bootstrap;
2. [ripristina dal backup](06-backup.md#tutto-il-server-su-uninstallazione-nuova) `/srv` e
   `/etc/homeserver`;
3. riavvia le app (`docker compose up -d --build` in ciascuna) e riattiva il timer del backup.

Dal PC, dopo una reinstallazione SSH avvisa che l'impronta del server è cambiata: è normale,
rimuovi quella vecchia con `ssh-keygen -R casa`.

Avanti: [9. Problemi comuni](09-problemi-comuni.md).
