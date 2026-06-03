#!/usr/bin/env bash

################################################################################
# Homelab Toolchain Installer (Linux-only — BD790i target)
# Description: Installs the daemons the BD790i actually runs as Henry's homelab
# head: Tailscale (mesh), Docker (docker-ce), K3s (Kubernetes), Ollama (local
# LLMs). Prints next-step commands for Gitea + n8n (Helm or compose) so the
# operator picks the orchestration model.
#
# Flags:
#   --skip-tailscale   skip Tailscale install
#   --skip-docker      skip docker-ce install
#   --skip-k3s         skip K3s install
#   --skip-ollama      skip Ollama install
#   --dry-run          print actions only
#   --help
#
# K3s cluster join (make THIS box a GPU worker in an existing homelab cluster):
#   --agent                 install K3s as an agent/worker instead of a server
#   --server <url>          control-plane URL, e.g. https://homelab:6443  (K3S_URL)
#   --token  <tok>          node token  (K3S_TOKEN) — prefer --token-file
#   --token-file <path>     read the token from a file (keeps it out of ps/history)
#     Token source on the server: /var/lib/rancher/k3s/server/node-token
#     A detected NVIDIA GPU auto-labels the node `nvidia.com/gpu.present=true`.
################################################################################

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"

# ── Flags (parsed BEFORE OS gate so --help works on Mac too) ──
SKIP_TAILSCALE=false
SKIP_DOCKER=false
SKIP_K3S=false
SKIP_OLLAMA=false
DRY_RUN=false
K3S_MODE=server
K3S_SERVER_URL="${K3S_URL:-}"
K3S_NODE_TOKEN="${K3S_TOKEN:-}"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-tailscale) SKIP_TAILSCALE=true ;;
        --skip-docker)    SKIP_DOCKER=true ;;
        --skip-k3s)       SKIP_K3S=true ;;
        --skip-ollama)    SKIP_OLLAMA=true ;;
        --agent)          K3S_MODE=agent ;;
        --server)         K3S_SERVER_URL="$2"; shift ;;
        --token)          K3S_NODE_TOKEN="$2"; shift ;;
        --token-file)     [[ -f "$2" ]] || { log_error "token file not found: $2"; exit 1; }
                          K3S_NODE_TOKEN="$(< "$2")"; shift ;;
        --dry-run)        DRY_RUN=true ;;
        --help|-h)
            # Print the top doc-block: skip shebang + banner lines, print
            # comment bodies until the first non-comment line.
            awk '
                NR == 1 && /^#!/    { next }
                /^####*$/           { next }   # banner separators
                /^# / || /^#$/      { sub(/^# ?/, ""); print; next }
                NF == 0             { print ""; next }
                { exit }
            ' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) log_error "Unknown flag: $1"; exit 1 ;;
    esac
    shift
done

detect_os

# ── Gate: Linux only ─────────────────────────────────────
if [[ "$OS_TYPE" == "macos" ]]; then
    log_error "Homelab toolchain is Linux-only (target: BD790i)"
    log_info  "On macOS, use Docker Desktop + Tailscale.app + Orbstack/colima for K3s"
    exit 1
fi

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf '  [DRY] %s\n' "$*"
    else
        eval "$@"
    fi
}

log_info "── Homelab Toolchain (OS: $OS_TYPE) ──"

# ─────────────────────────────────────────────
# Tailscale — mesh networking. Must be on host (kernel module + tailscaled).
# ─────────────────────────────────────────────
install_tailscale() {
    [[ "$SKIP_TAILSCALE" == "true" ]] && { log_info "skip: tailscale"; return 0; }
    if command -v tailscale &>/dev/null; then
        log_info "tailscale already installed ($(tailscale version | head -1))"
        return 0
    fi
    log_info "Installing Tailscale via official APT repo..."
    run "curl -fsSL https://pkgs.tailscale.com/stable/${OS_TYPE}/$(lsb_release -cs).noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null"
    run "curl -fsSL https://pkgs.tailscale.com/stable/${OS_TYPE}/$(lsb_release -cs).tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list"
    run "sudo apt-get update -qq"
    run "sudo apt-get install -y tailscale"
    log_success "tailscale installed — run: ${0##*/} → then 'sudo tailscale up'"
}

