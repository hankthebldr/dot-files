#!/usr/bin/env bats
LINT="$BATS_TEST_DIRNAME/../scripts/utils/profiles-lint.sh"

@test "profiles lint passes on the real tree" {
  run bash "$LINT"
  [ "$status" -eq 0 ]
}

@test "profiles lint fails when a meta declares a missing toolchain" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  cat > "$tmp/shell/profiles/ghost/meta.zsh" <<'EOF'
PROFILE_NAME="ghost"
PROFILE_TOOLCHAIN="ghost-toolchain.sh"
PROFILE_KEY_TOOLS="ls"
EOF
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  rm -rf "$tmp"
}

@test "profiles lint fails when a meta omits PROFILE_START_DIR" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  cat > "$tmp/shell/profiles/ghost/meta.zsh" <<'EOF'
PROFILE_NAME="ghost"
PROFILE_KEY_TOOLS="ls"
EOF
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no PROFILE_START_DIR"* ]]
  rm -rf "$tmp"
}

@test "profiles lint fails on an unknown PROFILE_START_DIR token" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  cat > "$tmp/shell/profiles/ghost/meta.zsh" <<'EOF'
PROFILE_NAME="ghost"
PROFILE_KEY_TOOLS="ls"
PROFILE_START_DIR="@nope|$HOME/x"
EOF
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown PROFILE_START_DIR token: @nope"* ]]
  rm -rf "$tmp"
}

@test "profiles lint accepts an empty PROFILE_START_DIR (stay put)" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  cat > "$tmp/shell/profiles/ghost/meta.zsh" <<'EOF'
PROFILE_NAME="ghost"
PROFILE_KEY_TOOLS="ls"
PROFILE_START_DIR=""
EOF
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
}

@test "profiles lint rejects a top-level cd in a profile file" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  cat > "$tmp/shell/profiles/ghost/meta.zsh" <<'EOF'
PROFILE_NAME="ghost"
PROFILE_KEY_TOOLS="ls"
PROFILE_START_DIR="@vault"
EOF
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
