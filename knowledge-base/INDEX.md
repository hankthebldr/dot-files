# Open Claw Knowledge Base — Index

## How to use this KB (for agents)
1. Read this index first. Pick notes by their descriptions; open only those.
2. To answer a question, prefer opening 1–3 specific notes over scanning everything.
3. Cite the note `id` when you use information from it.
4. Facts here are verified-against-code snapshots (see `updated`); if a note
   contradicts CLAUDE.md, the note is usually newer — verify in code and fix
   whichever is stale.

## How to update this KB (for agents)
- New idea → create a new note (atomic). Same idea changed → edit the note in place and bump `updated`.
- Any create / rename / delete MUST update this registry and the topic's `_topic.md` in the same change.
- Use only tags from the controlled vocabulary below; add a new tag here before using it.

## Controlled tags
`spine`, `profiles`, `themes`, `shell`

## Registry
### spine
- `20260718-one-dispatcher` — **One dispatcher** — `topics/spine/one-dispatcher.md` — The single claw() function, what stays in-shell, and how bin/claw routes.
- `20260718-one-theme-engine` — **One theme engine** — `topics/spine/one-theme-engine.md` — theme.sh as sole color source and the CLAW_THEME precedence chain.
- `20260718-one-render-path` — **One render path** — `topics/spine/one-render-path.md` — claw-dashboard.py as the login/default renderer and its fallbacks.

### profiles
- `20260718-profile-directory-contract` — **Profile directory contract** — `topics/profiles/profile-directory-contract.md` — The dispatcher + meta/common/mac/linux per-profile layout (post-dates CLAUDE.md's single-file description).
- `20260718-profile-registration-points` — **Profile registration points** — `topics/profiles/profile-registration-points.md` — Every hardcoded list a new profile must be added to.

### themes
- `20260718-theme-directory-layout` — **Theme directory layout** — `topics/themes/theme-directory-layout.md` — config/themes/<slug>/ structure, required palette keys, generated ghostty.conf, clin slug map.
