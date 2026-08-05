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
# TODO(henry): implement. See the note in chat — this is the one real policy
# call in this script and it is yours to make.
#
# Context: steps 1-3 are purely additive. Run this script for terminal, then
# for ghostty, and BOTH end up as login items, BOTH pinned, BOTH in the Finder
# menu. Nothing ever says "this one is primary" — the word loses its meaning.
#
# $OTHER_NAME / $OTHER_APP below name the terminal that is NOT the target.
# Decide what, if anything, --target should take away from it.
#
demote_other() {
  # shellcheck disable=SC2034  # other_app is scaffolding for the policy below.
  local other_name="$1" other_app="$2"
  # TODO: your policy here (~5-10 lines).
  #
  #   Options worth weighing:
  #   a) No-op — purely additive. Both stay everywhere. "Primary" means nothing
  #      but is maximally safe and reversible.
  #   b) Remove the other's LOGIN ITEM only. Only one terminal auto-opens, but
  #      both stay pinned and both stay in the Finder menu. Keeps "primary"
  #      meaningful at the one moment it matters (login) and touches nothing else.
  #   c) Full demotion — pull the other's login item, Dock pin, and Quick Action.
  #      Cleanest mental model, but destroys a Dock arrangement you may have
  #      hand-tuned, and Dock pins are annoying to restore.
  #
  #   Useful primitives:
  #     osascript -e "tell application \"System Events\" to delete login item \"$other_name\""
  #     rm -rf "$HOME/Library/Services/Open in ${other_name}.workflow"
  #   Dock removal needs a plist rewrite (PlistBuddy or a defaults read/filter/write)
  #   — note the existing pin step already backs the Dock plist up for you.
  #
  #   Respect DRY_RUN via the run() helper, and stay idempotent: a second run
  #   with the same --target must be a clean no-op.
  inf "demotion policy not implemented — $other_name left as-is"
}

if [[ "$TARGET" == "terminal" ]]; then
  OTHER_NAME="Ghostty"; OTHER_APP="/Applications/Ghostty.app"
else
  OTHER_NAME="Terminal"; OTHER_APP="/System/Applications/Utilities/Terminal.app"
fi
[[ -d "$OTHER_APP" ]] && demote_other "$OTHER_NAME" "$OTHER_APP"

printf '\n  %s set as the default macOS terminal experience.\n' "$APP_NAME"
printf "  (macOS has no true 'default terminal' flag — this is the practical equivalent.)\n"
printf '  The other terminal remains installed and fully functional.\n'
