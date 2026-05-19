#!/usr/bin/env bash

################################################################################
# Security Toolchain Installer (Parrot OS Curriculum)
# Description: OSINT, offensive, web, network, forensics, RE tooling.
# Cross-platform: macOS (brew) + Linux (Parrot/Kali: most via apt; Ubuntu: apt
# + Linuxbrew + go install + .deb for GUIs).
################################################################################

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"
detect_os

log_info "── Security Toolchain install (OS: $OS_TYPE, pkg: $PKG_MANAGER) ──"

# Wordlists path — convention on Parrot/Kali is /usr/share/wordlists
if [[ "$OS_TYPE" == "macos" ]]; then
    WORDLISTS_DIR="/usr/local/share/wordlists"
else
    WORDLISTS_DIR="/usr/share/wordlists"
fi

# ─────────────────────────────────────────────
# macOS — Homebrew (original behavior, preserved)
# ─────────────────────────────────────────────
install_macos() {
    if ! command -v brew &>/dev/null; then
        log_error "Homebrew is required on macOS. Install it first."
        exit 1
    fi
    log_info "Tapping security repos..."
    brew tap owasp/zap 2>/dev/null || true
    brew tap knqyf263/trivy 2>/dev/null || true

    local brew_tools=(
        # OSINT / recon
        nmap theharvester amass subfinder massdns httprobe whatweb sslscan sslyze nikto shodan
        # Offensive
        sqlmap crackmapexec hashcat hydra john-jumbo netcat socat
        # Web
        ffuf gobuster dirb wpscan wafw00f
        # Network
        tcpdump ettercap bettercap aircrack-ng scapy hping
        # Forensics
        sleuthkit binwalk foremost scalpel exiftool yara volatility
        # RE
        radare2 capstone
    )
    for tool in "${brew_tools[@]}"; do
        brew list "$tool" &>/dev/null && { log_info "$tool already installed."; continue; }
        log_info "Installing $tool..."
        brew install "$tool" || log_warning "$tool install failed"
    done

    local cask_tools=(wireshark burp-suite owasp-zap ghidra maltego)
    for tool in "${cask_tools[@]}"; do
        brew list --cask "$tool" &>/dev/null && { log_info "$tool already installed."; continue; }
        log_info "Installing $tool (cask)..."
        brew install --cask "$tool" || log_warning "$tool cask install failed"
    done
}

