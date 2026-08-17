#!/usr/bin/env bash
# scripts/utils/update-status.sh — pending-update VISIBILITY for the one
# updater front door (`claw update`). Probes cheap "what's waiting" counts —
# brew/apt outdated packages, dotfiles repo ahead/behind upstream, last engine
# run — into ~/.cache/claw/updates.json so every surface (situation.sh probe,
# ff-readout dashboards, claw doctor, welcome TUI) reads one snapshot in <1ms
# instead of shelling out to package managers at render time.
# Design: docs/superpowers/specs/2026-08-17-claw-update-one-engine-design.md
#
# Subcommands:
#   --refresh        probe -> updates.json (atomic); self-throttled: no-op
#                    while the snapshot is younger than 6h (login kick stays cheap)
#   --force          probe now, ignoring the throttle
#   read [--json]    render the snapshot ("12 pkg · repo ↓3" / "current" /
#                    "n/a"); NEVER probes. --json dumps the raw JSON.
#
# JSON shape (design contract — absent/failed manager => null, NEVER 0):
#   {"ts":"…","brew":N|null,"apt":N|null,"repo_behind":N|null,
#    "repo_ahead":N|null,"last_run":EPOCH|null}
set -u

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claw"
SNAP="$CACHE_DIR/updates.json"
RECEIPTS="$CACHE_DIR/updates.tsv"
LOCK="$CACHE_DIR/.updates.lock"
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
THROTTLE_S=21600            # 6h — dashboards want fresh-ish, not live
LOCK_STALE_S=900            # steal a lock this old (crashed probe)

mkdir -p "$CACHE_DIR" 2>/dev/null

have() { command -v "$1" >/dev/null 2>&1; }

# GNU `timeout` is absent on stock macOS (brew coreutils ships only gtimeout).
# Every probe below is wrapped in `timeout N`, so shim it: prefer gtimeout,
# else run the command unbounded — degraded but working beats exit 127.
if ! have timeout; then
    if have gtimeout; then
        timeout() { gtimeout "$@"; }
    else
        timeout() { shift; "$@"; }
    fi
fi

# seconds since a path's mtime (GNU then BSD stat); huge number when unreadable
# so a stat failure reads as "ancient" (refresh proceeds, stale lock is stolen)
file_age() {
    local m; m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)"
    if [ -n "$m" ]; then echo $(( $(date +%s) - m )); else echo 999999999; fi
}

# ISO-8601 UTC (2026-08-17T12:00:00Z) -> epoch; empty on failure (GNU then BSD)
iso_to_epoch() {
    date -u -d "$1" +%s 2>/dev/null \
        || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}

# ── Probes: best-effort, timeout-bounded, absent/failed manager => null ─────
probe_json() {
    local ts brew_n=null apt_n=null behind=null ahead=null last=null out lts

    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # brew: one line per outdated formula/cask (a clean run with none IS 0)
    if have brew; then
        if out="$(timeout 30 brew outdated --quiet 2>/dev/null)"; then
            brew_n="$(printf '%s\n' "$out" | grep -c '[^[:space:]]')"
        fi
    fi

    # apt: simulated upgrade — no sudo needed; one `Inst …` line per package
    if have apt-get; then
        if out="$(timeout 30 apt-get -s upgrade 2>/dev/null)"; then
            apt_n="$(printf '%s\n' "$out" | grep -c '^Inst ')"
        fi
    fi

    # repo: ahead/behind vs upstream. The fetch is best-effort (offline the
    # counts run against the last-known upstream ref — still honest); a repo
    # with no upstream (or no repo at all) stays null.
    if have git && git -C "$DOTFILES" rev-parse --git-dir >/dev/null 2>&1 \
       && git -C "$DOTFILES" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        # Login-kicked background probe: git/ssh must NEVER open /dev/tty for
        # credentials (a "Username:" prompt painted over the welcome TUI, then
        # SIGTTIN wedging the probe on the lock). Fail the fetch instead — the
        # counts fall back to the last-known upstream ref, still honest.
        GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -oBatchMode=yes" \
            timeout 10 git -C "$DOTFILES" fetch -q 2>/dev/null || true
        behind="$(git -C "$DOTFILES" rev-list --count 'HEAD..@{u}' 2>/dev/null)" || behind=null
        ahead="$(git -C "$DOTFILES" rev-list --count '@{u}..HEAD' 2>/dev/null)" || ahead=null
        : "${behind:=null}"; : "${ahead:=null}"
    fi

    # last engine run: epoch of the newest receipt row (updates.tsv col 1)
    if [ -s "$RECEIPTS" ]; then
        lts="$(tail -n 1 "$RECEIPTS" | cut -f1)"
        [ -n "$lts" ] && last="$(iso_to_epoch "$lts")"
        : "${last:=null}"
    fi

    cat <<EOF
{ "ts": "$ts", "brew": $brew_n, "apt": $apt_n, "repo_behind": $behind, "repo_ahead": $ahead, "last_run": $last }
EOF
}

