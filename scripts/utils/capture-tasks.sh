#!/usr/bin/env bash
# capture-tasks.sh — scan vault notes for actionable lines and stage them as
# Things 3 tasks with an obsidian:// backlink. Lines like:
#     - [ ] do the thing @things ^list:Work
# On macOS, --apply opens things:/// URLs to create them; elsewhere it prints
# the candidates + URLs for review (Things is mac-only).
set -uo pipefail
VAULT="${OBSIDIAN_VAULT:-$HOME/hr-vault-main-pa}"
SCAN="${1:-$VAULT}"; APPLY=0; [[ "${2:-}" == "--apply" || "${1:-}" == "--apply" ]] && { APPLY=1; [[ "$1" == "--apply" ]] && SCAN="$VAULT"; }
[[ -d "$SCAN" ]] || { echo "✗ scan path not found: $SCAN"; exit 1; }
# _grep <pattern> <path> → "file:lineno:line" (ripgrep, else recursive grep -E).
_grep(){ if command -v rg &>/dev/null; then rg -n --no-heading -- "$1" "$2" 2>/dev/null
         else grep -rEn -- "$1" "$2" 2>/dev/null; fi; }
enc(){ python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$1"; }
vname="$(basename "$VAULT")"
n=0
while IFS= read -r m; do
  file="${m%%:*}"; rest="${m#*:}"; line="${rest#*:}"
  task="$(sed -E 's/.*- \[ \] //; s/@things//; s/\^list:[A-Za-z0-9_-]+//; s/[[:space:]]+$//' <<<"$line")"
  [[ -z "$task" ]] && continue
  list="$(grep -oE '\^list:[A-Za-z0-9_-]+' <<<"$line" | sed 's/\^list://')"
  rel="${file#"$VAULT"/}"; note="${rel%.md}"
  back="obsidian://open?vault=$(enc "$vname")&file=$(enc "$note")"
  url="things:///add?title=$(enc "$task")&notes=$(enc "source: $back")${list:+&list=$(enc "$list")}"
  n=$((n+1))
  printf "  • %s%s\n    %s\n" "$task" "${list:+  [$list]}" "$url"
  if (( APPLY )) && [[ "$(uname -s)" == Darwin ]]; then open "$url"; fi
done < <(_grep '- \[ \] .*@things' "$SCAN")
echo "  ── $n actionable line(s)$( ((APPLY)) && [[ "$(uname -s)" == Darwin ]] && echo ' → sent to Things' || echo ' (review; --apply on macOS to create)')"