# ─────────────────────────────────────────────
# Linux — apt (Parrot/Kali get a richer set; Ubuntu gets fallbacks)
# ─────────────────────────────────────────────
install_linux() {
    sudo apt-get update -qq || log_warning "apt update failed (continuing)"

    # Tools that exist in apt on Ubuntu AND in the Parrot/Kali meta-repos.
    local apt_tools=(
        # OSINT / recon
        nmap whatweb sslscan nikto theharvester
        # Offensive
        sqlmap hashcat hydra john netcat-openbsd socat
        # Web
        ffuf gobuster dirb wpscan wafw00f
        # Network
        tcpdump ettercap-graphical aircrack-ng python3-scapy hping3
        # Forensics
        sleuthkit binwalk foremost scalpel libimage-exiftool-perl yara
        # RE
        radare2
        # Capture / GUI
        wireshark
    )
    for tool in "${apt_tools[@]}"; do
        dpkg -s "$tool" &>/dev/null && { log_info "$tool already installed."; continue; }
        log_info "Installing $tool..."
        sudo apt-get install -y "$tool" 2>/dev/null || log_warning "$tool apt install failed"
    done

    # Parrot/Kali ship most of these via meta-packages too — short-circuit if so.
    if [[ "$OS_TYPE" == "parrot" || "$OS_TYPE" == "kali" ]]; then
        log_info "Detected $OS_TYPE — most tools may already be in /usr/share/* via metapackages"
    fi

    # ── crackmapexec / bettercap / amass / subfinder / massdns / httprobe / sslyze ──
    # These are NOT reliably in Ubuntu's apt repos. Use Linuxbrew when present,
    # otherwise go install / pipx / curl.

    if command -v brew &>/dev/null; then
        log_info "Using Linuxbrew for tools missing from apt..."
        local brew_extras=(amass subfinder massdns httprobe sslyze bettercap shodan)
        for tool in "${brew_extras[@]}"; do
            brew list "$tool" &>/dev/null && continue
            log_info "Installing $tool via brew..."
            brew install "$tool" || log_warning "$tool brew install failed"
        done
    else
        # Go-based recon: install with `go install` if Go present
        if command -v go &>/dev/null; then
            log_info "Installing Go-based recon tools..."
            go install -v github.com/owasp-amass/amass/v4/...@master    || log_warning "amass install failed"
            go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest || log_warning "subfinder install failed"
            go install -v github.com/tomnomnom/httprobe@latest          || log_warning "httprobe install failed"
        else
            log_warning "Go missing — amass/subfinder/httprobe skipped (install Go or Linuxbrew)"
        fi
        # pipx for Python tools
        if command -v pipx &>/dev/null; then
            pipx install crackmapexec 2>/dev/null || pipx upgrade crackmapexec 2>/dev/null \
                || log_warning "crackmapexec pipx install failed"
            pipx install sslyze 2>/dev/null || pipx upgrade sslyze 2>/dev/null \
                || log_warning "sslyze pipx install failed"
            pipx install shodan 2>/dev/null || pipx upgrade shodan 2>/dev/null \
                || log_warning "shodan pipx install failed"
        fi
    fi

    # ── volatility3 (volatility2 in apt is dead; use pipx for v3) ──
    if command -v pipx &>/dev/null && ! command -v vol &>/dev/null; then
        log_info "Installing volatility3 via pipx..."
        pipx install volatility3 || log_warning "volatility3 install failed"
    fi

    # ── GUI / Frameworks ──
    # wireshark: handled in apt_tools above
    # burp-suite: free community .deb from PortSwigger
    # owasp-zap: snap or .deb
    # ghidra: tarball
    # maltego: .deb from Paterva
    if ! command -v burpsuite &>/dev/null; then
        log_info "Burp Suite Community — manual install required:"
        log_warning "  download .deb: https://portswigger.net/burp/releases/community/latest"
    fi
    if ! command -v zaproxy &>/dev/null && ! command -v zap &>/dev/null; then
        if command -v snap &>/dev/null; then
            log_info "Installing OWASP ZAP via snap..."
            sudo snap install zaproxy --classic || log_warning "ZAP snap install failed"
        else
            log_warning "OWASP ZAP needs snap or manual .deb (skipping)"
        fi
    fi
    if [[ ! -d /opt/ghidra ]]; then
        log_warning "Ghidra not installed — manual download from https://ghidra-sre.org/"
    fi

    # Capstone — apt library, the brew formula is the bindings.
    sudo apt-get install -y libcapstone-dev 2>/dev/null || true
}

# ─────────────────────────────────────────────
# Cross-platform: Metasploit + SecLists
# ─────────────────────────────────────────────
install_metasploit() {
    if command -v msfconsole &>/dev/null; then
        log_info "Metasploit already installed."
        return 0
    fi
    log_info "Installing Metasploit Framework (rapid7 omnibus)..."
    local tmp; tmp=$(mktemp -d)
    curl -fsSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb \
        -o "$tmp/msfinstall" \
        && chmod +x "$tmp/msfinstall" \
        && (cd "$tmp" && ./msfinstall) \
        || log_warning "Metasploit install failed"
    rm -rf "$tmp"
}

install_seclists() {
    if [[ -d "$WORDLISTS_DIR/SecLists" ]]; then
        log_info "SecLists already at $WORDLISTS_DIR/SecLists"
        return 0
    fi
    log_info "Cloning SecLists to $WORDLISTS_DIR..."
    sudo mkdir -p "$WORDLISTS_DIR"
    sudo git clone --depth 1 https://github.com/danielmiessler/SecLists.git \
        "$WORDLISTS_DIR/SecLists" || log_warning "SecLists clone failed"
    # Make it readable by current user
    if [[ "$OS_TYPE" == "macos" ]]; then
        sudo chown -R "$USER:admin" "$WORDLISTS_DIR" 2>/dev/null || true
    else
        sudo chown -R "$USER:$USER" "$WORDLISTS_DIR" 2>/dev/null || true
    fi
}

# ─────────────────────────────────────────────
# Dispatch
# ─────────────────────────────────────────────
case "$PKG_MANAGER" in
    brew) install_macos ;;
    apt)  install_linux ;;
    *)    log_warning "Unsupported package manager ($PKG_MANAGER); install security tools manually" ;;
esac

install_metasploit
install_seclists

log_success "Security Toolchain install complete."
