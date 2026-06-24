#!/usr/bin/env bash
# ============================================
# OPEN CLAW — Gamified 80s Onboarding TUI
# ============================================
# A retro arcade-style character-creation flow that asks the user a few
# personality questions, scores their answers against the 8 workflow
# profiles (cloud / security / devops / ai / research / cortex / claude /
# local), and offers to install + activate the winning profile.
#
# Visual aesthetic: hot pink / neon cyan / synthwave purple, chunky ASCII
# banners, 80s arcade vocabulary ("INSERT COIN", "PRESS START", "CHOOSE
# YOUR FIGHTER"). Designed to be funny — it will roast the user gently
# based on their answers.
#
# Subcommands:
#   start              run the full character-creation flow (default)
#   replay             clear saved state + run again
#   show               print last saved profile choice
#
# State: $XDG_DATA_HOME/claw/onboarding.tsv  (one row per completed run)

set -e

# Bash 4+ required for `declare -A` (associative arrays, used for SCORES).
# macOS ships bash 3.2; re-exec under Homebrew/Linuxbrew bash if available.
if (( BASH_VERSINFO[0] < 4 )); then
    for _claw_newer_bash in /opt/homebrew/bin/bash /usr/local/bin/bash /home/linuxbrew/.linuxbrew/bin/bash; do
        if [[ -x "$_claw_newer_bash" ]]; then
            exec "$_claw_newer_bash" "$0" "$@"
        fi
    done
    echo "onboarding.sh needs bash >= 4 (got $BASH_VERSION). Install via 'brew install bash'." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claw"
STATE_FILE="$STATE_DIR/onboarding.tsv"

# ============================================
# CINEMATIC PRIMITIVES (palette, themes, animations)
# ============================================
# Sourced from the shared lib. Provides HAS_COLOR, the 4 themes, log helpers,
# and all _anim_* primitives. Idempotent — guarded by _CINEMATIC_LOADED.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/cinematic.sh"

# Themes, _list_themes, _apply_theme, and the default activation all come
# from cinematic.sh (sourced above). The theme registry below is retained
# inline for reference but commented out — single source of truth in the lib.
: <<'INLINE_THEME_REGISTRY_REMOVED'
THEME REGISTRY
#
# Globals every theme MUST set:
#   c_pink c_cyan c_purple c_orange c_green c_yellow c_grid c_white c_dim
#   THEME_NAME (short label shown in chrome) THEME_TAG (one-line subtitle)
#   SPLASH_VARIANT (synthwave|matrix|dosbbs|vhs — selects ASCII art)
#   BOOT_SEQ (newline-separated CRT boot lines, theme-flavoured)

# Default theme: 80s synthwave. Hot pink #ff2e88, neon cyan #00f5ff,
# synthwave purple #b537f2, sunset orange #ff6f3c, neon green #39ff14.
_theme_synthwave() {
    if $HAS_COLOR; then
        c_pink=$'\e[38;2;255;46;136m'
        c_cyan=$'\e[38;2;0;245;255m'
        c_purple=$'\e[38;2;181;55;242m'
        c_orange=$'\e[38;2;255;111;60m'
        c_green=$'\e[38;2;57;255;20m'
        c_yellow=$'\e[38;2;255;230;46m'
        c_grid=$'\e[38;2;74;74;138m'
        c_white=$'\e[38;2;253;246;227m'
        c_dim=$'\e[38;2;139;148;158m'
    else
        c_pink='' c_cyan='' c_purple='' c_orange='' c_green=''
        c_yellow='' c_grid='' c_white='' c_dim=''
    fi
    THEME_NAME="SYNTHWAVE"
    THEME_TAG="rad new wave dotfiles, c.1986"
    SPLASH_VARIANT="synthwave"
    SPLASH_SUBTITLE="CHARACTER  SELECT"
    NOISE_CHARS='!@#$%^&*░▒▓█┤┐└┴┬├─┼╔╗╚╝║═╬◢◣◤◥'
    BOOT_SEQ=$'> INITIALIZING CHARACTER CREATION MATRIX...\n> LOADING NEURAL PROFILE DATABASE..............[OK]\n> CALIBRATING SYNTHWAVE COLOR GAMUT.............[OK]\n> MOUNTING PERSONALITY VECTORS..................[OK]\n> SCANNING TERMINAL CAPABILITIES................[OK]\n> READY.'
}

# Matrix: green phosphor, digital rain energy. Bright green ramps from
# #00ff41 (foreground) through #39ff14 (accent) to #006000 (chrome).
_theme_matrix() {
    if $HAS_COLOR; then
        c_pink=$'\e[38;2;0;255;65m'
        c_cyan=$'\e[38;2;57;255;20m'
        c_purple=$'\e[38;2;0;120;0m'
        c_orange=$'\e[38;2;180;255;100m'
        c_green=$'\e[38;2;0;255;65m'
        c_yellow=$'\e[38;2;200;255;130m'
        c_grid=$'\e[38;2;0;90;0m'
        c_white=$'\e[38;2;220;255;220m'
        c_dim=$'\e[38;2;0;100;0m'
    else
        c_pink='' c_cyan='' c_purple='' c_orange='' c_green=''
        c_yellow='' c_grid='' c_white='' c_dim=''
    fi
    THEME_NAME="MATRIX"
    THEME_TAG="wake up, neo. the terminal has you."
    SPLASH_VARIANT="matrix"
    SPLASH_SUBTITLE="WAKE  UP,  NEO"
    NOISE_CHARS='01ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑ'
    BOOT_SEQ=$'> ESTABLISHING UPLINK TO CONSTRUCT.............[OK]\n> DECRYPTING ZION KEYRING......................[OK]\n> LOADING AGENT-SMITH HEURISTICS................[OK]\n> RECEIVING WHITE-RABBIT PACKET..................[OK]\n> THERE IS NO SPOON.'
}

