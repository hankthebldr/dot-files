---
description: Generate a session handoff summary and (optionally) write to the Obsidian vault. Use for /handoff or /handoff <topic>.
---

Compose a concise handoff for the current session (or a specific topic if `$ARGUMENTS` is provided).

Output structure:

```markdown
---
title: <short title>
date: <UTC ISO8601>
engagement: <id-or-context>
tags: [handoff, <project>, <other>]
---

## TL;DR
<2-3 sentences. What was done, what's next, what's blocking>

## What changed
- <commits, configs, infra deltas>

## Decisions taken
- <one-liner per decision, with link/ref to ADR if applicable>

## Findings (if any)
<reference report-writeup skill format if recon was involved>

## Open items / followups
- [ ] <task>  — owner — due
- [ ] ...

## Context for next session
<short paragraph: what state the work is in, what to read first, what hooks/scripts to run>
```

Storage:
- Default: print to chat for review.
- If operator confirms: write to `$OBSIDIAN_VAULT/00-Inbox/handoffs/$(date +%Y-%m-%d)-<slug>.md` (Inbox is the agent-write zone — operator promotes to canonical folders manually).
- Phase 8 dependency: requires obsidian write-MCP. Until then, output to chat and operator pastes into vault.

Rules:
- Never overwrite an existing handoff file. Append a `-2`, `-3` suffix on collision.
- Never include raw credentials, API keys, full PII. Use surrogates (engagement IDs, role labels).
- If the session was OPSEC-sensitive (used `safeclaude`), include a one-line note: "Generated via OPSEC route (DontFeedTheAI). Surrogate values used."
