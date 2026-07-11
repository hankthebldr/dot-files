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
#   homelab          probe the HR-TRUST fleet -> ~/.cache/claw/homelab.json (atomic)
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
HOMELAB_SNAP="$CACHE_DIR/homelab.json"
HOMELAB_FLEET="$DOTFILES/config/homelab/fleet.yml"
[ -r "$CONFIG_DIR/fleet.yml" ] && HOMELAB_FLEET="$CONFIG_DIR/fleet.yml"   # machine-local override wins

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

# GNU `timeout` is absent on stock macOS (brew coreutils ships only gtimeout).
# Every probe below is wrapped in `timeout N`, so shim it: prefer gtimeout,
# else run the command unbounded — degraded but working beats exit 127.
if ! have timeout; then
    if have gtimeout; then
        timeout() { gtimeout "$@"; }
    else
        timeout() { shift; "$@"; }
    fi
fi

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

# --- HR-TRUST fleet probe -------------------------------------------------
# Reads config/homelab/fleet.yml, probes each machine's reachability + its
# declared services, plus access-level identity + the tailscale traffic route.
# Emits the canonical homelab.json by string accumulation (NO jq for emission,
# matching probe_json); jq is used only (guarded) to PARSE tailscale/gh output.
# Every external call is timeout-bounded so a tick never hangs.

_hl_json_str() {                      # minimal JSON string escaper (quotes + backslash)
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Probe one service. Echoes:  <state>\t<detail>
# $5 = cluster traefik_ip (for Host-header http probes); $6 = cluster context.
# curl probes carry --noproxy '*' — LAN/tailnet targets must never route
# through an HTTP proxy (a proxy's 403 would read as the service being up).
_hl_probe_service() {
    local host="$1" user="$2" ssh_ok="$3" svc="$4" traefik_ip="$5" ctx_default="$6"
    local kind shost port health planned state detail
    kind="$(yq -r ".services.${svc}.kind // \"native\"" "$HOMELAB_FLEET" 2>/dev/null)"
    planned="$(yq -r ".services.${svc}.planned // false" "$HOMELAB_FLEET" 2>/dev/null)"
    state="down"; detail="unreachable"
    case "$kind" in
        http)
            shost="$(yq -r ".services.${svc}.host // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            port="$(yq -r ".services.${svc}.port // 0" "$HOMELAB_FLEET" 2>/dev/null)"
            health="$(yq -r ".services.${svc}.health // \"/\"" "$HOMELAB_FLEET" 2>/dev/null)"
            local code
            if [ "$port" != "0" ]; then
                # direct endpoint probe (e.g. ollama :11434/api/tags)
                code="$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' --max-time 2 \
                    "http://${shost}:${port}${health}" 2>/dev/null)"
            else
                # cluster app via Traefik Host header — DNS-independent
                code="$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' --max-time 2 \
                    -H "Host: ${shost}" "http://${traefik_ip}/" 2>/dev/null)"
            fi
            case "$code" in
                2*|30*|401|403) state="up";       detail="http ${code}" ;;
                50[234])        state="degraded"; detail="http ${code}" ;;
                *)              state="down";     detail="${code:-000}" ;;
            esac ;;
        dns)
            local server probe ans
            server="$(yq -r ".services.${svc}.server // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            probe="$(yq -r ".services.${svc}.dns_probe // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            if [ -n "$server" ] && [ -n "$probe" ]; then
                ans="$(timeout 2 dig +short "@${server}" "$probe" 2>/dev/null | head -1)"
                if [ -n "$ans" ]; then state="up"; detail="${probe%%.*}→${ans}"; fi
            fi ;;
        tcp)
            shost="$(yq -r ".services.${svc}.host // \"$host\"" "$HOMELAB_FLEET" 2>/dev/null)"
            port="$(yq -r ".services.${svc}.port // 0" "$HOMELAB_FLEET" 2>/dev/null)"
            if [ "$port" != "0" ] && timeout 2 bash -c "exec 3<>/dev/tcp/${shost}/${port}" 2>/dev/null; then
                state="up"; detail=":${port}"
            fi ;;
        kube)
            local kctx; kctx="$(yq -r ".services.${svc}.context // \"$ctx_default\"" "$HOMELAB_FLEET" 2>/dev/null)"
            local nodes=""
            if have kubectl; then
                nodes="$(timeout 5 kubectl --context "$kctx" get nodes --no-headers 2>/dev/null)"
            fi
            if [ -z "$nodes" ] && [ "$ssh_ok" = "true" ]; then
                nodes="$(timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 \
                    "${user}@${host}" "kubectl get nodes --no-headers 2>/dev/null" 2>/dev/null)"
            fi
            if [ -n "$nodes" ]; then
                local tot rdy; tot="$(printf '%s\n' "$nodes" | grep -c .)"
                rdy="$(printf '%s\n' "$nodes" | awk '$2=="Ready"{c++} END{print c+0}')"
                [ "$rdy" -gt 0 ] 2>/dev/null && state="up"
                detail="${kctx} · ${rdy}/${tot} Ready"
            fi ;;
        ssh)
            local cmd; cmd="$(yq -r ".services.${svc}.cmd // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            if [ "$ssh_ok" = "true" ] && [ -n "$cmd" ]; then
                local out; out="$(timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 \
                    "${user}@${host}" "$cmd" 2>/dev/null | tr -d ' ')"
                if [ -n "$out" ]; then state="up"; detail="${out} containers"; fi
            fi ;;
        native|*)
            # tailscale BackendState — local if this box, else over ssh
            local bs=""
            if [ "$ssh_ok" = "true" ]; then
                bs="$(timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 "${user}@${host}" \
                    "tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null" 2>/dev/null)"
            elif have tailscale; then
                bs="$(timeout 3 tailscale status --json 2>/dev/null | { have jq && jq -r '.BackendState' 2>/dev/null; })"
            fi
            if [ "${bs:-}" = "Running" ]; then state="up"; detail="running"; fi ;;
    esac
    # A declared-but-not-yet-deployed service shows as 'planned', not red 'down'.
    [ "$state" = "down" ] && [ "$planned" = "true" ] && { state="planned"; detail="not deployed"; }
    printf '%s\t%s' "$state" "$detail"
}

