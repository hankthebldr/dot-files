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
#   theme.sh emit <p10k|tui|fzf|osc>   — ready-made palette artifacts
#   theme.sh depth                     — CLAW_COLOR_DEPTH probe
#   theme.sh render-depth              — the depth surfaces emit at
#   theme.sh glyphs                    — CLAW_GLYPHS (nerd|ascii)
#   theme.sh sgr <r;g;b>               — one SGR at the render depth
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
# Keep in sync with the static case in claw_theme_load (its key allow-list).
CLAW_THEME_KEYS="bg bg_alt fg muted divider blue green purple amber red cyan"

# Path to a theme's palette source. Falls back to the legacy flat layout
# (config/themes/<slug>.theme) so a half-migrated checkout still loads.
# _claw_theme_path sets $_claw_tf (no fork — the load path uses it);
# _claw_theme_file prints it for the $(...) call sites in the CLI verbs.
_claw_theme_path() {
    if [ -r "$CLAW_THEME_DIR/$1/palette.theme" ]; then
        _claw_tf="$CLAW_THEME_DIR/$1/palette.theme"
    else
        _claw_tf="$CLAW_THEME_DIR/$1.theme"
    fi
}
_claw_theme_file() { _claw_theme_path "$1"; printf '%s' "$_claw_tf"; }

# slug of the active theme. Precedence: CLAW_THEME env (session override, set
# by profile loads) → state file (the user's persisted `claw theme set` pick)
# → default. The env override lets a profile re-theme one session without
# touching the persisted choice. _claw_theme_resolve sets $_claw_slug without
# forking; claw_theme_current is the printing wrapper (public name).
_claw_theme_resolve() {
    _claw_slug=""
    if [ -n "${CLAW_THEME:-}" ]; then
        _claw_theme_path "$CLAW_THEME"
        [ -r "$_claw_tf" ] && _claw_slug="$CLAW_THEME"
    fi
    if [ -z "$_claw_slug" ] && [ -r "$CLAW_THEME_ACTIVE_FILE" ]; then
        IFS= read -r _claw_slug < "$CLAW_THEME_ACTIVE_FILE" || :
        _claw_slug="${_claw_slug%$'\r'}"
    fi
    [ -n "$_claw_slug" ] || _claw_slug="$CLAW_THEME_DEFAULT"
}
claw_theme_current() {
    _claw_theme_resolve
    printf '%s\n' "$_claw_slug"
}

# "rrggbb" → "r;g;b" (decimal, for ANSI 24-bit + python). Substring expansion
# is valid in bash and zsh (theme.sh is never run under dash — `16#` already
# rules that out). _claw_hex2rgb_set fills $_claw_rgb without a fork.
_claw_hex2rgb_set() {
    _h="${1#\#}"
    _claw_rgb="$(( 16#${_h:0:2} ));$(( 16#${_h:2:2} ));$(( 16#${_h:4:2} ))"
}
_claw_hex2rgb() {
    _h="${1#\#}"
    printf '%d;%d;%d' "$(( 16#${_h:0:2} ))" "$(( 16#${_h:2:2} ))" "$(( 16#${_h:4:2} ))"
}

