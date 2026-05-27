# ADR-002 — MCP server selection

- **Status:** Accepted
- **Date:** 2026-05-04
- **Deciders:** Henry
- **Spec reference:** SPEC §4 (Phase 4), §6 (Phase 6), §9 (risk: MCP tool poisoning)

## Context

MCP (Model Context Protocol) servers expand an agent's tool surface — but every MCP is a privileged execution channel. Invariant Labs (Apr 2025) demonstrated tool poisoning attacks where a benign-looking server quietly redirects file reads or pipes credentials. Server selection is therefore a security decision, not a convenience decision.

Existing connected servers on this box:

| Server | Status | Disposition |
|---|---|---|
| plugin:asana:asana | Needs auth | Keep — operator workflow |
| plugin:figma:figma | Needs auth | Keep — deck production |
| plugin:firebase:firebase | Connected | Keep — homelab integration |
| plugin:playwright:playwright | Connected | Keep — recon adjuncts |
| plugin:greptile:greptile | **Failed to connect** | Remove — broken, unused |

None of the spec's required servers are present. We need to add foundational + OSINT tiers.

## Decision

### Foundational tier (Phase 4)

| Server | Source | Scope | Notes |
|---|---|---|---|
| filesystem | `@modelcontextprotocol/server-filesystem` | `~/work`, `~/.dotfiles`, `$OBSIDIAN_VAULT` (read-only initially) | Explicit roots. No `~` or `/`. |
| git | `@modelcontextprotocol/server-git` | Inherits filesystem roots | Read-only diffs / log / status. |
| memory | `@modelcontextprotocol/server-memory` | KV namespace per project | Persistent across sessions. |
| fetch | `@modelcontextprotocol/server-fetch` | Internet | Operator confirms egress for any sensitive query. |
| smart-connections | `jacksteamdev/obsidian-mcp-tools` (current canonical — verify at install) | Vault embeddings | Read-only. Write-MCP scoped separately to `00-Inbox/` in Phase 8. |

### OSINT tier (Phase 6)

| Server | Source | Containerized? | API key |
|---|---|---|---|
| shodan | `BurtTheCoder/mcp-shodan` | No (npm) | `SHODAN_API_KEY` |
| osint-37 | `badchars/osint-mcp-server` | No (npm) | Multiple — see source |
| security-hub | `FuzzingLabs/mcp-security-hub` | **Yes — Docker Desktop** | None at server layer; tool-specific |

Initial Security-Hub enablement: nmap, nuclei, masscan, gitleaks. The remaining tools stay disabled until specific need.

### Removed

- **greptile** — unhealthy, unused.

## Consequences

**Positive**
- Both agents (Claude Code + Hermes) have parity tool surface (mirror via `hermes mcp add`).
- Filesystem MCP scoped to explicit roots blocks naive exfil paths.
- Security-Hub containerization isolates the highest-risk surface.
- Greptile cleanup removes a failing connection from `claude mcp list`.

**Negative**
- Five new privileged channels per agent. Mitigated by:
  - Pre-tool-use hook (Phase 3) blocks `curl`/`wget` POST with `~/.ssh/`, `~/.aws/`, `*.env` in body.
  - Default-deny scope policy on every active recon tool (`~/.claude/scope.txt`).
  - Sensitive engagements route through DontFeedTheAI (Phase 7) before any cloud egress.
- Smart Connections MCP author churn — the current canonical implementation may shift. Verify at install time, document in commit message.

## Secrets handling

- API keys live in `~/.zshenv` (gitignored) or 1Password CLI references — **never** in `claude/mcp.json`.
- `claude/mcp.json` references env vars by name, not value (`"SHODAN_API_KEY": "${SHODAN_API_KEY}"`).
- Pre-flight before each install: confirm key is present in the operator's secret store.

## Verification

Phase 4 gate: `claude mcp list` and `hermes mcp list` both show 5 foundational servers in `connected` state. Operator runs a test: "find my notes on XSIAM detection patterns and summarize" — result is sane.

Phase 6 gate: a controlled recon test against an authorized scope target via the OSINT MCPs returns expected enumeration data through both agents.