# ── Refresh: throttle → single-flight lock → probe → atomic landing ─────────
cmd_refresh() {   # $1 = 1 to ignore the 6h throttle (--force)
    if [ "${1:-0}" -eq 0 ] && [ -f "$SNAP" ] && [ "$(file_age "$SNAP")" -lt "$THROTTLE_S" ]; then
        return 0                                 # fresh enough — the whole point
    fi
    # single-flight: login kick + timer + a manual --force can race; mkdir is
    # the portable atomic test-and-set. A crashed probe's stale lock is stolen.
    if ! mkdir "$LOCK" 2>/dev/null; then
        [ "$(file_age "$LOCK")" -lt "$LOCK_STALE_S" ] && return 0
        rmdir "$LOCK" 2>/dev/null || true
        mkdir "$LOCK" 2>/dev/null || return 0
    fi
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT
    trap 'exit 143' INT TERM

    # probe into memory first, then land via mktemp+mv (situation.sh pattern):
    # readers never see a partial file, a killed probe leaves nothing behind.
    local body tmp
    body="$(probe_json)" || return 1
    tmp="$(mktemp "$CACHE_DIR/.upd.XXXXXX")" || return 1
    if printf '%s\n' "$body" > "$tmp"; then mv -f "$tmp" "$SNAP"; else rm -f "$tmp"; return 1; fi
}

# ── Read: render-only (never probes) — the doctor/dashboard glance ──────────
cmd_read() {
    if [ "${1:-}" = "--json" ]; then
        [ -r "$SNAP" ] && cat "$SNAP"
        return 0
    fi
    if [ ! -r "$SNAP" ] || ! have jq; then echo "n/a"; return 0; fi
    # "12 pkg · repo ↓3" (pkg = brew+apt) / "current" (probed, nothing pending)
    # / "n/a" (nothing probe-able on this box). ff-readout renders through here
    # too, so the glance is identical on every surface.
    jq -r '
      (if .brew == null and .apt == null then null
       else ((.brew // 0) + (.apt // 0)) end) as $pkg
      | [ (if ($pkg // 0) > 0 then (($pkg | tostring) + " pkg") else empty end),
          (if (.repo_behind // 0) > 0
           then ("repo ↓" + (.repo_behind | tostring)) else empty end) ]
      | if length > 0 then join(" · ")
        elif $pkg == null and .repo_behind == null then "n/a"
        else "current" end
    ' "$SNAP" 2>/dev/null || echo "n/a"
}

case "${1:-read}" in
    --refresh)      cmd_refresh 0 ;;
    --force)        cmd_refresh 1 ;;
    read)           shift; cmd_read "${1:-}" ;;
    help|-h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "usage: update-status {--refresh|--force|read [--json]}" >&2; exit 1 ;;
esac
