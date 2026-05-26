#!/bin/bash

################################################################################
# ZSH Configuration Additions for Poweruser Setup
# Description: Append these configurations to your ~/.zshrc
# Usage: cat zshrc-poweruser-additions.sh >> ~/.zshrc
#        OR bash zshrc-poweruser-additions.sh (auto-append with backup)
################################################################################

ZSHRC="$HOME/.zshrc"
BACKUP="$HOME/.zshrc.backup.$(date +%Y%m%d_%H%M%S)"

# Function to append to zshrc
append_to_zshrc() {
    # Create backup
    cp "$ZSHRC" "$BACKUP"
    echo "Backup created: $BACKUP"

    # Append configurations
    cat << 'EOF' >> "$ZSHRC"

################################################################################
# POWERUSER ADDITIONS - Added $(date +%Y-%m-%d)
################################################################################

# ============================================================================
# OH MY ZSH CONFIGURATION
# ============================================================================

# Path to oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Theme - using starship instead
# ZSH_THEME="robbyrussell"

# Plugins
plugins=(
  git
  docker
  docker-compose
  kubectl
  terraform
  aws
  gcloud
  python
  poetry
  rust
  golang
  npm
  yarn
  sudo
  command-not-found
  zsh-autosuggestions
  zsh-syntax-highlighting
  you-should-use
  fzf
  z
)

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

# ============================================================================
# PATH CONFIGURATION
# ============================================================================

# Homebrew
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/sbin:$PATH"

# Local binaries
export PATH="$HOME/.local/bin:$PATH"

# GNU coreutils (use GNU versions over BSD)
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/findutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-tar/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/grep/libexec/gnubin:$PATH"

# Programming languages
export PATH="$HOME/.cargo/bin:$PATH"                    # Rust
export PATH="$HOME/go/bin:$PATH"                        # Go
export PATH="$HOME/.pyenv/bin:$PATH"                    # Python

# ============================================================================
# MODERN CLI REPLACEMENTS
# ============================================================================

# Core utilities
alias ls='eza --icons --group-directories-first'
alias ll='eza -lah --icons --group-directories-first --git'
alias la='eza -a --icons --group-directories-first'
alias lt='eza --tree --level=2 --icons'
alias cat='bat --style=auto'
alias find='fd'
alias grep='rg'
alias top='btop'
alias htop='btop'
alias du='dust'
alias df='duf'
alias ps='procs'
alias dig='dog'

# Git aliases with delta
alias gd='git diff'
alias gds='git diff --staged'
alias glog='git log --graph --oneline --decorate'

# ============================================================================
# SAFETY NETS
# ============================================================================

# Safer file operations
alias rm='trash'                # Use trash instead of rm
alias cp='cp -iv'               # Interactive, verbose
alias mv='mv -iv'               # Interactive, verbose
alias mkdir='mkdir -pv'         # Create parent dirs, verbose
alias ln='ln -i'                # Interactive

# Prevent common mistakes
alias chown='chown --preserve-root'
alias chmod='chmod --preserve-root'
alias chgrp='chgrp --preserve-root'

# ============================================================================
# NAVIGATION & DIRECTORY SHORTCUTS
# ============================================================================

# Zoxide (smarter cd)
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
    alias cd='z'
fi

# Quick directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'

# Directory shortcuts (customize these)
alias proj='cd ~/Projects'
alias dl='cd ~/Downloads'
alias docs='cd ~/Documents'
alias desk='cd ~/Desktop'

# ============================================================================
# FZF CONFIGURATION
# ============================================================================

if [ -f ~/.fzf.zsh ]; then
    source ~/.fzf.zsh
fi

# Use fd for fzf
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'

# FZF preview with bat
export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range :500 {}'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=1 {}'"

# FZF color scheme
export FZF_DEFAULT_OPTS='
  --color=fg:#e0def4,bg:#191724,hl:#31748f
  --color=fg+:#e0def4,bg+:#26233a,hl+:#31748f
  --color=border:#403d52,header:#31748f,gutter:#191724
  --color=spinner:#f6c177,info:#9ccfd8
  --color=pointer:#c4a7e7,marker:#eb6f92,prompt:#908caa
  --height 40% --layout=reverse --border
'

# ============================================================================
# HISTORY CONFIGURATION
# ============================================================================

export HISTFILE=~/.zsh_history
export HISTSIZE=1000000
export SAVEHIST=1000000

setopt EXTENDED_HISTORY          # Write timestamp to history
setopt HIST_IGNORE_ALL_DUPS      # Remove old duplicates
setopt HIST_FIND_NO_DUPS         # Don't show duplicates in search
setopt HIST_REDUCE_BLANKS        # Remove extra blanks
setopt HIST_IGNORE_SPACE         # Don't save commands starting with space
setopt SHARE_HISTORY             # Share history across sessions
setopt APPEND_HISTORY            # Append to history
setopt INC_APPEND_HISTORY        # Append immediately

# ============================================================================
# PROMPT CONFIGURATION
# ============================================================================

# Starship prompt
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
fi

# Atuin (better history sync)
if command -v atuin &> /dev/null; then
    eval "$(atuin init zsh)"
fi

# ============================================================================
# ENVIRONMENT VARIABLES
# ============================================================================

# Default editor
export EDITOR='nvim'
export VISUAL='nvim'

# Prefer US English and UTF-8
export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

# Colored man pages
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export MANROFFOPT="-c"

# BAT configuration
export BAT_THEME="Monokai Extended"

# Ripgrep configuration
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# Less configuration
export LESS='-R -F -X'
export LESSOPEN='|~/.lessfilter %s'

# Python
if command -v pyenv &> /dev/null; then
    eval "$(pyenv init -)"
fi

# Node.js
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# Go
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"

# Rust
export CARGO_HOME="$HOME/.cargo"

# ============================================================================
# DOCKER & KUBERNETES
# ============================================================================

alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dexec='docker exec -it'
alias dlogs='docker logs -f'
alias dclean='docker system prune -af'

alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kdel='kubectl delete'
alias kl='kubectl logs -f'
alias kex='kubectl exec -it'
alias kctx='kubectx'
alias kns='kubens'

# ============================================================================
# GIT ALIASES
# ============================================================================

alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -v'
alias gcm='git commit -m'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gb='git branch'
alias gba='git branch -a'
alias gst='git status'
alias gp='git push'
alias gpl='git pull'
alias gf='git fetch'
alias gl='git log --oneline --graph --decorate'
alias gla='git log --oneline --graph --decorate --all'
alias gclean='git clean -fd'
alias greset='git reset --hard'
alias gstash='git stash'
alias gpop='git stash pop'

# ============================================================================
# SECURITY TOOLS ALIASES
# ============================================================================

# Network scanning
alias nmap-quick='nmap -T4 -F'
alias nmap-full='nmap -T4 -A -v'
alias nmap-vuln='nmap --script vuln'

# Web security
alias nikto-scan='nikto -h'
alias whatweb-scan='whatweb -a 3'

# Password cracking
alias hashcat-list='hashcat --help | grep -i mode'
alias john-list='john --list=formats'

# Network analysis
alias sniff='sudo tcpdump -i any -n'
alias httpdump='sudo tcpdump -i any -A -s 0 "tcp port 80"'

# SSL/TLS testing
alias testssl-scan='testssl.sh --fast'
alias sslyze-scan='sslyze --regular'

# ============================================================================
# DEVELOPMENT ALIASES
# ============================================================================

# Python
alias py='python3'
alias pip='pip3'
alias venv='python3 -m venv'
alias activate='source venv/bin/activate'

# Node.js
alias ni='npm install'
alias nid='npm install --save-dev'
alias nig='npm install -g'
alias nr='npm run'
alias nt='npm test'
alias yi='yarn install'
alias ya='yarn add'
alias yr='yarn remove'

# Terraform
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfv='terraform validate'

# Ansible
alias ap='ansible-playbook'
alias av='ansible-vault'

# ============================================================================
# SYSTEM UTILITIES
# ============================================================================

# System information
alias sysinfo='neofetch'
alias cpu='sysctl -n machdep.cpu.brand_string'
alias mem='top -l 1 -s 0 | grep PhysMem'
alias disk='df -h'
alias ports='sudo lsof -iTCP -sTCP:LISTEN -n -P'

# Network utilities
alias myip='curl -s https://ifconfig.me'
alias localip='ipconfig getifaddr en0'
alias speedtest='speedtest-cli'
alias ping='gping'

# Process management
alias pgrep='procs'
alias killall='pkill -f'

# ============================================================================
# HOMEBREW ALIASES
# ============================================================================

alias brewup='brew update && brew upgrade && brew cleanup'
alias brewinfo='brew info'
alias brewlist='brew list'
alias brewsearch='brew search'
alias brewdoctor='brew doctor'

# ============================================================================
# CUSTOM FUNCTIONS
# ============================================================================

# Create and enter directory
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract any archive
extract() {
    if [ -f $1 ]; then
        case $1 in
            *.tar.bz2)   tar xjf $1     ;;
            *.tar.gz)    tar xzf $1     ;;
            *.bz2)       bunzip2 $1     ;;
            *.rar)       unrar e $1     ;;
            *.gz)        gunzip $1      ;;
            *.tar)       tar xf $1      ;;
            *.tbz2)      tar xjf $1     ;;
            *.tgz)       tar xzf $1     ;;
            *.zip)       unzip $1       ;;
            *.Z)         uncompress $1  ;;
            *.7z)        7z x $1        ;;
            *)           echo "'$1' cannot be extracted" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Find process by name
