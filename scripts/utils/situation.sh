#!/usr/bin/env bash
# scripts/utils/situation.sh — OPEN CLAW situational-awareness state model.
#
# Probes the operator's FLEET/slow state into a cached JSON snapshot that any
# surface (prompt, panel, notification, later a ratatui cockpit) can read in
# <1ms. This is the SPINE; renderers are downstream. v1 ships the INTERRUPT
# renderer only: `tick` diffs the snapshot and fires a desktop notification
# *only on a state transition* — the one tier that can't become wallpaper.
#
# Spec: vault _research/2026-06-15-claw-situation-spec.md
# Why fleet-state lives in a timer-refreshed cache: probing the homelab/K3s over
# the tailnet every prompt would lag every keystroke. Shell-LOCAL fast state
# (cwd/git/profile) is NOT modeled here — that's gathered at render time later.
#
# Subcommands:
#   probe            gather state -> ~/.cache/claw/situation.json (atomic)
#   tick             roll snapshot, probe, diff vs previous, notify on transitions
#   show [--json]    one-line glance (+ raw JSON with --json)
#   alerts           recent fired alerts
#   install          install + enable the systemd --user timer (runs `tick` ~60s)
#   uninstall        disable + remove the timer
#   review [--no-write]      summarize fired alerts + local-model tier-2 go/no-go
#   schedule-review <date> [HH:MM]   one-shot --user timer that runs `review` once
#   help
#
# Config (optional): ~/.config/claw/situation.env  (KEY=VALUE)
#   OLLAMA_HOST=127.0.0.1:11434   HOMELAB_HOST=bd790i   DISK_WARN_PCT=90
#   GPU_TEMP_WARN=85              KUBECONFIG_PATH=/etc/rancher/k3s/k3s.yaml
set -u

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claw"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claw"
SNAP="$CACHE_DIR/situation.json"
PREV="$CACHE_DIR/situation.prev.json"
ALERTS="$CACHE_DIR/situation.alerts.tsv"
ENVF="$CONFIG_DIR/situation.env"
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"

# Per-box overrides (defaults work whether this box IS the homelab or a remote cockpit).
[ -f "$ENVF" ] && . "$ENVF"
: "${OLLAMA_HOST:=127.0.0.1:11434}"
: "${HOMELAB_HOST:=}"                                  # remote host to ping; empty = skip
: "${DISK_WARN_PCT:=90}"
: "${GPU_TEMP_WARN:=85}"
: "${KUBECONFIG_PATH:=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}}"

mkdir -p "$CACHE_DIR" 2>/dev/null

have() { command -v "$1" >/dev/null 2>&1; }
gf()   { jq -r "$2" "$1" 2>/dev/null; }                # gf <file> <jq-filter>

# ── Desktop notification (the interrupt tier) ──────────────────────────────
notify() {
    # notify <info|crit> <title> <body>
    local urg="$1" title="CLAW · $2" body="$3"
    case "$(uname -s)" in
        Darwin) osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null ;;
        *)      if have notify-send; then
                    local u=normal; [ "$urg" = crit ] && u=critical
                    notify-send -u "$u" -i utilities-terminal "$title" "$body" 2>/dev/null
                fi ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$urg" "$2" "$body" >> "$ALERTS" 2>/dev/null || true
}

