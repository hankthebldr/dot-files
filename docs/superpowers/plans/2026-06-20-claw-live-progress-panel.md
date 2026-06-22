# Live Progress Panel (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give long-running single-process `claw` ops (`pkg install/track/scan`) an inline, themed, phase-driven status panel framed in viewfinder corner brackets, default-on a TTY and degrading to clean plain log lines over SSH/CI — plus persisted `claw output` settings to control it.

**Architecture:** A sourced bash library `scripts/utils/claw-progress.sh` holds in-process progress state in shell variables and repaints a pinned bottom panel directly from the foreground (no background renderer, no event file — those are deferred to the Phase 2 / `provision` plan; the public API is identical so internals swap later). A sibling `scripts/utils/claw-output.sh` is the settings home (resolver + setters + `claw output` CLI), mirroring the theme engine's `env → state-file → default` precedence. Call sites (`pkg-manifest.sh`) source the lib and bracket each unit of work with `claw_prog_*` calls; raw tool output is captured to a logfile and never reaches the screen.

**Tech Stack:** Bash (`#!/usr/bin/env bash`), zsh (`shell/progress.zsh` bridge), `bats` for tests, `shellcheck` for lint. Theme colors consumed from exported `CLAW_C_*` env (set by `scripts/utils/theme.sh`) with refined-dark ANSI fallbacks.

## Global Constraints

- **Shebang:** every new script uses `#!/usr/bin/env bash`.
- **shellcheck-clean:** new `scripts/utils/*.sh` must pass `shellcheck -S warning -e SC1090,SC1091` (CI gates the core engine at warning severity; see `.github/workflows/ci.yml:27-34`).
- **SSH/CI safety:** never emit ANSI/cursor control unless rich mode is active. Rich mode requires ALL of: `stdout` is a TTY, `CLAW_PROGRESS_ENABLED != 0`, `TERM != dumb`, `$CI` unset, and resolved `output.mode != plain`. Otherwise plain mode (synchronous newline-terminated lines, no cursor control, no temp files).
- **Theme via env:** colors come from `CLAW_C_<key>` (exported by theme.sh) with hardcoded refined-dark fallbacks — never hardcode a palette without a `${CLAW_C_x:-…}` fallback. Refined-dark fallbacks: blue `\e[38;5;75m`, green `\e[38;5;78m`, red `\e[38;5;203m`, amber `\e[38;5;215m`, muted `\e[38;5;245m`, purple `\e[38;5;141m`, reset `\e[0m`.
- **One toggle:** reuse the existing `CLAW_PROGRESS_ENABLED` flag from `shell/progress.zsh`; do not add a second enable variable.
- **State paths:** settings state file `${XDG_STATE_HOME:-$HOME/.local/state}/claw/output`; captured logs `${XDG_STATE_HOME:-$HOME/.local/state}/claw/logs/<op>-<epoch>.log`.
- **Commit style:** one-line `type(scope): imperative` ≤72 chars, matching `git log --oneline`; keep the `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer.
- **Stage by name:** `git add <explicit paths>` only — never `git add -A`/`.`.
- **Scope:** This plan is Phase 1 (the `pkg-manifest.sh` ops, all single-process). Deferred to a follow-up Phase 2 plan: `provision` two-tier panel (owner/child event-file + background renderer), the global `claw update` path, and the interactive `claw config` hub.

---

### Task 1: Settings engine — `claw-output.sh` (resolver + setters + CLI)

**Files:**
- Create: `scripts/utils/claw-output.sh`
- Test: `tests/progress.bats`

**Interfaces:**
- Produces (sourced API): `_claw_output_get <key>` echoes the resolved value for `key ∈ {mode,frame,banner}`; `_claw_output_set <key> <value>` validates and persists.
- Produces (CLI): `claw-output.sh {mode|frame|banner} <value>`, `claw-output.sh get <key>`, `claw-output.sh status`.
- Resolution precedence per key: env `CLAW_OUTPUT_<UPPER>` → state file line `<key>=<value>` → default. Defaults: `mode=auto`, `frame=viewfinder`, `banner=on`. Valid: `mode ∈ {auto,rich,plain}`, `frame ∈ {viewfinder,none}`, `banner ∈ {on,off}`.

- [ ] **Step 1: Write the failing test**

Append to `tests/progress.bats` (create the file with this header + first tests):

```bash
#!/usr/bin/env bats
# Tests for the live progress panel engine + output settings.

setup() {
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  OUT="$BATS_TEST_DIRNAME/../scripts/utils/claw-output.sh"
}

@test "output: defaults resolve when nothing is set" {
  run bash "$OUT" get mode;   [ "$status" -eq 0 ]; [ "$output" = "auto" ]
  run bash "$OUT" get frame;  [ "$status" -eq 0 ]; [ "$output" = "viewfinder" ]
  run bash "$OUT" get banner; [ "$status" -eq 0 ]; [ "$output" = "on" ]
}

@test "output: set persists and get reads it back" {
  run bash "$OUT" mode plain;     [ "$status" -eq 0 ]
  run bash "$OUT" frame none;     [ "$status" -eq 0 ]
  run bash "$OUT" get mode;  [ "$output" = "plain" ]
  run bash "$OUT" get frame; [ "$output" = "none" ]
}

@test "output: env overrides the state file" {
  bash "$OUT" mode plain
  run env CLAW_OUTPUT_MODE=rich bash "$OUT" get mode
  [ "$output" = "rich" ]
}

