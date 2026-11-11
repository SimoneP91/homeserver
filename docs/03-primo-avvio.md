# 3. Primo avvio: SSH, repository, bootstrap

Da qui in poi si lavora dal PC Windows. Alla fine il server è configurato e si raggiunge con
`ssh casa`, senza password e senza conoscere il suo IP.

Nei comandi: `casa` è l'hostname scelto all'installazione, `<utente>` il tuo utente sul server.

## 1. Il client SSH di Windows

Windows 11 ha già OpenSSH. Controlla in PowerShell:

```powershell
ssh -V
```

Se il comando non esiste: *Impostazioni → Sistema → Funzionalità facoltative → Aggiungi →
Client OpenSSH*.

## 2. Creare la chiave SSH (sul PC Windows)

```powershell
ssh-keygen -t ed25519 -C "pc-windows"
```

Premi `Invio` per il percorso proposto (`C:\Users\<te>\.ssh\id_ed25519`). La *passphrase* protegge
la chiave se qualcuno copia il file: è consigliata. Per non doverla riscrivere ogni volta, fai
ricordare la chiave all'agente SSH di Windows (PowerShell **come amministratore**, una volta sola):

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
```

poi, in un PowerShell normale:

```powershell
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

Il file **senza** estensione è la chiave privata: non va mai copiata altrove. Sul server va solo
`id_ed25519.pub`.

## 3. Copiare la chiave sul server

Su Windows non c'è `ssh-copy-id`; questo comando fa la stessa cosa (chiede la password del server
per l'ultima volta):

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh <utente>@casa.local "umask 077; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

Alla prima connessione SSH chiede di confermare l'impronta del server: rispondi `yes`.

## 4. `ssh casa`: la configurazione sul PC

Crea il file `C:\Users\<te>\.ssh\config` (senza estensione):

```powershell
notepad $env:USERPROFILE\.ssh\config
```

con questo contenuto:

```text
Host casa
    HostName casa.local
    User <utente>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    HostKeyAlias casa
    ServerAliveInterval 30
    ServerAliveCountMax 4
```

- `HostName casa.local`: il nome mDNS, che segue il server anche quando il router gli cambia IP.
- `HostKeyAlias casa`: l'impronta del server è ricordata sotto il nome `casa`, qualunque indirizzo
  tu usi per raggiungerlo (nome, IP, Tailscale): niente avvisi a ogni cambio di IP.
- `ServerAlive…`: tiene viva la connessione e si accorge in 2 minuti se è caduta.

Salva come file **senza** `.txt` (in Blocco note: *Tipo file → Tutti i file*). Prova:

```powershell
ssh casa
```

Deve entrare senza chiedere la password del server.

### Se `casa.local` non si risolve

Il nome mDNS funziona solo nella stessa rete. Alternative, senza cambiare la configurazione:

1. **IP dal router**: nella pagina del router, elenco dei dispositivi/DHCP, cerca `casa`. Poi:

   ```powershell
   ssh -o HostName=192.168.1.23 casa
   ```

   (utente, chiave e impronta restano quelli di `Host casa`).
2. **IP dal server**: con monitor e tastiera, `ip -4 addr show`.
3. **Tailscale**, anche da fuori casa: `ssh -o HostName=casa casa` (vedi
   [7. Accesso remoto](07-accesso-remoto.md)).

Per capire se il problema è il nome: `ping casa.local` e `Resolve-DnsName casa.local`.

## 5. Portare questo repository sul server

Il repository deve stare in **`/srv/homeserver`**: i servizi installati dal bootstrap puntano lì.

**Opzione A, GitHub (consigliata).** Sul PC, pubblica il repository su GitHub (privato va bene).
Sul server:

```sh
sudo apt install -y git gh
gh auth login                    # GitHub.com → HTTPS → login con il browser: apri il link sul PC e inserisci il codice
sudo install -d -o "$USER" -g "$USER" /srv/homeserver
gh repo clone <utente-github>/homeserver /srv/homeserver
```

**Opzione B, senza GitHub.** Da PowerShell sul PC:

```powershell
scp -r C:\Users\<te>\Documents\Development\homeserver casa:/tmp/homeserver
```

e sul server:

```sh
sudo install -d -o "$USER" -g "$USER" /srv/homeserver
cp -a /tmp/homeserver/. /srv/homeserver/ && rm -rf /tmp/homeserver
git -C /srv/homeserver reset --hard     # ripristina i permessi di esecuzione persi da Windows
```

