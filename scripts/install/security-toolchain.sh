#!/usr/bin/env bash
################################################################################
# Security Toolchain — Cross-Platform
#
# OSINT, offensive, web, network, forensics, RE, and wireless tools across
# macOS (brew), Debian/Ubuntu/Parrot/Kali (apt), and Fedora (dnf). All install
# logic lives in scripts/install/lib/toolchain-runner.sh — this file just
# declares the data table and the security-specific extras (Metasploit,
# SecLists wordlists).
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toolchain-runner.sh"

TOOLCHAIN_TITLE="ARSENAL  INITIALIZING"
TOOLCHAIN_CLASS="NIGHTHACKER  TOOLCHAIN"
TOOLCHAIN_TAG="reconnaissance · offensive · forensics · reverse engineering"

# ── TOOL MAPPING ───────────────────────────────────────────────────────────
# Format: "tool-id|brew-name|apt-name|fallback|notes"
#
# >>> HENRY: rows with apt-name=? need your Parrot/Kali domain knowledge to
#     pin the real package name. Until corrected, those tools fall through to
#     the declared fallback (cargo/gem/pipx/manual). The script runs cleanly
#     either way — these edits just unlock 8 more native apt installs.
TOOLCHAIN_MAP=(
    # ── 01. OSINT / Reconnaissance ─────────────────────────────────────────
    "nmap|nmap|nmap|none|port scanner — universal"
    "theharvester|theharvester|theharvester|pipx|email/subdomain OSINT"
    "amass|amass|amass|none|subdomain enumeration"
    "subfinder|subfinder|?|go:github.com/projectdiscovery/subfinder/v2/cmd/subfinder|passive subdomain discovery"
    "massdns|massdns|massdns|none|high-perf DNS resolver"
    "httprobe|httprobe|?|go:github.com/tomnomnom/httprobe|HTTP/S liveness"
    "whatweb|whatweb|whatweb|none|web fingerprinter"
    "sslscan|sslscan|sslscan|none|SSL/TLS scanner"
    "sslyze|sslyze|sslyze|pipx|deeper SSL scanner"
    "nikto|nikto|nikto|none|web vuln scanner"
    "shodan|shodan|?|pipx|shodan CLI"

    # ── 02. Red Team / Offensive ───────────────────────────────────────────
    "sqlmap|sqlmap|sqlmap|none|SQL injection automation"
    "crackmapexec|crackmapexec|crackmapexec|pipx|AD/SMB swiss army knife"
    "hashcat|hashcat|hashcat|none|GPU password cracker"
    "hydra|hydra|hydra|none|brute-force login"
    "john|john-jumbo|john|none|john the ripper"
    "nc|netcat|ncat|none|netcat (apt: ncat or netcat-traditional)"
    "socat|socat|socat|none|multi-purpose relay"
    "ffuf|ffuf|ffuf|go:github.com/ffuf/ffuf/v2|fast web fuzzer"
    "gobuster|gobuster|gobuster|go:github.com/OJ/gobuster/v3|dir/dns brute force"
    "dirb|dirb|dirb|none|legacy dir brute"
    "wpscan|wpscan|wpscan|gem|wordpress audit (gem on apt sometimes)"
    "wafw00f|wafw00f|wafw00f|pipx|WAF fingerprinter"

    # ── 03. Network & Spoofing ─────────────────────────────────────────────
    "tcpdump|tcpdump|tcpdump|none|packet capture"
    "ettercap|ettercap|ettercap-text-only|none|MITM framework"
    "bettercap|bettercap|bettercap|none|modern MITM"
    "aircrack-ng|aircrack-ng|aircrack-ng|none|wifi cracking suite"
    "scapy|?|python3-scapy|pipx|packet manipulation"
    "hping3|hping|hping3|none|packet crafter"

    # ── 04. Digital Forensics ──────────────────────────────────────────────
    "fls|sleuthkit|sleuthkit|none|the sleuth kit"
    "binwalk|binwalk|binwalk|none|firmware analysis"
    "foremost|foremost|foremost|none|file carving"
    "scalpel|scalpel|scalpel|none|file carving (alt)"
    "exiftool|exiftool|libimage-exiftool-perl|none|metadata reader"
    "yara|yara|yara|none|malware pattern matching"
    "vol|volatility|volatility3|pipx|memory forensics (vol3)"

    # ── 05. Reverse Engineering ────────────────────────────────────────────
    "r2|radare2|radare2|none|RE framework"
    "capstone|capstone|libcapstone-dev|none|disassembly lib"

    # ── 06. Heavy / GUI ────────────────────────────────────────────────────
    "wireshark|wireshark|wireshark|none|packet GUI"
    "burpsuite|burp-suite|?|manual:https://portswigger.net/burp/releases|web proxy GUI"
    "zaproxy|owasp-zap|zaproxy|none|OWASP ZAP"
    "ghidra|ghidra|?|manual:https://ghidra-sre.org|NSA reverse engineering"
    "maltego|maltego|?|manual:https://maltego.com|graph OSINT"
)

