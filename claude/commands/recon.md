---
description: Run the recon pipeline against an authorized target. Use for /recon <domain|ip>.
---

Invoke the `recon-methodology` skill to plan and execute reconnaissance against `$ARGUMENTS`.

Required pre-flight:
1. Confirm `$ARGUMENTS` is in `~/.claude/scope.txt`. If not, refuse and propose `/scope $ARGUMENTS`.
2. State the engagement context (id, authorization reference, dates) — ask the operator if not in current conversation memory.
3. Confirm posture: which tier of the recon ladder is authorized for this engagement. Default: tier 3 (soft-touch active) unless the operator green-lights tier 4.

Execution:
1. Walk the recon-methodology ladder up to the authorized tier.
2. Each tool invocation passes through the pre_tool_use.py hook — do not attempt to bypass.
3. Output each tier's results before moving to the next. Wait for operator go/no-go between tiers 3→4.
4. Land outputs in `~/work/recon/<engagement>/$(date +%Y-%m-%d)/<tool>.{json,txt}`.

Output:
- Structured findings YAML per the recon-methodology skill.
- Final summary using `report-writeup` skill (executive + technical).
- Propose `/handoff` to write the summary to the Obsidian vault.

Stop conditions:
- High/Critical finding → pause, surface to operator, await direction.
- Out-of-scope target discovered → log only, do not probe.
- Suspected breach indicator → switch to IR handoff format.
