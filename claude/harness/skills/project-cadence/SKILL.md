---
name: project-cadence
description: >-
  Run the cadence rituals for a repo-bound project — phase kickoff, sprint
  planning that emits tasks, and the RESUME HERE marker for picking a session
  back up. Use when the user says "start a phase", "plan the sprint", "sprint
  planning for {repo}", "kick off phase N", "set a resume point", "where did we
  leave off", or when a working session ends mid-stream and needs a durable
  re-entry marker in Things 3. Emits and completes todos ONLY through docsync's
  verbs — never raw add_todo.
---

# project-cadence — phases, sprints, resume markers

Cadence layer over `docsync`. This skill decides WHAT todos a phase/sprint/resume
ritual produces; `docsync` owns HOW they are created, found, completed, and
updated. No Things call is made here except through docsync's verbs.

**Todo identity = docsync's KIND REGISTRY key scheme
(`docsync:{repo}:{kind}:{slug}`).** This skill owns kinds `task`, `phase`,
`sprint`, `resume`; the title forms (`◆ PHASE: <n>`, `▶ SPRINT <n>:`,
`⏸ RESUME HERE`, plain) are display convention only and are defined in that
registry — do not restate or reinvent them here or anywhere else.

## Rituals

1. **Phase kickoff** — `add_todo_for(repo, "◆ PHASE: <n>", kind="phase",
   slug="phase-<n>")`, then one `kind="task"` todo per phase deliverable.
   Closing a phase = `complete_todo_for(repo, "phase:phase-<n>")` after its
   tasks are complete — never before; fail loud if any task key won't resolve.
2. **Sprint planning** — `add_todo_for(repo, "▶ SPRINT <n>: <goal>",
   kind="sprint", slug="sprint-<n>")` plus its `kind="task"` todos
   (slug from the story/task id when one exists). Sprint close mirrors phase
   close: complete the tasks by key, then the sprint marker.
3. **Resume marker** — at most ONE live `kind="resume"` todo per repo
   (`slug="resume"`). Setting a new one: `find_todo_for(repo, "resume:resume")`
   first — hit → `update_todo_for` with the new context in notes; miss →
   `add_todo_for(repo, "⏸ RESUME HERE", kind="resume", slug="resume")`.
   Picking up: read it, then `complete_todo_for(repo, "resume:resume")`.

## Rules

- Every completion is reported upstream so the caller can log
  `vault_log_sync(todos_completed=[...])` — cadence events are sync events.
- Inherit docsync's guard wholesale: binding-first resolution, explicit
  `list_id`, exact-key mutation, fail loud, never silent-Inbox-on-error.
- Repo name stays byte-identical across repo / Things project / vault folder;
  cadence never invents a display alias for a project.

## Boundary

- `project-cadence` owns the ritual shape (what a phase/sprint/resume emits).
- `docsync` owns todo identity + lifecycle. `/sync-docs` owns the sync run.
- Phase gates in `docs/spec-integration.md` are chat-signoff artifacts — a
  completed `phase` todo records the gate, it does not grant it.
