# 6. Backup

Ogni notte alle 3 il server salva su un **disco USB** tutto quello che non si può ricostruire,
cifrato, con la cronologia delle versioni. In più, facoltativamente, una copia **fuori casa**.

## Cosa viene salvato

| Percorso | Contenuto |
| --- | --- |
| `/srv/homeserver` | questo repository (anche con modifiche non ancora committate) |
| `/srv/apps` | le app con i loro segreti: `devices.yaml`, `.env`… |
| `/srv/data` | dati di Caddy, Dockge, Uptime Kuma |
| `/etc/homeserver` | impostazioni del backup |
| `/home` | la tua home: cloni di sviluppo, configurazioni |

Esclusi ([config/backup-excludes.txt](../config/backup-excludes.txt)): `node_modules`, `.venv`,
cache, server di VS Code, e tutto ciò che sta in `/var/lib/docker` (immagini, container, volumi
con nome): si ricostruisce con `docker compose up -d --build`. Per questo i dati da conservare
delle app vanno in cartelle sotto `/srv/apps/<app>`, non in volumi Docker.

Il database SQLite di Uptime Kuma viene prima copiato con il backup "a caldo" di SQLite, così la
copia è coerente anche se Kuma sta scrivendo (`BACKUP_SQLITE` nelle impostazioni).

## Perché restic

