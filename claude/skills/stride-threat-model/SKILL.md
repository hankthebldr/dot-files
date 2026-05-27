---
name: stride-threat-model
description: Use when the operator asks for a STRIDE threat model, security review of an architecture, or asks "what could go wrong" about a system design. Wraps the structured STRIDE methodology and produces an actionable threat register.
---

# STRIDE threat model

STRIDE = Spoofing, Tampering, Repudiation, Information Disclosure, DoS, Elevation of Privilege.

## Inputs you need

1. **System diagram** — components + data flows + trust boundaries. ASCII/mermaid is fine.
2. **Asset inventory** — what's worth attacking (data, accounts, infra).
3. **Trust model** — who is trusted at each boundary.
4. **Existing controls** — auth, encryption, monitoring, segmentation.

If any input is missing, ask one sharp question. Don't guess.

## Method

1. Decompose the system into **components** and **data flows**. Mark trust boundaries explicitly.
2. For each component AND each flow, walk all six STRIDE categories. Generate threats.
3. For each threat: rate **likelihood** (low/med/high) × **impact** (low/med/high) → priority.
4. Map controls (existing + recommended). Identify gaps.
5. Output a **threat register** + **Cortex/PANW-style summary**.

## Output template

```markdown
# Threat Model — <system>
**Date:** <YYYY-MM-DD>  **Reviewer:** Henry  **Spec version:** <ref>

## Executive summary
<one paragraph, business language, names top 3 risks + recommended action>

## Architecture (decomposed)
```mermaid
<component diagram with trust boundaries>
```

## Threat register
| ID | Component | Category | Threat | Likelihood | Impact | Priority | Existing control | Recommended control |
|---|---|---|---|---|---|---|---|---|
| T-001 | API gateway | Spoofing | ... | M | H | P1 | mTLS to backend | Add JWT iss/aud validation |

## Recommended detections (Cortex XSIAM/XDR)
- T-001: XQL rule sketch: `dataset = http_logs | filter ...`
- ...

## Open questions
- ...
```

## Defaults

- Default to **high-impact, plausibly-likely** threats. Don't pad with theoretical exotics unless the ask is explicitly comprehensive.
- For Cortex/PANW pre-sales: every threat that maps to an XSIAM/XDR detection should include the rule sketch.
- Use mermaid for the architecture diagram. Keep it under 15 nodes.
