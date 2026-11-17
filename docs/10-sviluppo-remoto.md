# 10. Sviluppo remoto (facoltativo)

## Prima di tutto: dove sviluppare

**Con il server attuale (Celeron N4020, 2 core, 8 GB), lo sviluppo quotidiano resta sul PC
Windows.** VS Code Remote-SSH, `npm install`, le build di Vite, i test e Claude Code consumano CPU
e memoria: su 2 core lenti sarebbero scomodi e rallenterebbero le app in produzione che girano
accanto.

| Dove | Cosa |
| --- | --- |
| PC Windows | sviluppo: editor, `make dev`, test, Claude Code; poi `git push` |
| server | produzione: `git pull` e `docker compose up -d --build` in `/srv/apps/<app>` ([capitolo 5](05-app.md#aggiornare)); più avanti, l'agente self-hosted di Azure DevOps, che costruisce e pubblica le app (più lento che sul PC, ma va bene: lavora da solo) |

Il resto di questo capitolo serve **se un giorno il server sarà una macchina più potente** (o per
una modifica al volo): descrive come svilupparci sopra da Windows, via SSH. `dev-tools.sh` resta
facoltativo e il bootstrap non lo lancia.

## Sviluppare sul server, via SSH

Il server non ha monitor: ci si sviluppa sopra **da Windows, via SSH**. VS Code (Remote-SSH) mostra
l'editor sul PC, ma file, terminale, compilazioni e server di sviluppo girano sul server. Claude Code
gira sul server dentro tmux, così le sessioni sopravvivono alle disconnessioni. Le app in
produzione restano accese nel frattempo.

Prerequisito: `ssh casa` funziona con la chiave ([capitolo 3](03-primo-avvio.md)).

## Dove stanno i repository

Due copie per ogni app, con ruoli diversi:

| | Produzione | Sviluppo |
| --- | --- | --- |
| Percorso | `/srv/apps/<app>` | `~/dev/<app>` |
| Cosa ci fai | solo `git pull` e `docker compose up -d --build` | branch, modifiche, `make dev`, test |
| Impostazioni | `.env` di produzione (porta 8100, mDNS spento) | le tue, di sviluppo |
| Visto da | Dockge, backup | backup (senza `node_modules`, `.venv`…) |

Perché due copie e non una: la produzione non esegue mai codice scritto a metà; un esperimento
rotto non spegne i condizionatori; i file `.env` di produzione e di sviluppo non si mescolano
(LocalClima legge `backend/.env` in entrambi i casi); `git status` in produzione è sempre pulito.
Il prezzo è un passaggio in più per pubblicare una modifica ([sotto](#portare-una-modifica-in-produzione)).

## 1. Installare gli strumenti

```sh
sudo bash /srv/homeserver/scripts/dev-tools.sh --claude
```

Chiede nome ed email per i commit di git (oppure `--git-name "…" --git-email …`). Installa, oltre a
`make`, `build-essential`, `tmux`, `shellcheck` e `yamllint`:

| Strumento | Da dove | Perché così |
| --- | --- | --- |
| GitHub CLI (`gh`) | repository apt ufficiale di GitHub | login a GitHub e PR da terminale; aggiornato con `apt` |
| Node.js 24 | repository apt di NodeSource | una sola versione per tutto il sistema, aggiornata con `apt` insieme al resto, uguale per terminale, VS Code e `make`, senza un version manager da caricare in ogni shell. 24 è la versione LTS che usa LocalClima; un'altra con `--node-major 26` |
| uv | installer ufficiale, nella tua home | gestisce progetti Python e scarica da solo il Python giusto (LocalClima vuole 3.12, Debian ha 3.13) |
| Claude Code | installer nativo ufficiale (`curl -fsSL https://claude.ai/install.sh \| bash`), nella tua home | metodo raccomandato; si aggiorna da solo |

Poi esci e rientra (il `PATH` nuovo vale dal login successivo) e collega GitHub:

```sh
gh auth login          # GitHub.com → HTTPS → login con il browser sul PC
gh auth setup-git      # git push/pull via HTTPS usano il login di gh
```

E il primo repository:

```sh
mkdir -p ~/dev && cd ~/dev
gh repo clone <utente-github>/localclima
cd localclima
make install           # uv sync + npm ci
make dev-sim           # backend :8000 + Vite :5173, con dispositivi simulati
```

## 2. VS Code Remote-SSH

1. Sul PC installa VS Code e l'estensione **Remote - SSH** (`ms-vscode-remote.remote-ssh`).
2. `F1` → *Remote-SSH: Connect to Host…* → **casa** (legge `C:\Users\<te>\.ssh\config`) → *Linux*.
   La prima volta installa il suo server in `~/.vscode-server` sul server.
3. *File → Open Folder…* → `/home/<utente>/dev/localclima`. Ogni repository è un workspace a sé.
4. Le estensioni (Python, ESLint, Prettier…) vanno installate "in SSH: casa": VS Code lo propone.
5. Il terminale integrato (*Terminal → New Terminal*) è un terminale **sul server**.

Fuori casa, con Tailscale, si usa allo stesso modo l'host `casa-ts`
([capitolo 7](07-accesso-remoto.md#raggiungere-il-server-magicdns)).

### Porte dei server di sviluppo nel browser di Windows

Quando lanci `make dev` nel terminale di VS Code, VS Code si accorge delle porte 8000 e 5173 e le
**inoltra** dentro la connessione SSH: sul PC apri <http://localhost:5173>. Il pannello *Ports*
(*View → Ports*) mostra gli inoltri e permette di aggiungerne altri. Funziona ovunque funzioni SSH,
anche fuori casa.

Senza VS Code, lo stesso con SSH da PowerShell:

```powershell
ssh -L 5173:localhost:5173 -L 8000:localhost:8000 casa
```

## 3. Sviluppo e produzione insieme

| | Produzione (`/srv/apps/localclima`) | Sviluppo (`~/dev/localclima`) |
| --- | --- | --- |
| Come gira | container Docker, sempre acceso | `make dev` / `make dev-sim`, quando serve |
| Backend | `127.0.0.1:8100` | `:8000` |
| Frontend | servito dal backend | Vite `:5173` (inoltra `/api` al backend :8000) |
| Nome in rete | `localclima.local`, tramite Caddy | nessuno: `make dev` non annuncia mDNS |
| Raggiungibile | dalla LAN, tramite Caddy | dal PC tramite l'inoltro SSH |

Per questo la produzione usa le porte 81xx: le porte predefinite dei framework (8000, 5173, 3000…)
restano libere per lo sviluppo ([apps/README.md](../apps/README.md#porte)).

- **Dispositivi veri o simulati.** `make dev-sim` usa dispositivi finti: va bene per quasi tutto il
  lavoro sull'interfaccia. Per provare con quelli veri copia `devices.yaml` (è ignorato da git):

  ```sh
  cp /srv/apps/localclima/backend/devices.yaml ~/dev/localclima/backend/
  ```

  Ricorda che anche la produzione sta parlando con gli stessi dispositivi.
- **Non copiare** il `.env` di produzione nella copia di sviluppo.

### Provare dal telefono

Il firewall **non** apre le porte di sviluppo alla LAN: si raggiungono solo con l'inoltro SSH, così
in rete non finisce mai codice a metà. Per provare l'interfaccia dal telefono, apri la porta di Vite
solo per il tempo che serve (Vite inoltra `/api` al backend sul server, quindi basta la 5173):

```sh
sudo ufw allow from 192.168.0.0/16 to any port 5173 proto tcp comment 'dev: vite, temporary'
hostname -I                     # l'IP del server, per esempio 192.168.1.23
```

Sul telefono apri `http://192.168.1.23:5173`: con l'IP e non con `casa.local`, perché Vite risponde
solo a `localhost` e agli indirizzi IP (per accettare anche il nome, lancia
`__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=casa.local make dev`). Finito:

```sh
sudo ufw delete allow from 192.168.0.0/16 to any port 5173 proto tcp
```

(Se il router usa indirizzi `10.x.x.x`, metti `10.0.0.0/8` al posto di `192.168.0.0/16`.)

## 4. Claude Code sul server, dentro tmux

**tmux** tiene vive le sessioni del terminale sul server: se la connessione cade o chiudi il PC,
Claude Code continua a lavorare e ritrovi tutto riconnettendoti.

```sh
tmux new -A -s claude          # crea la sessione "claude", o ci rientra se esiste già
cd ~/dev/localclima
claude                         # la prima volta: login (sotto)
```

- **Staccarsi** senza chiudere: `Ctrl+b` poi `d`. Ora puoi chiudere SSH.
- **Riattaccarsi**: `ssh casa`, poi `tmux new -A -s claude` (o `tmux ls` per l'elenco).
- Altri tasti: `Ctrl+b c` nuova finestra, `Ctrl+b n` la successiva, `Ctrl+b [` per scorrere
  (`q` per uscire). Per scorrere con il mouse: `echo 'set -g mouse on' >> ~/.tmux.conf`.

**Login.** Il server non ha un browser: al primo `claude` scegli il login con l'account, apri sul
PC il link che stampa e incolla nel terminale il codice che ti mostra.

**Da VS Code.** L'estensione Claude Code funziona anche in Remote-SSH. Però i terminali di VS Code
si chiudono quando VS Code si disconnette: per le sessioni lunghe usa tmux anche lì.

**Attenzione.** Claude Code esegue comandi con il tuo utente, che è nel gruppo `docker` (cioè può
fare tutto sul server). Lavora in `~/dev`, non in `/srv/apps`, e non disattivare le richieste di
permesso su questo server.

## Portare una modifica in produzione

```sh
cd ~/dev/localclima
make check && git push                    # lint + test, poi su GitHub
cd /srv/apps/localclima
git pull && docker compose up -d --build && docker image prune -f
```

Senza passare da GitHub, la copia di produzione può prendere i commit direttamente da quella di
sviluppo: `git -C /srv/apps/localclima pull ~/dev/localclima main`.
