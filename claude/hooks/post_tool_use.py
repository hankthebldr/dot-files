#!/usr/bin/env python3
"""Post-tool-use hook. Logs every tool call to ~/.claude/logs/tool-use.sqlite.

Reads stdin: JSON {tool_name, tool_input, tool_response, ...}
Always exits 0 (logging must never block).
"""
from __future__ import annotations

import json
import sys

sys.path.insert(0, str(__import__("pathlib").Path(__file__).parent))
from _lib import extract_targets, log_row, redact  # noqa: E402


def _coerce_str(x) -> str:
    if x is None:
        return ""
    if isinstance(x, str):
        return x
    try:
        return json.dumps(x)[:2000]
    except (TypeError, ValueError):
        return str(x)[:2000]


def main() -> None:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        sys.exit(0)

    tool = payload.get("tool_name", "unknown")
    tool_input = payload.get("tool_input", {}) or {}
    tool_response = payload.get("tool_response", {}) or {}

    cmd = ""
    if tool == "Bash":
        cmd = tool_input.get("command", "") or ""
    else:
        cmd = _coerce_str(tool_input)[:400]

    response_str = _coerce_str(tool_response)
    exit_code = None
    if isinstance(tool_response, dict):
        ec = tool_response.get("exit_code") or tool_response.get("exitCode")
        if isinstance(ec, int):
            exit_code = ec

    targets = extract_targets(cmd) if cmd else []

    try:
        log_row(
            event="post",
            tool=tool,
            decision=None,
            reason=None,
            cmd_excerpt=redact(cmd[:400]),
            targets=json.dumps(targets),
            exit_code=exit_code,
            output_len=len(response_str),
        )
    except Exception:
        pass  # never block

    sys.exit(0)


if __name__ == "__main__":
    main()
