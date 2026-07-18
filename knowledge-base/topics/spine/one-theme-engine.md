---
id: 20260718-one-theme-engine
title: One theme engine
tags: [spine, themes]
created: 2026-07-18
updated: 2026-07-18
related: [20260718-theme-directory-layout]
summary: theme.sh as sole color source and the CLAW_THEME precedence chain.
---

# One theme engine

> Summary: theme.sh as sole color source and the CLAW_THEME precedence chain.

## Context
Every surface (prompt, dashboards, fzf, rust TUI, clin) must consume the same
palette variables; hardcoding hex/ANSI in a surface breaks theme switching.

## Details
- `scripts/utils/theme.sh` is the single source of truth; sourced by
  `.zshrc` step 2b.
- Precedence: `CLAW_THEME` env (session override, set by profile loads via
  `PROFILE_THEME_DEFAULT` in the profile's `meta.zsh`) →
  `$XDG_STATE_HOME/claw/theme` (persisted `claw theme set`) → refined-dark.
- Surfaces consume `CLAW_RGB_*` / `CLAW_C_*` / `claw_theme_fzf`, with
  refined-dark fallbacks where the engine may not be loaded yet.
- The rust TUI reads the same persisted state in `tui/claw-tui/src/theme.rs`
  — no per-theme rust code.
- `claw theme set <slug>` also re-renders clin's config and the active
  Ghostty include.

## Related
- [Theme directory layout](../themes/theme-directory-layout.md) — supports: the on-disk format this engine parses.
