# RESEARCH — dot-files

In-repo trail for cross-system research artifacts (repo summaries, deep-dives,
design notes). The canonical full-depth summary lives in the vault at
`Github-Projects/dot-files/SUMMARY.md` (regenerated idempotently by `/repo-summary`).

## Log

- 2026-06-19 — `/repo-summary` regenerated the full-depth repo snapshot →
  `~/hr-vault-main-pa/Github-Projects/dot-files/SUMMARY.md` @ commit `aa5dcb6`
  (master). Flagged: missing `_MOC dot-files.md` vault anchor; Things project
  note (`2UHGWLicqNLi5JMfk3YS4K`, 2026-05-28) stale vs HEAD.
  NOTE: vault renamed `SUMMARY.md` → `dot-files project summary.md` (external) —
  breaks the fixed-filename idempotency contract; see DEFERRED below.
- 2026-06-20 — expanded `docs-to-vault.{sh,py}` into a structured planning-corpus
  transposer; mirrored 58 docs (specs/plans/decisions/backlog/reference/harness/
  archive) + `_planning-index.md` into `Github-Projects/dot-files/` with
  provenance frontmatter @ `1919eae`. Re-runnable via `claw docs-sync`.