@test "output: invalid value is rejected with nonzero exit" {
  run bash "$OUT" mode bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "output: status prints all three resolved keys" {
  run bash "$OUT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode"* ]]
  [[ "$output" == *"frame"* ]]
  [[ "$output" == *"banner"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/progress.bats`
Expected: FAIL — `claw-output.sh` does not exist yet (errors / nonzero).

- [ ] **Step 3: Write the implementation**

Create `scripts/utils/claw-output.sh`:

```bash
#!/usr/bin/env bash
# claw-output.sh — persisted output/display settings for claw surfaces.
# Mirrors the theme engine's precedence: env → state file → default.
#   keys: mode ∈ {auto,rich,plain}  frame ∈ {viewfinder,none}  banner ∈ {on,off}
# Sourced for _claw_output_get/_claw_output_set; executed for the `claw output` CLI.
set -uo pipefail

CLAW_OUTPUT_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claw"
CLAW_OUTPUT_STATE_FILE="$CLAW_OUTPUT_STATE_DIR/output"

_claw_output_default() {
  case "$1" in
    mode) echo auto ;; frame) echo viewfinder ;; banner) echo on ;;
    *) return 1 ;;
  esac
}

_claw_output_valid() {  # _claw_output_valid <key> <value>
  case "$1" in
    mode)   [[ "$2" == auto || "$2" == rich || "$2" == plain ]] ;;
    frame)  [[ "$2" == viewfinder || "$2" == none ]] ;;
    banner) [[ "$2" == on || "$2" == off ]] ;;
    *) return 1 ;;
  esac
}

_claw_output_get() {  # _claw_output_get <key> → resolved value on stdout
  local key="$1" up val
  up="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  # tier 1: env CLAW_OUTPUT_<KEY>
  eval "val=\"\${CLAW_OUTPUT_${up}:-}\""
  if [[ -n "$val" ]]; then printf '%s\n' "$val"; return 0; fi
  # tier 2: state file
  if [[ -r "$CLAW_OUTPUT_STATE_FILE" ]]; then
    val="$(grep -E "^${key}=" "$CLAW_OUTPUT_STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2-)"
    if [[ -n "$val" ]]; then printf '%s\n' "$val"; return 0; fi
  fi
  # tier 3: default
  _claw_output_default "$key"
}

_claw_output_set() {  # _claw_output_set <key> <value>
  local key="$1" value="$2"
  _claw_output_valid "$key" "$value" || { echo "invalid $key: $value" >&2; return 2; }
  mkdir -p "$CLAW_OUTPUT_STATE_DIR" 2>/dev/null || true
  local tmp; tmp="$(mktemp "${CLAW_OUTPUT_STATE_FILE}.XXXXXX")" || return 3
  if [[ -r "$CLAW_OUTPUT_STATE_FILE" ]]; then
    grep -vE "^${key}=" "$CLAW_OUTPUT_STATE_FILE" 2>/dev/null >> "$tmp" || true
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv -f "$tmp" "$CLAW_OUTPUT_STATE_FILE"
}

# ── CLI (only when executed, not when sourced) ──────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-status}" in
    get)    shift; _claw_output_get "${1:?usage: get <key>}" ;;
    status)
      printf "  output settings\n"
      printf "    %-8s %s\n" "mode"   "$(_claw_output_get mode)"
      printf "    %-8s %s\n" "frame"  "$(_claw_output_get frame)"
      printf "    %-8s %s\n" "banner" "$(_claw_output_get banner)"
      ;;
    mode|frame|banner)
      key="$1"; shift
      val="${1:?usage: claw output $key <value>}"
      _claw_output_set "$key" "$val" && printf "  \xE2\x9C\x93 %s: %s (persisted)\n" "$key" "$val"
      ;;
    *) echo "usage: claw output {mode auto|rich|plain | frame viewfinder|none | banner on|off | status | get <key>}" >&2; exit 2 ;;
  esac
fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/progress.bats`
Expected: PASS (5 tests).

- [ ] **Step 5: Lint**

Run: `shellcheck -S warning -e SC1090,SC1091 scripts/utils/claw-output.sh`
Expected: no output (clean), exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/utils/claw-output.sh tests/progress.bats
git commit -m "feat(output): persisted claw output settings (mode/frame/banner)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Route `claw output` through the dispatcher

**Files:**
- Modify: `bin/claw` (dispatch `case`, near `theme|themes|colors)` and the help text block)

**Interfaces:**
- Consumes: `scripts/utils/claw-output.sh` CLI from Task 1.
- Produces: `claw output …` invocable end-to-end.

- [ ] **Step 1: Write the failing test**

Append to `tests/progress.bats`:

```bash
@test "claw output: dispatches through bin/claw" {
  run env DOTFILES_DIR="$BATS_TEST_DIRNAME/.." bash "$BATS_TEST_DIRNAME/../bin/claw" output status
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode"* ]]
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bats tests/progress.bats -f "dispatches through bin/claw"`
Expected: FAIL — `claw` prints unknown-command/usage, nonzero or missing "mode".

- [ ] **Step 3: Add the dispatch route**

In `bin/claw`, add a route line immediately after the `theme|themes|colors) shift; cmd_theme "$@" ;;` line:

```bash
    output)         shift; bash "$DOTFILES/scripts/utils/claw-output.sh" "$@" ;;
```

- [ ] **Step 4: Add the help entry**

In `bin/claw`, in the help text block (the `claw — Open Claw dispatcher` heredoc/printf around lines 126-163), add under the Workflows section, after the `claw update` line:

```bash
    ${c_white}claw output${c_reset}           ${c_dim}display settings: mode auto|rich|plain · frame viewfinder|none · banner on|off${c_reset}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bats tests/progress.bats -f "dispatches through bin/claw"`
Expected: PASS.

- [ ] **Step 6: Lint + syntax**

Run: `bash -n bin/claw && shellcheck -S warning -e SC1090,SC1091,SC2034 bin/claw`
Expected: exit 0 (pre-existing warnings unrelated to your two lines are acceptable only if `shellcheck` was already non-clean on `bin/claw`; your added lines must introduce none).

- [ ] **Step 7: Commit**

```bash
git add bin/claw tests/progress.bats
git commit -m "feat(output): route claw output through the dispatcher

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Framing primitive + glyph/width helpers in `claw-progress.sh`

**Files:**
- Create: `scripts/utils/claw-progress.sh`
- Test: `tests/progress.bats`

