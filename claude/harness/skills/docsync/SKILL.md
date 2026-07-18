---
name: docsync
description: >
  Project-aware sync between a GitHub repo, its Things 3 project, and its Obsidian
  vault subdirectory. The repo NAME is the common key across all three surfaces.
  Use whenever an agent needs to create, find, complete, or update Things 3 todos
  tied to a repo, onboard a repo, or mirror a repo's key markdown into the vault.
  Replaces ad-hoc add_todo calls that silently land in the Inbox, and ad-hoc
  update/complete calls that fuzzy-match titles. Trigger on "docsync", "sync this
  repo to Things", "create a todo for {repo}", "mark X done", "complete the task",
  "close out", "finished the todo", "update the task", "the task we tracked",
  sprint planning that emits tasks, any repo-scoped task capture, or any
  completion/update/close of a task previously tracked for a repo.
---

# docsync

Thin orchestration layer over the **vault-os MCP tools**. docsync does NOT
re-implement the binding model — it calls the tools that own it. This keeps one
source of truth and avoids the drift this whole effort exists to prevent.

```
MAC  ~/Github/Github_desktop/{repo}/        (left) code, authoritative for identity
              |
        +-----+-----------------------+
        v                             v
THINGS 3 project "{repo}"      VAULT  Github-Projects/{repo}/
   (manages the work)                (one-way mirror of repo artifacts + your context)
                                      anchored by  _MOC {repo}.md
```

Authority model:
- **Repo name** = identity key. Same string names the repo dir, the Things project, and the vault subdir.
- **`{VAULT}/Github-Projects/{repo}/_MOC {repo}.md`** = the single binding anchor.
  Carries the binding frontmatter (`repo-path`, `things-project-uuid`,
  `things-project-name`, `last-sync-date`, `last-sync-sha`) AND a self-locating
  dataviewjs folder tree. Owned and written by the MCP tools, never by docsync directly.
- Things 3 and the vault are **projections**. Mirroring is **one-directional, repo wins**.
  docsync never writes back to a repo.

Paths:
- Repos root (Mac): `~/Github/Github_desktop`
- Vault root: `/Users/henry/hr-vault-main-pa`   (direct path; vault = hr-vault-main-pa. Adjust if your home dir differs.)
- Vault mirror root: `{VAULT}/Github-Projects`

---

## The tools docsync calls (do not reimplement)

| Tool | Role | Mutating |
|------|------|----------|
| `vault_list_projects()` | List all dev-project bindings (repo ↔ Things ↔ last-sync) | no |
| `vault_project_home(project, repo_path?, things_uuid?, things_name?, create?)` | Read, or (create=true) scaffold/update the `_MOC {project}.md` binding | when create=true |
| `vault_log_sync(project, sha, summary, docs_updated?, docs_flagged?, todos_added?, todos_completed?, manual_review?)` | Append a sync-log entry and bump `last-sync-*` in the anchor | yes |

docsync owns NONE of the scaffold / frontmatter / sync-log mechanics. Those live in
`vault_mcp_server.py` and are unit-tested there.

<!-- TODO: frontmatter-overwrite asymmetry — the right fix is another NARROW verb
     modeled on vault_log_sync (e.g. a future vault_set_phase), never a
     general-purpose vault overwrite verb. Noted only; do not build yet. -->

---

## Why this skill exists (the failure it kills)

The `hald/things-mcp` AppleScript bridge resolves projects by **title** and, on any
miss (whitespace, emoji, duplicate, casing), **silently routes the todo to the Inbox**.
Every `add_todo` here resolves to a **UUID** (via the persisted binding) and passes it
as `list_id`. A todo is never created with an empty/unknown `list_id` — see the guard.

---

## Core operations

### 1. `resolve_project(repo)` -> `{uuid, status}`

Binding-first. Prefer the persisted binding over name matching.

```
1. BINDING   vault_project_home(repo)
                returns things-project-uuid (non-empty)? -> {uuid, status: "bound"}

2. EXACT     get_projects(); project whose name == repo (exact, case-sensitive)
                hit? -> persist via vault_project_home(repo, repo_path={abs},
                        things_uuid={uuid}, things_name={title}, create=true)
                     -> {uuid, status: "exact"}

3. SIMILAR   get_projects(); project whose name ~ repo
             (case-insensitive / trimmed / single-token diff)
                hit? -> {uuid: {that uuid}, status: "questionable"}
                (do NOT auto-use; caller routes to Inbox + prompts — see add_todo_for)

4. CREATE    no match ->
                vault_project_home(repo, repo_path={abs}, create=true)
                  (the tool scaffolds the anchor; Things project creation, if any,
                   uses the first available area — confirm before add_project)
                -> {uuid, status: "created"}
```

