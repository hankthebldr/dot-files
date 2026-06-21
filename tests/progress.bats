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
