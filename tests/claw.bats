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

# Regression for the WiFi-detection bug: macOS 14.4+ removed `airport` and made
# `networksetup -getairportnetwork` always say "not associated", so the dashboard
# read "offline" while connected. The fix reads the SSID from `ipconfig getsummary`;
# these pin the parser (the part that's testable without a real Wi-Fi radio / mac).
@test "ff-readout wifi: SSID parser extracts the SSID from ipconfig getsummary output" {
  src="$BATS_TEST_DIRNAME/../scripts/utils/ff-readout.sh"
  run bash -c 'set -- _none_; source "'"$src"'" >/dev/null 2>&1
    printf "%s\n" "  BSSID : aa:bb:cc:dd:ee:ff" "  SSID : Cafe WiFi 5G" "  Security : WPA2 Personal" | _ffr_ssid_from_summary'
  [ "$status" -eq 0 ]
  [ "$output" = "Cafe WiFi 5G" ]
}

@test "ff-readout wifi: SSID parser is empty for the not-associated string (drives link-state fallback)" {
  src="$BATS_TEST_DIRNAME/../scripts/utils/ff-readout.sh"
  run bash -c 'set -- _none_; source "'"$src"'" >/dev/null 2>&1
    printf "%s\n" "You are not associated with an AirPort network." | _ffr_ssid_from_summary'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
