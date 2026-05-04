---
name: report-writeup
description: Use when the operator asks for a written report, briefing, executive summary, customer deliverable, engagement write-up, or PoC findings doc. Produces PANW Cortex-style two-section output (executive + technical) with consistent formatting.
---

# Report writeup (Cortex/PANW style)

Default deliverable shape. Used for engagement reports, PoC writeups, customer briefings, internal handoffs.

## Two-section structure (mandatory)

### 1. Executive summary
- **One paragraph.** Business language. Audience: CISO, risk officer, BU leader.
- Names: the **risk**, the **business impact**, the **recommended action**.
- **No tool names.** No CVE numbers. No XQL. No jargon that requires SOC fluency.
- Lead with the risk, not the methodology.

### 2. Technical detail
- Audience: SOC analyst, red team peer, detection engineer.
- Sections, in order:
  1. **Scope** — what was assessed, what was excluded, dates, authorization reference.
  2. **Methodology** — tools, posture (passive/active tier), key configuration choices.
  3. **Findings** — table, ranked by severity. Each row: id, severity, asset, finding, evidence excerpt, recommended remediation.
  4. **IOCs** (when applicable) — defanged, with context. Reference `iocs-extract` skill output.
  5. **Recommended detections** — XSIAM/XDR rule sketches. XQL preferred. Tag with MITRE ATT&CK technique IDs.
  6. **Reproduction steps** — terse, ordered list. Operator can rerun.
  7. **Open questions / followups** — explicit. Don't bury.

## Style

- **Severity language:** Critical / High / Medium / Low / Info. No "very serious", no "concerning".
- **Numbers over adjectives.** "12 open Redis instances across 3 subnets" beats "many exposed Redis services".
- **Time is UTC.** ISO 8601 format.
- **Code blocks** for tool output, XQL, queries. Never inline-quote multi-line output.
- **Tables** for findings, IOCs, scope. Markdown table format.
- **Mermaid** for any topology, sequence, or data flow.

## Cortex XSIAM/XDR detection sketch format

```markdown
### Detection: <short name>
**ATT&CK:** Txxxx (Technique name)
**Severity:** High
**Confidence:** Medium

```xql
dataset = <source>
| filter <condition>
| comp count() as hits by <dimension>
| filter hits > <threshold>
```

**False-positive risks:** <list>
**Tuning notes:** <list>
```

## Defaults

- **Length:** technical section as long as needed; executive ≤ 150 words.
- **Naming:** filename `engagement-<id>-report-YYYY-MM-DD.md`.
- **Storage:** lands in `$OBSIDIAN_VAULT/40-Findings/` via `/handoff` slash command (Phase 8).
- **Sanitization for cloud delivery:** when generating via Claude Code with sensitive data, route through `safeclaude` (DontFeedTheAI proxy, Phase 7).
