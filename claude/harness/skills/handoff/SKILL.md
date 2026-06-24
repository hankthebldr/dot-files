---
name: handoff
description: Generate a concise session-handoff summary — TL;DR, what changed, decisions taken, open items, and context for the next session — and optionally save it to the Obsidian vault _wip/ inbox via the capture skill. Use at the end of a working session, when switching context, or when the user says "handoff", "hand this off", "wrap up", "session summary", or "/handoff". Never include raw credentials or PII; use surrogates.
---

# Session Handoff

Compose a concise handoff for the current session (or a specific topic if one is given).

## Output structure

```markdown
## TL;DR
<2-3 sentences. What was done, what's next, what's blocking>

## What changed
- <commits, configs, infra deltas>

## Decisions taken
- <one-liner per decision, with link/ref to a spec/ADR if applicable>

## Findings (if any)
<reference the report-writeup skill format if recon was involved>

## Open items / followups
- [ ] <task> — owner — due

## Context for next session
<short paragraph: what state the work is in, what to read first, what to run>
```

## Storage

- **Default:** print to chat for review.
- **If the operator confirms:** save through the `obsidian-vault-capture` skill
  (`capture_note.py` in Claude Code, or `vault_create_note` in chat/Cowork) into
  `_wip/` as `YYYY-MM-DD-handoff-<slug>.md` with
  `--type reference --tags "handoff, <project>"` and an explicit `--area` so the
  router can classify it (a handoff with no `area` returns "no routing signal" and
  stalls in `_wip`). Use the `handoff` tag plus `--area` matching the work's domain
  (`lab`, `panw-gtm`, the relevant Cortex area, etc.). `_wip/` is the vault's inbox;
  the router files it on the next `vault_route_note(apply=True)` / `oroute` run.
  (Legacy `/handoff` targeted `00-Inbox/handoffs/`; `_wip/` is now the canonical
  inbox.) `type: capture` is retired — the type vocabulary is
  `working-note | research | reference | meeting | demo | discovery`; use
  `reference` for a handoff.

## Rules

- Never overwrite an existing handoff — `capture_note.py` auto-suffixes collisions.
- Never include raw credentials, API keys, or full PII. Use surrogates (engagement IDs, role labels).
- If the session was OPSEC-sensitive (safeclaude route), add a one-line note:
  "Generated via OPSEC route. Surrogate values used."
- This is session-level capture (a higher bar than per-run `sync-log.md`). It does not
  write project binding anchors — that is owned by `docsync` / the vault-os tools.
