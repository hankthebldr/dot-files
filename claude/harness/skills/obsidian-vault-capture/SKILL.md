---
name: obsidian-vault-capture
description: "Use whenever a session produces output with lasting reference value — research conclusions, comparison or evaluation results, command output worth keeping, architecture decisions, or notable findings — even if the user does not explicitly say \"save this to my vault\". Also trigger on \"capture this\", \"save to my vault\", \"note this\", \"vault this\", and as the default RECORD/REFLECT step in autonomous loops. This is the canonical way to write vault notes; do not hand-roll frontmatter or write notes ad hoc when this skill applies."
---

# Obsidian Vault Capture

Write a well-formed capture note into Henry's Obsidian vault. The note schema
(frontmatter key order, type vocabulary, filename convention) is fixed and
deterministic so captures are consistent and machine-readable later — the vault
linter, the MOC Dataview dashboards, and `wip-router.py` all depend on that
consistency.

There are two equivalent ways to write a note, by surface. **They emit the same
schema**, so a note written either way is byte-compatible with the linter and the
router:

| Surface | Mechanism | Filesystem |
| --- | --- | --- |
| Chat / Cowork | vault-os MCP `vault_create_note` | the MCP *is* the filesystem access |
| Claude Code (MBP) | `scripts/capture_note.py` | direct write to the local vault |

Do **not** produce a downloadable `.md` and do **not** claim a write failed
because "chat has no filesystem access." In chat, the MCP is the access path.

## The one write decision: assert a seam, or stage to _wip

This replaces the old domain-based `ouroute` routing. Every capture is one of two
shapes:

```
                 ┌─ Known seam?  pass dest explicitly → direct write, router skipped
 capture ────────┤
                 └─ Ambiguous?   omit dest → lands in _wip/ → router classifies by `area:`
```

**Known seams** (assert at write time; the router never produces these on its own):

| Destination | When | dest / --dest value |
| --- | --- | --- |
| Research | research output | `_research` |
| Project doc | project why/how | `_projects` |
| Repo docs | code-coupled docs | `github-projects/<repo>` (repo name == Things project == folder) |
| Domain note | Cortex etc. | the domain folder, e.g. `CORTEX/Cortex Cloud` |

**Everything else** → omit `dest` → the note stages in `_wip/` and the router
classifies it. **The router routes on the `area:` frontmatter key only.** Observed
mappings: `area:cortex-cloud → CORTEX/Cortex Cloud`, `area:panw-gtm → PANW GTM`,
`area:cortex-xdr → CORTEX/XDR`, `area:lab → _agents`. A note with no recognized
`area` returns `"no routing signal"` and stalls in `_wip/`. **So if you want a
_wip note auto-routed, you must set `area`.**

## Frontmatter schema (identical across MCP and script)

The schema below is the working copy; `_agents/vault-schema.md` is the single
source of truth that the MCP server, this skill, the router, and `enrich-this-note`
all reference. If they ever disagree, that file wins — keep this in sync with it.

Canonical linter key order — the tool enforces it, you supply values:

```
title → type → status → area → period → product → source →
informed-by → tags → aliases → date-created → date-modified
```

`type` is a fixed vocabulary (matches the MCP enum exactly):
`working-note | research | reference | meeting | demo | discovery`.
There is no `capture` or `decision` type — use `research` for research,
`reference` for ADR-style decisions and durable reference, `working-note` as the
default. Tag conventions still apply on top of `type`: `research` notes carry a
`research` tag; slash-command output carries `command-output`; decisions carry
`decision`.

## Chat / Cowork: vault_create_note (+ vault_route_note)

vault-os tools are deferred. Once per session, call `tool_search` (e.g.
`"vault create note route"`) to load them. No permission needed.

**Explicit-seam capture** — one call, done:

```
vault_create_note(
  title="XSIAM Ingest Rate Findings",
  note_type="research",
  area="xsiam",
  source="claude-deep-research",
  informed_by=["[[_MOC XSIAM]]"],
  tags=["research","cortex","xsiam"],
  dest="_research",          # seam asserted → router skipped
  body="## Question\n...\n## Findings\n...\n## Sources\n- ... (dated)")
# → report the returned path. Done.
```

**WIP / ambiguous capture** — create, then route:

1. `vault_create_note(..., area=..., note_type=..., tags=..., source=...,
   informed_by=...)` — **omit `dest`** so it lands in `_wip/`. Populate
   `area`/`note_type`/`tags` accurately; the router routes on them.
2. Immediately `vault_route_note(path=<returned path>, apply=True)` — moves the
   file to its final folder and fires the REST link-fix. This is what makes
   routing autonomous; no `oroute` CLI run needed.
3. Report: final destination path + the router's reason. If the router left it in
   `_wip` (no confident match), say so and either suggest an explicit `dest` or
   call `vault_suggest_routing(path)` and report what it proposed.

## Claude Code: scripts/capture_note.py

Direct-filesystem mirror of `vault_create_note` — same schema, same `--type`
enum, same seam-vs-`_wip` decision via `--dest`. Pipe the body via stdin to avoid
shell-escaping; pass metadata as flags. Prints the final note path on success
(exit 0); on failure prints a reason to stderr (2 = bad args, 3 = write error).

