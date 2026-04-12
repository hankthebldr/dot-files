#!/usr/bin/env bash
# scripts/install/brew.sh
# Install Homebrew package manager

source "$(dirname "${BASH_SOURCE[0]}")/../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../utils/detect-os.sh"

install_brew() {
    detect_os

    if command -v brew &>/dev/null; then
        log_success "Homebrew is already installed."
        return 0
    fi

    case "$OS_TYPE" in
        macos)
            log_info "Installing Homebrew for macOS..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Apple Silicon
            [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
            ;;
        ubuntu|debian|linux-generic)
            log_info "Installing Homebrew (Linuxbrew) for $OS_TYPE..."
            # Prerequisites
            sudo apt install -y build-essential procps curl file git 2>/dev/null || true
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Add to current session
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            ;;
        kali|parrot)
            log_info "Installing Homebrew (Linuxbrew) for $OS_TYPE..."
            sudo apt install -y build-essential procps curl file git 2>/dev/null || true
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            ;;
        *)
            log_info "Skipping Homebrew install for $OS_TYPE (using native package manager)."
            ;;
    esac
}

install_brew
