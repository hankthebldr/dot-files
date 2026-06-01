#!/usr/bin/env zsh
# tests/session-identity.test.zsh — unit tests for the session-identity layer
# in shell/progress.zsh. Run standalone: `zsh tests/session-identity.test.zsh`

typeset -gi _pass=0 _fail=0
# Capture the script dir at TOP scope: inside a function zsh's FUNCTION_ARGZERO
# makes $0 the function name, so ${0:A:h} would resolve against the cwd instead.
typeset -g _THIS="${0:A:h}"

assert_eq() {        # assert_eq <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    print -r -- "  ✓ $1"; (( _pass++ ))
  else
    print -r -- "  ✗ $1"
    print -r -- "      expected: [$2]"
    print -r -- "      actual:   [$3]"
    (( _fail++ ))
  fi
}

assert_contains() {  # assert_contains <desc> <haystack> <needle>
  if [[ "$2" == *"$3"* ]]; then
    print -r -- "  ✓ $1"; (( _pass++ ))
  else
    print -r -- "  ✗ $1"
    print -r -- "      [$2] does not contain [$3]"
    (( _fail++ ))
  fi
}

test_resolver() {
  local REPLY
  CLAW_SESSION="xsiam-poc"; CLAW_ACTIVE_PROFILE="cortex"; CLAW_ACTIVE_GROUP="domain"; CLAW_SESSION_SEQ=3
  __claw_session_resolve; assert_eq "tier1 pin wins" "xsiam-poc" "$REPLY"

  CLAW_SESSION="";          CLAW_ACTIVE_PROFILE="cortex"; CLAW_ACTIVE_GROUP="domain"; CLAW_SESSION_SEQ=3
  __claw_session_resolve; assert_eq "tier2 group/subprofile" "domain/cortex" "$REPLY"

  CLAW_SESSION="";          CLAW_ACTIVE_PROFILE="claude"; CLAW_ACTIVE_GROUP="";       CLAW_SESSION_SEQ=3
  __claw_session_resolve; assert_eq "tier2 bare profile (no group)" "claude" "$REPLY"

  CLAW_SESSION="";          CLAW_ACTIVE_PROFILE="";       CLAW_ACTIVE_GROUP="";       CLAW_SESSION_SEQ=5
  __claw_session_resolve; assert_eq "tier3 auto-seq" "session-5" "$REPLY"
}

main() {
  emulate -L zsh
  print -r -- "▶ session-identity tests"
  local PROGRESS="$_THIS/../shell/progress.zsh"
  export XDG_CACHE_HOME="$(mktemp -d)"   # isolate the source-time seq claim
  source "$PROGRESS"

  test_resolver

  print -r -- "  ──"
  print -r -- "  ${_pass} passed, ${_fail} failed"
  rm -rf "$XDG_CACHE_HOME"
  (( _fail == 0 ))
}

main "$@"