# Parse the active .theme file into CLAW_C_* / CLAW_RGB_* exports.
# Fork-free (audit F-11: this ran ~66 forks, 5× per login). Idempotent: when
# the resolved slug is already exported with a palette, return without
# touching the file — child processes that source theme.sh inherit the env
# for free. CLAW_THEME_FORCE=1 (set by the slug-changing verbs) re-reads.
claw_theme_load() {
    _claw_theme_resolve
    _slug="$_claw_slug"
    [ "${CLAW_THEME_SLUG:-}" = "$_slug" ] && [ -n "${CLAW_C_BG:-}" ] \
        && [ "${CLAW_THEME_FORCE:-0}" != 1 ] && return 0
    _claw_theme_path "$_slug"; _f="$_claw_tf"
    [ -r "$_f" ] || { _slug="$CLAW_THEME_DEFAULT"; _claw_theme_path "$_slug"; _f="$_claw_tf"; }
    [ -r "$_f" ] || return 0
    export CLAW_THEME_SLUG="$_slug"
    while IFS='=' read -r _k _v; do
        case "$_k" in ''|\#*) continue ;; esac
        _v="${_v%$'\r'}"                        # strip trailing CR (CRLF files)
        case "$_k" in
            name) export CLAW_THEME_NAME="$_v"; continue ;;
            slug) continue ;;                     # slug comes from the filename
        esac
        # Static upper-casing doubles as the key allow-list (= CLAW_THEME_KEYS).
        case "$_k" in
            bg) _u=BG ;;         bg_alt) _u=BG_ALT ;;   fg) _u=FG ;;
            muted) _u=MUTED ;;   divider) _u=DIVIDER ;; blue) _u=BLUE ;;
            green) _u=GREEN ;;   purple) _u=PURPLE ;;   amber) _u=AMBER ;;
            red) _u=RED ;;       cyan) _u=CYAN ;;
            *) continue ;;
        esac
        _v="${_v#\#}"
        case "$_v" in
            [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
            *) continue ;;                        # not a 6-digit hex — skip, never abort the load
        esac
        _claw_hex2rgb_set "$_v"
        export "CLAW_C_$_u=$_v" "CLAW_RGB_$_u=$_claw_rgb"
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
            printf '  \033[38;2;%sm●\033[0m \033[1m%-18s\033[0m %s\n' "${CLAW_RGB_GREEN:-63;185;80}" "$_s" "$_n"
        else
            printf '    \033[38;2;%sm%-18s %s\033[0m\n' "${CLAW_RGB_MUTED:-139;148;158}" "$_s" "$_n"
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
    printf '\n  \033[1m%s\033[0m  \033[38;2;%sm(%s)\033[0m\n\n' "$_n" "${CLAW_RGB_MUTED:-139;148;158}" "$_t"
    for _key in $CLAW_THEME_KEYS; do
        _hex="$(sed -n "s/^$_key=//p" "$_f" | head -n1)"
        [ -n "$_hex" ] || continue
        _rgb="$(_claw_hex2rgb "$_hex")"
        printf '    \033[48;2;%sm      \033[0m  \033[38;2;%sm%-8s\033[0m \033[38;2;%sm#%s\033[0m\n' \
            "$_rgb" "$_rgb" "$_key" "${CLAW_RGB_MUTED:-139;148;158}" "$_hex"
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
    CLAW_THEME_FORCE=1 claw_theme_load           # slug changed — bypass the idempotency guard
    claw_theme_apply_ghostty                     # point Ghostty at this theme's library
    # clin plugin: re-render its config so the note TUI tracks the new palette.
    if command -v clin >/dev/null 2>&1 && [ -r "${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils/clin.sh" ]; then
        sh "${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils/clin.sh" sync >/dev/null 2>&1 || true
    fi
    _g="${CLAW_RGB_GREEN:-63;185;80}"; _m="${CLAW_RGB_MUTED:-139;148;158}"
    printf '  \033[38;2;%sm✓\033[0m theme set to \033[1m%s\033[0m\n' "$_g" "$_t"
    printf '  \033[38;2;%smrun \033[0m\033[1mexec zsh\033[0m\033[38;2;%sm to apply everywhere (prompt, fzf, dashboard)\033[0m\n' "$_m" "$_m"
    printf '  \033[38;2;%smGhostty: press \033[0m\033[1mSuper+Shift+R\033[0m\033[38;2;%sm to reload terminal colors\033[0m\n' "$_m" "$_m"
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
            printf '  \033[38;2;%sm✓\033[0m %s/ghostty.conf\n' "${CLAW_RGB_GREEN:-63;185;80}" "$_bs"
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
# it only if that .theme actually exists. claw-fn.zsh and claw-login.zsh both use
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
    CLAW_THEME_FORCE=1 claw_theme_load
}

# Drop any session override and reload the persisted palette (used by claw off).
claw_theme_reset_session() {
    unset CLAW_THEME
    CLAW_THEME_FORCE=1 claw_theme_load
}

