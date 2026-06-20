# Live Progress Panel — phase-driven status for long-running `claw` ops

> Design spec for an inline, themed, phase-driven progress surface that long-running
> `claw` operations render while they work.
> Brainstormed 2026-06-20. Extends the existing passive title-bar progress
> ([`shell/progress.zsh`](../../../shell/progress.zsh)) and consumes the theme
> engine ([`scripts/utils/theme.sh`](../../../scripts/utils/theme.sh), spine
> contract #2).
>
> **Status:** draft, pending operator review. Not yet decomposed into an
> implementation plan.

---

## 1. The problem

`claw pkg track`, `claw provision`, and `claw update` are long-running. Today the
only live signal is the **terminal title** — `shell/progress.zsh` backgrounds a
per-second updater that repaints `[profile] repo/subdir ⏳ 30s — cmd` into the
window title (OSC 0). That's the passive layer, and it works well.

What's missing is the **active layer**. The actual ops are bash scripts dispatched
through `bin/claw`; they stream `log_info`/`log_success` lines top-to-bottom with:

- no sense of **how far along** the op is (no `N/M`, no bar),
- no **semantic status** of what's happening right now (just raw log lines),
- no **health tally** (how many ok / failed / skipped),
- nothing **visually distinct** that reads as a first-class surface.

`claw_run` in `progress.zsh` exists but (a) is opt-in, (b) *hides* all output
behind a gum spinner until completion, and (c) isn't wired into the ops above.

## 2. What we're building

A new shared bash lib, **`scripts/utils/claw-progress.sh`**, that instrumented ops
source. It renders an inline, **pinned bottom status panel** showing the op's
overall progress bar, the **current item's phase** (`downloading` → `installing`
→ `verifying`), and a running health tally — framed in **viewfinder corner
brackets** for a distinct visual identity. Raw tool output (the noisy
`brew`/`cargo` stream) is captured to a logfile and never hits the screen.

It is **default-on** on a real TTY and degrades automatically to plain log lines
over SSH / pipes / CI. The render styles are **user-configurable** and persisted,
surfaced through new `claw output` setters and a new `claw config` menu.

### Locked decisions (from the brainstorm)

| Decision | Choice |
|---|---|
| Surface | Inline live progress, foreground |
| Render | Pinned bottom panel, **phase status** (not log-for-log) |
| Frame | Viewfinder corner brackets (`⌜ ⌝ ⌞ ⌟`, open edges), reusable primitive |
| Phase source | Explicit `claw_prog_phase` markers in the scripts |
| Architecture | Event file + single background renderer (sole terminal writer); owner/child election for multi-process `provision` |
| Default-on | Auto rich-mode on TTY; plain-log fallback on SSH/CI/`dumb`/`progress off`; reuses `CLAW_PROGRESS_ENABLED` |
| Theme | `theme.sh` `CLAW_C_*` with refined-dark fallbacks |
| Settings | `claw output {mode\|frame\|banner}` setters (mirror `claw theme set`) + new interactive `claw config` hub |
| Scope | Phase 1: `pkg track/scan/install`, `update`. Phase 2: `provision` two-tier |
| Raw output | Captured to `$XDG_STATE_HOME/claw/logs/`, never on screen |

## 3. Architecture — one contract, one renderer

The spine pattern ("one X") applies: **one progress contract, one renderer.**

```
 install scripts  ──emit events──►  $XDG_STATE_HOME/claw/progress/<runid>/events
 (provision, pkg,                          │
  toolchains)                       ┌──────┴───────┐
                                    │  renderer    │  ← the ONLY terminal writer
                                    │ (background, │     (no write races, ever)
                                    │  owner-only) │
                                    └──────┬───────┘
                                  viewfinder-framed panel + curated scrollback
```

The decisive invariant: **the renderer is the only thing that writes to the
terminal.** Emitting calls (`claw_prog_phase`, `claw_prog_ok`, …) append one line
to the run's event file; the renderer reads them and owns all painting. This is
what makes `provision`'s multi-process delegation work — it runs
`bash packages/common.sh`, `bash pkg-manifest.sh install all`, toolchain scripts
as **child processes**. Each child inherits an exported `CLAW_PROGRESS_RUN` run-id
and appends to the *same* event file, so there is exactly one panel no matter how
many nested `bash` calls run, and never two writers fighting over the bottom of
the screen.

