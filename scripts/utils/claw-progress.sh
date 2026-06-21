#!/usr/bin/env bash
# claw-progress.sh — inline, phase-driven live status panel for long-running
# claw ops. Foreground, single-process (Phase 1). Sourced by call sites.
#   See docs/superpowers/specs/2026-06-20-claw-live-progress-panel-design.md
set -uo pipefail

_CLAW_PROG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CLAW_PROG_DIR/claw-output.sh" 2>/dev/null || true

# ── theme colors (consume exported CLAW_C_*; refined-dark fallbacks) ─────────
_c() {  # _c <key> → ANSI color (env CLAW_C_<key> or fallback)
  local v; eval "v=\"\${CLAW_C_$1:-}\""
  if [[ -n "$v" ]]; then printf '%s' "$v"; return; fi
  case "$1" in
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
