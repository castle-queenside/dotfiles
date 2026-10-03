#!/usr/bin/env bash
# bootstrap.sh — turn a fresh Linux box into chris's agent rig
# Usage:   curl -fsSL https://raw.githubusercontent.com/castle-queenside/dotfiles/main/bootstrap.sh | sh
# Or:      ./bootstrap.sh
#
# Idempotent. Re-run any time. Never destructive.

set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────
GITHUB_USER="castle-queenside"
GIT_NAME="Chris"
GIT_EMAIL="271900091+castle-queenside@users.noreply.github.com"
HERDR_LABEL_MAC="mac-studio"
MAC_TAILSCALE_IP="100.86.142.107"   # update if the Mac's Tailscale IP changes

# ─── Logging ──────────────────────────────────────────────────────────────
say()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✘\033[0m %s\n' "$*" >&2; exit 1; }

# ─── Distro detection ─────────────────────────────────────────────────────
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  DISTRO="$ID"
else
  die "Can't detect distro (no /etc/os-release)"
fi
say "Distro: $DISTRO"

# ─── PATH prime ───────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

# ─── 1. Homebrew (if missing) ─────────────────────────────────────────────
if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # brew drops its path config in these for the current user
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
  ok "Homebrew installed"
else
  ok "Homebrew already installed"
fi

# ─── 2. Git ───────────────────────────────────────────────────────────────
say "Configuring git..."
git config --global user.name  "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global push.autoSetupRemote true
git config --global core.autocrlf input
git config --global rerere.enabled true
git config --global help.autocorrect 5
ok "git configured (commits as $GIT_NAME <$GIT_EMAIL>)"

# ─── 3. SSH key (for talking to the Mac Studio) ───────────────────────────
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [[ ! -f ~/.ssh/mac-studio ]]; then
  say "Generating SSH key for the Mac Studio..."
  ssh-keygen -t ed25519 -C "$GIT_NAME@$HOSTNAME" -f ~/.ssh/mac-studio -N ""
  cat ~/.ssh/mac-studio.pub
  warn ""
  warn "PASTE the public key above to the Mac Studio:"
  warn "  ssh chris@$MAC_TAILSCALE_IP 'echo \"\$SSH_KEY\" >> ~/.ssh/authorized_keys'"
  warn "Or: send it to chris (me) and I'll add it."
  warn ""
  read -rp "Press Enter once the key is in the Mac's authorized_keys..."
else
  ok "SSH key ~/.ssh/mac-studio already exists"
fi
chmod 600 ~/.ssh/mac-studio
# accept the Mac's host key automatically on first connect
ssh-keyscan -t ed25519 "$MAC_TAILSCALE_IP" >> ~/.ssh/known_hosts 2>/dev/null || true
ok "SSH ready (target: chris@$MAC_TAILSCALE_IP)"

# ─── 4. Tailscale (if missing) ────────────────────────────────────────────
if ! command -v tailscale >/dev/null 2>&1; then
  say "Installing Tailscale..."
  case "$DISTRO" in
    arch|omarchy|manjaro)
      sudo pacman -S --noconfirm tailscale || warn "pacman install failed; install manually"
      ;;
    ubuntu|debian|pop)
      curl -fsSL https://tailscale.com/install.sh | sh
      ;;
    fedora|rhel|centos)
      sudo dnf install -y tailscale || warn "dnf install failed; install manually"
      ;;
    *)
      warn "Unknown distro — install Tailscale manually: https://tailscale.com/download/linux"
      ;;
  esac
  if command -v tailscale >/dev/null 2>&1; then
    sudo tailscale up
    ok "Tailscale installed and authenticated"
  fi
else
  ok "Tailscale already installed"
fi

# ─── 5. herdr (the multiplexer) ──────────────────────────────────────────
if [[ ! -x $HOME/.local/bin/herdr ]]; then
  say "Installing herdr..."
  curl -fsSL https://herdr.dev/install.sh | sh
  ok "herdr installed"
else
  ok "herdr already installed"
fi
export PATH="$HOME/.local/bin:$PATH"

# ─── 6. Pi (the agent) ───────────────────────────────────────────────────
if ! command -v pi >/dev/null 2>&1; then
  say "Installing Pi..."
  if command -v npm >/dev/null 2>&1; then
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
    ok "Pi installed"
  else
    warn "npm not found — install Node.js first, then: npm i -g @earendil-works/pi-coding-agent"
  fi
else
  ok "Pi already installed"
fi

# ─── 7. herdr ↔ Pi integration ───────────────────────────────────────────
if [[ -x $HOME/.local/bin/herdr ]]; then
  herdr integration install pi 2>/dev/null || true
  ok "herdr↔Pi integration installed"
fi

# ─── 8. Add the Mac as a herdr remote ────────────────────────────────────
if ! herdr machine list 2>/dev/null | grep -q "$HERDR_LABEL_MAC"; then
  say "Adding Mac Studio as a herdr remote (label: $HERDR_LABEL_MAC)..."
  herdr machine add --label "$HERDR_LABEL_MAC" "chris@$MAC_TAILSCALE_IP" || \
    warn "herdr machine add failed — you can run it manually: herdr machine add --label $HERDR_LABEL_MAC chris@$MAC_TAILSCALE_IP"
else
  ok "Mac Studio already saved in herdr"
fi

# ─── 9. Obsidian (optional, only on the Mac usually) ─────────────────────
# Obsidian on Linux: AppImage from obsidian.md. Skip if you only use the Mac's vault.

# ─── 10. Useful aliases ──────────────────────────────────────────────────
SHELL_RC="$HOME/.bashrc"
[[ "$SHELL" == */zsh ]] && SHELL_RC="$HOME/.zshrc"
if [[ -f $SHELL_RC ]] && ! grep -q "dotfiles aliases" "$SHELL_RC"; then
  cat >> "$SHELL_RC" <<'ALIASES'

# ─── dotfiles aliases ───────────────────────────────────────────────
alias mac='ssh -i ~/.ssh/mac-studio chris@100.86.142.107'
alias herd-mac='herdr --machine mac-studio'
alias pi-mac='ssh -i ~/.ssh/mac-studio -t chris@100.86.142.107 pi'
ALIASES
  ok "Aliases added to $SHELL_RC"
fi

# ─── Done ────────────────────────────────────────────────────────────────
cat <<'DONE'

─────────────────────────────────────────────────────────────
✔  bootstrap complete

Quick checks:
  ssh -i ~/.ssh/mac-studio chris@100.86.142.107 'echo hi from mac'
  herdr machine list
  herdr --machine mac-studio
  pi

Common gotchas:
  • herdr machine add: if it asks about installing on the Mac, decline
    (it's already installed there).
  • If herdr attach fails, run: herdr machine status mac-studio
─────────────────────────────────────────────────────────────
DONE