probe_homelab() {
    local ts fleet_name route_via route_path gh_user gh_state
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fleet_name="HR-TRUST"; route_via="unknown"; route_path=""; gh_user=""; gh_state="down"
    : "${USER:=$(id -un)}"          # set -u guard: USER feeds the per-machine default

    # Need yq + a fleet file, else emit an empty-but-valid snapshot.
    if ! have yq || [ ! -r "$HOMELAB_FLEET" ]; then
        cat <<EOF
{ "ts": "$ts", "fleet": "$fleet_name",
  "cluster": {"context":"","ready":null,"total":null},
  "route": {"via":"unknown","path":"","exit_node":null},
  "identity": {}, "machines": [] }
EOF
        return 0
    fi
    fleet_name="$(yq -r '.fleet.name // "HR-TRUST"' "$HOMELAB_FLEET" 2>/dev/null)"

    # Access-level identity: github login via gh
    if have gh; then
        local _gh_out
        _gh_out="$(timeout 4 gh api user --jq .login 2>/dev/null)" && gh_user="$_gh_out"
        [ -n "$gh_user" ] && gh_state="up"
    fi

    # Tailscale status JSON, fetched ONCE — drives both the route and per-machine
    # reachability. (Uses `tailscale status --json`, the same proven invocation as
    # probe_json; deliberately NOT `tailscale ping`, whose count flag varies by
    # build. `startswith($h+".")` matches the MagicDNS name without regex metachar
    # surprises.)
    local tj=""; have tailscale && tj="$(timeout 3 tailscale status --json 2>/dev/null)"

    # Traffic route to the first machine: CurAddr present → direct; else Relay = DERP hop.
    local first_host; first_host="$(yq -r '.machines[0].host // ""' "$HOMELAB_FLEET" 2>/dev/null)"
    if [ -n "$tj" ] && have jq && [ -n "$first_host" ]; then
        local cur relay
        cur="$(printf '%s' "$tj" | jq -r --arg h "$first_host" \
            '[(.Peer // {})[] | select(.DNSName|startswith($h+"."))][0] // {} | .CurAddr // ""' 2>/dev/null)"
        relay="$(printf '%s' "$tj" | jq -r --arg h "$first_host" \
            '[(.Peer // {})[] | select(.DNSName|startswith($h+"."))][0] // {} | .Relay // ""' 2>/dev/null)"
        if [ -n "$cur" ]; then route_via="direct"; route_path="→ ${first_host}"
        elif [ -n "$relay" ]; then route_via="derp"; route_path="→ DERP(${relay}) → ${first_host}"
        else route_via="unknown"; route_path="→ ${first_host}"; fi
    fi

    # cluster block — context + traefik probe target
    local cl_ctx cl_ip cl_ready=null cl_total=null cn=""
    cl_ctx="$(yq -r '.cluster.context // ""' "$HOMELAB_FLEET" 2>/dev/null)"
    cl_ip="$(yq -r '.cluster.traefik_ip // ""' "$HOMELAB_FLEET" 2>/dev/null)"
    # cluster readiness once (cheap, reused as the k3s service detail too)
    if have kubectl && [ -n "$cl_ctx" ]; then
        cn="$(timeout 5 kubectl --context "$cl_ctx" get nodes --no-headers 2>/dev/null)"
        if [ -n "$cn" ]; then
            cl_total="$(printf '%s\n' "$cn" | grep -c .)"
            cl_ready="$(printf '%s\n' "$cn" | awk '$2=="Ready"{c++} END{print c+0}')"
        fi
    fi

    # Machines × services
    local machines_json="" mi=0 mcount
    mcount="$(yq -r '.machines | length' "$HOMELAB_FLEET" 2>/dev/null)"; : "${mcount:=0}"
    while [ "$mi" -lt "$mcount" ]; do
        local id host user ssh_ok role mstate addr latency
        id="$(yq -r ".machines[$mi].id // \"node$mi\"" "$HOMELAB_FLEET" 2>/dev/null)"
        host="$(yq -r ".machines[$mi].host // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
        user="$(yq -r ".machines[$mi].user // \"$USER\"" "$HOMELAB_FLEET" 2>/dev/null)"
        ssh_ok="$(yq -r ".machines[$mi].ssh // false" "$HOMELAB_FLEET" 2>/dev/null)"
        role="$(yq -r ".machines[$mi].role // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
        mstate="down"; addr=""; latency="null"

        # reachability: tailscale peer first, else nc/ping fallback (LAN-friendly).
        # latency stays null (status doesn't measure RTT; no render needs it).
        if [ -n "$tj" ] && have jq && [ -n "$host" ]; then
            local online
            online="$(printf '%s' "$tj" | jq -r --arg h "$host" \
                '[(.Peer // {})[] | select(.DNSName|startswith($h+"."))][0] // {} | .Online // false' 2>/dev/null)"
            addr="$(printf '%s' "$tj" | jq -r --arg h "$host" \
                '[(.Peer // {})[] | select(.DNSName|startswith($h+"."))][0] // {} | (.TailscaleIPs // [""])[0] // ""' 2>/dev/null)"
            [ "$online" = "true" ] && mstate="up"
        fi
        if [ "$mstate" != "up" ] && [ -n "$host" ]; then
            if timeout 2 bash -c "exec 3<>/dev/tcp/${host}/22" 2>/dev/null \
               || timeout 2 bash -c "exec 3<>/dev/tcp/${host}/80" 2>/dev/null \
               || ping -c1 -W1 "$host" >/dev/null 2>&1; then
                mstate="up"; : "${addr:=$host}"
            fi
        fi
        : "${addr:=}"; : "${latency:=null}"

        # node Ready state from the cluster probe overrides reachability for k8s nodes
        if [ -n "$cn" ]; then
            local nr; nr="$(printf '%s\n' "$cn" | awk -v n="$id" '$1==n{print $2}')"
            [ "$nr" = "NotReady" ] && mstate="degraded"
            [ "$nr" = "Ready" ] && mstate="up"
        fi

        local svcs_json="" si=0 scount svc
        scount="$(yq -r ".machines[$mi].services | length" "$HOMELAB_FLEET" 2>/dev/null)"; : "${scount:=0}"
        while [ "$si" -lt "$scount" ]; do
            svc="$(yq -r ".machines[$mi].services[$si]" "$HOMELAB_FLEET" 2>/dev/null)"
            local skind sstate sdetail line grp gly
            skind="$(yq -r ".services.${svc}.kind // \"native\"" "$HOMELAB_FLEET" 2>/dev/null)"
            grp="$(yq -r ".services.${svc}.group // \"apps\"" "$HOMELAB_FLEET" 2>/dev/null)"
            gly="$(yq -r ".services.${svc}.glyph // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            # cluster-level kinds probe regardless of machine reachability;
            # shell-level kinds (ssh/native) require the box up.
            if [ "$mstate" = "up" ] || [ "$mstate" = "degraded" ] \
               || [ "$skind" = "http" ] || [ "$skind" = "dns" ] \
               || [ "$skind" = "kube" ] || [ "$skind" = "tcp" ]; then
                line="$(_hl_probe_service "$host" "$user" "$ssh_ok" "$svc" "$cl_ip" "$cl_ctx")"
                sstate="${line%%	*}"; sdetail="${line#*	}"
            else
                sstate="down"; sdetail="host down"
            fi
            [ -n "$svcs_json" ] && svcs_json="${svcs_json},"
            svcs_json="${svcs_json}{\"id\":\"$(_hl_json_str "$svc")\",\"state\":\"${sstate}\",\"detail\":\"$(_hl_json_str "$sdetail")\",\"group\":\"$(_hl_json_str "$grp")\",\"glyph\":\"$(_hl_json_str "$gly")\"}"
            si=$((si+1))
        done

        [ -n "$machines_json" ] && machines_json="${machines_json},"
        machines_json="${machines_json}{\"id\":\"$(_hl_json_str "$id")\",\"state\":\"${mstate}\",\"addr\":\"$(_hl_json_str "$addr")\",\"latency_ms\":${latency:-null},\"role\":\"$(_hl_json_str "$role")\",\"services\":[${svcs_json}]}"
        mi=$((mi+1))
    done

    cat <<EOF
{
  "ts": "$ts",
  "fleet": "$(_hl_json_str "$fleet_name")",
  "cluster": { "context": "$(_hl_json_str "$cl_ctx")", "ready": ${cl_ready:-null}, "total": ${cl_total:-null} },
  "route": { "via": "$(_hl_json_str "$route_via")", "path": "$(_hl_json_str "$route_path")", "exit_node": null },
  "identity": { "github": { "user": "$(_hl_json_str "$gh_user")", "state": "$gh_state" } },
  "machines": [${machines_json}]
}
EOF
}

