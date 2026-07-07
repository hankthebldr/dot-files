# Ratatui flagship parity — M3–M5 + readout convergence (draft design)

**Date:** 2026-07-06
**Status:** DRAFT — blocked on a dedicated ratatui research pass (see Gate below); do not start implementation planning until the gate clears
**Author:** Henry + Claude
**Related:**
- `docs/superpowers/specs/2026-07-06-fast-first-ux-hardening-design.md` (predecessor wave; §6 dispositions feed this doc)
- `docs/FEATURE-BACKLOG.md` P2 "Ratatui TUI to parity (Wave 4 M3–M5)"
- Deep-research run 2026-07-06: **zero claims on ratatui ecosystem practice survived verification** — everything sourced here from that run is marked *(unverified lead)*

## Intent

Make the ratatui front-end (`tui/claw-tui/`) the flagship surface: visual
parity with the fzf path, then depth the shell sub-TUIs can't match (live
refresh, richer navigation), without ever breaking the fzf/no-binary fallback
(spine invariant: everything additive and guarded).

## Scope (carried from backlog, ordered)

1. **Visual convergence first (cheap, high-impact — confirmed P1-of-P2):**
   - Render the same `logo-*.txt` truecolor art in the TUI (`ansi-to-tui` or
     equivalent) — kill the plain block-ASCII divergence.
   - Readout already converged on `fastfetch --format json` (done per
     backlog); extend to a **single shared readout component** consumed by
     welcome screen and any future dashboard screen. Judgment call unblocked
     by the fast-first spec §6: consistent with the one-render-path spine
     rule even without external evidence.
2. **M3 — tunnels + homelab screens (L):** port `tunnel-manager.sh` topology
   (Block chain, live `ssh -O check` on tick) and `homelab.sh` (ssh_config
   parse + preview pane); `EXEC` outcome for TTY handoff.
3. **M4 — mcp + toolkit screens (M):** `mcp.toml` /
   `claude_desktop_config.json` via serde_json; toolkit launcher tree.
4. **M5 — CI release binaries (M):** `tui-release.yml` (macOS arm64 + Linux
   x86_64/arm64 musl); `claw install claw-tui` downloads a verified binary.
5. **Live refresh (S):** k8s context / docker counts on tick — **approved
   with guardrails** by the fast-first research:
   - expensive sampling (kubectl/docker CLI) runs on a background task,
     never on the render path;
   - each frame is one atomic write, wrapped in DEC mode 2026 where the
     terminal supports it (same allowlist as `claw-progress.sh` §3b);
   - static readout fallback when stdout is not a TTY.

## Constraints already settled (inherit, do not re-derive)

- **Theme:** the TUI reads the same persisted theme state
  (`tui/claw-tui/src/theme.rs`); must honor the `claw_color_enabled` contract
  from the fast-first spec §4 (NO_COLOR → monochrome rendering).
- **Terminal safety** *(unverified lead — validate in research pass)*: alt
  screen, panic-safe terminal restore, SIGWINCH, SIGTSTP handling as the four
  non-negotiables for any TUI.
- **Architecture** *(unverified lead)*: ratatui official docs endorse a
  Component-trait architecture (each component owns state/events/render, mpsc
  Action channel for tick propagation); the old `ratatui/async-template` is
  archived — source patterns from `ratatui-org/templates` instead.

## Gate — research pass required before implementation plan

A dedicated deep-research pass must answer (from the 2026-07-06 run's open
questions):

1. What tick-rate, event-loop, keybinding-overlay, and theme-propagation
   patterns do btop / k9s / lazygit / atuin actually use?
2. Does ratatui 2025–2026 have a settled convention for reusable themed
   widgets that `theme.rs` should follow?
3. Confirm/refute the two *(unverified lead)* items above.

Gate clears when that pass produces verified findings and the operator signs
off the ordering above in chat.

## Acceptance sketch

- fzf path and ratatui path visually indistinguishable on the welcome screen
  (same logo art, same readout data, same theme).
- All M3/M4 screens degrade: binary missing → shell sub-TUIs unchanged.
- `TestBackend` snapshots extended to the new screens (existing test pattern).
