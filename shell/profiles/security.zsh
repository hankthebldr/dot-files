# Security Profile (Parrot OS Toolset)
# Loadout for Pentesting, Scanners, and Security Audits
export CLAW_PROFILE_THEME="security"

# ==========================================
# ENVIRONMENT VARIABLES
# ==========================================
export PENTEST_WORKSPACE="$HOME/pentest"
export WORDLISTS="/usr/local/share/wordlists/SecLists"

# Auto-create engagement directory structure
ENGAGEMENT_NAME=$(date +"%Y-%m-%d_engagement")
ENGAGEMENT_DIR="$PENTEST_WORKSPACE/$ENGAGEMENT_NAME"
mkdir -p "$ENGAGEMENT_DIR"/{scans,exploits,loot,evidence}

# Automatically jump to the engagement directory
cd "$ENGAGEMENT_DIR" || true

# ==========================================
# CATEGORIZED ALIASES
# ==========================================

# --- 1. OSINT / Reconnaissance ---
alias osint-nmap="nmap -T4 -A -v"
alias osint-recon="theHarvester -d"
alias osint-amass="amass enum -d"
alias osint-sub="subfinder -d"
alias osint-what="whatweb -v"
alias osint-ssl="sslyze --regular"

# --- 2. Red Team / Offensive ---
alias red-msf="msfconsole"
alias red-sql="sqlmap --batch --random-agent"
alias red-cme="crackmapexec"
alias red-hash="hashcat -a 0 -m"
alias red-hydra="hydra -l admin -P $WORDLISTS/Passwords/Common-Credentials/10-million-password-list-top-100000.txt"
alias red-listen="nc -lvnp"

# --- 3. Web App Interrogation ---
alias web-ffuf="ffuf -w $WORDLISTS/Discovery/Web-Content/raft-large-directories.txt -u"
alias web-go="gobuster dir -w $WORDLISTS/Discovery/Web-Content/directory-list-2.3-medium.txt -u"
alias web-dir="dirb"
alias web-wp="wpscan --url"
alias web-waf="wafw00f"

# --- 4. Network & Spoofing ---
alias net-dump="sudo tcpdump -i any -w $ENGAGEMENT_DIR/loot/capture.pcap"
alias net-better="sudo bettercap"
alias net-air="sudo aircrack-ng"

# --- 5. Digital Forensics ---
alias dfir-bin="binwalk -e"
alias dfir-fore="foremost -i"
alias dfir-exif="exiftool"
alias dfir-vol="volatility -f"

# --- 6. Reverse Engineering ---
alias rev-rad="radare2"
alias rev-cap="cstool"

# ==========================================
# HELPER FUNCTIONS
# ==========================================

