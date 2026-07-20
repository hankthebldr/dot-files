#!/usr/bin/env bats
# ai-config.sh — render/sentinel/gate regression tests

setup() {
  ENGINE="$BATS_TEST_DIRNAME/../scripts/utils/ai-config.sh"
  TMP="$(mktemp -d)"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export OBSIDIAN_VAULT="$TMP/fake-vault"
}
teardown() { rm -rf "$TMP"; }

@test "render opencode writes sentinel on line 1 and valid JSON" {
  run bash "$ENGINE" render opencode "$TMP/oc.jsonc"
  [ "$status" -eq 0 ]
  head -1 "$TMP/oc.jsonc" | grep -q "managed by the Open Claw ai-config plugin"
  # strip // comments, then it must parse as JSON
  sed 's:^[[:space:]]*//.*$::' "$TMP/oc.jsonc" | python3 -c "import json,sys; json.load(sys.stdin)"
}
