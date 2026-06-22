# ============================================
# OBSIDIAN VAULT INTEGRATION
# ============================================
# One registered vault (~/hr-vault-main-pa) with profile-aware routing at the
# FOLDER level: $CLAW_ACTIVE_PROFILE selects a top-level folder *inside* the
# vault that the scoped helpers (o/on/os/ov) target. Daily-note helpers
# (otoday/ocapture) stay GLOBAL in the "Daily Note/" journal regardless of
# profile. Resolution splits into four single-purpose helpers:
#   _claw_obsidian_vault  → vault root path        (which vault)
#   _claw_obsidian_folder → folder name in vault   (which folder)
#   _claw_obsidian_dir    → vault/folder absolute  (the two joined)
#   _claw_obsidian_uri    → obsidian:// deep-link  (vault-relative path)
# Override the folder per-shell with OBSIDIAN_FOLDER_OVERRIDE (see `ovuse`);
# override the whole vault with OBSIDIAN_VAULT_OVERRIDE (rare — a different vault).

# Parent dir used to resolve a bare-name vault override.
export OBSIDIAN_ROOT="${OBSIDIAN_ROOT:-$HOME}"
# The registered Obsidian vault — Henry's knowledge spine.
export OBSIDIAN_VAULT_NAME="${OBSIDIAN_VAULT_NAME:-hr-vault-main-pa}"
# Triage folder: catch-all for profiles without a dedicated home and for
# no-profile shells. Un-themed notes land here to be filed later.
export OBSIDIAN_TRIAGE_FOLDER="${OBSIDIAN_TRIAGE_FOLDER:-_wip}"
# Global daily-note folder — one continuous journal, profile-independent.
export OBSIDIAN_DAILY_FOLDER="${OBSIDIAN_DAILY_FOLDER:-Daily Note}"

# Per-profile → top-level folder mapping. Unlisted profiles fall back to
# $OBSIDIAN_TRIAGE_FOLDER. Override per-shell with OBSIDIAN_FOLDER_OVERRIDE.
typeset -gA _CLAW_OBSIDIAN_FOLDERS
_CLAW_OBSIDIAN_FOLDERS=(
    cortex   "CORTEX"
    deck     "CORTEX"
    devops   "DEVELOPMENT"
    pmo      "WWTS - Projects"
    security "Secops"
    cloud    "PUBLIC CLOUD PROVIDERS"
    ai       "_agents"
    claude   "_agents"
)

