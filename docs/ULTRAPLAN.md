---
title: Open Claw — Ultra-Plan
project: dot-files
status: living
created: 2026-06-06
tags: [open-claw, dotfiles, roadmap, tui, ratatui, spec]
vault_path: Github-Projects/dot-files/ULTRAPLAN.md
---

# Open Claw — Ultra-Plan

> The single source of truth for taking Open Claw from "half-baked, semi-functional"
> to the most sophisticated swiss-army-knife TUI on the market: a modern, visually
> delightful, hardware-aware terminal experience that provisions a fresh Linux/macOS
> box in one pass, runs all our agentic harnesses complementarily, and wires the
> Things 3 / Claude / Obsidian workflow spine together.

## 0. North star

Each element must **earn its place** by improving the experience visually or
functionally. No dormant tools, no half-wired paths. The product is:

1. **One-pass provisioning** — a fresh Parrot/Ubuntu box → fully loaded in one command.
2. **Curated per-profile loadouts** — design-specific TUI/CLI tools + helpers + context.
3. **Daily-driver delight** — progress bars on cp/downloads, fact-of-the-day, custom ASCII, fast modern replacements.
4. **Self-supporting** — tool management, one-command self-update, guided wizard, integrity.
5. **Foundational solidity** — secret storage, SSH tunneling, aliases, cross-platform shims.
6. **Agentic-first** — open-claw + hermes + claude-code + gemini-cli + local harnesses, complementary, sharing one secret source and one MCP registry.
7. **Workflow interop** — Things 3 (tasks) ↔ Claude (specs) ↔ Obsidian (knowledge).

## 1. Where we are (audit — 2026-06-06)

Four-agent audit. The skeleton is **sound**; rot is concentrated in two layers.

### 🔴 P0 — Broken
- **`scripts/install/lib/toolchain-runner.sh` was missing** → all 12 `*-toolchain.sh`
  died on `source` → every `claw install <domain>` failed. **FIXED** (runner rebuilt
  to the exact contract; `eget:` fallback added; verified via dry-run).

### 🟠 P1 — Platform gaps
- **Terminal configs never stow on Linux** — `symlinks.sh` adds the `terminal` module
  only on macOS, so ghostty (snap-installed), kitty, alacritty are **orphaned on Ubuntu**.
- **Starship** installed but never `init`'d. **colorls** config may not reach `~/.config/colorls/`.

### 🟡 P2 — Incomplete-but-working
- **8 profiles missing `_tool_check()`** (blackwell, brainstorm, deck, demo, design, homelab, pmo, tunnels) — load fine, status card just doesn't render.
- `claw-fn.zsh:15` help lists 9/18 profiles. `should_skip_plugin()` is a stub.

### 🟢 P3 — Dead weight (triage: wire or delete)
`config/integrity/`, `config/agentic/openshell/policy.yaml`, `config/ai/serve-nemotron-omni.sh`, `config/.config/themes/`, `tools/.config/{bottom,lazygit}/.gitkeep`.

### ✅ Healthy
All 18 profiles reachable end-to-end; 26 `claw` subcommands dispatch to real code; no orphaned scripts; all fastfetch configs present; `agents.toml` registry with `[claude]`/`[gemini]` already exists.

## 2. The next-gen tool catalog (research, verified 2026)

Excludes what we already ship. Distribution: `apt`/`brew` → `eget` (GitHub binaries) → `cargo`/`go`/`pipx`. **All bundled into `claw install nextgen`** (built — see §5 Wave 1).

| Bucket | Must-add ★ | Strong picks |
|---|---|---|
| Progress/Download | **pv** | aria2, xh, gtrash, chafa |
| TUI cockpits | **k9s** | oxker, trippy(`trip`), gdu, doggo, sshs |
| Productivity | **just** | mise, watchexec, hyperfine, sd, jless, qsv, gron |
| Secrets | **sops + age** | keychain, op (1Password) optional |
| System ops | **topgrade + eget** | gh, mas (mac) |
| Delight | **onefetch** | tte, wttr.in, pokeget, fortune+lolcat |

**Migrations within the existing stack:** `fnm + pyenv → mise`; `dog → doggo`; `entr → watchexec`; `xsv → qsv`. **Keystone:** `eget` (fetch any GitHub-release binary, sha-verified) + `topgrade` (update everything) = the "one fell swoop" provisioning + self-update engine.

## 3. Agentic harness coexistence + interop (research)

**Design invariants:** one secret source (`.env`/`op://` via `load-env.zsh`) → many harnesses; one MCP registry (`~/.agents/mcp.toml`) → *rendered* into each client's native config (mirrors the proven `gen-fastfetch.py` pattern); Claude Desktop's MCP stays a separate render target (mac GUI boundary).

| Harness | Config | Key | Share via |
|---|---|---|---|
| Claude Code | `~/.claude.json`, project `.mcp.json` | `ANTHROPIC_API_KEY`/sub | `claude mcp add[-json] --scope user` |
| Gemini CLI | `~/.gemini/settings.json` | `GEMINI_API_KEY`(`:=GOOGLE_API_KEY`) | `mcpServers{}` (expands `$VARS`) |
| aichat / openrouter | `~/.config/aichat/config.yaml` | `OPENROUTER_API_KEY` | consumer (not MCP host) |
| Ollama / hermes | `~/.ollama` `:11434` (+`/v1`) | none | model server |

**Unified launcher:** extend `agents.toml` (`kind`, `mcp` keys) + `cmd_run_agent` so `claw claude|gemini|hermes|openrouter|aichat` all dispatch through one registry reading one `.env`.

