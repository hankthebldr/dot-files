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
# Each theme is a LIBRARY under config/themes/<slug>/ :
#   palette.theme   key=hex source of truth (committed)
#   ghostty.conf    rendered Ghostty color include (committed; built by
#                   `claw theme build`). Other surface artifacts can join it.
# Active choice is stored per-machine in $XDG_STATE_HOME/claw/theme (NOT
# committed) so each box picks its own without dirtying the repo. The active
# theme's ghostty.conf is copied to terminal/.config/ghostty/theme.conf (a
# git-ignored, per-machine pointer the terminal includes). POSIX-portable.

CLAW_THEME_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}/config/themes"
CLAW_THEME_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claw"
CLAW_THEME_ACTIVE_FILE="$CLAW_THEME_STATE_DIR/theme"
CLAW_THEME_DEFAULT="refined-dark"
# Where the active theme's Ghostty colors are mirrored (git-ignored include).
CLAW_THEME_GHOSTTY_ACTIVE="${DOTFILES_DIR:-$HOME/.dotfiles}/terminal/.config/ghostty/theme.conf"

# Color keys present in every palette.theme (order = swatch/preview order).
CLAW_THEME_KEYS="bg bg_alt fg muted divider blue green purple amber red cyan"

# Path to a theme's palette source. Falls back to the legacy flat layout
# (config/themes/<slug>.theme) so a half-migrated checkout still loads.
_claw_theme_file() {
    if [ -r "$CLAW_THEME_DIR/$1/palette.theme" ]; then
        printf '%s/%s/palette.theme' "$CLAW_THEME_DIR" "$1"
    else
        printf '%s/%s.theme' "$CLAW_THEME_DIR" "$1"
    fi
}

