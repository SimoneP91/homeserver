# App del server

Ogni app è un progetto docker compose a sé in `/srv/apps/<app>` (di solito il clone del suo
repository), visibile anche da Dockge (<http://dockge.local>). Questa cartella del repo contiene
solo quello che serve **lato server**: impostazioni, istruzioni e il modello per le app nuove.

| Cartella                  | Contenuto                                                        |
| ------------------------- | ---------------------------------------------------------------- |
| [localclima/](localclima/) | file `.env` di produzione per LocalClima (guida: [docs/05-app.md](../docs/05-app.md)) |
| [_template/](_template/)   | `compose.yaml` e sito Caddy di esempio per un'app nuova          |

## Porte

Le app ascoltano solo su `127.0.0.1` (loopback): dalla LAN si arriva a loro esclusivamente
tramite Caddy, sulla porta 80, con il nome `<app>.local`.

| Porta     | Servizio                                             |
| --------- | ---------------------------------------------------- |
| 80, 443   | Caddy (unica porta HTTP aperta verso la LAN)         |
| 2019      | API di amministrazione di Caddy (loopback)           |
| 3001      | Uptime Kuma                                          |
| 5001      | Dockge                                               |
| 8100      | LocalClima (produzione)                              |
| 8101–8199 | app future (produzione): una porta ciascuna          |
| 8000, 5173, 3000… | **libere per lo sviluppo** (`make dev`, Vite…): vedi [docs/10-sviluppo-remoto.md](../docs/10-sviluppo-remoto.md) |

Le porte di produzione stanno nella fascia 81xx proprio per lasciare libere quelle predefinite
dei framework, così un server di sviluppo può girare accanto all'app in produzione.

## Aggiungere un'app

Esempio: un'app `ricette` che ascolta sulla porta 8101.

1. **Codice e compose.** Clona il repository in `/srv/apps/ricette` (deve contenere un
   `compose.yaml` o `docker-compose.yml`; per partire c'è [_template/compose.yaml](_template/compose.yaml)).
   Regole:
   - `restart: unless-stopped`, così riparte dopo un riavvio o un crash;
   - porta pubblicata solo su loopback: `127.0.0.1:8101:<porta interna>`; oppure
     `network_mode: host` se l'app deve vedere la LAN (discovery in broadcast, Wake-on-LAN), e in
     quel caso va configurata per ascoltare su `127.0.0.1:8101`;
   - immagini con la versione maggiore fissata (`postgres:17`, non `latest`);
   - dati persistenti in una sottocartella, per esempio `./data` (bind mount): tutto quello che
     sta in `/srv` finisce nel backup, i volumi Docker con nome **no**;
   - segreti in `.env` o in file ignorati da git, mai nel repository.

2. **Avvio.**

   ```sh
   cd /srv/apps/ricette
   docker compose up -d --build     # --build solo se l'app si costruisce dal sorgente
   docker compose ps                # deve essere "running" (o "healthy")
   curl -I http://127.0.0.1:8101    # risponde?
   ```

3. **Sito Caddy.** Crea `infra/caddy/sites/ricette.caddy` (modello: [_template/site.caddy](_template/site.caddy)):

   ```caddy
   http://ricette.local {
   	reverse_proxy 127.0.0.1:8101
   }
   ```

   poi `cd /srv/homeserver && make caddy-reload`.

4. **Nome mDNS.** Aggiungi `ricette` a [infra/mdns/aliases](../infra/mdns/aliases). Il servizio
   se ne accorge da solo in pochi secondi; controlla con `make aliases`. Se l'app sa annunciarsi
   da sola via mDNS, disattiva quella funzione: il nome lo pubblica il server.

5. **Pagina iniziale** (facoltativo). Aggiungi un link in [infra/caddy/www/index.html](../infra/caddy/www/index.html).

6. **Monitoraggio.** In Uptime Kuma (<http://status.local>): *Add New Monitor* → *HTTP(s)*,
   URL `http://127.0.0.1:8101/` (o l'endpoint di health dell'app), intervallo 60 s, e le
   notifiche che hai configurato. Kuma usa la rete dell'host, quindi raggiunge le porte su
   loopback.

7. **Backup.** Già incluso se i dati stanno in `/srv/apps/ricette`. Se l'app usa SQLite,
   aggiungi il percorso del database a `BACKUP_SQLITE` in `/etc/homeserver/backup.env` per una
   copia coerente anche ad app accesa (vedi [docs/06-backup.md](../docs/06-backup.md)).

8. **Committa** in questo repository il sito Caddy, l'alias e il link: così una reinstallazione
   da zero li ritrova.

## Aggiornare un'app

```sh
cd /srv/apps/<app>
git pull
docker compose up -d --build
docker image prune -f            # elimina le immagini vecchie
```

Il pulsante *Update* di Dockge fa `docker compose pull` (immagini già pronte) ma **non**
ricostruisce: per le app costruite dal sorgente, come LocalClima, usa i comandi sopra.

## Togliere un'app

```sh
cd /srv/apps/<app> && docker compose down       # aggiungi -v per cancellare anche i volumi
```

poi rimuovi il sito in `infra/caddy/sites/`, l'alias in `infra/mdns/aliases`, il link nella
pagina iniziale e il monitor in Uptime Kuma, e lancia `make caddy-reload`.
