#!/usr/bin/env python3
"""`claw sec run` — execute a flow against an engagement directory.

Everything a run needs is on disk afterwards: the scope that was in force, the
gate's decisions both ways, every artifact, and a hash-chained audit of how it
got there. Nothing about the run depends on a model being present.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import engagement as E
import lint as L
import phases as P
import registry as R

REPO = Path(__file__).resolve().parents[2]

def _rgb(key: str, fallback: str) -> str:
    """One theme engine: consume the palette's r;g;b triplet, fall back to
    refined-dark, and drop colour entirely when output is not a terminal."""
    if not sys.stdout.isatty() or os.environ.get("NO_COLOR"):
        return ""
    return f"\033[38;2;{os.environ.get('CLAW_RGB_' + key) or fallback}m"


C_OK = _rgb("GREEN", "63;185;80")
C_WARN = _rgb("AMBER", "227;179;65")
C_ERR = _rgb("RED", "255;123;114")
C_HEAD = _rgb("BLUE", "88;166;255")
C_MUTED = _rgb("MUTED", "139;148;158")
C_OFF = "\033[0m" if (sys.stdout.isatty() and not os.environ.get("NO_COLOR")) else ""


def _find_flow(name: str, flows_dir: Path) -> dict:
    for flow in L.load_flows(flows_dir):
        if flow.get("name") == name:
            return flow
    available = ", ".join(f.get("name", "?") for f in L.load_flows(flows_dir)) or "none"
    raise SystemExit(f"unknown flow {name!r}; available: {available}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="claw sec run", description=__doc__)
    ap.add_argument("flow")
    ap.add_argument("--domain", action="append", default=[],
                    help="seed domain (repeatable)")
    ap.add_argument("--engagement", default=None,
                    help="engagement directory (default: $CLAW_SEC_ENGAGEMENT, else ./engagements/<flow>)")
    ap.add_argument("--registry", default=str(REPO / "config" / "security" / "tools.yaml"))
    ap.add_argument("--flows-dir", default=str(REPO / "config" / "security" / "flows"))
    ap.add_argument("--scope", default=os.path.expanduser("~/.claude/scope.txt"))
    ap.add_argument("--dry-run", action="store_true",
                    help="build argv and enforce the gate, execute nothing")
    ap.add_argument("--redo", action="append", type=int, default=[],
                    help="force a phase to run again (repeatable)")
    ap.add_argument("--invasive", action="store_true",
                    help="opt this engagement in to active-invasive tools")
    ap.add_argument("--disclose", action="store_true",
                    help="permit passive sources that disclose the target")
    args = ap.parse_args(argv)

    registry = L.load_registry(args.registry)
    errors = L.lint_registry(registry)
    if errors:
        for err in errors:
            print(f"{C_ERR}lint: {err}{C_OFF}", file=sys.stderr)
        return 1

    flow = _find_flow(args.flow, Path(args.flows_dir))
    if not args.domain:
        raise SystemExit("at least one --domain is required to seed the flow")

    # Same resolution `claw sec scope add` uses, so a target added to the
    # overlay is in scope for the very next run with no flag repeated:
    # --engagement > CLAW_SEC_ENGAGEMENT > ./engagements/<flow>.
    root = Path(args.engagement).expanduser() if args.engagement else None
    if root is None:
        env_root = os.environ.get("CLAW_SEC_ENGAGEMENT")
        root = Path(env_root).expanduser() if env_root else (
            Path.cwd() / "engagements" / args.flow)
    ctx = E.build(root, run_id=f"{args.flow}-{os.getpid()}", scope_path=args.scope,
                  registry_path=args.registry, allow_invasive=args.invasive,
                  allow_disclosure=args.disclose, actor="operator")
    ctx.registry = registry
    sc = ctx.scope

    print(f"{C_HEAD}flow{C_OFF}       {args.flow}"
          f"{'  (dry run)' if args.dry_run else ''}")
    print(f"{C_HEAD}engagement{C_OFF} {root}")
    print(f"{C_HEAD}scope{C_OFF}      {args.scope}  policy={sc.policy}  "
          f"sha256={sc.sha256()[:12]}")
    print()

    report = P.run(flow, ctx, seed=args.domain, dry_run=args.dry_run, redo=args.redo)

    for phase in report.phases:
        mark = f"{C_MUTED}skip{C_OFF}" if phase.skipped else f"{C_OK}done{C_OFF}"
        print(f"  {mark}  {phase.id}  {phase.name}")
    if report.invocations:
        print()
        for call in report.invocations:
            colour = C_OK if call.status in ("ok", "empty") else C_WARN
            print(f"  {colour}{call.status:<14}{C_OFF} {call.tool:<12} "
                  f"phase {call.phase}  targets={len(call.targets)}  rows={call.count}")

    print()
    print(f"  authorized {report.authorized}   denied {report.denied}   "
          f"gate passes {report.gate_iterations}")
    if report.denied:
        print(f"  {C_WARN}denied hosts recorded in {root / 'gate' / 'denied.jsonl'}{C_OFF}")
    ok, detail = R.verify_audit(ctx)
    print(f"  audit chain {'ok' if ok else 'BROKEN'}: {detail}")

    if report.blocked:
        print(f"\n{C_ERR}{report.status}{C_OFF}", file=sys.stderr)
        return 2
    if report.halted:
        print(f"\n{C_WARN}{report.status}{C_OFF}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
