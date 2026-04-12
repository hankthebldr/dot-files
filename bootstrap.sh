#!/usr/bin/env bash
# ============================================
# OPEN CLAW — Bootstrap Installer
# ============================================
# Cross-platform setup for macOS and Ubuntu/Debian
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<user>/dot-files/master/install.sh | bash
#   -- or --
#   git clone <repo> ~/.dotfiles && cd ~/.dotfiles && ./bootstrap.sh
#
# Options:
#   --minimal      Essentials only (no domain toolchains)
#   --security     Include pentesting tools
#   --dry-run      Preview what would happen
#   --no-backup    Skip config backup
#   --help         Show usage

set -e

# ── Source utilities ─────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/utils/logger.sh"
source "$SCRIPT_DIR/scripts/utils/detect-os.sh"
source "$SCRIPT_DIR/scripts/utils/validators.sh"

# ── Configuration ────────────────────────────────────────
INSTALL_MODE="full"
BACKUP_ENABLED=true
DRY_RUN=false
SECURITY_MODE=false
DOTFILES_DIR="$HOME/.dotfiles"

# ── Parse Arguments ──────────────────────────────────────
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --minimal)    INSTALL_MODE="minimal" ;;
        --no-backup)  BACKUP_ENABLED=false ;;
        --dry-run)    DRY_RUN=true ;;
        --security)   SECURITY_MODE=true ;;
        --help)
            echo ""
            echo "  OPEN CLAW — Dot-Files Bootstrap"
            echo ""
            echo "  Usage: ./bootstrap.sh [options]"
            echo ""
            echo "  Options:"
            echo "    --minimal      Essentials only (zsh, modern CLI, symlinks)"
            echo "    --security     Include pentesting tools"
            echo "    --dry-run      Preview what would happen"
            echo "    --no-backup    Skip config backup"
            echo ""
            exit 0
            ;;
        *) log_error "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# ── Styled Header ────────────────────────────────────────
print_header() {
    local c_reset=$'\e[0m'
    local c_cyan=$'\e[38;2;88;166;255m'
    local c_green=$'\e[38;2;63;185;80m'
    local c_purple=$'\e[38;2;188;140;255m'
    local c_dim=$'\e[38;2;139;148;158m'
    local c_white=$'\e[38;2;201;209;217m'
    local c_bold=$'\e[1m'

    echo ""
    echo "  ${c_purple}╭──────────────────────────────────────────────────────╮${c_reset}"
    echo "  ${c_purple}│${c_reset}                                                      ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}   ${c_cyan}█▀█ █▀█ █▀▀ █▄░█   ${c_green}█▀▀ █░░ ▄▀█ █░█░█${c_reset}        ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}   ${c_cyan}█▄█ █▀▀ ██▄ █░▀█   ${c_green}█▄▄ █▄▄ █▀█ ▀▄▀▄▀${c_reset}        ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}                                                      ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}   ${c_white}${c_bold}Bootstrap Installer${c_reset}  ${c_dim}v2.0${c_reset}                        ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}   ${c_dim}Mode: $INSTALL_MODE · OS: $OS_TYPE${c_reset}$(printf '%*s' $((22 - ${#INSTALL_MODE} - ${#OS_TYPE})) '')${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}                                                      ${c_purple}│${c_reset}"
    echo "  ${c_purple}╰──────────────────────────────────────────────────────╯${c_reset}"
    echo ""
}

# ── Step counter ─────────────────────────────────────────
STEP=0
TOTAL_STEPS=9
step() {
    ((STEP++))
    echo ""
    log_info "[$STEP/$TOTAL_STEPS] $1"
    echo "  ─────────────────────────────────────────"
}

