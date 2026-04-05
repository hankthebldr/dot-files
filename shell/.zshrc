# ============================================
# OPEN CLAW — ZSH Configuration (Cross-Platform)
# ============================================
# Supports: macOS (ARM/Intel), Ubuntu, Debian, Kali, Parrot
# Loading order:
#   1. P10k instant prompt (must be first)
#   2. Oh-My-Zsh framework + plugins (conditional per OS)
#   3. DOTFILES_DIR + platform shims + modular sources
#   4. Tool initializations (zoxide, direnv, atuin, eza, thefuck)
#   5. P10k theme config
#   6. Welcome TUI (interactive shells only)

# ── 1. Powerlevel10k Instant Prompt ──────────────────────
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ── 2. Oh-My-Zsh Framework ──────────────────────────────
export ZSH="$HOME/.oh-my-zsh"

# Oh-My-Zsh (skip silently if not installed — never print to stdout, breaks scp/rsync)
if [[ -d "$ZSH" ]]; then
    ZSH_THEME="powerlevel10k/powerlevel10k"

    # Completions
    if [[ -d ${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src ]]; then
        fpath+=${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src
    fi

    # Settings
    HYPHEN_INSENSITIVE="true"
    COMPLETION_WAITING_DOTS="true"
    zstyle ':omz:update' mode auto

    # Plugins — cross-platform core + conditional OS plugins
    plugins=(
        # Core (all platforms)
        git gh github aliases sudo vi-mode copybuffer copypath copyfile cp
        colored-man-pages jsontools
        # Cloud & Infra
        aws azure gcloud kubectl helm kubectx terraform vault ansible
        docker docker-compose istioctl operator-sdk kind
        # Languages & Tools
        golang python node npm dotnet brew
        # Shell UX
        colorize web-search emoji ssh ssh-agent
    )
    # macOS-only plugins
    [[ "$OSTYPE" == "darwin"* ]] && plugins+=(macos vscode)
    # Debian/Ubuntu-only plugins
    [[ -f /etc/debian_version ]] && plugins+=(ubuntu debian)

    source "$ZSH/oh-my-zsh.sh"
fi

# ── 3. Open Claw Modular Configuration ──────────────────
export DOTFILES_DIR="$HOME/.dotfiles"

# Platform shims FIRST (clipboard, open, local IP, HOMEBREW_PREFIX)
[[ -f "$DOTFILES_DIR/shell/platform.zsh" ]] && source "$DOTFILES_DIR/shell/platform.zsh"

# PATH setup (homebrew on macOS/Linux, cargo, go, local bin)
[[ -f "$DOTFILES_DIR/shell/path.zsh" ]] && source "$DOTFILES_DIR/shell/path.zsh"

# Environment exports (FZF, BAT_THEME, GIT_PAGER, XDG, history)
[[ -f "$DOTFILES_DIR/shell/exports.zsh" ]] && source "$DOTFILES_DIR/shell/exports.zsh"

# Load .env variables (if present)
[[ -f "$DOTFILES_DIR/shell/load-env.zsh" ]] && source "$DOTFILES_DIR/shell/load-env.zsh"

# Core aliases and functions
[[ -f "$DOTFILES_DIR/shell/aliases.zsh" ]] && source "$DOTFILES_DIR/shell/aliases.zsh"

# Security aliases (safe file ops, network recon, scanning)
[[ -f "$DOTFILES_DIR/shell/security.zsh" ]] && source "$DOTFILES_DIR/shell/security.zsh"

# Obsidian vault integration (on, os, ov)
[[ -f "$DOTFILES_DIR/shell/obsidian.zsh" ]] && source "$DOTFILES_DIR/shell/obsidian.zsh"

# External: Obsidian vault OS-specific aliases
[[ -f ~/hr-vault-main-pa/_agents/shell-aliases.sh ]] && source ~/hr-vault-main-pa/_agents/shell-aliases.sh

# ── 4. Tool Initializations (all guarded) ───────────────

# Zoxide (smarter cd — use 'z' command)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# Direnv (per-directory environment variables)
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# Atuin (magical shell history)
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# TheFuck (command correction)
command -v thefuck &>/dev/null && eval $(thefuck --alias)

# Eza (modern ls replacement)
if command -v eza &>/dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -l --icons --group-directories-first'
    alias la='eza -la --icons --group-directories-first'
    alias lt='eza --tree --level=2 --icons'
    alias tree='eza --tree --icons'
fi

# zsh-syntax-highlighting (cross-platform: brew or apt)
for _zsh_hl in \
    "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "/home/linuxbrew/.linuxbrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"; do
    if [[ -f "$_zsh_hl" ]]; then source "$_zsh_hl"; break; fi
done
unset _zsh_hl

# zsh-autocomplete (cross-platform: brew or apt)
for _zsh_ac in \
    "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh" \
    "/home/linuxbrew/.linuxbrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh" \
    "/usr/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh"; do
    if [[ -f "$_zsh_ac" ]]; then source "$_zsh_ac"; break; fi
done
unset _zsh_ac

# Google Cloud SDK (various install locations)
for _gcloud in \
    "$HOME/Downloads/google-cloud-sdk" \
    "/usr/lib/google-cloud-sdk" \
    "/snap/google-cloud-cli/current" \
    "$HOME/google-cloud-sdk"; do
    if [[ -f "$_gcloud/path.zsh.inc" ]]; then
        source "$_gcloud/path.zsh.inc"
        [[ -f "$_gcloud/completion.zsh.inc" ]] && source "$_gcloud/completion.zsh.inc"
        break
    fi
done
unset _gcloud

# ── 5. Powerlevel10k Theme ──────────────────────────────

export EDITOR='vim'
export VISUAL='vim'
export CLICOLOR=1

# Load active profile (set by welcome TUI or manually)
if [[ -n "$CLAW_ACTIVE_PROFILE" ]]; then
    PROFILE_PATH="$DOTFILES_DIR/shell/profiles/${CLAW_ACTIVE_PROFILE}.zsh"
    [[ -f "$PROFILE_PATH" ]] && source "$PROFILE_PATH"
fi

# Profile-aware p10k config
P10K_CONFIG_FILE="$HOME/.p10k.zsh"
for _pn in security cloud devops research ai; do
    if [[ "$CLAW_ACTIVE_PROFILE" == "$_pn" && -f "$HOME/.p10k-${_pn}.zsh" ]]; then
        P10K_CONFIG_FILE="$HOME/.p10k-${_pn}.zsh"
        break
    fi
done
[[ -f "$P10K_CONFIG_FILE" ]] && source "$P10K_CONFIG_FILE"
unset _pn

# Terraform completion (cross-platform)
_tf_bin="$(command -v terraform 2>/dev/null)"
if [[ -n "$_tf_bin" ]]; then
    autoload -U +X bashcompinit && bashcompinit
    complete -o nospace -C "$_tf_bin" terraform
fi
unset _tf_bin

typeset -g POWERLEVEL9K_KUBECONTEXT_SHOW_ON_COMMAND='kubectl|helm|kubens'

# fpath for zsh site-functions
if (( ! ${fpath[(I)/usr/local/share/zsh/site-functions]} )); then
    FPATH=/usr/local/share/zsh/site-functions:$FPATH
fi

alias zshconfig="${EDITOR:-vim} ~/.zshrc"
alias ohmyzsh="${EDITOR:-vim} ~/.oh-my-zsh"

# ── 6. Interactive Open Claw Login Dashboard ────────────
if [[ -f "$DOTFILES_DIR/shell/welcome-tui.zsh" ]]; then
    source "$DOTFILES_DIR/shell/welcome-tui.zsh"
    claw_welcome_tui
fi

# ── Appended PATH (external tools) ──────────────────────
[[ -d "$HOME/.antigravity/antigravity/bin" ]] && export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
[[ -d "$HOME/.lmstudio/bin" ]] && export PATH="$PATH:$HOME/.lmstudio/bin"
