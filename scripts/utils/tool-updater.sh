#!/usr/bin/env bash
# scripts/utils/tool-updater.sh
# Background auto-updater for integrated CLI tools, with optional interactive UI.
#
# Modes:
#   tool-updater.sh                  silent background daemon (default — runs
#                                    in a backgrounded subshell, all output
#                                    suppressed; respects per-category intervals)
#   tool-updater.sh --interactive    foreground TUI render with sections,
#                                    "next due" hints, and summary card
#   tool-updater.sh --force          like --interactive but ignores cache
#                                    intervals (run everything now)
#
# Cache granularity is per-CATEGORY (brew/pipx/go/cargo), not per-tool.
# Each category has its own interval — see CATEGORIES below.

# ============================================
# CONFIG
# ============================================
CACHE_DIR="$HOME/.cache/claw-updates"
mkdir -p "$CACHE_DIR"

CURRENT_TIME=$(date +%s)

# Per-category: name | interval-seconds | tool list (space-separated)
# - brew  weekly      pre-built binaries, lightweight
# - pipx  weekly      python wheels, fast
# - go    bi-weekly   binary downloads, moderate CPU
# - cargo monthly     compiles from source, CPU heavy (runs at nice 19)
CATEGORIES=(
    "brew|604800|eza bat zoxide fd ripgrep bottom zellij"
    "pipx|604800|rovr osint-d2"
    "go|1209600|github.com/cladamos/clawea@latest"
    "cargo|2592000|netwatch-tui eilmeldung"
)

# ============================================
# ARGV PARSING
# ============================================
INTERACTIVE=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --interactive|-i) INTERACTIVE=1 ;;
        --force|-f)       FORCE=1; INTERACTIVE=1 ;;  # force implies interactive
        --help|-h)
            sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# ============================================
# CACHE HELPERS
# ============================================
needs_update() {
    local cache_file="$CACHE_DIR/$1"
    local interval_seconds="$2"
    [[ ! -f "$cache_file" ]] && return 0
    local last
    last=$(cat "$cache_file")
    (( CURRENT_TIME - last >= interval_seconds ))
}

mark_updated() {
    echo "$CURRENT_TIME" > "$CACHE_DIR/$1"
}

# Format remaining time until next update in human-friendly Nd Nh form.
time_until_due() {
    local cache_file="$CACHE_DIR/$1"
    local interval="$2"
    [[ ! -f "$cache_file" ]] && { echo "now"; return; }
    local last elapsed remaining
    last=$(cat "$cache_file")
    elapsed=$(( CURRENT_TIME - last ))
    remaining=$(( interval - elapsed ))
    (( remaining <= 0 )) && { echo "now"; return; }
    local days=$(( remaining / 86400 ))
    local hours=$(( (remaining % 86400) / 3600 ))
    if (( days > 0 )); then
        printf "%dd %dh" "$days" "$hours"
    else
        local mins=$(( (remaining % 3600) / 60 ))
        printf "%dh %dm" "$hours" "$mins"
    fi
}

# Run the brew tool list (or just `brew upgrade <list>`). stderr is NOT
# suppressed so tui_run_step's `gum spin --show-error` can surface a real
# failure; the exit code propagates so the step renders ●/✗ correctly.
run_brew()  { brew upgrade $*; }
run_pipx()  { for t in $*; do pipx upgrade "$t"; done; }
run_go()    { for t in $*; do go install "$t"; done; }
run_cargo() { for t in $*; do nice -n 19 cargo install "$t"; done; }
# Export so the gum-spinner subshell (`bash -c "run_<name> <tool>"`) resolves
# them — without this they are "command not found" (exit 127) in that subshell,
# which made `claw tools` a silent no-op that still claimed success.
export -f run_brew run_pipx run_go run_cargo

# ============================================
# SILENT MODE (default — preserves prior behavior)
# ============================================
if [[ $INTERACTIVE -eq 0 ]]; then
    # Single-flight lock: mkdir is atomic, so two concurrent shell logins can't
    # both kick off cargo/go builds at once. Stale lock from a dead PID is
    # reclaimed. Failures land in a log instead of being swallowed by /dev/null.
    LOCK_DIR="$CACHE_DIR/.update.lock"
    ERR_LOG="$CACHE_DIR/last-error.log"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_DIR/pid"
    else
        # Lock held — reclaim only if the owning PID is gone.
        old_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || echo '')"
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            exit 0   # another updater is genuinely running
        fi
        rm -rf "$LOCK_DIR" 2>/dev/null
        mkdir "$LOCK_DIR" 2>/dev/null || exit 0
        echo "$$" > "$LOCK_DIR/pid"
    fi
    (
        trap 'rm -rf "$LOCK_DIR" 2>/dev/null' EXIT
        for entry in "${CATEGORIES[@]}"; do
            IFS='|' read -r name interval tools <<< "$entry"
            if needs_update "$name" "$interval"; then
                if command -v "$name" &>/dev/null; then
                    if ! "run_$name" $tools 2>>"$ERR_LOG"; then
                        echo "[$(date '+%F %T')] $name update returned nonzero" >> "$ERR_LOG"
                    fi
                fi
                mark_updated "$name"
            fi
        done
    ) >/dev/null 2>>"$ERR_LOG" &
    exit 0
