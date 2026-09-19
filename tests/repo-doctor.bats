#!/usr/bin/env bats
# Tests for `claw doctor repo` — the deployed-checkout guard (bin/claw
# doctor_repo). Contract: docs/BRANCHING.md. The deployed tree (~/.dotfiles)
# must sit on the one long-lived branch with an upstream, clean and not ahead,
# or `claw update` phase 1 (repo-sync.sh) silently skips the pull.
# Fixture: a throwaway origin + a clone standing in for ~/.dotfiles.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$HOME/.cache"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$HOME"
  export GIT_CONFIG_SYSTEM=/dev/null
  git config --global user.email claw@test
  git config --global user.name "Claw Test"
  git config --global init.defaultBranch master
  export CLAW_NO_LOG=1

  ORIGIN="$BATS_TEST_TMPDIR/origin"
  DF="$BATS_TEST_TMPDIR/dotfiles"
  git init -q -b master "$ORIGIN"
  mkdir -p "$ORIGIN/config/integrity"
  echo base > "$ORIGIN/README.md"
  echo seed > "$ORIGIN/config/integrity/manifest.sha256"
  git -C "$ORIGIN" add -A
  git -C "$ORIGIN" commit -qm init
  git clone -q "$ORIGIN" "$DF"
  CLAW="$BATS_TEST_DIRNAME/../bin/claw"
}

run_doc() { run env DOTFILES_DIR="$DF" bash "$CLAW" doctor repo; }

@test "doctor repo: healthy deployed tree — on master, upstream set, in sync, clean → exit 0" {
  run_doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch"*"master"* ]]
  [[ "$output" == *"in sync"*"origin/master"* ]]
  [[ "$output" == *"clean tree"* ]]
  [[ "$output" != *"✗"* ]]
}

@test "doctor repo: deployed tree checked out on a feature branch → ✗ names master and the worktree fix, exit 1" {
  git -C "$DF" checkout -q -b fix/something
  run_doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗"*"on branch"*"fix/something"* ]]
  [[ "$output" == *"master"* ]]
  [[ "$output" == *"claw wt new"* ]]
}

@test "doctor repo: detached HEAD → ✗, exit 1" {
  git -C "$DF" checkout -q --detach
  run_doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗"*"detached"* ]]
}

@test "doctor repo: no upstream → ✗ with the set-upstream-to fix, exit 1" {
  git -C "$DF" branch --unset-upstream
  run_doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗"*"no upstream"* ]]
  [[ "$output" == *"--set-upstream-to origin/master"* ]]
}

@test "doctor repo: unpushed local commit on the deployed tree → ✗ ahead, exit 1" {
  echo local > "$DF/local.txt"
  git -C "$DF" add local.txt && git -C "$DF" commit -qm "local edit"
  run_doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗"*"ahead 1"* ]]
}

@test "doctor repo: behind origin is informational, not a failure → exit 0" {
  echo more > "$ORIGIN/more.txt"
  git -C "$ORIGIN" add more.txt && git -C "$ORIGIN" commit -qm "upstream moved"
  git -C "$DF" fetch -q origin
  run_doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"behind"*"1"* ]]
  [[ "$output" == *"claw update"* ]]
  [[ "$output" != *"✗"* ]]
}

@test "doctor repo: diverged (ahead AND behind) → ✗ diverged, exit 1" {
  echo more > "$ORIGIN/more.txt"
  git -C "$ORIGIN" add more.txt && git -C "$ORIGIN" commit -qm "upstream moved"
  git -C "$DF" fetch -q origin
  echo local > "$DF/local.txt"
  git -C "$DF" add local.txt && git -C "$DF" commit -qm "local edit"
  run_doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗"*"diverged"* ]]
}

@test "doctor repo: modified tracked file → ✗ dirty, exit 1" {
  echo edit >> "$DF/README.md"
  run_doc
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗"*"dirty tree"* ]]
}

@test "doctor repo: integrity-manifest drift alone is NOT dirty (same exclusion as repo-sync) → exit 0" {
  echo regen > "$DF/config/integrity/manifest.sha256"
  run_doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean tree"* ]]
}

@test "doctor repo: untracked files never count as dirty → exit 0" {
  echo secret > "$DF/.env"
  run_doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean tree"* ]]
}

@test "doctor repo: not a git checkout (tarball install) → informational, exit 0" {
  rm -rf "$DF/.git"
  run_doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a git checkout"* ]]
  [[ "$output" != *"✗"* ]]
}

@test "doctor repo: CLAW_REPO_BRANCH overrides the expected branch" {
  git -C "$DF" checkout -q -b dev
  git -C "$DF" push -q -u origin dev
  run env DOTFILES_DIR="$DF" CLAW_REPO_BRANCH=dev bash "$CLAW" doctor repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch"*"dev"* ]]
  [[ "$output" != *"✗"* ]]
}

@test "doctor repo: extra worktrees are reported, not failed" {
  git -C "$DF" worktree add -q -b feat/wt "$BATS_TEST_TMPDIR/wt" master
  run_doc
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 worktree"* ]]
  [[ "$output" == *"claw wt ls"* ]]
}

@test "doctor (full) embeds the Repo section and never fails on it" {
  git -C "$DF" checkout -q -b fix/something
  run env DOTFILES_DIR="$DF" bash "$CLAW" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Repo"* ]]
  [[ "$output" == *"on branch"*"fix/something"* ]]
}
