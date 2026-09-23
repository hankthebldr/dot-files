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
  # Deterministic terminal facts: the emitters are depth-aware as of T2-03, so
  # a bats run must not inherit the ambient TERM (empty in some agents/CI).
  export TERM=xterm-256color
  unset CLAW_COLOR_DEPTH CLAW_COLOR_DEPTH_STRICT CLAW_GLYPHS
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
  env -u COLORTERM -u TERM_PROGRAM -u NO_COLOR -u VTE_VERSION \
      -u CLAW_COLOR_DEPTH -u CLAW_COLOR_DEPTH_STRICT "$@" \
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

# --- (10) T2-03 · the ONE quantiser ------------------------------------------
# theme.sh owns rgb→xterm-256 / rgb→ANSI-8 (spine contract 2) and the Python
# renderer mirrors it. These pin the precedence, the emitted forms, and that
# the two implementations never drift apart.

DASH_PY() { printf '%s' "$REPO/scripts/utils/claw-dashboard.py"; }

# render_depth_of <env assignments...> → the depth surfaces actually emit at
render_depth_of() {
  env -u COLORTERM -u TERM_PROGRAM -u NO_COLOR -u VTE_VERSION \
      -u CLAW_COLOR_DEPTH -u CLAW_COLOR_DEPTH_STRICT "$@" \
    bash -c "source '$THEME'; claw_theme_render_depth; printf %s \"\$_claw_rdepth\""
}

@test "theme: render depth — a declared CLAW_COLOR_DEPTH is obeyed, a probed 256 is not" {
  # declared wins, exactly
  [ "$(render_depth_of TERM=xterm CLAW_COLOR_DEPTH=256)" = 256 ]
  [ "$(render_depth_of TERM=xterm-256color CLAW_COLOR_DEPTH=24)" = 24 ]
  [ "$(render_depth_of TERM=xterm-256color CLAW_COLOR_DEPTH=0)" = 0 ]
  # probed 256 keeps emitting truecolor unless asked to be strict
  [ "$(render_depth_of TERM=xterm-256color)" = 24 ]
  [ "$(render_depth_of TERM=xterm-256color TERM_PROGRAM=Apple_Terminal)" = 24 ]
  [ "$(render_depth_of TERM=xterm-256color CLAW_COLOR_DEPTH_STRICT=1)" = 256 ]
  # 8 and 0 always degrade — there a wrong code really does render wrong
  [ "$(render_depth_of TERM=xterm)" = 8 ]
  [ "$(render_depth_of TERM=dumb)" = 0 ]
  # calling it twice must not promote its own probe into a declaration
  run env -u COLORTERM -u TERM_PROGRAM -u NO_COLOR -u CLAW_COLOR_DEPTH \
      TERM=xterm-256color bash -c \
      "source '$THEME'; claw_theme_render_depth; claw_theme_render_depth; printf %s \"\$_claw_rdepth\""
  [ "$output" = 24 ]
}

@test "theme: emit tui degrades — 8 uses base ANSI, 256 the cube, 0 is plain" {
  run env -u COLORTERM -u TERM_PROGRAM -u NO_COLOR CLAW_COLOR_DEPTH=8 TERM=xterm \
      bash "$THEME" emit tui
  [ "$status" -eq 0 ]
  [[ "$output" == *"c_blue=\$'\e[36m'"* ]]
  [[ "$output" == *"c_green=\$'\e[32m'"* ]]
  [[ "$output" == *"c_red=\$'\e[31m'"* ]]
  [[ "$output" != *"38;2;"* ]]
  [[ "$output" != *"38;5;"* ]]

  run env -u COLORTERM -u TERM_PROGRAM -u NO_COLOR CLAW_COLOR_DEPTH=256 TERM=xterm-256color \
      bash "$THEME" emit tui
  [ "$status" -eq 0 ]
  [[ "$output" == *"c_blue=\$'\e[38;5;75m'"* ]]
  [[ "$output" != *"38;2;"* ]]

  run env -u COLORTERM -u TERM_PROGRAM -u NO_COLOR CLAW_COLOR_DEPTH=0 TERM=dumb \
      bash "$THEME" emit tui
  [ "$status" -eq 0 ]
  [[ "$output" == *"c_blue=''"* ]]
  [[ "$output" == *"c_reset=''"* ]]
  [[ "$output" != *$'\e['* ]]

  # the default (probed, non-strict) path is unchanged: 24-bit
  run env -u COLORTERM -u TERM_PROGRAM -u NO_COLOR -u CLAW_COLOR_DEPTH \
      TERM=xterm-256color bash "$THEME" emit tui
  [[ "$output" == *"c_blue=\$'\e[38;2;"* ]]
}

