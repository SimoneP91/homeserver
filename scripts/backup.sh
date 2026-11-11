#!/usr/bin/env bash
# Backups with restic: /srv (this repository, the apps and their secrets, infra data),
# /etc/homeserver and /home, to a USB disk and optionally to an off-site repository.
#
#   sudo /srv/homeserver/scripts/backup.sh <command>
#
# Commands:
#   init                 create the password file (if missing) and the repositories
#   run                  back up now: what homeserver-backup.timer runs every night
#   snapshots            list the snapshots of the main repository
#   test-restore [PATH]  restore PATH (default /srv/homeserver) from the latest snapshot into a
#                        temporary directory and compare it with the live files
#   restic ARGS...       run restic on the main repository, e.g. `restic mount /mnt/restore`
#   restic-offsite ARGS  the same on the off-site repository
#
# Settings: /etc/homeserver/backup.env (template: config/backup.env.example).
# See docs/06-backup.md.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/common.sh
source "$REPO_DIR/scripts/lib/common.sh"

CONFIG=${BACKUP_CONFIG:-/etc/homeserver/backup.env}
SQLITE_DIR=/var/backups/homeserver-sqlite

usage() {
  sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"
}

load_config() {
  [[ -r $CONFIG ]] || die "missing $CONFIG: run bootstrap.sh, or copy config/backup.env.example there"
  # shellcheck source=/dev/null
  source "$CONFIG"
  : "${RESTIC_REPOSITORY:?is not set in $CONFIG}"
  : "${RESTIC_PASSWORD_FILE:?is not set in $CONFIG}"
  BACKUP_MOUNT=${BACKUP_MOUNT:-}
  BACKUP_PATHS=${BACKUP_PATHS:-/srv /etc/homeserver /home}
  BACKUP_EXCLUDES_FILE=${BACKUP_EXCLUDES_FILE:-$REPO_DIR/config/backup-excludes.txt}
  BACKUP_SQLITE=${BACKUP_SQLITE:-}
  BACKUP_KEEP=${BACKUP_KEEP:---keep-daily 7 --keep-weekly 4 --keep-monthly 12}
  BACKUP_PUSH_URL=${BACKUP_PUSH_URL:-}
  OFFSITE_REPOSITORY=${OFFSITE_REPOSITORY:-}
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
  command -v restic >/dev/null || die "restic is not installed (sudo apt install restic)"
}

require_password() {
  [[ -s $RESTIC_PASSWORD_FILE ]] || die "missing $RESTIC_PASSWORD_FILE: run '$0 init' first"
}

# The USB disk must really be mounted: otherwise the repository path is a plain directory on
# the system SSD. Try the fstab entry once before giving up.
require_mount() {
  [[ -n $BACKUP_MOUNT ]] || return 0
  mountpoint -q "$BACKUP_MOUNT" && return 0
  mount "$BACKUP_MOUNT" 2>/dev/null || true
  mountpoint -q "$BACKUP_MOUNT" || die "$BACKUP_MOUNT is not mounted: is the backup disk plugged in?"
}

# restic on one repository (empty = the main one).
restic_on() {
  local repo=$1
  shift
  if [[ -n $repo ]]; then restic -r "$repo" "$@"; else restic "$@"; fi
}

cmd_init() {
  load_config
  if [[ -s $RESTIC_PASSWORD_FILE ]]; then
    info "password file present: $RESTIC_PASSWORD_FILE"
  else
    install -d -m 0700 "$(dirname "$RESTIC_PASSWORD_FILE")"
    (umask 077 && head -c 32 /dev/urandom | base64 >"$RESTIC_PASSWORD_FILE")
    ok "new password in $RESTIC_PASSWORD_FILE"
    warn "copy it to your password manager NOW (sudo cat $RESTIC_PASSWORD_FILE): without it the backups are unreadable"
  fi
  require_mount
  local repo
  for repo in "$RESTIC_REPOSITORY" "$OFFSITE_REPOSITORY"; do
    [[ -n $repo ]] || continue
    if restic -r "$repo" cat config >/dev/null 2>&1; then
      info "repository already initialised: $repo"
    else
      restic -r "$repo" init
      ok "repository created: $repo"
    fi
  done
}

