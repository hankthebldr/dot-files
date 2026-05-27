---
description: Generate a STRIDE threat model from a design doc, architecture diagram, or system description. Use for /threat-model <file-or-description>.
---

Invoke the `stride-threat-model` skill to produce a threat register and recommended detections for `$ARGUMENTS`.

Pre-flight:
1. If `$ARGUMENTS` is a file path, read it. If it's a description, use it directly.
2. Confirm you have:
   - Components and data flows
   - Trust boundaries
   - Asset inventory
   - Existing controls
3. If any are missing, ask **one** sharp question to fill the gap. Don't guess.

Execution:
1. Decompose the system. Render trust boundaries in mermaid.
2. Walk STRIDE for every component and every flow. Generate threats.
3. Likelihood × impact → priority.
4. Map existing + recommended controls.
5. Author the threat register table.
6. Sketch Cortex XSIAM/XDR detections (XQL) for every P1 / P2 threat.

Output (using `report-writeup` skill structure):
- Executive summary (top 3 risks, business-language).
- Architecture (mermaid).
- Threat register table.
- Recommended detections.
- Open questions.

Storage:
- If `$OBSIDIAN_VAULT` is set, propose `/handoff` to write to `$OBSIDIAN_VAULT/50-Threat-Models/`.
