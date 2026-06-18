#!/usr/bin/env bash
################################################################################
# openshell-gateway.sh — bring up / manage the OpenShell gateway (Phase 2).
#
# OpenShell's `sandbox` and `policy` commands are no-ops without an active
# GATEWAY (the control plane). The CLI only *registers* a gateway endpoint
# (`gateway add/select`) — the gateway itself runs as a server (locally, or on
# the homelab K3s cluster via Helm so sandboxes land on the Blackwell GPU node).
#
# Subcommands:
#   check                      openshell doctor check (Docker/host prereqs)   [verified]
#   register <endpoint> [name] gateway add <endpoint> + gateway select        [verified]
#   status                     list gateways + sandboxes                      [verified]
#   sandbox [args…]            passthrough; defaults --policy to the repo template
#   deploy-cluster             helm install on K3s  [⚠ VERIFY chart values vs docs]
#
# Flags: --dry-run, --help
# Docs:  https://docs.nvidia.com/openshell/latest/
################################################################################
set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "$DOTFILES_DIR/scripts/utils/logger.sh"

# Managed channel is the unconfined uv-tool install under ~/.local/bin. The
# NVIDIA snap can't reach an apt docker-ce socket (no docker-snap slot to bind
# openshell:docker), so it fails `doctor check` here — uv-tool is the one that
# works. Ensure ~/.local/bin is findable if no openshell is on PATH yet.
command -v openshell &>/dev/null || { [[ -d "$HOME/.local/bin" ]] && PATH="$HOME/.local/bin:$PATH"; }

POLICY="$DOTFILES_DIR/config/agentic/openshell/policy.yaml"
DRY_RUN=false
ARGS=()
for a in "$@"; do
    case $a in
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            awk 'NR==1&&/^#!/{next} /^####*$/{next} /^# /||/^#$/{sub(/^# ?/,"");print;next} NF==0{print"";next} {exit}' \
                "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) ARGS+=("$a") ;;
    esac
done
set -- "${ARGS[@]}"

run() { if [[ "$DRY_RUN" == "true" ]]; then printf '  [DRY] %s\n' "$*"; else eval "$@"; fi; }

if ! command -v openshell &>/dev/null; then
    log_error "openshell not found — install it first:"
    log_error "  bash $DOTFILES_DIR/scripts/install/ai-workstation-toolchain.sh --agentic-only"
    exit 1
fi

cmd="${1:-status}"; shift || true

case "$cmd" in
    check)
        run "openshell doctor check"
        ;;
    register)
        endpoint="${1:?usage: openshell-gateway.sh register <endpoint> [name]}"
        name="${2:-homelab}"
        log_info "Registering gateway '$name' → $endpoint"
        run "openshell gateway add '$endpoint'"
        run "openshell gateway select '$name'"
        run "openshell sandbox list"   # confirms the gateway answers
        log_success "Gateway registered. Persist it: echo 'OPENSHELL_GATEWAY=$name' >> ~/.dotfiles/.env"
        ;;
    status)
        run "openshell gateway list"
        run "openshell sandbox list || true"
        ;;
    sandbox)
        # Passthrough; inject the repo policy for `create` unless caller set one.
        if [[ "${1:-}" == "create" && "$*" != *"--policy"* ]]; then
            shift
            run "openshell sandbox create --gpu --policy '$POLICY' $* "
        else
            run "openshell sandbox $*"
        fi
        ;;
    deploy-cluster)
        log_warning "⚠ Gateway-on-K3s via Helm — VERIFY chart name/values against the docs"
        log_warning "  before trusting this in production. Reference command:"
        log_info  "  helm install openshell oci://ghcr.io/nvidia/openshell/helm-chart"
        log_info  "  Then: openshell-gateway.sh register https://<svc-or-ingress>:<port> homelab"
        ;;
    *)
        log_error "Unknown subcommand: $cmd (try: check | register | status | sandbox | deploy-cluster)"
        exit 1
        ;;
esac
