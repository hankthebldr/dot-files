#!/usr/bin/env bats
# Login-path integration tests driven through a real pty
# (tests/fixtures/pty_login.py forks `zsh -i` against a generated rc that
# sources the repo's shell/.zshrc inside a hermetic HOME).
#
# audit 2026-09-20 F-01/F-25: Ctrl-C during the step-3 dashboard render killed
# .zshrc mid-file. The shell survived, but steps 4-8 never ran — no aliases, no
# claw(), no p10k — a login that looks crashed. Pinned here: an rc-scoped
# `trap ':' INT` (step 1) released by `trap - INT` on the last line, so an
# interrupt costs you the render and nothing else, and the interactive shell
# is handed back with the DEFAULT INT disposition.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HARNESS="$BATS_TEST_DIRNAME/fixtures/pty_login.py"
  # Real oh-my-zsh checkout (if any) resolved BEFORE HOME is redirected.
  REAL_OMZ="${ZSH:-$HOME/.oh-my-zsh}"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/share"
  export CLAW_NO_LOG=1
  mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
}

# Skip whole-file when the harness cannot run here (CI without python3/pty).
require_pty() {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  command -v zsh     >/dev/null 2>&1 || skip "zsh not available"
  python3 -c 'import pty, termios, fcntl' 2>/dev/null || skip "pty/termios unavailable"
}

# login <run-dir> [extra pty_login.py args...]
# Always probes the two "did the rc finish?" symbols plus the live INT trap
# count (`command grep`: aliases.zsh maps bare grep to rg).
login() {
  local dir="$BATS_TEST_TMPDIR/$1"; shift
  mkdir -p "$dir"
  local -a omz=()
  [ -f "$REAL_OMZ/oh-my-zsh.sh" ] && omz=(--omz "$REAL_OMZ")
  run python3 "$HARNESS" --repo "$REPO" --zdotdir "$dir" "${omz[@]}" \
      --timeout 45 \
      --probe 'print "PROBE_ALIAS=$(alias ll >/dev/null 2>&1 && echo yes || echo no)"' \
      --probe 'print "PROBE_CLAW=$(typeset -f claw >/dev/null 2>&1 && echo yes || echo no)"' \
      --probe 'print "PROBE_INTTRAP=$(trap | command grep -c INT)"' \
      "$@"
}

# --- (a) interrupted login --------------------------------------------------

@test "login: Ctrl-C at 300ms leaves the shell fully initialised" {
  require_pty
  login int300 --send-int-at 300
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"__PROMPT__"* ]]
  [[ "$output" == *"PROBE_ALIAS=yes"* ]]
  [[ "$output" == *"PROBE_CLAW=yes"* ]]
}

# --- (b) control run --------------------------------------------------------

@test "login: uninterrupted login reaches the same state" {
  require_pty
  login control
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"__PROMPT__"* ]]
  [[ "$output" == *"PROBE_ALIAS=yes"* ]]
  [[ "$output" == *"PROBE_CLAW=yes"* ]]
}

# --- (c) the guard is rc-scoped, not leaked ---------------------------------

@test "login: no INT trap survives into the interactive shell" {
  require_pty
  login trapscope
  echo "$output"
  [ "$status" -eq 0 ]
  # `trap` with no args lists live handlers; INT must not be among them.
  [[ "$output" == *"PROBE_INTTRAP=0"* ]]
}

@test "login: Ctrl-C at 300ms also leaves no INT trap behind" {
  require_pty
  login int300trap --send-int-at 300
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROBE_INTTRAP=0"* ]]
}

# --- static contract on the rc itself (runs everywhere, no pty needed) ------

@test "zshrc: arms 'trap : INT' in step 1 and releases it on the last line" {
  local rc="$REPO/shell/.zshrc"
  run grep -n "^trap ':' INT$" "$rc"
  echo "$output"
  [ "$status" -eq 0 ]
  # release must be the last non-empty line of the file
  run bash -c "grep -v '^[[:space:]]*\$' '$rc' | tail -n 1"
  echo "$output"
  [ "$output" = "trap - INT" ]
}

@test "zshrc: parses under zsh -n" {
  run zsh -n "$REPO/shell/.zshrc"
  echo "$output"
  [ "$status" -eq 0 ]
}
