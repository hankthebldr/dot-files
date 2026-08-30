---
name: project-init
description: "Use when starting work on a new repo, or when the user says \"onboard <repo>\", \"project-init <repo>\", \"set up docsync for <repo>\", or before the first /sync-docs on a repo. Resolves (or creates, with confirmation) the Things 3 project and scaffolds github-projects/<repo>/ with its _MOC <repo>.md binding anchor. One-time per repo; afterward docsync and /sync-docs take the deterministic binding path automatically."
---

# project-init — onboard a dev project

Creates the per-project binding that makes `docsync` and `/sync-docs` deterministic for a repo.
Thin orchestration over the vault-os MCP tools — it does NOT hand-roll the anchor.

## Input
A repo path or repo name. Resolve to:
- absolute repo path under `~/Github/Github_desktop/<repo>` (the repos root — no `Repos/` subdir)
- `project` = repo basename (the identity key shared across repo / Things project / vault subdir)

If no repo is given, ask which repo to onboard (offer `vault_list_projects` to show what's already bound).

## Steps
1. **Check existing binding:** call `vault_project_home(project)`. If it returns a non-empty
   `things_uuid`, report "already onboarded" with the binding and STOP — unless the user
   explicitly wants to re-bind.
2. **Resolve the Things 3 project** (prefer an existing match; never create silently):
   - Call `get_projects`. Match a project whose name == `project` (exact), else a close match
     (case-insensitive / trimmed / single-token diff).
   - **Exact / confident match** → confirm `<title> [<uuid>]` with the user (yes/no).
   - **Multiple candidates** → numbered list; the user picks, or `none`.
   - **No match** → offer to `add_project(title=<Title-Cased project>)` — **confirm before
     creating**. Area: use `get_areas()` and the first available area unless the user names one.
     Or accept a pasted UUID, or `skip` (scaffold with an empty uuid; /sync-docs resolves + persists later).
3. **Persist the binding:** call
   `vault_project_home(project, repo_path=<abs>, things_uuid=<uuid>, things_name=<title>, create=true)`.
   This scaffolds `github-projects/<project>/` with `_MOC <project>.md` (binding frontmatter +
   self-locating folder tree), a `design/` dir, and `sync-log.md`.
4. **Report:** the created `moc_path`, `sync_log_path`, and the bound Things project.
   Point the user to `/sync-docs <repo-path>` as the next step.

## Rules
- Never `add_project` without explicit confirmation (avoids junk Things projects from a typo).
- The `repo_path` written is the absolute resolved path.
- Read-only until the user confirms the Things project; then a single `create=true` call.
- The `_MOC <project>.md` anchor is **tool-owned** — never hand-edit its binding keys here.

## Boundary
- `project-init` does the **one-time onboarding**. `docsync` owns ongoing Things todo-routing +
  artifact mirroring; `/sync-docs` owns the doc-sync run + `sync-log.md`. This skill is the setup
  that makes both deterministic.
