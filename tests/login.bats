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

# ============================================================================
# T1-07b — the render hook: strip, daily card, background kicks, OSC, one row.
#
# Everything here runs from the FIRST precmd, after the rc is complete
# (F-01), and only for the modes that have a human looking at them (F-02).
# ============================================================================

# Fake DOTFILES_DIR whose four login-time children are markers, plus a `python3`
# on PATH that records the card render instead of doing one.
render_env() {
  STUBD="$BATS_TEST_TMPDIR/dot"
  mkdir -p "$STUBD/scripts/utils" "$BATS_TEST_TMPDIR/bin" "$XDG_CACHE_HOME/claw"
  local s
  for s in situation.sh update-status.sh tool-updater.sh; do
    cat > "$STUBD/scripts/utils/$s" <<EOS
#!/usr/bin/env bash
printf '%s %s\n' "\$(basename "\$0")" "\$*" >> "$BATS_TEST_TMPDIR/probes.log"
exit 0
EOS
    chmod +x "$STUBD/scripts/utils/$s"
  done
  : > "$STUBD/scripts/utils/claw-dashboard.py"
  cat > "$BATS_TEST_TMPDIR/bin/python3" <<EOS
#!/usr/bin/env bash
printf 'python3 %s\n' "\$*" >> "$BATS_TEST_TMPDIR/dash.log"
echo "__CARD__"
exit 0
EOS
  chmod +x "$BATS_TEST_TMPDIR/bin/python3"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  ZL_RENDER="export DOTFILES_DIR='$STUBD'"
}

att() {
  mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/attention/attention.tsv" "$XDG_CACHE_HOME/claw/attention.tsv"
}

@test "strip: two items render two lines, an empty file renders nothing" {
  zl_pre
  att
  zl '_claw_attention_strip'
  echo "$output"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"tailscale down"* ]]
  [[ "$output" == *"tailscale up"* ]]
  [[ "$output" == *"gitea on ms-01"* ]]
  # since ≠ src_ts on the second row -> the clock is spelled out
  [[ "$output" == *"since "* ]]

  : > "$XDG_CACHE_HOME/claw/attention.tsv"
  zl '_claw_attention_strip; print -n END'
  [ "$output" = "END" ]

  rm -f "$XDG_CACHE_HOME/claw/attention.tsv"
  zl '_claw_attention_strip; print -n END'
  [ "$output" = "END" ]
}

@test "strip: caps at three lines and says how many it hid" {
  zl_pre
  att
  local f="$XDG_CACHE_HOME/claw/attention.tsv"
  printf 'warn\tbrew\tbrew ✗ locked\tclaw update --packages\t%s\t%s\n' "$(date +%s)" "$(date +%s)" >> "$f"
  printf 'warn\tload\tload 9.1 on 8 cores\tbtop\t%s\t%s\n' "$(date +%s)" "$(date +%s)" >> "$f"
  zl '_claw_attention_strip'
  echo "$output"
  [ "${#lines[@]}" -eq 4 ]
  [[ "$output" == *"+1 more · claw dash"* ]]
}

@test "strip: an info item with no next action is not worth a login line" {
  zl_pre
  mkdir -p "$XDG_CACHE_HOME/claw"
  local now; now="$(date +%s)"
  printf 'info\tquiet\tnothing to do here\t\t%s\t%s\n' "$now" "$now" \
      > "$XDG_CACHE_HOME/claw/attention.tsv"
  printf 'info\trepo\tdotfiles ↓3\tclaw update\t%s\t%s\n' "$now" "$now" \
      >> "$XDG_CACHE_HOME/claw/attention.tsv"
  zl '_claw_attention_strip'
  echo "$output"
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *"dotfiles"* ]]
  [[ "$output" != *"nothing to do here"* ]]
  # items counts every row, strip counts what was printed
  zl '_claw_attention_strip >/dev/null; print "items=$_CLAW_STRIP_ITEMS strip=$_CLAW_STRIP_LINES"'
  echo "$output"
  [ "$output" = "items=2 strip=1" ]
}

