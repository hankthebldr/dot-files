#!/usr/bin/env bats
# audit 2026-09-20 F-16: `claw tui-stats` was the instrument that told Henry the
# wrong thing — it counted only fires that produced an outcome (13% no-ops
# against a true 85% dark rate) and bucketed picks with hardcoded regexes that
# mis-filed `vault` and `homelab`. These tests pin the rewritten instrument:
# the --days window, the --actor split, registry-driven pick classification,
# and the two rates the old one could not compute at all (abort, autoload).

REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
CLAW="$REPO/bin/claw"

# A fixed clock so the window maths is deterministic on every host.
NOW=1789900000

setup() {
  export CLAW_NO_LOG=1
  export DOTFILES_DIR="$REPO"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export CLAW_NOW="$NOW"
  export NO_COLOR=1
  mkdir -p "$HOME" "$XDG_CACHE_HOME/claw"
  LOG="$XDG_CACHE_HOME/claw/usage.tsv"
}

# Write one usage row. $1 = seconds BEFORE $NOW, $2 = event, $3 = profile,
# $4 = payload (omit entirely for a legacy 4-column row).
row() {
  local ago="$1" ev="$2" prof="${3:-none}" pay="${4-__NONE__}" ts
  ts="$(python3 -c 'import sys,time;print(time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime(int(sys.argv[1]))))' \
        "$(( NOW - ago ))")"
  if [ "$pay" = "__NONE__" ]; then
    printf '%s\t%s\t0\t%s\n' "$ts" "$ev" "$prof" >> "$LOG"
  else
    printf '%s\t%s\t0\t%s\t%s\n' "$ts" "$ev" "$prof" "$pay" >> "$LOG"
  fi
}

H='term=ghostty;actor=human'
A='term=xterm-256color;actor=agent'

# A small but representative log: fresh human logins, an agent loop, palette
# traffic, two aborts, one autoload correction, and pre-instrumentation
# legacy rows — including the `tui:pick:vault` the old code mis-bucketed.
seed() {
  row 3600  'tui:login:human:default' default "$H"
  row 3500  'tui:login:human:default' default "$H"
  row 3400  'tui:login:ssh:default'   default 'term=xterm;actor=ssh'
  row 3300  'tui:abort:render'        default "$H"
  row 3200  'tui:abort:init'          default "$H"
  row 3100  'tui:palette:open'        default "$H"
  row 3090  'tui:palette:pick:security' default "$H"
  row 3080  'tui:palette:open'        default "$H"
  row 3070  'tui:palette:esc'         default 'term=ghostty;actor=human;q=tunnl'
  # autoload correction: a human login then `claw load security` 60 s later
  row 3000  'tui:login:human:default' default "$H"
  row 2940  'load:security'           default "$H"
  # agent loop — must never inflate the human numbers
  row 2000  'harness'                 none "$A"
  row 1900  'upgrade'                 none "$A"
  row 1800  'tui:login:agent:default' default "$A"
  # legacy, pre-instrumentation rows (4 columns, no payload)
  row 1700  'tui:fire'                none
  row 1600  'tui:pick:vault'          none
  row 1500  'tui:pick:vault'          none
  row 1400  'tui:esc_to_default'      none
  # out of a 30-day window, inside a 60-day one
  row 3456000 'tui:login:human:cortex' cortex "$H"   # 40 days ago
  row 3456100 'tui:pick:doctor'        none
}

@test "tui-stats: no log yet is a soft no-op" {
  run env "CLAW_NOW=$NOW" bash "$CLAW" tui-stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"no usage logged yet"* ]]
}

@test "tui-stats: --days windows the log and reports the window it used" {
  seed
  run env "CLAW_NOW=$NOW" bash "$CLAW" tui-stats --days 30 --actor all
  [ "$status" -eq 0 ]
  [[ "$output" == *"last 30 days"* ]]
  # the 40-day-old cortex login is outside the window
  [[ "$output" != *"cortex"* ]]

  run env "CLAW_NOW=$NOW" bash "$CLAW" tui-stats --days 60 --actor all
  [ "$status" -eq 0 ]
  [[ "$output" == *"last 60 days"* ]]
  [[ "$output" == *"cortex"* ]]
}

@test "tui-stats: --actor human suppresses the agent loop, --actor agent shows it" {
  seed
  run env "CLAW_NOW=$NOW" bash "$CLAW" tui-stats --actor human
  [ "$status" -eq 0 ]
  [[ "$output" == *"actor human"* ]]
  # 4 human logins + 1 ssh login; the agent's CLI loop is not in this view
  [[ "$output" == *"Logins by mode"* ]]
  [[ "$output" != *"harness"* ]]

  run env "CLAW_NOW=$NOW" bash "$CLAW" tui-stats --actor agent
  [ "$status" -eq 0 ]
  [[ "$output" == *"actor agent"* ]]
  [[ "$output" == *"Top verbs"* ]]
  [[ "$output" == *"harness"* ]]
}

@test "tui-stats: legacy tui:pick:vault is classified from the registry, not a regex" {
  seed
  run env "CLAW_NOW=$NOW" bash "$CLAW" tui-stats --actor all
  [ "$status" -eq 0 ]
  [[ "$output" == *"Top picks"* ]]
  # `vault` is a profile in the registry; the old code filed it under tools.
  [[ "$output" =~ vault[[:space:]]+profile ]]
  [[ "$output" =~ security[[:space:]]+profile ]]
}

@test "tui-stats: reports abort rate and autoload accuracy for human rows" {
  seed
  run env "CLAW_NOW=$NOW" bash "$CLAW" tui-stats --actor human
  [ "$status" -eq 0 ]
  [[ "$output" == *"Abort rate"* ]]
  [[ "$output" == *"Autoload accuracy"* ]]
  [[ "$output" == *"init"* ]]
  [[ "$output" == *"render"* ]]
}

@test "tui-stats: reports palette opens/picks/esc and top no-pick queries" {
  seed
  run env "CLAW_NOW=$NOW" bash "$CLAW" tui-stats --actor human
  [ "$status" -eq 0 ]
  [[ "$output" == *"Palette"* ]]
  [[ "$output" == *"No-pick queries"* ]]
  [[ "$output" == *"tunnl"* ]]
}

@test "tui-stats: the footer names the real log path" {
  seed
  # regression: the awk var was called `log`, which is awk's natural-logarithm
  # builtin — the footer printed 7.61382 instead of the path.
  run env "CLAW_NOW=$NOW" bash "$CLAW" tui-stats --actor all
  [ "$status" -eq 0 ]
  [[ "$output" == *"log: $LOG"* ]]
}

@test "tui-stats: rejects a bad --actor" {
  seed
  run env "CLAW_NOW=$NOW" bash "$CLAW" tui-stats --actor wombat
  [ "$status" -ne 0 ]
  [[ "$output" == *"--actor"* ]]
}
