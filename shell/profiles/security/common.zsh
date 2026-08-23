# shell/profiles/security/common.zsh
# Aliases / functions / help — work identically on macOS and Linux.
# OS-specific bits (WORDLISTS path, install hints) live in {mac,linux}.zsh.

export PENTEST_WORKSPACE="${PENTEST_WORKSPACE:-$HOME/pentest}"

# WORDLISTS path is set by {mac,linux}.zsh before this file is consumed by
# the wrappers below. If absent (no OS-family file sourced), fall back to a
# sane default that exists on most pentest distros.
export WORDLISTS="${WORDLISTS:-/usr/share/wordlists/SecLists}"

# IMPORTANT: profile load never auto-CREATES an engagement directory — use
# `sec_engagement` to carve + jump into one on demand (see below). Load-time
# relocation is a separate, declarative thing: meta.zsh's PROFILE_START_DIR
# lands you in $PENTEST_WORKSPACE when it already exists (else the vault's
# Secops folder), reversibly (`cd -`) and opt-out-able (CLAW_PROFILE_CD=0).

# ==========================================
# ALIASES — short, unprefixed, value-add only
# ==========================================

# --- Recon ---
_claw_guard nrecon   nmap          nmap -T4 -A -v
_claw_guard nharvest theHarvester  theHarvester -d
_claw_guard amasse   amass         amass enum -d
_claw_guard subf     subfinder     subfinder -d

# --- Offensive ---
_claw_guard sqli     sqlmap        sqlmap --batch --random-agent
_claw_guard listen   nc            nc -lvnp
_claw_guard hash0    hashcat       hashcat -a 0 -m
_claw_guard hydraq   hydra         hydra -l admin -P "$WORDLISTS/Passwords/Common-Credentials/10-million-password-list-top-100000.txt"

# --- Web App fuzzing wrappers ---
_claw_guard fuzz     ffuf          ffuf -w "$WORDLISTS/Discovery/Web-Content/raft-large-directories.txt" -u
_claw_guard gobust   gobuster      gobuster dir -w "$WORDLISTS/Discovery/Web-Content/directory-list-2.3-medium.txt" -u

# --- Network capture (function so $(date) re-evaluates per invocation) ---
pcap() {
    sudo tcpdump -i any -w "./capture-$(date +%H%M%S).pcap" "$@"
}

# ==========================================
# ENGAGEMENT WORKSPACE (on-demand)
# ==========================================
sec_engagement() {
    local name="${1:-$(date +%Y-%m-%d)_engagement}"
    local dir="$PENTEST_WORKSPACE/$name"
    mkdir -p "$dir"/{scans,exploits,loot,evidence}
    cd "$dir" || return 1
    export ENGAGEMENT_DIR="$dir"
    printf "  \e[38;2;57;255;20m✓\e[0m engagement workspace: %s\n" "$dir"
    printf "  \e[38;2;139;148;158m  scans/ exploits/ loot/ evidence/\e[0m\n"
}

