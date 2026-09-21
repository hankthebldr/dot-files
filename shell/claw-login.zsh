# shell/claw-login.zsh — the login path: DECIDE, then render.
#
# Sourced from .zshrc step 2b. `claw_login` may only DECIDE: resolve the mode,
# the profile, the theme and the group, export them, and register a ONE-SHOT
# precmd hook. Everything that renders, probes or touches the terminal runs
# from that hook, AFTER the rc has finished and the shell is complete.
#
# Why (audit 2026-09-20):
#   F-03  the old step-3 block asked "which profile?" — a question whose answer
#         is the same 91% of the time. It is now pinned data, not a prompt.
#   F-02  85% of shells are agents and IDE panels. They get no render, no
#         background probes, and not a single byte of output.
#   F-01  an interrupt during the render used to kill .zshrc mid-file (no
#         aliases, no claw(), no p10k). The render now runs after the rc.
#   F-06  nothing on the login path reads stdin, so typed-ahead text stays
#         typed-ahead text instead of being eaten as a menu pick.
#   F-21  _CLAW_FRESH_LOGIN is deliberately NOT exported — that is what stops
#         tmux panes, `nvim :terminal` and `exec zsh` being relocated.
#
# Contract: pure zsh, no forks, no output. Functions that return a value set
# $REPLY (capturing with $(...) would fork, which is the whole point).
#
# Env knobs:
#   CLAW_LOGIN_PROFILE   pin the profile for this shell (beats the pin file)
#   CLAW_LOGIN_CARD      always | daily (default) | never
#   CLAW_LOGIN_RENDER    0 disables the render hook's body entirely
#   CLAW_ACTOR           force the actor (human|agent|ide|ssh|unknown)
#   CLAW_LOGIN_TERMS     extra space-separated TERM_PROGRAM values = human
#   CLAW_LOGIN_FORCE_TTY 1 bypasses the interactive/tty guards (test hook)
#   CLAW_NO_LOG          1 suppresses every telemetry row

# ── telemetry ────────────────────────────────────────────────────────────────
# One append-only TSV row: ISO-ts \t event \t argc \t profile [\t k=v;k=v].
# The 4-column readers (bin/claw stats) still parse it. Fork-free: zsh/datetime
# instead of date(1), and mkdir only when the cache dir is genuinely absent.
# Every error is swallowed — a broken log must never break a login.
_claw_tlog() {
    [[ "${CLAW_NO_LOG:-0}" == 1 ]] && return 0
    emulate -L zsh
    local TZ=UTC ts dir="${XDG_CACHE_HOME:-$HOME/.cache}/claw"
    zmodload -i zsh/datetime 2>/dev/null || return 0
    strftime -s ts '%Y-%m-%dT%H:%M:%SZ' $EPOCHSECONDS 2>/dev/null || return 0
    [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null || return 0
    if [[ -n "${2-}" ]]; then
        print -r -- "$ts	${1:-tui:unknown}	0	${CLAW_ACTIVE_PROFILE:-none}	$2" >> "$dir/usage.tsv" 2>/dev/null
    else
        print -r -- "$ts	${1:-tui:unknown}	0	${CLAW_ACTIVE_PROFILE:-none}" >> "$dir/usage.tsv" 2>/dev/null
    fi
    return 0
}

# ── who is at the other end of this pty? ─────────────────────────────────────
# Sets $REPLY to agent | ide | ssh | human | unknown. Order is precedence:
# an agent driving a real Apple Terminal pty (Claude Desktop) is still an agent.
_claw_actor() {
    emulate -L zsh
    if [[ -n "${CLAW_ACTOR:-}" ]]; then
        REPLY="$CLAW_ACTOR"
        return 0
    fi
    # Claude Code sets both; either alone is enough (verified in a Claude
    # Desktop pty, where TERM_PROGRAM is a perfectly human-looking terminal).
    if [[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]]; then
        REPLY=agent
        return 0
    fi
    local tp="${(L)TERM_PROGRAM:-}"
    case "$tp" in
        vscode*|cursor*|antigravity*|jetbrains*) REPLY=ide; return 0 ;;
    esac
    if [[ -n "${SSH_TTY:-}" || -n "${SSH_CONNECTION:-}" ]]; then
        REPLY=ssh
        return 0
    fi
    case "${TERM_PROGRAM:-}" in
        Apple_Terminal|ghostty|iTerm.app|WezTerm|kitty) REPLY=human; return 0 ;;
    esac
    local t
    for t in ${(s: :)CLAW_LOGIN_TERMS:-}; do
        [[ "$t" == "${TERM_PROGRAM:-}" ]] && { REPLY=human; return 0 }
    done
    if [[ -n "${VTE_VERSION:-}" || -n "${KITTY_WINDOW_ID:-}" ]]; then
        REPLY=human
        return 0
    fi
    REPLY=unknown
    return 0
}