# ── Probe: best-effort, short-timeout, never hangs ─────────────────────────
probe_json() {
    local ts host ts_state peers_on peers_tot oll_up oll_models
    local gpu_present gpu_util gpu_mem_u gpu_mem_t gpu_temp disk_pct k_ready k_total hl_reach
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; host="$(hostname 2>/dev/null)"

    ts_state="unknown"; peers_on=0; peers_tot=0
    if have tailscale; then
        local tj; tj="$(timeout 3 tailscale status --json 2>/dev/null)"
        if [ -n "$tj" ] && have jq; then
            ts_state="$(printf '%s' "$tj" | jq -r '.BackendState // "unknown"' 2>/dev/null)"
            peers_tot="$(printf '%s' "$tj" | jq -r '(.Peer // {}) | length' 2>/dev/null)"
            peers_on="$(printf '%s' "$tj" | jq -r '[(.Peer // {})[] | select(.Online==true)] | length' 2>/dev/null)"
        fi
    fi
    : "${peers_on:=0}"; : "${peers_tot:=0}"; : "${ts_state:=unknown}"

    oll_up=false; oll_models=0
    local of; of="$(mktemp)"
    if curl -fsS --max-time 2 "http://${OLLAMA_HOST}/api/tags" >"$of" 2>/dev/null; then
        oll_up=true
        have jq && oll_models="$(jq -r '(.models // []) | length' <"$of" 2>/dev/null || echo 0)"
    fi
    rm -f "$of"; : "${oll_models:=0}"

    gpu_present=false; gpu_util=null; gpu_mem_u=null; gpu_mem_t=null; gpu_temp=null
    if have nvidia-smi; then
        local g; g="$(timeout 3 nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)"
        if [ -n "$g" ]; then
            gpu_present=true
            gpu_util="$(printf '%s' "$g" | awk -F', *' '{print $1+0}')"
            gpu_mem_u="$(printf '%s' "$g" | awk -F', *' '{print $2+0}')"
            gpu_mem_t="$(printf '%s' "$g" | awk -F', *' '{print $3+0}')"
            gpu_temp="$(printf '%s' "$g" | awk -F', *' '{print $4+0}')"
        fi
    fi

    disk_pct="$(df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5);print $5+0}')"; : "${disk_pct:=0}"

    k_ready=null; k_total=null
    if have kubectl && [ -r "$KUBECONFIG_PATH" ]; then
        local nodes; nodes="$(KUBECONFIG="$KUBECONFIG_PATH" timeout 4 kubectl get nodes --no-headers 2>/dev/null)"
        if [ -n "$nodes" ]; then
            k_total="$(printf '%s\n' "$nodes" | grep -c .)"
            k_ready="$(printf '%s\n' "$nodes" | awk '$2=="Ready"{c++} END{print c+0}')"
        fi
    fi

    hl_reach=null
    if [ -n "$HOMELAB_HOST" ]; then
        if timeout 2 ping -c1 -W1 "$HOMELAB_HOST" >/dev/null 2>&1; then hl_reach=true; else hl_reach=false; fi
    fi

    cat <<EOF
{
  "ts": "$ts",
  "host": "$host",
  "tailscale": { "state": "$ts_state", "peers_online": ${peers_on:-0}, "peers_total": ${peers_tot:-0} },
  "ollama": { "up": $oll_up, "models": ${oll_models:-0} },
  "gpu": { "present": $gpu_present, "util": ${gpu_util:-null}, "mem_used": ${gpu_mem_u:-null}, "mem_total": ${gpu_mem_t:-null}, "temp": ${gpu_temp:-null} },
  "disk_root_pct": ${disk_pct:-0},
  "k3s": { "ready": ${k_ready:-null}, "total": ${k_total:-null} },
  "homelab_reachable": ${hl_reach:-null}
}
EOF
}

cmd_probe() {
    local tmp; tmp="$(mktemp "${CACHE_DIR}/.sit.XXXXXX")" || return 1
    if probe_json >"$tmp" 2>/dev/null; then mv -f "$tmp" "$SNAP"; else rm -f "$tmp"; return 1; fi
}

# ── Tick: probe, diff vs previous, fire interrupts on TRANSITIONS only ──────
cmd_tick() {
    [ -f "$SNAP" ] && cp -f "$SNAP" "$PREV"
    cmd_probe || return 1
    have jq || return 0          # diff needs jq; degraded mode just refreshes the snapshot
    [ -f "$PREV" ] || return 0   # first run — nothing to compare against

    local p="$PREV" c="$SNAP"

    # Tailscale up/down
    local pts cts; pts="$(gf "$p" '.tailscale.state')"; cts="$(gf "$c" '.tailscale.state')"
    [ "$pts" = "Running" ] && [ "$cts" != "Running" ] && notify crit "Tailscale down" "BackendState: $cts"
    [ "$pts" != "Running" ] && [ "$pts" != "unknown" ] && [ "$cts" = "Running" ] && notify info "Tailscale up" "tailnet connected"

    # Ollama daemon up -> down
    local po co; po="$(gf "$p" '.ollama.up')"; co="$(gf "$c" '.ollama.up')"
    [ "$po" = "true" ] && [ "$co" = "false" ] && notify crit "Ollama down" "daemon unreachable at ${OLLAMA_HOST}"
    [ "$po" = "false" ] && [ "$co" = "true" ] && notify info "Ollama up" "daemon reachable"

    # K3s: transition into a NotReady state (ready < total, when previously whole)
    local pkr pkt ckr ckt; pkr="$(gf "$p" '.k3s.ready')"; pkt="$(gf "$p" '.k3s.total')"
    ckr="$(gf "$c" '.k3s.ready')"; ckt="$(gf "$c" '.k3s.total')"
    if [ "$ckt" != "null" ] && [ "$ckr" != "null" ] && [ "$ckr" -lt "$ckt" ] 2>/dev/null; then
        if [ "$pkr" = "null" ] || [ "$pkr" = "$pkt" ]; then
            notify crit "K3s node NotReady" "${ckr}/${ckt} nodes Ready"
        fi
    fi

    # Disk crossing the warn threshold (rising edge)
    local pd cd; pd="$(gf "$p" '.disk_root_pct')"; cd="$(gf "$c" '.disk_root_pct')"
    if [ "${cd:-0}" -ge "$DISK_WARN_PCT" ] 2>/dev/null && [ "${pd:-0}" -lt "$DISK_WARN_PCT" ] 2>/dev/null; then
        notify crit "Disk ${cd}%" "root filesystem above ${DISK_WARN_PCT}%"
    fi

    # GPU temp crossing the warn threshold (rising edge)
    local pgt cgt; pgt="$(gf "$p" '.gpu.temp')"; cgt="$(gf "$c" '.gpu.temp')"
    if [ "$cgt" != "null" ] && [ "${cgt:-0}" -ge "$GPU_TEMP_WARN" ] 2>/dev/null && [ "${pgt:-0}" -lt "$GPU_TEMP_WARN" ] 2>/dev/null; then
        notify crit "GPU ${cgt}°C" "above ${GPU_TEMP_WARN}°C"
    fi

    # Remote homelab reachability
    local ph ch; ph="$(gf "$p" '.homelab_reachable')"; ch="$(gf "$c" '.homelab_reachable')"
    [ "$ph" = "true" ] && [ "$ch" = "false" ] && notify crit "Homelab unreachable" "${HOMELAB_HOST} not responding"
    [ "$ph" = "false" ] && [ "$ch" = "true" ] && notify info "Homelab back" "${HOMELAB_HOST} reachable"

    return 0   # don't leak the last test's status — the systemd unit would show 'failed' on a clean run
}

