#!/usr/bin/env bash
# Turn a fresh Debian 13 (trixie) install into the home server. Idempotent: run it again after
# pulling changes to this repository, it only touches what is missing or different.
#
#   sudo /srv/homeserver/scripts/bootstrap.sh [options]
#
# Options:
#   --user NAME          account that manages the server (default: the one running sudo)
#   --locale LOCALE      set the system language, e.g. it_IT.UTF-8 (default: leave it as is)
#   --auto-reboot HH:MM  let unattended-upgrades reboot at that time when an update needs it
#   --tailscale          also install Tailscale (then run: sudo tailscale up)
#   --no-firewall        do not configure or enable ufw
#   --no-infra           do not start the infra stack (Caddy, Dockge, Uptime Kuma)
#   --no-ssh-hardening   keep password logins over SSH even when a key is installed
#   --no-laptop          on a laptop, leave lid, sleep, screen and battery settings alone
#   -h, --help           show this help
#
# See docs/03-primo-avvio.md (and docs/03b-portatile-come-server.md on a laptop).
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EXPECTED_REPO_DIR=/srv/homeserver
# shellcheck source=lib/common.sh
source "$REPO_DIR/scripts/lib/common.sh"

# Private address ranges: the LAN, whatever the router uses. The server sits behind the router's
# NAT, so these are the only IPv4 sources that can reach it; for IPv6 only link-local and ULA
# addresses are allowed, so a router that lets IPv6 in does not expose the apps to the Internet.
LAN_V4=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16)
LAN_V6=(fe80::/10 fc00::/7)

TIMEZONE=Europe/Rome
DATA_DIRS=(/srv/data/caddy/data /srv/data/caddy/config /srv/data/dockge /srv/data/uptime-kuma)

opt_user=${SUDO_USER:-}
opt_locale=''
opt_reboot=''
opt_tailscale=false
opt_firewall=true
opt_infra=true
opt_ssh_hardening=true
opt_laptop=true

usage() {
  sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"
}