# ============================================================================
# GENERATOR — claw_theme_emit <p10k|tui|fzf|osc>   (audit F-13)
# ============================================================================
# theme.sh is the ONE source of colour, so every other surface ASKS it for a
# ready-made artifact instead of re-deriving literals. `p10k`/`tui`/`fzf` print
# shell code the caller evals; `osc` prints terminal control bytes directly.
# These run off the login hot path (once per prompt config, once per `claw
# theme set`) — unlike claw_theme_load they are allowed to fork, and do not.
# Every value carries the refined-dark fallback so a half-loaded palette still
# renders.

# One p10k "block" segment: solid background in the palette hue, text in bg.
_claw_p10k_block() {   # $1 = segment stem, $2 = background hex
    printf "typeset -g POWERLEVEL9K_%s_BACKGROUND='#%s'\n" "$1" "$2"
    printf "typeset -g POWERLEVEL9K_%s_FOREGROUND='#%s'\n" "$1" "$_e_bg"
}

_claw_emit_p10k() {
    printf '# generated by claw_theme_emit p10k — palette: %s\n' "${CLAW_THEME_SLUG:-$CLAW_THEME_DEFAULT}"
    _claw_p10k_block OS_ICON "$_e_mut"
    _claw_p10k_block DIR "$_e_blu"
    printf "typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND='#%s'\n" "$_e_bga"
    printf "typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND='#%s'\n" "$_e_bg"
    _claw_p10k_block VCS_CLEAN "$_e_grn"
    _claw_p10k_block VCS_UNTRACKED "$_e_grn"
    _claw_p10k_block VCS_MODIFIED "$_e_amb"
    _claw_p10k_block VCS_CONFLICTED "$_e_red"
    printf "typeset -g POWERLEVEL9K_VCS_LOADING_BACKGROUND='#%s'\n" "$_e_div"
    _claw_p10k_block STATUS_ERROR "$_e_red"
    _claw_p10k_block COMMAND_EXECUTION_TIME "$_e_amb"
    _claw_p10k_block BACKGROUND_JOBS "$_e_grn"
    _claw_p10k_block DIRENV "$_e_amb"
    _claw_p10k_block VIRTUALENV "$_e_blu"
    _claw_p10k_block PYENV "$_e_blu"
    _claw_p10k_block NODE_VERSION "$_e_grn"
    _claw_p10k_block NODENV "$_e_grn"
    _claw_p10k_block KUBECONTEXT "$_e_pur"
    _claw_p10k_block TERRAFORM "$_e_pur"
    _claw_p10k_block AWS "$_e_amb"
    _claw_p10k_block GCLOUD "$_e_cyn"
    _claw_p10k_block CONTEXT_ROOT "$_e_red"
    _claw_p10k_block CONTEXT_REMOTE "$_e_mut"
    _claw_p10k_block CONTEXT_REMOTE_SUDO "$_e_mut"
    # prompt_char is transparent: foreground only, green ok / red error.
    printf "typeset -g POWERLEVEL9K_PROMPT_CHAR_BACKGROUND=\n"
    for _m in VIINS VICMD VIVIS VIOWR; do
        printf "typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_%s_FOREGROUND='#%s'\n" "$_m" "$_e_grn"
        printf "typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_%s_FOREGROUND='#%s'\n" "$_m" "$_e_red"
    done
}

