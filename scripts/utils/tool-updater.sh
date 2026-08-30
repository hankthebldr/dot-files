#!/usr/bin/env bash
# scripts/utils/tool-updater.sh
# Background auto-updater for integrated CLI tools, with optional interactive UI.
# The fast lane is driven by cadence-tagged rows of config/manifest/tools.list
# (the ONE registry — spine contract): `id|source|cadence`, cadence ∈
# daily|weekly|biweekly|monthly. Rows without a cadence never enter the lane.
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
# Cache granularity is per-CATEGORY — one (source, cadence) group — not
# per-tool. Runner mapping by source: brew → brew upgrade <id> · pipx →
# pipx upgrade <id> · cargo → nice -n 19 cargo install <id> ·
# go:<pkg> → go install <pkg>@latest.

# ============================================
# CONFIG
# ============================================
CACHE_DIR="$HOME/.cache/claw-updates"
mkdir -p "$CACHE_DIR"

CURRENT_TIME=$(date +%s)

DOTFILES="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MANIFEST="$DOTFILES/config/manifest/tools.list"

# cadence → seconds (design contract; `fast` is not a cadence — daily is the floor)
cadence_seconds() {
    case "$1" in
        daily)    echo 86400   ;;
        weekly)   echo 604800  ;;
        biweekly) echo 1209600 ;;
        monthly)  echo 2592000 ;;
        *)        echo ""      ;;   # unknown cadence → row is not fast-lane
    esac
}

# seconds → cadence label, for the fallback entries' section headers
interval_cadence() {
    case "$1" in
        86400)   echo daily    ;;
        604800)  echo weekly   ;;
        1209600) echo biweekly ;;
        2592000) echo monthly  ;;
        *)       echo "${1}s"  ;;
    esac
}

# FALLBACK ONLY. The registry merge moved fast-lane curation into
# config/manifest/tools.list (cadence-tagged rows); this hardcoded set is used
# solely when the manifest is missing or carries no cadence-tagged rows.
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

