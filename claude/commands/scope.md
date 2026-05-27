---
description: Append a target to ~/.claude/scope.txt after operator confirmation. Use for /scope <domain|ip|cidr>.
---

The operator wants to add `$ARGUMENTS` to `~/.claude/scope.txt`.

Steps:
1. Validate `$ARGUMENTS` is a plausible target (domain glob, IPv4, IPv6, hostname, or CIDR). If it's empty or malformed, refuse with an example.
2. Read `~/.claude/scope.txt` and check whether the target (or a covering CIDR) is already present. If yes, report and exit.
3. Show the operator:
   - The line you propose to append.
   - Existing scope entries for visual context.
   - A brief risk note (e.g., "wildcard `*.example.com` covers ALL subdomains — confirm intent").
4. Ask for explicit confirmation in chat ("yes" / "no").
5. On "yes": append with a leading comment line `# added <UTC ISO8601> via /scope` and the target. Then `cat` the relevant section back so the operator can verify.
6. On "no": exit.

Rules:
- Never silently append.
- Never use `sudo`.
- Backup `~/.claude/scope.txt` to `~/.dotfiles-backups/$(date +%Y%m%d-%H%M%S)/scope.txt` before any write.
- The pre_tool_use.py hook enforces scope at scan time — adding to scope is a deliberate, reviewed action.
