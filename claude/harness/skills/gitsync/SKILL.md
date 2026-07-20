---
name: gitsync
description: >-
  End-of-session git hygiene for a repo — sweep the working tree, commit named
  files at sensible boundaries per the commit policy, push the working branch,
  and capture anything deliberately NOT done as a deferred todo in the repo's
  Things 3 project. Use when the user says "gitsync", "sync up the repo", "wrap
  up the branch", "commit and capture the rest", or when a session ends with
  known follow-ups (skipped tests, TODOs noticed, refactors parked) that must
  not evaporate with the context window. Emits todos ONLY through docsync's
  verbs — never raw add_todo.
---

# gitsync — commit sweep + deferred capture

Git wrap-up ritual. Two halves: get the working tree committed/pushed per
Henry's commit policy, and turn everything consciously deferred into a durable
todo. This skill decides what counts as deferred; `docsync` owns todo identity
and lifecycle.

**Todo identity = docsync's KIND REGISTRY key scheme
(`docsync:{repo}:{kind}:{slug}`).** This skill owns kind `deferred`; the
`[deferred]` title form is display convention only and is defined in that
registry — do not restate or reinvent it here or anywhere else.

## Steps

1. **Sweep** — `git status`; group session-touched files into coherent chunks.
   Files not touched this session belong to a different chunk — leave them.
2. **Commit** — one commit per chunk, named files only (never `-A`/`.`),
   one-line imperative subject ≤ 72 chars matching `git log --oneline` style.
   Push the working branch. PRs only on explicit ask.
3. **Capture deferrals** — for each item deliberately not done (skipped test,
   parked refactor, TODO noticed in passing, review comment left open):
   `add_todo_for(repo, "[deferred] <item>", kind="deferred", slug=<short
   stable slug>, notes=<where it lives: file/line/branch + why deferred>)`.
4. **Resolve deferrals** — when a later session does the work:
   `complete_todo_for(repo, "deferred:<slug>")`, reported upstream for
   `vault_log_sync(todos_completed=[...])`. Never re-capture a deferral that
   already has a key — `find_todo_for` first, update its notes instead.

## Rules

- A deferral is captured at the moment of deferral, not reconstructed later
  from memory — step 3 runs before the session ends, every time.
- Inherit docsync's guard wholesale: binding-first resolution, explicit
  `list_id`, exact-key mutation, fail loud, never silent-Inbox-on-error.
- Force-push, reset --hard, branch deletion stay confirm-first — gitsync's
  sweep never rewrites history.

## Boundary

- `gitsync` owns the wrap-up ritual (commits + deferred capture). `docsync`
  owns todo identity + lifecycle. `handoff` owns the prose session summary —
  it may reference deferred keys but never creates them.