# DOS BBS: amber CRT meets early-90s ANSI art. Saturated CGA-ish palette,
# heavy CP437 box-drawing in the splash.
_theme_dosbbs() {
    if $HAS_COLOR; then
        c_pink=$'\e[38;2;255;176;0m'
        c_cyan=$'\e[38;2;0;170;170m'
        c_purple=$'\e[38;2;170;0;170m'
        c_orange=$'\e[38;2;255;85;0m'
        c_green=$'\e[38;2;0;170;0m'
        c_yellow=$'\e[38;2;255;255;85m'
        c_grid=$'\e[38;2;85;85;85m'
        c_white=$'\e[38;2;255;255;255m'
        c_dim=$'\e[38;2;128;128;128m'
    else
        c_pink='' c_cyan='' c_purple='' c_orange='' c_green=''
        c_yellow='' c_grid='' c_white='' c_dim=''
    fi
    THEME_NAME="DOS BBS"
    THEME_TAG="2400 baud · CONNECT · welcome to the rootshell"
    SPLASH_VARIANT="dosbbs"
    SPLASH_SUBTITLE="SYSOP  LOGIN"
    NOISE_CHARS='░▒▓█│─┐└┴┬├┼╔╗╚╝║═╬◄►▲▼'
    BOOT_SEQ=$'> DIALING +1-555-ROOTSH3LL.....................[CONNECT]\n> NEGOTIATING ANSI HANDSHAKE....................[OK]\n> LOADING DOOR.SYS..............................[OK]\n> CHECKING TIME LIMIT (90 MIN/DAY)...............[OK]\n> WELCOME, SYSOP.'
}

# VHS: tracking-error magenta + icy cyan, intentional scanline grit.
_theme_vhs() {
    if $HAS_COLOR; then
        c_pink=$'\e[38;2;255;0;220m'
        c_cyan=$'\e[38;2;0;220;255m'
        c_purple=$'\e[38;2;120;0;180m'
        c_orange=$'\e[38;2;255;255;255m'
        c_green=$'\e[38;2;0;255;200m'
        c_yellow=$'\e[38;2;255;240;0m'
        c_grid=$'\e[38;2;60;30;80m'
        c_white=$'\e[38;2;240;240;220m'
        c_dim=$'\e[38;2;120;100;120m'
    else
        c_pink='' c_cyan='' c_purple='' c_orange='' c_green=''
        c_yellow='' c_grid='' c_white='' c_dim=''
    fi
    THEME_NAME="VHS"
    THEME_TAG="please rewind before returning"
    SPLASH_VARIANT="vhs"
    SPLASH_SUBTITLE="» PLAY  ◀◀ REC ●"
    NOISE_CHARS='▓▒░█▌▐▀▄≡≈※○●◐◑'
    BOOT_SEQ=$'> TRACKING.....................................[ADJUST]\n> HEAD CLEAN....................................[OK]\n> SP / LP MODE..................................[SP]\n> LOADING TAPE: \xc2\xab USER PROFILE \xc2\xbb...................[OK]\n> PLEASE STAND BY.'
}

_list_themes() {
    # label::function::short-description
    printf '%s\n' \
        "SYNTHWAVE  ─  hot pink / neon cyan / purple. classic 80s.::_theme_synthwave" \
        "MATRIX     ─  green phosphor. wake up, neo.::_theme_matrix" \
        "DOS BBS    ─  amber CRT / ANSI art. dial-up vibes.::_theme_dosbbs" \
        "VHS        ─  magenta / cyan tracking error.::_theme_vhs"
}

INLINE_THEME_REGISTRY_REMOVED

# Optional gum (pretty prompts). We don't require it — fallback uses
# stdlib read so onboarding works on a minimal install (the whole point of
# bootstrapping the dotfiles).
HAS_GUM=false
command -v gum &>/dev/null && HAS_GUM=true

# ============================================
# THEME PICKER
# ============================================
# Asks the user to pick an aesthetic BEFORE the quiz. The selected theme is
# applied immediately, so the rest of the flow inherits the palette.
_pick_theme() {
    clear
    cat <<EOF

${c_purple}  ════════════════════════════════════════════════════════${c_reset}
${c_cyan}        ░▒▓█  ${c_pink}AESTHETIC  CALIBRATION${c_cyan}  █▓▒░${c_reset}
${c_purple}  ════════════════════════════════════════════════════════${c_reset}

EOF
    _anim_type "  pick the vibe. replay later with: claw onboard replay" 0.018
    echo ""

    local -a labels=()
    local -a funcs=()
    local row label fn
    while IFS= read -r row; do
        label="${row%%::*}"
        fn="${row##*::}"
        labels+=("$label")
        funcs+=("$fn")
    done < <(_list_themes)

    local i=1
    for label in "${labels[@]}"; do
        printf "    ${c_cyan}[${c_bold}%d${c_reset}${c_cyan}]${c_reset} ${c_white}%s${c_reset}\n" "$i" "$label"
        ((i++)) || true
    done
    echo ""

    local choice=""
    if $HAS_GUM; then
        # gum fails non-interactively; tolerate so set -e doesn't kill us.
        choice="$(printf '%s\n' "${labels[@]}" | gum choose \
            --cursor.foreground="#ff2e88" \
            --selected.foreground="#00f5ff" \
            --header="  vibe >" 2>/dev/null || true)"
    fi

    local idx=0
    if [[ -n "$choice" ]]; then
        local k=0
        for label in "${labels[@]}"; do
            if [[ "$label" == "$choice" ]]; then idx=$k; break; fi
            ((k++)) || true
        done
    else
        local n=""
        while true; do
            printf "  ${c_yellow}>${c_reset} "
            IFS= read -r n
            [[ -z "$n" ]] && n=1
            if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#labels[@]} )); then
                idx=$((n-1))
                break
            fi
            printf "  ${c_orange}!${c_reset} ${c_dim}1..%d${c_reset}\n" "${#labels[@]}"
        done
    fi

    "${funcs[$idx]}"
    SELECTED_THEME="${funcs[$idx]#_theme_}"

    printf "\n  ${c_green}✓${c_reset} "
    _anim_type "theme locked: ${THEME_NAME}" 0.02
    _anim_pause 0.5
}

