---
name: new-profile
description: "Use when the user says \"new profile\", \"add a profile\", or names a workflow that should become an Open Claw profile. Covers every registration surface (profile dir, dispatcher, meta.zsh registry fields, onboarding, rust TUI grouping, fastfetch config and logo, optional toolchain) to prevent the classic half-wired profile that loads fine but is missing from the palette or onboarding."
disable-model-invocation: true
---

# New Profile Scaffold

Most of the registration is now **derived**: `scripts/utils/registry.sh` reads
every `shell/profiles/<slug>/meta.zsh`, and the palette, `claw help` and shell
completion are generated from it. There is no menu file to edit — the fzf
welcome TUI was retired to `legacy/welcome-tui.zsh` in 2026-09. What is left to
do by hand is the profile directory itself, the two lint-enforced metadata
fields, and the handful of surfaces that still carry their own list. A profile
missing one of those still degrades silently (no onboarding class, no rust-TUI
group). Work through every step; use `pmo` as the canonical reference profile
throughout.

## Inputs to collect first

- **slug** — lowercase, one word (`pmo`, `deck`, …)
- **class name** — RPG-style, uppercase (`SCRIBE-OPERATOR`, `NIGHTHACKER`)
- **theme** — existing slug from `config/themes/` for `PROFILE_THEME_DEFAULT`
- **tier** — `PROFILE_TIER` 1-6, which becomes the palette group
  (1 core · 2 domain · 3 agent · 4 knowledge · 5 customer · 6 hardware)
- **glyph** — one Nerd Font glyph no other profile uses (`PROFILE_GLYPH`)
- **desc** — ≤40 chars, never names a sibling profile (`PROFILE_DESC`)
- **key tools** — 3-6 binaries the tool check should validate

## Checklist (do ALL of these)

### 1. Profile files — `shell/profiles/`

- `shell/profiles/<slug>.zsh` — 5-line dispatcher; copy `pmo.zsh` verbatim and
  change the directory name.
- `shell/profiles/<slug>/meta.zsh` — `PROFILE_NAME`, `PROFILE_CLASS`,
  `PROFILE_TIER`, `PROFILE_GLYPH`, `PROFILE_DESC`, `PROFILE_THEME_DEFAULT`,
  `PROFILE_START_DIR`, `PROFILE_TAG`, `PROFILE_FLAIR`, `PROFILE_OS_SUPPORT`,
  `PROFILE_TOOLCHAIN` (empty string if none), `PROFILE_KEY_TOOLS`.
  **`PROFILE_GLYPH` and `PROFILE_DESC` are what put the profile in the palette,
  in `claw help` and in completion — they are not decoration.** Both are
  enforced by `claw profiles lint` (non-empty, glyph unique across the tree),
  which runs in CI, as is `PROFILE_START_DIR` (`""` is a valid answer; the line
  must exist).
- `shell/profiles/<slug>/common.zsh` — cross-platform aliases (grouped by
  category), `<slug>-help` styled card, `_<slug>_tool_check`. Use `platform.zsh`
  shims only — never raw `pbcopy`/`open`/`ipconfig`. Colors via `CLAW_C_*`,
  never hardcoded hex/ANSI.
- `shell/profiles/<slug>/mac.zsh` + `linux.zsh` — OS-specific extras (either
  may be a commented stub; the dispatcher sources them conditionally via
  `OS_FAMILY`).

### 2. Registration — what is derived vs what you still edit

**Derived, do nothing:** the palette (bare `claw` / `claw menu` / `^G`),
`claw help`, `claw tui-stats` and shell completion all read
`scripts/utils/registry.sh`, which reads the `meta.zsh` files plus
`config/claw/actions.tsv`. A profile with a unique glyph and a desc shows up in
all four on its own. `shell/claw-fn.zsh`'s "available:" list is derived too
(`registry.sh ids profiles`), and so is the bare-profile shorthand `claw <slug>`.

**Still hand-maintained (grep for `pmo` to find the exact lines):**

- `scripts/utils/onboarding.sh` — class-name `case`, flavor-line `case`, and
  the three `for p in …` profile loops.
- `tui/claw-tui/src/main.rs` — the category-grouping `match` arm
  (`"vault" | "brainstorm" | "pmo" => …`); then `cargo build` in `tui/claw-tui`
  must pass.

Then run `scripts/utils/registry.sh check` (also enforced by
`claw profiles lint`) — it fails on a duplicate glyph or id, a missing field,
or a `run` that names a `claw` subcommand with no dispatch arm.

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
bash scripts/utils/profiles-lint.sh   # glyph/desc/start-dir contract
claw <slug>            # bare-profile shorthand loads it
claw                   # ...and the palette lists it, unprompted
<slug>-help            # card renders
bats tests/            # nothing regressed
```

Commit at sensible boundaries: profile files, registrations, fastfetch, docs.