# Sets $REPLY to the login mode: `nested` when this shell already inherited a
# profile (a tmux pane, `exec zsh`, a subshell), else the actor.
_claw_login_mode() {
    if [[ -n "${CLAW_ACTIVE_PROFILE:-}" ]]; then
        REPLY=nested
        return 0
    fi
    _claw_actor
}

# ── meta.zsh field reader (no fork) ──────────────────────────────────────────
# _claw_meta_field <profile> <PROFILE_VAR> → $REPLY (empty when absent).
# The grammar is lint-enforced (profiles-lint.sh): one field per line,
# PROFILE_X="value" with an optional trailing `# comment`. Values are RAW and
# unexpanded — PROFILE_START_DIR's ${VAR:-…} and `a|b` alternatives belong to
# _claw_profile_cd, not to this reader.
_claw_meta_field() {
    emulate -L zsh
    REPLY=""
    local f="${DOTFILES_DIR:-$HOME/.dotfiles}/shell/profiles/$1/meta.zsh" line
    [[ -r "$f" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" == "$2="\"* ]] || continue
        line="${line#$2=\"}"
        REPLY="${line%%\"*}"
        return 0
    done < "$f"
    return 0
}

# PROFILE_TIER → the group name the registry and the palette use.
_claw_login_group() {
    _claw_meta_field "$1" PROFILE_TIER
    case "$REPLY" in
        1) REPLY=core ;;
        2) REPLY=domain ;;
        3) REPLY=agent ;;
        4) REPLY=knowledge ;;
        5) REPLY=customer ;;
        6) REPLY=hardware ;;
        *) REPLY=other ;;
    esac
}

# ── the decision ─────────────────────────────────────────────────────────────
claw_login() {
    emulate -L zsh

    if [[ "${CLAW_LOGIN_FORCE_TTY:-0}" != 1 ]]; then
        # SAFETY (verbatim from the retiring welcome-tui.zsh): never in
        # non-interactive shells (breaks scp, rsync, git-over-ssh), never with
        # piped stdin, never inside an SSH session that is piping data.
        [[ ! -o interactive ]] && return 0
        [[ ! -t 0 ]] && return 0
        [[ -n "$SSH_CONNECTION" && ! -t 1 ]] && return 0
    fi
    [[ "$TERM" == dumb ]] && return 0

    _claw_login_mode
    local mode="$REPLY"

    # A nested shell inherited its profile: no render, no relocation, no row.
    if [[ "$mode" == nested ]]; then
        typeset -g _CLAW_FRESH_LOGIN=0
        return 0
    fi

    # Profile: explicit pin → per-machine pin file → default. A pin naming a
    # profile this checkout does not have is not a profile.
    local d="${DOTFILES_DIR:-$HOME/.dotfiles}"
    local p="${CLAW_LOGIN_PROFILE:-}"
    if [[ -z "$p" ]]; then
        local pin="${XDG_CONFIG_HOME:-$HOME/.config}/claw/login-profile"
        [[ -r "$pin" ]] && read -r p < "$pin"
    fi
    p="${p//[[:space:]]/}"
    [[ -z "$p" || ! -f "$d/shell/profiles/$p.zsh" ]] && p=default
    export CLAW_ACTIVE_PROFILE="$p"

    # Theme: the profile's declared palette, only when it really exists.
    # F-14 — default/local/claude declare "" and inherit the persisted slug,
    # so an empty value must NOT clobber CLAW_THEME.
    _claw_meta_field "$p" PROFILE_THEME_DEFAULT
    local t="$REPLY"
    if [[ -n "$t" ]] && \
       [[ -r "$d/config/themes/$t/palette.theme" || -r "$d/config/themes/$t.theme" ]]; then
        export CLAW_THEME="$t"
    fi

    _claw_login_group "$p"
    export CLAW_ACTIVE_GROUP="$REPLY"

    zmodload -i zsh/datetime 2>/dev/null
    # NOT exported, on purpose (F-21): a tmux pane, `nvim :terminal` or
    # `exec zsh` inherits the profile but not the flag, so step 8 leaves its
    # cwd alone. A pid check would not work — `exec zsh` keeps the pid.
    typeset -g _CLAW_FRESH_LOGIN=1 _CLAW_LOGIN_MODE="$mode" _CLAW_LOGIN_T0="${EPOCHREALTIME:-0}"

    # F-02: an agent shell renders nothing and probes nothing. One row so
    # `claw tui-stats` can still count the shells it suppressed.
    if [[ "$mode" == agent ]]; then
        _claw_tlog "tui:login:agent:$p" "term=${TERM_PROGRAM:-$TERM};actor=agent"
        return 0
    fi

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _claw_login_render
    # Armed here, disarmed by the render hook: a shell that exits before its
    # first prompt aborted the login somewhere in steps 4-8.
    add-zsh-hook zshexit _claw_login_abort
    return 0
}

_claw_login_abort() { _claw_tlog tui:abort:init }

# ── the render (body lands in T1-07b) ────────────────────────────────────────
_claw_login_render() {
    add-zsh-hook -d precmd _claw_login_render
    add-zsh-hook -d zshexit _claw_login_abort
    trap - INT
    return 0
}