@test "strip: NO_COLOR swaps the dot for a tier mark and emits no escapes" {
  zl_pre
  att
  zl 'NO_COLOR=1 _claw_attention_strip'
  echo "$output"
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"! tailscale down"* ]]
  [[ "$output" == *"~ gitea on ms-01"* ]]
  run bash -c "printf '%s' \"\$1\" | command grep -c \$'\\033'" _ "$output"
  [ "$output" = "0" ]
}

@test "strip: ages read as Ns / Nm / Nh / Nd" {
  zl_pre
  mkdir -p "$XDG_CACHE_HOME/claw"
  local now; now="$(date +%s)"
  local f="$XDG_CACHE_HOME/claw/attention.tsv"
  printf 'crit\ta\tseconds ago\tfix\t%s\t%s\n' "$(( now - 12 ))"    "$(( now - 12 ))"    >  "$f"
  printf 'crit\tb\tminutes ago\tfix\t%s\t%s\n' "$(( now - 240 ))"   "$(( now - 240 ))"   >> "$f"
  printf 'crit\tc\thours ago\tfix\t%s\t%s\n'   "$(( now - 7200 ))"  "$(( now - 7200 ))"  >> "$f"
  zl 'NO_COLOR=1 _claw_attention_strip'
  echo "$output"
  # The age is computed at RENDER time, so the seconds bucket drifts by however
  # long the shell took to start — asserting exactly "(12s)" failed whenever the
  # machine was busy. Assert the FORMAT and a tolerant window instead; the
  # minute and hour buckets round and so stay stable.
  [[ "$output" =~ \(1[2-9]s\) ]]
  [[ "$output" == *"(4m)"* ]]
  [[ "$output" == *"(2h)"* ]]
}

@test "render: the hook disarms itself and hands back a clean INT trap" {
  zl_pre; render_env
  zl "$ZL_RENDER
      _CLAW_LOGIN_MODE=ide
      autoload -Uz add-zsh-hook; add-zsh-hook precmd _claw_login_render
      add-zsh-hook zshexit _claw_login_abort
      trap ':' INT
      _claw_login_render
      print \"precmd=\$(( \${precmd_functions[(I)_claw_login_render]:-0} ))\"
      print \"zshexit=\$(( \${zshexit_functions[(I)_claw_login_abort]:-0} ))\"
      print \"inttrap=\$(trap | command grep -c INT)\""
  echo "$output"
  [[ "$output" == *"precmd=0"* ]]
  [[ "$output" == *"zshexit=0"* ]]
  [[ "$output" == *"inttrap=0"* ]]
}

@test "render: CLAW_LOGIN_RENDER=0 prints nothing and probes nothing" {
  zl_pre; render_env; att
  zl "$ZL_RENDER
      _CLAW_LOGIN_MODE=human CLAW_LOGIN_RENDER=0 _claw_login_render
      print -n END"
  echo "$output"
  [ "$output" = "END" ]
  [ ! -f "$BATS_TEST_TMPDIR/probes.log" ]
  [ ! -f "$BATS_TEST_TMPDIR/dash.log" ]
}

@test "render: the daily card runs once a day" {
  zl_pre; render_env; att
  local stamp="$XDG_CACHE_HOME/claw/card.stamp"

  # yesterday -> rendered
  date -v-1d +%Y%m%d > "$stamp" 2>/dev/null || date -d yesterday +%Y%m%d > "$stamp"
  zl "$ZL_RENDER
      _CLAW_LOGIN_MODE=human TERM_PROGRAM=Apple_Terminal _claw_login_render"
  echo "$output"
  [[ "$output" == *"__CARD__"* ]]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/dash.log")" -eq 1 ]
  grep -q -- '--login' "$BATS_TEST_TMPDIR/dash.log"
  [ "$(cat "$stamp")" = "$(date +%Y%m%d)" ]

  # same day -> not rendered again
  zl "$ZL_RENDER
      _CLAW_LOGIN_MODE=human TERM_PROGRAM=Apple_Terminal _claw_login_render"
  echo "$output"
  [[ "$output" != *"__CARD__"* ]]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/dash.log")" -eq 1 ]

  # never / always
  zl "$ZL_RENDER
      _CLAW_LOGIN_MODE=human CLAW_LOGIN_CARD=always TERM_PROGRAM=Apple_Terminal _claw_login_render"
  [[ "$output" == *"__CARD__"* ]]
  rm -f "$stamp"
  zl "$ZL_RENDER
      _CLAW_LOGIN_MODE=human CLAW_LOGIN_CARD=never TERM_PROGRAM=Apple_Terminal _claw_login_render"
  [[ "$output" != *"__CARD__"* ]]
}

