# 9. Problemi comuni

## Il telefono non apre `http://localclima.local`

Procedi in ordine:

1. **Dal server**: `cd /srv/homeserver && make aliases`. Ogni nome deve risolversi nell'IP attuale
   del server. Se no, `journalctl -u homeserver-mdns-aliases -n 50`.
2. **Dal PC**: `ping localclima.local`. Se il PC lo raggiunge e il telefono no, il problema è il
   telefono o il Wi-Fi.
3. **L'app risponde?** Sul server: `curl -s http://127.0.0.1:8100/api/health`. Se il nome si
   risolve ma la pagina dà `502 Bad Gateway`, Caddy funziona e l'app è ferma: vedi
   [Docker](#un-container-non-parte-o-si-riavvia-di-continuo).

Cause tipiche:

- **Scrivi l'indirizzo completo**, con `http://`: senza, Safari e Chrome possono trattare
  `localclima.local` come una ricerca.
- **Android vecchi.** Android risolve i nomi `.local` a livello di sistema solo dalla versione 12–13
  in poi. Sui telefoni più vecchi usa Tailscale ([capitolo 7](07-accesso-remoto.md)), che funziona
  su qualsiasi Android. L'IP del server non basta: Caddy sceglie l'app in base al nome, e con l'IP
  mostra la pagina iniziale.
- **Chrome su iPhone** chiede il permesso *Rete locale* (Impostazioni → Chrome → Rete locale):
  deve essere attivo. Safari non ne ha bisogno.
- **Rete ospiti o isolamento dei client** (*AP isolation*, *client isolation*): i dispositivi Wi-Fi
  non vedono gli altri. Collega il telefono alla rete principale o disattiva l'isolamento.
- **Multicast filtrato.** Alcuni router e sistemi mesh bloccano o limitano il multicast tra Wi-Fi e
  cavo (*IGMP snooping*, *multicast to unicast*, *multicast enhancement*): mDNS non passa. Prova a
  cambiare quelle impostazioni.
- **VPN sul telefono**: alcune app VPN instradano tutto fuori casa; disattivala per provare.
- **Nome già usato da un altro dispositivo**, per esempio il vecchio PC con LocalClima ancora
  acceso. `make aliases` mostra un IP che non è quello del server, e il journal del servizio parla
  di *collision*. Spegni l'altro o cambia nome.
- **IP appena cambiato**: telefoni e PC ricordano il vecchio indirizzo per un paio di minuti. Su
  Windows: `ipconfig /flushdns`.

## Windows non risolve `casa.local`

Windows 10 e 11 risolvono i nomi `.local`. Se non funziona: la rete deve essere di tipo *Privata*
(Impostazioni → Rete e Internet → Proprietà); alcuni client VPN aziendali disattivano mDNS. In
alternativa usa l'IP: `ssh -o HostName=<ip> casa` ([capitolo 3](03-primo-avvio.md#se-casalocal-non-si-risolve)).

## Il server sparisce dalla rete ogni tanto

Succede soprattutto con un portatile o con il Wi-Fi. Dalla console (o appena torna raggiungibile):

```sh
journalctl -b -1 -n 50                    # le ultime righe prima dell'ultimo riavvio: spento, sospeso?
journalctl -b -u systemd-logind | grep -i -E 'lid|suspend'   # coperchio, sospensione
systemctl is-enabled sleep.target         # deve essere "masked"
iw dev wlp2s0 get power_save              # con il Wi-Fi: deve essere "off"
iw dev wlp2s0 link                        # segnale: sotto -70 dBm è debole
journalctl -k | grep -i -E 'wlp|r8152|enx|link (is )?(up|down)'   # cadute della scheda di rete
```

- **Si sospende chiudendo il coperchio**: il bootstrap non è stato lanciato, o con `--no-laptop`
  ([3b](03b-portatile-come-server.md#coperchio-chiuso)).
- **Wi-Fi debole a coperchio chiuso**: le antenne sono spesso nello schermo. Avvicinalo al router,
  lascialo socchiuso o, meglio, usa un cavo o un adattatore USB-Ethernet.
- **L'adattatore USB-Ethernet si disconnette**: prova un'altra porta USB 3, senza hub; non usare
  `powertop --auto-tune` ([3b](03b-portatile-come-server.md#il-risparmio-energetico-del-wi-fi)).
- **Si spegne del tutto**: blackout lungo con la batteria scarica, o surriscaldamento (`journalctl
  -k -b -1 | grep -i -E 'thermal|critical'`): vedi
  [ventilazione](03b-portatile-come-server.md#ventilazione-e-temperature).

## SSH

| Messaggio | Cosa fare |
| --- | --- |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | normale dopo una reinstallazione: `ssh-keygen -R casa`, poi riconnettiti. Se non hai reinstallato nulla, fermati e capisci perché |
| `Permission denied (publickey)` | la chiave non è quella giusta o non è in `~/.ssh/authorized_keys` sul server. `ssh -v casa` mostra quali chiavi prova |
| `Could not resolve hostname casa.local` | vedi sopra; intanto entra con l'IP |
| `Connection timed out` | server spento, fuori rete o IP sbagliato |

## Il server non risponde più in SSH

Entra dalla console (apri il portatile, o collega monitor e tastiera). Poi, a seconda del caso:

```sh
ip -4 addr show                  # ha un IP? il cavo (o l'adattatore USB) è collegato? il Wi-Fi?
systemctl status ssh             # sshd è attivo?
sudo rm /etc/ssh/sshd_config.d/10-homeserver.conf && sudo systemctl reload ssh   # riattiva le password
sudo ufw disable                 # per escludere il firewall; dopo: sudo ufw enable
```

Se nemmeno la console funziona: chiavetta di Debian → *Advanced options → Rescue mode*.

## Il firewall blocca qualcosa?

```sh
sudo ufw status verbose
sudo ufw logging on                         # registra i pacchetti bloccati
journalctl -k -f | grep 'UFW BLOCK'         # riproduci il problema e guarda cosa viene bloccato
sudo ufw logging off
```

Per una prova veloce `sudo ufw disable`, poi **sempre** `sudo ufw enable`.

## LocalClima non trova condizionatori o TV

- La regola per le risposte alla discovery deve esserci: `sudo ufw status | grep -i discovery`
  (spiegazione nel [capitolo 4](04-servizi-base.md#firewall)).
- `cd /srv/apps/localclima && docker compose exec localclima msmart-ng discover` deve elencare i
  condizionatori.
- Server e dispositivi devono stare nella stessa rete, non nella rete ospiti.
- Un TV spento del tutto (non in standby) non è in rete: accendilo col telecomando.

## Un container non parte o si riavvia di continuo

```sh
docker ps -a                                        # STATUS: Restarting, Exited (1)...
docker logs --tail 100 <nome>                       # perché
docker inspect --format '{{json .State.Health}}' localclima | jq   # esito degli health check
sudo ss -tlnp | grep -E ':(80|8100|3001|5001) '      # la porta è già occupata da altro?
```

`permission denied … /var/run/docker.sock` quando usi `docker`: non sei ancora nel gruppo
`docker` per questa sessione. Esci e rientra.

## Il backup fallisce

| Messaggio (in `journalctl -u homeserver-backup`) | Cosa fare |
| --- | --- |
| `/mnt/backup is not mounted` | collega il disco USB; `sudo mount /mnt/backup` |
| `repository is already locked` | un backup precedente si è interrotto: `sudo /srv/homeserver/scripts/backup.sh restic unlock` |
| `missing /etc/homeserver/restic-password` | `sudo /srv/homeserver/scripts/backup.sh init`, o rimetti la password dal password manager |

## Disco pieno

```sh
df -h /
docker system df
docker image prune -f && docker builder prune -f
sudo ncdu /
```

Vedi anche [manutenzione](08-manutenzione.md#spazio-su-disco-e-salute-del-disco).
