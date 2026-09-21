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

autoload -Uz add-zsh-hook

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
# True when this shell is one a PERSON is looking at, i.e. a login-path renderer
# may print. agent/ide shells are opened by tooling (Claude Desktop, IDE panels)
# and nested shells already showed their login — neither gets output. An
# unrecognised terminal is treated as human so a new terminal degrades to
# visible-but-plain, never to silence (audit F-02).
_claw_login_is_human() {
    case "${_CLAW_LOGIN_MODE:-unknown}" in
        agent|ide|nested) return 1 ;;
        *)                return 0 ;;
    esac
}

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
        # SAFETY (carried over from the retired fzf login menu, now legacy/): never in
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
    # Pin the tree the login was decided from. shell/exports.zsh re-exports
    # DOTFILES_DIR at step 6 as the fully resolved path (${0:A:h:h}), so by the
    # time the hook fires $DOTFILES_DIR can name a different path to the same
    # checkout. The render must use the tree the rc actually loaded.
    typeset -g _CLAW_LOGIN_DOTFILES="$d"
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

# ── the attention strip ──────────────────────────────────────────────────────
# Reads the one attention file situation.sh writes (tier, id, text, hint,
# since_epoch, src_epoch — already sorted crit→warn→info, acked rows already
# dropped) and prints at most three lines. Silent when everything is clear: a
# login that says nothing is a login that says "nothing is wrong".
# Sets _CLAW_STRIP_ITEMS (rows in the file) and _CLAW_STRIP_LINES (lines
# printed, including the overflow line) for the telemetry row.
_claw_attention_strip() {
    emulate -L zsh
    typeset -g _CLAW_STRIP_LINES=0 _CLAW_STRIP_ITEMS=0
    local f="${XDG_CACHE_HOME:-$HOME/.cache}/claw/attention.tsv"
    [[ -s "$f" ]] || return 0
    zmodload -i zsh/datetime 2>/dev/null

    local rst=$'\e[0m'
    local c_red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    local c_amb=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    local c_blue=$'\e[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"$'m'
    local c_fg=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
    local c_mut=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local plain=0
    [[ -n "${NO_COLOR:-}" ]] && plain=1

    local -a out row
    local tier id text hint since src mark tone age hhmm line
    local rows=0 want=0 shown=0 delta
    # NOT `IFS=$'\t' read -r a b c ...`: tab is IFS whitespace, so read would
    # collapse the two tabs around an empty hint and shift every later column.
    # Splitting the raw line keeps the empty fields where they belong.
    while IFS= read -r line; do
        row=("${(@ps:\t:)line}")
        tier="${row[1]}" id="${row[2]}" text="${row[3]}"
        hint="${row[4]}" since="${row[5]}" src="${row[6]}"
        [[ -z "$tier" ]] && continue
        (( rows++ ))
        # An info item with no next action is noise on a login line; it still
        # shows on the card, which has room to explain itself.
        [[ "$tier" == info && -z "$hint" ]] && continue
        (( want++ ))
        (( shown >= 3 )) && continue
        case "$tier" in
            crit) mark='!'; tone="$c_red" ;;
            warn) mark='~'; tone="$c_amb" ;;
            *)    mark='i'; tone="$c_blue" ;;
        esac
        age=""
        if [[ "$src" == <-> ]]; then
            delta=$(( EPOCHSECONDS - src ))
            (( delta < 0 )) && delta=0
            if   (( delta < 60 ));    then age="${delta}s"
            elif (( delta < 3600 ));  then age="$(( delta / 60 ))m"
            elif (( delta < 86400 )); then age="$(( delta / 3600 ))h"
            else                           age="$(( delta / 86400 ))d"
            fi
            # `since` is when the item first appeared, `src` when the cache it
            # came from was last written — they differ once a probe re-confirms
            # something that has been broken for a while.
            if [[ "$since" == <-> && "$since" != "$src" ]] && \
               strftime -s hhmm '%H:%M' "$since" 2>/dev/null; then
                age="$age · since $hhmm"
            fi
        fi
        if (( plain )); then
            line="  $mark $text"
            [[ -n "$hint" ]] && line="$line  $hint"
            [[ -n "$age"  ]] && line="$line  ($age)"
        else
            line="  ${tone}●${rst} ${c_fg}${text}${rst}"
            [[ -n "$hint" ]] && line="$line  ${c_mut}${hint}${rst}"
            [[ -n "$age"  ]] && line="$line  ${c_mut}(${age})${rst}"
        fi
        out+=("$line")
        (( shown++ ))
    done < "$f"

    _CLAW_STRIP_ITEMS=$rows
    (( ${#out} )) || return 0
    print -rl -- "${out[@]}"
    _CLAW_STRIP_LINES=${#out}
    if (( want > shown )); then
        if (( plain )); then
            print -r -- "  +$(( want - shown )) more · claw dash"
        else
            print -r -- "  ${c_mut}+$(( want - shown )) more · claw dash${rst}"
        fi
        (( _CLAW_STRIP_LINES++ ))
    fi
    return 0
}

# ── the render ───────────────────────────────────────────────────────────────
# Runs from the FIRST precmd, so aliases, claw(), completion and p10k already
# exist. An interrupt here costs you the render and nothing else (F-01).
_claw_login_render() {
    # FIRST, unconditionally: this hook can never fire twice.
    add-zsh-hook -d precmd _claw_login_render
    add-zsh-hook -d zshexit _claw_login_abort
    # Belt for the braces in .zshrc's last line: whatever happened during the
    # rc, Ctrl-C belongs to the user from here on.
    trap - INT
    [[ "${CLAW_LOGIN_RENDER:-1}" == 0 ]] && return 0

    emulate -L zsh
    setopt localtraps
    # `return` aborts the function, so the log call lives INSIDE the trap
    # string — as a following statement it would never run.
    trap '_claw_tlog tui:abort:render; return 130' INT

    local d="${_CLAW_LOGIN_DOTFILES:-${DOTFILES_DIR:-$HOME/.dotfiles}}"
    local mode="${_CLAW_LOGIN_MODE:-unknown}"
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/claw"

    _claw_attention_strip

    # ── daily card ──────────────────────────────────────────────────────────
    # One card per day per machine, not per tab.
    #
    # The day is CLAIMED by writing the stamp before the render, not after:
    # ten tabs opened together otherwise all read yesterday during the ~120 ms
    # the card takes to draw and all draw it. Claiming first shrinks that
    # window to two syscalls. `zsystem flock` closes it completely where the
    # module exists — and the whole check-claim sequence stays inside the block
    # that took the lock, because zsh drops a `flock -f` descriptor when the
    # enclosing compound command finishes.
    local card=0 want="${CLAW_LOGIN_CARD:-daily}" today="" stamp="$cache/card.stamp"
    if [[ "$mode" == human && "$want" != never ]]; then
        zmodload -i zsh/datetime 2>/dev/null
        strftime -s today '%Y%m%d' $EPOCHSECONDS 2>/dev/null
        if [[ "$want" == always ]]; then
            card=1
        elif [[ -n "$today" ]]; then
            [[ -d "$cache" ]] || mkdir -p "$cache" 2>/dev/null
            [[ -e "$stamp" ]] || : >| "$stamp" 2>/dev/null
            zmodload -F zsh/system b:zsystem 2>/dev/null
            local fd="" prev=""
            if (( $+builtins[zsystem] )) && zsystem flock -t 1 -f fd "$stamp" 2>/dev/null; then
                read -r prev < "$stamp" 2>/dev/null
                if [[ "$prev" != "$today" ]]; then
                    print -r -- "$today" >| "$stamp" 2>/dev/null && card=1
                fi
                exec {fd}>&-
            else
                read -r prev < "$stamp" 2>/dev/null
                if [[ "$prev" != "$today" ]]; then
                    print -r -- "$today" >| "$stamp" 2>/dev/null && card=1
                fi
            fi
        fi
    fi
    # Inline on purpose: a `trap ... INT` handler runs in the context of the
    # function that was executing when the signal arrived, so `return 130` has
    # to be able to return from THIS function. Wrapping the card in a helper
    # would abort the helper and let the render carry on.
    # `cmd || card=0` would swallow the trap's status: an INT during the card
    # still aborts the render, but the function would report 0.
    if (( card )); then
        DOTFILES_DIR="$d" python3 "$d/scripts/utils/claw-dashboard.py" --login
        (( $? )) && card=0
    fi

    # ── background kicks ────────────────────────────────────────────────────
    # Only where a person will see the result (F-02). All four are throttled
    # and single-flighted by their own scripts; `&!` disowns so no job-control
    # notice bleeds over the card.
    if [[ "$mode" == human || "$mode" == ssh ]]; then
        nice -n 10 bash "$d/scripts/utils/situation.sh" homelab &>/dev/null &!
        nice -n 10 bash "$d/scripts/utils/situation.sh" local &>/dev/null &!
        "$d/scripts/utils/update-status.sh" --refresh &>/dev/null &!
        "$d/scripts/utils/tool-updater.sh" &>/dev/null &!
    fi

    # Terminal chrome follows the palette — the emitter's own gate makes this a
    # no-op on SSH, under tmux, and on terminals that do not answer OSC.
    if [[ "$mode" == human ]] && (( $+functions[claw_theme_emit] )); then
        claw_theme_emit osc
    fi

    local actor ms=0
    _claw_actor
    actor="$REPLY"
    if [[ -n "${_CLAW_LOGIN_T0:-}" && -n "${EPOCHREALTIME:-}" ]]; then
        ms=$(( (EPOCHREALTIME - _CLAW_LOGIN_T0) * 1000 ))
        ms="${ms%%.*}"
        [[ "$ms" == <-> ]] || ms=0
    fi
    _claw_tlog "tui:login:$mode:${CLAW_ACTIVE_PROFILE:-none}" \
        "term=${TERM_PROGRAM:-$TERM};actor=$actor;shell=${CLAW_SESSION_SEQ:-0};ms=$ms;items=${_CLAW_STRIP_ITEMS:-0};strip=${_CLAW_STRIP_LINES:-0};card=$card"
    return 0
}
