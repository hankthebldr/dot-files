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

# --- (6) claw_theme_emit — the palette generator (F-13) -----------------------
# theme.sh is the ONE source of colour, so every other surface must be able to
# ask it for a ready-made artifact instead of re-deriving literals.

@test "theme: emit p10k parses under zsh -n and carries the palette blue" {
  run bash -c "source '$THEME'; CLAW_THEME=refined-dark CLAW_THEME_FORCE=1 claw_theme_load; claw_theme_emit p10k"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/p10k.zsh"
  zsh -n "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_DIR_BACKGROUND='#58a6ff'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_DIR_FOREGROUND='#0d1117'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_VCS_CLEAN_BACKGROUND='#3fb950'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_VCS_MODIFIED_BACKGROUND='#e3b341'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_VCS_CONFLICTED_BACKGROUND='#ff7b72'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_OS_ICON_BACKGROUND='#8b949e'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_KUBECONTEXT_BACKGROUND='#bc8cff'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_TERRAFORM_BACKGROUND='#bc8cff'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_AWS_BACKGROUND='#e3b341'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_GCLOUD_BACKGROUND='#39c5ff'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_STATUS_ERROR_BACKGROUND='#ff7b72'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_FOREGROUND='#3fb950'" "$BATS_TEST_TMPDIR/p10k.zsh"
  grep -q "POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_FOREGROUND='#ff7b72'" "$BATS_TEST_TMPDIR/p10k.zsh"
}

@test "theme: emit p10k follows the active palette (synthwave ≠ refined-dark)" {
  run bash -c "source '$THEME'; CLAW_THEME=synthwave CLAW_THEME_FORCE=1 claw_theme_load; claw_theme_emit p10k"
  [ "$status" -eq 0 ]
  blue="$(bash -c "source '$THEME'; CLAW_THEME=synthwave CLAW_THEME_FORCE=1 claw_theme_load; printf %s \"\$CLAW_C_BLUE\"")"
  [[ "$output" == *"POWERLEVEL9K_DIR_BACKGROUND='#$blue'"* ]]
  [[ "$output" != *"58a6ff"* ]]
}

@test "theme: emit tui defines c_* and the legacy aliases equal their twins" {
  run bash -c "
    source '$THEME'; CLAW_THEME=refined-dark CLAW_THEME_FORCE=1 claw_theme_load
    eval \"\$(claw_theme_emit tui)\"
    printf 'eq_cyan=%s\n' \"\$([ \"\$c_cyan\" = \"\$c_blue\" ] && echo yes || echo no)\"
    printf 'eq_yellow=%s\n' \"\$([ \"\$c_yellow\" = \"\$c_amber\" ] && echo yes || echo no)\"
    printf 'eq_orange=%s\n' \"\$([ \"\$c_orange\" = \"\$c_amber\" ] && echo yes || echo no)\"
    printf 'eq_dim=%s\n' \"\$([ \"\$c_dim\" = \"\$c_muted\" ] && echo yes || echo no)\"
    printf 'eq_white=%s\n' \"\$([ \"\$c_white\" = \"\$c_fg\" ] && echo yes || echo no)\"
    printf 'blue=%s\n' \"\$c_blue\"
    printf 'reset=%s\n' \"\$c_reset\"
    printf 'bold=%s\n' \"\$c_bold\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"eq_cyan=yes"* ]]
  [[ "$output" == *"eq_yellow=yes"* ]]
  [[ "$output" == *"eq_orange=yes"* ]]
  [[ "$output" == *"eq_dim=yes"* ]]
  [[ "$output" == *"eq_white=yes"* ]]
  [[ "$output" == *"blue="$'\e[38;2;88;166;255m'* ]]
  [[ "$output" == *"reset="$'\e[0m'* ]]
  [[ "$output" == *"bold="$'\e[1m'* ]]
}

@test "theme: emit fzf exports CLAW_FZF_COLOR = claw_theme_fzf" {
  run bash -c "
    source '$THEME'; CLAW_THEME=refined-dark CLAW_THEME_FORCE=1 claw_theme_load
    want=\"\$(claw_theme_fzf)\"
    eval \"\$(claw_theme_emit fzf)\"
    [ \"\$CLAW_FZF_COLOR\" = \"\$want\" ] && echo match || echo \"mismatch: \$CLAW_FZF_COLOR\"
    env | grep -q '^CLAW_FZF_COLOR=' && echo exported
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *match* ]]
  [[ "$output" == *exported* ]]
}

# --- (7) emit osc — allow-listed terminals only --------------------------------

@test "theme: emit osc is non-empty for ghostty with the tty force hook" {
  run env -u SSH_CONNECTION -u SSH_TTY -u TMUX -u VTE_VERSION \
    CLAW_THEME_OSC_FORCE_TTY=1 TERM_PROGRAM=ghostty \
    bash -c "source '$THEME'; claw_theme_emit osc"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$output" == *"]10;#c9d1d9"* ]]
  [[ "$output" == *"]11;#0d1117"* ]]
  [[ "$output" == *"]12;#58a6ff"* ]]
}

