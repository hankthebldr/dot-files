#!/usr/bin/env bash
# scripts/install/packages/common.sh
# Install essential cross-platform tools that every workstation should have.

source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/detect-os.sh"

PACKAGES=(
    git
    git-lfs        # large file storage for AI model repos
    curl
    wget
    vim
    tmux
    zsh
    unzip
    tar
    tree
    stow
    build-essential   # gcc/make/g++ — required to compile native deps
    cmake             # cross-platform build generator
    rsync
    ncdu              # interactive disk usage analyzer
    ffmpeg            # multimedia framework
    nmap              # network scanner
    openssh-server    # remote access
)

# Packages that have different names per package manager
declare -A PKG_ALIAS
PKG_ALIAS[build-essential.brew]=""   # macOS ships clang via Xcode CLT
PKG_ALIAS[openssh-server.brew]=""    # macOS has its own sshd
PKG_ALIAS[ncdu.brew]="ncdu"

install_common() {
    log_info "Installing essential packages..."
    detect_os

    for pkg in "${PACKAGES[@]}"; do
        # Skip pkgs that don't apply to current pkg manager
        alias_key="${pkg}.${PKG_MANAGER}"
        if [[ -v PKG_ALIAS[$alias_key] ]]; then
            pkg_real="${PKG_ALIAS[$alias_key]}"
            [[ -z "$pkg_real" ]] && { log_info "Skip $pkg on $PKG_MANAGER"; continue; }
        else
            pkg_real="$pkg"
        fi

        # `command -v` test only works for binaries — many of these (build-essential, ca-certificates)
        # aren't a single command, so prefer dpkg/brew presence checks where available.
        if command -v "$pkg_real" &>/dev/null; then
            log_success "$pkg_real already installed."
            continue
        fi
        if [[ "$PKG_MANAGER" == "apt" ]] && dpkg -s "$pkg_real" &>/dev/null; then
            log_success "$pkg_real already installed."
            continue
        fi

        log_info "Installing $pkg_real..."
        case $PKG_MANAGER in
            brew)   brew install "$pkg_real" ;;
            apt)    sudo apt-get install -y "$pkg_real" ;;
            dnf)    sudo dnf install -y "$pkg_real" ;;
            pacman) sudo pacman -S --noconfirm "$pkg_real" ;;
            *)      log_error "Unknown package manager: $PKG_MANAGER" ;;
        esac
    done

    # ── rclone — vendor script (apt's rclone lags behind upstream) ─────
    if ! command -v rclone &>/dev/null; then
        log_info "Installing rclone..."
        case "$PKG_MANAGER" in
            brew) brew install rclone ;;
            *)    curl -fsSL https://rclone.org/install.sh | sudo bash \
                      || log_warning "rclone install failed" ;;
        esac
    fi
}

install_common