declare -A TOOLCHAIN_SECTIONS=(
    [0]="01|OSINT  /  Reconnaissance"
    [11]="02|Red  Team  /  Offensive"
    [23]="03|Network  &  Spoofing"
    [29]="04|Digital  Forensics"
    [36]="05|Reverse  Engineering"
    [38]="06|Heavy  /  GUI  Tools"
)

# ── EXTRAS: Metasploit + SecLists ──────────────────────────────────────────
# Runs after the main MAP install loop. Mutates RESULT_* arrays directly so
# the lib's summary picks these up.
toolchain_extras() {
    _section 7 "Metasploit  Framework"
    if command -v msfconsole &>/dev/null; then
        log_skip "msfconsole already installed"
        RESULT_SKIPPED+=("metasploit")
    else
        case "$PKG_MANAGER" in
            apt)
                if [[ "$OS_TYPE" == "parrot" || "$OS_TYPE" == "kali" ]]; then
                    log_info "installing metasploit-framework via apt..."
                    sudo apt-get install -y metasploit-framework \
                        && RESULT_INSTALLED+=("metasploit") \
                        || RESULT_FAILED+=("metasploit")
                else
                    log_info "downloading Rapid7 omnibus installer..."
                    local tmp; tmp="$(mktemp)"
                    curl -fsSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb -o "$tmp"
                    chmod +x "$tmp"
                    sudo "$tmp" \
                        && RESULT_INSTALLED+=("metasploit") \
                        || RESULT_FAILED+=("metasploit")
                    rm -f "$tmp"
                fi
                ;;
            brew)
                log_info "downloading Rapid7 omnibus installer..."
                local tmp; tmp="$(mktemp)"
                curl -fsSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb -o "$tmp"
                chmod +x "$tmp"
                "$tmp" && RESULT_INSTALLED+=("metasploit") || RESULT_FAILED+=("metasploit")
                rm -f "$tmp"
                ;;
            *)
                log_warning "metasploit install path unknown for $PKG_MANAGER"
                RESULT_FAILED+=("metasploit")
                ;;
        esac
    fi

    _section 8 "Wordlists  (SecLists)"
    # OS-aware path. Kali/Parrot/Ubuntu all use /usr/share/wordlists; macOS
    # uses /usr/local/share/wordlists for Homebrew alignment.
    local wordlists_dir
    case "$OS_TYPE" in
        parrot|kali|ubuntu|debian) wordlists_dir="/usr/share/wordlists" ;;
        macos)                     wordlists_dir="/usr/local/share/wordlists" ;;
        *)                         wordlists_dir="$HOME/.local/share/wordlists" ;;
    esac
    log_info "wordlists target: ${c_white}${wordlists_dir}${c_reset}"

    if [[ -d "$wordlists_dir/SecLists" ]]; then
        log_skip "SecLists already present"
        RESULT_SKIPPED+=("seclists")
    else
        sudo mkdir -p "$wordlists_dir"
        # Linux uses $USER:$USER; macOS uses $USER:admin.
        if [[ "$OS_TYPE" == "macos" ]]; then
            sudo chown -R "$USER":admin "$wordlists_dir"
        else
            sudo chown -R "$USER":"$USER" "$wordlists_dir"
        fi
        if sudo git clone --depth 1 https://github.com/danielmiessler/SecLists.git "$wordlists_dir/SecLists"; then
            RESULT_INSTALLED+=("seclists")
        else
            log_warning "Failed to clone SecLists"
            RESULT_FAILED+=("seclists")
        fi
    fi
}

toolchain_run