# One `name=$'\e[<body>m'` assignment for the bash TUI helpers. The body comes
# from the ONE quantiser, so a depth-8 terminal gets `\e[34m`, a strict 256 one
# `\e[38;5;75m`, and depth 0 gets an empty string (plain text, no escapes).
_claw_tui_var() {      # $1 = var name, $2 = "r;g;b"
    _claw_sgr_body "$2"
    if [ -z "$_claw_sgr_out" ]; then
        printf "%s=''\n" "$1"
    else
        printf "%s=\$'\\\\e[%sm'\n" "$1" "$_claw_sgr_out"
    fi
}
_claw_emit_tui() {
    claw_theme_render_depth
    if [ "$_claw_rdepth" = 0 ]; then
        printf "c_reset=''\n"
        printf "c_bold=''\n"
    else
        printf "c_reset=\$'\\\\e[0m'\n"
        printf "c_bold=\$'\\\\e[1m'\n"
    fi
    _claw_tui_var c_blue   "${CLAW_RGB_BLUE:-88;166;255}"
    _claw_tui_var c_green  "${CLAW_RGB_GREEN:-63;185;80}"
    _claw_tui_var c_purple "${CLAW_RGB_PURPLE:-188;140;255}"
    _claw_tui_var c_amber  "${CLAW_RGB_AMBER:-227;179;65}"
    _claw_tui_var c_red    "${CLAW_RGB_RED:-255;123;114}"
    _claw_tui_var c_muted  "${CLAW_RGB_MUTED:-139;148;158}"
    _claw_tui_var c_fg     "${CLAW_RGB_FG:-201;209;217}"
    # Legacy names are misnamed hues kept so no call site changes.
    printf 'c_cyan="$c_blue"; c_orange="$c_amber"; c_yellow="$c_amber"; c_dim="$c_muted"; c_white="$c_fg"\n'
}

# OSC 10/11/12 (fg / bg / cursor). Allow-list only: never through tmux or SSH,
# never on a terminal that half-applies it, never when stdout is not a tty
# (CLAW_THEME_OSC_FORCE_TTY=1 is the test hook), never with CLAW_THEME_OSC=0.
# Apple_Terminal is deliberately absent — it ignores OSC 11 (spec T2).
_claw_emit_osc() {
    [ "${CLAW_THEME_OSC:-1}" != 0 ] || return 0
    [ -z "${SSH_CONNECTION:-}${SSH_TTY:-}${TMUX:-}" ] || return 0
    [ "${CLAW_THEME_OSC_FORCE_TTY:-0}" = 1 ] || [ -t 1 ] || return 0
    case "${TERM_PROGRAM:-}" in
        ghostty|iTerm.app|WezTerm|kitty) ;;
        *) [ -n "${VTE_VERSION:-}" ] || return 0 ;;
    esac
    printf '\033]10;#%s\033\\\033]11;#%s\033\\\033]12;#%s\033\\' "$_e_fg" "$_e_bg" "$_e_blu"
}

claw_theme_emit() {
    _e_bg="${CLAW_C_BG:-0d1117}";       _e_bga="${CLAW_C_BG_ALT:-161b22}"
    _e_fg="${CLAW_C_FG:-c9d1d9}";       _e_mut="${CLAW_C_MUTED:-8b949e}"
    _e_div="${CLAW_C_DIVIDER:-30363d}"; _e_blu="${CLAW_C_BLUE:-58a6ff}"
    _e_grn="${CLAW_C_GREEN:-3fb950}";   _e_pur="${CLAW_C_PURPLE:-bc8cff}"
    _e_amb="${CLAW_C_AMBER:-e3b341}";   _e_red="${CLAW_C_RED:-ff7b72}"
    _e_cyn="${CLAW_C_CYAN:-39c5ff}"
    case "${1:-}" in
        p10k) _claw_emit_p10k ;;
        tui)  _claw_emit_tui ;;
        fzf)  printf "export CLAW_FZF_COLOR='%s'\n" "$(claw_theme_fzf)" ;;
        osc)  _claw_emit_osc ;;
        *)    printf 'usage: claw_theme_emit <p10k|tui|fzf|osc>\n' >&2; return 2 ;;
    esac
}

