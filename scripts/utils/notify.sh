#!/usr/bin/env bash
# scripts/utils/notify.sh — OPEN CLAW single cross-platform notification engine.
#
# The SPINE for desktop notifications: one place that knows how to reach the
# desktop on macOS (terminal-notifier → osascript) and Linux (notify-send),
# with a stderr fallback so scripts never lose the message. Every surface that
# wants to alert the operator routes through here instead of hand-rolling an
# osascript/notify-send call:
#   - bin/claw               → `claw notify …`  (user-facing, scriptable)
#   - shell/platform.zsh     → claw_notify()    (interactive shim / `notify` alias)
#   - scripts/utils/situation.sh → notify()     (the fleet interrupt tier)
#
# WHY this exists: crit vs info had NO difference on macOS (both a silent,
# identical banner) while Linux gave crit a persistent `urgency=critical` red
# banner. That broke the "interrupt tier that can't become wallpaper" design on
# MBP. This engine gives macOS crit a sound + "⚠ CRITICAL" subtitle so the two
# platforms behave the same.
#
# Subcommands:
#   send [flags] [TITLE] [BODY]     fire one notification (default subcommand)
#   after [flags] -- CMD [ARGS…]    run CMD, notify on completion (exit + duration)
#   help
#
# send flags:
#   --crit | --critical      urgency=critical (red/persistent on Linux, sound on macOS)
#   --info                   urgency=normal (default)
#   --sound NAME             override the sound (macOS sound name / any truthy on Linux)
#   --icon ICON              Linux notify-send icon (default: utilities-terminal)
#   --title TITLE            set the title explicitly (else first positional)
#   --subtitle SUB           macOS subtitle line (default derived from urgency)
#   --app NAME               app name (default: "Open Claw")
#
# after flags: same urgency/sound flags, plus
#   --label LABEL            human label for the command (default: the command)
#   --crit-on-fail           escalate to crit urgency when CMD exits non-zero
#
# Portable across macOS (terminal-notifier/osascript) and Linux (notify-send).
# Runs under launchd/systemd with a minimal PATH — no dependency on the shell.
set -u

APP_DEFAULT="Open Claw"

# ── low-level: escape a string for embedding inside an AppleScript "…" literal.
_osa_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# ── the one desktop dispatch. Args are already-parsed named locals.
# _emit <urgency> <app> <title> <subtitle> <body> <sound> <icon>
_emit() {
    local urg="$1" app="$2" title="$3" sub="$4" body="$5" sound="$6" icon="$7"
    case "$(uname -s)" in
        Darwin)
            # macOS: crit MUST be distinguishable from info — sound + subtitle.
            # Default the sound only for crit (info stays quiet to avoid noise).
            if [ -z "$sound" ] && [ "$urg" = crit ]; then sound="Basso"; fi
            if command -v terminal-notifier >/dev/null 2>&1; then
                # terminal-notifier takes argv directly — no manual escaping, and
                # it groups (updates the same banner in place) + can play a sound.
                local -a tn_args=(-title "${title:-$app}" -message "$body" -group "open-claw")
                [ -n "$sub" ]   && tn_args+=(-subtitle "$sub")
                [ -n "$sound" ] && tn_args+=(-sound "$sound")
                terminal-notifier "${tn_args[@]}" >/dev/null 2>&1 && return 0
            fi
            # Fallback: osascript. Compose the AppleScript with escaped literals.
            local script="display notification \"$(_osa_escape "$body")\" with title \"$(_osa_escape "${title:-$app}")\""
            [ -n "$sub" ]   && script="$script subtitle \"$(_osa_escape "$sub")\""
            [ -n "$sound" ] && script="$script sound name \"$(_osa_escape "$sound")\""
            osascript -e "$script" >/dev/null 2>&1
            ;;
        *)
            if command -v notify-send >/dev/null 2>&1; then
                local u=normal; [ "$urg" = crit ] && u=critical
                # crit stays on screen until dismissed; info auto-expires.
                local args=(--app-name="$app" --urgency="$u" --icon="$icon")
                [ "$urg" = crit ] && args+=(--expire-time=0)
                [ -n "$sub" ] && body="${sub}
${body}"
                notify-send "${args[@]}" "${title:-$app}" "$body" 2>/dev/null && return 0
            fi
            # No desktop channel — never lose the message.
            printf '[notify:%s] %s — %s\n' "$urg" "${title:-$app}" "$body" >&2
            ;;
    esac
    return 0
}

