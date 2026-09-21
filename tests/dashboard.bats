#!/usr/bin/env bats
# claw-dashboard.py render tests. Run: bats tests/
#
# Every case feeds the pinned fastfetch fixture (tests/fixtures/fastfetch.json)
# via --json-fixture: CI has no fastfetch, and a live probe would make the
# assertions machine-dependent.

setup() {
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR"; mkdir -p "$HOME"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export CLAW_NO_LOG=1
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"; mkdir -p "$XDG_CONFIG_HOME"
  # The renderer is depth- and glyph-aware as of T2-03; pin both inputs so a
  # bats run never inherits the ambient TERM / CLAW_GLYPHS.
  export TERM=xterm-256color
  unset CLAW_GLYPHS CLAW_COLOR_DEPTH CLAW_COLOR_DEPTH_STRICT CLAW_FORCE_COLOR
  DASH="$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py"
  FIX="$BATS_TEST_DIRNAME/fixtures/fastfetch.json"
}

# Visible width (ANSI stripped) of the widest output line.
_maxw() {
  python3 -c 'import sys,re
a=re.compile("\x1b\\[[0-9;?]*[A-Za-z]")
print(max((len(a.sub("",l)) for l in sys.stdin.read().splitlines()), default=0))'
}

# ── T1-06a · data path ───────────────────────────────────────────────────────

# F-04: ff-readout parsed `kern.boottime` with a greedy regex and matched
# `usec`, rendering "20708d". Uptime now comes from fastfetch's Uptime.uptime,
# which is MILLISECONDS: 10178514 ms = 2 h 49 m.
@test "dashboard --login: uptime comes from Uptime.uptime milliseconds" {
  run env NO_COLOR=1 COLUMNS=120 python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up 2h49m"* ]]
  [[ "$output" != *"20708d"* ]]
}

# F-09: the header read `henry@Mac16,7` because ff-readout set host from
# `hw.model`. Host is now os.uname().nodename; the model is its own segment.
@test "dashboard --login: header host is the nodename, not the hardware model" {
  nodename=$(python3 -c 'import os;print(os.uname().nodename)')
  run env NO_COLOR=1 COLUMNS=120 USER=tester python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tester@${nodename}"* ]]
  [[ "$output" != *"tester@Mac16,7"* ]]
}

# F-12: docker (115 ms) + tailscale (144 ms) + kubectl were probed live on every
# render. The data path is now one fastfetch call plus cached JSON reads; the
# stubs are ON PATH so `shutil.which` finds them — nothing must execute them.
@test "dashboard --login: no docker/tailscale/kubectl process spawned" {
  stub="$BATS_TEST_TMPDIR/stub"; mark="$BATS_TEST_TMPDIR/mark"
  mkdir -p "$stub" "$mark"
  for t in docker tailscale kubectl systemctl; do
    printf '#!/bin/sh\ntouch "%s/%s"\nexit 0\n' "$mark" "$t" > "$stub/$t"
    chmod +x "$stub/$t"
  done
  run env NO_COLOR=1 COLUMNS=120 PATH="$stub:/usr/bin:/bin" \
      python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  for t in docker tailscale kubectl systemctl; do
    [ ! -e "$mark/$t" ] || { echo "spawned: $t"; false; }
  done
}

# The frame must be width-exact (every line the same visible width) and never
# exceed the terminal, at each breakpoint: <80 single column, 80-99 body only,
# >=100 logo + body.
@test "dashboard --login: width-exact and clamped at 58/80/100/120/200" {
  for w in 58 80 100 120 200; do
    run env NO_COLOR=1 COLUMNS="$w" python3 "$DASH" --login --json-fixture "$FIX"
    [ "$status" -eq 0 ]
    widths=$(printf '%s\n' "$output" | python3 -c 'import sys,re
a=re.compile("\x1b\\[[0-9;?]*[A-Za-z]")
ws={len(a.sub("",l)) for l in sys.stdin.read().splitlines() if l.strip()}
print(" ".join(str(x) for x in sorted(ws)))')
    [ "$(printf '%s\n' "$widths" | wc -w | tr -d ' ')" -eq 1 ] || { echo "w=$w widths=$widths"; false; }
    [ "$widths" -le "$w" ] || { echo "w=$w overflow=$widths"; false; }
  done
}

# F-09: 10 of 16 grid cells were static laptop facts and four were duplicated
# (Host, Up, Load, Mem). The grid is gone; those live in `claw specs`.
@test "dashboard --login: static spec-sheet cells are gone, no duplicate Load" {
  run env NO_COLOR=1 COLUMNS=120 python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | command grep -c 'Load')" -eq 1 ]
  [[ "$output" != *"Locale"* ]]
  [[ "$output" != *"Kernel"* ]]
  [[ "$output" != *"n/a"* ]]
  [[ "$output" != *"dumb"* ]]
}

