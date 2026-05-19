#!/usr/bin/env bash
# scripts/install/packages/dev-tools.sh
# Install development languages + per-project version managers.
# Cross-platform: macOS (brew) + Linux (apt + official installers).

source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/detect-os.sh"

install_dev_tools() {
    log_info "Installing development tools..."
    detect_os

    case "$PKG_MANAGER" in
        brew)
            brew install node go rust python3 fnm pyenv
            if ! command -v atuin &>/dev/null; then
                log_info "Installing Atuin..."
                brew install atuin
            fi
            ;;
        apt)
            # System Node is OK as a fallback; fnm is the daily driver.
            sudo apt-get update -qq
            sudo apt-get install -y nodejs npm golang-go python3 python3-pip python3-venv \
                build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
                libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev \
                libxmlsec1-dev libffi-dev liblzma-dev curl ca-certificates \
                2>/dev/null || true

            # Linuxbrew path (preferred when present — gives parity with Mac)
            if command -v brew &>/dev/null; then
                for tool in node go rust fnm pyenv atuin; do
                    if ! command -v "$tool" &>/dev/null; then
                        log_info "Installing $tool via brew..."
                        brew install "$tool" || log_warning "$tool brew install failed"
                    fi
                done
            else
                # fnm — single static binary from GitHub releases
                if ! command -v fnm &>/dev/null; then
                    log_info "Installing fnm (Node version manager)..."
                    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell \
                        || log_warning "fnm install failed"
                fi

                # pyenv — official installer (clones to ~/.pyenv)
                if [[ ! -d "$HOME/.pyenv" ]]; then
                    log_info "Installing pyenv..."
                    curl -fsSL https://pyenv.run | bash || log_warning "pyenv install failed"
                    # pyenv's shell init lives in shell/path.zsh + shell/exports.zsh;
                    # users with existing .zshrc will need to re-source after install.
                fi

                # Rust via rustup (official, user-space — no sudo)
                if ! command -v rustc &>/dev/null; then
                    log_info "Installing Rust via rustup..."
                    curl -fsSL --proto '=https' --tlsv1.2 https://sh.rustup.rs | \
                        sh -s -- -y --no-modify-path || log_warning "rustup install failed"
                fi

                # Atuin — official installer
                if ! command -v atuin &>/dev/null; then
                    log_info "Installing Atuin..."
                    bash <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh) \
                        || log_warning "Atuin install failed"
                fi
            fi
            ;;
        dnf|pacman)
            log_warning "$PKG_MANAGER: dev-tools script does not auto-install — install Node/Go/Rust/Python via your package manager and use fnm/pyenv from upstream"
            ;;
    esac
}

install_dev_tools
