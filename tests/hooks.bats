#!/usr/bin/env bats
# Regression tests for claude/hooks/pre_tool_use.py

HOOK="$BATS_TEST_DIRNAME/../claude/hooks/pre_tool_use.py"

# helper: run the hook with a JSON payload on stdin, capture exit code
run_hook() { run bash -c "printf '%s' '$1' | python3 '$HOOK'"; }

@test "edit to generated fastfetch config is denied" {
  run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/x/config/.config/fastfetch/config-ai.jsonc"}}'
  [ "$status" -eq 2 ]
}

@test "sed -i on a generated config via Bash is denied" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ config/.config/fastfetch/config-cortex.jsonc"}}'
  [ "$status" -eq 2 ]
}

@test "edit to a hand-maintained fastfetch config is allowed" {
  run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/x/config/.config/fastfetch/config-pmo.jsonc"}}'
  [ "$status" -eq 0 ]
}
