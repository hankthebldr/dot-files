#!/usr/bin/env bash
# tests/shellcheck.sh
# Lint all shell scripts in the repo using shellcheck

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[0;90m'
NC='\033[0m'

if ! command -v shellcheck &> /dev/null; then
    echo -e "${RED}shellcheck is not installed.${NC}"
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
        echo -e "  ${GREEN}✓${NC} $rel"
        ((PASS++))
    else
        echo -e "  ${RED}✗${NC} $rel"
        ((FAIL++))
    fi
done < <(find "$REPO_ROOT" -name "*.sh" -not -path "*/legacy/*" -not -path "*/.git/*" | sort)

echo ""
echo "──────────────────────────────"
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${DIM}Skipped:${NC} $SKIP (zsh files)"
echo "──────────────────────────────"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi

echo -e "${GREEN}All shell scripts passed!${NC}"
