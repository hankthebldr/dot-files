#!/usr/bin/env bats
# Tests for update-status.sh — the pending-update visibility cache
# (~/.cache/claw/updates.json) and its readers: situation.sh probe/tick/show,
# ff-readout.sh fields, and the welcome-TUI login kick.
# Interfaces (normative): argv --refresh (6h throttle) / --force / read
# [--json]; JSON shape with null (never 0) for an absent/failed manager;
# atomic mktemp+mv landing; mkdir single-flight lock.
#   Design: docs/superpowers/specs/2026-08-17-claw-update-one-engine-design.md

setup() {
  DOTFILES="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  US="$DOTFILES/scripts/utils/update-status.sh"
  SIT="$DOTFILES/scripts/utils/situation.sh"
  FFR="$DOTFILES/scripts/utils/ff-readout.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  CACHE="$XDG_CACHE_HOME/claw"
  SNAP="$CACHE/updates.json"
  RCPT="$CACHE/updates.tsv"
  STUB="$BATS_TEST_TMPDIR/stub"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  DOTS="$BATS_TEST_TMPDIR/notgit"          # a DOTFILES dir that is NOT a repo
  mkdir -p "$HOME" "$CACHE" "$STUB" "$DOTS"
  : > "$CALLS"
}

# Stub brew: `brew outdated --quiet` prints $1 package lines (default 2).
stub_brew() {
  cat > "$STUB/brew" <<EOF
#!/usr/bin/env bash
echo "brew \$*" >> "$CALLS"
if [ "\$1" = outdated ]; then
  n=${1:-2}; i=0
  while [ \$i -lt \$n ]; do echo "pkg\$i"; i=\$((i+1)); done
fi
EOF
  chmod +x "$STUB/brew"
}

# Stub apt-get: `apt-get -s upgrade` prints $1 `Inst …` lines (default 3).
stub_apt() {
  cat > "$STUB/apt-get" <<EOF
#!/usr/bin/env bash
echo "apt-get \$*" >> "$CALLS"
echo "NOTE: This is only a simulation!"
n=${1:-3}; i=0
while [ \$i -lt \$n ]; do echo "Inst pkg\$i [1.0] (1.1 Debian:stable [amd64])"; i=\$((i+1)); done
echo "Conf pkg0 (1.1 Debian:stable [amd64])"
EOF
  chmod +x "$STUB/apt-get"
}

# Stub that fails — a manager that errors must read as null, never 0.
stub_fail() {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/$1"
  chmod +x "$STUB/$1"
}

run_us() { run env PATH="$STUB:$PATH" DOTFILES_DIR="$DOTS" bash "$US" "$@"; }

# ── JSON shape ───────────────────────────────────────────────────────────────

@test "json shape: stubbed brew/apt counts land; no repo/receipt => nulls" {
  stub_brew 2; stub_apt 3
  run_us --force
  [ "$status" -eq 0 ]
  [ -f "$SNAP" ]
  jq -e '.brew == 2'         "$SNAP"
  jq -e '.apt == 3'          "$SNAP"
  jq -e '.repo_behind == null and .repo_ahead == null' "$SNAP"
  jq -e '.last_run == null'  "$SNAP"
  jq -e '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$SNAP"
}

@test "json shape: missing brew => null, never 0" {
  command -v brew &>/dev/null && skip "brew installed on this box"
  stub_apt 1
  run_us --force
  [ "$status" -eq 0 ]
  jq -e '.brew == null' "$SNAP"
  jq -e '.apt == 1'     "$SNAP"
}

@test "json shape: a FAILING manager probe => null, never 0" {
  stub_fail brew; stub_fail apt-get
  run_us --force
  [ "$status" -eq 0 ]
  jq -e '.brew == null and .apt == null' "$SNAP"
}

@test "last_run: epoch of the newest receipt row" {
  stub_brew 0; stub_apt 0
  printf '2026-08-16T09:00:00Z\tmanual\t12\tok\tengine=topgrade\n'      >> "$RCPT"
  printf '2026-08-17T10:30:00Z\ttimer\t80\tfail\tengine=sweep fail=1\n' >> "$RCPT"
  run_us --force
  [ "$status" -eq 0 ]
  exp="$(date -u -d '2026-08-17T10:30:00Z' +%s 2>/dev/null \
         || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-08-17T10:30:00Z' +%s)"
  [ "$(jq -r '.last_run' "$SNAP")" = "$exp" ]
}

