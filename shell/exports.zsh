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
# config/themes/<slug>/palette.theme is the single source of truth for every surface.
[[ -r "$DOTFILES_DIR/scripts/utils/theme.sh" ]] && source "$DOTFILES_DIR/scripts/utils/theme.sh"

# eza/ls colors — soft "gruvbox-material" listing palette. eza's defaults paint
# dirs dim-blue, archives bright-red, images/video bright-magenta, source bold-
# yellow — all harsh on the dark bg. We override the UI/category colors AND the
# noisy per-extension rules (which take precedence over the category codes) so
# every file kind lands on a calm gruvbox tone. Decoupled from `claw theme` on
# purpose; no leading `reset`, so unspecified keys keep eza's defaults. Built in
# an anon function so the extension-group temporaries don't leak into the shell.
# Palette: dir #7daea3 · exec/source #a9b665 · symlink/audio #89b482 ·
# image/video #d3869b · archive #e78a4e · size/doc #d8a657 · crypto #ea6962 ·
# file/user #d4be98 · date/group/temp #928374.
() {
  local _img='38;2;211;134;155' _aud='38;2;137;180;130' _arc='38;2;231;138;78' \
        _src='38;2;169;182;101'  _cfg='38;2;212;190;152' _e
  EZA_COLORS='di=1;38;2;125;174;163:ex=1;38;2;169;182;101:ln=38;2;137;180;130:da=38;2;146;131;116:uu=38;2;212;190;152:gu=38;2;146;131;116:sn=38;2;216;166;87:sb=38;2;216;166;87:fi=38;2;212;190;152:or=38;2;234;105;98:cr=38;2;234;105;98:do=38;2;216;166;87:tm=38;2;146;131;116'
  for _e in jpg jpeg png gif bmp svg webp tiff ico heic avif jxl mp4 m4v mkv avi mov webm flv wmv mpeg mpg; do EZA_COLORS+=":*.$_e=$_img"; done
  for _e in mp3 flac wav ogg oga m4a aac opus wma aiff; do EZA_COLORS+=":*.$_e=$_aud"; done
  for _e in tar tgz gz bz2 xz txz zst zip 7z rar lz4 lzma deb rpm jar war apk iso dmg cab; do EZA_COLORS+=":*.$_e=$_arc"; done
  for _e in py js mjs cjs ts tsx jsx rs go c cc cpp h hpp java kt rb php pl pm lua vim el swift dart scala sql jl r sh bash zsh fish ipynb; do EZA_COLORS+=":*.$_e=$_src"; done
  for _e in json yaml yml toml ini cfg conf xml html htm css scss sass less md markdown rst tex env; do EZA_COLORS+=":*.$_e=$_cfg"; done
  export EZA_COLORS
}

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