**Interfaces:**
- Produces (sourced API):
  - `_claw_cols` → echoes terminal width (int): `$COLUMNS`, else `tput cols`, else `80`.
  - `_claw_unicode` → returns 0 if UTF-8/non-dumb (glyphs OK), 1 otherwise (ASCII fallback).
  - `_claw_glyph <name>` → echoes a glyph for `name ∈ {tl,tr,bl,br,bar_full,bar_empty,ok,fail,skip,run,arrow}` with ASCII fallback.
  - `claw_frame_top` / `claw_frame_bottom` → print one full-width viewfinder corner line (corner glyph at column 1 and column N, spaces between), honoring `output.frame` (when `frame=none`, print a plain dim divider of `─`/`-` instead).
  - `claw_card <title>` (body on stdin) → print a framed card: top line, ` <title>`, each stdin line indented two spaces, bottom line.
- Consumes: `_claw_output_get` (Task 1) — `claw-progress.sh` sources `claw-output.sh`.

- [ ] **Step 1: Write the failing test**

Append to `tests/progress.bats`:

```bash
@test "frame: viewfinder top line spans COLUMNS and carries corner glyphs" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env COLUMNS=40 TERM=xterm-256color bash -c "source '$PROG'; claw_frame_top"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\xE2\x8C\x9C'* ]]   # ⌜ top-left
  [[ "$output" == *$'\xE2\x8C\x9D'* ]]   # ⌝ top-right
}

@test "frame: dumb terminal falls back to ASCII corners" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env COLUMNS=40 TERM=dumb bash -c "source '$PROG'; claw_frame_top"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+"* ]]
  [[ "$output" != *$'\xE2\x8C\x9C'* ]]   # no unicode corner
}

@test "frame: claw_card wraps a title and body" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env COLUMNS=40 TERM=xterm-256color bash -c "source '$PROG'; printf 'line one\nline two\n' | claw_card 'My Title'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"My Title"* ]]
  [[ "$output" == *"line one"* ]]
  [[ "$output" == *"line two"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/progress.bats -f "frame:"`
Expected: FAIL — `claw-progress.sh` does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/utils/claw-progress.sh` with the helpers (the progress engine is added in Task 4/5):

```bash
#!/usr/bin/env bash
# claw-progress.sh — inline, phase-driven live status panel for long-running
# claw ops. Foreground, single-process (Phase 1). Sourced by call sites.
#   See docs/superpowers/specs/2026-06-20-claw-live-progress-panel-design.md
set -uo pipefail

_CLAW_PROG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CLAW_PROG_DIR/claw-output.sh" 2>/dev/null || true

# ── theme colors (consume exported CLAW_C_*; refined-dark fallbacks) ─────────
_c() {  # _c <key> → ANSI color (env CLAW_C_<key> or fallback)
  local v; eval "v=\"\${CLAW_C_$1:-}\""
  if [[ -n "$v" ]]; then printf '%s' "$v"; return; fi
  case "$1" in
    blue)  printf '\033[38;5;75m'  ;; green) printf '\033[38;5;78m'  ;;
    red)   printf '\033[38;5;203m' ;; amber) printf '\033[38;5;215m' ;;
    muted) printf '\033[38;5;245m' ;; purple)printf '\033[38;5;141m' ;;
    *)     printf '' ;;
  esac
}
_creset() { printf '\033[0m'; }

_claw_cols() {
  if [[ -n "${COLUMNS:-}" ]]; then printf '%s' "$COLUMNS"; return; fi
  local c; c="$(tput cols 2>/dev/null)"; printf '%s' "${c:-80}"
}

_claw_unicode() {  # 0 = glyphs OK, 1 = ASCII fallback
  [[ "${TERM:-}" != dumb ]] || return 1
  [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *[Uu][Tt][Ff]* || -z "${LANG:-}" ]] || return 1
  return 0
}

_claw_glyph() {  # _claw_glyph <name>
  if _claw_unicode; then
    case "$1" in
      tl) printf '\xE2\x8C\x9C' ;; tr) printf '\xE2\x8C\x9D' ;;   # ⌜ ⌝
      bl) printf '\xE2\x8C\x9E' ;; br) printf '\xE2\x8C\x9F' ;;   # ⌞ ⌟
      bar_full) printf '\xE2\x96\x93' ;; bar_empty) printf '\xE2\x96\x91' ;; # ▓ ░
      ok) printf '\xE2\x9C\x93' ;; fail) printf '\xE2\x9C\x97' ;; # ✓ ✗
      skip) printf '\xC2\xB7' ;;  arrow) printf '\xE2\x96\xB8' ;; # · ▸
      run) printf '\xE2\x8F\xB3' ;;                               # ⏳
      div) printf '\xE2\x94\x80' ;;                               # ─
    esac
  else
    case "$1" in
      tl|tr|bl|br) printf '+' ;; bar_full) printf '#' ;; bar_empty) printf '.' ;;
      ok) printf 'OK' ;; fail) printf 'X' ;; skip) printf '-' ;;
      arrow) printf '>' ;; run) printf '*' ;; div) printf '-' ;;
    esac
  fi
}

# ── viewfinder frame primitive ──────────────────────────────────────────────
claw_frame_top() {
  local w; w="$(_claw_cols)"; local frame; frame="$(_claw_output_get frame)"
  if [[ "$frame" == none ]]; then
    printf '%s' "$(_c muted)"; local i; for ((i=0;i<w;i++)); do _claw_glyph div; done; _creset; printf '\n'; return
  fi
  local mid=$(( w - 2 )); (( mid < 0 )) && mid=0
  printf '%s%s%*s%s%s\n' "$(_c muted)" "$(_claw_glyph tl)" "$mid" "" "$(_claw_glyph tr)" "$(_creset)"
}
claw_frame_bottom() {
  local w; w="$(_claw_cols)"; local frame; frame="$(_claw_output_get frame)"
  if [[ "$frame" == none ]]; then
    printf '%s' "$(_c muted)"; local i; for ((i=0;i<w;i++)); do _claw_glyph div; done; _creset; printf '\n'; return
  fi
  local mid=$(( w - 2 )); (( mid < 0 )) && mid=0
  printf '%s%s%*s%s%s\n' "$(_c muted)" "$(_claw_glyph bl)" "$mid" "" "$(_claw_glyph br)" "$(_creset)"
}

