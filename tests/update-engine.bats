#!/usr/bin/env bats
# Tests for the ONE package engine — topgrade-first system-update.sh.
# Interfaces (normative): argv --non-interactive/--dry-run, exit ≠0 iff a step
# failed, one receipt TSV row per run, CLAW_UPDATE_TRIGGER → receipt trigger.
#   Design: docs/superpowers/specs/2026-08-17-claw-update-one-engine-design.md

setup() {
  DOTFILES="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SU="$DOTFILES/scripts/utils/system-update.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export CLAW_OUTPUT_MODE=plain
  export TERM=xterm-256color
  STUB="$BATS_TEST_TMPDIR/stub"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  RCPT="$XDG_CACHE_HOME/claw/updates.tsv"
  mkdir -p "$HOME" "$STUB"
  : > "$CALLS"
  # Sweep tests must not see the host's topgrade — the engine is topgrade-FIRST,
  # so leaking the real $PATH silently reroutes them to the wrong branch (every
  # sweep assertion then fails on any box that actually has topgrade, i.e. the
  # design's preferred setup). Pin a minimal PATH — the idiom tests/claw.bats
  # already uses — and let $STUB supply every manager the sweep reaches for.
  SWEEP_PATH="$STUB:/usr/bin:/bin"
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

# Shadow EVERY tool the fallback sweep can invoke so nothing real executes.
stub_sweep_managers() {
  local m
  for m in sudo apt-get dnf pacman snap flatpak fwupdmgr brew npm yarn pnpm \
           uv pipx pip3 python3 gem rustup go omz; do
    make_stub "$m"
  done
}

@test "topgrade path: one streamed step invoked with the repo config" {
  make_stub topgrade
  make_stub brew   # present but must never be called — sweep is bypassed
  run env PATH="$STUB:$PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --non-interactive
  [ "$status" -eq 0 ]
  grep -qF "topgrade --config $DOTFILES/config/topgrade.toml -y" "$CALLS"
  ! grep -q '^brew ' "$CALLS"
  [[ "$output" == *"SYSTEM UPDATE"* ]]
  [[ "$output" != *"Press any key"* ]]   # --non-interactive: no pause
}

@test "topgrade path: --dry-run passes -n through to topgrade" {
  make_stub topgrade
  run env PATH="$STUB:$PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --non-interactive --dry-run
  [ "$status" -eq 0 ]
  grep -qF -- "-y -n" "$CALLS"
}

@test "receipt: one row, 5 tab-separated fields, trigger defaults to manual" {
  make_stub topgrade
  run env PATH="$STUB:$PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --non-interactive
  [ "$status" -eq 0 ]
  [ -f "$RCPT" ]
  [ "$(wc -l < "$RCPT" | tr -d ' ')" -eq 1 ]
  row="$(tail -n 1 "$RCPT")"
  [ "$(printf '%s\n' "$row" | awk -F'\t' '{print NF}')" -eq 5 ]
  printf '%s\n' "$row" | cut -f1 | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
  [ "$(printf '%s\n' "$row" | cut -f2)" = "manual" ]
  printf '%s\n' "$row" | cut -f3 | grep -Eq '^[0-9]+$'
  [ "$(printf '%s\n' "$row" | cut -f4)" = "ok" ]
  [[ "$(printf '%s\n' "$row" | cut -f5)" == *"engine=topgrade"* ]]
}

@test "receipt: CLAW_UPDATE_TRIGGER stamps the trigger column" {
  make_stub topgrade
  run env PATH="$STUB:$PATH" DOTFILES_DIR="$DOTFILES" CLAW_UPDATE_TRIGGER=timer \
      bash "$SU" --non-interactive
  [ "$status" -eq 0 ]
  [ "$(tail -n 1 "$RCPT" | cut -f2)" = "timer" ]
}

@test "topgrade failure: exit != 0 and a fail receipt row" {
  make_stub topgrade 1
  run env PATH="$STUB:$PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --non-interactive
  [ "$status" -ne 0 ]
  row="$(tail -n 1 "$RCPT")"
  [ "$(printf '%s\n' "$row" | cut -f4)" = "fail" ]
  [[ "$(printf '%s\n' "$row" | cut -f5)" == *"engine=topgrade"* ]]
}

@test "sweep dry-run: prints the plan, executes nothing, still writes a receipt" {
  stub_sweep_managers
  run env PATH="$SWEEP_PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --non-interactive --dry-run
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]                       # not one stub was ever invoked
  [[ "$output" == *"apt-get upgrade -y"* ]]
  [[ "$output" == *"gem update"* ]]
  row="$(tail -n 1 "$RCPT")"
  [ "$(printf '%s\n' "$row" | cut -f4)" = "ok" ]
  [[ "$(printf '%s\n' "$row" | cut -f5)" == *"engine=sweep"* ]]
  [[ "$(printf '%s\n' "$row" | cut -f5)" == *"dry_run=1"* ]]
}

@test "sweep: sudo primed upfront, gem updates gems, no modcache wipe" {
  stub_sweep_managers
  run env PATH="$SWEEP_PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --non-interactive
  [ "$status" -eq 0 ]
  # ticket probed before any step; non-interactive uses -n (no tty to prompt on)
  [ "$(head -n 1 "$CALLS")" = "sudo -n true" ]
  grep -qx "gem update" "$CALLS"
  ! grep -q "gem update --system" "$CALLS"
  ! grep -q "go clean" "$CALLS"
  [[ "$(tail -n 1 "$RCPT" | cut -f5)" == *"engine=sweep"* ]]
}

