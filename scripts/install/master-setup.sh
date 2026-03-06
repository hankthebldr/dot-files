#!/bin/bash

################################################################################
# MacBook Pro Master Setup Script
# Description: Automated installation of core base tools and delegation to 
#              specialized domain toolchains (Cloud, Security, DevOps, AI, Research).
# Date: 2026-02-20
# Usage: bash master-setup.sh [category]
#        Categories: all, base, domains, shell, dev, network, extras
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if Homebrew is installed
check_brew() {
    if ! command -v brew &> /dev/null; then
        log_error "Homebrew is not installed. Installing now..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add to PATH for Apple Silicon
        if [[ $(uname -m) == 'arm64' ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    else
        log_success "Homebrew is already installed"
        brew update
    fi
}

# Install shell and terminal tools
install_shell_tools() {
    log_info "Installing shell and terminal enhancements..."

    local tools=(
        "eza" "yazi" "fd" "ripgrep" "fzf" "zoxide" "starship" "tmux" "neovim"
        "thefuck" "tldr" "trash-cli" "tree" "watch" "htop" "glances" "procs"
        "bat" "bottom" "btop" "zellij" "fastfetch" "gum"
    )

    for tool in "${tools[@]}"; do
        if brew list "$tool" &>/dev/null; then
            log_info "$tool already installed"
        else
            brew install "$tool" || log_warning "Failed to install $tool"
        fi
    done

    local cask_tools=("iterm2" "wezterm")
    for tool in "${cask_tools[@]}"; do
        if brew list --cask "$tool" &>/dev/null; then
            log_info "$tool already installed"
        else
            brew install --cask "$tool" || log_warning "Failed to install $tool"
        fi
    done

    log_success "Shell tools installation complete"
}

# Install development tools
install_dev_tools() {
    log_info "Installing core development base tools..."

    local tools=(
        "gh" "git-lfs" "git-delta" "lazygit" "tig" "pre-commit"
        "node" "nvm" "yarn" "pnpm" "bun" "pyenv" "pipenv" "poetry" "black" "ruff"
        "go" "gopls" "rust" "rust-analyzer" "openjdk" "maven" "gradle" "kotlin"
        "ruby" "rbenv" "elixir" "lua"
        "postgresql@16" "mysql" "redis" "sqlite" "duckdb" "pgcli" "mycli" "litecli" "usql"
        "httpie" "wget" "grpcurl" "websocat"
        "shellcheck" "hadolint" "yamllint" "jsonlint" "tflint" "markdownlint-cli"
    )

    for tool in "${tools[@]}"; do
        if brew list "$tool" &>/dev/null; then
            log_info "$tool already installed"
        else
            brew install "$tool" || log_warning "Failed to install $tool"
        fi
    done

    if brew list --cask insomnia &>/dev/null; then
        log_info "insomnia already installed"
    else
        brew install --cask insomnia || log_warning "Failed to install insomnia"
    fi

    log_success "Development base installation complete"
}

# Install network tools
install_network_tools() {
    log_info "Installing base networking and system tools..."

    local tools=(
        "ipcalc" "whois" "bind" "mtr" "iperf3" "speedtest-cli" "bandwhich" "gping" "dog" "aria2"
        "coreutils" "findutils" "gnu-sed" "gnu-tar" "gawk" "grep" "gzip" "xz" "p7zip"
        "unrar" "pigz" "ncdu" "duf" "dust" "hyperfine"
    )

    for tool in "${tools[@]}"; do
        if brew list "$tool" &>/dev/null; then
            log_info "$tool already installed"
        else
            brew install "$tool" || log_warning "Failed to install $tool"
        fi
    done

    log_success "Network and system tools installation complete"
}

# Install extra productivity tools
install_extra_tools() {
    log_info "Installing additional productivity tools..."

    local extra_casks=("maccy" "rectangle" "alfred" "utm")
    for tool in "${extra_casks[@]}"; do
        if brew list --cask "$tool" &>/dev/null; then
            log_info "$tool already installed"
        else
            brew install --cask "$tool" || log_warning "Failed to install $tool"
        fi
    done

    local extra_tools=("cheat" "mdcat" "glow")
    for tool in "${extra_tools[@]}"; do
        if brew list "$tool" &>/dev/null; then
            log_info "$tool already installed"
        else
            brew install "$tool" || log_warning "Failed to install $tool"
        fi
    done

    log_success "Extra tools installation complete"
}

# Install Oh My Zsh
install_oh_my_zsh() {
    log_info "Installing Oh My Zsh..."
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        log_success "Oh My Zsh installed"
    else
        log_info "Oh My Zsh already installed"
    fi

    log_info "Installing ZSH plugins..."
    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    [ ! -d "$ZSH_CUSTOM/plugins/you-should-use" ] && git clone https://github.com/MichaelAquilina/zsh-you-should-use "$ZSH_CUSTOM/plugins/you-should-use"
    log_success "ZSH plugins installed"
}

# Delegate to domain toolchains
install_domains() {
    log_info "Triggering modular specialized domain install scripts..."
    
    local domains=("cloud" "security" "devops" "research" "ai" "cortex")
    
    for domain in "${domains[@]}"; do
        local script_path="$SCRIPT_DIR/${domain}-toolchain.sh"
        if [ -f "$script_path" ]; then
            log_info "Executing $domain toolchain installer..."
            bash "$script_path"
        else
            log_error "Domain script not found: $script_path"
        fi
    done
    
    log_success "All domain toolchains processed."
}

# Main installation function
main() {
    local category="${1:-all}"

    echo ""
    log_info "Starting MacBook Pro Master Setup"
    log_info "Category: $category"
    echo ""

    check_brew

    case "$category" in
        all)
            install_shell_tools
            install_dev_tools
            install_network_tools
            install_extra_tools
            install_oh_my_zsh
            install_domains
            ;;
        base)
            install_shell_tools
            install_dev_tools
            install_network_tools
            install_extra_tools
            install_oh_my_zsh
            ;;
        domains)
            install_domains
            ;;
        shell) install_shell_tools; install_oh_my_zsh ;;
        dev) install_dev_tools ;;
        network) install_network_tools ;;
        extras) install_extra_tools ;;
        *)
            log_error "Unknown category: $category"
            log_info "Available categories: all, base, domains, shell, dev, network, extras"
            exit 1
            ;;
    esac

    echo ""
    log_success "Installation run complete!"
    log_info "Run 'brew cleanup' to remove old versions"
    echo ""
}

main "$@"
