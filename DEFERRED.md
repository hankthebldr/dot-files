# DEFERRED — dot-files

Known gaps / deferred follow-ups surfaced during agent runs. Not blockers.

## Open

- **Vault renames `SUMMARY.md`, breaking `/repo-summary` idempotency.**
  `/repo-summary` writes the fixed filename `Github-Projects/dot-files/SUMMARY.md`
  so re-runs overwrite in place. On 2026-06-19 the vault (Obsidian-side process or
  manual rename) renamed it to `dot-files project summary.md`. Effect: the next
  `/repo-summary` will create a fresh `SUMMARY.md` alongside the renamed copy →
  duplicate summaries. **Decide:** (a) rename back to `SUMMARY.md` and disable the
  renaming automation for this folder, or (b) update the `/repo-summary` contract +
  `docs-to-vault` to target `dot-files project summary.md` as the canonical name.
- **No `_MOC dot-files.md` binding anchor** in `Github-Projects/dot-files/` — the
  folder doesn't surface in `_MOC Dev Projects.md`. Fix: run `project-init dot-files`.
- **Things project note stale** (`2UHGWLicqNLi5JMfk3YS4K`, 2026-05-28) vs HEAD —
  S9 quality gates / CI have since landed; re-baseline onto TUI v2 + spec Phases 5–8.
