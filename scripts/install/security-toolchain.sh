#!/bin/bash

################################################################################
# Security Toolchain Installer (Parrot OS Curriculum)
# Description: Automated installation of security, OSINT, and forensics tools
#              natively compiled or ported for macOS via Homebrew.
################################################################################

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if ! command -v brew &> /dev/null; then
    log_error "Homebrew is required. Please install it first."
    exit 1
fi

log_info "Tapping necessary repositories..."
brew tap owasp/zap || true
brew tap knqyf263/trivy || true

# 1. OSINT / Reconnaissance
osint_tools=(
    "nmap"
    "theharvester"
    "amass"
    "subfinder"
    "massdns"
    "httprobe"
    "whatweb"
    "sslscan"
    "sslyze"
    "nikto"
    "shodan"
)

# 2. Red Team / Offensive
offensive_tools=(
    "sqlmap"
    "crackmapexec"
    "hashcat"
    "hydra"
    "john-jumbo"
    "netcat"
    "socat"
)

# 3. Web App Interrogation
web_tools=(
    "ffuf"
    "gobuster"
    "dirb"
    "wpscan"
    "wafw00f"
)

# 4. Network & Spoofing
network_tools=(
    "tcpdump"
    "ettercap"
    "bettercap"
    "aircrack-ng"
    "scapy"
    "hping"
)

# 5. Digital Forensics
forensics_tools=(
    "sleuthkit"
    "binwalk"
    "foremost"
    "scalpel"
    "exiftool"
    "yara"
    "volatility"
)

# 6. Reverse Engineering
re_tools=(
    "radare2"
    "capstone"
)

# Combine all brew packages
all_brew_tools=(
    "${osint_tools[@]}"
    "${offensive_tools[@]}"
    "${web_tools[@]}"
    "${network_tools[@]}"
    "${forensics_tools[@]}"
    "${re_tools[@]}"
)

log_info "Installing CLI tools via Homebrew..."
for tool in "${all_brew_tools[@]}"; do
    if brew list "$tool" &>/dev/null; then
        log_info "$tool is already installed."
    else
        log_info "Installing $tool..."
        brew install "$tool" || log_warning "Failed to install $tool"
    fi
done

# Casks (GUI or Frameworks)
cask_tools=(
    "wireshark"
    "burp-suite"
    "owasp-zap"
    "ghidra"
    "maltego"
)

log_info "Installing Cask applications..."
for tool in "${cask_tools[@]}"; do
    if brew list --cask "$tool" &>/dev/null; then
        log_info "$tool is already installed."
    else
        log_info "Installing $tool..."
        brew install --cask "$tool" || log_warning "Failed to install $tool (requires sudo occasionally)"
    fi
done

log_info "Installing specialized frameworks..."
if ! command -v msfconsole &> /dev/null; then
    log_info "Installing Metasploit Framework..."
    curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && chmod 755 msfinstall && ./msfinstall || log_warning "Failed to install Metasploit"
    rm msfinstall
else
    log_info "Metasploit Framework already installed."
fi

# Clone SecLists for Wordlists
WORDLISTS_DIR="/usr/local/share/wordlists"
if [ ! -d "$WORDLISTS_DIR" ]; then
    log_info "Installing SecLists (Wordlists) to $WORDLISTS_DIR..."
    sudo mkdir -p "$WORDLISTS_DIR"
    sudo git clone --depth 1 https://github.com/danielmiessler/SecLists.git "$WORDLISTS_DIR/SecLists" || log_warning "Failed to clone SecLists"
    sudo chown -R $USER:admin "$WORDLISTS_DIR"
else
    log_info "SecLists already installed at $WORDLISTS_DIR"
fi

log_success "Security Toolchain Installation Complete!"
