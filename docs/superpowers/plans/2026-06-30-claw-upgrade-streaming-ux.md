# claw upgrade — streaming process UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the output-swallowing `gum spin` in `claw upgrade`/`claw update` with a live, theme-reactive, viewfinder-framed "stream + collapse-on-success" process view so every install step is visible.

**Architecture:** Extend the existing progress module `scripts/utils/claw-progress.sh` with a streaming step runner (`claw_step`) plus themed chrome helpers, fix its broken `_c()` theme reader, migrate the two visible update surfaces (`system-update.sh`, `tool-updater.sh`) onto it, and redirect the legacy `tui_run_step` shim to the same runner so `integrity.sh`/`storage-doctor.sh`/`welcome-tui.zsh` also lose the blackout without a restyle.

**Tech Stack:** Bash (must run under macOS system **bash 3.2**), zsh (welcome-tui consumer), `bats` for tests, `shellcheck` for linting. Theme via `scripts/utils/theme.sh` (`CLAW_RGB_*`). Display settings via `scripts/utils/claw-output.sh` (`mode`/`frame`).

## Global Constraints

- **bash 3.2 compatible.** No `${arr[@]: -n}` negative offsets, no associative arrays, no `${var^^}` outside a `_c()` helper that is only ever run under `bash` (see note in Task 1). Guard every empty-array expansion with a count check: `(( ${#a[@]} )) && for x in "${a[@]}"; do …`.
- **`set -uo pipefail` is already active** at the top of `claw-progress.sh:5` — every new variable must be initialized; every array expansion guarded.
- **No `gum` on the update path.** `gum` is the blackout source being removed; do not reintroduce it.
- **Theme contract:** `CLAW_RGB_<KEY>` = `"r;g;b"` decimal triplet (truecolor); `CLAW_C_<KEY>` = bare hex (NOT an ANSI escape). Keys used: `blue green red amber muted purple` (all exist in `CLAW_THEME_KEYS`).
- **Every command a step runs gets `</dev/null` on stdin** — the deadlock guard.
- **Full output always tee'd** to `$XDG_STATE_HOME/claw/logs/<op>-<ts>.log` (reuse `_claw_logfile`).
- **Run all tests with:** `bats tests/progress.bats` (add cases there). Lint touched scripts with `shellcheck -x <file>`.
- **Commit style:** one-line imperative ≤72 chars, matching `git log --oneline`. Stage named files only (never `-A`).

---

### Task 1: Fix `_c()` to emit truecolor from `CLAW_RGB_*`

**Files:**
- Modify: `scripts/utils/claw-progress.sh:12-21` (the `_c()` helper)
- Test: `tests/progress.bats` (append)

**Interfaces:**
- Produces: `_c <key>` → prints an ANSI SGR escape string (`\033[38;2;r;g;bm` when `CLAW_RGB_<KEY>` is set, else a 256-color fallback). Consumed by every later task.

- [ ] **Step 1: Write the failing tests** — append to `tests/progress.bats`:

```bash
@test "theme: _c builds truecolor from CLAW_RGB_* when set" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_RGB_BLUE='10;20;30' bash -c "source '$PROG'; _c blue"
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;10;20;30m"* ]]
}

@test "theme: _c falls back to 256-color when CLAW_RGB_* unset" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run bash -c "unset CLAW_RGB_BLUE CLAW_C_BLUE; source '$PROG'; _c blue"
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;5;75m"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/progress.bats -f "theme:"`
Expected: FAIL — current `_c` prints the raw `CLAW_C_BLUE` hex (or empty), never `38;2;10;20;30m`.

- [ ] **Step 3: Replace the `_c()` helper**

Replace `scripts/utils/claw-progress.sh:12-21` with:

```bash
_c() {  # _c <key> → ANSI truecolor from CLAW_RGB_<KEY>, else 256-color fallback
  local key up rgb
  key="$1"
  up="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  eval "rgb=\"\${CLAW_RGB_${up}:-}\""
  if [[ -n "$rgb" ]]; then printf '\033[38;2;%sm' "$rgb"; return; fi
  case "$key" in
    blue)  printf '\033[38;5;75m'  ;; green) printf '\033[38;5;78m'  ;;
    red)   printf '\033[38;5;203m' ;; amber) printf '\033[38;5;215m' ;;
    muted) printf '\033[38;5;245m' ;; purple)printf '\033[38;5;141m' ;;
    *)     printf '' ;;
  esac
}
```

