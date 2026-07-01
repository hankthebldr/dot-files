# claw upgrade — streaming process UX (design)

**Date:** 2026-06-30
**Status:** Approved (design) → pending implementation plan
**Author:** Henry + Claude
**Related:** `docs/superpowers/specs/2026-06-20-claw-live-progress-panel-design.md` (the original claw-progress engine)

## Problem

`claw upgrade` (alias of `claw update`, → `scripts/utils/system-update.sh`) appears to **hang**: it prints none of the install-log-level output while running; cancelling with Ctrl-C flushes buffered text to the screen. It is not a deadlock — it is a **visibility blackout**.

Root cause: `tui_run_step()` in `scripts/utils/tui-style.sh` runs every command as
`gum spin … -- bash -c "$cmd"`, which captures the command's stdout entirely and repaints only a dot spinner. The non-gum fallback path is no better — it pipes `>/dev/null`. So the upgrade path has **no live output by construction**. On macOS the first real step is `brew update` → `brew upgrade`, which runs for minutes with zero visible feedback → reads as a hang.

This also violates the user's stated goal: every `claw` CLI operation should be optimized for a detailed, power-user, "nerd-core" aesthetic that shows the process and steps, not hide them.

Secondary defects found while mapping:
- `tui-style.sh` hardcodes GitHub-Dark hex literals (`tui-style.sh:23-32`) instead of consuming the theme engine — violates the "one theme engine" spine rule (CLAUDE.md).
- `scripts/utils/claw-progress.sh` — the *intended* framed, step-level progress engine — is **only wired into `pkg-manifest.sh`**, reachable from `claw update` solely via `claw selfupdate now`. The visible `claw update` and `claw update --tools` paths never touch it.
- `claw-progress.sh`'s `_c()` helper (`claw-progress.sh:12-21`) returns the **raw `CLAW_C_*` hex string** (e.g. `58a6ff`) instead of an ANSI escape. Per the theme contract, `CLAW_C_*` is bare hex and truecolor requires the `CLAW_RGB_*` triplet. So `_c` only renders correctly via its 256-color *fallback* (when `CLAW_C_*` is unset); when a theme is loaded it emits literal hex into the output. The engine is not actually theme-reactive today.
- `claw-progress.sh`'s `claw_prog_run` (`:217-232`) redirects command output to a logfile in **both** plain and rich mode — so migrating to it *as-is* would trade gum's blackout for a panel blackout. The streaming behavior has to be built.

## Decisions (locked with operator)

1. **Render model: stream + collapse on success.** Live install-log output streams under each step while it runs; on success the step collapses to a single verdict line. Failures keep their output. (Chosen over "full firehose" and "tail viewport + pinned panel".)
2. **Scope: engine + both surfaces.** Fix the shared engine and wire both `claw update` (`system-update.sh`) and `claw update --tools` (`tool-updater.sh`).
3. Rewrite `tui_run_step` to delegate to the new streaming runner — approved, to kill the `gum spin` blackout for `integrity.sh` / `storage-doctor.sh` too (one render path), without changing their rounded-box chrome.
4. Live viewport cap ≈ 6 lines during a running step — approved.

## Architecture

### Home: `scripts/utils/claw-progress.sh`

