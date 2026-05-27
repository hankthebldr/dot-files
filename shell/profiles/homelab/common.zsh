# shell/profiles/homelab/common.zsh
# Cross-platform aliases / help for the BD790i homelab.
# Per-OS divergence (SSH wrappers vs native daemon control) lives in mac.zsh / linux.zsh.

export CLAW_PROFILE_THEME="homelab"

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
    printf "\n  \e[36m▸\e[0m \e[1mBD790i homelab status\e[0m  \e[2m(%s)\e[0m\n\n" "$BD790I_HOST"
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
            || _hl_kubectl describe node | grep -E "(Name:|cpu|memory|pods)" | head -20
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
