---
description: Operator-invoked repo doc + Things 3 PMO sync. Use for /sync-docs <repo-path> [--scope=FULL|DOCS_ONLY|PMO_ONLY] [--pmo-uuid=<uuid>] [--apply]. Default is dry-run.
---

The operator is invoking `/sync-docs $ARGUMENTS`.

This is the operator-invoked replacement for the deprecated scheduled task
`comprehensive-project-managment-and-things-review`. Full methodology lives in
`~/.claude/scheduled-tasks/comprehensive-project-managment-and-things-review/SKILL.md`
(kept as reference; cron disabled). This command is the *wrapper* that adds explicit
scope, dry-run safety, and Things 3 UUID resolution.

## Argument parsing

Parse `$ARGUMENTS` as: `<repo-path> [flags...]`

- `<repo-path>` (required) — absolute, `~`-relative, or relative to CWD.
- `--scope=FULL|DOCS_ONLY|PMO_ONLY` (default `FULL`)
- `--pmo-uuid=<uuid>` (optional; if omitted, resolved interactively)
- `--apply` (default: dry-run — show diffs, do not write)

If `<repo-path>` is empty or starts with `-`, refuse with usage example.

## Preflight (read-only — no confirmation needed)

1. Resolve and `cd` into the repo path. If the path doesn't exist, isn't a directory,
   or has no `.git/`, refuse and tell the operator the expected shape.
2. `git status --porcelain` — if non-empty, list dirty files and **abort** per the
   methodology spec's "uncommitted changes not in scope" criterion.
3. `git log -1 --format='%h %s (%cr)'` — capture HEAD.
4. Show the operator a confirmation block and **wait for explicit `yes`**:

   ```
   Target  : <abs path>
   Repo    : <basename>
   Branch  : <current branch>
   HEAD    : <short SHA> — <subject>
   Scope   : <FULL|DOCS_ONLY|PMO_ONLY>
   Mode    : <DRY-RUN | APPLY>
   PMO UUID: <supplied UUID | "to be resolved" | "n/a (DOCS_ONLY)">
   Proceed? (yes/no)
   ```

   Refuse on anything other than `yes` / `y`.

## Stages (delegated to methodology spec)

Run Stages 1–4 from
`~/.claude/scheduled-tasks/comprehensive-project-managment-and-things-review/SKILL.md`
with the following overrides:

- **Stage 1 (Audit)** — always runs. Read-only.
- **Stage 2 (Docs)** — runs if scope is `FULL` or `DOCS_ONLY`.
  - In DRY-RUN: produce unified diffs for each file that *would* be modified
    (README, CHANGELOG, .env.example, deployment artifact comments) and print
    to chat. Do NOT write to disk.
  - In APPLY: for each file to be modified, copy to
    `~/.dotfiles-backups/$(date +%Y%m%d-%H%M%S)/<repo-name>/<relative-path>` first,
    then write. Confirm "wrote N files" at end of stage.
- **Stage 3 (Workflow & CI)** — always runs. Read-only validation; findings become
  Stage 4 tasks.
- **Stage 4 (Things 3 PMO)** — runs if scope is `FULL` or `PMO_ONLY`.
  - In DRY-RUN: print the proposed `update_todo` (completions) and `add_todo`
    (new tasks) calls verbatim. Do NOT call MCP write tools.
  - In APPLY: execute the calls. Every `add_todo` MUST include explicit `list_id`
    (the resolved UUID). Never rely on inbox routing — global CLAUDE.md rule.

## Things 3 UUID resolution

If `--pmo-uuid=<uuid>` was provided:
- Call `get_projects`. Verify a project exists with that UUID. If not, refuse Stage 4.

If `--pmo-uuid` was omitted AND scope includes PMO:
- Call `get_projects`. Build a case-insensitive substring match between project titles
  and the repo basename (and any obvious tokens, e.g. `cortex-dc-web` → match on
  `cortex-dc-web`, `cortex dc web`, `dc-web`).
- **Exactly one match:** surface `<title> [<uuid>]` and ask `Use this project? (yes/no)`.
- **Multiple matches:** print a numbered list, ask operator to pick by number, or `none`.
- **Zero matches:** print all project titles + UUIDs, ask operator to either pick by
  index, supply `--pmo-uuid` and re-run, or accept `skip` to run Stages 1–3 only.

## Abort criteria (from methodology spec — restate here)

Stop immediately and report on any of:

- Merge conflicts present in working tree.
- `git status` shows uncommitted changes not in scope.
- Workflow file references a secret that no longer exists.
- A doc section marked `<!-- DO NOT AUTO-UPDATE -->` would be touched (skip that
  section, report it, continue).
- Things 3 MCP times out (skip Stage 4, log a manual follow-up).
- Ambiguous Things 3 task match (>1 open todo could match a finding) — report both
  candidates, do not auto-close either.

## Output

End every run with the structured summary defined in the methodology spec
("OUTPUT FORMAT" section). In DRY-RUN, append:

```
══════════════════════════════════════════════
DRY RUN — no files written, no Things 3 calls made.
Re-run with --apply to commit changes.
══════════════════════════════════════════════
```

## Rules

- Never call any Things 3 write tool in DRY-RUN mode.
- Never call `add_todo` without an explicit `list_id`.
- Always backup before editing any doc file (mirror to `~/.dotfiles-backups/$(date +%Y%m%d-%H%M%S)/<repo-name>/`).
- Never auto-fix `:latest` image tags — flag for manual review.
- Never auto-fix broken doc references — flag for manual review.
- If the operator declines the preflight confirmation, exit with no side effects.

## Examples

```
/sync-docs ~/Github/Github_desktop/cortex-dc-web
  → dry-run, FULL scope, interactive UUID resolution

/sync-docs ~/Github/Github_desktop/cortex-dc-web --apply
  → after dry-run review, commit changes with backups

/sync-docs ~/Github/Github_desktop/dot-files --scope=DOCS_ONLY --apply
  → skip Things 3 entirely (e.g. for repos without a PMO project)

/sync-docs ~/Github/Github_desktop/cortex-kg-26 --pmo-uuid=AB12-... --apply
  → bypass interactive resolution when UUID is already known
```
