# Da studiare

Argomenti incontrati mentre preparavamo il server, da approfondire con calma. Per ognuno: cosa è
successo, i concetti da capire e i comandi per fare pratica.

## Utenti, gruppi e permessi

- **Cosa è successo**: `docker stop` dava *permission denied* finché non siamo usciti e rientrati
  con SSH.
- **Concetti**:
  - utenti e gruppi;
  - i gruppi si leggono **all'accesso**;
  - `sudo`;
  - il gruppo `docker` equivale ad amministratore;
  - permessi dei file (`rwx`, proprietario/gruppo/altri).
- **Comandi**: `id`, `id -nG`, `groups`, `sudo usermod -aG <gruppo> <utente>`, `newgrp`,
  `ls -l`, `chmod`, `chown`.

## systemd: servizi e registri

- **Cosa è successo**: il servizio dei nomi `.local` falliva; l'abbiamo capito leggendo il journal
  e provando varianti con `systemd-run`.
- **Concetti**:
  - unit `.service`, `.timer` e `.target`;
  - `Restart=`, `User=`;
  - le protezioni (`ProtectSystem`, `ProtectHome`, `NoNewPrivileges`, `DynamicUser`);
  - il journal.
- **Comandi**:
  - stato e controllo: `systemctl status|start|stop|restart|enable <servizio>`,
    `systemctl list-timers`, `systemctl cat <servizio>`;
  - registri: `journalctl -u <servizio> -n 50`, `journalctl -b -p err`, `journalctl -f`;
  - prove: `systemd-run`.

## Rete: indirizzi, nomi `.local` e firewall

- **Cosa è successo**: il router cambia gli indirizzi, quindi usiamo i nomi `.local` (mDNS con
  avahi). Il firewall lascia passare solo la rete di casa.
- **Concetti**:
  - DHCP;
  - mDNS e avahi;
  - D-Bus, il canale con cui i programmi di sistema si parlano;
  - porte e `127.0.0.1` rispetto alla rete;
  - reverse proxy (Caddy);
  - firewall con stato (ufw).
- **Comandi**:
  - indirizzi e porte: `ip -4 addr`, `ip route show default`, `ss -ltn`;
  - nomi `.local`: `avahi-resolve -4 -n <nome>.local`, `avahi-browse -a`;
  - firewall: `sudo ufw status verbose`;
  - prove di connessione: `curl -I http://localhost/`.

## Docker e Docker Compose

- **Cosa c'è**: Caddy, Dockge e Uptime Kuma girano in container definiti in
  `infra/compose.yaml`.
- **Concetti**:
  - immagine e container;
  - volumi (i dati in `/srv/data`);
  - `network_mode: host`;
  - `restart: unless-stopped`;
  - aggiornare un'immagine.
- **Comandi**:
  - container: `docker ps`, `docker logs <container>`, `docker stop|start <container>`;
  - Compose: `docker compose -f /srv/homeserver/infra/compose.yaml ps|up -d|pull`;
  - immagini: `docker images`, `docker system df`.

## SSH

- **Cosa è successo**: accesso con chiave invece che con password, poi login con password
  disattivato; nome `localhome.local` in `~/.ssh/config`.
- **Concetti**:
  - coppia di chiavi (privata/pubblica);
  - `authorized_keys`;
  - `known_hosts` e l'impronta del server;
  - il file di configurazione del client.
- **Comandi**: `ssh-keygen`, `ssh localhome`, `scp`, `ssh-keygen -F <host>`,
  `ssh-keyscan`.

## Git senza server remoto

- **Cosa è successo**: `homeserver` è arrivato sul server come `git bundle` copiato con `scp`, in
  attesa di Azure DevOps.
- **Concetti**: remote, `git pull`, bundle.
- **Comandi**: `git remote -v`, `git log --oneline`, `git bundle create`, `git pull`.

## Monitoraggio

- **Cosa c'è**: Uptime Kuma controlla Caddy, Dockge e il router e avvisa sul telefono con ntfy.
  L'abbiamo provato fermando Dockge.
- **Concetti**: controlli HTTP o ping, intervallo, notifiche, i limiti (se il server si spegne non
  può avvisare).
