# shell/claw-fn.zsh
# THE canonical claw() shell wrapper — the single zsh layer over bin/claw.
# Handles in the CURRENT shell only what must mutate it (the bash binary can't):
#   claw            → open the palette in-shell (a pick must land in THIS shell)
#   claw menu       → the same palette
#   claw load <p>   → _claw_load_profile: helpers, profile, theme, frame, cd
#   claw <p>        → shorthand for `claw load <p>` when <p> is a real profile
#   claw off        → unload the profile + restore the persisted palette
#   claw dash       → the login card
#   claw theme set  → persist the slug AND recolour this shell live
# Everything else passes through to the bash binary (bin/claw).
# Colors come from the active theme (CLAW_RGB_*, theme.sh via .zshrc step 2b);
# fallbacks are refined-dark so the wrapper renders standalone.

# Usage telemetry for `claw stats` / `claw tui-stats`: load/off are handled
# entirely in this zsh function (they mutate the shell) and never reach
# bin/claw's log_usage. Same TSV, same shape as _claw_tlog:
#   ts \t subcommand \t arg_count \t profile [\t payload]
_claw_fn_log() {
    [[ "${CLAW_NO_LOG:-}" == 1 ]] && return 0
    local _c="${XDG_CACHE_HOME:-$HOME/.cache}/claw"
    { mkdir -p "$_c" 2>/dev/null
      if [[ -n "${3-}" ]]; then
          printf '%s\t%s\t0\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:-none}" "$3" >> "$_c/usage.tsv"
      else
          printf '%s\t%s\t0\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:-none}" >> "$_c/usage.tsv"
      fi
    } 2>/dev/null || true
}

