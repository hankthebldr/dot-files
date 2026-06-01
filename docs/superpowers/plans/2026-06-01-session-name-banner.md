# Session-name Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every shell a stable session label (manual pin → `group/subprofile` → auto `session-N`) shown in the terminal title and the tmux top status bar.

**Architecture:** Fold a session-identity layer into the existing single title owner [`shell/progress.zsh`](../../../shell/progress.zsh). The label is resolved inline from live shell vars on every `precmd` repaint via zsh's no-fork `REPLY` convention, so no cache or profile-switch hook is needed. The welcome-TUI gains a one-line group export; tmux's empty `status-left` reads a `@claw_session` user option pushed on change.

**Tech Stack:** zsh (`add-zsh-hook`, prompt expansion `%n/%m/%~`, `zsh/system` `zsystem flock`, `zsh/parameter` `$functions`), tmux user options, plain-script tests via the repo's `tests/test-runner.sh`.

**Spec:** [docs/superpowers/specs/2026-06-01-session-name-banner-design.md](../specs/2026-06-01-session-name-banner-design.md)

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `tests/session-identity.test.zsh` | zsh unit tests for the identity layer | **Create** |
| `shell/progress.zsh` | session identity (resolve, seq claim, tmux sync, `session` cmd) + label-aware title writers | Modify |
| `shell/welcome-tui.zsh` | persist the picked group as `CLAW_ACTIVE_GROUP` | Modify (~3 lines) |
| `tmux/.tmux.conf` | render the label in `status-left` | Modify (~3 lines) |
| `tests/test-runner.sh` | run the new test file in the suite | Modify (~6 lines) |

