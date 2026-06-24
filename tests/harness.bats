#!/usr/bin/env bats
# Tests for the `claw harness` engine (scripts/utils/harness.sh).

setup() {
  export DF="$BATS_TEST_TMPDIR/df"
  mkdir -p "$DF/scripts/utils" "$DF/scripts/setup" \
           "$DF/claude/harness/"{skills,commands,agents,plugins,_templates}
  cp "$BATS_TEST_DIRNAME/../scripts/utils/harness.sh" "$DF/scripts/utils/"
  cp "$BATS_TEST_DIRNAME/../scripts/utils/logger.sh"  "$DF/scripts/utils/"
  cp -R "$BATS_TEST_DIRNAME/../claude/harness/_templates/." "$DF/claude/harness/_templates/"
  printf '#!/usr/bin/env bash\necho "LINK_CLAUDE_RAN $*"\n' > "$DF/scripts/setup/link-claude.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/"{skills,commands,agents,plugins}
  export H="$DF/scripts/utils/harness.sh"
}

run_h() { run env DOTFILES_DIR="$DF" bash "$H" "$@"; }

@test "new skill: bare name defaults to skill and substitutes __NAME__" {
  run_h new foo
  [ "$status" -eq 0 ]
  [ -f "$DF/claude/harness/skills/foo/SKILL.md" ]
  grep -q "^name: foo$" "$DF/claude/harness/skills/foo/SKILL.md"
}

@test "new command/agent/plugin each scaffold the right file" {
  run_h new command bar; [ "$status" -eq 0 ]; [ -f "$DF/claude/harness/commands/bar.md" ]
  run_h new agent baz;   [ "$status" -eq 0 ]; [ -f "$DF/claude/harness/agents/baz.md" ]
  grep -q "^name: baz$" "$DF/claude/harness/agents/baz.md"
  run_h new plugin qux;  [ "$status" -eq 0 ]; [ -f "$DF/claude/harness/plugins/qux/plugin.json" ]
  grep -q '"name": "qux"' "$DF/claude/harness/plugins/qux/plugin.json"
}

@test "new: refuses to clobber an existing tool" {
  run_h new foo; [ "$status" -eq 0 ]
  run_h new foo; [ "$status" -ne 0 ]; [[ "$output" == *"already exists"* ]]
}

@test "new: rejects an invalid name" {
  run_h new "bad name/with slash"
  [ "$status" -ne 0 ]; [[ "$output" == *"invalid name"* ]]
}

@test "path: prints the harness root" {
  run_h path
  [ "$status" -eq 0 ]; [[ "$output" == *"/claude/harness"* ]]
}

@test "deploy: delegates to link-claude.sh" {
  run_h deploy --dry-run
  [ "$status" -eq 0 ]; [[ "$output" == *"LINK_CLAUDE_RAN --dry-run"* ]]
}

@test "list: shows a scaffolded skill with a not-deployed marker" {
  run_h new foo
  run_h list
  [ "$status" -eq 0 ]; [[ "$output" == *"foo"* ]]; [[ "$output" == *"○"* ]]
}

@test "claw harness: routes new/list/path through the engine" {
  cp "$BATS_TEST_DIRNAME/../bin/claw" "$DF/bin-claw" 2>/dev/null || true
  run env DOTFILES_DIR="$DF" bash "$BATS_TEST_DIRNAME/../bin/claw" harness new skill plumbed
  [ "$status" -eq 0 ]
  [ -f "$DF/claude/harness/skills/plumbed/SKILL.md" ]
  run env DOTFILES_DIR="$DF" bash "$BATS_TEST_DIRNAME/../bin/claw" harness path
  [[ "$output" == *"/claude/harness"* ]]
}

@test "list: shows the skill's description, not just its name" {
  run_h new foo
  run_h list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Use when"* ]]   # from the template description
}

@test "list --all: also walks claude/skills and claude/agent-skills" {
  mkdir -p "$DF/claude/skills/sec-skill" "$DF/claude/agent-skills/vend-skill"
  printf -- '---\nname: sec-skill\ndescription: Use when security.\n---\n' > "$DF/claude/skills/sec-skill/SKILL.md"
  printf -- '---\nname: vend-skill\ndescription: Use when vendored.\n---\n' > "$DF/claude/agent-skills/vend-skill/SKILL.md"
  run_h list --all
  [[ "$output" == *"sec-skill"* ]]
  [[ "$output" == *"vend-skill"* ]]
  [[ "$output" == *"Use when security."* ]]
  [[ "$output" == *"Use when vendored."* ]]
}

@test "sync: errors clearly when DOTFILES_DIR is not a git repo" {
  run_h sync
  [ "$status" -ne 0 ]; [[ "$output" == *"not a git repo"* ]]
}

@test "sync --dry-run: in a git repo with no upstream, mutates nothing" {
  ( cd "$DF" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
  before="$(git -C "$DF" rev-parse HEAD)"
  run_h sync --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"LINK_CLAUDE_RAN --dry-run"* ]]
  after="$(git -C "$DF" rev-parse HEAD)"
  [ "$before" = "$after" ]            # no new commit
}
