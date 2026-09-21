#!/usr/bin/env bats
# Login-path integration tests driven through a real pty
# (tests/fixtures/pty_login.py forks `zsh -i` against a generated rc that
# sources the repo's shell/.zshrc inside a hermetic HOME).
#
# audit 2026-09-20 F-01/F-25: Ctrl-C during the step-3 dashboard render killed
# .zshrc mid-file. The shell survived, but steps 4-8 never ran — no aliases, no
# claw(), no p10k — a login that looks crashed. Pinned here: an rc-scoped
# `trap ':' INT` (step 1) released by `trap - INT` on the last line, so an
# interrupt costs you the render and nothing else, and the interactive shell
# is handed back with the DEFAULT INT disposition.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HARNESS="$BATS_TEST_DIRNAME/fixtures/pty_login.py"
  # Real oh-my-zsh checkout (if any) resolved BEFORE HOME is redirected.
  REAL_OMZ="${ZSH:-$HOME/.oh-my-zsh}"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/share"
  export CLAW_NO_LOG=1
  mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
}

# Skip whole-file when the harness cannot run here (CI without python3/pty).
require_pty() {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  command -v zsh     >/dev/null 2>&1 || skip "zsh not available"
  python3 -c 'import pty, termios, fcntl' 2>/dev/null || skip "pty/termios unavailable"
}

# login <run-dir> [extra pty_login.py args...]
# Always probes the two "did the rc finish?" symbols plus the live INT trap
# count (`command grep`: aliases.zsh maps bare grep to rg).
login() {
  local dir="$BATS_TEST_TMPDIR/$1"; shift
  mkdir -p "$dir"
  local -a omz=()
  [ -f "$REAL_OMZ/oh-my-zsh.sh" ] && omz=(--omz "$REAL_OMZ")
  run python3 "$HARNESS" --repo "$REPO" --zdotdir "$dir" "${omz[@]}" \
      --timeout 45 \
      --probe 'print "PROBE_ALIAS=$(alias ll >/dev/null 2>&1 && echo yes || echo no)"' \
      --probe 'print "PROBE_CLAW=$(typeset -f claw >/dev/null 2>&1 && echo yes || echo no)"' \
      --probe 'print "PROBE_INTTRAP=$(trap | command grep -c INT)"' \
      "$@"
}

# --- (a) interrupted login --------------------------------------------------

@test "login: Ctrl-C at 300ms leaves the shell fully initialised" {
  require_pty
  login int300 --send-int-at 300
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"__PROMPT__"* ]]
  [[ "$output" == *"PROBE_ALIAS=yes"* ]]
  [[ "$output" == *"PROBE_CLAW=yes"* ]]
}

# --- (b) control run --------------------------------------------------------

@test "login: uninterrupted login reaches the same state" {
  require_pty
  login control
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"__PROMPT__"* ]]
  [[ "$output" == *"PROBE_ALIAS=yes"* ]]
  [[ "$output" == *"PROBE_CLAW=yes"* ]]
}

# --- (c) the guard is rc-scoped, not leaked ---------------------------------

@test "login: no INT trap survives into the interactive shell" {
  require_pty
  login trapscope
  echo "$output"
  [ "$status" -eq 0 ]
  # `trap` with no args lists live handlers; INT must not be among them.
  [[ "$output" == *"PROBE_INTTRAP=0"* ]]
}

@test "login: Ctrl-C at 300ms also leaves no INT trap behind" {
  require_pty
  login int300trap --send-int-at 300
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROBE_INTTRAP=0"* ]]
}

# --- static contract on the rc itself (runs everywhere, no pty needed) ------

@test "zshrc: arms 'trap : INT' in step 1 and releases it on the last line" {
  local rc="$REPO/shell/.zshrc"
  run grep -n "^trap ':' INT$" "$rc"
  echo "$output"
  [ "$status" -eq 0 ]
  # release must be the last non-empty line of the file
  run bash -c "grep -v '^[[:space:]]*\$' '$rc' | tail -n 1"
  echo "$output"
  [ "$output" = "trap - INT" ]
}

