#!/usr/bin/env bash
# claw-progress.sh — inline, phase-driven live status panel for long-running
# claw ops. Foreground, single-process (Phase 1). Sourced by call sites.
#   See docs/superpowers/specs/2026-06-20-claw-live-progress-panel-design.md
set -uo pipefail

_CLAW_PROG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CLAW_PROG_DIR/claw-output.sh" 2>/dev/null || true

# ── theme colors (consume exported CLAW_RGB_*; refined-dark fallbacks) ───────
_c() {  # _c <key> → ANSI truecolor from CLAW_RGB_<KEY>, else 256-color fallback
  local key up rgb
  key="$1"
  up="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  eval "rgb=\"\${CLAW_RGB_${up}:-}\""
  if [[ -n "$rgb" ]]; then printf '\033[38;2;%sm' "$rgb"; return; fi
  case "$key" in
    blue)  printf '\033[38;5;75m'  ;; green) printf '\033[38;5;78m'  ;;
    red)   printf '\033[38;5;203m' ;; amber) printf '\033[38;5;215m' ;;
    muted) printf '\033[38;5;245m' ;; purple)printf '\033[38;5;141m' ;;
    *)     printf '' ;;
  esac
}
_creset() { printf '\033[0m'; }

_claw_cols() {
  if [[ -n "${COLUMNS:-}" ]]; then printf '%s' "$COLUMNS"; return; fi
  local c; c="$(tput cols 2>/dev/null)"; printf '%s' "${c:-80}"
}

_claw_unicode() {  # 0 = glyphs OK, 1 = ASCII fallback
  [[ "${TERM:-}" != dumb ]] || return 1
  [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *[Uu][Tt][Ff]* || -z "${LANG:-}" ]] || return 1
  return 0
}

_claw_glyph() {  # _claw_glyph <name>
  if _claw_unicode; then
    case "$1" in
      tl) printf '\xE2\x8C\x9C' ;; tr) printf '\xE2\x8C\x9D' ;;   # ⌜ ⌝
      bl) printf '\xE2\x8C\x9E' ;; br) printf '\xE2\x8C\x9F' ;;   # ⌞ ⌟
      bar_full) printf '\xE2\x96\x93' ;; bar_empty) printf '\xE2\x96\x91' ;; # ▓ ░
      ok) printf '\xE2\x9C\x93' ;; fail) printf '\xE2\x9C\x97' ;; # ✓ ✗
      skip) printf '\xC2\xB7' ;;  arrow) printf '\xE2\x96\xB8' ;; # · ▸
      run) printf '\xE2\x8F\xB3' ;;                               # ⏳
      div) printf '\xE2\x94\x80' ;;                               # ─
    esac
  else
    case "$1" in
      tl|tr|bl|br) printf '+' ;; bar_full) printf '#' ;; bar_empty) printf '.' ;;
      ok) printf 'OK' ;; fail) printf 'X' ;; skip) printf '-' ;;
      arrow) printf '>' ;; run) printf '*' ;; div) printf '-' ;;
    esac
  fi
}

# ── viewfinder frame primitive ──────────────────────────────────────────────
claw_frame_top() {
  local w; w="$(_claw_cols)"; local frame; frame="$(_claw_output_get frame)"
  if [[ "$frame" == none ]]; then
    printf '%s' "$(_c muted)"; local i; for ((i=0;i<w;i++)); do _claw_glyph div; done; _creset; printf '\n'; return
  fi
  local mid=$(( w - 2 )); (( mid < 0 )) && mid=0
  printf '%s%s%*s%s%s\n' "$(_c muted)" "$(_claw_glyph tl)" "$mid" "" "$(_claw_glyph tr)" "$(_creset)"
}
claw_frame_bottom() {
  local w; w="$(_claw_cols)"; local frame; frame="$(_claw_output_get frame)"
  if [[ "$frame" == none ]]; then
    printf '%s' "$(_c muted)"; local i; for ((i=0;i<w;i++)); do _claw_glyph div; done; _creset; printf '\n'; return
  fi
  local mid=$(( w - 2 )); (( mid < 0 )) && mid=0
  printf '%s%s%*s%s%s\n' "$(_c muted)" "$(_claw_glyph bl)" "$mid" "" "$(_claw_glyph br)" "$(_creset)"
}

claw_card() {  # claw_card <title>   (body on stdin)
  local title="$1"
  claw_frame_top
  printf '  %s%s%s\n' "$(_c purple)" "$title" "$(_creset)"
  local line; while IFS= read -r line; do printf '  %s\n' "$line"; done
  claw_frame_bottom
}

