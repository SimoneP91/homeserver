#!/usr/bin/env bash
# Publish extra mDNS names (<name>.local) that all point at this server's CURRENT IPv4 address,
# so every app gets its own name (localclima.local, status.local, ...) without fixed IPs.
#
# avahi-daemon already publishes the machine's own <hostname>.local and follows its address.
# The extra names are published with one `avahi-publish -a -R <name>.local <ip>` per name: that
# record carries a fixed address, so whenever the address of the default route changes (DHCP),
# or the names file changes, every publisher is stopped and started again with the new one.
# A publisher that dies (name collision, avahi-daemon restart) is restarted with a backoff.
#
# Runs in the foreground under systemd (homeserver-mdns-aliases.service); logs go to journald.
# Usage: mdns-aliases.sh [NAMES_FILE]
set -euo pipefail

NAMES_FILE=${1:-${MDNS_ALIASES_FILE:-/srv/homeserver/infra/mdns/aliases}}
CHECK_INTERVAL=${MDNS_CHECK_INTERVAL:-5}   # seconds between two checks of the address
RETRY_MIN=${MDNS_RETRY_MIN:-10}            # first delay before restarting a dead publisher
RETRY_MAX=${MDNS_RETRY_MAX:-600}           # backoff cap (e.g. a name taken by another device)

declare -A pid=()     # name -> PID of its avahi-publish
declare -A since=()   # name -> when it was last started (epoch seconds)
declare -A delay=()   # name -> current restart delay
current_ip=''
current_names=''
current_text=$'\n' # never equal to what $(cat) returns: forces the first parse

log() { printf '%s\n' "$*"; }

# IPv4 source address of the default route, or nothing when the network is down. No packet
# is sent: the kernel only looks up the route.
lan_ipv4() {
  local out
  out=$(ip -4 -o route get 192.0.2.1 2>/dev/null) || return 0
  out=$(awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }' <<<"$out")
  if [[ $out =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then printf '%s\n' "$out"; fi
}

# Valid names in the text on stdin, one per line, sorted: comments and blanks skipped, ".local"
# optional, the machine's own hostname left out (avahi-daemon publishes it already).
# Problems go to stderr.
parse_names() {
  local line name own
  own=$(hostname | tr '[:upper:]' '[:lower:]')
  own=${own%%.*}
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    name=$(tr -d '[:space:]' <<<"$line" | tr '[:upper:]' '[:lower:]')
    name=${name%.local}
    [[ -n $name ]] || continue
    if [[ ! $name =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
      log >&2 "ignoring invalid name '$name' in $NAMES_FILE (one DNS label: letters, digits, '-')"
      continue
    fi
    [[ $name != "$own" ]] || continue
    printf '%s\n' "$name"
  done | sort -u
}

# True while PID runs (a zombie, i.e. exited but not yet reaped, counts as dead).
alive() {
  local state
  state=$(awk '/^State:/ { print $2 }' "/proc/$1/status" 2>/dev/null) || return 1
  [[ -n $state && $state != Z ]]
}

start_one() {
  local name=$1
  avahi-publish -a -R "$name.local" "$current_ip" &
  pid[$name]=$!
  since[$name]=$(date +%s)
  log "publishing $name.local -> $current_ip (pid ${pid[$name]})"
}

stop_all() {
  local name
  for name in "${!pid[@]}"; do
    kill "${pid[$name]}" 2>/dev/null || true
  done
  for name in "${!pid[@]}"; do
    wait "${pid[$name]}" 2>/dev/null || true
  done
  pid=()
  since=()
  delay=()
}

shutdown() {
  log "stopping: withdrawing every alias"
  stop_all
  exit 0
}

main() {
  local ip text names='' name now
  command -v avahi-publish >/dev/null || {
    log "avahi-publish not found: install avahi-utils"
    exit 1
  }
  trap shutdown TERM INT
  log "names file: $NAMES_FILE"

  while true; do
    ip=$(lan_ipv4)
    text=$(cat "$NAMES_FILE" 2>/dev/null || true)
    if [[ $text != "$current_text" ]]; then
      current_text=$text
      names=$(parse_names <<<"$text")
    fi
    now=$(date +%s)

    if [[ $ip != "$current_ip" || $names != "$current_names" ]]; then
      stop_all
      if [[ $ip != "$current_ip" ]]; then
        log "address changed: '${current_ip:-none}' -> '${ip:-none}'"
      fi
      if [[ $names != "$current_names" ]]; then
        log "names: $(tr '\n' ' ' <<<"$names")"
      fi
      current_ip=$ip
      current_names=$names
      if [[ -n $current_ip ]]; then
        for name in $current_names; do
          delay[$name]=$RETRY_MIN
          start_one "$name"
        done
      fi
    else
      for name in "${!pid[@]}"; do
        if alive "${pid[$name]}"; then
          # Alive for a while: the next failure starts again from the shortest delay.
          if ((now - since[$name] > RETRY_MAX)); then delay[$name]=$RETRY_MIN; fi
          continue
        fi
        wait "${pid[$name]}" 2>/dev/null || true # reap it
        if ((now - since[$name] >= delay[$name])); then
          log "publisher of $name.local exited: restarting it"
          start_one "$name"
          delay[$name]=$((delay[$name] * 2 > RETRY_MAX ? RETRY_MAX : delay[$name] * 2))
        fi
      done
    fi

    # Sleep in the background so that SIGTERM is handled at once.
    sleep "$CHECK_INTERVAL" &
    wait $! || true
  done
}

main "$@"