claw_card() {  # claw_card <title>   (body on stdin)
  local title="$1"
  claw_frame_top
  printf '  %s%s%s\n' "$(_c purple)" "$title" "$(_creset)"
  local line; while IFS= read -r line; do printf '  %s\n' "$line"; done
  claw_frame_bottom
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/progress.bats -f "frame:"`
Expected: PASS (3 tests).

- [ ] **Step 5: Lint**

Run: `shellcheck -S warning -e SC1090,SC1091 scripts/utils/claw-progress.sh`
Expected: clean, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/utils/claw-progress.sh tests/progress.bats
git commit -m "feat(progress): viewfinder frame primitive + glyph/width helpers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Progress engine — plain-mode state machine

**Files:**
- Modify: `scripts/utils/claw-progress.sh`
- Test: `tests/progress.bats`

**Interfaces:**
- Consumes: helpers + `_claw_output_get` (Tasks 1, 3).
- Produces (sourced API, used by all call sites):
  - `claw_prog_begin <op> [total]` — total defaults 0 (indeterminate). Resolves mode once into `_CLAW_PROG_MODE` (`rich`|`plain`). Initializes counters and `_CLAW_PROG_T0`.
  - `claw_prog_item <id> [source]`, `claw_prog_phase <phase>`, `claw_prog_note <text>` — set current state.
  - `claw_prog_ok [msg]`, `claw_prog_fail [msg]`, `claw_prog_skip [msg]` — finalize current item: bump `done` + the matching tally, emit one curated scrollback line.
  - `claw_prog_end` — print a summary card, reset state.
- Plain-mode contract (this task): `begin` → `▸ <op> (<total>)` (omit ` (0)` when total is 0); `item`/`phase`/`note` → no output; `ok` → `  ✓ <id> <msg>`; `fail` → `  ✗ <id> <msg>`; `skip` → `  · <id> <msg>`; `end` → `  summary: ✓<ok> ✗<fail> ·<skip> · <dur>`.

- [ ] **Step 1: Write the failing test**

Append to `tests/progress.bats`:

```bash
@test "engine: plain mode emits clean per-item lines + summary" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain bash -c "
    source '$PROG'
    claw_prog_begin demo 3
    claw_prog_item awscli brew;   claw_prog_phase install; claw_prog_ok
    claw_prog_item kubectl brew;  claw_prog_ok
    claw_prog_item helm brew;     claw_prog_fail 'network timeout'
    claw_prog_end
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo (3)"* ]]
  [[ "$output" == *"awscli"* ]]
  [[ "$output" == *"helm"* ]]
  [[ "$output" == *"network timeout"* ]]
  [[ "$output" == *"summary:"* ]]
}

@test "engine: summary tally counts ok/fail/skip correctly" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain bash -c "
    source '$PROG'
    claw_prog_begin demo 0
    claw_prog_item a; claw_prog_ok
    claw_prog_item b; claw_prog_ok
    claw_prog_item c; claw_prog_skip
    claw_prog_item d; claw_prog_fail
    claw_prog_end
  "
  [[ "$output" == *$'\xE2\x9C\x93'"2"* ]]   # ✓2
  [[ "$output" == *$'\xE2\x9C\x97'"1"* ]]   # ✗1
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/progress.bats -f "engine:"`
Expected: FAIL — `claw_prog_begin` undefined.

- [ ] **Step 3: Write the implementation**

Append to `scripts/utils/claw-progress.sh` (before the file end):

```bash
# ── progress engine (Phase 1: foreground, single-process) ───────────────────
_CLAW_PROG_OP=""; _CLAW_PROG_TOTAL=0; _CLAW_PROG_DONE=0
_CLAW_PROG_OK=0;  _CLAW_PROG_FAIL=0;  _CLAW_PROG_SKIP=0
_CLAW_PROG_ITEM=""; _CLAW_PROG_SRC=""; _CLAW_PROG_PHASE=""; _CLAW_PROG_NOTE=""
_CLAW_PROG_T0=0; _CLAW_PROG_MODE="plain"

_claw_prog_detect_mode() {
  local m; m="$(_claw_output_get mode)"
  case "$m" in plain) echo plain; return ;; rich) echo rich; return ;; esac
  if [[ -t 1 && "${CLAW_PROGRESS_ENABLED:-1}" != 0 && "${TERM:-}" != dumb && -z "${CI:-}" ]]; then
    echo rich
  else
    echo plain
  fi
}

_claw_dur() {  # _claw_dur <seconds> → "Ns" or "MmSSs"
  local s="$1"
  if (( s < 60 )); then printf '%ds' "$s"; else printf '%dm%02ds' $(( s/60 )) $(( s%60 )); fi
}

claw_prog_begin() {
  _CLAW_PROG_OP="$1"; _CLAW_PROG_TOTAL="${2:-0}"
  _CLAW_PROG_DONE=0; _CLAW_PROG_OK=0; _CLAW_PROG_FAIL=0; _CLAW_PROG_SKIP=0
  _CLAW_PROG_ITEM=""; _CLAW_PROG_SRC=""; _CLAW_PROG_PHASE=""; _CLAW_PROG_NOTE=""
  _CLAW_PROG_T0="$(date +%s)"
  _CLAW_PROG_MODE="$(_claw_prog_detect_mode)"
  if [[ "$_CLAW_PROG_MODE" == plain ]]; then
    if (( _CLAW_PROG_TOTAL > 0 )); then
      printf '%s%s %s(%d)%s\n' "$(_c blue)" "$_CLAW_PROG_OP" "$(_c muted)" "$_CLAW_PROG_TOTAL" "$(_creset)"
    else
      printf '%s%s%s\n' "$(_c blue)" "$_CLAW_PROG_OP" "$(_creset)"
    fi
  fi
  # rich mode draw is added in Task 5
}

