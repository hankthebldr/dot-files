#!/usr/bin/env bats
# Hardening tests for the Open Claw shell engines. Run: bats tests/

setup() {
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export USER="${USER:-tester}"
  export HOME="$BATS_TEST_TMPDIR"
  mkdir -p "$HOME"
}

@test "pkg-manifest: add then list shows the tool" {
  export DOTFILES_DIR="$BATS_TEST_TMPDIR/df"; mkdir -p "$DOTFILES_DIR/config/manifest" "$DOTFILES_DIR/scripts/utils"
  cp "$BATS_TEST_DIRNAME/../scripts/utils/cinematic.sh" "$DOTFILES_DIR/scripts/utils/" 2>/dev/null || true
  cp "$BATS_TEST_DIRNAME/../scripts/utils/detect-os.sh" "$DOTFILES_DIR/scripts/utils/" 2>/dev/null || true
  run bash "$BATS_TEST_DIRNAME/../scripts/utils/pkg-manifest.sh" add ripgrep cargo
  [ "$status" -eq 0 ]
  run bash "$BATS_TEST_DIRNAME/../scripts/utils/pkg-manifest.sh" list
  [[ "$output" == *"ripgrep"* ]]
}

@test "toolchain-runner: dry-run renders summary and installs nothing" {
  run env DRY_RUN=1 USER=tester bash "$BATS_TEST_DIRNAME/../scripts/install/cloud-toolchain.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"install summary"* ]]
  [[ "$output" == *"DRY:"* ]]
}

@test "capture-tasks: extracts @things line and emits a things:/// url" {
  v="$BATS_TEST_TMPDIR/vault"; mkdir -p "$v"
  printf -- '- [ ] ship it @things ^list:Work\n- [ ] not this\n' > "$v/n.md"
  run env OBSIDIAN_VAULT="$v" bash "$BATS_TEST_DIRNAME/../scripts/utils/capture-tasks.sh" "$v"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ship it"* ]]
  [[ "$output" == *"things:///add"* ]]
  [[ "$output" == *"1 actionable"* ]]
}

@test "mcp-sync: security server gated out by default, included with --all" {
  run python3 "$BATS_TEST_DIRNAME/../scripts/utils/mcp-sync.py" --dry-run --only gemini
  [[ "$output" != *"shodan"* ]]
  run python3 "$BATS_TEST_DIRNAME/../scripts/utils/mcp-sync.py" --dry-run --only gemini --all
  [[ "$output" == *"shodan"* ]]
}

@test "cheatsheet: runs and lists core commands" {
  run bash "$BATS_TEST_DIRNAME/../scripts/utils/cheatsheet.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claw provision"* ]]
  [[ "$output" == *"claw secret"* ]]
}

@test "claw-dashboard: renders a framed dashboard with system info + OPEN CLAW title" {
  run env DOTFILES_DIR="$BATS_TEST_DIRNAME/.." USER=tester python3 "$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OPEN CLAW"* ]]   # title in the frame
  [[ "$output" == *"OS"* ]]          # readout present
  [[ "$output" == *"╭"* ]]           # framed
}
