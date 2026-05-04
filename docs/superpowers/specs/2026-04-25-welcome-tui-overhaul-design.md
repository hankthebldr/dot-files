# Welcome TUI Overhaul — Design

**Date:** 2026-04-25
**Status:** Pending review
**Supersedes:** 2026-04-22-tool-updater-tui-design.md

## Problem

Five issues with the welcome-flow experience, surfaced together because they all touch the same render path (`.zshrc` → `welcome-tui.zsh` → `fastfetch` → menu → profile → fastfetch → optional launch):

1. **Generic OPEN CLAW header is broken.** `config/.config/fastfetch/config.jsonc` line 4 sets `"type": "auto"`, which makes fastfetch auto-detect the OS and render the macOS Apple logo — silently ignoring `logo.txt` (the hand-drawn OPEN CLAW v2.0 ASCII art). The intended pre-menu branded header never renders.
2. **`[1] + done` job-control notification cuts through the logo** on shell init. `welcome-tui.zsh:18` backgrounds the tool-updater wrapper with `&`, which puts it under zsh's job table; the wrapper exits in milliseconds and zsh prints the completion line over the freshly rendered logo.
3. **Tool updater is invisible.** It runs only as a silent background daemon — no foreground UX, no way to see what's pending or due.
4. **Eight profile logos are clones.** `logo-{security,cloud,devops,ai,research,cortex,local,claude}.txt` are all the same "smiley face" with only a badge text + emoji swap. Reads as a clone army wearing different hats; visually flat compared to fastfetch's hand-crafted built-in distro art.
5. **Claude profile doesn't actually launch Claude.** The `claude)` case branch in `welcome-tui.zsh` (line 162) that would `exec claude` is unreachable because `claude` is consumed by the multi-profile branch (line 117) first. There are also two duplicate menu entries with key `claude` (lines 74 + 83). The dashboard shows Claude version + node + MCP server count, but then drops to a plain prompt instead of launching a session.

## Goals

- Restore the branded OPEN CLAW logo on initial shell load.
- Eliminate the job-control bleed without behavior change to the background updater.
- Give the tool updater a polished interactive mode matching `system-update.sh`.
- Replace 8 cloned smiley logos with curated, multi-color built-in fastfetch art.
- Make the Claude profile actually launch `claude` after rendering its dashboard.
- Stop duplicating the ANSI/theme/spinner helpers between `system-update.sh` and the new interactive `tool-updater.sh`.

## Non-Goals

- Changing what tools are auto-updated or their intervals.
- Replacing the silent background mode (it stays as the default invocation).
- Touching `scripts/utils/logger.sh` (its colors are basic ANSI for install scripts; the TUI scripts need true-color GitHub-dark — different concern).
- Modifying `default.zsh` profile or its dashboard (Apple logo + cheatsheet stays).

## Design

### 1. Restore OPEN CLAW logo on shell init

`config/.config/fastfetch/config.jsonc`:

```diff
   "logo": {
-    "type": "auto",
+    "source": "~/.dotfiles/config/.config/fastfetch/logo.txt",
+    "type": "file",
+    "color": {
+      "1": "38;2;188;140;255",   // purple frame
+      "2": "38;2;88;166;255",    // blue OPEN
+      "3": "38;2;210;153;34",    // gold accents
+      "4": "38;2;63;185;80",     // green CLAW
+      "5": "38;2;201;209;217",   // cream highlights
+      "6": "38;2;255;123;114"    // red v2.0 stamp
+    },
     "padding": { "top": 1, "left": 2, "right": 3 }
   }
```

Mirrors the pattern in every `config-{profile}.jsonc`. Existing `logo.txt` already references `$1–$6` color tokens, so the recolor wires up automatically.

### 2. Job-control fix (one character)

`shell/welcome-tui.zsh:18`:

```zsh
# before
( "$_d/scripts/utils/tool-updater.sh" ) &> /dev/null &

# after
"$_d/scripts/utils/tool-updater.sh" &>/dev/null &!
```

`&!` is zsh's "background-and-disown-immediately." The job never enters the job table, so no completion notification fires. Drop the wrapper subshell at the same time — redundant since `tool-updater.sh` self-backgrounds at line 71.

### 3. Shared TUI helper: `scripts/utils/tui-style.sh`

New file containing the theme tokens and helpers currently duplicated in `system-update.sh`:

- Color exports: `c_reset c_cyan c_green c_purple c_orange c_red c_dim c_white c_bold` (GitHub macOS Dark true-color)
- `tui_has_gum` — sets `HAS_GUM=true|false`
- `tui_section "Title"` — purple bold heading + dim underline
- `tui_run_step "title" "command…"` — gum spin if available, styled inline echo + run otherwise
- `tui_skip "name"` — dim `○ name — not installed`
- `tui_header "title" "subtitle"` — purple rounded box header
- `tui_footer "✓ message"` — green check + timestamp
- `tui_pause` — interactive "press any key" guarded by `INTERACTIVE` flag

