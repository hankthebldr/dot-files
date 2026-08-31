#!/usr/bin/env python3
"""Flow execution: phase DAG, the gate phase, feedback, resume (spec §6.4, §11).

A flow is a declared sequence of phases. Types flow between them, and the gate
is one of the phases — the only producer of `authorized_host`. Because a gated
tool may only consume types descended from that (§6.2, enforced by lint), the
runner cannot hand a gated tool an unauthorized target even if it wanted to.

Resumption is where authorization can quietly drift, so the comparison is
structural rather than byte-wise: an engagement overlay gaining lab hosts is
additive and every new host still traverses the gate, but a narrowed scope, a
new deny, or a changed policy invalidates prior work.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import registry as R
import scope as S

__all__ = ["run", "gate_hosts", "read_rows", "read_targets", "RunReport",
           "MAX_GATE_ITERATIONS"]

MAX_GATE_ITERATIONS = 5


# --------------------------------------------------------------------------
@dataclass
class Invocation:
    tool: str
    phase: int
    status: str
    targets: list = field(default_factory=list)
    argv: tuple = ()
    count: int = 0
    artifact: str | None = None


@dataclass
class PhaseResult:
    id: int
    name: str
    completed_at: str | None = None
    skipped: bool = False
    reason: str = ""


@dataclass
class RunReport:
    flow: str
    phases: list = field(default_factory=list)
    invocations: list = field(default_factory=list)
    authorized: int = 0
    denied: int = 0
    gate_iterations: int = 0
    halted: bool = False
    blocked: bool = False
    status: str = "ok"

    @property
    def ok(self) -> bool:
        return not (self.halted or self.blocked)


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --------------------------------------------------------------------------
# Artifact plumbing
# --------------------------------------------------------------------------
def read_rows(*paths):
    """Yield rows from one or more canonical artifacts."""
    for path in paths:
        p = Path(path)
        if not p.exists():
            continue
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if isinstance(row, dict):
                yield row


def read_targets(ctx: R.Engagement, artifact_type: str = "authorized_host"):
    """(host, addrs) pairs for a produced type. `authorized_host` reads the
    gate's own artifact and nothing else."""
    if artifact_type == "authorized_host":
        return R.targets_from_artifact(ctx.root / "gate" / "authorized.jsonl")[0]
    return R.targets_from_artifact(ctx.root / "inputs" / f"{artifact_type}.jsonl")[0]


def _materialize(ctx: R.Engagement, artifact_type: str, produced: dict) -> Path:
    """Merge every artifact that produced this type into one deduped input."""
    if artifact_type == "authorized_host":
        return ctx.root / "gate" / "authorized.jsonl"
    out = ctx.root / "inputs" / f"{artifact_type}.jsonl"
    out.parent.mkdir(parents=True, exist_ok=True)
    seen, lines = set(), []
    for path in produced.get(artifact_type, []):
        for row in read_rows(path):
            key = json.dumps(row, sort_keys=True)
            if key in seen:
                continue
            seen.add(key)
            lines.append(key)
    out.write_text("".join(l + "\n" for l in lines), encoding="utf-8")
    return out


# --------------------------------------------------------------------------
# The gate phase
# --------------------------------------------------------------------------
def gate_hosts(ctx: R.Engagement, targets) -> tuple[list, list]:
    """Authorize hosts and record the outcome. Append-only and idempotent: a
    host already decided is never re-decided, so re-entry from a mid-run
    discovery can never re-authorize something already denied."""
    gate_dir = ctx.root / "gate"
    gate_dir.mkdir(parents=True, exist_ok=True)
    allowed_path, denied_path = gate_dir / "authorized.jsonl", gate_dir / "denied.jsonl"

    decided = {row["host"] for row in read_rows(allowed_path, denied_path) if "host" in row}
    new_allowed, new_denied = [], []

    for host, addrs in targets:
        if host in decided:
            continue
        decided.add(host)
        verdict = S.authorize(host, addrs, ctx.scope, scope_class="active")
        record = {"host": host, "addrs": list(addrs), "policy": verdict.policy,
                  "reason": verdict.reason, "decided_at": _now()}
        if verdict.allowed:
            record["unverified_addr"] = verdict.unverified_addr
            new_allowed.append(record)
        else:
            record["proposal"] = verdict.proposal
            new_denied.append(record)
        R.audit_event(ctx, tool="gate", verdict="allow" if verdict.allowed else "deny",
                      status="ok" if verdict.allowed else "denied_scope",
                      target=host, target_count=1,
                      unverified_addr=verdict.unverified_addr, reason=verdict.reason)

    for path, rows in ((allowed_path, new_allowed), (denied_path, new_denied)):
        if rows:
            with path.open("a", encoding="utf-8") as fh:
                for row in rows:
                    fh.write(json.dumps(row, sort_keys=True) + "\n")
    return new_allowed, new_denied


