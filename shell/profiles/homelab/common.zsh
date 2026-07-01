# shell/profiles/homelab/common.zsh
# Cross-platform aliases / help for the BD790i homelab.
# Per-OS divergence (SSH wrappers vs native daemon control) lives in mac.zsh / linux.zsh.


# BD790i identity — override via env if hostname differs (e.g. Tailscale IP).
# Examples: BD790I_HOST=100.64.0.5  or  BD790I_HOST=bd790i.tail-scale.ts.net
export BD790I_HOST="${BD790I_HOST:-bd790i}"
export BD790I_USER="${BD790I_USER:-henry}"

# Where homelab YAML/Compose lives (Gitea repo paths, k3s manifests, etc.).
export HOMELAB_REPO="${HOMELAB_REPO:-$HOME/homelab}"

# ==========================================
# STATUS / DIAGNOSTICS
# ==========================================

# hstatus  — quick health pane of the homelab stack
# Renders 4 lines: tailscale · docker · k3s · ollama. Works in both
# native and remote modes via the per-OS helpers below.
hstatus() {
    local c_reset=$'\e[0m'
    local c_cyan=$'\e[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"$'m'
    local c_green=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    local c_red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    local c_amber=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    local c_dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local c_bold=$'\e[1m'

    # Cache-first: if the situation poller wrote a fresh homelab.json (<5min),
    # render the whole fleet from it (multi-machine). Else fall back to the live
    # single-host _hl_status_* probes.
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json"
    if [[ -r "$cache" ]] && command -v jq &> /dev/null; then
        local ts now then elapsed fresh=0
        ts=$(jq -r '.ts // ""' "$cache" 2>/dev/null)
        if [[ -n "$ts" && "$ts" != "null" ]]; then
            now=$(date -u +%s 2>/dev/null)
            then=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || date -u -d "$ts" +%s 2>/dev/null)
            [[ -n "$then" ]] && elapsed=$(( now - then )) && (( elapsed >= 0 && elapsed < 300 )) && fresh=1
        fi
        if (( fresh )); then
            local fleet; fleet=$(jq -r '.fleet // "HR-TRUST"' "$cache" 2>/dev/null)
            printf "\n  ${c_cyan}▸${c_reset} ${c_bold}%s fleet${c_reset}  ${c_dim}(cached %ss ago)${c_reset}\n\n" "$fleet" "${elapsed:-0}"
            # Detailed grouped board (Nodes/Cluster/DNS/Apps/Infra/Route) via the
            # shared renderer. SSH_CONNECTION is cleared: hstatus is an explicit
            # user command, so the renderer's login-safety guard doesn't apply.
            local _hb="${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils/homelab-board.sh"
            if [[ -x "$_hb" ]]; then
                local sect
                for sect in nodes cluster dns apps infra route; do
                    SSH_CONNECTION= command bash "$_hb" "$sect"
                done
                echo ""
                return 0
            fi
            # Fallback (renderer missing): flat per-machine service list.
            local dot
            jq -r '.machines[]? | "M\u0001\(.id)\u0001\(.state)", (.services[]? | "S\u0001\(.id)\u0001\(.state)\u0001\(.detail)")' "$cache" 2>/dev/null \
            | while IFS=$'\001' read -r kind a b c; do
                if [[ "$kind" == "M" ]]; then
                    [[ "$b" == "up" ]] && dot="${c_green}●${c_reset}" || dot="${c_red}●${c_reset}"
                    printf "  %s ${c_bold}%s${c_reset}\n" "$dot" "$a"
                else
                    case "$b" in up) dot="${c_green}●${c_reset}";; down) dot="${c_red}●${c_reset}";; *) dot="${c_amber}●${c_reset}";; esac
                    printf "      %s %-10s ${c_dim}%s${c_reset}\n" "$dot" "$a" "$c"
                fi
              done
            echo ""
            return 0
        fi
    fi

    # Live fallback (single host, on-demand probes).
    printf "\n  ${c_cyan}▸${c_reset} ${c_bold}BD790i homelab status${c_reset}  ${c_dim}(%s · live)${c_reset}\n\n" "$BD790I_HOST"
    if typeset -f _hl_status_tailscale &>/dev/null; then _hl_status_tailscale; else echo "  tailscale: (helper not loaded)"; fi
    if typeset -f _hl_status_docker    &>/dev/null; then _hl_status_docker;    else echo "  docker:    (helper not loaded)"; fi
    if typeset -f _hl_status_k3s       &>/dev/null; then _hl_status_k3s;       else echo "  k3s:       (helper not loaded)"; fi
    if typeset -f _hl_status_ollama    &>/dev/null; then _hl_status_ollama;    else echo "  ollama:    (helper not loaded)"; fi
    echo ""
}