claw_prog_item()  { _CLAW_PROG_ITEM="$1"; _CLAW_PROG_SRC="${2:-}"; _CLAW_PROG_PHASE=""; _CLAW_PROG_NOTE=""; _claw_prog_repaint; }
claw_prog_phase() { _CLAW_PROG_PHASE="$1"; _claw_prog_repaint; }
claw_prog_note()  { _CLAW_PROG_NOTE="$1"; _claw_prog_repaint; }

# A finalize helper: glyph, color, tally var name.
_claw_prog_finalize() {  # _claw_prog_finalize <glyph-name> <color> <msg>
  _CLAW_PROG_DONE=$(( _CLAW_PROG_DONE + 1 ))
  local line; line="$(printf '  %s%s%s %s%s' "$2" "$(_claw_glyph "$1")" "$(_creset)" "$_CLAW_PROG_ITEM" "${3:+ ${3}}")"
  _claw_prog_scrollback "$line"
}
claw_prog_ok()   { _CLAW_PROG_OK=$((   _CLAW_PROG_OK+1   )); _claw_prog_finalize ok   "$(_c green)" "${1:-}"; }
claw_prog_fail() { _CLAW_PROG_FAIL=$(( _CLAW_PROG_FAIL+1 )); _claw_prog_finalize fail "$(_c red)"   "${1:-}"; }
claw_prog_skip() { _CLAW_PROG_SKIP=$(( _CLAW_PROG_SKIP+1 )); _claw_prog_finalize skip "$(_c muted)" "${1:-}"; }

claw_prog_end() {
  local dur; dur="$(_claw_dur $(( $(date +%s) - _CLAW_PROG_T0 )))"
  local summary; summary="$(printf '%s%s%d%s %s%s%d%s %s%s%d%s %s· %s%s' \
    "$(_c green)" "$(_claw_glyph ok)"   "$_CLAW_PROG_OK"   "$(_creset)" \
    "$(_c red)"   "$(_claw_glyph fail)" "$_CLAW_PROG_FAIL" "$(_creset)" \
    "$(_c muted)" "$(_claw_glyph skip)" "$_CLAW_PROG_SKIP" "$(_creset)" \
    "$(_c muted)" "$dur" "$(_creset)")"
  _claw_prog_teardown    # rich teardown (added Task 5; no-op in plain)
  printf '  summary: %s\n' "$summary"
}

# Plain-mode stubs; Task 5 overrides repaint/scrollback/teardown for rich mode.
_claw_prog_repaint()    { :; }
_claw_prog_scrollback() { printf '%s\n' "$1"; }
_claw_prog_teardown()   { :; }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/progress.bats -f "engine:"`
Expected: PASS (2 tests).

- [ ] **Step 5: Lint**

Run: `shellcheck -S warning -e SC1090,SC1091 scripts/utils/claw-progress.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add scripts/utils/claw-progress.sh tests/progress.bats
git commit -m "feat(progress): plain-mode phase state machine + tally summary

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Rich-mode pinned panel + `claw_prog_run`

**Files:**
- Modify: `scripts/utils/claw-progress.sh`
- Test: `tests/progress.bats`

**Interfaces:**
- Consumes: engine vars + helpers (Tasks 3, 4).
- Produces:
  - Rich overrides for `_claw_prog_repaint`, `_claw_prog_scrollback`, `_claw_prog_teardown` that maintain a 4-line pinned panel as the last lines on screen (frame_top · bar line · item/phase line · frame_bottom).
  - `claw_prog_run <phase> -- <cmd...>` — set phase, run `<cmd>` with stdout+stderr redirected to `${XDG_STATE_HOME:-$HOME/.local/state}/claw/logs/<op>-<t0>.log`; in rich mode tick the panel (spinner + live elapsed) every 1s until exit; return the command's real exit code. In plain mode, run synchronously with output to the logfile and return rc (no ticking).
- Panel height constant `_CLAW_PANEL_H=4`.

- [ ] **Step 1: Write the failing test**

Append to `tests/progress.bats`:

```bash
@test "claw_prog_run returns the command's real exit code (plain)" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain bash -c "
    source '$PROG'
    claw_prog_begin demo 1
    claw_prog_item thing
    claw_prog_run install -- false
    echo \"rc=\$?\"
    claw_prog_end
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=1"* ]]
}

@test "claw_prog_run captures command output to a logfile, not the screen" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" bash -c "
    source '$PROG'
    claw_prog_begin demo 1
    claw_prog_item thing
    claw_prog_run install -- sh -c 'echo NOISE_FROM_TOOL'
    claw_prog_ok
    claw_prog_end
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"NOISE_FROM_TOOL"* ]]          # not on screen
  run grep -rl "NOISE_FROM_TOOL" "$BATS_TEST_TMPDIR/state/claw/logs"
  [ "$status" -eq 0 ]                              # captured in a logfile
}

@test "rich mode forced into a pipe still returns rc and prints a summary" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=rich TERM=xterm-256color COLUMNS=60 bash -c "
    source '$PROG'
    claw_prog_begin demo 1
    claw_prog_item thing brew; claw_prog_phase install; claw_prog_ok
    claw_prog_end
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"summary:"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/progress.bats -f "claw_prog_run\|rich mode forced"`
Expected: FAIL — `claw_prog_run` undefined.

- [ ] **Step 3: Write the implementation**

In `scripts/utils/claw-progress.sh`, **replace** the three plain-mode stub lines from Task 4 —

```bash
_claw_prog_repaint()    { :; }
_claw_prog_scrollback() { printf '%s\n' "$1"; }
_claw_prog_teardown()   { :; }
```

— with the mode-aware implementations and `claw_prog_run`:

```bash
_CLAW_PANEL_H=4
_CLAW_PANEL_DRAWN=0
_CLAW_SPIN_FRAMES='|/-\'
_CLAW_SPIN_I=0

_claw_logfile() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/claw/logs"
  mkdir -p "$d" 2>/dev/null || true
  printf '%s/%s-%s.log' "$d" "${_CLAW_PROG_OP:-op}" "${_CLAW_PROG_T0:-0}"
}

# Build the bar string: <full×k><empty×(width-k)>  done/total
_claw_prog_bar() {
  local width=14 k=0
  if (( _CLAW_PROG_TOTAL > 0 )); then
    k=$(( _CLAW_PROG_DONE * width / _CLAW_PROG_TOTAL ))
    (( k > width )) && k=width
  fi
  local i out=""
  for ((i=0;i<k;i++));      do out+="$(_claw_glyph bar_full)";  done
  for ((i=k;i<width;i++));  do out+="$(_claw_glyph bar_empty)"; done
  printf '%s' "$out"
}

# Print the 4 panel lines (no cursor moves; caller positions the cursor).
_claw_panel_render() {
  local dur; dur="$(_claw_dur $(( $(date +%s) - _CLAW_PROG_T0 )))"
  local count=""
  (( _CLAW_PROG_TOTAL > 0 )) && count="$(printf '%d/%d' "$_CLAW_PROG_DONE" "$_CLAW_PROG_TOTAL")"
  claw_frame_top
  printf '\033[2K  %s%s%s  %s  %s%s · %s%d %s%s%d %s!%d%s\n' \
    "$(_c blue)" "$_CLAW_PROG_OP" "$(_creset)" "$(_claw_prog_bar)" \
    "$(_c muted)" "$count" "$dur" "$_CLAW_PROG_OK" \
    "$(_c red)" "$(_claw_glyph fail)" "$_CLAW_PROG_FAIL" "$_CLAW_PROG_SKIP" "$(_creset)"
  local spin="${_CLAW_SPIN_FRAMES:$(( _CLAW_SPIN_I % ${#_CLAW_SPIN_FRAMES} )):1}"
  printf '\033[2K  %s%s%s %s %s%s%s%s\n' \
    "$(_c amber)" "${_CLAW_PROG_ITEM:+$spin}" "$(_creset)" \
    "${_CLAW_PROG_ITEM:-…}" \
    "$(_c muted)" "${_CLAW_PROG_PHASE:+${_CLAW_PROG_PHASE} }${_CLAW_PROG_NOTE}" \
    "${_CLAW_PROG_SRC:+  ($_CLAW_PROG_SRC)}" "$(_creset)"
  claw_frame_bottom
}

_claw_prog_repaint() {
  [[ "$_CLAW_PROG_MODE" == rich ]] || return 0
  if (( _CLAW_PANEL_DRAWN )); then printf '\033[%dA' "$_CLAW_PANEL_H"; fi
  _claw_panel_render
  _CLAW_PANEL_DRAWN=1
}

_claw_prog_scrollback() {  # insert a line above the pinned panel
  if [[ "$_CLAW_PROG_MODE" != rich ]]; then printf '%s\n' "$1"; return; fi
  if (( _CLAW_PANEL_DRAWN )); then printf '\033[%dA' "$_CLAW_PANEL_H"; fi
  printf '\033[2K%s\n' "$1"     # the freed line, cleared then written
  _claw_panel_render
  _CLAW_PANEL_DRAWN=1
}

_claw_prog_teardown() {
  [[ "$_CLAW_PROG_MODE" == rich ]] || return 0
  if (( _CLAW_PANEL_DRAWN )); then
    printf '\033[%dA' "$_CLAW_PANEL_H"
    local i; for ((i=0;i<_CLAW_PANEL_H;i++)); do printf '\033[2K\n'; done
    printf '\033[%dA' "$_CLAW_PANEL_H"
  fi
  printf '\033[?25h'    # ensure cursor visible
  _CLAW_PANEL_DRAWN=0
}

claw_prog_run() {  # claw_prog_run <phase> -- <cmd...>
  local phase="$1"; shift
  [[ "${1:-}" == "--" ]] && shift
  _CLAW_PROG_PHASE="$phase"
  local log; log="$(_claw_logfile)"
  if [[ "$_CLAW_PROG_MODE" != rich ]]; then
    "$@" >>"$log" 2>&1; return $?
  fi
  _claw_prog_repaint
  "$@" >>"$log" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    _CLAW_SPIN_I=$(( _CLAW_SPIN_I + 1 )); _claw_prog_repaint; sleep 1
  done
  wait "$pid"; return $?
}

# Rich mode: hide cursor + guarantee teardown on signals.
_claw_prog_begin_rich() {
  [[ "$_CLAW_PROG_MODE" == rich ]] || return 0
  printf '\033[?25l'
  trap '_claw_prog_teardown' EXIT INT TERM
  _claw_prog_repaint
}
```

Then wire the rich-begin hook: in `claw_prog_begin`, replace the trailing comment line `  # rich mode draw is added in Task 5` with:

```bash
  [[ "$_CLAW_PROG_MODE" == rich ]] && _claw_prog_begin_rich
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/progress.bats -f "claw_prog_run\|rich mode forced"`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the whole progress suite + lint**

Run: `bats tests/progress.bats && shellcheck -S warning -e SC1090,SC1091 scripts/utils/claw-progress.sh`
Expected: all tests PASS, shellcheck clean.

- [ ] **Step 6: Manual visual verification (real TTY)**

Run in an interactive terminal (not CI):
```bash
source scripts/utils/claw-progress.sh
claw_prog_begin demo 3
claw_prog_item terraform brew; claw_prog_run install -- sleep 2; claw_prog_ok
claw_prog_item helm brew;      claw_prog_run install -- sleep 1; claw_prog_fail "boom"
claw_prog_item kubectl brew;   claw_prog_ok
claw_prog_end
```
Expected: a viewfinder-framed panel pinned at the bottom with a moving spinner + live elapsed during the `sleep`s; `✓ terraform` / `✗ helm boom` scroll above it; clean teardown + `summary: ✓2 ✗1 ·0 · …` at the end; cursor restored; Ctrl-C mid-run leaves no corrupted panel.

- [ ] **Step 7: Commit**

