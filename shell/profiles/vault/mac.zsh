# shell/profiles/vault/mac.zsh — macOS-specific vault tooling

# --- Spotlight-backed vault search ---
# mdfind hits Spotlight's index, which is way faster than rg over large vaults.
# Falls through to rg for content matching since Spotlight is filename-biased.
vfind() {
    local needle="${1:?usage: vfind <pattern>}"
    local vault="$(_claw_obsidian_vault)"
    mdfind -onlyin "$vault" "kMDItemDisplayName == '*${needle}*' || kMDItemTextContent == '*${needle}*'" 2>/dev/null
}

# --- Open vault in Obsidian via URL scheme ---
vopen() {
    local note="${1:-}"
    local vault_name
    vault_name="$(basename "$(_claw_obsidian_vault)")"
    if [[ -n "$note" ]]; then
        open "obsidian://open?vault=${vault_name}&file=$(printf %s "$note" | jq -sRr @uri 2>/dev/null || echo "$note")"
    else
        open "obsidian://open?vault=${vault_name}"
    fi
}

# --- Granola transcript landing ---
# If granola is installed, jump to its capture dir (Mac-only audio capture tool)
GRANOLA_DIR="$HOME/Library/Application Support/Granola/transcripts"
[[ -d "$GRANOLA_DIR" ]] && alias vgranola='cd "$GRANOLA_DIR" && ls -lt'

# --- Quick capture via macOS Shortcut (if user defined one) ---
# Henry: define a "Quick Note" shortcut in macOS Shortcuts.app that takes text
# input and appends to your inbox, then this alias triggers it.
alias vquick='shortcuts run "Quick Note" 2>/dev/null || echo "create a Quick Note shortcut in Shortcuts.app"'

_vault_install_hint() {
    case "$1" in
        ripgrep|fzf|glow|bat|pandoc|yq)
            echo "brew install $1"
            ;;
        obsidian)
            echo "brew install --cask obsidian"
            ;;
        *)
            echo "claw install vault"
            ;;
    esac
}
