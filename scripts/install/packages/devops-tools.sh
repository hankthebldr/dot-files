#!/usr/bin/env bash
# scripts/install/packages/devops-tools.sh
# Lightweight DevOps essentials for the bootstrap "full" path.
# Heavy lifting (HashiCorp/k8s.io APT, GitHub releases) lives in
# scripts/install/devops-toolchain.sh — invoked explicitly via
# `claw install devops`.

source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/detect-os.sh"

install_devops_tools() {
    log_info "Installing DevOps essentials..."
    detect_os

    case "$PKG_MANAGER" in
        brew)
            local brew_tools=(docker docker-compose kubectl helm k9s terraform ansible awscli azure-cli gh)
            for tool in "${brew_tools[@]}"; do
                brew list "$tool" &>/dev/null && { log_info "$tool already installed."; continue; }
                brew install "$tool" || log_warning "$tool install failed"
            done
            ;;
        apt)
            # Linuxbrew is the parity path. If present, use it for the same set as Mac.
            if command -v brew &>/dev/null; then
                log_info "Using Linuxbrew for DevOps essentials..."
                local brew_tools=(kubectl helm k9s terraform ansible awscli gh)
                # Skip docker (brew CLI-only on Linux) and azure-cli (uses MS repo)
                for tool in "${brew_tools[@]}"; do
                    brew list "$tool" &>/dev/null && { log_info "$tool already installed."; continue; }
                    brew install "$tool" || log_warning "$tool install failed"
                done
            else
                log_warning "Linuxbrew missing — only apt-native subset will install"
                log_info "Run: claw install devops    # full toolchain via vendor APT repos"
                sudo apt-get install -y docker.io docker-compose ansible 2>/dev/null || true
            fi
            ;;
        *)
            log_warning "Unknown package manager ($PKG_MANAGER); skipping DevOps essentials"
            ;;
    esac
}

install_devops_tools