@test "zshrc: parses under zsh -n" {
  run zsh -n "$REPO/shell/.zshrc"
  echo "$output"
  [ "$status" -eq 0 ]
}

# ============================================================================
# F-22 — three oh-my-zsh plugins dropped from the login path.
# istioctl and operator-sdk each run `<tool> completion zsh` in a subshell on
# EVERY shell start; emoji sources a 314 KB definitions file. Measured on an
# M4 mac (hyperfine, 25 runs): 227.8ms -> 161.9ms. CLAW_OMZ_EXTRA_PLUGINS is
# the documented escape hatch for anyone who wants one of them back.
# ============================================================================

@test "zshrc: istioctl, operator-sdk and emoji are not in the plugins array" {
  # Scoped to the array literal so the explanatory comment naming them
  # (and the CLAW_OMZ_EXTRA_PLUGINS example) cannot mask a regression.
  run awk '/^    plugins=\(/,/^    \)/' "$REPO/shell/.zshrc"
  echo "$output"
  [ -n "$output" ]
  [[ "$output" != *istioctl* ]]
  [[ "$output" != *operator-sdk* ]]
  [[ "$output" != *emoji* ]]
  # sanity: the array really was captured
  [[ "$output" == *kubectl* ]]
}

@test "zshrc: CLAW_OMZ_EXTRA_PLUGINS is appended to plugins" {
  run grep -n 'plugins+=("${CLAW_OMZ_EXTRA_PLUGINS\[@\]}")' "$REPO/shell/.zshrc"
  echo "$output"
  [ "$status" -eq 0 ]
}

# Hermetic: runs the real array+append snippet under `zsh -f` with a stub
# oh-my-zsh, so no plugin is ever sourced and nothing outside tmp is touched.
@test "zshrc: CLAW_OMZ_EXTRA_PLUGINS re-adds a dropped plugin" {
  local snippet="$BATS_TEST_TMPDIR/plugins.zsh"
  awk '/^    plugins=\(/,/CLAW_OMZ_EXTRA_PLUGINS\[@\]/' "$REPO/shell/.zshrc" > "$snippet"
  [ -s "$snippet" ]

  # unset -> array unchanged, and no empty element leaks in
  run zsh -f -c "source '$snippet'; print -r -- \"n=\${#plugins[@]} has=\${plugins[(I)istioctl]}\""
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has=0"* ]]
  local before="$output"

  # set -> the named plugins are appended, in order, at the end
  run zsh -f -c "CLAW_OMZ_EXTRA_PLUGINS=(istioctl operator-sdk); source '$snippet'; print -r -- \"last2=\${plugins[-2,-1]} has=\${plugins[(I)istioctl]}\""
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"last2=istioctl operator-sdk"* ]]
  [[ "$output" != *"has=0"* ]]
  echo "unset-case was: $before"
}

# Never fails — a printed number, so a regression is visible in CI logs
# without making the suite flaky on a loaded runner.
@test "zshrc: perf smoke — interactive startup wall time (informational)" {
  require_pty
  command -v zsh >/dev/null 2>&1 || skip "zsh not available"
  local dir="$BATS_TEST_TMPDIR/perf"
  mkdir -p "$dir"
  local -a omz=()
  [ -f "$REAL_OMZ/oh-my-zsh.sh" ] && omz=(--omz "$REAL_OMZ")
  python3 "$BATS_TEST_DIRNAME/fixtures/pty_login.py" --setup-only \
      --repo "$REPO" --zdotdir "$dir" "${omz[@]}" > "$dir/env" || skip "harness setup failed"

  local t0 t1
  # zsh's EPOCHREALTIME avoids date(1)'s 1s granularity on BSD.
  # One warmup first: the very first shell pays for a cold compinit dump,
  # which would dominate (and mislead) the reported number.
  ( set -a; . "$dir/env"; set +a; export CLAW_ACTIVE_PROFILE=default CLAW_NO_LOG=1
    zsh -ic exit >/dev/null 2>&1 ) || true
  t0=$(zsh -fc 'zmodload zsh/datetime; print $EPOCHREALTIME')
  ( set -a; . "$dir/env"; set +a; export CLAW_ACTIVE_PROFILE=default CLAW_NO_LOG=1
    for _ in 1 2 3; do zsh -ic exit >/dev/null 2>&1; done ) || true
  t1=$(zsh -fc 'zmodload zsh/datetime; print $EPOCHREALTIME')

  echo "# perf-smoke: 3x 'zsh -ic exit' = $(zsh -fc "printf '%.0f' \$(( ($t1 - $t0) * 1000 ))")ms total" >&3
  true
}