Source it from the top of any TUI script:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/tui-style.sh"
```

### 4. `system-update.sh` refactor

Strip duplicated theme/helpers (lines 8–46), source `tui-style.sh`, replace local helper calls with `tui_*` calls. Behavior unchanged. Net diff is ~40 lines removed.

### 5. `tool-updater.sh` interactive mode

Two new modes selected by argv:

| Invocation | Behavior |
|---|---|
| `tool-updater.sh` (no args, default) | Current silent background behavior — unchanged. |
| `tool-updater.sh --interactive` | Foreground TUI: header → per-category section → run step or "not yet due (next in Nd Nh)" → summary card. |
| `tool-updater.sh --force` | Like `--interactive` but ignores cache intervals (run everything now). |

Interactive mode uses `tui-style.sh`. Each **category** (brew, pipx, go, cargo) renders as a `tui_section` — cache granularity is per-category, not per-tool, so the whole category is either due or not.

Per category:

- **Category due** (or `--force`) → for each tool: `tui_run_step "Upgrading eza…" "brew upgrade eza"` if installed, else `tui_skip "eza"`. Then `mark_updated <category>`.
- **Category not yet due** → single dim line: `○ brew — next update in 4d 12h` (computed as `interval - (now - cached_timestamp)`, formatted as `Nd Nh`). Tool list rendered below in dim as a hint of what *would* run.

Summary card at the end shows: `N tools updated · M categories deferred · K tools unavailable`.

### 6. Welcome TUI menu entry for the tool updater

Insert in `shell/welcome-tui.zsh` System group, just below `update`:

```zsh
choices+="tools\t${c_yellow}🛠️  CLI Tool Update${c_reset}${c_dim}    Eza · Bat · Zoxide · Cargo${c_reset}\n"
```

And a case branch:

```zsh
tools)
    if [[ -f "$_d/scripts/utils/tool-updater.sh" ]]; then
        "$_d/scripts/utils/tool-updater.sh" --interactive
        printf "  ${c_dim}Press any key to continue...${c_reset}"
        read -k 1; echo ""
    fi
    ;;
```

### 7. Profile logo overhaul — built-in fastfetch art

Replace 7 of the 8 cloned smiley logos with curated fastfetch built-in distro logos (richer multi-color art) + recolor each via `logo.color["1"]…["6"]` overrides. Keep `claude` as a single custom file because there is no Anthropic logo built into fastfetch.

| Profile | Built-in logo | Why it fits | Recolor strategy |
|---|---|---|---|
| security | `Kali` | Iconic dragon swirl — universal pentest signal | `$1` red, `$2` purple, `$3` red dim, `$4` muted, `$5` purple, `$6` gold |
| cloud | `pop` | Geometric diamond lattice = distributed infra | `$1` blue, `$2` cream, `$3` blue dim, `$4` muted, `$5` gold, `$6` green |
| devops | `NixOS` | Interlocking snowflake = infra-as-code | `$1` green, `$2` cream, `$3` green dim, `$4` muted, `$5` purple, `$6` gold |
| ai | `GarudaDragon` | 22-line richly detailed multi-color art | `$1` purple, `$2` red, `$3` gold, `$4` green, `$5` blue, `$6` cream |
| research | `Aperture` | Portal-style curved vortex = exploration | `$1` gold, `$2` cream, `$3` gold dim, `$4` muted, `$5` blue, `$6` green |
| cortex | `BlackMesa` | Faceted gem prism = SOC console | `$1` cortex orange, `$2` cream, `$3` orange dim, `$4` muted, `$5` red, `$6` gold |
| local | `Gentoo` | Carved abstract stone = source-built | `$1` green, `$2` cream, `$3` green dim, `$4` muted, `$5` blue, `$6` gold |
| claude | *custom* (`logo-claude.txt`) | No fastfetch built-in for Anthropic; clean 9-line spark | `$1` gold core, `$2` cream glow, `$5` blue rim ticks |

Per profile the work is:

1. Edit `config-{profile}.jsonc` — change logo block from `"type": "file"` + `"source": "..."` to `"type": "builtin"` + `"name": "<distro>"`. Keep the existing `logo.color` block (just remap RGBs to match the table above).
2. Delete obsolete `logo-{profile}.txt` (except `logo-claude.txt` and `logo-default.txt`).
3. Verify render: `fastfetch -c config/.config/fastfetch/config-{profile}.jsonc`.

The custom `logo-claude.txt` becomes a clean 4-point spark (no smiley face, no badge, no emoji):

```
$1                ▲
$1               ███
$2              █████
$5  ▄▄▄▄▄▄▄▄$1█████████$5▄▄▄▄▄▄▄▄
$5  ▀▀▀▀▀▀▀▀$1█████████$5▀▀▀▀▀▀▀▀
$2              █████
$1               ███
$1                ▼
```

### 8. Claude profile — dedupe + auto-launch

Two changes in `welcome-tui.zsh`:

**Dedupe (lines 74 + 83):** both currently use key `claude`. Remove the second (Tools-group `💻 Claude Code` entry on line 83). Keep the orange Workflow-Profiles entry on line 74.

**Auto-launch:** split `claude` out of the multi-profile case branch into its own dedicated branch:

```diff
- default|security|cloud|devops|research|ai|cortex|claude|local)
+ default|security|cloud|devops|research|ai|cortex|local)
      export CLAW_ACTIVE_PROFILE="$key"
      ...