# ── progress engine (Phase 1: foreground, single-process) ───────────────────
_CLAW_PROG_OP=""; _CLAW_PROG_TOTAL=0; _CLAW_PROG_DONE=0
_CLAW_PROG_OK=0;  _CLAW_PROG_FAIL=0;  _CLAW_PROG_SKIP=0
_CLAW_PROG_ITEM=""; _CLAW_PROG_SRC=""; _CLAW_PROG_PHASE=""; _CLAW_PROG_NOTE=""
_CLAW_PROG_T0=0; _CLAW_PROG_MODE="plain"

_claw_prog_detect_mode() {
  local m; m="$(_claw_output_get mode)"
  case "$m" in plain) echo plain; return ;; rich) echo rich; return ;; esac
  if [[ -t 1 && "${CLAW_PROGRESS_ENABLED:-1}" != 0 && "${TERM:-}" != dumb && -z "${CI:-}" ]]; then
    echo rich
  else
    echo plain
  fi
}

_claw_dur() {  # _claw_dur <seconds> → "Ns" or "MmSSs"
  local s="$1"
  if (( s < 60 )); then printf '%ds' "$s"; else printf '%dm%02ds' $(( s/60 )) $(( s%60 )); fi
}

claw_prog_begin() {
  _CLAW_PROG_OP="$1"; _CLAW_PROG_TOTAL="${2:-0}"
  _CLAW_PROG_DONE=0; _CLAW_PROG_OK=0; _CLAW_PROG_FAIL=0; _CLAW_PROG_SKIP=0
  _CLAW_PROG_ITEM=""; _CLAW_PROG_SRC=""; _CLAW_PROG_PHASE=""; _CLAW_PROG_NOTE=""
  _CLAW_PROG_T0="$(date +%s)"
  _CLAW_PROG_MODE="$(_claw_prog_detect_mode)"
  if [[ "$_CLAW_PROG_MODE" == plain ]]; then
    if (( _CLAW_PROG_TOTAL > 0 )); then
      printf '%s%s (%d)%s\n' "$(_c blue)" "$_CLAW_PROG_OP" "$_CLAW_PROG_TOTAL" "$(_creset)"
    else
      printf '%s%s%s\n' "$(_c blue)" "$_CLAW_PROG_OP" "$(_creset)"
    fi
  fi
  [[ "$_CLAW_PROG_MODE" == rich ]] && _claw_prog_begin_rich
}

claw_prog_item()  { _CLAW_PROG_ITEM="$1"; _CLAW_PROG_SRC="${2:-}"; _CLAW_PROG_PHASE=""; _CLAW_PROG_NOTE=""; _claw_prog_repaint; }
claw_prog_phase() { _CLAW_PROG_PHASE="$1"; _claw_prog_repaint; }
claw_prog_note()  { _CLAW_PROG_NOTE="$1"; _claw_prog_repaint; }

# A finalize helper: glyph, color, tally var name.
_claw_prog_finalize() {  # _claw_prog_finalize <glyph-name> <color> <msg>
  _CLAW_PROG_DONE=$(( _CLAW_PROG_DONE + 1 ))
  local line; line="$(printf '  %s%s%s %s%s' "$2" "$(_claw_glyph "$1")" "$(_creset)" "$_CLAW_PROG_ITEM" "${3:+ ${3}}")"
  _claw_prog_scrollback "$line"
}
claw_prog_ok()   { _CLAW_PROG_OK=$((   _CLAW_PROG_OK+1   )); _claw_prog_finalize ok   "$(_c green)" "${1:-}"; }
claw_prog_fail() { _CLAW_PROG_FAIL=$(( _CLAW_PROG_FAIL+1 )); _claw_prog_finalize fail "$(_c red)"   "${1:-}"; }
claw_prog_skip() { _CLAW_PROG_SKIP=$(( _CLAW_PROG_SKIP+1 )); _claw_prog_finalize skip "$(_c muted)" "${1:-}"; }

claw_prog_end() {
  local dur; dur="$(_claw_dur $(( $(date +%s) - _CLAW_PROG_T0 )))"
  local summary; summary="$(printf '%s%s%d%s %s%s%d%s %s%s%d%s %s· %s%s' \
    "$(_c green)" "$(_claw_glyph ok)"   "$_CLAW_PROG_OK"   "$(_creset)" \
    "$(_c red)"   "$(_claw_glyph fail)" "$_CLAW_PROG_FAIL" "$(_creset)" \
    "$(_c muted)" "$(_claw_glyph skip)" "$_CLAW_PROG_SKIP" "$(_creset)" \
    "$(_c muted)" "$dur" "$(_creset)")"
  _claw_prog_teardown    # rich teardown (added Task 5; no-op in plain)
  printf '  summary: %s\n' "$summary"
}

