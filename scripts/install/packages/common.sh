#!/usr/bin/env bash
# scripts/install/packages/common.sh
# Install essential cross-platform tools

source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/detect-os.sh"

PACKAGES=(
    git
    curl
    wget
    vim
    tmux
    zsh
    unzip
    tar
    tree
    stow
)

install_common() {
    log_info "Installing essential packages..."
    detect_os
    
    for pkg in "${PACKAGES[@]}"; do
        if command -v "$pkg" &>/dev/null; then
            log_success "$pkg is already installed."
            continue
        fi

        log_info "Installing $pkg..."
        case $PKG_MANAGER in
            brew) brew install "$pkg" ;;
            apt)  sudo apt install -y "$pkg" ;;
            dnf)  sudo dnf install -y "$pkg" ;;
            pacman) sudo pacman -S --noconfirm "$pkg" ;;
            *)    log_error "Unknown package manager: $PKG_MANAGER" ;;
        esac
    done
}

install_common
