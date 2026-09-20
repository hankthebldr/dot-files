#!/usr/bin/env bats
# tui-style.bats — the bash TUI helpers and the cheatsheet consume the ONE
# theme engine (audit F-13). Before this, tui-style.sh / cheatsheet.sh carried
# their own GitHub-dark literals, so integrity / storage-doctor / cheatsheet
# ignored `claw theme set`.
#
# Contract under test:
#   * with theme.sh reachable and CLAW_THEME=<slug>, every c_* / letter colour
#     is derived from that palette's CLAW_RGB_* triplet
#   * with theme.sh unreachable (DOTFILES_DIR → empty dir) the refined-dark
#     fallback triplets apply, so a half-installed checkout still renders
#   * legacy names (c_cyan c_orange c_yellow c_dim c_white) stay defined and
#     the correctly-named twins (c_blue c_amber c_muted c_fg) equal them
#   * an already-loaded palette in the environment is honoured, not re-read
#
# The expected matrix triplets are read from the palette file — never
# hardcoded — so a palette tweak cannot silently invalidate the test.

setup() {
  DOTFILES="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TUI="$DOTFILES/scripts/utils/tui-style.sh"
  CHEAT="$DOTFILES/scripts/utils/cheatsheet.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export CLAW_NO_LOG=1
  export TERM=xterm-256color
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  EMPTY="$BATS_TEST_TMPDIR/empty"      # a DOTFILES_DIR with no theme.sh at all
  mkdir -p "$EMPTY"
  PALETTE="$DOTFILES/config/themes/matrix/palette.theme"
  MATRIX_BLUE="$(rgb_of blue)"
  MATRIX_PURPLE="$(rgb_of purple)"
  MATRIX_AMBER="$(rgb_of amber)"
  MATRIX_MUTED="$(rgb_of muted)"
  MATRIX_FG="$(rgb_of fg)"
  REFINED_BLUE="88;166;255"
}

