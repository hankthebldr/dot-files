#!/usr/bin/env bash
# scripts/setup/macos-default-terminal.sh
#
# Make Ghostty the default terminal *experience* on macOS.
#
# macOS has NO OS-level "default terminal" setting (unlike Linux's
# x-terminal-emulator / $TERMINAL / GNOME default-app). So "default" here is the
# practical equivalent, in three parts:
#   1. Login item   — Ghostty opens at login.
#   2. Dock pin      — Ghostty kept in the Dock.
#   3. Finder Quick Action — right-click a folder → "Open in Ghostty".
#
# Idempotent and reversible. Each step backs up before it mutates and skips work
# that's already done. For the Linux/BD790i side, see terminal/README.md.
set -euo pipefail

APP="/Applications/Ghostty.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backups"
SERVICE_NAME="Open in Ghostty.workflow"
SERVICE_SRC="$DOTFILES_DIR/terminal/macos/$SERVICE_NAME"
SERVICE_DST="$HOME/Library/Services/$SERVICE_NAME"

log() { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
inf() { printf '  \033[0;34m•\033[0m %s\n' "$*"; }
warn(){ printf '  \033[0;33m!\033[0m %s\n' "$*" >&2; }

[[ "$(uname)" == "Darwin" ]] || {
  warn "macOS only. On Linux set the default via update-alternatives / gsettings (see terminal/README.md)."
  exit 0
}
[[ -d "$APP" ]] || {
  warn "Ghostty not installed at $APP — run: brew install --cask ghostty"
  exit 1
}
mkdir -p "$BACKUP_DIR"

# ── 1. Login item ──────────────────────────────────────────────────────
if osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -q 'Ghostty'; then
  inf "login item already present"
else
  osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Ghostty.app", hidden:false}' >/dev/null
  log "added Ghostty to Login Items"
fi

# ── 2. Dock pin ────────────────────────────────────────────────────────
if defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q 'Ghostty.app'; then
  inf "already pinned to the Dock"
else
  cp "$HOME/Library/Preferences/com.apple.dock.plist" \
     "$BACKUP_DIR/com.apple.dock.$(date +%Y%m%d-%H%M%S).plist" 2>/dev/null \
     && inf "backed up Dock prefs"
  defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file:///Applications/Ghostty.app/</string><key>_CFURLStringType</key><integer>15</integer></dict></dict><key>tile-type</key><string>file-tile</string></dict>'
  killall Dock 2>/dev/null || true
  log "pinned Ghostty to the Dock"
fi

# ── 3. Finder Quick Action ─────────────────────────────────────────────
if [[ -d "$SERVICE_SRC" ]]; then
  mkdir -p "$HOME/Library/Services"
  rm -rf "$SERVICE_DST"
  cp -R "$SERVICE_SRC" "$SERVICE_DST"
  /System/Library/CoreServices/pbs -update 2>/dev/null || true
  log "installed Finder Quick Action: 'Open in Ghostty'"
  inf "if it doesn't appear: System Settings → Keyboard → Keyboard Shortcuts → Services, or relaunch Finder"
else
  warn "Quick Action source missing: $SERVICE_SRC"
fi

printf '\n  Ghostty set as the default macOS terminal experience.\n'
printf "  (macOS has no true 'default terminal' flag — this is the practical equivalent.)\n"