fi

# ============================================
# INTERACTIVE MODE
# ============================================
source "$(dirname "${BASH_SOURCE[0]}")/tui-style.sh"

clear

total_tools=0
for entry in "${CATEGORIES[@]}"; do
    IFS='|' read -r _ _ tools <<< "$entry"
    for _ in $tools; do ((total_tools++)); done
done

if (( FORCE )); then
    tui_header "🛠️  CLI TOOL UPDATE  (--force)" "Refreshing all $total_tools curated tools regardless of cache"
else
    tui_header "🛠️  CLI TOOL UPDATE" "Curated refresh across $total_tools tools (per-category interval)"
fi

# Counters for the summary card
SUMMARY_UPDATED=0
SUMMARY_FAILED=0
SUMMARY_DEFERRED=0
SUMMARY_UNAVAILABLE=0

for entry in "${CATEGORIES[@]}"; do
    IFS='|' read -r name interval tools <<< "$entry"

    # Pretty section name
    case "$name" in
        brew)  pretty="Homebrew" ;;
        pipx)  pretty="pipx (Python)" ;;
        go)    pretty="Go" ;;
        cargo) pretty="Cargo (Rust)" ;;
        *)     pretty="$name" ;;
    esac
    tui_section "$pretty"

    # Is the manager itself installed?
    if ! command -v "$name" &>/dev/null; then
        tui_skip "$name"
        for _ in $tools; do ((SUMMARY_UNAVAILABLE++)); done
        continue
    fi

    # Decide: due, forced, or deferred?
    if (( FORCE )) || needs_update "$name" "$interval"; then
        for tool in $tools; do
            # Pretty short label for the spinner
            label="${tool##*/}"
            label="${label%%@*}"
            if tui_run_step "Upgrading ${label}…" "run_$name $tool"; then
                SUMMARY_UPDATED=$((SUMMARY_UPDATED + 1))
            else
                SUMMARY_FAILED=$((SUMMARY_FAILED + 1))
            fi
        done
        mark_updated "$name"
    else
        local_due=$(time_until_due "$name" "$interval")
        printf "  ${c_dim}○ %s — next update in %s${c_reset}\n" "$name" "$local_due"
        printf "    ${c_dim}deferred: %s${c_reset}\n" "$tools"
        for _ in $tools; do ((SUMMARY_DEFERRED++)); done
    fi
done

# ============================================
# SUMMARY CARD
# ============================================
echo ""
echo "  ${c_purple}╭──────────────────────────────────────────────────────╮${c_reset}"
printf "  ${c_purple}│${c_reset}  ${c_green}${c_bold}%d${c_reset} ${c_dim}updated${c_reset}   ${c_orange}${c_bold}%d${c_reset} ${c_dim}deferred${c_reset}   ${c_red}${c_bold}%d${c_reset} ${c_dim}unavailable${c_reset}" \
    "$SUMMARY_UPDATED" "$SUMMARY_DEFERRED" "$SUMMARY_UNAVAILABLE"
# right-pad
total_chars=$(( 9 + ${#SUMMARY_UPDATED} + 10 + ${#SUMMARY_DEFERRED} + 13 + ${#SUMMARY_UNAVAILABLE} ))
pad=$(( 50 - total_chars ))
(( pad < 0 )) && pad=0
printf "%${pad}s${c_purple}│${c_reset}\n" ""
echo "  ${c_purple}╰──────────────────────────────────────────────────────╯${c_reset}"
echo ""

if (( SUMMARY_FAILED > 0 )); then
    printf "  ${c_red}✗ %d failed${c_reset} ${c_dim}— error output shown above each ✗ step${c_reset}\n\n" "$SUMMARY_FAILED"
fi

if (( SUMMARY_DEFERRED > 0 )) && [[ $FORCE -eq 0 ]]; then
    printf "  ${c_dim}Force a full refresh: ${c_white}claw tools --force${c_reset}\n\n"
fi
