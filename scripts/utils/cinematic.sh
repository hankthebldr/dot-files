#!/usr/bin/env bash
################################################################################
# scripts/utils/cinematic.sh
#
# Shared cinematic engine for all of Open Claw's themed output:
#   - The onboarding flow (scripts/utils/onboarding.sh)
#   - The toolchain installers (scripts/install/lib/toolchain-runner.sh)
#   - The claw load <profile> activation ceremony (planned)
#   - claw doctor themed sections (planned)
#
# Provides:
#   - Capability detection (HAS_COLOR)
#   - Theme registry: _theme_synthwave / _theme_matrix / _theme_dosbbs / _theme_vhs
#   - Palette globals (c_pink, c_cyan, c_purple, etc.)
#   - Log helpers (log_info / log_success / log_warning / log_error / log_skip)
#   - Animation primitives (_anim_type / _anim_pause / _anim_glitch /
#     _anim_boot / _anim_drumroll / _anim_score_bar)
#   - Banner + section templates (_banner, _section)
#
# All animations are tty-gated — non-interactive runs (CI, pipes) get plain
# text fast-path so the lib is safe to source anywhere.
################################################################################

# Idempotent sourcing guard — multiple consumers may source this in one shell.
if [[ -n "${_CINEMATIC_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_CINEMATIC_LOADED=1

# ── CAPABILITY DETECTION ───────────────────────────────────────────────────
if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
    HAS_COLOR=true
    c_reset=${c_reset:-$'\e[0m'}
    c_bold=${c_bold:-$'\e[1m'}
    c_blink=${c_blink:-$'\e[5m'}
else
    HAS_COLOR=false
    c_reset='' c_bold='' c_blink=''
fi

# ── THEME REGISTRY ─────────────────────────────────────────────────────────
# Each theme is a function that (re)assigns the palette globals + sets the
# THEME_NAME / THEME_TAG / SPLASH_VARIANT / NOISE_CHARS / BOOT_SEQ exports.
# Metadata always loads; only ANSI codes are gated on HAS_COLOR.

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
        c_red=$'\e[38;2;255;100;100m'
    else
        c_pink='' c_cyan='' c_purple='' c_orange='' c_green=''
        c_yellow='' c_grid='' c_white='' c_dim='' c_red=''
    fi
    THEME_NAME="SYNTHWAVE"
    THEME_TAG="rad new wave dotfiles, c.1986"
    SPLASH_VARIANT="synthwave"
    SPLASH_SUBTITLE="CHARACTER  SELECT"
    NOISE_CHARS='!@#$%^&*░▒▓█┤┐└┴┬├─┼╔╗╚╝║═╬◢◣◤◥'
    BOOT_SEQ=$'> INITIALIZING CHARACTER CREATION MATRIX...\n> LOADING NEURAL PROFILE DATABASE..............[OK]\n> CALIBRATING SYNTHWAVE COLOR GAMUT.............[OK]\n> MOUNTING PERSONALITY VECTORS..................[OK]\n> SCANNING TERMINAL CAPABILITIES................[OK]\n> READY.'
}

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
        c_red=$'\e[38;2;255;100;100m'
    else
        c_pink='' c_cyan='' c_purple='' c_orange='' c_green=''
        c_yellow='' c_grid='' c_white='' c_dim='' c_red=''
    fi
    THEME_NAME="MATRIX"
    THEME_TAG="wake up, neo. the terminal has you."
    SPLASH_VARIANT="matrix"
    SPLASH_SUBTITLE="WAKE  UP,  NEO"
    NOISE_CHARS='01ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑ'
    BOOT_SEQ=$'> ESTABLISHING UPLINK TO CONSTRUCT.............[OK]\n> DECRYPTING ZION KEYRING......................[OK]\n> LOADING AGENT-SMITH HEURISTICS................[OK]\n> RECEIVING WHITE-RABBIT PACKET..................[OK]\n> THERE IS NO SPOON.'
}

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
        c_red=$'\e[38;2;255;100;100m'
    else
        c_pink='' c_cyan='' c_purple='' c_orange='' c_green=''
        c_yellow='' c_grid='' c_white='' c_dim='' c_red=''
    fi
    THEME_NAME="DOS BBS"
    THEME_TAG="2400 baud · CONNECT · welcome to the rootshell"
    SPLASH_VARIANT="dosbbs"
    SPLASH_SUBTITLE="SYSOP  LOGIN"
    NOISE_CHARS='░▒▓█│─┐└┴┬├┼╔╗╚╝║═╬◄►▲▼'
    BOOT_SEQ=$'> DIALING +1-555-ROOTSH3LL.....................[CONNECT]\n> NEGOTIATING ANSI HANDSHAKE....................[OK]\n> LOADING DOOR.SYS..............................[OK]\n> CHECKING TIME LIMIT (90 MIN/DAY)...............[OK]\n> WELCOME, SYSOP.'
}

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
        c_red=$'\e[38;2;255;100;100m'
    else
        c_pink='' c_cyan='' c_purple='' c_orange='' c_green=''
        c_yellow='' c_grid='' c_white='' c_dim='' c_red=''
    fi
    THEME_NAME="VHS"
    THEME_TAG="please rewind before returning"
    SPLASH_VARIANT="vhs"
    SPLASH_SUBTITLE="» PLAY  ◀◀ REC ●"
    NOISE_CHARS='▓▒░█▌▐▀▄≡≈※○●◐◑'
    BOOT_SEQ=$'> TRACKING.....................................[ADJUST]\n> HEAD CLEAN....................................[OK]\n> SP / LP MODE..................................[SP]\n> LOADING TAPE: « USER PROFILE »...................[OK]\n> PLEASE STAND BY.'
}

