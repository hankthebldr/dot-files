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
#   homelab [--force]  probe the HR-TRUST fleet -> ~/.cache/claw/homelab.json
#                    (300s throttle + mkdir single-flight lock; --force ignores both)
#   local [--force]  probe SHELL-LOCAL slow state (Things, handoff, dirty repos,
#                    worktrees, claude sessions) -> ~/.cache/claw/local.json (600s throttle)
#   evaluate         the ONE attention rule set over situation/homelab/updates/local
#                    -> attention.json + attention.tsv + attention.count (atomic)
#   install          install + enable the systemd --user timer (runs `tick` ~60s)
#   uninstall        disable + remove the timer
#   review [--no-write]      summarize fired alerts + local-model tier-2 go/no-go
#   schedule-review <date> [HH:MM]   one-shot timer that runs `review` once
#                                    (systemd --user on Linux · launchd on macOS)
#   help
#
# Config (optional): ~/.config/claw/situation.env  (KEY=VALUE)
#   OLLAMA_HOST=127.0.0.1:11434   HOMELAB_HOST=bd790i   DISK_WARN_PCT=90
#   GPU_TEMP_WARN=85              KUBECONFIG_PATH=/etc/rancher/k3s/k3s.yaml
#   UPDATES_NOTIFY=info           # repo-behind notify tier: info | off
#   LOAD_WARN_X=2.0               # warn when load1/ncpu crosses this
#   THINGS_SHOW=nonzero           # context-row policy for the renderers
#   CLAW_TTL_SITUATION/_HOMELAB/_UPDATES/_LOCAL   # staleness TTLs (s); 2xTTL = stale
#   CLAW_HOMELAB_THROTTLE=300  CLAW_LOCAL_THROTTLE=600  CLAW_LOCK_STALE=120
set -u

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claw"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claw"
SNAP="$CACHE_DIR/situation.json"
ALERTS="$CACHE_DIR/situation.alerts.tsv"
ENVF="$CONFIG_DIR/situation.env"
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
HOMELAB_SNAP="$CACHE_DIR/homelab.json"
LOCAL_SNAP="$CACHE_DIR/local.json"
UPDATES_SNAP="$CACHE_DIR/updates.json"
ATTN_JSON="$CACHE_DIR/attention.json"
ATTN_TSV="$CACHE_DIR/attention.tsv"
ATTN_COUNT="$CACHE_DIR/attention.count"
ATTN_PREV="$CACHE_DIR/attention.prev.json"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claw"
ACKS="$STATE_DIR/acks.tsv"
HOMELAB_FLEET="$DOTFILES/config/homelab/fleet.yml"
[ -r "$CONFIG_DIR/fleet.yml" ] && HOMELAB_FLEET="$CONFIG_DIR/fleet.yml"   # machine-local override wins

# IPv4 default gateway, or empty. macOS `route`, Linux `ip`; both silent on failure.
_default_gateway() {
    if [ "$(uname -s)" = Darwin ]; then
        route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}'
    else
        ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}'
    fi
}

# Per-box overrides (defaults work whether this box IS the homelab or a remote cockpit).
[ -f "$ENVF" ] && . "$ENVF"
: "${OLLAMA_HOST:=127.0.0.1:11434}"
: "${HOMELAB_HOST:=}"                                  # remote host to ping; empty = skip
: "${DISK_WARN_PCT:=90}"
: "${GPU_TEMP_WARN:=85}"
: "${KUBECONFIG_PATH:=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}}"
: "${UPDATES_NOTIFY:=info}"                            # repo-behind alerts: info|off
: "${LOAD_WARN_X:=2.0}"                                # warn at load1/ncpu >= this
: "${THINGS_SHOW:=nonzero}"                            # renderer policy for the context row
# Staleness TTLs (seconds). A source older than 2xTTL is reported as ONE warn and
# its items are dropped rather than rendered as current. Each TTL is the source's
# own refresh cadence.
: "${CLAW_TTL_HOMELAB:=300}"
: "${CLAW_TTL_UPDATES:=21600}"
: "${CLAW_TTL_LOCAL:=600}"
: "${CLAW_HOMELAB_THROTTLE:=300}"                      # homelab re-poll floor
: "${CLAW_LOCAL_THROTTLE:=600}"                        # local re-poll floor
: "${CLAW_LOCK_STALE:=120}"                            # a lock older than this is a corpse
: "${GH_IDENT_TTL:=21600}"                             # `gh api user` stamp lifetime