# ============================================
# ART
# ============================================
# Splash. The CRT divider lines use ▀▄▀ for that "scanline" feel.
# Splash dispatcher: picks the art variant for the active theme.
# Each variant is a self-contained scene printed via cat <<EOF — keeps the
# art readable as source instead of buried in printf escapes.
_splash() {
    clear
    case "${SPLASH_VARIANT:-synthwave}" in
        synthwave) _splash_synthwave ;;
        matrix)    _splash_matrix    ;;
        dosbbs)    _splash_dosbbs    ;;
        vhs)       _splash_vhs       ;;
        *)         _splash_synthwave ;;
    esac
    _anim_pause 0.4
    printf "                  ${c_dim}%s · %s${c_reset}\n\n" "${THEME_NAME:-SYNTHWAVE}" "${THEME_TAG:-rad new wave dotfiles, c.1986}"
}

# Original 80s scanline divider + OPEN CLAW logo + cyan claw face.
_splash_synthwave() {
    cat <<EOF
${c_purple}
            ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
            ▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄
${c_reset}
${c_pink}             ██████╗ ██████╗ ███████╗███╗   ██╗${c_reset}    ${c_cyan}        ${c_reset}
${c_pink}            ██╔═══██╗██╔══██╗██╔════╝████╗  ██║${c_reset}    ${c_cyan} ▄▄▄▄▄  ${c_reset}
${c_pink}            ██║   ██║██████╔╝█████╗  ██╔██╗ ██║${c_reset}    ${c_cyan} █ ╳ █  ${c_reset}
${c_pink}            ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║${c_reset}    ${c_cyan} ▀▄▄▄▀  ${c_reset}
${c_pink}            ╚██████╔╝██║     ███████╗██║ ╚████║${c_reset}    ${c_cyan}        ${c_reset}
${c_pink}             ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝${c_reset}
${c_cyan}                ▄████▄   ██▓     ▄▄▄       █     █░${c_reset}
${c_cyan}               ▒██▀ ▀█  ▓██▒    ▒████▄    ▓█░ █ ░█░${c_reset}
${c_cyan}               ▒▓█    ▄ ▒██░    ▒██  ▀█▄  ▒█░ █ ░█ ${c_reset}
${c_cyan}               ▒▓▓▄ ▄██▒▒██░    ░██▄▄▄▄██ ░█░ █ ░█ ${c_reset}
${c_cyan}               ▒ ▓███▀ ░░██████▒ ▓█   ▓██▒░░██▒██▓ ${c_reset}
${c_purple}
            ▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄
            ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
${c_reset}
              ${c_yellow}${c_blink}»»»${c_reset}  ${c_white}${c_bold}${SPLASH_SUBTITLE:-CHARACTER  SELECT}${c_reset}  ${c_yellow}${c_blink}«««${c_reset}
EOF
}

# Matrix: half-width katakana + binary bookend the OPEN CLAW logo. The rain
# rows are static (a frozen frame of the iconic effect) but feel kinetic
# next to the typewriter+glitch transitions that follow.
# Half-width katakana (U+FF61–U+FF9F) render as 1-cell in Nerd Fonts.
_splash_matrix() {
    cat <<EOF
${c_dim}
   ｸ  ﾐ  0  ﾗ  1  ﾈ  ｵ  ｱ  1  ﾆ  0  ﾇ  ｹ  ﾂ  1  ｻ  ﾜ  ﾉ  0  ﾌ  ﾇ  ﾗ  1  ｸ
${c_reset}
${c_dim}ｱ${c_reset}                                                                  ${c_dim}ﾈ${c_reset}
${c_dim}ﾗ${c_reset}     ${c_green}██████╗ ██████╗ ███████╗███╗   ██╗${c_reset}                  ${c_dim}ｶ${c_reset}
${c_dim}1${c_reset}    ${c_green}██╔═══██╗██╔══██╗██╔════╝████╗  ██║${c_reset}                  ${c_dim}ｵ${c_reset}
${c_dim}ﾐ${c_reset}    ${c_green}██║   ██║██████╔╝█████╗  ██╔██╗ ██║${c_reset}                  ${c_dim}ﾗ${c_reset}
${c_dim}0${c_reset}    ${c_green}██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║${c_reset}                  ${c_dim}ﾆ${c_reset}
${c_dim}ｸ${c_reset}    ${c_green}╚██████╔╝██║     ███████╗██║ ╚████║${c_reset}                  ${c_dim}1${c_reset}
${c_dim}ﾆ${c_reset}     ${c_green}╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝${c_reset}                  ${c_dim}ﾂ${c_reset}
${c_dim}ﾂ${c_reset}        ${c_green}▄████▄   ██▓     ▄▄▄       █     █░${c_reset}             ${c_dim}ﾑ${c_reset}
${c_dim}1${c_reset}       ${c_green}▒██▀ ▀█  ▓██▒    ▒████▄    ▓█░ █ ░█░${c_reset}             ${c_dim}ｶ${c_reset}
${c_dim}0${c_reset}       ${c_green}▒▓█    ▄ ▒██░    ▒██  ▀█▄  ▒█░ █ ░█${c_reset}              ${c_dim}ﾐ${c_reset}
${c_dim}ｾ${c_reset}       ${c_green}▒▓▓▄ ▄██▒▒██░    ░██▄▄▄▄██ ░█░ █ ░█${c_reset}              ${c_dim}0${c_reset}
${c_dim}ﾆ${c_reset}       ${c_green}▒ ▓███▀ ░░██████▒ ▓█   ▓██▒░░██▒██▓${c_reset}              ${c_dim}1${c_reset}
${c_dim}ﾂ${c_reset}                                                                  ${c_dim}ﾗ${c_reset}
${c_dim}
   1  ﾗ  ｱ  ﾐ  0  ｸ  ﾆ  ﾂ  ﾑ  0  ﾐ  ﾇ  ｹ  ﾗ  1  ｸ  ﾆ  0  ﾐ  ﾗ  ﾂ  ﾑ  1  ｵ
${c_reset}
              ${c_yellow}${c_blink}»»»${c_reset}  ${c_white}${c_bold}${SPLASH_SUBTITLE:-WAKE  UP,  NEO}${c_reset}  ${c_yellow}${c_blink}«««${c_reset}
EOF
}