# Build the runtime category set from cadence-tagged manifest rows, grouped by
# (source, cadence) at startup. Entry: manager|cache-key|interval|cadence|tools.
# Both silent and interactive modes consume this same parsed set.
RUN_SET=()
build_run_set() {
    local id src cad mgr tool secs key found i
    local keys=() mgrs=() intervals=() cads=() toolsets=()
    [[ -r "$MANIFEST" ]] || return 0
    while IFS='|' read -r id src cad; do
        id="${id//[[:space:]]/}"; src="${src//[[:space:]]/}"; cad="${cad//[[:space:]]/}"
        [[ -z "$id" || "$id" == \#* ]] && continue   # comments / section headers
        [[ -z "$cad" ]] && continue                  # 2-field row — not fast lane
        secs="$(cadence_seconds "$cad")"
        [[ -z "$secs" ]] && continue
        case "$src" in                               # runner mapping by source
            brew|pipx|cargo) mgr="$src"; tool="$id" ;;
            go:*)            mgr="go";   tool="${src#go:}@latest" ;;
            *)               continue ;;             # no fast-lane runner for this source
        esac
        key="${mgr}-${cad}"
        found=0; i=0
        while (( i < ${#keys[@]} )); do
            if [[ "${keys[$i]}" == "$key" ]]; then
                toolsets[$i]="${toolsets[$i]} $tool"
                found=1; break
            fi
            i=$(( i + 1 ))
        done
        if (( ! found )); then
            keys+=("$key"); mgrs+=("$mgr"); intervals+=("$secs")
            cads+=("$cad"); toolsets+=("$tool")
        fi
    done < "$MANIFEST"
    i=0
    while (( i < ${#keys[@]} )); do
        RUN_SET+=("${mgrs[$i]}|${keys[$i]}|${intervals[$i]}|${cads[$i]}|${toolsets[$i]}")
        i=$(( i + 1 ))
    done
}
build_run_set

if (( ${#RUN_SET[@]} == 0 )); then
    # Fallback path — keep the legacy bare-source cache keys (brew/pipx/go/cargo).
    for entry in "${CATEGORIES[@]}"; do
        IFS='|' read -r name interval tools <<< "$entry"
        RUN_SET+=("${name}|${name}|${interval}|$(interval_cadence "$interval")|${tools}")
    done
else
    # Cache-key continuity: pre-merge releases stamped bare per-source keys.
    # Adopt a legacy stamp for a new (source,cadence) composite key once, so
    # the first login after the registry merge doesn't rebuild every tool.
    for entry in "${RUN_SET[@]}"; do
        IFS='|' read -r mgr key _ _ _ <<< "$entry"
        [[ ! -f "$CACHE_DIR/$key" && -f "$CACHE_DIR/$mgr" ]] \
            && cp "$CACHE_DIR/$mgr" "$CACHE_DIR/$key" 2>/dev/null
    done
fi

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
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
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
# suppressed so claw_step can stream a real failure live; the exit code
# propagates so the step renders ✓/✗ correctly.
run_brew()  { brew upgrade "$@"; }
run_pipx()  { for t in "$@"; do pipx upgrade "$t"; done; }
run_go()    { for t in "$@"; do go install "$t"; done; }
run_cargo() { for t in "$@"; do nice -n 19 cargo install "$t"; done; }
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
        for entry in "${RUN_SET[@]}"; do
            IFS='|' read -r mgr key interval _ tools <<< "$entry"
            if needs_update "$key" "$interval"; then
                if command -v "$mgr" &>/dev/null; then
                    if ! "run_$mgr" $tools 2>>"$ERR_LOG"; then
                        echo "[$(date '+%F %T')] $key update returned nonzero" >> "$ERR_LOG"
                    fi
                fi
                mark_updated "$key"
            fi
        done
    ) >/dev/null 2>>"$ERR_LOG" &
    exit 0
fi

# ============================================
# INTERACTIVE MODE
# ============================================
source "$(dirname "${BASH_SOURCE[0]}")/theme.sh" 2>/dev/null || true
source "$(dirname "${BASH_SOURCE[0]}")/claw-progress.sh"

clear

total_tools=0
for entry in "${RUN_SET[@]}"; do
    IFS='|' read -r _ _ _ _ tools <<< "$entry"
    for _ in $tools; do ((total_tools++)); done
done

if (( FORCE )); then
    claw_ui_header "🛠️  CLI TOOL UPDATE  (--force)" "Refreshing all $total_tools curated tools regardless of cache"
else
    claw_ui_header "🛠️  CLI TOOL UPDATE" "Curated refresh across $total_tools tools (per-category interval)"
fi

# Counters for the summary card
SUMMARY_UPDATED=0
SUMMARY_FAILED=0
SUMMARY_DEFERRED=0
SUMMARY_UNAVAILABLE=0

for entry in "${RUN_SET[@]}"; do
    IFS='|' read -r mgr key interval cad tools <<< "$entry"

    # Pretty section name
    case "$mgr" in
        brew)  pretty="Homebrew" ;;
        pipx)  pretty="pipx (Python)" ;;
        go)    pretty="Go" ;;
        cargo) pretty="Cargo (Rust)" ;;
        *)     pretty="$mgr" ;;
    esac
    claw_ui_section "$pretty · $cad"

    # Is the manager itself installed?
    if ! command -v "$mgr" &>/dev/null; then
        claw_ui_skip "$mgr"
        for _ in $tools; do ((SUMMARY_UNAVAILABLE++)); done
        continue
    fi

    # Decide: due, forced, or deferred?
    if (( FORCE )) || needs_update "$key" "$interval"; then
        for tool in $tools; do
            # Pretty short label for the spinner
            label="${tool##*/}"
            label="${label%%@*}"
            if claw_step "Upgrading ${label}…" -- "run_$mgr" "$tool"; then
                SUMMARY_UPDATED=$((SUMMARY_UPDATED + 1))
            else
                SUMMARY_FAILED=$((SUMMARY_FAILED + 1))
            fi
        done
        mark_updated "$key"
    else
        local_due=$(time_until_due "$key" "$interval")
        printf "  %s○ %s — next update in %s%s\n" "$(_c muted)" "$mgr" "$local_due" "$(_creset)"
        printf "    %sdeferred: %s%s\n" "$(_c muted)" "$tools" "$(_creset)"
        for _ in $tools; do ((SUMMARY_DEFERRED++)); done
    fi
done

# ============================================
# SUMMARY CARD
# ============================================
echo ""
echo "  $(_c purple)╭──────────────────────────────────────────────────────╮$(_creset)"
printf "  $(_c purple)│$(_creset)  $(_c green)\033[1m%d$(_creset) $(_c muted)updated$(_creset)   $(_c amber)\033[1m%d$(_creset) $(_c muted)deferred$(_creset)   $(_c red)\033[1m%d$(_creset) $(_c muted)unavailable$(_creset)" \
    "$SUMMARY_UPDATED" "$SUMMARY_DEFERRED" "$SUMMARY_UNAVAILABLE"
# right-pad
total_chars=$(( 9 + ${#SUMMARY_UPDATED} + 10 + ${#SUMMARY_DEFERRED} + 13 + ${#SUMMARY_UNAVAILABLE} ))
pad=$(( 50 - total_chars ))
(( pad < 0 )) && pad=0
printf "%${pad}s$(_c purple)│$(_creset)\n" ""
echo "  $(_c purple)╰──────────────────────────────────────────────────────╯$(_creset)"
echo ""

if (( SUMMARY_FAILED > 0 )); then
    printf "  %s✗ %d failed%s %s— error output shown above each ✗ step%s\n\n" "$(_c red)" "$SUMMARY_FAILED" "$(_creset)" "$(_c muted)" "$(_creset)"
fi

if (( SUMMARY_DEFERRED > 0 )) && [[ $FORCE -eq 0 ]]; then
    printf "  %sForce a full refresh: %sclaw tools --force%s\n\n" "$(_c muted)" "$(_c blue)" "$(_creset)"
fi