# slug of the active theme. Precedence: CLAW_THEME env (session override, set
# by profile loads) → state file (the user's persisted `claw theme set` pick)
# → default. The env override lets a profile re-theme one session without
# touching the persisted choice.
claw_theme_current() {
    if [ -n "${CLAW_THEME:-}" ] && [ -r "$(_claw_theme_file "$CLAW_THEME")" ]; then
        printf '%s\n' "$CLAW_THEME"
    elif [ -r "$CLAW_THEME_ACTIVE_FILE" ]; then
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
    _f="$(_claw_theme_file "$_slug")"
    [ -r "$_f" ] || { _slug="$CLAW_THEME_DEFAULT"; _f="$(_claw_theme_file "$_slug")"; }
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
    for _td in "$CLAW_THEME_DIR"/*/; do
        _s="$(basename "$_td")"
        _tf="$(_claw_theme_file "$_s")"
        [ -r "$_tf" ] || continue
        _n="$(sed -n 's/^name=//p' "$_tf" | head -n1)"
        if [ "$_s" = "$_cur" ]; then
            printf '  \033[38;2;63;185;80m●\033[0m \033[1m%-18s\033[0m %s\n' "$_s" "$_n"
        else
            printf '    \033[38;2;139;148;158m%-18s %s\033[0m\n' "$_s" "$_n"
        fi
    done
    # Straggler guard: surface any flat <slug>.theme not yet migrated to
    # <slug>/palette.theme so it can't silently vanish from the listing.
    for _tf in "$CLAW_THEME_DIR"/*.theme; do
        [ -e "$_tf" ] || continue
        _s="$(basename "$_tf" .theme)"
        [ -d "$CLAW_THEME_DIR/$_s" ] && continue   # already shown as a dir
        _n="$(sed -n 's/^name=//p' "$_tf" | head -n1)"
        printf '    \033[38;2;%sm%-18s %s (flat — migrate)\033[0m\n' "${CLAW_RGB_RED:-255;123;114}" "$_s" "$_n"
    done
}

# Swatch preview for a theme (defaults to active).
claw_theme_preview() {
    _t="${1:-$(claw_theme_current)}"
    _f="$(_claw_theme_file "$_t")"
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
    [ -r "$(_claw_theme_file "$_t")" ] || {
        printf 'theme not found: %s\n' "$_t" >&2
        printf 'available:\n' >&2; claw_theme_list >&2
        return 1
    }
    mkdir -p "$CLAW_THEME_STATE_DIR" 2>/dev/null
    printf '%s\n' "$_t" > "$CLAW_THEME_ACTIVE_FILE"
    claw_theme_load
    claw_theme_apply_ghostty                     # point Ghostty at this theme's library
    # clin plugin: re-render its config so the note TUI tracks the new palette.
    if command -v clin >/dev/null 2>&1 && [ -r "${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils/clin.sh" ]; then
        sh "${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils/clin.sh" sync >/dev/null 2>&1 || true
    fi
    printf '  \033[38;2;63;185;80m✓\033[0m theme set to \033[1m%s\033[0m\n' "$_t"
    printf '  \033[38;2;139;148;158mrun \033[0m\033[1mexec zsh\033[0m\033[38;2;139;148;158m to apply everywhere (prompt, fzf, dashboard)\033[0m\n'
    printf '  \033[38;2;139;148;158mGhostty: press \033[0m\033[1mSuper+Shift+R\033[0m\033[38;2;139;148;158m to reload terminal colors\033[0m\n'
}

# Render ONE theme's palette.theme → a Ghostty color include.
# Usage: _claw_render_ghostty <slug> <out-file>. Parses the file directly (not
# the active env) so the whole library can be (re)built regardless of which
# theme is active.
_claw_render_ghostty() {
    _rs="$1"; _ro="$2"
    _rf="$(_claw_theme_file "$_rs")"
    [ -r "$_rf" ] || return 1
    _claw_g() { sed -n "s/^$1=//p" "$_rf" | head -n1 | tr -d '\r#'; }
    _name="$(sed -n 's/^name=//p' "$_rf" | head -n1)"
    _bg="$(_claw_g bg)"; _bga="$(_claw_g bg_alt)"; _fg="$(_claw_g fg)"
    _mut="$(_claw_g muted)"; _div="$(_claw_g divider)"
    _blu="$(_claw_g blue)"; _grn="$(_claw_g green)"; _pur="$(_claw_g purple)"
    _amb="$(_claw_g amber)"; _red="$(_claw_g red)"; _cyn="$(_claw_g cyan)"
    [ -n "$_bg" ] || return 1
    [ -n "$_div" ] || _div="$_bga"
    {
        printf '# Generated by `claw theme build` — do not edit by hand.\n'
        printf '# Source of truth: config/themes/%s/palette.theme  (%s)\n\n' "$_rs" "$_name"
        printf 'background = %s\n' "$_bg"
        printf 'foreground = %s\n' "$_fg"
        printf 'selection-background = %s\n' "$_div"
        printf 'selection-foreground = %s\n' "$_fg"
        printf 'cursor-color = %s\n' "$_amb"
        printf 'cursor-text = %s\n\n' "$_bg"
        printf 'palette = 0=#%s\n'  "$_bga"
        printf 'palette = 1=#%s\n'  "$_red"
        printf 'palette = 2=#%s\n'  "$_grn"
        printf 'palette = 3=#%s\n'  "$_amb"
        printf 'palette = 4=#%s\n'  "$_blu"
        printf 'palette = 5=#%s\n'  "$_pur"
        printf 'palette = 6=#%s\n'  "$_cyn"
        printf 'palette = 7=#%s\n'  "$_fg"
        printf 'palette = 8=#%s\n'  "$_mut"
        printf 'palette = 9=#%s\n'  "$_red"
        printf 'palette = 10=#%s\n' "$_grn"
        printf 'palette = 11=#%s\n' "$_amb"
        printf 'palette = 12=#%s\n' "$_blu"
        printf 'palette = 13=#%s\n' "$_pur"
        printf 'palette = 14=#%s\n' "$_cyn"
        printf 'palette = 15=#%s\n' "$_fg"
    } > "$_ro" 2>/dev/null
}

# Build the LIBRARY: render config/themes/<slug>/ghostty.conf for one theme
# (default: active) or, with `all`, every theme. These artifacts are committed.
claw_theme_ghostty() {
    _gs="${1:-$(claw_theme_current)}"
    if [ "$_gs" = "all" ]; then claw_theme_build; return; fi
    _claw_render_ghostty "$_gs" "$CLAW_THEME_DIR/$_gs/ghostty.conf"
}
claw_theme_build() {
    for _bd in "$CLAW_THEME_DIR"/*/; do
        _bs="$(basename "$_bd")"
        [ -r "$(_claw_theme_file "$_bs")" ] || continue
        if _claw_render_ghostty "$_bs" "$CLAW_THEME_DIR/$_bs/ghostty.conf"; then
            printf '  \033[38;2;63;185;80m✓\033[0m %s/ghostty.conf\n' "$_bs"
        fi
    done
    # Straggler guard: build flat <slug>.theme files too (into <slug>/) so an
    # unmigrated palette still gets a Ghostty artifact instead of vanishing.
    for _bf in "$CLAW_THEME_DIR"/*.theme; do
        [ -e "$_bf" ] || continue
        _bs="$(basename "$_bf" .theme)"
        [ -d "$CLAW_THEME_DIR/$_bs" ] && continue   # already built as a dir
        mkdir -p "$CLAW_THEME_DIR/$_bs" 2>/dev/null
        if _claw_render_ghostty "$_bs" "$CLAW_THEME_DIR/$_bs/ghostty.conf"; then
            printf '  \033[38;2;%sm✓ %s/ghostty.conf (flat — migrate)\033[0m\n' "${CLAW_RGB_RED:-255;123;114}" "$_bs"
        fi
    done
}

# Point the terminal at the ACTIVE theme: copy its library ghostty.conf to the
# git-ignored include the Ghostty config reads. Renders on the fly if the
# library artifact is missing (e.g. a stale checkout pre-`claw theme build`).
claw_theme_apply_ghostty() {
    _as="$(claw_theme_current)"
    _src="$CLAW_THEME_DIR/$_as/ghostty.conf"
    if [ -r "$_src" ]; then
        cp "$_src" "$CLAW_THEME_GHOSTTY_ACTIVE" 2>/dev/null
    else
        _claw_render_ghostty "$_as" "$CLAW_THEME_GHOSTTY_ACTIVE" 2>/dev/null
    fi
}

# Apply a profile's declared palette for THIS SESSION (env override only — the
# persisted `claw theme set` choice is untouched). Call after sourcing a
# profile: reads PROFILE_THEME_DEFAULT (set in the profile's meta.zsh), applies
# it only if that .theme actually exists. claw-fn.zsh and welcome-tui both use
# this, so `claw load security` re-themes the prompt/menus/dashboard in one move.
claw_theme_apply_profile() {
    _pt="${PROFILE_THEME_DEFAULT:-}"
    [ -n "$_pt" ] || return 0
    # Use the canonical resolver (dir layout config/themes/<slug>/palette.theme,
    # flat fallback) — the old hardcoded flat path silently skipped theming for
    # any profile whose palette only exists as a directory (refined-dark, etc.).
    [ -r "$(_claw_theme_file "$_pt")" ] || return 0
    [ "$_pt" = "${CLAW_THEME_SLUG:-}" ] && return 0
    export CLAW_THEME="$_pt"
    claw_theme_load
}

# Drop any session override and reload the persisted palette (used by claw off).
claw_theme_reset_session() {
    unset CLAW_THEME
    claw_theme_load
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
        build)          claw_theme_build ;;
        ghostty)        claw_theme_ghostty "$@" ;;
        apply)          claw_theme_apply_ghostty ;;
        reload|load)    claw_theme_load ;;
        *)              printf 'usage: theme.sh {list|current|set <slug>|preview [slug]|fzf|build|ghostty [slug|all]|apply|reload}\n' >&2; exit 1 ;;
    esac
fi