@test "render: four tabs opened at once render the card once" {
  zl_pre; render_env; att
  local stamp="$XDG_CACHE_HOME/claw/card.stamp"
  date -v-1d +%Y%m%d > "$stamp" 2>/dev/null || date -d yesterday +%Y%m%d > "$stamp"
  local snippet="$ZL_PRE
$ZL_RENDER
_CLAW_LOGIN_MODE=human TERM_PROGRAM=Apple_Terminal _claw_login_render"
  local i
  for i in 1 2 3 4; do zsh -f -c "$snippet" >/dev/null 2>&1 & done
  wait || true
  echo "dash.log: $(cat "$BATS_TEST_TMPDIR/dash.log" 2>/dev/null)"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/dash.log")" -eq 1 ]
}

@test "render: background kicks fire for human and ssh, never for ide or unknown" {
  zl_pre; render_env; att
  local m
  for m in human ssh; do
    rm -f "$BATS_TEST_TMPDIR/probes.log"
    zl "$ZL_RENDER
        _CLAW_LOGIN_MODE=$m CLAW_LOGIN_CARD=never _claw_login_render
        # The kicks are disowned, so they land asynchronously and NOT in order.
        # Waiting for the log to be merely non-empty then sleeping a fixed 0.3 s
        # raced the remaining three under load (~1 run in 4). Wait for all four
        # markers, with a deadline so a genuine regression still fails fast.
        _n=0
        while (( _n < 60 )); do
          if grep -q 'situation.sh homelab' \"$BATS_TEST_TMPDIR/probes.log\" 2>/dev/null &&
             grep -q 'situation.sh local'   \"$BATS_TEST_TMPDIR/probes.log\" 2>/dev/null &&
             grep -q 'update-status.sh --refresh' \"$BATS_TEST_TMPDIR/probes.log\" 2>/dev/null &&
             grep -q 'tool-updater.sh' \"$BATS_TEST_TMPDIR/probes.log\" 2>/dev/null; then
            break
          fi
          sleep 0.05; _n=\$(( _n + 1 ))
        done"
    echo "$m: $(cat "$BATS_TEST_TMPDIR/probes.log")"
    grep -q 'situation.sh homelab' "$BATS_TEST_TMPDIR/probes.log"
    grep -q 'situation.sh local' "$BATS_TEST_TMPDIR/probes.log"
    grep -q 'update-status.sh --refresh' "$BATS_TEST_TMPDIR/probes.log"
    grep -q 'tool-updater.sh' "$BATS_TEST_TMPDIR/probes.log"
  done
  for m in ide unknown; do
    rm -f "$BATS_TEST_TMPDIR/probes.log"
    zl "$ZL_RENDER
        _CLAW_LOGIN_MODE=$m _claw_login_render
        sleep 0.3"
    [ ! -f "$BATS_TEST_TMPDIR/probes.log" ]
  done
}