# Styled quick-reference card for all security aliases
sec-help() {
  local red='\e[38;2;255;123;114m'
  local purple='\e[38;2;188;140;255m'
  local dim='\e[38;2;139;148;158m'
  local white='\e[38;2;201;209;217m'
  local bold='\e[1m'
  local reset='\e[0m'

  printf "\n"
  printf "  ${purple}╭──────────────────────────────────────────────────────────╮${reset}\n"
  printf "  ${purple}│${reset}  ${bold}${red}SECURITY PROFILE${reset} ${dim}— Quick Reference${reset}                      ${purple}│${reset}\n"
  printf "  ${purple}╰──────────────────────────────────────────────────────────╯${reset}\n"
  printf "\n"

  printf "  ${bold}${red}1. OSINT / Reconnaissance${reset}\n"
  printf "  ${white}osint-nmap${reset}    ${dim}nmap -T4 -A -v${reset}\n"
  printf "  ${white}osint-recon${reset}   ${dim}theHarvester -d${reset}\n"
  printf "  ${white}osint-amass${reset}   ${dim}amass enum -d${reset}\n"
  printf "  ${white}osint-sub${reset}     ${dim}subfinder -d${reset}\n"
  printf "  ${white}osint-what${reset}    ${dim}whatweb -v${reset}\n"
  printf "  ${white}osint-ssl${reset}     ${dim}sslyze --regular${reset}\n"
  printf "\n"

  printf "  ${bold}${red}2. Red Team / Offensive${reset}\n"
  printf "  ${white}red-msf${reset}       ${dim}msfconsole${reset}\n"
  printf "  ${white}red-sql${reset}       ${dim}sqlmap --batch --random-agent${reset}\n"
  printf "  ${white}red-cme${reset}       ${dim}crackmapexec${reset}\n"
  printf "  ${white}red-hash${reset}      ${dim}hashcat -a 0 -m${reset}\n"
  printf "  ${white}red-hydra${reset}     ${dim}hydra brute-force${reset}\n"
  printf "  ${white}red-listen${reset}    ${dim}nc -lvnp${reset}\n"
  printf "\n"

  printf "  ${bold}${red}3. Web App Interrogation${reset}\n"
  printf "  ${white}web-ffuf${reset}      ${dim}ffuf directory fuzzing${reset}\n"
  printf "  ${white}web-go${reset}        ${dim}gobuster directory brute${reset}\n"
  printf "  ${white}web-dir${reset}       ${dim}dirb${reset}\n"
  printf "  ${white}web-wp${reset}        ${dim}wpscan --url${reset}\n"
  printf "  ${white}web-waf${reset}       ${dim}wafw00f${reset}\n"
  printf "\n"

  printf "  ${bold}${red}4. Network & Spoofing${reset}\n"
  printf "  ${white}net-dump${reset}      ${dim}tcpdump capture to pcap${reset}\n"
  printf "  ${white}net-better${reset}    ${dim}bettercap${reset}\n"
  printf "  ${white}net-air${reset}       ${dim}aircrack-ng${reset}\n"
  printf "\n"

  printf "  ${bold}${red}5. Digital Forensics${reset}\n"
  printf "  ${white}dfir-bin${reset}      ${dim}binwalk -e${reset}\n"
  printf "  ${white}dfir-fore${reset}     ${dim}foremost -i${reset}\n"
  printf "  ${white}dfir-exif${reset}     ${dim}exiftool${reset}\n"
  printf "  ${white}dfir-vol${reset}      ${dim}volatility -f${reset}\n"
  printf "\n"

  printf "  ${bold}${red}6. Reverse Engineering${reset}\n"
  printf "  ${white}rev-rad${reset}       ${dim}radare2${reset}\n"
  printf "  ${white}rev-cap${reset}       ${dim}cstool${reset}\n"
  printf "\n"
}

# Check availability of core security tools
_sec_tool_check() {
  local green='\e[38;2;63;185;80m'
  local red='\e[38;2;255;123;114m'
  local white='\e[38;2;201;209;217m'
  local dim='\e[38;2;139;148;158m'
  local bold='\e[1m'
  local reset='\e[0m'

  local -a tools=(
    "nmap:nmap"
    "metasploit:msfconsole"
    "sqlmap:sqlmap"
    "hashcat:hashcat"
    "hydra:hydra"
    "ffuf:ffuf"
    "gobuster:gobuster"
    "wireshark:tshark"
    "trivy:trivy"
    "grype:grype"
    "nikto:nikto"
  )

  local found=0
  local missing=0
  local total=${#tools[@]}

  printf "\n  ${bold}${white}Security Toolchain Status${reset}\n"
  printf "  ${dim}─────────────────────────${reset}\n"

  for entry in "${tools[@]}"; do
    local label="${entry%%:*}"
    local cmd="${entry##*:}"
    if command -v "$cmd" &> /dev/null; then
      printf "  ${green}●${reset}  ${white}%-14s${reset} ${dim}$(command -v "$cmd")${reset}\n" "$label"
      ((found++))
    else
      printf "  ${red}✗${reset}  ${white}%-14s${reset} ${dim}not found${reset}\n" "$label"
      ((missing++))
    fi
  done

  printf "\n  ${dim}${found}/${total} tools available"
  if (( missing > 0 )); then
    printf " ${red}(${missing} missing)${reset}"
  fi
  printf "${reset}\n\n"
}

# Profile banner handled by fastfetch (config-security.jsonc)
