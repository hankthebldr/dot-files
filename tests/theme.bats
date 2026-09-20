#!/usr/bin/env bats
# theme.sh — the one theme engine (audit 2026-09-20 F-11, F-16).
# F-11: the load path forked ~66 processes (cut ×22, tr ×11, head, $(...)) and
# ran 5× per login. Pin: zero external commands in claw_theme_load under
# xtrace (bash AND zsh), identical exports from both shells, an idempotent
# second load, and exports.zsh no longer re-sourcing theme.sh.
# F-16: exports.zsh force-exported XDG_* so scratch-redirected shells hit the
# real ~/.cache; pin that pre-set XDG vars are honoured.
#
# Fork-count assertions trace the FUNCTION after sourcing (theme.sh's
# source-time `claw_theme_load 2>/dev/null` swallows xtrace). `grep -a`: BSD
# grep treats the palette's UTF-8 comments in a zsh -f (C locale) trace as
# binary and prints no count without it.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  THEME="$REPO/scripts/utils/theme.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export CLAW_NO_LOG=1
  export DOTFILES_DIR="$REPO"
  mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME/claw" "$XDG_CONFIG_HOME"
  unset CLAW_THEME CLAW_THEME_SLUG CLAW_C_BG CLAW_RGB_BLUE CLAW_THEME_FORCE
}

FORK_RE='^\+.*\b(cut|tr|head|sed|awk|basename|grep)\b'

# --- (1) fork-free load path ------------------------------------------------

@test "theme: claw_theme_load spawns no external command under zsh xtrace" {
  # state file present so claw_theme_current takes the read-from-file branch
  printf 'synthwave\n' > "$XDG_STATE_HOME/claw/theme"
  run zsh -fc "source '$THEME'; unset CLAW_THEME_SLUG; set -x; claw_theme_load"
  [ "$status" -eq 0 ]
  n="$(printf '%s\n' "$output" | grep -acE "$FORK_RE" || true)"
  [ "${n:-0}" -eq 0 ]
  # sanity: the trace really covered the loop (a value was exported)
  [[ "$output" == *"CLAW_RGB_BLUE"* ]]
}

@test "theme: claw_theme_load spawns no external command under bash xtrace" {
  printf 'synthwave\n' > "$XDG_STATE_HOME/claw/theme"
  run bash -c "source '$THEME'; unset CLAW_THEME_SLUG; set -x; claw_theme_load"
  [ "$status" -eq 0 ]
  n="$(printf '%s\n' "$output" | grep -acE "$FORK_RE" || true)"
  [ "${n:-0}" -eq 0 ]
  [[ "$output" == *"CLAW_RGB_BLUE"* ]]
}

@test "theme: claw_theme_current reads the state file without head" {
  printf 'synthwave\n' > "$XDG_STATE_HOME/claw/theme"
  run bash -c "source '$THEME'; set -x; claw_theme_current"
  [ "$status" -eq 0 ]
  [[ "$output" == *"synthwave"* ]]
  n="$(printf '%s\n' "$output" | grep -acE "$FORK_RE" || true)"
  [ "${n:-0}" -eq 0 ]
}

# --- (2) bash and zsh agree --------------------------------------------------

dump_theme() {  # $1 = shell, $2 = slug (via CLAW_THEME)
  CLAW_THEME="$2" "$1" -c "source '$THEME'; env" | grep -E '^CLAW_(C|RGB|THEME_SLUG|THEME_NAME)' | sort
}

@test "theme: bash and zsh export identical CLAW_C_*/CLAW_RGB_* (refined-dark)" {
  dump_theme bash refined-dark > "$BATS_TEST_TMPDIR/bash.env"
  dump_theme zsh  refined-dark > "$BATS_TEST_TMPDIR/zsh.env"
  diff "$BATS_TEST_TMPDIR/bash.env" "$BATS_TEST_TMPDIR/zsh.env"
  grep -qx 'CLAW_RGB_BLUE=88;166;255' "$BATS_TEST_TMPDIR/bash.env"
  grep -qx 'CLAW_C_BG=0d1117'         "$BATS_TEST_TMPDIR/bash.env"
  grep -qx 'CLAW_THEME_SLUG=refined-dark' "$BATS_TEST_TMPDIR/bash.env"
  # all 11 palette keys land, both flavours
  [ "$(grep -c '^CLAW_C_'   "$BATS_TEST_TMPDIR/bash.env")" -eq 11 ]
  [ "$(grep -c '^CLAW_RGB_' "$BATS_TEST_TMPDIR/bash.env")" -eq 11 ]
}

@test "theme: bash and zsh export identical CLAW_C_*/CLAW_RGB_* (synthwave)" {
  dump_theme bash synthwave > "$BATS_TEST_TMPDIR/bash.env"
  dump_theme zsh  synthwave > "$BATS_TEST_TMPDIR/zsh.env"
  diff "$BATS_TEST_TMPDIR/bash.env" "$BATS_TEST_TMPDIR/zsh.env"
  # leading-zero hex pairs must not be read as octal (00b3ff → 0;179;255)
  grep -qx 'CLAW_RGB_BLUE=0;179;255'  "$BATS_TEST_TMPDIR/bash.env"
  grep -qx 'CLAW_RGB_GREEN=0;255;163' "$BATS_TEST_TMPDIR/bash.env"
  grep -qx 'CLAW_THEME_NAME=Synthwave' "$BATS_TEST_TMPDIR/bash.env"
}

