# Discoverability & delight wave (draft design)

**Date:** 2026-07-06
**Status:** DRAFT — discoverability core blocked on a research pass (see Gate); the two delight items (§3) are unblocked and can be planned any time
**Author:** Henry + Claude
**Related:**
- `docs/superpowers/specs/2026-07-06-fast-first-ux-hardening-design.md` (§6 rescoped `tte` intro to this wave)
- `docs/FEATURE-BACKLOG.md` P2 "Visual / delight packs" + UX-WALKTHROUGH friction "delight helpers discoverable only by reading delight.zsh"
- Deep-research run 2026-07-06: **zero claims on CLI discoverability survived verification** — items below marked *(unverified lead)* came from fetched-but-unverified sources (clig.dev, navi/tldr writeups, bettercli.org)

## Intent

Make the ~680 lines of aliases, 18 profiles, and the delight pack findable
without reading source — and give the showpiece visuals a proper home that
never touches the login path (fast-first spec is the ruling constraint).

## Scope

### §1 Fuzzy cheat layer (M) — the core bet

An fzf-searchable, locally-cached cheat corpus over Open Claw's own surface:

- Source of truth: generate cheat entries from what already exists —
  `aliases.zsh` (comment-annotated), each profile's `<name>-help` card,
  `delight.zsh`, `claw help` groups — rather than hand-maintaining a second
  list. A small generator (mirroring `gen-fastfetch.py`'s single-source
  pattern) emits a cheat corpus file; `claw cheatsheet` grows an interactive
  `--fzf` mode over it.
- *(unverified lead)* navi-style fuzzy search over a curated personal corpus
  beats man/`--help` grepping for infrequent commands; tldr-style local
  caching keeps it SSH/offline-safe. Both fit the existing stack (fzf, no new
  runtime deps) even if the research pass adjusts details.
- Keybinding: a zsh widget (e.g. `^G`) opens the cheat search and inserts the
  chosen command at the prompt — discoverability at the point of need, zero
  login cost.

### §2 Help design pass (S/M)

- *(unverified lead — clig.dev / bettercli.org)* top-level `claw help` should
  answer three questions immediately: what it does, where to begin, how to
  learn more; help should teach workflows ("suggest what command to run
  next"), not just list flags.
- Concrete candidate: each `claw <cmd> --help` ends with a themed "next
  steps" line (e.g. `claw pkg scan` → suggests `claw pkg track --commit`).
  The interop loop (scan → track → update → provision) becomes visible in
  help text, not just in docs.
- Fold the delight pack (`cpv`/`mvv`/`dlv`/`xtract`/`weather`) into `claw
  cheatsheet` + `claw help` groups (long-standing walkthrough friction).

### §3 Delight items — unblocked now

- **`claw intro` (S):** the rescoped `tte` showpiece — animated OPEN CLAW
  reveal as a manual command only. Guarded on `command -v tte`; degrades to
  the static logo cat. Never wired into login (fast-first §6 disposition).
- **`pokeget`/`onefetch` MOTD options (S):** toggleable personality for the
  login strip — must register through `claw_login_strip` (fast-first §2) and
  obey its local-cache-only contract: any fetch happens in a background
  refresh job, never at login.

## Constraints inherited

- Login path is frozen by the fast-first spec: nothing in this wave adds
  pre-prompt work. All discoverability surfaces are on-demand (command,
  widget, TUI entry).
- Color output goes through `claw_color_enabled` (fast-first §4).
- Cheat corpus generation must not create a second source of truth — it
  derives from the existing alias/help/profile files.

## Gate — research pass required for §1–§2

The 2026-07-06 run's open question, verbatim: *what do clig.dev, tldr /
navi / cheat, carapace / inshellisense, and the charm/gum ecosystem actually
converge on for making 680 lines of aliases and 18 profiles discoverable?*
Run a focused deep-research pass on that before writing the implementation
plan for §1–§2. §3 needs no gate.

## Acceptance sketch

- A newly-added alias with a doc comment appears in `claw cheatsheet --fzf`
  after regeneration with zero extra bookkeeping.
- `^G` from an idle prompt to an inserted command in under a second, offline.
- `claw intro` runs the reveal on demand; `time zsh -lic exit` unchanged
  before/after this wave (login budget untouched).