**MCP registry → `claw agent mcp-sync`:** render `~/.agents/mcp.toml` into Claude Code (`claude mcp add`), Gemini (`jq` into settings.json), and (mac) Desktop (refactor `mcp-manager.sh`). Servers that matter: filesystem(scoped to `~/projects`+`$OBSIDIAN_VAULT`), git, fetch, memory, **mcp-obsidian** (Local REST API plugin + `OBSIDIAN_API_KEY`), **things-mcp** (mac), shodan (security profile).

**Things ↔ Claude ↔ Obsidian flow:** `otoday` → `ocapture` → `claw capture-tasks` (notes → Things `add_todo` with explicit `list_id` + `obsidian://` backlink) → `claw handoff` / `/handoff` skill (session → vault `00-Inbox`, backlinked). The Obsidian half exists in `shell/obsidian.zsh`; wire Things + handoff onto it.

**Local AI stack:** `claw ai serve|models|pull|chat|web|doctor` umbrella over Ollama(`:11434/v1`) + aichat + open-webui + n8n (homelab), surfaced in the welcome-TUI `ai_tools` pick.

## 4. Ratatui TUI (the visual leap — design locked, build deferred to Wave 4)

**Why:** ratatui's `Layout`+`Table` solve the two-column alignment problem natively (the exact `ff-readout.sh` pain) and enable responsive multi-pane, live-refresh, mouse.

**Hard fact:** a child binary can't `source` a profile into the login shell → **Rust selects, zsh applies**. The binary renders+picks, prints a one-line `PROFILE\t…`/`ACTION`/`EXEC`/`NONE` contract; a thin zsh wrapper acts on it.

**Coexistence:** `command -v claw-tui && claw-tui welcome || _claw_welcome_fzf` — fzf path stays as permanent fallback (`CLAW_TUI_DISABLE=1`). **Zero risk** to boxes without the binary.

**Crate:** `tui/claw-tui/` — `screens/{welcome,group,tunnels,homelab,mcp,toolkit}`, `widgets/{logo,readout,menu_list,topology}`, `data/{fastfetch(json),profiles(meta parse),tunnels,ssh_config}`, `theme.rs` (GitHub-dark, one source of truth). Deps: ratatui 0.29, crossterm 0.28, serde/serde_json/serde_yaml, ansi-to-tui, tui-input, directories. **Keep fastfetch** as the JSON probe; shell out for side-effecting actions.

**Distribution:** CI builds per-platform binaries (macOS arm64, Linux x86_64/arm64 **musl**) → release assets → `scripts/install/claw-tui.sh` downloads to `~/.local/bin`; never forces a Rust compile.

**Milestones:** M0 seam (no UI, prove fallback) → **M1 welcome dashboard** (solves alignment) → M2 menu/action parity → M3 tunnels+homelab → M4 mcp+toolkit → M5 CI/distribution.

## 5. Phased roadmap

### Wave 1 — Foundations un-broken + the tool pack  ✅ (this session)
- [x] Rebuild `toolchain-runner.sh` (un-break all 12 `claw install`).
- [x] `claw install nextgen` curated pack (pv/k9s/just/eget/topgrade/age/sops/onefetch/mise/…) + `eget:` fallback.
- [x] Terminal configs stow on Linux (ghostty/kitty/alacritty).
- [x] Generic `_claw_profile_tool_check` (8 profiles) + `claw-fn` help → 18.
- [x] Visual delight module (onefetch-on-cd, fact-of-the-day, `pv`/aria2 progress ops).

### Wave 2 — Provisioning + self-update spine  ✅ (mostly landed)
- [x] `claw provision` — one-pass fresh-box (apt/brew base → modern-cli → stow → nextgen → manifest → agentic → fonts → integrity). Idempotent, `--dry-run`, `--minimal`.
- [x] `claw pkg` self-aware manifest (track/scan/install/update via topgrade) — the interop loop. [ ] self-update timer (next).
- [x] Secrets foundation: `claw secret` (age/sops) + sops-encrypted `.env.sops` auto-loaded; shared agentic env.

### Wave 3 — Agentic + interop  ✅ (core landed)
- [x] `claude/mcp.toml` + `claw mcp-sync` (Claude Code + Gemini + Desktop renderers, 9 servers).
- [x] `claw ai` umbrella (Ollama/aichat/open-webui/n8n). agents.toml: +hermes/openrouter/aichat.
- [x] `claw handoff` (vault inbox). [ ] `claw capture-tasks` / `/handoff` skill (next).

### Wave 4 — Ratatui TUI  ✅ (M0+M1 landed, compiles)
- [x] M0 seam (outcome contract + `_claw_apply_outcome` + `CLAW_TUI=1` guard) + M1 welcome screen (logo + native two-column readout + profile picker), compiles on cargo 1.94. [ ] M2–M5 (next).

### Wave 5 — Polish + triage
- [ ] P3 dead-weight triage (wire or delete, with operator sign-off).
- [ ] Per-profile tool curation pass; visual packs (`tte` intros, profile MOTDs).

## 6. Conventions (unchanged, enforced)
Cross-platform `platform.zsh` shims · `command -v` guards everywhere · GitHub macOS Dark palette · SSH-safe (no stdout in non-interactive init) · idempotent installs · `set -e` · safety aliases · stage-by-name commits.

---
*Generated from the 2026-06-06 four-agent audit + two deep-research passes (tool catalog, agentic/interop). Update this doc as waves land.*
