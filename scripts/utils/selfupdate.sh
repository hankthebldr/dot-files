#!/usr/bin/env bash
# selfupdate.sh — keep the whole stack current automatically.
#   claw selfupdate now        run a full update right now (topgrade → manifest)
#   claw selfupdate install    schedule weekly (systemd user timer / launchd)
#   claw selfupdate status     show the schedule
#   claw selfupdate uninstall  remove the schedule
set -uo pipefail
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
source "$DOTFILES/scripts/utils/cinematic.sh" 2>/dev/null || { log_info(){ echo "▸ $*"; }; log_success(){ echo "✓ $*"; }; log_warning(){ echo "! $*"; }; c_white=''; c_reset=''; }
IS_MAC(){ [[ "$(uname -s)" == Darwin ]]; }

su_now(){ bash "$DOTFILES/scripts/utils/pkg-manifest.sh" update "$@"; }

su_install(){
  if IS_MAC; then
    local plist="$HOME/Library/LaunchAgents/com.openclaw.selfupdate.plist"
    mkdir -p "$(dirname "$plist")"
    cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.openclaw.selfupdate</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>$DOTFILES/scripts/utils/pkg-manifest.sh</string><string>update</string></array>
  <key>StartCalendarInterval</key><dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>10</integer></dict>
  <key>StandardOutPath</key><string>$HOME/.cache/claw/selfupdate.log</string>
  <key>StandardErrorPath</key><string>$HOME/.cache/claw/selfupdate.log</string>
</dict></plist>
PL
    launchctl unload "$plist" 2>/dev/null; launchctl load "$plist" && log_success "weekly self-update scheduled (Sun 10:00, launchd)"
  else
    local svc="$HOME/.config/systemd/user"; mkdir -p "$svc"
    cat > "$svc/claw-selfupdate.service" <<SV
[Unit]
Description=Open Claw self-update (topgrade + manifest)
[Service]
Type=oneshot
ExecStart=/bin/bash $DOTFILES/scripts/utils/pkg-manifest.sh update
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
