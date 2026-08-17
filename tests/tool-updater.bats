#!/usr/bin/env bats
# Tests for the registry merge — tool-updater.sh's fast lane driven by
# cadence-tagged rows of config/manifest/tools.list (id|source|cadence), and
# pkg-manifest.sh's 3-field tolerance + pkg_update delegation to the one engine.
#   Design: docs/superpowers/specs/2026-08-17-claw-update-one-engine-design.md

setup() {
  DOTFILES="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TU="$DOTFILES/scripts/utils/tool-updater.sh"
  PKG="$DOTFILES/scripts/utils/pkg-manifest.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export CLAW_OUTPUT_MODE=plain
  export TERM=xterm-256color
  STUB="$BATS_TEST_TMPDIR/stub"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  CACHE="$HOME/.cache/claw-updates"
  FIX="$BATS_TEST_TMPDIR/df"              # fixture dotfiles tree (manifest home)
  mkdir -p "$HOME" "$STUB" "$FIX/config/manifest" "$FIX/scripts/utils"
  : > "$CALLS"
}

# make_stub <name> [exit-code] — PATH-stub fake that records its argv.
make_stub() {
  cat > "$STUB/$1" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$1" "\$*" >> "$CALLS"
exit ${2:-0}
EOF
  chmod +x "$STUB/$1"
}

# Every manager the fast lane can invoke (cargo goes through nice).
stub_managers() {
  local m
  for m in brew pipx cargo go nice; do make_stub "$m"; done
}

# write_manifest <row>... — fixture tools.list, one arg per line.
write_manifest() { printf '%s\n' "$@" > "$FIX/config/manifest/tools.list"; }

run_tu() { run env PATH="$STUB:$PATH" DOTFILES_DIR="$FIX" bash "$TU" "$@"; }

# ── fast lane: manifest parsing ──────────────────────────────────────────────

@test "3-field rows parse: grouped by (source, cadence), all runners fire" {
  stub_managers
  write_manifest \
    "# comment" "## Section" "" \
    "eza|brew|weekly" "bat|brew|weekly" \
    "rovr|pipx|weekly" \
    "clawea|go:github.com/cladamos/clawea|biweekly" \
    "netwatch-tui|cargo|monthly"
  run_tu --interactive
  [ "$status" -eq 0 ]
  grep -qx "brew upgrade eza" "$CALLS"
  grep -qx "brew upgrade bat" "$CALLS"
  grep -qx "pipx upgrade rovr" "$CALLS"
  grep -qx "nice -n 19 cargo install netwatch-tui" "$CALLS"
  # composite (source,cadence) cache keys stamped per category
  [ -f "$CACHE/brew-weekly" ]
  [ -f "$CACHE/pipx-weekly" ]
  [ -f "$CACHE/go-biweekly" ]
  [ -f "$CACHE/cargo-monthly" ]
}

@test "2-field rows never enter the fast lane" {
  stub_managers
  write_manifest "git|brew" "fzf|brew" "eza|brew|weekly"
  run_tu --interactive
  [ "$status" -eq 0 ]
  grep -qx "brew upgrade eza" "$CALLS"
  ! grep -q "git" "$CALLS"
  ! grep -q "fzf" "$CALLS"
}

@test "go:<pkg> source maps to go install <pkg>@latest" {
  stub_managers
  write_manifest "clawea|go:github.com/cladamos/clawea|biweekly"
  run_tu --interactive
  [ "$status" -eq 0 ]
  grep -qx "go install github.com/cladamos/clawea@latest" "$CALLS"
}

@test "unknown cadence or non-runnable source rows are ignored" {
  stub_managers
  write_manifest \
    "eza|brew|fast" \
    "sops|eget:getsops/sops|weekly" \
    "colorls|gem|weekly" \
    "bat|brew|weekly"
  run_tu --interactive
  [ "$status" -eq 0 ]
  grep -qx "brew upgrade bat" "$CALLS"
  ! grep -q "brew upgrade eza" "$CALLS"
  ! grep -q "sops" "$CALLS"
  ! grep -q "colorls" "$CALLS"
}

# ── fast lane: fallback CATEGORIES ───────────────────────────────────────────

@test "fallback: cadence-less manifest activates the hardcoded set" {
  stub_managers
  write_manifest "git|brew" "tmux|brew"     # tracked, but nothing cadence-tagged
  run_tu --interactive
  [ "$status" -eq 0 ]
  # hardcoded curated set ran (tools NOT in the fixture manifest prove it)
  grep -qx "brew upgrade zoxide" "$CALLS"
  grep -qx "pipx upgrade osint-d2" "$CALLS"
  grep -qx "go install github.com/cladamos/clawea@latest" "$CALLS"
  # legacy bare-source cache keys preserved on the fallback path
  [ -f "$CACHE/brew" ]
  [ -f "$CACHE/cargo" ]
}