# ============================================================================
# COLOUR DEPTH — the ONE hex→index quantiser (audit T2-03)
# ============================================================================
# Every surface used to emit 24-bit `\e[38;2;r;g;bm` unconditionally, so a
# terminal that only has 256 (or 8) colours either approximated silently or
# rendered the wrong hue. theme.sh is the generator (spine contract 2), so the
# rgb→xterm-256 and rgb→ANSI-8 mapping lives HERE and nowhere else. The Python
# renderer carries a byte-identical mirror (claw-dashboard.py `_sgr_body`);
# tests/theme.bats pins that the two agree on a table of sample colours.
#
# PRECEDENCE, and why a probed 256 still renders 24-bit:
#   CLAW_COLOR_DEPTH set to 0|8|24|256 in the environment is a DECLARATION and
#   is obeyed exactly. Anything else is a PROBE (claw_theme_depth), and a
#   probed 256 keeps emitting 24-bit unless CLAW_COLOR_DEPTH_STRICT=1 — every
#   terminal that reports "256" through TERM=*256color* in practice either
#   renders truecolor or approximates it silently, and downgrading a palette
#   nobody asked to downgrade is the worse failure. Depth 8 and 0 always
#   degrade: there the wrong code really does render the wrong colour.

# xterm 6×6×6 cube axis value for level 0..5.
_claw_cube_level() {
    case "$1" in
        0) _cl=0 ;; 1) _cl=95 ;; 2) _cl=135 ;;
        3) _cl=175 ;; 4) _cl=215 ;; *) _cl=255 ;;
    esac
}

# Nearest cube level for one 0-255 channel (thresholds are the midpoints).
_claw_cube_axis() {
    if   [ "$1" -lt 48 ];  then _ca=0
    elif [ "$1" -lt 115 ]; then _ca=1
    elif [ "$1" -lt 155 ]; then _ca=2
    elif [ "$1" -lt 195 ]; then _ca=3
    elif [ "$1" -lt 235 ]; then _ca=4
    else                        _ca=5
    fi
}

# claw_theme_index256 <r> <g> <b> → $_claw_idx, the nearest xterm-256 index.
# Candidates are the 6×6×6 cube (16-231) and the 24-step grey ramp (232-255);
# 0-15 are skipped on purpose — those eight/sixteen slots are whatever the
# user themed them to be, so quantising INTO them would fight the palette.
claw_theme_index256() {
    _q_r=$1 _q_g=$2 _q_b=$3
    _claw_cube_axis "$_q_r"; _cx=$_ca; _claw_cube_level "$_cx"; _vr=$_cl
    _claw_cube_axis "$_q_g"; _cy=$_ca; _claw_cube_level "$_cy"; _vg=$_cl
    _claw_cube_axis "$_q_b"; _cz=$_ca; _claw_cube_level "$_cz"; _vb=$_cl
    _dc=$(( (_q_r - _vr) * (_q_r - _vr) + (_q_g - _vg) * (_q_g - _vg) \
          + (_q_b - _vb) * (_q_b - _vb) ))
    _ga=$(( (_q_r + _q_g + _q_b) / 3 ))
    if [ "$_ga" -lt 8 ]; then _gi=0; else _gi=$(( (_ga - 8 + 5) / 10 )); fi
    if [ "$_gi" -gt 23 ]; then _gi=23; fi
    _gv=$(( 8 + 10 * _gi ))
    _dg=$(( (_q_r - _gv) * (_q_r - _gv) + (_q_g - _gv) * (_q_g - _gv) \
          + (_q_b - _gv) * (_q_b - _gv) ))
    if [ "$_dg" -lt "$_dc" ]; then
        _claw_idx=$(( 232 + _gi ))
    else
        _claw_idx=$(( 16 + 36 * _cx + 6 * _cy + _cz ))
    fi
}

# Reference RGB for the eight ANSI base slots, in the SATURATED (bright)
# rendering every modern terminal ships. The dim 205-based xterm defaults put
# every light palette hue nearer to white than to its own hue (#ff7b72 "red"
# quantised to WHITE against them, measured) — these agree with the standard
# rgb→ansi16 reduction instead.
# (unrolled below rather than iterated over a string: zsh does not word-split
# an unquoted parameter, so a "0,0,0 255,0,0 ..." list silently arrives as one
# word there and the arithmetic blows up. theme.sh is sourced by BOTH shells.)

