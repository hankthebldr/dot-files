#!/usr/bin/env bash
# tests/shellcheck.sh
# Lint all shell scripts in the repo using shellcheck

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure Homebrew is in PATH for non-interactive Apple Silicon shells
if [[ -d "/opt/homebrew/bin" ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi

# Colors
green='\033[0;32m'
red='\033[0;31m'
dim='\033[0;90m'
nc='\033[0m'

if ! command -v shellcheck &> /dev/null; then
    echo -e "${red}shellcheck is not installed.${nc}"
    echo "Install with: brew install shellcheck"
    exit 1
fi

echo "🔍 Running shellcheck on all .sh files..."
echo ""

PASS=0
FAIL=0
SKIP=0

# Find all .sh files, excluding legacy/
while IFS= read -r file; do
    rel=$(echo "$file" | sed "s|$REPO_ROOT/||")

    # Skip known non-bash files
    if head -1 "$file" | grep -q "zsh"; then
        ((SKIP++))
        continue
    fi

    if shellcheck -x -S warning "$file" 2>/dev/null; then
        echo -e "  ${green}✓${nc} $rel"
        ((PASS++))
    else
        echo -e "  ${red}✗${nc} $rel"
        ((FAIL++))
    fi
done < <(find "$REPO_ROOT" -name "*.sh" -not -path "*/legacy/*" -not -path "*/.git/*" | sort)

echo ""
echo "──────────────────────────────"
echo -e "  ${green}Passed:${nc}  $PASS"
echo -e "  ${red}Failed:${nc}  $FAIL"
echo -e "  ${dim}Skipped:${nc} $SKIP (zsh files)"
echo "──────────────────────────────"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi

echo -e "${green}All shell scripts passed!${nc}"