Forward-compat note: that event file is already a structured job log. The
`claw jobs` dashboard considered-but-deferred in the brainstorm could consume it
later with no protocol change.

### State layout

```
$XDG_STATE_HOME/claw/progress/<runid>/events   # append-only event line-protocol
$XDG_STATE_HOME/claw/logs/<op>-<ts>.log         # captured raw tool output
```

### Event line-protocol

Plain text, pipe-delimited, append-only:

```
begin|<op>|<total>|<epoch>
stage|<label>|<total>          # multi-process outer tier (Phase 2)
item|<id>|<source>
phase|<phase>
note|<text>                    # transient sub-status, e.g. "312 crates"
ok|<id>|<msg>
fail|<id>|<msg>
skip|<id>|<msg>
log|<arbitrary line>           # curated scrollback line
end|<epoch>
```

The renderer maintains derived state (op label, total, done count, ok/fail/skip
tallies, current item + phase + note, start time) and repaints. On `ok`/`fail`/
`skip` it emits exactly one curated scrollback line above the panel.

## 4. The lib API (call-site surface)

```bash
source "$_U/claw-progress.sh"

claw_prog_begin "provision" 44          # op label, total (0 = indeterminate)
claw_prog_item terraform brew           # current item + source
claw_prog_phase download                # ⬇ downloading…
claw_prog_run install -- brew install terraform
                                        # set phase, run cmd with output → logfile,
                                        # tick spinner + live elapsed until it exits
claw_prog_ok                            # ✓ → scrollback line, bar advances, tally++
claw_prog_fail "network timeout"        # ✗ → red scrollback line, tally++
claw_prog_skip "already present"        # · → dim scrollback line, tally++
claw_prog_note "312 crates"             # transient sub-status on the panel
claw_prog_end                           # summary line, panel teardown, term restore
```

**`claw_prog_run`** is the workhorse. It launches the real command in the
background with stdout+stderr redirected to the run's logfile, then ticks the
panel (spinner + live elapsed) every ~1s until it exits, capturing the real exit
code. A 2-minute `cargo build` therefore shows a *moving* panel, not a frozen
label. (Same background-updater pattern `progress.zsh` already uses for the title.)
Single foreground writer in the single-process case; in the multi-process case the
owner's background renderer is the single writer and `claw_prog_run` in a child
just brackets `phase` + `ok`/`fail` events.

### Phase vocabulary

A themed glyph map; ops use the subset they need, extendable in one place:

```
scan 🔍 · download ⬇ · build ⚙ · install ⚙ · link 🔗 · verify ✓ · update ↻ · cleanup ✕
```

- `pkg track`/`scan` → `scan` (per source: brew → cargo → pipx → npm → diffing → writing)
- `pkg install` / `provision` → `download` → `install` → `verify`
- `update` → `update` per source

## 5. Rendering

### Viewfinder frame primitive

A reusable framing helper — `claw_frame_open "<title>"` / `claw_frame_close`, plus
`claw_card` for static blocks — draws the four viewfinder corner glyphs
(`⌜ ⌝ ⌞ ⌟`) with **open edges** (no horizontal/vertical rules between corners),
width from `$COLUMNS` / `tput cols`, corners colored via `CLAW_C_*`. ASCII
fallback: corners → `+`, or dropped entirely on `TERM=dumb` / non-UTF-8.

```
⌜                                              ⌝
   provision   ▓▓▓▓▓▓▓░░░  31/44 · 1m12s · ✓29 ✗0 !2
   ▸ terraform   ⬇ downloading            (brew)
⌞                                              ⌟
```

