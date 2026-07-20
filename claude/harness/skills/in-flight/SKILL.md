---
name: in-flight
description: >-
  Track work items that are mid-stream during a working session — capture a unit
  of work as a Things 3 todo when it starts, land it when it ships. Use when the
  user says "track this work item", "what's in flight", "WI this", "park this
  work item", "that landed / ship it off the board", or when an agentic session
  starts a multi-step piece of work that could outlive the session and needs a
  durable in-flight record. Emits and completes todos ONLY through docsync's
  verbs — never raw add_todo.
---

# in-flight — work-item tracking

Session-level WIP board over `docsync`. A **work item (WI)** is a unit of work
big enough to survive a session boundary: a fix in progress, a refactor
half-landed, a doc mid-draft. This skill decides when a WI exists and when it
lands; `docsync` owns identity and lifecycle.

**Todo identity = docsync's KIND REGISTRY key scheme
(`docsync:{repo}:{kind}:{slug}`).** This skill owns kind `wi`; the
`[WI:<slug>]` title form is display convention only and is defined in that
registry — do not restate or reinvent it here or anywhere else.

## Operations

1. **Open** — pick a short stable slug for the work item (kebab-case, from the
   branch/fix name, NOT re-derived from the title later), then
   `add_todo_for(repo, "[WI:<slug>] <summary>", kind="wi", slug="<slug>",
   notes=<context: branch, files, next step>)`.
2. **Status** — "what's in flight" = `find_todo_for(repo, "wi:<slug>")` per
   known slug, or search the repo's Things project for open `wi` keys; report
   title + next-step line from notes.
3. **Progress** — `update_todo_for(repo, "wi:<slug>", notes=...)` to move the
   next-step line forward. Never edit the slug; titles may change, keys do not.
4. **Land** — `complete_todo_for(repo, "wi:<slug>")` when the work ships
   (merged/committed/delivered — per the repo's definition of done), and report
   it upstream for `vault_log_sync(todos_completed=[...])`.

## Rules

- One WI = one todo = one key. A WI that splits becomes new WIs with new slugs;
  the original is completed or updated, never silently abandoned.
- Inherit docsync's guard wholesale: exact-key lookup, fail loud on 0 or >1
  hits, never guess-complete a similar title, never silent-Inbox.
- A WI is repo-scoped. Work with no repo has no WI — capture it with
  obsidian-vault-capture or a plain Things todo instead.

## Boundary

- `in-flight` owns WI semantics (open/progress/land). `docsync` owns todo
  identity + lifecycle. `handoff` summarizes a session; it may LIST in-flight
  WIs but never completes them.
