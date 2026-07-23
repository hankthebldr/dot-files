# shell/claw-fn.zsh
# THE canonical claw() shell wrapper — the single zsh layer over bin/claw.
# Handles in the CURRENT shell only what must mutate it (the bash binary can't):
#   claw            → relaunch the welcome TUI in-shell (profile picks persist)
#   claw load <p>   → source the profile + export CLAW_ACTIVE_PROFILE
#                     + apply the profile's palette for this session
#   claw <p>        → shorthand for `claw load <p>` when <p> is a real profile
#   claw off        → unload the profile + restore the persisted palette
# Everything else passes through to the bash binary (bin/claw).
# Colors come from the active theme (CLAW_RGB_*, theme.sh via .zshrc step 2b);
# fallbacks are refined-dark so the wrapper renders standalone.

# Usage telemetry for `claw stats`: load/off are handled entirely in this zsh
# function (they mutate the shell) and never reach bin/claw's log_usage. Record
# them in the same TSV (ts \t subcommand \t arg_count \t profile).
_claw_fn_log() {
    [[ "${CLAW_NO_LOG:-}" == 1 ]] && return 0
    local _c="${XDG_CACHE_HOME:-$HOME/.cache}/claw"
    { mkdir -p "$_c" 2>/dev/null
      printf '%s\t%s\t0\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:-none}" >> "$_c/usage.tsv"
    } 2>/dev/null || true
}

claw() {
    local _grn=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    local _red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    local _dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local _fg=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
    local _amb=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    local _rst=$'\e[0m'

    # Bare-profile shorthand: `claw security` == `claw load security`.
    # Only rewrites when the arg is an actual profile file, so agents and
    # subcommands are never shadowed.
    if [[ -n "${1:-}" && "$1" != "load" && \
          -f "${DOTFILES_DIR:-$HOME/.dotfiles}/shell/profiles/$1.zsh" ]]; then
        set -- load "$@"
    fi
    case "${1:-}" in
        "")
            # No args: relaunch the FZF welcome TUI in THIS shell so a profile
            # pick lands in the current session (bin/claw menu runs in a child
            # zsh, where a pick can't mutate this shell).
            local _wt="${DOTFILES_DIR:-$HOME/.dotfiles}/shell/welcome-tui.zsh"
            if [[ -o interactive && -f "$_wt" ]]; then
                unset CLAW_ACTIVE_PROFILE
                source "$_wt"
                claw_welcome_tui
            else
                command claw
            fi
            ;;
        load)
            shift
            local p="${1:-}"
            if [[ -z "$p" ]]; then
                printf "  ${_red}✗${_rst} usage: claw load <profile>\n" >&2
                printf "  ${_dim}available: default local claude cloud devops security cortex ai research vault brainstorm pmo deck design demo homelab blackwell tunnels${_rst}\n" >&2
                return 1
            fi
            local pfile="${DOTFILES_DIR:-$HOME/.dotfiles}/shell/profiles/$p.zsh"
            if [[ ! -f "$pfile" ]]; then
                printf "  ${_red}✗${_rst} profile not found: %s\n" "$p" >&2
                return 1
            fi
            export CLAW_ACTIVE_PROFILE="$p"
            source "$pfile"
            # Profile-reactive theming: apply the profile's declared palette
            # (PROFILE_THEME_DEFAULT from meta.zsh) for this session only.
            # theme.sh guards on the palette actually existing.
            if typeset -f claw_theme_apply_profile >/dev/null 2>&1; then
                claw_theme_apply_profile
            fi
            printf "  ${_grn}✓${_rst} loaded profile: ${_fg}%s${_rst}" "$p"
            [[ -n "${CLAW_THEME:-}" ]] && printf "  ${_dim}· theme ${_fg}%s${_rst}" "$CLAW_THEME"
            printf "\n"
            _claw_fn_log load "$p"
            # per-profile MOTD: the profile's flavor tag (set in meta.zsh)
            [[ -n "${PROFILE_TAG:-}" ]] && printf "  ${_dim}%s${_rst}\n" "$PROFILE_TAG"
            # load↔install bridge: nudge if the profile's key tools aren't present.
            if [[ -n "${PROFILE_KEY_TOOLS:-}" ]]; then
                local _miss=() _t
                for _t in ${(s: :)PROFILE_KEY_TOOLS}; do
                    command -v "$_t" &>/dev/null || _miss+=("$_t")
                done
                if (( ${#_miss[@]} )); then
                    local _tc="${PROFILE_TOOLCHAIN%-toolchain.sh}"
                    if [[ -n "$_tc" ]]; then
                        printf "  ${_amb}●${_rst} ${_dim}%d tool(s) missing (%s) — ${_fg}claw install %s${_rst}\n" "${#_miss[@]}" "${_miss[*]}" "$_tc"
                    else
                        printf "  ${_amb}●${_rst} ${_dim}%d tool(s) missing (%s)${_rst}\n" "${#_miss[@]}" "${_miss[*]}"
                    fi
                fi
            fi
            # Optional: drop a breadcrumb into the active vault's daily note.
            # Gated by CLAW_VAULT_BREADCRUMBS=1; obsidian.zsh defines the fn.
            if typeset -f _claw_vault_breadcrumb &>/dev/null; then
                _claw_vault_breadcrumb
            fi
            # Render the profile dashboard inline (skip if non-interactive)
            if [[ -o interactive ]]; then
                local _ff="${DOTFILES_DIR:-$HOME/.dotfiles}/config/.config/fastfetch/config-$p.jsonc"
                # claw_ff = kitty/iterm raster logo in Ghostty/Kitty/iTerm, text fallback elsewhere.
                if typeset -f claw_ff &>/dev/null; then claw_ff "$p" "$_ff"
                else command -v fastfetch &>/dev/null && [[ -f "$_ff" ]] && fastfetch -c "$_ff" 2>/dev/null; fi
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
            printf "  ${_grn}✓${_rst} unloaded profile: ${_fg}%s${_rst}\n" "$_was"
            _claw_fn_log off "$_was"
            printf "  ${_dim}  (aliases/exports still defined; ${_fg}exec zsh${_dim} for a clean shell)${_rst}\n"
            ;;
        *)
            command claw "$@"
            ;;
    esac
}
