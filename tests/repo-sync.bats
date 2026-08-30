#!/usr/bin/env bats
# Tests for scripts/utils/repo-sync.sh (phase 1 of `claw update`) plus the
# phased front door in bin/claw and the selfupdate timer re-point.
# Fixture: a throwaway origin repo + clone. Regen hooks are stub scripts
# committed INTO the fixture (link-claude.sh, integrity.sh) and PATH-stub
# fakes (python3, stow); every stub records its argv into $CALLS/log.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$HOME/.cache"
  mkdir -p "$HOME"
  export GIT_CONFIG_SYSTEM=/dev/null
  git config --global user.email claw@test
  git config --global user.name "Claw Test"
  git config --global init.defaultBranch main

  ORIGIN="$BATS_TEST_TMPDIR/origin"
  CLONE="$BATS_TEST_TMPDIR/clone"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$ORIGIN" "$CALLS"

  git -C "$ORIGIN" init -q
  mkdir -p "$ORIGIN/scripts/utils" "$ORIGIN/scripts/setup" "$ORIGIN/shell" "$ORIGIN/claude" \
           "$ORIGIN/config/integrity"
  echo base > "$ORIGIN/README.md"
  echo '# generator' > "$ORIGIN/scripts/utils/gen-fastfetch.py"
  echo '# aliases' > "$ORIGIN/shell/aliases.zsh"
  echo '# global rules' > "$ORIGIN/claude/CLAUDE.md"
  # tracked manifest, like the real repo — the integrity stub REWRITES it after
  # every pull (mirroring cmd_generate) so the regen-drift deadlock is testable
  echo 'seed-manifest' > "$ORIGIN/config/integrity/manifest.sha256"
  printf '#!/usr/bin/env bash\necho "link-claude $*" >> "$CALLS/log"\n' > "$ORIGIN/scripts/setup/link-claude.sh"
  printf '#!/usr/bin/env bash\necho "integrity $*" >> "$CALLS/log"\nDF="$(cd "$(dirname "$0")/../.." && pwd)"\necho "regen $RANDOM" > "$DF/config/integrity/manifest.sha256"\n' > "$ORIGIN/scripts/utils/integrity.sh"
  git -C "$ORIGIN" add -A
  git -C "$ORIGIN" commit -qm init
  git clone -q "$ORIGIN" "$CLONE"

  # PATH-stub fakes — topgrade/python3/stow are never the real thing in tests.
  STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB"
  printf '#!/usr/bin/env bash\necho "python3 $*" >> "$CALLS/log"\n' > "$STUB/python3"
  printf '#!/usr/bin/env bash\necho "stow $*" >> "$CALLS/log"\n' > "$STUB/stow"
  chmod +x "$STUB/python3" "$STUB/stow"

  RS="$BATS_TEST_DIRNAME/../scripts/utils/repo-sync.sh"
  CLAW="$BATS_TEST_DIRNAME/../bin/claw"
}

# One new origin commit touching <file> (created if missing).
advance_origin() {
  mkdir -p "$ORIGIN/$(dirname "$1")"
  echo "bump $BATS_TEST_NAME" >> "$ORIGIN/$1"
  git -C "$ORIGIN" add -A
  git -C "$ORIGIN" commit -qm "touch $1"
}

run_rs() { run env DOTFILES_DIR="$CLONE" PATH="$STUB:$PATH" bash "$RS" "$@"; }

# ── repo-sync: pull paths ────────────────────────────────────────────────────

@test "behind-by-one: ff-pulls and reports old..new SHAs" {
  old=$(git -C "$CLONE" rev-parse --short HEAD)
  advance_origin README.md
  new=$(git -C "$ORIGIN" rev-parse --short HEAD)
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo: ${old}..${new}"* ]]
  [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse HEAD)" ]
}

@test "up-to-date: reports and exits 0" {
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo: up-to-date"* ]]
}

# ── repo-sync: conservative skips (always exit 0) ────────────────────────────

@test "dirty tree: skips with reason, pulls nothing" {
  advance_origin README.md
  echo local-edit >> "$CLONE/README.md"
  before=$(git -C "$CLONE" rev-parse HEAD)
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo: skipped (dirty tree)"* ]]
  [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ]
}

@test "untracked-only files do NOT count as dirty" {
  echo secret > "$CLONE/.env"
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo: up-to-date"* ]]
}

@test "no upstream: skips with reason" {
  git -C "$CLONE" branch --unset-upstream
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo: skipped (no upstream)"* ]]
}

@test "diverged: skips with reason, never merges" {
  advance_origin README.md
  echo divergent > "$CLONE/local.txt"
  git -C "$CLONE" add local.txt
  git -C "$CLONE" commit -qm divergent
  before=$(git -C "$CLONE" rev-parse HEAD)
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo: skipped (diverged)"* ]]
  [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ]
}

