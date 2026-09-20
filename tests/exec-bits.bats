#!/usr/bin/env bats
# audit 2026-09-20 F-05: situation.sh was tracked as 100644 and exec'd directly
# by the login kick and the launchd plist → "permission denied", swallowed by
# &>/dev/null, so the homelab fleet cache was never written on the Mac.
# Rule: any file under scripts/ or bin/ that starts with a shebang is meant to
# be executed directly and MUST carry the exec bit in the git index.

REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "every shebang'd file under scripts/ and bin/ is 100755 in the index" {
  cd "$REPO"
  bad=""
  while IFS= read -r f; do
    if head -c 2 "$f" 2>/dev/null | grep -q '^#!'; then bad="$bad $f"; fi
  done < <(git ls-files -s scripts bin | awk '$1=="100644"{print $4}')
  echo "non-executable scripts:$bad"
  [ -z "$bad" ]
}

@test "login kick and launchd plist can exec situation.sh directly" {
  cd "$REPO"
  [ -x scripts/utils/situation.sh ]
}