# _claw_load_profile <profile> [src]
#
# THE one load path. `claw load <p>`, the bare-profile shorthand and the
# palette all call this — the design's "ONE load path".
#
# Order matters (audit 2026-09-20 F-20): profile-helpers.zsh defines
# _claw_guard, which security/common.zsh calls at source time. The old TUI
# sourced the profile FIRST and the helpers after, so a TUI pick gave security
# half its aliases and ten `command not found: _claw_guard` lines. Helpers
# first, then the profile — and the profile's `source` rc is CHECKED, so a
# half-applied profile is rolled back rather than left exported.
_claw_load_profile() {
    local p="${1:-}" src="${2:-cmd}"
    local d="${DOTFILES_DIR:-$HOME/.dotfiles}"
    local _grn=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    local _red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    local _dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local _fg=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
    local _rst=$'\e[0m'

    if [[ -z "$p" ]]; then
        printf "  ${_red}✗${_rst} usage: claw load <profile>\n" >&2
        # The available list is DERIVED — the profile metas via registry.sh.
        # This used to be a hardcoded 18-name copy (the last one in the tree).
        local _avail
        _avail="$(command bash "$d/scripts/utils/registry.sh" ids profiles 2>/dev/null | tr '\n' ' ')"
        [[ -n "$_avail" ]] && printf "  ${_dim}available: %s${_rst}\n" "${_avail% }" >&2
        return 1
    fi

    local pfile="$d/shell/profiles/$p.zsh"
    if [[ ! -f "$pfile" ]]; then
        printf "  ${_red}✗${_rst} profile not found: %s\n" "$p" >&2
        return 1
    fi

    # F-20: helpers BEFORE the profile.
    if ! typeset -f _claw_profile_cd >/dev/null 2>&1; then
        [[ -f "$d/shell/profile-helpers.zsh" ]] && source "$d/shell/profile-helpers.zsh"
    fi

    export CLAW_ACTIVE_PROFILE="$p"
    if ! source "$pfile"; then
        printf "  ${_red}✗${_rst} ${_dim}profile failed to load: ${_fg}%s${_rst}${_dim} — nothing applied${_rst}\n" "$p" >&2
        unset CLAW_ACTIVE_PROFILE PROFILE_NAME
        _claw_fn_log load:fail "$p" "src=$src"
        return 1
    fi

    # Group for the prompt/telemetry, from the tier the profile declares.
    # Pure zsh — claw_login uses the same map and neither of us forks for it.
    case "${PROFILE_TIER:-}" in
        1) export CLAW_ACTIVE_GROUP=core ;;
        2) export CLAW_ACTIVE_GROUP=domain ;;
        3) export CLAW_ACTIVE_GROUP=agent ;;
        4) export CLAW_ACTIVE_GROUP=knowledge ;;
        5) export CLAW_ACTIVE_GROUP=customer ;;
        6) export CLAW_ACTIVE_GROUP=hardware ;;
        *) export CLAW_ACTIVE_GROUP=other ;;
    esac

    # Profile-reactive theming: the profile's declared palette for this session
    # (a no-op when PROFILE_THEME_DEFAULT is empty — F-14), then the prompt and
    # the terminal chrome. claw_theme_emit osc is gated and safe to call always.
    if typeset -f claw_theme_apply_profile >/dev/null 2>&1; then
        claw_theme_apply_profile
    fi
    if (( ${+functions[claw_theme_emit]} )); then
        eval "$(claw_theme_emit p10k)"
        (( ${+functions[p10k]} )) && p10k reload
        claw_theme_emit osc
    fi

    # ONE framed screen (F-23): claw-dashboard.py --profile is the render path
    # for every profile, not just the one that had bespoke art. The PROFILE_*
    # set comes from the meta.zsh just sourced; the renderer never sources zsh.
    # CLAW_PROFILE_ART=fastfetch keeps the old per-profile jsonc art.
    local _rendered=0
    if [[ -o interactive ]]; then
        local _dash="$d/scripts/utils/claw-dashboard.py"
        if [[ "${CLAW_PROFILE_ART:-frame}" == frame ]] && \
           command -v python3 &>/dev/null && [[ -f "$_dash" ]]; then
            PROFILE_CLASS="${PROFILE_CLASS:-}" \
            PROFILE_GLYPH="${PROFILE_GLYPH:-}" \
            PROFILE_TAG="${PROFILE_TAG:-}" \
            PROFILE_KEY_TOOLS="${PROFILE_KEY_TOOLS:-}" \
            PROFILE_TOOLCHAIN="${PROFILE_TOOLCHAIN:-}" \
            PROFILE_HELP_CMD="${PROFILE_HELP_CMD:-}" \
            DOTFILES_DIR="$d" \
            python3 "$_dash" --profile "$p" && _rendered=1
        else
            local _ff="$d/config/.config/fastfetch/config-$p.jsonc"
            # claw_ff = kitty/iterm raster logo in Ghostty/Kitty/iTerm, text fallback elsewhere.
            if typeset -f claw_ff &>/dev/null; then
                claw_ff "$p" "$_ff" && _rendered=1
            elif command -v fastfetch &>/dev/null && [[ -f "$_ff" ]]; then
                fastfetch -c "$_ff" 2>/dev/null && _rendered=1
            fi
        fi
    fi
    # The frame carries the class, tag, key tools and help card, so the old
    # inline "loaded profile"/tag/missing-tools lines are gone with it. Without
    # a frame (non-interactive, no python3, no fastfetch) still say what happened.
    if (( ! _rendered )); then
        printf "  ${_grn}✓${_rst} loaded profile: ${_fg}%s${_rst}" "$p"
        [[ -n "${CLAW_THEME:-}" ]] && printf "  ${_dim}· theme ${_fg}%s${_rst}" "$CLAW_THEME"
        printf "\n"
    fi

    # Land in the profile's declared start dir (PROFILE_START_DIR in meta.zsh).
    # ONE applier for every load path — see shell/profile-helpers.zsh. cd - undoes it.
    if typeset -f _claw_profile_cd >/dev/null 2>&1; then
        _claw_profile_cd "$p"
    fi
    # Optional: drop a breadcrumb into the active vault's daily note.
    # Gated by CLAW_VAULT_BREADCRUMBS=1; obsidian.zsh defines the fn.
    if typeset -f _claw_vault_breadcrumb &>/dev/null; then
        _claw_vault_breadcrumb
    fi

    typeset -f _claw_frecency_bump >/dev/null 2>&1 && _claw_frecency_bump "$p"
    _claw_fn_log load "$p" "src=$src"
    return 0
}