## 6. Lanciare il bootstrap

```sh
sudo bash /srv/homeserver/scripts/bootstrap.sh
```

Opzioni utili (si possono aggiungere anche rilanciandolo in seguito):

| Opzione | Effetto |
| --- | --- |
| `--tailscale` | installa anche Tailscale ([capitolo 7](07-accesso-remoto.md)) |
| `--auto-reboot 04:30` | dopo un aggiornamento che lo richiede (kernel), riavvia da solo a quell'ora |
| `--locale it_IT.UTF-8` | sistema in italiano |
| `--help` | tutte le opzioni |

Ci mette 5–10 minuti. Cosa fa, in ordine:

1. aggiorna il sistema e installa i pacchetti di base (git, make, tmux, restic, avahi, ufw…);
2. fuso orario `Europe/Rome`, ora sincronizzata via NTP, lingue inglese e italiano;
3. limita lo spazio del journal di sistema (500 MB) e dei log dei container (30 MB ciascuno);
4. aggiornamenti di sicurezza automatici (unattended-upgrades);
5. Docker Engine e il plugin compose, dal repository ufficiale di Docker; il tuo utente entra nel
   gruppo `docker`;
6. avahi (mDNS): `casa.local` solo in IPv4 e solo sulla scheda di rete del router;
7. le cartelle `/srv/apps`, `/srv/data`, `/etc/homeserver`;
8. il servizio che pubblica i nomi delle app (`localclima.local`, `status.local`,
   `dockge.local`);
9. backup: copia le impostazioni in `/etc/homeserver/backup.env` (si attivano nel
   [capitolo 6](06-backup.md));
10. firewall (ufw), descritto nel [capitolo 4](04-servizi-base.md#firewall);
11. **SSH solo con chiave**: se nel tuo `~/.ssh/authorized_keys` c'è una chiave, disattiva
    l'accesso con password e l'accesso come root;
12. avvia Caddy, Dockge e Uptime Kuma.

Si può rilanciare quando vuoi (per esempio dopo un `git pull` di questo repository): modifica solo
ciò che manca o è diverso.

### Verificare SSH prima di chiudere la sessione

Se il bootstrap ha appena disattivato le password, stampa un avviso. **Non chiudere la finestra in
cui l'hai lanciato.** Apri un **secondo** PowerShell e prova:

```powershell
ssh casa
```

Se entra, va tutto bene. Se no, nella prima finestra (ancora aperta) annulla la modifica e cerca
la causa:

```sh
sudo rm /etc/ssh/sshd_config.d/10-homeserver.conf && sudo systemctl reload ssh
```

Se nel tuo `authorized_keys` non c'era ancora una chiave, il bootstrap lascia le password attive:
completa il passo 3 e rilancialo.

## 7. Controlli finali

Esci e rientra (`exit`, poi `ssh casa`): serve perché il gruppo `docker` valga anche per te. Poi:

```sh
cd /srv/homeserver
make ps          # caddy, dockge, uptime-kuma: "Up"
make aliases     # ogni nome .local con l'IP attuale del server
sudo ufw status verbose
```

E dal PC o dal telefono, nella rete di casa:

- <http://casa.local>: la pagina iniziale con i link;
- <http://status.local>: Uptime Kuma. Crea subito l'account amministratore e, se chiede il tipo di
  database, scegli **SQLite** (il backup è pensato per quello);
- <http://dockge.local>: Dockge. Crea subito l'account amministratore.

Da questo momento monitor e tastiera si possono scollegare.

## Se SSH smette di funzionare

Collega monitor e tastiera ed entra dalla console, poi a seconda del caso:

```sh
ip -4 addr show                                              # che IP ha? è in rete?
sudo rm /etc/ssh/sshd_config.d/10-homeserver.conf && sudo systemctl reload ssh   # riattiva le password
sudo ufw disable                                             # esclude il firewall (riattivalo dopo: sudo ufw enable)
systemctl status ssh
```

Se non riesci nemmeno a entrare dalla console, avvia la chiavetta di Debian e scegli
*Advanced options → Rescue mode*.

Avanti: [4. Servizi di base](04-servizi-base.md). Per sviluppare sul server:
[10. Sviluppo remoto](10-sviluppo-remoto.md).
