#!/usr/bin/env bash
# Development toolchain, to work on the server over SSH and VS Code Remote-SSH. Optional and
# separate from bootstrap.sh (a pure server does not need it). Idempotent: run it again at will.
#
#   sudo bash /srv/homeserver/scripts/dev-tools.sh [options]
#
# Installs: build-essential, make, git, tmux, jq, ripgrep, shellcheck, yamllint (Debian);
# GitHub CLI (gh, its official apt repository); Node.js LTS (NodeSource apt repository);
# uv (official installer, for the user); optionally Claude Code (official installer, for the user).
#
# Options:
#   --user NAME          account that develops (default: the one running sudo)
#   --git-name "NAME"    git user.name   (asked if missing and a terminal is attached)
#   --git-email EMAIL    git user.email  (same)
#   --node-major N       Node.js major version (default: 24, what LocalClima uses)
#   --claude             also install Claude Code
#   -h, --help           show this help
#
# See docs/10-sviluppo-remoto.md.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/common.sh
source "$REPO_DIR/scripts/lib/common.sh"

opt_user=${SUDO_USER:-}
opt_git_name=''
opt_git_email=''
opt_node_major=24
opt_claude=false
user_home=''

usage() {
  sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"
}

parse_args() {
  while (($#)); do
    case $1 in
      --user) opt_user=${2:?--user needs a name}; shift ;;
      --git-name) opt_git_name=${2:?--git-name needs a value}; shift ;;
      --git-email) opt_git_email=${2:?--git-email needs a value}; shift ;;
      --node-major) opt_node_major=${2:?--node-major needs a number}; shift ;;
      --claude) opt_claude=true ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  [[ $opt_node_major =~ ^[0-9]+$ ]] || die "--node-major wants a number, e.g. 24"
}

check_user() {
  [[ -n $opt_user && $opt_user != root ]] || die "run with sudo from your account, or pass --user NAME"
  id "$opt_user" >/dev/null 2>&1 || die "user '$opt_user' does not exist"
  user_home=$(getent passwd "$opt_user" | cut -d: -f6)
}

debian_tools() {
  step "Build tools and utilities (Debian)"
  apt_get update
  apt_install build-essential make git tmux curl ca-certificates gnupg jq ripgrep unzip \
    shellcheck yamllint
}

github_cli() {
  step "GitHub CLI (gh), official apt repository"
  fetch_key https://cli.github.com/packages/githubcli-archive-keyring.gpg githubcli-archive-keyring.gpg
  if write_file /etc/apt/sources.list.d/github-cli.list 0644 <<EOF; then
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main
EOF
    apt_get update
    # Replaces Debian's older gh, if it was installed to clone the repositories at first.
    apt_get install gh
  else
    apt_install gh
  fi
}

# One system-wide Node.js from NodeSource: updated by apt with the rest of the system, the same
# for the shell, VS Code tasks and `make`, with no version manager to load in each shell.
install_nodejs() {
  step "Node.js ${opt_node_major}.x (NodeSource apt repository)"
  local changed=false
  fetch_key https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key nodesource.gpg
  write_file /etc/apt/sources.list.d/nodesource.sources 0644 <<EOF && changed=true
Types: deb
URIs: https://deb.nodesource.com/node_${opt_node_major}.x/
Suites: nodistro
Components: main
Signed-By: /etc/apt/keyrings/nodesource.gpg
EOF
  # Prefer NodeSource's nodejs over Debian's older one.
  write_file /etc/apt/preferences.d/nodesource 0644 <<'EOF' || true
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 600
EOF
  if $changed || ! command -v node >/dev/null; then
    apt_get update
    apt_get install nodejs
  fi
  local major
  major=$(node --version | sed -E 's/^v([0-9]+).*/\1/')
  [[ $major == "$opt_node_major" ]] || warn "node is v$major, expected $opt_node_major: check 'apt policy nodejs'"
  ok "node $(node --version), npm $(npm --version)"
}

uv_tool() {
  step "uv (Python projects and Python versions), for $opt_user"
  if [[ -x $user_home/.local/bin/uv ]]; then
    info "already installed: $(as_user "$opt_user" "$user_home/.local/bin/uv" --version)"
    return 0
  fi
  as_user "$opt_user" sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
  ok "installed in $user_home/.local/bin (on the PATH from the next login)"
}

claude_code() {
  $opt_claude || return 0
  step "Claude Code, for $opt_user"
  if [[ -x $user_home/.local/bin/claude ]]; then
    info "already installed (it updates itself)"
    return 0
  fi
  as_user "$opt_user" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
  ok "installed: run 'claude' in a project and log in"
}

git_identity() {
  step "git settings for $opt_user"
  local key value prompt
  for key in user.name user.email; do
    value=$(as_user "$opt_user" git config --global --get "$key" || true)
    if [[ $key == user.name ]]; then prompt='Name for git commits'; else prompt='Email for git commits'; fi
    if [[ $key == user.name && -n $opt_git_name ]]; then value=$opt_git_name; fi
    if [[ $key == user.email && -n $opt_git_email ]]; then value=$opt_git_email; fi
    if [[ -z $value && -t 0 ]]; then
      read -r -p "    $prompt: " value
    fi
    if [[ -z $value ]]; then
      warn "$key not set: git config --global $key '...'"
      continue
    fi
    as_user "$opt_user" git config --global "$key" "$value"
    ok "$key = $value"
  done
  # Sensible defaults, only where the user has not chosen already.
  for key in init.defaultBranch pull.ff; do
    if ! as_user "$opt_user" git config --global --get "$key" >/dev/null; then
      if [[ $key == init.defaultBranch ]]; then value=main; else value=only; fi
      as_user "$opt_user" git config --global "$key" "$value"
      ok "$key = $value"
    fi
  done
}

summary() {
  step "Done"
  cat <<EOF
    Next steps, as $opt_user (log out and back in first, for the PATH):
      gh auth login && gh auth setup-git     # GitHub over HTTPS for git push/pull
      mkdir -p ~/dev && cd ~/dev && gh repo clone <you>/localclima
      cd localclima && make install && make dev
    VS Code Remote-SSH, ports and tmux: docs/10-sviluppo-remoto.md
EOF
}

main() {
  parse_args "$@"
  require_root
  check_user
  debian_tools
  github_cli
  install_nodejs
  uv_tool
  claude_code
  git_identity
  summary
}

main "$@"
