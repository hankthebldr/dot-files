# Ghostty Experience Overhaul — Title, Tabs, Clipboard, Font

- **Status:** Approved (operator, 2026-07-18)
- **Problem statement (operator, verbatim intent):** the MBP Ghostty window
  top shows neither the current working path nor the activated sub-profile;
  window controls / tab creation / tab navigation aren't behaving like the
  previous BD790i implementation; copy/paste, window management, and
  text/font are unoptimized end to end.
- **Key context:** the repo config is already sophisticated and *claims* the
  right behavior — `~/.config/ghostty` symlinks into the repo, `no-title`
  hands title authorship to `shell/progress.zsh` (which sets
  `[profile] user@host: cwd` on precmd), and `os-macos.conf` sets
  `macos-titlebar-style = tabs`. The symptoms therefore indicate a broken
  chain between repo and the running app, not missing config.

## Gate 0 — diagnose on live hardware (evidence before edits)

Run on the MBP, record results in the plan before changing anything:

1. `ghostty +version` — rule out an app build predating the config surface.
2. Diff `ghostty +show-config` against the repo files — proves what the app
   actually loaded (includes, os-active symlink, keybinds).
3. Inspect/remove the stray shadow file
   `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`
   (0 bytes, nonstandard name — likely a mis-saved in-app edit). Confirm
   whether the app also reads an App Support `config` that shadows XDG.
4. In a live shell: `print -l $precmd_functions` — is
   `__claw_progress_reset_title` registered? Then `printf '\e]0;TEST\a'` —
   does the titlebar render shell-set titles at all?
5. Restart Ghostty fully (window-chrome options only apply to new windows).

Every fix below is conditioned on this evidence; the gate output decides
which fixes are config, which are shell, and which are "restart the app".

## 1. Title contract

Outcome: titlebar/tab shows `[<profile>] user@host: cwd`, updating on every
prompt — including after `claw load <profile>` and `cd`.

- Fix whatever Gate 0 implicates: precmd hook registration/order, any gating
  env var, shadow-config interference, or `shell-integration-features`
  merge semantics on the installed version.
- Keep `no-title` + progress.zsh as sole title author (the design is right;
  the wiring is the bug).
- Acceptance: new tab → title correct; `claw load security` → title shows
  `[security]` on next prompt; `cd` → path updates. Verified on macOS AND
  via SSH from the BD790i.

## 2. Window controls & tab management (macOS)

- Verify `macos-titlebar-style = tabs` renders native controls + draggable
  tab strip after restart; if the installed version misbehaves with `tabs`,
  fall back to `native` (decision recorded in the plan).
- **Move quick terminal off `cmd+backquote`** → `global:ctrl+backquote`.
  The current `global:cmd+backquote` steals macOS's native window-cycling
  shortcut system-wide — a confirmed config bug and likely the core of
  "window management feels wrong".
- Add muscle-memory tab cycling: `ctrl+tab` → `next_tab`,
  `ctrl+shift+tab` → `previous_tab` (cross-platform section; existing
  `cmd+shift+[`/`]` binds stay).
- Confirm `cmd+t` / `cmd+w` / `cmd+shift+w` / `cmd+1..9` behave; document
  the final keymap in the config header comment.
- BD790i parity: os-linux.conf (gtk-titlebar, tabs top, single-instance,
  Ctrl+Shift C/V) is already correct — verify untouched, spot-check next
  time on the box.

## 3. Copy/paste ergonomics

- `copy-on-select = clipboard` → `true`: drag-select stops silently
  overwriting the macOS system clipboard (Linux keeps selection-buffer
  semantics). This is the approved behavior change.
- Drop the surprising `cmd+x = copy_to_clipboard` remap.
- Keep `clipboard-paste-protection = true`, but verify during Gate 0 that
  its confirmation prompt isn't the "broken paste" being felt; if it fires
  on routine multi-line pastes, relax to trim + keep protection only for
  control-char payloads (as the installed version allows).

## 4. Text / font

- Per-OS `font-size`: macOS layer ~13pt for the MBP Retina panel (validated
  side-by-side at implementation, 12-14 range), Linux layer stays 10-11pt.
  Base config keeps the family; sizes move to the OS layers.
- Revisit `font-feature = "-calt"` (ligatures currently disabled): render a
  ligature sample both ways at implementation; operator picks. Default if
  no preference: keep ligatures off (current behavior).
- `font-thicken` (macOS) stays; `adjust-cell-height` revisited only if the
  13pt bump makes rows feel cramped.
- Note: per machine-local convention, anything truly host-specific
  discovered here goes in an os-layer comment, not hardcoded one-off values.

## 5. Drift guard

Extend `claw validate` with a Ghostty chain check: `~/.config/ghostty`
symlink resolves into the repo, `os-active.conf` points at the right OS
layer, `theme.conf` exists (or warn "run claw theme build"), and no App
Support shadow config exists on macOS. Prevents "config says X, app does Y"
from recurring silently.

## Testing

Gate 0 evidence recorded in the implementation plan. Section acceptance
checks are manual-visual by nature (titlebar, tabs, font) — each lands with
a one-line "verified on MBP" note in the commit body. The validate check
gets a bats case with a faked home tree.

## Out of scope

tmux titlebar interplay, Apple Terminal mbp-m4 profile, Ghostty shaders,
theme palette work (owned by the theme feature spec), any BD790i-side GTK
changes beyond verification.

## Sequencing

Independent of the hardening wave (different files); may land in parallel.
Gate 0 + sections 2-4 are config-only and fast; section 1 may touch
shell/progress.zsh; section 5 touches scripts/utils/validate-install.sh.