psgrep() {
    procs | grep -i "$1"
}

# Quick server
serve() {
    local port="${1:-8000}"
    python3 -m http.server "$port"
}

# Git clone and cd
gclone() {
    git clone "$1" && cd "$(basename "$1" .git)"
}

# Create backup of file
backup() {
    cp "$1"{,.backup-$(date +%Y%m%d-%H%M%S)}
}

# Quick notes
note() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $*" >> "$HOME/notes.txt"
}

# Weather
weather() {
    curl -s "wttr.in/${1:-}"
}

# Cheat sheet
cheat() {
    curl -s "cheat.sh/$1"
}

# URL encode/decode
urlencode() {
    python3 -c "import sys, urllib.parse as ul; print(ul.quote_plus(sys.argv[1]))" "$1"
}

urldecode() {
    python3 -c "import sys, urllib.parse as ul; print(ul.unquote_plus(sys.argv[1]))" "$1"
}

# JSON pretty print
json() {
    if [ -t 0 ]; then
        jq '.' "$1"
    else
        jq '.'
    fi
}

# Base64 encode/decode
b64encode() {
    echo -n "$1" | base64
}

b64decode() {
    echo -n "$1" | base64 -d
}

# Port check
portcheck() {
    nc -zv "$1" "$2"
}

# Docker cleanup
dcleanup() {
    docker system prune -af --volumes
    docker image prune -af
}