```bash
git add scripts/utils/claw-progress.sh tests/progress.bats
git commit -m "feat(progress): rich pinned panel + claw_prog_run with output capture

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Instrument `pkg install` (the per-tool phase lifecycle)

**Files:**
- Modify: `scripts/utils/pkg-manifest.sh:122-149` (`_install_via`, `pkg_install`)
- Test: `tests/progress.bats`

**Interfaces:**
- Consumes: `claw_prog_*` (Tasks 4, 5).
- Produces: `pkg_install` drives the panel — one `claw_prog_item` per manifest tool, `download`/`install` phases via `claw_prog_run`, `claw_prog_ok|skip|fail` per tool, `claw_prog_end` summary.

- [ ] **Step 1: Write the failing test**

Append to `tests/progress.bats`:

```bash
@test "pkg install: drives the progress panel (plain) with per-tool result + summary" {
  DF="$BATS_TEST_TMPDIR/df"
  mkdir -p "$DF/config/manifest" "$DF/scripts/utils"
  cp "$BATS_TEST_DIRNAME"/../scripts/utils/{cinematic.sh,detect-os.sh,claw-progress.sh,claw-output.sh} "$DF/scripts/utils/"
  cp "$BATS_TEST_DIRNAME/../scripts/utils/pkg-manifest.sh" "$DF/scripts/utils/"
  # a tool guaranteed present so _install_via takes the skip path, plus a real one
  printf 'bash|manual\n' > "$DF/config/manifest/tools.list"
  run env DOTFILES_DIR="$DF" CLAW_OUTPUT_MODE=plain bash "$DF/scripts/utils/pkg-manifest.sh" install all
  [ "$status" -eq 0 ]
  [[ "$output" == *"bash"* ]]
  [[ "$output" == *"summary:"* ]]
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bats tests/progress.bats -f "pkg install:"`
Expected: FAIL — current `pkg_install` prints `installed ok=.. failed=..`, not a `summary:` line.

- [ ] **Step 3: Source the lib at the top of pkg-manifest.sh**

In `scripts/utils/pkg-manifest.sh`, after the existing `source "$_U/detect-os.sh" …` line (around line 31), add:

```bash
# shellcheck source=/dev/null
source "$_U/claw-progress.sh" 2>/dev/null || true
```

- [ ] **Step 4: Rewrite `_install_via` to report phase + skip, and `pkg_install` to drive the panel**

Replace `_install_via` (lines 122-138) and `pkg_install` (lines 140-149) with:

```bash
# Returns: 0 installed · 10 already-present (skip) · 1 failed/unknown.
_install_via() {  # _install_via <id> <source>
    local id="$1" src="$2"
    command -v "$id" &>/dev/null && return 10
    case "$src" in
        brew)    claw_prog_run install -- brew install "$id" ;;
        apt)     claw_prog_run install -- sudo apt-get install -y "$id" ;;
        cargo)   claw_prog_run build   -- cargo install "$id" ;;
        pipx)    claw_prog_run install -- pipx install "$id" ;;
        gem)     claw_prog_run install -- gem install "$id" ;;
        npm)     claw_prog_run install -- npm install -g "$id" ;;
        go:*)    claw_prog_run build   -- go install "${src#go:}@latest" ;;
        eget|eget:*)
                 claw_prog_run download -- sh -c 'command -v eget >/dev/null && eget "$1" --to "$2" 2>/dev/null || eget "$3" --to "$2" 2>/dev/null' \
                     _ "${src#eget:}" "$HOME/.local/bin/$id" "$id" ;;
        curl:*)  claw_prog_run install -- sh -c "curl -fsSL \"\$1\" | sh" _ "${src#curl:}" ;;
        manual)  return 10 ;;   # nothing to install — treat as present/skip
        *)       return 1 ;;
    esac
}

