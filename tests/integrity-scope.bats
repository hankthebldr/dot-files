#!/usr/bin/env bats
# integrity-scope.bats — the committed manifest must describe REPO CONTENT ONLY.
#
# Regression guard for the machine-dependent-manifest bug: integrity.sh used to
# hash git-ignored paths (vendored skills, __pycache__, machine-local state), so
# regenerating on a second machine silently dropped those rows and `verify` then
# reported EXTRA for every such file the first machine had.
#
# integrity.sh derives REPO_ROOT from its own location, so each test builds a
# throwaway repo in BATS_TEST_TMPDIR and runs a copy of the script from there —
# the real checkout is never touched.

setup() {
  SRC="$BATS_TEST_DIRNAME/../scripts/utils"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts/utils"
  cp "$SRC/integrity.sh" "$SRC/tui-style.sh" "$SRC/claw-progress.sh" \
     "$SRC/claw-output.sh" "$SRC/theme.sh" "$REPO/scripts/utils/" 2>/dev/null || true

  printf 'real repo content\n'  > "$REPO/tracked.txt"
  printf 'junk/\n'              > "$REPO/.gitignore"
  mkdir -p "$REPO/junk" "$REPO/.remember/tmp"
  printf 'machine local\n'      > "$REPO/junk/machine-local.txt"
  printf 'session state\n'      > "$REPO/.remember/now.md"
  printf '4242\n'               > "$REPO/.remember/tmp/save.pid"

  git -C "$REPO" init -q 2>/dev/null
  git -C "$REPO" add -A 2>/dev/null
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm init 2>/dev/null
  MANIFEST="$REPO/config/integrity/manifest.sha256"
}

gen() { run bash "$REPO/scripts/utils/integrity.sh" generate; }

@test "integrity scope: tracked repo content IS hashed" {
  gen
  [ "$status" -eq 0 ]
  grep -q '  tracked.txt$' "$MANIFEST"
}

@test "integrity scope: git-ignored files are NOT hashed" {
  gen
  [ "$status" -eq 0 ]
  ! grep -q 'junk/machine-local.txt' "$MANIFEST"
}

@test "integrity scope: .remember/ machine-local state is NOT hashed" {
  gen
  [ "$status" -eq 0 ]
  ! grep -q '.remember/' "$MANIFEST"
}

@test "integrity scope: manifest is deterministic across regenerations" {
  gen
  cp "$MANIFEST" "$BATS_TEST_TMPDIR/first.sha256"
  gen
  diff -q "$BATS_TEST_TMPDIR/first.sha256" "$MANIFEST"
}

@test "integrity scope: verify is clean immediately after generate" {
  gen
  run bash "$REPO/scripts/utils/integrity.sh" verify
  [ "$status" -eq 0 ]
}

@test "integrity scope: a NEW git-ignored file does not make verify drift" {
  # The real-world failure: machine B has local junk machine A never saw.
  gen
  printf 'appeared later\n' > "$REPO/junk/another.txt"
  run bash "$REPO/scripts/utils/integrity.sh" verify
  [ "$status" -eq 0 ]
}

@test "integrity scope: tampering with tracked content STILL trips verify" {
  # The guard must not have blunted actual tamper detection.
  gen
  printf 'tampered\n' > "$REPO/tracked.txt"
  run bash "$REPO/scripts/utils/integrity.sh" verify
  [ "$status" -ne 0 ]
}

@test "integrity scope: non-git (tarball) tree still generates" {
  rm -rf "$REPO/.git"
  gen
  [ "$status" -eq 0 ]
  grep -q '  tracked.txt$' "$MANIFEST"
}
