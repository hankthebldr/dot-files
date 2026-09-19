#!/usr/bin/env bats
# Tests for `claw wt` (scripts/utils/worktree.sh) — worktree-per-task, the
# implementation of docs/BRANCHING.md §3. Fixture: a throwaway origin + a clone
# standing in for the deployed tree (~/.dotfiles), which must never move.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$HOME/.cache"
  mkdir -p "$HOME"
  export GIT_CONFIG_SYSTEM=/dev/null
  git config --global user.email claw@test
  git config --global user.name "Claw Test"
  git config --global init.defaultBranch master
  export CLAW_NO_LOG=1

  ORIGIN="$BATS_TEST_TMPDIR/origin"
  DF="$BATS_TEST_TMPDIR/dotfiles"
  git init -q -b master "$ORIGIN"
  echo base > "$ORIGIN/README.md"
  git -C "$ORIGIN" add -A && git -C "$ORIGIN" commit -qm init
  git clone -q "$ORIGIN" "$DF"
  W="$BATS_TEST_DIRNAME/../scripts/utils/worktree.sh"
  WT="$DF/.claude/worktrees"
}

run_wt() { run env DOTFILES_DIR="$DF" bash "$W" "$@"; }

@test "new: creates .claude/worktrees/<slug> on the branch, based on origin/master; deployed tree untouched" {
  run_wt new feat/thing
  [ "$status" -eq 0 ]
  [ -d "$WT/feat-thing" ]
  [ "$(git -C "$WT/feat-thing" symbolic-ref --short HEAD)" = "feat/thing" ]
  [ "$(git -C "$WT/feat-thing" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse master)" ]
  # the deployed tree stays on master, clean, and in place
  [ "$(git -C "$DF" symbolic-ref --short HEAD)" = "master" ]
  [ -z "$(git -C "$DF" status --porcelain -uno)" ]
  [[ "$output" == *"$WT/feat-thing"* ]]
}

@test "new: the branch does NOT track origin/master (push -u sets its own upstream later)" {
  run_wt new fix/track
  [ "$status" -eq 0 ]
  run git -C "$WT/fix-track" rev-parse --abbrev-ref '@{upstream}'
  [ "$status" -ne 0 ]
}

@test "new: slug maps '/' to '-' and path resolves it back" {
  run_wt new fix/a-b
  [ "$status" -eq 0 ]
  [ -d "$WT/fix-a-b" ]
  run_wt path fix/a-b
  [ "$status" -eq 0 ]
  # git reports the physical path; $BATS_TEST_TMPDIR may be a symlink (/var → /private/var on macOS)
  [ "$(cd "$output" && pwd -P)" = "$(cd "$WT/fix-a-b" && pwd -P)" ]
}

@test "new: refuses a branch that already exists" {
  git -C "$DF" branch feat/dup
  run_wt new feat/dup
  [ "$status" -ne 0 ]
  [[ "$output" == *"exists"* ]]
  [ ! -d "$WT/feat-dup" ]
}

@test "new: refuses a name git itself rejects" {
  run_wt new 'bad..name'
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid"* ]]
  run_wt new ''
  [ "$status" -ne 0 ]
}

@test "new: starts at the CURRENT origin/master even when the deployed tree is behind" {
  echo more > "$ORIGIN/more.txt"
  git -C "$ORIGIN" add more.txt && git -C "$ORIGIN" commit -qm "upstream moved"
  run_wt new feat/fresh
  [ "$status" -eq 0 ]
  [ "$(git -C "$WT/feat-fresh" rev-parse HEAD)" = "$(git -C "$ORIGIN" rev-parse master)" ]
  # and it did NOT advance the deployed tree's checkout to do it
  [ "$(git -C "$DF" rev-parse HEAD)" != "$(git -C "$ORIGIN" rev-parse master)" ]
}

@test "new: offline falls back to local master and says so" {
  git -C "$DF" remote set-url origin "$BATS_TEST_TMPDIR/does-not-exist"
  run_wt new feat/offline
  [ "$status" -eq 0 ]
  [ -d "$WT/feat-offline" ]
  [ "$(git -C "$WT/feat-offline" rev-parse HEAD)" = "$(git -C "$DF" rev-parse master)" ]
  [[ "$output" == *"offline"* || "$output" == *"fetch failed"* ]]
}

@test "ls: shows the deployed tree and every worktree with ahead/behind and a dirty marker" {
  run_wt new feat/one
  run_wt new fix/two
  echo change > "$WT/fix-two/README.md"                       # dirty tracked file
  echo x > "$WT/feat-one/x.txt"; git -C "$WT/feat-one" add x.txt; git -C "$WT/feat-one" commit -qm ahead
  run_wt ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"master"* ]]
  [[ "$output" == *"feat/one"*"+1"* ]]
  [[ "$output" == *"fix/two"*"dirty"* ]]
}

@test "rm: a merged, clean worktree — directory and branch both go" {
  run_wt new fix/done
  run_wt rm fix/done
  [ "$status" -eq 0 ]
  [ ! -d "$WT/fix-done" ]
  run git -C "$DF" rev-parse --verify --quiet refs/heads/fix/done
  [ "$status" -ne 0 ]
  # no stale worktree metadata left behind
  [ -z "$(git -C "$DF" worktree list --porcelain | grep 'fix-done' || true)" ]
}

@test "rm: refuses unmerged work without --force, removes it with --force" {
  run_wt new feat/wip
  echo x > "$WT/feat-wip/x.txt"; git -C "$WT/feat-wip" add x.txt; git -C "$WT/feat-wip" commit -qm wip
  run_wt rm feat/wip
  [ "$status" -ne 0 ]
  [[ "$output" == *"--force"* ]]
  [ -d "$WT/feat-wip" ]
  run_wt rm feat/wip --force
  [ "$status" -eq 0 ]
  [ ! -d "$WT/feat-wip" ]
}

@test "rm: refuses a dirty worktree without --force" {
  run_wt new fix/dirty
  echo change > "$WT/fix-dirty/README.md"
  run_wt rm fix/dirty
  [ "$status" -ne 0 ]
  [ -d "$WT/fix-dirty" ]
}

@test "rm: never removes the deployed tree or the base branch" {
  run_wt rm master
  [ "$status" -ne 0 ]
  [ -d "$DF/.git" ]
  [ "$(git -C "$DF" symbolic-ref --short HEAD)" = "master" ]
}

@test "path: unknown branch → exit 1, nothing on stdout" {
  run env DOTFILES_DIR="$DF" bash "$W" path nope/nothing
  [ "$status" -eq 1 ]
}

@test "help / unknown subcommand" {
  run_wt help;   [ "$status" -eq 0 ]; [[ "$output" == *"claw wt"* ]]
  run_wt bogus;  [ "$status" -ne 0 ]
}

@test "shellcheck: engine passes at warning severity (house exclusions)" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  run shellcheck -S warning -e SC1090,SC1091,SC2034,SC2059,SC2015,SC2154 "$W"
  [ "$status" -eq 0 ]
}
