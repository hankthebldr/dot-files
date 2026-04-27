# Open Claw MVP — Design (v3)

**Date:** 2026-04-27
**Status:** Pending review
**Supersedes:** v1 (welcome-tui-overhaul) and v2 (initial mvp-rewrite which over-cut)

## Pivot from v2

User direction is to **keep the rich profile-driven experience** but make it actually good — 8 polished profiles instead of 22 half-built pieces. Cuts only what's clearly dead weight; future-proofs the agent layer for non-Claude agents (Hermes, Aider, etc.).

| v2 said | v3 says |
|---|---|
| Archive 8 profiles to `legacy/` | **Keep them in-tree.** Drop only `local` → 8 profiles total. |
| Welcome TUI runs once/day | **Keep current per-shell flow** with profile selection. |
| Drop fastfetch profile dashboards | **Keep them.** Hand-tune each logo so they're genuinely distinctive. |
| Auto-launch `exec claude` from menu | **Generalize to agents** via `agents.toml` registry + `claw <agent-name>`. |
| Drop alias prefixes | **Still drop them.** Muscle memory wins. |

## Problem (recap, sharpened)

- **Logos are smiley clones** — 8 profiles, one template, badge-text-swap. Read as cosplay, not branding.
- **Aliases lose to muscle memory** — `cloud-k` is longer than `k`; `osint-nmap` doesn't beat `nmap`.
- **`[N] + done` bleeds over the logo** — already fixed (see git history).
- **Generic OPEN CLAW header doesn't render** — `config.jsonc` has `type: auto` so fastfetch picks Apple instead of `logo.txt`.
- **Claude profile shows a dashboard but never launches `claude`** — and the same problem will repeat for every future agent.
- **No single entry point** — workflows scattered across `tunnel-manager.sh`, `mcp-manager.sh`, `homelab.sh`, `toolkit.sh`, `system-update.sh`, `tool-updater.sh`. Hard to discover, hard to remember.
- **No agent abstraction** — adding Hermes or Aider would mean another bespoke welcome-TUI menu entry + case branch, not a plug-in.

## Goals

1. **One entry point: `claw`** — surfaces every existing tool (skills/MCP/homelab/tunnels/updates/agents) without rewriting any of them.
2. **8 fully-realized profiles** — each visually distinctive, functional, and useful day-to-day.
3. **Agent-agnostic launcher** — `claw claude`, `claw hermes`, `claw aider` all work via a single registry file.
4. **Drop alias-prefix bloat** — `cloud-k`/`osint-nmap`/etc. removed; what survives is genuinely shorter than the real command.
5. **Restore OPEN CLAW logo** — fix the broken `auto` → `file` config.
6. **Keep the polish** — modern CLI base, Starship, fastfetch dashboards, help functions, docs all stay.

## Non-Goals

- Removing any profile beyond `local`.
- Cutting the welcome TUI's profile selector.
- Touching `bootstrap.sh`'s base-layer install logic.
- Building per-profile install toolchains automatically (`claw install <toolchain>` is opt-in, no auto-run).
- Multi-agent composition (`claw claude+hermes` — defer to v4).

## Design

### 1. The `claw` command (single entry point)

New file: `bin/claw` (~150 lines bash). Added to PATH via `shell/path.zsh`.

Subcommands surface every existing capability:

| Subcommand | Routes to |
|---|---|
| `claw` (no args) | `claw_welcome_tui` (current FZF menu) |
| `claw doctor` | Renders system + active-profile health (replaces per-profile `_xxx_tool_check`) |
| `claw update` | `scripts/utils/system-update.sh` |
| `claw tools` | `scripts/utils/tool-updater.sh --interactive` |
| `claw tun` | `scripts/utils/tunnel-manager.sh` |
| `claw mcp` | `scripts/utils/mcp-manager.sh` |
| `claw homelab` | `scripts/utils/homelab.sh` |
| `claw toolkit` | `scripts/utils/toolkit.sh` |
| `claw skills` | FZF list of `~/.claude/skills/` (or wherever skills live) — opens picked skill's README in `glow` |
| `claw load <profile>` | `source shell/profiles/<p>.zsh` + export `CLAW_ACTIVE_PROFILE` |
| `claw off` | Unset `CLAW_ACTIVE_PROFILE`, instruct user to `exec zsh` for a clean shell |
| **`claw <agent>`** | **Look up `<agent>` in `~/.config/claw/agents.toml`, optionally load profile, then exec the binary** |
| `claw agent list` | Print registered agents from `agents.toml` |
| `claw agent add <name> <cmd> [profile]` | Append entry to `agents.toml` |
| `claw install <toolchain>` | Run `scripts/install/<toolchain>-toolchain.sh` (opt-in only) |
| `claw help` | Subcommand list |

**Implementation note:** dispatcher uses a flat `case "$1" in ... esac` pattern — readable, no clever metaprogramming. Adding a subcommand = adding a case arm.

### 2. Agent registry (the Hermes-future-proofing piece)

