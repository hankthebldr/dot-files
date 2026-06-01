# shell/progress.zsh — live progress for long-running commands.
#
# Two layers, both opt-out via `progress off`:
#
#   1. PASSIVE (auto): preexec/precmd hooks update the terminal window
#      title with live elapsed time + truncated cmd, every 1s, for any
#      command running longer than $CLAW_PROGRESS_THRESHOLD. Does NOT
#      touch stdout/stderr — won't clobber tool output.
#
#   2. ACTIVE (opt-in): `claw_run <cmd>` wraps a command with a themed
#      gum spinner. Output is preserved; spinner runs on stderr.
#
#   3. COMPLETION BANNER: any command taking ≥ $CLAW_PROGRESS_BANNER_SEC
#      gets a styled one-liner after exit (duration, exit code, glyph).
#
# Toggle: `progress on`, `progress off`, `progress status`.
# Tune:   `export CLAW_PROGRESS_THRESHOLD=2`     # min seconds before title progress
#         `export CLAW_PROGRESS_BANNER_SEC=10`   # min seconds before completion banner
#         `export CLAW_PROGRESS_SKIP_RE='^(vim|nvim|less|man|ssh|tmux|htop|btop|top|hx)\b'`

: "${CLAW_PROGRESS_THRESHOLD:=2}"
: "${CLAW_PROGRESS_BANNER_SEC:=10}"
: "${CLAW_PROGRESS_SKIP_RE:='^(vim|nvim|less|more|man|ssh|tmux|screen|htop|btop|top|hx|helix|fzf|gum|nano|emacs)\b'}"
: "${CLAW_PROGRESS_ENABLED:=1}"

# ─── State ──────────────────────────────────────────────────────────────
typeset -g __claw_progress_pid=""
typeset -g __claw_progress_t0=0
typeset -g __claw_progress_cmd=""
typeset -g __claw_progress_skip=0

# ─── Helpers ────────────────────────────────────────────────────────────
__claw_progress_skip_cmd() {
  [[ "$1" =~ ${CLAW_PROGRESS_SKIP_RE} ]]
}

__claw_progress_set_title() {
  # OSC 0 sets window+icon title in most terminals (Ghostty, iTerm2,
  # Terminal.app, Alacritty, Wezterm, kitty, gnome-terminal, etc.)
  printf "\033]0;%s\007" "$1"
}

__claw_progress_reset_title() {
  # Restore to a sensible default: user@host:cwd
  local cwd="${PWD/#$HOME/~}"
  __claw_progress_set_title "${USER}@${HOST%%.*}: ${cwd}"
}

# ─── Session identity ───────────────────────────────────────────────────
# Stable per-shell label, resolved fresh on every repaint (no cache, no
# profile-switch hook needed — precmd already fires each prompt). Returns
# via REPLY (zsh's no-subshell scalar return) so the hook never forks.
#   tier 1: $CLAW_SESSION         (manual pin via `session <label>`)
#   tier 2: group/subprofile      (from the welcome-TUI pick)
#   tier 3: session-<N>           (auto sequence — the no-profile default)
__claw_session_resolve() {
  if   [[ -n "$CLAW_SESSION" ]];        then REPLY="$CLAW_SESSION"
  elif [[ -n "$CLAW_ACTIVE_PROFILE" ]]; then REPLY="${CLAW_ACTIVE_GROUP:+$CLAW_ACTIVE_GROUP/}$CLAW_ACTIVE_PROFILE"
  else REPLY="session-${CLAW_SESSION_SEQ:-0}"
  fi
}

# Glyphs (Nerd Font) with ANSI fallbacks
__claw_progress_glyph_ok="\033[38;5;78m✓\033[0m"      # green
__claw_progress_glyph_err="\033[38;5;203m✗\033[0m"    # red
__claw_progress_glyph_run="\033[38;5;215m⏳\033[0m"   # orange

