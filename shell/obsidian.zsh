# ============================================
# OBSIDIAN VAULT INTEGRATION
# ============================================
# Profile-aware vault routing — `_claw_obsidian_vault` returns the right
# sub-vault based on $CLAW_ACTIVE_PROFILE. All helpers (o/obs/on/os/ov)
# delegate to it, so switching profiles automatically swaps which vault
# they target.

# Root vault directory (parent of all sub-vaults)
export OBSIDIAN_ROOT="${OBSIDIAN_ROOT:-$HOME/vault-main}"

# Per-profile sub-vault mapping. Override per-shell by exporting
# OBSIDIAN_VAULT_OVERRIDE=<full-path-or-subdir-name>.
typeset -gA _CLAW_OBSIDIAN_VAULTS
_CLAW_OBSIDIAN_VAULTS=(
    cortex     "cortex-obsidian-vault"
    security   "_working"
    devops     "_working"
    cloud      "_working"
    ai         "_working"
    research   "000_master_vault"
    claude     "_working"
    local      "000_master_vault"
    default    "000_master_vault"
    # Phase B1 additions:
    vault      "000_master_vault"
    brainstorm "000_master_vault"
    pmo        "_working"
)

# Resolve the active vault path. Order:
#   1. $OBSIDIAN_VAULT_OVERRIDE (full path or sub-vault name) — caller wins
#   2. _CLAW_OBSIDIAN_VAULTS[$CLAW_ACTIVE_PROFILE]
#   3. fallback: $OBSIDIAN_ROOT/000_master_vault
_claw_obsidian_vault() {
    local sub
    if [[ -n "${OBSIDIAN_VAULT_OVERRIDE:-}" ]]; then
        sub="$OBSIDIAN_VAULT_OVERRIDE"
    elif [[ -n "${CLAW_ACTIVE_PROFILE:-}" ]]; then
        sub="${_CLAW_OBSIDIAN_VAULTS[$CLAW_ACTIVE_PROFILE]:-000_master_vault}"
    else
        sub="000_master_vault"
    fi
    # Allow absolute path as override
    if [[ "$sub" = /* ]]; then
        echo "$sub"
    else
        echo "$OBSIDIAN_ROOT/$sub"
    fi
}

# Live var that everything else reads. Re-evaluated when this file is
# resourced (e.g. after profile switch). For up-to-date routing in long-
# running shells, helpers below call _claw_obsidian_vault directly.
export OBSIDIAN_VAULT="$(_claw_obsidian_vault)"

# --------------------------------------------
# Aliases
# --------------------------------------------
alias o='cd "$(_claw_obsidian_vault)" && ls -lt'
alias obs='claw_open "obsidian://"'

# --------------------------------------------
# Functions
# --------------------------------------------

# on: Open Note (New or Existing) in the active vault
# Usage: on "Note Name"
function on() {
    local note_name="$1"
    if [[ -z "$note_name" ]]; then
        echo "Usage: on \"Note Name\""
        return 1
    fi
    local vault="$(_claw_obsidian_vault)"
    local note="$vault/$note_name.md"
    if [[ ! -f "$note" ]]; then
        printf "# %s\n\nCreated: %s\n" "$note_name" "$(date '+%Y-%m-%d %H:%M')" > "$note"
        echo "Created new note: $note_name.md (in $(basename "$vault"))"
    fi
    claw_open "obsidian://open?vault=$(basename "$vault")&file=$(urlencode "$note_name")"
}

# os: Obsidian Search (Content) via Ripgrep + FZF
# Usage: os "search term"   |   os  (no arg → fuzzy file picker)
function os() {
    local vault="$(_claw_obsidian_vault)"
    if [[ -z "$1" ]]; then
        cd "$vault" && fzf --preview 'bat --style=numbers --color=always {}' \
            | xargs -I {} claw_open "obsidian://open?vault=$(basename "$vault")&file={}"
    else
        cd "$vault" && rg --line-number --no-heading --color=always --smart-case "$1" | \
          fzf --ansi --delimiter : \
              --preview 'bat --style=numbers --color=always {1} --highlight-line {2}' \
              --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' \
              --bind "enter:become(claw_open 'obsidian://open?vault=$(basename "$vault")&file={1}')"
    fi
}

# ov: Vault file-name fuzzy picker
function ov() {
    local vault="$(_claw_obsidian_vault)"
    cd "$vault" && find . -maxdepth 3 -not -path '*/.*' | fzf --preview 'bat --style=numbers --color=always {}'
}

# Daily note (./<vault>/dailies/YYYY-MM-DD.md)
# Created with a starter template if missing.
function otoday() {
    local vault="$(_claw_obsidian_vault)"
    local today="$(date '+%Y-%m-%d')"
    local dir="$vault/dailies"
    local note="$dir/$today.md"
    mkdir -p "$dir"
    if [[ ! -f "$note" ]]; then
        cat > "$note" <<EOF
# $today

## Notes

## Captures

## Profile log
EOF
        echo "Created daily note: dailies/$today.md (in $(basename "$vault"))"
    fi
    claw_open "obsidian://open?vault=$(basename "$vault")&file=$(urlencode "dailies/$today")"
}

# Quick-capture: append text to today's daily note under a "Captures" heading.
# Usage: ocapture "anything you want to remember"
function ocapture() {
    if [[ -z "$1" ]]; then
        echo "Usage: ocapture \"text to capture\""
        return 1
    fi
    local vault="$(_claw_obsidian_vault)"
    local today="$(date '+%Y-%m-%d')"
    local note="$vault/dailies/$today.md"
    mkdir -p "$(dirname "$note")"
    [[ ! -f "$note" ]] && otoday >/dev/null
    printf -- "- [%s] %s\n" "$(date '+%H:%M')" "$*" >> "$note"
    echo "  ✓ captured to dailies/$today.md"
}

# List all sub-vaults under OBSIDIAN_ROOT, marking the active one.
function ovaults() {
    local active="$(_claw_obsidian_vault)"
    local active_name="$(basename "$active")"
    echo ""
    printf "  Vault root: \e[38;2;201;209;217m%s\e[0m\n" "$OBSIDIAN_ROOT"
    printf "  Active:     \e[38;2;63;185;80m%s\e[0m" "$active_name"
    [[ -n "$CLAW_ACTIVE_PROFILE" ]] && printf "  \e[38;2;139;148;158m(profile: %s)\e[0m" "$CLAW_ACTIVE_PROFILE"
    echo ""
    echo ""
    if [[ ! -d "$OBSIDIAN_ROOT" ]]; then
        printf "  \e[38;2;255;123;114m✗\e[0m vault root not found\n"
        return 1
    fi
    setopt local_options null_glob
    for d in "$OBSIDIAN_ROOT"/*/; do
        local name="$(basename "$d")"
        # Skip Obsidian's own metadata
        [[ "$name" == ".obsidian" ]] && continue
        if [[ "$name" == "$active_name" ]]; then
            printf "  \e[38;2;63;185;80m●\e[0m \e[38;2;201;209;217m%s\e[0m \e[38;2;139;148;158m(active)\e[0m\n" "$name"
        else
            printf "  \e[38;2;139;148;158m○ %s\e[0m\n" "$name"
        fi
    done
    echo ""
}

# Switch sub-vault for the rest of this shell.
# Usage: ovuse cortex-obsidian-vault   |   ovuse /path/to/other-vault
function ovuse() {
    if [[ -z "$1" ]]; then
        echo "Usage: ovuse <subvault-name-or-absolute-path>"
        ovaults
        return 1
    fi
    export OBSIDIAN_VAULT_OVERRIDE="$1"
    local resolved="$(_claw_obsidian_vault)"
    if [[ ! -d "$resolved" ]]; then
        printf "  \e[38;2;255;123;114m✗\e[0m vault not found: %s\n" "$resolved" >&2
        unset OBSIDIAN_VAULT_OVERRIDE
        return 1
    fi
    export OBSIDIAN_VAULT="$resolved"
    printf "  \e[38;2;63;185;80m✓\e[0m active vault → \e[38;2;201;209;217m%s\e[0m\n" "$(basename "$resolved")"
}

# Helper for URL encoding
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
# a one-line "[HH:MM] Loaded <profile>" entry under the daily note's
# "Profile log" section. Useful for context-switch journaling. Off by default.
_claw_vault_breadcrumb() {
    [[ "${CLAW_VAULT_BREADCRUMBS:-0}" -eq 1 ]] || return 0
    [[ -z "${CLAW_ACTIVE_PROFILE:-}" ]] && return 0
    local vault="$(_claw_obsidian_vault)"
    [[ ! -d "$vault" ]] && return 0
    local today="$(date '+%Y-%m-%d')"
    local note="$vault/dailies/$today.md"
    mkdir -p "$(dirname "$note")"
    [[ ! -f "$note" ]] && {
        printf "# %s\n\n## Notes\n\n## Captures\n\n## Profile log\n" "$today" > "$note"
    }
    printf -- "- [%s] Loaded **%s** profile\n" "$(date '+%H:%M')" "$CLAW_ACTIVE_PROFILE" >> "$note"
}
