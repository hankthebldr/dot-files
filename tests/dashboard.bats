#!/usr/bin/env bats
# claw-dashboard.py render tests. Run: bats tests/

setup() {
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR"; mkdir -p "$HOME"
}

# infra_lines() should render each cloud identity with its OWN provider glyph
# (AWS=U+F270, GCP=U+F1A0, Azure=U+F17A), not a single shared cloud icon, and
# without the old "aws:"/"gcp:"/"az:" text prefixes.
@test "dashboard infra_lines: per-provider cloud icons (aws/gcp/azure)" {
  run env NO_COLOR=1 python3 - "$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py" <<'PY'
import sys, importlib.util as u
spec = u.spec_from_file_location('d', sys.argv[1])
m = u.module_from_spec(spec); spec.loader.exec_module(m)
# Neutralize the non-cloud probes so output is deterministic (no tailscale/tunnels).
m.shutil.which = lambda *_: None
m._tunnel_count = lambda: 0
m._aws_profile = lambda: '111111111111'
m._gcp_project = lambda: 'my-gcp-proj'
m._az_subscription = lambda: 'my-azure-sub'
out = '\n'.join(m.infra_lines())
print(out)
glyphs = tuple(chr(c) for c in (0xf270, 0xf1a0, 0xf17a))   # aws / gcp / azure
print('GLYPHS_OK' if all(g in out for g in glyphs) else 'GLYPHS_MISSING')
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"111111111111"* ]]
  [[ "$output" == *"my-gcp-proj"* ]]
  [[ "$output" == *"my-azure-sub"* ]]
  [[ "$output" == *"GLYPHS_OK"* ]]
  [[ "$output" != *"aws:"* ]]
}

# A new tab inherits the current window width (window-width applies to new
# windows only), so the dashboard box must clamp to the live terminal instead of
# overflowing/wrapping.
@test "dashboard: box clamps to a narrow terminal — no overflow" {
  run env COLUMNS=58 DOTFILES_DIR="$BATS_TEST_DIRNAME/.." python3 "$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py"
  [ "$status" -eq 0 ]
  # measure VISIBLE width (strip ANSI) — a clipped line may carry a reset code
  maxw=$(printf '%s\n' "$output" | python3 -c 'import sys,re
a=re.compile("\x1b\\[[0-9;?]*[A-Za-z]")
print(max((len(a.sub("",l)) for l in sys.stdin.read().splitlines()), default=0))')
  [ "$maxw" -le 58 ]
}

# Each homelab service renders with its OWN implementation icon (not a generic
# dot): docker U+F308, ollama U+F2DB, portainer U+F1B3, plus the github/server/
# route glyphs on the head + machine rows.
@test "dashboard homelab_lines: per-service implementation icons" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  python3 - "$XDG_CACHE_HOME/claw/homelab.json" <<'PY'
import sys, json
json.dump({"ts":"2099-01-01T00:00:00Z","fleet":"HR-TRUST",
  "route":{"via":"direct","path":"→ bd790i","exit_node":None},
  "identity":{"github":{"user":"hankthebldr","state":"up"}},
  "machines":[{"id":"bd790i","state":"up","addr":"100.64.0.5","latency_ms":12,
    "services":[{"id":s,"state":"up","detail":"x"} for s in
      ["tailscale","k3s","docker","gitea","ollama","portainer"]]}]},
  open(sys.argv[1],"w"))
PY
  run env NO_COLOR=1 python3 - "$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py" <<'PY'
import sys, importlib.util as u
spec=u.spec_from_file_location('d', sys.argv[1]); m=u.module_from_spec(spec); spec.loader.exec_module(m)
out="\n".join(m.homelab_lines())
need={"docker":0xf308,"ollama":0xf2db,"portainer":0xf1b3,"gitea":0xf1d3,
      "github":0xf09b,"server":0xf233}
print("ALL_ICONS_OK" if all(chr(c) in out for c in need.values()) else "ICONS_MISSING")
print(out)
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALL_ICONS_OK"* ]]
  [[ "$output" == *"bd790i"* ]]
}

# Audit 2026-09-20 F-08: load is shown as TEXT (`Load  <load1>/<ncpu>`), never a
# red bar — the old ("cpu","CPU") bar was load1/ncpu clamped at 100%. Colour
# comes from the loaded palette: fg below 1.0, amber ≥1.0, red ≥2.0.
@test "dashboard bar_rows: Load text row present, CPU bar absent, palette thresholds" {
  run env NO_COLOR=1 python3 - "$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py" <<'PY'
import sys, importlib.util as u
spec = u.spec_from_file_location('d', sys.argv[1])
m = u.module_from_spec(spec); spec.loader.exec_module(m)
base = dict(cores="14", mem_pct="72", swap_pct="3", disk_pct="82", batt_pct="90")
rows = m.bar_rows(dict(base, load="2.2 1.9 1.7", load_ratio="0.16", cpu_pct="16"))
print("\n".join(rows))
print("NO_CPU_BAR" if not any("CPU " in r for r in rows) else "CPU_BAR_PRESENT")
load = [r for r in rows if "Load" in r]
print("LOAD_TEXT" if len(load) == 1 and "[" not in load[0] and "2.2/14" in load[0] else "LOAD_BAD")
# threshold colours, from the palette dict (never literals)
m.NOCOLOR = False
def tone(ratio, load1):
    return [x for x in m.bar_rows(dict(base, load=f"{load1} 0 0", load_ratio=ratio, cpu_pct="0")) if "Load" in x][0]
ok = m.C["fg"] in tone("0.50", "7.0") and m.C["amber"] not in tone("0.50", "7.0") and m.C["red"] not in tone("0.50", "7.0")
ok = ok and m.C["amber"] in tone("1.00", "14.0") and m.C["red"] not in tone("1.00", "14.0")
ok = ok and m.C["red"] in tone("2.00", "28.0")
print("TONES_OK" if ok else "TONES_BAD")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO_CPU_BAR"* ]]
  [[ "$output" == *"LOAD_TEXT"* ]]
  [[ "$output" == *"TONES_OK"* ]]
  [[ "$output" == *"Mem "* ]]
  [[ "$output" == *"Disk"* ]]
}

@test "dashboard render: no CPU bar row anywhere in the frame" {
  run env NO_COLOR=1 COLUMNS=120 DOTFILES_DIR="$BATS_TEST_DIRNAME/.." python3 "$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Load"* ]]
  ! printf '%s\n' "$output" | grep -qE 'CPU +\['
}