# rgb_of <key> → "r;g;b" for that key of the matrix palette (bash arithmetic,
# no awk — portable across BSD/mawk/gawk).
rgb_of() {
  local hex
  hex="$(sed -n "s/^$1=//p" "$PALETTE" | head -n1 | tr -d '\r')"
  [ -n "$hex" ] || { echo "palette key missing: $1" >&2; return 1; }
  printf '%d;%d;%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Run a bash snippet with a scrubbed CLAW_* environment (the host shell may
# have exported a palette) and the given DOTFILES_DIR / CLAW_THEME.
fresh() {  # fresh <dotfiles_dir> <theme-or-empty> <snippet>
  run env DOTFILES_DIR="$1" CLAW_THEME="$2" bash -c "
    for v in \${!CLAW_C_@} \${!CLAW_RGB_@} CLAW_THEME_SLUG CLAW_THEME_NAME; do unset \"\$v\"; done
    [ -n \"\$CLAW_THEME\" ] || unset CLAW_THEME
    $3
  "
}

# ── tui-style.sh ─────────────────────────────────────────────────────────────

@test "tui-style: c_cyan follows CLAW_THEME=matrix (blue triplet from the palette)" {
  fresh "$DOTFILES" matrix "source '$TUI'; printf %s \"\$c_cyan\""
  [ "$status" -eq 0 ]
  [ "$output" = $'\e[38;2;'"${MATRIX_BLUE}m" ]
}

@test "tui-style: every legacy name maps to its palette key under matrix" {
  fresh "$DOTFILES" matrix "source '$TUI'
    printf 'purple=%s\n' \"\$c_purple\"
    printf 'orange=%s\n' \"\$c_orange\"
    printf 'yellow=%s\n' \"\$c_yellow\"
    printf 'dim=%s\n'    \"\$c_dim\"
    printf 'white=%s\n'  \"\$c_white\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"purple="$'\e[38;2;'"${MATRIX_PURPLE}m"* ]]
  [[ "$output" == *"orange="$'\e[38;2;'"${MATRIX_AMBER}m"* ]]
  [[ "$output" == *"yellow="$'\e[38;2;'"${MATRIX_AMBER}m"* ]]
  [[ "$output" == *"dim="$'\e[38;2;'"${MATRIX_MUTED}m"* ]]
  [[ "$output" == *"white="$'\e[38;2;'"${MATRIX_FG}m"* ]]
}

@test "tui-style: correctly-named twins equal their legacy aliases" {
  fresh "$DOTFILES" matrix "source '$TUI'
    [ \"\$c_blue\"  = \"\$c_cyan\" ]   || { echo blue-mismatch; exit 1; }
    [ \"\$c_amber\" = \"\$c_orange\" ] || { echo amber-mismatch; exit 1; }
    [ \"\$c_amber\" = \"\$c_yellow\" ] || { echo yellow-mismatch; exit 1; }
    [ \"\$c_muted\" = \"\$c_dim\" ]    || { echo muted-mismatch; exit 1; }
    [ \"\$c_fg\"    = \"\$c_white\" ]  || { echo fg-mismatch; exit 1; }
    [ -n \"\$c_reset\" ] && [ -n \"\$c_bold\" ] && [ -n \"\$c_green\" ] && [ -n \"\$c_red\" ] || { echo missing; exit 1; }
    echo twins-ok"
  [ "$status" -eq 0 ]
  [ "$output" = "twins-ok" ]
}

@test "tui-style: falls back to refined-dark when theme.sh is unreadable" {
  fresh "$EMPTY" matrix "source '$TUI'; printf %s \"\$c_cyan\""
  [ "$status" -eq 0 ]
  [ "$output" = $'\e[38;2;'"${REFINED_BLUE}m" ]
}

@test "tui-style: an already-loaded palette in the environment wins (no re-source)" {
  # CLAW_C_BG set ⇒ the shell already ran theme.sh; tui-style must consume the
  # exported triplets as-is even though no theme.sh is reachable.
  run env DOTFILES_DIR="$EMPTY" CLAW_C_BG=000000 CLAW_RGB_BLUE="1;2;3" \
      bash -c "source '$TUI'; printf %s \"\$c_cyan\""
  [ "$status" -eq 0 ]
  [ "$output" = $'\e[38;2;1;2;3m' ]
}

@test "tui-style: tui_header renders in the matrix palette (integrity/storage-doctor path)" {
  fresh "$DOTFILES" matrix "source '$TUI'; tui_header 'OPEN CLAW · Integrity Audit' 'sub'"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[38;2;'"${MATRIX_PURPLE}m"* ]]   # box border
  [[ "$output" == *$'\e[38;2;'"${MATRIX_BLUE}m"* ]]     # title
  [[ "$output" != *$'\e[38;2;'"${REFINED_BLUE}m"* ]]    # no refined-dark leak
}

@test "tui-style: still sources under set -e / set -u (integrity.sh, cheatsheet.sh)" {
  fresh "$EMPTY" "" "set -euo pipefail; source '$TUI'; echo strict-ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict-ok"* ]]
  fresh "$DOTFILES" matrix "set -euo pipefail; source '$TUI'; echo strict-ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict-ok"* ]]
}

# ── cheatsheet.sh ────────────────────────────────────────────────────────────

@test "cheatsheet: header B follows CLAW_THEME=matrix" {
  fresh "$DOTFILES" matrix "bash '$CHEAT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[38;2;'"${MATRIX_BLUE}m"*"OPEN CLAW"* ]]
  [[ "$output" == *$'\e[38;2;'"${MATRIX_PURPLE}m"* ]]
  [[ "$output" != *$'\e[38;2;'"${REFINED_BLUE}m"* ]]
}

@test "cheatsheet: falls back to refined-dark when theme.sh is unreadable" {
  fresh "$EMPTY" matrix "bash '$CHEAT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[38;2;'"${REFINED_BLUE}m"*"OPEN CLAW"* ]]
  [[ "$output" != *$'\e[38;2;'"${MATRIX_BLUE}m"* ]]
}
