# 4. Servizi di base

Cosa gira sul server oltre alle app, come funziona e come si controlla.

| Servizio | Dove | A cosa serve |
| --- | --- | --- |
| avahi-daemon | sistema | annuncia `casa.local` in rete (mDNS) |
| homeserver-mdns-aliases | sistema (systemd) | annuncia i nomi delle app: `localclima.local`, `status.local`, `dockge.local` |
| Caddy | container `caddy` | porta 80: smista le richieste all'app giusta in base al nome |
| Dockge | container `dockge` | gestione dei progetti compose di `/srv/apps` dal browser |
| Uptime Kuma | container `uptime-kuma` | controlla che tutto risponda e manda notifiche al telefono |
| ufw | sistema | firewall |
| unattended-upgrades | sistema | aggiornamenti di sicurezza automatici |
| homeserver-backup.timer | sistema (systemd) | backup notturno ([capitolo 6](06-backup.md)) |
| homeserver-docker-prune.timer | sistema (systemd) | ogni domenica cancella le immagini Docker non più usate |
| homeserver-battery-limit | sistema (systemd) | solo sui portatili che lo permettono: limite di carica della batteria ([3b](03b-portatile-come-server.md#batteria)) |

I container dell'infrastruttura sono definiti in [infra/compose.yaml](../infra/compose.yaml) e
salvano i dati in `/srv/data/<servizio>`. Comandi, da `/srv/homeserver`:

```sh
make            # elenco dei comandi
make ps         # stato di tutti i container
make logs       # log di caddy, dockge e uptime-kuma (uno solo: make logs S=caddy)
make up         # avvia o applica le modifiche a infra/compose.yaml
```

## Nomi in rete senza IP fissi (mDNS)

Il router cambia gli indirizzi ogni poche ore e a ogni riavvio, e non vogliamo dipendere dalla sua
configurazione. Per questo nessuna parte del sistema usa IP fissi: tutto passa per nomi `.local`,
risolti con **mDNS** (lo stesso meccanismo di stampanti e AirPlay), che non ha bisogno del router.

- `casa.local` (l'hostname) è annunciato da **avahi-daemon**, che segue da solo i cambi di IP.
- Ogni app ha un **nome in più** che punta allo stesso server. L'elenco è in
  [infra/mdns/aliases](../infra/mdns/aliases), un nome per riga. Il servizio
  `homeserver-mdns-aliases` ([scripts/mdns-aliases.sh](../scripts/mdns-aliases.sh)) lancia un
  `avahi-publish -a -R <nome>.local <ip>` per ogni nome e ogni 5 secondi controlla l'IP del
  server: se cambia, o se cambia il file, ripubblica tutto con il nuovo indirizzo. Se un
  annuncio si interrompe (per esempio perché un altro dispositivo usa lo stesso nome) lo riprova
  con intervalli crescenti, fino a 10 minuti.
- Le app **non** si annunciano da sole (LocalClima ha `LOCALCLIMA_MDNS_HOSTNAME` vuoto): due
  annunci dello stesso nome andrebbero in conflitto.
- avahi lavora solo in **IPv4** e solo sulle schede di rete fisiche (cavo, Wi-Fi, adattatore USB),
  non sulle reti interne di Docker: così telefoni e PC ricevono sempre l'indirizzo giusto.

Dopo un cambio di IP i telefoni possono ricordare il vecchio indirizzo per un paio di minuti.

```sh
make aliases                                     # stato del servizio e IP di ogni nome
journalctl -u homeserver-mdns-aliases -n 50      # cosa ha pubblicato e quando
avahi-resolve -4 -n localclima.local             # risolve un nome dal server
```

Il bootstrap indica ad avahi le schede di rete presenti in quel momento: se il server passa dal
cavo al Wi-Fi integrato, per i nomi non serve altro; con una scheda nuova (per esempio un altro
adattatore USB-Ethernet, che ha un nome diverso) rilancia il bootstrap
([3b](03b-portatile-come-server.md#rete-cavo-adattatore-usb-o-wi-fi)).

## Caddy: un nome per ogni app

Caddy è l'unico servizio sulla porta 80. Legge il nome richiesto dal browser (`Host`) e inoltra la
richiesta all'app, che ascolta solo su `127.0.0.1` (loopback). File:

- [infra/caddy/Caddyfile](../infra/caddy/Caddyfile): impostazioni generali e pagina iniziale;
- [infra/caddy/sites/](../infra/caddy/sites/): **un file per app**, per esempio

  ```caddy
  http://localclima.local {
      reverse_proxy 127.0.0.1:8100
  }
  ```

- [infra/caddy/www/index.html](../infra/caddy/www/index.html): la pagina con i link, mostrata per
  ogni nome non riconosciuto, per esempio <http://casa.local>.

Dopo una modifica: `make caddy-reload` (controlla la sintassi e applica senza interruzioni).

**Perché HTTP e non HTTPS.** I nomi `.local` non possono avere un certificato pubblico, quindi in
casa le app usano HTTP: il prefisso `http://` nel nome del sito spegne l'HTTPS automatico di Caddy
solo per quel sito. Il traffico non esce dalla rete di casa. Da fuori casa si usa Tailscale, che
offre anche HTTPS con certificati veri ([capitolo 7](07-accesso-remoto.md)).

## Dockge

<http://dockge.local> mostra i progetti compose di `/srv/apps` (stato, log, terminale, avvio e
arresto). Comodo dal telefono per vedere se un'app è su e per riavviarla.

- Ha il controllo completo di Docker, quindi del server: password robusta e mai esposto fuori casa.
- Il pulsante *Update* scarica immagini nuove ma **non ricostruisce** le app che si costruiscono
  dal sorgente, come LocalClima: per quelle vedi [5. App](05-app.md#aggiornare).
- I file creati da Dockge appartengono a root: per modificarli dal terminale serve `sudo`.

## Uptime Kuma: monitoraggio e notifiche

<http://status.local>. Al primo accesso crea l'account e scegli il database **SQLite**.

**Notifiche sul telefono** (*Settings → Notifications → Setup Notification*). Funzionano sia su
iPhone sia su Android, per esempio:

- **ntfy**: installa l'app ntfy, iscriviti a un argomento con un nome difficile da indovinare e
  usa lo stesso argomento in Kuma (server `https://ntfy.sh`);
- **Telegram**: crea un bot con @BotFather e incolla token e chat ID.

**Monitor consigliati** (*Add New Monitor*). Kuma usa la rete dell'host, quindi raggiunge le app
su `127.0.0.1`:

| Nome | Tipo | Indirizzo | Note |
| --- | --- | --- | --- |
| LocalClima | HTTP(s) | `http://127.0.0.1:8100/api/health` | intervallo 60 s |
| Caddy | HTTP(s) | `http://127.0.0.1/` | la pagina iniziale |
| Dockge | HTTP(s) | `http://127.0.0.1:5001/` | — |
| Backup | Push | — | *Heartbeat Interval* 90000 s (25 ore): vedi [capitolo 6](06-backup.md#notifica-in-uptime-kuma) |
| Router | Ping | IP del router (di solito non cambia, es. `192.168.1.1`) | facoltativo: dice se è caduta la rete |

Kuma gira sul server stesso: se il server si spegne del tutto non può avvisarti. Se ti serve,
un servizio esterno gratuito come healthchecks.io può ricevere lo stesso "ping" del backup.

## Firewall

`ufw` blocca tutto ciò che arriva da fuori, tranne:

| Regola | Da dove | Perché |
| --- | --- | --- |
| TCP 22 (SSH) | ovunque | si entra solo con la chiave; aperto ovunque per non restare mai chiusi fuori |
| TCP 80, 443 | reti private (`10/8`, `172.16/12`, `192.168/16`, IPv6 locali) | le app tramite Caddy, solo dalla LAN |
| UDP 5353 | reti private | mDNS: risposte e domande dirette ad avahi |
| UDP **da** porta 1900, 6445, 20086 | reti private | risposte alla discovery di LocalClima (vedi sotto) |
| tutto su `tailscale0` | i tuoi dispositivi Tailscale | solo con `--tailscale` |

Il traffico in uscita è libero. Le porte delle app (8100, 3001, 5001…) **non** sono aperte: le app
ascoltano solo su loopback e si raggiungono tramite Caddy.

**Perché la regola sulla discovery.** Un firewall "stateful" lascia passare le risposte alle
connessioni che il server ha aperto. Ma quando LocalClima cerca i dispositivi, manda un messaggio a
*tutti* (broadcast `255.255.255.255` per i condizionatori Midea, multicast `239.255.255.250:1900`
SSDP per i TV Samsung) e ogni dispositivo risponde dal **proprio** indirizzo: per il firewall
quella risposta non corrisponde alla richiesta (che era indirizzata a "tutti") e verrebbe
scartata come una connessione nuova. La regola accetta quindi i pacchetti UDP che arrivano dalla LAN
**dalle porte sorgente** usate da quei protocolli: 1900 (SSDP), 6445 e 20086 (Midea). Tutto il
resto di LocalClima (comandi ai condizionatori sulla 6444, TV sulle porte 8001/8002/9197,
Wake-on-LAN) parte dal server, quindi le risposte passano già. Se un TV rispondesse alla ricerca
SSDP da un'altra porta, LocalClima lo trova comunque con la scansione della rete sulla porta 8001.

**Docker e ufw.** Le porte pubblicate da Docker con `ports:` scavalcano ufw. Per questo in tutti i
compose di questo server le porte sono pubblicate solo su `127.0.0.1` (o i container usano la rete
dell'host, dove ufw vale normalmente).

```sh
sudo ufw status verbose          # regole attive
sudo ufw status numbered         # con il numero, per cancellarne una: sudo ufw delete <n>
```

## Aggiornamenti automatici

`unattended-upgrades` installa ogni giorno gli aggiornamenti di sicurezza di Debian. Non riavvia, a
meno di aver lanciato il bootstrap con `--auto-reboot 04:30`: senza quell'opzione, quando un
aggiornamento (di solito il kernel) richiede un riavvio, esiste il file `/var/run/reboot-required`
e il riavvio lo decidi tu ([manutenzione](08-manutenzione.md)).

```sh
cat /var/run/reboot-required 2>/dev/null || echo "nessun riavvio necessario"
less /var/log/unattended-upgrades/unattended-upgrades.log
```

Docker e gli altri pacchetti dei repository esterni si aggiornano a mano, con
`sudo apt update && sudo apt full-upgrade`.

Avanti: [5. App](05-app.md).
