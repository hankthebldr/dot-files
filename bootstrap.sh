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
    # Pre-increment so the arithmetic expression's value is the NEW counter,
    # never 0. Bash (( )) returns exit 1 when the expression is 0, and `set -e`
    # then kills the script silently — `((STEP++))` on the first call (STEP=0)
    # produced exactly that: install died at Step 1 with no error message.
    ((++STEP))
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

    # Warm sudo creds up front. Without this, the first sudo call (apt update
    # in Step 3) hangs forever when bootstrap is invoked via `curl | bash` —
    # piped stdin can't carry a password, and `set -e` aborts the whole run.
    # check_sudo prints a clear message + uses `sudo -v` which prefers /dev/tty.
    if [[ "$PKG_MANAGER" != "brew" ]]; then
        check_sudo || { log_error "Sudo required for apt installs. Re-run with sudo cached (e.g. \`sudo -v\` first), or pass NOPASSWD via /etc/sudoers."; exit 1; }
    fi

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
        local backup_dir
        backup_dir="$HOME/.dotfiles-backups/$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        for f in .zshrc .gitconfig .tmux.conf .vimrc .p10k.zsh; do
            [[ -f "$HOME/$f" && ! -L "$HOME/$f" ]] && cp "$HOME/$f" "$backup_dir/" && log_info "Backed up $f"
        done
        log_success "Backups saved to $backup_dir"
    else
        log_info "Backup skipped (--no-backup)"
    fi

    # ── Step 3: Install package manager + Ubuntu essentials ─
    step "Installing package manager"
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        log_info "Updating apt and installing build prerequisites..."
        sudo apt update -y
        sudo apt install -y \
            build-essential curl git wget unzip tar \
            software-properties-common apt-transport-https \
            ca-certificates gnupg lsb-release \
            xclip xsel wl-clipboard \
            libnotify-bin \
            python3 python3-pip python3-venv \
            net-tools dnsutils iproute2 traceroute \
            2>/dev/null || true
    fi
    source "$SCRIPT_DIR/scripts/install/brew.sh"

    # Make brew visible to the rest of this bootstrap session. brew.sh runs
    # `eval "$(brew shellenv)"` in its own subshell, which doesn't bleed back
    # up to us — without this, step 6's `brew_extras` block is silently
    # skipped on a fresh Linux install.
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi

    # On Ubuntu, also install tools available via apt that brew may not have
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        log_info "Installing Ubuntu-native quality-of-life tools..."
        local apt_tools=(
            zsh-syntax-highlighting    # syntax coloring
            zsh-autosuggestions        # fish-like suggestions
            shellcheck                 # shell linter
            tree                       # directory tree
            htop                       # process viewer
            ncdu                       # disk usage
            mtr                        # better traceroute
            nmap                       # network scanner
            nethogs                    # per-process bandwidth
            iftop                      # network top
            httpie                     # friendly curl
            entr                       # file watcher
            tmux                       # terminal multiplexer
            neovim                     # editor
            silversearcher-ag          # code search
            fd-find                    # find replacement (fd)
            ripgrep                    # grep replacement
            bat                        # cat replacement
            fzf                        # fuzzy finder
        )
        for tool in "${apt_tools[@]}"; do
            sudo apt install -y "$tool" 2>/dev/null || true
        done
        # fd-find installs as fdfind on Ubuntu — create symlink
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
            log_success "Linked fdfind → fd"
        fi
        # bat installs as batcat on Ubuntu — create symlink
        if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
            sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
            log_success "Linked batcat → bat"
        fi
    fi

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
            # sudo chsh bypasses PAM password prompt — vanilla chsh hangs or
            # silently fails under `curl|bash` because it reads /dev/tty for the
            # user's password, which isn't reachable from the piped subshell.
            sudo chsh -s "$zsh_path" "$USER" || log_warning "chsh failed — change shell manually: chsh -s $zsh_path"
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

    # Install brew-only tools (not available via apt or need newer versions)
    if command -v brew &>/dev/null; then
        local brew_extras=(bash yq gum eza zoxide atuin btop lazygit lazydocker git-delta dust duf procs glow fastfetch vivid)
        for tool in "${brew_extras[@]}"; do
            if [[ "$tool" == bash ]]; then
                # /bin/bash 3.2 always resolves; gate on the BREW bash existing,
                # not `command -v bash` (which the system bash always satisfies).
                if [[ ! -x "$(brew --prefix)/bin/bash" ]]; then
                    log_info "Installing modern bash via brew..."
                    brew install bash 2>/dev/null || log_warning "Failed to install bash"
                else
                    log_success "modern bash already installed"
                fi
                continue
            fi
            if ! command -v "$tool" &>/dev/null; then
                log_info "Installing $tool via brew..."
                brew install "$tool" 2>/dev/null || log_warning "Failed to install $tool"
            else
                log_success "$tool already installed"
            fi
        done
    else
        log_warning "Homebrew not available — some modern CLI tools will be missing (eza, zoxide, atuin, btop, lazygit, delta)"
        log_info "Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    fi

    # colorls — Ruby-based ls with Font Awesome / Nerd Font icons
    if command -v colorls &>/dev/null; then
        log_success "colorls already installed"
    elif command -v gem &>/dev/null; then
        log_info "Installing colorls (Ruby gem)..."
        if gem install colorls --no-document 2>/dev/null || sudo gem install colorls --no-document 2>/dev/null; then
            log_success "colorls installed"
        else
            log_warning "colorls install failed — run 'gem install colorls' manually (needs Ruby ≥ 2.5)"
        fi
    else
        log_warning "Ruby/gem not found — skipping colorls (install ruby, then 'gem install colorls')"
    fi

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
        # Font Awesome — glyphs used by colorls
        if ! ls ~/Library/Fonts/*FontAwesome* ~/Library/Fonts/*Font*Awesome* &>/dev/null 2>&1; then
            log_info "Installing Font Awesome (colorls glyphs) via brew..."
            brew install --cask font-fontawesome 2>/dev/null || \
                log_warning "Font Awesome install failed — install manually from fontawesome.com"
        else
            log_success "Font Awesome already installed"
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
        # Font Awesome — glyphs used by colorls
        if ! fc-list 2>/dev/null | grep -qi 'font.*awesome'; then
            log_info "Installing Font Awesome (colorls glyphs)..."
            mkdir -p "$font_dir"
            local fa_url="https://github.com/FortAwesome/Font-Awesome/releases/download/6.5.2/fontawesome-free-6.5.2-desktop.zip"
            local fa_tmp; fa_tmp="$(mktemp -d)"
            if curl -fsSL "$fa_url" -o "$fa_tmp/fa.zip" 2>/dev/null && \
               unzip -joq "$fa_tmp/fa.zip" '*/otfs/*.otf' -d "$font_dir" 2>/dev/null; then
                fc-cache -fv "$font_dir" >/dev/null 2>&1
                log_success "Font Awesome installed"
            else
                log_warning "Font Awesome install failed — download from fontawesome.com"
            fi
            rm -rf "$fa_tmp"
        else
            log_success "Font Awesome already installed"
        fi
    fi

    # ── Step 8: Deploy symlinks ──────────────────────────
    step "Deploying symlinks with GNU Stow"
    source "$SCRIPT_DIR/scripts/setup/symlinks.sh"
    stow_modules

    # ── Step 8b: Ensure claw dispatcher + helpers are executable ──
    # Git tracks the executable bit but a fresh clone over a different
    # umask (or a bad mirror) can drop it. Belt-and-suspenders.
    log_info "Setting executable bits on bin/ + scripts/"
    # Why an explicit allowlist instead of `find scripts -name '*.sh' -exec chmod +x`:
    #   1. Many *.sh files in scripts/ are SOURCE-ONLY libraries (logger.sh,
    #      detect-os.sh, validators.sh, tui-style.sh, claw-output.sh,
    #      symlinks.sh, …) — marking them +x is misleading and invites a
    #      caller to exec a library that has no shebang/main.
    #   2. The recursive form also DEFEATS the `chmod -x` opt-out pattern:
    #      Step 9b's integrity.sh records the executable bit, so a user (or
    #      previous run) who deliberately unsets +x on a vendored script
    #      would have it silently re-armed on every bootstrap, producing
    #      spurious integrity drift.
    # The list below is the surgical set of true entry points (CLIs invoked
    # directly by claw, the welcome TUI, or the bootstrap itself).
    chmod +x "$SCRIPT_DIR/bin/claw" 2>/dev/null || true
    # Toolchain installers, master-setup, brew/macos/desktop-linux helpers, etc.
    for f in "$SCRIPT_DIR"/scripts/install/*.sh; do
        [[ -f "$f" ]] && chmod +x "$f" 2>/dev/null || true
    done
    # The Claude tree linker is exec'd; symlinks.sh is sourced, not exec'd.
    chmod +x "$SCRIPT_DIR/scripts/setup/link-claude.sh" 2>/dev/null || true
    # Utility entry points (TUIs, managers, dashboards). Libraries omitted.
    for util in theme toolkit tunnel-manager ai-services homelab \
                system-update tool-updater mcp-manager onboarding \
                integrity selfupdate help cheatsheet docker-overview \
                ssh-deploy storage-doctor uninstall; do
        f="$SCRIPT_DIR/scripts/utils/$util.sh"
        [[ -f "$f" ]] && chmod +x "$f" 2>/dev/null || true
    done
    # claw-dashboard ships as a Python script (not .sh) but is exec'd directly.
    [[ -f "$SCRIPT_DIR/scripts/utils/claw-dashboard.py" ]] && \
        chmod +x "$SCRIPT_DIR/scripts/utils/claw-dashboard.py" 2>/dev/null || true
    log_success "claw + entry-point scripts marked executable"

    # Verify claw is reachable after a synthetic PATH refresh
    if [[ -x "$SCRIPT_DIR/bin/claw" ]] && "$SCRIPT_DIR/bin/claw" help &>/dev/null; then
        log_success "claw dispatcher verified at $SCRIPT_DIR/bin/claw"
    else
        log_warning "claw dispatcher not running cleanly — check $SCRIPT_DIR/bin/claw manually"
    fi

    # ── Step 8c: Deploy Claude Code tree (CLAUDE.md, hooks, skills) ──
    # claude/ can't be stowed (it'd splatter into $HOME and clobber managed
    # skills), so a dedicated item-level linker handles it and registers the
    # default-deny scope hooks if Claude Code is installed.
    if [[ -x "$SCRIPT_DIR/scripts/setup/link-claude.sh" ]]; then
        log_info "Deploying Claude Code config (claude/ → ~/.claude)"
        bash "$SCRIPT_DIR/scripts/setup/link-claude.sh" 2>&1 | grep -E '✓|backed up|WARNING' || true
    fi

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

    # Linux: verify clipboard support is available
    if [[ "$OS_TYPE" != "macos" ]] && ! command -v xclip &>/dev/null && ! command -v xsel &>/dev/null; then
        log_warning "No clipboard tool found. Install: sudo apt install xclip"
    fi

    # ── Step 9b: Generate integrity manifest ───────────────
    # Captures the SHA-256 of every shell script / config / profile we
    # just deployed so the user (or a CI job) can detect tampering or a
    # partial install later via `claw integrity verify`.
    if [[ -x "$SCRIPT_DIR/scripts/utils/integrity.sh" ]]; then
        log_info "Recording install integrity manifest..."
        bash "$SCRIPT_DIR/scripts/utils/integrity.sh" generate >/dev/null 2>&1 && \
            log_success "Integrity manifest saved (run: claw integrity verify)" || \
            log_warning "Integrity manifest generation failed (non-fatal)"
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
    echo "  │     3. Prompt is pre-themed (edit ~/.p10k.zsh)       │"
    echo "  │     4. Try:  claw help   (single command surface)    │"
    echo "  │                                                      │"
    if [[ "$SECURITY_MODE" == "true" ]]; then
    echo "  │   Security tools:                                    │"
    echo "  │     4. Verify with:  nmap --version                  │"
    echo "  │                                                      │"
    fi
    echo "  │   Quick start:                                       │"
    echo "  │     claw onboard   ▶ pick a profile (80s arcade)     │"
    echo "  │     claw integrity verify   tamper-check your install │"
    echo "  │     default-help   show all commands                 │"
    echo "  │     tun            SSH tunnel manager                │"
    echo "  │                                                      │"
    echo "  ╰──────────────────────────────────────────────────────╯"
    echo ""
}

main