cmd_show() {
    [ -f "$SNAP" ] || { echo "no snapshot yet — run: claw situation probe  (or: claw situation install)"; return 0; }
    if have jq; then
        jq -r '
          "● tailscale:" + .tailscale.state
          + " peers:" + (.tailscale.peers_online|tostring) + "/" + (.tailscale.peers_total|tostring)
          + "  ollama:" + (if .ollama.up then "up("+(.ollama.models|tostring)+")" else "DOWN" end)
          + "  k3s:" + (if .k3s.total then (.k3s.ready|tostring)+"/"+(.k3s.total|tostring) else "n/a" end)
          + (if .gpu.present then "  gpu:"+(.gpu.temp|tostring)+"°C/"+(.gpu.util|tostring)+"%" else "" end)
          + "  disk:" + (.disk_root_pct|tostring) + "%"
          + (if .homelab_reachable==null then "" else "  homelab:"+(if .homelab_reachable then "up" else "DOWN" end) end)
          + "   (" + .ts + ")"
        ' "$SNAP"
        [ "${1:-}" = "--json" ] && jq . "$SNAP"
    else
        cat "$SNAP"
    fi
    return 0
}

cmd_alerts() {
    [ -s "$ALERTS" ] || { echo "no alerts fired yet ($ALERTS)"; return 0; }
    tail -n "${1:-20}" "$ALERTS"
}

cmd_install() {
    local udir="$HOME/.config/systemd/user"
    if ! have systemctl; then echo "systemctl not found — user timers need systemd (Linux)"; return 1; fi
    mkdir -p "$udir"
    cp -f "$DOTFILES/config/systemd/claw-situation.service" "$udir/" || return 1
    cp -f "$DOTFILES/config/systemd/claw-situation.timer"   "$udir/" || return 1
    systemctl --user daemon-reload
    systemctl --user enable --now claw-situation.timer
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
    echo "✓ claw-situation timer enabled (runs 'situation tick' ~every 60s; linger on)"
    systemctl --user status claw-situation.timer --no-pager 2>/dev/null | sed -n '1,4p' || true
}

cmd_uninstall() {
    local udir="$HOME/.config/systemd/user"
    systemctl --user disable --now claw-situation.timer 2>/dev/null || true
    rm -f "$udir/claw-situation.service" "$udir/claw-situation.timer"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "✓ claw-situation timer removed"
}

