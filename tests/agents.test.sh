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

# --- claw forwards extra args to the agent ---
claw_tmp="$(mktemp -d)"
mkdir -p "$claw_tmp/cfg/claw" "$claw_tmp/bin"
cat > "$claw_tmp/bin/recorder" <<'EOF'
#!/usr/bin/env bash
printf 'ARGS:[%s]\n' "$*"
EOF
chmod +x "$claw_tmp/bin/recorder"
cat > "$claw_tmp/cfg/claw/agents.toml" <<'EOF'
[rec]
command = "recorder"
EOF
got="$(XDG_CONFIG_HOME="$claw_tmp/cfg" PATH="$claw_tmp/bin:$PATH" \
        bash "$REPO/bin/claw" rec --serve "hi there" 2>/dev/null | grep '^ARGS:')"
assert_eq "claw forwards args to agent" "ARGS:[--serve hi there]" "$got"
rm -rf "$claw_tmp"

# --- registry `args` default: used only when caller passes none (openwork case) ---
claw_tmp2="$(mktemp -d)"
mkdir -p "$claw_tmp2/cfg/claw" "$claw_tmp2/bin"
cat > "$claw_tmp2/bin/recorder" <<'EOF'
#!/usr/bin/env bash
printf 'ARGS:[%s]\n' "$*"
EOF
chmod +x "$claw_tmp2/bin/recorder"
cat > "$claw_tmp2/cfg/claw/agents.toml" <<'EOF'
[rec]
command = "recorder"
args = "start"
EOF
got_default="$(XDG_CONFIG_HOME="$claw_tmp2/cfg" PATH="$claw_tmp2/bin:$PATH" \
        bash "$REPO/bin/claw" rec 2>/dev/null | grep '^ARGS:')"
assert_eq "claw uses registry default args when none passed" "ARGS:[start]" "$got_default"
got_override="$(XDG_CONFIG_HOME="$claw_tmp2/cfg" PATH="$claw_tmp2/bin:$PATH" \
        bash "$REPO/bin/claw" rec status 2>/dev/null | grep '^ARGS:')"
assert_eq "explicit args override registry default args" "ARGS:[status]" "$got_override"
rm -rf "$claw_tmp2"

# --- openwork/opencode ship as default agents & self-heal into a stale registry ---
claw_tmp3="$(mktemp -d)"
mkdir -p "$claw_tmp3/cfg/claw"
cat > "$claw_tmp3/cfg/claw/agents.toml" <<'EOF'
[claude]
command = "claude"
EOF
XDG_CONFIG_HOME="$claw_tmp3/cfg" bash "$REPO/bin/claw" agent list >/dev/null 2>&1
grep -q '^\[openwork\]$'  "$claw_tmp3/cfg/claw/agents.toml" && ow=yes || ow=no
grep -q '^\[opencode\]$'  "$claw_tmp3/cfg/claw/agents.toml" && oc=yes || oc=no
kept="$(grep -c '^\[claude\]$' "$claw_tmp3/cfg/claw/agents.toml")"
assert_eq "openwork self-heals into a stale [claude]-only registry" "yes" "$ow"
assert_eq "opencode self-heals into a stale [claude]-only registry" "yes" "$oc"
assert_eq "reconcile does not duplicate the existing [claude]"      "1"   "$kept"
rm -rf "$claw_tmp3"

echo "  ──"
echo "  ${pass} passed, ${fail} failed"
(( fail == 0 ))