Scope of framing: **only content we render** — the progress panel, section
headers, the end-of-run summary card. Raw streamed tool output is *not* framed
(it's captured to a logfile and, by the no-log-spam decision, never on screen).
This deliberately avoids the bash footgun of measuring arbitrary lines' *display*
width (ANSI-stripping + emoji/CJK double-width accounting).

### Redraw technique

No scroll-regions (fragile across resize / non-cooperating programs). The panel is
always the last thing on screen. To emit a scrollback line or tick: cursor-up `H`
lines → clear-to-end-of-screen → (print the new line) → repaint the framed panel.
A `trap` on `EXIT`/`INT`/`TERM` restores the cursor and clears the panel so Ctrl-C
never leaves a corrupted tail.

## 6. Default-on + graceful degradation

`claw_prog_begin` decides the mode once:

| Condition | Mode |
|---|---|
| TTY **and** `CLAW_PROGRESS_ENABLED≠0` **and** `TERM≠dumb` **and** no `$CI` **and** `output.mode≠plain` | **rich** — event file + background renderer + framed panel |
| else (SSH-pipe, CI, `progress off`, `output.mode=plain`) | **plain** — each call prints one synchronous log line, no panel, no files |

Because the call sites are **identical** in both modes, instrumenting a script is
safe everywhere — which is exactly what lets the panel be default behavior.
`output.mode=rich` forces the panel even off-TTY (escape hatch); `auto` is the
default.

It reuses the existing `CLAW_PROGRESS_ENABLED` toggle from `progress.zsh` (one
toggle, not a second one). `progress off` will be bridged to `export` the var so
child bash processes see it.

## 7. Settings — `claw output` + `claw config`

Mirrors the theme engine's precedence chain exactly:
**`CLAW_OUTPUT_* env` (session override) → state file → default.** No parallel
store; same mechanism as `claw theme set`.

### Persisted keys

| Key | Values | Default | Meaning |
|---|---|---|---|
| `output.mode` | `auto` \| `rich` \| `plain` | `auto` | force/auto-detect the panel |
| `output.frame` | `viewfinder` \| `none` (+ other corner styles) | `viewfinder` | frame style; `none` = unframed panel |
| `output.banner` | `on` \| `off` (+ `CLAW_PROGRESS_BANNER_SEC`) | `on ≥10s` | the completion banner |

State file: `$XDG_STATE_HOME/claw/output` (sibling of `…/claw/theme`).

### Setters (mirror `claw theme set`)

```
claw output mode auto|rich|plain
claw output frame viewfinder|none
claw output banner on|off
claw output status            # show resolved values
```

### `claw config` hub (new front door)

A themed interactive menu (gum / FZF, viewfinder-framed) — the discoverable
options home. It **delegates**, it does not re-store: theme rows call the existing
`claw_theme_set`; output rows call the `claw output` setters above. Reserves the
already-defined-but-unused `CLAW_CONFIG_DIR`.

```
claw config
⌜                                  ⌝
   ▸ Theme        refined-dark
     Output mode  auto
     Frame        viewfinder
     Banner       on ≥ 10s
⌞   ↑↓ select · enter edit · esc done ⌟
```

## 8. Scope & phasing

### Phase 1 — lib + single-process ops (fast payoff)

- `scripts/utils/claw-progress.sh`: event protocol, renderer, viewfinder frame
  primitive, phase map, rich/plain mode detection, `trap` teardown.
- Instrument `scripts/utils/pkg-manifest.sh` (`track`/`scan`/`install`) and the
  `update` path. These are single-process loops → full panel immediately.
- **This alone resolves the original `claw pkg track` complaint.**
- `claw output` setters + state file + env precedence.

### Phase 2 — multi-process + settings hub

- Owner/child election (`CLAW_PROGRESS_RUN`) and `stage` events so `provision`
  shows a **two-tier** panel: a coarse outer stage bar
  (`Homebrew → base → toolchains → manifest → AI → fonts`) plus the inner
  per-tool phase from the delegated child scripts.
- `claw config` interactive hub delegating to `claw output` + `claw theme`.

## 9. Testing

The event protocol is plain text, so the lib is testable **headlessly** with no
TTY: feed a scripted event stream and assert (a) the **tally math**
(`ok`/`fail`/`skip`/`done` counts), and (b) the **plain-mode** rendered lines.
Rich-mode ANSI sequences can be asserted at the frame-primitive level (corner
placement, width padding, ASCII fallback) by capturing output with a forced
`COLUMNS` and `TERM`.

## 10. Spine alignment (invariants honored)

- **One dispatcher** — new subcommands (`claw output`, `claw config`) route through
  `bin/claw`; no second dispatcher.
- **One theme engine** — colors via `theme.sh` `CLAW_C_*` with refined-dark
  fallbacks; settings mirror its precedence chain.
- **One toggle** — reuses `CLAW_PROGRESS_ENABLED` / `progress off`; does not add a
  parallel enable flag.
- **Graceful degradation** — never pollutes non-interactive stdout (SSH/CI/pipe →
  plain mode), honoring the SSH-safety convention.
