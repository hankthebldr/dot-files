# shell/exports.zsh
# Centralized environment exports for Open Claw CLI

# ============================================
# CORE ENVIRONMENT
# ============================================

export EDITOR='nvim'
export VISUAL='nvim'
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Dotfiles root (auto-detect from this file's location)
export DOTFILES_DIR="${0:A:h:h}"

# ============================================
# XDG BASE DIRECTORIES
# ============================================

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# ============================================
# ZSH HISTORY
# ============================================

HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=100000
SAVEHIST=100000

# Create history directory if missing
[[ -d "${HISTFILE:h}" ]] || mkdir -p "${HISTFILE:h}"

setopt EXTENDED_HISTORY       # Write timestamps to history
setopt HIST_EXPIRE_DUPS_FIRST # Expire duplicate entries first when trimming
setopt HIST_IGNORE_DUPS       # Don't record an entry that was just recorded
setopt HIST_IGNORE_ALL_DUPS   # Delete old recorded entry if new entry is a duplicate
setopt HIST_IGNORE_SPACE      # Don't record entries starting with a space
setopt HIST_FIND_NO_DUPS      # Do not display a line previously found
setopt HIST_SAVE_NO_DUPS      # Don't write duplicate entries in the history file
setopt SHARE_HISTORY          # Share history between all sessions
setopt INC_APPEND_HISTORY     # Write to history file immediately, not when shell exits

# ============================================
# TOOL CONFIGURATIONS
# ============================================

# Active Open Claw theme → CLAW_C_* / CLAW_RGB_* + the fzf --color string.
# config/themes/<slug>.theme is the single source of truth for every surface.
[[ -r "$DOTFILES_DIR/scripts/utils/theme.sh" ]] && source "$DOTFILES_DIR/scripts/utils/theme.sh"

# FZF — colors come from the active theme (falls back to refined-dark defaults).
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
if typeset -f claw_theme_fzf &>/dev/null; then
    export CLAW_FZF_COLOR="$(claw_theme_fzf)"
else
    export CLAW_FZF_COLOR="bg+:#161b22,fg+:#c9d1d9,prompt:#58a6ff,header:#8b949e,pointer:#3fb950,hl:#ff7b72,hl+:#ff7b72,info:#8b949e,marker:#e3b341,spinner:#bc8cff"
fi
export FZF_DEFAULT_OPTS="
    --height 40%
    --layout=reverse
    --border
    --inline-info
    --color=\"$CLAW_FZF_COLOR\"
"

# Bat (syntax highlighting)
export BAT_THEME="GitHub"

# Ripgrep
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# Git pager (delta)
export GIT_PAGER='delta'

# ── Agentic shared env (one secret source → many harnesses) ─────────────────
: "${GEMINI_API_KEY:=${GOOGLE_API_KEY:-}}"; [[ -n "$GEMINI_API_KEY" ]] && export GEMINI_API_KEY
export OLLAMA_OPENAI_BASE="${OLLAMA_OPENAI_BASE:-http://localhost:11434/v1}"