# Resolve the active vault ROOT. OBSIDIAN_VAULT_OVERRIDE wins (absolute path,
# or bare name under $OBSIDIAN_ROOT); else $OBSIDIAN_ROOT/$OBSIDIAN_VAULT_NAME.
_claw_obsidian_vault() {
    local sub="${OBSIDIAN_VAULT_OVERRIDE:-$OBSIDIAN_VAULT_NAME}"
    if [[ "$sub" = /* ]]; then
        echo "$sub"
    else
        echo "$OBSIDIAN_ROOT/$sub"
    fi
}

# Resolve the active FOLDER name (relative to the vault root). Order:
#   1. $OBSIDIAN_FOLDER_OVERRIDE — caller wins (set by `ovuse`)
#   2. _CLAW_OBSIDIAN_FOLDERS[$CLAW_ACTIVE_PROFILE]
#   3. $OBSIDIAN_TRIAGE_FOLDER (default: _wip)
_claw_obsidian_folder() {
    if [[ -n "${OBSIDIAN_FOLDER_OVERRIDE:-}" ]]; then
        echo "$OBSIDIAN_FOLDER_OVERRIDE"
    elif [[ -n "${CLAW_ACTIVE_PROFILE:-}" && -n "${_CLAW_OBSIDIAN_FOLDERS[$CLAW_ACTIVE_PROFILE]:-}" ]]; then
        echo "${_CLAW_OBSIDIAN_FOLDERS[$CLAW_ACTIVE_PROFILE]}"
    else
        echo "$OBSIDIAN_TRIAGE_FOLDER"
    fi
}

# Absolute path to the active profile-scoped folder (vault root + folder).
_claw_obsidian_dir() {
    echo "$(_claw_obsidian_vault)/$(_claw_obsidian_folder)"
}

# Build an obsidian:// open URL for a path relative to the vault root.
# Vault name is fixed to the registered vault; spaces/punctuation are encoded.
_claw_obsidian_uri() {
    local vault_name="$(basename "$(_claw_obsidian_vault)")"
    echo "obsidian://open?vault=$(urlencode "$vault_name")&file=$(urlencode "$1")"
}

# Live var consumers (toolkit.sh, fastfetch) read — always the vault ROOT,
# not the scoped folder. Re-evaluated when this file is resourced.
export OBSIDIAN_VAULT="$(_claw_obsidian_vault)"

# --------------------------------------------
# Aliases
# --------------------------------------------
alias obs='claw_open "obsidian://"'

# --------------------------------------------
# Functions
# --------------------------------------------

# o: cd into the active profile-scoped folder.
function o() {
    local dir="$(_claw_obsidian_dir)"
    mkdir -p "$dir" 2>/dev/null
    cd "$dir" && command ls -lt
}

# on: Open Note (New or Existing) in the active profile-scoped folder.
# Usage: on "Note Name"
function on() {
    local note_name="$1"
    if [[ -z "$note_name" ]]; then
        echo "Usage: on \"Note Name\""
        return 1
    fi
    local dir="$(_claw_obsidian_dir)"
    local folder="$(_claw_obsidian_folder)"
    mkdir -p "$dir"
    local note="$dir/$note_name.md"
    if [[ ! -f "$note" ]]; then
        printf "# %s\n\nCreated: %s\n" "$note_name" "$(date '+%Y-%m-%d %H:%M')" > "$note"
        echo "Created new note: $note_name.md (in $folder)"
    fi
    claw_open "$(_claw_obsidian_uri "$folder/$note_name")"
}

# os: Obsidian Search (Content) via Ripgrep + FZF, scoped to the active folder.
# Usage: os "search term"   |   os  (no arg → fuzzy file picker)
# Selection is captured back in this shell (not fzf `become`), so claw_open and
# url-encoding work even for folders with spaces.
function os() {
    local dir="$(_claw_obsidian_dir)"
    local folder="$(_claw_obsidian_folder)"
    mkdir -p "$dir"
    local sel
    if [[ -z "$1" ]]; then
        sel="$(cd "$dir" && fzf --preview 'bat --style=numbers --color=always {}')"
        [[ -n "$sel" ]] && claw_open "$(_claw_obsidian_uri "$folder/$sel")"
    else
        sel="$(cd "$dir" && rg --line-number --no-heading --color=always --smart-case "$1" | \
          fzf --ansi --delimiter : \
              --preview 'bat --style=numbers --color=always {1} --highlight-line {2}' \
              --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' | cut -d: -f1)"
        [[ -n "$sel" ]] && claw_open "$(_claw_obsidian_uri "$folder/$sel")"
    fi
}

# ov: Folder file-name fuzzy picker (active profile-scoped folder).
function ov() {
    local dir="$(_claw_obsidian_dir)"
    mkdir -p "$dir"
    cd "$dir" && find . -maxdepth 3 -not -path '*/.*' | fzf --preview 'bat --style=numbers --color=always {}'
}

# otoday: GLOBAL daily note (<vault>/Daily Note/YYYY-MM-DD.md), profile-independent.
# Created with a starter template if missing.
function otoday() {
    local vault="$(_claw_obsidian_vault)"
    local today="$(date '+%Y-%m-%d')"
    local dir="$vault/$OBSIDIAN_DAILY_FOLDER"
    local note="$dir/$today.md"
    mkdir -p "$dir"
    if [[ ! -f "$note" ]]; then
        cat > "$note" <<EOF
# $today

## Notes

## Captures

## Profile log
EOF
        echo "Created daily note: $OBSIDIAN_DAILY_FOLDER/$today.md"
    fi
    claw_open "$(_claw_obsidian_uri "$OBSIDIAN_DAILY_FOLDER/$today")"
}

# ocapture: append text to today's GLOBAL daily note under "Captures".
# Usage: ocapture "anything you want to remember"
function ocapture() {
    if [[ -z "$1" ]]; then
        echo "Usage: ocapture \"text to capture\""
        return 1
    fi
    local vault="$(_claw_obsidian_vault)"
    local today="$(date '+%Y-%m-%d')"
    local note="$vault/$OBSIDIAN_DAILY_FOLDER/$today.md"
    mkdir -p "$(dirname "$note")"
    [[ ! -f "$note" ]] && otoday >/dev/null
    printf -- "- [%s] %s\n" "$(date '+%H:%M')" "$*" >> "$note"
    echo "  ✓ captured to $OBSIDIAN_DAILY_FOLDER/$today.md"
}

# Show the active profile-scoped folder + list the vault's top-level folders.
function ovaults() {
    local vault="$(_claw_obsidian_vault)"
    local active_folder="$(_claw_obsidian_folder)"
    echo ""
    printf "  Vault:  \e[38;2;201;209;217m%s\e[0m\n" "$(basename "$vault")"
    printf "  Folder: \e[38;2;63;185;80m%s\e[0m" "$active_folder"
    [[ -n "$CLAW_ACTIVE_PROFILE" ]] && printf "  \e[38;2;139;148;158m(profile: %s)\e[0m" "$CLAW_ACTIVE_PROFILE"
    echo ""
    echo ""
    if [[ ! -d "$vault" ]]; then
        printf "  \e[38;2;255;123;114m✗\e[0m vault not found: %s\n" "$vault"
        return 1
    fi
    printf "  \e[38;2;139;148;158mFolders (● = active route):\e[0m\n"
    setopt local_options null_glob   # dotdirs (.obsidian/.git/.trash) skipped by default
    for d in "$vault"/*/; do
        local name="$(basename "$d")"
        if [[ "$name" == "$active_folder" ]]; then
            printf "  \e[38;2;63;185;80m●\e[0m \e[38;2;201;209;217m%s\e[0m \e[38;2;139;148;158m(active)\e[0m\n" "$name"
        else
            printf "  \e[38;2;139;148;158m○ %s\e[0m\n" "$name"
        fi
    done
    echo ""
}

# Switch the active profile-scoped folder for the rest of this shell.
# Usage: ovuse CORTEX   |   ovuse Secops
function ovuse() {
    if [[ -z "$1" ]]; then
        echo "Usage: ovuse <folder-name>"
        ovaults
        return 1
    fi
    local vault="$(_claw_obsidian_vault)"
    if [[ ! -d "$vault/$1" ]]; then
        printf "  \e[38;2;255;123;114m✗\e[0m folder not found in vault: %s\n" "$1" >&2
        return 1
    fi
    export OBSIDIAN_FOLDER_OVERRIDE="$1"
    printf "  \e[38;2;63;185;80m✓\e[0m active folder → \e[38;2;201;209;217m%s\e[0m\n" "$1"
}

# Helper for URL encoding (preserves '/' so vault-relative paths stay intact).
function urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            /                ) o="${c}" ;;
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# --------------------------------------------
# Profile-load breadcrumb (opt-in)
# --------------------------------------------
# When CLAW_VAULT_BREADCRUMBS=1 is set in the env, every profile load drops
# a one-line "[HH:MM] Loaded <profile>" entry under the GLOBAL daily note's
# "Profile log" section. Useful for context-switch journaling. Off by default.
_claw_vault_breadcrumb() {
    [[ "${CLAW_VAULT_BREADCRUMBS:-0}" -eq 1 ]] || return 0
    [[ -z "${CLAW_ACTIVE_PROFILE:-}" ]] && return 0
    local vault="$(_claw_obsidian_vault)"
    [[ ! -d "$vault" ]] && return 0
    local today="$(date '+%Y-%m-%d')"
    local note="$vault/$OBSIDIAN_DAILY_FOLDER/$today.md"
    mkdir -p "$(dirname "$note")"
    [[ ! -f "$note" ]] && {
        printf "# %s\n\n## Notes\n\n## Captures\n\n## Profile log\n" "$today" > "$note"
    }
    printf -- "- [%s] Loaded **%s** profile\n" "$(date '+%H:%M')" "$CLAW_ACTIVE_PROFILE" >> "$note"
}
