# ============================================
# OPTIMIZED ZSH ALIASES & FUNCTIONS
# Generated: 2025-10-16
# For: macOS Production Laptop & ParrotOS Interoperability
# ============================================

# ============================================
# MODERN CLI REPLACEMENTS
# ============================================

# File operations (waiting for eza install, using enhanced ls)
alias ls='ls -G'                        # macOS color
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias lt='ls -lhtr'                     # Sort by time

# Better cat/grep/find (using installed tools)
alias cat='bat --paging=never'
alias catp='bat'                        # With paging
alias catn='bat --style=plain'          # No decorations
alias grep='rg'
alias gi='rg -i'                        # Case insensitive
alias rga='rg --hidden --no-ignore'     # Search all files

# Git with delta (already installed!)
alias diff='delta'

# System monitoring
alias top='btop'
alias htop='btop'
alias cpu='btop'

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -pv'

# Tree with color
alias tree='tree -C'

# ============================================
# KUBERNETES & DOCKER
# ============================================

# Kubectl shortcuts
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kgd='kubectl get deployments'
alias kd='kubectl describe'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'
alias kctx='kubectl config current-context'
alias kns='kubectl config set-context --current --namespace'
alias kga='kubectl get all'
alias kdel='kubectl delete'
alias kapply='kubectl apply -f'

# Helm shortcuts
alias h='helm'
alias hls='helm list'
alias hlsa='helm list -A'
alias hi='helm install'
alias hu='helm upgrade'
alias hd='helm delete'
alias hs='helm search'
alias hh='helm show values'

# Docker shortcuts
alias d='docker'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dex='docker exec -it'
alias dl='docker logs'
alias dlf='docker logs -f'
alias dprune='docker system prune -af'
alias drmi='docker rmi $(docker images -q)'
alias drm='docker rm $(docker ps -aq)'
alias dstop='docker stop $(docker ps -q)'

# Docker Compose
alias dc='docker-compose'
alias dcu='docker-compose up -d'
alias dcd='docker-compose down'
alias dcl='docker-compose logs -f'
alias dcr='docker-compose restart'
alias dcp='docker-compose ps'

# Minikube
alias mk='minikube'
alias mks='minikube start'
alias mkst='minikube status'
alias mkstop='minikube stop'
alias mkdel='minikube delete'

# ============================================
# CLOUD PLATFORMS
# ============================================

# AWS
alias awswho='aws sts get-caller-identity'
alias awsls='aws s3 ls'
alias awsprofiles='aws configure list-profiles'

# GCloud
alias gcwho='gcloud config get-value account'
alias gcproj='gcloud config get-value project'
alias gclist='gcloud projects list'
alias gcconf='gcloud config list'

# Terraform
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfaa='terraform apply -auto-approve'
alias tfd='terraform destroy'
alias tfda='terraform destroy -auto-approve'
alias tfo='terraform output'
alias tfv='terraform validate'
alias tff='terraform fmt -recursive'
alias tfw='terraform workspace'
alias tfwl='terraform workspace list'
alias tfs='terraform state'
alias tfsl='terraform state list'

# Vault
alias vl='vault login'
alias vr='vault read'
alias vw='vault write'
alias vls='vault list'
alias vs='vault status'

# ============================================
# GIT ALIASES (complement oh-my-zsh git plugin)
# ============================================

# Quick status and logs
alias gs='git status -sb'
alias gst='git status'
alias gl='git log --oneline --graph --decorate -20'
alias gla='git log --oneline --graph --decorate --all -20'
alias glp='git log -p'
alias gll='git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'

# GitHub CLI
alias ghpr='gh pr create'
alias ghpv='gh pr view'
alias ghpl='gh pr list'
alias ghpc='gh pr checkout'
alias ghpm='gh pr merge'
alias ghi='gh issue list'
alias ghiv='gh issue view'
alias ghic='gh issue create'
alias ghr='gh repo view --web'

# GitLab CLI
alias glpr='glab mr create'
alias glmr='glab mr create'
alias glml='glab mr list'
alias glmv='glab mr view'

# Git shortcuts
alias ga='git add'
alias gaa='git add .'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gcan='git commit --amend --no-edit'
alias gcf='git commit --fixup'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull'
alias gplr='git pull --rebase'
alias gf='git fetch'
alias gfa='git fetch --all'
alias gr='git rebase'
alias gri='git rebase -i'
alias grc='git rebase --continue'
alias gra='git rebase --abort'
alias grs='git restore'
alias grst='git restore --staged'
alias gsw='git switch'
alias gswc='git switch -c'
alias gd='git diff'
alias gds='git diff --staged'
alias gsh='git stash'
alias gshp='git stash pop'
alias gshl='git stash list'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gbD='git branch -D'
alias gm='git merge'
alias gma='git merge --abort'
alias gt='git tag'
alias gta='git tag -a'

