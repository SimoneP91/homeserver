#!/usr/bin/env bash
# Limit the charge of a laptop battery that stays on AC power day and night: charging stops at
# END percent and starts again below START, so the battery does not sit at 100% (which wears it
# out faster). Only where the firmware lets Linux do it:
#
#   - charge_control_start/end_threshold in /sys/class/power_supply/BAT*/, the kernel's standard
#     interface, offered by some vendor drivers (for example thinkpad_acpi; asus-wmi has only the
#     end threshold). Drivers round to the values the hardware supports.
#   - otherwise charge_types "Long_Life", for hardware with a single fixed limit.
#
# Many firmwares forget the setting at power off: homeserver-battery-limit.service runs this at
# every boot. Logs go to journald.
#
# Usage: battery-limit.sh [START END]   apply (default: 75 80)
#        battery-limit.sh --check       print what each battery supports and its current limit;
#                                       exit 1 if no battery can be limited
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/common.sh
source "$REPO_DIR/scripts/lib/common.sh"

WAIT_SECONDS=30 # at boot, the vendor driver that adds the attributes may load a bit later

# How BAT (a sysfs path) can be limited: "thresholds", "long-life" or nothing.
limit_kind() {
  local bat=$1
  if [[ -f $bat/charge_control_end_threshold ]]; then
    echo thresholds
  elif [[ -f $bat/charge_types ]] && grep -qw Long_Life "$bat/charge_types"; then
    echo long-life
  fi
}

describe() {
  local bat=$1 name=${1##*/}
  case $(limit_kind "$bat") in
    thresholds)
      if [[ -f $bat/charge_control_start_threshold ]]; then
        echo "$name: charging stops at $(<"$bat/charge_control_end_threshold")%," \
          "starts again below $(<"$bat/charge_control_start_threshold")%"
      else
        echo "$name: charging stops at $(<"$bat/charge_control_end_threshold")%"
      fi
      ;;
    long-life) echo "$name: charge type $(<"$bat/charge_types")" ;;
    *) echo "$name: the firmware offers no charge limit to Linux" ;;
  esac
}

put() {
  local file=$1 value=$2
  if ! printf '%s\n' "$value" 2>/dev/null >"$file"; then
    echo "${file#/sys/class/power_supply/}: the driver refused '$value'" >&2
    return 1
  fi
}

apply_thresholds() {
  local bat=$1 start=$2 end=$3 start_file end_file
  start_file=$bat/charge_control_start_threshold
  end_file=$bat/charge_control_end_threshold
  if [[ ! -f $start_file ]]; then
    put "$end_file" "$end"
    return
  fi
  # Drivers may refuse a start threshold above the end one: write in the order that keeps
  # start < end at every step.
  if ((start < $(<"$end_file"))); then
    put "$start_file" "$start" && put "$end_file" "$end"
  else
    put "$end_file" "$end" && put "$start_file" "$start"
  fi
}

check() {
  local bat found=false supported=false
  while IFS= read -r bat; do
    found=true
    describe "$bat"
    [[ -z $(limit_kind "$bat") ]] || supported=true
  done < <(system_batteries)
  $found || echo "no battery found"
  $supported
}

apply() {
  local start=$1 end=$2 bat batteries=() waited=0 failed=false limited=false
  if [[ ! $start =~ ^[0-9]+$ || ! $end =~ ^[0-9]+$ ]] || ((start >= end || end > 100)); then
    die "want START < END <= 100, got '$start' '$end'"
  fi

  while true; do
    mapfile -t batteries < <(system_batteries)
    for bat in "${batteries[@]}"; do
      [[ -z $(limit_kind "$bat") ]] || limited=true
    done
    if $limited || ((waited >= WAIT_SECONDS)); then break; fi
    sleep 1
    waited=$((waited + 1))
  done
  ((${#batteries[@]})) || die "no battery found"
  $limited || die "no battery offers a charge limit (waited ${WAIT_SECONDS}s for the driver)"

  for bat in "${batteries[@]}"; do
    case $(limit_kind "$bat") in
      thresholds) apply_thresholds "$bat" "$start" "$end" || failed=true ;;
      long-life) put "$bat/charge_types" Long_Life || failed=true ;;
    esac
    describe "$bat"
  done
  ! $failed
}

main() {
  if [[ ${1:-} == --check ]]; then
    check
  else
    require_root
    apply "${1:-75}" "${2:-80}"
  fi
}

main "$@"
