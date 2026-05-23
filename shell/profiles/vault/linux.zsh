# shell/profiles/vault/linux.zsh — Linux-specific vault tooling

# --- Ripgrep-based vault search (no Spotlight on Linux) ---
vfind() {
    local needle="${1:?usage: vfind <pattern>}"
    local vault="$(_claw_obsidian_vault)"
    # Title match (filename basename), then content match — separated for clarity
    {
        find "$vault" -iname "*${needle}*.md" 2>/dev/null
        rg -l --hidden -g '!.git' "$needle" "$vault" 2>/dev/null
    } | sort -u
}

# --- Open vault note via xdg-open (uses Obsidian URL scheme if installed) ---
vopen() {
    local note="${1:-}"
    local vault_name
    vault_name="$(basename "$(_claw_obsidian_vault)")"
    local url="obsidian://open?vault=${vault_name}"
    [[ -n "$note" ]] && url="${url}&file=$(printf %s "$note" | jq -sRr @uri 2>/dev/null || echo "$note")"

    if command -v xdg-open &>/dev/null; then
        xdg-open "$url" 2>/dev/null
    else
        echo "$url"  # print so user can paste into a Mac running Obsidian
    fi
}

# --- Inotify watcher: log every vault write to a tail-able file ---
# Useful when you want to know what changed in the vault (sync debugging, etc.)
vwatch() {
    if ! command -v inotifywait &>/dev/null; then
        echo "needs inotify-tools — sudo apt install inotify-tools" >&2
        return 1
    fi
    local vault="$(_claw_obsidian_vault)"
    local logfile="${1:-/tmp/vault-watch.log}"
    echo "watching $vault → $logfile (Ctrl-C to stop)"
    inotifywait -r -m -e modify,create,delete,move \
        --timefmt '%Y-%m-%d %H:%M:%S' \
        --format '%T %e %w%f' \
        "$vault" >> "$logfile"
}

# --- Granola not available on Linux ---
alias vgranola='echo "granola is macOS-only — capture audio elsewhere, drop transcripts in 00-Inbox/"'

# --- Quick capture via stdin → inbox ---
# Pipe text in, get an inbox note with timestamp. Lighter than the Mac shortcut.
vquick() {
    local vault="$(_claw_obsidian_vault)"
    local inbox="$vault/00-Inbox"
    [[ -d "$inbox" ]] || inbox="$vault"
    local note="$inbox/quick-$(date +%Y%m%d-%H%M%S).md"
    cat > "$note"
    echo "captured → $note"
}

_vault_install_hint() {
    case "$1" in
        ripgrep|fzf|glow|bat|pandoc)
            echo "sudo apt install $1"
            ;;
        yq)
            echo "see scripts/install/research-toolchain.sh (binary download)"
            ;;
        obsidian)
            echo "see https://obsidian.md/download (AppImage / snap / flatpak)"
            ;;
        *)
            echo "claw install vault"
            ;;
    esac
}
