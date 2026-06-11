#!/usr/bin/env bash
# tests/shellcheck.sh
# Local proxy for the CI shell-lint gate (.github/workflows/ci.yml). Mirrors
# CI's two-tier policy so "green locally" means "green in CI":
#   1. error severity, whole repo        — real bugs, must pass
#   2. warning severity, the core engine — new/core code held to a higher bar
# A third, INFORMATIONAL pass surfaces warning-level findings in the rest of the
# tree (the long tail of style debt) without failing the gate.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

if [[ -d "/opt/homebrew/bin" ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi

green='\033[0;32m'; red='\033[0;31m'; dim='\033[0;90m'; yellow='\033[0;33m'; nc='\033[0m'

if ! command -v shellcheck &>/dev/null; then
    echo -e "${red}shellcheck is not installed.${nc}  Install: brew install shellcheck / apt install shellcheck"
    exit 1
fi

# Exclusions shared with CI step (b): source-following + cinematic color-logging
# style codes (unused palette vars, color in printf, A||B||C, unassigned color).
EXCL="SC1090,SC1091,SC2034,SC2059,SC2015,SC2154"

# Core engine — held to warning severity (must pass). Keep in sync with ci.yml.
CORE=(
    scripts/install/lib/toolchain-runner.sh
    scripts/install/provision.sh
    scripts/install/nextgen-toolchain.sh
    scripts/utils/pkg-manifest.sh
    scripts/utils/secret.sh
    scripts/utils/ai.sh
    scripts/utils/selfupdate.sh
    scripts/utils/capture-tasks.sh
    scripts/utils/handoff.sh
    scripts/utils/cheatsheet.sh
    scripts/utils/docs-to-vault.sh
)

FAIL=0

echo "🔍 [1/3] error severity — whole repo (must pass)"
while IFS= read -r f; do
    head -1 "$f" | grep -qE 'bash|sh' || continue
    if ! shellcheck -S error -e SC1090,SC1091 "$f" 2>/dev/null; then
        echo -e "  ${red}✗${nc} $f"
        FAIL=$((FAIL + 1))
    fi
done < <(git ls-files 'scripts/**/*.sh' 'bin/*' 'install.sh' 'bootstrap.sh' '*.sh')
[[ $FAIL -eq 0 ]] && echo -e "  ${green}✓ no error-severity findings${nc}"

echo "🔍 [2/3] warning severity — core engine (must pass)"
core_fail=0
for f in "${CORE[@]}"; do
    if ! shellcheck -S warning -e "$EXCL" "$f" 2>/dev/null; then
        echo -e "  ${red}✗${nc} $f"
        FAIL=$((FAIL + 1)); core_fail=$((core_fail + 1))
    fi
done
[[ $core_fail -eq 0 ]] && echo -e "  ${green}✓ core engine clean at warning severity${nc}"

echo "🔍 [3/3] warning severity — rest of tree (informational, non-fatal)"
info=0
while IFS= read -r f; do
    head -1 "$f" | grep -qE 'bash|sh' || continue
    printf '%s\n' "${CORE[@]}" | grep -qxF "$f" && continue
    shellcheck -S warning -e "$EXCL" "$f" >/dev/null 2>&1 || { echo -e "  ${yellow}•${nc} $f"; info=$((info + 1)); }
done < <(git ls-files 'scripts/**/*.sh' 'bin/*' 'install.sh' 'bootstrap.sh' '*.sh')
[[ $info -eq 0 ]] && echo -e "  ${green}✓ none${nc}" || echo -e "  ${dim}$info file(s) with style/warning debt — not enforced (see backlog)${nc}"

echo "──────────────────────────────"
if [[ $FAIL -gt 0 ]]; then
    echo -e "  ${red}FAILED${nc} — $FAIL enforced check(s) failed"
    exit 1
fi
echo -e "  ${green}PASSED${nc} — matches CI shell-lint policy"
