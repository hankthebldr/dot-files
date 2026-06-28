#!/usr/bin/env bash
# handoff.sh — write a session handoff note into the Obsidian vault inbox.
set -uo pipefail
VAULT="${OBSIDIAN_VAULT:-$HOME/hr-vault-main-pa}"
case "${1:-}" in
    -h|--help) echo 'usage: claw handoff [title…]   write a session-handoff note into $VAULT/00-Inbox'; exit 0 ;;
esac
title="${*:-session handoff}"; slug="$(echo "$title" | tr ' /' '--' | tr -cd '[:alnum:]-' | tr '[:upper:]' '[:lower:]')"
dest="$VAULT/00-Inbox"; note="$dest/handoff-$(date +%F)-${slug:-note}.md"
[[ -d "$VAULT" ]] || { echo "✗ vault not found: $VAULT (set OBSIDIAN_VAULT)"; exit 1; }
mkdir -p "$dest"
i=2; while [[ -e "$note" ]]; do note="${note%.md}-$i.md"; i=$((i+1)); done
cat > "$note" <<NOTE
---
title: "$title"
date: $(date '+%Y-%m-%d %H:%M')
profile: ${CLAW_ACTIVE_PROFILE:-none}
tags: [handoff, ${CLAW_ACTIVE_PROFILE:-general}]
---

## TL;DR

## What changed

## Decisions

## Open items / next
- [ ]

## Context for next session
NOTE
echo "✓ handoff → $note"
command -v claw_open &>/dev/null && claw_open "$note" 2>/dev/null || true
