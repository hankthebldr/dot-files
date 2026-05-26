# shell/profiles/pmo/mac.zsh — macOS-only Things 3 integration

# Things 3 lives on macOS only. AppleScript is the canonical interface,
# but the things-mcp / mbmccormick.things plugin exposes it via Claude tools.
# These shell aliases give you a CLI-side path that doesn't require Claude.

# --- Direct AppleScript ---
# Quick add to Things 3 inbox via URL scheme
tadd() {
    local title="$*"
    [[ -z "$title" ]] && { echo "usage: tadd <task title>" >&2; return 1; }
    # URL-encode the title (safe-ish for typical inputs)
    local encoded; encoded=$(printf %s "$title" | jq -sRr @uri 2>/dev/null || echo "$title")
    open "things:///add?title=${encoded}"
    echo "→ Things 3 inbox: $title"
}

# Show Today list (parses Things 3 AppleScript output)
today() {
    osascript -e 'tell application "Things3"
        set out to ""
        repeat with t in to dos of list "Today"
            set out to out & "  □ " & (name of t) & "\n"
        end repeat
        return out
    end tell' 2>/dev/null | head -50
}

# Show Inbox list
inbox() {
    osascript -e 'tell application "Things3"
        set out to ""
        repeat with t in to dos of list "Inbox"
            set out to out & "  □ " & (name of t) & "\n"
        end repeat
        return out
    end tell' 2>/dev/null | head -50
}

# Mark a task complete by exact title (best-effort fuzzy match)
tdone() {
    local title="$*"
    [[ -z "$title" ]] && { echo "usage: tdone <task title or partial>" >&2; return 1; }
    osascript -e "tell application \"Things3\"
        set candidates to (to dos whose name contains \"${title}\" and status is open)
        if (count of candidates) is 0 then
            return \"no match\"
        else if (count of candidates) is 1 then
            set status of item 1 of candidates to completed
            return \"✓ \" & (name of item 1 of candidates)
        else
            return \"ambiguous: \" & (count of candidates) & \" matches\"
        end if
    end tell"
}

# --- Things MCP awareness ---
# If you're inside Claude Code and the things-mcp plugin is enabled, the AI
# can do all of this directly. This alias points you at it.
alias things-mcp-help='echo "in Claude: use the things tools (add_todo, get_today, get_inbox, etc.)"'

_pmo_install_hint() {
    case "$1" in
        gh|jq)
            echo "brew install $1"
            ;;
        claude)
            echo "see https://docs.anthropic.com/claude/docs/claude-code"
            ;;
        *)
            echo "Things 3 install: https://culturedcode.com/things/"
            ;;
    esac
}