(Uses `tr` for upper-casing instead of `${key^^}` so it is bash 3.2 safe.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/progress.bats -f "theme:"`
Expected: PASS (2 tests)

- [ ] **Step 5: Lint + regression**

Run: `shellcheck -x scripts/utils/claw-progress.sh && bats tests/progress.bats`
Expected: shellcheck clean (or no new warnings); all existing progress tests still pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/utils/claw-progress.sh tests/progress.bats
git commit -m "fix(progress): _c emits truecolor from CLAW_RGB_* (was raw hex)"
```

---

### Task 2: Add the streaming `claw_step` runner

**Files:**
- Modify: `scripts/utils/claw-progress.sh` (append after the existing `claw_prog_run` block, ~line 232)
- Test: `tests/progress.bats` (append)

**Interfaces:**
- Consumes: `_c`, `_claw_glyph`, `_creset`, `_claw_cols`, `_claw_logfile`, `_claw_prog_detect_mode` (all existing in `claw-progress.sh`); tally globals `_CLAW_PROG_OK/_CLAW_PROG_FAIL/_CLAW_PROG_DONE`, `_CLAW_PROG_OP`, `_CLAW_PROG_T0`, `_CLAW_PROG_MODE`.
- Produces: `claw_step "<label>" -- <cmd...>` — runs `<cmd...>` with stdin `</dev/null`, streams stdout+stderr live, tees to the op logfile, returns the command's real exit code, and increments `_CLAW_PROG_OK`/`_CLAW_PROG_FAIL` + `_CLAW_PROG_DONE`. Rich mode (interactive tty or `mode=rich`) shows a moving ≤6-line viewport that collapses to one verdict line on success and is retained on failure; plain mode streams linearly.

- [ ] **Step 1: Write the failing tests** — append to `tests/progress.bats`:

```bash
@test "claw_step: streams command output to the screen (plain)" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain bash -c "
    source '$PROG'
    _CLAW_PROG_MODE=plain; _CLAW_PROG_OK=0; _CLAW_PROG_FAIL=0; _CLAW_PROG_DONE=0
    _CLAW_PROG_OP=demo; _CLAW_PROG_T0=0
    claw_step 'run thing' -- sh -c 'echo VISIBLE_LINE'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"VISIBLE_LINE"* ]]
  [[ "$output" == *"run thing"* ]]
}

@test "claw_step: returns the command's real exit code (plain)" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain bash -c "
    source '$PROG'
    _CLAW_PROG_MODE=plain; _CLAW_PROG_OK=0; _CLAW_PROG_FAIL=0; _CLAW_PROG_DONE=0
    _CLAW_PROG_OP=demo; _CLAW_PROG_T0=0
    claw_step 'boom' -- false; echo \"rc=\$?\"
  "
  [[ "$output" == *"rc=1"* ]]
}

@test "claw_step: failure shows (exit N) and retains output" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain bash -c "
    source '$PROG'
    _CLAW_PROG_MODE=plain; _CLAW_PROG_OK=0; _CLAW_PROG_FAIL=0; _CLAW_PROG_DONE=0
    _CLAW_PROG_OP=demo; _CLAW_PROG_T0=0
    claw_step 'boom' -- sh -c 'echo ERRDETAIL; exit 3'
  "
  [[ "$output" == *"ERRDETAIL"* ]]
  [[ "$output" == *"(exit 3)"* ]]
}

@test "claw_step: stdin is /dev/null so a reader never blocks" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain bash -c "
    source '$PROG'
    _CLAW_PROG_MODE=plain; _CLAW_PROG_OK=0; _CLAW_PROG_FAIL=0; _CLAW_PROG_DONE=0
    _CLAW_PROG_OP=demo; _CLAW_PROG_T0=0
    claw_step 'reader' -- sh -c 'read x; echo \"got=[\$x]\"'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"got=[]"* ]]
}

@test "claw_step: also tees output to a logfile" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" bash -c "
    source '$PROG'
    _CLAW_PROG_MODE=plain; _CLAW_PROG_OK=0; _CLAW_PROG_FAIL=0; _CLAW_PROG_DONE=0
    _CLAW_PROG_OP=demo; _CLAW_PROG_T0=0
    claw_step 'thing' -- sh -c 'echo LOGGED_LINE'
  "
  run grep -rl LOGGED_LINE "$BATS_TEST_TMPDIR/state/claw/logs"
  [ "$status" -eq 0 ]
}

@test "claw_step: rich forced into a pipe returns rc and shows the verdict" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=rich TERM=xterm-256color COLUMNS=60 bash -c "
    source '$PROG'
    _CLAW_PROG_MODE=rich; _CLAW_PROG_OK=0; _CLAW_PROG_FAIL=0; _CLAW_PROG_DONE=0
    _CLAW_PROG_OP=demo; _CLAW_PROG_T0=0
    claw_step 'ok step' -- true; echo \"rc=\$?\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=0"* ]]
  [[ "$output" == *"ok step"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/progress.bats -f "claw_step:"`
Expected: FAIL — `claw_step: command not found`.

- [ ] **Step 3: Implement `claw_step`** — append to `scripts/utils/claw-progress.sh`:

```bash
# ── streaming step runner: stream + collapse-on-success (Task 2) ─────────────
_CLAW_STEP_TAIL_MAX=6
_CLAW_STEP_LABEL=""
_CLAW_STEP_RING=()
_CLAW_STEP_REGION=0

_claw_step_trunc() {  # _claw_step_trunc <text> → single-row, width-clamped
  local w s
  w=$(( $(_claw_cols) - 4 )); (( w < 8 )) && w=8
  s="$1"; s="${s//$'\r'/}"; s="${s//$'\t'/  }"
  if (( ${#s} > w )); then printf '%s…' "${s:0:w-1}"; else printf '%s' "$s"; fi
}

_claw_step_repaint() {  # redraw the live block (header + ring tail) in place
  (( _CLAW_STEP_REGION > 0 )) && printf '\033[%dA\033[J' "$_CLAW_STEP_REGION"
  printf '  %s%s%s %s…\n' "$(_c amber)" "$(_claw_glyph run)" "$(_creset)" "$_CLAW_STEP_LABEL"
  _CLAW_STEP_REGION=1
  local l
  if (( ${#_CLAW_STEP_RING[@]} )); then
    for l in "${_CLAW_STEP_RING[@]}"; do
      printf '  %s│%s %s\n' "$(_c muted)" "$(_creset)" "$l"
      _CLAW_STEP_REGION=$(( _CLAW_STEP_REGION + 1 ))
    done
  fi
}

claw_step() {  # claw_step "<label>" -- <cmd...>
  local label="$1"; shift
  [[ "${1:-}" == "--" ]] && shift
  local log rcf rc line mode
  log="$(_claw_logfile)"
  mode="${_CLAW_PROG_MODE:-$(_claw_prog_detect_mode)}"
  rcf="$(mktemp 2>/dev/null || printf '%s/claw_step.%s' "${TMPDIR:-/tmp}" "$$")"

  if [[ "$mode" != rich ]]; then
    # plain: stream each line with a gutter, then a verdict line
    while IFS= read -r line; do
      printf '  %s│%s %s\n' "$(_c muted)" "$(_creset)" "$line"
    done < <( { "$@" </dev/null 2>&1; printf '%d' "$?" >"$rcf"; } | tee -a "$log" )
    rc="$(cat "$rcf" 2>/dev/null || echo 1)"; rm -f "$rcf"
    if (( rc == 0 )); then
      printf '  %s%s%s %s\n' "$(_c green)" "$(_claw_glyph ok)" "$(_creset)" "$label"
      _CLAW_PROG_OK=$(( _CLAW_PROG_OK + 1 ))
    else
      printf '  %s%s%s %s %s(exit %d)%s\n' "$(_c red)" "$(_claw_glyph fail)" "$(_creset)" "$label" "$(_c muted)" "$rc" "$(_creset)"
      _CLAW_PROG_FAIL=$(( _CLAW_PROG_FAIL + 1 ))
    fi
    _CLAW_PROG_DONE=$(( _CLAW_PROG_DONE + 1 ))
    return "$rc"
  fi

  # rich: moving ≤N-line viewport, collapse on success / retain on failure
  _CLAW_STEP_LABEL="$label"; _CLAW_STEP_RING=(); _CLAW_STEP_REGION=0
  printf '\033[?25l'
  _claw_step_repaint
  while IFS= read -r line; do
    line="$(_claw_step_trunc "$line")"
    _CLAW_STEP_RING+=("$line")
    (( ${#_CLAW_STEP_RING[@]} > _CLAW_STEP_TAIL_MAX )) && _CLAW_STEP_RING=("${_CLAW_STEP_RING[@]:1}")
    _claw_step_repaint
  done < <( { "$@" </dev/null 2>&1; printf '%d' "$?" >"$rcf"; } | tee -a "$log" )
  rc="$(cat "$rcf" 2>/dev/null || echo 1)"; rm -f "$rcf"

  (( _CLAW_STEP_REGION > 0 )) && printf '\033[%dA\033[J' "$_CLAW_STEP_REGION"
  if (( rc == 0 )); then
    printf '  %s%s%s %s\n' "$(_c green)" "$(_claw_glyph ok)" "$(_creset)" "$label"
    _CLAW_PROG_OK=$(( _CLAW_PROG_OK + 1 ))
  else
    printf '  %s%s%s %s %s(exit %d)%s\n' "$(_c red)" "$(_claw_glyph fail)" "$(_creset)" "$label" "$(_c muted)" "$rc" "$(_creset)"
    if (( ${#_CLAW_STEP_RING[@]} )); then
      for line in "${_CLAW_STEP_RING[@]}"; do
        printf '  %s│%s %s\n' "$(_c muted)" "$(_creset)" "$line"
      done
    fi
    _CLAW_PROG_FAIL=$(( _CLAW_PROG_FAIL + 1 ))
  fi
  printf '\033[?25h'
  _CLAW_PROG_DONE=$(( _CLAW_PROG_DONE + 1 ))
  return "$rc"
}
```

Notes for the implementer:
- The rc-capture ordering is deliberate: inside `{ "$@"; printf $? >"$rcf"; } | tee`, the `printf >"$rcf"` runs after the command and before the brace subshell closes its stdout, so `tee` only sees EOF (ending the `while`) after `$rcf` is written. No race.
- Process substitution `< <( … )` keeps the `while` loop in the current shell, so `_CLAW_PROG_*` and `_CLAW_STEP_*` updates persist (a plain pipe `… | while` would lose them to a subshell).
- `\033[J` clears cursor-to-end-of-screen; the live block is always the last thing on screen, so nothing below is destroyed.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/progress.bats -f "claw_step:"`
Expected: PASS (6 tests)

- [ ] **Step 5: Lint + full regression**

Run: `shellcheck -x scripts/utils/claw-progress.sh && bats tests/progress.bats`
Expected: no new shellcheck warnings; all progress tests pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/utils/claw-progress.sh tests/progress.bats
git commit -m "feat(progress): claw_step streaming runner (stream + collapse)"
```

---

### Task 3: Add themed chrome helpers `claw_ui_*`

**Files:**
- Modify: `scripts/utils/claw-progress.sh` (append after `claw_step`)
- Test: `tests/progress.bats` (append)

**Interfaces:**
- Consumes: `_c`, `_claw_glyph`, `_creset`, `_claw_dur`, `claw_frame_top`, `claw_frame_bottom`, `_claw_prog_detect_mode`, tally globals.
- Produces:
  - `claw_ui_header "<TITLE>" ["<subtitle>"]` — resets tallies + `_CLAW_PROG_T0` + `_CLAW_PROG_MODE` + `_CLAW_PROG_OP`, prints `claw_frame_top` + bold title (+ dim subtitle).
  - `claw_ui_section "<Title>"` — blank line + purple label.
  - `claw_ui_skip "<name>"` — dim "· <name> — not installed", increments `_CLAW_PROG_SKIP`.
  - `claw_ui_footer ["<message>"]` — tally summary (`✓ok ✗fail ·skip · dur`) + `claw_frame_bottom` (+ optional green message).
  - `claw_ui_pause` — "press any key" when `INTERACTIVE=1`.

- [ ] **Step 1: Write the failing tests** — append to `tests/progress.bats`:

```bash
@test "claw_ui_header: prints title, subtitle, and a viewfinder top corner" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env COLUMNS=50 TERM=xterm-256color bash -c "
    source '$PROG'; claw_ui_header 'SYSTEM UPDATE' 'updating everything'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"SYSTEM UPDATE"* ]]
  [[ "$output" == *"updating everything"* ]]
  [[ "$output" == *$'\xE2\x8C\x9C'* ]]   # ⌜
}

@test "claw_ui_footer: prints tally summary, bottom corner, and message" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env COLUMNS=50 TERM=xterm-256color CLAW_OUTPUT_MODE=plain bash -c "
    source '$PROG'
    claw_ui_header demo
    claw_step a -- true
    claw_step b -- false
    claw_ui_footer 'Update complete'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\xE2\x9C\x93'"1"* ]]   # ✓1
  [[ "$output" == *$'\xE2\x9C\x97'"1"* ]]   # ✗1
  [[ "$output" == *"Update complete"* ]]
  [[ "$output" == *$'\xE2\x8C\x9F'* ]]      # ⌟
}

@test "claw_ui_skip: reports not installed and tallies a skip" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env COLUMNS=50 TERM=xterm-256color bash -c "
    source '$PROG'
    claw_ui_header demo
    claw_ui_skip brew
    claw_ui_footer done
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew — not installed"* ]]
  [[ "$output" == *$'\xC2\xB7'"1"* ]]       # ·1 skip in the tally
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/progress.bats -f "claw_ui_"`
Expected: FAIL — `claw_ui_header: command not found`.

- [ ] **Step 3: Implement the chrome helpers** — append to `scripts/utils/claw-progress.sh`:

```bash
# ── themed chrome for the update surfaces (Task 3) ───────────────────────────
claw_ui_header() {  # claw_ui_header "<TITLE>" ["<subtitle>"]
  _CLAW_PROG_OP="$1"
  _CLAW_PROG_OK=0; _CLAW_PROG_FAIL=0; _CLAW_PROG_SKIP=0; _CLAW_PROG_DONE=0
  _CLAW_PROG_T0="$(date +%s)"
  _CLAW_PROG_MODE="$(_claw_prog_detect_mode)"
  claw_frame_top
  printf '  \033[1m%s%s%s\n' "$(_c blue)" "$1" "$(_creset)"
  [[ -n "${2:-}" ]] && printf '  %s%s%s\n' "$(_c muted)" "$2" "$(_creset)"
}

claw_ui_section() {  # claw_ui_section "<Title>"
  printf '\n  %s%s%s\n' "$(_c purple)" "$1" "$(_creset)"
}

claw_ui_skip() {  # claw_ui_skip "<name>"
  printf '  %s%s %s — not installed%s\n' "$(_c muted)" "$(_claw_glyph skip)" "$1" "$(_creset)"
  _CLAW_PROG_SKIP=$(( _CLAW_PROG_SKIP + 1 ))
}

claw_ui_footer() {  # claw_ui_footer ["<message>"]
  local dur; dur="$(_claw_dur $(( $(date +%s) - _CLAW_PROG_T0 )))"
  printf '  %s%s%d%s %s%s%d%s %s%s%d%s %s· %s%s\n' \
    "$(_c green)" "$(_claw_glyph ok)"   "$_CLAW_PROG_OK"   "$(_creset)" \
    "$(_c red)"   "$(_claw_glyph fail)" "$_CLAW_PROG_FAIL" "$(_creset)" \
    "$(_c muted)" "$(_claw_glyph skip)" "$_CLAW_PROG_SKIP" "$(_creset)" \
    "$(_c muted)" "$dur" "$(_creset)"
  claw_frame_bottom
  [[ -n "${1:-}" ]] && printf '  %s%s %s%s\n' "$(_c green)" "$(_claw_glyph ok)" "$1" "$(_creset)"
}

claw_ui_pause() {
  [[ "${INTERACTIVE:-1}" -eq 1 ]] || return 0
  printf '  %sPress any key to continue...%s' "$(_c muted)" "$(_creset)"
  if [[ -n "${ZSH_VERSION:-}" ]]; then read -k 1; else read -r -n 1 -s; fi
  echo ""
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/progress.bats -f "claw_ui_"`
Expected: PASS (3 tests)

- [ ] **Step 5: Lint + full regression**

Run: `shellcheck -x scripts/utils/claw-progress.sh && bats tests/progress.bats`
Expected: clean; all progress tests pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/utils/claw-progress.sh tests/progress.bats
git commit -m "feat(progress): themed claw_ui_ header/section/footer/skip/pause"
```

---

### Task 4: Redirect `tui_run_step` to `claw_step` (kill blackout for other consumers)

**Files:**
- Modify: `scripts/utils/tui-style.sh` (add a source line near the top; replace the `tui_run_step` body at `:85-108`)
- Test: `tests/progress.bats` (append)

**Interfaces:**
- Consumes: `claw_step` (Task 2) from `claw-progress.sh`.
- Produces: `tui_run_step "<title>" "<cmd-string>"` — unchanged signature (command is a single eval string), but now streams output via `claw_step … -- bash -c "<cmd-string>"` instead of hiding it under `gum spin`. Existing `c_*` color exports and `tui_header`/`tui_section`/`tui_footer`/`tui_skip`/`tui_pause` are untouched (integrity/storage-doctor/welcome-tui keep their rounded-box chrome).

- [ ] **Step 1: Write the failing tests** — append to `tests/progress.bats`:

```bash
@test "tui_run_step: now streams tool output to the screen (no blackout)" {
  TUI="$BATS_TEST_DIRNAME/../scripts/utils/tui-style.sh"
  run env CLAW_OUTPUT_MODE=plain bash -c "source '$TUI'; tui_run_step 'label' 'echo STREAMED_OUT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STREAMED_OUT"* ]]
  [[ "$output" == *"label"* ]]
}