# --- (3) idempotent ------------------------------------------------------------

# A private copy of one palette so we can move/edit it without touching the repo.
make_private_dots() {
  PDOTS="$BATS_TEST_TMPDIR/dots"
  mkdir -p "$PDOTS/config/themes/refined-dark" "$PDOTS/scripts/utils"
  cp "$REPO/config/themes/refined-dark/palette.theme" "$PDOTS/config/themes/refined-dark/"
  cp "$THEME" "$PDOTS/scripts/utils/theme.sh"
}

@test "theme: second load with CLAW_THEME_SLUG set does not re-read the palette" {
  make_private_dots
  run bash -c "
    export DOTFILES_DIR='$PDOTS'
    source '$PDOTS/scripts/utils/theme.sh'
    mv '$PDOTS/config/themes/refined-dark/palette.theme' '$PDOTS/gone.theme'
    claw_theme_load
    printf 'slug=%s blue=%s rgb=%s\n' \"\$CLAW_THEME_SLUG\" \"\$CLAW_C_BLUE\" \"\$CLAW_RGB_BLUE\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"slug=refined-dark blue=58a6ff rgb=88;166;255"* ]]
}

@test "theme: unchanged slug skips the file; CLAW_THEME_FORCE=1 re-reads it" {
  make_private_dots
  run bash -c "
    export DOTFILES_DIR='$PDOTS'
    source '$PDOTS/scripts/utils/theme.sh'
    sed -i.bak 's/^blue=58a6ff/blue=010203/' '$PDOTS/config/themes/refined-dark/palette.theme'
    claw_theme_load;                   printf 'plain=%s\n' \"\$CLAW_RGB_BLUE\"
    CLAW_THEME_FORCE=1 claw_theme_load; printf 'force=%s\n' \"\$CLAW_RGB_BLUE\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"plain=88;166;255"* ]]
  [[ "$output" == *"force=1;2;3"* ]]
}

@test "theme: a changed slug (claw_theme_set) reloads without CLAW_THEME_FORCE" {
  run bash -c "
    source '$THEME'
    claw_theme_set synthwave >/dev/null
    printf 'slug=%s blue=%s\n' \"\$CLAW_THEME_SLUG\" \"\$CLAW_RGB_BLUE\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"slug=synthwave blue=0;179;255"* ]]
  [ "$(cat "$XDG_STATE_HOME/claw/theme")" = synthwave ]
}

@test "theme: apply_profile / reset_session switch palettes in one shell" {
  run bash -c "
    source '$THEME'
    PROFILE_THEME_DEFAULT=synthwave claw_theme_apply_profile
    printf 'prof=%s:%s\n' \"\$CLAW_THEME_SLUG\" \"\$CLAW_RGB_BLUE\"
    claw_theme_reset_session
    printf 'reset=%s:%s\n' \"\$CLAW_THEME_SLUG\" \"\$CLAW_RGB_BLUE\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"prof=synthwave:0;179;255"* ]]
  [[ "$output" == *"reset=refined-dark:88;166;255"* ]]
}

# --- (4) exports.zsh honours pre-set XDG vars ---------------------------------

@test "exports.zsh: pre-set XDG_* survive (F-16)" {
  run env XDG_CACHE_HOME=/x XDG_CONFIG_HOME=/c XDG_DATA_HOME=/d XDG_STATE_HOME="$XDG_STATE_HOME" \
    zsh -fc "source '$REPO/shell/exports.zsh'; print -r -- \"\$XDG_CACHE_HOME \$XDG_CONFIG_HOME \$XDG_DATA_HOME \$XDG_STATE_HOME\""
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == "/x /c /d $XDG_STATE_HOME" ]]
}

@test "exports.zsh: unset XDG_* default to the spec paths and are exported" {
  run env -u XDG_CACHE_HOME -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME \
    zsh -fc "source '$REPO/shell/exports.zsh'; env | grep '^XDG_' | sort"
  [ "$status" -eq 0 ]
  [[ "$output" == *"XDG_CACHE_HOME=$HOME/.cache"* ]]
  [[ "$output" == *"XDG_CONFIG_HOME=$HOME/.config"* ]]
  [[ "$output" == *"XDG_DATA_HOME=$HOME/.local/share"* ]]
  [[ "$output" == *"XDG_STATE_HOME=$HOME/.local/state"* ]]
}

# --- (5) single load ----------------------------------------------------------

@test "exports.zsh: no longer sources theme.sh (.zshrc step 2c is the one load)" {
  ! grep -qE 'source[[:space:]].*theme\.sh|\.[[:space:]].*theme\.sh' "$REPO/shell/exports.zsh"
}
