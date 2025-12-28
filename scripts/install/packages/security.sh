#!/usr/bin/env bash
# scripts/install/packages/security.sh
# Install security and pentesting tools

source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/detect-os.sh"

# List of security tools (CLI)
SECURITY_TOOLS=(
    nmap
    tshark
    tcpdump
    netcat
    sqlmap
    aircrack-ng
    nikto
)

# List of optional/heavy tools
HEAVY_TOOLS=(
    metasploit-framework
    john
    hydra
)

install_security_tools() {
    log_info "Installing security tools..."
    
    detect_os
    
    for tool in "${SECURITY_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            log_success "$tool is already installed"
        else
            log_info "Installing $tool..."
            if [[ "$PKG_MANAGER" == "brew" ]]; then
                brew install "$tool"
            elif [[ "$PKG_MANAGER" == "apt" ]]; then
                sudo apt install -y "$tool"
            elif [[ "$PKG_MANAGER" == "dnf" ]]; then
                sudo dnf install -y "$tool"
            else
                log_warning "Manual installation required for $tool"
            fi
        fi
    done
}

install_security_tools