# _claw_a8 <idx> <r> <g> <b> — keep the nearest candidate so far.
_claw_a8() {
    _a8d=$(( (_q_r - $2) * (_q_r - $2) + (_q_g - $3) * (_q_g - $3) \
           + (_q_b - $4) * (_q_b - $4) ))
    if [ "$_a8best" -lt 0 ] || [ "$_a8d" -lt "$_a8best" ]; then
        _a8best=$_a8d; _claw_idx=$1
    fi
}

# claw_theme_index8 <r> <g> <b> → $_claw_idx, nearest of the 8 base colours.
claw_theme_index8() {
    _q_r=$1 _q_g=$2 _q_b=$3
    _claw_idx=7; _a8best=-1
    _claw_a8 0   0   0   0
    _claw_a8 1 255   0   0
    _claw_a8 2   0 255   0
    _claw_a8 3 255 255   0
    _claw_a8 4   0   0 255
    _claw_a8 5 255   0 255
    _claw_a8 6   0 255 255
    _claw_a8 7 255 255 255
}

# The probe, factored out of claw_theme_depth so the render-depth resolver can
# ask without publishing (exporting) an answer.
_claw_probe_depth() {
    _pd=8
    case "${TERM:-}" in ''|dumb) _pd=0 ;; esac
    [ -z "${NO_COLOR:-}" ] || _pd=0
    if [ "$_pd" != 0 ]; then
        case "${TERM_PROGRAM:-}" in
            Apple_Terminal)                  _pd=256 ;;
            ghostty|iTerm.app|WezTerm|kitty) _pd=24 ;;
            *)
                case "${COLORTERM:-}" in
                    truecolor|24bit) _pd=24 ;;
                    *)
                        case "${TERM:-}" in
                            *direct*)   _pd=24 ;;
                            *256color*) _pd=256 ;;
                            *)          _pd=8 ;;
                        esac
                        ;;
                esac
                ;;
        esac
    fi
}

# claw_theme_render_depth → $_claw_rdepth (0|8|24|256): the depth surfaces
# actually EMIT at. See the precedence note above. Never exports, so calling
# it twice cannot promote its own probe into a declaration.
claw_theme_render_depth() {
    case "${CLAW_COLOR_DEPTH:-}" in
        0|8|24|256) _claw_rdepth="$CLAW_COLOR_DEPTH"; return 0 ;;
    esac
    _claw_probe_depth
    _claw_rdepth="$_pd"
    if [ "$_claw_rdepth" = 256 ] && [ "${CLAW_COLOR_DEPTH_STRICT:-0}" != 1 ]; then
        _claw_rdepth=24
    fi
}

# _claw_sgr_body "<r;g;b>" → $_claw_sgr_out, the SGR PARAMETER body for the
# active render depth ("38;2;r;g;b" | "38;5;N" | "3X" | "" at depth 0). The
# body, not the whole escape, so callers can splice it into either a raw
# string or a `$'\e[...m'` literal without re-deriving anything.
_claw_sgr_body() {
    _claw_in="${1:-}"
    _claw_r="${_claw_in%%;*}"; _claw_t="${_claw_in#*;}"
    _claw_g="${_claw_t%%;*}"; _claw_b="${_claw_t#*;}"
    case "$_claw_r" in ''|*[!0-9]*) _claw_r=0 ;; esac
    case "$_claw_g" in ''|*[!0-9]*) _claw_g=0 ;; esac
    case "$_claw_b" in ''|*[!0-9]*) _claw_b=0 ;; esac
    if [ "$_claw_r" -gt 255 ]; then _claw_r=255; fi
    if [ "$_claw_g" -gt 255 ]; then _claw_g=255; fi
    if [ "$_claw_b" -gt 255 ]; then _claw_b=255; fi
    claw_theme_render_depth
    case "$_claw_rdepth" in
        0)   _claw_sgr_out="" ;;
        8)   claw_theme_index8 "$_claw_r" "$_claw_g" "$_claw_b"
             _claw_sgr_out="3$_claw_idx" ;;
        256) claw_theme_index256 "$_claw_r" "$_claw_g" "$_claw_b"
             _claw_sgr_out="38;5;$_claw_idx" ;;
        *)   _claw_sgr_out="38;2;$_claw_r;$_claw_g;$_claw_b" ;;
    esac
}