+ claude)
+     export CLAW_ACTIVE_PROFILE="claude"
+     source "$_d/shell/profiles/claude.zsh"
+     fastfetch -c "$_d/config/.config/fastfetch/config-claude.jsonc"
+     if command -v claude &>/dev/null; then
+         exec claude
+     else
+         echo "${c_red}claude not installed — drop to shell${c_reset}"
+     fi
+     ;;
```

`exec claude` replaces the current shell process with a Claude session — clean handoff, no nested-shell weirdness.

**Bonus dashboard polish:** add to `config-claude.jsonc` modules:

```jsonc
{ "type": "command", "key": "  CWD",     "text": "pwd | sed \"s|$HOME|~|\"" },
{ "type": "command", "key": "  PROJECT", "text": "git rev-parse --show-toplevel 2>/dev/null | xargs basename || echo '—'" },
{ "type": "command", "key": "  DOCTOR",  "text": "claude doctor 2>/dev/null | grep -E '(✓|✗)' | head -3 || echo 'n/a'" }
```

So the pre-launch refresher actually tells you *where you are* and *whether your install is healthy*.

## File Touch List

| File | Change |
|---|---|
| `config/.config/fastfetch/config.jsonc` | logo block: `auto` → `file` + color palette |
| `shell/welcome-tui.zsh` | line 18: `&` → `&!` + drop wrapper subshell; dedupe claude entry; split claude case branch with `exec claude`; add `tools` menu entry + case branch |
| `scripts/utils/tui-style.sh` | **new** — shared TUI helpers |
| `scripts/utils/system-update.sh` | source `tui-style.sh`, remove duplicated helpers, swap calls |
| `scripts/utils/tool-updater.sh` | argv parsing, interactive renderer, "next due" calc; silent path unchanged |
| `config/.config/fastfetch/config-{security,cloud,devops,ai,research,cortex,local}.jsonc` | logo block: `file` → `builtin` + remap colors per table |
| `config/.config/fastfetch/config-claude.jsonc` | add CWD + PROJECT + DOCTOR command modules |
| `config/.config/fastfetch/logo-claude.txt` | replace with 9-line spark |
| `config/.config/fastfetch/logo-{security,cloud,devops,ai,research,cortex,local}.txt` | **delete** |

## Verification

- Open new shell — confirm OPEN CLAW logo renders (not Apple logo) and no `[1] + done` line appears under it.
- `bash scripts/utils/system-update.sh --non-interactive` — confirm same visual output as before refactor.
- `bash scripts/utils/tool-updater.sh --interactive` — clean TUI render, sections, summary.
- `bash scripts/utils/tool-updater.sh --interactive --force` — cache override works.
- For each non-default profile: `fastfetch -c config/.config/fastfetch/config-{profile}.jsonc` — built-in art renders with profile palette.
- Welcome menu shows ONE "Claude Code" entry; selecting it renders dashboard then enters a `claude` session.
- Background invocation `tool-updater.sh &>/dev/null &!` — confirm no job notification.

## Risks & Notes

- **`&!` is zsh-only.** `welcome-tui.zsh` is sourced from `.zshrc`, so this is fine — but document it in a one-line comment so future-me doesn't port the line to bash.
- **`${BASH_SOURCE[0]}`** in `tui-style.sh` is bash-only. Both consumers (`system-update.sh`, `tool-updater.sh`) are bash-shebanged — safe.
- **Logo deletion** is destructive but the art is replaceable from git history; not worth keeping clutter on disk.
- **`exec claude`** terminates the shell. If `claude` exits, the user is dropped at a parent shell (terminal). If they want to come back to the menu, they'd need a new terminal window — acceptable since the menu is meant for entry, not re-entry.
