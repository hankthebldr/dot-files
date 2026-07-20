#!/usr/bin/env bats
# ai-config.sh — render/sentinel/gate regression tests

setup() {
  ENGINE="$BATS_TEST_DIRNAME/../scripts/utils/ai-config.sh"
  TMP="$(mktemp -d)"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export OBSIDIAN_VAULT="$TMP/fake-vault"
  export OW_DIR_TEST="$TMP/cfg/openwork"
}
teardown() { rm -rf "$TMP"; }

@test "render opencode writes sentinel on line 1 and valid JSON" {
  run bash "$ENGINE" render opencode "$TMP/oc.jsonc"
  [ "$status" -eq 0 ]
  head -1 "$TMP/oc.jsonc" | grep -q "managed by the Open Claw ai-config plugin"
  # strip // comments, then it must parse as JSON
  sed 's:^[[:space:]]*//.*$::' "$TMP/oc.jsonc" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "render openwork writes _claw_managed and vault in authorizedRoots" {
  run bash "$ENGINE" render openwork "$TMP/ow.json"
  [ "$status" -eq 0 ]
  python3 -c "import json; d=json.load(open('$TMP/ow.json')); assert d['_claw_managed'] is True; assert '$TMP/fake-vault' in d['authorizedRoots']"
}

@test "sync refuses to clobber an unmanaged openwork config" {
  mkdir -p "$OW_DIR_TEST"
  printf '{"workspaces":[{"path":"/hand/edited"}]}' > "$OW_DIR_TEST/server.json"
  run env CLAW_AICONFIG_MANAGED=1 XDG_CONFIG_HOME="$TMP/cfg" bash "$ENGINE" sync
  # direct gate check: an unmanaged file must not gain the sentinel key
  ! grep -q '_claw_managed' "$OW_DIR_TEST/server.json"
}

@test "setup seeds openwork roots from an existing extra workspace (lossless)" {
  mkdir -p "$OW_DIR_TEST"
  # existing file with our key + an extra workspace the render wouldn't produce
  printf '{"_claw_managed":true,"workspaces":[{"id":"x","path":"/extra/ws","name":"extra"}],"authorizedRoots":["/extra/ws"]}' > "$OW_DIR_TEST/server.json"
  run env XDG_CONFIG_HOME="$TMP/cfg" OBSIDIAN_VAULT="$TMP/fake-vault" bash "$ENGINE" setup
  python3 -c "import json; d=json.load(open('$OW_DIR_TEST/server.json')); paths=[w['path'] for w in d['workspaces']]; assert '/extra/ws' in paths, paths"
}
