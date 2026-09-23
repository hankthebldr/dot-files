#!/usr/bin/env bats
# ff-readout.sh `fields` — the dashboard's key=value data contract.
# Audit 2026-09-20 F-04: macOS uptime read 20708d because the kern.boottime
# sed captured the `usec` field. Pin the parser.

setup() {
  export DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export CLAW_NO_LOG=1
  mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
  FFR="$DOTFILES_DIR/scripts/utils/ff-readout.sh"
}

uptime_days() { printf '%s\n' "$1" | awk -F'uptime=' '/^uptime=/{split($2,a,"d"); print a[1]}'; }

@test "ff-readout uptime: days are plausible (< 10 years) on this host" {
  run bash "$FFR" fields
  [ "$status" -eq 0 ]
  d="$(uptime_days "$output")"
  [ -n "$d" ]
  [ "$d" -lt 3650 ]
}

@test "ff-readout uptime (Darwin): parses kern.boottime sec, not usec" {
  [ "$(uname -s)" = Darwin ] || skip "macOS-only parser"
  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  boot=$(( $(date +%s) - 7200 ))            # booted exactly 2h ago
  cat > "$stub/sysctl" <<STUB
#!/usr/bin/env bash
if [ "\$1" = -n ] && [ "\$2" = kern.boottime ]; then
  echo "{ sec = $boot, usec = 747253 } Sun Sep 20 12:00:00 2026"; exit 0
fi
exec /usr/sbin/sysctl "\$@"
STUB
  chmod +x "$stub/sysctl"
  run env PATH="$stub:$PATH" bash "$FFR" fields
  [ "$status" -eq 0 ]
  [[ "$output" == *"uptime=0d 2h 0m"* || "$output" == *"uptime=0d 2h 1m"* ]]
}

# Audit 2026-09-20 F-08: the "CPU" bar was load1/ncpu clamped at 100 (26.8/14
# rendered a full red bar). cpu_pct stays as a key but is no longer clamped, and
# `fields` also emits load_ratio (load1/ncpu, 2 decimals) so the dashboard can
# show load as text with threshold colouring.
@test "ff-readout load (Darwin): cpu_pct unclamped, load_ratio 2 decimals (28/14 → 200, 2.00)" {
  [ "$(uname -s)" = Darwin ] || skip "macOS-only sysctl stub"
  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  cat > "$stub/sysctl" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = -n ] && [ "$2" = vm.loadavg ]; then echo "{ 28.0 2.0 1.0 }"; exit 0; fi
if [ "$1" = -n ] && [ "$2" = hw.ncpu ];    then echo "14"; exit 0; fi
exec /usr/sbin/sysctl "$@"
STUB
  chmod +x "$stub/sysctl"
  run env PATH="$stub:$PATH" bash "$FFR" fields
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'cpu_pct=200'
  printf '%s\n' "$output" | grep -qx 'load_ratio=2.00'
}

@test "ff-readout fields: emits load_ratio (cross-platform)" {
  run bash "$FFR" fields
  [ "$status" -eq 0 ]
  n=$(printf '%s\n' "$output" | grep -c '^load_ratio=')
  [ "$n" -eq 1 ]
}

# Audit F-12: `fields` printed mem_pct twice (g() memory_pressure branch AND the
# pct() vm_stat path). One key, one value — from pct().
@test "ff-readout fields: emits exactly one mem_pct= line" {
  run bash "$FFR" fields
  [ "$status" -eq 0 ]
  n=$(printf '%s\n' "$output" | grep -c '^mem_pct=')
  [ "$n" -eq 1 ]
}
