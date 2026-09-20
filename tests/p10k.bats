#!/usr/bin/env bats
# p10k.bats — the prompt consumes the ONE theme engine and carries the
# attention flag (audit 2026-09-20 F-13, F-10).
#
# F-13: `.p10k.zsh` carried 45 gruvbox literals, so `claw theme set` changed
# every surface except the thing Henry looks at 1200×/day. Pin: with
# CLAW_P10K_THEMED=1 (the default) the colour typesets come from
# `claw_theme_emit p10k`; with 0 the pinned gruvbox block is restored byte for
# byte.
# F-10: nothing at a prompt said "something needs you". Pin: `⚑N` renders from
# $XDG_CACHE_HOME/claw/attention.count ("<n> <worst_tier>"), is hidden at 0 or
# when the file is absent, tiers to the palette colour, re-reads only when the
# mtime moves, and forks nothing — it runs on EVERY prompt.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  THEME="$REPO/scripts/utils/theme.sh"
  P10K="$REPO/shell/.p10k.zsh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export CLAW_NO_LOG=1
  export DOTFILES_DIR="$REPO"
  export TERM=xterm-256color
  mkdir -p "$HOME" "$XDG_CACHE_HOME/claw" "$XDG_STATE_HOME/claw"
  unset CLAW_THEME CLAW_THEME_SLUG CLAW_P10K_THEMED
  ATT="$XDG_CACHE_HOME/claw/attention.count"
}

# Run a zsh snippet in a virgin shell with a p10k stub, theme.sh and .p10k.zsh
# loaded. `zsh -f`: no user rc, so nothing but this repo is under test.
prompt_run() {  # prompt_run <snippet>
  cat > "$BATS_TEST_TMPDIR/run.zsh" <<ZSH
p10k() { print -r -- "p10k:\$*" }
source '$THEME'
source '$P10K'
$1
ZSH
  run zsh -f "$BATS_TEST_TMPDIR/run.zsh"
}

# --- (1) the file still parses ------------------------------------------------

@test "p10k: .p10k.zsh parses under zsh -n" {
  run zsh -n "$P10K"
  [ "$status" -eq 0 ]
}

# --- (2) themed palette vs the gruvbox fallback -------------------------------

@test "p10k: CLAW_P10K_THEMED=1 paints the dir block with the palette blue" {
  prompt_run 'print -r -- "dir=$POWERLEVEL9K_DIR_BACKGROUND fg=$POWERLEVEL9K_DIR_FOREGROUND"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"dir=#58a6ff fg=#0d1117"* ]]
}

@test "p10k: CLAW_P10K_THEMED=1 follows claw theme set (synthwave)" {
  printf 'synthwave\n' > "$XDG_STATE_HOME/claw/theme"
  blue="$(bash -c "source '$THEME'; printf %s \"\$CLAW_C_BLUE\"")"
  prompt_run 'print -r -- "dir=$POWERLEVEL9K_DIR_BACKGROUND"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"dir=#$blue"* ]]
}

@test "p10k: CLAW_P10K_THEMED=0 restores the pinned gruvbox block" {
  export CLAW_P10K_THEMED=0
  prompt_run 'print -r -- "dir=$POWERLEVEL9K_DIR_BACKGROUND vcs=$POWERLEVEL9K_VCS_CLEAN_BACKGROUND ok=$POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_FOREGROUND"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"dir=#7daea3"* ]]
  [[ "$output" == *"vcs=#a9b665"* ]]
  [[ "$output" == *"ok=#a9b665"* ]]
}

@test "p10k: no theme engine in scope still yields the gruvbox block" {
  cat > "$BATS_TEST_TMPDIR/bare.zsh" <<ZSH
p10k() { print -r -- "p10k:\$*" }
source '$P10K'
print -r -- "dir=\$POWERLEVEL9K_DIR_BACKGROUND"
ZSH
  run zsh -f "$BATS_TEST_TMPDIR/bare.zsh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dir=#7daea3"* ]]
}

# --- (3) the ⚑ segment --------------------------------------------------------

@test "p10k: claw_attention sits immediately after status in the left prompt" {
  prompt_run 'print -r -- "${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[*]}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"status claw_attention"* ]]
}

@test "p10k: attention.count '2 crit' renders ⚑ 2 in the palette red" {
  printf '2 crit\n' > "$ATT"
  prompt_run 'prompt_claw_attention'
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚑ 2"* ]]
  [[ "$output" == *"#ff7b72"* ]]
}

@test "p10k: tier colours map warn→amber and info/ok→blue" {
  printf '3 warn\n' > "$ATT"
  prompt_run 'prompt_claw_attention'
  [[ "$output" == *"⚑ 3"* ]]
  [[ "$output" == *"#e3b341"* ]]
  printf '1 info\n' > "$ATT"
  prompt_run 'prompt_claw_attention'
  [[ "$output" == *"⚑ 1"* ]]
  [[ "$output" == *"#58a6ff"* ]]
}

@test "p10k: attention is hidden at 0 and when the file is absent" {
  printf '0 ok\n' > "$ATT"
  prompt_run 'prompt_claw_attention; print -r -- "END"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"⚑"* ]]
  [[ "$output" == *"END"* ]]
  rm -f "$ATT"
  prompt_run 'prompt_claw_attention; print -r -- "END"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"⚑"* ]]
  [[ "$output" == *"END"* ]]
}

@test "p10k: a garbage attention.count renders nothing and does not error" {
  printf 'not-a-number\n' > "$ATT"
  prompt_run 'prompt_claw_attention; print -r -- "END"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"⚑"* ]]
  [[ "$output" == *"END"* ]]
}

@test "p10k: the count is re-read when the mtime moves" {
  printf '1 info\n' > "$ATT"
  prompt_run 'prompt_claw_attention
    print "4 crit" > "$XDG_CACHE_HOME/claw/attention.count"
    touch -t 203001010101 "$XDG_CACHE_HOME/claw/attention.count"
    prompt_claw_attention'
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚑ 1"* ]]
  [[ "$output" == *"⚑ 4"* ]]
}

# --- (4) it runs on EVERY prompt — it must not fork ---------------------------

@test "p10k: prompt_claw_attention forks nothing under zsh xtrace" {
  printf '2 crit\n' > "$ATT"
  prompt_run 'set -x; prompt_claw_attention'
  [ "$status" -eq 0 ]
  # match the traced COMMAND WORD, not the whole line: `zmodload -F zsh/stat`
  # is a builtin and must not read as a fork.
  n="$(printf '%s\n' "$output" | grep -acE '^\+[^:]*:[0-9]+> (cat|cut|tr|head|sed|awk|stat|date|wc|grep|ls|basename)\b' || true)"
  [ "${n:-0}" -eq 0 ]
  # and the segment really ran
  [[ "$output" == *"prompt_claw_attention:"* ]]
}
