#!/usr/bin/env bash
################################################################################
# ai-readiness.sh — verify the AI workstation stack is working as expected.
#
# Read-only by default. `--deep` additionally runs a GPU-in-container test
# (pulls a small CUDA image if not cached). Safe to run on this box now and on
# any future GPU node. Reports PASS / WARN / FAIL per check + a summary.
#
# Flags: --deep   run the container GPU passthrough test (== what K3s does)
#        --help
################################################################################
set -e
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "$DOTFILES_DIR/scripts/utils/logger.sh"
[[ -d "$HOME/.local/bin" ]] && PATH="$HOME/.local/bin:$PATH"
[[ -d /usr/local/cuda/bin ]] && PATH="/usr/local/cuda/bin:$PATH"

DEEP=false
for a in "$@"; do
    case $a in
        --deep) DEEP=true ;;
        --help|-h) awk 'NR==1&&/^#!/{next} /^####*$/{next} /^# /||/^#$/{sub(/^# ?/,"");print;next} NF==0{print"";next} {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    esac
done

PASS=0; WARN=0; FAIL=0
# NB: use $((x+1)) not ((x++)) — post-increment returns 0 on the first call,
# which `set -e` treats as a failure and aborts the script.
ok()   { printf '  \033[0;32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
warn() { printf '  \033[0;33m!\033[0m %s\n' "$*"; WARN=$((WARN+1)); }
bad()  { printf '  \033[0;31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }

log_info "── AI workstation readiness ──"

# 1. GPU + driver
if command -v nvidia-smi &>/dev/null && nvidia-smi -L &>/dev/null; then
    ok "GPU: $(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | head -1)"
else
    bad "no GPU visible (nvidia-smi) — driver/hardware issue"
fi

# 2. CUDA toolkit
if command -v nvcc &>/dev/null; then
    ok "CUDA toolkit: $(nvcc --version | grep -o 'release [0-9.]*' | head -1)"
else
    warn "nvcc not on PATH — needed only to build CUDA code locally (containers ship their own)"
fi

# 3. Docker nvidia runtime + CDI
if command -v docker &>/dev/null; then
    if docker info 2>/dev/null | grep -qi 'Runtimes:.*nvidia'; then
        ok "docker nvidia runtime registered"
    else
        bad "docker present but nvidia runtime NOT registered (run: sudo nvidia-ctk runtime configure --runtime=docker)"
    fi
    docker info 2>/dev/null | grep -qi 'cdi: nvidia.com/gpu' \
        && ok "CDI GPU devices exposed (k8s device-plugin path)" \
        || warn "no CDI GPU devices in docker info"
else
    warn "docker not installed (needed for OpenShell sandboxes + on-cluster serving)"
fi

# 4. Deep: GPU inside a container (the exact K3s mechanism)
if [[ "$DEEP" == "true" ]] && command -v docker &>/dev/null; then
    img="nvidia/cuda:12.6.0-base-ubuntu24.04"
    log_info "deep: running nvidia-smi inside $img ..."
    if docker run --rm --gpus all "$img" nvidia-smi -L &>/dev/null; then
        ok "container GPU passthrough works"
    else
        bad "container GPU passthrough FAILED — K3s GPU scheduling would not work here"
    fi
fi

# 5. Inference stack
command -v vllm   &>/dev/null && ok "vLLM: $(vllm --version 2>&1 | head -1)" || warn "vLLM not installed (claw install ai-workstation --inference-only)"
command -v ollama &>/dev/null && ok "ollama present" || warn "ollama not installed"
[[ -x "$DOTFILES_DIR/config/ai/serve-nemotron-omni.sh" ]] && ok "Nemotron launcher present" || warn "Nemotron launcher missing/not executable"

# 6. Agentic runtime
if command -v openshell &>/dev/null; then
    ok "OpenShell: $(openshell --version 2>&1 | head -1)"
    openshell doctor check &>/dev/null && ok "openshell doctor check passed" || warn "openshell doctor check reported issues"
    if openshell gateway list 2>/dev/null | grep -qiE 'https?://|ssh://'; then
        ok "OpenShell gateway registered"
    else
        warn "no OpenShell gateway yet — register one: claw gateway register ssh://user@homelab:PORT"
    fi
else
    warn "openshell not installed (claw install ai-workstation --agentic-only)"
fi

# 7. K3s / cluster (only meaningful once joined)
if command -v kubectl &>/dev/null; then
    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    if kubectl get nodes &>/dev/null; then
        ok "cluster reachable ($(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ') node/s)"
        gpu_cap=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.capacity.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | grep -c '[1-9]' || true)
        [[ "$gpu_cap" -gt 0 ]] && ok "GPU schedulable on $gpu_cap node/s (nvidia.com/gpu)" \
                              || warn "no node advertises nvidia.com/gpu yet (run: claw gpu --test on the server)"
    else
        warn "kubectl present but no cluster reachable — not joined yet (expected pre-SSH)"
    fi
else
    warn "kubectl not installed (claw install devops)"
fi

echo
printf '  \033[1mReadiness:\033[0m \033[0;32m%d pass\033[0m · \033[0;33m%d warn\033[0m · \033[0;31m%d fail\033[0m\n' "$PASS" "$WARN" "$FAIL"
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