Conventions to follow (from the existing code):
- All new functions are `__claw_session_*` / `__claw_progress_*` (matches the file's prefix).
- Never print to stdout at source time (SSH-safe init — see `CLAUDE.md`).
- Guard every tmux call with `[[ -n "$TMUX" ]]` and `command tmux … 2>/dev/null`.

---

## Task 1: Test harness + label resolver (TDD)

**Files:**
- Create: `tests/session-identity.test.zsh`
- Modify: `shell/progress.zsh` (add resolver after the `# ─── Helpers` block, around line 47)

- [ ] **Step 1: Write the failing test file**

Create `tests/session-identity.test.zsh` with the harness and the resolver tests:

```zsh
#!/usr/bin/env zsh
# tests/session-identity.test.zsh — unit tests for the session-identity layer
# in shell/progress.zsh. Run standalone: `zsh tests/session-identity.test.zsh`

typeset -gi _pass=0 _fail=0

assert_eq() {        # assert_eq <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    print -r -- "  ✓ $1"; (( _pass++ ))
  else
    print -r -- "  ✗ $1"
    print -r -- "      expected: [$2]"
    print -r -- "      actual:   [$3]"
    (( _fail++ ))
  fi
}

assert_contains() {  # assert_contains <desc> <haystack> <needle>
  if [[ "$2" == *"$3"* ]]; then
    print -r -- "  ✓ $1"; (( _pass++ ))
  else
    print -r -- "  ✗ $1"
    print -r -- "      [$2] does not contain [$3]"
    (( _fail++ ))
  fi
}

test_resolver() {
  local REPLY
  CLAW_SESSION="xsiam-poc"; CLAW_ACTIVE_PROFILE="cortex"; CLAW_ACTIVE_GROUP="domain"; CLAW_SESSION_SEQ=3
  __claw_session_resolve; assert_eq "tier1 pin wins" "xsiam-poc" "$REPLY"

  CLAW_SESSION="";          CLAW_ACTIVE_PROFILE="cortex"; CLAW_ACTIVE_GROUP="domain"; CLAW_SESSION_SEQ=3
  __claw_session_resolve; assert_eq "tier2 group/subprofile" "domain/cortex" "$REPLY"

  CLAW_SESSION="";          CLAW_ACTIVE_PROFILE="claude"; CLAW_ACTIVE_GROUP="";       CLAW_SESSION_SEQ=3
  __claw_session_resolve; assert_eq "tier2 bare profile (no group)" "claude" "$REPLY"

  CLAW_SESSION="";          CLAW_ACTIVE_PROFILE="";       CLAW_ACTIVE_GROUP="";       CLAW_SESSION_SEQ=5
  __claw_session_resolve; assert_eq "tier3 auto-seq" "session-5" "$REPLY"
}

main() {
  emulate -L zsh
  print -r -- "▶ session-identity tests"
  local PROGRESS="${0:A:h}/../shell/progress.zsh"
  export XDG_CACHE_HOME="$(mktemp -d)"   # isolate the source-time seq claim
  source "$PROGRESS"

  test_resolver

  print -r -- "  ──"
  print -r -- "  ${_pass} passed, ${_fail} failed"
  rm -rf "$XDG_CACHE_HOME"
  (( _fail == 0 ))
}

main "$@"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `zsh tests/session-identity.test.zsh`
Expected: FAIL — `command not found: __claw_session_resolve` (resolver undefined), exit non-zero.

- [ ] **Step 3: Add the resolver to `shell/progress.zsh`**

Insert immediately after `__claw_progress_reset_title()` (after line 47), opening the identity section:

```zsh
# ─── Session identity ───────────────────────────────────────────────────
# Stable per-shell label, resolved fresh on every repaint (no cache, no
# profile-switch hook needed — precmd already fires each prompt). Returns
# via REPLY (zsh's no-subshell scalar return) so the hook never forks.
#   tier 1: $CLAW_SESSION         (manual pin via `session <label>`)
#   tier 2: group/subprofile      (from the welcome-TUI pick)
#   tier 3: session-<N>           (auto sequence — the no-profile default)
__claw_session_resolve() {
  if   [[ -n "$CLAW_SESSION" ]];        then REPLY="$CLAW_SESSION"
  elif [[ -n "$CLAW_ACTIVE_PROFILE" ]]; then REPLY="${CLAW_ACTIVE_GROUP:+$CLAW_ACTIVE_GROUP/}$CLAW_ACTIVE_PROFILE"
  else REPLY="session-${CLAW_SESSION_SEQ:-0}"
  fi
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `zsh tests/session-identity.test.zsh`
Expected: PASS — `4 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/session-identity.test.zsh shell/progress.zsh
git commit -m "feat(tui): session label resolver (pin/profile/auto)"
```

---

## Task 2: Sequence claim (TDD)

**Files:**
- Modify: `tests/session-identity.test.zsh` (add `test_seq_claim`, call it in `main`)
- Modify: `shell/progress.zsh` (add `__claw_session_claim_seq`, invoke once near hook registration ~line 116)

- [ ] **Step 1: Write the failing test**

Add this function above `main()` in `tests/session-identity.test.zsh`:

```zsh
test_seq_claim() {
  local PROGRESS="${0:A:h}/../shell/progress.zsh"
  local _tmp; _tmp="$(mktemp -d)"

  # Two independent shells sharing one cache must claim distinct ordinals.
  local one two
  one="$(XDG_CACHE_HOME="$_tmp" zsh -c "source '$PROGRESS'; print -r -- \$CLAW_SESSION_SEQ")"
  two="$(XDG_CACHE_HOME="$_tmp" zsh -c "source '$PROGRESS'; print -r -- \$CLAW_SESSION_SEQ")"
  assert_eq "first shell claims 1"  "1" "$one"
  assert_eq "second shell claims 2" "2" "$two"

  # Re-sourcing within the SAME shell must not renumber it.
  local guard
  guard="$(XDG_CACHE_HOME="$_tmp" zsh -c "source '$PROGRESS'; a=\$CLAW_SESSION_SEQ; source '$PROGRESS'; print -r -- \"\${a}:\${CLAW_SESSION_SEQ}\"")"
  assert_eq "re-source keeps same number" "${guard%%:*}" "${guard##*:}"

  rm -rf "$_tmp"
}
```

And add the call inside `main()`, after `test_resolver`:

```zsh
  test_seq_claim
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `zsh tests/session-identity.test.zsh`
Expected: FAIL — `first shell claims 1` gets actual `[]` (var unset; `CLAW_SESSION_SEQ` never set), exit non-zero.

- [ ] **Step 3: Implement the sequence claim in `shell/progress.zsh`**

Add this function at the end of the identity section (after the resolver from Task 1):

```zsh
# Claim a monotonic ordinal once per interactive shell, frozen in a
# NON-exported CLAW_SESSION_SEQ (non-export → child shells claim their own,
# keeping siblings distinct). zsh/system flock makes the bump race-safe with
# no external flock(1) binary (macOS lacks one); fallback tolerates the race.
__claw_session_claim_seq() {
  (( ${+CLAW_SESSION_SEQ} )) && return            # re-source in same shell: keep number
  local _seqf="${XDG_CACHE_HOME:-$HOME/.cache}/claw/session.seq"
  mkdir -p "${_seqf:h}" 2>/dev/null               # ${_seqf:h} = zsh dirname, no fork
  local _cur=0 _n _lockfd
  if zmodload zsh/system 2>/dev/null && zsystem flock -t 2 -f _lockfd "$_seqf" 2>/dev/null; then
    [[ -r "$_seqf" ]] && _cur="$(<"$_seqf")"
    _n=$(( _cur + 1 ))
    print -r -- "$_n" >| "$_seqf"                  # >| clobbers under setopt noclobber
    zsystem flock -u "$_lockfd"                    # release at once, don't hold for shell life
  else
    [[ -r "$_seqf" ]] && _cur="$(<"$_seqf")"
    _n=$(( _cur + 1 ))
    print -r -- "$_n" >| "$_seqf" 2>/dev/null
  fi
  typeset -g CLAW_SESSION_SEQ="$_n"                # typeset -g, NOT export
}
```

Then invoke it once. Find the registration block (currently lines 110–116):

```zsh
# Register only once
if (( ! ${+__claw_progress_registered} )); then
  autoload -U add-zsh-hook
  add-zsh-hook preexec __claw_progress_preexec
  add-zsh-hook precmd  __claw_progress_precmd
  typeset -g __claw_progress_registered=1
fi
```

Add the claim immediately **before** that block:

```zsh
# Claim this shell's session ordinal (once).
__claw_session_claim_seq
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `zsh tests/session-identity.test.zsh`
Expected: PASS — `7 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/session-identity.test.zsh shell/progress.zsh
git commit -m "feat(tui): per-shell session sequence number (flock-safe)"
```

---

## Task 3: `session` command (TDD)

**Files:**
- Modify: `tests/session-identity.test.zsh` (add `test_session_cmd`, call it)
- Modify: `shell/progress.zsh` (add `session()` in the identity section)

- [ ] **Step 1: Write the failing test**

Add above `main()`:

```zsh
test_session_cmd() {
  local REPLY
  # Save & restore the real repaint fn so this test causes no terminal side effects.
  local _orig="$functions[__claw_progress_reset_title]"
  __claw_progress_reset_title() { : }

  CLAW_SESSION=""; CLAW_ACTIVE_PROFILE="cortex"; CLAW_ACTIVE_GROUP="domain"
  session foo
  assert_eq "session <label> pins CLAW_SESSION" "foo" "$CLAW_SESSION"
  __claw_session_resolve; assert_eq "pinned label resolves" "foo" "$REPLY"

  session -r
  assert_eq "session -r clears the pin" "" "$CLAW_SESSION"
  __claw_session_resolve; assert_eq "after reset falls back to profile" "domain/cortex" "$REPLY"

  functions[__claw_progress_reset_title]="$_orig"
}
```

And call it in `main()` after `test_seq_claim`:

```zsh
  test_session_cmd
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `zsh tests/session-identity.test.zsh`
Expected: FAIL — `command not found: session`, exit non-zero.

- [ ] **Step 3: Implement `session()` in `shell/progress.zsh`**

Add at the end of the identity section (after `__claw_session_claim_seq`):

```zsh
# ─── User-facing: session <label> ───────────────────────────────────────
# session <label>  → pin this shell's name        session -r → clear the pin
# session          → print the current label
session() {
  case "${1:-}" in
    "")            __claw_session_resolve
                   print -r -- "session: ${REPLY}${CLAW_SESSION:+ (pinned)}" ;;
    -r|--reset|-)  unset CLAW_SESSION ;;
    *)             export CLAW_SESSION="$1" ;;
  esac
  __claw_progress_reset_title    # repaint title + push to tmux immediately
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `zsh tests/session-identity.test.zsh`
Expected: PASS — `11 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/session-identity.test.zsh shell/progress.zsh
git commit -m "feat(tui): session command (pin/print/reset)"
```