parse_args() {
  while (($#)); do
    case $1 in
      --user) opt_user=${2:?--user needs a name}; shift ;;
      --locale) opt_locale=${2:?--locale needs a value, e.g. it_IT.UTF-8}; shift ;;
      --auto-reboot) opt_reboot=${2:?--auto-reboot needs a time, e.g. 04:30}; shift ;;
      --tailscale) opt_tailscale=true ;;
      --no-firewall) opt_firewall=false ;;
      --no-infra) opt_infra=false ;;
      --no-ssh-hardening) opt_ssh_hardening=false ;;
      --no-laptop) opt_laptop=false ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  if [[ -n $opt_reboot && ! $opt_reboot =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    die "--auto-reboot wants HH:MM, e.g. 04:30"
  fi
}

check_system() {
  step "Checking the system"
  [[ $REPO_DIR == "$EXPECTED_REPO_DIR" ]] ||
    die "this repository must be cloned to $EXPECTED_REPO_DIR (it is in $REPO_DIR): the services point there"
  [[ -n $opt_user ]] || die "cannot tell which user manages the server: run with sudo, or pass --user NAME"
  [[ $opt_user != root ]] || die "pass your own account with --user, not root"
  id "$opt_user" >/dev/null 2>&1 || die "user '$opt_user' does not exist"
  local codename
  codename=$(debian_codename)
  if [[ $codename != trixie ]]; then
    warn "this was written for Debian 13 (trixie), found '${codename:-unknown}': continuing anyway"
  fi
  [[ $(dpkg --print-architecture) == amd64 ]] || warn "written for amd64, found $(dpkg --print-architecture)"
  ok "Debian ${codename:-?}, user $opt_user, repository in $REPO_DIR"
}

base_packages() {
  step "Updating the system and installing the base packages"
  apt_get update
  apt_get full-upgrade
  apt_install ca-certificates curl gnupg git make jq sqlite3 rsync tmux htop ncdu \
    locales unattended-upgrades apt-listchanges lm-sensors \
    avahi-daemon avahi-utils libnss-mdns ufw restic
  # SSD health (smartctl); its recommends would pull in a mail server.
  apt_install --no-recommends smartmontools
  # Time sync: keep chrony if someone installed it, otherwise systemd's own client.
  if ! dpkg-query -W -f='${Status}' chrony 2>/dev/null | grep -q 'install ok installed'; then
    apt_install systemd-timesyncd
  fi
}

time_and_locale() {
  step "Time zone and locale"
  timedatectl set-timezone "$TIMEZONE"
  timedatectl set-ntp true || warn "could not enable NTP time sync"
  ok "time zone $TIMEZONE, NTP on"

  # Generate English (clearer error messages to search for) and Italian.
  local loc changed=false
  for loc in en_US.UTF-8 it_IT.UTF-8; do
    if ! grep -Eq "^${loc//./\\.} UTF-8" /etc/locale.gen; then
      if grep -Eq "^# *${loc//./\\.} UTF-8" /etc/locale.gen; then
        sed -i -E "s/^# *(${loc//./\\.} UTF-8)/\1/" /etc/locale.gen
      else
        printf '%s UTF-8\n' "$loc" >>/etc/locale.gen
      fi
      changed=true
    fi
  done
  if $changed; then locale-gen; else info "locales already generated"; fi
  if [[ -n $opt_locale ]]; then
    update-locale "LANG=$opt_locale"
    ok "system language: $opt_locale (applies at the next login)"
  fi
}

journald_limits() {
  step "Limiting the size of the system journal"
  if write_file /etc/systemd/journald.conf.d/50-homeserver.conf 0644 <<'EOF'; then
# Managed by /srv/homeserver/scripts/bootstrap.sh
[Journal]
Storage=persistent
SystemMaxUse=500M
SystemKeepFree=2G
MaxRetentionSec=3month
EOF
    systemctl restart systemd-journald
  fi
}

laptop() {
  step "Laptop: lid, sleep, screen, battery"
  local batteries
  batteries=$(system_batteries)
  if [[ -z $batteries ]]; then
    info "no battery: not a laptop, nothing to do"
    return 0
  fi
  if ! $opt_laptop; then
    warn "battery found, but skipped (--no-laptop): closing the lid may suspend the server"
    return 0
  fi
  info "battery found ($(xargs -n1 basename <<<"$batteries" | xargs)): this is a laptop"
  laptop_lid
  laptop_no_sleep
  laptop_screen_off
  laptop_battery_limit
}

laptop_lid() {
  if write_file /etc/systemd/logind.conf.d/50-homeserver-laptop.conf 0644 <<'EOF'; then
# Managed by /srv/homeserver/scripts/bootstrap.sh (--no-laptop to skip).
# A laptop used as a server: closing the lid does nothing, on battery, on AC power or docked.
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
    # systemd-logind is a Type=notify-reload service (systemd 253 and later): a reload makes it
    # read its configuration again without ending the login sessions, as a restart could.
    systemctl reload systemd-logind
  fi
  local value
  value=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
    org.freedesktop.login1.Manager HandleLidSwitch 2>/dev/null || true)
  if [[ $value == 's "ignore"' ]]; then
    ok "closing the lid: ignored"
  else
    warn "logind reports HandleLidSwitch ${value:-unknown}: see systemd-analyze cat-config systemd/logind.conf"
  fi
}