# ============================================
# DEVELOPMENT
# ============================================

# Python
alias py='python3'
alias pip='pip3'
alias venv='python3 -m venv'
alias activate='source venv/bin/activate'
alias deactivate='deactivate'
alias jl='jupyter lab'
alias jn='jupyter notebook'
alias pipr='pip install -r requirements.txt'
alias pipf='pip freeze > requirements.txt'

# Node/NPM
alias ni='npm install'
alias nid='npm install --save-dev'
alias nr='npm run'
alias ns='npm start'
alias nt='npm test'
alias nb='npm run build'
alias nci='rm -rf node_modules package-lock.json && npm install'
alias nls='npm list --depth=0'
alias nog='npm outdated --global'

# Yarn
alias y='yarn'
alias yi='yarn install'
alias yr='yarn run'
alias ys='yarn start'
alias yb='yarn build'
alias yt='yarn test'
alias ya='yarn add'
alias yad='yarn add --dev'
alias yug='yarn upgrade'

# Go
alias gor='go run'
alias gob='go build'
alias got='go test'
alias gom='go mod'
alias gomt='go mod tidy'
alias gomi='go mod init'
alias gog='go get'

# Task runner
alias t='task'
alias tl='task --list'

# ============================================
# PRODUCTIVITY
# ============================================

# File search with fzf
alias f='fzf --preview "bat --color=always {}"'
alias fv='vim $(fzf --preview "bat --color=always {}")'

# JSON processing
alias json='jq'
alias jsonp='jq "."'
alias jsonc='jq -c'

# Quick help
alias h='tldr'
alias halp='tldr'
alias cheat='tldr'

# System info
alias info='neofetch'
alias sysinfo='neofetch'
alias fetch='neofetch'

# Network
alias myip='curl -s ifconfig.me'
alias localip='ipconfig getifaddr en0'
alias ips='ifconfig | grep "inet " | grep -v 127.0.0.1'
alias ping='ping -c 5'
alias speed='networkQuality'
alias ports='lsof -i -P -n | grep LISTEN'

# Tmux shortcuts
alias ta='tmux attach -t'
alias tad='tmux attach -d -t'
alias ts='tmux new-session -s'
alias tl='tmux list-sessions'
alias tksv='tmux kill-server'
alias tkss='tmux kill-session -t'

# Quick edits
alias zshrc='$EDITOR ~/.zshrc'
alias reload='source ~/.zshrc'
alias aliases='$EDITOR ~/.config/zsh/aliases.zsh'
alias vimrc='$EDITOR ~/.vimrc'

# Package management
alias brewup='brew update && brew upgrade && brew cleanup'
alias brewdump='brew bundle dump --force --file=~/Github/Github_desktop/dot-files/Brewfile'
alias brewlist='brew list --formula'
alias brewcask='brew list --cask'
alias brewinfo='brew info'
alias brewsearch='brew search'

# Disk usage
alias du='du -h'
alias df='df -h'
alias ducks='du -cksh * | sort -hr | head -15'

# History
alias hist='history'
alias histg='history | grep'

# ============================================
# SECURITY & SCANNING
# ============================================

# Nmap shortcuts
alias nmap-quick='nmap -T4 -F'
alias nmap-full='nmap -T4 -A -v'
alias nmap-vuln='nmap --script vuln'
alias nmap-ping='nmap -sn'

# Checkov (IaC security)
alias ckv='checkov'
alias ckvtf='checkov -f terraform'
alias ckvd='checkov -d .'

# OpenSSL
alias certinfo='openssl x509 -text -noout -in'
alias certdates='openssl x509 -noout -dates -in'

# SSH
alias sshconfig='$EDITOR ~/.ssh/config'
alias sshkey='cat ~/.ssh/id_rsa.pub | pbcopy && echo "SSH key copied to clipboard"'

# ============================================
# MACOS SPECIFIC
# ============================================

# Clipboard
alias copy='pbcopy'
alias paste='pbpaste'

# Finder
alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'

# Clean up
alias cleanup='find . -type f -name "*.DS_Store" -ls -delete'
alias emptytrash='sudo rm -rfv /Volumes/*/.Trashes; sudo rm -rfv ~/.Trash'

