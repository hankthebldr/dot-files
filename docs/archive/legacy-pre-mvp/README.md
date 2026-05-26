# Legacy pre-MVP archive

Files in this directory predate the **Open Claw MVP rewrite** (April 2026,
PR #1: `mvp/claw-rewrite`). They're preserved here for historical reference
and because they sometimes contain useful prose, but they are **not** the
current source of truth.

## What's here

| File | Why archived |
|---|---|
| `cli-optimization-summary.md` | Completion summary of a pre-MVP optimization sprint |
| `demo-test-guide.md` | Documents a separate `cortex-dc-web` demo app — wrong repo entirely |
| `export-system-config-USAGE.md` | References `cli-config/export-system-config.sh` which no longer exists |
| `homelab-mcp-deployment-strategy.md` | MicroK8s at 192.168.1.104 — now K3s on BD790i |
| `HOMELAB-MCP-SUMMARY.md` | Duplicate of the strategy doc |
| `macbook-pro-poweruser-setup.md` | Mac-only setup guide — replaced by `claw doctor` + profile system |
| `MERGE_STRATEGY.md` | About a `Cortex-DC-Web` directory merge — wrong repo |
| `quick-commands-reference.md` | Replaced by `claw help`, `default-help`, profile-help functions |
| `quick-start-guide.md` | Replaced by `claw onboard` (the 80s arcade flow) |
| `zshrc-poweruser-additions.sh` | Pre-MVP zshrc-append script — conflicts with current modular `shell/*.zsh` architecture |

## Current docs (in active use)

- `docs/claw.md` — single-page user guide
- `docs/ALIASES.md` — generated alias reference
- `docs/ARCHITECTURE.md` — current system architecture
- `CHANGELOG.md` — release notes

## If you need something from here

Read it. Don't restore it. If a piece of content is still relevant, fold it
into one of the active docs (claw.md / ARCHITECTURE.md) rather than
resurrecting the pre-MVP file.