@test "repo probe: behind/ahead counted both ways vs upstream" {
  export GIT_CONFIG_SYSTEM=/dev/null
  git config --global user.email claw@test
  git config --global user.name "Claw Test"
  git config --global init.defaultBranch main
  ORIGIN="$BATS_TEST_TMPDIR/origin"; CLONE="$BATS_TEST_TMPDIR/clone"
  git -C "$(mkdir -p "$ORIGIN" && echo "$ORIGIN")" init -q
  echo base > "$ORIGIN/README.md"
  git -C "$ORIGIN" add -A && git -C "$ORIGIN" commit -qm init
  git clone -q "$ORIGIN" "$CLONE"
  # origin advances twice (behind=2), clone commits once locally (ahead=1)
  echo up1 >> "$ORIGIN/README.md"; git -C "$ORIGIN" commit -qam up1
  echo up2 >> "$ORIGIN/README.md"; git -C "$ORIGIN" commit -qam up2
  echo mine > "$CLONE/local.txt";  git -C "$CLONE" add -A && git -C "$CLONE" commit -qm mine
  stub_brew 0; stub_apt 0
  run env PATH="$STUB:$PATH" DOTFILES_DIR="$CLONE" bash "$US" --force
  [ "$status" -eq 0 ]
  jq -e '.repo_behind == 2 and .repo_ahead == 1' "$SNAP"
}

# ── throttle + single-flight ─────────────────────────────────────────────────

@test "throttle: fresh snapshot short-circuits --refresh; --force overrides" {
  stub_brew 1; stub_apt 1
  run_us --refresh                       # no snapshot yet → probes
  [ "$status" -eq 0 ]
  [ -f "$SNAP" ]
  : > "$CALLS"
  run_us --refresh                       # <6h old → no probe at all
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  run_us --force                         # --force ignores the throttle
  [ "$status" -eq 0 ]
  grep -q '^brew ' "$CALLS"
}

@test "throttle: a stale (>6h) snapshot is re-probed by --refresh" {
  stub_brew 1; stub_apt 1
  run_us --force
  touch -t 202001010000 "$SNAP"          # age the snapshot far past 6h
  : > "$CALLS"
  run_us --refresh
  [ "$status" -eq 0 ]
  grep -q '^brew ' "$CALLS"
}

@test "single-flight: a held lock bails quietly without probing" {
  stub_brew 1; stub_apt 1
  mkdir -p "$CACHE/.updates.lock"        # fresh lock = another prober running
  run_us --force
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALLS" ]
  [ ! -f "$SNAP" ]
}

# ── atomicity ────────────────────────────────────────────────────────────────

@test "atomicity: a killed probe leaves no partial snapshot and frees the lock" {
  cat > "$STUB/brew" <<'EOF'
#!/usr/bin/env bash
[ "$1" = outdated ] && sleep 5
EOF
  chmod +x "$STUB/brew"
  stub_apt 0
  PATH="$STUB:$PATH" DOTFILES_DIR="$DOTS" bash "$US" --force &
  pid=$!
  sleep 1
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ ! -f "$SNAP" ]
  [ ! -d "$CACHE/.updates.lock" ]
  run bash -c "ls '$CACHE'/.upd.* 2>/dev/null | wc -l"
  [ "$(echo "$output" | tr -d ' ')" = "0" ]
}

# ── read: render-only, three states ──────────────────────────────────────────

@test "read: no cache => n/a (and never probes)" {
  stub_brew 5; stub_apt 5
  run_us read
  [ "$status" -eq 0 ]
  [ "$output" = "n/a" ]
  [ ! -s "$CALLS" ]                      # read NEVER touches a manager
}

@test "read: pending counts render as '12 pkg · repo ↓3'" {
  echo '{"ts":"x","brew":9,"apt":3,"repo_behind":3,"repo_ahead":0,"last_run":null}' > "$SNAP"
  run_us read
  [ "$status" -eq 0 ]
  [ "$output" = "12 pkg · repo ↓3" ]
}

@test "read: probed-and-clean renders 'current'; all-null renders 'n/a'" {
  echo '{"ts":"x","brew":0,"apt":0,"repo_behind":0,"repo_ahead":0,"last_run":null}' > "$SNAP"
  run_us read
  [ "$output" = "current" ]
  echo '{"ts":"x","brew":null,"apt":null,"repo_behind":null,"repo_ahead":null,"last_run":null}' > "$SNAP"
  run_us read
  [ "$output" = "n/a" ]
}

@test "read --json: dumps the raw snapshot" {
  echo '{"ts":"x","brew":1,"apt":null,"repo_behind":null,"repo_ahead":null,"last_run":null}' > "$SNAP"
  run_us read --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.brew == 1'
}

# ── readers: situation.sh ────────────────────────────────────────────────────

