#!/bin/bash

################################################################################
# MacBook Pro Poweruser Tools Installation Script
# Description: Automated installation of development, security, and system tools
# Author: Claude Code
# Date: 2025-11-05
# Usage: bash install-poweruser-tools.sh [category]
#        Categories: all, shell, dev, security, devops, network, data, extras
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

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
        # Modern CLI replacements
        "eza"
        "fd"
        "ripgrep"
        "fzf"
        "zoxide"
        "starship"
        "tmux"
        "neovim"

        # Productivity
        "thefuck"
        "tldr"
        "trash-cli"
        "tree"
        "watch"
        "htop"
        "glances"
        "procs"
        "bat"
        "bottom"
        "btop"

        # Multiplexers
        "zellij"
    )

    for tool in "${tools[@]}"; do
        brew install "$tool" || log_warning "Failed to install $tool"
    done

    # Cask applications
    local cask_tools=(
        "iterm2"
        "wezterm"
    )

    for tool in "${cask_tools[@]}"; do
        brew install --cask "$tool" || log_warning "Failed to install $tool"
    done

    log_success "Shell tools installation complete"
}

# Install development tools
install_dev_tools() {
    log_info "Installing development tools..."

    # Version control
    local vcs_tools=(
        "gh"
        "git-lfs"
        "git-delta"
        "lazygit"
        "tig"
        "pre-commit"
    )

    # Languages
    local lang_tools=(
        "node"
        "nvm"
        "yarn"
        "pnpm"
        "bun"
        "pyenv"
        "pipenv"
        "poetry"
        "black"
        "ruff"
        "go"
        "gopls"
        "rust"
        "rust-analyzer"
        "openjdk"
        "maven"
        "gradle"
        "kotlin"
        "ruby"
        "rbenv"
        "elixir"
        "lua"
    )

    # Databases
    local db_tools=(
        "postgresql@16"
        "mysql"
        "redis"
        "sqlite"
        "duckdb"
        "pgcli"
        "mycli"
        "litecli"
        "usql"
    )

    # API tools
    local api_tools=(
        "httpie"
        "wget"
        "grpcurl"
        "websocat"
    )

    # Code quality
    local quality_tools=(
        "shellcheck"
        "hadolint"
        "yamllint"
        "jsonlint"
        "tflint"
        "markdownlint-cli"
    )

    local all_dev_tools=("${vcs_tools[@]}" "${lang_tools[@]}" "${db_tools[@]}" "${api_tools[@]}" "${quality_tools[@]}")

    for tool in "${all_dev_tools[@]}"; do
        brew install "$tool" || log_warning "Failed to install $tool"
    done

    # Cask applications
    brew install --cask insomnia || log_warning "Failed to install insomnia"

    log_success "Development tools installation complete"
}

# Install security tools
install_security_tools() {
    log_info "Installing information security tools..."

    # Network scanning
    local scan_tools=(
        "nmap"
        "masscan"
        "zmap"
        "rustscan"
        "netcat"
        "socat"
    )

    # Web security
    local web_tools=(
        "nikto"
        "sqlmap"
        "gobuster"
        "ffuf"
        "wfuzz"
        "nuclei"
        "whatweb"
        "wafw00f"
    )

    # Password tools
    local pass_tools=(
        "hashcat"
        "john-jumbo"
        "hydra"
        "crunch"
    )

    # Network analysis
    local analysis_tools=(
        "tcpdump"
        "ngrep"
        "mitmproxy"
    )

    # Wireless
    local wireless_tools=(
        "aircrack-ng"
    )

    # Exploitation
    local exploit_tools=(
        "metasploit"
        "powershell"
    )

    # Forensics
    local forensics_tools=(
        "binwalk"
        "foremost"
        "radare2"
        "rizin"
        "xxd"
        "hexyl"
        "exiftool"
    )

    # Crypto
    local crypto_tools=(
        "gnupg"
        "openssl"
        "age"
        "sops"
        "jwt-cli"
    )

    # SSL/TLS
    local ssl_tools=(
        "testssl"
        "sslyze"
        "sslscan"
    )

    # Container security
    local container_sec_tools=(
        "trivy"
        "grype"
        "syft"
        "cosign"
    )

    local all_sec_tools=(
        "${scan_tools[@]}"
        "${web_tools[@]}"
        "${pass_tools[@]}"
        "${analysis_tools[@]}"
        "${wireless_tools[@]}"
        "${exploit_tools[@]}"
        "${forensics_tools[@]}"
        "${crypto_tools[@]}"
        "${ssl_tools[@]}"
        "${container_sec_tools[@]}"
    )

    for tool in "${all_sec_tools[@]}"; do
        brew install "$tool" || log_warning "Failed to install $tool"
    done

    # Cask applications
    local sec_casks=(
        "wireshark"
        "burp-suite"
        "ghidra"
    )

    for tool in "${sec_casks[@]}"; do
        brew install --cask "$tool" || log_warning "Failed to install $tool"
    done

    log_success "Security tools installation complete"
}

