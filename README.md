# homeserver

La "ricetta" del server di casa: tutto quello che serve per trasformare un computer qualsiasi (nel
nostro caso un portatile di qualche anno) in un server Linux acceso 24 ore su 24, che ospita le
app di casa (domotica e altro). La prima app è LocalClima (condizionatori e TV, repository a parte).

Non è un'app: sono script, configurazioni e guide. Con questo repository e il backup il server si
reinstalla da zero seguendo le guide, senza dover ricordare nulla.

- **Hardware**: la macchina server, nel nostro caso un portatile HP consumer (Intel Celeron N4020 a
  2 core, 8 GB di RAM, disco da 128 GB, forse eMMC), sempre collegato all'alimentatore, con il
  coperchio chiuso; in rete via cavo (anche con un adattatore USB-Ethernet) o, in mancanza, Wi-Fi.
  Le guide e gli script valgono anche per un desktop o un mini PC: le impostazioni da portatile si
  attivano solo se c'è una batteria.
- **Sistema**: Debian 13 "trixie", senza desktop, gestito via SSH.
- **Niente IP fissi**: il router cambia gli indirizzi ogni poche ore e non vogliamo dipendere dalla
  sua configurazione. Server e app si raggiungono per nome (`casa.local`, `localclima.local`…),
  con mDNS, anche dai telefoni.

## Come è fatto

```text
 Rete di casa                                    Server "casa" · Debian 13
 ───────────────                                 ─────────────────────────────────────────────────
                        mDNS (avahi)             casa.local + localclima.local, status.local,
 telefono, PC  ◄──────────────────────────────── dockge.local: tutti puntano all'IP attuale

 http://localclima.local ─┐                      ┌─► 127.0.0.1:8100  LocalClima ──► condizionatori,
 http://status.local ─────┼──► :80  Caddy ───────┼─► 127.0.0.1:3001  Uptime Kuma     TV (LAN)
 http://dockge.local ─────┘    (unico ingresso)  └─► 127.0.0.1:5001  Dockge ──► /srv/apps/*

 ssh casa, VS Code ────────────► :22  sshd (solo chiave)
 da fuori casa ───────────────► Tailscale (facoltativo, nessuna porta aperta sul router)

                                                 restic, ogni notte ──► disco USB (+ copia remota)
```

Sul server:

| Percorso | Cosa |
| --- | --- |
| `/srv/homeserver` | questo repository |
| `/srv/apps/<app>` | ogni app: clone del suo repository, compose, segreti (`.env`, `devices.yaml`) |
| `/srv/data/<servizio>` | dati di Caddy, Dockge, Uptime Kuma |
| `/etc/homeserver` | impostazioni e password del backup (solo root) |

## Percorso rapido

1. [Prima dell'installazione](docs/01-prima-dell-installazione.md): salva i dati, prova l'hardware, BIOS,
   chiavetta.
2. [Installare Debian](docs/02-installare-debian.md): hostname `casa`, solo *SSH server* e
   *standard system utilities*.
3. [Primo avvio](docs/03-primo-avvio.md): chiave SSH dal PC, `ssh casa`, poi:

   ```sh
   sudo install -d -o "$USER" -g "$USER" /srv/homeserver
   gh repo clone <utente-github>/homeserver /srv/homeserver
   sudo bash /srv/homeserver/scripts/bootstrap.sh
   ```

4. Su un portatile, [3b. Un portatile come server](docs/03b-portatile-come-server.md): verifica
   coperchio, sospensione, schermo, batteria, Wi-Fi.
5. [App](docs/05-app.md): LocalClima in `/srv/apps/localclima`.
6. [Backup](docs/06-backup.md): disco USB, `backup.sh init`, timer notturno.
7. [Sviluppo remoto](docs/10-sviluppo-remoto.md): con il portatile attuale si sviluppa sul PC
   Windows; su una macchina più potente, facoltativo: `scripts/dev-tools.sh`, VS Code Remote-SSH,
   Claude Code in tmux.

## Guide

| Capitolo | Contenuto |
| --- | --- |
| [1. Prima dell'installazione](docs/01-prima-dell-installazione.md) | salvare i dati, controllare l'hardware, tasti e BIOS (HP), rete, chiavetta con Rufus o Ventoy |
| [2. Installare Debian](docs/02-installare-debian.md) | l'installer passo per passo, con cavo o Wi-Fi |
| [3. Primo avvio](docs/03-primo-avvio.md) | SSH da Windows con chiave e per nome, repository, bootstrap |
| [3b. Un portatile come server](docs/03b-portatile-come-server.md) | coperchio chiuso, niente sospensione, schermo spento, batteria, Wi-Fi o adattatore USB-Ethernet, temperature, eMMC, verifiche |
| [4. Servizi di base](docs/04-servizi-base.md) | nomi mDNS, Caddy, Dockge, Uptime Kuma, firewall, aggiornamenti |
| [5. App](docs/05-app.md) | LocalClima sul server; [aggiungere un'app](apps/README.md) |
| [6. Backup](docs/06-backup.md) | restic su disco USB, copia fuori casa, ripristino |
| [7. Accesso remoto](docs/07-accesso-remoto.md) | Tailscale, MagicDNS, Tailscale Serve |
| [8. Manutenzione](docs/08-manutenzione.md) | aggiornamenti, log, spazio, blackout, reinstallazione |
| [9. Problemi comuni](docs/09-problemi-comuni.md) | `.local` dal telefono, SSH, firewall, Docker, backup |
| [10. Sviluppo remoto](docs/10-sviluppo-remoto.md) | dove sviluppare (sul PC, con questo server), strumenti di sviluppo, VS Code Remote-SSH, porte, Claude Code in tmux, sviluppo e produzione insieme |
| [Da studiare](docs/da-studiare.md) | gli argomenti incontrati durante la preparazione, da approfondire, con i comandi per fare pratica |

## Il repository

```text
scripts/bootstrap.sh       configura un Debian 13 appena installato (idempotente)
scripts/mdns-aliases.sh    pubblica i nomi delle app via mDNS e li sposta quando cambia l'IP
scripts/backup.sh          backup restic: init, run, test-restore, restic …
scripts/battery-limit.sh   limite di carica della batteria, sui portatili che lo permettono
scripts/dev-tools.sh       strumenti di sviluppo (facoltativi): gh, Node.js, uv, Claude Code
scripts/lib/common.sh      funzioni comuni degli script
systemd/                   nomi mDNS, backup notturno, pulizia settimanale di Docker, limite di carica
infra/compose.yaml         Caddy, Dockge, Uptime Kuma
infra/caddy/               Caddyfile, un sito per app in sites/, pagina iniziale in www/
infra/mdns/aliases         i nomi .local delle app
apps/                      impostazioni lato server delle app e modello per quelle nuove
config/                    modelli delle impostazioni del backup
docs/                      le guide
Makefile                   comandi di tutti i giorni sul server (make per l'elenco)
```

Regole: niente segreti in git (sono in `/etc/homeserver` e accanto alle app, e finiscono nel
backup); script bash con `set -euo pipefail` e puliti per **shellcheck**; YAML validi per
**yamllint**; Caddyfile validato. La CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) li
controlla a ogni push; sul server, `make lint`.
