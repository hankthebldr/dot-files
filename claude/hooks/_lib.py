"""Shared helpers for Claude Code hooks.

Owns: scope resolution (delegated), SQLite log path, ANSI styling for stderr.

Scope authority lives in ONE place — `scripts/security/scope.py` — and this
module borrows it (build order §18.10). It used to carry a second, independent
parser, which read a `!deny` entry as an ordinary allow-list name that never
matched, silently discarding the exclusion. The hook then permitted recon the
harness gate refused: a confused deputy in the fail-open direction.
"""
from __future__ import annotations

import os
import re
import sqlite3
import sys
from pathlib import Path
from typing import Iterable

# ─── Paths ──────────────────────────────────────────────────────────────
CLAUDE_HOME = Path(os.environ.get("CLAUDE_HOME", Path.home() / ".claude"))
SCOPE_FILE = CLAUDE_HOME / "scope.txt"
LOG_DIR = CLAUDE_HOME / "logs"
LOG_DB = LOG_DIR / "tool-use.sqlite"

# ─── ANSI (GitHub Dark palette) ─────────────────────────────────────────
class C:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    BLUE = "\033[38;5;75m"     # #58a6ff
    GREEN = "\033[38;5;78m"    # #3fb950
    PURPLE = "\033[38;5;141m"  # #bc8cff
    ORANGE = "\033[38;5;215m"  # #d29922
    RED = "\033[38;5;203m"     # #ff7b72
    MUTED = "\033[38;5;245m"   # #8b949e


def banner_block(title: str, lines: Iterable[str], color: str = C.RED) -> str:
    body = "\n".join(f"{color}║{C.RESET}  {line}" for line in lines)
    bar = f"{color}╔══ {C.BOLD}{title}{C.RESET}{color} {'═' * max(1, 60 - len(title))}{C.RESET}"
    foot = f"{color}╚{'═' * 64}{C.RESET}"
    return f"{bar}\n{body}\n{foot}"


# ─── Scope ──────────────────────────────────────────────────────────────
def _scope_module():
    """Import the harness's scope parser. Returns None if it cannot be reached.

    ~/.claude/hooks/_lib.py is a symlink into the dotfiles repo, so resolving
    this file lands inside the checkout and `parents[2]` is its root. DOTFILES_DIR
    wins when set; ~/.dotfiles is the last resort for an unusual layout.
    """
    roots = []
    env = os.environ.get("DOTFILES_DIR")
    if env:
        roots.append(Path(env))
    roots.append(Path(__file__).resolve().parents[2])
    roots.append(Path.home() / ".dotfiles")

    for root in roots:
        d = root / "scripts" / "security"
        if (d / "scope.py").is_file():
            if str(d) not in sys.path:
                sys.path.insert(0, str(d))
            try:
                import scope  # noqa: PLC0415  — deliberately lazy; see _scope()
                return scope
            except Exception:
                return None
    return None


def _scope():
    """The parsed Scope, or None. Every failure path yields None, and every
    caller treats None as 'authorize nothing' — a hook that cannot read its
    scope must not be the reason a scan proceeds.

    Deliberately not memoized. The file is small, a hook invocation asks about
    a handful of targets, and a cached verdict would outlive an operator's edit
    to scope.txt. Only the module import is cached, by `sys.modules`.
    """
    mod = _scope_module()
    if mod is None or not SCOPE_FILE.exists():
        return None
    try:
        return mod.Scope.from_files(SCOPE_FILE)
    except Exception:
        # Malformed scope (ScopeParseError) or unreadable file. The old parser
        # accepted junk silently; refusing to authorize is the safe reading.
        return None


def in_scope(target: str) -> bool:
    """Name-level authorization, identical to the harness gate's name/deny half.

    Address verification (§5.2 resolve-policy) is deliberately NOT attempted:
    the hook runs before execution and has no resolved addresses. The harness
    gate applies that extra check at invoke time, so it can only ever be
    stricter than this — never more permissive.
    """
    if not target:
        return False
    sc = _scope()
    if sc is None:
        return False
    if sc.denied(target, []):
        return False
    return sc.name_allows(target)


# ─── Target extraction from common recon CLIs ───────────────────────────
# Matches the LAST plausible host/IP/CIDR in the cmd line. Naive but effective.
HOST_RE = re.compile(
    r"(?:(?<=\s)|(?<=^))"
    r"((?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?"   # IPv4 or CIDR
    r"|[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?"
    r"(?:\.[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?)+)"
    r"(?=\s|$|/)",
    re.IGNORECASE,
)


def extract_targets(cmd: str) -> list[str]:
    """Best-effort: pull domains/IPs/CIDRs out of a recon command line."""
    return [m.group(1) for m in HOST_RE.finditer(cmd)]


# ─── SQLite log ─────────────────────────────────────────────────────────
DDL = """
CREATE TABLE IF NOT EXISTS tool_use (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL DEFAULT (datetime('now')),
    event TEXT NOT NULL,           -- pre|post
    tool TEXT NOT NULL,
    decision TEXT,                 -- allow|deny|null
    reason TEXT,
    cmd_excerpt TEXT,              -- first 400 chars of cmd, secrets-redacted
    targets TEXT,                  -- JSON array of extracted hosts
    exit_code INTEGER,
    output_len INTEGER
);
CREATE INDEX IF NOT EXISTS idx_tool_use_ts ON tool_use(ts);
CREATE INDEX IF NOT EXISTS idx_tool_use_tool ON tool_use(tool);
"""

SECRET_PATTERNS = [
    re.compile(r"(AKIA[0-9A-Z]{16})"),                       # AWS access key id
    re.compile(r"(ghp_[A-Za-z0-9]{30,})"),                   # GitHub PAT
    re.compile(r"(sk-[A-Za-z0-9]{20,})"),                    # OpenAI/Anthropic-ish
    re.compile(r"(eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+)"),  # JWT
    re.compile(r"(?i)(authorization:\s*bearer\s+)\S+"),      # Bearer headers
    re.compile(r"(?i)(api[_-]?key[\"'\s:=]+)\S+"),
]


def redact(s: str) -> str:
    if not s:
        return s
    out = s
    for pat in SECRET_PATTERNS:
        out = pat.sub(lambda m: m.group(1) + "<REDACTED>" if m.lastindex == 1 else "<REDACTED>", out)
    return out


def db() -> sqlite3.Connection:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(LOG_DB)
    conn.executescript(DDL)
    return conn


def log_row(**kw) -> None:
    cols = ("event", "tool", "decision", "reason", "cmd_excerpt", "targets", "exit_code", "output_len")
    vals = tuple(kw.get(c) for c in cols)
    placeholders = ", ".join("?" for _ in cols)
    with db() as conn:
        conn.execute(
            f"INSERT INTO tool_use ({', '.join(cols)}) VALUES ({placeholders})",
            vals,
        )


def stderr(msg: str) -> None:
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()