# ============================================================================
# T1-07a — shell/claw-login.zsh: the DECIDE half of the login.
#
# audit F-02/F-03/F-16/F-21: the old step-3 block asked a question whose answer
# is known 91% of the time and rendered for the 85% of shells that are agents
# and IDE panels. claw_login only DECIDES (mode, profile, theme, group) and
# registers a precmd hook; nothing renders until the shell is complete.
#
# These cases are pure `zsh -f` — no pty, no fzf, no forks of repo scripts.
# ============================================================================

# zl '<zsh code>' — run CODE under `zsh -f` with shell/claw-login.zsh sourced
# and every actor-detection variable cleared first (bats itself runs under
# Claude Code, so CLAUDECODE would otherwise flip the agent gate).
zl() {
  run zsh -f -c "$ZL_PRE
$1"
}

zl_pre() {
  ZL_PRE="unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT TERM_PROGRAM SSH_TTY SSH_CONNECTION \
VTE_VERSION KITTY_WINDOW_ID CLAW_ACTOR CLAW_LOGIN_TERMS CLAW_ACTIVE_PROFILE \
CLAW_LOGIN_PROFILE CLAW_THEME CLAW_ACTIVE_GROUP CLAW_LOGIN_CARD CLAW_LOGIN_RENDER \
CLAW_SESSION_SEQ NO_COLOR 2>/dev/null
export DOTFILES_DIR='$REPO' TERM=xterm-256color
source '$REPO/shell/claw-login.zsh' || exit 9"
}