# DOS BBS: heavy CP437 frame, login banner, NODE/USER/BAUD status bar.
# Magenta frame + amber OPEN logo + cyan CLAW body = early-90s ANSI vibe.
_splash_dosbbs() {
    cat <<EOF
${c_purple}  ╔═══════════════════════════════════════════════════════════════════╗${c_reset}
${c_purple}  ║${c_reset} ${c_pink}░▒▓█ OPEN CLAW BBS █▓▒░${c_reset}  ${c_cyan}►► PRESS [SPACE] FOR MAIN MENU ◄◄${c_reset}     ${c_purple}║${c_reset}
${c_purple}  ╠═══════════════════════════════════════════════════════════════════╣${c_reset}
${c_purple}  ║${c_reset}                                                                   ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}           ${c_pink}██████╗ ██████╗ ███████╗███╗   ██╗${c_reset}                   ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}          ${c_pink}██╔═══██╗██╔══██╗██╔════╝████╗  ██║${c_reset}                   ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}          ${c_pink}██║   ██║██████╔╝█████╗  ██╔██╗ ██║${c_reset}                   ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}          ${c_pink}██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║${c_reset}                   ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}          ${c_pink}╚██████╔╝██║     ███████╗██║ ╚████║${c_reset}                   ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}           ${c_pink}╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝${c_reset}                   ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}              ${c_cyan}▄████▄   ██▓     ▄▄▄       █     █░${c_reset}              ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}             ${c_cyan}▒██▀ ▀█  ▓██▒    ▒████▄    ▓█░ █ ░█░${c_reset}              ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}             ${c_cyan}▒▓█    ▄ ▒██░    ▒██  ▀█▄  ▒█░ █ ░█ ${c_reset}              ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}             ${c_cyan}▒▓▓▄ ▄██▒▒██░    ░██▄▄▄▄██ ░█░ █ ░█ ${c_reset}              ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}             ${c_cyan}▒ ▓███▀ ░░██████▒ ▓█   ▓██▒░░██▒██▓ ${c_reset}              ${c_purple}║${c_reset}
${c_purple}  ║${c_reset}                                                                   ${c_purple}║${c_reset}
${c_purple}  ╠═══════════════════════════════════════════════════════════════════╣${c_reset}
${c_purple}  ║${c_reset} ${c_yellow}NODE: 01${c_reset}   ${c_yellow}USER: SYSOP${c_reset}   ${c_yellow}BAUD: 2400${c_reset}   ${c_orange}TIME LEFT: 89 MIN${c_reset}    ${c_purple}║${c_reset}
${c_purple}  ╚═══════════════════════════════════════════════════════════════════╝${c_reset}

              ${c_yellow}${c_blink}»»»${c_reset}  ${c_white}${c_bold}${SPLASH_SUBTITLE:-SYSOP  LOGIN}${c_reset}  ${c_yellow}${c_blink}«««${c_reset}
EOF
}

# VHS: thick ████ tracking bars + per-line magenta/cyan alternation on the
# logo (suggests analog color-channel separation). Status bar shows
# transport indicators (PLAY/REC) and timecode.
_splash_vhs() {
    cat <<EOF
${c_pink}  ████████████████████████████████████████████████████████████████████${c_reset}
${c_pink}  ████${c_reset} ${c_orange}TRACKING${c_reset} ${c_pink}██████${c_reset}  ${c_cyan}▷ PLAY${c_reset}  ${c_pink}████████${c_reset}  ${c_orange}● REC${c_reset}  ${c_pink}██████${c_reset}
${c_pink}  ████████████████████████████████████████████████████████████████████${c_reset}

${c_pink}             ██████╗ ██████╗ ███████╗███╗   ██╗${c_reset}
${c_cyan}             ██╔═══██╗██╔══██╗██╔════╝████╗  ██║${c_reset}
${c_pink}             ██║   ██║██████╔╝█████╗  ██╔██╗ ██║${c_reset}
${c_cyan}             ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║${c_reset}
${c_pink}             ╚██████╔╝██║     ███████╗██║ ╚████║${c_reset}
${c_cyan}              ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝${c_reset}
${c_pink}  ████████████████████████████████████████████████████████████████████${c_reset}
${c_cyan}                ▄████▄   ██▓     ▄▄▄       █     █░${c_reset}
${c_pink}               ▒██▀ ▀█  ▓██▒    ▒████▄    ▓█░ █ ░█░${c_reset}
${c_cyan}               ▒▓█    ▄ ▒██░    ▒██  ▀█▄  ▒█░ █ ░█ ${c_reset}
${c_pink}               ▒▓▓▄ ▄██▒▒██░    ░██▄▄▄▄██ ░█░ █ ░█ ${c_reset}
${c_cyan}               ▒ ▓███▀ ░░██████▒ ▓█   ▓██▒░░██▒██▓ ${c_reset}

${c_pink}  ████████████████████████████████████████████████████████████████████${c_reset}
${c_pink}  ████${c_reset} ${c_orange}SP${c_reset}  ${c_cyan}LP${c_reset}  ${c_pink}████${c_reset}  ${c_yellow}00:00:01:24${c_reset}  ${c_pink}████${c_reset}  ${c_orange}STEREO ●${c_reset}  ${c_pink}████${c_reset}
${c_pink}  ████████████████████████████████████████████████████████████████████${c_reset}

              ${c_yellow}${c_blink}»»»${c_reset}  ${c_white}${c_bold}${SPLASH_SUBTITLE:-» PLAY ◀◀ REC ●}${c_reset}  ${c_yellow}${c_blink}«««${c_reset}
EOF
}