Never hardcode an area UUID. Auto-created Things projects default to the first
available area (Homelab lives under the Home space; projects carry internal sections).

### 2. `add_todo_for(repo, task_name, task_id=None, kind="task", slug=None, **kw)`

```
r = resolve_project(repo)

key  = make_key(repo, kind, slug or task_id or slugify(task_name))
# -> "docsync:{repo}:{kind}:{slug}" — see KIND REGISTRY. Slug is frozen at
#    creation; later title edits never change identity.

if r.status in ("bound", "exact", "created"):
    notes = kw.pop("notes", "")
    notes = (notes + "\n\n" if notes else "") + f"docsync-key: {key}"
    add_todo(title=task_name, list_id=r.uuid, notes=notes, **kw)   # lands in the project

elif r.status == "questionable":
    # similar-but-not-exact: don't risk misfiling. Make it trivially movable.
    label = f"[{repo}] [{task_id}] {task_name}" if task_id else f"[{repo}] {task_name}"
    notes = kw.pop("notes", "")
    notes = (notes + "\n\n" if notes else "") + f"docsync-key: {key}"
    add_todo(title=label, notes=notes, **kw)                # Inbox (no list_id)
    # key is stamped even on the Inbox fallback, so the todo stays findable
    # by find_todo_for after the operator drags it into the right project.
    PROMPT_USER(
      f'docsync: no exact Things project for "{repo}". '
      f'Closest match: "{r.match_name}". Sent to Inbox as "{label}". '
      f'Confirm the project, or rename it to match the repo.'
    )
```

`task_id` is whatever the working agent is operating under (sprint/story id, etc.).
Optional, pass-through — docsync never invents one. When present it is also forwarded
to `/sync-docs` Stage 4 so the Inbox-fallback label is reconstructable.

### 3. `find_todo_for(repo, key)` -> `{uuid, title, notes, status}`

Resolves a todo by its **machine key**, never by title. Read-only.

```
1. NORMALIZE  key may be full ("docsync:{repo}:{kind}:{slug}") or short
              ("{kind}:{slug}") -> always expand to the full form.
2. BINDING    resolve_project(repo); require status in ("bound", "exact").
              A lookup NEVER creates a project or an anchor as a side effect.
3. SEARCH     search_todos(query=key)      # hald/things-mcp matches notes too
4. FILTER     exact hits only: todos whose notes contain the literal line
              "docsync-key: {key}". No substring-of-a-different-key, no
              title similarity.
5.  1 hit  -> return it (uuid + fields)
    0 hits -> FAIL LOUD: report "no todo with key {key} in {repo}". Do NOT
              fall back to fuzzy title matching.
   >1 hits -> FAIL LOUD: duplicate key; list the UUIDs and stop. Operator
              resolves — docsync never picks one.
```

### 4. `complete_todo_for(repo, key)`

```
t = find_todo_for(repo, key)        # asserts exactly one hit, or has already
                                    # failed loud — there is no partial path here
update_todo(id=t.uuid, completed=true)
```

Then report the completion upstream: the caller (usually `/sync-docs` or the
working agent) includes the key in `vault_log_sync(todos_completed=[key, ...])`
so the anchor's sync log finally receives real completion events instead of
improvised ones. Never guess-complete a similar title — if the key does not
resolve, the failure report IS the correct output.

Batches: collect UUIDs from repeated `find_todo_for` calls, then one
`bulk_update_todos(ids=[...], completed=true)`.

### 5. `update_todo_for(repo, key, **fields)`

```
t = find_todo_for(repo, key)
if "notes" in fields and "docsync-key: {key}" not in fields["notes"]:
    fields["notes"] += f"\n\ndocsync-key: {key}"   # identity survives note rewrites
update_todo(id=t.uuid, **fields)
```

Same lookup, same fail-loud contract. Title changes are allowed — identity
lives in the key, not the title (this is the whole point).

### 6. GUARD — fail loud, never silent-Inbox-on-error, never fuzzy-mutate

```
Before ANY add_todo meant for a project:
  assert list_id is set and non-empty
  if not -> raise / abort visibly. Do NOT fall back to Inbox silently.

Before ANY complete/update (verbs 4-5):
  assert find_todo_for returned exactly one exact-key hit
  if not -> raise / abort visibly. Do NOT mutate a similar-titled todo.

The ONLY intentional Inbox write is the "questionable" branch, always prefixed
with [{repo}] so it is one drag to file.
```