# ==========================================
# QUICK REFERENCE
# ==========================================
sec-help() {
    local green='\e[38;2;57;255;20m'         # matrix theme green
    local dim='\e[38;2;0;100;0m'              # matrix theme dim
    local white='\e[38;2;220;255;220m'
    local red='\e[38;2;255;100;100m'
    local bold='\e[1m'
    local reset='\e[0m'

    printf "\n"
    printf "  ${green}╭──────────────────────────────────────────────────────────╮${reset}\n"
    printf "  ${green}│${reset}  ${bold}NIGHTHACKER${reset} ${dim}— Security profile  (${PROFILE_OS_SUPPORT})${reset}    ${green}│${reset}\n"
    printf "  ${green}╰──────────────────────────────────────────────────────────╯${reset}\n"
    printf "\n"
    printf "  ${bold}Recon${reset}\n"
    printf "  ${white}nrecon${reset}    ${dim}nmap -T4 -A -v${reset}\n"
    printf "  ${white}nharvest${reset}  ${dim}theHarvester -d${reset}\n"
    printf "  ${white}amasse${reset}    ${dim}amass enum -d${reset}\n"
    printf "  ${white}subf${reset}      ${dim}subfinder -d${reset}\n"
    printf "\n"
    printf "  ${bold}Offensive${reset}\n"
    printf "  ${white}sqli${reset}      ${dim}sqlmap --batch --random-agent${reset}\n"
    printf "  ${white}listen${reset}    ${dim}nc -lvnp${reset}\n"
    printf "  ${white}hash0${reset}     ${dim}hashcat -a 0 -m${reset}\n"
    printf "  ${white}hydraq${reset}    ${dim}hydra (pre-loaded admin/passwords)${reset}\n"
    printf "\n"
    printf "  ${bold}Web fuzzing${reset}  ${dim}(pre-loaded SecLists)${reset}\n"
    printf "  ${white}fuzz${reset}      ${dim}ffuf -w raft-large-directories.txt${reset}\n"
    printf "  ${white}gobust${reset}    ${dim}gobuster dir -w directory-list-2.3-medium${reset}\n"
    printf "\n"
    printf "  ${bold}Capture${reset}\n"
    printf "  ${white}pcap${reset}      ${dim}sudo tcpdump → ./capture-HHMMSS.pcap${reset}\n"
    printf "\n"
    printf "  ${bold}Workspace${reset}\n"
    printf "  ${white}sec_engagement${reset}  ${dim}create + cd into engagement dir${reset}\n"
    printf "                  ${dim}(NOT auto-loaded; explicit only)${reset}\n"
    printf "\n"
    printf "  ${bold}Use directly${reset}  ${dim}(no profile prefix)${reset}\n"
    printf "  ${dim}nmap · sslyze · whatweb · wafw00f · dirb · wpscan · msfconsole${reset}\n"
    printf "  ${dim}crackmapexec · bettercap · aircrack-ng · binwalk · foremost${reset}\n"
    printf "  ${dim}exiftool · volatility · radare2 · cstool${reset}\n"
    printf "\n"
    printf "  ${bold}Env${reset}    ${white}WORDLISTS${reset}=${dim}${WORDLISTS}${reset}\n"
    printf "\n"
}

# ==========================================
# TOOL AVAILABILITY CHECK
# ==========================================
_security_tool_check() {
    local green='\e[38;2;57;255;20m'
    local red='\e[38;2;255;100;100m'
    local white='\e[38;2;220;255;220m'
    local dim='\e[38;2;0;100;0m'
    local bold='\e[1m'
    local reset='\e[0m'

    local -a tools=(
        "nmap:nmap" "metasploit:msfconsole" "sqlmap:sqlmap"
        "hashcat:hashcat" "hydra:hydra" "ffuf:ffuf" "gobuster:gobuster"
        "wireshark:tshark" "trivy:trivy" "grype:grype" "nikto:nikto"
    )
    local found=0 missing=0
    local total=${#tools[@]}

    printf "\n  ${bold}${white}NIGHTHACKER Toolchain Status${reset}  ${dim}(${OS_FAMILY:-?})${reset}\n"
    printf "  ${dim}─────────────────────────${reset}\n"
    for entry in "${tools[@]}"; do
        local label="${entry%%:*}"
        local cmd="${entry##*:}"
        if command -v "$cmd" &> /dev/null; then
            printf "  ${green}●${reset}  ${white}%-14s${reset} ${dim}$(command -v "$cmd")${reset}\n" "$label"
            ((found++))
        else
            local hint="$(_security_install_hint "$label")"
            printf "  ${red}✗${reset}  ${white}%-14s${reset} ${dim}${hint}${reset}\n" "$label"
            ((missing++))
        fi
    done
    printf "\n  ${dim}${found}/${total} tools available"
    if (( missing > 0 )); then
        printf " ${red}(${missing} missing)${reset}"
    fi
    printf "${reset}\n\n"
}

# Backwards-compat alias (old name → new)
alias _sec_tool_check=_security_tool_check