# ── repo-sync: dry-run ───────────────────────────────────────────────────────

@test "--dry-run: pulls nothing, runs no regens, still writes a receipt" {
  advance_origin scripts/utils/gen-fastfetch.py
  before=$(git -C "$CLONE" rev-parse HEAD)
  run_rs --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ]
  [ ! -f "$CALLS/log" ]
  [ -s "$XDG_CACHE_HOME/claw/updates.tsv" ]
}

# ── repo-sync: conditional regen ─────────────────────────────────────────────

@test "regen: gen-fastfetch.py + shell/ changes run generator + stow (not link-claude)" {
  advance_origin scripts/utils/gen-fastfetch.py
  advance_origin shell/aliases.zsh
  run_rs
  [ "$status" -eq 0 ]
  grep -q "python3 .*gen-fastfetch.py" "$CALLS/log"
  grep -q "stow -R" "$CALLS/log"
  grep -q "integrity generate" "$CALLS/log"
  ! grep -q "link-claude" "$CALLS/log"
}

@test "regen: claude/-only change runs link-claude (not generator/stow)" {
  advance_origin claude/CLAUDE.md
  run_rs
  [ "$status" -eq 0 ]
  grep -q "link-claude" "$CALLS/log"
  grep -q "integrity generate" "$CALLS/log"
  ! grep -q "python3" "$CALLS/log"
  ! grep -q "stow" "$CALLS/log"
}

@test "regen: unrelated change regenerates only the integrity manifest" {
  advance_origin README.md
  run_rs
  [ "$status" -eq 0 ]
  grep -q "integrity generate" "$CALLS/log"
  ! grep -q "python3" "$CALLS/log"
  ! grep -q "stow" "$CALLS/log"
  ! grep -q "link-claude" "$CALLS/log"
}

@test "regen: missing stow is a skip note, not a phantom stow failure" {
  # restricted PATH: everything repo-sync needs, minus stow (and no real PATH
  # fallthrough — `command -v stow` must genuinely miss)
  NOSTOW="$BATS_TEST_TMPDIR/nostow"
  mkdir -p "$NOSTOW"
  for t in bash git date mkdir grep sed dirname cat tr uname head tail cut wc \
           mktemp rm mv sleep env ls; do
    p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$NOSTOW/$t" || true
  done
  ln -sf "$STUB/python3" "$NOSTOW/python3"
  advance_origin shell/aliases.zsh
  run env DOTFILES_DIR="$CLONE" PATH="$NOSTOW" bash "$RS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stow missing"* ]]
  [[ "$output" != *"stow -R shell failed"* ]]
  ! grep -q "stow" "$CALLS/log"
}

# ── repo-sync: integrity-manifest drift must never wedge the pull ────────────
# config/integrity/manifest.sha256 is git-tracked but machine-generated (it
# hashes untracked files too), so post-pull/bootstrap regens ALWAYS leave it
# modified. If the dirty guard counted it, the first regen would deadlock
# every later sync: pull → regen → "dirty tree" forever.

@test "manifest-only drift never blocks the pull" {
  echo "local-regen" > "$CLONE/config/integrity/manifest.sha256"
  advance_origin README.md
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" != *"skipped (dirty tree)"* ]]
  [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse HEAD)" ]
}

@test "manifest drift + upstream manifest change: ff pull still succeeds" {
  echo "local-regen" > "$CLONE/config/integrity/manifest.sha256"
  advance_origin config/integrity/manifest.sha256
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" != *"pull failed"* ]]
  [[ "$output" != *"skipped (dirty tree)"* ]]
  [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse HEAD)" ]
}

@test "back-to-back pulls: run 1's integrity regen does not wedge run 2" {
  advance_origin README.md
  run_rs
  [ "$status" -eq 0 ]
  # run 1's integrity stub rewrote the tracked manifest — tree now drifts
  [ -n "$(git -C "$CLONE" status --porcelain -uno)" ]
  advance_origin shell/aliases.zsh
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" != *"skipped (dirty tree)"* ]]
  [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse HEAD)" ]
}

@test "real dirt still skips even when the manifest also drifted" {
  echo "local-regen" > "$CLONE/config/integrity/manifest.sha256"
  echo local-edit >> "$CLONE/README.md"
  advance_origin README.md
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo: skipped (dirty tree)"* ]]
}

# ── repo-sync: receipts ──────────────────────────────────────────────────────

@test "receipt: one TSV row, 5 tab-separated fields, ok result, manual trigger" {
  advance_origin README.md
  run_rs
  [ "$status" -eq 0 ]
  receipts="$XDG_CACHE_HOME/claw/updates.tsv"
  [ -s "$receipts" ]
  row=$(tail -1 "$receipts")
  [ "$(printf '%s\n' "$row" | awk -F'\t' '{print NF}')" -eq 5 ]
  [ "$(printf '%s\n' "$row" | cut -f2)" = "manual" ]
  [ "$(printf '%s\n' "$row" | cut -f4)" = "ok" ]
}

