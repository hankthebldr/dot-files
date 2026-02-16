#!/usr/bin/env bash
# scripts/install/brew.sh
# Install Homebrew package manager

source "$(dirname "${BASH_SOURCE[0]}")/../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../utils/detect-os.sh"

install_brew() {
    detect_os
    
    if [[ "$OS_TYPE" == "macos" || "$OS_TYPE" == "linux-generic" ]]; then
        if ! command -v brew &>/dev/null; then
            log_info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            # Add to path for Linux
            if [[ "$OS_TYPE" != "macos" ]]; then
                eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            fi
        else
            log_success "Homebrew is already installed."
        fi
    else
        log_info "Skipping Homebrew install for $OS_TYPE (using native package manager)."
    fi
}

install_brew
