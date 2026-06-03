# Spec Integration — Agentic Terminal Stack v1.0

> Source spec: `~/Downloads/dot-files-spec/SPEC.md` (Weeks 1–8 build).
> This doc reconciles the spec with the existing `dot-files` repo and re-sequences execution.

## 1. Platform stance

- **Primary host:** macOS Darwin (this box).
- **Secondary host:** Ubuntu/Debian desktop (Parrot OS for the spec's security edition use case).
- All `apt` lines in the spec are translated to `brew` on the Darwin branch via existing `shell/platform.zsh` shims (`$HOMEBREW_PREFIX`, `clip_copy`, `claw_open`, `local_ip`).
- New shell artifacts MUST use `platform.zsh` shims — no raw `pbcopy` / `ipconfig` / `xdg-open`.

## 2. Repo path resolution

| Spec path | Actual canonical | Status |
|---|---|---|
| `~/.dotfiles/` | `~/Github/Github_desktop/dot-files/` | `~/.dotfiles` is symlinked to canonical ✓ |

All spec references to `~/.dotfiles/...` resolve transparently. No move required.

## 3. Phase audit & merge decisions

| Phase | Existing % | Action |
|---|---|---|
| 1. Terminal foundation | ~70% | Skip Antidote (keep OMZ+P10k — repo convention). Defer Ghostty (brew issues; current terminal sufficient). LazyVim-equivalent already lives at `vim/config/nvim/` — symlink + dashboard add. |
| 2. Repo scaffold | ~90% | Verify `~/.dotfiles` symlink ✓. Skip Stow re-architecture — repo's symlink script works. |
| 3. Claude Code hardening | ~10% | Largest gap. Author `~/.claude/CLAUDE.md`, 2 hooks (pre/post tool-use), 5 skills, 4 slash commands, `scope.txt`, SQLite tool-use log. Source at `claude/` in repo, symlinked into `~/.claude/`. |
| 4. Foundational MCPs | ~30% | Currently connected: asana, figma, firebase, playwright, greptile (broken). Add per spec: filesystem (scoped), git, memory, fetch, smart-connections. Clean up greptile. Persist to `claude/mcp.json`. |
| 5. Hermes Agent | ~90% — built, not activated | **Scope narrowed** by the [2026-05-06 design](superpowers/specs/2026-05-06-hermes-openrouter-design.md) (decisions finalized 2026-06-02): local Ollama (`hermes3:8b`, `claw hermes --serve` auto-starts the daemon) + OpenRouter via `aichat` (default `claude-opus-4.7`). **Supersedes** the original Nous Portal / `hermes gateway` / tool-call fallback parser / MCP-mirror scope — all dropped (local-only decision). Code shipped in `416f193`; remaining work = small deltas + `claw install ai` activation, **BD790i first**. Tracked in [activation plan](superpowers/plans/2026-06-02-hermes-openrouter-activation.md). |
| 6. OSINT MCPs + Fabric | ~10% | Have httpx, nuclei. Add Fabric, subfinder, Shodan MCP, OSINT MCP, Security-Hub (Docker Desktop on macOS). |
| 7. OPSEC + recon | 0% | DontFeedTheAI install. `safeclaude`, `recon` shell functions in repo's `shell/security.zsh` (additive, never overwrite). |
| 8. Knowledge layer | ~50% | Have `shell/obsidian.zsh` + profile-aware vault routing. Add OSINT vault folder structure, Smart Connections MCP wiring, `lhermes`, aichat `--serve` (launchd on macOS, not systemd). |

## 4. Touch-don't-break rules

1. **Never overwrite existing `shell/*.zsh`.** Spec functions (`safeclaude`, `recon`, `lhermes`, `note`) are additive — placed in `shell/security.zsh` or new `shell/agents.zsh`.
2. **Welcome TUI / claw functions / fastfetch profiles stay as-is.** New spec functions register alongside.
3. **Backups before edit** to `~/.dotfiles-backups/$(date +%Y%m%d-%H%M%S)/` per repo convention.
4. **Conventional commits per phase** (e.g. `feat(claude): phase 3 hooks + skills + scope policy`).
5. **State-changing actions confirmed in chat** before execution.
6. **Visual standards inherited:** every new artifact uses GitHub Dark palette, gum styling, Nerd Font glyphs, fzf-driven TUIs where interactive. No bare echo.

## 5. Revised execution order

| # | Phase | Why this order |
|---|---|---|
| 1 | Reconciliation (this doc + ADR-001 + ADR-002) + LazyVim symlink | Bookkeeping + 1 visible win |
| 2 | Phase 3 — Claude hardening | Biggest gap, unblocks downstream |
| 3 | Phase 4 — Foundational MCPs | Required before OSINT MCPs (mental model) |
| 4 | Phase 8 partial — Smart Connections MCP | Same wiring as Phase 4 Obsidian server |
| 5 | Phase 5 — Hermes + OpenRouter (local-only; built `416f193`, activation pending) | Independent; unblocks dual-agent OSINT |
| 6 | Phase 6 — OSINT arsenal + Fabric | Builds on Phases 3–5 |
| 7 | Phase 7 — OPSEC layer + recon pipelines | Final agentic glue |
| 8 | Phase 8 complete — vault structure, lhermes, aichat-server | Sealing the loop |

## 6. Definition of done (mirrors SPEC §11)

- All 8 phase gates signed off in chat.
- Conventional-commit history per phase.
- ADR-001 + ADR-002 authored (this commit).
- `docs/runbook.md` covering cold-boot install, MCP key rotation, Hermes provider failover, OPSEC checklist (deferred until Phase 8).
- One real engagement (or controlled lab equivalent) executed end-to-end through the stack, findings in Obsidian vault.
