# SSH Tunnel Manager Design

**Date:** 2026-03-30
**Status:** Approved

## Summary

Interactive FZF-based SSH tunnel manager with ASCII topology visualization, YAML-persisted tunnel configs, multi-hop support (2-3 hops) with per-hop credentials/keys, and SSH ControlMaster lifecycle management.

## Decisions

- **Tunnel types:** Local (-L), Remote (-R), SOCKS (-D)
- **Persistence:** YAML config at `config/ssh/tunnels.yml`
- **Hop depth:** 2-3 hops via SSH ProxyJump (-J)
- **Lifecycle:** SSH ControlMaster/ControlPath for status/teardown
- **Visualization:** ASCII box-and-arrow topology diagrams with GitHub Dark colors
- **Approach:** Shell script (Approach B) — native SSH features, FZF TUI

## Files

- `scripts/utils/tunnel-manager.sh` — Main TUI script
- `config/ssh/tunnels.yml` — Tunnel definitions (user-created)
- `config/ssh/tunnels.yml.example` — Example template

## Integration

- Welcome TUI: `tunnel` menu entry
- Aliases: `tun`, `tunls`, `tunkill`
- Dependencies: yq, fzf, SSH >= 7.3