# ─── Title-bar updater (background loop) ────────────────────────────────
__claw_progress_updater() {
  local pid="$1" cmd="$2" t0="$3"
  # Wait until threshold before painting anything
  sleep "$CLAW_PROGRESS_THRESHOLD"
  while kill -0 "$pid" 2>/dev/null; do
    local elapsed=$(( $(date +%s) - t0 ))
    local short="${cmd:0:60}"
    [[ ${#cmd} -gt 60 ]] && short="${short}…"
    __claw_progress_set_title "⏳ ${elapsed}s — ${short}"
    sleep 1
  done
}

# ─── Hooks ──────────────────────────────────────────────────────────────
__claw_progress_preexec() {
  (( CLAW_PROGRESS_ENABLED )) || return
  __claw_progress_cmd="$1"
  __claw_progress_t0=$(date +%s)
  __claw_progress_skip=0
  if __claw_progress_skip_cmd "$1"; then
    __claw_progress_skip=1
    return
  fi
  # Fork the title updater into the background, disowned
  ( __claw_progress_updater "$$" "$__claw_progress_cmd" "$__claw_progress_t0" ) &!
  __claw_progress_pid=$!
}

__claw_progress_precmd() {
  local exit_code=$?
  if [[ -n "$__claw_progress_pid" ]]; then
    kill "$__claw_progress_pid" 2>/dev/null
    __claw_progress_pid=""
  fi
  __claw_progress_reset_title

  # Completion banner for sufficiently-long commands (skipped editors etc.)
  if (( CLAW_PROGRESS_ENABLED )) && (( ! __claw_progress_skip )) && [[ -n "$__claw_progress_cmd" ]]; then
    local elapsed=$(( $(date +%s) - __claw_progress_t0 ))
    if (( elapsed >= CLAW_PROGRESS_BANNER_SEC )); then
      local glyph="$__claw_progress_glyph_ok"
      local exit_label="\033[38;5;245mexit 0\033[0m"
      if (( exit_code != 0 )); then
        glyph="$__claw_progress_glyph_err"
        exit_label="\033[38;5;203mexit ${exit_code}\033[0m"
      fi
      local short="${__claw_progress_cmd:0:50}"
      [[ ${#__claw_progress_cmd} -gt 50 ]] && short="${short}…"
      printf "  %b \033[38;5;245m%ds\033[0m  %b  \033[38;5;245m%s\033[0m\n" \
        "$glyph" "$elapsed" "$exit_label" "$short"
    fi
  fi
  __claw_progress_cmd=""
}

# Register only once
if (( ! ${+__claw_progress_registered} )); then
  autoload -U add-zsh-hook
  add-zsh-hook preexec __claw_progress_preexec
  add-zsh-hook precmd  __claw_progress_precmd
  typeset -g __claw_progress_registered=1
fi

# ─── User-facing toggle ─────────────────────────────────────────────────
progress() {
  case "${1:-status}" in
    on)
      CLAW_PROGRESS_ENABLED=1
      print "\033[38;5;78m✓\033[0m progress: \033[1mon\033[0m  (threshold ${CLAW_PROGRESS_THRESHOLD}s, banner ≥${CLAW_PROGRESS_BANNER_SEC}s)"
      ;;
    off)
      CLAW_PROGRESS_ENABLED=0
      [[ -n "$__claw_progress_pid" ]] && kill "$__claw_progress_pid" 2>/dev/null
      __claw_progress_reset_title
      print "\033[38;5;245m∅\033[0m progress: \033[1moff\033[0m"
      ;;
    status)
      local state="\033[38;5;78mon\033[0m"
      (( ! CLAW_PROGRESS_ENABLED )) && state="\033[38;5;245moff\033[0m"
      printf "progress %b  threshold=%ss  banner_at=%ss  skip=/%s/\n" \
        "$state" "$CLAW_PROGRESS_THRESHOLD" "$CLAW_PROGRESS_BANNER_SEC" "$CLAW_PROGRESS_SKIP_RE"
      ;;
    *)
      print "usage: progress {on|off|status}"
      return 1
      ;;
  esac
}

# ─── Active wrapper: claw_run <cmd...> ──────────────────────────────────
# Opt-in spinner (uses gum if present). Captures output to a tempfile so
# the spinner doesn't fight stdout. Prints output AFTER completion.
claw_run() {
  if (( $# == 0 )); then
    print "usage: claw_run <command> [args...]"
    return 1
  fi
  local label="$*"
  local out_file rc_file
  out_file=$(mktemp -t claw_run_out.XXXXXX)
  rc_file=$(mktemp -t claw_run_rc.XXXXXX)
  local t0=$(date +%s)
  local rc

  # Run the command in a subshell that writes its real exit code to rc_file.
  # This survives the gum-spin wrapper which would otherwise mask non-zero rc.
  if command -v gum >/dev/null 2>&1; then
    CLAW_OUT="$out_file" CLAW_RC="$rc_file" \
      gum spin --spinner dot --title "${label:0:60}" -- \
      zsh -c '"$@" > "$CLAW_OUT" 2>&1; print -n $? > "$CLAW_RC"' _ "$@" \
      >/dev/null 2>&1
  else
    print -n "\033[38;5;215m⏳\033[0m ${label:0:60} ..." >&2
    "$@" > "$out_file" 2>&1
    print -n $? > "$rc_file"
    print "\r\033[K" >&2
  fi

  rc=$(<"$rc_file")
  cat "$out_file"
  rm -f "$out_file" "$rc_file"
  local elapsed=$(( $(date +%s) - t0 ))
  local glyph="$__claw_progress_glyph_ok"
  local exit_color="\033[38;5;245m"
  if (( rc != 0 )); then
    glyph="$__claw_progress_glyph_err"
    exit_color="\033[38;5;203m"
  fi
  printf "  %b \033[38;5;245m%ds  ${exit_color}exit %d\033[0m\n" "$glyph" "$elapsed" "$rc"
  return $rc
}