cmd_homelab_poll() {
    local tmp; tmp="$(mktemp "${CACHE_DIR}/.hl.XXXXXX")" || return 1
    if probe_homelab >"$tmp" 2>/dev/null; then mv -f "$tmp" "$HOMELAB_SNAP"; else rm -f "$tmp"; return 1; fi
    return 0
}

cmd_probe() {
    local tmp; tmp="$(mktemp "${CACHE_DIR}/.sit.XXXXXX")" || return 1
    if probe_json >"$tmp" 2>/dev/null; then mv -f "$tmp" "$SNAP"; else rm -f "$tmp"; return 1; fi
}

# ── Tick: probe, diff vs previous, fire interrupts on TRANSITIONS only ──────
cmd_tick() {
    [ -f "$SNAP" ] && cp -f "$SNAP" "$PREV"
    cmd_probe || return 1
    cmd_homelab_poll || true     # keep homelab.json fresh on the same timer (best-effort)
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
    if have launchctl && [ "$(uname -s)" = Darwin ]; then
        mkdir -p "$HOME/Library/LaunchAgents"
        cp -f "$DOTFILES/config/launchd/com.openclaw.situation.plist" \
              "$HOME/Library/LaunchAgents/com.openclaw.situation.plist" || return 1
        launchctl unload "$HOME/Library/LaunchAgents/com.openclaw.situation.plist" 2>/dev/null || true
        launchctl load "$HOME/Library/LaunchAgents/com.openclaw.situation.plist"
        echo "✓ claw-situation timer installed (runs 'situation tick' ~every 60s; launchd)"
    elif have systemctl; then
        local udir="$HOME/.config/systemd/user"
        mkdir -p "$udir"
        cp -f "$DOTFILES/config/systemd/claw-situation.service" "$udir/" || return 1
        cp -f "$DOTFILES/config/systemd/claw-situation.timer"   "$udir/" || return 1
        systemctl --user daemon-reload
        systemctl --user enable --now claw-situation.timer
        loginctl enable-linger "$USER" >/dev/null 2>&1 || true
        echo "✓ claw-situation timer enabled (runs 'situation tick' ~every 60s; linger on)"
        systemctl --user status claw-situation.timer --no-pager 2>/dev/null | sed -n '1,4p' || true
    else
        echo "no timer scheduler found — need launchctl (macOS) or systemctl (Linux)"; return 1
    fi
}

cmd_uninstall() {
    if have launchctl && [ "$(uname -s)" = Darwin ]; then
        launchctl unload "$HOME/Library/LaunchAgents/com.openclaw.situation.plist" 2>/dev/null || true
        rm -f "$HOME/Library/LaunchAgents/com.openclaw.situation.plist"
    elif have systemctl; then
        local udir="$HOME/.config/systemd/user"
        systemctl --user disable --now claw-situation.timer 2>/dev/null || true
        rm -f "$udir/claw-situation.service" "$udir/claw-situation.timer"
        systemctl --user daemon-reload 2>/dev/null || true
    fi
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
    homelab|fleet)    cmd_homelab_poll ;;
    help|-h|--help)
        sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "usage: situation {probe|tick|show [--json]|alerts|homelab|install|uninstall}"; exit 1 ;;
esac
