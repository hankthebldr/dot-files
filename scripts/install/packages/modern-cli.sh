#!/usr/bin/env bash
# scripts/install/packages/modern-cli.sh
# Install modern CLI replacements and productivity tools

source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/detect-os.sh"

TOOLS=(
    bat         # cat replacement
    ripgrep     # grep replacement
    fd          # find replacement (fd-find)
    eza         # ls replacement
    zoxide      # cd replacement
    fzf         # fuzzy finder
    htop        # top replacement
    btop        # better top
    tldr        # man replacement
    jq          # json processor
    yq          # yaml processor
    lazygit     # git tui
    neovim      # vim replacement
    starship    # prompt
    glow        # markdown reader
    navi        # interactive cheatsheet
    zellij      # modern terminal multiplexer (tmux alternative)
    nvtop       # GPU process viewer
)

install_modern_cli() {
    log_info "Installing modern CLI tools..."
    
    detect_os
    
    for tool in "${TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            log_success "$tool is already installed"
        else
            log_info "Installing $tool..."
            
            # Handle package name differences
            local pkg_name="$tool"
            if [[ "$tool" == "fd" && ("$PKG_MANAGER" == "apt" || "$PKG_MANAGER" == "dnf") ]]; then
                pkg_name="fd-find"
            fi
            
            # Many of these tools (lazygit, eza, zoxide, glow, navi, starship,
            # btop, tldr) aren't in Ubuntu < 24.04 / Debian < 13 stock repos.
            # Fail-soft so a missing package doesn't trip `set -e` upstream —
            # the brew_extras block in bootstrap.sh picks them up afterwards.
            if [[ "$PKG_MANAGER" == "brew" ]]; then
                brew install "$pkg_name" 2>/dev/null || log_warning "brew couldn't install $pkg_name"
            elif [[ "$PKG_MANAGER" == "apt" ]]; then
                sudo apt install -y "$pkg_name" 2>/dev/null || log_warning "$pkg_name not in apt repo (will retry via brew)"
            elif [[ "$PKG_MANAGER" == "dnf" ]]; then
                sudo dnf install -y "$pkg_name" 2>/dev/null || log_warning "$pkg_name not in dnf repo"
            fi
        fi
    done
}

install_modern_cli