# Consistent copies of live SQLite databases, made with SQLite's online backup API.
dump_sqlite() {
  local db dest
  install -d -m 0700 "$SQLITE_DIR"
  for db in $BACKUP_SQLITE; do
    if [[ ! -f $db ]]; then
      warn "SQLite database not found, skipped: $db"
      continue
    fi
    dest=$SQLITE_DIR/$(tr '/' '_' <<<"${db#/}")
    sqlite3 -cmd '.timeout 10000' "$db" ".backup '$dest.tmp'"
    mv "$dest.tmp" "$dest"
    info "SQLite copy: $db -> $dest"
  done
}

# One full cycle on one repository: backup, retention, quick integrity check. Each step is
# checked explicitly: callers run this in an `if`, where `set -e` does not apply.
backup_to() {
  local repo=$1 label=$2 paths keep
  read -r -a paths <<<"$BACKUP_PATHS"
  read -r -a keep <<<"$BACKUP_KEEP"
  [[ -d $SQLITE_DIR ]] && paths+=("$SQLITE_DIR")
  step "Backup to the $label repository"
  restic_on "$repo" backup --one-file-system --exclude-caches \
    --exclude-file "$BACKUP_EXCLUDES_FILE" --tag homeserver "${paths[@]}" || return 1
  step "Retention on the $label repository"
  restic_on "$repo" forget --tag homeserver --prune "${keep[@]}" || return 1
  step "Integrity check of the $label repository"
  restic_on "$repo" check || return 1
}

cmd_run() {
  load_config
  require_password
  local failed=()
  dump_sqlite || warn "could not copy every SQLite database: backing up anyway"

  if (require_mount && backup_to "" main); then
    ok "main repository done"
  else
    failed+=(main)
  fi
  if [[ -n $OFFSITE_REPOSITORY ]]; then
    if backup_to "$OFFSITE_REPOSITORY" off-site; then ok "off-site repository done"; else failed+=(off-site); fi
  fi

  if ((${#failed[@]})); then
    die "backup FAILED for: ${failed[*]} (details above, or: journalctl -u homeserver-backup)"
  fi
  if [[ -n $BACKUP_PUSH_URL ]]; then
    curl -fsS -m 15 -o /dev/null "$BACKUP_PUSH_URL" || warn "could not notify Uptime Kuma"
  fi
  ok "backup completed"
}

cmd_test_restore() {
  load_config
  require_password
  require_mount
  local path=${1:-/srv/homeserver} target count
  target=$(mktemp -d /var/tmp/restore-test.XXXXXX)
  # shellcheck disable=SC2064 # expand now: the path is fixed
  trap "rm -rf '$target'" EXIT
  step "Restoring $path from the latest snapshot into $target"
  restic restore latest --target "$target" --include "$path"
  [[ -e $target$path ]] || die "nothing restored: is $path part of BACKUP_PATHS?"
  count=$(find "$target$path" -type f | wc -l)
  ((count > 0)) || die "the restored copy of $path has no files"
  ok "$count files restored"
  step "Differences from the live files (changes made after the snapshot are expected)"
  if diff -rq "$target$path" "$path"; then ok "identical to the live copy"; fi
  ok "test restore succeeded (the temporary copy is deleted now)"
}

main() {
  local cmd=${1:-}
  (($#)) && shift
  case $cmd in
    init) require_root; cmd_init ;;
    run) require_root; cmd_run ;;
    snapshots) require_root; load_config; require_mount; restic snapshots ;;
    test-restore) require_root; cmd_test_restore "$@" ;;
    restic) require_root; load_config; require_mount; restic "$@" ;;
    restic-offsite)
      require_root
      load_config
      [[ -n $OFFSITE_REPOSITORY ]] || die "OFFSITE_REPOSITORY is not set in $CONFIG"
      restic -r "$OFFSITE_REPOSITORY" "$@"
      ;;
    -h | --help | help | '') usage ;;
    *) die "unknown command: $cmd (see --help)" ;;
  esac
}

main "$@"
