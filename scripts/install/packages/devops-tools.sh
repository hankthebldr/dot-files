#!/usr/bin/env bash
# scripts/install/packages/devops-tools.sh
# Install DevOps and Cloud tools

source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/detect-os.sh"

install_devops_tools() {
    log_info "Installing DevOps tools..."
    detect_os
    
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        brew install \
            docker \
            docker-compose \
            kubectl \
            helm \
            k9s \
            terraform \
            ansible \
            awscli \
            azure-cli \
            gh
    elif [[ "$PKG_MANAGER" == "apt" ]]; then
        # On Linux, these often need specific repos
        # Installing basics usually available
        sudo apt install -y docker.io docker-compose ansible
        # Others might need manual install scripts (skipping for complexity in MVP)
    fi
}

install_devops_tools