# segment_rows() is presence-driven: each row carries a show_if the caller
# honours, so a bare machine renders a short card instead of empty cells.
@test "dashboard segment_rows: presence-driven with show_if" {
  run env NO_COLOR=1 python3 - "$DASH" "$FIX" <<'PY'
import sys, importlib.util as u
spec = u.spec_from_file_location('d', sys.argv[1])
m = u.module_from_spec(spec); spec.loader.exec_module(m)
d = m.ff_json(sys.argv[2])
rows = m.segment_rows(d)
shown = {r[0]: r[3] for r in rows}
print("KEYS=" + ",".join(r[0] for r in rows))
print("MODEL_ON" if shown.get("model") else "MODEL_OFF")
print("NET_ON" if shown.get("net") else "NET_OFF")
print("BATT_ON" if shown.get("batt") else "BATT_OFF")
print("SWAP_ON" if shown.get("swap") else "SWAP_OFF")
d2 = dict(d, batt_pct=100, batt_status="Full")
print("FULL_BATT_OFF" if not dict((r[0], r[3]) for r in m.segment_rows(d2))["batt"] else "FULL_BATT_ON")
d3 = dict(d, swap_used=0)
print("NOSWAP_OFF" if not dict((r[0], r[3]) for r in m.segment_rows(d3))["swap"] else "NOSWAP_ON")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODEL_ON"* ]]
  [[ "$output" == *"NET_ON"* ]]
  [[ "$output" == *"BATT_ON"* ]]
  [[ "$output" == *"SWAP_ON"* ]]
  [[ "$output" == *"FULL_BATT_OFF"* ]]
  [[ "$output" == *"NOSWAP_OFF"* ]]
}

# Cloud identity keeps its per-provider glyph (AWS U+F270, GCP U+F1A0,
# Azure U+F17A) — now as segment rows, read from config files only.
@test "dashboard segment_rows: per-provider cloud icons (aws/gcp/azure)" {
  run env NO_COLOR=1 python3 - "$DASH" "$FIX" <<'PY'
import sys, importlib.util as u
spec = u.spec_from_file_location('d', sys.argv[1])
m = u.module_from_spec(spec); spec.loader.exec_module(m)
m._aws_profile = lambda: '111111111111'
m._gcp_project = lambda: 'my-gcp-proj'
m._az_subscription = lambda: 'my-azure-sub'
d = m.ff_json(sys.argv[2])
out = "\n".join(f"{g} {l} {v}" for g, l, v, on in m.segment_rows(d) if on)
print(out)
glyphs = tuple(chr(c) for c in (0xf270, 0xf1a0, 0xf17a))
print('GLYPHS_OK' if all(g in out for g in glyphs) else 'GLYPHS_MISSING')
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"111111111111"* ]]
  [[ "$output" == *"my-gcp-proj"* ]]
  [[ "$output" == *"my-azure-sub"* ]]
  [[ "$output" == *"GLYPHS_OK"* ]]
  [[ "$output" != *"aws:"* ]]
}

# The stdlib fallback keeps the card alive when fastfetch is missing (CI) or
# fails: partial data, exit 0, uptime still sane.
@test "dashboard: stdlib fallback when fastfetch is absent" {
  stub="$BATS_TEST_TMPDIR/empty"; mkdir -p "$stub"
  run env NO_COLOR=1 COLUMNS=100 PATH="$stub:/usr/bin:/bin" python3 "$DASH" --login
  [ "$status" -eq 0 ]
  [[ "$output" == *"OPEN CLAW"* ]]
  [[ "$output" != *"20708d"* ]]
}

# A new tab inherits the current window width (window-width applies to new
# windows only), so the dashboard box must clamp to the live terminal instead of
# overflowing/wrapping.
@test "dashboard: box clamps to a narrow terminal — no overflow" {
  run env COLUMNS=58 python3 "$DASH" --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  maxw=$(printf '%s\n' "$output" | _maxw)
  [ "$maxw" -le 58 ]
}

