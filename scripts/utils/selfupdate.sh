#!/usr/bin/env bash
# selfupdate.sh — keep the whole stack current automatically.
#   claw selfupdate now        run the phased update right now (repo-sync → packages)
#   claw selfupdate install    schedule weekly (systemd user timer / launchd)
#   claw selfupdate status     show the schedule
#   claw selfupdate uninstall  remove the schedule
set -uo pipefail
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
source "$DOTFILES/scripts/utils/cinematic.sh" 2>/dev/null || { log_info(){ echo "▸ $*"; }; log_success(){ echo "✓ $*"; }; log_warning(){ echo "! $*"; }; c_white=''; c_reset=''; }
IS_MAC(){ [[ "$(uname -s)" == Darwin ]]; }

# One phased front door — `now` and the timers run the exact command a human
# would (`claw update --non-interactive`), so scheduled ≡ manual. Nonzero exit
# fires the one notification engine at crit tier; notify.sh's own stderr
# fallback means a missing desktop channel can never crash the run.
su_now(){
  local rc=0
  CLAW_UPDATE_TRIGGER=timer bash "$DOTFILES/bin/claw" update --non-interactive "$@" || rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -r "$DOTFILES/scripts/utils/notify.sh" ]; then
      bash "$DOTFILES/scripts/utils/notify.sh" send --crit --app CLAW --title "Self-update failed" \
        "claw update exited $rc — log: ~/.cache/claw/selfupdate.log" 2>/dev/null || true
    else
      log_warning "self-update failed (exit $rc) — notify.sh missing, message stays here"
    fi
  fi
  return $rc
}

# Timer units run with the daemon default PATH (launchd: /usr/bin:/bin:…;
# systemd --user: no brew/cargo/local), where `command -v topgrade`/brew/npm
# all miss and the weekly run silently no-ops — defeating scheduled ≡ manual.
# Bake the same prefixes .zshrc step 1 puts first (brew, ~/.local/bin, cargo,
# go, linuxbrew); nonexistent dirs in PATH are harmless on the other OS.
su_unit_path(){
  printf '%s' "$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
}

su_install(){
  if IS_MAC; then
    local plist="$HOME/Library/LaunchAgents/com.openclaw.selfupdate.plist"
    mkdir -p "$(dirname "$plist")"
    # bash -c wrapper so the failure path can fire notify.sh from inside the
    # unit (launchd only sees one exit code, and this keeps the crit alert
    # working even when the run dies before selfupdate's own su_now handler).
    cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.openclaw.selfupdate</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>CLAW_UPDATE_TRIGGER=timer /bin/bash '$DOTFILES/bin/claw' update --non-interactive || [ ! -r '$DOTFILES/scripts/utils/notify.sh' ] || /bin/bash '$DOTFILES/scripts/utils/notify.sh' send --crit --app CLAW --title 'Self-update failed' 'weekly claw update failed - log: ~/.cache/claw/selfupdate.log'</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$(su_unit_path)</string></dict>
  <key>StartCalendarInterval</key><dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>10</integer></dict>
  <key>StandardOutPath</key><string>$HOME/.cache/claw/selfupdate.log</string>
  <key>StandardErrorPath</key><string>$HOME/.cache/claw/selfupdate.log</string>
</dict></plist>
PL
    launchctl unload "$plist" 2>/dev/null; launchctl load "$plist" && log_success "weekly self-update scheduled (Sun 10:00, launchd)"
  else
    local svc="$HOME/.config/systemd/user"; mkdir -p "$svc"
    # Same bash -c wrapper as the plist: run the phased front door, and on
    # nonzero exit fire notify.sh --crit (guarded — missing engine is a no-op).
    cat > "$svc/claw-selfupdate.service" <<SV
[Unit]
Description=Open Claw self-update (claw update: repo-sync + packages)
[Service]
Type=oneshot
Environment="PATH=$(su_unit_path)"
ExecStart=/bin/bash -c 'CLAW_UPDATE_TRIGGER=timer /bin/bash "$DOTFILES/bin/claw" update --non-interactive || [ ! -r "$DOTFILES/scripts/utils/notify.sh" ] || /bin/bash "$DOTFILES/scripts/utils/notify.sh" send --crit --app CLAW --title "Self-update failed" "weekly claw update failed - see journalctl --user -u claw-selfupdate"'
SV
    cat > "$svc/claw-selfupdate.timer" <<TM
[Unit]
Description=Weekly Open Claw self-update
[Timer]
OnCalendar=Sun *-*-* 10:00:00
Persistent=true
[Install]
WantedBy=timers.target
TM
    systemctl --user daemon-reload 2>/dev/null
    systemctl --user enable --now claw-selfupdate.timer 2>/dev/null \
      && log_success "weekly self-update scheduled (Sun 10:00, systemd --user)" \
      || log_warning "systemd --user unavailable — run 'claw selfupdate now' manually / via cron"
  fi
}

su_status(){ IS_MAC && launchctl list 2>/dev/null | grep openclaw || systemctl --user list-timers claw-selfupdate.timer 2>/dev/null || log_warning "no schedule installed"; }
su_uninstall(){ if IS_MAC; then launchctl unload "$HOME/Library/LaunchAgents/com.openclaw.selfupdate.plist" 2>/dev/null; rm -f "$HOME/Library/LaunchAgents/com.openclaw.selfupdate.plist"; else systemctl --user disable --now claw-selfupdate.timer 2>/dev/null; rm -f "$HOME/.config/systemd/user/claw-selfupdate."{service,timer}; fi; log_success "self-update schedule removed"; }

case "${1:-now}" in
  now) shift; su_now "$@";; install) su_install;; status) su_status;; uninstall) su_uninstall;;
  *) echo "usage: claw selfupdate {now|install|status|uninstall}";;
esac
