#!/usr/bin/env python3
"""Pre-tool-use hook.

Blocks:
  1. Catastrophic shell ops (rm -rf /, dd of=/dev/, mass writes to /etc).
  2. Active recon/scan tools targeting hosts not in ~/.claude/scope.txt.
  3. Credential exfiltration via curl/wget POST with sensitive paths in body.

Exit codes:
  0 = allow
  2 = deny (stderr is shown to Claude as the deny reason)

Reads stdin: JSON {tool_name, tool_input, ...}
"""
from __future__ import annotations

import json
import re
import sys
import shlex

sys.path.insert(0, str(__import__("pathlib").Path(__file__).parent))
from _lib import (  # noqa: E402
    C, banner_block, extract_targets, in_scope, log_row, redact, stderr,
)

# ─── Static block patterns ──────────────────────────────────────────────
CATASTROPHIC = [
    re.compile(r"\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+/(\s|$)"),
    re.compile(r"\brm\s+-rf\s+/\*"),
    re.compile(r"\bdd\s+.*of=/dev/(sd|nvme|hd|disk)"),
    re.compile(r"\bmkfs\.\w+\s+/dev/"),
    re.compile(r":\(\)\s*\{.*:\|:&"),  # fork bomb
    re.compile(r"\bchmod\s+-R?\s+777\s+/(\s|$)"),
    re.compile(r"\bchown\s+-R?\s+.*\s+/(\s|$)"),
    re.compile(r"(?:>|tee\s+)\s*/etc/(passwd|shadow|sudoers)"),
]

# Recon tools whose first hostname/IP arg must be in scope
RECON_TOOLS = {
    "nmap", "masscan", "rustscan", "naabu",
    "nuclei", "ffuf", "gobuster", "feroxbuster", "dirb",
    "sqlmap", "wpscan", "nikto",
    "subfinder", "amass", "assetfinder", "findomain",
    "httpx", "katana", "hakrawler",
    "hydra", "medusa", "patator",
    "wfuzz", "dnsx",
}

# Credential exfil sensors (curl/wget posting sensitive paths)
EXFIL_PATHS = (
    r"~/\.ssh/", r"\$HOME/\.ssh/", r"/Users/[^/]+/\.ssh/", r"/home/[^/]+/\.ssh/",
    r"~/\.aws/", r"\$HOME/\.aws/", r"/Users/[^/]+/\.aws/", r"/home/[^/]+/\.aws/",
    r"\.env(\b|[\"'/])",
    r"id_rsa", r"id_ed25519",
)
EXFIL_RE = re.compile(
    r"\b(curl|wget)\b.*(?:-X\s*POST|--data|-d\s|--upload-file|-T\s).*?(" +
    "|".join(EXFIL_PATHS) + ")",
    re.IGNORECASE | re.DOTALL,
)


def deny(tool: str, cmd: str, reason: str, targets: list[str] | None = None) -> None:
    log_row(
        event="pre", tool=tool, decision="deny", reason=reason,
        cmd_excerpt=redact(cmd[:400]),
        targets=json.dumps(targets or []),
    )
    stderr(banner_block(
        "✗ TOOL USE DENIED",
        [
            f"{C.BOLD}Tool:{C.RESET} {tool}",
            f"{C.BOLD}Reason:{C.RESET} {reason}",
            f"{C.MUTED}cmd:{C.RESET} {redact(cmd[:200])}",
            "",
            f"{C.MUTED}If this is legitimate, propose a scope.txt amendment via /scope.{C.RESET}",
        ],
    ))
    sys.exit(2)


def allow(tool: str, cmd: str, reason: str = "ok", targets: list[str] | None = None) -> None:
    log_row(
        event="pre", tool=tool, decision="allow", reason=reason,
        cmd_excerpt=redact(cmd[:400]),
        targets=json.dumps(targets or []),
    )
    sys.exit(0)


def main() -> None:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        sys.exit(0)  # don't block on malformed input

    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {}) or {}

    # We only inspect Bash for now; other tools default-allow.
    if tool != "Bash":
        sys.exit(0)

    cmd = (tool_input.get("command") or "").strip()
    if not cmd:
        sys.exit(0)

    # 1. Catastrophic
    for pat in CATASTROPHIC:
        if pat.search(cmd):
            deny(tool, cmd, f"catastrophic shell op (pattern: {pat.pattern[:60]})")

    # 2. Credential exfil
    if EXFIL_RE.search(cmd):
        deny(tool, cmd, "credential exfiltration pattern (curl/wget POST with sensitive path)")

    # 3. Recon scope check
    try:
        argv = shlex.split(cmd, posix=True)
    except ValueError:
        argv = cmd.split()
    if not argv:
        sys.exit(0)
    bin_name = argv[0].rsplit("/", 1)[-1]
    if bin_name in RECON_TOOLS:
        targets = extract_targets(cmd)
        if not targets:
            deny(tool, cmd, f"recon tool {bin_name} invoked with no parseable target")
        for t in targets:
            if not in_scope(t):
                deny(
                    tool, cmd,
                    f"target {t!r} not in ~/.claude/scope.txt (default-deny)",
                    targets=targets,
                )
        allow(tool, cmd, reason=f"recon-in-scope:{bin_name}", targets=targets)

    allow(tool, cmd)


if __name__ == "__main__":
    main()
