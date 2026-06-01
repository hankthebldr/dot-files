# Session-name banner — design

**Date:** 2026-06-01
**Status:** Approved (brainstorm) — pending spec review
**Topic:** Stable per-shell session identity surfaced in the terminal title and the tmux status bar.

## Problem

On Ubuntu the terminal window/tab title shows the **current foreground process**, so every shell looks alike and tabs are hard to tell apart. The root cause is already in-repo: `shell/.zshrc:92` sources [`shell/progress.zsh`](../../../shell/progress.zsh), which **owns the terminal title** via `preexec`/`precmd` hooks:

- idle (`precmd`) → resets the title to `user@host: cwd` (line 46)
- running (`preexec` → background updater) → overwrites it with `⏳ Ns — <cmd>` (line 63)

There is no concept of a **session identity** anywhere. `CLAW_PROFILE_THEME` / `CLAW_ACTIVE_PROFILE` track the active profile, but nothing pins a stable, human-meaningful name to a shell. Two compounding realities:

1. No default login/startup command selects a profile, so most shells boot with `CLAW_ACTIVE_PROFILE` **empty** — a profile-only scheme would collapse every shell to a bare hostname.
2. tmux already renders its status bar at the **top** (`tmux/.tmux.conf:39`) but `status-left` is empty (line 41) — a ready-made slot for a pinned banner that is currently unused.

## Goals

- A **stable session label** that survives command execution and is visible in (a) the OS window/tab title and (b) the tmux top status bar.
- Works with **zero setup** (sensible auto-default) and supports an explicit override.
- A defined **identity structure** that degrades gracefully from "named" → "profile" → "auto-numbered".

## Non-goals (v1)

- Per-**pane** labels — window-scope is enough to distinguish tabs.
- Pinning tmux **window names** in the window-status list (separate `automatic-rename` toggle; easy follow-up).
- A printed in-content banner line (rejected during brainstorm — costs a content line, clutters scrollback).

## Identity structure

Resolution ladder — **first non-empty wins**:

| Tier | Source | Example label | When |
|---|---|---|---|
| 1. Pin | `CLAW_SESSION` (manual) | `xsiam-poc` | after `session xsiam-poc` |
| 2. Profile | `group/subprofile` | `domain/cortex`, `hardware/homelab` | after a TUI pick |
| 3. Default | `session-N` (auto-seq) | `session-1`, `session-2` | no profile (the common boot case) |

- Tier 2 renders `group/subprofile` when the group is known, else the bare sub-profile (e.g. direct picks `default` / `local` / `claude` have no group).
- Tier 3 gives each shell a distinct ordinal so two un-profiled shells differ. The host is already present in the title's `%n@%m`, so the label itself stays short.

## Architecture

**Single title owner.** `progress.zsh` remains the only writer of the OS title. The session-identity layer is **folded into `progress.zsh`** (its scope broadens from "progress" to "terminal identity + progress") — no parallel `precmd` hook, no competing writers. The label is resolved **inline on every repaint** from live shell variables, which deletes any need for a cached global or a profile-switch hook: the `precmd` already fires every prompt, so the vars are always fresh.

**Seams between modules:**
- `welcome-tui.zsh` **produces** `CLAW_ACTIVE_PROFILE` + `CLAW_ACTIVE_GROUP` (env vars).
- `progress.zsh` **consumes** them (plus `CLAW_SESSION`, `CLAW_SESSION_SEQ`) to compute the label, paints the title, and pushes the label into tmux.
- `.tmux.conf` **consumes** the tmux user option `@claw_session` to render the banner.

Decoupled via plain variables — each piece is independently testable and degrades if another is absent.

## Components

### 1. Sequence claim (`progress.zsh`, runs once per interactive shell)

Each shell claims a monotonic ordinal exactly once and freezes it in a **non-exported** `CLAW_SESSION_SEQ`:

```zsh
if (( ! ${+CLAW_SESSION_SEQ} )); then                # guard: re-source in the same shell won't renumber
  local _seqf="${XDG_CACHE_HOME:-$HOME/.cache}/claw/session.seq"
  mkdir -p "${_seqf:h}" 2>/dev/null                  # ${_seqf:h} = zsh dirname modifier, no fork
  local _n _lockfd
  if zmodload zsh/system 2>/dev/null && zsystem flock -t 2 -f _lockfd "$_seqf" 2>/dev/null; then
    _n=$(( $(<"$_seqf" 2>/dev/null || echo 0) + 1 ))
    print -r -- "$_n" >| "$_seqf"                     # >| clobbers under setopt noclobber
    zsystem flock -u "$_lockfd"                       # release at once — don't hold for shell lifetime
  else                                               # fallback: plain read+write (race tolerated — cosmetic)
    _n=$(( $(<"$_seqf" 2>/dev/null || echo 0) + 1 ))
    print -r -- "$_n" >| "$_seqf" 2>/dev/null
  fi
  typeset -g CLAW_SESSION_SEQ="$_n"                   # typeset -g, NOT export → each new shell claims its own
fi
```

- **Not exported.** A child shell inherits no `CLAW_SESSION_SEQ`, so it claims a fresh ordinal — that is what keeps sibling shells distinct. The `${+CLAW_SESSION_SEQ}` guard only protects against a re-source *within the same shell* (the `reload` alias).
- **`zsh/system`** supplies `zsystem flock` (acquire with `-f <fd-var>`, release with `-u <fd>`) — no external `flock(1)` binary, which macOS lacks by default. The lock is released right after the critical section so concurrent shells never block each other; the fallback tolerates the rare race (worst case: two shells share a number — cosmetic).

### 2. Label resolver (`progress.zsh`)

Returns via `REPLY` — zsh's no-subshell scalar-return convention — so the per-prompt repaint never forks:

```zsh
__claw_session_resolve() {            # sets REPLY
  if   [[ -n "$CLAW_SESSION" ]];        then REPLY="$CLAW_SESSION"
  elif [[ -n "$CLAW_ACTIVE_PROFILE" ]]; then REPLY="${CLAW_ACTIVE_GROUP:+$CLAW_ACTIVE_GROUP/}$CLAW_ACTIVE_PROFILE"
  else REPLY="session-${CLAW_SESSION_SEQ:-0}"; fi
}
```

### 3. Title writers reworked (`progress.zsh`)

Idle title uses zsh prompt expansion (`%n` user, `%m` short host, `%~` cwd) instead of hand-built strings, prefixed with the label:

```zsh
__claw_progress_reset_title() {
  __claw_session_resolve
  print -Pn "\e]0;${REPLY:+[$REPLY] }%n@%m: %~\a"   # [domain/cortex] henry@bd790i: ~/work/x
  __claw_session_tmux_sync "$REPLY"
}
```

Running title — the background updater receives the label captured at `preexec` (4th arg) so it stays fixed for the command's duration:

```
[domain/cortex] ⏳ 12s — terraform apply
```

`__claw_progress_preexec` resolves the label once and passes `$REPLY` into the forked updater.

### 4. tmux sync — push-on-change (`progress.zsh`)

Avoids a `tmux` fork on every prompt by pushing only when the label changes:

```zsh
typeset -g __claw_session_tmux_last=""
__claw_session_tmux_sync() {
  [[ -n "$TMUX" ]] || return
  [[ "$1" == "$__claw_session_tmux_last" ]] && return
  command tmux set-option -w @claw_session "$1" 2>/dev/null
  __claw_session_tmux_last="$1"
}
```

Window-scoped (`-w`) user option — sidesteps tmux `automatic-rename` churn entirely (the same class of bug as the title bar).

### 5. `session` command (`progress.zsh`, user-facing)

```zsh
session() {
  case "${1:-}" in
    "")           __claw_session_resolve; print -r -- "session: $REPLY${CLAW_SESSION:+ (pinned)}" ;;
    -r|--reset|-) unset CLAW_SESSION ;;
    *)            export CLAW_SESSION="$1" ;;
  esac
  __claw_progress_reset_title    # repaint title + tmux immediately
}
```

