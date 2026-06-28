#!/usr/bin/env bats
# shell/progress.zsh terminal-title behavior: the live (flickering) title is
# opt-in via CLAW_PROGRESS_TITLE; the default is a static [profile] cwd title.
# Run: bats tests/

setup() {
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  mkdir -p "$HOME" "$XDG_CACHE_HOME"
  PROG="$BATS_TEST_DIRNAME/../shell/progress.zsh"
}

# Default (CLAW_PROGRESS_TITLE unset → 0): preexec must NOT fork the background
# title updater, so the tab title never flickers with the running command.
@test "progress title: static by default — preexec does not fork the updater" {
  run zsh -c '
    unset CLAW_PROGRESS_TITLE
    source "'"$PROG"'"
    __claw_progress_preexec "sleep 30"
    print "PID=[${__claw_progress_pid}]"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"PID=[]"* ]]
}

# Opt-in (CLAW_PROGRESS_TITLE=1): preexec forks the updater (live title).
@test "progress title: live mode (opt-in) forks the updater" {
  run zsh -c '
    export CLAW_PROGRESS_TITLE=1 CLAW_PROGRESS_THRESHOLD=9
    source "'"$PROG"'"
    __claw_progress_preexec "sleep 30"
    [[ -n "$__claw_progress_pid" ]] && print "FORKED"
    kill "$__claw_progress_pid" 2>/dev/null
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"FORKED"* ]]
}

# `progress status` reports the title mode.
@test "progress status: reports title=static by default" {
  run zsh -c '
    unset CLAW_PROGRESS_TITLE
    source "'"$PROG"'"
    progress status
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"title="* ]]
  [[ "$output" == *"static"* ]]
}

# `progress title on` flips to live; `progress title off` back to static.
@test "progress title on/off: toggles CLAW_PROGRESS_TITLE" {
  run zsh -c '
    unset CLAW_PROGRESS_TITLE
    source "'"$PROG"'"
    progress title on  >/dev/null; print "AFTER_ON=${CLAW_PROGRESS_TITLE}"
    progress title off >/dev/null; print "AFTER_OFF=${CLAW_PROGRESS_TITLE}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"AFTER_ON=1"* ]]
  [[ "$output" == *"AFTER_OFF=0"* ]]
}
