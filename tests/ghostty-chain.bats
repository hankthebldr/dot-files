#!/usr/bin/env bats
# ghostty-chain.bats — the `claw validate` Ghostty drift guard (validate-install.sh
# phase 1b, from the 2026-07-18 experience spec § 5). Runs the real validator
# against a FAKED home tree so no host state is touched.

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  FAKE="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE/.config"
}

run_validate() {
  HOME="$FAKE" DOTFILES_DIR="$REPO" run bash "$REPO/scripts/utils/validate-install.sh" --no-fetch
}

@test "ghostty chain: skipped entirely when not installed and not deployed" {
  # Fake HOME has no ~/.config/ghostty; strip ghostty from PATH resolution by
  # using the fake home (the container has no ghostty binary either).
  run_validate
  [[ "$output" != *"Ghostty chain"* ]]
}

@test "ghostty chain: unlinked dir warns and points at symlinks.sh" {
  mkdir -p "$FAKE/.config/ghostty"   # real dir, NOT a repo symlink
  run_validate
  [[ "$output" == *"Ghostty chain"* ]]
  [[ "$output" == *"NOT linked into the repo"* ]]
  [[ "$output" == *"symlinks.sh"* ]]
}

@test "ghostty chain: repo-linked dir with os-active + theme passes" {
  ln -s "$REPO/terminal/.config/ghostty" "$FAKE/.config/ghostty"
  # os-active + theme live INSIDE the (symlinked) repo dir in real deployments
  # and are git-ignored; create them only if absent and clean up after.
  created=""
  if [[ ! -e "$REPO/terminal/.config/ghostty/os-active.conf" ]]; then
    ln -s os-linux.conf "$REPO/terminal/.config/ghostty/os-active.conf"
    created="$created os-active"
  fi
  if [[ ! -s "$REPO/terminal/.config/ghostty/theme.conf" ]]; then
    echo "# test theme" > "$REPO/terminal/.config/ghostty/theme.conf"
    created="$created theme"
  fi
  run_validate
  if [[ "$created" == *os-active* ]]; then rm -f "$REPO/terminal/.config/ghostty/os-active.conf"; fi
  if [[ "$created" == *theme* ]]; then rm -f "$REPO/terminal/.config/ghostty/theme.conf"; fi
  [[ "$output" == *"→ repo"* ]]
  [[ "$output" == *"os-active.conf → os-linux.conf"* ]]
  [[ "$output" == *"theme.conf present"* ]]
}

@test "ghostty chain: missing theme.conf warns with claw theme build fix" {
  ln -s "$REPO/terminal/.config/ghostty" "$FAKE/.config/ghostty"
  if [[ -s "$REPO/terminal/.config/ghostty/theme.conf" ]]; then
    skip "host checkout has a real theme.conf"
  fi
  run_validate
  [[ "$output" == *"theme.conf missing"* ]]
  [[ "$output" == *"claw theme build"* ]]
}
