#!/usr/bin/env bash
# scripts/utils/tui-style.sh
# Shared TUI helpers for Open Claw scripts (system-update.sh, tool-updater.sh,
# and any other terminal UX in this dotfiles repo).
#
# Source it from a bash script:
#   source "$(dirname "${BASH_SOURCE[0]}")/tui-style.sh"
#
# Provides:
#   - GitHub Dark true-color exports (c_reset c_cyan c_green c_purple c_orange
#     c_red c_dim c_white c_bold c_yellow)
#   - HAS_GUM bool + tui_has_gum
#   - tui_section "Title"          → purple bold heading + dim divider
#   - tui_run_step "title" "cmd"   → gum spin if available, else styled echo+run
#   - tui_skip "name"              → dim "○ name — not installed"
#   - tui_header "title" "subtitle" → purple rounded box header
#   - tui_footer "✓ message"       → green check + timestamp
#   - tui_pause                    → "press any key" if INTERACTIVE=1

# ============================================
# THEME — GitHub macOS Dark (true-color)
# ============================================
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;88;166;255m'
c_green=$'\e[38;2;63;185;80m'
c_purple=$'\e[38;2;188;140;255m'
c_orange=$'\e[38;2;210;153;34m'
c_yellow=$'\e[38;2;210;153;34m'   # alias for orange
c_red=$'\e[38;2;255;123;114m'
c_dim=$'\e[38;2;139;148;158m'
c_white=$'\e[38;2;201;209;217m'
c_bold=$'\e[1m'

# ============================================
# GUM DETECTION
# ============================================
HAS_GUM=false
tui_has_gum() { $HAS_GUM; }
command -v gum &>/dev/null && HAS_GUM=true

# ============================================
# HEADERS / FOOTERS / SECTIONS
# ============================================

# tui_header "TITLE" "subtitle"
tui_header() {
    local title="$1"
    local subtitle="${2:-}"
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
# Renders a spinner if gum is available, otherwise styled inline echo+run.
tui_run_step() {
    local title="$1"
    shift
    if $HAS_GUM; then
        gum spin --spinner dot --spinner.foreground="#58a6ff" --title "  $title" -- bash -c "$*" 2>/dev/null
    else
        printf "  ${c_cyan}◌${c_reset} ${c_white}%s${c_reset}" "$title"
        if eval "$*" &>/dev/null; then
            printf "\r  ${c_green}●${c_reset} ${c_white}%s${c_reset}\n" "$title"
        else
            printf "\r  ${c_red}✗${c_reset} ${c_white}%s${c_reset} ${c_dim}(failed)${c_reset}\n" "$title"
        fi
    fi
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
