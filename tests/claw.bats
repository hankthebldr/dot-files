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
  [[ "$output" == *"tester@"* ]]     # header identity present
  [[ "$output" == *"attention"* ]]   # the attention block is on the login card
  [[ "$output" == *"╭"* ]]           # framed
  # The static OS/Kernel/Host/Locale cells moved to `claw specs` (audit F-09):
  # 10 of the old 16 grid cells were facts about the machine that never change.
  [[ "$output" != *"Locale"* ]]
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

# ---------------------------------------------------------------------------
# audit 2026-09-20 F-15/F-16/F-18 — bin/claw's user-facing surfaces are
# generated from the registry, the four owed dispatch arms exist, and
# `claw menu` is a hint instead of a child zsh that silently no-ops.
# ---------------------------------------------------------------------------

REPO_ROOT() { cd "$BATS_TEST_DIRNAME/.." && pwd; }

@test "claw menu: prints the in-shell hint and never spawns a child zsh" {
  repo="$(REPO_ROOT)"
  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/usr/bin/env bash\ntouch "%s/zsh.spawned"\n' "$BATS_TEST_TMPDIR" > "$stub/zsh"
  chmod +x "$stub/zsh"
  run env DOTFILES_DIR="$repo" CLAW_NO_LOG=1 PATH="$stub:$PATH" bash "$repo/bin/claw" menu
  [ "$status" -eq 0 ]
  [[ "$output" == *"claw"* ]]
  [[ "$output" == *"^G"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/zsh.spawned" ]
}

@test "claw pin: writes the login-profile file, prints it, and --clear removes it" {
  repo="$(REPO_ROOT)"
  cfg="$BATS_TEST_TMPDIR/config"
  run env DOTFILES_DIR="$repo" CLAW_NO_LOG=1 XDG_CONFIG_HOME="$cfg" bash "$repo/bin/claw" pin security
  [ "$status" -eq 0 ]
  [ "$(cat "$cfg/claw/login-profile")" = "security" ]

  run env DOTFILES_DIR="$repo" CLAW_NO_LOG=1 XDG_CONFIG_HOME="$cfg" bash "$repo/bin/claw" pin
  [ "$status" -eq 0 ]
  [[ "$output" == *"security"* ]]

  run env DOTFILES_DIR="$repo" CLAW_NO_LOG=1 XDG_CONFIG_HOME="$cfg" bash "$repo/bin/claw" pin --clear
  [ "$status" -eq 0 ]
  [ ! -e "$cfg/claw/login-profile" ]
}

@test "claw pin: an unknown profile is refused and writes nothing" {
  repo="$(REPO_ROOT)"
  cfg="$BATS_TEST_TMPDIR/config"
  run env DOTFILES_DIR="$repo" CLAW_NO_LOG=1 XDG_CONFIG_HOME="$cfg" bash "$repo/bin/claw" pin wombat
  [ "$status" -ne 0 ]
  [ ! -e "$cfg/claw/login-profile" ]
}

@test "claw ack: appends <id> TAB until-epoch to acks.tsv" {
  repo="$(REPO_ROOT)"
  st="$BATS_TEST_TMPDIR/state"; ca="$BATS_TEST_TMPDIR/cache"
  run env DOTFILES_DIR="$repo" CLAW_NO_LOG=1 XDG_STATE_HOME="$st" XDG_CACHE_HOME="$ca" \
      bash "$repo/bin/claw" ack svc:ms-01:gitea --hours 1
  [ "$status" -eq 0 ]
  [ -s "$st/claw/acks.tsv" ]
  line="$(tail -1 "$st/claw/acks.tsv")"
  [ "$(printf '%s' "$line" | cut -f1)" = "svc:ms-01:gitea" ]
  until_epoch="$(printf '%s' "$line" | cut -f2)"
  now="$(date +%s)"
  [ "$until_epoch" -gt "$now" ]
  [ "$until_epoch" -le "$(( now + 3700 ))" ]
}

@test "claw ack: no id is a usage error" {
  repo="$(REPO_ROOT)"
  run env DOTFILES_DIR="$repo" CLAW_NO_LOG=1 XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" \
      bash "$repo/bin/claw" ack
  [ "$status" -ne 0 ]
  [[ "$output" == *"claw ack"* ]]
}

@test "claw registry: forwards to registry.sh" {
  repo="$(REPO_ROOT)"
  run env DOTFILES_DIR="$repo" CLAW_NO_LOG=1 bash "$repo/bin/claw" registry ids profiles
  [ "$status" -eq 0 ]
  [[ "$output" == *"security"* ]]
  [[ "$output" == *"default"* ]]
}

@test "claw help: Profiles and verbs come from the registry" {
  repo="$(REPO_ROOT)"
  run env DOTFILES_DIR="$repo" CLAW_NO_LOG=1 NO_COLOR=1 bash "$repo/bin/claw" help
  [ "$status" -eq 0 ]
  # registry groups, not the old hand-maintained sections
  [[ "$output" == *"core"* ]]
  [[ "$output" == *"domain"* ]]
  [[ "$output" == *"system"* ]]
  # every profile id is listed, including the ones the old help never named
  for p in security cortex blackwell tunnels; do
    [[ "$output" == *"$p"* ]]
  done
  [[ "$output" == *"Config:"* ]]
}

@test "claw log_usage: rows carry a 5th column with term and actor" {
  repo="$(REPO_ROOT)"
  ca="$BATS_TEST_TMPDIR/cache"
  run env DOTFILES_DIR="$repo" XDG_CACHE_HOME="$ca" CLAW_NO_LOG=0 \
      TERM_PROGRAM=ghostty CLAUDECODE= CLAUDE_CODE_ENTRYPOINT= \
      bash "$repo/bin/claw" registry ids profiles
  [ "$status" -eq 0 ]
  line="$(tail -1 "$ca/claw/usage.tsv")"
  [ "$(printf '%s' "$line" | awk -F'\t' '{print NF}')" -eq 5 ]
  [[ "$line" == *"term=ghostty"* ]]
  [[ "$line" == *"actor=human"* ]]

  run env DOTFILES_DIR="$repo" XDG_CACHE_HOME="$ca" CLAW_NO_LOG=0 \
      TERM_PROGRAM=ghostty CLAUDECODE=1 \
      bash "$repo/bin/claw" registry ids profiles
  [ "$status" -eq 0 ]
  [[ "$(tail -1 "$ca/claw/usage.tsv")" == *"actor=agent"* ]]
}

@test "claw log_usage: claw load logs the TARGET profile as load:<id>" {
  repo="$(REPO_ROOT)"
  ca="$BATS_TEST_TMPDIR/cache"
  # `claw load` from bash only prints the shell-function hint; the log row is
  # written before dispatch either way, which is the datum tui-stats needs.
  run env DOTFILES_DIR="$repo" XDG_CACHE_HOME="$ca" CLAW_NO_LOG=0 \
      bash "$repo/bin/claw" load security
  [[ "$(cut -f2 "$ca/claw/usage.tsv" | tail -1)" = "load:security" ]]
}

@test "claw doctor: prints cache ages and the attention count" {
  repo="$(REPO_ROOT)"
  ca="$BATS_TEST_TMPDIR/cache"; mkdir -p "$ca/claw"
  printf '{}\n' > "$ca/claw/situation.json"
  printf '3\n'  > "$ca/claw/attention.count"
  run env DOTFILES_DIR="$repo" CLAW_NO_LOG=1 XDG_CACHE_HOME="$ca" HOME="$BATS_TEST_TMPDIR" \
      bash "$repo/bin/claw" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Caches"* ]]
  [[ "$output" == *"situation"* ]]
  [[ "$output" == *"attention"* ]]
  [[ "$output" == *"3"* ]]
}

@test "registry.sh check: exits 0 and silent with PENDING_ARMS empty" {
  repo="$(REPO_ROOT)"
  grep -q '^PENDING_ARMS=""$' "$repo/scripts/utils/registry.sh"
  run env DOTFILES_DIR="$repo" bash "$repo/scripts/utils/registry.sh" check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "claw-completion: the top-level word list is generated from the registry" {
  repo="$(REPO_ROOT)"
  run zsh -fc "DOTFILES_DIR='$repo'; source '$repo/shell/claw-completion.zsh' 2>/dev/null
               _claw_top_words; print -rl -- \$_claw_top_cache"
  [ "$status" -eq 0 ]
  # every registry id (and alias) is offered — including the ones the old
  # hardcoded 41-entry list missed (harness was Henry's #1 verb).
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [[ "$output" == *"$id:"* ]] || { echo "missing completion word: $id"; return 1; }
  done < <(env DOTFILES_DIR="$repo" bash "$repo/scripts/utils/registry.sh" ids --with-aliases)
  [[ "$output" == *"harness:"* ]]
  [[ "$output" == *"security:"* ]]
  [[ "$output" == *"sec:"* ]]
}
