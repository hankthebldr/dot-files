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

    # ── 07. LLM / AI Security ──────────────────────────────────────────────
    "garak|garak|?|pipx|NVIDIA LLM vulnerability scanner (prompt-injection/jailbreak probes)"

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

    # ── Harness Tier 0 ─────────────────────────────────────────────────────
    # The package map is NOT restated here. config/security/tools.yaml already
    # carries kali/debian/darwin packages per tool, `claw sec doctor` asserts
    # identity against the same file, and a second copy in this array is a copy
    # that drifts. Read the registry instead.
    #
    # These traps are why the registry exists (§13): Kali ships the scanner as
    # httpx-toolkit while `pipx install httpx` silently shadows it with a
    # Python HTTP client; naabu degrades to a connect scan without libpcap-dev
    # and CAP_NET_RAW. Presence is not identity — verify with `claw sec doctor`.
    _section 8 "Security  Harness  (Tier  0)"
    local reg="$DOTFILES_DIR/config/security/tools.yaml"
    if [[ ! -r "$reg" ]]; then
        log_skip "registry not found — skipping harness chain ($reg)"
        RESULT_SKIPPED+=("sec-harness-tier0")
    elif ! command -v python3 &>/dev/null; then
        log_skip "python3 missing — cannot read the tool registry"
        RESULT_SKIPPED+=("sec-harness-tier0")
    else
        local _key
        case "$OS_TYPE" in
            kali|parrot) _key=kali ;;
            macos)       _key=darwin ;;
            *)           _key=debian ;;
        esac
        local _rows
        _rows="$(CLAW_REG="$reg" CLAW_KEY="$_key" python3 - <<'PY' 2>/dev/null || true
import os, yaml
reg = yaml.safe_load(open(os.environ["CLAW_REG"])) or {}
for name, spec in reg.items():
    pkg = (spec.get("packages") or {}).get(os.environ["CLAW_KEY"])
    if pkg:
        print(f"{name}\t{pkg}")
PY
)"
        if [[ -z "$_rows" ]]; then
            log_warning "could not read packages from the registry"
            RESULT_FAILED+=("sec-harness-tier0")
        fi
        local _name _pkg
        while IFS=$'\t' read -r _name _pkg; do
            [[ -n "$_name" ]] || continue
            if command -v "$_name" &>/dev/null; then
                log_skip "$_name present — verify identity with: claw sec doctor $_name"
                RESULT_SKIPPED+=("$_name")
                continue
            fi
            log_info "installing $_name ($_pkg)"
            # The registry's debian values already carry @latest.
            case "$_pkg" in
                go:*)
                    if command -v go &>/dev/null && _run go install "${_pkg#go:}"; then
                        RESULT_INSTALLED+=("$_name (go)")
                    else
                        log_warning "$_name: go install failed (is the Go toolchain present?)"
                        RESULT_FAILED+=("$_name")
                    fi
                    ;;
                *)
                    if [[ "$PKG_MANAGER" == "brew" ]]; then
                        _run brew install "$_pkg"
                    else
                        _run sudo apt-get install -y "$_pkg"
                    fi && RESULT_INSTALLED+=("$_name ($_pkg)") || {
                        log_warning "$_name: installing $_pkg failed"
                        RESULT_FAILED+=("$_name")
                    }
                    ;;
            esac
        done <<< "$_rows"

        # naabu's raw-socket capability is the difference between the scan the
        # operator thinks they ran and a quieter, slower connect scan.
        if command -v naabu &>/dev/null && [[ "$OS_TYPE" != "macos" ]] \
           && command -v setcap &>/dev/null; then
            _run sudo setcap cap_net_raw+eip "$(command -v naabu)" 2>/dev/null \
                || log_warning "naabu: setcap failed — it will degrade to a connect scan"
        fi
        log_info "verify identity, not presence: ${c_white}claw sec doctor${c_reset}"
    fi

    _section 9 "Wordlists  (SecLists)"
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