claw() {
    local _grn=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    local _red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    local _dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local _fg=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
    local _amb=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    local _rst=$'\e[0m'
    local _d="${DOTFILES_DIR:-$HOME/.dotfiles}"

    # Bare-profile shorthand: `claw security` == `claw load security`.
    # Only rewrites when the arg is an actual profile file, so agents and
    # subcommands are never shadowed.
    if [[ -n "${1:-}" && "$1" != "load" && -f "$_d/shell/profiles/$1.zsh" ]]; then
        set -- load "$@"
    fi
    case "${1:-}" in
        ""|menu)
            # The palette runs in THIS shell so a pick can mutate it (bin/claw
            # menu runs in a child zsh, where it cannot). Never on the login
            # path — only here, after a prompt exists (F-06).
            if [[ -o interactive ]] && typeset -f claw_palette >/dev/null 2>&1; then
                claw_palette --src=cmd
            else
                command claw menu
            fi
            ;;
        load)
            shift
            _claw_load_profile "${1:-}" cmd
            ;;
        dash)
            shift
            local _dash="$_d/scripts/utils/claw-dashboard.py"
            if command -v python3 &>/dev/null && [[ -f "$_dash" ]]; then
                DOTFILES_DIR="$_d" python3 "$_dash" --login "$@"
            else
                command claw dash "$@"
            fi
            ;;
        off)
            if [[ -z "${CLAW_ACTIVE_PROFILE:-}" ]]; then
                printf "  ${_dim}○ no profile loaded${_rst}\n"
                return 0
            fi
            local _was="$CLAW_ACTIVE_PROFILE"
            unset CLAW_ACTIVE_PROFILE
            # Restore the user's persisted palette (drop any profile override).
            if typeset -f claw_theme_reset_session >/dev/null 2>&1; then
                claw_theme_reset_session
            fi
            if (( ${+functions[claw_theme_emit]} )); then
                eval "$(claw_theme_emit p10k)"
                (( ${+functions[p10k]} )) && p10k reload
                claw_theme_emit osc
            fi
            printf "  ${_grn}✓${_rst} unloaded profile: ${_fg}%s${_rst}\n" "$_was"
            _claw_fn_log off "$_was"
            printf "  ${_dim}  (aliases/exports still defined; ${_fg}exec zsh${_dim} for a clean shell)${_rst}\n"
            ;;
        theme|themes|colors)
            shift
            case "${1:-}" in
                set|use)
                    command claw theme set "${@:2}" || return $?
                    # Live recolour: the persisted slug is already written, now
                    # make THIS shell agree — theme.sh is POSIX and cannot call
                    # `p10k reload`, so the zsh half of the sequence lives here.
                    if typeset -f claw_theme_load >/dev/null 2>&1; then
                        CLAW_THEME_FORCE=1 claw_theme_load
                    fi
                    if (( ${+functions[claw_theme_emit]} )); then
                        eval "$(claw_theme_emit p10k)"
                        (( ${+functions[p10k]} )) && p10k reload
                        claw_theme_emit osc
                    fi
                    ;;
                *)
                    command claw theme "$@"
                    ;;
            esac
            ;;
        *)
            command claw "$@"
            ;;
    esac
}

# The palette (and with it _claw_apply_outcome, _claw_action, _claw_frecency_bump
# and the ^G widget) rides on claw(): it is sourced here, right after the
# dispatcher exists — which is .zshrc step 6, where the design puts it.
[[ -f "${DOTFILES_DIR:-$HOME/.dotfiles}/shell/claw-palette.zsh" ]] && \
    source "${DOTFILES_DIR:-$HOME/.dotfiles}/shell/claw-palette.zsh"
