#!/usr/bin/env bats
# Guards spine-invariant #1 and the twice-defined-function regressions.

SHELL_DIR="$BATS_TEST_DIRNAME/../shell"

# count function-definition sites (name followed by '()') across shell/
defcount() { grep -rEc "^\s*$1\s*\(\)" "$SHELL_DIR" | awk -F: '{s+=$2} END {print s}'; }

@test "exactly one claw() definition (spine invariant #1)" {
  # claw() lives ONLY in claw-fn.zsh
  [ "$(defcount claw)" -eq 1 ]
}

@test "exactly one extract() definition" {
  [ "$(defcount extract)" -eq 1 ]
}

@test "exactly one fkill() definition" {
  [ "$(defcount fkill)" -eq 1 ]
}

# audit 2026-09-20 F-22: aliases.zsh regenerated kubectl/docker/helm/gh
# completions synchronously on EVERY shell (211 ms) although the oh-my-zsh
# plugins already generate + cache them. Completion generation belongs to omz.
@test "aliases.zsh does not regenerate tool completions synchronously (omz plugins own it)" {
  ! grep -qE 'source <\([a-z]+ completion' "$SHELL_DIR/aliases.zsh"
}
