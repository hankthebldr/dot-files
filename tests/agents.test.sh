#!/usr/bin/env bash
# tests/agents.test.sh — unit tests for the Hermes/OpenRouter agent plumbing.
# Run standalone: bash tests/agents.test.sh
set -uo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$THIS_DIR/.." && pwd)"
pass=0; fail=0

assert_eq() { # assert_eq <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; (( ++pass ))
  else echo "  ✗ $1"; echo "      expected: [$2]"; echo "      actual:   [$3]"; (( ++fail )); fi
}

# --- ollama_serve_cmd selection (pure, no daemon started) ---
source "$REPO/scripts/utils/ollama.sh"

# Prefix-assign the test seams directly on the function call so the function body
# sees them. (Assignments on a command-substitution's *arguments* would NOT reach
# the subshell — POSIX expands args before the prefix assignment takes effect.)
check_serve_cmd() { # <desc> <os> <systemctl> <brew> <expected>
  local actual
  actual="$(OS_TYPE="$2" _OLLAMA_HAS_SYSTEMCTL="$3" _OLLAMA_HAS_BREW="$4" ollama_serve_cmd)"
  assert_eq "$1" "$5" "$actual"
}

check_serve_cmd "linux+systemd → systemctl enable --now" ubuntu        1 0 "sudo systemctl enable --now ollama"
check_serve_cmd "macos+brew → brew services start"        macos         0 1 "brew services start ollama"
check_serve_cmd "fallback → nohup ollama serve"           linux-generic 0 0 "nohup ollama serve >/dev/null 2>&1 & disown"
check_serve_cmd "fedora+systemd (non-enumerated) → systemctl" fedora        1 0 "sudo systemctl enable --now ollama"

echo "  ──"
echo "  ${pass} passed, ${fail} failed"
(( fail == 0 ))
