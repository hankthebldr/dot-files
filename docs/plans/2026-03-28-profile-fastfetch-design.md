# Profile-Specific Fastfetch Design

**Date:** 2026-03-28
**Status:** Approved

## Summary

Add per-profile fastfetch configurations with themed ASCII logos and profile-specific system info modules. Each profile (default, security, cloud, devops, ai, research, cortex, local) gets its own fastfetch config displaying themed OPEN CLAW art + live tooling context after profile selection in the welcome TUI.

## Decisions

- **Info depth:** Live + static (tool versions AND live context like k8s context, AWS profile, docker containers)
- **Art style:** Shared OPEN CLAW base art with per-profile color schemes and banner text
- **Display order:** Generic header + FZF menu first, profile-specific fastfetch after selection
- **Approach:** Static config files per profile (Approach B) — one `.jsonc` + one `logo-*.txt` per profile

## File Structure

```
config/.config/fastfetch/
├── config.jsonc              # existing — generic pre-menu header
├── logo.txt                  # existing — generic OPEN CLAW logo
├── config-{profile}.jsonc    # 8 NEW profile configs
└── logo-{profile}.txt        # 8 NEW logo color/banner variants
```

## Logo Variants

Same OPEN CLAW face geometry. Each variant changes color assignments (`$1`-`$6`) and banner text (line 10).

| Profile  | Banner     | Primary        | Accent         |
|----------|-----------|----------------|----------------|
| default  | OPEN CLAW | Blue #58a6ff   | Green #3fb950  |
| security | SEC  MODE | Red #ff7b72    | Purple #bc8cff |
| cloud    | CLOUD OPS | Cyan #58a6ff   | Orange #d29922 |
| devops   | DEV  OPS  | Green #3fb950  | Purple #bc8cff |
| ai       | AI  MODE  | Purple #bc8cff | Green #3fb950  |
| research | RESEARCH  | Orange #d29922 | Blue #58a6ff   |
| cortex   | CORTEX    | Orange #ff6600 | Red #ff7b72    |
| local    | LOCAL DEV | Green #3fb950  | Blue #58a6ff   |

## Module Layout

Each config: Logo → System Block (OS, HW, CPU, MEM, DSK, IP, Uptime) → Profile Block (tool versions + live context via `command` modules) → Color circles.

## Profile-Specific Modules

- **default:** Shell, Terminal, Packages, Battery
- **security:** nmap version, public IP, VPN status, Packages, Battery
- **cloud:** AWS account, k8s context, terraform version, docker containers
- **devops:** docker containers, k8s context, git version, terraform version
- **ai:** ollama model count, python version, GPU, pip packages
- **research:** python version, jq version, ripgrep version, Packages
- **cortex:** demisto-sdk version, cortexcli version, python version
- **local:** Shell, Terminal, Packages, Battery

## Integration

`welcome-tui.zsh` calls `fastfetch -c config-${key}.jsonc` after profile source. Profile `echo` banners are removed (fastfetch replaces them).

## Also Fix

- Logo path in `config.jsonc`: update `~/.dotfiles/config/fastfetch/logo.txt` → `~/.dotfiles/config/.config/fastfetch/logo.txt`
