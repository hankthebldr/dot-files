# shell/profiles/pmo/linux.zsh — Linux fallback (Things 3 is macOS-only)
#
# Strategy on Linux:
#   1. If you SSH to your Mac (claw remote mac …), invoke Things 3 there.
#   2. If you don't, fall back to taskwarrior as a local task system.
#   3. If neither is set up, the aliases print a clear hint instead of
#      pretending to work.

# Override: set TASKWARRIOR=1 if you've installed `task` locally and want it
# as the primary backend.
TASKWARRIOR="${TASKWARRIOR:-0}"
command -v task &>/dev/null && [[ "$TASKWARRIOR" == "1" ]] && _PMO_BACKEND="task" || _PMO_BACKEND="hint"

# Override: set MAC_HOST to your Mac's Tailscale name to SSH-forward Things 3.
MAC_HOST="${MAC_HOST:-}"

tadd() {
    local title="$*"
    [[ -z "$title" ]] && { echo "usage: tadd <task title>" >&2; return 1; }
    case "$_PMO_BACKEND" in
        task)
            task add "$title"
            ;;
        *)
            if [[ -n "$MAC_HOST" ]]; then
                # Use the Mac's `tadd` over SSH — assumes dot-files is loaded there
                ssh -o ConnectTimeout=3 "$MAC_HOST" "zsh -ic 'tadd \"$title\"'" 2>/dev/null \
                    || echo "ssh to $MAC_HOST failed — install taskwarrior or fix tailscale"
            else
                echo "Things 3 is macOS-only. Options:"
                echo "  · install taskwarrior:  sudo apt install task  +  export TASKWARRIOR=1"
                echo "  · SSH to Mac:           export MAC_HOST=<tailscale-name>"
            fi
            ;;
    esac
}

today() {
    case "$_PMO_BACKEND" in
        task) task next limit:20 ;;
        *)    [[ -n "$MAC_HOST" ]] && ssh "$MAC_HOST" "zsh -ic today" || echo "see tadd — same setup needed" ;;
    esac
}

inbox() {
    case "$_PMO_BACKEND" in
        task) task project: limit:20 ;;
        *)    [[ -n "$MAC_HOST" ]] && ssh "$MAC_HOST" "zsh -ic inbox" || echo "see tadd — same setup needed" ;;
    esac
}

tdone() {
    local query="$*"
    case "$_PMO_BACKEND" in
        task) task /"$query"/ done ;;
        *)    [[ -n "$MAC_HOST" ]] && ssh "$MAC_HOST" "zsh -ic 'tdone \"$query\"'" || echo "see tadd — same setup needed" ;;
    esac
}

_pmo_install_hint() {
    case "$1" in
        task|taskwarrior)
            echo "sudo apt install task"
            ;;
        gh)
            echo "sudo apt install gh   # (or use the GitHub repo for latest)"
            ;;
        jq)
            echo "sudo apt install jq"
            ;;
        claude)
            echo "see https://docs.anthropic.com/claude/docs/claude-code"
            ;;
        *)
            echo "set MAC_HOST=<tailscale-name> for Things 3 over SSH"
            ;;
    esac
}
