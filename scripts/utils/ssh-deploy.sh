#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Open Claw SSH Deploy — Remote Environment Provisioner
# ==============================================================================
# Deploys portable shell and editor configs to remote machines.
# Part of the Open Claw dot-files system.
# ==============================================================================

# --- Resolve dotfiles root ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- GitHub Dark Theme Colors ---
RED='\033[38;2;255;123;114m'
GREEN='\033[38;2;63;185;80m'
BLUE='\033[38;2;88;166;255m'
YELLOW='\033[38;2;227;179;65m'
PURPLE='\033[38;2;188;140;255m'
DIM='\033[38;2;139;148;158m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Remote env file paths ---
ZSHRC_REMOTE="$DOTFILES_DIR/config/ssh/remote-env/zshrc-remote"
VIMRC_REMOTE="$DOTFILES_DIR/config/ssh/remote-env/vimrc-remote"
DEPLOYED_LOG="$HOME/.ssh/.openclaw-deployed"

# --- State ---
DRY_RUN=false
TARGET_HOST=""

# ==============================================================================
# Functions
# ==============================================================================

banner() {
    echo -e "${PURPLE}${BOLD}"
    echo '    ___                    ___ _'
    echo '   / _ \ _ __   ___ _ __ / __| | __ ___      __'
    echo '  | | | |  _ \ / _ \  _ \| |  | |/ _` \ \ /\ / /'
    echo '  | |_| | |_) |  __/ | | | |__| | (_| |\ V  V /'
    echo '   \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/'
    echo '        |_|          SSH Deploy'
    echo -e "${RESET}"
}

log_info()    { echo -e "${BLUE}[INFO]${RESET}    $1"; }
log_success() { echo -e "${GREEN}[OK]${RESET}      $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${RESET}   $1"; }
log_step()    { echo -e "${PURPLE}[STEP]${RESET}    $1"; }
log_dry()     { echo -e "${DIM}[DRY-RUN]${RESET} $1"; }

usage() {
    echo -e "${BOLD}Usage:${RESET} ssh-deploy <hostname> [options]"
    echo ""
    echo -e "${BOLD}Options:${RESET}"
    echo "  --dry-run    Show what would be deployed without making changes"
    echo "  --help       Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${RESET}"
    echo "  ssh-deploy myserver"
    echo "  ssh-deploy user@10.0.1.5 --dry-run"
    echo "  ssh-deploy bastion.example.com"
    echo ""
    echo -e "${DIM}Deploys Open Claw shell and editor configs to remote machines.${RESET}"
    echo -e "${DIM}Backs up existing configs before overwriting.${RESET}"
}

check_files() {
    local missing=0
    if [[ ! -f "$ZSHRC_REMOTE" ]]; then
        log_error "Missing: $ZSHRC_REMOTE"
        missing=1
    fi
    if [[ ! -f "$VIMRC_REMOTE" ]]; then
        log_error "Missing: $VIMRC_REMOTE"
        missing=1
    fi
    if [[ $missing -eq 1 ]]; then
        log_error "Remote env files not found. Is DOTFILES_DIR correct?"
        exit 1
    fi
}

check_connectivity() {
    log_step "Checking SSH connectivity to ${BOLD}$TARGET_HOST${RESET}..."
    if $DRY_RUN; then
        log_dry "Would test: ssh -o ConnectTimeout=5 -o BatchMode=yes $TARGET_HOST true"
        return 0
    fi
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$TARGET_HOST" true 2>/dev/null; then
        log_error "Cannot connect to $TARGET_HOST"
        log_error "Ensure SSH key auth is configured and the host is reachable."
        exit 1
    fi
    log_success "Connection established"
}

detect_remote_os() {
    log_step "Detecting remote OS..."
    if $DRY_RUN; then
        log_dry "Would run: ssh $TARGET_HOST 'uname -s'"
        REMOTE_OS="(dry-run)"
        return 0
    fi
    REMOTE_OS=$(ssh "$TARGET_HOST" 'uname -s' 2>/dev/null || echo "Unknown")
    log_success "Remote OS: ${BOLD}$REMOTE_OS${RESET}"
}

detect_remote_shell() {
    log_step "Detecting remote shell..."
    if $DRY_RUN; then
        log_dry "Would check for zsh and bash on remote"
        REMOTE_SHELL="(dry-run)"
        REMOTE_SHELL_RC="(dry-run)"
        return 0
    fi
    if ssh "$TARGET_HOST" 'command -v zsh' &>/dev/null; then
        REMOTE_SHELL="zsh"
        REMOTE_SHELL_RC=".zshrc"
        log_success "Remote shell: ${BOLD}zsh${RESET}"
    elif ssh "$TARGET_HOST" 'command -v bash' &>/dev/null; then
        REMOTE_SHELL="bash"
        REMOTE_SHELL_RC=".bashrc"
        log_success "Remote shell: ${BOLD}bash${RESET} (zsh not available)"
    else
        REMOTE_SHELL="sh"
        REMOTE_SHELL_RC=".profile"
        log_warn "Only sh detected; deploying to .profile"
    fi
}

backup_remote_configs() {
    log_step "Backing up existing remote configs..."
    if $DRY_RUN; then
        log_dry "Would back up .zshrc, .bashrc, .vimrc on remote"
        return 0
    fi
    ssh "$TARGET_HOST" 'for f in .zshrc .bashrc .vimrc; do [ -f ~/$f ] && cp ~/$f ~/${f}.bak-openclaw 2>/dev/null; done; true'
    log_success "Backups created (*.bak-openclaw)"
}