The streaming engine and framed chrome live in `claw-progress.sh` (the spine's intended progress module). No new styling layer is created. `tui-style.sh` is retained for its non-update consumers but its run-step path is redirected here.

### Consumer migration

| Script | Before | After |
|--------|--------|-------|
| `scripts/utils/system-update.sh` | sources `tui-style.sh`; `tui_header`/`tui_section`/`tui_run_step`/`tui_skip`/`tui_footer`/`tui_pause` | sources `theme.sh` + `claw-progress.sh`; `claw_ui_header`/`claw_ui_section`/`claw_step`/`claw_ui_skip`/`claw_ui_footer`/`claw_ui_pause` |
| `scripts/utils/tool-updater.sh` (interactive mode) | same `tui_*` set | same `claw_*` set |
| `scripts/utils/tui-style.sh` | `tui_run_step` = `gum spin` blackout | `tui_run_step` = thin shim that sources `claw-progress.sh` and delegates to `claw_step` (chrome/header funcs unchanged) |

`integrity.sh`, `storage-doctor.sh`, `welcome-tui.zsh` keep calling `tui_run_step` unchanged and transparently gain streaming; their `tui_header`/`tui_section` rounded-box chrome is untouched.

### Public API added to `claw-progress.sh`

```
claw_step "<label>" -- <cmd...>       # run, stream, collapse-on-success; returns cmd rc; updates tallies
claw_ui_header "<TITLE>" "<subtitle>" # viewfinder frame_top + themed title; starts tally/timer
claw_ui_section "<Title>"             # dim sub-label (group divider; no frame)
claw_ui_skip "<name>"                 # "○ <name> — not installed" (dim)
claw_ui_footer "<✓ message>"          # tally summary (✓ok ✗fail ·skip · dur) + frame_bottom
claw_ui_pause                         # "press any key" when INTERACTIVE=1
```

Tally state reuses the existing `_CLAW_PROG_OK/FAIL/SKIP/DONE/T0` counters. `claw_ui_header` wraps `claw_prog_begin`-style init; `claw_ui_footer` wraps the `claw_prog_end` summary format (`✓4 ✗1 ·0 · 38.2s`).

### `claw_step` behavior

**Mode detection** reuses `_claw_prog_detect_mode` (honors `claw-output.sh` `mode`, tty check, `$CI`, `$TERM`).

**Rich mode (interactive tty):**
```
  ⏳ <label>…                       (amber running header — 1 physical row)
    │ <output line>                 (last ≤ TAIL_MAX=6 lines; each truncated to $COLUMNS-4; gutter dim)
    │ <output line>                 (moving viewport, redrawn in place)
  ● <label>   <summary?> · <dur>    (SUCCESS: whole block collapses to ONE green line)
```
On failure the block is kept and finalized as:
```
  ✗ <label>   <cmd-basename> (exit N)
    │ <last ≤6 error lines, retained>
```

**Plain mode:** each output line streams linearly with `│` gutter (no cursor motion), then a single verdict line. Pipe/CI safe.

**Full output** of every step is always appended to `$XDG_STATE_HOME/claw/logs/<op>-<ts>.log` (reuse `_claw_logfile`), regardless of mode, for post-run review.

### Implementation notes for `claw_step` (rich mode)

- Drive the read loop via **process substitution** so counter/ring-buffer state stays in the current shell:
  ```bash
  local rcf; rcf="$(mktemp)"
  while IFS= read -r line; do
      _claw_step_push "$line"     # ring buffer (last TAIL_MAX), truncate to width
      _claw_step_repaint          # cursor-up region_rows, clear-to-eos, reprint header+tail
  done < <( { "$@" </dev/null 2>&1; printf '%d' "$?" >"$rcf"; } | tee -a "$log" )
  rc="$(cat "$rcf")"; rm -f "$rcf"
  ```
  The command's rc is captured into `$rcf` inside the brace group (before `tee`), so it never pollutes stdout and `$?` is the command's, not `tee`'s.
- `region_rows` = `1 (header) + min(streamed, TAIL_MAX)`. Because every printed line is truncated to a single physical row, `region_rows` is exact — `\033[<region_rows>A` then `\033[J` (clear to end of screen) then reprint leaves no residue, even for wrapping-prone brew output.
- Truncation: strip to `COLUMNS-4` display columns; append `…` when cut. Compute width via `${COLUMNS:-$(tput cols)}`.
- Cursor hidden during a step (`\033[?25l`) and restored on completion; an `EXIT/INT/TERM` trap restores the cursor and tears down the live region (reuse the existing `_claw_prog_begin_rich` trap pattern).

### Theme fix

Rewrite `_c()` to build truecolor from `CLAW_RGB_*`:
```bash
_c() {  # _c <key> → ANSI truecolor (CLAW_RGB_<KEY>) or 256-color fallback
  local rgb; eval "rgb=\"\${CLAW_RGB_${1^^}:-}\""
  [[ -n "$rgb" ]] && { printf '\033[38;2;%sm' "$rgb"; return; }
  case "$1" in blue) printf '\033[38;5;75m';; green) printf '\033[38;5;78m';;
    red) printf '\033[38;5;203m';; amber) printf '\033[38;5;215m';;
    muted) printf '\033[38;5;245m';; purple) printf '\033[38;5;141m';; *) printf '';; esac
}
```
Keys used by the engine (`blue green red amber muted purple`) all exist in `CLAW_THEME_KEYS`. Case: `CLAW_RGB_*` keys are uppercase (`CLAW_RGB_BLUE`), so upper-case the arg.

### Safety guarantees (these resolve the "hang")

1. Every step runs with `</dev/null` on stdin — no invisible input block.
2. Output is streamed, never hidden — a slow step shows live lines; a prompt is visible.
3. Bounded, truncated redraw region — exact cursor math, no residue, never clears the full backlog.
4. `gum` is no longer on the update path at all (it was the blackout source).

## Out of scope

- `claw update --schedule` / `selfupdate.sh` — a scheduler installer, not an updater.
- `pkg-manifest.sh`'s existing `claw_prog_run` pinned-panel path — left as-is (separate surface).
- Re-theming `tui-style.sh`'s own hardcoded box colors for its remaining consumers — not required for this pass.

## Testing

- **Non-tty / plain mode:** `claw update 2>&1 | cat` — must stream linearly with gutter + verdicts, no escape-sequence garbage, no cursor jumps.
- **Success collapse:** a fast succeeding step (e.g. `brew cleanup`) collapses to one line.
- **Failure retention:** force a failing step (e.g. system `gem update --system` permission error on macOS) — output retained, `(exit N)` shown, run continues.
- **Width/wrap:** narrow the terminal to ~40 cols mid-run — lines truncate with `…`, no residue after collapse.
- **Theme reactivity:** `claw theme set gruvbox-material` then `claw update` — frame/glyph colors track the palette; no literal hex leaks.
- **ASCII fallback:** `TERM=dumb claw update` — glyphs degrade to ASCII, frame degrades to `+`/`-`.
- **Deadlock guard:** a step that reads stdin (synthetic `read x`) returns immediately instead of hanging.
- **Both surfaces:** repeat success/failure/plain checks for `claw update --tools`.