@test "theme: emit tui legacy aliases still track their twins at depth 8" {
  run env -u COLORTERM -u TERM_PROGRAM -u NO_COLOR CLAW_COLOR_DEPTH=8 TERM=xterm bash -c \
    "eval \"\$(bash '$THEME' emit tui)\"
     [ \"\$c_cyan\" = \"\$c_blue\" ] && [ \"\$c_orange\" = \"\$c_amber\" ] &&
     [ \"\$c_dim\" = \"\$c_muted\" ] && [ \"\$c_white\" = \"\$c_fg\" ] && echo twins-ok"
  [ "$status" -eq 0 ]
  [ "$output" = twins-ok ]
}

@test "theme: theme.sh and claw-dashboard.py quantise identically" {
  # A table that exercises the cube, the grey ramp and the 8-colour reduction.
  samples="88;166;255 63;185;80 188;140;255 227;179;65 255;123;114 139;148;158 \
201;209;217 13;17;23 48;54;61 0;0;0 255;255;255 128;128;128 1;2;3 254;1;1 \
57;197;255 100;0;100"
  sh_out=""
  for c in $samples; do
    r="${c%%;*}"; rest="${c#*;}"; g="${rest%%;*}"; b="${rest#*;}"
    i256="$(bash -c "source '$THEME'; claw_theme_index256 $r $g $b; printf %s \"\$_claw_idx\"")"
    i8="$(bash -c "source '$THEME'; claw_theme_index8 $r $g $b; printf %s \"\$_claw_idx\"")"
    sh_out="$sh_out$c=$i256/$i8 "
  done
  py_out="$(DASH="$(DASH_PY)" SAMPLES="$samples" python3 -c '
import importlib.util, os
spec = importlib.util.spec_from_file_location("d", os.environ["DASH"])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
out = []
for c in os.environ["SAMPLES"].split():
    r, g, b = (int(x) for x in c.split(";"))
    out.append("%s=%d/%d" % (c, m.index256(r, g, b), m.index8(r, g, b)))
print(" ".join(out) + " ")')"
  [ "$sh_out" = "$py_out" ] || { echo "sh: $sh_out"; echo "py: $py_out"; false; }
}

# --- (11) T2-03 · CLAW_GLYPHS -------------------------------------------------

glyphs_of() {  # glyphs_of <env assignments...>
  env -u CLAW_GLYPHS "$@" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    bash -c "source '$THEME'; claw_theme_glyphs; printf %s \"\$CLAW_GLYPHS\""
}

@test "theme: claw_theme_glyphs precedence (env → file → TERM → nerd)" {
  rm -f "$XDG_CONFIG_HOME/claw/glyphs"
  mkdir -p "$XDG_CONFIG_HOME/claw"
  [ "$(glyphs_of TERM=xterm-256color)" = nerd ]
  [ "$(glyphs_of TERM=linux)" = ascii ]
  [ "$(glyphs_of TERM=dumb)" = ascii ]
  printf 'ascii\n' > "$XDG_CONFIG_HOME/claw/glyphs"
  [ "$(glyphs_of TERM=xterm-256color)" = ascii ]
  # an explicit env value beats the file, and `auto` re-detects past it
  [ "$(glyphs_of TERM=xterm-256color CLAW_GLYPHS=nerd)" = nerd ]
  [ "$(glyphs_of TERM=xterm-256color CLAW_GLYPHS=auto)" = nerd ]
  [ "$(glyphs_of TERM=linux CLAW_GLYPHS=auto)" = ascii ]
  # a junk file value is ignored, not obeyed
  printf 'wingdings\n' > "$XDG_CONFIG_HOME/claw/glyphs"
  [ "$(glyphs_of TERM=xterm-256color)" = nerd ]
  rm -f "$XDG_CONFIG_HOME/claw/glyphs"
}

@test "theme: theme.sh and claw-dashboard.py resolve the glyph mode identically" {
  mkdir -p "$XDG_CONFIG_HOME/claw"
  printf 'ascii\n' > "$XDG_CONFIG_HOME/claw/glyphs"
  for e in "TERM=xterm-256color" "TERM=linux" "TERM=xterm-256color CLAW_GLYPHS=nerd" \
           "TERM=xterm-256color CLAW_GLYPHS=auto"; do
    sh_v="$(glyphs_of $e)"
    py_v="$(env -u CLAW_GLYPHS $e XDG_CONFIG_HOME="$XDG_CONFIG_HOME" python3 -c '
import importlib.util, os
spec = importlib.util.spec_from_file_location("d", os.environ["DASH"])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.glyph_mode())' DASH="$(DASH_PY)" 2>/dev/null || env -u CLAW_GLYPHS $e \
      XDG_CONFIG_HOME="$XDG_CONFIG_HOME" DASH="$(DASH_PY)" python3 -c '
import importlib.util, os
spec = importlib.util.spec_from_file_location("d", os.environ["DASH"])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.glyph_mode())')"
    [ "$sh_v" = "$py_v" ] || { echo "$e: sh=$sh_v py=$py_v"; false; }
  done
  rm -f "$XDG_CONFIG_HOME/claw/glyphs"
}

# --- (12) T1-03 follow-up (requested by impl/t1-m, tests/theme.bats is ours) --

@test "theme: apply_profile is a no-op when PROFILE_THEME_DEFAULT is empty" {
  printf 'synthwave\n' > "$XDG_STATE_HOME/claw/theme"
  run bash -c "source '$THEME'; PROFILE_THEME_DEFAULT='' claw_theme_apply_profile
               printf '%s|%s' \"\${CLAW_THEME:-unset}\" \"\$CLAW_THEME_SLUG\""
  [ "$status" -eq 0 ]
  [ "$output" = "unset|synthwave" ]
}