mkdir -p "$CACHE_DIR" 2>/dev/null

have() { command -v "$1" >/dev/null 2>&1; }
gf()   { jq -r "$2" "$1" 2>/dev/null; }                # gf <file> <jq-filter>

# seconds since a file's mtime (GNU/BSD stat); huge number when unreadable so
# a missing cache always reads as stale
file_age() {
    local m; m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)"
    if [ -n "$m" ]; then echo $(( $(date +%s) - m )); else echo 999999999; fi
}

# digits-only guard for values embedded raw into the JSON snapshot — anything
# else (jq's "null", an error, a corrupt cache) degrades to null, never breaks
# the emitted document
num_or_null() { case "${1:-}" in ''|*[!0-9]*) echo null ;; *) echo "$1" ;; esac; }
# same, but for a decimal (load average) — '' / 'null' / junk all degrade to null
dec_or_null() { case "${1:-}" in ''|*[!0-9.]*|.|*.*.*) echo null ;; *) echo "$1" ;; esac; }

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
# Delegates the desktop popup to the ONE notify engine (scripts/utils/notify.sh)
# so macOS and Linux behave identically — crit is audible + distinguishable on
# both (macOS was previously a silent banner identical to info). The alert-log
# TSV is the one thing kept local. Falls back to an inline osascript/notify-send
# if the engine is somehow absent (e.g. a partial checkout).
NOTIFY_ENGINE="$DOTFILES/scripts/utils/notify.sh"
notify() {
    # notify <info|crit> <title> <body>
    local urg="$1" title="CLAW · $2" body="$3" flag="--info"
    [ "$urg" = crit ] && flag="--crit"
    if [ -r "$NOTIFY_ENGINE" ]; then
        bash "$NOTIFY_ENGINE" send "$flag" --app "CLAW" --title "$title" "$body" 2>/dev/null
    else
        case "$(uname -s)" in
            Darwin)
                local sound=""; [ "$urg" = crit ] && sound=" sound name \"Basso\""
                osascript -e "display notification \"$body\" with title \"$title\"${sound}" 2>/dev/null ;;
            *)      if have notify-send; then
                        local u=normal; [ "$urg" = crit ] && u=critical
                        notify-send -u "$u" -i utilities-terminal "$title" "$body" 2>/dev/null
                    fi ;;
        esac
    fi
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

    # 1-minute load + core count — the two numbers the LOAD_WARN_X rule needs.
    # BSD `uptime` says "load averages:", GNU says "load average:"; one sed covers both.
    local load1 ncpu
    load1="$(uptime 2>/dev/null | sed 's/.*load averages*:[[:space:]]*//' | awk -F'[, ]+' '{print $1}')"
    ncpu="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '')"
    load1="$(dec_or_null "$load1")"; ncpu="$(num_or_null "$ncpu")"

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

    # Pending updates: merge update-status.sh's cache when fresh (<24h), else
    # nulls. Deliberately a cache READ — probing package managers here would
    # slow every ~60s tick; the welcome-TUI kick / --force keeps it warm.
    local up_brew=null up_apt=null up_behind=null up_ahead=null up_last=null
    local upf="$CACHE_DIR/updates.json"
    if have jq && [ -r "$upf" ] && [ "$(file_age "$upf")" -lt 86400 ]; then
        up_brew="$(num_or_null "$(gf "$upf" '.brew')")"
        up_apt="$(num_or_null "$(gf "$upf" '.apt')")"
        up_behind="$(num_or_null "$(gf "$upf" '.repo_behind')")"
        up_ahead="$(num_or_null "$(gf "$upf" '.repo_ahead')")"
        up_last="$(num_or_null "$(gf "$upf" '.last_run')")"
    fi

    cat <<EOF
{
  "ts": "$ts",
  "host": "$host",
  "tailscale": { "state": "$ts_state", "peers_online": ${peers_on:-0}, "peers_total": ${peers_tot:-0} },
  "ollama": { "up": $oll_up, "models": ${oll_models:-0} },
  "gpu": { "present": $gpu_present, "util": ${gpu_util:-null}, "mem_used": ${gpu_mem_u:-null}, "mem_total": ${gpu_mem_t:-null}, "temp": ${gpu_temp:-null} },
  "disk_root_pct": ${disk_pct:-0},
  "load": { "load1": ${load1:-null}, "ncpu": ${ncpu:-null} },
  "k3s": { "ready": ${k_ready:-null}, "total": ${k_total:-null} },
  "updates": { "brew": ${up_brew:-null}, "apt": ${up_apt:-null}, "repo_behind": ${up_behind:-null}, "repo_ahead": ${up_ahead:-null}, "last_run": ${up_last:-null} },
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

    # LAN-fallback gate (audit 2026-09-20 F-05). The nc/ping fallback below dials
    # the RFC1918 addresses in fleet.yml. Off the home LAN that means ~20 s of
    # probing a stranger's network on every login kick. Fall back only when the
    # default gateway matches fleet.lan_gateway; an undeclared lan_gateway keeps
    # the legacy always-probe behaviour. CLAW_HOMELAB_LAN=1|0 forces either way.
    local lan_gw cur_gw lan_ok=1
    lan_gw="$(yq -r '.fleet.lan_gateway // ""' "$HOMELAB_FLEET" 2>/dev/null)"
    if [ -n "$lan_gw" ]; then
        cur_gw="$(_default_gateway)"
        [ "$cur_gw" = "$lan_gw" ] || lan_ok=0
    fi
    case "${CLAW_HOMELAB_LAN:-}" in 1) lan_ok=1 ;; 0) lan_ok=0 ;; esac

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
        if [ "$lan_ok" = 1 ] && [ "$mstate" != "up" ] && [ -n "$host" ]; then
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


