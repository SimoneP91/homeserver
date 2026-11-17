# 3b. Un portatile come server

Il nostro server è un **portatile HP consumer** di qualche anno: Intel Celeron N4020 (2 core,
6 W), 8 GB di RAM, disco da 128 GB, forse eMMC. Per le app di casa basta e avanza, consuma poco e
ha una batteria che fa da gruppo di continuità. Però un portatile è fatto per essere chiuso, messo
in borsa e usato a batteria: questo capitolo spiega cosa cambia per tenerlo acceso giorno e notte,
cosa fa il bootstrap e come verificarlo.

Su un desktop o un mini PC questo capitolo non serve: il bootstrap riconosce il portatile dalla
batteria (`/sys/class/power_supply/BAT*`) e altrimenti non tocca nulla.

## Cosa fa il bootstrap su un portatile

| Cosa | Come | File |
| --- | --- | --- |
| [coperchio chiuso](#coperchio-chiuso): nessuna conseguenza | systemd-logind ignora il coperchio | `/etc/systemd/logind.conf.d/50-homeserver-laptop.conf` |
| [niente sospensione](#niente-sospensione-né-ibernazione) né ibernazione | i target di sospensione sono *masked* | link in `/etc/systemd/system/` |
| [schermo spento](#schermo-spento) dopo 60 secondi | parametro del kernel `consoleblank=60` | `/etc/default/grub.d/50-homeserver-laptop.cfg` |
| [limite di carica](#batteria) 75–80%, se il firmware lo permette | `homeserver-battery-limit.service` a ogni avvio | [scripts/battery-limit.sh](../scripts/battery-limit.sh) |
| [Wi-Fi](#rete-cavo-adattatore-usb-o-wi-fi) senza risparmio energetico (anche sui desktop) | hook di ifupdown | `/etc/network/if-up.d/homeserver-wifi-powersave` |
| [temperature](#ventilazione-e-temperature) | pacchetto `lm-sensors` (anche sui desktop) | comando `sensors` |

Per non applicare le impostazioni del portatile: `bootstrap.sh --no-laptop`. Per toglierle dopo,
cancella i file della tabella, poi `sudo systemctl unmask sleep.target suspend.target
hibernate.target hybrid-sleep.target suspend-then-hibernate.target`, `sudo update-grub` e
`sudo systemctl disable homeserver-battery-limit`.

## Rete: cavo, adattatore USB o Wi-Fi

**Il cavo è meglio**: più veloce, latenza costante, nessun problema di segnale con il coperchio
chiuso (le antenne Wi-Fi sono spesso nella cornice dello schermo) e mDNS più affidabile. Se il
portatile non ha la porta di rete, un **adattatore da USB 3 a Gigabit Ethernet** con chip
**Realtek RTL8153** funziona senza installare nulla (driver `r8152`, già nel kernel di Debian).

- Il nome dell'interfaccia di un adattatore USB è `enx` seguito dal suo MAC (per esempio
  `enx00e04c680001`): resta lo stesso per quell'adattatore, cambia se ne usi un altro.
- **Se cambi scheda di rete** (dal Wi-Fi al cavo, un adattatore nuovo) aggiorna
  `/etc/network/interfaces` (sotto) e rilancia il bootstrap: avahi annuncia i nomi `.local` solo
  sulle schede di rete che c'erano quando è stato lanciato.
- Se nei log del kernel (`journalctl -k | grep r8152`) compare un avviso di firmware mancante,
  `sudo apt install firmware-realtek` (l'adattatore funziona comunque).

### ifupdown, non NetworkManager

Senza desktop, l'installer di Debian configura la rete con **ifupdown** (`/etc/network/interfaces`)
e il Wi-Fi con **wpa_supplicant**. Li teniamo:

- è quello che c'è già, senza pacchetti in più, ed è il modo standard di Debian per un server;
- un server ha **una** rete fissa: NetworkManager serve soprattutto a passare da una rete all'altra
  e a gestirle da un desktop;
- cambiare il sistema che gestisce la rete, collegati via SSH proprio attraverso quella rete, è il
  modo più facile per restare chiusi fuori.

Con un cavo o un adattatore USB, il file contiene qualcosa come:

```text
allow-hotplug enx00e04c680001
iface enx00e04c680001 inet dhcp
```

e con il Wi-Fi:

```text
allow-hotplug wlp2s0
iface wlp2s0 inet dhcp
    wpa-ssid NomeDellaRete
    wpa-psk  passwordInChiaro
```

Il file contiene la password: deve essere leggibile solo da root (`sudo chmod 600
/etc/network/interfaces`). Al posto della password in chiaro si può mettere la chiave già
calcolata: `wpa_passphrase "NomeDellaRete"` (chiede la password) stampa una riga `psk=…`, da usare
come `wpa-psk` senza virgolette.

**Cambiare rete o password del Wi-Fi, o passare al cavo.** Fallo **dalla console** (il portatile
aperto), non via SSH attraverso la rete che stai cambiando:

```sh
sudo nano /etc/network/interfaces     # modifica la voce, o aggiungine una per enx…/enp… e commenta il Wi-Fi
sudo ifdown wlp2s0; sudo ifup wlp2s0  # applica (o semplicemente: sudo reboot)
ip -4 addr show                       # c'è un indirizzo?
sudo bash /srv/homeserver/scripts/bootstrap.sh   # avahi sulle schede nuove
```

Meglio una sola rete configurata alla volta: con cavo e Wi-Fi attivi insieme, il server ha due
indirizzi e i telefoni possono riceverne uno qualsiasi.

### Il risparmio energetico del Wi-Fi

Con il risparmio energetico (attivo di default) la scheda Wi-Fi "dorme" tra un pacchetto e
l'altro: le risposte arrivano in ritardo e le domande mDNS dei telefoni vanno perse, così
`localclima.local` a volte non si risolve. Il bootstrap lo spegne subito e installa un hook di
ifupdown che lo rispegne ogni volta che il Wi-Fi si collega. Verifica:

```sh
iw dev                                  # nome dell'interfaccia Wi-Fi
iw dev wlp2s0 get power_save            # deve dire: Power save: off
iw dev wlp2s0 link                      # rete, segnale (dBm: meglio sopra -67) e velocità
```

Se un giorno usi NetworkManager al posto di ifupdown, l'hook non vale: imposta la stessa cosa
sulla connessione (`2` = disattivato):

```sh
sudo nmcli connection modify "NomeConnessione" 802-11-wireless.powersave 2
sudo nmcli connection up "NomeConnessione"
```

Sullo stesso tema, `powertop --auto-tune` **non** viene applicato: attiva il risparmio energetico
di USB, PCIe e Wi-Fi, utile su un portatile a batteria, ma su un server può rendere instabili
l'adattatore USB-Ethernet, il Wi-Fi e la tastiera. Per lo stesso motivo non usiamo TLP
([sotto](#perché-non-tlp)).

## Coperchio chiuso

Di base, chiudendo il coperchio Debian sospende il portatile: il server sparisce dalla rete. Il
bootstrap aggiunge un file di configurazione a systemd-logind che ignora il coperchio in ogni caso
(a batteria, con l'alimentatore, con un monitor esterno), poi gli fa rileggere la configurazione
(`systemctl reload systemd-logind`, che non chiude le sessioni aperte).

```sh
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \
  HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked
# tre righe: s "ignore"
systemd-analyze cat-config systemd/logind.conf | grep -i lid
```

Prova: chiudi il coperchio, poi dal PC `ping casa.local` deve continuare a rispondere. Nel log
(`journalctl -b -u systemd-logind`) compare *Lid closed* senza che succeda altro.

## Niente sospensione né ibernazione

Oltre al coperchio, un tasto di sospensione o un comando sbagliato potrebbero mettere il server a
dormire. Il bootstrap rende impossibili sospensione e ibernazione mascherando i target di systemd
(`sleep.target`, `suspend.target`, `hibernate.target`, `hybrid-sleep.target`,
`suspend-then-hibernate.target`).

```sh
systemctl status sleep.target           # Loaded: masked
systemctl is-enabled suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
                                        # masked, per ciascuno
```

Il tasto di accensione resta com'è: una pressione breve **spegne** il server in modo pulito.

## Schermo spento

Senza desktop, lo schermo del portatile mostra la console di testo e resterebbe acceso per
sempre. Il bootstrap aggiunge al kernel il parametro `consoleblank=60`: dopo 60 secondi senza
usare la tastiera la console si oscura e lo schermo si spegne, retroilluminazione compresa. Basta
premere un tasto per riaccenderlo.

Il parametro è in un file a parte, `/etc/default/grub.d/50-homeserver-laptop.cfg`, che il GRUB di
Debian legge dopo `/etc/default/grub`: così `/etc/default/grub` resta intatto e il parametro è
aggiunto una volta sola. Vale **dal riavvio successivo**.

```sh
cat /proc/cmdline                                 # deve contenere consoleblank=60
cat /sys/module/kernel/parameters/consoleblank    # 60
```

Prova: dopo un minuto senza toccare la tastiera lo schermo deve essere nero e spento (guardalo di
lato o al buio: non deve esserci luce).

## Batteria

Una batteria agli ioni di litio tenuta sempre al 100% e al caldo invecchia in fretta. Molti
portatili permettono di **fermare la carica prima**, per esempio all'80%: con l'alimentatore
sempre collegato la batteria resta lì e il portatile va a corrente.

**Cosa fa il bootstrap.** Se il kernel offre il limite di carica
(`/sys/class/power_supply/BAT0/charge_control_end_threshold`, più eventualmente
`charge_control_start_threshold`; oppure il tipo di carica *Long_Life*), installa
`homeserver-battery-limit.service`, che a ogni avvio imposta: carica fino all'**80%**, ricarica
quando scende sotto il **75%**. Altrimenti stampa un avviso e non fa nulla.

```sh
/srv/homeserver/scripts/battery-limit.sh --check           # cosa offre ogni batteria e il limite attuale
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
systemctl status homeserver-battery-limit
cat /sys/class/power_supply/BAT0/{status,capacity}         # Charging/Not charging/Full, e la carica in %
```

Per altri valori: `sudo systemctl edit homeserver-battery-limit` e scrivi

```ini
[Service]
ExecStart=
ExecStart=/srv/homeserver/scripts/battery-limit.sh 55 60
```

poi `sudo systemctl restart homeserver-battery-limit`. Il driver arrotonda ai valori che
l'hardware supporta: `--check` mostra quelli effettivi.

**Sul nostro HP, quasi certamente non c'è.** Il limite dipende dal driver del produttore: lo
offrono per esempio i ThinkPad e molti ASUS, ma i portatili **HP consumer di solito non lo
espongono a Linux**. Su questo portatile la batteria resterà probabilmente al 100%, ed è
accettabile: invecchierà più in fretta e coprirà blackout più brevi, ma il server funziona lo
stesso. Alternative, se ci sono:

- **nel BIOS** (`F10`): alcuni HP hanno *Adaptive Battery Optimizer* (consumer recenti) o *Battery
  Health Manager* (soprattutto i modelli business, EliteBook e ProBook); su altre marche *Battery
  Charge Limit*, *Primarily AC Use* (Dell), *Conservation mode* (Lenovo IdeaPad, di solito dal
  programma Vantage di Windows: resta impostato anche dopo). Un limite impostato dal BIOS vale
  anche con Linux;
- togliere la batteria e usarlo solo con l'alimentatore: solo se la batteria è rimovibile senza
  aprire il portatile, e si perde il "gruppo di continuità".

**Controlla la batteria ogni tanto**, soprattutto se resta al 100%: se il fondo si solleva, il
touchpad sporge o la scocca si deforma, la batteria si sta **gonfiando**. Spegni il portatile,
staccalo dalla corrente e falla sostituire: una batteria gonfia è pericolosa. Lo stato di salute:

```sh
grep -H . /sys/class/power_supply/BAT0/{energy_full,energy_full_design,charge_full,charge_full_design} 2>/dev/null
# capacità attuale rispetto a quella di fabbrica (energy_* o charge_*, a seconda del modello)
```

### Perché non TLP

TLP è il programma più noto per la batteria dei portatili Linux. Per il limite di carica usa gli
stessi file del kernel di `battery-limit.sh` (più qualche interfaccia specifica di alcuni
produttori), ma fa molto altro: risparmio energetico di CPU, USB, PCIe, Wi-Fi e dischi, pensato
per un portatile che funziona a batteria. Su un server sempre collegato quei risparmi non servono
e possono creare problemi (adattatore USB-Ethernet che si disconnette, Wi-Fi più lento). Il
bootstrap fa solo la parte che serve. Se un giorno il tuo modello supportasse il limite solo
tramite TLP, si può installare impostando soltanto le soglie di carica.

## Blackout

Su un portatile la **batteria fa da gruppo di continuità**: un blackout breve non spegne nulla (il
router invece sì, quindi la rete si ferma finché non torna la corrente).

In un blackout lungo la batteria si scarica e il portatile si spegne di colpo, come farebbe un
desktop appena manca la corrente. Al ritorno della corrente:

- sui desktop e mini PC il BIOS ha di solito *Restore on AC Power Loss → Power On*;
- **sui portatili quella voce di solito non c'è.** Alcuni (diversi HP business, Lenovo e Dell)
  hanno *Power On When AC Detected*, *Wake on AC* o simili: se c'è, attivala
  ([capitolo 1](01-prima-dell-installazione.md#impostazioni-del-bios-uefi));
- altrimenti il portatile resta spento finché non premi il tasto di accensione. Uptime Kuma gira
  sul server e non può avvisarti: per saperlo anche da fuori casa serve un controllo esterno
  ([capitolo 4](04-servizi-base.md#uptime-kuma-monitoraggio-e-notifiche)).

## Ventilazione e temperature

Un portatile acceso giorno e notte, magari chiuso, scalda più di quanto sembri.

- Appoggialo su una **superficie rigida** (tavolo, mensola), mai su letto, divano, tessuti o
  dentro un mobile chiuso; lascia libere le prese d'aria, sotto e ai lati.
- **Coperchio chiuso o aperto**: chiuso va bene se le temperature restano basse; alcuni portatili
  smaltiscono parte del calore attraverso la tastiera, e lì è meglio lasciarlo socchiuso (lo
  schermo si spegne comunque).
- Una volta l'anno togli la polvere dalle prese d'aria (aria compressa, a portatile spento).
- Alcuni HP hanno nel BIOS *Fan Always On*: ventola sempre accesa, più rumore e meno calore.

```sh
sensors                                   # temperature (coretemp: Package id 0, Core 0/1; acpitz)
watch -n 2 sensors                        # dal vivo, mentre per esempio ricostruisci un'app
journalctl -k | grep -i -E 'throttl|thermal|critical'   # surriscaldamenti registrati dal kernel
```

`sensors` funziona di solito senza configurazione; se non mostra la CPU, `sudo sensors-detect`
(rispondi con i valori proposti). Indicativamente, per un Celeron come il nostro: a riposo
35–50 °C, sotto carico fino a 80 °C va bene; se resta stabilmente sopra i 90 °C migliora la
ventilazione.

## Disco piccolo o eMMC

Molti portatili economici, compresi parecchi HP con Celeron N4020, hanno un **eMMC**: memoria
flash saldata sulla scheda madre, simile a una scheda SD. Funziona, ma è più lenta di un SSD e
sopporta meno scritture; e non si sostituisce. Per capire che disco hai:

```sh
lsblk -d -o NAME,MODEL,SIZE,ROTA,TRAN
```

| `NAME` | Cos'è |
| --- | --- |
| `mmcblk0` (con `mmcblk0boot0`, `mmcblk0boot1` di pochi MB) | eMMC |
| `nvme0n1` | SSD NVMe |
| `sda` con `ROTA` 0 e `TRAN` `sata` | SSD SATA (con `ROTA` 1: disco meccanico) |

Il bootstrap stampa lo stesso all'inizio. **Usura dell'eMMC** (`smartctl` non funziona sugli eMMC;
sugli SSD vedi il [capitolo 8](08-manutenzione.md#spazio-su-disco-e-salute-del-disco)):

```sh
cat /sys/block/mmcblk0/device/life_time       # due valori: 0x01 = usato fino al 10%, 0x02 fino al 20%… 0x0b = esaurito
cat /sys/block/mmcblk0/device/pre_eol_info    # 0x01 normale, 0x02 attenzione, 0x03 urgente
```

Cosa limita già le scritture:

- il journal di sistema è limitato a 500 MB e i log di ogni container a 30 MB;
- Debian monta i dischi con `relatime`: la data di ultimo accesso dei file si aggiorna al massimo
  una volta al giorno per file. `noatime` (mai) risparmierebbe pochissimo in più e richiede di
  modificare `/etc/fstab`, dove un errore impedisce l'avvio: non lo applichiamo. Se vuoi farlo
  comunque, aggiungi `,noatime` alle opzioni della riga di `/` (per esempio
  `errors=remount-ro,noatime`), poi `sudo findmnt --verify` prima di riavviare;
- ogni domenica `homeserver-docker-prune.timer` cancella le immagini Docker non più usate.

**Spazio.** 128 GB bastano largamente per queste app; quello che cresce sono le immagini e la
cache di build di Docker:

```sh
df -h /
docker system df                  # immagini, container, volumi, cache di build
docker builder prune              # cache di build (la prossima build sarà più lenta)
docker system prune               # anche container fermi e reti inutilizzate: attenzione, i container
                                  # fermati apposta vengono cancellati (i dati nei volumi restano)
```

## Prestazioni: un Celeron a 2 core

Per far girare le app (Caddy, Dockge, Uptime Kuma, LocalClima) bastano pochi punti percentuali
della CPU e 1–2 GB di RAM. Quello che è lento sono le **compilazioni**:

- la prima `docker compose up -d --build` di LocalClima (dipendenze npm, compilazione del
  frontend, dipendenze Python) può richiedere **parecchi minuti**, anche più di dieci; le build
  successive riusano la cache e sono più rapide. 8 GB di RAM bastano;
- lo sviluppo quotidiano (VS Code, `npm`, test, Claude Code) conviene farlo **sul PC Windows**,
  non sul server ([capitolo 10](10-sviluppo-remoto.md)).

Nulla negli script presuppone più di 2 core.

## Verificare tutto

Dopo il bootstrap e un riavvio (`sudo reboot`):

| Cosa | Comando | Risultato atteso |
| --- | --- | --- |
| coperchio ignorato | `busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitch` | `s "ignore"` |
| niente sospensione | `systemctl is-enabled sleep.target suspend.target hibernate.target` | `masked` |
| schermo spento | `cat /sys/module/kernel/parameters/consoleblank` | `60` |
| limite di carica | `/srv/homeserver/scripts/battery-limit.sh --check` | `charging stops at 80%`, oppure (HP) *no charge limit* |
| Wi-Fi (se usato) | `iw dev wlp2s0 get power_save` | `Power save: off` |
| temperature | `sensors` | a riposo sotto i 50–60 °C |
| disco | `lsblk -d -o NAME,MODEL,SIZE,ROTA,TRAN` | il disco atteso; per un eMMC, `life_time` basso |
| rete | dal PC: `ping casa.local` con il coperchio chiuso | risponde |

Avanti: [4. Servizi di base](04-servizi-base.md).