# Lock screen
alias lock='/System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -suspend'

# ============================================
# SMART FUNCTIONS
# ============================================

# Create and enter directory
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract any archive
extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2) tar xjf "$1" ;;
            *.tar.gz) tar xzf "$1" ;;
            *.bz2) bunzip2 "$1" ;;
            *.rar) unrar x "$1" ;;
            *.gz) gunzip "$1" ;;
            *.tar) tar xf "$1" ;;
            *.tbz2) tar xjf "$1" ;;
            *.tgz) tar xzf "$1" ;;
            *.zip) unzip "$1" ;;
            *.Z) uncompress "$1" ;;
            *.7z) 7z x "$1" ;;
            *) echo "'$1' cannot be extracted" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Find process by name
psgrep() {
    ps aux | grep -v grep | grep -i -e VSZ -e "$1"
}

# Git commit and push (unalias gcp from git plugin first)
unalias gcp 2>/dev/null
gcpush() {
    git add .
    git commit -m "$1"
    git push
}

# Git quick commit (commit all with message)
gcap() {
    git add .
    git commit -m "$1"
    git push
}

# Docker cleanup
dclean() {
    echo "Cleaning Docker..."
    docker system prune -af
    docker volume prune -f
    echo "Docker cleaned!"
}

# K8s context switcher with fzf
kctx-switch() {
    local ctx
    ctx=$(kubectl config get-contexts -o name | fzf --height 40% --reverse)
    if [ -n "$ctx" ]; then
        kubectl config use-context "$ctx"
    fi
}

# K8s namespace switcher with fzf
kns-switch() {
    local ns
    ns=$(kubectl get ns -o name | cut -d/ -f2 | fzf --height 40% --reverse)
    if [ -n "$ns" ]; then
        kubectl config set-context --current --namespace="$ns"
        echo "Switched to namespace: $ns"
    fi
}

# AWS profile switcher with fzf
awsp() {
    local profile
    profile=$(aws configure list-profiles | fzf --height 40% --reverse)
    if [ -n "$profile" ]; then
        export AWS_PROFILE="$profile"
        echo "Switched to AWS profile: $AWS_PROFILE"
    fi
}

# Find and kill process with fzf
fkill() {
    local pid
    pid=$(ps aux | fzf --height 50% --reverse | awk '{print $2}')
    if [ -n "$pid" ]; then
        kill -9 "$pid"
        echo "Killed process $pid"
    fi
}

# Git checkout branch with fzf
gcof() {
    local branch
    branch=$(git branch -a | fzf --height 40% --reverse | sed 's/remotes\/origin\///' | tr -d ' *')
    if [ -n "$branch" ]; then
        git checkout "$branch"
    fi
}

# Terraform workspace switcher with fzf
tfw-switch() {
    local workspace
    workspace=$(terraform workspace list | fzf --height 40% --reverse | tr -d ' *')
    if [ -n "$workspace" ]; then
        terraform workspace select "$workspace"
    fi
}

# Quick HTTP server
serve() {
    local port="${1:-8000}"
    echo "Starting HTTP server on port $port..."
    python3 -m http.server "$port"
}

# Find files by name
ff() {
    find . -iname "*$1*"
}

# Find in files
fif() {
    rg -i "$1"
}

# Quick backup
backup() {
    cp "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
}

# Make executable
x() {
    chmod +x "$1"
}

# Weather
weather() {
    curl "wttr.in/${1:-}"
}

# Cheat.sh integration
cht() {
    curl "cheat.sh/$1"
}

# Show PATH in readable format
showpath() {
    echo $PATH | tr ':' '\n'
}

# Quick note
note() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> ~/notes.txt
}

# ============================================
# TOOL INTEGRATIONS
# ============================================

# FZF configuration
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --inline-info'

# Bat theme (Gruvbox)
export BAT_THEME="gruvbox-dark"

# Ripgrep config file
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# TheFuck integration
eval $(thefuck --alias)
eval $(thefuck --alias fk)

# Delta for git diff
export GIT_PAGER='delta'

# ============================================
# HOMELAB & CLOUD POWER USER ALIASES
# ============================================

# ----------------
# Kubernetes Aliases
# ----------------
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kd='kubectl describe'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kx='kubectx'
alias kns='kubens'
alias kwatch='watch -n 2 kubectl get pods'

# K9s with common views
alias k9='k9s'
alias k9p='k9s -c pods'
alias k9d='k9s -c deployments'
alias k9s='k9s -c services'