- `session <label>` → pin · `session` → print current · `session -r` → clear pin, back to profile/auto default.

### 6. Capture the group (`welcome-tui.zsh`, ~1 line)

In the two-level loop, remember the group token when descending (`local _group="$tok"` before the L2 break), and in the profile-loading case export it alongside the profile:

```zsh
export CLAW_ACTIVE_PROFILE="$key"
export CLAW_ACTIVE_GROUP="$_group"   # "" for direct picks (default/local/claude)
```

### 7. tmux status-left (`tmux/.tmux.conf`, ~3 lines)

```tmux
set -g status-left ' #[fg=#0d1117,bg=#58a6ff,bold] #{?#{!=:#{@claw_session},},#{@claw_session},#S} #[default] '
set -g status-left-length 32
```

Shows `@claw_session` when set, else tmux's own session name `#S`; GitHub-blue accent matching the existing window-current style.

## Data flow

```
welcome-tui pick ──► CLAW_ACTIVE_PROFILE, CLAW_ACTIVE_GROUP ─┐
session <label>  ──► CLAW_SESSION ───────────────────────────┤
shell init       ──► CLAW_SESSION_SEQ ───────────────────────┤
                                                              ▼
                                          __claw_session_resolve → REPLY
                                                              │
                              ┌───────────────────────────────┼───────────────────────────┐
                              ▼                                                             ▼
                  print -Pn "\e]0;[REPLY] …\a"                              tmux set -w @claw_session REPLY
                  (OS window/tab title)                                     (status-left banner, on change)
```

## Error handling & guards

- **Non-interactive / SSH-safe:** identity code lives inside the existing `precmd`/`preexec` hooks, which only run in interactive shells. The sequence claim and `session` command emit nothing to stdout except when `session` is invoked by hand. No init-time stdout pollution.
- **tmux absent / not inside tmux:** `__claw_session_tmux_sync` returns early unless `$TMUX` is set; `command tmux … 2>/dev/null` swallows errors.
- **`zsh/system` absent:** sequence claim falls back to plain read+write.
- **Module not loaded:** the label prefix uses `${REPLY:+…}`, so if the identity layer is somehow absent the title degrades to the plain `%n@%m: %~` form.
- **`progress off`:** only silences the running-command updater and completion banner; the idle `precmd` still repaints, so **session identity stays on even with progress disabled**.

## Testing strategy

- **Resolver unit checks** (sourced in a non-interactive zsh): assert `REPLY` for each tier — pin set, profile+group, profile only, neither.
- **Sequence claim:** two subshells each source the claim; assert distinct `CLAW_SESSION_SEQ`; assert a re-source in the same shell does not change it.
- **Title bytes:** capture `print -Pn` output to a pipe; assert the OSC-0 sequence contains `[label]` and the expanded host/cwd.
- **tmux sync:** with a throwaway `tmux` session, run `session foo`; assert `tmux show-options -w @claw_session` == `foo`; assert no redundant set when label unchanged.
- **Manual smoke:** new tab → `session-1`; pick `domain/cortex` → title + tmux show `domain/cortex`; `session xsiam-poc` → both update; `session -r` → back to profile; long `sleep 20` → running title keeps `[label]` prefix.

## Files touched

| File | Change |
|---|---|
| [`shell/progress.zsh`](../../../shell/progress.zsh) | Add session-identity layer (seq claim, resolver, tmux sync, `session` command); rework `reset_title` + updater + `preexec` to carry the label. |
| [`shell/welcome-tui.zsh`](../../../shell/welcome-tui.zsh) | Capture group token; `export CLAW_ACTIVE_GROUP` beside `CLAW_ACTIVE_PROFILE`. |
| [`tmux/.tmux.conf`](../../../tmux/.tmux.conf) | Populate `status-left` from `@claw_session`. |

## Open choices (low-stakes, default chosen)

- Verb: **`session`** (no zsh-builtin collision). Alternatives: `name`, `claw session`.
- Profile label format: **`group/subprofile`**. Alternative: bare `subprofile`.
- Default label: **`session-N`**. Alternative: `<shorthost>-N`.