# ── rich-mode pinned panel (Task 5) ─────────────────────────────────────────
_CLAW_PANEL_H=4
_CLAW_PANEL_DRAWN=0
_CLAW_SPIN_FRAMES='|/-\'
_CLAW_SPIN_I=0

_claw_logfile() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/claw/logs"
  mkdir -p "$d" 2>/dev/null || true
  printf '%s/%s-%s.log' "$d" "${_CLAW_PROG_OP:-op}" "${_CLAW_PROG_T0:-0}"
}

# Build the bar string: <full×k><empty×(width-k)>.
_claw_prog_bar() {
  local width=14 k=0
  if (( _CLAW_PROG_TOTAL > 0 )); then
    k=$(( _CLAW_PROG_DONE * width / _CLAW_PROG_TOTAL ))
    (( k > width )) && k=$width
  fi
  local i out=""
  for ((i=0;i<k;i++));      do out+="$(_claw_glyph bar_full)";  done
  for ((i=k;i<width;i++));  do out+="$(_claw_glyph bar_empty)"; done
  printf '%s' "$out"
}

# Print the 4 panel lines (no cursor moves; caller positions the cursor).
# Bar line: "  <op>  <bar>  <count> <dur> · ✓<ok> ✗<fail> ·<skip>"
_claw_panel_render() {
  local dur; dur="$(_claw_dur $(( $(date +%s) - _CLAW_PROG_T0 )))"
  local count=""
  (( _CLAW_PROG_TOTAL > 0 )) && count="$(printf '%d/%d' "$_CLAW_PROG_DONE" "$_CLAW_PROG_TOTAL")"
  claw_frame_top
  printf '\033[2K  %s%s%s  %s  %s%s%s%s · %s%s%d %s%s%d %s%s%d%s\n' \
    "$(_c blue)"  "$_CLAW_PROG_OP" "$(_creset)" \
    "$(_claw_prog_bar)" \
    "$(_c muted)" "${count:+$count }" "$dur" "$(_creset)" \
    "$(_c green)" "$(_claw_glyph ok)"   "$_CLAW_PROG_OK" \
    "$(_c red)"   "$(_claw_glyph fail)" "$_CLAW_PROG_FAIL" \
    "$(_c muted)" "$(_claw_glyph skip)" "$_CLAW_PROG_SKIP" "$(_creset)"
  local spin="${_CLAW_SPIN_FRAMES:$(( _CLAW_SPIN_I % ${#_CLAW_SPIN_FRAMES} )):1}"
  printf '\033[2K  %s%s%s %s %s%s%s%s\n' \
    "$(_c amber)" "${_CLAW_PROG_ITEM:+$spin}" "$(_creset)" \
    "${_CLAW_PROG_ITEM:-…}" \
    "$(_c muted)" "${_CLAW_PROG_PHASE:+${_CLAW_PROG_PHASE} }${_CLAW_PROG_NOTE}" \
    "${_CLAW_PROG_SRC:+  ($_CLAW_PROG_SRC)}" "$(_creset)"
  claw_frame_bottom
}

_claw_prog_repaint() {
  [[ "$_CLAW_PROG_MODE" == rich ]] || return 0
  if (( _CLAW_PANEL_DRAWN )); then printf '\033[%dA' "$_CLAW_PANEL_H"; fi
  _claw_panel_render
  _CLAW_PANEL_DRAWN=1
}

_claw_prog_scrollback() {  # insert a line above the pinned panel
  if [[ "$_CLAW_PROG_MODE" != rich ]]; then printf '%s\n' "$1"; return; fi
  if (( _CLAW_PANEL_DRAWN )); then printf '\033[%dA' "$_CLAW_PANEL_H"; fi
  printf '\033[2K%s\n' "$1"     # the freed line, cleared then written
  _claw_panel_render
  _CLAW_PANEL_DRAWN=1
}

_claw_prog_teardown() {
  [[ "$_CLAW_PROG_MODE" == rich ]] || return 0
  if (( _CLAW_PANEL_DRAWN )); then
    printf '\033[%dA' "$_CLAW_PANEL_H"
    local i; for ((i=0;i<_CLAW_PANEL_H;i++)); do printf '\033[2K\n'; done
    printf '\033[%dA' "$_CLAW_PANEL_H"
  fi
  printf '\033[?25h'    # ensure cursor visible
  _CLAW_PANEL_DRAWN=0
}

