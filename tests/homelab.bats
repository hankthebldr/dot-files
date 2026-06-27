#!/usr/bin/env bats
# HR-TRUST homelab fleet status — poller + cache schema + readers. Run: bats tests/
setup() {
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR"; mkdir -p "$HOME"
}

@test "fleet.yml: parses and lists bd790i with its services" {
  run yq -r '.machines[] | select(.id=="bd790i") | .services[]' \
    "$BATS_TEST_DIRNAME/../config/homelab/fleet.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3s"* ]]
  [[ "$output" == *"tailscale"* ]]
}

@test "fleet.yml.example: is valid yaml" {
  run yq -e '.' "$BATS_TEST_DIRNAME/../config/homelab/fleet.yml.example"
  [ "$status" -eq 0 ]
}

@test "situation homelab: writes a schema-valid homelab.json" {
  command -v yq >/dev/null || skip "yq required to parse fleet.yml"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  run bash "$BATS_TEST_DIRNAME/../scripts/utils/situation.sh" homelab
  [ "$status" -eq 0 ]
  run jq -e '.ts and .fleet and (.machines|type=="array") and (.machines[0].id=="bd790i")' \
    "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$status" -eq 0 ]
  # service id is passed through verbatim from fleet.yml, which names it "k3s"
  run jq -e '.machines[0].services | map(.id) | index("k3s")' \
    "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$status" -eq 0 ]
}

@test "situation homelab: every service has a state in {up,down,degraded}" {
  command -v yq >/dev/null || skip "yq required to parse fleet.yml"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  bash "$BATS_TEST_DIRNAME/../scripts/utils/situation.sh" homelab
  run jq -e '[.machines[].services[].state] | all(. as $s | ["up","down","degraded"]|index($s))' \
    "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$status" -eq 0 ]
}

@test "dashboard homelab_lines: renders host + service dots from cache" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/homelab.up.json" "$XDG_CACHE_HOME/claw/homelab.json"
  run env NO_COLOR=1 python3 -c "import sys; sys.argv=['d']; \
    import importlib.util as u; s=u.spec_from_file_location('d','$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py'); \
    m=u.module_from_spec(s); s.loader.exec_module(m); print('\n'.join(m.homelab_lines()))"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bd790i"* ]]
  [[ "$output" == *"k3s"* ]]
}

@test "dashboard homelab_lines: empty list when cache absent" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/none"
  run env NO_COLOR=1 python3 -c "import sys; sys.argv=['d']; \
    import importlib.util as u; \
    s=u.spec_from_file_location('d','$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py'); \
    m=u.module_from_spec(s); s.loader.exec_module(m); print('LINES=%d'%len(m.homelab_lines()))"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LINES=0"* ]]
}

@test "dashboard homelab_lines: stale cache emits 'stale' not 'updated'" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/homelab.stale.json" "$XDG_CACHE_HOME/claw/homelab.json"
  run env NO_COLOR=1 python3 -c "import sys; sys.argv=['d']; \
    import importlib.util as u; s=u.spec_from_file_location('d','$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py'); \
    m=u.module_from_spec(s); s.loader.exec_module(m); print('\n'.join(m.homelab_lines()))"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale"* ]]
  [[ "$output" != *"updated"* ]]
}

@test "dashboard homelab_lines: down service renders ollama from mixed cache" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/homelab.mixed.json" "$XDG_CACHE_HOME/claw/homelab.json"
  run env NO_COLOR=1 python3 -c "import sys; sys.argv=['d']; \
    import importlib.util as u; s=u.spec_from_file_location('d','$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py'); \
    m=u.module_from_spec(s); s.loader.exec_module(m); print('\n'.join(m.homelab_lines()))"
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3s"* ]]
  [[ "$output" == *"ollama"* ]]
}