# Horizon between sections — now with a brief glitch on the LEVEL banner.
# Settles fast (~0.25s) so it punctuates without dragging.
_horizon() {
    printf "${c_purple}  ════════════════════════════════════════════════════════${c_reset}\n"
    # Build the inner banner as a plain string, glitch it, then redraw in
    # color. The glitch helper writes its own newline.
    if [[ -t 1 ]]; then
        printf "${c_cyan}    ░▒▓█  ${c_pink}"
        _anim_glitch "LEVEL  $1" 2
        printf "\e[1A\r${c_cyan}    ░▒▓█  ${c_pink}LEVEL  $1${c_cyan}  █▓▒░${c_reset}\n"
    else
        printf "${c_cyan}    ░▒▓█  ${c_pink}LEVEL  %s${c_cyan}  █▓▒░${c_reset}\n" "$1"
    fi
    printf "${c_purple}  ════════════════════════════════════════════════════════${c_reset}\n\n"
}

# ============================================
# PROFILE METADATA
# ============================================
# Each profile gets a class name (RPG-style), a one-liner roast, and an
# install hook (the toolchain script under scripts/install). The class
# names are deliberately tongue-in-cheek.
_profile_class() {
    case "$1" in
        # Tier 1: general
        default)    echo "PIXEL-DRIFTER" ;;
        local)      echo "GARAGE-HACKER" ;;
        # Tier 2: domain
        cloud)      echo "SKYSURFER" ;;
        devops)     echo "WRENCH-MAGE" ;;
        security)   echo "NIGHTHACKER" ;;
        cortex)     echo "GHOST-IN-THE-XSIAM" ;;
        ai)         echo "NEUROMANCER" ;;
        research)   echo "DATA-DJ" ;;
        # Tier 3: agent/IDE
        claude)     echo "PROMPT-RIDER" ;;
        # Tier 4: knowledge & ideation (NEW)
        vault)      echo "KNOWLEDGE-KEEPER" ;;
        brainstorm) echo "SPARK-CATCHER" ;;
        pmo)        echo "SCRIBE-OPERATOR" ;;
        # Tier 5: customer-facing & visual (NEW)
        deck)       echo "DECK-SMITH" ;;
        design)     echo "FRAME-SMITH" ;;
        demo)       echo "SHOW-RUNNER" ;;
        # Tier 6: hardware & ops (NEW)
        homelab)    echo "RACK-WIZARD" ;;
        blackwell)  echo "PHOSPHOR-GHOST" ;;
        tunnels)    echo "PORT-RUNNER" ;;
        *)          echo "UNKNOWN-WANDERER" ;;
    esac
}
_profile_flair() {
    case "$1" in
        cloud)      echo "boots up clusters before breakfast. owns 4 TLDs you've never heard of." ;;
        security)   echo "thinks your password is cute. has been in your router since Tuesday." ;;
        devops)     echo "speaks fluent YAML. has opinions about Kubernetes. strong opinions." ;;
        ai)         echo "prompted their way out of a parking ticket. has a 70B model on a thumb drive." ;;
        research)   echo "scraped the entire internet last weekend. now organizing it by vibe." ;;
        cortex)     echo "knows what XSOAR stands for. actually likes it." ;;
        claude)     echo "talks to AI more than humans. their git history is 90 percent agent commits." ;;
        local)      echo "compiles everything from source. owns 11 unfinished CLI tools." ;;
        default)    echo "the chill one. just wants a nice prompt and \`z\` to work." ;;
        # Tier 4 — knowledge & ideation
        vault)      echo "scraped your second brain and organized it by vibe. every note links to three others." ;;
        brainstorm) echo "captures shower thoughts at 3 AM. has a parking lot tag for ideas with no home yet." ;;
        pmo)        echo "Things 3 inbox at zero by Friday. weekly review on Sunday with espresso." ;;
        # Tier 5 — customer-facing & visual
        deck)       echo "ships customer artifacts on a 6-hour deadline. every screenshot crops itself." ;;
        design)     echo "every diagram tells the same story, just better. pixel-grid alignment is not negotiable." ;;
        demo)       echo "never accidentally leaks a secret on screen-share. big font, DND on, history scrubbed." ;;
        # Tier 6 — hardware & ops
        homelab)    echo "owns the BD790i and its 47 unread alerts. k3s · tailscale · gitea · n8n · ollama." ;;
        blackwell)  echo "FP4 enabled, 24GB VRAM, Tensor cores warm. has a 70B model running in the basement." ;;
        tunnels)    echo "every host is one port-forward away. ControlMaster sockets warm, multi-hop chains tested." ;;
    esac
}

# ============================================
# Q&A ENGINE
# ============================================
# Each question prints a numbered menu; the user types 1..N or picks via
# gum choose. Each option declares which profiles it tilts the score
# toward (space-separated; appears in the OPTS array). After the run we
# tally and pick the highest scorer.
#
# Conventions:
#   OPTS=("label::profile1 profile2 weight" ...)
#   weight is omitted → 1; if present, it adds N to the named profiles.
declare -A SCORES
for p in cloud security devops ai research cortex claude local default vault brainstorm pmo deck design demo homelab blackwell tunnels; do
    SCORES[$p]=0
done

