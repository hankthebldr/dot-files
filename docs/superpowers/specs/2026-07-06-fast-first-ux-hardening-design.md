# Fast-first UX hardening (design)

**Date:** 2026-07-06
**Status:** Approved (design) → pending implementation plan
**Author:** Henry + Claude
**Related:**
- `docs/superpowers/specs/2026-06-30-claw-upgrade-streaming-ux-design.md` (amended by §3)
- `docs/FEATURE-BACKLOG.md` (P2 visual items re-ranked by §6)
- Deep-research validation run 2026-07-06 (105 agents, 24/25 claims confirmed; sources cited inline)

## Problem

Open Claw's ruling UX principle — **prompt usable near-instantly, heavy visuals
async or gracefully degraded** — was validated by adversarially-verified
research, but the system currently violates it in measurable ways:

1. **First paint blows the perception budget.** The blinded zsh-bench study
   (romkatv, [zsh-bench README](https://github.com/romkatv/zsh-bench)) puts the
   thresholds at **≤50ms first prompt lag / ≤150ms first command lag**; values
   under those are indistinguishable from zero. `claw-dashboard.py` renders in
   **~830ms wall** (measured M4 MBP, 2026-07-06), synchronously, at `.zshrc`
   step 3 — and everything sourced before the welcome TUI lands on first paint,
   because interactive TUIs cannot be deferred (deferred code cannot read
   stdin — [zsh-defer README](https://github.com/romkatv/zsh-defer), mechanical
   constraint). Open Claw disabled p10k instant prompt in favor of the TUI, so
   there is no masking mechanism: the pre-TUI path *is* the budget.
2. **The login strip has three independent writers.** Fact-of-the-day and the
   pkg-track nudge (`shell/delight.zsh`) plus the profile banner each print on
   their own schedule with no shared line budget — the stacking friction
   already logged in `FEATURE-BACKLOG.md`.
3. **No color-degradation contract.** No surface honors
   `NO_COLOR` / `CLICOLOR` / `CLICOLOR_FORCE`
   ([no-color.org](https://no-color.org/),
   [bixense.com/clicolors](http://bixense.com/clicolors/)) — the settled
   ecosystem spine for piped/CI/SSH degradation.
4. **The approved streaming-engine spec predates the research** and lacks three
   practices the industry converged on (steady non-TTY cadence, atomic frames,
   synchronized output).

Non-goals: ratatui M3–M5, the discoverability wave (both returned **zero**
surviving research claims — blocked on a second research pass), any change to
the fzf menu itself.

## Design

### §1 Measurement baseline (S)

Instrument before touching. A `CLAW_PROFILE_STARTUP=1` guard in `shell/.zshrc`
stamps `$EPOCHREALTIME` at each numbered step (1, 2, 2b, 3, 5, 6, 7, 8) and
prints a per-step ms table after init. Zero cost when unset (single `[[ -n`
check per stamp). Additionally decompose the dashboard's ~830ms:
time `ff-readout.sh fields` (fastfetch subprocess) separately from the python
render.

Baselines recorded in this doc's **Appendix A** (M4 MBP local + SSH →
BD790i) before §5 lands, and re-run after as the acceptance gate.

### §2 Login strip consolidation (S/M)

One renderer, `claw_login_strip`, owns a **≤3-line budget**. Contributors
*register* lines instead of printing:

- `claw_strip_add <priority> <line>` appends to an array during init;
  priorities: `banner` (profile/session banner) > `nudge` (pkg-track) >
  `fact` (fact-of-the-day).
- The strip renders once, at the point the current banner prints today:
  dedupes, sorts by priority, truncates to 3 lines (dropped lines are simply
  not shown — lowest priority first), then emits in a single write.
- **Local-cache-only contract:** every registered line must come from a local
  file read or in-memory state — never a network fetch or subprocess pipeline
  at login (research: pre-prompt code must not "take unpredictably long",
  zsh-defer/instant-prompt fast-section rule). The existing `facts.txt` native
  read and the cached nudge count already comply; this makes it structural.

Existing writers in `delight.zsh` convert to `claw_strip_add` calls. The strip
is skipped entirely in non-interactive/SSH-pipe shells (same guard as today's
fact stamp).

### §3 Streaming-engine refinements (amendment to 2026-06-30 spec)

The approved stream-and-collapse design stands. Three additions, folded into
the same `claw-progress.sh` work — implement together, not as a follow-up:

- **(a) Steady non-TTY cadence.** In plain mode, long-running steps emit a
  heartbeat line (`… <label> still running (Ns)`) at a **fixed ≥1s minimum
  interval** — never time-escalating thinning. Precedent: Bazel classified
  escalating delay as a bug and removed it in 6.0.0
  ([bazelbuild/bazel#16119](https://github.com/bazelbuild/bazel/issues/16119)).
- **(b) Atomic frames + synchronized output.** Every rich-mode repaint is
  composed off-screen and flushed as **one write**. When the terminal supports
  DEC private mode 2026, wrap the frame in `CSI ? 2026 h` … `CSI ? 2026 l`
  (Synchronized Output — [WezTerm escape-sequences
  doc](https://wezterm.org/escape-sequences.html); supported by Ghostty,
  WezTerm, kitty, iTerm2). Detection: `TERM_PROGRAM`/`TERM` allowlist
  (`ghostty`, `WezTerm`, `iTerm.app`, `xterm-kitty`), degrade silently — the
  sequences are ignored gracefully elsewhere, but the allowlist avoids noise
  in dumb terminals.
- **(c) Citations attached to the render model.** Stream-while-running +
  collapse-on-success + expand-on-failure is the BuildKit-converged pattern
  ([moby/buildkit#824](https://github.com/moby/buildkit/issues/824), fixed by
  PR #916); gum spin's blackout is its *documented default* (`--show-output`
  is opt-in), so the migration off `tui_run_step`'s gum path is a correction,
  not a preference. Note the refuted stronger claim: pre-fix BuildKit tty mode
  did **not** suppress output "entirely" — cite the collapse/expand behavior,
  not total suppression.

### §4 Color degradation contract (S)

One function in `scripts/utils/theme.sh`:

```
claw_color_enabled()   # rc 0 = emit color, rc 1 = plain
```

Precedence (settled ecosystem order):
1. `NO_COLOR` set (non-empty, any value) → **no ANSI, ever** (no-color.org).
2. `CLICOLOR_FORCE` set non-zero (and NO_COLOR unset) → color even to
   non-TTY (bixense CLICOLOR spec).
3. Otherwise → color iff stdout `isatty` (`[[ -t 1 ]]`).

When disabled, `theme.sh` exports every `CLAW_RGB_*` / `CLAW_C_*` as **empty**
and `claw_theme_fzf` emits no `--color` args — so the dashboard, progress
panel, fzf strings, and clin render all inherit the contract with zero
per-surface changes (this is the payoff of the one-theme-engine spine rule).
The rust TUI reads the same state via `tui/claw-tui/src/theme.rs` and needs a
matching empty-value guard. `CLAW_THEME` persisted state does **not** override
`NO_COLOR` — a stored theme is not per-instance consent to colorize (per
no-color.org precedence guidance).

### §5 Dashboard first-paint: cached-fields render (M)

- `ff-readout.sh fields` output is written to
  `$XDG_STATE_HOME/claw/readout.cache` (atomic mv) on every successful
  collection.
- Login render path: if the cache exists, `claw-dashboard.py` paints
  immediately from it — python + string formatting only, target **<100ms** —
  and kicks a fully-detached background refresh (`ff-readout.sh fields >
  cache.tmp && mv`) for the *next* paint. No job-control output (same
  `NOTIFY`-suppression pattern the welcome TUI already uses).
- Volatile fields (cpu/mem/disk pct bars) show cached values — acceptable for
  a login snapshot. A dim `as of <rel-time>` marker renders only when the
  cache is older than **1h**.
- Cold path (no cache — fresh install, cleared state) falls through to
  today's synchronous render, which seeds the cache.
- The fastfetch `config.jsonc` fallback and the no-python zsh quickref
  fallback are untouched.

### §6 Backlog dispositions

Applied to `docs/FEATURE-BACKLOG.md` as part of this wave:

| Item | Disposition | Basis |
|---|---|---|
| `tte` intro animation on login | **Rescoped** → manual `claw intro` showpiece command; never runs at login | Hundreds of ms of pre-prompt TTY time by design; blows the 50ms budget |
| Fact-of-the-day / per-profile MOTD | **Keep** with local-cache-only constraint (§2) | Fast-section rule: no network/unpredictable work pre-prompt |
| Live k8s/docker counts on tick (ratatui) | **Approved with guardrails**, deferred to M3: background sampling off the render path, atomic mode-2026 frames, static non-TTY fallback | nom/WezTerm findings |
| fzf↔ratatui readout convergence; shared readout component | **Unblocked as judgment call** — consistent with one-render-path spine; no external evidence either way | Research returned zero surviving claims on ratatui practice |

## Error handling

- Instrumentation (§1): stamps are no-ops when the guard is unset; a missing
  `EPOCHREALTIME` (ancient zsh) silently disables the table.
- Strip (§2): a contributor that fails to register loses its line — the strip
  never blocks login; empty registry → nothing printed.
- Progress (§3): mode-2026 wrap only inside the allowlist; heartbeat timer
  failure degrades to today's silent plain mode.
- Theme (§4): `claw_color_enabled` defaults to color-on-TTY if the env is in a
  contradictory state (both NO_COLOR and CLICOLOR_FORCE → NO_COLOR wins).
- Dashboard (§5): corrupt/empty cache → treated as cold path; background
  refresh failure leaves the previous cache in place (atomic mv).

## Testing

- **bats:** strip budget/priority/truncation matrix; `claw_color_enabled`
  precedence matrix (NO_COLOR × CLICOLOR_FORCE × tty); cache
  cold/warm/stale/corrupt paths; heartbeat cadence (fake clock).
- **Acceptance:** re-run §1 instrumentation on both machines; pre-TUI init
  within the 50ms-order budget and dashboard warm paint <100ms. Record in
  Appendix A.

## Appendix A — Baselines

*(filled during implementation)*

| Step | M4 MBP (ms) | BD790i via SSH (ms) |
|---|---|---|
| pre-TUI init (steps 1–2b) | — | — |
| dashboard cold render | ~830 (2026-07-06) | — |
| dashboard warm (cached) render | — | — |