# Install DevOps and cloud tools
install_devops_tools() {
    log_info "Installing DevOps and cloud infrastructure tools..."

    # Container tools
    local container_tools=(
        "docker-compose"
        "podman"
        "kubernetes-cli"
        "k9s"
        "kubectx"
        "helm"
        "minikube"
        "kind"
        "k3d"
        "skaffold"
        "stern"
        "kustomize"
    )

    # IaC tools
    local iac_tools=(
        "terraform"
        "terragrunt"
        "ansible"
        "packer"
        "vagrant"
        "pulumi"
    )

    # Cloud CLIs
    local cloud_tools=(
        "aws-vault"
        "azure-cli"
        "doctl"
        "heroku"
    )

    # CI/CD
    local cicd_tools=(
        "circleci"
        "act"
    )

    # Monitoring
    local monitoring_tools=(
        "prometheus"
        "grafana"
        "telegraf"
    )

    local all_devops_tools=(
        "${container_tools[@]}"
        "${iac_tools[@]}"
        "${cloud_tools[@]}"
        "${cicd_tools[@]}"
        "${monitoring_tools[@]}"
    )

    for tool in "${all_devops_tools[@]}"; do
        brew install "$tool" || log_warning "Failed to install $tool"
    done

    log_success "DevOps tools installation complete"
}

# Install network tools
install_network_tools() {
    log_info "Installing networking and system tools..."

    local net_tools=(
        "ipcalc"
        "whois"
        "bind"
        "mtr"
        "iperf3"
        "speedtest-cli"
        "bandwhich"
        "gping"
        "dog"
        "aria2"
    )

    local sys_tools=(
        "coreutils"
        "findutils"
        "gnu-sed"
        "gnu-tar"
        "gawk"
        "grep"
        "gzip"
        "xz"
        "p7zip"
        "unrar"
        "pigz"
        "ncdu"
        "duf"
        "dust"
        "hyperfine"
    )

    local all_net_tools=("${net_tools[@]}" "${sys_tools[@]}")

    for tool in "${all_net_tools[@]}"; do
        brew install "$tool" || log_warning "Failed to install $tool"
    done

    log_success "Network and system tools installation complete"
}

# Install data processing tools
install_data_tools() {
    log_info "Installing data processing and analysis tools..."

    local data_tools=(
        "jq"
        "yq"
        "csvkit"
        "miller"
        "xmlstarlet"
        "pandoc"
        "grex"
        "rsync"
        "rclone"
        "restic"
    )

    for tool in "${data_tools[@]}"; do
        brew install "$tool" || log_warning "Failed to install $tool"
    done

    log_success "Data processing tools installation complete"
}

# Install extra productivity tools
install_extra_tools() {
    log_info "Installing additional productivity tools..."

    local extra_casks=(
        "maccy"
        "rectangle"
        "alfred"
    )

    for tool in "${extra_casks[@]}"; do
        brew install --cask "$tool" || log_warning "Failed to install $tool"
    done

    local extra_tools=(
        "cheat"
        "mdcat"
        "glow"
    )

    for tool in "${extra_tools[@]}"; do
        brew install "$tool" || log_warning "Failed to install $tool"
    done

    # Virtualization
    brew install --cask utm || log_warning "Failed to install utm"

    log_success "Extra tools installation complete"
}

# Install Oh My Zsh
install_oh_my_zsh() {
    log_info "Installing Oh My Zsh..."

    if [ -d "$HOME/.oh-my-zsh" ]; then
        log_warning "Oh My Zsh is already installed"
    else
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        log_success "Oh My Zsh installed"
    fi

    # Install plugins
    log_info "Installing ZSH plugins..."

    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    # zsh-autosuggestions
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    fi

    # zsh-syntax-highlighting
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    fi

    # you-should-use
    if [ ! -d "$ZSH_CUSTOM/plugins/you-should-use" ]; then
        git clone https://github.com/MichaelAquilina/zsh-you-should-use "$ZSH_CUSTOM/plugins/you-should-use"
    fi

    log_success "ZSH plugins installed"
}

# Main installation function
main() {
    local category="${1:-all}"

    echo ""
    log_info "Starting MacBook Pro Poweruser Tools Installation"
    log_info "Category: $category"
    echo ""

    check_brew

    case "$category" in
        all)
            install_shell_tools
            install_dev_tools
            install_security_tools
            install_devops_tools
            install_network_tools
            install_data_tools
            install_extra_tools
            install_oh_my_zsh
            ;;
        shell)
            install_shell_tools
            install_oh_my_zsh
            ;;
        dev)
            install_dev_tools
            ;;
        security)
            install_security_tools
            ;;
        devops)
            install_devops_tools
            ;;
        network)
            install_network_tools
            ;;
        data)
            install_data_tools
            ;;
        extras)
            install_extra_tools
            ;;
        *)
            log_error "Unknown category: $category"
            log_info "Available categories: all, shell, dev, security, devops, network, data, extras"
            exit 1
            ;;
    esac

    echo ""
    log_success "Installation complete!"
    log_info "Run 'brew cleanup' to remove old versions"
    log_info "Restart your terminal to apply changes"
    echo ""
}

# Run main function
main "$@"
