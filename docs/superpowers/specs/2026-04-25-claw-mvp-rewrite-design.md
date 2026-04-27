# Open Claw MVP Rewrite — Design

**Date:** 2026-04-25
**Status:** Pending review
**Supersedes:** 2026-04-25-welcome-tui-overhaul-design.md (which only treated symptoms)

## Problem

The current architecture has accumulated more surface than value:

- **Profile system is high-overhead, low-payoff.** 8 profile zsh files × ~150 lines each, 8 fastfetch configs, 8 logo files, 8 install scripts. Each profile defines 30-60 prefixed aliases (`cloud-k`, `osint-nmap`, `red-msf`) that lose to muscle memory — most users will type `kubectl`, `nmap`, `msfconsole` directly. Most aliases are dead code in practice.
- **Welcome TUI runs on every shell.** Every tmux pane, every new tab, every `exec zsh` blocks on the menu. Default-on-ESC helps but is still friction. The branded dashboard is a one-time impression overhead repeated 50× per day.
- **Profiles are pretend-stateful.** `source cloud.zsh` mutates only the current shell. New tab → no cloud. There's no prompt indicator, no session propagation, no way to know which profile you're in. The architecture promises "modes" but delivers one-shot sourcing.
- **Workspace mutation on profile load is a footgun.** `security.zsh` auto-`cd`s into a freshly created `~/pentest/<date>_engagement/` tree just from selecting it in a menu.
- **Three months in and there's no real MVP.** The polish (logos, dashboards, color palettes) outpaced the actual daily-use value.

## Goals

Ship an MVP that:

1. **Removes friction** — no menu blocks every shell; the polished dashboard is for first-impression moments only.
2. **One entry point** — `claw` command surfaces everything (status, update, tunnels, MCP, optional profile load).
3. **Aliases serve muscle memory** — global, short, no `<profile>-` prefixes; what's shorter than the original survives.
4. **Profiles are optional and discoverable** — auto-load via `.claw` file in a project root (direnv-style); never imposed by global state.
5. **Active context is visible** — Starship segment shows `[profile]` when one is loaded.
6. **Cuts maintenance burden** — archive 8 profile files + 8 fastfetch configs + 8 logos to `legacy/`; recovered later if needed.

## Non-Goals

- Deleting any working code permanently. Everything cut moves to `legacy/` first.
- Replacing the modern CLI base layer (eza, bat, rg, fd, fzf, zoxide, atuin, delta, btop, lazygit, yazi, starship). These are the foundation and stay.
- Touching `bootstrap.sh`'s install logic for the base layer.
- Removing the tunnel manager, MCP manager, system-update.sh, toolkit.sh — these are real value.
- Building per-profile install toolchains (`*-toolchain.sh`). They become opt-in: only fire if user explicitly invokes them, e.g. `claw install cloud`.

## Design

### 1. The `claw` command (single entry point)

New file: `bin/claw` (added to PATH in `shell/path.zsh`).

A pure-bash dispatcher with subcommands:

| Subcommand | Behavior |
|---|---|
| `claw` (no args) | Open FZF launcher menu (slimmed-down current welcome-tui) |
| `claw doctor` | Render system + tool health dashboard (replaces per-profile `_xxx_tool_check`) |
| `claw update` | Run `system-update.sh` (full system update with gum spinners) |
| `claw tools` | Run `tool-updater.sh --interactive` (curated CLI tool refresh) |
| `claw tun` | Launch tunnel manager |
| `claw mcp` | Launch MCP manager |
| `claw load <profile>` | Source `legacy/profiles/<profile>.zsh` in current shell + set `CLAW_ACTIVE_PROFILE` (opt-in) |
| `claw off` | Unset `CLAW_ACTIVE_PROFILE`, clear profile-loaded aliases |
| `claw install <toolchain>` | Run `scripts/install/<toolchain>-toolchain.sh` (opt-in) |
| `claw help` | Show subcommand list |

Implementation: ~80 lines of bash, case statement, sources the relevant scripts. No clever abstractions — readable wins.

### 2. Welcome TUI runs once per day, not every shell

In `.zshrc`, gate the call:

```zsh
# Welcome TUI: only first interactive shell per day
if [[ -o interactive ]] && [[ -t 0 ]]; then
    local _welcome_sentinel="$HOME/.cache/claw/welcomed-$(date +%F)"
    if [[ ! -f "$_welcome_sentinel" ]]; then
        mkdir -p "$(dirname "$_welcome_sentinel")"
        touch "$_welcome_sentinel"
        claw_welcome_tui
    fi
fi
```