# ── humanize a duration in seconds → "1h2m3s" / "12s"
_human_dur() {
    local s="$1" h m
    h=$(( s / 3600 )); s=$(( s % 3600 )); m=$(( s / 60 )); s=$(( s % 60 ))
    local out=""
    [ "$h" -gt 0 ] && out="${out}${h}h"
    [ "$m" -gt 0 ] && out="${out}${m}m"
    printf '%s%ss' "$out" "$s"
}

cmd_send() {
    local urg=info app="$APP_DEFAULT" title="" subtitle="" sound="" icon="utilities-terminal"
    local -a pos=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --crit|--critical) urg=crit ;;
            --info)            urg=info ;;
            --sound)     shift; sound="${1:-}" ;;
            --icon)      shift; icon="${1:-utilities-terminal}" ;;
            --title)     shift; title="${1:-}" ;;
            --subtitle)  shift; subtitle="${1:-}" ;;
            --app)       shift; app="${1:-$APP_DEFAULT}" ;;
            --) shift; while [ $# -gt 0 ]; do pos+=("$1"); shift; done; break ;;
            -*) printf 'notify: unknown flag %s\n' "$1" >&2; return 2 ;;
            *)  pos+=("$1") ;;
        esac
        shift 2>/dev/null || break
    done

    # Positional forms:  [TITLE] [BODY]. One arg = body under the app title.
    local body=""
    if [ -z "$title" ]; then
        if [ "${#pos[@]}" -ge 2 ]; then title="${pos[0]}"; body="${pos[1]}"
        elif [ "${#pos[@]}" -eq 1 ]; then body="${pos[0]}"
        fi
    else
        [ "${#pos[@]}" -ge 1 ] && body="${pos[0]}"
    fi

    # Default subtitle communicates urgency when none was given.
    [ -z "$subtitle" ] && [ "$urg" = crit ] && subtitle="⚠ CRITICAL"

    _emit "$urg" "$app" "$title" "$subtitle" "$body" "$sound" "$icon"
}

cmd_after() {
    local urg=info app="$APP_DEFAULT" sound="" icon="utilities-terminal"
    local label="" crit_on_fail=0
    local -a cmd=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --crit|--critical) urg=crit ;;
            --info)            urg=info ;;
            --sound)     shift; sound="${1:-}" ;;
            --icon)      shift; icon="${1:-utilities-terminal}" ;;
            --app)       shift; app="${1:-$APP_DEFAULT}" ;;
            --label)     shift; label="${1:-}" ;;
            --crit-on-fail) crit_on_fail=1 ;;
            --) shift; while [ $# -gt 0 ]; do cmd+=("$1"); shift; done; break ;;
            -*) printf 'notify: unknown flag %s\n' "$1" >&2; return 2 ;;
            *)  cmd+=("$1") ;;
        esac
        shift 2>/dev/null || break
    done

    [ "${#cmd[@]}" -eq 0 ] && { printf 'usage: notify after [flags] -- CMD [ARGS…]\n' >&2; return 2; }
    [ -z "$label" ] && label="${cmd[*]}"

    local start end dur rc
    start="$(date +%s)"
    "${cmd[@]}"; rc=$?
    end="$(date +%s)"
    dur="$(_human_dur "$(( end - start ))")"

    local title subtitle body eurg="$urg"
    if [ "$rc" -eq 0 ]; then
        title="✓ ${label}"; subtitle="done in ${dur}"; body="exit 0 · ${dur}"
    else
        title="✗ ${label}"; subtitle="failed (exit ${rc}) in ${dur}"; body="exit ${rc} · ${dur}"
        [ "$crit_on_fail" -eq 1 ] && eurg=crit
    fi
    [ "$eurg" = crit ] && [ -z "$sound" ] && sound="Basso"
    _emit "$eurg" "$app" "$title" "$subtitle" "$body" "$sound" "$icon"
    return "$rc"
}

cmd_help() { sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-send}" in
    after|--after)     shift; cmd_after "$@" ;;
    send)              shift; cmd_send "$@" ;;
    help|-h|--help)    cmd_help ;;
    # No subcommand keyword → treat everything as `send` args (ergonomic default
    # so `claw notify "Build" "done"` and `claw notify --crit "Down"` just work).
    *)                 cmd_send "$@" ;;
esac
