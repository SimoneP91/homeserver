# 5. App

Ogni app vive in `/srv/apps/<app>`: è il clone del suo repository, con il suo compose e i suoi
segreti (ignorati da git). È la copia di **produzione**: si aggiorna solo con `git pull`, non ci si
sviluppa dentro (per lo sviluppo vedi [10. Sviluppo remoto](10-sviluppo-remoto.md)).

Per aggiungere un'app qualsiasi: [apps/README.md](../apps/README.md). Qui sotto, LocalClima passo
per passo.

## LocalClima

Come gira sul server:

```text
telefono ──► http://localclima.local ──► Caddy :80 ──► 127.0.0.1:8100  container "localclima"
                                                                       (rete dell'host)
                                                                            │ broadcast, SSDP,
                                                                            ▼ Wake-on-LAN
                                                                     condizionatori e TV
```

- Il container usa la **rete dell'host** (`network_mode: host`), necessaria per trovare
  condizionatori e TV in broadcast e per il Wake-on-LAN.
- Ascolta solo su `127.0.0.1:8100`: dalla LAN si passa da Caddy. La porta 8100, e non 8000, lascia
  libera la 8000 per un `make dev` di sviluppo accanto alla produzione.
- Il nome `localclima.local` lo pubblica il server; l'app ha l'annuncio mDNS spento.
- Log e IP trovati in rete stanno nel volume Docker `localclima_localclima-data` (`/data` nel
  container). Si ricostruiscono da soli, quindi non sono nel backup; `devices.yaml` e `.env` sì.

Le impostazioni di produzione sono in
[apps/localclima/backend.env.example](../apps/localclima/backend.env.example).

### 1. Spegnere LocalClima sul vecchio PC

Ferma l'istanza che gira su Windows (`Ctrl+C` nel terminale di `make start`, o chiudi il processo).
Due istanze insieme si contenderebbero il nome `localclima.local` e i dispositivi.

### 2. Clonare il repository

Sul server:

```sh
gh repo clone <utente-github>/localclima /srv/apps/localclima
# oppure, se è pubblico: git clone https://github.com/<utente-github>/localclima.git /srv/apps/localclima
```

(`gh auth login` è nel [capitolo 3](03-primo-avvio.md#5-portare-questo-repository-sul-server).)

### 3. Copiare i segreti dal vecchio PC

`devices.yaml` contiene token e chiavi: non è in git e va copiato a mano. Da PowerShell sul PC
Windows:

```powershell
scp C:\Users\<te>\Documents\Development\localclima\backend\devices.yaml casa:/srv/apps/localclima/backend/devices.yaml
```

Il vecchio `backend\.env` **non** va copiato così com'è (per esempio `LOCALCLIMA_PORT=80` qui
andrebbe in conflitto con Caddy). Guarda cosa contiene:

```powershell
Get-Content C:\Users\<te>\Documents\Development\localclima\backend\.env
```

e riporta nel nuovo file solo le impostazioni cambiate di proposito (intervalli, livello di log…).

### 4. Il file `.env` di produzione

Sul server:

```sh
cd /srv/apps/localclima
cp /srv/homeserver/apps/localclima/backend.env.example backend/.env
nano backend/.env                # solo se devi aggiungere qualcosa dal vecchio .env
chmod 600 backend/.env
chmod 644 backend/devices.yaml
```

`devices.yaml` deve essere leggibile dal container, che gira con un utente suo (uid 10001); sul
server l'unico utente sei tu, quindi `644` va bene.

### 5. Costruire e avviare

```sh
cd /srv/apps/localclima
docker compose up -d --build     # la prima volta qualche minuto: frontend e dipendenze Python
docker compose ps                # STATUS deve diventare "healthy"
curl -s http://127.0.0.1:8100/api/health
```

Poi apri <http://localclima.local> dal telefono. Log:

```sh
docker compose logs -f --tail=100                                   # dal vivo (Ctrl+C per uscire)
docker compose exec localclima tail -n 100 /data/localclima.log     # il file di log (JSON)
```

Il primo avvio può metterci fino a mezzo minuto a trovare i dispositivi: gli IP salvati sul vecchio
PC non servono, li ritrova per `device_id` e MAC.

### 6. TV Samsung: autorizzare di nuovo, se serve

Il token di un TV appartiene al TV, non al PC: di solito quello copiato in `devices.yaml` continua a
funzionare. Alcuni modelli però chiedono di nuovo il permesso quando il client cambia indirizzo.

- Se sul TV compare *"LocalClima" vuole connettersi*: scegli **Consenti**.
- Se nel log compare `The TV rejected the token`, o i comandi al TV falliscono per autenticazione,
  associa di nuovo il TV **dal container** (usa la rete dell'host, quindi parla col TV come se
  fosse il server stesso):

  ```sh
  cd /srv/apps/localclima
  curl -s http://127.0.0.1:8100/api/tvs | jq '.[] | {id, ip, power}'   # IP attuale dei TV
  docker compose exec localclima python -m localclima.tools.pair_tv 192.168.1.11
  ```

  Con il TV acceso, accetta la richiesta sullo schermo entro 60 secondi. Il comando stampa la voce
  completa per `devices.yaml`: copia solo il nuovo `token:` nella voce di quel TV
  (`nano backend/devices.yaml`), poi `docker compose restart`.

### 7. Monitor e backup

- In Uptime Kuma, un monitor HTTP su `http://127.0.0.1:8100/api/health`
  ([capitolo 4](04-servizi-base.md#uptime-kuma-monitoraggio-e-notifiche)).
- Il backup include già `/srv/apps/localclima` con `devices.yaml` e `.env`.

### Aggiornare

```sh
cd /srv/apps/localclima
git pull
docker compose up -d --build
docker image prune -f
```

Il container viene ricreato solo se l'immagine è cambiata; l'interruzione dura pochi secondi.

### Se non trova condizionatori o TV

```sh
sudo ufw status | grep -i discovery                       # la regola per le risposte alla discovery c'è?
docker compose exec localclima msmart-ng discover         # discovery dei condizionatori dal container
docker compose logs --since 10m | grep -i -E "moved|offline|error"
```

Server e dispositivi devono essere nella stessa rete (non la rete ospiti del router). Altri casi in
[problemi comuni](09-problemi-comuni.md).

Avanti: [6. Backup](06-backup.md).
