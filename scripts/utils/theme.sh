#!/usr/bin/env bash
# theme.sh — Open Claw single-source-of-truth color system.
#
# SOURCE it (bash or zsh) to load the ACTIVE palette into the environment:
#   CLAW_C_<KEY>    hex string, no '#'   (e.g. CLAW_C_BLUE=58a6ff)
#   CLAW_RGB_<KEY>  "r;g;b" triplet      (e.g. CLAW_RGB_BLUE=88;166;255)
#   CLAW_THEME_NAME / CLAW_THEME_SLUG
# plus helper functions used by the dashboard, fastfetch readout, fzf, and the
# `claw theme` switcher.
#
# RUN it (bash scripts/utils/theme.sh ...) for the CLI:
#   theme.sh list | current | set <slug> | preview [slug] | fzf | reload
#
# Palettes live in config/themes/<slug>.theme (key=hex). Active choice is stored
# per-machine in $XDG_STATE_HOME/claw/theme (NOT committed) so each box can pick
# its own without dirtying the repo. POSIX-portable; works under bash and zsh.

CLAW_THEME_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}/config/themes"
CLAW_THEME_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claw"
CLAW_THEME_ACTIVE_FILE="$CLAW_THEME_STATE_DIR/theme"
CLAW_THEME_DEFAULT="refined-dark"

# Color keys present in every .theme file (order = swatch/preview order).
CLAW_THEME_KEYS="bg bg_alt fg muted divider blue green purple amber red cyan"

# slug of the active theme (state file → default).
claw_theme_current() {
    if [ -r "$CLAW_THEME_ACTIVE_FILE" ]; then
        head -n1 "$CLAW_THEME_ACTIVE_FILE" 2>/dev/null
    else
        printf '%s\n' "$CLAW_THEME_DEFAULT"
    fi
}

# "rrggbb" → "r;g;b" (decimal, for ANSI 24-bit + python).
_claw_hex2rgb() {
    _h="${1#\#}"
    printf '%d;%d;%d' "$(( 16#${_h%????} ))" "$(( 16#$(printf '%s' "$_h" | cut -c3-4) ))" "$(( 16#$(printf '%s' "$_h" | cut -c5-6) ))"
}

# Parse the active .theme file into CLAW_C_* / CLAW_RGB_* exports.
claw_theme_load() {
    _slug="$(claw_theme_current)"
    _f="$CLAW_THEME_DIR/$_slug.theme"
    [ -r "$_f" ] || { _slug="$CLAW_THEME_DEFAULT"; _f="$CLAW_THEME_DIR/$_slug.theme"; }
    [ -r "$_f" ] || return 0
    export CLAW_THEME_SLUG="$_slug"
    while IFS='=' read -r _k _v; do
        case "$_k" in ''|\#*) continue ;; esac
        _v="${_v%$'\r'}"                        # strip trailing CR (CRLF files)
        case "$_k" in
            name) export CLAW_THEME_NAME="$_v" ;;
            slug) : ;;                            # slug comes from the filename
            *)
                _u="$(printf '%s' "$_k" | tr '[:lower:]' '[:upper:]')"
                eval "export CLAW_C_$_u=\"$_v\""
                eval "export CLAW_RGB_$_u=\"$(_claw_hex2rgb "$_v")\""
                ;;
        esac
    done < "$_f"
}

# fzf --color string built from the active palette (no leading/trailing space).
claw_theme_fzf() {
    printf 'bg+:#%s,fg+:#%s,prompt:#%s,header:#%s,pointer:#%s,hl:#%s,hl+:#%s,info:#%s,marker:#%s,spinner:#%s' \
        "${CLAW_C_BG_ALT:-161b22}" "${CLAW_C_FG:-c9d1d9}" "${CLAW_C_BLUE:-58a6ff}" \
        "${CLAW_C_MUTED:-8b949e}" "${CLAW_C_GREEN:-3fb950}" "${CLAW_C_RED:-ff7b72}" \
        "${CLAW_C_RED:-ff7b72}" "${CLAW_C_MUTED:-8b949e}" "${CLAW_C_AMBER:-e3b341}" \
        "${CLAW_C_PURPLE:-bc8cff}"
}

claw_theme_list() {
    _cur="$(claw_theme_current)"
    for _tf in "$CLAW_THEME_DIR"/*.theme; do
        [ -r "$_tf" ] || continue
        _s="$(basename "$_tf" .theme)"
        _n="$(sed -n 's/^name=//p' "$_tf" | head -n1)"
        if [ "$_s" = "$_cur" ]; then
            printf '  \033[38;2;63;185;80m●\033[0m \033[1m%-18s\033[0m %s\n' "$_s" "$_n"
        else
            printf '    \033[38;2;139;148;158m%-18s %s\033[0m\n' "$_s" "$_n"
        fi
    done
}

# Swatch preview for a theme (defaults to active).
claw_theme_preview() {
    _t="${1:-$(claw_theme_current)}"
    _f="$CLAW_THEME_DIR/$_t.theme"
    [ -r "$_f" ] || { printf 'theme not found: %s\n' "$_t" >&2; return 1; }
    _n="$(sed -n 's/^name=//p' "$_f" | head -n1)"
    printf '\n  \033[1m%s\033[0m  \033[38;2;139;148;158m(%s)\033[0m\n\n' "$_n" "$_t"
    for _key in $CLAW_THEME_KEYS; do
        _hex="$(sed -n "s/^$_key=//p" "$_f" | head -n1)"
        [ -n "$_hex" ] || continue
        _rgb="$(_claw_hex2rgb "$_hex")"
        printf '    \033[48;2;%sm      \033[0m  \033[38;2;%sm%-8s\033[0m \033[38;2;139;148;158m#%s\033[0m\n' \
            "$_rgb" "$_rgb" "$_key" "$_hex"
    done
    printf '\n'
}

claw_theme_set() {
    _t="$1"
    [ -n "$_t" ] || { printf 'usage: claw theme set <slug>\n' >&2; return 1; }
    [ -r "$CLAW_THEME_DIR/$_t.theme" ] || {
        printf 'theme not found: %s\n' "$_t" >&2
        printf 'available:\n' >&2; claw_theme_list >&2
        return 1
    }
    mkdir -p "$CLAW_THEME_STATE_DIR" 2>/dev/null
    printf '%s\n' "$_t" > "$CLAW_THEME_ACTIVE_FILE"
    claw_theme_load
    printf '  \033[38;2;63;185;80m✓\033[0m theme set to \033[1m%s\033[0m\n' "$_t"
    printf '  \033[38;2;139;148;158mrun \033[0m\033[1mexec zsh\033[0m\033[38;2;139;148;158m to apply everywhere (prompt, fzf, dashboard)\033[0m\n'
}

# Load the palette into the environment on every source.
claw_theme_load 2>/dev/null || true

# CLI dispatch — only when EXECUTED via bash, never when sourced (incl. zsh).
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE}" = "${0}" ]; then
    _cmd="${1:-list}"; shift 2>/dev/null || true
    case "$_cmd" in
        list|ls)        claw_theme_list ;;
        current|active) claw_theme_current ;;
        set|use)        claw_theme_set "$@" ;;
        preview|show)   claw_theme_preview "$@" ;;
        fzf)            claw_theme_fzf; printf '\n' ;;
        reload|load)    claw_theme_load ;;
        *)              printf 'usage: theme.sh {list|current|set <slug>|preview [slug]|fzf|reload}\n' >&2; exit 1 ;;
    esac
fi