@test "fallback: missing manifest activates the hardcoded set" {
  stub_managers
  rm -f "$FIX/config/manifest/tools.list"
  run_tu --interactive
  [ "$status" -eq 0 ]
  grep -qx "brew upgrade ripgrep" "$CALLS"
  grep -qx "nice -n 19 cargo install eilmeldung" "$CALLS"
}

# ── fast lane: per-category cache ────────────────────────────────────────────

@test "interactive: only due (source,cadence) categories run" {
  stub_managers
  write_manifest "eza|brew|weekly" "netwatch-tui|cargo|monthly"
  mkdir -p "$CACHE"
  date +%s > "$CACHE/brew-weekly"          # fresh — brew is deferred
  run_tu --interactive
  [ "$status" -eq 0 ]
  ! grep -q "brew upgrade" "$CALLS"
  grep -qx "nice -n 19 cargo install netwatch-tui" "$CALLS"
  [[ "$output" == *"next update in"* ]]
  [ -f "$CACHE/cargo-monthly" ]
}

@test "--force ignores the cache intervals" {
  stub_managers
  write_manifest "eza|brew|weekly"
  mkdir -p "$CACHE"
  date +%s > "$CACHE/brew-weekly"
  run_tu --force
  [ "$status" -eq 0 ]
  grep -qx "brew upgrade eza" "$CALLS"
}

@test "legacy bare-source cache stamp is adopted for the composite key" {
  stub_managers
  write_manifest "eza|brew|weekly"
  mkdir -p "$CACHE"
  date +%s > "$CACHE/brew"                 # pre-merge stamp, still fresh
  run_tu --interactive
  [ "$status" -eq 0 ]
  ! grep -q "brew upgrade" "$CALLS"        # no surprise re-run after the merge
  [ -f "$CACHE/brew-weekly" ]
}

# ── fast lane: silent mode consumes the same parsed set ──────────────────────

@test "silent mode: manifest categories drive the background pass" {
  stub_managers
  write_manifest "eza|brew|weekly" "bat|brew|weekly" "rovr|pipx|weekly"
  run_tu
  [ "$status" -eq 0 ]
  # the daemon backgrounds itself — wait for the single-flight lock to clear
  for _ in $(seq 1 50); do
    [ ! -d "$CACHE/.update.lock" ] && [ -f "$CACHE/pipx-weekly" ] && break
    sleep 0.1
  done
  grep -qx "brew upgrade eza bat" "$CALLS"   # silent brew: one batched call
  grep -qx "pipx upgrade rovr" "$CALLS"
  [ -f "$CACHE/brew-weekly" ]
}

# ── pkg-manifest.sh: 3-field tolerance + one-engine delegation ───────────────

@test "pkg update: delegates to system-update.sh with one info line" {
  cat > "$FIX/scripts/utils/system-update.sh" <<EOF
#!/usr/bin/env bash
printf 'system-update %s\n' "\$*" >> "$CALLS"
EOF
  chmod +x "$FIX/scripts/utils/system-update.sh"
  write_manifest "eza|brew|weekly"
  run env DOTFILES_DIR="$FIX" bash "$PKG" update --dry-run
  [ "$status" -eq 0 ]
  grep -qx "system-update --dry-run" "$CALLS"
  [[ "$output" == *"one engine"* ]]
  [[ "$output" != *"per-source update"* ]]
}

@test "_m_source on a 3-field row still returns the bare source" {
  write_manifest "eza|brew|weekly" "clawea|go:github.com/cladamos/clawea|biweekly"
  run env DOTFILES_DIR="$FIX" bash -c "source '$PKG' list >/dev/null 2>&1; _m_source eza; _m_source clawea"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "brew" ]
  [ "${lines[1]}" = "go:github.com/cladamos/clawea" ]
}

@test "_m_ids tolerates 3-field rows" {
  write_manifest "eza|brew|weekly" "git|brew"
  run env DOTFILES_DIR="$FIX" bash -c "source '$PKG' list >/dev/null 2>&1; _m_ids"
  [ "$status" -eq 0 ]
  [[ "$output" == *"eza"* ]]
  [[ "$output" == *"git"* ]]
  [[ "$output" != *"weekly"* ]]
}

@test "pkg install: 3-field row installs with bare id and source" {
  # pkg_install needs the progress engine inside the fixture tree
  cp "$DOTFILES/scripts/utils/claw-progress.sh" \
     "$DOTFILES/scripts/utils/claw-output.sh" "$FIX/scripts/utils/"
  make_stub brew
  write_manifest "fastlane-x|brew|weekly"
  run env PATH="$STUB:$PATH" DOTFILES_DIR="$FIX" bash "$PKG" install fastlane-x
  [ "$status" -eq 0 ]
  grep -qx "brew install fastlane-x" "$CALLS"
}

# ── hygiene ──────────────────────────────────────────────────────────────────

@test "shellcheck: tool-updater + pkg-manifest pass at warning severity" {
  command -v shellcheck &>/dev/null || skip "shellcheck not installed"
  run shellcheck -x -S warning -e SC1090,SC1091,SC2034,SC2059,SC2015,SC2154 "$TU" "$PKG"
  [ "$status" -eq 0 ]
}
