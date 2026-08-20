---
name: enrich-this-note
description: "Use when the user asks to \"enrich this note\", wants frontmatter, tag, wikilink, or MOC suggestions for a note, or is triaging a _wip/ note. Suggests only; never overwrites frontmatter without confirmation."
---

# Vault Note Enrichment

Analyze the current note and propose enrichment suggestions. Suggest; do not overwrite
without the operator's confirmation.

## Task
1. Review the note's content and existing frontmatter.
2. Suggest missing or improved frontmatter values (use the current vault schema below).
3. Identify 3-5 vault notes that should be wiki-linked from this note.
4. Recommend which MOC this note belongs in.
5. Generate a 1-sentence summary suitable for MOC inclusion.

## Current vault schema (defined in `_agents/vault-schema.md` — that file is authoritative; this is a working copy, keep in sync)
- **type (create-time — only these may be suggested for a NEW note):**
  working-note | research | reference | meeting | demo | discovery
- **type (recognized at rest — exist in the vault, do not suggest for new notes):**
  task | daily | weekly | project-doc  *(`capture` is retired — never suggest it)*
- **status:** draft | active | archived | wip
- **area:** cortex-cloud | cortex-xdr | xdr | xsiam | xsoar | prisma-cloud | panw-gtm | personal | development | lab | …
- **product (optional):** XDR | XSIAM | XSOAR | Agentix | Cortex Cloud | Prisma Cloud | Strata | CDR
- Frontmatter key order (linter): title → type → status → area → period → product → source → informed-by → tags → aliases → date-created → date-modified

When enriching, suggest `type` from the create-time set unless the note is already
one of the recognized-at-rest types (then preserve it). A good `area:` suggestion
is what moves a `_wip/` note out of the inbox — the router classifies on `area:`.

## Output format
Return suggestions as a fenced block the operator can review/apply — do not edit the file
directly. Note that `_wip/` notes route on `area:`/`space:`/`type:` via `oroute`, so a good
`area:` suggestion is what moves the note out of the inbox.
