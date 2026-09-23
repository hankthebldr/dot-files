#!/usr/bin/env bats
# situation.sh evaluate / local / homelab — the ONE attention rule set and the
# two probes that feed it. Contract (normative, consumed by the login strip,
# the dashboard card, the p10k ⚑ segment and the notifier):
#   attention.tsv   tier\tid\ttext\thint\tsince_epoch\tsrc_epoch, crit→warn→info then since asc
#   attention.count one line "<n> <worst_tier>"; n counts crit+warn; "0 ok" when clear
#   attention.json  {v:1, checked:{situation,homelab,updates,local}, items:[{id,tier,text,hint,since,src_ts}]}
#   Design: docs/superpowers/specs/2026-09-20-tui-redesign-design.md (Attention rules, State files)

setup() {
  DOTFILES="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SIT="$DOTFILES/scripts/utils/situation.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures/attention"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export DOTFILES_DIR="$DOTFILES"
  export CLAW_NO_LOG=1
  CACHE="$XDG_CACHE_HOME/claw"
  STATE="$XDG_STATE_HOME/claw"
  STUB="$BATS_TEST_TMPDIR/stub"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$HOME" "$CACHE" "$STATE" "$STUB" "$XDG_CONFIG_HOME/claw"
  : > "$CALLS"
}

need_jq() { command -v jq >/dev/null || skip "jq required"; }

# seed <name>… : copy a fixture cache in with a fresh mtime
seed() { local f; for f in "$@"; do cp "$FIX/$f.json" "$CACHE/$f.json"; done; }

ev() { run env PATH="$STUB:$PATH" bash "$SIT" evaluate; }

# tier of an item id in attention.json ("-" when absent)
tier_of() { jq -r --arg i "$1" '[.items[] | select(.id==$i) | .tier][0] // "-"' "$CACHE/attention.json"; }
text_of() { jq -r --arg i "$1" '[.items[] | select(.id==$i) | .text][0] // "-"' "$CACHE/attention.json"; }
hint_of() { jq -r --arg i "$1" '[.items[] | select(.id==$i) | .hint][0] // "-"' "$CACHE/attention.json"; }

# ── evaluate: the rule table ───────────────────────────────────────────────

@test "evaluate: k3s ready<total is a crit item naming the cluster context" {
  need_jq; seed situation homelab updates local
  ev; [ "$status" -eq 0 ]
  [ -f "$CACHE/attention.json" ]
  [ "$(tier_of k3s)" = "crit" ]
  [[ "$(text_of k3s)" == "k3s 2/3 Ready · k3s-ms01" ]]
}

@test "evaluate: brew_err is a warn carrying the xcode-license hint" {
  need_jq; seed situation homelab updates local
  ev; [ "$status" -eq 0 ]
  [ "$(tier_of brew)" = "warn" ]
  [[ "$(text_of brew)" == *"xcode-license"* ]]
  [ "$(hint_of brew)" = "sudo xcodebuild -license" ]
}

@test "evaluate: repo_behind is an info item hinting claw update" {
  need_jq; seed situation homelab updates local
  ev; [ "$status" -eq 0 ]
  [ "$(tier_of repo)" = "info" ]
  [ "$(text_of repo)" = "dotfiles ↓3" ]
  [ "$(hint_of repo)" = "claw update" ]
}

@test "evaluate: a down machine is crit and an unknown machine is not an item" {
  need_jq; seed situation homelab updates local
  ev; [ "$status" -eq 0 ]
  [ "$(tier_of machine:r630)" = "crit" ]
  [ "$(text_of machine:r630)" = "r630 down" ]
  [ "$(tier_of machine:bd790i)" = "-" ]
}

@test "evaluate: a non-up service on an up machine is a warn, planned is not" {
  need_jq; seed situation homelab updates local
  ev; [ "$status" -eq 0 ]
  [ "$(tier_of svc:ms-01:gitea)" = "warn" ]
  [ "$(text_of svc:ms-01:gitea)" = "gitea on ms-01" ]
  [ "$(tier_of svc:ms-01:harbor)" = "-" ]
}