@test "render: one telemetry row carrying the whole login payload" {
  zl_pre; render_env; att
  zl "$ZL_RENDER
      unset CLAW_NO_LOG
      export CLAW_ACTIVE_PROFILE=cortex
      zmodload zsh/datetime
      _CLAW_LOGIN_T0=\$EPOCHREALTIME
      _CLAW_LOGIN_MODE=human CLAW_LOGIN_CARD=never TERM_PROGRAM=Apple_Terminal _claw_login_render
      sleep 0.3" >/dev/null
  local log="$XDG_CACHE_HOME/claw/usage.tsv"
  [ -f "$log" ]
  echo "$(cat "$log")"
  run grep -c 'tui:login:human:cortex' "$log"
  [ "$output" = "1" ]
  local row; row="$(grep 'tui:login:human:cortex' "$log")"
  [[ "$row" == *"term=Apple_Terminal"* ]]
  [[ "$row" == *"actor=human"* ]]
  [[ "$row" == *"shell=0"* ]]
  [[ "$row" == *"ms="* ]]
  [[ "$row" == *"items=2"* ]]
  [[ "$row" == *"strip=2"* ]]
  [[ "$row" == *"card=0"* ]]
  # 5 columns: the 4-column readers (bin/claw stats) still parse it
  [ "$(awk -F'\t' '/tui:login:human:cortex/ {print NF}' "$log")" = "5" ]
}

# ============================================================================
# T1-07c — the whole login path, end to end, through a real pty.
#
# .zshrc step 2b decides; the first precmd renders. These cases pin the
# behaviours the audit found broken: F-01 (interrupt), F-02 (agents render
# nothing), F-03 (no question at login), F-06 (typed-ahead survives),
# F-20 (no fzf on the path), F-21 (nested shells keep their cwd).
# ============================================================================

# Seed the harness's hermetic HOME before the run: two attention items and a
# card stamp from yesterday, so a human login has something to say and a card
# to draw.
seed_home() {
  local h="$BATS_TEST_TMPDIR/$1/home"
  mkdir -p "$h/.cache/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/attention/attention.tsv" "$h/.cache/claw/attention.tsv"
  date -v-1d +%Y%m%d > "$h/.cache/claw/card.stamp" 2>/dev/null || \
    date -d yesterday +%Y%m%d > "$h/.cache/claw/card.stamp"
}

@test "zshrc: step 2b sources claw-login and the welcome-TUI block is gone" {
  local rc="$REPO/shell/.zshrc"
  run grep -n 'source "$DOTFILES_DIR/shell/claw-login.zsh"' "$rc"
  echo "$output"; [ "$status" -eq 0 ]
  run grep -c 'claw_welcome_tui' "$rc"
  [ "$output" = "0" ]
  # claw_login must be decided before the theme engine reads CLAW_THEME
  local a b
  a="$(grep -n 'shell/claw-login.zsh' "$rc" | head -1 | cut -d: -f1)"
  b="$(grep -n 'scripts/utils/theme.sh' "$rc" | head -1 | cut -d: -f1)"
  echo "claw-login@$a theme@$b"
  [ "$a" -lt "$b" ]
}

@test "zshrc: the start-dir applier is gated on a fresh login" {
  run grep -n '_CLAW_FRESH_LOGIN:-0' "$REPO/shell/.zshrc"
  echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" == *"_claw_profile_cd"* ]]
}