# ── Evaluate: the ONE attention rule set ───────────────────────────────────
# Reads the four caches (any of them missing == null), applies the rule table
# from the design spec ONCE, and lands the three files every renderer reads:
#   attention.json   {v:1, checked:{…}, items:[{id,tier,text,hint,since,src_ts}]}
#   attention.tsv    tier\tid\ttext\thint\tsince_epoch\tsrc_epoch  (crit→warn→info, since asc)
#   attention.count  "<n> <worst_tier>"  — n counts crit+warn only; "0 ok" when clear
# `since` survives across runs for an id that persists, so the strip can say how
# long something has been broken. Acked ids (acks.tsv, until > now) are demoted to
# info/hint=acked: kept in the json so `tick` still diffs them, dropped from the
# tsv/count so the strip and the ⚑ segment stay quiet.
# A source older than 2xTTL contributes ONE warn and NONE of its items — a stale
# cache must never render as current truth.

# mtime epoch of $1, or empty
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# echo a cache's JSON when it parses, else the literal null
_cache_json() {
    if [ -r "$1" ] && jq -e . "$1" >/dev/null 2>&1; then cat "$1"; else echo null; fi
}
_cache_mtime_json() {
    local m; m="$(_mtime "$1" 2>/dev/null)"
    if [ -r "$1" ] && [ -n "$m" ]; then echo "$m"; else echo null; fi
}

# live acks as a {id: until_epoch} object
_acks_json() {
    local body="" now; now="$(date +%s)"
    if [ -r "$ACKS" ]; then
        body="$(awk -F'\t' -v now="$now" \
            'NF>=2 && $2+0>now { gsub(/"/,"",$1); printf "%s\"%s\":%d", (c++?",":""), $1, $2+0 }' \
            "$ACKS" 2>/dev/null)"
    fi
    printf '{%s}' "$body"
}

# situation.json's TTL is the fleet's poll cadence, floored at 300s so a box
# without the timer installed doesn't report itself stale between logins.
_ttl_situation() {
    if [ -n "${CLAW_TTL_SITUATION:-}" ]; then printf '%s' "$CLAW_TTL_SITUATION"; return 0; fi
    local p=""
    have yq && [ -r "$HOMELAB_FLEET" ] && p="$(yq -r '.fleet.poll_seconds // ""' "$HOMELAB_FLEET" 2>/dev/null)"
    p="$(num_or_null "$p")"
    if [ "$p" != null ] && [ "$p" -gt 300 ] 2>/dev/null; then printf '%s' "$p"; else printf '300'; fi
}

_ATTN_JQ='
def ageword($s):
  if   $s >= 86400 then ((($s/86400)|floor|tostring) + "d")
  elif $s >= 3600  then ((($s/3600)|floor|tostring) + "h")
  elif $s >= 60    then ((($s/60)|floor|tostring) + "m")
  else (($s|floor|tostring) + "s") end;

