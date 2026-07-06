#!/usr/bin/env bash
# homelab-board.sh — detailed HR-TRUST fleet board. Reads the situation cache
# (~/.cache/claw/homelab.json); ZERO network. Theme-aware via theme.sh, so dot
# colors track `claw theme`. Grouped sections (Nodes/Cluster/DNS/Apps/Infra/Route)
# in the dashboard's icon→context→status idiom. Safe at login: emits nothing when
# the shell is an SSH session (scp/rsync safety), or when the cache is
# absent/malformed.
#
# Usage: homelab-board.sh [all|nodes|cluster|dns|apps|infra|route]
# CLAW_BOARD_LABEL=0 suppresses the leading section label (for callers whose
# own chrome already names the row, e.g. fastfetch `key:` columns).
set -u

# ── safety: never leak into scp/rsync/piped shells ──────────────────────────
case "${1:-all}" in --help|-h) echo "usage: homelab-board.sh [all|nodes|cluster|dns|apps|infra|route]"; exit 0;; esac
[ -n "${SSH_CONNECTION:-}" ] && exit 0

have() { command -v "$1" >/dev/null 2>&1; }
have jq || exit 0

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json"
[ -r "$CACHE" ] || exit 0
jq -e . "$CACHE" >/dev/null 2>&1 || exit 0      # malformed → skip

# ── palette (theme.sh exports CLAW_RGB_*; GitHub-dark fallback) ──────────────
_dots="${DOTFILES_DIR:-$HOME/.dotfiles}"
# shellcheck source=/dev/null
[ -r "$_dots/scripts/utils/theme.sh" ] && . "$_dots/scripts/utils/theme.sh" 2>/dev/null
if [ -n "${NO_COLOR:-}" ]; then
  GREEN=""; AMBER=""; RED=""; MUTED=""; BLUE=""; LABEL=""; RST=""
else
  GREEN=$'\033[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"'m'
  AMBER=$'\033[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"'m'
  RED=$'\033[38;2;'"${CLAW_RGB_RED:-255;123;114}"'m'
  MUTED=$'\033[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"'m'
  BLUE=$'\033[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"'m'
  LABEL=$'\033[38;2;'"${CLAW_RGB_PURPLE:-188;140;255}"'m'
  RST=$'\033[0m'
fi

# state → "<color><dot>"  (planned uses a hollow ○)
dot() { case "$1" in
  up)       printf '%s●' "$GREEN" ;;
  degraded) printf '%s●' "$AMBER" ;;
  planned)  printf '%s○' "$MUTED" ;;
  *)        printf '%s●' "$RED" ;;
esac; }

# ── freshness: fresh (<300s) | stale | (absent handled above) ───────────────
_age_secs() {   # ISO-8601 Z → seconds since, portable (mac+linux)
  local iso="$1" t now; now="$(date -u +%s)"
  if t="$(date -u -d "$iso" +%s 2>/dev/null)"; then :
  elif t="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null)"; then :
  else echo 0; return; fi
  echo $(( now - t ))
}
_age_human() { local s="$1"; [ "$s" -lt 0 ] && s=0; if [ "$s" -lt 90 ]; then echo "${s}s"; elif [ "$s" -lt 5400 ]; then echo "$((s/60))m"; else echo "$((s/3600))h"; fi; }

TS="$(jq -r '.ts // ""' "$CACHE")"
AGE="$(_age_secs "$TS")"
if [ "$AGE" -gt 300 ]; then FRESHTAG="${MUTED}stale $(_age_human "$AGE") ago${RST}"
else FRESHTAG="${MUTED}updated $(_age_human "$AGE") ago${RST}"; fi

# header line (printed by `all` only)
_hdr() { printf '  %s%s%s ───────────────  %s\n' "$BLUE" "$(jq -r '.fleet // "FLEET"' "$CACHE")" "$RST" "$FRESHTAG"; }

_label() {  # _label <text> — the row's leading section label (suppressible)
  [ "${CLAW_BOARD_LABEL:-1}" = 0 ] && return 0
  printf '  %s%-8s%s' "$LABEL" "$1" "$RST"
}

# render one service group as a single row: "<glyph> <dot> <id>" cells.
# Fields ride a \x01 separator (same idiom as hstatus) — ids/details never
# contain control chars, so the split is unambiguous.
_group_line() {  # $1=group label  $2=group key
  local label="$1" key="$2" printed=0 gly st id
  while IFS=$'\001' read -r gly st id; do
    [ -n "$id" ] || continue
    if [ "$printed" -eq 0 ]; then
      _label "$label"
      printed=1
    fi
    printf '  %s%s %s%s%s%s' "${gly:+$gly }" "$(dot "$st")" "$RST" "$MUTED" "$id" "$RST"
  done < <(jq -r --arg g "$key" \
    '.machines[].services[] | select(.group==$g) | (.glyph // "") + "" + .state + "" + .id' \
    "$CACHE" 2>/dev/null)
  [ "$printed" -eq 1 ] && printf '\n'
  return 0
}

_nodes_line() {
  # machines carry no glyph field; use a fixed node glyph (U+F473 server rack)
  local ngly=$'\xef\x91\xb3' st id printed=0
  while IFS=$'\001' read -r st id; do
    [ -n "$id" ] || continue
    if [ "$printed" -eq 0 ]; then
      _label "Nodes"
      printed=1
    fi
    printf '  %s %s%s %s%s%s' "$ngly" "$(dot "$st")" "$RST" "$MUTED" "$id" "$RST"
  done < <(jq -r \
    '.machines[] | .state + "" + .id + (if .role=="control-plane" then " cp" else "" end)' \
    "$CACHE" 2>/dev/null)
  [ "$printed" -eq 1 ] && printf '\n'
  return 0
}

_cluster_line() {
  local ctx rdy tot; ctx="$(jq -r '.cluster.context // ""' "$CACHE")"
  rdy="$(jq -r '.cluster.ready // "?"' "$CACHE")"; tot="$(jq -r '.cluster.total // "?"' "$CACHE")"
  [ -z "$ctx" ] && return 0
  local st=up; [ "$rdy" != "$tot" ] && st=degraded
  _label "Cluster"
  printf '  %s%s %s%s%s  %s%s/%s Ready%s\n' \
    "$(dot "$st")" "$RST" "$BLUE" "$ctx" "$RST" "$MUTED" "$rdy" "$tot" "$RST"
}

_route_line() {
  local p; p="$(jq -r '.route.path // ""' "$CACHE")"; [ -z "$p" ] && return 0
  _label "Route"
  printf '  %s%s%s\n' "$MUTED" "$p" "$RST"
}

case "${1:-all}" in
  nodes)   _nodes_line ;;
  cluster) _cluster_line ;;
  dns)     _group_line "DNS" dns ;;
  apps)    _group_line "Apps" apps ;;
  infra)   _group_line "Infra" infra ;;
  route)   _route_line ;;
  all|*)   _hdr; _nodes_line; _cluster_line; _group_line "DNS" dns; _group_line "Apps" apps; _group_line "Infra" infra; _route_line ;;
esac
exit 0