# hsync  — sync the local homelab repo (manifests, compose files) and apply.
# Customize per your gitops setup; defaults assume the repo is a git checkout
# under $HOMELAB_REPO and changes apply via `kubectl apply -k .` from there.
hsync() {
    if [[ ! -d "$HOMELAB_REPO" ]]; then
        echo "no homelab repo at $HOMELAB_REPO — clone it first" >&2
        return 1
    fi
    (
        cd "$HOMELAB_REPO" || exit 1
        echo "▸ git pull"
        git pull --rebase 2>&1 | tail -5
        echo "▸ apply"
        if typeset -f _hl_apply_manifests &>/dev/null; then
            _hl_apply_manifests
        else
            kubectl apply -k . 2>&1 | tail -10
        fi
    )
}

# ==========================================
# K8S (delegates to per-OS variants)
# ==========================================

# halloc  — show node resource pressure (CPU/mem/pods used). Sanity check
# before deploying something hungry.
halloc() {
    if typeset -f _hl_kubectl &>/dev/null; then
        _hl_kubectl top nodes 2>/dev/null \
            || _hl_kubectl describe node | command grep -E "(Name:|cpu|memory|pods)" | head -20
    fi
}

# hpods [namespace]  — pods across namespaces, sorted by status
hpods() {
    local ns="${1:-}"
    if typeset -f _hl_kubectl &>/dev/null; then
        if [[ -n "$ns" ]]; then
            _hl_kubectl get pods -n "$ns" -o wide
        else
            _hl_kubectl get pods -A | head -40
        fi
    fi
}

# hlogs <pod> [namespace]  — tail logs from a pod (default ns=default)
hlogs() {
    local pod="${1:?usage: hlogs <pod-name> [ns]}"
    local ns="${2:-default}"
    if typeset -f _hl_kubectl &>/dev/null; then
        _hl_kubectl logs -f -n "$ns" "$pod"
    fi
}

# ==========================================
# OLLAMA (delegates to per-OS variants)
# ==========================================

# ollist  — list local models on the BD790i
ollist() {
    if typeset -f _hl_ollama &>/dev/null; then
        _hl_ollama list
    fi
}

# olchat <model>  — start a chat with a model on the BD790i
olchat() {
    local model="${1:?usage: olchat <model>}"
    if typeset -f _hl_ollama &>/dev/null; then
        _hl_ollama run "$model"
    fi
}

# olpull <model>  — pull a new model to the BD790i
olpull() {
    local model="${1:?usage: olpull <model>}"
    if typeset -f _hl_ollama &>/dev/null; then
        _hl_ollama pull "$model"
    fi
}

# ==========================================
# HELP
# ==========================================

homelab-help() {
    cat <<EOF
HOMELAB profile — RACK-WIZARD (Tier 6: hardware & ops)

  identity:  BD790I_HOST=$BD790I_HOST  ·  BD790I_USER=$BD790I_USER

  ── overview ─────────────────────────
  hstatus              tailscale · docker · k3s · ollama health pane
  hsync                pull \$HOMELAB_REPO + apply manifests

  ── kubernetes ───────────────────────
  halloc               node resource pressure
  hpods [ns]           pods (sorted by status)
  hlogs <pod> [ns]     tail pod logs

  ── ollama ───────────────────────────
  ollist               local models
  olchat <model>       start a chat
  olpull <model>       pull a new model

  ── platform-specific (see mac.zsh / linux.zsh) ──
  hssh                 SSH into the BD790i (mac mode)
  hreboot              graceful reboot
  hssh-tunnel <ports>  set up local→bd790i forwards

  override BD790I_HOST in env to point at a Tailscale IP or other hostname
EOF
}