# claw_theme_sgr "<r;g;b>" — the full escape (empty at depth 0). Printing
# wrapper for scripts; the fork-free callers use _claw_sgr_body directly.
claw_theme_sgr() {
    _claw_sgr_body "$1"
    [ -n "$_claw_sgr_out" ] || return 0
    printf '\033[%sm' "$_claw_sgr_out"
}

# ============================================================================
# GLYPHS — CLAW_GLYPHS=ascii|nerd|auto  (audit T2-03)
# ============================================================================
# Nerd Font glyphs are load-bearing in the dashboard, the login strip and the
# profile cards, and they had no fallback: when the terminal font resets to a
# non-Nerd face (Apple Terminal does this on a profile reset) the whole screen
# becomes replacement boxes. One switch, resolved here, consumed everywhere.
#
# PRECEDENCE: $CLAW_GLYPHS (ascii|nerd win outright; auto re-detects)
#   → ${XDG_CONFIG_HOME:-~/.config}/claw/glyphs (one line: ascii|nerd|auto)
#   → auto.
# AUTO checks the ONE thing an environment can actually prove: a TERM that
# cannot possibly be carrying a Nerd Font (the Linux/BSD console, dumb, vt100,
# ansi) → ascii. Everything else → nerd. The font itself is invisible from
# inside the terminal, so `claw doctor` reads it out of the macOS Terminal
# profile and tells you what to change — auto never guesses at it.
claw_theme_glyphs() {
    _gm="${CLAW_GLYPHS:-}"
    case "$_gm" in
        ascii|nerd) export CLAW_GLYPHS="$_gm"; return 0 ;;
    esac
    if [ "$_gm" != auto ]; then
        _gf="${XDG_CONFIG_HOME:-$HOME/.config}/claw/glyphs"
        if [ -r "$_gf" ]; then
            _gv=""
            read -r _gv < "$_gf" 2>/dev/null || _gv=""
            case "$_gv" in
                ascii|nerd) export CLAW_GLYPHS="$_gv"; return 0 ;;
            esac
        fi
    fi
    # An EMPTY TERM is deliberately NOT ascii: it means "nobody told us" (cron,
    # CI, a bats run), not "a console that cannot draw glyphs" — the Linux
    # console always announces itself as TERM=linux.
    case "${TERM:-}" in
        linux|dumb|vt100|vt102|vt220|ansi|cons25|sun) _gm=ascii ;;
        *) _gm=nerd ;;
    esac
    export CLAW_GLYPHS="$_gm"
}

# Probe what the terminal can actually render and export CLAW_COLOR_DEPTH
# (24 = true colour · 256 · 8 · 0 = no colour). Apple_Terminal claims nothing
# and renders 256 only, so it is pinned regardless of what COLORTERM says.
claw_theme_depth() {
    _claw_probe_depth
    export CLAW_COLOR_DEPTH="$_pd"
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
        emit)           claw_theme_emit "$@" ;;
        depth)          claw_theme_depth; printf '%s\n' "$CLAW_COLOR_DEPTH" ;;
        render-depth)   claw_theme_render_depth; printf '%s\n' "$_claw_rdepth" ;;
        sgr)            claw_theme_sgr "${1:-}"; printf '\n' ;;
        glyphs)         claw_theme_glyphs; printf '%s\n' "$CLAW_GLYPHS" ;;
        build)          claw_theme_build ;;
        ghostty)        claw_theme_ghostty "$@" ;;
        apply)          claw_theme_apply_ghostty ;;
        reload|load)    CLAW_THEME_FORCE=1 claw_theme_load ;;
        *)              printf 'usage: theme.sh {list|current|set <slug>|preview [slug]|fzf|emit <p10k|tui|fzf|osc>|depth|render-depth|glyphs|sgr <r;g;b>|build|ghostty [slug|all]|apply|reload}\n' >&2; exit 1 ;;
    esac
fi