# Each homelab service renders with its OWN implementation icon (not a generic
# dot): docker U+F308, ollama U+F2DB, portainer U+F1B3, plus the github/server/
# route glyphs on the head + machine rows.
@test "dashboard homelab_lines: per-service implementation icons" {
  mkdir -p "$XDG_CACHE_HOME/claw"
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
  run env NO_COLOR=1 python3 - "$DASH" <<'PY'
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
# comes from the loaded palette: fg below 1.0, amber >=1.0, red >=2.0.
@test "dashboard bar_rows: Load text row present, CPU bar absent, palette thresholds" {
  run env -u NO_COLOR TERM=xterm-256color python3 - "$DASH" <<'PY'
import sys, importlib.util as u
spec = u.spec_from_file_location('d', sys.argv[1])
m = u.module_from_spec(spec); spec.loader.exec_module(m)
# NO_COLOR is no longer in the environment (it would pin DEPTH — and therefore
# every C[...] — to the empty string, which no tone assertion could tell apart);
# the module-level switch reproduces exactly the same monochrome rows.
m.NOCOLOR = True
base = dict(cores="14", mem_pct="72", swap_pct="3", disk_pct="82", batt_pct="90")
rows = m.bar_rows(dict(base, load="2.2 1.9 1.7", load_ratio="0.16", cpu_pct="16"))
print("\n".join(rows))
print("NO_CPU_BAR" if not any("CPU " in r for r in rows) else "CPU_BAR_PRESENT")
load = [r for r in rows if "Load" in r]
print("LOAD_TEXT" if len(load) == 1 and "[" not in load[0] and "2.2/14" in load[0] else "LOAD_BAD")
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
  run env NO_COLOR=1 COLUMNS=120 python3 "$DASH" --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Load"* ]]
  ! printf '%s\n' "$output" | command grep -qE 'CPU +\['
}

# ── T1-06b · attention card ──────────────────────────────────────────────────

# F-10: nothing at login read situation.json. The card now ends in an
# `attention` rule followed by the evaluated items: tier dot, text, hint, age,
# and `since HH:MM` when the item is older than the probe that last saw it.
@test "dashboard attention_lines: rows from the attention fixture" {
  mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/attention/attention.json" "$XDG_CACHE_HOME/claw/"
  cp "$BATS_TEST_DIRNAME/fixtures/attention/local.json" "$XDG_CACHE_HOME/claw/"
  run env NO_COLOR=1 TZ=UTC COLUMNS=120 python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"attention"* ]]
  [[ "$output" == *"k3s 2/3 Ready"* ]]
  [[ "$output" == *"since 03:12"* ]]
  [[ "$output" == *"kubectl get nodes"* ]]
  [[ "$output" == *"26 inbox"* ]]
  [[ "$output" == *"5 claude sessions"* ]]
  [[ "$output" == *"31/65 repos dirty"* ]]
  [[ "$output" == *"checked "* ]]
  # acked items are hidden from the card
  [[ "$output" != *"acked item must not render"* ]]
}

@test "dashboard attention_lines: all-clear and no-state lines" {
  mkdir -p "$XDG_CACHE_HOME/claw"
  run env NO_COLOR=1 TZ=UTC COLUMNS=120 python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no state yet"* ]]
  [[ "$output" == *"claw situation probe"* ]]

  cp "$BATS_TEST_DIRNAME/fixtures/attention/attention.empty.json" \
     "$XDG_CACHE_HOME/claw/attention.json"
  run env NO_COLOR=1 TZ=UTC COLUMNS=120 python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all clear"* ]]
  [[ "$output" == *"checked "* ]]
  [[ "$output" != *"no state yet"* ]]
}

# More items than the card shows collapse into one `+N more` pointer.
@test "dashboard attention_lines: caps at six items then points at claw doctor" {
  mkdir -p "$XDG_CACHE_HOME/claw"
  python3 - "$XDG_CACHE_HOME/claw/attention.json" <<'PY'
import sys, json, time
now = int(time.time())
json.dump({"v": 1, "checked": {"situation": now},
           "items": [{"id": f"i{n}", "tier": "warn", "text": f"item {n}",
                      "hint": "", "since": now, "src_ts": now} for n in range(9)]},
          open(sys.argv[1], "w"))
PY
  run env NO_COLOR=1 TZ=UTC COLUMNS=120 python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"item 5"* ]]
  [[ "$output" != *"item 6"* ]]
  [[ "$output" == *"+3 more"* ]]
  [[ "$output" == *"claw doctor"* ]]
}

