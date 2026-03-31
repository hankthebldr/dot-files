# ============================================
# OPEN CLAW — ZSH Configuration
# ============================================
# Loading order:
#   1. P10k instant prompt (must be first)
#   2. Oh-My-Zsh framework + plugins
#   3. DOTFILES_DIR + modular sources (path, exports, aliases, security, obsidian)
#   4. Tool initializations (zoxide, direnv, atuin, eza, thefuck)
#   5. P10k theme config
#   6. Welcome TUI (interactive shells only)

# ── 1. Powerlevel10k Instant Prompt ──────────────────────
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ── 2. Oh-My-Zsh Framework ──────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# Completions
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src

# Settings
HYPHEN_INSENSITIVE="true"
COMPLETION_WAITING_DOTS="true"
zstyle ':omz:update' mode auto

# Plugins (curated for macOS — removed Linux-only and duplicates)
plugins=(
    # Core
    git gh github aliases sudo vi-mode copybuffer copypath copyfile cp
    colored-man-pages jsontools
    # Cloud & Infra
    aws azure gcloud kubectl helm kubectx terraform vault ansible
    docker docker-compose istioctl operator-sdk kind
    # Languages & Tools
    golang python node npm dotnet
    # macOS
    macos brew vscode
    # Shell UX
    colorize web-search emoji ssh ssh-agent
)

# zsh-autocomplete (brew)
if [[ -f /opt/homebrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh ]]; then
    source /opt/homebrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh
fi

source $ZSH/oh-my-zsh.sh

# ── 3. Open Claw Modular Configuration ──────────────────
export DOTFILES_DIR="$HOME/.dotfiles"

# PATH setup (homebrew, cargo, go, local bin)
[[ -f "$DOTFILES_DIR/shell/path.zsh" ]] && source "$DOTFILES_DIR/shell/path.zsh"

# Environment exports (FZF, BAT_THEME, GIT_PAGER, XDG, history)
[[ -f "$DOTFILES_DIR/shell/exports.zsh" ]] && source "$DOTFILES_DIR/shell/exports.zsh"

# Load .env variables (if present)
[[ -f "$DOTFILES_DIR/shell/load-env.zsh" ]] && source "$DOTFILES_DIR/shell/load-env.zsh"

# Core aliases and functions (~660 aliases)
[[ -f "$DOTFILES_DIR/shell/aliases.zsh" ]] && source "$DOTFILES_DIR/shell/aliases.zsh"

# Security aliases (safe file ops, network recon, scanning)
[[ -f "$DOTFILES_DIR/shell/security.zsh" ]] && source "$DOTFILES_DIR/shell/security.zsh"

# Obsidian vault integration (on, os, ov)
[[ -f "$DOTFILES_DIR/shell/obsidian.zsh" ]] && source "$DOTFILES_DIR/shell/obsidian.zsh"

# External: Obsidian vault OS-specific aliases
[[ -f ~/hr-vault-main-pa/_agents/shell-aliases.sh ]] && source ~/hr-vault-main-pa/_agents/shell-aliases.sh

# ── 4. Tool Initializations (guarded) ───────────────────

# Zoxide (smarter cd — use 'z' command)
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
fi

# Direnv (per-directory environment variables)
if command -v direnv &> /dev/null; then
    eval "$(direnv hook zsh)"
fi

# Atuin (magical shell history)
if command -v atuin &> /dev/null; then
    eval "$(atuin init zsh)"
fi

# TheFuck (command correction — 'fuck' to fix last command)
if command -v thefuck &> /dev/null; then
    eval $(thefuck --alias)
fi

# Eza (modern ls replacement)
if command -v eza &> /dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -l --icons --group-directories-first'
    alias la='eza -la --icons --group-directories-first'
    alias lt='eza --tree --level=2 --icons'
    alias tree='eza --tree --icons'
fi

# zsh-syntax-highlighting (brew)
if [[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# Google Cloud SDK
if [[ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]]; then
    source "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"
fi
if [[ -f "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc" ]]; then
    source "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc"
fi

# ── 5. Powerlevel10k Theme ──────────────────────────────

# Editor
export EDITOR='vim'
export VISUAL='vim'

# Terminal colors
export CLICOLOR=1

# Load active profile (set by welcome TUI or manually)
if [[ -n "$CLAW_ACTIVE_PROFILE" ]]; then
    PROFILE_PATH="$DOTFILES_DIR/shell/profiles/${CLAW_ACTIVE_PROFILE}.zsh"
    [[ -f "$PROFILE_PATH" ]] && source "$PROFILE_PATH"
fi

# Profile-aware p10k config
P10K_CONFIG_FILE="$HOME/.p10k.zsh"
for _profile_name in security cloud devops research ai; do
    if [[ "$CLAW_ACTIVE_PROFILE" == "$_profile_name" && -f "$HOME/.p10k-${_profile_name}.zsh" ]]; then
        P10K_CONFIG_FILE="$HOME/.p10k-${_profile_name}.zsh"
        break
    fi
done
[[ -f "$P10K_CONFIG_FILE" ]] && source "$P10K_CONFIG_FILE"
unset _profile_name

# Terraform completion
if [[ -f /opt/homebrew/bin/terraform ]]; then
    autoload -U +X bashcompinit && bashcompinit
    complete -o nospace -C /opt/homebrew/bin/terraform terraform
fi

# Kubecontext display (only when relevant commands typed)
typeset -g POWERLEVEL9K_KUBECONTEXT_SHOW_ON_COMMAND='kubectl|helm|kubens'

# fpath for zsh site-functions
if (( ! ${fpath[(I)/usr/local/share/zsh/site-functions]} )); then
    FPATH=/usr/local/share/zsh/site-functions:$FPATH
fi

# Quick config editing
alias zshconfig="${EDITOR:-vim} ~/.zshrc"
alias ohmyzsh="${EDITOR:-vim} ~/.oh-my-zsh"

# ── 6. Interactive Open Claw Login Dashboard ────────────
if [[ -f "$DOTFILES_DIR/shell/welcome-tui.zsh" ]]; then
    source "$DOTFILES_DIR/shell/welcome-tui.zsh"
    claw_welcome_tui
fi

# ── Appended PATH (external tools) ──────────────────────
[[ -d "/Users/henry/.antigravity/antigravity/bin" ]] && export PATH="/Users/henry/.antigravity/antigravity/bin:$PATH"
[[ -d "/Users/henry/.lmstudio/bin" ]] && export PATH="$PATH:/Users/henry/.lmstudio/bin"
