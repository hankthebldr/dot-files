---
name: recon-methodology
description: Use when planning or executing reconnaissance against an authorized target. Enforces passive→active enumeration ladder with OPSEC defaults. Trigger phrases - "recon", "enumerate", "attack surface", "subdomain enumeration", "port scan", "what's exposed".
---

# Recon methodology

A passive-first ladder. Climb only as far as the engagement authorizes. Every active step validates against `~/.claude/scope.txt` (the pre-tool-use hook enforces this — don't bypass).

## Ladder

| Tier | Posture | Tools | What it tells you |
|---|---|---|---|
| 0. Pre-flight | Read-only | `cat ~/.claude/scope.txt`, engagement letter | What's in scope. Refuse to proceed if unclear. |
| 1. Passive OSINT | No traffic to target | crt.sh, Censys/Shodan (cached), GitHub dorks, archive.org, DNS history | Cert footprint, public infra, leaked secrets |
| 2. Passive infra | DNS/WHOIS only | `dnsx`, `subfinder` (passive sources), VirusTotal | Subdomain inventory, ASN/owner |
| 3. Soft-touch active | Single TCP/HTTP probes | `httpx -silent -status-code -tech-detect -title`, `dnsx -resp` | Live hosts, tech stack, titles |
| 4. Active enumeration | Full scans | `naabu`/`nmap`, `nuclei -severity medium,high,critical`, `ffuf` | Open ports, CVE candidates, directory layout |
| 5. Targeted exploitation | Per-finding manual | Out of recon scope — handoff to red team | — |

## Defaults

- **Wordlists:** SecLists. Avoid `-recursion-depth >2` without reason.
- **Rate limits:** `nuclei -rl 50`, `ffuf -rate 50`. Higher only with operator green-light.
- **User-Agent:** identify on consensual engagements (`-H "User-Agent: Cortex-Recon/1.0 (engagement <id>)"`); strip on authorized red-team.
- **Storage:** outputs land in `~/work/recon/<engagement>/<YYYY-MM-DD>/<tool>.{json,txt}`. Findings summary lands in `$OBSIDIAN_VAULT/40-Findings/` via `/handoff`.

## Output: structured findings

For every recon session, return:

```yaml
engagement: <id>
scope:
  - <from scope.txt>
posture: <tier reached>
duration_s: <int>
findings:
  - host: example.com
    port: 443
    severity: high|medium|low|info
    title: <short>
    evidence: <output excerpt>
    detection_hint: <XSIAM/XDR rule sketch where applicable>
followups:
  - <next step proposal, requires operator approval>
```

## Escalation rules

- **Tier 4 finding with severity ≥ high** → pause, surface to operator, await go/no-go before any tier-5 follow-up.
- **Suspected breach indicator** (live web shell, leaked production cred) → IR handoff template, do NOT continue scanning.
- **Out-of-scope subdomain discovered** → log it, do NOT probe, propose `/scope` amendment.