def _hosts_from_rows(rows):
    """Hosts named by downstream output — cert SANs, redirect targets. These
    are discoveries, not authorizations: they go back through the gate."""
    out = {}
    for row in rows:
        host = row.get("host")
        if not host:
            continue
        addrs = row.get("addrs") or []
        if isinstance(addrs, str):
            addrs = [addrs]
        out.setdefault(host, list(addrs))
    return list(out.items())


# --------------------------------------------------------------------------
# Resume (§11)
# --------------------------------------------------------------------------
def _state_path(ctx: R.Engagement, phase_id: int) -> Path:
    return ctx.root / "state" / f"{phase_id}.done"


def _write_state(ctx: R.Engagement, phase_id: int, extra=None) -> None:
    path = _state_path(ctx, phase_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    state = {"completed_at": _now(), **ctx.scope.facts(), **(extra or {})}
    path.write_text(json.dumps(state, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def resume_verdict(state: dict, scope: S.Scope) -> tuple[bool, str]:
    """Structural comparison. Additive overlay growth resumes; anything that
    changes what was authorized does not."""
    now = scope.facts()
    if state.get("policy") != now["policy"]:
        return False, (f"resolve-policy changed {state.get('policy')!r} -> {now['policy']!r}; "
                       f"authorization strength differs. Re-run with --redo.")
    if state.get("global_sha256") != now["global_sha256"]:
        return False, ("the global scope file changed; the durable layer is not expected to "
                       "churn mid-engagement. Re-run with --redo.")
    for key in ("deny_names", "deny_addrs"):
        if set(state.get(key, [])) != set(now[key]):
            return False, (f"{key} changed; narrowing must invalidate prior work. "
                           f"Re-run with --redo.")
    for key in ("allow_names", "allow_addrs"):
        removed = set(state.get(key, [])) - set(now[key])
        if removed:
            return False, (f"{key} lost {sorted(removed)}; a host authorized earlier may no "
                           f"longer be. Re-run with --redo.")
    return True, "scope unchanged or additively extended"


# --------------------------------------------------------------------------
# The runner
# --------------------------------------------------------------------------
def run(flow: dict, ctx: R.Engagement, seed, dry_run: bool = False,
        redo=None) -> RunReport:
    """Execute a flow. Every phase is resumable, every invocation is audited,
    and the kill switch is checked at every phase boundary."""
    report = RunReport(flow=flow.get("name", "<unnamed>"))
    redo = set(redo or ())
    ctx.dry_run = dry_run
    produced: dict = {}

    ctx.root.mkdir(parents=True, exist_ok=True)
    snapshot = ctx.root / "scope.snapshot"
    if not snapshot.exists():
        snapshot.write_text(ctx.scope.to_text(), encoding="utf-8")

    for phase in flow.get("phases", []):
        pid, pname = phase["id"], phase.get("name", str(phase["id"]))
        ctx.phase = pid

        if R.is_halted(ctx):
            report.halted = True
            report.status = f"halted before phase {pid} ({pname}) — operator kill switch"
            return report

        state_path = _state_path(ctx, pid)
        if state_path.exists() and pid not in redo:
            state = json.loads(state_path.read_text(encoding="utf-8"))
            resumable, why = resume_verdict(state, ctx.scope)
            if not resumable:
                report.blocked = True
                report.status = f"phase {pid} ({pname}): {why}"
                return report
            report.phases.append(PhaseResult(pid, pname, state["completed_at"],
                                             skipped=True, reason=why))
            _reindex(ctx, phase, produced)
            continue

        if phase.get("gate"):
            report.gate_iterations += 1
            targets = R.targets_from_artifact(_materialize(ctx, "host", produced))[0]
            allowed, denied = gate_hosts(ctx, targets)
            report.authorized += len(allowed)
            report.denied += len(denied)
            produced.setdefault("authorized_host", []).append(
                ctx.root / "gate" / "authorized.jsonl")
        else:
            for tool in phase.get("tools") or []:
                report.invocations.append(_run_tool(ctx, tool, pid, produced, phase))

        if pid == 0:
            produced.setdefault("domain", []).append(_seed_artifact(ctx, seed))

        report.phases.append(PhaseResult(pid, pname, _now()))
        _write_state(ctx, pid, {"phase": pname})

        feeds_back = phase.get("feeds_back_to")
        if feeds_back is not None and not dry_run:
            _feedback(ctx, phase, produced, report, flow)

    report.status = (f"{len(report.phases)} phase(s), {report.authorized} authorized, "
                     f"{report.denied} denied")
    return report


def _seed_artifact(ctx: R.Engagement, seed) -> Path:
    path = ctx.root / "scans" / "seed-0000.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps({"domain": d, "tainted": False}) + "\n"
                            for d in seed), encoding="utf-8")
    return path


def _reindex(ctx: R.Engagement, phase: dict, produced: dict) -> None:
    """A skipped phase still contributed artifacts; re-register them so later
    phases resolve their inputs."""
    if phase.get("gate"):
        produced.setdefault("authorized_host", []).append(
            ctx.root / "gate" / "authorized.jsonl")
        return
    if phase["id"] == 0:
        seed = ctx.root / "scans" / "seed-0000.jsonl"
        if seed.exists():
            produced.setdefault("domain", []).append(seed)
    for tool in phase.get("tools") or []:
        for path in sorted((ctx.root / "scans").glob(f"{tool}-*.jsonl")):
            for artifact_type in ctx.registry[tool].get("emits") or []:
                produced.setdefault(artifact_type, []).append(path)


def _run_tool(ctx: R.Engagement, tool: str, pid: int, produced: dict,
              phase: dict) -> Invocation:
    spec = ctx.registry[tool]
    params, targets = {}, []
    for pname, pspec in (spec.get("params") or {}).items():
        if pspec.get("type") != "artifact":
            continue
        path = _materialize(ctx, pspec["of"], produced)
        params[pname] = str(path)
        targets = [h for h, _ in R.targets_from_artifact(path)[0]]

    result = R.invoke(tool, params, ctx)
    if result.artifact:
        for artifact_type in spec.get("emits") or []:
            produced.setdefault(artifact_type, []).append(result.artifact)
    return Invocation(tool=tool, phase=pid, status=result.status.value,
                      targets=targets, argv=result.argv, count=result.count,
                      artifact=str(result.artifact) if result.artifact else None)


def _feedback(ctx: R.Engagement, phase: dict, produced: dict,
              report: RunReport, flow: dict) -> None:
    """A host discovered downstream re-enters at the gate, never around it.
    Bounded, and converged when a pass authorizes nothing new."""
    gate_id = phase["feeds_back_to"]
    gate_phase = next((p for p in flow["phases"] if p["id"] == gate_id), None)
    if gate_phase is None:
        return
    for _ in range(MAX_GATE_ITERATIONS - 1):
        discovered = []
        for artifact_type in phase.get("emits") or []:
            discovered += _hosts_from_rows(read_rows(*produced.get(artifact_type, [])))
        if not discovered:
            return
        report.gate_iterations += 1
        allowed, denied = gate_hosts(ctx, discovered)
        report.authorized += len(allowed)
        report.denied += len(denied)
        if not allowed:
            return  # converged: nothing new was authorized
        for tool in phase.get("tools") or []:
            report.invocations.append(_run_tool(ctx, tool, phase["id"], produced, phase))