@test "theme: emit osc fires for every allow-listed TERM_PROGRAM and VTE" {
  for tp in ghostty iTerm.app WezTerm kitty; do
    run env -u SSH_CONNECTION -u SSH_TTY -u TMUX -u VTE_VERSION \
      CLAW_THEME_OSC_FORCE_TTY=1 TERM_PROGRAM="$tp" \
      bash -c "source '$THEME'; claw_theme_emit osc"
    [ "$status" -eq 0 ]
    [ -n "$output" ] || { echo "empty for $tp"; return 1; }
  done
  run env -u SSH_CONNECTION -u SSH_TTY -u TMUX -u TERM_PROGRAM \
    CLAW_THEME_OSC_FORCE_TTY=1 VTE_VERSION=6003 \
    bash -c "source '$THEME'; claw_theme_emit osc"
  [ -n "$output" ]
}

@test "theme: emit osc is empty for Apple_Terminal, TMUX, SSH and CLAW_THEME_OSC=0" {
  run env -u SSH_CONNECTION -u SSH_TTY -u TMUX -u VTE_VERSION \
    CLAW_THEME_OSC_FORCE_TTY=1 TERM_PROGRAM=Apple_Terminal \
    bash -c "source '$THEME'; claw_theme_emit osc"
  [ "$status" -eq 0 ]; [ -z "$output" ]

  run env -u SSH_CONNECTION -u SSH_TTY -u VTE_VERSION \
    CLAW_THEME_OSC_FORCE_TTY=1 TERM_PROGRAM=ghostty TMUX=/tmp/tmux-501/default,1,0 \
    bash -c "source '$THEME'; claw_theme_emit osc"
  [ "$status" -eq 0 ]; [ -z "$output" ]

  run env -u SSH_TTY -u TMUX -u VTE_VERSION \
    CLAW_THEME_OSC_FORCE_TTY=1 TERM_PROGRAM=ghostty SSH_CONNECTION="10.0.0.1 1 10.0.0.2 22" \
    bash -c "source '$THEME'; claw_theme_emit osc"
  [ "$status" -eq 0 ]; [ -z "$output" ]

  run env -u SSH_CONNECTION -u SSH_TTY -u TMUX -u VTE_VERSION \
    CLAW_THEME_OSC_FORCE_TTY=1 TERM_PROGRAM=ghostty CLAW_THEME_OSC=0 \
    bash -c "source '$THEME'; claw_theme_emit osc"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "theme: emit osc is empty without a tty and without the force hook" {
  run env -u SSH_CONNECTION -u SSH_TTY -u TMUX -u VTE_VERSION -u CLAW_THEME_OSC_FORCE_TTY \
    TERM_PROGRAM=ghostty bash -c "source '$THEME'; claw_theme_emit osc"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "theme: emit with an unknown target fails loudly" {
  run bash -c "source '$THEME'; claw_theme_emit nope"
  [ "$status" -ne 0 ]
}

# --- (8) claw_theme_depth ------------------------------------------------------

depth_of() {  # depth_of <env assignments...>
  env -u COLORTERM -u TERM_PROGRAM -u NO_COLOR -u VTE_VERSION "$@" \
    bash -c "source '$THEME'; claw_theme_depth; printf %s \"\$CLAW_COLOR_DEPTH\""
}

@test "theme: claw_theme_depth table (dumb/NO_COLOR/Apple/truecolor/allow-list/256/8)" {
  [ "$(depth_of TERM=dumb)" = 0 ]
  [ "$(depth_of TERM=xterm-256color NO_COLOR=1)" = 0 ]
  [ "$(depth_of TERM=xterm-256color TERM_PROGRAM=Apple_Terminal COLORTERM=truecolor)" = 256 ]
  [ "$(depth_of TERM=xterm-256color COLORTERM=truecolor)" = 24 ]
  [ "$(depth_of TERM=xterm-256color TERM_PROGRAM=ghostty)" = 24 ]
  [ "$(depth_of TERM=xterm-256color)" = 256 ]
  [ "$(depth_of TERM=xterm)" = 8 ]
}

@test "theme: claw_theme_depth exports CLAW_COLOR_DEPTH to children" {
  run env -u COLORTERM -u TERM_PROGRAM -u NO_COLOR TERM=xterm-256color \
    bash -c "source '$THEME'; claw_theme_depth; env | grep '^CLAW_COLOR_DEPTH='"
  [ "$status" -eq 0 ]
  [ "$output" = "CLAW_COLOR_DEPTH=256" ]
}

# --- (9) no raw ANSI literals left in theme.sh --------------------------------

@test "theme: theme.sh carries no hardcoded 38;2 triplet outside a palette fallback" {
  run bash -c "grep -n '38;2;[0-9]' '$THEME' | grep -v 'CLAW_RGB_' || true"
  [ -z "$output" ]
  run bash -c "grep -n '48;2;[0-9]' '$THEME' | grep -v 'CLAW_RGB_' || true"
  [ -z "$output" ]
}
