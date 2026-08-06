---
id: 20260718-profile-directory-contract
title: Profile directory contract
tags: [profiles, shell]
created: 2026-07-18
updated: 2026-07-19
related: [20260718-profile-registration-points, 20260718-one-theme-engine]
summary: The dispatcher + meta/common/mac/linux per-profile layout (post-dates CLAUDE.md's single-file description).
---

# Profile directory contract

> Summary: The dispatcher + meta/common/mac/linux per-profile layout (post-dates CLAUDE.md's single-file description).

## Context
CLAUDE.md describes profiles as single `shell/profiles/<name>.zsh` files;
the code moved to a directory-per-profile layout. Verified against `pmo`
on 2026-07-18.

## Details
- `shell/profiles/<slug>.zsh` — 5-line dispatcher: resolves
  `_PROFILE_DIR="${0:A:h}/<slug>"`, sources `meta.zsh` + `common.zsh`, then
  `${OS_FAMILY}.zsh` if present.
- `shell/profiles/<slug>/meta.zsh` — identity block: `PROFILE_NAME`,
  `PROFILE_CLASS` (RPG class, e.g. `SCRIBE-OPERATOR`), `PROFILE_TIER`,
  `PROFILE_THEME_DEFAULT`, `PROFILE_TAG`, `PROFILE_FLAIR`,
  `PROFILE_OS_SUPPORT`, `PROFILE_TOOLCHAIN` (empty = no installer),
  `PROFILE_KEY_TOOLS`.
- `shell/profiles/<slug>/common.zsh` — cross-platform aliases, the
  `<slug>-help` card, `_<slug>_tool_check`. platform.zsh shims and
  `CLAW_C_*` colors only.
- `shell/profiles/<slug>/mac.zsh` / `linux.zsh` — OS-specific extras; may be
  stubs.
- The harness skill `new-profile` (claude/harness/skills/) carries the full
  scaffold checklist.
- `claw profiles lint` (`scripts/utils/profiles-lint.sh`, 2026-07-19 hardening
  wave) validates the contract — every profile dir has the expected files and
  exports the required `meta.zsh` symbols.

## Related
- [Profile registration points](profile-registration-points.md) — prerequisite: files alone don't surface the profile anywhere.
- [One theme engine](../spine/one-theme-engine.md) — see-also: `PROFILE_THEME_DEFAULT` feeds the theme precedence chain.
