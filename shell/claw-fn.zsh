# shell/claw-fn.zsh
# THE canonical claw() shell wrapper — the single zsh layer over bin/claw.
# Handles in the CURRENT shell only what must mutate it (the bash binary can't):
#   claw            → relaunch the welcome TUI in-shell (profile picks persist)
#   claw load <p>   → source the profile + export CLAW_ACTIVE_PROFILE
#   claw <p>        → shorthand for `claw load <p>` when <p> is a real profile
#   claw off        → unload the profile
# Everything else passes through to the bash binary (bin/claw).

claw() {
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
                unset CLAW_ACTIVE_PROFILE CLAW_PROFILE_THEME
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
                printf "  \e[38;2;255;123;114m✗\e[0m usage: claw load <profile>\n" >&2
                printf "  \e[38;2;139;148;158mavailable: default local claude cloud devops security cortex ai research vault brainstorm pmo deck design demo homelab blackwell tunnels\e[0m\n" >&2
                return 1
            fi
            local pfile="${DOTFILES_DIR:-$HOME/.dotfiles}/shell/profiles/$p.zsh"
            if [[ ! -f "$pfile" ]]; then
                printf "  \e[38;2;255;123;114m✗\e[0m profile not found: %s\n" "$p" >&2
                return 1
            fi
            export CLAW_ACTIVE_PROFILE="$p"
            source "$pfile"
            printf "  \e[38;2;63;185;80m✓\e[0m loaded profile: \e[38;2;201;209;217m%s\e[0m\n" "$p"
            # per-profile MOTD: the profile's flavor tag (set in meta.zsh)
            [[ -n "${PROFILE_TAG:-}" ]] && printf "  \e[38;2;139;148;158m%s\e[0m\n" "$PROFILE_TAG"
            # load↔install bridge: nudge if the profile's key tools aren't present.
            if [[ -n "${PROFILE_KEY_TOOLS:-}" ]]; then
                local _miss=() _t
                for _t in ${(s: :)PROFILE_KEY_TOOLS}; do
                    command -v "$_t" &>/dev/null || _miss+=("$_t")
                done
                (( ${#_miss[@]} )) && printf "  \e[38;2;227;179;65m●\e[0m \e[38;2;139;148;158m%d tool(s) missing (%s) — \e[38;2;201;209;217mclaw install %s\e[0m\n" "${#_miss[@]}" "${_miss[*]}" "$p"
            fi
            # Optional: drop a breadcrumb into the active vault's daily note.
            # Gated by CLAW_VAULT_BREADCRUMBS=1; obsidian.zsh defines the fn.
            if typeset -f _claw_vault_breadcrumb &>/dev/null; then
                _claw_vault_breadcrumb
            fi
            # Render the profile dashboard inline (skip if non-interactive)
            if [[ -o interactive ]]; then
                local _ff="${DOTFILES_DIR:-$HOME/.dotfiles}/config/.config/fastfetch/config-$p.jsonc"
                command -v fastfetch &>/dev/null && [[ -f "$_ff" ]] && fastfetch -c "$_ff" 2>/dev/null
            fi
            ;;
        off)
            if [[ -z "${CLAW_ACTIVE_PROFILE:-}" ]]; then
                printf "  \e[38;2;139;148;158m○ no profile loaded\e[0m\n"
                return 0
            fi
            local _was="$CLAW_ACTIVE_PROFILE"
            unset CLAW_ACTIVE_PROFILE
            printf "  \e[38;2;63;185;80m✓\e[0m unloaded profile: \e[38;2;201;209;217m%s\e[0m\n" "$_was"
            printf "  \e[38;2;139;148;158m  (aliases/exports still defined; \e[38;2;201;209;217mexec zsh\e[38;2;139;148;158m for a clean shell)\e[0m\n"
            ;;
        *)
            command claw "$@"
            ;;
    esac
}