# List all available themes — used by theme pickers and `claw doctor`.
_list_themes() {
    printf '%s\n' \
        "SYNTHWAVE  ─  hot pink / neon cyan / purple. classic 80s.::_theme_synthwave" \
        "MATRIX     ─  green phosphor. wake up, neo.::_theme_matrix" \
        "DOS BBS    ─  amber CRT / ANSI art. dial-up vibes.::_theme_dosbbs" \
        "VHS        ─  magenta / cyan tracking error.::_theme_vhs"
}

# Apply theme by name. Used by `claw load <profile>` ceremony to honor
# PROFILE_THEME_DEFAULT or CLAW_THEME override.
_apply_theme() {
    case "$1" in
        synthwave) _theme_synthwave ;;
        matrix)    _theme_matrix    ;;
        dosbbs)    _theme_dosbbs    ;;
        vhs)       _theme_vhs       ;;
        *)         _theme_synthwave ;;
    esac
}

# Activate synthwave by default so any pre-quiz output is themed.
_theme_synthwave

# ── LOG HELPERS ────────────────────────────────────────────────────────────
log_info()    { printf "  ${c_cyan}▸${c_reset} %s\n" "$1"; }
log_success() { printf "  ${c_green}✓${c_reset} %s\n" "$1"; }
log_warning() { printf "  ${c_yellow}!${c_reset} %s\n" "$1"; }
log_error()   { printf "  ${c_red}✗${c_reset} %s\n" "$1" >&2; }
log_skip()    { printf "  ${c_dim}·${c_reset} ${c_dim}%s${c_reset}\n" "$1"; }

# ── ANIMATION PRIMITIVES ───────────────────────────────────────────────────
# All animation helpers are tty-gated. Non-interactive callers get a fast
# plain-text path so this lib is safe to source in CI / pipes / scripts.
# Animation is also suppressed if CLAW_NO_ANIM=1 is set (operator opt-out).

_anim_should_skip() {
    [[ ! -t 1 ]] || [[ "${CLAW_NO_ANIM:-}" == "1" ]]
}

_anim_pause() {
    _anim_should_skip && return 0
    sleep "$1"
}

