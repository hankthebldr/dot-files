#!/usr/bin/env bats
# audit 2026-09-20 F-15: toolkit.sh shipped two destructive one-shots behind
# a bare numeric prompt — "Quick Commit & Push" (git add . && commit && push)
# and "System Prune" (docker system prune -af --volumes). Both are gone; the
# sub-menus must stay numbered contiguously from 1 so the echo list, the case
# arms and the [1-N] prompt never drift apart again.

REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
TOOLKIT="$REPO/scripts/utils/toolkit.sh"

@test "toolkit.sh has no 'git add .' arm" {
  run grep -nE 'git add \.' "$TOOLKIT"
  echo "$output"
  [ "$status" -ne 0 ]
}

@test "toolkit.sh has no 'docker system prune -af --volumes' arm" {
  run grep -nE 'prune -af --volumes' "$TOOLKIT"
  echo "$output"
  [ "$status" -ne 0 ]
}

@test "nothing under scripts/ runs 'git add .' or 'prune -af --volumes'" {
  run grep -rnE 'git add \.|prune -af --volumes' "$REPO/scripts"
  echo "$output"
  [ "$status" -ne 0 ]
}

@test "toolkit.sh parses (bash -n)" {
  run bash -n "$TOOLKIT"
  echo "$output"
  [ "$status" -eq 0 ]
}

# One row per category: "<cat> <echo numbers,> <case arm numbers,> <prompt max>".
# Top-level arms sit at 4-space indent, their echo rows at 8, their case arms at 12.
_toolkit_menu_table() {
  awk '
    /^    [0-9]+\)$/ { cat=$1; sub(/\)/,"",cat); next }
    cat != "" && /^        echo "  [0-9]+\. / {
      n=$0; sub(/^        echo "  /,"",n); sub(/\..*/,"",n); echo_[cat]=echo_[cat] n ","
    }
    cat != "" && /^            [0-9]+\)/ {
      n=$0; sub(/^ +/,"",n); sub(/\).*/,"",n); arms[cat]=arms[cat] n ","
    }
    cat != "" && /Run workflow \[1-[0-9]+\]/ {
      r=$0; sub(/.*\[1-/,"",r); sub(/\].*/,"",r); range[cat]=r
    }
    END { for (c in echo_) print c, echo_[c], arms[c], range[c] }
  ' "$TOOLKIT" | sort -n
}

@test "every category sub-menu is numbered contiguously from 1 in echo list, case arms and [1-N] prompt" {
  table="$(_toolkit_menu_table)"
  echo "$table"
  [ -n "$table" ]
  ncat=$(printf '%s\n' "$table" | wc -l | tr -d ' ')
  [ "$ncat" -eq 8 ]
  while read -r cat echos arms range; do
    [ -n "$range" ] || { echo "category $cat: no [1-N] prompt"; return 1; }
    expected=""
    for ((i=1; i<=range; i++)); do expected="$expected$i,"; done
    [ "$echos" = "$expected" ] || { echo "category $cat: echo list '$echos' != '$expected'"; return 1; }
    [ "$arms" = "$expected" ] || { echo "category $cat: case arms '$arms' != '$expected'"; return 1; }
  done <<< "$table"
}

# The welcome TUI was the only caller that pre-seeded TK_AUTO_START (with "8");
# it retired to legacy/ with the menu (T1-10), so the old cross-file assertion
# had nothing left to assert. The env-var contract in toolkit.sh survives for
# any future caller, so pin THAT instead: the hook reads TK_AUTO_START, unsets
# it so a sub-menu loop can't re-fire it, and category 8 is still the AI arm.
@test "toolkit.sh TK_AUTO_START hook still bypasses the prompt for category 8" {
  grep -q 'if \[\[ -n "\$TK_AUTO_START" \]\]' "$TOOLKIT"
  grep -q 'main_choice="\$TK_AUTO_START"' "$TOOLKIT"
  grep -q 'unset TK_AUTO_START' "$TOOLKIT"
  grep -qE '^    8\)$' "$TOOLKIT"
  grep -q 'Agentic & AI Solutions' "$TOOLKIT"
}