_ask() {
    local title="$1"
    shift
    local opts=("$@")

    echo ""
    printf "  ${c_pink}${c_bold}▸ "
    _anim_type "$title" 0.018
    printf "%s" "$c_reset"
    echo ""

    local i=1
    local labels=()
    for opt in "${opts[@]}"; do
        local label="${opt%%::*}"
        labels+=("$label")
        printf "    ${c_cyan}[${c_bold}%d${c_reset}${c_cyan}]${c_reset} ${c_white}%s${c_reset}\n" "$i" "$label"
        ((i++)) || true
    done
    echo ""

    local choice=""
    if $HAS_GUM; then
        choice="$(printf '%s\n' "${labels[@]}" | gum choose \
            --cursor.foreground="#ff2e88" \
            --selected.foreground="#00f5ff" \
            --header="  pick one >" 2>/dev/null || true)"
    fi

    # Fallback / gum failure → numeric read loop.
    if [[ -z "$choice" ]]; then
        local n=""
        while true; do
            printf "  ${c_yellow}>${c_reset} "
            IFS= read -r n
            # Default to 1 if they just hit enter — friendly behaviour.
            [[ -z "$n" ]] && n=1
            if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#opts[@]} )); then
                choice="${labels[$((n-1))]}"
                break
            fi
            printf "  ${c_orange}!${c_reset} ${c_dim}come on, just 1..%d${c_reset}\n" "${#opts[@]}"
        done
    fi

    # Find the chosen option and apply its score delta.
    local picked=""
    for opt in "${opts[@]}"; do
        local label="${opt%%::*}"
        if [[ "$label" == "$choice" ]]; then
            picked="$opt"
            break
        fi
    done
    if [[ -z "$picked" ]]; then
        printf "  ${c_orange}(skipped — no match)${c_reset}\n"
        return
    fi

    local payload="${picked#*::}"
    # Parse: "prof1 prof2 [N]" — last field is weight iff it's numeric.
    local fields=($payload)
    local weight=1
    local last="${fields[${#fields[@]}-1]}"
    if [[ "$last" =~ ^[0-9]+$ ]]; then
        weight=$last
        unset 'fields[${#fields[@]}-1]'
    fi
    for prof in "${fields[@]}"; do
        SCORES[$prof]=$(( ${SCORES[$prof]:-0} + weight ))
    done

    printf "  ${c_green}✓${c_reset} ${c_dim}logged: %s${c_reset}\n" "$choice"
}

# ============================================
# THE QUIZ
# ============================================
# Six questions: enough signal to pick a profile, few enough to stay fun.
# Each option tilts the score toward 1–3 profiles. I keep one "joke" option
# per question that scores `default` — for users who want the basic shell.
_run_quiz() {
    _horizon 1

    _ask "WHEN does your best code happen?" \
        "3 AM — neon hours::security ai 2" \
        "9-to-5, fueled by enterprise coffee::devops cloud" \
        "weekend marathon, no sleep::ai research" \
        "whenever the linter stops yelling::default"

    _horizon 2

    _ask "Your terminal is mostly running…" \
        "kubectl + terraform plan::cloud devops 2" \
        "nmap + burp + a Wireshark capture::security 2" \
        "ollama serve + a python repl::ai research" \
        "XSOAR playbook + a frantic incident chan::cortex 2" \
        "claude code in --dangerously-skip-permissions::claude 2" \
        "vim + tmux + makefile + tears::local default"

    _horizon 3

    _ask "Pick your weapon" \
        "a freshly-rotated SSH key::security devops" \
        "a perfect IAM policy::cloud" \
        "a fine-tuned 13B you trained in the garage::ai" \
        "a regex that took 3 hours but works once::research" \
        "a Helm chart you wrote yourself::devops cloud" \
        "an alias. just a really good alias::default local"

    _horizon 4

    _ask "Production just exploded. You…" \
        "open the runbook you actually wrote::devops cortex 2" \
        "tail logs while quietly cursing::devops default" \
        "ask Claude what happened::claude ai" \
        "are already three pivots deep in someone else's network::security" \
        "git blame, then pretend it wasn't you::default" \
        "scrape postmortems from every similar outage::research"

    _horizon 5

    _ask "Your dream homelab is…" \
        "a rack of mini-PCs running k3s::cloud devops" \
        "an air-gapped lab full of CTF VMs::security 2" \
        "a single big GPU and a 70B model::ai 2" \
        "a Cortex XSIAM tenant + 4 data lakes::cortex 2" \
        "a notebook server humming with web scrapers::research" \
        "one quiet thinkpad and a tiling WM::local default"

    _horizon 6

    _ask "Which prompt does your soul live in?" \
        "the silent one — info on demand::default local" \
        "k8s context + AWS profile + git branch::cloud devops 2" \
        "a tiny skull emoji::security 2" \
        "model name + token count::ai claude 2" \
        "a paper count + arxiv id::research" \
        "the one your XSIAM tenant gave you::cortex"
}

# ============================================
# RESULT
# ============================================
_winner() {
    local best="default"
    local best_score=-1
    # zsh-vs-bash safe iteration: list keys explicitly.
    for p in cloud security devops ai research cortex claude local default vault brainstorm pmo deck design demo homelab blackwell tunnels; do
        local s=${SCORES[$p]:-0}
        if (( s > best_score )); then
            best_score=$s
            best="$p"
        fi
    done
    echo "$best"
}

_show_scoreboard() {
    echo ""
    printf "  ${c_pink}${c_bold}═══ "
    _anim_type "SCOREBOARD" 0.03
    printf "\e[1A\e[2C${c_pink}${c_bold}═══ SCOREBOARD ═══${c_reset}\n\n"
    _anim_pause 0.3
    # Sort desc by score, then animate each bar in turn. Each row's fill is
    # animated by _anim_score_bar — so the audience sees the leader pull away.
    {
        for p in cloud security devops ai research cortex claude local default vault brainstorm pmo deck design demo homelab blackwell tunnels; do
            printf "%s\t%d\n" "$p" "${SCORES[$p]:-0}"
        done
    } | sort -k2 -nr | while IFS=$'\t' read -r p s; do
        _anim_score_bar "$p" "$s"
        _anim_pause 0.08
    done
    echo ""
    _anim_pause 0.5
}