[restic](https://restic.net) è nei pacchetti di Debian, cifra tutto sul server prima di scrivere,
salva ogni file una volta sola (i backup giornalieri occupano solo le differenze) e scrive
direttamente su disco locale, SFTP, S3/Backblaze B2 e altri, **senza installare nulla dall'altra
parte**. BorgBackup è altrettanto valido ma per la copia remota vuole borg anche sulla
destinazione: con restic la copia fuori casa può essere un semplice spazio cloud.

## Preparare il disco USB

Un disco qualsiasi, anche piccolo (i dati sono pochi GB). Viene **cancellato**.

```sh
lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL,MOUNTPOINTS     # trova il disco USB, per esempio sdb
```

Al posto di `sdX` metti il disco giusto (**non** il disco di sistema, che ha le partizioni montate su
`/` e `/boot/efi`; se il sistema è su un eMMC, `mmcblk0`, il disco USB è spesso `sda`):

```sh
sudo parted /dev/sdX --script mklabel gpt mkpart backup ext4 0% 100%
sudo mkfs.ext4 -L backup /dev/sdX1
sudo mkdir -p /mnt/backup
echo 'LABEL=backup /mnt/backup ext4 defaults,nofail,noatime,x-systemd.device-timeout=10s 0 2' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount /mnt/backup
findmnt /mnt/backup                                     # deve mostrare /dev/sdX1
```

`nofail` fa partire il server anche se il disco non è collegato; in quel caso il backup si rifiuta
di partire (invece di riempire il disco di sistema) e Uptime Kuma te lo segnala.

## Attivare il backup

1. Le impostazioni sono in `/etc/homeserver/backup.env` (modello:
   [config/backup.env.example](../config/backup.env.example)). Quelle predefinite vanno già bene
   per il disco USB:

   ```sh
   sudo nano /etc/homeserver/backup.env
   ```

2. Crea la password e il repository:

   ```sh
   sudo /srv/homeserver/scripts/backup.sh init
   sudo cat /etc/homeserver/restic-password
   ```

   **Copia la password nel tuo password manager.** Senza, i backup sono illeggibili: se il server
   si rompe, la copia che sta sul server non serve.

3. Primo backup, guardandolo, poi il timer notturno:

   ```sh
   cd /srv/homeserver
   make backup
   sudo systemctl enable --now homeserver-backup.timer
   systemctl list-timers homeserver-backup.timer          # prossima esecuzione
   ```

Se il server era spento alle 3, il backup parte al successivo avvio. Ogni backup tiene 7 copie
giornaliere, 4 settimanali e 12 mensili (`BACKUP_KEEP`) e verifica l'integrità del repository.

```sh
make snapshots                                   # elenco delle copie
journalctl -u homeserver-backup -n 50            # com'è andato l'ultimo backup
```

### Notifica in Uptime Kuma

1. In <http://status.local>: *Add New Monitor* → tipo **Push**, *Heartbeat Interval* **90000**
   secondi (25 ore). Copia l'URL che propone.
2. Nell'URL sostituisci `http://status.local` con `http://127.0.0.1:3001` e mettilo, **tra
   virgolette**, in `BACKUP_PUSH_URL` dentro `/etc/homeserver/backup.env`.

Ogni backup riuscito "spinge" il monitor; se per 25 ore non arriva nulla, Kuma ti avvisa.

## Provare il ripristino

Un backup mai provato non è un backup. Una volta al mese:

```sh
make test-restore
```

ripristina `/srv/homeserver` dall'ultima copia in una cartella temporanea, controlla che ci siano i
file e li confronta con quelli attuali (le differenze dovute a modifiche successive sono normali).

## Ripristinare

Un file o una cartella, per esempio `devices.yaml`:

```sh
sudo /srv/homeserver/scripts/backup.sh restic snapshots                       # scegli la copia (o usa latest)
sudo /srv/homeserver/scripts/backup.sh restic restore latest --target /tmp/ripristino \
  --include /srv/apps/localclima/backend/devices.yaml
sudo cp /tmp/ripristino/srv/apps/localclima/backend/devices.yaml /srv/apps/localclima/backend/
sudo rm -rf /tmp/ripristino
```

Per sfogliare tutte le copie come cartelle:

```sh
sudo apt install -y fuse3
sudo mkdir -p /mnt/restic
sudo /srv/homeserver/scripts/backup.sh restic mount /mnt/restic   # resta in primo piano: in un'altra sessione ls /mnt/restic/snapshots/
```

### Tutto il server, su un'installazione nuova

1. Installa Debian e clona questo repository ([capitoli 2](02-installare-debian.md) e
   [3](03-primo-avvio.md)), poi `sudo bash /srv/homeserver/scripts/bootstrap.sh --no-infra`.
2. Collega il disco USB e montalo come sopra (solo `mkdir`, la riga in `/etc/fstab` e `mount`:
   **non** formattarlo).
3. Rimetti la password dal password manager e le impostazioni:

   ```sh
   sudo nano /etc/homeserver/restic-password              # incolla la password
   sudo chmod 600 /etc/homeserver/restic-password
   ```

4. Ripristina `/srv` e `/etc/homeserver` (e, se vuoi, `/home`):

   ```sh
   sudo /srv/homeserver/scripts/backup.sh restic restore latest --target / \
     --include /srv --include /etc/homeserver
   ```

5. Riavvia tutto:

   ```sh
   sudo bash /srv/homeserver/scripts/bootstrap.sh        # riapplica le impostazioni e avvia l'infrastruttura
   cd /srv/apps/localclima && docker compose up -d --build
   sudo systemctl enable --now homeserver-backup.timer
   ```

## Copia fuori casa (facoltativa)

Il disco USB protegge da un guasto del server, non da furto, incendio o fulmine. Regola 3-2-1: tre
copie, su due supporti diversi, una fuori casa. Imposta `OFFSITE_REPOSITORY` in
`/etc/homeserver/backup.env`; ogni notte, dopo il disco USB, il backup viene fatto anche lì, in
modo indipendente. I dati sono cifrati dal server: il fornitore non può leggerli.

- **Backblaze B2** (pochi centesimi al mese per qualche GB): crea un bucket privato e una
  *Application Key* limitata a quel bucket, poi

  ```sh
  OFFSITE_REPOSITORY=s3:https://s3.<regione>.backblazeb2.com/<bucket>/homeserver
  AWS_ACCESS_KEY_ID=<keyID>
  AWS_SECRET_ACCESS_KEY=<applicationKey>
  ```

- **SFTP** verso un altro computer (di un parente, un NAS…) raggiungibile via SSH, magari con
  Tailscale: `OFFSITE_REPOSITORY=sftp:utente@host:/backup/homeserver`. Il backup gira come root:
  crea una chiave per root (`sudo ssh-keygen -t ed25519`) e autorizzala sull'altro computer.

Poi `sudo /srv/homeserver/scripts/backup.sh init` crea il repository remoto e
`sudo /srv/homeserver/scripts/backup.sh restic-offsite snapshots` ne mostra le copie.

Avanti: [7. Accesso remoto](07-accesso-remoto.md).