(($sit_ts != null) and (($now - $sit_ts) > (2 * $ttl_sit))) as $sit_stale
| (($hl_ts  != null) and (($now - $hl_ts)  > (2 * $ttl_hl)))  as $hl_stale
| (($upd_ts != null) and (($now - $upd_ts) > (2 * $ttl_upd))) as $upd_stale
| (($loc_ts != null) and (($now - $loc_ts) > (2 * $ttl_loc))) as $loc_stale
| (if ($sit == null) or $sit_stale then null else $sit end) as $S
| (if ($hl  == null) or $hl_stale  then null else $hl  end) as $H
| (if ($upd == null) or $upd_stale then null else $upd end) as $U
| ((($prev.items // []) | map({key: .id, value: .since}) | from_entries)) as $was
| ([
    # crit — tailnet down ("unknown" means no tailscale on this box, not an outage)
    (if ($S != null) and (($S.tailscale.state // "unknown") | (. != "Running" and . != "unknown"))
     then {id:"tailscale", tier:"crit", text:"tailscale down", hint:"tailscale up", src_ts:$sit_ts}
     else empty end),

    # crit — k3s short of quorum. situation.json owns this when it has a reading;
    # otherwise the fleet poll does (a laptop has no kubeconfig but does have homelab.json).
    ((if ($S != null) and (($S.k3s.total // null) != null) and (($S.k3s.ready // null) != null)
      then {r: $S.k3s.ready, t: $S.k3s.total, ctx: ($H.cluster.context // ""), src: $sit_ts}
      elif ($H != null) and (($H.cluster.total // null) != null) and (($H.cluster.ready // null) != null)
      then {r: $H.cluster.ready, t: $H.cluster.total, ctx: ($H.cluster.context // ""), src: $hl_ts}
      else null end) as $k
     | if ($k != null) and ($k.r < $k.t)
       then {id:"k3s", tier:"crit",
             text:("k3s " + ($k.r|tostring) + "/" + ($k.t|tostring) + " Ready"
                   + (if ($k.ctx // "") == "" then "" else " · " + $k.ctx end)),
             hint:"kubectl get nodes", src_ts:$k.src}
       else empty end),

    # crit — root filesystem / GPU thresholds
    (if ($S != null) and (($S.disk_root_pct // 0) >= $disk_warn)
     then {id:"disk", tier:"crit", text:("disk " + ($S.disk_root_pct|tostring) + "%"),
           hint:"claw doctor", src_ts:$sit_ts}
     else empty end),
    (if ($S != null) and (($S.gpu.temp // null) != null) and ($S.gpu.temp >= $gpu_warn)
     then {id:"gpu", tier:"crit", text:("gpu " + ($S.gpu.temp|tostring) + "°C"),
           hint:"nvidia-smi", src_ts:$sit_ts}
     else empty end),

    # crit — a machine that answered "down". `unknown` (off-LAN, no tailnet peer)
    # is NOT an outage and never becomes an item.
    (if $H == null then empty else
       ($H.machines // [])[] | select((.state // "") == "down")
       | {id:("machine:" + .id), tier:"crit", text:(.id + " down"), hint:"", src_ts:$hl_ts}
     end),

    # warn — a service that is not up on a machine that IS up (planned != broken)
    (if $H == null then empty else
       ($H.machines // [])[] | select((.state // "") == "up") as $m
       | ($m.services // [])[] | select((.state // "up") | (. != "up" and . != "planned"))
       | {id:("svc:" + $m.id + ":" + .id), tier:"warn", text:(.id + " on " + $m.id),
          hint:(.detail // ""), src_ts:$hl_ts}
     end),

    # warn — a package manager that could not be read at all
    (if ($U != null) and (($U.brew_err // null) != null) and (($U.brew_err|tostring) != "")
     then {id:"brew", tier:"warn", text:("brew ✗ " + ($U.brew_err|tostring)),
           hint:(if ($U.brew_err|tostring) == "xcode-license"
                 then "sudo xcodebuild -license" else "claw update --packages" end),
           src_ts:$upd_ts}
     else empty end),
    (if ($U != null) and (($U.apt_err // null) != null) and (($U.apt_err|tostring) != "")
     then {id:"apt", tier:"warn", text:("apt ✗ " + ($U.apt_err|tostring)),
           hint:"claw update --packages", src_ts:$upd_ts}
     else empty end),

    # warn — sustained load
    (if ($S != null) and (($S.load.load1 // null) != null) and (($S.load.ncpu // 0) > 0)
        and ((($S.load.load1) / ($S.load.ncpu)) >= $load_warn)
     then {id:"load", tier:"warn",
           text:("load " + ($S.load.load1|tostring) + " on " + ($S.load.ncpu|tostring) + " cores"),
           hint:"btop", src_ts:$sit_ts}
     else empty end),

    # warn — a stale source: one warn row, and none of its items
    (if $sit_stale then {id:"stale:situation", tier:"warn",
        text:("situation stale " + ageword($now - $sit_ts)),
        hint:"claw situation probe", src_ts:$sit_ts} else empty end),
    (if $hl_stale then {id:"stale:homelab", tier:"warn",
        text:("homelab stale " + ageword($now - $hl_ts)),
        hint:"claw situation homelab --force", src_ts:$hl_ts} else empty end),
    (if $upd_stale then {id:"stale:updates", tier:"warn",
        text:("updates stale " + ageword($now - $upd_ts)),
        hint:"claw update", src_ts:$upd_ts} else empty end),
    (if $loc_stale then {id:"stale:local", tier:"warn",
        text:("local stale " + ageword($now - $loc_ts)),
        hint:"claw situation local --force", src_ts:$loc_ts} else empty end),

    # info — the repo fell behind, or packages are pending
    (((if $U != null then ($U.repo_behind // 0)
       elif $S != null then ($S.updates.repo_behind // 0) else 0 end) // 0) as $rb
     | if (($rb|type) == "number") and ($rb > 0)
       then {id:"repo", tier:"info", text:("dotfiles ↓" + ($rb|tostring)),
             hint:"claw update", src_ts:($upd_ts // $sit_ts)}
       else empty end),
    ((if $U == null then 0 else (($U.brew // 0) + ($U.apt // 0)) end) as $pk
     | if $pk > 0
       then {id:"pkg", tier:"info", text:(($pk|tostring) + " pkg pending"),
             hint:"claw update", src_ts:$upd_ts}
       else empty end)
  ]
  | map(if ($acks[.id] // null) != null then (. + {tier:"info", hint:"acked"}) else . end)
  | map(. + {since: ($was[.id] // $now)})
  | sort_by((if .tier == "crit" then 0 elif .tier == "warn" then 1 else 2 end), .since)
 ) as $items
| { v: 1,
    checked: { situation: $sit_ts, homelab: $hl_ts, updates: $upd_ts, local: $loc_ts },
    items: $items }
'

cmd_evaluate() {
    have jq || return 0
    mkdir -p "$CACHE_DIR" 2>/dev/null

    local now ttl_sit tmp
    now="$(date +%s)"
    ttl_sit="$(_ttl_situation)"
    tmp="$(mktemp "${CACHE_DIR}/.att.XXXXXX")" || return 1

    if ! jq -n \
        --argjson now      "$now" \
        --argjson sit      "$(_cache_json "$SNAP")" \
        --argjson hl       "$(_cache_json "$HOMELAB_SNAP")" \
        --argjson upd      "$(_cache_json "$UPDATES_SNAP")" \
        --argjson loc      "$(_cache_json "$LOCAL_SNAP")" \
        --argjson prev     "$(_cache_json "$ATTN_JSON")" \
        --argjson acks     "$(_acks_json)" \
        --argjson sit_ts   "$(_cache_mtime_json "$SNAP")" \
        --argjson hl_ts    "$(_cache_mtime_json "$HOMELAB_SNAP")" \
        --argjson upd_ts   "$(_cache_mtime_json "$UPDATES_SNAP")" \
        --argjson loc_ts   "$(_cache_mtime_json "$LOCAL_SNAP")" \
        --argjson ttl_sit  "$ttl_sit" \
        --argjson ttl_hl   "$CLAW_TTL_HOMELAB" \
        --argjson ttl_upd  "$CLAW_TTL_UPDATES" \
        --argjson ttl_loc  "$CLAW_TTL_LOCAL" \
        --argjson disk_warn "$DISK_WARN_PCT" \
        --argjson gpu_warn  "$GPU_TEMP_WARN" \
        --argjson load_warn "$LOAD_WARN_X" \
        "$_ATTN_JQ" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"; return 1
    fi
    mv -f "$tmp" "$ATTN_JSON"

    # tsv — the zsh-readable view the login strip reads with `read`; acked rows out
    local ttmp; ttmp="$(mktemp "${CACHE_DIR}/.att.XXXXXX")" || return 1
    jq -r '.items[] | select(.hint != "acked")
           | [.tier, .id, .text, (.hint // ""), (.since|tostring), ((.src_ts // 0)|tostring)]
           | @tsv' "$ATTN_JSON" > "$ttmp" 2>/dev/null || : > "$ttmp"
    mv -f "$ttmp" "$ATTN_TSV"

    # count — one line for the p10k segment, fork-free to read with $(<file)
    local n worst ctmp
    n="$(jq -r '[.items[] | select(.hint != "acked") | select(.tier == "crit" or .tier == "warn")] | length' "$ATTN_JSON" 2>/dev/null)"
    : "${n:=0}"
    worst="$(jq -r '[.items[] | select(.hint != "acked") | .tier]
                    | if index("crit") then "crit" elif index("warn") then "warn" else "ok" end' \
             "$ATTN_JSON" 2>/dev/null)"
    : "${worst:=ok}"
    [ "$n" = 0 ] && worst="ok"
    ctmp="$(mktemp "${CACHE_DIR}/.att.XXXXXX")" || return 1
    printf '%s %s\n' "$n" "$worst" > "$ctmp"
    mv -f "$ctmp" "$ATTN_COUNT"
    return 0
}


# ── Local: SHELL-LOCAL slow state (the context row) ────────────────────────
# Things counts, the newest handoff note, dirty repos, worktrees and live
# claude sessions. Every probe is independently guarded: a box without
# sqlite3/git/pgrep, or without a Things DB, writes null for that key and
# still lands a valid document. Throttled on the snapshot's own mtime so the
# login kick is free to fire from every new tab.
_local_json() {
    local ts things_json handoff_json
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Things 3 — read-only over the group-container DB; immutable=1 so a live
    # Things never sees a reader and a background job never trips its locking.
    things_json=null
    if have sqlite3; then
        local tdb=""
        tdb="$(ls -1d "$HOME/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-"*"/Things Database.thingsdatabase/main.sqlite" 2>/dev/null | head -1)"
        if [ -n "$tdb" ] && [ -r "$tdb" ]; then
            local t_today t_inbox
            t_today="$(timeout 5 sqlite3 -readonly "file:${tdb}?immutable=1" \
                'select count(*) from TMTask where status=0 and trashed=0 and start=1 and startDate is not null' 2>/dev/null)"
            t_inbox="$(timeout 5 sqlite3 -readonly "file:${tdb}?immutable=1" \
                'select count(*) from TMTask where status=0 and trashed=0 and start=0 and project is null and heading is null' 2>/dev/null)"
            t_today="$(num_or_null "$t_today")"; t_inbox="$(num_or_null "$t_inbox")"
            if [ "$t_today" != null ] || [ "$t_inbox" != null ]; then
                things_json="{\"today\": ${t_today}, \"inbox\": ${t_inbox}}"
            fi
        fi
    fi

    # Newest handoff: the vault inbox first, the repo's remember note as the
    # fallback for a box with no vault checked out.
    handoff_json=null
    local vault hf=""
    # Same resolution order as shell/obsidian.zsh — one vault, one answer.
    vault="${VAULT_PATH:-${OBSIDIAN_VAULT:-${OBSIDIAN_ROOT:-$HOME}/${OBSIDIAN_VAULT_NAME:-hr-vault-main-pa}}}"
    hf="$(ls -1t "$vault/00-Inbox/"*handoff*.md "$vault/_wip/"*handoff*.md 2>/dev/null | head -1)"
    if [ -z "$hf" ] && [ -r "$DOTFILES/.remember/remember.md" ]; then hf="$DOTFILES/.remember/remember.md"; fi
    if [ -n "$hf" ] && [ -r "$hf" ]; then
        local title age
        title="$(grep -m1 '^# ' "$hf" 2>/dev/null | sed 's/^#[[:space:]]*//')"
        [ -n "$title" ] || title="$(basename "$hf" .md)"
        age="$(file_age "$hf")"
        handoff_json="{\"title\": \"$(_hl_json_str "$title")\", \"path\": \"$(_hl_json_str "$hf")\", \"age_s\": ${age}}"
    fi

    # Dirty repos across the two checkout roots. Capped and timeout-bounded:
    # a stalled network mount must not hold the login kick open.
    local dirty=0 total=0 nsample=0 sample_json="" d st name
    if have git; then
        for d in "$HOME"/Github/*/ "$HOME"/Github/Github_desktop/*/; do
            [ -e "$d/.git" ] || continue
            [ "$total" -ge 120 ] && break
            total=$((total+1))
            st="$(timeout 20 git -C "$d" status --porcelain 2>/dev/null | head -1)"
            if [ -n "$st" ]; then
                dirty=$((dirty+1))
                if [ "$nsample" -lt 3 ]; then
                    name="$(basename "${d%/}")"
                    [ -n "$sample_json" ] && sample_json="${sample_json},"
                    sample_json="${sample_json}\"$(_hl_json_str "$name")\""
                    nsample=$((nsample+1))
                fi
            fi
        done
    fi

    local wt=null cs=null
    if have git && [ -e "$DOTFILES/.git" ]; then
        wt="$(num_or_null "$(git -C "$DOTFILES" worktree list 2>/dev/null | grep -c .)")"
    fi
    # BSD pgrep has no -c, so count the pids (and never let 0 matches look like an error)
    if have pgrep; then
        cs="$(num_or_null "$(pgrep -f 'claude( |$)' 2>/dev/null | grep -c . || true)")"
    fi

    cat <<EOF
{
  "ts": "$ts",
  "things": ${things_json},
  "handoff": ${handoff_json},
  "repos": { "dirty": ${dirty}, "total": ${total}, "sample": [${sample_json}] },
  "worktrees": ${wt},
  "claude_sessions": ${cs},
  "cwd_repo": null
}
EOF
}

cmd_local() {
    local force=0
    [ "${1:-}" = "--force" ] && force=1
    if [ "$force" = 0 ] && [ -f "$LOCAL_SNAP" ] \
       && [ "$(file_age "$LOCAL_SNAP")" -lt "$CLAW_LOCAL_THROTTLE" ]; then
        return 0
    fi
    local tmp; tmp="$(mktemp "${CACHE_DIR}/.loc.XXXXXX")" || return 1
    if _local_json >"$tmp" 2>/dev/null; then mv -f "$tmp" "$LOCAL_SNAP"; else rm -f "$tmp"; return 1; fi
    cmd_evaluate || true
    return 0
}

# ── Tick: probe, evaluate, fire interrupts on TRANSITIONS only ─────────────
# The seven hand-rolled per-field transitions this used to carry are gone: the
# rule table lives in cmd_evaluate, and tick is now a generic diff of the
# evaluated item ids. Adding a rule means editing _ATTN_JQ and nothing else.
#   appeared crit/warn (or the repo-behind info item) -> notify
#   a crit that vanished entirely                     -> notify info "<id> back"
# Acked ids stay in attention.json as info, so acking is silent in both directions.
cmd_tick() {
    if [ -f "$ATTN_JSON" ]; then cp -f "$ATTN_JSON" "$ATTN_PREV"
    else printf '{"v":1,"items":[]}\n' > "$ATTN_PREV" 2>/dev/null || true; fi

    cmd_probe || return 1
    cmd_homelab_poll || true     # keep homelab.json fresh on the same timer (throttled)
    cmd_evaluate || return 0
    have jq || return 0          # diff needs jq; degraded mode just refreshes the caches
    [ -f "$ATTN_JSON" ] && [ -f "$ATTN_PREV" ] || return 0

    local appeared cleared tier id text hint
    appeared="$(jq -r --slurpfile p "$ATTN_PREV" '
        (($p[0].items // []) | map(select(.tier == "crit" or .tier == "warn" or .id == "repo")) | map(.id)) as $was
        | .items[]
        | select(.tier == "crit" or .tier == "warn" or .id == "repo")
        | . as $i | select(($was | index($i.id)) == null)
        | [.tier, .id, .text, (.hint // "")] | @tsv' "$ATTN_JSON" 2>/dev/null)"

    while IFS="$(printf '\t')" read -r tier id text hint; do
        [ -n "${id:-}" ] || continue
        # UPDATES_NOTIFY still gates the repo-behind item, as it always did
        [ "$id" = repo ] && [ "$UPDATES_NOTIFY" = off ] && continue
        # The alert log is user-visible history, so ids that had a hand-rolled
        # title before the generic diff keep it (tests/update-status.bats asserts
        # the repo-behind wording). Everything else notifies as "<text>" / "<hint>".
        case "$id" in repo) hint="${text} — run: ${hint:-claw update}"; text="Dotfiles behind" ;; esac
        if [ "$tier" = crit ]; then notify crit "$text" "${hint:-}"
        else                        notify info "$text" "${hint:-}"; fi
    done <<EOF
$appeared
EOF

    cleared="$(jq -r --slurpfile c "$ATTN_JSON" '
        (($c[0].items // []) | map(.id)) as $now
        | (.items // [])[] | select(.tier == "crit")
        | . as $i | select(($now | index($i.id)) == null) | [.id, .text] | @tsv' "$ATTN_PREV" 2>/dev/null)"

    while IFS="$(printf '\t')" read -r id text; do
        [ -n "${id:-}" ] || continue
        notify info "$id back" "was: ${text:-$id}"
    done <<EOF
$cleared
EOF

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
          + (if ((.updates.brew // null) != null or (.updates.apt // null) != null)
             then "  updates:" + (((.updates.brew // 0) + (.updates.apt // 0))|tostring) else "" end)
          + (if (.updates.repo_behind // 0) > 0 then "  repo:↓" + (.updates.repo_behind|tostring) else "" end)
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

# ── Schedule a one-shot review at a specific local datetime ─────────────────
# Linux → systemd --user timer (OnCalendar). macOS → launchd LaunchAgent with a
# StartCalendarInterval (month/day/hour/minute) that runs `review` then unloads
# + deletes itself so it fires exactly once. Parity: this used to hard-fail on
# MBP with "systemctl required".
cmd_schedule_review() {
    local d="${1:-}" t="${2:-09:00}"
    [ -z "$d" ] && { echo "usage: situation schedule-review <YYYY-MM-DD> [HH:MM]"; return 1; }
    local hh="${t%%:*}" mm="${t#*:}"

    if have launchctl && [ "$(uname -s)" = Darwin ]; then
        # Parse YYYY-MM-DD → month/day for StartCalendarInterval (no year field
        # in launchd; the self-unload below makes it a genuine one-shot anyway).
        local mo dd
        mo="$(printf '%s' "$d" | cut -d- -f2 | sed 's/^0*//')"; : "${mo:=1}"
        dd="$(printf '%s' "$d" | cut -d- -f3 | sed 's/^0*//')"; : "${dd:=1}"
        hh="$(printf '%s' "$hh" | sed 's/^0*//')"; : "${hh:=0}"
        mm="$(printf '%s' "$mm" | sed 's/^0*//')"; : "${mm:=0}"
        local plist="$HOME/Library/LaunchAgents/com.openclaw.situation-review.plist"
        mkdir -p "$HOME/Library/LaunchAgents"
        cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.openclaw.situation-review</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-lc</string>
        <string>"\$HOME/.dotfiles/scripts/utils/situation.sh" review; launchctl unload "$plist" 2>/dev/null; rm -f "$plist"</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Month</key><integer>${mo}</integer>
        <key>Day</key><integer>${dd}</integer>
        <key>Hour</key><integer>${hh}</integer>
        <key>Minute</key><integer>${mm}</integer>
    </dict>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
    <key>StandardOutPath</key><string>/dev/null</string>
    <key>StandardErrorPath</key><string>/dev/null</string>
</dict>
</plist>
EOF
        launchctl unload "$plist" 2>/dev/null || true
        launchctl load "$plist" || return 1
        echo "✓ review scheduled for ${d} ${t} (local); runs 'situation review' once (launchd, self-removing)"
        return 0
    fi

    have systemctl || { echo "no timer scheduler found — need launchctl (macOS) or systemctl (Linux)"; return 1; }
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
    homelab|fleet)    shift; cmd_homelab_poll "$@" ;;
    local)            shift; cmd_local "$@" ;;
    evaluate|attention) cmd_evaluate ;;
    help|-h|--help)
        sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "usage: situation {probe|tick|show [--json]|alerts|homelab [--force]|local [--force]|evaluate|install|uninstall}"; exit 1 ;;
esac
