#!/usr/bin/env bash
# scripts/utils/tui-style.sh
# Shared TUI helpers for Open Claw scripts (system-update.sh, tool-updater.sh,
# and any other terminal UX in this dotfiles repo).
#
# Source it from a bash script:
#   source "$(dirname "${BASH_SOURCE[0]}")/tui-style.sh"
#
# Provides:
#   - true-color exports derived from the active claw theme (c_reset c_bold
#     c_blue c_green c_purple c_amber c_red c_muted c_fg + legacy aliases
#     c_cyan=blue c_orange/c_yellow=amber c_dim=muted c_white=fg)
#   - HAS_GUM bool + tui_has_gum
#   - tui_section "Title"          → purple bold heading + dim divider
#   - tui_run_step "title" "cmd"   → gum spin if available, else styled echo+run
#   - tui_skip "name"              → dim "○ name — not installed"
#   - tui_header "title" "subtitle" → purple rounded box header (drawn by
#     claw-dashboard.py --card when python3 is available; printf fallback else)
#   - tui_footer "✓ message"       → green check + timestamp
#   - tui_pause                    → "press any key" if INTERACTIVE=1

# ============================================
# THEME — derived from the ONE theme engine (F-13)
# ============================================
# theme.sh exports CLAW_RGB_* for the active palette (CLAW_THEME env → persisted
# `claw theme set` → refined-dark). Source it only if the shell has not already
# (CLAW_C_BG is its footprint); every triplet below falls back to refined-dark
# so a checkout without theme.sh still renders. Legacy names are misnamed hues
# (c_cyan is BLUE, c_orange/c_yellow are AMBER, c_dim is MUTED, c_white is FG)
# and stay so no call site changes; the twins carry the palette-key names.
# theme.sh IS the generator now: `claw_theme_emit tui` renders exactly these
# names from the active palette. The literal block survives only as the
# fallback for a shell that inherited CLAW_RGB_* without the function (or a
# checkout with no theme.sh at all).
# ── begin palette block ──
_ts_dots="${DOTFILES_DIR:-$HOME/.dotfiles}"
[ -n "${CLAW_C_BG:-}" ] || { [ -r "$_ts_dots/scripts/utils/theme.sh" ] && . "$_ts_dots/scripts/utils/theme.sh" 2>/dev/null; }
if command -v claw_theme_emit >/dev/null 2>&1; then
    eval "$(claw_theme_emit tui)"
else
    c_reset=$'\e[0m'
    c_bold=$'\e[1m'
    c_blue=$'\e[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"$'m'
    c_green=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    c_purple=$'\e[38;2;'"${CLAW_RGB_PURPLE:-188;140;255}"$'m'
    c_amber=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    c_red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    c_muted=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    c_fg=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
    c_cyan="$c_blue"; c_orange="$c_amber"; c_yellow="$c_amber"; c_dim="$c_muted"; c_white="$c_fg"
fi
unset _ts_dots
# ── end palette block ──

# ============================================
# GUM DETECTION
# ============================================
HAS_GUM=false
tui_has_gum() { $HAS_GUM; }
command -v gum &>/dev/null && HAS_GUM=true

# Streaming step runner lives in claw-progress.sh (single render path). Sourcing
# it here routes tui_run_step through claw_step, so every tui-style consumer
# streams process output instead of hiding it. Guarded: absence is non-fatal.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/claw-progress.sh" 2>/dev/null || true

# ============================================
# HEADERS / FOOTERS / SECTIONS
# ============================================

# tui_header "TITLE" "subtitle"
# ONE box (audit T2-02): claw-dashboard.py's frame()/vis()/_clip() is the only
# width-exact, ANSI-safe, NO_COLOR-aware box in the repo, and `--card` exposes
# it. The printf box below survives as the fallback for a host with no python3
# (or a checkout without the renderer) — it is the ragged one, so it goes last.
_tui_card() {   # $1 = title, $2 = subtitle (may be empty) → rc 0 when rendered
    local _d="${DOTFILES_DIR:-$HOME/.dotfiles}"
    local _dash="$_d/scripts/utils/claw-dashboard.py"
    command -v python3 >/dev/null 2>&1 || return 1
    [ -r "$_dash" ] || return 1
    printf '%s' "${2:-}" | CLAW_FORCE_COLOR=1 DOTFILES_DIR="$_d" \
        python3 "$_dash" --card "$1" --border purple --title-tone blue
}

tui_header() {
    local title="$1"
    local subtitle="${2:-}"
    _tui_card "$title" "$subtitle" && return 0
    echo ""
    echo "  ${c_purple}╭──────────────────────────────────────────────────────╮${c_reset}"
    printf "  ${c_purple}│${c_reset}  ${c_cyan}${c_bold}%s${c_reset}" "$title"
    # right-pad to box width (54 chars between bars). 4 chars = "  " + bar+" "
    local pad=$(( 50 - ${#title} ))
    (( pad < 0 )) && pad=0
    printf "%${pad}s${c_purple}│${c_reset}\n" ""
    if [[ -n "$subtitle" ]]; then
        printf "  ${c_purple}│${c_reset}  ${c_dim}%s${c_reset}" "$subtitle"
        pad=$(( 50 - ${#subtitle} ))
        (( pad < 0 )) && pad=0
        printf "%${pad}s${c_purple}│${c_reset}\n" ""
    fi
    echo "  ${c_purple}╰──────────────────────────────────────────────────────╯${c_reset}"
}

# tui_section "Title"
tui_section() {
    echo ""
    echo "  ${c_purple}${c_bold}$1${c_reset}"
    echo "  ${c_dim}$(printf '%.0s─' {1..44})${c_reset}"
}

# tui_footer "✓ message"
tui_footer() {
    echo ""
    echo "  ${c_green}${c_bold}$1${c_reset}  ${c_dim}$(date '+%H:%M:%S')${c_reset}"
    echo ""
}

# ============================================
# PROGRESS STEPS
# ============================================

# tui_run_step "title" "command…"
# Delegates to claw_step (streaming). The command stays a single eval string for
# backward-compat with existing callers; we run it via `bash -c` (matching the
# old gum path's `bash -c "$*"` semantics). No more gum spin, no more blackout.
tui_run_step() {
    local title="$1"; shift
    if command -v claw_step &>/dev/null; then
        claw_step "$title" -- bash -c "$*"
        return $?
    fi
    # Fallback if claw-progress.sh was unavailable at source time: run visibly.
    printf "  ${c_cyan}◌${c_reset} ${c_white}%s${c_reset}\n" "$title"
    bash -c "$*" </dev/null
}

# tui_skip "name"
tui_skip() {
    printf "  ${c_dim}○ %s — not installed${c_reset}\n" "$1"
}

# ============================================
# INTERACTIVE PAUSE
# ============================================
# Caller should set INTERACTIVE=1 (default) or INTERACTIVE=0 (--non-interactive)
# before sourcing.
tui_pause() {
    [[ "${INTERACTIVE:-1}" -eq 1 ]] || return 0
    printf "  ${c_dim}Press any key to continue...${c_reset}"
    if [[ -n "$ZSH_VERSION" ]]; then
        read -k 1
    else
        read -n 1 -s -r
    fi
    echo ""
}