# ── Week-1 review: summarize the fired alerts + local-model go/no-go ────────
# The spec's decision gate. Judges via local Hermes (sovereign) → Claude → manual.
cmd_review() {
    local nowrite=0; [ "${1:-}" = "--no-write" ] && nowrite=1
    local today; today="$(date +%F)"
    local total by_type flap first days current
    if [ -s "$ALERTS" ]; then
        total="$(wc -l < "$ALERTS" | tr -d ' ')"
        by_type="$(cut -f3 "$ALERTS" 2>/dev/null | sort | uniq -c | sort -rn)"
        flap="$(cut -f3 "$ALERTS" 2>/dev/null | sort | uniq -c | awk '$1>5{print "  ⚠ "$1"× "$2$3$4" (possible flapping)"}')"
        first="$(head -1 "$ALERTS" | cut -f1)"; days="first alert: $first"
    else
        total=0; by_type="  (none fired)"; flap=""; days="no alerts logged"
    fi
    current="$(cmd_show 2>/dev/null | head -1)"

    local summary
    summary="$(cat <<EOF
CLAW SITUATION — week-1 review ($today)
Alerts fired: $total   ($days)
By type:
$(printf '%s\n' "$by_type" | sed 's/^/  /')
${flap:+Flapping:
$flap
}Current fleet: $current
EOF
)"

    local prompt
    prompt="You are reviewing a one-week test of a homelab situational-awareness alerter for a sovereign/security operator. Decision gate: does the fleet change often enough that proactive change-alerts earn their keep?
- ~0 useful alerts => fleet is stable; HOLD (don't build tier 2; interrupt was the wrong bet).
- noisy/flapping => TUNE thresholds + dedup before expanding.
- a handful of ACTIONABLE alerts that caught real problems => GO: build tier 2 (an ambient prompt segment showing fleet health, then a one-week 'does it become wallpaper' test).
Data:
$summary

Give a SHORT (4-6 lines) opinionated recommendation labelled GO / TUNE / HOLD, and name the single most important observation."

    local verdict=""
    if have hermes && curl -fsS --max-time 2 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
        verdict="$(hermes "$prompt" 2>/dev/null | tr -d '\r' | sed $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' | sed '/^[[:space:]]*$/d')"
    elif have claude; then
        verdict="$(printf '%s' "$prompt" | claude -p 2>/dev/null)"
    fi
    [ -z "$verdict" ] && verdict="(no local model reachable — judge manually against the decision gate above)"

    printf '\n%s\n\n=== RECOMMENDATION (tier 2 go/no-go) ===\n%s\n\n' "$summary" "$verdict"

    local doc="$CACHE_DIR/situation-review-$today.md"
    printf '# claw situation — week-1 review (%s)\n\n```\n%s\n```\n\n## Recommendation\n\n%s\n' \
        "$today" "$summary" "$verdict" > "$doc" 2>/dev/null
    if [ "$nowrite" = 0 ]; then
        local vault="${OBSIDIAN_VAULT:-$HOME/Documents/hr-vault-main-pa}"
        if [ -d "$vault/_research" ]; then
            cp -f "$doc" "$vault/_research/${today}-claw-situation-week1-review.md" 2>/dev/null \
                && notify info "Situation review ready" "vault: _research/${today}-claw-situation-week1-review.md"
        fi
    fi
    return 0
}

# ── Schedule a one-shot review at a specific local datetime (systemd --user) ─
cmd_schedule_review() {
    local d="${1:-}" t="${2:-09:00}"
    [ -z "$d" ] && { echo "usage: situation schedule-review <YYYY-MM-DD> [HH:MM]"; return 1; }
    have systemctl || { echo "systemctl required (Linux user timers)"; return 1; }
    local udir="$HOME/.config/systemd/user"; mkdir -p "$udir"
    cp -f "$DOTFILES/config/systemd/claw-situation-review.service" "$udir/" || return 1
    cat > "$udir/claw-situation-review.timer" <<EOF
# One-shot: run the situation week-1 review at a specific LOCAL datetime.
# Generated by 'claw situation schedule-review' — machine-local, not in the repo.
[Unit]
Description=One-shot claw situation review at ${d} ${t}

[Timer]
OnCalendar=${d} ${t}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now claw-situation-review.timer
    echo "✓ review scheduled for ${d} ${t} (America/Chicago); runs 'situation review' once"
    systemctl --user list-timers --all claw-situation-review.timer --no-pager 2>/dev/null | sed -n '1,2p'
}

case "${1:-show}" in
    probe)            cmd_probe ;;
    tick)             cmd_tick ;;
    show|status|"")   shift 2>/dev/null || true; cmd_show "$@" ;;
    alerts)           shift; cmd_alerts "$@" ;;
    install|enable)   cmd_install ;;
    uninstall|disable) cmd_uninstall ;;
    review)           shift; cmd_review "$@" ;;
    schedule-review)  shift; cmd_schedule_review "$@" ;;
    help|-h|--help)
        sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "usage: situation {probe|tick|show [--json]|alerts|install|uninstall}"; exit 1 ;;
esac