# Verdict: 2-3 lines of long-form roast, typed out cinematically after the
# box reveal. _profile_flair is the snappy one-liner inside the box;
# _verdict is the dramatic monologue underneath.
#
# >>>  HENRY: tune these. Each class gets 2-3 lines. Keep lines under 60
#      chars. Speak in second person. Roast > praise.
_verdict() {
    case "$1" in
        cloud)
            printf '%s\n' \
                "you were never going to be happy on a single host." \
                "the cluster is calling. it has 47 unread alerts." \
                "answer them."
            ;;
        security)
            printf '%s\n' \
                "the network speaks. you have been listening for years." \
                "tonight you patch. tomorrow you pivot." \
                "just don't get caught."
            ;;
        devops)
            printf '%s\n' \
                "the pipeline is your temple. the runbook your scripture." \
                "you do not panic during outages." \
                "the outages panic about you."
            ;;
        ai)
            printf '%s\n' \
                "you don't write code anymore. you describe it." \
                "half your twitter followers are bots you trained." \
                "they have opinions about your prompting."
            ;;
        research)
            printf '%s\n' \
                "the dataset is yours. the question came later." \
                "someday you'll publish a paper about all of this." \
                "today, you'll scrape one more table."
            ;;
        cortex)
            printf '%s\n' \
                "the SOC sleeps. the playbooks do not." \
                "you've written automations the customer hasn't asked for." \
                "they will. soon."
            ;;
        claude)
            printf '%s\n' \
                "you and the model? unstoppable." \
                "you, alone? still figuring it out." \
                "remember which one of you is reviewing the code."
            ;;
        local)
            printf '%s\n' \
                "the cloud is fine. for other people." \
                "you have one good thinkpad and a tiling WM." \
                "that is, somehow, enough."
            ;;
        default|*)
            printf '%s\n' \
                "not every hero needs a class." \
                "some heroes just need a working shell and zoxide." \
                "respect. profile activated. go do whatever you do."
            ;;
    esac
}

_announce() {
    local profile="$1"
    local class flair
    class="$(_profile_class "$profile")"
    flair="$(_profile_flair "$profile")"

    # Beat 1: drumroll into the headline.
    echo ""
    _anim_drumroll
    _anim_pause 0.25

    # Beat 2: box draws line-by-line. Each line costs a small beat. Pre-
    # rendering into an array lets us iterate uniformly with one delay.
    local -a box_lines=()
    box_lines+=("${c_purple}  ┌────────────────────────────────────────────────────────┐${c_reset}")
    box_lines+=("${c_purple}  │${c_reset}                                                        ${c_purple}│${c_reset}")
    box_lines+=("$(printf "${c_purple}  │${c_reset}   ${c_yellow}${c_bold}>>>  YOU ARE THE  %-31s${c_reset}${c_purple}│${c_reset}" "$class  <<<")")
    box_lines+=("${c_purple}  │${c_reset}                                                        ${c_purple}│${c_reset}")
    box_lines+=("$(printf "${c_purple}  │${c_reset}   ${c_cyan}class:${c_reset}    ${c_white}%-44s${c_reset}${c_purple}│${c_reset}" "$class")")
    box_lines+=("$(printf "${c_purple}  │${c_reset}   ${c_cyan}profile:${c_reset}  ${c_white}%-44s${c_reset}${c_purple}│${c_reset}" "$profile")")
    box_lines+=("$(printf "${c_purple}  │${c_reset}   ${c_cyan}theme:${c_reset}    ${c_white}%-44s${c_reset}${c_purple}│${c_reset}" "${THEME_NAME:-SYNTHWAVE}")")
    box_lines+=("${c_purple}  │${c_reset}                                                        ${c_purple}│${c_reset}")
    local fl
    while IFS= read -r fl; do
        box_lines+=("$(printf "${c_purple}  │${c_reset}   ${c_dim}%-52s${c_reset}${c_purple}│${c_reset}" "$fl")")
    done < <(printf '%s\n' "$flair" | fold -s -w 52)
    box_lines+=("${c_purple}  │${c_reset}                                                        ${c_purple}│${c_reset}")
    box_lines+=("${c_purple}  └────────────────────────────────────────────────────────┘${c_reset}")
    local bl
    for bl in "${box_lines[@]}"; do
        printf '%s\n' "$bl"
        _anim_pause 0.06
    done

    # Beat 3: "CALCULATING DESTINY" pulse, then VERDICT typewriter.
    echo ""
    _anim_pause 0.5
    printf "  ${c_grid}> CALCULATING DESTINY${c_reset}"
    local dot
    for dot in 1 2 3 4 5 6 7 8 9 10; do
        printf "${c_grid}.${c_reset}"
        _anim_pause 0.08
    done
    printf "  ${c_green}[DONE]${c_reset}\n"
    _anim_pause 0.4
    printf "  ${c_pink}${c_bold}> VERDICT:${c_reset}\n\n"
    _anim_pause 0.3
    local vline
    while IFS= read -r vline; do
        printf "  ${c_white}"
        _anim_type "  $vline" 0.028
        printf "%s" "$c_reset"
        _anim_pause 0.18
    done < <(_verdict "$profile")
    echo ""
    _anim_pause 0.5
}