# Typewriter: print $1 char-by-char with $2 delay (default 25ms).
_anim_type() {
    local text="$1"
    local delay="${2:-0.025}"
    if _anim_should_skip; then printf '%s\n' "$text"; return; fi
    local i=0 len=${#text}
    while (( i < len )); do
        printf '%s' "${text:$i:1}"
        sleep "$delay"
        ((i++)) || true
    done
    printf '\n'
}

# Glitch: scramble random chars of $1 for a few frames, then settle on the
# real string. Uses the active theme's NOISE_CHARS alphabet.
_anim_glitch() {
    local text="$1"
    local frames="${2:-3}"
    if _anim_should_skip; then printf '%s\n' "$text"; return; fi
    local noise="${NOISE_CHARS:-!@#\$%^&*░▒▓█┤┐└┴┬├─┼╔╗╚╝║═╬◢◣◤◥}"
    local nlen=${#noise} tlen=${#text}
    local f=0 i=0
    while (( f < frames )); do
        printf '\r'
        i=0
        while (( i < tlen )); do
            if (( RANDOM % 3 == 0 )); then
                printf '%s' "${noise:$((RANDOM % nlen)):1}"
            else
                printf '%s' "${text:$i:1}"
            fi
            ((i++)) || true
        done
        sleep 0.08
        ((f++)) || true
    done
    printf '\r%s\n' "$text"
}

# CRT boot sequence: print $BOOT_SEQ line-by-line with a beat between.
_anim_boot() {
    _anim_should_skip && return 0
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        printf "  ${c_grid}%s${c_reset}\n" "$line"
        sleep 0.28
    done <<< "$BOOT_SEQ"
    sleep 0.65
}

# Drumroll: 5-frame ramp from a single ">" to "${c_bold}>>>". Use right
# before a dramatic reveal.
_anim_drumroll() {
    _anim_should_skip && return 0
    local frames=(
        "  ${c_yellow}>"
        "  ${c_yellow}>>"
        "  ${c_yellow}>>>"
        "  ${c_pink}>>>"
        "  ${c_pink}${c_bold}>>>"
    )
    local f
    for f in "${frames[@]}"; do
        printf '\r%s%s' "$f" "$c_reset"
        sleep 0.2
    done
    printf '\n'
}

# Animated score bar: $1=label, $2=score. Fills one █ at a time.
_anim_score_bar() {
    local label="$1" score="$2"
    printf "    ${c_cyan}%-10s${c_reset}  ${c_pink}" "$label"
    local fill=$score
    (( fill > 10 )) && fill=10
    local i=0
    if _anim_should_skip; then
        while (( i < fill )); do printf '█'; ((i++)) || true; done
    else
        while (( i < fill )); do
            printf '█'
            sleep 0.05
            ((i++)) || true
        done
    fi
    local pad=$(( 10 - fill ))
    local j=0
    printf '%s' "$c_dim"
    while (( j < pad )); do printf '·'; ((j++)) || true; done
    printf '%s' "$c_reset"
    if (( score > 10 )); then
        printf "  ${c_orange}+%d${c_reset}  ${c_white}%d${c_reset}\n" "$((score - 10))" "$score"
    else
        printf "    ${c_white}%d${c_reset}\n" "$score"
    fi
}

# ── BANNER + SECTION TEMPLATES ─────────────────────────────────────────────
# Generic chrome consumers fill in via positional args. Each consumer
# (onboarding splash, toolchain banner, claw load ceremony) has its own
# more elaborate banner, but this is the cross-cutting default.
_banner_basic() {
    local title="$1" subtitle="${2:-}" tag="${3:-}"
    cat <<EOF
${c_purple}
  ╔══════════════════════════════════════════════════════════════════╗
  ║${c_reset}  ${c_pink}${c_bold}░▒▓█  ${title}  █▓▒░${c_reset}    ${c_cyan}${subtitle}${c_reset}  ${c_purple}║
  ╠══════════════════════════════════════════════════════════════════╣
  ║${c_reset}  ${c_dim}theme: ${c_white}${THEME_NAME}${c_reset}  ${c_dim}·${c_reset}  ${c_dim}user: ${c_white}${USER}${c_reset}                                ${c_purple}║
  ╚══════════════════════════════════════════════════════════════════╝
${c_reset}
EOF
    if [[ -n "$tag" ]]; then
        printf "  ${c_dim}%s${c_reset}\n\n" "$tag"
    fi
}

_section() {
    echo ""
    printf "${c_purple}  ──[ ${c_pink}${c_bold}%02d${c_reset} ${c_purple}]──${c_pink}  %s${c_reset}\n" "$1" "$2"
    printf "${c_purple}  ──────────────────────────────────────────────────────────────${c_reset}\n"
}
