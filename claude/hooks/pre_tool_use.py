#!/usr/bin/env python3
"""Pre-tool-use hook.

Blocks:
  1. Catastrophic shell ops (rm -rf /, dd of=/dev/, mass writes to /etc).
  2. Active recon/scan tools targeting hosts not in ~/.claude/scope.txt.
  3. Credential exfiltration via curl/wget POST with sensitive paths in body.
  4. Hand-edits to fastfetch configs owned by scripts/utils/gen-fastfetch.py.

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

# Wrapper commands and env-assignment prefixes to strip before matching a
# segment's leading binary against RECON_TOOLS.
_WRAPPERS = {"sudo", "doas", "env", "command", "nohup", "timeout", "nice", "xargs"}


# Commands that execute a heredoc body as shell. Their bodies stay in scope;
# every other heredoc body is data (a file being written, a doc, a payload).
_SHELL_INTERPRETERS = {
    "bash", "sh", "zsh", "dash", "ksh", "csh", "tcsh", "fish",
    "eval", "source", ".", "ssh", "su", "docker", "kubectl", "podman",
}

_HEREDOC_RE = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def _strip_heredocs(cmd: str) -> str:
    """Drop heredoc bodies that are data rather than script.

    The matcher previously saw tool names inside heredoc payloads — commit
    messages, documentation, report text — and denied the command. A body is
    removed only when the command that owns it is not a shell, and only when
    its terminator is found: an unterminated heredoc means we cannot prove
    where data ends, so nothing is stripped and the scan stays fail-closed.
    """
    lines = cmd.split("\n")
    kept: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        kept.append(line)
        i += 1
        openers = list(_HEREDOC_RE.finditer(line))
        if not openers:
            continue
        owner = _leading_bin(line[: openers[0].start()])
        for match in openers:
            word = match.group(2)
            end = i
            while end < len(lines) and lines[end].strip() != word:
                end += 1
            if end >= len(lines):
                break  # unterminated — fail closed, scan the remainder
            if owner in _SHELL_INTERPRETERS:
                kept.extend(lines[i:end])  # a script, not data
            kept.append(lines[end])
            i = end + 1
    return "\n".join(kept)


def _strip_line_comments(cmd: str) -> str:
    """Drop whole-line comments. A trailing comment is left alone so it cannot
    be used to hide the command it follows."""
    return "\n".join(l for l in cmd.split("\n") if not l.lstrip().startswith("#"))


def _recon_segments(cmd: str) -> list[str]:
    """Split a command line into statement/pipeline segments for recon scanning.

    Quote-aware: a separator inside a quoted string is text, not a boundary.
    Splitting blindly meant prose like "the `nmap` entry" produced a segment
    whose leading word was a tool name.
    """
    segments: list[str] = []
    buf: list[str] = []
    quote = None
    i, n = 0, len(cmd)
    while i < n:
        ch = cmd[i]
        if quote:
            if ch == "\\" and quote == '"' and i + 1 < n:
                buf.append(ch)
                buf.append(cmd[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            buf.append(ch)
            i += 1
            continue
        if ch in "'\"":
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            buf.append(ch)
            buf.append(cmd[i + 1])
            i += 2
            continue
        if cmd.startswith("&&", i) or cmd.startswith("||", i) or cmd.startswith("$(", i):
            segments.append("".join(buf))
            buf = []
            i += 2
            continue
        if ch in ";|&`()\n":
            segments.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    segments.append("".join(buf))
    return [s for s in segments if s.strip()]


def recon_hits(cmd: str) -> list[tuple]:
    """Segments that actually invoke a recon tool in command position.

    Heredoc payloads and whole-line comments are removed first, so a command
    that merely *discusses* a tool is not treated as running one. See §20.1 of
    docs/superpowers/specs/2026-08-23-security-harness-design.md.
    """
    scanned = _strip_line_comments(_strip_heredocs(cmd))
    return [(seg, _leading_bin(seg)) for seg in _recon_segments(scanned)
            if _leading_bin(seg) in RECON_TOOLS]


def _leading_bin(segment: str) -> str:
    """First real binary in a segment, past env-assignments and wrappers."""
    try:
        argv = shlex.split(segment, posix=True)
    except ValueError:
        argv = segment.split()
    i = 0
    while i < len(argv):
        tok = argv[i]
        if "=" in tok and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
            i += 1  # env assignment
            continue
        base = tok.rsplit("/", 1)[-1]
        if base in _WRAPPERS:
            i += 1  # wrapper command
            continue
        return base
    return ""

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

# fastfetch configs owned by scripts/utils/gen-fastfetch.py — a hand-edit is
# clobbered on the next generator run. Matched by basename + parent dir so the
# repo file, the ~/.dotfiles clone, and the stowed ~/.config symlink all hit.
GENERATED_FASTFETCH = {
    "config.jsonc", "config-default.jsonc",
    "config-cloud.jsonc", "config-security.jsonc", "config-devops.jsonc",
    "config-ai.jsonc", "config-research.jsonc", "config-cortex.jsonc",
    "config-local.jsonc",
}

# Obfuscated / alternate-channel exfil the curl-POST sensor above misses.
# These are the channels a prompt-injection payload reaches for once it has
# coaxed the agent into shelling out: encode-then-send, DNS tunnelling, and
# raw sockets. High-signal — these shapes almost never occur in legit work.
_SENS = "(?:" + "|".join(EXFIL_PATHS) + ")"
_EGRESS = r"(?:curl|wget|nc|ncat|netcat|socat|telnet|dig|host|nslookup|openssl\s+s_client)"
_ENCODE = r"(?:base64|xxd|od\b|openssl\s+enc|gzip|gpg|xz)"
EXFIL_OBFUSCATED = [
    # encode a secret, then pipe to any egress tool:  cat ~/.ssh/id_rsa | base64 | curl ...
    re.compile(_SENS + r".*\|\s*" + _ENCODE + r".*\|\s*" + _EGRESS, re.IGNORECASE | re.DOTALL),
    re.compile(_ENCODE + r"\b.*" + _SENS + r".*\|\s*" + _EGRESS, re.IGNORECASE | re.DOTALL),
    # DNS exfil: secret spliced into a lookup via command substitution
    re.compile(r"\b(?:dig|host|nslookup)\b.*\$\(.*?" + _SENS, re.IGNORECASE | re.DOTALL),
    re.compile(r"\b(?:dig|host|nslookup)\b.*`.*?" + _SENS, re.IGNORECASE | re.DOTALL),
    # raw secret read piped straight into a non-curl/wget network tool
    re.compile(_SENS + r".*\|\s*(?:nc|ncat|netcat|socat|telnet)\b", re.IGNORECASE | re.DOTALL),
]


def deny(tool: str, cmd: str, reason: str, targets: list[str] | None = None,
         hint: str = "If this is legitimate, propose a scope.txt amendment via /scope.") -> None:
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
            f"{C.MUTED}{hint}{C.RESET}",
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

    # 0. Generated-file guard: file-editing tools may not touch generator output.
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        fp = (tool_input.get("file_path") or tool_input.get("notebook_path") or "").strip()
        parts = fp.replace("\\", "/").rstrip("/").rsplit("/", 2)
        if len(parts) == 3 and parts[1] == "fastfetch" and parts[2] in GENERATED_FASTFETCH:
            deny(
                tool, fp,
                f"{parts[2]} is generated by scripts/utils/gen-fastfetch.py",
                hint="Edit the generator, then re-run: python3 scripts/utils/gen-fastfetch.py",
            )
        sys.exit(0)

    # Beyond this point we only inspect Bash; other tools default-allow.
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
    for pat in EXFIL_OBFUSCATED:
        if pat.search(cmd):
            deny(tool, cmd, "obfuscated credential-exfil pattern (encode / DNS / raw-socket channel)")

    # Generated-fastfetch guard for shell-side edits (sed -i / tee / redirect).
    for gen in GENERATED_FASTFETCH:
        if gen in cmd and re.search(r"(sed\s+-i|tee|>>?)\b", cmd) and "fastfetch" in cmd:
            deny(
                tool, cmd,
                f"{gen} is generated by scripts/utils/gen-fastfetch.py",
                hint="Edit the generator, then re-run: python3 scripts/utils/gen-fastfetch.py",
            )

    # 3. Recon scope check — scan every pipeline/statement segment, stripping
    #    sudo/env/wrapper prefixes so `sudo nmap` and `x; nmap` can't bypass.
    hit_recon = False
    for seg, _bin in recon_hits(cmd):
        hit_recon = True
        targets = extract_targets(seg)
        if not targets:
            deny(tool, cmd, f"recon tool in {seg.strip()!r} invoked with no parseable target")
        for t in targets:
            if not in_scope(t):
                deny(tool, cmd, f"target {t!r} not in ~/.claude/scope.txt (default-deny)", targets=targets)
    if hit_recon:
        allow(tool, cmd, reason="recon-in-scope")

    allow(tool, cmd)


if __name__ == "__main__":
    main()