### 7. Artifact mirror (one-way repo -> vault) — runs in /sync-docs APPLY mode

docsync does not copy files itself. The mirror is a gated, mutating step inside
`/sync-docs` apply-mode (alongside Stage 5), so it shares the same DRY-RUN/--apply
gate as every other write and is logged via `vault_log_sync(docs_updated=[...])`.

Default artifact set (copy if present, skip silently if not; overwrite-on-change, repo wins):

```
{repo}/README.md
{repo}/CHANGELOG.md
{repo}/docs/**            (recursive)
{repo}/**/ADR*.md , adr/**, decisions/**
{repo}/SKILL.md           (if the repo is itself a skill)
```

Never touch:
- `_MOC {repo}.md` (the binding anchor — tool-owned)
- any file you authored under `Github-Projects/{repo}/` with no repo counterpart
  (those are your context notes; leave them).

In DRY-RUN: print the proposed copies. In APPLY: copy, then `vault_log_sync(...)`
with the copied set, then `vault_refresh_mocs` so the anchor tree + roll-up reflect it.

---

## Binding anchor — `{VAULT}/Github-Projects/{repo}/_MOC {repo}.md`

Written by `vault_project_home`. Schema (frontmatter keys are authoritative — match exactly):

```yaml
---
title: {Display Name}
type: project-doc
status: active
area: development
repo-path: ~/Github/Github_desktop/{repo}
things-project-uuid: {UUID}
things-project-name: {Things title}
last-sync-date: {YYYY-MM-DD}
last-sync-sha: {short sha}
tags: [dev-project, {repo}]
---
```

`type: project-doc` keeps these out of the domain MOCs/Bases/Command Center.

---

## Known UUIDs (seed bindings; not a substitute for resolution)

| repo / project          | things_uuid              |
|-------------------------|--------------------------|
| dot-files               | 2UHGWLicqNLi5JMfk3YS4K   |
| local-ai-platform       | EqtKRtJr5CGmHbxWbfGDPQ   |
| One-Cortex              | 5Q7msdPei2zcZygY4tKNFJ   |
| DFW Dining Backlog      | 8onyKhAyNsf7fuSnUHn3tA   |

`Homelab` is an **area** (`EpMwMXZPEoUdydRfBNNNxE`), not a project — never a `list_id`.

---

## Onboarding

First time a repo is seen, onboard it with `/project-init {repo-path}` (which calls
`vault_project_home(... create=true)`), or let `resolve_project` step 2/4 persist the
binding on first sync. After that, every run takes the BINDING path.

---

## Boundary with obsidian-vault-capture

docsync and `obsidian-vault-capture` share the vault but own different territory.
Respect the seam:

- **docsync / vault-os tools** own the project workspace: `Github-Projects/{repo}/`
  — the `_MOC {repo}.md` anchor, `sync-log.md`, `design/`, and mirrored repo
  artifacts. Written only through the vault-os MCP tools.
- **obsidian-vault-capture** owns the inbox: `_wip/` only. Research findings,
  ADR-style decisions, and notable command output captured during a run go there
  via its own `capture_note.py`, never into `Github-Projects/`.
- A `/sync-docs` run records its **run history** to the project `sync-log.md`
  (every sync). It captures to `_wip/` only for **notable findings/decisions**
  surfaced during the sync — a higher, selective bar. The two never double-log the
  same event: sync-log = durable per-run trail, capture = surfaced insight.
- docsync never calls `capture_note.py`; capture never writes the binding anchor.
  Capture notes carry a non-domain `type` from the capture vocabulary
  (`working-note | research | reference | meeting | demo | discovery`) and route
  on `area:` — they surface in the MOC dashboards that query those types/areas,
  and stay out of the binding-anchor lane the same way `type: project-doc` keeps
  the `_MOC {repo}.md` anchors excluded from domain Bases.

## Operating rules (environment conventions)

- Prefer the persisted binding over `get_projects` matching; persist any newly resolved UUID.
- Always pass explicit `list_id` on `add_todo` for project-bound todos.
- Always `get_projects()` to confirm a UUID before trusting a title (resolution steps 2/3).
- The Things AppleScript bridge can crash silently; if a call returns nothing
  unexpected, a full Claude Desktop relaunch (not a retry) restores it.
- Mirroring is one-way today (repo -> vault). Bidirectional is explicitly out of scope.
