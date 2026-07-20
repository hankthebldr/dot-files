#!/usr/bin/env python3
"""Post-tool-use hook.

1. Logs every tool call to ~/.claude/logs/tool-use.sqlite (never blocks).
2. Lints shell files just edited via Edit/Write/MultiEdit — shellcheck error
   tier for bash/sh, `zsh -n` for zsh — mirroring ci.yml so a break surfaces
   at edit time instead of after push. A lint failure exits 2 (stderr is fed
   back to Claude); everything else exits 0.

Reads stdin: JSON {tool_name, tool_input, tool_response, ...}
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _lib import C, banner_block, extract_targets, log_row, redact, stderr  # noqa: E402

# Mirrors the ci.yml "error severity" shellcheck step.
SHELLCHECK_EXCLUDES = "SC1090,SC1091"


def _shell_dialect(path: Path) -> str | None:
    """'zsh' | 'sh' | None for a just-edited file, by suffix then shebang."""
    name = path.name
    if name.endswith(".zsh") or name in (".zshrc", ".zshenv", ".p10k.zsh"):
        return "zsh"
    if name.endswith(".sh") or name.endswith(".bash"):
        return "sh"
    if "." in name.lstrip("."):
        return None  # has some other extension — not a shell script
    try:
        with path.open("rb") as fh:
            first = fh.readline(120).decode("utf-8", "replace")
    except OSError:
        return None
    if not first.startswith("#!"):
        return None
    if "zsh" in first:
        return "zsh"
    if re.search(r"\b(ba)?sh\b", first):
        return "sh"
    return None


def lint_shell_edit(path_str: str) -> None:
    """Run the CI-equivalent check on one edited file; exit 2 on failure."""
    if not path_str:
        return
    path = Path(path_str)
    if not path.is_file():
        return
    dialect = _shell_dialect(path)
    if dialect is None:
        return
    if dialect == "zsh":
        label, argv = "zsh -n", ["zsh", "-n", str(path)]
    else:
        label = "shellcheck -S error"
        argv = ["shellcheck", "-S", "error", "-e", SHELLCHECK_EXCLUDES, str(path)]
    if shutil.which(argv[0]) is None:
        return
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return
    if proc.returncode == 0:
        return
    detail = (proc.stdout + proc.stderr).strip()[:1500] or "(no output)"
    stderr(banner_block(
        "✗ SHELL LINT FAILED (post-edit)",
        [
            f"{C.BOLD}File:{C.RESET} {path}",
            f"{C.BOLD}Check:{C.RESET} {label}  {C.MUTED}(same tier CI enforces){C.RESET}",
            "",
            *detail.splitlines()[:20],
            "",
            f"{C.MUTED}Fix before committing — ci.yml runs this exact check.{C.RESET}",
        ],
        color=C.ORANGE,
    ))
    sys.exit(2)


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

    if tool in ("Edit", "Write", "MultiEdit"):
        try:
            lint_shell_edit(tool_input.get("file_path") or "")
        except SystemExit:
            raise
        except Exception:
            pass  # lint plumbing must never break the hook

    sys.exit(0)


if __name__ == "__main__":
    main()
