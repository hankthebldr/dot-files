---
id: 20260718-profile-registration-points
title: Profile registration points
tags: [profiles, shell]
created: 2026-07-18
updated: 2026-07-18
related: [20260718-profile-directory-contract, 20260718-one-dispatcher]
summary: Every hardcoded list a new profile must be added to.
---

# Profile registration points

> Summary: Every hardcoded list a new profile must be added to.

## Context
Profile names are hardcoded in several places; missing one produces a
half-wired profile that loads but is invisible or rejected somewhere.
Grep for an existing slug (e.g. `pmo`) to find the exact lines.

## Details
- `shell/welcome-tui.zsh` — four spots: group header (`l1+=`), entry line
  (`l2[<group>]+=`), profile `case` allowlist (~line 291), glyph `case`
  (~line 591).
- `shell/claw-fn.zsh` — the "available:" list in the bare-profile error
  message (~line 58).
- `bin/claw` — the `tui:pick:(…)` allowlist regex (~line 313).
- `scripts/utils/onboarding.sh` — class-name `case` (~421), flavor-line
  `case` (~447), and three `for p in …` loops (~471, ~623, ~642).
- `tui/claw-tui/src/main.rs` — category-grouping `match` arm (~line 203);
  requires `cargo build` to verify.
- fastfetch: `config-<slug>.jsonc` + `logo-<slug>.txt` (hand-maintained
  unless the profile is added to `gen-fastfetch.py`).

## Related
- [Profile directory contract](profile-directory-contract.md) — prerequisite: the files these lists point at.
- [One dispatcher](../spine/one-dispatcher.md) — see-also: claw-fn.zsh owns bare-profile shorthand.
