---
id: 20260718-one-dispatcher
title: One dispatcher
tags: [spine, shell]
created: 2026-07-18
updated: 2026-07-18
related: [20260718-profile-registration-points]
summary: The single claw() function, what stays in-shell, and how bin/claw routes.
---

# One dispatcher

> Summary: The single claw() function, what stays in-shell, and how bin/claw routes.

## Context
A previous duplicate `claw()` in aliases.zsh was dead-shadowed for weeks.
This invariant exists so that never recurs.

## Details
- `shell/claw-fn.zsh` defines the ONLY `claw()` shell function.
- In-shell work (must mutate the current shell): no-args TUI relaunch,
  `load`/`off`, and bare-profile shorthand (`claw security` ≡ `claw load security`).
- Everything else passes through to `bin/claw` (bash), which routes to
  `scripts/`.
- `claw update` is the one updater front door (`--tools` → tool-updater,
  `--schedule` → selfupdate).
- Superseded scripts are archived in `legacy/` (see `legacy/README.md`) —
  never left as strays.

## Related
- [Profile registration points](../profiles/profile-registration-points.md) — see-also: claw-fn.zsh carries one of the hardcoded profile lists.