# ─────────────────────────────────────────────
# Docker CE — needed for Gitea/n8n containers (even if K3s is primary).
# ─────────────────────────────────────────────
install_docker() {
    [[ "$SKIP_DOCKER" == "true" ]] && { log_info "skip: docker"; return 0; }
    if command -v docker &>/dev/null && docker --version 2>/dev/null | grep -q 'Docker version'; then
        log_info "docker already installed ($(docker --version))"
        return 0
    fi
    log_info "Installing Docker CE via official APT repo..."
    run "sudo install -m 0755 -d /etc/apt/keyrings"
    run "curl -fsSL https://download.docker.com/linux/${OS_TYPE}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    run "sudo chmod a+r /etc/apt/keyrings/docker.gpg"
    run "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_TYPE} \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null"
    run "sudo apt-get update -qq"
    run "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    run "sudo usermod -aG docker \$USER"
    log_success "docker installed — log out + back in for group membership to take effect"
}

# ─────────────────────────────────────────────
# K3s — lightweight Kubernetes. INSTALL_K3S_EXEC writes kubeconfig readable.
# ─────────────────────────────────────────────
install_k3s() {
    [[ "$SKIP_K3S" == "true" ]] && { log_info "skip: k3s"; return 0; }
    [[ "$K3S_MODE" == "agent" ]] && { install_k3s_agent; return $?; }

    # ── server (single-node control plane) ──
    if command -v k3s &>/dev/null && [[ -f /etc/rancher/k3s/k3s.yaml ]]; then
        log_info "k3s server already installed ($(k3s --version | head -1))"
        return 0
    fi
    log_info "Installing K3s (server)..."
    run "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--write-kubeconfig-mode=644' sh -"
    log_success "k3s installed — kubeconfig at /etc/rancher/k3s/k3s.yaml"
    log_info "Add to ~/.dotfiles/.env: KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    log_info "Join a GPU worker from another box:"
    log_info "  ${0##*/} --agent --server https://$(hostname -I 2>/dev/null | awk '{print $1}'):6443 --token-file /var/lib/rancher/k3s/server/node-token"
}

# ─────────────────────────────────────────────
# Join THIS box to an existing K3s server as a (GPU) agent/worker node.
# A detected NVIDIA GPU is auto-labelled so AI workloads can target it via
# nodeSelector/affinity (nvidia.com/gpu.present=true).
# ─────────────────────────────────────────────
install_k3s_agent() {
    # Agents register a k3s-agent systemd unit (no kubeconfig) — use that for idempotency.
    if systemctl list-unit-files 2>/dev/null | grep -q '^k3s-agent\.service'; then
        log_info "k3s-agent already installed on this node ($(k3s --version 2>/dev/null | head -1))"
        return 0
    fi
    if [[ -z "$K3S_SERVER_URL" || -z "$K3S_NODE_TOKEN" ]]; then
        log_error "agent join needs --server <https://host:6443> and --token / --token-file"
        log_info  "Token lives on the server at /var/lib/rancher/k3s/server/node-token"
        exit 1
    fi

    # Auto-label as a GPU node so AI workloads can schedule onto the Blackwell card.
    local exec_args=""
    if command -v nvidia-smi &>/dev/null && nvidia-smi -L &>/dev/null; then
        log_info "GPU detected ($(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)) — labelling nvidia.com/gpu.present=true"
        exec_args="--node-label nvidia.com/gpu.present=true"
    else
        log_warning "No GPU visible here — joining as a plain worker (no GPU label)."
    fi

    log_info "Joining $K3S_SERVER_URL as a K3s agent..."
    # Pass the token via the ENVIRONMENT (not the command string) so it never
    # lands in `ps`, shell history, or the --dry-run printout.
    if [[ "$DRY_RUN" == "true" ]]; then
        printf '  [DRY] curl -sfL https://get.k3s.io | K3S_URL=%s K3S_TOKEN=*** INSTALL_K3S_EXEC='\''agent %s'\'' sh -\n' \
            "$K3S_SERVER_URL" "$exec_args"
    else
        K3S_URL="$K3S_SERVER_URL" K3S_TOKEN="$K3S_NODE_TOKEN" INSTALL_K3S_EXEC="agent $exec_args" \
            sh -c 'curl -sfL https://get.k3s.io | sh -'
    fi
    log_success "k3s-agent joined. Verify FROM THE SERVER: kubectl get nodes -o wide"
    log_warning "Next — GPU passthrough on THIS node (configures nvidia containerd runtime):"
    log_warning "  bash $DOTFILES_DIR/scripts/install/ai-workstation-toolchain.sh --inference-only --skip-agentic --skip-data"
    log_warning "Then FROM THE SERVER apply the device plugin: kubectl apply -f config/k3s/gpu/"
}

