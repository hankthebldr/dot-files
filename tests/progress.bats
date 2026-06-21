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

@test "claw output: dispatches through bin/claw" {
  run env DOTFILES_DIR="$BATS_TEST_DIRNAME/.." bash "$BATS_TEST_DIRNAME/../bin/claw" output status
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode"* ]]
}

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

@test "engine: plain mode emits clean per-item lines + summary" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain TERM=xterm-256color bash -c "
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
  run env CLAW_OUTPUT_MODE=plain TERM=xterm-256color bash -c "
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