The sentinel auto-rolls every midnight (different filename each day). Old sentinels from prior days get cleaned by a once-weekly find:

```zsh
find "$HOME/.cache/claw" -name 'welcomed-*' -mtime +7 -delete 2>/dev/null
```

Inside the welcome TUI itself, drop the profile-selector entries — keep only the launcher actions (tunnel, MCP, system update, claw toolkit). Profiles get loaded via `claw load <p>` or `.claw` file, not the menu.

### 3. Drop alias prefixes (the "C" piece)

Audit `shell/aliases.zsh`. Apply this rule:

- **Keep** if shorter than the real command and unambiguous: `k=kubectl`, `tf=terraform`, `g=git`, `lzd=lazydocker`, `glg=lazygit`, `ll=eza -l`
- **Drop** if it just adds a namespace prefix without saving keystrokes: `cloud-k`, `cloud-tff`, `osint-nmap`, `red-msf`, `web-ffuf`, `dfir-bin`, `rev-rad` — all gone
- **Move** profile-specific helpers (engagement-dir-creator, AWS profile switcher, etc.) into `legacy/profiles/<profile>.zsh` so they survive but don't pollute the global namespace

Also flag any alias targeting a tool that's not in the standard install (e.g. `wpscan`, `crackmapexec`, `volatility`) — those move to legacy too. Global aliases must be globally available.

### 4. Profile auto-load via `.claw` file (the "B" piece)

Direnv-style optional hook. In `shell/load-env.zsh` (or new `shell/claw-direnv.zsh`):

```zsh
_claw_check_envrc() {
    local _claw_file="$PWD/.claw"
    if [[ -f "$_claw_file" ]]; then
        local _profile
        _profile=$(grep -E '^profile=' "$_claw_file" | head -1 | cut -d= -f2)
        if [[ -n "$_profile" && -f "$HOME/.dotfiles/legacy/profiles/$_profile.zsh" ]]; then
            export CLAW_ACTIVE_PROFILE="$_profile"
            source "$HOME/.dotfiles/legacy/profiles/$_profile.zsh"
        fi
    fi
}
chpwd_functions+=(_claw_check_envrc)
_claw_check_envrc   # also fire on shell start
```

If direnv is installed, prefer using its native hook (cleaner unload). Otherwise the chpwd hook is the fallback. The `.claw` file format is intentionally trivial:

```
profile=cloud
```

(Future expansion: `profile=cloud,security` could compose; not in MVP.)

### 5. Starship `[profile]` segment

In `terminal/.config/starship.toml`, add a `custom.claw_profile` block:

```toml
[custom.claw_profile]
command = "echo $CLAW_ACTIVE_PROFILE"
when = "test -n \"$CLAW_ACTIVE_PROFILE\""
format = "[\\[$output\\]]($style) "
style = "bold purple"
```

Insert in the `format` line. Now you always know what's loaded.

### 6. Restore OPEN CLAW logo (the surviving fastfetch config)

`config/.config/fastfetch/config.jsonc` line 4: change `"type": "auto"` to `"type": "file"` + explicit source + 6-color GitHub-dark palette. (Same one-shot fix from prior spec — kept because it still matters; this is the *only* fastfetch config that survives.)

The other 8 `config-*.jsonc` files and 8 `logo-*.txt` files move to `legacy/fastfetch/`.

### 7. `tool-updater.sh` interactive mode (still useful, kept from prior spec)

Add `--interactive` and `--force` argv modes. Surface via `claw tools`. Same design as prior spec § 5. Build atop a new `scripts/utils/tui-style.sh` that also gets sourced by `system-update.sh` (extracts duplicated theme/spinner helpers).

### 8. Archive plan

```
legacy/
├── profiles/
│   ├── ai.zsh
│   ├── claude.zsh
│   ├── cloud.zsh
│   ├── cortex.zsh
│   ├── default.zsh         # [keep top-level too — it's the base]
│   ├── devops.zsh
│   ├── local.zsh
│   ├── research.zsh
│   └── security.zsh
└── fastfetch/
    ├── config-ai.jsonc
    ├── config-claude.jsonc
    ├── config-cloud.jsonc
    ├── ... (5 more)
    ├── logo-ai.txt
    ├── ... (7 more)
    └── README.md           # one-paragraph note: "These were per-profile dashboards in v1. Restore by moving back to config/ and adding a `claw load <p>` call."
```

`shell/profiles/default.zsh` stays at its current path because `claw_welcome_tui`'s "Default Shell" choice still sources it as the base experience.

