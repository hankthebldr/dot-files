# shell/security.zsh - ParrotOS & Security Interoperability

# 1. Tool Aliases
alias nmapf='nmap -Pn -sCV -sS'
alias myip='curl ifconfig.me'
alias prox='proxychains4'
alias torstart='sudo service tor start'
alias torstop='sudo service tor stop'

# 2. History Security
# Prevent sensitive commands from being logged
setopt HIST_IGNORE_SPACE

# 3. Functions
function scanner() {
    if [[ -z "$1" ]]; then
        echo "Usage: scanner <target-ip>"
        return 1
    fi
    echo "Running Nmap on $1..."
    nmap -sC -sV -oA scan_$1 $1
}

# 4. Environment
export METASPLOIT_HELPER_DIR="/usr/share/metasploit-framework"
