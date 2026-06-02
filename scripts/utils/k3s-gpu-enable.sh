#!/usr/bin/env bash
################################################################################
# k3s-gpu-enable.sh — make GPU nodes schedulable (RUN FROM THE K3s SERVER).
#
# The agent-side runtime config lives elsewhere: a GPU worker joins via
#   scripts/install/homelab-toolchain.sh --agent --server … --token-file …
# (auto-labels nvidia.com/gpu.present=true), then configures its nvidia
# containerd runtime via
#   scripts/install/ai-workstation-toolchain.sh --inference-only --skip-agentic --skip-data
#
# THIS script is the server-side half: it applies the cluster-scoped RuntimeClass
# + device-plugin DaemonSet (from config/k3s/gpu/), optionally taints GPU nodes,
# and verifies that nvidia.com/gpu is advertised as a schedulable resource.
#
# Flags:
#   --test         after enabling, run a gpu-smoke-test pod and print nvidia-smi
#   --taint        taint GPU nodes nvidia.com/gpu=present:NoSchedule (dedicate
#                  them to GPU workloads; pods then need a matching toleration)
#   --kubeconfig <path>   default: /etc/rancher/k3s/k3s.yaml
#   --dry-run      print actions without executing
#   --help
################################################################################
set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "$DOTFILES_DIR/scripts/utils/logger.sh"

MANIFEST_DIR="$DOTFILES_DIR/config/k3s/gpu"
KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
RUN_TEST=false
DO_TAINT=false
DRY_RUN=false
GPU_LABEL="nvidia.com/gpu.present=true"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --test)       RUN_TEST=true ;;
        --taint)      DO_TAINT=true ;;
        --kubeconfig) KUBECONFIG_PATH="$2"; shift ;;
        --dry-run)    DRY_RUN=true ;;
        --help|-h)
            awk '
                NR == 1 && /^#!/ { next }
                /^####*$/        { next }
                /^# / || /^#$/   { sub(/^# ?/, ""); print; next }
                NF == 0          { print ""; next }
                { exit }
            ' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) log_error "Unknown flag: $1"; exit 1 ;;
    esac
    shift
done

run() {
    if [[ "$DRY_RUN" == "true" ]]; then printf '  [DRY] %s\n' "$*"; else eval "$@"; fi
}

export KUBECONFIG="$KUBECONFIG_PATH"

# ── Preflight ────────────────────────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
    log_error "kubectl not on PATH — install via 'claw install devops'."
    exit 1
fi
if [[ ! -f "$MANIFEST_DIR/nvidia-device-plugin.yaml" ]]; then
    log_error "Missing manifests under $MANIFEST_DIR (incomplete checkout?)."
    exit 1
fi
if [[ "$DRY_RUN" == "false" ]] && ! kubectl get nodes &>/dev/null; then
    log_error "Can't reach the cluster with KUBECONFIG=$KUBECONFIG_PATH."
    log_info  "Run this ON THE K3s SERVER, or pass --kubeconfig <path>."
    exit 1
fi

log_info "── K3s GPU enablement (server-side) · KUBECONFIG=$KUBECONFIG_PATH ──"

# ── 1. RuntimeClass + device plugin ──────────────────────────────────────────
log_info "Applying RuntimeClass + NVIDIA device plugin DaemonSet..."
run "kubectl apply -f '$MANIFEST_DIR/runtimeclass-nvidia.yaml'"
run "kubectl apply -f '$MANIFEST_DIR/nvidia-device-plugin.yaml'"
run "kubectl -n kube-system rollout status ds/nvidia-device-plugin-daemonset --timeout=120s"

# ── 2. GPU node discovery / taint ────────────────────────────────────────────
if [[ "$DRY_RUN" == "false" ]]; then
    mapfile -t gpu_nodes < <(kubectl get nodes -l "$GPU_LABEL" -o name 2>/dev/null)
    if [[ ${#gpu_nodes[@]} -eq 0 ]]; then
        log_warning "No nodes labelled '$GPU_LABEL' yet."
        log_warning "Join a GPU worker so it gets labelled:"
        log_warning "  homelab-toolchain.sh --agent --server https://$(hostname -s):6443 --token-file /var/lib/rancher/k3s/server/node-token"
    else
        log_success "GPU nodes: ${gpu_nodes[*]}"
    fi
fi

if [[ "$DO_TAINT" == "true" ]]; then
    log_info "Tainting GPU nodes (dedicate to GPU workloads; needs matching toleration)..."
    run "kubectl taint nodes -l '$GPU_LABEL' nvidia.com/gpu=present:NoSchedule --overwrite"
fi

# ── 3. Verify schedulable capacity ───────────────────────────────────────────
log_info "GPU capacity per node:"
run "kubectl get nodes -o custom-columns='NODE:.metadata.name,GPU:.status.capacity.nvidia\\.com/gpu' 2>/dev/null"

# ── 4. Optional smoke test ───────────────────────────────────────────────────
if [[ "$RUN_TEST" == "true" ]]; then
    log_info "Running gpu-smoke-test pod (nvidia-smi)..."
    run "kubectl delete pod gpu-smoke-test --ignore-not-found"
    run "kubectl apply -f '$MANIFEST_DIR/gpu-test-pod.yaml'"
    run "kubectl wait --for=condition=Ready pod/gpu-smoke-test --timeout=120s || true"
    run "kubectl logs gpu-smoke-test || true"
    run "kubectl delete pod gpu-smoke-test --ignore-not-found"
fi

log_success "Done. A GPU pod needs: runtimeClassName: nvidia + limits.nvidia.com/gpu: 1"
[[ "$DO_TAINT" == "true" ]] && log_info "Tainted: add a toleration for key nvidia.com/gpu."