@test "login(pty): an agent shell renders nothing and probes nothing" {
  require_pty
  seed_home agent
  login agent --dash-sleep-ms 50 --env CLAUDECODE=1 \
    --probe 'print "PROBE_MODE=${_CLAW_LOGIN_MODE:-none}"' \
    --probe 'print "PROBE_HOOK=$(( ${precmd_functions[(I)_claw_login_render]:-0} ))"' \
    --probe 'print "PROBE_P=$CLAW_ACTIVE_PROFILE"'
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROBE_MODE=agent"* ]]
  [[ "$output" == *"PROBE_HOOK=0"* ]]
  [[ "$output" == *"PROBE_P=default"* ]]
  # nothing from the attention file, no card, no background probes, no picker
  [[ "$output" != *"tailscale down"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/agent/home/dash.log" ]
  [ ! -f "$BATS_TEST_TMPDIR/agent/home/probes.log" ]
  [ ! -f "$BATS_TEST_TMPDIR/agent/home/fzf.log" ]
  # the shell itself is still fully built
  [[ "$output" == *"PROBE_CLAW=yes"* ]]
}

@test "login(pty): a human tab gets the strip, then the card once a day" {
  require_pty
  seed_home human
  login human --dash-sleep-ms 50 --env TERM_PROGRAM=Apple_Terminal \
    --probe 'print "PROBE_MODE=$_CLAW_LOGIN_MODE"'
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROBE_MODE=human"* ]]
  [[ "$output" == *"tailscale down"* ]]
  [[ "$output" == *"gitea on ms-01"* ]]
  [[ "$output" != *"more · claw dash"* ]]
  local h="$BATS_TEST_TMPDIR/human/home"
  echo "dash: $(cat "$h/dash.log")"
  [ "$(wc -l < "$h/dash.log")" -eq 1 ]
  grep -q -- '--login' "$h/dash.log"
  echo "probes: $(cat "$h/probes.log")"
  grep -q 'situation.sh homelab' "$h/probes.log"
  grep -q 'situation.sh local' "$h/probes.log"
  grep -q 'update-status.sh --refresh' "$h/probes.log"
  grep -q 'tool-updater.sh' "$h/probes.log"
  [ ! -f "$h/fzf.log" ]

  # second login the same day: strip again, card not again
  login human --dash-sleep-ms 50 --env TERM_PROGRAM=Apple_Terminal
  echo "$output"
  [[ "$output" == *"tailscale down"* ]]
  [ "$(wc -l < "$h/dash.log")" -eq 1 ]
}

@test "login(pty): an unknown terminal gets the strip but no card" {
  require_pty
  seed_home unknownterm
  login unknownterm --dash-sleep-ms 50 \
    --probe 'print "PROBE_MODE=$_CLAW_LOGIN_MODE"'
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROBE_MODE=unknown"* ]]
  [[ "$output" == *"tailscale down"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/unknownterm/home/dash.log" ]
  [ ! -f "$BATS_TEST_TMPDIR/unknownterm/home/probes.log" ]
}

@test "login(pty): typed-ahead text runs as a command instead of being eaten" {
  require_pty
  seed_home typeahead
  # F-06: the old fzf menu read stdin during the rc, so this became a menu pick.
  login typeahead --dash-sleep-ms 50 --env TERM_PROGRAM=Apple_Terminal \
    --type 'cd /tmp
' --probe 'print "PROBE_PWD=$PWD"' --probe 'print "PROBE_P=$CLAW_ACTIVE_PROFILE"'
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROBE_PWD=/tmp"* ]]
  [[ "$output" == *"PROBE_P=default"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/typeahead/home/fzf.log" ]
}

@test "login(pty): a nested shell keeps its cwd (F-21)" {
  require_pty
  login nested --dash-sleep-ms 50 --env CLAW_ACTIVE_PROFILE=vault \
    --pre 'cd /tmp' \
    --probe 'print "PROBE_PWD=$PWD"' \
    --probe 'print "PROBE_FRESH=${_CLAW_FRESH_LOGIN:-unset}"' \
    --probe 'print "PROBE_NAME=${PROFILE_NAME:-unset}"'
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROBE_PWD=/tmp"* ]]
  [[ "$output" == *"PROBE_FRESH=0"* ]]
  # the profile is still sourced — only the relocation is skipped
  [[ "$output" == *"PROBE_NAME=vault"* ]]
  [[ "$output" != *"start dir missing"* ]]
}

@test "login(pty): a pinned profile is loaded without asking (F-03)" {
  require_pty
  login pinned --dash-sleep-ms 50 --env TERM_PROGRAM=Apple_Terminal \
    --env CLAW_LOGIN_PROFILE=security \
    --probe 'print "PROBE_P=$CLAW_ACTIVE_PROFILE"' \
    --probe 'print "PROBE_NAME=${PROFILE_NAME:-unset}"' \
    --probe 'print "PROBE_THEME=${CLAW_THEME:-unset}"' \
    --probe 'print "PROBE_GROUP=${CLAW_ACTIVE_GROUP:-unset}"' \
    --probe 'print "PROBE_HELP=$(typeset -f sec-help >/dev/null 2>&1 && echo yes || echo no)"'
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROBE_P=security"* ]]
  [[ "$output" == *"PROBE_NAME=security"* ]]
  [[ "$output" == *"PROBE_THEME=matrix"* ]]
  [[ "$output" == *"PROBE_GROUP=domain"* ]]
  [[ "$output" == *"PROBE_HELP=yes"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/pinned/home/fzf.log" ]
}

@test "login(pty): Ctrl-C at 50/200/500ms leaves the shell whole (F-01)" {
  require_pty
  local ms
  for ms in 50 200 500; do
    seed_home "int$ms"
    login "int$ms" --dash-sleep-ms 400 --env TERM_PROGRAM=Apple_Terminal \
      --env CLAW_NO_LOG=0 --send-int-at "$ms"
    echo "--- ${ms}ms: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"__PROMPT__"* ]]
    [[ "$output" == *"PROBE_ALIAS=yes"* ]]
    [[ "$output" == *"PROBE_CLAW=yes"* ]]
    [[ "$output" == *"PROBE_INTTRAP=0"* ]]
    # whatever the interrupt landed on, it is either survived or recorded
    local log="$BATS_TEST_TMPDIR/int$ms/home/.cache/claw/usage.tsv"
    if [ -f "$log" ] && grep -q 'tui:abort' "$log"; then
      run grep -oE 'tui:abort:(init|render)' "$log"
      echo "abort rows: $output"
      [ "$status" -eq 0 ]
    fi
  done
}

@test "render: an interrupt during the card is logged and returns 130" {
  zl_pre; render_env; att
  # Ctrl-C reaches the whole foreground group, so the stand-in card signals
  # the shell that spawned it exactly as a real interrupted python3 would.
  cat > "$BATS_TEST_TMPDIR/bin/python3" <<'EOS'
#!/usr/bin/env bash
kill -INT "$PPID"
sleep 1
EOS
  chmod +x "$BATS_TEST_TMPDIR/bin/python3"
  zl "$ZL_RENDER
      unset CLAW_NO_LOG
      _CLAW_LOGIN_MODE=human CLAW_LOGIN_CARD=always _claw_login_render
      print \"rc=\$?\""
  echo "$output"
  [[ "$output" == *"rc=130"* ]]
  grep -q 'tui:abort:render' "$XDG_CACHE_HOME/claw/usage.tsv"
  # the interrupt costs the render, not the shell: no login row, no kicks
  run grep -c 'tui:login' "$XDG_CACHE_HOME/claw/usage.tsv"
  [ "$output" = "0" ]
  [ ! -f "$BATS_TEST_TMPDIR/probes.log" ]
}

# audit F-02: "has a pty" is not "a human is here". delight.zsh's fact card and
# pkg nudge gated on `-t 1` alone, so every Claude Desktop / IDE pty printed
# them — the exact pollution the actor model exists to stop. They must consume
# _CLAW_LOGIN_MODE (set by claw_login) like every other login-path renderer.
@test "delight: fact card and pkg nudge are gated on the login actor, not the tty" {
  grep -qE '_CLAW_LOGIN_MODE|_claw_login_is_human' "$BATS_TEST_DIRNAME/../shell/delight.zsh"
  # both render blocks must carry the gate
  run bash -c "grep -cE '_CLAW_LOGIN_MODE|_claw_login_is_human' '$BATS_TEST_DIRNAME/../shell/delight.zsh'"
  [ "$output" -ge 2 ]
}

@test "delight: helper says agent/ide are not human, human/unknown/ssh render" {
  run zsh -fc '
    DOTFILES_DIR="'"$BATS_TEST_DIRNAME"'/.."
    source "$DOTFILES_DIR/shell/claw-login.zsh"
    for m in human unknown ssh agent ide nested; do
      _CLAW_LOGIN_MODE=$m
      _claw_login_is_human && print "$m=yes" || print "$m=no"
    done'
  [ "$status" -eq 0 ]
  [[ "$output" == *"human=yes"* ]]
  [[ "$output" == *"unknown=yes"* ]]
  [[ "$output" == *"ssh=yes"* ]]
  [[ "$output" == *"agent=no"* ]]
  [[ "$output" == *"ide=no"* ]]
  [[ "$output" == *"nested=no"* ]]
}
