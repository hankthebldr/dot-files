#!/usr/bin/env bats
LINT="$BATS_TEST_DIRNAME/../scripts/utils/profiles-lint.sh"

# A meta.zsh that satisfies every rule — fixtures below mutate one field at a
# time so a failure names exactly the rule under test.
ghost_meta() {
  # U+F01B — a Nerd Font glyph no real profile claims. Built with printf so
  # this file stays plain ASCII and survives editors that mangle the PUA.
  local glyph="${1:-$(printf '\xef\x80\x9b')}"
  cat <<EOF
# ghost — fixture profile
PROFILE_NAME="ghost"
PROFILE_TIER="4"
PROFILE_GLYPH="$glyph"
PROFILE_DESC="fixture profile for the lint"
PROFILE_KEY_TOOLS="ls"
PROFILE_START_DIR=""
EOF
}

@test "profiles lint passes on the real tree" {
  run env DOTFILES_DIR="$BATS_TEST_DIRNAME/.." bash "$LINT"
  [ "$status" -eq 0 ]
}

@test "profiles lint fails when a meta declares a missing toolchain" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  { ghost_meta; printf 'PROFILE_TOOLCHAIN="ghost-toolchain.sh"\n'; } \
    > "$tmp/shell/profiles/ghost/meta.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  rm -rf "$tmp"
}

@test "profiles lint fails when a meta omits PROFILE_START_DIR" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  ghost_meta | grep -v '^PROFILE_START_DIR=' > "$tmp/shell/profiles/ghost/meta.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no PROFILE_START_DIR"* ]]
  rm -rf "$tmp"
}

@test "profiles lint fails on an unknown PROFILE_START_DIR token" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  ghost_meta | sed 's|^PROFILE_START_DIR=.*|PROFILE_START_DIR="@nope\|$HOME/x"|' \
    > "$tmp/shell/profiles/ghost/meta.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown PROFILE_START_DIR token: @nope"* ]]
  rm -rf "$tmp"
}

@test "profiles lint accepts an empty PROFILE_START_DIR (stay put)" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  ghost_meta > "$tmp/shell/profiles/ghost/meta.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
}

@test "profiles lint rejects a top-level cd in a profile file" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  ghost_meta > "$tmp/shell/profiles/ghost/meta.zsh"
  printf 'cd "$HOME/ghost"\n' > "$tmp/shell/profiles/ghost/common.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"top-level 'cd'"* ]]
  # the same cd INSIDE a function (indented) is fine
  printf 'gh() {\n  cd "$HOME/ghost"\n}\n' > "$tmp/shell/profiles/ghost/common.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
}

@test "profiles lint fails when a meta omits PROFILE_GLYPH" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  ghost_meta | grep -v '^PROFILE_GLYPH=' > "$tmp/shell/profiles/ghost/meta.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PROFILE_GLYPH"* ]]
  rm -rf "$tmp"
}

@test "profiles lint fails when PROFILE_DESC is empty" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  ghost_meta | sed 's|^PROFILE_DESC=.*|PROFILE_DESC=""|' \
    > "$tmp/shell/profiles/ghost/meta.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PROFILE_DESC"* ]]
  rm -rf "$tmp"
}

@test "profiles lint fails when two profiles share a glyph" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/shell/profiles/wraith" "$tmp/scripts/install"
  ghost_meta > "$tmp/shell/profiles/ghost/meta.zsh"
  ghost_meta | sed 's|^PROFILE_NAME=.*|PROFILE_NAME="wraith"|' \
    > "$tmp/shell/profiles/wraith/meta.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate PROFILE_GLYPH"* ]]
  rm -rf "$tmp"
}

@test "profiles lint fails on a line that breaks the meta grammar" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  { ghost_meta; printf 'export PROFILE_EXTRA=ghost\n'; } \
    > "$tmp/shell/profiles/ghost/meta.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 8"* ]]
  rm -rf "$tmp"
}

@test "profiles lint accepts a trailing comment after a field" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  { ghost_meta; printf 'PROFILE_HELP_CMD="ghost-help"   # bespoke card name\n'; } \
    > "$tmp/shell/profiles/ghost/meta.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
}

@test "profiles lint fails on an out-of-range PROFILE_TIER" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  ghost_meta | sed 's|^PROFILE_TIER=.*|PROFILE_TIER="7"|' \
    > "$tmp/shell/profiles/ghost/meta.zsh"
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PROFILE_TIER"* ]]
  rm -rf "$tmp"
}
