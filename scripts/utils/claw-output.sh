#!/usr/bin/env bash
# claw-output.sh — persisted output/display settings for claw surfaces.
# Mirrors the theme engine's precedence: env → state file → default.
#   keys: mode ∈ {auto,rich,plain}  frame ∈ {viewfinder,none}  banner ∈ {on,off}
# Sourced for _claw_output_get/_claw_output_set; executed for the `claw output` CLI.
set -uo pipefail

CLAW_OUTPUT_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claw"
CLAW_OUTPUT_STATE_FILE="$CLAW_OUTPUT_STATE_DIR/output"

_claw_output_default() {
  case "$1" in
    mode) echo auto ;; frame) echo viewfinder ;; banner) echo on ;;
    *) return 1 ;;
  esac
}

_claw_output_valid() {  # _claw_output_valid <key> <value>
  case "$1" in
    mode)   [[ "$2" == auto || "$2" == rich || "$2" == plain ]] ;;
    frame)  [[ "$2" == viewfinder || "$2" == none ]] ;;
    banner) [[ "$2" == on || "$2" == off ]] ;;
    *) return 1 ;;
  esac
}

_claw_output_get() {  # _claw_output_get <key> → resolved value on stdout
  local key="$1" up val
  up="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  # tier 1: env CLAW_OUTPUT_<KEY>
  eval "val=\"\${CLAW_OUTPUT_${up}:-}\""
  if [[ -n "$val" ]]; then printf '%s\n' "$val"; return 0; fi
  # tier 2: state file
  if [[ -r "$CLAW_OUTPUT_STATE_FILE" ]]; then
    val="$(grep -E "^${key}=" "$CLAW_OUTPUT_STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2-)"
    if [[ -n "$val" ]]; then printf '%s\n' "$val"; return 0; fi
  fi
  # tier 3: default
  _claw_output_default "$key"
}

_claw_output_set() {  # _claw_output_set <key> <value>
  local key="$1" value="$2"
  _claw_output_valid "$key" "$value" || { echo "invalid $key: $value" >&2; return 2; }
  mkdir -p "$CLAW_OUTPUT_STATE_DIR" 2>/dev/null || true
  local tmp; tmp="$(mktemp "${CLAW_OUTPUT_STATE_FILE}.XXXXXX")" || return 3
  if [[ -r "$CLAW_OUTPUT_STATE_FILE" ]]; then
    grep -vE "^${key}=" "$CLAW_OUTPUT_STATE_FILE" 2>/dev/null >> "$tmp" || true
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv -f "$tmp" "$CLAW_OUTPUT_STATE_FILE"
}

# ── CLI (only when executed, not when sourced) ──────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-status}" in
    get)    shift; _claw_output_get "${1:?usage: get <key>}" ;;
    status)
      printf "  output settings\n"
      printf "    %-8s %s\n" "mode"   "$(_claw_output_get mode)"
      printf "    %-8s %s\n" "frame"  "$(_claw_output_get frame)"
      printf "    %-8s %s\n" "banner" "$(_claw_output_get banner)"
      ;;
    mode|frame|banner)
      key="$1"; shift
      val="${1:?usage: claw output $key <value>}"
      _claw_output_set "$key" "$val" && printf "  \xE2\x9C\x93 %s: %s (persisted)\n" "$key" "$val"
      ;;
    *) echo "usage: claw output {mode auto|rich|plain | frame viewfinder|none | banner on|off | status | get <key>}" >&2; exit 2 ;;
  esac
fi
