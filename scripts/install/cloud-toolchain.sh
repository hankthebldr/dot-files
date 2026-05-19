#!/usr/bin/env bash

################################################################################
# Cloud Toolchain Installer
# Description: AWS, GCP, Azure, K8s, and IaC security tooling.
# Cross-platform: macOS (brew) + Linux (Linuxbrew preferred; native cloud
# vendor repos as fallback for the SDKs that ship them).
################################################################################

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"
detect_os

log_info "── Cloud Toolchain install (OS: $OS_TYPE, pkg: $PKG_MANAGER) ──"

# Unified list — same logical tools, install path differs per OS
brew_tools=(
    awscli azure-cli google-cloud-sdk
    eksctl
    kubernetes-cli openshift-cli
    stern helm
    hashicorp/tap/terraform terragrunt
    aws-iam-authenticator
    k9s
    tfsec checkov
    falco kube-hunter
    jq
)

case "$PKG_MANAGER" in
    brew)
        brew tap hashicorp/tap 2>/dev/null || true
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
        if command -v brew &>/dev/null; then
            log_info "Linuxbrew detected — using brew for parity with Mac"
            brew tap hashicorp/tap 2>/dev/null || true
            for tool in "${brew_tools[@]}"; do
                if brew list "$tool" &>/dev/null; then
                    log_info "$tool already installed."
                else
                    log_info "Installing $tool via brew..."
                    brew install "$tool" || log_warning "Failed to install $tool"
                fi
            done
        else
            log_warning "Linuxbrew not found — falling back to vendor APT repos"
            sudo apt-get update -qq
            sudo apt-get install -y jq curl unzip ca-certificates apt-transport-https \
                gnupg lsb-release 2>/dev/null || true
            sudo install -m 0755 -d /etc/apt/keyrings

            # AWS CLI v2 (official zip — vendor recommends over apt)
            if ! command -v aws &>/dev/null; then
                log_info "Installing AWS CLI v2..."
                local arch; arch=$(uname -m)
                local awspkg="awscli-exe-linux-${arch}.zip"
                local tmp; tmp=$(mktemp -d)
                curl -fsSL "https://awscli.amazonaws.com/$awspkg" -o "$tmp/awscli.zip" \
                    && unzip -q "$tmp/awscli.zip" -d "$tmp" \
                    && sudo "$tmp/aws/install" --update \
                    || log_warning "AWS CLI install failed"
                rm -rf "$tmp"
            fi

            # Azure CLI (Microsoft APT repo)
            if ! command -v az &>/dev/null; then
                log_info "Installing Azure CLI via Microsoft APT repo..."
                curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
                    sudo gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | \
                    sudo tee /etc/apt/sources.list.d/azure-cli.list >/dev/null
                sudo apt-get update -qq && sudo apt-get install -y azure-cli \
                    || log_warning "azure-cli install failed"
            fi

            # gcloud (Google Cloud SDK APT repo)
            if ! command -v gcloud &>/dev/null; then
                log_info "Installing gcloud via Google Cloud APT repo..."
                curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
                    sudo gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg
                echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] \
https://packages.cloud.google.com/apt cloud-sdk main" | \
                    sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
                sudo apt-get update -qq && sudo apt-get install -y google-cloud-cli \
                    || log_warning "gcloud install failed"
            fi

            # HashiCorp APT (terraform; vault/consul/nomad covered in devops-toolchain)
            if ! command -v terraform &>/dev/null; then
                log_info "Installing terraform via HashiCorp APT..."
                curl -fsSL https://apt.releases.hashicorp.com/gpg | \
                    sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
                echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
                    sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
                sudo apt-get update -qq && sudo apt-get install -y terraform terragrunt \
                    || log_warning "terraform install failed"
            fi

            # kubectl
            if ! command -v kubectl &>/dev/null; then
                log_info "Installing kubectl..."
                curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | \
                    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
                echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | \
                    sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
                sudo apt-get update -qq && sudo apt-get install -y kubectl \
                    || log_warning "kubectl install failed"
            fi

            # Helm
            if ! command -v helm &>/dev/null; then
                log_info "Installing helm..."
                curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
                    || log_warning "helm install failed"
            fi

            # Falco (official falcosecurity APT)
            if ! command -v falco &>/dev/null; then
                log_info "Installing falco via falcosecurity APT..."
                curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | \
                    sudo gpg --dearmor -o /etc/apt/keyrings/falco-archive-keyring.gpg
                echo "deb [signed-by=/etc/apt/keyrings/falco-archive-keyring.gpg] \
https://download.falco.org/packages/deb stable main" | \
                    sudo tee /etc/apt/sources.list.d/falcosecurity.list >/dev/null
                sudo apt-get update -qq && sudo apt-get install -y falco \
                    || log_warning "falco install failed (kernel module / eBPF setup may need attention)"
            fi

            # Python-based: tfsec → use Aqua install script; checkov + kube-hunter via pipx
            command -v pipx &>/dev/null || sudo apt-get install -y pipx || python3 -m pip install --user pipx
            if command -v pipx &>/dev/null; then
                pipx ensurepath
                for ptool in checkov kube-hunter; do
                    log_info "Installing $ptool via pipx..."
                    pipx install "$ptool" 2>/dev/null || pipx upgrade "$ptool" 2>/dev/null \
                        || log_warning "$ptool pipx install failed"
                done
            fi

            if ! command -v tfsec &>/dev/null; then
                log_info "Installing tfsec via aquasecurity script..."
                curl -fsSL https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash \
                    || log_warning "tfsec install failed"
            fi

            # k9s + stern + eksctl + aws-iam-authenticator from GitHub releases.
            # Defer to a small helper to keep this script readable.
            install_release_bin() {
                local tool="$1" url="$2"
                command -v "$tool" &>/dev/null && { log_info "$tool already installed."; return 0; }
                log_info "Installing $tool from $url..."
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
            local arch; arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
            install_release_bin k9s     "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${arch}.tar.gz"
            install_release_bin stern   "https://github.com/stern/stern/releases/latest/download/stern_$(curl -fsSL https://api.github.com/repos/stern/stern/releases/latest | grep tag_name | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')_linux_${arch}.tar.gz"
            install_release_bin eksctl  "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_${arch}.tar.gz"
            install_release_bin aws-iam-authenticator "https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/latest/download/aws-iam-authenticator_$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/aws-iam-authenticator/releases/latest | grep tag_name | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')_linux_${arch}"

            # openshift-cli (oc) — Red Hat mirror
            if ! command -v oc &>/dev/null; then
                log_info "Installing openshift-cli (oc)..."
                local tmp; tmp=$(mktemp -d)
                curl -fsSL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz" -o "$tmp/oc.tgz" \
                    && tar -C "$tmp" -xzf "$tmp/oc.tgz" \
                    && sudo install -m 0755 "$tmp/oc" /usr/local/bin/oc \
                    || log_warning "oc install failed"
                rm -rf "$tmp"
            fi
        fi
        ;;
    *)
        log_warning "Unknown package manager ($PKG_MANAGER); install Cloud tools manually"
        ;;
esac

log_success "Cloud Toolchain install complete."
