# ============================================
# OBSIDIAN VAULT INTEGRATION
# ============================================

# Vault Path - Update if you move your vault
export OBSIDIAN_VAULT="$HOME/vault-main"

# --------------------------------------------
# Aliases
# --------------------------------------------
alias o='cd "$OBSIDIAN_VAULT" && ls -lt'
alias obs='open -a "Obsidian"'

# --------------------------------------------
# Functions
# --------------------------------------------

# on: Open Note (New or Existing)
# Usage: on "Note Name"
function on() {
    local note_name="$1"
    if [ -z "$note_name" ]; then
        echo "Usage: on \"Note Name\""
        return 1
    fi
    
    # Create file if it doesn't exist
    if [ ! -f "$OBSIDIAN_VAULT/$note_name.md" ]; then
        echo "# $note_name\n\nCreated: $(date '+%Y-%m-%d %H:%M')\n" > "$OBSIDIAN_VAULT/$note_name.md"
        echo "Created new note: $note_name.md"
    fi
    
    # Open in Obsidian via URI
    open "obsidian://open?vault=$(basename "$OBSIDIAN_VAULT")&file=$(urlencode "$note_name")"
}

# os: Obsidian Search (Content) using Ripgrep + FZF
# Usage: os "search term"
function os() {
    if [ -z "$1" ]; then
        # If no argument, just fuzzy find file names
        cd "$OBSIDIAN_VAULT" && fzf --preview 'bat --style=numbers --color=always {}' | xargs -I {} open "obsidian://open?vault=$(basename "$OBSIDIAN_VAULT")&file={}"
    else
        # Search content with ripgrep and feed to fzf
        cd "$OBSIDIAN_VAULT" && rg --line-number --no-heading --color=always --smart-case "$1" | \
          fzf --ansi \
              --delimiter : \
              --preview 'bat --style=numbers --color=always {1} --highlight-line {2}' \
              --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' \
              --bind 'enter:become(open "obsidian://open?vault=$(basename "$OBSIDIAN_VAULT")&file={1}")'
    fi
}

# ov: Obsidian Vault Search (File Names)
function ov() {
    cd "$OBSIDIAN_VAULT" && find . -maxdepth 3 -not -path '*/.*' | fzf --preview 'bat --style=numbers --color=always {}'
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
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}
