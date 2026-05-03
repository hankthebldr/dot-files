# Security Profile (Pentesting + DFIR + Reverse Engineering)
# Loadout for Pentesting, Scanners, and Security Audits
export CLAW_PROFILE_THEME="security"

# ==========================================
# ENVIRONMENT
# ==========================================
export PENTEST_WORKSPACE="$HOME/pentest"
export WORDLISTS="${WORDLISTS:-/usr/local/share/wordlists/SecLists}"

# IMPORTANT: profile load no longer auto-creates an engagement directory or
# auto-cd's into it (footgun — selecting a profile shouldn't relocate you).
# Use `sec_engagement` to create + jump on demand. See bottom of file.

# ==========================================
# ALIASES — short, unprefixed, value-add only
# ==========================================
# (de-prefixed 2026-04-28: dropped osint-/red-/web-/net-/dfir-/rev- prefixes.
#  Pure renames (osint-nmap=nmap, dfir-exif=exiftool, rev-rad=radare2) are
#  GONE — type the real binary. Compositions kept under short mnemonics.)

# --- Recon (compositions worth keeping; guarded — get install hint if missing) ---
_claw_guard nrecon   nmap          nmap -T4 -A -v
_claw_guard nharvest theHarvester  theHarvester -d
_claw_guard amasse   amass         amass enum -d
_claw_guard subf     subfinder     subfinder -d

# --- Offensive ---
_claw_guard sqli     sqlmap        sqlmap --batch --random-agent
_claw_guard listen   nc            nc -lvnp
_claw_guard hash0    hashcat       hashcat -a 0 -m
# hydra wrapper — pre-loads admin/passwords for quick AD spraying. Override with -l/-P.
_claw_guard hydraq   hydra         hydra -l admin -P "$WORDLISTS/Passwords/Common-Credentials/10-million-password-list-top-100000.txt"

# --- Web App fuzzing wrappers (pre-load wordlists) ---
_claw_guard fuzz     ffuf          ffuf -w "$WORDLISTS/Discovery/Web-Content/raft-large-directories.txt" -u
_claw_guard gobust   gobuster      gobuster dir -w "$WORDLISTS/Discovery/Web-Content/directory-list-2.3-medium.txt" -u

# --- Network capture ---
# Capture to current dir (NOT a hardcoded engagement dir) — safer.
# Function (not alias) so $(date) re-evaluates per invocation. An alias would
# bake the load-time timestamp in once, causing every `pcap` call in the same
# session to overwrite the same file.
pcap() {
    sudo tcpdump -i any -w "./capture-$(date +%H%M%S).pcap" "$@"
}

# Note: nmap, sslyze, whatweb, wafw00f, dirb, wpscan, msfconsole,
# crackmapexec, bettercap, aircrack-ng, binwalk, foremost, exiftool,
# volatility, radare2, cstool — type the real binary.

# ==========================================
# ENGAGEMENT WORKSPACE (on-demand)
# ==========================================
sec_engagement() {
  local name="${1:-$(date +%Y-%m-%d)_engagement}"
  local dir="$PENTEST_WORKSPACE/$name"
  mkdir -p "$dir"/{scans,exploits,loot,evidence}
  cd "$dir" || return 1
  export ENGAGEMENT_DIR="$dir"
  printf "  \e[38;2;63;185;80m✓\e[0m engagement workspace: %s\n" "$dir"
  printf "  \e[38;2;139;148;158m  scans/ exploits/ loot/ evidence/\e[0m\n"
}

# ==========================================
# QUICK REFERENCE
# ==========================================
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

  printf "  ${bold}${red}Recon (composition wrappers)${reset}\n"
  printf "  ${white}nrecon${reset}    ${dim}nmap -T4 -A -v <target>${reset}\n"
  printf "  ${white}nharvest${reset}  ${dim}theHarvester -d <domain>${reset}\n"
  printf "  ${white}amasse${reset}    ${dim}amass enum -d <domain>${reset}\n"
  printf "  ${white}subf${reset}      ${dim}subfinder -d <domain>${reset}\n"
  printf "\n"
  printf "  ${bold}${red}Offensive${reset}\n"
  printf "  ${white}sqli${reset}      ${dim}sqlmap --batch --random-agent -u <url>${reset}\n"
  printf "  ${white}hash0${reset}     ${dim}hashcat -a 0 -m <mode> <hash> <wordlist>${reset}\n"
  printf "  ${white}hydraq${reset}    ${dim}hydra w/ admin + top-100k passwords${reset}\n"
  printf "  ${white}listen${reset}    ${dim}nc -lvnp <port>${reset}\n"
  printf "\n"
  printf "  ${bold}${red}Web fuzzing${reset}\n"
  printf "  ${white}fuzz${reset}      ${dim}ffuf w/ raft-large-directories${reset}\n"
  printf "  ${white}gobust${reset}    ${dim}gobuster dir w/ medium-directory-list${reset}\n"
  printf "\n"
  printf "  ${bold}${red}Capture${reset}\n"
  printf "  ${white}pcap${reset}      ${dim}sudo tcpdump → ./capture-HHMMSS.pcap${reset}\n"
  printf "\n"
  printf "  ${bold}${red}Workspace${reset}\n"
  printf "  ${white}sec_engagement${reset}  ${dim}create + cd into engagement dir${reset}\n"
  printf "                  ${dim}(NOT auto-loaded; explicit only)${reset}\n"
  printf "\n"
  printf "  ${bold}${red}Use directly${reset}  ${dim}(no profile prefix)${reset}\n"
  printf "  ${dim}nmap · sslyze · whatweb · wafw00f · dirb · wpscan · msfconsole${reset}\n"
  printf "  ${dim}crackmapexec · bettercap · aircrack-ng · binwalk · foremost${reset}\n"
  printf "  ${dim}exiftool · volatility · radare2 · cstool${reset}\n"
  printf "\n"
}

# ==========================================
# TOOL AVAILABILITY CHECK
# ==========================================
_security_tool_check() {
  local green='\e[38;2;63;185;80m'
  local red='\e[38;2;255;123;114m'
  local white='\e[38;2;201;209;217m'
  local dim='\e[38;2;139;148;158m'
  local bold='\e[1m'
  local reset='\e[0m'

  local -a tools=(
    "nmap:nmap" "metasploit:msfconsole" "sqlmap:sqlmap"
    "hashcat:hashcat" "hydra:hydra" "ffuf:ffuf" "gobuster:gobuster"
    "wireshark:tshark" "trivy:trivy" "grype:grype" "nikto:nikto"
  )
  local found=0 missing=0
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

# Backwards-compat alias (old name → new)
alias _sec_tool_check=_security_tool_check

# Profile banner handled by fastfetch (config-security.jsonc)