claw_prog_run() {  # claw_prog_run <phase> -- <cmd...>
  local phase="$1"; shift
  [[ "${1:-}" == "--" ]] && shift
  _CLAW_PROG_PHASE="$phase"
  local log; log="$(_claw_logfile)"
  if [[ "$_CLAW_PROG_MODE" != rich ]]; then
    "$@" >>"$log" 2>&1; return $?
  fi
  _claw_prog_repaint
  "$@" >>"$log" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    _CLAW_SPIN_I=$(( _CLAW_SPIN_I + 1 )); _claw_prog_repaint; sleep 1
  done
  wait "$pid"; return $?
}

# ── streaming step runner: stream + collapse-on-success ─────────────────────
_CLAW_STEP_TAIL_MAX=6
_CLAW_STEP_LABEL=""
_CLAW_STEP_RING=()
_CLAW_STEP_REGION=0

_claw_step_trunc() {  # _claw_step_trunc <text> → single-row, width-clamped
  local w s
  w=$(( $(_claw_cols) - 4 )); (( w < 8 )) && w=8
  s="$1"; s="${s//$'\r'/}"; s="${s//$'\t'/  }"
  if (( ${#s} > w )); then printf '%s…' "${s:0:w-1}"; else printf '%s' "$s"; fi
}

_claw_step_repaint() {  # redraw the live block (header + ring tail) in place
  (( _CLAW_STEP_REGION > 0 )) && printf '\033[%dA\033[J' "$_CLAW_STEP_REGION"
  printf '  %s%s%s %s…\n' "$(_c amber)" "$(_claw_glyph run)" "$(_creset)" "$_CLAW_STEP_LABEL"
  _CLAW_STEP_REGION=1
  local l
  if (( ${#_CLAW_STEP_RING[@]} )); then
    for l in "${_CLAW_STEP_RING[@]}"; do
      printf '  %s│%s %s\n' "$(_c muted)" "$(_creset)" "$l"
      _CLAW_STEP_REGION=$(( _CLAW_STEP_REGION + 1 ))
    done
  fi
}

claw_step() {  # claw_step "<label>" -- <cmd...>
  local label="$1"; shift
  [[ "${1:-}" == "--" ]] && shift
  local log rcf rc line mode
  log="$(_claw_logfile)"
  mode="${_CLAW_PROG_MODE:-$(_claw_prog_detect_mode)}"
  rcf="$(mktemp 2>/dev/null || printf '%s/claw_step.%s' "${TMPDIR:-/tmp}" "$$")"

  if [[ "$mode" != rich ]]; then
    # plain: stream each line with a gutter, then a verdict line
    while IFS= read -r line; do
      printf '  %s│%s %s\n' "$(_c muted)" "$(_creset)" "$line"
    done < <( { "$@" </dev/null 2>&1; printf '%d' "$?" >"$rcf"; } | tee -a "$log" )
    rc="$(cat "$rcf" 2>/dev/null || echo 1)"; rm -f "$rcf"
    if (( rc == 0 )); then
      printf '  %s%s%s %s\n' "$(_c green)" "$(_claw_glyph ok)" "$(_creset)" "$label"
      _CLAW_PROG_OK=$(( _CLAW_PROG_OK + 1 ))
    else
      printf '  %s%s%s %s %s(exit %d)%s\n' "$(_c red)" "$(_claw_glyph fail)" "$(_creset)" "$label" "$(_c muted)" "$rc" "$(_creset)"
      _CLAW_PROG_FAIL=$(( _CLAW_PROG_FAIL + 1 ))
    fi
    _CLAW_PROG_DONE=$(( _CLAW_PROG_DONE + 1 ))
    return "$rc"
  fi

  # rich: moving ≤N-line viewport, collapse on success / retain on failure
  _CLAW_STEP_LABEL="$label"; _CLAW_STEP_RING=(); _CLAW_STEP_REGION=0
  printf '\033[?25l'
  _claw_step_repaint
  while IFS= read -r line; do
    line="$(_claw_step_trunc "$line")"
    _CLAW_STEP_RING+=("$line")
    (( ${#_CLAW_STEP_RING[@]} > _CLAW_STEP_TAIL_MAX )) && _CLAW_STEP_RING=("${_CLAW_STEP_RING[@]:1}")
    _claw_step_repaint
  done < <( { "$@" </dev/null 2>&1; printf '%d' "$?" >"$rcf"; } | tee -a "$log" )
  rc="$(cat "$rcf" 2>/dev/null || echo 1)"; rm -f "$rcf"

  (( _CLAW_STEP_REGION > 0 )) && printf '\033[%dA\033[J' "$_CLAW_STEP_REGION"
  if (( rc == 0 )); then
    printf '  %s%s%s %s\n' "$(_c green)" "$(_claw_glyph ok)" "$(_creset)" "$label"
    _CLAW_PROG_OK=$(( _CLAW_PROG_OK + 1 ))
  else
    printf '  %s%s%s %s %s(exit %d)%s\n' "$(_c red)" "$(_claw_glyph fail)" "$(_creset)" "$label" "$(_c muted)" "$rc" "$(_creset)"
    if (( ${#_CLAW_STEP_RING[@]} )); then
      for line in "${_CLAW_STEP_RING[@]}"; do
        printf '  %s│%s %s\n' "$(_c muted)" "$(_creset)" "$line"
      done
    fi
    _CLAW_PROG_FAIL=$(( _CLAW_PROG_FAIL + 1 ))
  fi
  printf '\033[?25h'
  _CLAW_PROG_DONE=$(( _CLAW_PROG_DONE + 1 ))
  return "$rc"
}

# ── themed chrome for the update surfaces ────────────────────────────────────
claw_ui_header() {  # claw_ui_header "<TITLE>" ["<subtitle>"]
  _CLAW_PROG_OP="$1"
  _CLAW_PROG_OK=0; _CLAW_PROG_FAIL=0; _CLAW_PROG_SKIP=0; _CLAW_PROG_DONE=0
  _CLAW_PROG_T0="$(date +%s)"
  _CLAW_PROG_MODE="$(_claw_prog_detect_mode)"
  claw_frame_top
  printf '  \033[1m%s%s%s\n' "$(_c blue)" "$1" "$(_creset)"
  [[ -n "${2:-}" ]] && printf '  %s%s%s\n' "$(_c muted)" "$2" "$(_creset)"
}

claw_ui_section() {  # claw_ui_section "<Title>"
  printf '\n  %s%s%s\n' "$(_c purple)" "$1" "$(_creset)"
}

claw_ui_skip() {  # claw_ui_skip "<name>"
  printf '  %s%s %s — not installed%s\n' "$(_c muted)" "$(_claw_glyph skip)" "$1" "$(_creset)"
  _CLAW_PROG_SKIP=$(( _CLAW_PROG_SKIP + 1 ))
}

claw_ui_footer() {  # claw_ui_footer ["<message>"]
  local dur; dur="$(_claw_dur $(( $(date +%s) - _CLAW_PROG_T0 )))"
  printf '  %s%s%d%s %s%s%d%s %s%s%d%s %s· %s%s\n' \
    "$(_c green)" "$(_claw_glyph ok)"   "$_CLAW_PROG_OK"   "$(_creset)" \
    "$(_c red)"   "$(_claw_glyph fail)" "$_CLAW_PROG_FAIL" "$(_creset)" \
    "$(_c muted)" "$(_claw_glyph skip)" "$_CLAW_PROG_SKIP" "$(_creset)" \
    "$(_c muted)" "$dur" "$(_creset)"
  claw_frame_bottom
  # Verdict line is honest: red ✗ when any step failed, green ✓ otherwise
  # (a green check next to "finished with failures" reads as success).
  if [[ -n "${1:-}" ]]; then
    if (( _CLAW_PROG_FAIL > 0 )); then
      printf '  %s%s %s%s\n' "$(_c red)" "$(_claw_glyph fail)" "$1" "$(_creset)"
    else
      printf '  %s%s %s%s\n' "$(_c green)" "$(_claw_glyph ok)" "$1" "$(_creset)"
    fi
  fi
  return 0
}

claw_ui_pause() {
  [[ "${INTERACTIVE:-1}" -eq 1 ]] || return 0
  printf '  %sPress any key to continue...%s' "$(_c muted)" "$(_creset)"
  if [[ -n "${ZSH_VERSION:-}" ]]; then read -k 1; else read -r -n 1 -s; fi
  echo ""
}

# Rich mode: hide cursor + guarantee teardown on signals.
_claw_prog_begin_rich() {
  [[ "$_CLAW_PROG_MODE" == rich ]] || return 0
  printf '\033[?25l'
  trap '_claw_prog_teardown' EXIT INT TERM
  _claw_prog_repaint
}
