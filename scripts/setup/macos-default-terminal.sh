#!/usr/bin/env bash
# scripts/setup/macos-default-terminal.sh
#
# Make a chosen terminal the default terminal *experience* on macOS.
#
# macOS has NO OS-level "default terminal" setting (unlike Linux's
# x-terminal-emulator / $TERMINAL / GNOME default-app). So "default" here is the
# practical equivalent, in three parts:
#   1. Login item          — the app opens at login.
#   2. Dock pin            — the app is kept in the Dock.
#   3. Finder Quick Action — right-click a folder → "Open in <App>".
#
# Both Terminal.app and Ghostty stay fully functional and installable; --target
# only decides which one gets the three "primary" affordances above. Terminal.app
# is the default target (the daily driver); Ghostty remains a first-class peer.
#
# Usage:
#   macos-default-terminal.sh                      # target terminal (default)
#   macos-default-terminal.sh --target ghostty
#   macos-default-terminal.sh --target terminal --dry-run
#
# Idempotent and reversible. Each step backs up before it mutates and skips work
# that's already done. For the Linux/BD790i side, see terminal/README.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backups"

TARGET="terminal"
DRY_RUN=0

log() { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
inf() { printf '  \033[0;34m•\033[0m %s\n' "$*"; }
warn(){ printf '  \033[0;33m!\033[0m %s\n' "$*" >&2; }
# run() takes a command as a single string so --dry-run can echo it verbatim.
# shellcheck disable=SC2294  # eval-as-string is the point: we print or run the same text.
run() { if (( DRY_RUN )); then printf '  \033[0;35m→\033[0m would: %s\n' "$*"; else eval "$@"; fi; }

usage() {
  cat <<'EOF'
usage: macos-default-terminal.sh [--target terminal|ghostty] [--dry-run]

  --target   which terminal gets the login item, Dock pin, and Quick Action.
             terminal = Apple Terminal.app (default) · ghostty = Ghostty.app
  --dry-run  print what would change; mutate nothing.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --target=*) TARGET="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn "unknown argument: $1"; usage; exit 2 ;;
  esac
done

# ── Target registry ────────────────────────────────────────────────────
# Adding a terminal = one case arm here + a matching terminal/macos/*.workflow.
case "$TARGET" in
  terminal|Terminal|terminal.app|Terminal.app)
    TARGET="terminal"
    APP_NAME="Terminal"
    APP="/System/Applications/Utilities/Terminal.app"
    # Pre-Catalina fallback; harmless on modern macOS.
    [[ -d "$APP" ]] || APP="/Applications/Utilities/Terminal.app"
    INSTALL_HINT="Terminal.app ships with macOS — if it is missing, something is very wrong."
    ;;
  ghostty|Ghostty|ghostty.app|Ghostty.app)
    TARGET="ghostty"
    APP_NAME="Ghostty"
    APP="/Applications/Ghostty.app"
    INSTALL_HINT="run: brew install --cask ghostty"
    ;;
  *)
    warn "unknown --target '$TARGET' (expected: terminal | ghostty)"; usage; exit 2 ;;
esac

SERVICE_NAME="Open in ${APP_NAME}.workflow"
SERVICE_SRC="$DOTFILES_DIR/terminal/macos/$SERVICE_NAME"
SERVICE_DST="$HOME/Library/Services/$SERVICE_NAME"

[[ "$(uname)" == "Darwin" ]] || {
  warn "macOS only. On Linux set the default via update-alternatives / gsettings (see terminal/README.md)."
  exit 0
}
[[ -d "$APP" ]] || {
  warn "$APP_NAME not installed at $APP — $INSTALL_HINT"
  exit 1
}
(( DRY_RUN )) || mkdir -p "$BACKUP_DIR"

printf '\n  Target: \033[1m%s\033[0m  (%s)\n\n' "$APP_NAME" "$APP"

# ── 1. Login item ──────────────────────────────────────────────────────
if osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -q "$APP_NAME"; then
  inf "login item already present"
else
  run "osascript -e 'tell application \"System Events\" to make login item at end with properties {path:\"$APP\", hidden:false}' >/dev/null"
  log "added $APP_NAME to Login Items"
fi

# ── 2. Dock pin ────────────────────────────────────────────────────────
if defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "$(basename "$APP")"; then
  inf "already pinned to the Dock"
else
  if (( DRY_RUN )); then
    inf "would back up Dock prefs to $BACKUP_DIR"
  else
    cp "$HOME/Library/Preferences/com.apple.dock.plist" \
       "$BACKUP_DIR/com.apple.dock.$(date +%Y%m%d-%H%M%S).plist" 2>/dev/null \
       && inf "backed up Dock prefs"
  fi
  run "defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file://${APP}/</string><key>_CFURLStringType</key><integer>15</integer></dict></dict><key>tile-type</key><string>file-tile</string></dict>'"
  run "killall Dock 2>/dev/null || true"
  log "pinned $APP_NAME to the Dock"
fi

# ── 3. Finder Quick Action ─────────────────────────────────────────────
# Both workflows may be installed at once — they are separate Services entries,
# so the Finder context menu can offer "Open in Terminal" AND "Open in Ghostty".
# Only the --target one is installed by this run.
if [[ -d "$SERVICE_SRC" ]]; then
  run "mkdir -p '$HOME/Library/Services'"
  run "rm -rf '$SERVICE_DST'"
  run "cp -R '$SERVICE_SRC' '$SERVICE_DST'"
  run "/System/Library/CoreServices/pbs -update 2>/dev/null || true"
  log "installed Finder Quick Action: 'Open in $APP_NAME'"
  inf "if it doesn't appear: System Settings → Keyboard → Keyboard Shortcuts → Services, or relaunch Finder"
else
  warn "Quick Action source missing: $SERVICE_SRC"
fi

# ── 4. Demotion policy for the non-target terminal ─────────────────────
# POLICY: additive-only. Decided 2026-08-05.
#
# --target GRANTS the three affordances above; it never REVOKES them from the
# other terminal. Run this for terminal and then for ghostty and both end up as
# login items, both pinned, both in the Finder menu. That is intended, not a bug.
#
# Why: the stated goal is that both terminals stay fully functional, and
# additive-only is the only policy that cannot cost you state you arranged by
# hand — a Dock layout, a login item you actually wanted. Every revoking variant
# trades that away for a tidier mental model.
#
# Consequence to accept: "primary" here is documentation, not enforcement.
#
# If that ever chafes, the narrow escalation is to drop the other's LOGIN ITEM
# only — the one affordance where "primary" has teeth, and the only one that is
# trivially reversible:
#   run "osascript -e 'tell application \"System Events\" to delete login item \"$1\"'"
# Do NOT extend it to Dock pins: removal needs a plist rewrite, and that is the
# single step that destroys user-arranged state.
demote_other() {
  inf "additive-only policy — $1 left intact (login item, Dock, Quick Action)"
}

if [[ "$TARGET" == "terminal" ]]; then
  OTHER_NAME="Ghostty"; OTHER_APP="/Applications/Ghostty.app"
else
  OTHER_NAME="Terminal"; OTHER_APP="/System/Applications/Utilities/Terminal.app"
fi
[[ -d "$OTHER_APP" ]] && demote_other "$OTHER_NAME"

printf '\n  %s set as the default macOS terminal experience.\n' "$APP_NAME"
printf "  (macOS has no true 'default terminal' flag — this is the practical equivalent.)\n"
printf '  The other terminal remains installed and fully functional.\n'