@test "receipt: CLAW_UPDATE_TRIGGER stamps the trigger column" {
  run env DOTFILES_DIR="$CLONE" PATH="$STUB:$PATH" CLAW_UPDATE_TRIGGER=timer bash "$RS"
  [ "$status" -eq 0 ]
  [ "$(tail -1 "$XDG_CACHE_HOME/claw/updates.tsv" | cut -f2)" = "timer" ]
}

# ── front door: bin/claw cmd_update phases ───────────────────────────────────

# Stub dotfiles tree with fake phase engines that echo a marker.
make_front_door_df() {
  DF="$BATS_TEST_TMPDIR/df"
  mkdir -p "$DF/scripts/utils"
  printf '#!/usr/bin/env bash\necho "REPO_SYNC_RAN $*"\n' > "$DF/scripts/utils/repo-sync.sh"
  printf '#!/usr/bin/env bash\necho "SYSTEM_UPDATE_RAN phased=${CLAW_UPDATE_PHASED:-0} $*"\n' > "$DF/scripts/utils/system-update.sh"
  printf '#!/usr/bin/env bash\necho "TOOL_UPDATER_RAN $*"\n' > "$DF/scripts/utils/tool-updater.sh"
  printf '#!/usr/bin/env bash\necho "SELFUPDATE_RAN $*"\n' > "$DF/scripts/utils/selfupdate.sh"
}

@test "front door: default runs repo phase then packages phase, flags forwarded" {
  make_front_door_df
  run env DOTFILES_DIR="$DF" bash "$CLAW" update --dry-run --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"REPO_SYNC_RAN --dry-run --non-interactive"* ]]
  # phased marker set — phase 2 must not `clear` phase 1's report off screen
  [[ "$output" == *"SYSTEM_UPDATE_RAN phased=1 --dry-run --non-interactive"* ]]
  # phase order: repo before packages
  [[ "${output%%SYSTEM_UPDATE_RAN*}" == *"REPO_SYNC_RAN"* ]]
}

@test "front door: --repo runs repo-sync only, --packages runs the engine only" {
  make_front_door_df
  run env DOTFILES_DIR="$DF" bash "$CLAW" update --repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"REPO_SYNC_RAN"* ]]
  [[ "$output" != *"SYSTEM_UPDATE_RAN"* ]]
  run env DOTFILES_DIR="$DF" bash "$CLAW" update --packages
  [ "$status" -eq 0 ]
  # standalone engine run — no phase 1 output to protect, marker stays unset
  [[ "$output" == *"SYSTEM_UPDATE_RAN phased=0"* ]]
  [[ "$output" != *"REPO_SYNC_RAN"* ]]
}

@test "front door: --dry-run with --tools/--schedule refuses instead of dropping the flag" {
  make_front_door_df
  run env DOTFILES_DIR="$DF" bash "$CLAW" update --dry-run --tools
  [ "$status" -ne 0 ]
  [[ "$output" == *"--dry-run does not apply"* ]]
  [[ "$output" != *"TOOL_UPDATER_RAN"* ]]
  # reverse order refuses identically instead of erroring deep in tool-updater
  run env DOTFILES_DIR="$DF" bash "$CLAW" update --tools --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"--dry-run does not apply"* ]]
  [[ "$output" != *"TOOL_UPDATER_RAN"* ]]
  run env DOTFILES_DIR="$DF" bash "$CLAW" update --non-interactive --schedule
  [ "$status" -ne 0 ]
  [[ "$output" == *"--non-interactive does not apply"* ]]
  [[ "$output" != *"SELFUPDATE_RAN"* ]]
}

@test "front door: plain --tools still reaches tool-updater" {
  make_front_door_df
  run env DOTFILES_DIR="$DF" bash "$CLAW" update --tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"TOOL_UPDATER_RAN --interactive"* ]]
}

@test "front door: --last pretty-prints receipt rows" {
  mkdir -p "$XDG_CACHE_HOME/claw"
  printf '2026-08-17T10:00:00Z\ttimer\t42\tok\tengine=topgrade\n' > "$XDG_CACHE_HOME/claw/updates.tsv"
  printf '2026-08-17T11:00:00Z\tmanual\t3\tfail\tphase=repo error=fetch-failed\n' >> "$XDG_CACHE_HOME/claw/updates.tsv"
  run env DOTFILES_DIR="$BATS_TEST_DIRNAME/.." bash "$CLAW" update --last
  [ "$status" -eq 0 ]
  [[ "$output" == *"engine=topgrade"* ]]
  [[ "$output" == *"error=fetch-failed"* ]]
  [[ "$output" == *"timer"* ]]
}

