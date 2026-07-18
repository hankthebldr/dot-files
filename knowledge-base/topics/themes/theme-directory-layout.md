---
id: 20260718-theme-directory-layout
title: Theme directory layout
tags: [themes]
created: 2026-07-18
updated: 2026-07-18
related: [20260718-one-theme-engine]
summary: config/themes/<slug>/ structure, required palette keys, generated ghostty.conf, clin slug map.
---

# Theme directory layout

> Summary: config/themes/<slug>/ structure, required palette keys, generated ghostty.conf, clin slug map.

## Context
Themes migrated from flat `config/themes/<slug>.theme` files to directories;
the engine still falls back to the flat layout for half-migrated checkouts
(a few legacy `.theme` files remain, e.g. `dosbbs`, `matrix`).

## Details
- `config/themes/<slug>/palette.theme` — key=hex source of truth (bare hex,
  no `#`). Required keys (`CLAW_THEME_KEYS` in theme.sh): `bg bg_alt fg
  muted divider blue green purple amber red cyan`, plus `name=` and `slug=`.
- `config/themes/<slug>/ghostty.conf` — committed but GENERATED:
  `bash scripts/utils/theme.sh ghostty <slug>` (or `ghostty all`). The
  active theme's copy lands at `terminal/.config/ghostty/theme.conf`
  (git-ignored) via `theme.sh apply`.
- clin: `scripts/utils/clin.sh` maps slugs to clin-rs built-ins
  (`catppuccin-mocha`→`catppuccin_mocha`, `tokyo-night`→`tokyo_night`,
  `rose-pine`→`rose_pine`, `gruvbox-material`→`gruvbox`); unmapped slugs use
  clin's `default` + per-color overlay from `CLAW_C_*`.
- The harness skill `new-theme` (claude/harness/skills/) carries the full
  add-a-theme checklist.

## Related
- [One theme engine](../spine/one-theme-engine.md) — prerequisite: theme.sh is the only consumer-facing API over this layout.
