# shellcheck shell=bash
# Helpers shared by the scripts in scripts/. Source it, do not run it.

# Colours only when writing to a terminal (journald and log files get plain text).
if [[ -t 1 ]]; then
  _bold=$'\e[1m' _green=$'\e[32m' _yellow=$'\e[33m' _red=$'\e[31m' _reset=$'\e[0m'
else
  _bold='' _green='' _yellow='' _red='' _reset=''
fi

step() { printf '\n%s==> %s%s\n' "$_bold" "$*" "$_reset"; }
info() { printf '    %s\n' "$*"; }
ok() { printf '    %sok%s %s\n' "$_green" "$_reset" "$*"; }
warn() { printf '    %swarning:%s %s\n' "$_yellow" "$_reset" "$*" >&2; }
die() {
  printf '%serror:%s %s\n' "$_red" "$_reset" "$*" >&2
  exit 1
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "run it as root: sudo $0 ..."
}

# Write CONTENT (read from stdin) to PATH with MODE, only if it differs from what is there.
# Prints whether the file changed; returns 0 if it was written, 1 if it was already up to date,
# so callers can restart a service only when its configuration changed.
write_file() {
  local path=$1 mode=$2 content
  content=$(cat)
  if [[ -f $path ]] && [[ "$(cat "$path")" == "$content" ]]; then
    chmod "$mode" "$path"
    info "unchanged: $path"
    return 1
  fi
  install -d -m 0755 "$(dirname "$path")"
  printf '%s\n' "$content" >"$path.tmp"
  chmod "$mode" "$path.tmp"
  mv "$path.tmp" "$path"
  ok "written: $path"
  return 0
}

# apt-get without prompts (conffile questions keep the local version).
apt_get() {
  DEBIAN_FRONTEND=noninteractive apt-get -y \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

# Install the given packages if any of them is missing (with their recommended packages,
# unless the first argument is --no-recommends).
apt_install() {
  local missing=() pkg extra=()
  if [[ ${1:-} == --no-recommends ]]; then
    extra=(--no-install-recommends)
    shift
  fi
  for pkg in "$@"; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' || missing+=("$pkg")
  done
  if ((${#missing[@]} == 0)); then
    info "already installed: $*"
    return 0
  fi
  apt_get install "${extra[@]}" "${missing[@]}"
  ok "installed: ${missing[*]}"
}

# Download an apt signing key to DEST (a bare name means /etc/apt/keyrings/NAME) unless it is
# already there. Keys ending in .asc are stored armored; armored keys saved under any other
# name are dearmored to binary, binary keys are stored as they are.
fetch_key() {
  local url=$1 dest=$2 tmp
  [[ $dest == /* ]] || dest=/etc/apt/keyrings/$dest
  install -d -m 0755 "$(dirname "$dest")"
  if [[ -s $dest ]]; then
    info "key present: $dest"
    return 0
  fi
  tmp=$(mktemp)
  curl -fsSL "$url" -o "$tmp"
  if [[ $dest == *.asc ]] || ! grep -q -- '-----BEGIN PGP' "$tmp"; then
    install -m 0644 "$tmp" "$dest"
  else
    gpg --dearmor <"$tmp" >"$dest"
    chmod 0644 "$dest"
  fi
  rm -f "$tmp"
  ok "key saved: $dest"
}

# Codename of the running Debian release (trixie on Debian 13).
debian_codename() {
  # shellcheck source=/dev/null
  (. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")
}

# IPv4 source address and interface of the default route (empty when offline).
default_route_field() {
  local field=$1 out
  out=$(ip -4 -o route get 192.0.2.1 2>/dev/null) || return 0
  # Output looks like: "192.0.2.1 via 192.168.1.1 dev enp1s0 src 192.168.1.20 uid 0 \ cache"
  awk -v f="$field" '{ for (i = 1; i < NF; i++) if ($i == f) { print $(i + 1); exit } }' <<<"$out"
}

# The laptop batteries of this machine (/sys/class/power_supply/BAT*), one sysfs path per line;
# nothing on a desktop. Batteries of devices (a wireless mouse: scope "Device") do not count.
system_batteries() {
  local dev
  for dev in /sys/class/power_supply/BAT*; do
    [[ -r $dev/type && $(<"$dev/type") == Battery ]] || continue
    if [[ -r $dev/scope && $(<"$dev/scope") == Device ]]; then continue; fi
    printf '%s\n' "$dev"
  done
}

# Run a command as USER with a login-like environment (HOME, PATH from their profile).
as_user() {
  local user=$1
  shift
  sudo -u "$user" -H -- "$@"
}
