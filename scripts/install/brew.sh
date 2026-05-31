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

    # NONINTERACTIVE=1 makes the official installer skip the "Press RETURN to
    # continue" prompt and use sudo's already-cached creds instead of reading
    # /dev/tty — both are required to make this survive `curl | bash` over SSH.
    case "$OS_TYPE" in
        macos)
            log_info "Installing Homebrew for macOS..."
            NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Apple Silicon
            [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
            ;;
        ubuntu|debian|kali|parrot|linux-generic)
            log_info "Installing Homebrew (Linuxbrew) for $OS_TYPE..."
            sudo apt install -y build-essential procps curl file git 2>/dev/null || true
            NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            ;;
        *)
            # Catch-all for any Linux distro that detect-os didn't recognize
            # (Pop!_OS, Mint, Arch via apt-derivative, etc.). If apt is present
            # we can still install Linuxbrew — without this, Step 6 in bootstrap
            # silently skips ~13 modern CLI tools because brew never appears.
            if [[ "$PKG_MANAGER" == "apt" ]]; then
                log_info "Installing Homebrew (Linuxbrew) for unrecognized apt-based $OS_TYPE..."
                sudo apt install -y build-essential procps curl file git 2>/dev/null || true
                NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            else
                log_info "Skipping Homebrew install for $OS_TYPE (using $PKG_MANAGER)."
            fi
            ;;
    esac
}

install_brew