@test "evaluate: since is carried over when an id persists" {
  need_jq; seed situation homelab updates local
  ev; [ "$status" -eq 0 ]
  first="$(jq -r '[.items[] | select(.id=="k3s") | .since][0]' "$CACHE/attention.json")"
  [ -n "$first" ] && [ "$first" != "null" ]
  sleep 1
  ev; [ "$status" -eq 0 ]
  second="$(jq -r '[.items[] | select(.id=="k3s") | .since][0]' "$CACHE/attention.json")"
  [ "$second" = "$first" ]
}

@test "evaluate: an acked id is hidden from tsv and count but kept as info in json" {
  need_jq; seed situation homelab updates local
  printf 'k3s\t%s\n' "$(( $(date +%s) + 3600 ))" > "$STATE/acks.tsv"
  ev; [ "$status" -eq 0 ]
  [ "$(tier_of k3s)" = "info" ]
  [ "$(hint_of k3s)" = "acked" ]
  run grep -c $'\tk3s\t' "$CACHE/attention.tsv"
  [ "$output" = "0" ]
  # r630 crit + gitea warn + brew warn remain; the acked k3s crit does not count
  [ "$(cut -d' ' -f1 < "$CACHE/attention.count")" = "3" ]
}

@test "evaluate: a stale source is dropped and reported as one warn" {
  need_jq; seed situation
  touch -t 202001010000 "$CACHE/situation.json"
  ev; [ "$status" -eq 0 ]
  [ "$(tier_of k3s)" = "-" ]           # situation-derived items are dropped
  [ "$(tier_of stale:situation)" = "warn" ]
  [[ "$(text_of stale:situation)" == "situation stale "* ]]
}

@test "evaluate: attention.count is '0 ok' when nothing fires" {
  need_jq
  ev; [ "$status" -eq 0 ]
  [ "$(cat "$CACHE/attention.count")" = "0 ok" ]
  [ ! -s "$CACHE/attention.tsv" ]
  run jq -e '.v == 1 and (.items|length) == 0 and (.checked|has("situation"))' "$CACHE/attention.json"
  [ "$status" -eq 0 ]
}

@test "evaluate: attention.tsv is 6 columns sorted crit, warn, info" {
  need_jq; seed situation homelab updates local
  ev; [ "$status" -eq 0 ]
  run awk -F'\t' '{print NF}' "$CACHE/attention.tsv"
  for n in $output; do [ "$n" = "6" ]; done
  run awk -F'\t' '{printf "%s ", $1}' "$CACHE/attention.tsv"
  [[ "$output" == "crit crit warn warn info "* ]] || [[ "$output" == "crit crit warn warn warn info "* ]]
  [ "$(cat "$CACHE/attention.count")" = "4 crit" ]
}

# ── tick: notify on transitions only, from the evaluated diff ──────────────