```bash
# Explicit seam (research): direct write, router skipped
python3 scripts/capture_note.py \
  --title "XSIAM Ingest Rate Findings" \
  --type research --area xsiam \
  --tags "research,cortex,xsiam" \
  --informed-by "[[_MOC XSIAM]]" \
  --source "claude-deep-research" \
  --dest "_research" \
  <<'EOF'
## Question
...
## Findings
...
## Sources
- Cortex docs vX.Y (retrieved 2026-06-23)
EOF
```

For a `_wip` capture, omit `--dest` (defaults to `_wip`) and **set `--area`** so
the router can classify it; the routing step itself (the move) is the vault-os
side or the next `oroute --apply` run.

### Arguments

- `--title` (required) — human-readable title; also drives the slug.
- `--type` — one of `working-note | research | reference | meeting | demo |
  discovery` (default `working-note`). Invalid values are rejected (exit 2).
- `--status` — frontmatter status; defaults to `wip`.
- `--area` — routing area the wip-router keys on (`cortex-cloud | cortex-xdr |
  xsiam | prisma-cloud | panw-gtm | lab | personal`). **Required for a `_wip`
  note to auto-route.**
- `--period` — e.g. `FY27-Q1`.
- `--product` — product refinement, e.g. `XDR | XSIAM | CDR`.
- `--source` — provenance: `cowork: <project>`, `project: <name>`,
  `code: <repo>`, or a URL. Defaults to `cowork`.
- `--informed-by` — comma-separated wikilinks, e.g.
  `"[[_MOC XSIAM]],[[Cortex Index]]"`.
- `--tags` — comma/space separated; leading `#` stripped.
- `--aliases` — comma-separated aliases.
- `--dest` — destination folder relative to vault root. Default `_wip` lets the
  router classify by `area`. Pass a seam folder (`_research`, `_projects`,
  `github-projects/<repo>`, `CORTEX/Cortex Cloud`, …) to write directly and skip
  routing.
- `--vault-root` — vault root; defaults to `$VAULT_PATH`
  (`/Users/henry/hr-vault-main-pa`).
- `--date` — override date for `date-created`/`date-modified` (YYYY-MM-DD);
  defaults to today.
- `--slug` — override the auto slug (filename stem). The slug algorithm is held
  byte-identical with the router and the MCP — do not change it here.
- `--extra KEY=VALUE` — extra trailing frontmatter key (repeatable).
- `--print-only` — compose and print without writing (dry run).

### Resulting note shape

```
Filename: YYYY-MM-DD-<kebab-slug>.md   (collisions get -2, -3, … suffixes)

---
title: <title>
type: research
status: wip
area: xsiam
period:
product:
source: <context>
informed-by:
  - "[[_MOC XSIAM]]"
tags:
  - research
aliases: []
date-created: <YYYY-MM-DD>
date-modified: <YYYY-MM-DD>
---

# <title>

<body, structured with headings; sources/versions preserved>
```

## Body content guidance

Structure the body with markdown headings so the note is scannable later:
- **Research** (`--type research`): keep the question, the findings, and the
  **sources with dates/versions** — undated research rots. Note any decision made.
- **Slash-command output** (`command-output` tag): record the command and result.
- **Decisions** (`--type reference`, `decision` tag): state the choice, a one-line
  rationale, and the alternative rejected (ADR style).

Do not summarize away the substance — the note should stand on its own without the
chat it came from.

## MOC coupling (per-write trigger)

MOCs are Dataview dashboards, not hand-curated link lists; a note appears in a MOC
automatically when its folder is covered by the MOC's FROM clause AND its
frontmatter matches the query predicates. So when a capture lands in (or routes
to) `_projects/` or `_research/` — or any folder a `_MOC` covers — confirm a
governing MOC's FROM clause includes that folder and the note's `type`/`status`
will surface in it. If the note opens a new branch (a new folder no MOC covers),
that's the real work: create or extend a MOC. Creating a new MOC is additive and
fine from chat; **editing an existing MOC's queries requires overwrite, which chat
vault-os cannot do — hand that to Claude Code on the MBP.**

## Failure handling (important for autonomous loops)

If the write fails (script exit nonzero, or the MCP returns an error), the note
was NOT written — do not claim it was. In an autonomous or multi-step loop, log
the failure to `DEFERRED.md` and continue: capture is a side effect, never a
blocker for the actual work. Do **not** fall back to a downloadable `.md` — that
is the deprecated behavior; the MCP/script *is* the access path. A vault-os
silent-hang is a known failure mode that requires a full ⌘Q relaunch of Claude
Desktop; if the MCP stops responding, surface that rather than inventing a
fallback.

## Boundary with docsync / vault-os

This skill captures notes. The dev-project workspace plumbing —
`github-projects/{repo}/`, its `_MOC {repo}.md` binding anchor, `sync-log.md`, and
mirrored repo artifacts — is owned by the `docsync` skill and the vault-os tools.
You may *capture a note into* `github-projects/<repo>` (via `dest`/`--dest`), but
never write or edit a project binding anchor or sync-log from here. During a
`/sync-docs` run, per-run history goes to `sync-log.md`; use capture only for
**notable findings or decisions** that deserve a durable, filable note — a higher
bar than per-run logging, so the two never double-log the same event.

Vault root resolves from `$VAULT_PATH` (default `/Users/henry/hr-vault-main-pa`),
matching the vault-os agent layer — keep these in sync if the vault moves.