# ─────────────────────────────────────────────
# Ollama — local LLM runtime. Backs the Hermes agent (per CLAUDE.md).
# ─────────────────────────────────────────────
install_ollama() {
    [[ "$SKIP_OLLAMA" == "true" ]] && { log_info "skip: ollama"; return 0; }
    if command -v ollama &>/dev/null; then
        log_info "ollama already installed ($(ollama --version | head -1))"
    else
        log_info "Installing Ollama..."
        run "curl -fsSL https://ollama.com/install.sh | sh"
    fi
    # Pull the model claw doctor checks for, matching the default in bin/claw:213
    local model="${CLAW_HERMES_MODEL:-hermes3:8b}"
    if command -v ollama &>/dev/null; then
        if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "$model"; then
            log_info "ollama model $model already present"
        else
            log_info "Pulling ollama model: $model"
            run "ollama pull '$model'" || log_warning "model pull failed (network or daemon issue)"
        fi
    fi
}

# ─────────────────────────────────────────────
# Next-step instructions for Gitea + n8n
# ─────────────────────────────────────────────
print_next_steps() {
    cat <<EOF

  ───────────────────────────────────────────────────────
  Homelab daemons installed. Next steps (not auto-run):
  ───────────────────────────────────────────────────────

  Tailscale:
    sudo tailscale up --ssh
    # then verify mesh: tailscale status

  Docker group:
    newgrp docker          # or log out + back in
    docker info            # should succeed without sudo

  K3s kubectl:
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    kubectl get nodes      # BD790i should be Ready

  Gitea (pick one):
    # K3s + Helm:
    helm repo add gitea-charts https://dl.gitea.com/charts/
    helm install gitea gitea-charts/gitea --namespace gitea --create-namespace
    # OR Docker compose:
    mkdir -p ~/.homelab/gitea && cd ~/.homelab/gitea
    # write docker-compose.yml from https://docs.gitea.com/installation/install-with-docker
    docker compose up -d

  n8n (pick one):
    # K3s + Helm:
    helm repo add open-source-labs https://open-source-labs.github.io/helm-charts
    helm install n8n open-source-labs/n8n --namespace n8n --create-namespace
    # OR Docker compose:
    docker run -d --restart unless-stopped --name n8n -p 5678:5678 \\
      -v ~/.n8n:/home/node/.n8n docker.n8n.io/n8nio/n8n

  Ollama / Hermes agent:
    claw doctor            # verifies hermes model + daemon
    ollama serve &         # if not already systemd-managed

EOF
}

# ── Main ─────────────────────────────────────────────────
install_tailscale
install_docker
install_k3s
install_ollama
print_next_steps

log_success "Homelab toolchain install complete."