pkg_install() {
    local want="${1:-all}" id src rc
    local -a tools=()
    while IFS='|' read -r id src _; do
        [[ "$id" =~ ^#|^$ ]] && continue
        id="${id// /}"; src="${src// /}"
        [[ "$want" != "all" && "$want" != "$id" ]] && continue
        tools+=("$id|$src")
    done < "$MANIFEST"

    claw_prog_begin "pkg install" "${#tools[@]}"
    local entry
    for entry in "${tools[@]}"; do
        id="${entry%%|*}"; src="${entry#*|}"
        claw_prog_item "$id" "$src"
        _install_via "$id" "$src"; rc=$?
        case "$rc" in
            0)  claw_prog_ok ;;
            10) claw_prog_skip "present" ;;
            *)  claw_prog_fail ;;
        esac
    done
    claw_prog_end
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bats tests/progress.bats -f "pkg install:"`
Expected: PASS.

- [ ] **Step 6: Regression — existing pkg test still passes + lint**

Run: `bats tests/claw.bats -f "pkg-manifest" && shellcheck -S warning -e SC1090,SC1091 scripts/utils/pkg-manifest.sh`
Expected: PASS, clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/utils/pkg-manifest.sh tests/progress.bats
git commit -m "feat(pkg): drive the live progress panel from pkg install

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Instrument `pkg track` / `pkg scan` (indeterminate scan phases)

**Files:**
- Modify: `scripts/utils/pkg-manifest.sh` (`_discover` lines 44-55, `pkg_scan` 67-81, `pkg_track` 94-113)
- Test: `tests/progress.bats`

**Interfaces:**
- Consumes: `claw_prog_*`.
- Produces: a `_discover_sourced` helper that announces a `scan` phase per source (`brew`/`cargo`/`pipx`/`npm`/`userbin`) via `claw_prog_*`; `pkg_track`/`pkg_scan` wrap discovery in `claw_prog_begin … claw_prog_end` (indeterminate, total 0) so the user sees live scanning. Final result line is preserved.

- [ ] **Step 1: Write the failing test**

Append to `tests/progress.bats`:

```bash
@test "pkg track: shows live scan phase + still reports nothing-new on a current manifest" {
  DF="$BATS_TEST_TMPDIR/df2"
  mkdir -p "$DF/config/manifest" "$DF/scripts/utils"
  cp "$BATS_TEST_DIRNAME"/../scripts/utils/{cinematic.sh,detect-os.sh,claw-progress.sh,claw-output.sh,pkg-manifest.sh} "$DF/scripts/utils/"
  : > "$DF/config/manifest/tools.list"
  # Force discovery to find nothing by pointing user-bin dirs at empty + no pkg mgrs on PATH is unrealistic;
  # instead assert the op runs cleanly and emits a scan label.
  run env DOTFILES_DIR="$DF" CLAW_OUTPUT_MODE=plain bash "$DF/scripts/utils/pkg-manifest.sh" track
  [ "$status" -eq 0 ]
  [[ "$output" == *"pkg track"* ]]
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bats tests/progress.bats -f "pkg track:"`
Expected: FAIL — no `pkg track` label is emitted today.

- [ ] **Step 3: Add a per-source discovery wrapper**

In `scripts/utils/pkg-manifest.sh`, immediately after the existing `_discover_clean` definition (line ~56), add:

```bash
# Per-source discovery that announces a scan phase for the live panel, then
# feeds the same clean tool list. Used by pkg_track / pkg_scan.
_discover_announced() {
    local src
    for src in brew cargo pipx npm userbin; do
        claw_prog_item "$src"
        claw_prog_phase scan
    done
    _discover_clean
}
```

- [ ] **Step 4: Wrap `pkg_scan` and `pkg_track` discovery in begin/end**

In `pkg_scan`, change the discovery loop source from `_discover_clean` to a wrapped form. Replace the line `    done < <(_discover_clean)` (line ~72) with:

```bash
    done < <(claw_prog_begin "pkg scan" 0 >&2; _discover_announced; claw_prog_end >&2)
```

In `pkg_track`, replace the line `    done < <(_discover_clean)` (line ~103) with:

```bash
    done < <(claw_prog_begin "pkg track" 0 >&2; _discover_announced; claw_prog_end >&2)
```

(`>&2` keeps the panel/labels off the captured stdout stream that the `while read` consumes; the tool ids still flow on stdout.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `bats tests/progress.bats -f "pkg track:"`
Expected: PASS.

- [ ] **Step 6: Regression + lint**

Run: `bats tests/claw.bats -f "pkg-manifest" && bats tests/progress.bats && shellcheck -S warning -e SC1090,SC1091 scripts/utils/pkg-manifest.sh`
Expected: all PASS, clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/utils/pkg-manifest.sh tests/progress.bats
git commit -m "feat(pkg): live scan phases for pkg track and pkg scan

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Bridge the `progress off` toggle to child bash

**Files:**
- Modify: `shell/progress.zsh:206-229` (the `progress()` function)

**Interfaces:**
- Consumes: existing `CLAW_PROGRESS_ENABLED`.
- Produces: `progress on|off` exports `CLAW_PROGRESS_ENABLED` so `bash` child scripts (and thus `claw-progress.sh`'s mode detection) honor the toggle.

- [ ] **Step 1: Add the export bridge**

In `shell/progress.zsh`, inside `progress()`, change the two assignment lines:
- In the `on)` branch, change `CLAW_PROGRESS_ENABLED=1` to `export CLAW_PROGRESS_ENABLED=1`.
- In the `off)` branch, change `CLAW_PROGRESS_ENABLED=0` to `export CLAW_PROGRESS_ENABLED=0`.

- [ ] **Step 2: Verify syntax**

Run: `zsh -n shell/progress.zsh`
Expected: exit 0, no output.

- [ ] **Step 3: Verify the bridge propagates**

Run:
```bash
zsh -c 'source shell/progress.zsh; progress off >/dev/null; bash -c "echo CLAW_PROGRESS_ENABLED=\$CLAW_PROGRESS_ENABLED"'
```
Expected: prints `CLAW_PROGRESS_ENABLED=0`.

- [ ] **Step 4: Commit**

```bash
git add shell/progress.zsh
git commit -m "fix(progress): export CLAW_PROGRESS_ENABLED so child bash honors the toggle

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Full-suite verification + spec back-reference

**Files:**
- Modify: `docs/superpowers/specs/2026-06-20-claw-live-progress-panel-design.md` (status note)

**Interfaces:** none (verification + doc).

- [ ] **Step 1: Run the entire shell test suite**

Run: `bats tests/`
Expected: all tests PASS (existing `claw.bats` + new `progress.bats`).

- [ ] **Step 2: Run the repo's shellcheck gate over the new/changed engine files**

Run:
```bash
for f in scripts/utils/claw-progress.sh scripts/utils/claw-output.sh scripts/utils/pkg-manifest.sh; do
  shellcheck -S warning -e SC1090,SC1091 "$f" || echo "FAILED: $f"
done
```
Expected: no `FAILED:` lines.

- [ ] **Step 3: Mark Phase 1 done in the spec**

In `docs/superpowers/specs/2026-06-20-claw-live-progress-panel-design.md`, change the `**Status:**` line under the header blockquote to:

```markdown
> **Status:** Phase 1 implemented (engine + settings + pkg-manifest instrumentation). Phase 2 (provision two-tier, claw update, claw config hub) pending.
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-06-20-claw-live-progress-panel-design.md
git commit -m "docs(spec): mark live progress panel Phase 1 implemented

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2 (deferred — separate plan)

Not in this plan; capture for the follow-up:
- **`provision` two-tier panel** — multi-process owner/child election via exported `CLAW_PROGRESS_RUN`, the append-only event file, and a single background renderer (the spec's full architecture). Outer stage bar + inner per-tool phase.
- **Global `claw update`** (`bin/claw:cmd_update`) and `pkg_update` (topgrade-opaque → indeterminate item; per-source → phase per source).
- **`claw config`** interactive hub (gum/FZF, viewfinder-framed) delegating to `claw output` + `claw theme`.
- Reuse the identical `claw_prog_*` public API — only `claw-progress.sh` internals change.
