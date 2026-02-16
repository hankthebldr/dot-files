#!/usr/bin/env bash
# scripts/install/packages/dev-tools.sh
# Install development languages and tools

source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/detect-os.sh"

install_dev_tools() {
    log_info "Installing development tools..."
    detect_os

    # Node.js (via fnm or nvm recommended, but using pkg manager for base)
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        brew install node go rust python3
        
        # Package managers / Version managers
        brew install fnm pyenv
    elif [[ "$PKG_MANAGER" == "apt" ]]; then
        sudo apt install -y nodejs golang python3 python3-pip
    fi
    
    # Atuin (as requested in optimizations)
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        if ! command -v atuin &>/dev/null; then
            log_info "Installing Atuin..."
            brew install atuin
        fi
    else
        # Install via script if not brew
        if ! command -v atuin &>/dev/null; then
             bash <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)
        fi
    fi
}

install_dev_tools
