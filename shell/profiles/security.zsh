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
alias net-dump="sudo tcpdump -i en0 -w $ENGAGEMENT_DIR/loot/capture.pcap"
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

# Profile banner handled by fastfetch (config-security.jsonc)