# ============================================
# INSTALL HOOK
# ============================================
# Maps a profile to its toolchain installer. Some profiles have one, some
# don't (default/local/claude have no separate toolchain). For those we
# just activate the profile.
_install_for() {
    local profile="$1"
    local script="$REPO_ROOT/scripts/install/${profile}-toolchain.sh"
    if [[ -f "$script" ]]; then
        printf "  ${c_cyan}▸${c_reset} running ${c_white}%s${c_reset}\n" "$script"
        bash "$script" || printf "  ${c_orange}!${c_reset} toolchain finished with errors — check log\n"
    else
        printf "  ${c_dim}no toolchain script for '%s' — profile-only setup${c_reset}\n" "$profile"
    fi
}

_persist_state() {
    local profile="$1"
    mkdir -p "$STATE_DIR"
    # ISO timestamp · profile · OS · user · theme
    # The theme column is the 5th; older readers parsing 4 cols continue to work.
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$profile" \
        "$(uname -s)" \
        "${USER:-unknown}" \
        "${SELECTED_THEME:-synthwave}" \
        >> "$STATE_FILE"
}

# ============================================
# CONFIRM + INSTALL
# ============================================
_offer_install() {
    local profile="$1"
    echo ""
    printf "  ${c_pink}${c_bold}INSERT COIN TO CONTINUE${c_reset}\n"
    printf "  ${c_dim}I can install the %s toolchain and activate the profile now.${c_reset}\n" "$profile"
    printf "  ${c_dim}(or skip — you can always run \`claw load %s\` later)${c_reset}\n\n" "$profile"

    local answer=""
    if $HAS_GUM; then
        answer="$(gum choose --header="  go time?" \
            --cursor.foreground="#ff2e88" \
            "[Y] yes — install + activate" \
            "[N] no — just activate the profile" \
            "[S] skip — i'll do it myself" 2>/dev/null || true)"
        # Normalise to first letter.
        answer="${answer:1:1}"
        answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    else
        printf "  ${c_yellow}>${c_reset} [Y]es install · [N]o just activate · [S]kip: "
        IFS= read -r answer
        answer="$(printf '%s' "${answer:0:1}" | tr '[:upper:]' '[:lower:]')"
        [[ -z "$answer" ]] && answer="y"
    fi

    case "$answer" in
        y)
            printf "\n  ${c_green}${c_bold}>>> INSTALLING %s TOOLCHAIN <<<${c_reset}\n\n" "$profile"
            _install_for "$profile"
            ;;
        n)
            printf "\n  ${c_cyan}${c_bold}>>> ACTIVATING PROFILE <<<${c_reset}\n\n"
            ;;
        *)
            printf "\n  ${c_dim}skipped install. saved your class anyway.${c_reset}\n"
            _persist_state "$profile"
            return 0
            ;;
    esac

    _persist_state "$profile"

    printf "\n  ${c_purple}${c_bold}GAME COMPLETE${c_reset}  ${c_dim}— to activate in your CURRENT shell, run:${c_reset}\n"
    printf "    ${c_white}export CLAW_ACTIVE_PROFILE=%s && source \$DOTFILES_DIR/shell/profiles/%s.zsh${c_reset}\n" \
        "$profile" "$profile"
    printf "  ${c_dim}or open a new shell and run:${c_reset}\n"
    printf "    ${c_white}claw load %s${c_reset}\n\n" "$profile"
}

# ============================================
# SUBCOMMANDS
# ============================================
cmd_start() {
    # Beat 0: theme picker BEFORE splash, so the splash inherits the palette.
    _pick_theme

    _splash
    # Beat-the-CRT moment — wait for ENTER so the user reads the splash.
    printf "        ${c_yellow}${c_blink}»  PRESS  ENTER  TO  START  «${c_reset}"
    IFS= read -r _ || true
    clear

    # Cinematic boot: CRT-style scrolling log, then a brief mission brief.
    _anim_boot
    echo ""
    _anim_type "  ${c_cyan}character creation: ${THEME_NAME:-SYNTHWAVE} edition${c_reset}" 0.02
    _anim_type "  ${c_dim}~90 seconds. answer honestly — or don't, it's a game.${c_reset}" 0.014
    _anim_pause 0.6

    _run_quiz

    _show_scoreboard
    local winner
    winner="$(_winner)"
    _announce "$winner"
    _offer_install "$winner"
}

cmd_replay() {
    rm -f "$STATE_FILE"
    cmd_start
}

cmd_show() {
    if [[ ! -s "$STATE_FILE" ]]; then
        printf "  ${c_dim}no onboarding runs yet. try: claw onboard${c_reset}\n"
        return 0
    fi
    printf "\n  ${c_purple}${c_bold}past character runs${c_reset}\n"
    printf "  ${c_dim}─────────────────────────${c_reset}\n"
    # 5th column (theme) may be missing on legacy rows — awk just prints "".
    awk -F'\t' '{
        theme = ($5 == "" ? "synthwave" : $5)
        printf "    %s  %-10s  %-12s  (%s)\n", $1, $2, theme, $3
    }' "$STATE_FILE"
    echo ""
}

cmd_help() {
    cat <<EOF

  ${c_pink}${c_bold}claw onboard${c_reset} — ${c_dim}80s arcade character creation, picks your profile${c_reset}

  ${c_white}claw onboard${c_reset}            ${c_dim}run the character-creation flow${c_reset}
  ${c_white}claw onboard replay${c_reset}     ${c_dim}wipe saved state and run again${c_reset}
  ${c_white}claw onboard show${c_reset}       ${c_dim}list past runs + profiles chosen${c_reset}

  ${c_dim}State: $STATE_FILE${c_reset}
EOF
}

case "${1:-start}" in
    start|run|play|"")  cmd_start ;;
    replay|reset)       cmd_replay ;;
    show|list|history)  cmd_show ;;
    help|-h|--help)     cmd_help ;;
    *)
        printf "  ${c_orange}?${c_reset} unknown subcommand: %s\n" "$1"
        cmd_help
        exit 1
        ;;
esac