@test "tui_run_step: returns the command exit code" {
  TUI="$BATS_TEST_DIRNAME/../scripts/utils/tui-style.sh"
  run env CLAW_OUTPUT_MODE=plain bash -c "source '$TUI'; tui_run_step 'x' 'exit 4'; echo \"rc=\$?\""
  [[ "$output" == *"rc=4"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/progress.bats -f "tui_run_step:"`
Expected: FAIL — with no tty, the current `tui_run_step` runs `eval "$*" >/dev/null` and swallows `STREAMED_OUT`.

- [ ] **Step 3: Source claw-progress.sh in tui-style.sh**

After the `HAS_GUM` block in `scripts/utils/tui-style.sh` (i.e. after line 39), add:

```bash
# Streaming step runner lives in claw-progress.sh (single render path). Sourcing
# it here routes tui_run_step through claw_step, so every tui-style consumer
# streams process output instead of hiding it. Guarded: absence is non-fatal.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/claw-progress.sh" 2>/dev/null || true
```

- [ ] **Step 4: Replace the `tui_run_step` body**

Replace `scripts/utils/tui-style.sh:85-108` (the whole `tui_run_step()` function) with:

```bash
# tui_run_step "title" "command…"
# Delegates to claw_step (streaming). The command stays a single eval string for
# backward-compat with existing callers; we run it via `bash -c` (matching the
# old gum path's `bash -c "$*"` semantics). No more gum spin, no more blackout.
tui_run_step() {
    local title="$1"; shift
    if command -v claw_step &>/dev/null; then
        claw_step "$title" -- bash -c "$*"
        return $?
    fi
    # Fallback if claw-progress.sh was unavailable at source time: run visibly.
    printf "  ${c_cyan}◌${c_reset} ${c_white}%s${c_reset}\n" "$title"
    bash -c "$*" </dev/null
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/progress.bats -f "tui_run_step:"`
Expected: PASS (2 tests)

- [ ] **Step 6: Consumer syntax + smoke check**

Run:
```bash
shellcheck -x scripts/utils/tui-style.sh
bash -n scripts/utils/integrity.sh scripts/utils/storage-doctor.sh
bats tests/progress.bats
```
Expected: shellcheck clean; `bash -n` reports no syntax errors; all progress tests pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/utils/tui-style.sh tests/progress.bats
git commit -m "refactor(tui): tui_run_step streams via claw_step (drop gum blackout)"
```

---

### Task 5: Migrate `system-update.sh` to the streaming chrome

**Files:**
- Modify: `scripts/utils/system-update.sh` (replace the `tui-style.sh` source with `theme.sh` + `claw-progress.sh`; swap every `tui_*` call)
- Test: `tests/progress.bats` (append — structural + syntax, NOT an end-to-end run: this script would actually upgrade the machine)

**Interfaces:**
- Consumes: `claw_ui_header/section/skip/footer/pause` (Task 3), `claw_step` (Task 2).
- Produces: `claw update`/`claw upgrade` output rendered as the streaming viewfinder view.

**Why no end-to-end test:** running `system-update.sh` executes real `brew upgrade`/`npm update`/etc. Tests assert structure (no `tui_*` residue, sources the engine) + `bash -n`; behavior is covered by the engine's own tests and the manual smoke in Step 6.

- [ ] **Step 1: Write the failing tests** — append to `tests/progress.bats`:

```bash
@test "system-update: sources the streaming engine, not tui-style" {
  SU="$BATS_TEST_DIRNAME/../scripts/utils/system-update.sh"
  run grep -c 'claw-progress.sh' "$SU"; [ "$output" -ge 1 ]
  run grep -c 'tui-style.sh'    "$SU"; [ "$output" -eq 0 ]
}

@test "system-update: no legacy tui_ calls remain" {
  SU="$BATS_TEST_DIRNAME/../scripts/utils/system-update.sh"
  run grep -cE 'tui_(run_step|header|section|footer|skip|pause)' "$SU"
  [ "$output" -eq 0 ]
}

@test "system-update: parses cleanly" {
  SU="$BATS_TEST_DIRNAME/../scripts/utils/system-update.sh"
  run bash -n "$SU"; [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/progress.bats -f "system-update:"`
Expected: FAIL — the file still sources `tui-style.sh` and calls `tui_*`.

- [ ] **Step 3: Swap the source line**

In `scripts/utils/system-update.sh`, replace the source block at `:6-7`:

```bash
# Shared TUI helpers (theme + run_step + section + header/footer + pause)
source "$(dirname "${BASH_SOURCE[0]}")/tui-style.sh"
```

with:

```bash
# Theme engine (CLAW_RGB_*) + streaming progress chrome (single render path).
source "$(dirname "${BASH_SOURCE[0]}")/theme.sh" 2>/dev/null || true
source "$(dirname "${BASH_SOURCE[0]}")/claw-progress.sh"
```

- [ ] **Step 4: Swap the chrome + step calls**

Apply these exact substitutions throughout `scripts/utils/system-update.sh`:
- `tui_header "<A>" "<B>"` → `claw_ui_header "<A>" "<B>"` (line 28)
- every `tui_section "<X>"` → `claw_ui_section "<X>"`
- every `tui_skip "<X>"` → `claw_ui_skip "<X>"`
- `tui_footer "✓ Update complete"` → `claw_ui_footer "Update complete"` (line 166)
- `tui_pause` → `claw_ui_pause` (line 167)
- every `tui_run_step "<LABEL>" "<CMD>"` → `claw_step "<LABEL>" -- bash -c "<CMD>"`

Example — the Homebrew block (`:72-79`) becomes:

```bash
claw_ui_section "Homebrew"
if command -v brew &>/dev/null; then
    claw_step "Updating Homebrew formulae index..." -- bash -c "brew update"
    claw_step "Upgrading outdated packages..." -- bash -c "brew upgrade"
    claw_step "Cleaning up old versions..." -- bash -c "brew cleanup --prune=7"
else
    claw_ui_skip "brew"
fi
```

Note the one non-`tui_run_step` line at `:148` (`printf "  ${c_dim}○ Go binary managed…"`): replace `${c_dim}`/`${c_reset}` with `$(_c muted)`/`$(_creset)` since `c_dim` no longer exists:

```bash
    printf "  %s○ Go binary managed by brew/system package manager%s\n" "$(_c muted)" "$(_creset)"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/progress.bats -f "system-update:"`
Expected: PASS (3 tests)

- [ ] **Step 6: Manual smoke (operator, safe subset)**

Run (plain mode, non-interactive — this DOES update real packages, so run when ready):
`CLAW_OUTPUT_MODE=plain claw update --non-interactive 2>&1 | tail -40`
Expected: framed header, per-step `│` streamed lines, `●`/`✗` verdicts, tally footer — no blackout, no hang. Also confirm a piped run (`claw update --non-interactive | cat`) shows no cursor-escape garbage.

- [ ] **Step 7: Commit**

```bash
git add scripts/utils/system-update.sh tests/progress.bats
git commit -m "feat(update): claw update streams live via claw-progress engine"
```

---

### Task 6: Migrate `tool-updater.sh` interactive mode

**Files:**
- Modify: `scripts/utils/tool-updater.sh` (interactive block `:141-228`)
- Test: `tests/progress.bats` (append — structural + syntax)

**Interfaces:**
- Consumes: `claw_ui_header/section/skip` (Task 3), `claw_step` (Task 2), `_c`/`_creset` (Task 1) for the bespoke category summary card.
- Produces: `claw update --tools` / `claw tools` rendered as the streaming view.

- [ ] **Step 1: Write the failing tests** — append to `tests/progress.bats`:

```bash
@test "tool-updater: sources the streaming engine, not tui-style" {
  TU="$BATS_TEST_DIRNAME/../scripts/utils/tool-updater.sh"
  run grep -c 'claw-progress.sh' "$TU"; [ "$output" -ge 1 ]
  run grep -c 'tui-style.sh'    "$TU"; [ "$output" -eq 0 ]
}

@test "tool-updater: no legacy tui_ calls remain" {
  TU="$BATS_TEST_DIRNAME/../scripts/utils/tool-updater.sh"
  run grep -cE 'tui_(run_step|header|section|footer|skip|pause)' "$TU"
  [ "$output" -eq 0 ]
}

@test "tool-updater: parses cleanly" {
  TU="$BATS_TEST_DIRNAME/../scripts/utils/tool-updater.sh"
  run bash -n "$TU"; [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/progress.bats -f "tool-updater:"`
Expected: FAIL — still on `tui-style.sh`.

- [ ] **Step 3: Swap the source line** (`tool-updater.sh:144`)

Replace:
```bash
source "$(dirname "${BASH_SOURCE[0]}")/tui-style.sh"
```
with:
```bash
source "$(dirname "${BASH_SOURCE[0]}")/theme.sh" 2>/dev/null || true
source "$(dirname "${BASH_SOURCE[0]}")/claw-progress.sh"
```

- [ ] **Step 4: Swap the chrome + step calls** in the interactive block (`:141-228`)

- `tui_header "<A>" "<B>"` (both branches) → `claw_ui_header "<A>" "<B>"`
- `tui_section "$pretty"` → `claw_ui_section "$pretty"`
- `tui_skip "$name"` → `claw_ui_skip "$name"`
- The step call at `:53` — `if tui_run_step "Upgrading ${label}…" "run_$name $tool"; then` — becomes (argv form so the local `run_$name` function is visible in the in-shell subshell; `bash -c` would NOT see it):

```bash
            if claw_step "Upgrading ${label}…" -- "run_$name" "$tool"; then
```

- [ ] **Step 5: Recolor the summary card + deferred lines**

The bespoke summary card (`:71-89`) and the deferred lines (`:62-63`) reference `c_purple`/`c_green`/`c_orange`/`c_red`/`c_dim`/`c_reset`/`c_bold`/`c_white` from the now-removed `tui-style.sh`. Replace those with `_c`/`_creset` from the engine. Bold is `\033[1m`. Substitute:
- `${c_purple}` → `$(_c purple)`, `${c_green}` → `$(_c green)`, `${c_orange}` → `$(_c amber)`, `${c_red}` → `$(_c red)`, `${c_dim}` → `$(_c muted)`, `${c_white}` → `$(_c blue)`, `${c_reset}` → `$(_creset)`, `${c_bold}` → `$(printf '\033[1m')` (or fold `\033[1m` into the adjacent `printf` format string).

Example — the deferred lines (`:62-63`) become:
```bash
        printf "  %s○ %s — next update in %s%s\n" "$(_c muted)" "$name" "$local_due" "$(_creset)"
        printf "    %sdeferred: %s%s\n" "$(_c muted)" "$tools" "$(_creset)"
```

Keep the hand-drawn `╭─╮`/`╰─╯` box geometry as-is; only the color tokens change.

- [ ] **Step 6: Run tests to verify they pass**

Run: `bats tests/progress.bats -f "tool-updater:"`
Expected: PASS (3 tests)

- [ ] **Step 7: Manual smoke (operator)**

Run: `CLAW_OUTPUT_MODE=plain claw tools --force 2>&1 | tail -40`
Expected: framed header, streamed `│` lines per tool, `●`/`✗` verdicts, intact summary card with themed colors. Then `claw tools --force | cat` — no escape-sequence garbage.

- [ ] **Step 8: Full suite + lint + commit**

```bash
shellcheck -x scripts/utils/tool-updater.sh
bats tests/progress.bats
git add scripts/utils/tool-updater.sh tests/progress.bats
git commit -m "feat(tools): claw update --tools streams live via claw-progress"
```

---

## Self-Review

**Spec coverage:**
- Render model (stream + collapse) → Task 2. ✓
- Engine home = claw-progress.sh → Tasks 1-3. ✓
- Both surfaces migrated → Tasks 5, 6. ✓
- `tui_run_step` delegates (kills blackout for other consumers) → Task 4. ✓
- `_c()` theme fix (CLAW_RGB_*) → Task 1. ✓
- Frame honors claw-output (viewfinder/none) → reused existing `claw_frame_top/bottom` (no change needed). ✓
- Safety: `</dev/null`, stream-not-hide, bounded/truncated redraw, tee to logfile → Task 2. ✓
- ASCII glyph fallback → existing `_claw_glyph` (Task 3 tests exercise unicode; ASCII path already covered by existing `frame: dumb terminal` test). ✓
- Testing matrix (plain/rich/failure/width/theme/deadlock/both surfaces) → Tasks 2-6 tests + manual smokes. ✓
- Out of scope (selfupdate, pkg-manifest panel) → untouched. ✓

**Placeholder scan:** none — every code step shows complete content.

**Type/name consistency:** `claw_step`, `claw_ui_header/section/skip/footer/pause`, `_c`, `_claw_step_trunc`, `_claw_step_repaint`, `_CLAW_STEP_RING/REGION/LABEL/TAIL_MAX`, tally globals `_CLAW_PROG_OK/FAIL/SKIP/DONE`/`_CLAW_PROG_OP`/`_CLAW_PROG_T0`/`_CLAW_PROG_MODE` used consistently across tasks. `claw_ui_header` sets `_CLAW_PROG_MODE`, which `claw_step` reads. ✓
