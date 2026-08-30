---
name: new-theme
description: "Use when the user says \"new theme\", \"add a palette\", or names a color scheme to bring into Open Claw. Covers the whole spine — palette.theme key set, generated ghostty.conf, clin built-in slug map, and per-surface verification — because a partial add silently falls back to refined-dark on some surfaces."
disable-model-invocation: true
---

# New Theme Scaffold

`scripts/utils/theme.sh` is the single theme engine; every surface (prompt,
dashboards, fzf, rust TUI, clin) consumes `CLAW_C_*` / `CLAW_RGB_*` parsed
from one palette file. A theme is "added" only when all the steps below are
done — a missing key or unrendered ghostty.conf degrades quietly.

## 1. Palette — `config/themes/<slug>/palette.theme`

Directory layout (`<slug>/palette.theme`), NOT the legacy flat
`<slug>.theme`. Copy `config/themes/refined-dark/palette.theme` as the
template. Required keys (from `CLAW_THEME_KEYS` in `theme.sh`):

```
name=<Display Name>
slug=<slug>
bg bg_alt fg muted divider blue green purple amber red cyan
```

- Values are **bare hex, no leading `#`**.
- Every key must be present — surfaces index the full set.
- Add a short header comment describing the palette's character (see the
  existing files for tone).

## 2. Ghostty include — generated, not hand-written

`theme.sh` renders `config/themes/<slug>/ghostty.conf` from the palette and
the file is committed. Run the engine rather than authoring it:

```bash
bash scripts/utils/theme.sh ghostty <slug>   # render one theme's ghostty.conf
bash scripts/utils/theme.sh ghostty all      # or rebuild the whole library
```

## 3. Clin slug map — `scripts/utils/clin.sh`

If clin-rs ships a built-in theme matching this palette, add a mapping in
the slug `case` (~line 41, e.g. `catppuccin-mocha) printf 'catppuccin_mocha'`).
If not, skip — clin falls back to `default` + the per-color overlay from
`CLAW_C_*`, which already tracks the new palette.

## 4. Things you do NOT need to touch

- `tui/claw-tui/src/theme.rs` — reads persisted theme state at runtime; no
  per-theme code.
- Profile files — but if the theme was made FOR a profile, set that profile's
  `PROFILE_THEME_DEFAULT` in `shell/profiles/<profile>/meta.zsh`.

## Verify

```bash
claw theme list              # new slug appears
claw theme preview <slug>    # swatch renders all 11 keys
claw theme set <slug>        # activates; re-renders clin config + ghostty include
exec zsh                     # prompt/dashboard pick it up
claw theme set refined-dark  # restore unless the user wants to keep it
```

Commit: palette + generated ghostty.conf together; clin map separately if
touched.