@test "front door: unknown update flag errors with usage" {
  make_front_door_df
  run env DOTFILES_DIR="$DF" bash "$CLAW" update --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown update flag"* ]]
}

@test "doctor: updates line falls back to dim n/a when reader/cache absent" {
  make_front_door_df
  run env DOTFILES_DIR="$DF" bash "$CLAW" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"updates:"* ]]
  [[ "$output" == *"n/a"* ]]
}

@test "doctor: updates line reads update-status.sh when script + cache exist" {
  make_front_door_df
  printf '#!/usr/bin/env bash\n[ "$1" = read ] && echo "3 pkg · repo ↓1"\n' > "$DF/scripts/utils/update-status.sh"
  mkdir -p "$XDG_CACHE_HOME/claw"
  echo '{}' > "$XDG_CACHE_HOME/claw/updates.json"
  run env DOTFILES_DIR="$DF" bash "$CLAW" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"updates:"* ]]
  [[ "$output" == *"3 pkg"* ]]
}

# ── timer re-point: selfupdate.sh → the phased front door ────────────────────

@test "selfupdate now: runs claw update --non-interactive with timer trigger" {
  DF="$BATS_TEST_TMPDIR/df-su"
  mkdir -p "$DF/bin" "$DF/scripts/utils"
  printf '#!/usr/bin/env bash\necho "CLAW_RAN trigger=$CLAW_UPDATE_TRIGGER args=$*"\n' > "$DF/bin/claw"
  cp "$BATS_TEST_DIRNAME/../scripts/utils/selfupdate.sh" "$DF/scripts/utils/"
  run env DOTFILES_DIR="$DF" bash "$DF/scripts/utils/selfupdate.sh" now
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAW_RAN trigger=timer args=update --non-interactive"* ]]
}

@test "selfupdate now: nonzero exit fires notify.sh --crit and propagates rc" {
  DF="$BATS_TEST_TMPDIR/df-su"
  mkdir -p "$DF/bin" "$DF/scripts/utils"
  printf '#!/usr/bin/env bash\nexit 3\n' > "$DF/bin/claw"
  printf '#!/usr/bin/env bash\necho "NOTIFY $*"\n' > "$DF/scripts/utils/notify.sh"
  cp "$BATS_TEST_DIRNAME/../scripts/utils/selfupdate.sh" "$DF/scripts/utils/"
  run env DOTFILES_DIR="$DF" bash "$DF/scripts/utils/selfupdate.sh" now
  [ "$status" -eq 3 ]
  [[ "$output" == *"NOTIFY send --crit"* ]]
  [[ "$output" == *"Self-update failed"* ]]
}

@test "selfupdate now: missing notify.sh degrades to a warning, never crashes" {
  DF="$BATS_TEST_TMPDIR/df-su"
  mkdir -p "$DF/bin" "$DF/scripts/utils"
  printf '#!/usr/bin/env bash\nexit 7\n' > "$DF/bin/claw"
  cp "$BATS_TEST_DIRNAME/../scripts/utils/selfupdate.sh" "$DF/scripts/utils/"
  run env DOTFILES_DIR="$DF" bash "$DF/scripts/utils/selfupdate.sh" now
  [ "$status" -eq 7 ]
  [[ "$output" == *"self-update failed"* ]]
}

@test "selfupdate install: systemd unit re-points at the phased front door" {
  # Linux-only assertion on the generated unit text; on macOS the plist carries
  # the same command, but this sandbox is Linux so exercise the systemd branch.
  [ "$(uname -s)" = "Darwin" ] && skip "systemd branch is Linux-only"
  DF="$BATS_TEST_TMPDIR/df-su"
  mkdir -p "$DF/bin" "$DF/scripts/utils"
  cp "$BATS_TEST_DIRNAME/../scripts/utils/selfupdate.sh" "$DF/scripts/utils/"
  run env DOTFILES_DIR="$DF" bash "$DF/scripts/utils/selfupdate.sh" install
  unit="$HOME/.config/systemd/user/claw-selfupdate.service"
  [ -f "$unit" ]
  grep -q "CLAW_UPDATE_TRIGGER=timer" "$unit"
  grep -q "bin/claw\" update --non-interactive" "$unit"
  grep -q "notify.sh\" send --crit" "$unit"
  ! grep -q "pkg-manifest.sh" "$unit"
  # daemon PATH is bare (/usr/bin:/bin) — the unit must bake the interactive
  # prefixes or the weekly run can't see topgrade/brew and scheduled ≠ manual
  grep -q 'Environment="PATH=' "$unit"
  grep -q '\.cargo/bin' "$unit"
  grep -q '\.local/bin' "$unit"
}
