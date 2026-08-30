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

@test "pkg-manifest: npm parse keeps @scope and drops the --parseable root line" {
  # Regression: `sed 's#.*/##'` took the basename, which flattened
  # @anthropic-ai/claude-agent-sdk to claude-agent-sdk (a DIFFERENT package on
  # install) and turned npm's prefix root line into a phantom tool `lib`.
  df="$BATS_TEST_TMPDIR/df"; mkdir -p "$df/config/manifest" "$df/scripts/utils"
  for f in cinematic.sh detect-os.sh claw-progress.sh; do
    cp "$BATS_TEST_DIRNAME/../scripts/utils/$f" "$df/scripts/utils/" 2>/dev/null || true
  done
  : > "$df/config/manifest/tools.list"

  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  cat > "$stub/npm" <<'SH'
#!/usr/bin/env bash
# `npm ls -g --depth=0 --parseable` emits the prefix ROOT first, then one
# absolute path per installed package.
printf '%s\n' /opt/homebrew/lib \
               /opt/homebrew/lib/node_modules/npm \
               /opt/homebrew/lib/node_modules/@anthropic-ai/claude-agent-sdk \
               /opt/homebrew/lib/node_modules/defuddle
SH
  chmod +x "$stub/npm"

  # PATH without brew/cargo/pipx so npm is the only live discovery channel.
  run env DOTFILES_DIR="$df" HOME="$BATS_TEST_TMPDIR" PATH="$stub:/usr/bin:/bin" \
      bash "$BATS_TEST_DIRNAME/../scripts/utils/pkg-manifest.sh" scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"@anthropic-ai/claude-agent-sdk"* ]]   # scope survives
  [[ "$output" == *"defuddle"* ]]                          # unscoped still works
  [[ "$output" != *"    lib"* ]]                           # root line is not a tool
  [[ "$output" != *"    npm"* ]]                           # npm itself stays filtered
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

@test "claw upgrade: aliases claw update (routes to system-update, not the agent runner)" {
  DF="$BATS_TEST_TMPDIR/df"; mkdir -p "$DF/scripts/utils"
  # stub the updater so the dispatch is exercised without a real system upgrade
  printf '#!/usr/bin/env bash\necho "SYSTEM_UPDATE_RAN $*"\n' > "$DF/scripts/utils/system-update.sh"
  run env DOTFILES_DIR="$DF" bash "$BATS_TEST_DIRNAME/../bin/claw" upgrade
  [ "$status" -eq 0 ]
  [[ "$output" == *"SYSTEM_UPDATE_RAN"* ]]
  [[ "$output" != *"unknown subcommand"* ]]
}