@test "situation probe: merges .updates from a fresh updates.json" {
  echo '{"ts":"x","brew":7,"apt":2,"repo_behind":1,"repo_ahead":0,"last_run":1755424800}' > "$SNAP"
  run env DOTFILES_DIR="$DOTS" bash "$SIT" probe
  [ "$status" -eq 0 ]
  sit="$CACHE/situation.json"
  [ -f "$sit" ]
  jq -e '.updates.brew == 7 and .updates.apt == 2' "$sit"
  jq -e '.updates.repo_behind == 1 and .updates.last_run == 1755424800' "$sit"
}

@test "situation probe: a stale (>24h) updates.json merges as nulls" {
  echo '{"ts":"x","brew":7,"apt":2,"repo_behind":1,"repo_ahead":0,"last_run":null}' > "$SNAP"
  touch -t 202001010000 "$SNAP"
  run env DOTFILES_DIR="$DOTS" bash "$SIT" probe
  [ "$status" -eq 0 ]
  jq -e '.updates.brew == null and .updates.repo_behind == null' "$CACHE/situation.json"
}

@test "situation tick: info alert on the rising edge of repo_behind only" {
  echo '{"ts":"x","brew":0,"apt":0,"repo_behind":4,"repo_ahead":0,"last_run":null}' > "$SNAP"
  # previous snapshot: not behind (0) → this tick is the rising edge
  echo '{"updates":{"repo_behind":0}}' > "$CACHE/situation.json"
  run env DOTFILES_DIR="$DOTS" bash "$SIT" tick
  [ "$status" -eq 0 ]
  grep -q 'Dotfiles behind' "$CACHE/situation.alerts.tsv"
  # second tick: STILL behind 4 — no edge, no second alert
  run env DOTFILES_DIR="$DOTS" bash "$SIT" tick
  [ "$status" -eq 0 ]
  [ "$(grep -c 'Dotfiles behind' "$CACHE/situation.alerts.tsv")" -eq 1 ]
}

@test "situation tick: UPDATES_NOTIFY=off gates the repo-behind alert" {
  mkdir -p "$XDG_CONFIG_HOME/claw"
  echo 'UPDATES_NOTIFY=off' > "$XDG_CONFIG_HOME/claw/situation.env"
  echo '{"ts":"x","brew":0,"apt":0,"repo_behind":4,"repo_ahead":0,"last_run":null}' > "$SNAP"
  echo '{"updates":{"repo_behind":0}}' > "$CACHE/situation.json"
  run env DOTFILES_DIR="$DOTS" bash "$SIT" tick
  [ "$status" -eq 0 ]
  ! grep -q 'Dotfiles behind' "$CACHE/situation.alerts.tsv" 2>/dev/null
}

@test "situation show: appends updates:N repo:↓N when present" {
  echo '{"ts":"x","brew":9,"apt":3,"repo_behind":2,"repo_ahead":0,"last_run":null}' > "$SNAP"
  run env DOTFILES_DIR="$DOTS" bash "$SIT" probe
  [ "$status" -eq 0 ]
  run env DOTFILES_DIR="$DOTS" bash "$SIT" show
  [ "$status" -eq 0 ]
  [[ "$output" == *"updates:12"* ]]
  [[ "$output" == *"repo:↓2"* ]]
}

# ── readers: ff-readout + welcome-TUI kick ───────────────────────────────────

@test "ff-readout fields: emits the updates= line from the cache" {
  echo '{"ts":"x","brew":5,"apt":4,"repo_behind":2,"repo_ahead":0,"last_run":null}' > "$SNAP"
  run env DOTFILES_DIR="$DOTFILES" bash "$FFR" fields
  [ "$status" -eq 0 ]
  [[ "$output" == *"updates=9 pkg · repo ↓2"* ]]
}

@test "ff-readout fields: no cache => empty updates= (field drops, no probe)" {
  run env DOTFILES_DIR="$DOTFILES" bash "$FFR" fields
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'updates='
}

@test "welcome TUI: third background kick refreshes update-status" {
  grep -qF 'update-status.sh" --refresh &>/dev/null &!' "$DOTFILES/shell/welcome-tui.zsh"
  run zsh -n "$DOTFILES/shell/welcome-tui.zsh"
  [ "$status" -eq 0 ]
}

# ── hygiene ──────────────────────────────────────────────────────────────────

@test "shellcheck: update-status.sh passes at warning severity (house exclusions)" {
  command -v shellcheck &>/dev/null || skip "shellcheck not installed"
  run shellcheck -x -S warning -e SC1090,SC1091,SC2034,SC2059,SC2015,SC2154 "$US"
  [ "$status" -eq 0 ]
}