_tick_stubs() {
  NOTIFYLOG="$BATS_TEST_TMPDIR/notify.log"; : > "$NOTIFYLOG"
  FAKE_DOT="$BATS_TEST_TMPDIR/dot"; mkdir -p "$FAKE_DOT/scripts/utils"
  cat > "$FAKE_DOT/scripts/utils/notify.sh" <<EOF
#!/usr/bin/env bash
echo "notify \$*" >> "$NOTIFYLOG"
EOF
  chmod +x "$FAKE_DOT/scripts/utils/notify.sh"
  for t in tailscale kubectl gh curl nvidia-smi ping yq; do
    printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/$t"
  done
  cat > "$STUB/df" <<'EOF'
#!/usr/bin/env bash
echo "Filesystem 512-blocks Used Avail Capacity Mounted on"
echo "/dev/disk1 100 95 5 ${FAKE_DISK:-95}% /"
EOF
  chmod +x "$STUB"/*
}

tick() { run env PATH="$STUB:$PATH" DOTFILES_DIR="$FAKE_DOT" FAKE_DISK="$1" bash "$SIT" tick; }

@test "tick: notifies once when a crit appears and once when it clears" {
  need_jq; _tick_stubs
  tick 95; [ "$status" -eq 0 ]
  run grep -c 'disk 95%' "$NOTIFYLOG"; [ "$output" = "1" ]
  tick 95; [ "$status" -eq 0 ]
  run grep -c 'disk 95%' "$NOTIFYLOG"; [ "$output" = "1" ]   # still once — no re-notify
  tick 10; [ "$status" -eq 0 ]
  run grep -c 'disk back' "$NOTIFYLOG"; [ "$output" = "1" ]
}

@test "tick: leaves no hand-rolled transition blocks in the source" {
  run grep -c 'pts" = "Running"' "$SIT"
  [ "$output" = "0" ]
}

# ── local ──────────────────────────────────────────────────────────────────

_local_stubs() {
  cat > "$STUB/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >> "$CALLS"
case "\$*" in
  *"status --porcelain"*) echo " M file" ;;
  *"worktree list"*)      echo "/x abc [main]" ;;
esac
EOF
  # BSD pgrep has no -c, so situation.sh counts pid LINES — the stub prints three
  printf '#!/usr/bin/env bash\necho "pgrep $*" >> "%s"\nprintf "101\\n102\\n103\\n"\n' "$CALLS" > "$STUB/pgrep"
  printf '#!/usr/bin/env bash\necho "sqlite3 $*" >> "%s"\necho 7\n' "$CALLS" > "$STUB/sqlite3"
  chmod +x "$STUB"/*
  mkdir -p "$HOME/Github/repo-a/.git" "$HOME/Github/repo-b/.git"
}

@test "local --force: writes local.json with the documented keys" {
  need_jq; _local_stubs
  run env PATH="$STUB:$PATH" bash "$SIT" local --force
  [ "$status" -eq 0 ]
  [ -f "$CACHE/local.json" ]
  run jq -e 'has("ts") and has("things") and has("handoff") and has("repos")
             and has("worktrees") and has("claude_sessions") and has("cwd_repo")' "$CACHE/local.json"
  [ "$status" -eq 0 ]
  run jq -r '.repos.total' "$CACHE/local.json"; [ "$output" = "2" ]
  run jq -r '.repos.dirty' "$CACHE/local.json"; [ "$output" = "2" ]
  run jq -r '.repos.sample | length' "$CACHE/local.json"; [ "$output" = "2" ]
  run jq -r '.claude_sessions' "$CACHE/local.json"; [ "$output" = "3" ]
  # evaluate ran on the back of it
  [ -f "$CACHE/attention.json" ]
}

@test "local: a probe absent from the box degrades to null, never a failure" {
  need_jq; _local_stubs; rm -f "$STUB/sqlite3"
  run env PATH="$STUB:$PATH" bash "$SIT" local --force
  [ "$status" -eq 0 ]
  run jq -r '.things' "$CACHE/local.json"; [ "$output" = "null" ]
}

@test "local: a second call inside the throttle window does not re-probe" {
  need_jq; _local_stubs
  run env PATH="$STUB:$PATH" bash "$SIT" local --force
  [ "$status" -eq 0 ]; grep -q '^git ' "$CALLS"
  : > "$CALLS"
  run env PATH="$STUB:$PATH" bash "$SIT" local
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

# ── cache hygiene (T2-09) ──────────────────────────────────────────────────
# shell/delight.zsh used to touch a fact-YYYYMMDD / pkgscan-YYYYMMDD stamp per
# day and never prune (63 zero-byte files at audit time). The day now lives in
# ONE rewritten file per concern; `situation.sh local` sweeps the backlog.

@test "local: prunes fact-* and pkgscan-* stamps older than 30 d" {
  need_jq; _local_stubs
  touch -t 202001010000 "$CACHE/fact-20200101" "$CACHE/pkgscan-20200101"
  touch "$CACHE/fact-today" "$CACHE/pkgscan-today"
  run env PATH="$STUB:$PATH" bash "$SIT" local --force
  [ "$status" -eq 0 ]
  [ ! -e "$CACHE/fact-20200101" ]
  [ ! -e "$CACHE/pkgscan-20200101" ]
  # a stamp inside the grace window is left alone
  [ -e "$CACHE/fact-today" ]
  [ -e "$CACHE/pkgscan-today" ]
}

@test "local: pruning never touches the caches the login path reads" {
  need_jq; _local_stubs
  touch -t 202001010000 "$CACHE/situation.json" "$CACHE/attention.tsv" \
                        "$CACHE/card.stamp" "$CACHE/fact.stamp"
  run env PATH="$STUB:$PATH" bash "$SIT" local --force
  [ "$status" -eq 0 ]
  [ -e "$CACHE/attention.tsv" ]
  [ -e "$CACHE/card.stamp" ]
  [ -e "$CACHE/fact.stamp" ]
}

# ── delight.zsh daily stamp ────────────────────────────────────────────────

# Run <zsh code> with delight.zsh sourced. Non-interactive, so the file's own
# fact / pkg-nudge trigger blocks are inert and only the mechanism is exercised.
dz() {
  run env HOME="$HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" CLAW_NO_LOG=1 \
      zsh -fc "DOTFILES_DIR='$DOTFILES'; source '$DOTFILES/shell/delight.zsh'; $1"
}

@test "delight: _claw_day_stamp reports a day that has not been claimed yet" {
  command -v zsh >/dev/null || skip "zsh required"
  dz '_claw_day_stamp "$XDG_CACHE_HOME/claw/fact.stamp" && print yes || print no'
  [ "$status" -eq 0 ]
  [ "$output" = yes ]
}

@test "delight: claim writes today INTO one file and is idempotent for the day" {
  command -v zsh >/dev/null || skip "zsh required"
  f="$CACHE/fact.stamp"
  dz "_claw_day_stamp '$f' claim"
  [ "$status" -eq 0 ]
  [ "$(cat "$f")" = "$(date +%Y%m%d)" ]
  dz "_claw_day_stamp '$f' && print yes || print no"
  [ "$output" = no ]
  # a second claim rewrites the SAME file — nothing accumulates
  dz "_claw_day_stamp '$f' claim"
  [ "$(find "$CACHE" -maxdepth 1 -name 'fact*' | wc -l | tr -d ' ')" = 1 ]
}

@test "delight: claim sweeps the legacy per-day stamps it replaces" {
  command -v zsh >/dev/null || skip "zsh required"
  touch "$CACHE/fact-20260101" "$CACHE/fact-20260102" "$CACHE/keep.json"
  dz "_claw_day_stamp '$CACHE/fact.stamp' claim"
  [ "$status" -eq 0 ]
  [ ! -e "$CACHE/fact-20260101" ]
  [ ! -e "$CACHE/fact-20260102" ]
  [ -e "$CACHE/fact.stamp" ]
  [ -e "$CACHE/keep.json" ]
}

@test "delight: no per-day stamp path survives in the source" {
  run grep -nE '(fact|pkgscan)-\$\(date' "$DOTFILES/shell/delight.zsh"
  [ "$status" -ne 0 ]
}

# ── homelab throttle + single-flight lock ──────────────────────────────────

_hl_stubs() {
  printf '#!/usr/bin/env bash\necho "yq $*" >> "%s"\nexit 1\n' "$CALLS" > "$STUB/yq"
  for t in tailscale kubectl gh curl ping; do printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/$t"; done
  chmod +x "$STUB"/*
  cat > "$XDG_CONFIG_HOME/claw/fleet.yml" <<'YML'
fleet: { name: T, poll_seconds: 60 }
cluster: { context: "", traefik_ip: "" }
machines: []
services: {}
YML
}

@test "homelab: a second poll inside 300 s does not re-read the fleet file" {
  _hl_stubs
  run env PATH="$STUB:$PATH" bash "$SIT" homelab
  [ "$status" -eq 0 ]; grep -q '^yq ' "$CALLS"
  : > "$CALLS"
  run env PATH="$STUB:$PATH" bash "$SIT" homelab
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "homelab: --force overrides the throttle" {
  _hl_stubs
  run env PATH="$STUB:$PATH" bash "$SIT" homelab
  [ "$status" -eq 0 ]
  : > "$CALLS"
  run env PATH="$STUB:$PATH" bash "$SIT" homelab --force
  [ "$status" -eq 0 ]
  grep -q '^yq ' "$CALLS"
}

@test "homelab: a fresh lock directory makes the poll a silent no-op" {
  _hl_stubs
  mkdir -p "$CACHE/.hl.lock"
  run env PATH="$STUB:$PATH" bash "$SIT" homelab
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  [ ! -f "$CACHE/homelab.json" ]
  [ -d "$CACHE/.hl.lock" ]            # someone else's lock is left alone
}

@test "homelab: a stale lock directory is reclaimed" {
  _hl_stubs
  mkdir -p "$CACHE/.hl.lock"
  touch -t 202001010000 "$CACHE/.hl.lock"
  run env PATH="$STUB:$PATH" bash "$SIT" homelab
  [ "$status" -eq 0 ]
  grep -q '^yq ' "$CALLS"
  [ ! -d "$CACHE/.hl.lock" ]
}
