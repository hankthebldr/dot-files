# Tool Updater TUI + Welcome Logo Fix — Design

**Date:** 2026-04-22
**Status:** Approved (pending written-spec review)

## Problem

Two related issues with the welcome flow:

1. **Job-control "done" notification cuts through the fastfetch ASCII logo** on initial shell load. `shell/welcome-tui.zsh:18` backgrounds the tool-updater with `&`, which puts the wrapper subshell under zsh's job table. The wrapper exits in milliseconds (the inner script self-backgrounds at `tool-updater.sh:71`), so zsh prints `[1]  + done  ( … )` on top of the freshly rendered logo a fraction of a second later.

2. **The tool updater is invisible.** It only runs as a silent background daemon. There's no way to invoke it interactively, see what's pending, or watch a curated update run with the same polish as `system-update.sh`.

## Goals

- Eliminate the job-control notification with no behavior change to the background updater.
- Give the tool updater a polished interactive mode that matches the visual language of `system-update.sh` (GitHub-dark theme, gum spinners, sectioned output, summary card).
- Surface "what's due / what's pending" so the user can see *why* nothing happened on a given run.
- Stop duplicating the ANSI/theme/spinner helpers between `system-update.sh` and the new interactive `tool-updater.sh`.

## Non-Goals

- Changing what tools are auto-updated or their intervals.
- Replacing the silent background mode (it stays as the default invocation).
- Touching `scripts/utils/logger.sh` (its colors are basic ANSI for install scripts; the TUI scripts need true-color GitHub-dark — different concern).

## Design

### 1. Job-control fix (one character)

`shell/welcome-tui.zsh:18`:

```zsh
# before
( "$_d/scripts/utils/tool-updater.sh" ) &> /dev/null &

# after
( "$_d/scripts/utils/tool-updater.sh" ) &>/dev/null &!
```

`&!` is zsh's "background-and-disown-immediately." The job never enters the job table, so no completion notification can fire. Also drop the wrapper `( … )` — it's redundant since the script self-backgrounds — but keep the redirect to prevent any accidental future stdout from the script's outer shell.

Final form:

```zsh
"$_d/scripts/utils/tool-updater.sh" &>/dev/null &!
```

### 2. Shared TUI helper: `scripts/utils/tui-style.sh`

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

### 3. `system-update.sh` refactor

Strip the duplicated theme/helpers (lines 8–46), source `tui-style.sh`, replace local helper calls with `tui_*` calls. Behavior unchanged. Net diff is ~40 lines removed.

### 4. `tool-updater.sh` interactive mode

Two modes selected by argv:

| Invocation | Behavior |
|---|---|
| `tool-updater.sh` (no args, default) | Current silent background behavior — unchanged. |
| `tool-updater.sh --interactive` | Foreground TUI: header → per-category section → run step or "not yet due (next in Nd)" → summary card. |
| `tool-updater.sh --force` | Like `--interactive` but ignores cache intervals (run everything now). |

Interactive mode uses `tui-style.sh`. Each **category** (brew, pipx, go, cargo) renders as a `tui_section` — cache granularity is per-category, not per-tool, so the whole category is either due or not.

Per category:

- **Category due** (or `--force`) → for each tool in the category: `tui_run_step "Upgrading eza…" "brew upgrade eza"` if installed, else `tui_skip "eza"`. Then `mark_updated <category>`.
- **Category not yet due** → single dim line: `○ brew — next update in 4d 12h` (computed as `interval - (now - cached_timestamp)`, formatted as `Nd Nh`). Tool list rendered below in dim as a hint of what *would* run.

Summary card at the end shows: `N tools updated · M categories deferred · K tools unavailable`.

### 5. Welcome TUI menu entry

Insert in [shell/welcome-tui.zsh](shell/welcome-tui.zsh) System group, just below `update`:

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

## File Touch List

| File | Change |
|---|---|
| `shell/welcome-tui.zsh` | line 18: `&` → `&!` + drop wrapper subshell; add `tools` menu entry + case branch |
| `scripts/utils/tui-style.sh` | **new** — shared TUI helpers |
| `scripts/utils/system-update.sh` | source `tui-style.sh`, remove duplicated helpers, swap calls |
| `scripts/utils/tool-updater.sh` | argv parsing, interactive renderer, "next due" calculation; silent path unchanged |

## Verification

- Run `bash scripts/utils/system-update.sh --non-interactive` — confirm same visual output as before refactor.
- Run `bash scripts/utils/tool-updater.sh --interactive` — confirm clean TUI render, sections, summary.
- Run `bash scripts/utils/tool-updater.sh --interactive --force` — confirm cache override works.
- Open new shell — confirm fastfetch logo renders without `[1]  + done` appearing under it.
- Background invocation `tool-updater.sh &>/dev/null &!` — confirm no job notification.

## Risks

- **`&!` is zsh-only.** `welcome-tui.zsh` is sourced from `.zshrc`, so this is fine — but document it in a one-line comment so future-me doesn't port the line to bash.
- **Sourcing path resolution** in `tui-style.sh`: `${BASH_SOURCE[0]}` is bash-only. `system-update.sh` and `tool-updater.sh` both have `#!/usr/bin/env bash`, so safe.