@test "sweep non-interactive: no sudo ticket skips sudo sections, exit 0" {
  stub_sweep_managers
  make_stub sudo 1   # overwrite: `sudo -n true` fails — no cached ticket, no tty
  run env PATH="$SWEEP_PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --non-interactive
  [ "$status" -eq 0 ]
  ! grep -q 'apt-get' "$CALLS"            # not one sudo-needing step ran
  ! grep -q 'snap refresh' "$CALLS"
  grep -q '^brew ' "$CALLS"               # sudo-free managers still updated
  [[ "$output" == *"skipped, sudo needs a password"* ]]
  row="$(tail -n 1 "$RCPT")"
  [ "$(printf '%s\n' "$row" | cut -f4)" = "ok" ]
  [[ "$(printf '%s\n' "$row" | cut -f5)" == *"sudo=skipped"* ]]
}

@test "sweep: a failing step yields exit != 0 and a fail receipt with the tally" {
  stub_sweep_managers
  make_stub gem 2   # overwrite: gem step fails
  run env PATH="$SWEEP_PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --non-interactive
  [ "$status" -ne 0 ]
  row="$(tail -n 1 "$RCPT")"
  [ "$(printf '%s\n' "$row" | cut -f4)" = "fail" ]
  [[ "$(printf '%s\n' "$row" | cut -f5)" == *"fail=1"* ]]
}

@test "flags: parse in any order (--dry-run before --non-interactive)" {
  stub_sweep_managers
  run env PATH="$SWEEP_PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --dry-run --non-interactive
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "source hygiene: modcache wipe and RubyGems-system bump are gone" {
  run grep -c 'go clean -modcache' "$SU";   [ "$output" -eq 0 ]
  run grep -c 'gem update --system' "$SU";  [ "$output" -eq 0 ]
}

@test "config: topgrade.toml ships with the justified disables" {
  CFG="$DOTFILES/config/topgrade.toml"
  [ -f "$CFG" ]
  grep -q '"containers"' "$CFG"
  grep -q '"git_repos"' "$CFG"
}

@test "shellcheck: engine passes at warning severity (house exclusions)" {
  command -v shellcheck &>/dev/null || skip "shellcheck not installed"
  run shellcheck -x -S warning -e SC1090,SC1091,SC2034,SC2059,SC2015,SC2154 "$SU"
  [ "$status" -eq 0 ]
}

# ── Stall regression (2026-08-28) ─────────────────────────────────────────
# `claw update` (and its `claw upgrade` alias) hung on "the restart
# questions": needrestart's mid-run whiptail dialog and topgrade's post-run
# "Reboot?" prompt. Both read the TTY; claw_step feeds children /dev/null,
# pipes their output, and repaints over the prompt — so the run blocked
# invisibly and forever, because nothing bounded it.

@test "stall regression: topgrade.toml suppresses the post-run reboot prompt" {
  grep -Eq '^no_reboot = true' "$DOTFILES/config/topgrade.toml"
}

@test "stall regression: engine exports the non-interactive prompt contract" {
  cat > "$STUB/topgrade" <<'EOF'
#!/usr/bin/env bash
printf 'ENV[%s|%s|%s|%s]\n' "$DEBIAN_FRONTEND" "$NEEDRESTART_MODE" \
  "$UCF_FORCE_CONFOLD" "$GIT_TERMINAL_PROMPT"
EOF
  chmod +x "$STUB/topgrade"
  run env PATH="$STUB:$PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENV[noninteractive|l|1|0]"* ]]
}

@test "stall regression: a blocking step is killed by the deadline, not wedged" {
  if ! command -v timeout &>/dev/null && ! command -v gtimeout &>/dev/null; then
    skip "no GNU timeout/gtimeout — claw_deadline degrades to a no-op here"
  fi
  # stands in for a package manager that opens a TTY dialog and waits forever
  printf '#!/usr/bin/env bash\nsleep 60\n' > "$STUB/topgrade"
  chmod +x "$STUB/topgrade"
  run env PATH="$STUB:$PATH" DOTFILES_DIR="$DOTFILES" CLAW_UPDATE_TIMEOUT=2 \
      bash "$SU" --non-interactive
  [ "$status" -ne 0 ]                                    # deadline → failed run
  [ "$(tail -n 1 "$RCPT" | cut -f4)" = "fail" ]          # ...and a fail receipt
  [ "$(tail -n 1 "$RCPT" | cut -f3)" -lt 30 ]            # terminated fast, not hung
}

@test "stall regression: topgrade path primes sudo (was sweep-only, unreachable)" {
  make_stub topgrade
  make_stub sudo
  make_stub apt-get           # makes claw_sudo_prime's `need` check fire
  run env PATH="$STUB:$PATH" DOTFILES_DIR="$DOTFILES" bash "$SU" --non-interactive
  [ "$status" -eq 0 ]
  grep -qF "sudo -n true" "$CALLS"                       # ticket validated...
  grep -qF "topgrade --config" "$CALLS"                  # ...before topgrade ran
}
