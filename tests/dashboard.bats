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