# Stern (multi-pod logs)
alias klogs='stern'

# ----------------
# Docker & Container Aliases
# ----------------
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dex='docker exec -it'
alias dlog='docker logs -f'
alias dprune='docker system prune -af'
alias dstop='docker stop $(docker ps -q)'
alias drm='docker rm $(docker ps -aq)'
alias lzd='lazydocker'

# Docker cleanup functions
dcleanup() {
    echo "🧹 Cleaning up Docker..."
    docker system prune -af --volumes
    echo "✅ Docker cleanup complete"
}

# ----------------
# Infrastructure as Code
# ----------------
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfv='terraform validate'
alias tff='terraform fmt'

alias ans='ansible'
alias ansp='ansible-playbook'
alias ansv='ansible-vault'

# ----------------
# Cloud Provider CLIs
# ----------------
alias awswho='aws sts get-caller-identity'
alias awsprofile='export AWS_PROFILE=$(aws configure list-profiles | fzf)'
alias gcpwho='gcloud config get-value account'
alias gcpproj='gcloud config get-value project'
alias azwho='az account show'

# ----------------
# Security & Scanning
# ----------------
alias trivy-image='trivy image'
alias trivy-fs='trivy fs .'
alias grype-image='grype'
alias grype-dir='grype dir:.'

# ----------------
# Monitoring & System
# ----------------
alias top='btop'
alias htop='btop'
alias proc='procs'
alias du='dust'
alias df='duf'
alias diskusage='ncdu'

# ----------------
# Network & API Testing
# ----------------
alias myip='curl -s ifconfig.me'
alias localip='ipconfig getifaddr en0'
alias ports='lsof -iTCP -sTCP:LISTEN -n -P'
alias http='httpie'
alias https='http --verify=no'

# Quick HTTP server
serve() {
    local port="${1:-8000}"
    python3 -m http.server "$port"
}

# ----------------
# YAML/JSON Processing
# ----------------
alias yq='yq'
alias jq='jq'
alias prettyjson='jq .'
alias prettyyaml='yq .'

# ----------------
# File Watching & Monitoring
# ----------------
alias watchfile='entr'
alias watchcmd='watch'

# Live tail with color
alias logs='tail -f'

# ----------------
# SSH & Remote
# ----------------
# Quick SSH with key file
sshmykey() {
    ssh -i "$1" "${@:2}"
}

# Copy SSH key to clipboard
sshcopy() {
    cat ~/.ssh/id_rsa.pub | pbcopy
    echo "SSH public key copied to clipboard"
}

# ----------------
# Homelab Specific
# ----------------
# Quick connectivity test
pingtest() {
    local hosts=("8.8.8.8" "1.1.1.1" "google.com")
    for host in "${hosts[@]}"; do
        if ping -c 1 -W 1 "$host" &>/dev/null; then
            echo "✅ $host - reachable"
        else
            echo "❌ $host - unreachable"
        fi
    done
}

# Port scan wrapper
portscan() {
    nmap -sV -T4 "$1"
}

# Quick service status check
servstat() {
    curl -s -o /dev/null -w "%{http_code}" "$1"
}

# ----------------
# Development Workflow
# ----------------
# Quick commit (unalias gcm from git plugin first)
unalias gcm 2>/dev/null
gcm() {
    git add .
    git commit -m "$1"
}

# Interactive git log
alias glog='git log --oneline --graph --decorate --all'
alias glg='lazygit'

# ----------------
# Quality of Life
# ----------------
# Better help/man pages with colors
alias help='tldr'
alias cheat='navi'

# Interactive cheatsheets
cheet() {
    curl -s "cheat.sh/$1" | bat
}

# Markdown preview (unalias md from common-aliases if present)
unalias md 2>/dev/null
mdview() {
    glow "$1"
}

# ============================================
# ENHANCED TOOL CONFIGURATIONS
# ============================================

# FZF with better defaults for cloud work
export FZF_DEFAULT_OPTS='
    --height 40%
    --layout=reverse
    --border
    --inline-info
    --color=fg:#ebdbb2,bg:#282828,hl:#fabd2f
    --color=fg+:#ebdbb2,bg+:#3c3836,hl+:#fabd2f
    --color=info:#83a598,prompt:#bdae93,spinner:#fabd2f
    --color=pointer:#83a598,marker:#fe8019,header:#665c54
'

# Kubectl completion with fzf
if command -v kubectl &> /dev/null; then
    source <(kubectl completion zsh)
fi

# ============================================
# EOF
# ============================================
