#!/usr/bin/env bash

################################################################################
# DevOps Toolchain Installer
# Description: CI/CD, container, IaC, observability, and HashiCorp tools.
# Cross-platform: macOS (brew) + Linux (Linuxbrew preferred, with HashiCorp +
# k8s.io APT repos as fallback when brew is missing).
################################################################################

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"
detect_os

log_info "── DevOps Toolchain install (OS: $OS_TYPE, pkg: $PKG_MANAGER) ──"

# ─────────────────────────────────────────────
# Tool list — same set on either OS, install path differs
# ─────────────────────────────────────────────
brew_tools=(
    gh docker podman buildah
    skaffold argocd
    helm fluxcd/tap/flux
    ansible
    terragrunt terraform
    kubernetes-cli
    stern jq shellcheck go-task
    vault consul nomad
    prometheus
)

case "$PKG_MANAGER" in
    brew)
        brew tap homebrew/core 2>/dev/null || true
        brew tap fluxcd/tap 2>/dev/null || true
        for tool in "${brew_tools[@]}"; do
            if brew list "$tool" &>/dev/null; then
                log_info "$tool already installed."
            else
                log_info "Installing $tool..."
                brew install "$tool" || log_warning "Failed to install $tool"
            fi
        done
        ;;
    apt)
        # ── Preferred Linux path: Linuxbrew (same package names as Mac) ──
        if command -v brew &>/dev/null; then
            log_info "Linuxbrew detected — using brew path for parity with Mac"
            brew tap fluxcd/tap 2>/dev/null || true
            # docker via brew on Linux is CLI-only — skip and let homelab-toolchain
            # install the docker-ce daemon from Docker's APT repo.
            for tool in "${brew_tools[@]}"; do
                [[ "$tool" == "docker" ]] && { log_info "skipping docker via brew (use homelab-toolchain for docker-ce)"; continue; }
                if brew list "$tool" &>/dev/null; then
                    log_info "$tool already installed."
                else
                    log_info "Installing $tool via brew..."
                    brew install "$tool" || log_warning "Failed to install $tool"
                fi
            done
        else
            # ── Native repos fallback (when Linuxbrew not available) ──
            log_warning "Linuxbrew not found — installing via apt + vendor repos"
            log_warning "Recommend: install Linuxbrew for full parity (see scripts/install/brew.sh)"
            sudo apt-get update -qq

            # apt-native subset
            apt_tools=(ansible jq shellcheck podman buildah)
            for tool in "${apt_tools[@]}"; do
                dpkg -s "$tool" &>/dev/null && { log_info "$tool already installed."; continue; }
                sudo apt-get install -y "$tool" 2>/dev/null || log_warning "$tool apt install failed"
            done

            # HashiCorp APT (terraform, vault, consul, nomad)
            if ! command -v terraform &>/dev/null; then
                log_info "Adding HashiCorp APT repo..."
                sudo install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://apt.releases.hashicorp.com/gpg | \
                    sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg
                echo "deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
                    sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
                sudo apt-get update -qq
                sudo apt-get install -y terraform vault consul nomad terragrunt \
                    || log_warning "HashiCorp tools install failed"
            fi

            # gh (GitHub CLI) — official APT repo
            if ! command -v gh &>/dev/null; then
                log_info "Adding GitHub CLI APT repo..."
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
                    sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" | \
                    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
                sudo apt-get update -qq
                sudo apt-get install -y gh || log_warning "gh install failed"
            fi

            # kubectl via official k8s.io APT repo
            if ! command -v kubectl &>/dev/null; then
                log_info "Installing kubectl via k8s.io APT repo..."
                curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | \
                    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
                echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | \
                    sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
                sudo apt-get update -qq
                sudo apt-get install -y kubectl || log_warning "kubectl install failed"
            fi

            # Helm — official install script (single binary)
            if ! command -v helm &>/dev/null; then
                log_info "Installing helm via official script..."
                curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
                    || log_warning "helm install failed"
            fi

            # Single-binary GitHub releases (best-effort: skip on cargo absence)
            install_github_release() {
                local tool="$1" repo="$2" pattern="$3"
                command -v "$tool" &>/dev/null && { log_info "$tool already installed."; return 0; }
                local arch; arch=$(uname -m)
                [[ "$arch" == "x86_64" ]] && arch="amd64"
                [[ "$arch" == "aarch64" ]] && arch="arm64"
                log_info "Installing $tool from $repo releases..."
                local url
                url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | \
                    grep -oE "\"browser_download_url\":\s*\"[^\"]*${pattern}[^\"]*\"" | \
                    head -1 | sed -E 's/.*"(https[^"]+)".*/\1/')
                [[ -z "$url" ]] && { log_warning "$tool: no matching release asset for $pattern"; return 1; }
                local tmp; tmp=$(mktemp -d)
                curl -fsSL "$url" -o "$tmp/asset"
                case "$url" in
                    *.tar.gz) tar -C "$tmp" -xzf "$tmp/asset" ;;
                    *.zip)    unzip -q -d "$tmp" "$tmp/asset" ;;
                esac
                local bin; bin=$(find "$tmp" -type f -name "$tool" -perm -u+x | head -1)
                [[ -z "$bin" ]] && bin="$tmp/asset"
                sudo install -m 0755 "$bin" "/usr/local/bin/$tool" && log_success "installed $tool"
                rm -rf "$tmp"
            }
            install_github_release stern stern/stern   "linux_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz"
            install_github_release flux  fluxcd/flux2  "linux_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz"
            install_github_release task  go-task/task  "linux_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz"
        fi
        ;;
    *)
        log_warning "Unknown package manager ($PKG_MANAGER); install DevOps tools manually"
        ;;
esac

log_success "DevOps Toolchain install complete."