laptop_no_sleep() {
  local target todo=()
  for target in sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target; do
    [[ $(systemctl is-enabled "$target" 2>/dev/null || true) == masked ]] || todo+=("$target")
  done
  if ((${#todo[@]})); then
    systemctl mask --quiet "${todo[@]}"
    ok "suspend and hibernation off (masked: ${todo[*]})"
  else
    info "suspend and hibernation already off"
  fi
}

laptop_screen_off() {
  if [[ ! -f /etc/default/grub ]] || ! command -v update-grub >/dev/null; then
    warn "GRUB not found: add consoleblank=60 to the kernel command line by hand to turn the screen off"
    return 0
  fi
  # A drop-in rather than an edit of /etc/default/grub: Debian's grub-mkconfig reads
  # /etc/default/grub.d/*.cfg after it, and the line is added exactly once.
  if write_file /etc/default/grub.d/50-homeserver-laptop.cfg 0644 <<'EOF'; then
# Managed by /srv/homeserver/scripts/bootstrap.sh (--no-laptop to skip).
# Blank the text console after 60 s without keyboard input: the laptop's screen and its
# backlight go off.
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT consoleblank=60"
EOF
    update-grub
  fi
  if grep -qw consoleblank=60 /proc/cmdline; then
    ok "screen off after 60 s without input"
  else
    info "screen off after 60 s without input: from the next reboot"
  fi
}

laptop_battery_limit() {
  local unit=homeserver-battery-limit.service line
  chmod 0755 "$REPO_DIR/scripts/battery-limit.sh"
  if ! "$REPO_DIR/scripts/battery-limit.sh" --check >/dev/null; then
    warn "the firmware does not let Linux limit the battery charge (common on HP and other"
    warn "consumer laptops): it charges to 100%. Look for a charge limit in the BIOS, see"
    warn "docs/03b-portatile-come-server.md"
    return 0
  fi
  install_unit "$unit" || true
  systemctl daemon-reload
  systemctl enable --quiet "$unit"
  # Always run it again: it is cheap, and puts back a limit changed by hand.
  systemctl restart "$unit" || warn "$unit failed: journalctl -u $unit"
  while IFS= read -r line; do ok "$line"; done < <("$REPO_DIR/scripts/battery-limit.sh" --check || true)
}

automatic_updates() {
  step "Automatic security updates (unattended-upgrades)"
  write_file /etc/apt/apt.conf.d/20auto-upgrades 0644 <<'EOF' || true
// Managed by /srv/homeserver/scripts/bootstrap.sh
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
  local reboot=false time=04:30
  if [[ -n $opt_reboot ]]; then
    reboot=true
    time=$opt_reboot
  fi
  # Debian's 50unattended-upgrades already selects the Debian and Debian-Security origins.
  write_file /etc/apt/apt.conf.d/52homeserver-unattended-upgrades 0644 <<EOF || true
// Managed by /srv/homeserver/scripts/bootstrap.sh (--auto-reboot HH:MM turns reboots on)
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "$reboot";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "$time";
EOF
  systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null
  if $reboot; then ok "automatic reboot when needed, at $time"; else info "automatic reboot: off"; fi
}

install_docker() {
  step "Docker Engine and the compose plugin (Docker's apt repository)"
  local pkg old=()
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then old+=("$pkg"); fi
  done
  if ((${#old[@]})); then
    warn "removing packages that conflict with Docker's own: ${old[*]}"
    apt_get remove "${old[@]}"
  fi

  fetch_key https://download.docker.com/linux/debian/gpg docker.asc
  if write_file /etc/apt/sources.list.d/docker.sources 0644 <<EOF; then
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(debian_codename)
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    apt_get update
  fi
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Container logs are rotated (the default json-file driver grows forever).
  if write_file /etc/docker/daemon.json 0644 <<'EOF'; then
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
    systemctl restart docker
    info "log limits apply to containers created from now on"
  fi
  systemctl enable --now docker containerd >/dev/null

  if id -nG "$opt_user" | tr ' ' '\n' | grep -qx docker; then
    info "$opt_user is already in the docker group"
  else
    usermod -aG docker "$opt_user"
    ok "$opt_user added to the docker group (log out and back in to use docker without sudo)"
  fi
}

# Set KEY=VALUE in an ini-style file, replacing the line (commented or not) that has the key.
# Returns 0 if the file changed.
set_ini_key() {
  local file=$1 key=$2 value=$3 before
  before=$(md5sum "$file")
  if grep -Eq "^#?[[:space:]]*${key}=" "$file"; then
    sed -i -E "0,/^#?[[:space:]]*${key}=.*/s//${key}=${value}/" "$file"
  else
    warn "$key not found in $file: add '$key=$value' by hand"
    return 1
  fi
  [[ $(md5sum "$file") != "$before" ]]
}

# The interfaces that can reach the LAN, comma-separated: the one of the default route first,
# then every physical network card (cable, Wi-Fi, USB-Ethernet adapter: they have a "device" in
# sysfs), so switching from one to another needs no new run. Virtual ones (Docker bridges, veth,
# tailscale0) are left out.
lan_interfaces() {
  local uplink dev list=()
  uplink=$(default_route_field dev)
  [[ -z $uplink ]] || list+=("$uplink")
  for dev in /sys/class/net/*; do
    [[ -e $dev/device && ${dev##*/} != "$uplink" ]] || continue
    list+=("${dev##*/}")
  done
  (IFS=,; printf '%s' "${list[*]}")
}

# Wireless interfaces (wlp2s0, wlan0...), one per line.
wireless_interfaces() {
  local dev
  for dev in /sys/class/net/*; do
    [[ -d $dev/wireless || -e $dev/phy80211 ]] && printf '%s\n' "${dev##*/}"
  done
  return 0
}

wifi_power_save() {
  local ifaces iface uplink
  ifaces=$(wireless_interfaces)
  [[ -n $ifaces ]] || return 0
  step "Wi-Fi: power saving off (it delays packets and makes mDNS miss queries)"
  uplink=$(default_route_field dev)
  if grep -qx "$uplink" <<<"$ifaces"; then
    warn "the server reaches the router over Wi-Fi ($uplink): a cable, or a USB-Ethernet adapter,"
    warn "is faster and more reliable (docs/03b-portatile-come-server.md)"
  fi
  apt_install iw
  # The Debian installer configures Wi-Fi with ifupdown and wpa_supplicant. Its if-up.d hooks
  # run every time an interface comes up, so the setting survives reconnections and reboots.
  if [[ -d /etc/network/if-up.d ]]; then
    write_file /etc/network/if-up.d/homeserver-wifi-powersave 0755 <<'EOF' || true
#!/bin/sh
# Managed by /srv/homeserver/scripts/bootstrap.sh.
# ifupdown runs this after bringing up any interface: turn Wi-Fi power saving off, so that the
# server answers at once and does not miss mDNS queries.
[ -e "/sys/class/net/$IFACE/phy80211" ] || exit 0
/usr/sbin/iw dev "$IFACE" set power_save off || true
EOF
  fi
  if systemctl is-active --quiet NetworkManager; then
    warn "NetworkManager is running: the ifupdown hook does not apply to the connections it manages,"
    warn "see docs/03b-portatile-come-server.md"
  fi
  for iface in $ifaces; do
    if [[ $(cat "/sys/class/net/$iface/operstate" 2>/dev/null) == up ]]; then
      iw dev "$iface" set power_save off || warn "$iface: could not turn power saving off"
      ok "$iface: $(iw dev "$iface" get power_save 2>/dev/null || echo 'power save: unknown')"
    else
      info "$iface: not connected"
    fi
  done
}

configure_avahi() {
  step "mDNS (avahi-daemon): <hostname>.local and the app names"
  local conf=/etc/avahi/avahi-daemon.conf changed=false ifaces
  # IPv4 only: phones and PCs then connect over IPv4, which is what the firewall expects, and
  # never try an IPv6 address the server does not answer on first.
  set_ini_key "$conf" use-ipv6 no && changed=true
  set_ini_key "$conf" publish-aaaa-on-ipv4 no && changed=true
  # Only the network cards: never announce Docker's internal bridge addresses.
  ifaces=$(lan_interfaces)
  if [[ -n $ifaces ]]; then
    set_ini_key "$conf" allow-interfaces "$ifaces" && changed=true
  else
    warn "no network card found: avahi will answer on every interface"
  fi
  systemctl enable avahi-daemon >/dev/null
  if $changed; then
    systemctl restart avahi-daemon
    ok "avahi configured (interfaces ${ifaces:-any}, IPv4 only)"
  else
    systemctl start avahi-daemon
    info "avahi already configured"
  fi

  local host
  host=$(hostname)
  if grep -Eq "^[[:space:]]*${host}([.]local)?[[:space:]]*(#.*)?$" "$REPO_DIR/infra/mdns/aliases"; then
    warn "'$host' is both the hostname and an app alias: rename one of them"
  fi
}

directories() {
  step "Directories: /srv/apps (app stacks), /srv/data (infra data), /etc/homeserver (secrets)"
  install -d -m 0755 -o "$opt_user" -g "$opt_user" /srv/apps
  install -d -m 0755 /srv/data "${DATA_DIRS[@]}"
  install -d -m 0700 /etc/homeserver
  ok "created where missing"
}

install_unit() {
  local name=$1
  write_file "/etc/systemd/system/$name" 0644 <"$REPO_DIR/systemd/$name"
}

mdns_aliases() {
  step "Service that publishes the app names (homeserver-mdns-aliases)"
  local changed=false
  chmod 0755 "$REPO_DIR/scripts/mdns-aliases.sh"
  install_unit homeserver-mdns-aliases.service && changed=true
  systemctl daemon-reload
  systemctl enable homeserver-mdns-aliases.service >/dev/null
  if $changed; then systemctl restart homeserver-mdns-aliases.service; else systemctl start homeserver-mdns-aliases.service; fi
  ok "names: $(sed -e 's/#.*//' "$REPO_DIR/infra/mdns/aliases" | xargs | sed 's/\([^ ]*\)/\1.local/g')"
}

backups() {
  step "Backups (restic): settings and nightly timer"
  if [[ -f /etc/homeserver/backup.env ]]; then
    info "settings present: /etc/homeserver/backup.env"
  else
    install -m 0600 "$REPO_DIR/config/backup.env.example" /etc/homeserver/backup.env
    ok "settings template copied to /etc/homeserver/backup.env"
  fi
  chmod 0755 "$REPO_DIR/scripts/backup.sh"
  install_unit homeserver-backup.service || true
  install_unit homeserver-backup.timer || true
  systemctl daemon-reload
  if systemctl is-enabled --quiet homeserver-backup.timer; then
    info "nightly backup timer enabled"
  else
    info "timer off until the backup disk is set up: docs/06-backup.md"
  fi
}

firewall() {
  step "Firewall (ufw)"
  if ! $opt_firewall; then
    warn "skipped (--no-firewall)"
    return 0
  fi
  local src
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  # SSH from anywhere: key-only logins, and never locked out by an unexpected client address.
  ufw allow 22/tcp comment 'SSH' >/dev/null
  for src in "${LAN_V4[@]}" "${LAN_V6[@]}"; do
    ufw allow from "$src" to any port 80,443 proto tcp comment 'HTTP(S) via Caddy, LAN only' >/dev/null
  done
  for src in "${LAN_V4[@]}"; do
    # mDNS: answers to queries sent straight to this host (multicast is allowed by ufw's
    # before.rules already).
    ufw allow from "$src" to any port 5353 proto udp comment 'mDNS (avahi)' >/dev/null
    # Replies to LAN discovery. A device answers a broadcast or multicast search from its own
    # address, which the connection tracker cannot match with the request (sent to
    # 255.255.255.255 or 239.255.255.250), so the reply would be dropped as a new connection:
    # SSDP (Samsung TVs answer from port 1900) and Midea units (6445, 20086).
    ufw allow proto udp from "$src" port 1900,6445,20086 to any comment 'LAN discovery replies' >/dev/null
  done
  if $opt_tailscale; then
    ufw allow in on tailscale0 comment 'Tailscale' >/dev/null
    ufw allow 41641/udp comment 'Tailscale direct connections' >/dev/null
  fi
  ufw --force enable >/dev/null
  ok "enabled: $(ufw status | grep -c ALLOW) allow rules (see: sudo ufw status verbose)"
}

harden_ssh() {
  step "SSH: key-only logins, no root"
  if ! $opt_ssh_hardening; then
    warn "skipped (--no-ssh-hardening): password logins stay allowed"
    return 0
  fi
  local home keys conf=/etc/ssh/sshd_config.d/10-homeserver.conf
  home=$(getent passwd "$opt_user" | cut -d: -f6)
  keys=$home/.ssh/authorized_keys
  # Only once the user can log in with a key: turning passwords off earlier would lock them out.
  if ! grep -Eq '^[[:space:]]*(ssh-(ed25519|rsa)|ecdsa-sha2-|sk-)' "$keys" 2>/dev/null; then
    warn "no public key in $keys: password logins stay ON for now"
    warn "install your key (docs/03-primo-avvio.md), then run this script again"
    return 0
  fi
  # sshd uses the FIRST value it reads for each setting and Debian's sshd_config includes
  # sshd_config.d/*.conf at the top, so "10-" wins over files added later by other packages.
  if write_file "$conf" 0644 <<'EOF'; then
# Managed by /srv/homeserver/scripts/bootstrap.sh (--no-ssh-hardening to skip).
# Key-only logins, never as root. Recovery: log in at the console and delete this file.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
    if ! sshd -t; then
      rm -f "$conf"
      die "sshd rejected the new settings: they were removed, nothing changed"
    fi
    systemctl reload ssh
    warn "password logins over SSH are now OFF. Do NOT close this session yet: open a new"
    warn "terminal and check that 'ssh $(hostname)' still logs you in with your key"
  fi
  if sshd -T 2>/dev/null | grep -qx 'passwordauthentication no'; then
    ok "sshd: key-only logins"
  else
    warn "sshd still accepts passwords: another setting overrides $conf (check: sudo sshd -T)"
  fi
}

install_tailscale() {
  $opt_tailscale || return 0
  step "Tailscale"
  local codename
  codename=$(debian_codename)
  fetch_key "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" \
    /usr/share/keyrings/tailscale-archive-keyring.gpg
  if [[ ! -s /etc/apt/sources.list.d/tailscale.list ]]; then
    curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.tailscale-keyring.list" \
      -o /etc/apt/sources.list.d/tailscale.list
    apt_get update
  fi
  apt_install tailscale
  systemctl enable --now tailscaled >/dev/null
  if tailscale status >/dev/null 2>&1; then
    info "already connected to the tailnet"
  else
    info "to connect: sudo tailscale up --accept-dns=false (see docs/07-accesso-remoto.md)"
  fi
}

start_infra() {
  step "Infra stack: Caddy, Dockge, Uptime Kuma"
  if ! $opt_infra; then
    warn "skipped (--no-infra): start it with 'make up' in $REPO_DIR"
    return 0
  fi
  docker compose -f "$REPO_DIR/infra/compose.yaml" up -d
  ok "started"
}

summary() {
  local host ip
  host=$(hostname)
  ip=$(default_route_field src)
  step "Done"
  cat <<EOF
    Server:   $host.local  (now at ${ip:-no address})
    Pages:    http://$host.local  http://status.local  http://dockge.local
              Create the admin accounts of Uptime Kuma and Dockge right away.

    Next steps:
      - log out and back in, so that '$opt_user' can use docker without sudo
      - check the names:  cd $REPO_DIR && make aliases
      - apps:             docs/05-app.md
EOF
}

main() {
  parse_args "$@"
  require_root
  check_system
  base_packages
  time_and_locale
  journald_limits
  laptop
  wifi_power_save
  automatic_updates
  install_docker
  configure_avahi
  directories
  mdns_aliases
  backups
  install_tailscale
  firewall
  harden_ssh
  start_infra
  summary
}

main "$@"
