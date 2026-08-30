#!/usr/bin/env python3
"""`claw sec scope add` — amend scope without hand-editing a security file (§5.7).

Two layers, two lifetimes:

    global   ~/.claude/scope.txt          durable   standing authority, lab CIDR
    overlay  <engagement>/scope.local     ephemeral on-demand hosts for one run

Effective scope is their union, and a deny in *either* layer wins. Overlay
writes are unattended by design — targets are generated on demand and adding
one must not be a ceremony. Global writes are durable authority and therefore
always confirmed by the caller.

This module only ever *appends validated entries*. It does not remove authority,
it does not rewrite existing lines, and it cannot make a denied target allowed —
`add` refuses rather than producing a file whose meaning contradicts the request.

The engagement root comes from CLAW_SEC_ENGAGEMENT, falling back to
./engagements/current, so `scope add` and `run` agree on where an engagement
lives without either being told twice.
"""
from __future__ import annotations

import os
from pathlib import Path

import scope as S

__all__ = [
    "OVERLAY_NAME", "DEFAULT_GLOBAL", "engagement_root", "overlay_path",
    "classify", "AddResult", "add_entry", "describe_layers",
]

OVERLAY_NAME = "scope.local"
DEFAULT_GLOBAL = Path("~/.claude/scope.txt")
DEFAULT_ENGAGEMENT = Path("engagements/current")

_OVERLAY_HEADER = """\
# Engagement scope overlay (§5.7) — EPHEMERAL.
#
# On-demand hosts authorized for this engagement only. The durable allowlist is
# ~/.claude/scope.txt; this file is unioned with it, and a deny in either layer
# wins. Delete this file and the authority it grants is gone.
#
# Written by `claw sec scope add`.
"""


def engagement_root(explicit=None) -> Path:
    """CLAW_SEC_ENGAGEMENT, else ./engagements/current. An explicit path wins."""
    if explicit:
        return Path(explicit).expanduser()
    env = os.environ.get("CLAW_SEC_ENGAGEMENT")
    if env:
        return Path(env).expanduser()
    return Path.cwd() / DEFAULT_ENGAGEMENT


def overlay_path(explicit=None) -> Path:
    return engagement_root(explicit) / OVERLAY_NAME


def global_path() -> Path:
    return Path(os.environ.get("CLAW_SEC_SCOPE_FILE", "")).expanduser() \
        if os.environ.get("CLAW_SEC_SCOPE_FILE") else DEFAULT_GLOBAL.expanduser()


def classify(entry: str) -> str:
    """'cidr' | 'name' — or raise ScopeParseError. The grammar is scope.py's,
    borrowed rather than restated so `add` can never accept something the
    parser will later reject (or vice versa)."""
    token = entry.strip()
    if not token:
        raise S.ScopeParseError("empty entry")
    if token.startswith("!"):
        raise S.ScopeParseError(
            "refusing to add a deny entry: `add` grants authority, it never "
            "removes it — edit the scope file directly to deny")
    if token.startswith("resolve-policy"):
        raise S.ScopeParseError(
            "resolve-policy is a directive, not a target — set it in the file itself")
    if S._as_network(token) is not None:
        return "cidr"
    S._validate_name(token, 0)   # raises ScopeParseError with the reason
    return "name"


def canonical(entry: str) -> str:
    """The form written to the file: lowercased, trailing dot stripped, CIDRs
    normalized to their network address so 10.0.0.5/8 and 10.0.0.0/8 collapse."""
    token = entry.strip()
    net = S._as_network(token)
    if net is not None:
        return str(net)
    return token.lower().rstrip(".")


class AddResult:
    """What `add_entry` did, so callers can report precisely instead of guessing."""

    def __init__(self, entry, layer, path, status, detail=""):
        self.entry = entry
        self.layer = layer            # "overlay" | "global"
        self.path = Path(path)
        self.status = status          # "added" | "already-present" | "denied"
        self.detail = detail

    @property
    def ok(self) -> bool:
        return self.status in ("added", "already-present")

    def __repr__(self):  # pragma: no cover - debugging aid
        return f"<AddResult {self.status} {self.entry!r} -> {self.path}>"


def _existing_entries(path: Path) -> set[str]:
    if not path.exists():
        return set()
    out = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            out.add(canonical(line.lstrip("!").strip()) if line.startswith("!") else canonical(line))
    return out


def add_entry(entry: str, *, to_global: bool = False, engagement=None,
              global_file=None) -> AddResult:
    """Append one validated entry to the chosen layer.

    Refuses when a deny entry in the *effective* scope would contradict the
    addition — adding a name the global file explicitly denies would otherwise
    write a line that grants nothing and quietly misleads the operator.
    """
    kind = classify(entry)                 # raises on malformed input
    value = canonical(entry)

    gpath = Path(global_file).expanduser() if global_file else global_path()
    opath = overlay_path(engagement)
    layer = "global" if to_global else "overlay"
    target = gpath if to_global else opath

    # A deny anywhere in the effective scope wins (§5.7), so adding an allow
    # for it is a no-op the operator would misread as authorization.
    effective = S.Scope.from_files(gpath, opath if opath.exists() else None)
    probe = value[2:] if value.startswith("*.") else value
    if kind == "name":
        if effective.denied(probe, []):
            return AddResult(value, layer, target, "denied",
                             "an explicit deny entry already covers it")
    elif effective.addr_denies(probe.split("/")[0]):
        return AddResult(value, layer, target, "denied",
                         "an explicit deny entry already covers it")

    if value in _existing_entries(target):
        return AddResult(value, layer, target, "already-present", str(target))

    target.parent.mkdir(parents=True, exist_ok=True)
    fresh = not target.exists()
    with target.open("a", encoding="utf-8") as fh:
        if fresh and layer == "overlay":
            fh.write(_OVERLAY_HEADER)
        elif not fresh:
            existing = target.read_text(encoding="utf-8")
            if existing and not existing.endswith("\n"):
                fh.write("\n")
        fh.write(value + "\n")

    # Parse what we just wrote. A file `add` cannot read back is a file it must
    # not have written — surface it now, not on the next gated invocation.
    S.Scope.from_files(gpath, opath if opath.exists() else None)
    return AddResult(value, layer, target, "added", str(target))


def describe_layers(engagement=None, global_file=None) -> dict:
    """Both layers and the effective scope, for `claw sec scope` to render."""
    gpath = Path(global_file).expanduser() if global_file else global_path()
    opath = overlay_path(engagement)
    effective = S.Scope.from_files(gpath, opath if opath.exists() else None)
    return {
        "global_path": gpath,
        "overlay_path": opath,
        "overlay_active": opath.exists(),
        "scope": effective,
        "facts": effective.facts(),
    }