@test "claw-login: parses under zsh -n" {
  run zsh -n "$REPO/shell/claw-login.zsh"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "claw-login: actor table" {
  zl_pre
  # 1. nothing identifying at all
  zl '_claw_actor; print $REPLY'; echo "$output"; [ "$output" = unknown ]
  # 2-3. Claude Code, either marker
  zl 'CLAUDECODE=1; _claw_actor; print $REPLY'; [ "$output" = agent ]
  zl 'CLAUDE_CODE_ENTRYPOINT=cli; _claw_actor; print $REPLY'; [ "$output" = agent ]
  # 4-5. IDE panels
  zl 'TERM_PROGRAM=vscode; _claw_actor; print $REPLY'; [ "$output" = ide ]
  zl 'TERM_PROGRAM=JetBrains-JediTerm; _claw_actor; print $REPLY'; [ "$output" = ide ]
  # 6. ssh
  zl 'SSH_TTY=/dev/ttys004; _claw_actor; print $REPLY'; [ "$output" = ssh ]
  zl 'SSH_CONNECTION="10.0.0.1 1 10.0.0.2 22"; _claw_actor; print $REPLY'; [ "$output" = ssh ]
  # 7-9. human terminals
  zl 'TERM_PROGRAM=Apple_Terminal; _claw_actor; print $REPLY'; [ "$output" = human ]
  zl 'TERM_PROGRAM=ghostty; _claw_actor; print $REPLY'; [ "$output" = human ]
  zl 'VTE_VERSION=6003; _claw_actor; print $REPLY'; [ "$output" = human ]
  zl 'KITTY_WINDOW_ID=1; _claw_actor; print $REPLY'; [ "$output" = human ]
  # 10. CLAW_LOGIN_TERMS extends the allow-list
  zl 'CLAW_LOGIN_TERMS="Hyper Tabby"; TERM_PROGRAM=Tabby; _claw_actor; print $REPLY'
  [ "$output" = human ]
  # 11. CLAW_ACTOR overrides everything
  zl 'CLAW_ACTOR=human; CLAUDECODE=1; _claw_actor; print $REPLY'; [ "$output" = human ]
  # 12. agent wins over a human terminal (Claude Desktop runs in a real pty)
  zl 'CLAUDECODE=1; TERM_PROGRAM=Apple_Terminal; _claw_actor; print $REPLY'
  [ "$output" = agent ]
}

@test "claw-login: mode is nested when a profile is already active" {
  zl_pre
  zl 'CLAW_ACTIVE_PROFILE=cloud; TERM_PROGRAM=Apple_Terminal; _claw_login_mode; print $REPLY'
  echo "$output"; [ "$output" = nested ]
  zl 'TERM_PROGRAM=Apple_Terminal; _claw_login_mode; print $REPLY'
  [ "$output" = human ]
}

@test "claw-login: nested sets _CLAW_FRESH_LOGIN=0 and registers no hook" {
  zl_pre
  zl 'CLAW_LOGIN_FORCE_TTY=1 CLAW_ACTIVE_PROFILE=cloud claw_login
      print "fresh=${_CLAW_FRESH_LOGIN}"
      print "hook=$(( ${precmd_functions[(I)_claw_login_render]:-0} ))"'
  echo "$output"
  [[ "$output" == *"fresh=0"* ]]
  [[ "$output" == *"hook=0"* ]]
}

@test "claw-login: human mode exports the profile and registers the hook" {
  zl_pre
  zl 'CLAW_LOGIN_FORCE_TTY=1 TERM_PROGRAM=Apple_Terminal claw_login
      print "p=$CLAW_ACTIVE_PROFILE mode=$_CLAW_LOGIN_MODE fresh=$_CLAW_FRESH_LOGIN"
      print "hook=$(( ${precmd_functions[(I)_claw_login_render]:-0} > 0 ))"'
  echo "$output"
  [[ "$output" == *"p=default mode=human fresh=1"* ]]
  [[ "$output" == *"hook=1"* ]]
}

@test "claw-login: agent mode exports the profile, registers no hook, logs one row" {
  zl_pre
  zl "unset CLAW_NO_LOG
      CLAW_LOGIN_FORCE_TTY=1 CLAUDECODE=1 claw_login
      print \"p=\$CLAW_ACTIVE_PROFILE mode=\$_CLAW_LOGIN_MODE\"
      print \"hook=\$(( \${precmd_functions[(I)_claw_login_render]:-0} ))\""
  echo "$output"
  [[ "$output" == *"p=default mode=agent"* ]]
  [[ "$output" == *"hook=0"* ]]
  local log="$XDG_CACHE_HOME/claw/usage.tsv"
  [ -f "$log" ]
  echo "--- $(cat "$log")"
  [ "$(wc -l < "$log")" -eq 1 ]
  grep -q 'tui:login:agent:default' "$log"
  grep -q 'actor=agent' "$log"
}

@test "claw-login: CLAW_NO_LOG=1 writes nothing" {
  zl_pre
  zl 'CLAW_LOGIN_FORCE_TTY=1 CLAUDECODE=1 CLAW_NO_LOG=1 claw_login; print done'
  echo "$output"
  [ ! -f "$XDG_CACHE_HOME/claw/usage.tsv" ]
}

@test "claw-login: pinned profile resolves, unknown one falls back to default" {
  zl_pre
  mkdir -p "$XDG_CONFIG_HOME/claw"
  printf 'security\n' > "$XDG_CONFIG_HOME/claw/login-profile"
  zl 'CLAW_LOGIN_FORCE_TTY=1 TERM_PROGRAM=Apple_Terminal claw_login; print "p=$CLAW_ACTIVE_PROFILE"'
  echo "$output"; [[ "$output" == *"p=security"* ]]

  # CLAW_LOGIN_PROFILE beats the pin file
  zl 'CLAW_LOGIN_FORCE_TTY=1 CLAW_LOGIN_PROFILE=cloud TERM_PROGRAM=Apple_Terminal claw_login; print "p=$CLAW_ACTIVE_PROFILE"'
  [[ "$output" == *"p=cloud"* ]]

  # a profile with no shell/profiles/<p>.zsh is not a profile
  printf 'nosuchprofile\n' > "$XDG_CONFIG_HOME/claw/login-profile"
  zl 'CLAW_LOGIN_FORCE_TTY=1 TERM_PROGRAM=Apple_Terminal claw_login; print "p=$CLAW_ACTIVE_PROFILE"'
  echo "$output"; [[ "$output" == *"p=default"* ]]
}

@test "claw-login: CLAW_THEME follows PROFILE_THEME_DEFAULT, stays unset for default" {
  zl_pre
  zl 'CLAW_LOGIN_FORCE_TTY=1 CLAW_LOGIN_PROFILE=security TERM_PROGRAM=Apple_Terminal claw_login
      print "theme=${CLAW_THEME-UNSET} group=$CLAW_ACTIVE_GROUP"'
  echo "$output"
  [[ "$output" == *"theme=matrix"* ]]
  [[ "$output" == *"group=domain"* ]]
  # F-14: default/local/claude declare PROFILE_THEME_DEFAULT="" and inherit the
  # persisted slug — claw_login must not export an empty CLAW_THEME over it.
  zl 'CLAW_LOGIN_FORCE_TTY=1 TERM_PROGRAM=Apple_Terminal claw_login
      print "theme=${CLAW_THEME-UNSET} group=$CLAW_ACTIVE_GROUP"'
  echo "$output"
  [[ "$output" == *"theme=UNSET"* ]]
  [[ "$output" == *"group=core"* ]]
}

@test "claw-login: _claw_meta_field strips a trailing comment" {
  zl_pre
  zl '_claw_meta_field security PROFILE_HELP_CMD; print "[$REPLY]"'
  echo "$output"; [ "$output" = "[sec-help]" ]
  zl '_claw_meta_field default PROFILE_THEME_DEFAULT; print "[$REPLY]"'
  [ "$output" = "[]" ]
  zl '_claw_meta_field security PROFILE_START_DIR; print "[$REPLY]"'
  # values are RAW and unexpanded — the @token grammar belongs to _claw_profile_cd
  [[ "$output" == *'|@vault-folder]'* ]]
  zl '_claw_meta_field default PROFILE_NOPE; print "[$REPLY]"'
  [ "$output" = "[]" ]
}

@test "claw-login: the decide half runs without forking" {
  zl_pre
  # `set -x` traces every command; a fork shows up as a `+(anon):N>` subshell
  # line or an external binary. Assert on the binaries the login path must not
  # spawn (date, mkdir, cat, sed, awk, grep) with logging disabled.
  run zsh -f -c "$ZL_PRE
    exec 2>'$BATS_TEST_TMPDIR/trace'
    set -x
    CLAW_LOGIN_FORCE_TTY=1 CLAW_NO_LOG=1 TERM_PROGRAM=Apple_Terminal claw_login
    set +x"
  echo "$output"
  local trace="$BATS_TEST_TMPDIR/trace"
  [ -f "$trace" ]
  run bash -c "command grep -E '^\+[^ ]* (/usr/bin/|/bin/)?(date|mkdir|cat|sed|awk|grep|tr|cut|basename|dirname|printf-)\b' '$trace'"
  echo "forks: $output"
  [ -z "$output" ]
}

@test "claw-login: non-interactive and dumb shells decide nothing" {
  zl_pre
  # no CLAW_LOGIN_FORCE_TTY -> the interactive/tty guards return first
  zl 'TERM_PROGRAM=Apple_Terminal claw_login; print "p=${CLAW_ACTIVE_PROFILE-UNSET} fresh=${_CLAW_FRESH_LOGIN-UNSET}"'
  echo "$output"
  [[ "$output" == *"p=UNSET fresh=UNSET"* ]]
  zl 'TERM=dumb CLAW_LOGIN_FORCE_TTY=1 TERM_PROGRAM=Apple_Terminal claw_login; print "p=${CLAW_ACTIVE_PROFILE-UNSET}"'
  echo "$output"
  [[ "$output" == *"p=UNSET"* ]]
}
