#!/usr/bin/env python3
"""Preflight: assert what a binary *is*, never that a name resolves (spec §13).

`command -v` is not a check. On this workstation it reported four tools
present that turned out to be a Python library and three git aliases. The
failure mode that follows is the dangerous one: the wrong binary runs, exits
zero, prints nothing, and the run records a clean target.

`claw sec doctor` runs each registry entry's `verify` argv and requires its
`expect` string in the output, then attaches the provisioning trap for that
tool so it is surfaced before a run rather than diagnosed after one.
"""
from __future__ import annotations

import platform
import sys
from dataclasses import dataclass
from pathlib import Path

import yaml

import registry as R

REPO = Path(__file__).resolve().parents[2]
TRAPS_PATH = REPO / "config" / "security" / "kali-packages.yaml"

__all__ = ["check", "all_ok", "load_traps", "ToolStatus", "main"]


@dataclass
class ToolStatus:
    name: str
    binary: str
    present: bool
    identity_ok: bool
    path: str
    detail: str
    packages: dict
    trap: dict | None = None

    def install_hint(self, plat: str | None = None) -> str:
        plat = plat or detect_platform()
        pkg = (self.packages.get(plat)
               or self.packages.get("kali")
               or self.packages.get("debian")
               or self.packages.get("darwin"))
        if not pkg:
            return f"no install route declared for {self.name}"
        if pkg.startswith("go:"):
            return f"go install {pkg[3:]}"
        if plat == "darwin":
            return f"brew install {pkg}"
        return f"sudo apt install {pkg}"

    @property
    def ok(self) -> bool:
        return self.present and self.identity_ok


def detect_platform() -> str:
    system = platform.system().lower()
    if system == "darwin":
        return "darwin"
    try:
        release = Path("/etc/os-release").read_text(encoding="utf-8").lower()
    except OSError:
        return "debian"
    return "kali" if "kali" in release else "debian"


def load_traps(path=TRAPS_PATH) -> dict:
    p = Path(path)
    if not p.exists():
        return {}
    return yaml.safe_load(p.read_text(encoding="utf-8")) or {}


def check(registry: dict, only=None) -> list[ToolStatus]:
    """Assert identity for each tool. `only` narrows to named entries."""
    names = sorted(registry) if only is None else list(only)
    for name in names:
        if name not in registry:
            raise KeyError(f"unknown tool {name!r}")
    traps = load_traps()
    report = []
    for name in sorted(names):
        spec = registry[name]
        ok, detail = R.assert_identity(spec)
        present = "not on PATH" not in detail
        report.append(ToolStatus(
            name=name,
            binary=spec.get("binary", name),
            present=present,
            identity_ok=ok,
            path=detail if ok else "",
            detail=detail,
            packages=spec.get("packages") or {},
            trap=traps.get(name),
        ))
    return report


def all_ok(report) -> bool:
    return all(row.ok for row in report)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def main(argv=None) -> int:
    import lint as L

    argv = sys.argv[1:] if argv is None else list(argv)
    registry = L.load_registry()
    try:
        report = check(registry, only=argv or None)
    except KeyError as exc:
        print(f"doctor: {exc}", file=sys.stderr)
        return 2

    plat = detect_platform()
    width = max((len(r.name) for r in report), default=4)
    failures = 0
    for row in report:
        if row.ok:
            print(f"  ok       {row.name:<{width}}  {row.path}")
            continue
        failures += 1
        state = "MISSING " if not row.present else "IDENTITY"
        print(f"  {state} {row.name:<{width}}  {row.detail}")
        print(f"           {'':<{width}}  install: {row.install_hint(plat)}")
        if row.trap:
            print(f"           {'':<{width}}  trap: {row.trap.get('trap', '').strip()}")
            if row.trap.get("fix"):
                print(f"           {'':<{width}}  fix: {row.trap['fix']}")

    total = len(report)
    print(f"\n{total - failures}/{total} tool(s) verified on {plat}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