## Implementation Order (each commit-ready, each adds value alone)

1. **`bin/claw` dispatcher** + add `~/.dotfiles/bin` to `shell/path.zsh`
2. **Date-gate welcome TUI** in `.zshrc`
3. **Restore OPEN CLAW logo** in `config/.config/fastfetch/config.jsonc`
4. **Audit & de-prefix `shell/aliases.zsh`** — drop `cloud-`, `osint-`, `red-`, `web-`, `dfir-`, `rev-` aliases; keep what's shorter than the real command
5. **Archive 8 profiles + 8 fastfetch configs + 8 logos to `legacy/`** (one big `git mv`)
6. **Slim welcome TUI** — remove profile-picker rows; keep launcher rows (tunnel, MCP, system-update, claw)
7. **Starship `[profile]` segment**
8. **`.claw` direnv hook** in `shell/claw-direnv.zsh`
9. **`scripts/utils/tui-style.sh`** + refactor `system-update.sh` to source it
10. **`tool-updater.sh --interactive` / `--force` modes** + wire to `claw tools`

Each step ends in green; no step depends on a later step beyond ordering. After step 5 the repo is materially smaller and friction is materially lower.

## File Touch List

| File | Change |
|---|---|
| `bin/claw` | **new** — dispatcher |
| `shell/path.zsh` | add `$DOTFILES_DIR/bin` to PATH |
| `.zshrc` | gate `claw_welcome_tui` behind date sentinel; add cleanup find |
| `shell/welcome-tui.zsh` | drop profile rows; keep launcher rows; remove case branches for profile keys |
| `shell/aliases.zsh` | bulk de-prefix audit (~50-80 line removals expected) |
| `shell/claw-direnv.zsh` | **new** — `.claw` chpwd hook |
| `terminal/.config/starship.toml` | add `[custom.claw_profile]` block |
| `config/.config/fastfetch/config.jsonc` | logo block: `auto` → `file` + 6-color palette |
| `scripts/utils/tui-style.sh` | **new** — shared TUI helpers |
| `scripts/utils/system-update.sh` | source `tui-style.sh`, drop duplicated helpers |
| `scripts/utils/tool-updater.sh` | argv parsing, interactive/force modes |
| `legacy/profiles/*.zsh` | **moved** from `shell/profiles/` (8 files; default.zsh keeps a copy at original path) |
| `legacy/fastfetch/config-*.jsonc` | **moved** from `config/.config/fastfetch/` (8 files) |
| `legacy/fastfetch/logo-*.txt` | **moved** (8 files) |
| `legacy/README.md` | **new** — one-paragraph restoration note |
| `docs/claw.md` | **new** — single-page user docs for the `claw` command |

## Verification

After all 10 steps:

1. Open new shell after midnight rollover → fastfetch + welcome TUI fire once
2. Open new tmux pane same day → straight to prompt, no menu
3. Run `claw doctor` → health dashboard
4. Run `claw tun` → tunnel manager opens
5. `cd` into a directory containing `.claw` with `profile=cloud` → Starship shows `[cloud]`
6. `cd` out of it → Starship `[cloud]` clears
7. Type `k get pods` → works (kubectl alias)
8. Type `cloud-k get pods` → command not found (de-prefixed)
9. Type `claw load security` → security profile manually loaded; Starship shows `[security]`
10. Type `claw off` → profile unloaded
11. `bash scripts/utils/system-update.sh` → still renders identically
12. `claw tools` → interactive tool-updater render

## Risks & Notes

- **Breaking change for muscle memory.** Anyone who already types `cloud-k` will get errors. Mitigation: a one-time `~/.zshrc.local` warning on first shell after install pointing at a migration note in `legacy/README.md`.
- **Direnv is optional.** The `.claw` chpwd hook works without direnv; if direnv is installed, prefer its native `.envrc`. Document both paths.
- **`exec claude` from welcome TUI** (the prior idea) is **dropped from MVP**. Instead, dropping a `.claw` with `profile=claude` in a Claude project gives the same effect when you `cd` in. Cleaner.
- **`bin/` directory** is new. Bootstrap.sh needs to ensure `chmod +x bin/claw` lands.
- **Profile files moved to legacy/**. Anyone with a downstream fork referencing `shell/profiles/cloud.zsh` will break. Ship a NOTICE.md.
- **Defer real MVP value-adds for v2.1**: per-project virtualenv detection in `.claw`, multi-profile composition (`profile=cloud,security`), prompt-aware MCP server status. None of these are MVP.