deploy_zshrc() {
    log_step "Deploying zshrc-remote..."
    if $DRY_RUN; then
        log_dry "Would deploy $ZSHRC_REMOTE -> remote:~/.zshrc-openclaw"
        return 0
    fi
    cat "$ZSHRC_REMOTE" | ssh "$TARGET_HOST" 'cat > ~/.zshrc-openclaw'
    log_success "Deployed ~/.zshrc-openclaw"
}

deploy_vimrc() {
    log_step "Deploying vimrc-remote..."
    if $DRY_RUN; then
        log_dry "Would deploy $VIMRC_REMOTE -> remote:~/.vimrc"
        return 0
    fi
    cat "$VIMRC_REMOTE" | ssh "$TARGET_HOST" 'cat > ~/.vimrc'
    log_success "Deployed ~/.vimrc"
}

source_openclaw_rc() {
    log_step "Adding source line to remote $REMOTE_SHELL_RC..."
    local source_line='[ -f ~/.zshrc-openclaw ] && source ~/.zshrc-openclaw'
    if $DRY_RUN; then
        log_dry "Would append to ~/$REMOTE_SHELL_RC: $source_line"
        return 0
    fi
    local already_sourced
    already_sourced=$(ssh "$TARGET_HOST" "grep -qF '.zshrc-openclaw' ~/$REMOTE_SHELL_RC 2>/dev/null && echo yes || echo no")
    if [[ "$already_sourced" == "yes" ]]; then
        log_success "Source line already present in ~/$REMOTE_SHELL_RC (skipped)"
    else
        ssh "$TARGET_HOST" "echo '' >> ~/$REMOTE_SHELL_RC && echo '# Open Claw remote environment' >> ~/$REMOTE_SHELL_RC && echo '$source_line' >> ~/$REMOTE_SHELL_RC"
        log_success "Added source line to ~/$REMOTE_SHELL_RC"
    fi
}

create_ssh_sockets_dir() {
    log_step "Ensuring ~/.ssh/sockets exists on remote..."
    if $DRY_RUN; then
        log_dry "Would create ~/.ssh/sockets on remote"
        return 0
    fi
    ssh "$TARGET_HOST" 'mkdir -p ~/.ssh/sockets && chmod 700 ~/.ssh/sockets'
    log_success "~/.ssh/sockets ready"
}

track_deployment() {
    log_step "Tracking deployment locally..."
    if $DRY_RUN; then
        log_dry "Would append $TARGET_HOST to $DEPLOYED_LOG"
        return 0
    fi
    mkdir -p "$(dirname "$DEPLOYED_LOG")"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    if grep -qF "$TARGET_HOST" "$DEPLOYED_LOG" 2>/dev/null; then
        # Update existing entry
        local tmp
        tmp=$(mktemp)
        grep -vF "$TARGET_HOST" "$DEPLOYED_LOG" > "$tmp" || true
        echo "$timestamp  $TARGET_HOST  os=$REMOTE_OS shell=$REMOTE_SHELL" >> "$tmp"
        mv "$tmp" "$DEPLOYED_LOG"
        log_success "Updated deployment record"
    else
        echo "$timestamp  $TARGET_HOST  os=$REMOTE_OS shell=$REMOTE_SHELL" >> "$DEPLOYED_LOG"
        log_success "Recorded in $DEPLOYED_LOG"
    fi
}

print_summary() {
    echo ""
    echo -e "${PURPLE}${BOLD}============================================${RESET}"
    echo -e "${PURPLE}${BOLD}  Deployment Summary${RESET}"
    echo -e "${PURPLE}${BOLD}============================================${RESET}"
    echo -e "  ${DIM}Host:${RESET}       ${BOLD}$TARGET_HOST${RESET}"
    echo -e "  ${DIM}OS:${RESET}         ${BOLD}$REMOTE_OS${RESET}"
    echo -e "  ${DIM}Shell:${RESET}      ${BOLD}$REMOTE_SHELL${RESET}"
    echo -e "  ${DIM}Files:${RESET}      ~/.zshrc-openclaw, ~/.vimrc"
    echo -e "  ${DIM}Source:${RESET}     ~/$REMOTE_SHELL_RC"
    if $DRY_RUN; then
        echo -e "  ${DIM}Status:${RESET}     ${YELLOW}DRY RUN (no changes made)${RESET}"
    else
        echo -e "  ${DIM}Status:${RESET}     ${GREEN}Deployed successfully${RESET}"
    fi
    echo -e "${PURPLE}${BOLD}============================================${RESET}"
    echo ""
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [[ -z "$TARGET_HOST" ]]; then
                TARGET_HOST="$1"
            else
                log_error "Unexpected argument: $1"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$TARGET_HOST" ]]; then
    log_error "Hostname is required."
    echo ""
    usage
    exit 1
fi

# ==============================================================================
# Main
# ==============================================================================

banner

if $DRY_RUN; then
    echo -e "${YELLOW}${BOLD}  DRY RUN MODE — no changes will be made${RESET}"
    echo ""
fi

check_files
check_connectivity
detect_remote_os
detect_remote_shell
backup_remote_configs
deploy_zshrc
deploy_vimrc
source_openclaw_rc
create_ssh_sockets_dir
track_deployment
print_summary
