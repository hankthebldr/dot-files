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