New file: `~/.config/claw/agents.toml` (created on first run if absent, with claude pre-registered):

```toml
# Open Claw agent registry
# Add an entry per coding/AI agent you use. `claw <name>` launches it.

[claude]
command = "claude"
profile = "claude"      # optional — load this profile before launching
description = "Anthropic Claude Code (default agent)"

# Future:
# [hermes]
# command = "hermes-cli"
# profile = "ai"
# description = "Hermes 70B local agent"
#
# [aider]
# command = "aider"
# profile = "ai"
# description = "Aider pair-programmer"
```

Format intentionally trivial. `command` is the binary to exec. `profile` is optional (auto-source first if set). `description` is shown by `claw agent list`.

`bin/claw` parses with a 20-line awk/grep pipeline — no `yq`/`tomlq` dependency. If a key isn't found: error gracefully and suggest `claw agent list`.

**Adding Hermes later** = drop a `[hermes]` block in the TOML. No code change.

### 3. Drop the 9th profile, keep 8

Remove `shell/profiles/local.zsh` and `config/.config/fastfetch/config-local.jsonc` + `logo-local.txt` (its menu entry too). Reason: "local CLI tools" is now the dispatcher's job (`claw tools`, `claw toolkit`), and `default` already covers daily-driver CLI.

Surviving 8: `default, claude, cloud, security, devops, ai, research, cortex`.

### 4. Restore OPEN CLAW logo

`config/.config/fastfetch/config.jsonc` — change `"type": "auto"` → `"type": "file"` + explicit source + 6-color GitHub-dark palette. (Same fix from the earlier spec; still needed.)

### 5. Hand-tune 8 profile logos (the part that's failed twice)

Past attempts that fell flat:
- Original smiley clones — template-with-text-swap, all the same shape
- ASCII mockups (claude spark, infinity loop, etc.) — too thin, lacked depth
- Built-in distro logos (Kali, NixOS, GarudaDragon, etc.) — generic, not branded to the profile

**This time** — each logo is hand-curated and committed individually. Process per logo:

1. Pick subject matter that's profile-iconic (not generic)
2. Draft in `logo-<profile>.txt` using all 6 color slots `$1-$6` for depth/shading
3. Render via `fastfetch -c config-<profile>.jsonc`
4. Show inline in chat for approval
5. Iterate until it looks genuinely good (no shipping the first draft)

Per-profile direction (each gets its own subtask with mockups):

| Profile | Subject matter | Color palette intent |
|---|---|---|
| **default** | Apple silhouette (current) | Already good — keep |
| **claude** | Anthropic 8-ray asterisk, dense block, gold-on-cream | Brand-accurate, not generic spark |
| **cloud** | AWS hex stack (3D layered hexagons) | Blue + cream + cyan accents |
| **security** | Kali fastfetch built-in, recolored to red/purple | Iconic dragon swirl, universal pentest signal |
| **devops** | Docker whale (recognizable silhouette) OR Kubernetes wheel | Whale wins on recognition |
| **ai** | Dense neural-net node graph (multi-layer) | Purple core + green/red activations |
| **research** | Erlenmeyer flask + molecular lattice (composite) | Two-element scene, gold + green |
| **cortex** | Palo Alto Cortex hex grid + radar sweep | Brand-accurate orange + crimson |

**Approval gate**: each logo gets shown inline before committing. If a logo doesn't land, we iterate on it — not commit-and-move-on.

### 6. Drop alias prefixes

Audit `shell/aliases.zsh` + each `shell/profiles/*.zsh`. Apply rule:

- **KEEP** if shorter than the real command and unambiguous (`k=kubectl`, `tf=terraform`, `g=git`, `lzd=lazydocker`, `glg=lazygit`)
- **DROP** if it just adds a `<profile>-` namespace prefix (`cloud-k`, `osint-nmap`, `red-msf`, `web-ffuf`, `dfir-bin`, `rev-rad`)
- **REPLACE** with shorter unprefixed versions where they don't exist yet (e.g., `cloud-tff` → `tff` in cloud profile)

Profile aliases that target uninstalled tools (`wpscan`, `crackmapexec`, `volatility`) stay in the profile but get a `command -v` guard so they fail with a clear "tool not installed" message rather than confusing errors.

### 7. Welcome TUI: keep flow, polish the seams

`shell/welcome-tui.zsh` stays as the per-shell entry point. Changes:

- Drop `local` from the profile list (8 profiles instead of 9)
- Dedupe the duplicate `claude` entry (lines 74 + 83)
- For the `claude` profile, add `exec claude` after dashboard (and any other profile whose registered agent in `agents.toml` matches the profile name)
- Add a single `🚀 Agents` row that opens `claw agent list` so registered agents are discoverable

The job-control `&` → `&!` fix has already landed.

### 8. Skills / MCP / Homelab integration

These already exist as standalone scripts. Dispatcher just routes:

- `claw mcp` → `scripts/utils/mcp-manager.sh` (existing TUI)
- `claw homelab` → `scripts/utils/homelab.sh` (existing TUI)
- `claw skills` → **new tiny script** (~30 lines): FZF-pick from `~/.claude/skills/*/SKILL.md`, render with `glow`. Skills aren't currently surfaced anywhere in the project.

This is purely additive — no rewrite of existing scripts.

### 9. Tool updater interactive mode (kept from prior spec)

Add `--interactive` and `--force` argv modes to `tool-updater.sh`. Surface via `claw tools`. Built atop a new `scripts/utils/tui-style.sh` shared helper (de-duplicates with `system-update.sh`). Same design as the prior spec § 5 — no change.

## Implementation Order

Each step is commit-ready and independently valuable:

1. **`bin/claw` dispatcher** + add `$DOTFILES_DIR/bin` to `shell/path.zsh` (skeleton with all subcommands as case arms; agent registry parsing)
2. **Agent registry** — create `~/.config/claw/agents.toml` template + `claw agent list/add` subcommands
3. **Restore OPEN CLAW logo** in `config/.config/fastfetch/config.jsonc` (1-line config change)
4. **Drop `local` profile** + dedupe `claude` menu entry in welcome-tui
5. **Hand-tune 8 profile logos** (one commit per logo, each shown inline for approval)
6. **De-prefix alias audit** — `shell/aliases.zsh` + each `shell/profiles/*.zsh`
7. **Wire `claw <agent>`** to `exec` the agent binary with optional profile pre-load (claude works first; doc the pattern for adding others)
8. **`claw skills`** — new 30-line script, FZF picker over `~/.claude/skills/`
9. **`scripts/utils/tui-style.sh`** + refactor `system-update.sh` to source it
10. **`tool-updater.sh --interactive` / `--force`** + wire to `claw tools`
11. **`docs/claw.md`** — single-page user docs

## File Touch List

| File | Change |
|---|---|
| `bin/claw` | **new** — dispatcher (~150 lines) |
| `shell/path.zsh` | prepend `$DOTFILES_DIR/bin` to PATH |
| `~/.config/claw/agents.toml` | **new** (created on first run) — agent registry |
| `config/.config/fastfetch/config.jsonc` | `auto` → `file` + 6-color palette |
| `shell/welcome-tui.zsh` | drop `local`, dedupe claude, add `Agents` row |
| `shell/aliases.zsh` | de-prefix audit (~50 line removals) |
| `shell/profiles/*.zsh` | de-prefix per-profile aliases; add `command -v` guards |
| `shell/profiles/local.zsh` | **delete** |
| `config/.config/fastfetch/config-local.jsonc` | **delete** |
| `config/.config/fastfetch/logo-local.txt` | **delete** |
| `config/.config/fastfetch/logo-{profile}.txt` × 7 | **rewrite** with hand-tuned art (one commit each) |
| `config/.config/fastfetch/config-{profile}.jsonc` × 7 | update `logo.color` palette per profile |
| `scripts/utils/skills-picker.sh` | **new** (~30 lines) |
| `scripts/utils/tui-style.sh` | **new** — shared TUI helpers |
| `scripts/utils/system-update.sh` | source `tui-style.sh`, remove duplicates |
| `scripts/utils/tool-updater.sh` | argv parsing, interactive renderer |
| `docs/claw.md` | **new** — user docs |

## Verification

After all 11 steps:

1. New shell → fastfetch OPEN CLAW renders (not Apple) and welcome TUI shows 8 profiles + agents row
2. Pick `claude` from menu → dashboard renders, then `exec claude` lands in a Claude session
3. `claw` from prompt → menu opens
4. `claw doctor` → health dashboard
5. `claw mcp`/`claw tun`/`claw homelab`/`claw skills` → each opens the right TUI
6. `claw claude` → dashboard + exec
7. `claw agent list` → shows registered agents
8. `claw agent add hermes hermes-cli ai` → appends to `agents.toml`; `claw hermes` then works (assuming binary present)
9. Each of 8 profile logos renders distinctly (visual diff vs. v1 is obvious)
10. `cloud-k get pods` → "command not found" (de-prefixed)
11. `k get pods` → works
12. `claw tools` → interactive tool-updater renders

## Risks & Notes

- **Logo iteration burden** — committing to per-logo approval gates means 7 round-trips minimum. Worth it because past attempts failed by skipping iteration.
- **Agent registry parser** — bash TOML parsing is fragile. Keep format trivial (only `[name]`, `command`, `profile`, `description` keys; no nested tables; no array values). If it gets complex later, swap to `yq` (already required in extras).
- **Backwards-compat with prefix aliases** — anyone using `cloud-k` in scripts will break. Mitigation: print one-time NOTICE in `~/.zshrc.local` on first new-shell after install.
- **`exec claude` from welcome TUI** — terminates the shell. If claude exits, user lands at parent shell, not back in menu. Acceptable; menu is for entry, not re-entry.
- **`local` profile deletion is destructive** — git history retains it. Anyone who liked it can `git show <sha>:shell/profiles/local.zsh` to recover.