---

## Task 4: Label-aware title writers + tmux sync

**Files:**
- Modify: `tests/session-identity.test.zsh` (add `test_title_bytes`, call it)
- Modify: `shell/progress.zsh` — `__claw_session_tmux_sync` (new), `__claw_progress_reset_title` (rework, lines 43–47), `__claw_progress_updater` (rework, lines 55–66), `__claw_progress_preexec` (rework, lines 69–81)

- [ ] **Step 1: Write the failing test**

Add above `main()`:

```zsh
test_title_bytes() {
  CLAW_SESSION=""; CLAW_ACTIVE_PROFILE=""; CLAW_ACTIVE_GROUP=""; CLAW_SESSION_SEQ=9
  # TMUX= disables the tmux push for the capture (subshell-scoped, no real tmux touched).
  local out
  out="$(TMUX= __claw_progress_reset_title)"
  assert_contains "idle title carries [session-9]" "$out" "[session-9] "
  assert_contains "idle title emits OSC-0 intro"    "$out" $'\e]0;'
}
```

Call it in `main()` after `test_session_cmd`:

```zsh
  test_title_bytes
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `zsh tests/session-identity.test.zsh`
Expected: FAIL — current `reset_title` emits `user@host: cwd` with no `[session-9]` prefix; `assert_contains "idle title carries [session-9]"` fails.

- [ ] **Step 3: Implement the reworked writers**

First add the tmux-sync helper and its state var. Put them just after `__claw_progress_set_title()` (after line 41):

```zsh
# Push the session label into tmux (window-scoped user option) only when it
# changes — avoids forking tmux every prompt. status-left reads @claw_session.
typeset -g __claw_session_tmux_last=""
__claw_session_tmux_sync() {
  [[ -n "$TMUX" ]] || return
  [[ "$1" == "$__claw_session_tmux_last" ]] && return
  command tmux set-option -w @claw_session "$1" 2>/dev/null
  __claw_session_tmux_last="$1"
}
```

Replace `__claw_progress_reset_title()` (lines 43–47) with:

```zsh
__claw_progress_reset_title() {
  # Idle title: [label] user@host: cwd, via zsh prompt expansion (%n/%m/%~).
  __claw_session_resolve
  print -Pn "\e]0;${REPLY:+[$REPLY] }%n@%m: %~\a"
  __claw_session_tmux_sync "$REPLY"
}
```

Replace `__claw_progress_updater()` (lines 55–66) with (adds a 4th `lbl` arg, prefixes it):

```zsh
__claw_progress_updater() {
  local pid="$1" cmd="$2" t0="$3" lbl="$4"
  # Wait until threshold before painting anything
  sleep "$CLAW_PROGRESS_THRESHOLD"
  while kill -0 "$pid" 2>/dev/null; do
    local elapsed=$(( $(date +%s) - t0 ))
    local short="${cmd:0:60}"
    [[ ${#cmd} -gt 60 ]] && short="${short}…"
    __claw_progress_set_title "${lbl:+[$lbl] }⏳ ${elapsed}s — ${short}"
    sleep 1
  done
}
```

In `__claw_progress_preexec()` (lines 69–81), resolve the label and pass it as the 4th arg to the forked updater. Replace the fork line:

```zsh
  # Fork the title updater into the background, disowned
  ( __claw_progress_updater "$$" "$__claw_progress_cmd" "$__claw_progress_t0" ) &!
```

with:

```zsh
  # Resolve the session label now so the running-title keeps it for the whole cmd
  __claw_session_resolve
  # Fork the title updater into the background, disowned
  ( __claw_progress_updater "$$" "$__claw_progress_cmd" "$__claw_progress_t0" "$REPLY" ) &!
```

- [ ] **Step 4: Run the test + syntax check to verify they pass**

Run: `zsh tests/session-identity.test.zsh`
Expected: PASS — `13 passed, 0 failed`, exit 0.

Run: `zsh -n shell/progress.zsh`
Expected: no output, exit 0 (syntax OK).

- [ ] **Step 5: Manual smoke (running-title prefix)**

Run (interactive zsh with the module sourced — e.g. a new terminal tab):
```
sleep 12
```
Expected: while it runs, the tab/window title shows `[session-N] ⏳ 3s — sleep 12` (or `[domain/cortex] …` if a profile is active); after it returns, the title is `[session-N] user@host: ~/cwd`.

- [ ] **Step 6: Commit**

```bash
git add tests/session-identity.test.zsh shell/progress.zsh
git commit -m "feat(tui): label-aware title + tmux push on change"
```

---

## Task 5: Capture the picked group in the welcome-TUI

**Files:**
- Modify: `shell/welcome-tui.zsh` (lines 148, ~177, ~197)
- Modify: `tests/session-identity.test.zsh` (add `test_welcome_group_capture`, call it)

- [ ] **Step 1: Write the failing test**

Add above `main()`:

```zsh
test_welcome_group_capture() {
  local wt="${0:A:h}/../shell/welcome-tui.zsh"
  zsh -n "$wt" || { print -r -- "  ✗ welcome-tui.zsh syntax error"; (( _fail++ )); return; }
  assert_contains "welcome-tui exports CLAW_ACTIVE_GROUP" "$(<"$wt")" "export CLAW_ACTIVE_GROUP="
}
```

Call it in `main()` after `test_title_bytes`:

```zsh
  test_welcome_group_capture
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `zsh tests/session-identity.test.zsh`
Expected: FAIL — `welcome-tui exports CLAW_ACTIVE_GROUP` not found in the file.

- [ ] **Step 3: Implement the group capture in `shell/welcome-tui.zsh`**

Replace the loop-variable declaration (line 148):

```zsh
    local key="" raw_key=""
```

with (adds `_group`):

```zsh
    local key="" raw_key="" _group=""
```

In the group-descend branch, set `_group` just before the `break`. Replace (around line 177):

```zsh
            # ESC at L2 → back to the group picker
            [[ -z "$itok" ]] && continue
            key="$itok"; raw_key="$itok"; break
```

with:

```zsh
            # ESC at L2 → back to the group picker
            [[ -z "$itok" ]] && continue
            key="$itok"; raw_key="$itok"; _group="$tok"; break
```

In the profile-loading case, export the group next to the profile. Replace (line 197):

```zsh
            export CLAW_ACTIVE_PROFILE="$key"
```

with:

```zsh
            export CLAW_ACTIVE_PROFILE="$key"
            export CLAW_ACTIVE_GROUP="$_group"   # "" for direct picks (default/local/claude)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `zsh tests/session-identity.test.zsh`
Expected: PASS — `14 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/session-identity.test.zsh shell/welcome-tui.zsh
git commit -m "feat(tui): persist picked group as CLAW_ACTIVE_GROUP"
```

---

## Task 6: tmux status-left banner

**Files:**
- Modify: `tmux/.tmux.conf` (lines 41 and 44)

- [ ] **Step 1: Implement the status-left**

Replace the empty status-left (line 41):

```tmux
set -g status-left ''
```

with (reads the `@claw_session` user option, falls back to tmux's own `#S`):

```tmux
set -g status-left ' #[fg=#0d1117,bg=#58a6ff,bold] #{?#{!=:#{@claw_session},},#{@claw_session},#S} #[default] '
```

And widen the left segment — replace line 44:

```tmux
set -g status-left-length 20
```

with:

```tmux
set -g status-left-length 32
```

- [ ] **Step 2: Verify the config parses and the option round-trips**

Run (uses a throwaway tmux server socket `claw_test` so your real tmux is untouched):

```bash
tmux -L claw_test -f tmux/.tmux.conf new-session -d -s t \
  && tmux -L claw_test set-option -w @claw_session demo \
  && tmux -L claw_test show-options -w @claw_session \
  ; tmux -L claw_test kill-server 2>/dev/null
```

Expected: prints `@claw_session demo` with no config-parse error, then the server is killed.

- [ ] **Step 3: Manual smoke (banner in a real tmux)**

Inside a real tmux session, run `tmux source-file tmux/.tmux.conf` then `session demo`.
Expected: the top status bar's left segment shows a blue ` demo ` chip; `session -r` reverts it to the profile label (or tmux session name).

- [ ] **Step 4: Commit**

```bash
git add tmux/.tmux.conf
git commit -m "feat(tmux): show session label in status-left"
```

---

## Task 7: Wire the test file into the suite

**Files:**
- Modify: `tests/test-runner.sh` (add a `test_session_identity` function + a `run_test` line in `main`)

- [ ] **Step 1: Add the test function**

In `tests/test-runner.sh`, add this function after `test_configs()` (after line 41):

```bash
test_session_identity() {
    log_info "Testing session-identity layer..."
    command -v zsh >/dev/null 2>&1 || { log_warning "zsh not found; skipping"; return 0; }
    zsh "$(dirname "${BASH_SOURCE[0]}")/session-identity.test.zsh" || return 1
}
```

- [ ] **Step 2: Register it in `main`**

In `main()`, add a `run_test` line after the "Configuration Validity" line (after line 47):

```bash
    run_test "Session Identity" test_session_identity || ((failures++))
```

- [ ] **Step 3: Run the full suite**

Run: `bash tests/test-runner.sh`
Expected: the suite runs; the "Session Identity" test reports `14 passed, 0 failed` and the runner ends with `All tests passed!` (the pre-existing Tools/Config tests may warn in a non-installed environment — that is unrelated to this change).

- [ ] **Step 4: Commit**

```bash
git add tests/test-runner.sh
git commit -m "test: run session-identity suite in test-runner"
```

---

## Self-Review

**1. Spec coverage**

| Spec section | Task |
|---|---|
| Identity ladder tier 1/2/3 | Task 1 (resolver) + Task 2 (seq) |
| Sequence claim (flock, non-export, `:h`, guard) | Task 2 |
| Label resolver via `REPLY` | Task 1 |
| Title writers reworked (`print -Pn`, updater prefix, preexec capture) | Task 4 |
| tmux push-on-change (`@claw_session`, `__claw_session_tmux_last`) | Task 4 |
| `session` command (pin/print/reset) | Task 3 |
| welcome-TUI group capture (`CLAW_ACTIVE_GROUP`) | Task 5 |
| tmux `status-left` | Task 6 |
| Guards: SSH-safe, tmux-guard, `zsh/system` fallback, `progress off` | Tasks 2 & 4 (code comments + guards); `progress off` behavior unchanged (precmd still calls reset_title) |
| Testing strategy | Tasks 1–7 |

No gaps.

**2. Placeholder scan:** No TBD/TODO/"add error handling"/"similar to". Every code step shows complete code; every run step shows an exact command + expected result.

**3. Type/name consistency:** Verified across tasks — `__claw_session_resolve`, `__claw_session_claim_seq`, `__claw_session_tmux_sync`, `__claw_session_tmux_last`, `session`, and vars `CLAW_SESSION`, `CLAW_SESSION_SEQ`, `CLAW_ACTIVE_PROFILE`, `CLAW_ACTIVE_GROUP`, `@claw_session` are spelled identically everywhere. Updater's new 4th arg `lbl` matches the `$REPLY` passed by `preexec`. Test pass-counts are cumulative and consistent (4 → 7 → 11 → 13 → 14).
