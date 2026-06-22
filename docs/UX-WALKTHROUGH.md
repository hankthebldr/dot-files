---
title: Open Claw — UX Walkthrough
project: dot-files
status: living
created: 2026-06-06
tags: [open-claw, ux, walkthrough]
vault_path: Github-Projects/dot-files/UX-WALKTHROUGH.md
---

# Open Claw — End-to-End UX Walkthrough

A step-by-step trace of the actual user journey across everything built through
Waves 1–4, with the friction points found during review (→ tracked in
`FEATURE-BACKLOG.md`).

## 0. Day 0 — a fresh Parrot/Ubuntu (or macOS) box
```bash
git clone <repo> ~/.dotfiles && cd ~/.dotfiles
claw provision --dry-run     # preview every step
claw provision               # pkg mgr → base+modern-cli → stow → nextgen pack →
                             # manifest install → agents → fonts → integrity
exec zsh
```
**What happens:** Homebrew/apt bootstrapped → modern CLI → dotfiles stowed →
`claw install nextgen` (eget bootstrapped, then pv/k9s/just/age/sops/topgrade/…)
→ every tool in `config/manifest/tools.list` installed → claude-code/gemini/
ollama/aichat → JetBrainsMono Nerd Font → integrity baseline.
**Friction:** ① set the terminal font to *JetBrainsMono Nerd Font Mono* manually
(can't be scripted for Terminal.app/iTerm). ② `claw provision` is all-or-nothing
per step — no resume after a mid-run failure. → backlog.

## 1. First login — the welcome dashboard
The `.zshrc` runs the welcome TUI before p10k. Default = **fzf** path (system
Apple/distro logo + the justified two-column readout + grouped profile menu).
Pick a profile → it's sourced into the live shell; ESC → bare shell.
**Opt-in:** `bash scripts/install/claw-tui.sh && export CLAW_TUI=1` swaps in the
**ratatui** front-end (same picker, native column alignment, profiles+actions).
**Friction:** the ratatui path is M2 (welcome+picker only); tunnels/mcp/homelab
still fall to the shell sub-TUIs. → backlog (M3–M4).

## 2. Daily driver
- **Movement:** `z <dir>` (zoxide), `ctrl-r` (atuin), `fzf` everywhere.
- **Modern CLI:** `ls`→eza, `cat`→bat, `grep`→rg, `find`→fd, `cd`→z, `top`→btop.
- **Display & progress:** `claw output` persists how surfaces render
  (`mode auto|rich|plain · frame viewfinder|none · banner on|off`; env
  `CLAW_OUTPUT_*` → state file → default), `claw output status` shows the
  resolved set, and `progress on|off` is the master switch for the live pkg-op panel.
- **Delight (Wave 1):** `cpv`/`mvv` (rsync progress), `dlv <url>` (aria2/xh),
  `xtract` (pv archive), `weather`, fact-of-the-day on first login of the day,
  `onefetch` on entering a repo (`CLAW_ONEFETCH=1`).
**Friction:** delight helpers are discoverable only by reading `delight.zsh` —
no `claw help` surface for them. → backlog (help/cheatsheet integration).

## 3. Profiles & loadouts
`claw load security` (or pick in the TUI) → sources the profile: domain aliases,
`<name>-help` card, `_<name>_tool_check` (or the generic fallback) status, and a
themed fastfetch dashboard with truecolor art. `claw install <domain>` lays down
the matching toolchain (now working — Wave 1 P0 fix).
**Friction:** profile→toolchain mapping is implicit; `claw load security` doesn't
prompt "install the missing security tools?" → backlog (load↔install bridge).

## 4. Agents & AI
- `claw claude` / `claw gemini` / `claw hermes` / `claw openrouter` / `claw aichat`
  — all dispatch through `agents.toml`, all read one `.env`/sops secret source.
- `claw mcp-sync` — one `mcp.toml` rendered into Claude Code + Gemini + Desktop.
- `claw ai serve|models|pull|chat|web|doctor` — the local Ollama/aichat/open-webui/n8n stack.
**Friction:** ① `claw agent doctor` (per-agent binary/key/config check) is specced
but not built. ② mcp-sync doesn't yet filter by active profile (security servers
sync everywhere). → backlog.

## 5. Knowledge & tasks (Things ↔ Claude ↔ Obsidian)
- `on`/`os`/`ov`/`otoday`/`ocapture` — vault navigation/capture.
- `claw handoff "topic"` — session note → vault `00-Inbox`, backlinked.
- `claw capture-tasks` — scan notes for `- [ ] … @things ^list:X` → Things 3 tasks
  with `obsidian://` backlinks (opens `things:///` URLs on macOS `--apply`).
**Friction:** capture-tasks is one-way (notes→Things); no Things→note rollup yet,
and no `/handoff` Claude *skill* (only the shell + the existing slash command). → backlog.

## 6. Maintenance & self-awareness (the interop loop)
```bash
brew install some-new-tool        # you add a tool by hand
claw pkg scan                     # → shows it as untracked
claw pkg track --commit           # → logged to config/manifest/tools.list, committed
claw pkg update                   # → topgrade updates EVERYTHING incl. new tool
claw selfupdate install           # → weekly auto-update (systemd/launchd)
```
**Live progress:** each long-running `claw pkg` step (`install`/`track`/`scan`)
renders an inline, themed status panel — a phase-driven bar framed in viewfinder
corner brackets (`⌜⌝⌞⌟`), rich on a TTY and degrading to clean plain log lines
over SSH/CI; raw output is captured off-screen to `${XDG_STATE_HOME}/claw/logs/`.
`progress off` is the master kill-switch (toggles the exported
`CLAW_PROGRESS_ENABLED`); tune the panel's defaults with `claw output`.

On the next box, `claw provision` reinstalls it. `claw doctor` / `claw validate`
/ `claw integrity` verify health and tamper-state.
**Friction:** `claw pkg track` is manual — no auto-detect hook on shell exit or a
periodic timer. → backlog (auto-track).

## 7. Secrets
`claw secret init` (age key + `.sops.yaml`) → `claw secret env` (edit the
encrypted `.env.sops`) → it auto-decrypts into the shell on login. `claw secret
doctor` reports stack health.
**Friction:** no rotation helper; no `op`/`bw` bridge wired (specced). → backlog.

## Review verdict
The spine is now **coherent and connected**: provision → use → track → update →
re-provision is a closed loop; agents share one secret source + one MCP registry;
the TUI has a real (opt-in) Rust path. The remaining friction is **surfacing**
(help/discoverability), **depth** (ratatui M3–M5, agent doctor, auto-track), and
**bridges** (load↔install, Things↔note rollup) — all enumerated in the backlog.
