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
