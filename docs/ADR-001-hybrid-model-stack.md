# ADR-001 — Hybrid model stack

- **Status:** Accepted
- **Date:** 2026-05-04
- **Deciders:** Henry
- **Supersedes:** —
- **Spec reference:** SPEC §2 (architecture), §9 (risk register)

## Context

Pre-sales security work spans threat modeling, OSINT, recon, detection-rule authoring, deck production, and engagement reporting. No single LLM stack covers all of it:

- **Claude Code (cloud)** is the strongest at reasoning, code, and multi-tool orchestration but applies hard refusals to legitimate red-team / enumeration prompts.
- **Hermes-4 (Nous Portal or local Ollama)** is steerable on refusal-prone prompts (RefusalBench: 57.1% vs 17%, directional) and runs unattended; weaker on long-horizon coding tasks.
- **Local Ollama models** offer no-egress operation for sensitive engagements; bounded by VRAM and slower iteration.
- **Anthropic-cloud + sensitive engagement data** is incompatible without anonymization.

## Decision

Adopt a **hybrid stack** routed by task class:

| Task class | Primary | Fallback |
|---|---|---|
| Coding / dotfiles refactor | Claude Code | opencode |
| Threat-model / STRIDE | Claude Code + Fabric | Hermes-4 + Fabric |
| Active recon (refusal-prone) | Hermes-4 (Nous Portal) | Hermes-4 70B local |
| OSINT enrichment loops | Hermes Agent + execute_code | aichat + llm CLI |
| Scheduled monitoring | Hermes Agent cron | system cron + llm CLI |
| Sensitive engagement | DontFeedTheAI + Claude Code | Hermes-4 local |
| Knowledge retrieval | Smart-Connections MCP | ripgrep over vault |
| NL → shell command | atuin ai | llm cmd |
| Pipe-and-summarize | aichat | mods, llm |

Routing is implemented by shell functions (`shell/agents.zsh` — to be authored) backed by `claw_*` family. Operator override is always one keystroke away (the function name).

## Consequences

**Positive**
- No single point of refusal blocks legitimate work.
- Sensitive engagements never egress real PII / IPs / hostnames.
- Local fallback survives network or vendor outages.
- Each model runs at its strength.

**Negative**
- Higher cognitive load: operator must select route. Mitigated by sane defaults (`claw` → Claude, `herm` → Hermes, `lhermes` → local Ollama).
- Three credential surfaces (Anthropic, Nous Portal, local Ollama). Mitigated by `~/.zshenv` + 1Password CLI references.
- Hermes-4 tool-call reliability via Nous Portal is imperfect (issue #741). Mitigated by enabling regex fallback parser in `~/.hermes/config.yaml`.
- Local Hermes-4 70B requires ~48 GB VRAM; may need to drop to 14B / 36B variants depending on hardware.

## Verification

Phase 5 acceptance criterion: a refusal-prone prompt that Claude Code refuses (within the operator's authorized scope) is answered substantively by Hermes. If Hermes also refuses, escalate to local Ollama or surface the gap in the risk register.

## Notes

- RefusalBench is Nous's own benchmark — treat the 57.1% vs 17% gap as directional, not gospel. Validate empirically per Phase 5 gate.
- This ADR does NOT mandate using all three at once. The routing matrix is a suggestion; daily work usually stays on Claude Code.