# Kubernetes context switch with fzf
kctx-fzf() {
    kubectl config get-contexts -o name | fzf | xargs kubectl config use-context
}

# Find large files
findlarge() {
    du -ah "${1:-.}" | sort -rh | head -n "${2:-20}"
}

# ============================================================================
# COMPLETION CONFIGURATION
# ============================================================================

# Enable completion
autoload -Uz compinit
compinit

# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Completion colors
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Completion menu
zstyle ':completion:*' menu select

# Cache completion
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache

# ============================================================================
# SECURITY CONFIGURATIONS
# ============================================================================

# Disable core dumps
ulimit -c 0

# Secure umask
umask 077

# ============================================================================
# PERFORMANCE OPTIMIZATIONS
# ============================================================================

# Lazy load nvm (faster startup)
lazy_load_nvm() {
    unset -f node npm nvm
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

# Replace node, npm, nvm with lazy loading
node() {
    lazy_load_nvm
    node "$@"
}

npm() {
    lazy_load_nvm
    npm "$@"
}

nvm() {
    lazy_load_nvm
    nvm "$@"
}

# ============================================================================
# WELCOME MESSAGE
# ============================================================================

# Optional: Display system info on new terminal
# neofetch

echo "🚀 Poweruser environment loaded!"
echo "Run 'alias' to see available shortcuts"

################################################################################
# END POWERUSER ADDITIONS
################################################################################
EOF

    echo "Configuration appended to $ZSHRC"
    echo "Reload with: source ~/.zshrc"
}

# Check if script is being executed or sourced
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    echo "This will append poweruser configurations to your ~/.zshrc"
    echo "A backup will be created automatically."
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        append_to_zshrc
    else
        echo "Cancelled. To manually append, run: cat $0 >> ~/.zshrc"
    fi
fi