# NO_COLOR must produce a card with no escape sequences at all, and tiers must
# still be distinguishable — `!` crit, `~` warn, `i` info.
@test "dashboard --login: NO_COLOR output carries no escape sequences" {
  mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/attention/attention.json" "$XDG_CACHE_HOME/claw/"
  cp "$BATS_TEST_DIRNAME/fixtures/attention/local.json" "$XDG_CACHE_HOME/claw/"
  run env NO_COLOR=1 TZ=UTC COLUMNS=120 python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | command grep -q $'\033' && { echo "escape codes leaked"; false; }
  printf '%s\n' "$output" | command grep -qE '! +k3s 2/3 Ready'
  printf '%s\n' "$output" | command grep -qE '~ +brew'
  printf '%s\n' "$output" | command grep -qE 'i +dotfiles'
}

# ── T1-06c · --profile ───────────────────────────────────────────────────────

# F-23: "one render path" held for 1 of 18 profiles. All 18 now render through
# this engine, width-exact at every breakpoint, with no placeholder leaks.
@test "dashboard --profile: all 18 profiles render at 80/100/120/200" {
  n=0
  for dir in "$BATS_TEST_DIRNAME"/../shell/profiles/*/; do
    key=$(basename "$dir"); n=$((n + 1))
    meta="$dir/meta.zsh"
    unset PROFILE_CLASS PROFILE_TAG PROFILE_GLYPH PROFILE_HELP_CMD \
          PROFILE_TOOLCHAIN PROFILE_KEY_TOOLS
    if [ -f "$meta" ]; then
      eval "$(command grep -E '^PROFILE_(CLASS|TAG|GLYPH|HELP_CMD|TOOLCHAIN|KEY_TOOLS)=' "$meta" | sed 's/[[:space:]]*#.*$//')"
      export PROFILE_CLASS PROFILE_TAG PROFILE_GLYPH PROFILE_HELP_CMD \
             PROFILE_TOOLCHAIN PROFILE_KEY_TOOLS
    fi
    for w in 80 100 120 200; do
      run env NO_COLOR=1 COLUMNS="$w" python3 "$DASH" --profile "$key" --json-fixture "$FIX"
      [ "$status" -eq 0 ] || { echo "$key @ $w rc=$status"; echo "$output"; false; }
      [[ "$output" != *"n/a"* ]] || { echo "$key @ $w leaked n/a"; false; }
      [[ "$output" != *"dumb"* ]] || { echo "$key @ $w leaked dumb"; false; }
      widths=$(printf '%s\n' "$output" | python3 -c 'import sys,re
a=re.compile("\x1b\\[[0-9;?]*[A-Za-z]")
ws={len(a.sub("",l)) for l in sys.stdin.read().splitlines() if l.strip()}
print(" ".join(str(x) for x in sorted(ws)))')
      [ "$(printf '%s\n' "$widths" | wc -w | tr -d ' ')" -eq 1 ] \
        || { echo "$key @ $w widths=$widths"; false; }
      [ "$widths" -le "$w" ] || { echo "$key @ $w overflow=$widths"; false; }
    done
  done
  [ "$n" -eq 18 ] || { echo "expected 18 profiles, saw $n"; false; }
}

# The title names the profile's class, and the card carries its tag, the key
# tool presence line and the help-card pointer — all out of the environment.
@test "dashboard --profile: title, class, tools and help pointer" {
  run env NO_COLOR=1 COLUMNS=120 \
      PROFILE_CLASS=NIGHTHACKER PROFILE_TAG="thinks your password is cute" \
      PROFILE_HELP_CMD=sec-help PROFILE_TOOLCHAIN=security-toolchain.sh \
      PROFILE_KEY_TOOLS="sh __claw_absent_tool__" \
      python3 "$DASH" --profile security --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OPEN CLAW · NIGHTHACKER"* ]]
  [[ "$output" == *"thinks your password is cute"* ]]
  [[ "$output" == *"✓ sh"* ]]
  [[ "$output" == *"✗ __claw_absent_tool__"* ]]
  [[ "$output" == *"claw install security"* ]]
  [[ "$output" == *"sec-help"* ]]
  # profile card shows Mem + Disk, never a Load or Swap row
  [[ "$output" == *"Mem"* ]]
  [[ "$output" == *"Disk"* ]]
  [[ "$output" != *"Load"* ]]
}

# Logo resolution is SGR-first: the config-dir art wins when it carries colour,
# even though shell/profiles/<key>/logo.txt also exists.
@test "dashboard --profile: SGR-first logo resolver picks the coloured file" {
  d="$BATS_TEST_TMPDIR/dots"
  mkdir -p "$d/config/.config/fastfetch" "$d/shell/profiles/security"
  printf '\033[38;2;1;2;3mSGRFILE\033[0m\n' > "$d/config/.config/fastfetch/logo-security.txt"
  printf 'MONOFILE\n' > "$d/shell/profiles/security/logo.txt"
  run env NO_COLOR=1 COLUMNS=120 DOTFILES_DIR="$d" \
      python3 "$DASH" --profile security --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SGRFILE"* ]]
  [[ "$output" != *"MONOFILE"* ]]

  # and the other way round: coloured art under shell/profiles wins when the
  # config-dir file is monochrome
  printf 'MONOFILE\n' > "$d/config/.config/fastfetch/logo-security.txt"
  printf '\033[38;2;4;5;6mPROFILESGR\033[0m\n' > "$d/shell/profiles/security/logo.txt"
  run env NO_COLOR=1 COLUMNS=120 DOTFILES_DIR="$d" \
      python3 "$DASH" --profile security --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROFILESGR"* ]]
}

# A profile whose only art is monochrome gets tinted with the palette's blue —
# never a hardcoded hex.
@test "dashboard --profile: monochrome-only logo is tinted with CLAW_C_BLUE" {
  d="$BATS_TEST_TMPDIR/dots"
  mkdir -p "$d/shell/profiles/cloud"
  printf 'MONOCLOUD\n' > "$d/shell/profiles/cloud/logo.txt"
  run env DOTFILES_DIR="$d" CLAW_C_BG=000000 CLAW_C_BLUE=0088ff \
      python3 - "$DASH" <<'PY'
import sys, importlib.util as u
spec = u.spec_from_file_location('d', sys.argv[1])
m = u.module_from_spec(spec); spec.loader.exec_module(m)
m.NOCOLOR = False
lines = m.profile_logo('cloud')
want = m.rgb(*m.PAL['blue'])
print("BLUE_FROM_ENV" if m.PAL['blue'] == (0, 136, 255) else "BLUE_BAD")
print("TINTED" if any(want in l for l in lines) else "NOT_TINTED")
print("HAS_ART" if any('MONOCLOUD' in l for l in lines) else "NO_ART")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLUE_FROM_ENV"* ]]
  [[ "$output" == *"TINTED"* ]]
  [[ "$output" == *"HAS_ART"* ]]
}

@test "dashboard --profile: NO_COLOR output carries no escape sequences" {
  mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/attention/attention.json" "$XDG_CACHE_HOME/claw/"
  run env NO_COLOR=1 TZ=UTC COLUMNS=120 PROFILE_CLASS=SKYSURFER \
      python3 "$DASH" --profile cloud --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | command grep -q $'\033' && { echo "escape codes leaked"; false; }
  [[ "$output" == *"attention"* ]]
  [[ "$output" == *"k3s 2/3 Ready"* ]]
}

# Apple's fastfetch Host.name is a marketing string ("MacBook Pro (16-inch,
# 2024, Three Thunderbolt 5 ports)") that ate the header's network field.
# Keep the model and the size, drop the parenthetical spec list.
@test "dashboard header: Apple's verbose model is trimmed to name + size" {
  run python3 - "$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py" <<'PY'
import sys, importlib.util as u
spec = u.spec_from_file_location('d', sys.argv[1])
m = u.module_from_spec(spec); spec.loader.exec_module(m)
print(m._trim_model("MacBook Pro (16-inch, 2024, Three Thunderbolt 5 ports)"))
print(m._trim_model("MacBook Air (13-inch, M2, 2022)"))
print(m._trim_model("Mac16,7"))
print(m._trim_model("BD790i (AMD Ryzen 9 7945HX)"))
print(m._trim_model(""))
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "MacBook Pro 16-inch" ]
  [ "${lines[1]}" = "MacBook Air 13-inch" ]
  [ "${lines[2]}" = "Mac16,7" ]          # no parenthetical: unchanged
  [ "${lines[3]}" = "BD790i" ]           # no size in the parenthetical: name only
  [ "${#lines[@]}" -eq 4 ]               # empty input prints an empty line
}

# ── T2-03 · colour depth and glyph fallback ─────────────────────────────────

# Every codepoint above U+007F in the output, as hex — empty when pure ASCII.
_nonascii() {
  python3 -c 'import sys
print(" ".join(sorted({hex(ord(c)) for c in sys.stdin.read() if ord(c) > 127})))'
}

@test "dashboard: CLAW_GLYPHS=ascii renders with no codepoint above U+007F" {
  for mode in "--login" "--profile security"; do
    run env NO_COLOR=1 COLUMNS=120 CLAW_GLYPHS=ascii PROFILE_CLASS=NIGHTHACKER \
        PROFILE_KEY_TOOLS="nmap sh" PROFILE_TOOLCHAIN=security-toolchain.sh \
        python3 "$DASH" $mode --json-fixture "$FIX"
    [ "$status" -eq 0 ]
    hi="$(printf '%s' "$output" | _nonascii)"
    [ -z "$hi" ] || { echo "$mode leaked: $hi"; false; }
    [[ "$output" == *"OPEN CLAW"* ]]
  done
}

@test "dashboard: CLAW_GLYPHS=ascii keeps the frame width-exact at 58/80/120" {
  for w in 58 80 120 200; do
    run env NO_COLOR=1 COLUMNS="$w" CLAW_GLYPHS=ascii python3 "$DASH" --login \
        --json-fixture "$FIX"
    [ "$status" -eq 0 ]
    widths="$(printf '%s\n' "$output" | python3 -c 'import sys
ls=[len(l) for l in sys.stdin.read().splitlines() if l.strip()]
print(len(set(ls)), max(ls))')"
    set -- $widths
    [ "$1" -eq 1 ] || { echo "ragged at $w"; false; }
    [ "$2" -le "$w" ] || { echo "overflow at $w: $2"; false; }
  done
}

@test "dashboard: TERM=linux auto-detects ascii (no PUA glyphs on the console)" {
  run env NO_COLOR=1 COLUMNS=100 TERM=linux python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  hi="$(printf '%s' "$output" | _nonascii)"
  [ -z "$hi" ] || { echo "leaked: $hi"; false; }
}

@test "dashboard: CLAW_COLOR_DEPTH downgrades every escape it emits" {
  # 24: truecolor, unchanged
  run env COLUMNS=120 CLAW_FORCE_COLOR=1 CLAW_COLOR_DEPTH=24 python3 "$DASH" \
      --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[38;2;'* ]]

  # 256: the cube only — no 38;2 anywhere, and still coloured
  run env COLUMNS=120 CLAW_FORCE_COLOR=1 CLAW_COLOR_DEPTH=256 python3 "$DASH" \
      --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" != *"38;2;"* ]]
  [[ "$output" != *"48;2;"* ]]
  [[ "$output" == *$'\e[38;5;'* ]]

  # 8: base ANSI only — no 38;2, no 38;5, and every SGR a plain 3x/0/1
  run env COLUMNS=120 CLAW_FORCE_COLOR=1 CLAW_COLOR_DEPTH=8 python3 "$DASH" \
      --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" != *"38;2;"* ]]
  [[ "$output" != *"38;5;"* ]]
  bad="$(printf '%s' "$output" | python3 -c 'import sys,re
codes = set(re.findall("\x1b\\[([0-9;]*)m", sys.stdin.read()))
print(" ".join(sorted(c for c in codes if c not in ("0","1","30","31","32","33","34","35","36","37"))))')"
  [ -z "$bad" ] || { echo "non-base SGR: $bad"; false; }

  # 0: plain text, no escapes at all
  run env COLUMNS=120 CLAW_FORCE_COLOR=1 CLAW_COLOR_DEPTH=0 python3 "$DASH" \
      --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\e['* ]]
}

@test "dashboard: a probed 256 still emits truecolor unless asked to be strict" {
  run env COLUMNS=120 CLAW_FORCE_COLOR=1 TERM=xterm-256color python3 "$DASH" \
      --login --json-fixture "$FIX"
  [[ "$output" == *$'\e[38;2;'* ]]
  run env COLUMNS=120 CLAW_FORCE_COLOR=1 TERM=xterm-256color \
      CLAW_COLOR_DEPTH_STRICT=1 python3 "$DASH" --login --json-fixture "$FIX"
  [[ "$output" != *"38;2;"* ]]
  [[ "$output" == *$'\e[38;5;'* ]]
}

@test "dashboard: imported logo art is quantised too, not pasted raw" {
  d="$BATS_TEST_TMPDIR/dots"; mkdir -p "$d/shell/profiles/fixt"
  printf '\033[38;2;255;0;0mRED\033[0m\n' > "$d/shell/profiles/fixt/logo.txt"
  run env COLUMNS=120 CLAW_FORCE_COLOR=1 CLAW_COLOR_DEPTH=256 DOTFILES_DIR="$d" \
      python3 "$DASH" --profile fixt --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RED"* ]]
  [[ "$output" != *"38;2;255;0;0"* ]]
  [[ "$output" == *"38;5;196"* ]]
}

# ── T2-02 · the shared card primitive ───────────────────────────────────────

@test "dashboard --card: frames stdin, width-exact and clamped at 58/80/120" {
  for w in 58 80 120; do
    run env NO_COLOR=1 COLUMNS="$w" bash -c \
      "printf 'tamper-check + install verification\n' | python3 '$DASH' --card 'OPEN CLAW Integrity Audit'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tamper-check + install verification"* ]]
    [[ "$output" == *"OPEN CLAW Integrity Audit"* ]]
    widths="$(printf '%s\n' "$output" | python3 -c 'import sys
ls=[len(l) for l in sys.stdin.read().splitlines() if l.strip()]
print(len(set(ls)), max(ls), len(ls))')"
    set -- $widths
    [ "$1" -eq 1 ] || { echo "ragged at $w"; false; }
    [ "$2" -le "$w" ] || { echo "overflow at $w: $2"; false; }
    [ "$3" -eq 3 ] || { echo "want 3 lines at $w, got $3"; false; }
  done
}

@test "dashboard --card: empty stdin still frames, and the title is clipped" {
  run env NO_COLOR=1 COLUMNS=60 bash -c "printf '' | python3 '$DASH' --card 'T'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"T"* ]]
  run env NO_COLOR=1 COLUMNS=40 bash -c \
    "printf 'x\n' | python3 '$DASH' --card '$(printf 'L%.0s' $(seq 1 90))'"
  [ "$status" -eq 0 ]
  w="$(printf '%s\n' "$output" | python3 -c 'import sys
print(max(len(l) for l in sys.stdin.read().splitlines() if l.strip()))')"
  [ "$w" -le 40 ]
}

@test "dashboard --card: honours the palette and the requested tones" {
  blue="$(python3 -c '
import sys
hx=open(sys.argv[1]).read()
import re
m=dict(l.split("=",1) for l in hx.splitlines() if "=" in l and not l.startswith("#"))
v=m["blue"].strip()
print("%d;%d;%d" % (int(v[0:2],16), int(v[2:4],16), int(v[4:6],16)))' \
    "$DOTFILES_DIR/config/themes/matrix/palette.theme")"
  run env COLUMNS=80 CLAW_FORCE_COLOR=1 CLAW_THEME=matrix CLAW_COLOR_DEPTH=24 bash -c \
    "printf 'sub\n' | python3 '$DASH' --card 'Title' --border purple --title-tone blue"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[38;2;'"${blue}m"* ]]
}

@test "dashboard --card: NO_COLOR strips the caller's own escapes too" {
  run env NO_COLOR=1 COLUMNS=80 bash -c \
    "printf '\033[38;2;255;0;0mred line\033[0m\n' | python3 '$DASH' --card 'T'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"red line"* ]]
  [[ "$output" != *$'\e['* ]]
}

@test "dashboard --login: third breakpoint puts attention beside the grid at >=140" {
  run env NO_COLOR=1 COLUMNS=120 python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"attention"* ]]
  n120="$(printf '%s\n' "$output" | grep -c . || true)"
  run env NO_COLOR=1 COLUMNS=150 python3 "$DASH" --login --json-fixture "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"attention"* ]]
  n150="$(printf '%s\n' "$output" | grep -c . || true)"
  # the same payload, fewer lines: the attention block folded into the grid
  [ "$n150" -lt "$n120" ] || { echo "no fold: 120=$n120 150=$n150"; false; }
  widths="$(printf '%s\n' "$output" | python3 -c 'import sys
ls=[len(l) for l in sys.stdin.read().splitlines() if l.strip()]
print(len(set(ls)), max(ls))')"
  set -- $widths
  [ "$1" -eq 1 ]
  [ "$2" -le 150 ]
}
