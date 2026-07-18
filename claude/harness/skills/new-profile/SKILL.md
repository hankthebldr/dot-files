---
name: new-profile
description: Scaffold a new Open Claw workflow profile end-to-end across every registration surface — profile directory (meta/common/mac/linux), dispatcher, welcome TUI, claw-fn list, onboarding, bin/claw allowlist, rust TUI grouping, fastfetch config + logo, and optional toolchain. Use when the user says "new profile", "add a profile", or names a workflow that should become a claw profile. Prevents the classic half-wired profile (loads fine, missing from the TUI or onboarding).
disable-model-invocation: true
---

# New Profile Scaffold

Adding a profile touches **many hardcoded registration points**. A profile that
sources cleanly but is missing from one list silently degrades (no TUI entry,
no onboarding class, rejected by `claw <name>`). Work through every step; use
`pmo` as the canonical reference profile throughout.

## Inputs to collect first

- **slug** — lowercase, one word (`pmo`, `deck`, …)
- **class name** — RPG-style, uppercase (`SCRIBE-OPERATOR`, `NIGHTHACKER`)
- **theme** — existing slug from `config/themes/` for `PROFILE_THEME_DEFAULT`
- **TUI group** — which welcome-TUI section it belongs to (core / cloud+infra /
  knowledge / build …)
- **key tools** — 3-6 binaries the tool check should validate

## Checklist (do ALL of these)

### 1. Profile files — `shell/profiles/`

- `shell/profiles/<slug>.zsh` — 5-line dispatcher; copy `pmo.zsh` verbatim and
  change the directory name.
- `shell/profiles/<slug>/meta.zsh` — `PROFILE_NAME`, `PROFILE_CLASS`,
  `PROFILE_TIER`, `PROFILE_THEME_DEFAULT`, `PROFILE_TAG`, `PROFILE_FLAIR`,
  `PROFILE_OS_SUPPORT`, `PROFILE_TOOLCHAIN` (empty string if none),
  `PROFILE_KEY_TOOLS`.
- `shell/profiles/<slug>/common.zsh` — cross-platform aliases (grouped by
  category), `<slug>-help` styled card, `_<slug>_tool_check`. Use `platform.zsh`
  shims only — never raw `pbcopy`/`open`/`ipconfig`. Colors via `CLAW_C_*`,
  never hardcoded hex/ANSI.
- `shell/profiles/<slug>/mac.zsh` + `linux.zsh` — OS-specific extras (either
  may be a commented stub; the dispatcher sources them conditionally via
  `OS_FAMILY`).

### 2. Registration lists (grep for `pmo` to find the exact lines)

- `shell/welcome-tui.zsh` — three places: the group header line (`l1+=`), the
  entry line (`l2[<group>]+=`), the profile `case` allowlist (~line 291), and
  the glyph `case` (~line 591).
- `shell/claw-fn.zsh` — the "available:" profile list in the error message.
- `bin/claw` — the `tui:pick:(…)` allowlist regex.
- `scripts/utils/onboarding.sh` — class-name `case`, flavor-line `case`, and
  the three `for p in …` profile loops.
- `tui/claw-tui/src/main.rs` — the category-grouping `match` arm
  (`"vault" | "brainstorm" | "pmo" => …`); then `cargo build` in `tui/claw-tui`
  must pass.

### 3. Fastfetch dashboard — `config/.config/fastfetch/`

- `config-<slug>.jsonc` + `logo-<slug>.txt`. Specialized profiles are
  **hand-maintained** — copy the closest existing hand-maintained config
  (e.g. `config-pmo.jsonc`) and adapt the Tooling section.
- Only add it to `scripts/utils/gen-fastfetch.py` if it should become a
  generated core profile — then never hand-edit the output (a pre-tool-use
  hook enforces this).

### 4. Optional toolchain — `scripts/install/<slug>-toolchain.sh`

Only if the profile has installable packages. Follow an existing toolchain
script; set `PROFILE_TOOLCHAIN` in meta.zsh to match.

### 5. Docs

- `CLAUDE.md` — bump the profile counts (currently "18 profiles: 8 core + 10
  specialized") and the file-path table row.
- `README.md` / `QUICK-REFERENCE.md` — profile tables if present.

## Verify

```bash
zsh -n shell/profiles/<slug>.zsh shell/profiles/<slug>/*.zsh
claw <slug>            # bare-profile shorthand loads it
<slug>-help            # card renders
bats tests/            # nothing regressed
```

Commit at sensible boundaries: profile files, registrations, fastfetch, docs.