# ── Main ─────────────────────────────────────────────────
main() {
    detect_os
    print_header

    # Pre-flight checks
    check_internet || log_warning "No internet — some steps may fail."
    check_disk_space || exit 1

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: No changes will be made."
        log_info "OS: $OS_TYPE, PKG_MANAGER: $PKG_MANAGER, MODE: $INSTALL_MODE"
        exit 0
    fi

    # ── Step 1: Symlink repo to ~/.dotfiles ──────────────
    step "Linking repository to ~/.dotfiles"
    if [[ "$(cd "$SCRIPT_DIR" && pwd)" != "$DOTFILES_DIR" ]]; then
        if [[ -L "$DOTFILES_DIR" ]]; then
            log_success "Symlink already exists: $DOTFILES_DIR → $(readlink "$DOTFILES_DIR")"
        elif [[ -d "$DOTFILES_DIR" ]]; then
            log_warning "$DOTFILES_DIR exists and is not a symlink. Skipping."
        else
            ln -sf "$SCRIPT_DIR" "$DOTFILES_DIR"
            log_success "Created symlink: $DOTFILES_DIR → $SCRIPT_DIR"
        fi
    else
        log_success "Repo is already at $DOTFILES_DIR"
    fi

    # ── Step 2: Backup existing configs ──────────────────
    step "Backing up existing configs"
    if [[ "$BACKUP_ENABLED" == "true" ]]; then
        local backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        for f in .zshrc .gitconfig .tmux.conf .vimrc .p10k.zsh; do
            [[ -f "$HOME/$f" && ! -L "$HOME/$f" ]] && cp "$HOME/$f" "$backup_dir/" && log_info "Backed up $f"
        done
        log_success "Backups saved to $backup_dir"
    else
        log_info "Backup skipped (--no-backup)"
    fi

    # ── Step 3: Install package manager ──────────────────
    step "Installing package manager"
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        log_info "Updating apt index..."
        sudo apt update -y
        sudo apt install -y build-essential curl git
    fi
    source "$SCRIPT_DIR/scripts/install/brew.sh"

    # ── Step 4: Install essentials ───────────────────────
    step "Installing essential packages (git, zsh, tmux, stow, curl)"
    source "$SCRIPT_DIR/scripts/install/packages/common.sh"

    # ── Step 5: Install Zsh + Oh-My-Zsh + Powerlevel10k ─
    step "Setting up Zsh shell"
    # Ensure zsh is the default shell
    if [[ "$SHELL" != *"zsh"* ]]; then
        local zsh_path
        zsh_path="$(command -v zsh)"
        if [[ -n "$zsh_path" ]]; then
            log_info "Setting zsh as default shell..."
            # Add to /etc/shells if not there
            if ! grep -q "$zsh_path" /etc/shells 2>/dev/null; then
                echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
            fi
            chsh -s "$zsh_path" || log_warning "chsh failed — change shell manually: chsh -s $zsh_path"
            log_success "Default shell set to zsh"
        else
            log_error "zsh not found after install"
        fi
    else
        log_success "Zsh is already the default shell"
    fi

    # Oh-My-Zsh
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        log_info "Installing Oh-My-Zsh..."
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        log_success "Oh-My-Zsh installed"
    else
        log_success "Oh-My-Zsh already installed"
    fi

    # Powerlevel10k
    local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$p10k_dir" ]]; then
        log_info "Installing Powerlevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
        log_success "Powerlevel10k installed"
    else
        log_success "Powerlevel10k already installed"
    fi

    # zsh-completions
    local zsh_comp_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions"
    if [[ ! -d "$zsh_comp_dir" ]]; then
        log_info "Installing zsh-completions..."
        git clone https://github.com/zsh-users/zsh-completions "$zsh_comp_dir"
        log_success "zsh-completions installed"
    else
        log_success "zsh-completions already installed"
    fi

    # ── Step 6: Install modern CLI tools ─────────────────
    step "Installing modern CLI tools"
    source "$SCRIPT_DIR/scripts/install/packages/modern-cli.sh"

    # Install extras needed by dot-files features
    local extras=(yq gum)
    for tool in "${extras[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_info "Installing $tool..."
            if [[ "$PKG_MANAGER" == "brew" ]] || command -v brew &>/dev/null; then
                brew install "$tool" 2>/dev/null || log_warning "Failed to install $tool"
            elif [[ "$PKG_MANAGER" == "apt" ]]; then
                sudo apt install -y "$tool" 2>/dev/null || log_warning "Failed to install $tool via apt"
            fi
        else
            log_success "$tool already installed"
        fi
    done

    # ── Step 7: Install Nerd Fonts ───────────────────────
    step "Installing Nerd Fonts (icons for eza, starship, fastfetch)"
    if [[ "$OS_TYPE" == "macos" ]]; then
        if ! ls ~/Library/Fonts/*NerdFont* &>/dev/null 2>&1; then
            log_info "Installing MesloLGS + JetBrainsMono Nerd Fonts via brew..."
            brew install --cask font-meslo-lg-nerd-font font-jetbrains-mono-nerd-font 2>/dev/null || \
                log_warning "Font install failed — install manually from nerdfonts.com"
        else
            log_success "Nerd Fonts already installed"
        fi
    else
        local font_dir="$HOME/.local/share/fonts"
        if ! ls "$font_dir"/*NerdFont* &>/dev/null 2>&1; then
            log_info "Installing JetBrainsMono Nerd Font..."
            mkdir -p "$font_dir"
            local font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
            curl -fsSL "$font_url" | tar xJ -C "$font_dir" 2>/dev/null && \
                fc-cache -fv "$font_dir" >/dev/null 2>&1 && \
                log_success "Nerd Fonts installed" || \
                log_warning "Font install failed — download from nerdfonts.com"
        else
            log_success "Nerd Fonts already installed"
        fi
    fi

    # ── Step 8: Deploy symlinks ──────────────────────────
    step "Deploying symlinks with GNU Stow"
    source "$SCRIPT_DIR/scripts/setup/symlinks.sh"
    stow_modules

    # ── Step 9: Full mode extras ─────────────────────────
    step "Finalizing"
    if [[ "$INSTALL_MODE" == "full" ]]; then
        [[ -f "$SCRIPT_DIR/scripts/install/packages/dev-tools.sh" ]] && source "$SCRIPT_DIR/scripts/install/packages/dev-tools.sh"
        [[ -f "$SCRIPT_DIR/scripts/install/packages/devops-tools.sh" ]] && source "$SCRIPT_DIR/scripts/install/packages/devops-tools.sh"
    fi

    if [[ "$OS_TYPE" == "macos" ]]; then
        [[ -f "$SCRIPT_DIR/scripts/install/macos.sh" ]] && source "$SCRIPT_DIR/scripts/install/macos.sh"
    fi

    if [[ "$SECURITY_MODE" == "true" || "$OS_TYPE" == "parrot" || "$OS_TYPE" == "kali" ]]; then
        log_info "Security/Pentest mode active."
        [[ -f "$SCRIPT_DIR/scripts/install/packages/security.sh" ]] && source "$SCRIPT_DIR/scripts/install/packages/security.sh"
    fi

    # Linux: install xclip for clipboard support
    if [[ "$OS_TYPE" != "macos" ]]; then
        if ! command -v xclip &>/dev/null; then
            log_info "Installing xclip (clipboard support)..."
            sudo apt install -y xclip 2>/dev/null || log_warning "xclip install failed"
        fi
    fi

    # ── Done ─────────────────────────────────────────────
    echo ""
    echo "  ╭──────────────────────────────────────────────────────╮"
    echo "  │                                                      │"
    echo "  │   ✅  OPEN CLAW setup complete!                      │"
    echo "  │                                                      │"
    echo "  │   Next steps:                                        │"
    echo "  │     1. Restart your terminal:  exec zsh              │"
    echo "  │     2. Set terminal font to a Nerd Font              │"
    echo "  │     3. Run  p10k configure  for prompt setup         │"
    echo "  │                                                      │"
    if [[ "$SECURITY_MODE" == "true" ]]; then
    echo "  │   Security tools:                                    │"
    echo "  │     4. Verify with:  nmap --version                  │"
    echo "  │                                                      │"
    fi
    echo "  │   Quick start:                                       │"
    echo "  │     default-help   show all commands                 │"
    echo "  │     netcheck       network diagnostics               │"
    echo "  │     tun            SSH tunnel manager                │"
    echo "  │                                                      │"
    echo "  ╰──────────────────────────────────────────────────────╯"
    echo ""
}

main
