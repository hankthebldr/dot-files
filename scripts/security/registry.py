#!/usr/bin/env python3
"""The executor: gate, argv, exec, normalize, budget, audit (spec §4, §8-§10).

Every path into the security toolchain goes through `invoke()`. The MCP server
and the Ollama bridge are protocol translation and nothing else — they hold no
authorization logic, because a gate in the adapter is a gate with a way around
it. `pre_tool_use.py` guards the Bash path; an MCP `tools/call` never touches
Bash, so this is the layer that has to hold.

Order inside `invoke()` is deliberate and fail-closed:

    halt → tool identity → invasive/disclosure opt-in → GATE → rate → exec
         → normalize → budget → audit

The audit record is written by the executor on every outcome, denials
included. There is no parameter that suppresses it.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from urllib.parse import urlparse

import normalize as N
import scope as S

__all__ = [
    "Status", "Result", "Engagement", "ParamError",
    "invoke", "build_argv", "halt", "resume", "is_halted", "verify_audit",
    "audit_event", "targets_from_artifact", "materialize_input",
]

SAMPLE_ROWS = 5
DEFAULT_BUDGET_ROWS = 10_000
STDERR_TAIL_BYTES = 512
HALT_FILE = "HALT"
AUDIT_FILE = "audit.jsonl"

GATED_CLASSES = S.GATED_CLASSES


class Status(str, Enum):
    OK = "ok"
    EMPTY = "empty"
    DENIED_SCOPE = "denied_scope"
    DENIED_INVASIVE = "denied_invasive"
    DENIED_DISCLOSURE = "denied_disclosure"
    TOOL_MISSING = "tool_missing"
    TOOL_IDENTITY = "tool_identity"
    TIMEOUT = "timeout"
    RATE_LIMITED = "rate_limited"
    MALFORMED = "malformed"
    BUDGET = "budget"
    HALTED = "halted"


class ParamError(ValueError):
    """A parameter failed validation. Never reaches argv."""


@dataclass(frozen=True)
class Result:
    status: Status
    artifact: Path | None = None
    count: int = 0
    sample: list = field(default_factory=list)
    truncated: bool = False
    stderr_tail: str = ""
    duration_ms: int = 0
    reason: str = ""
    proposal: str | None = None
    retry_after_ms: int | None = None
    schema: list = field(default_factory=list)
    argv: tuple = ()

    def to_dict(self) -> dict:
        """The JSON shape the model sees. Never bulk data — a reference and a
        handful of sanitized sample rows (§7)."""
        out = {
            "status": self.status.value,
            "count": self.count,
            "truncated": self.truncated,
            "schema": list(self.schema),
        }
        if self.artifact:
            out["artifact"] = str(self.artifact)
        if self.sample:
            out["sample"] = self.sample
        for key in ("reason", "proposal", "retry_after_ms"):
            value = getattr(self, key)
            if value:
                out[key] = value
        if self.stderr_tail:
            out["stderr_tail"] = self.stderr_tail
        return out


@dataclass
class Engagement:
    root: Path
    run_id: str
    scope: S.Scope
    registry: dict
    allow_invasive: bool = False
    allow_disclosure: bool = False
    dry_run: bool = False
    budget_rows: int = DEFAULT_BUDGET_ROWS
    phase: int | None = None
    actor: str = "model"
    _buckets: dict = field(default_factory=dict, repr=False)

    @property
    def audit_path(self) -> Path:
        return Path(self.root) / AUDIT_FILE

    @property
    def halt_path(self) -> Path:
        return Path(self.root) / HALT_FILE

    @property
    def scans_dir(self) -> Path:
        return Path(self.root) / "scans"

    def gate_record(self) -> dict:
        """host -> addresses, as established by the gate.

        Types downstream of the gate (endpoint, url, param) name a host but
        carry no addresses — resolution happened upstream. Re-authorization
        therefore reads the addresses the gate itself recorded. A host the gate
        never saw resolves to nothing and, under `enforce`, is denied: a
        fabricated endpoint row cannot smuggle a target past this.
        """
        path = Path(self.root) / "gate" / "authorized.jsonl"
        if not path.exists():
            return {}
        out = {}
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if isinstance(row, dict) and row.get("host"):
                out[str(row["host"])] = [str(a) for a in (row.get("addrs") or [])]
        return out


# --------------------------------------------------------------------------
# Kill switch (§10) — checked before every invocation, model cannot clear it
# --------------------------------------------------------------------------
def halt(ctx: Engagement, reason: str = "operator kill switch") -> Path:
    ctx.halt_path.parent.mkdir(parents=True, exist_ok=True)
    ctx.halt_path.write_text(
        json.dumps({"reason": reason, "at": _now()}) + "\n", encoding="utf-8")
    return ctx.halt_path


def resume(ctx: Engagement) -> None:
    ctx.halt_path.unlink(missing_ok=True)


def is_halted(ctx: Engagement) -> bool:
    return ctx.halt_path.exists()


# --------------------------------------------------------------------------
# Parameters and argv
# --------------------------------------------------------------------------
def build_argv(tool: str, spec: dict, params: dict) -> list[str]:
    """Validate parameters and fill the registry's argv template.

    argv is a list of discrete elements and slots are whole elements, so there
    is no string for a value to escape out of, and nothing is passed to a shell.
    """
    declared = spec.get("params") or {}
    for name in params:
        if name not in declared:
            raise ParamError(f"{tool}: undeclared parameter {name!r}")

    values = {}
    for name, pspec in declared.items():
        if name in params and params[name] is not None:
            values[name] = _validate(tool, name, pspec, params[name])
        elif "default" in pspec:
            values[name] = _validate(tool, name, pspec, pspec["default"])
        else:
            raise ParamError(f"{tool}: required parameter {name!r} was not supplied")

    argv = [spec["binary"]]
    for element in spec.get("argv") or []:
        if element.startswith("{") and element.endswith("}"):
            argv.append(str(values[element[1:-1]]))
        else:
            argv.append(element)
    return argv


def _validate(tool: str, name: str, pspec: dict, value):
    ptype = pspec.get("type")
    if ptype in ("integer", "number"):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ParamError(f"{tool}: {name!r} must be a number, got {value!r}")
        if ptype == "integer" and int(value) != value:
            raise ParamError(f"{tool}: {name!r} must be an integer, got {value!r}")
        if "min" in pspec and value < pspec["min"]:
            raise ParamError(f"{tool}: {name!r}={value} is below the minimum {pspec['min']}")
        if "max" in pspec and value > pspec["max"]:
            raise ParamError(f"{tool}: {name!r}={value} is above the maximum {pspec['max']}")
        return int(value) if ptype == "integer" else value
    if ptype == "enum":
        if value not in (pspec.get("values") or []):
            raise ParamError(
                f"{tool}: {name!r}={value!r} is not one of {pspec.get('values')}")
        return value
    if ptype == "boolean":
        if not isinstance(value, bool):
            raise ParamError(f"{tool}: {name!r} must be a boolean")
        return value
    if ptype in ("artifact", "path"):
        text = str(value)
        if "\x00" in text:
            raise ParamError(f"{tool}: {name!r} contains a null byte")
        return text
    if ptype in ("string", "url", "hostname"):
        text = str(value)
        if any(c in text for c in "\x00\n\r"):
            raise ParamError(f"{tool}: {name!r} contains a control character")
        return text
    raise ParamError(f"{tool}: parameter {name!r} has unknown type {ptype!r}")


# --------------------------------------------------------------------------
# Targets — read from the input artifact, never from the caller
# --------------------------------------------------------------------------
def targets_from_artifact(path) -> list[tuple[str, list[str]]]:
    """Extract (host, addrs) pairs from a canonical artifact.

    The caller supplies an artifact reference, not a target. This is what makes
    the type rule (§6.2) load-bearing at runtime rather than only at lint time.
    """
    out = []
    p = Path(path)
    if not p.exists():
        return out
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if not isinstance(row, dict):
            continue
        host = row.get("host") or row.get("hostname") or row.get("address") or row.get("ip")
        if not host and row.get("url"):
            host = urlparse(str(row["url"])).hostname
        if not host:
            continue
        addrs = row.get("addrs") or row.get("a") or []
        if isinstance(addrs, str):
            addrs = [addrs]
        for key in ("ip", "address", "aaaa"):
            extra = row.get(key)
            if isinstance(extra, str):
                addrs = list(addrs) + [extra]
            elif isinstance(extra, list):
                addrs = list(addrs) + extra
        out.append((str(host), [str(a) for a in addrs]))
    return out


# --------------------------------------------------------------------------
# Tool-native input
# --------------------------------------------------------------------------
# Canonical artifacts are JSONL. Real scanners take a plain list on -list, and
# a scanner handed JSON reads each line as a hostname and finds nothing — one
# more way to produce zero rows that look like a clean target.
FIELD_FOR_TYPE = {
    "domain": "domain",
    "hostname": "host",
    "host": "host",
    "authorized_host": "host",
    "endpoint": "url",
    "url": "url",
    "param": "name",
    "cert": "host",
    "finding": "matched-at",
    "secret": "value",
    "wordlist": "path",
}
_FIELD_FALLBACKS = ("url", "host", "hostname", "domain", "value", "matched-at")


def materialize_input(ctx: Engagement, tool: str, param: str,
                      artifact, artifact_type: str) -> Path:
    """Write the plain, deduplicated list a scanner expects, inside the
    engagement so it is as auditable as everything else."""
    field = FIELD_FOR_TYPE.get(artifact_type)
    seen, values = set(), []
    for line in Path(artifact).read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if not isinstance(row, dict):
            continue
        value = row.get(field) if field else None
        if value is None:
            value = next((row[k] for k in _FIELD_FALLBACKS if row.get(k)), None)
        if value is None or value in seen:
            continue
        seen.add(value)
        values.append(str(value))
    out = Path(ctx.root) / "inputs" / f"{tool}-{param}.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("".join(v + "\n" for v in values), encoding="utf-8")
    return out


def _prepare_inputs(ctx: Engagement, tool: str, spec: dict, params: dict) -> dict:
    if spec.get("input_format", "lines") != "lines":
        return params
    prepared = dict(params)
    for pname, pspec in (spec.get("params") or {}).items():
        if pspec.get("type") != "artifact" or pname not in prepared:
            continue
        artifact = Path(prepared[pname])
        if not artifact.exists():
            continue
        prepared[pname] = str(materialize_input(ctx, tool, pname, artifact,
                                                pspec.get("of", "")))
    return prepared


# --------------------------------------------------------------------------
# Rate limiting (§10) — buckets key on resolved address, not hostname
# --------------------------------------------------------------------------
def _take_tokens(ctx: Engagement, addrs, rps: float) -> int | None:
    """Return retry_after_ms if any bucket is exhausted, else None (consumed)."""
    now = time.monotonic()
    keys = sorted(set(addrs)) or ["<no-address>"]
    waits = []
    for key in keys:
        tokens, last = ctx._buckets.get(key, (float(rps), now))
        tokens = min(float(rps), tokens + (now - last) * rps)
        if tokens < 1.0:
            waits.append(int(((1.0 - tokens) / rps) * 1000) + 1)
        ctx._buckets[key] = (tokens, now)
    if waits:
        return max(waits)
    for key in keys:
        tokens, last = ctx._buckets[key]
        ctx._buckets[key] = (tokens - 1.0, last)
    return None


# --------------------------------------------------------------------------
# Identity assertion (§13) — presence is not identity
# --------------------------------------------------------------------------
_IDENTITY_CACHE: dict = {}


def assert_identity(spec: dict) -> tuple[bool, str]:
    binary = spec["binary"]
    path = shutil.which(binary)
    if path is None:
        return False, f"binary {binary!r} is not on PATH"
    verify = list(spec.get("verify") or [binary, "-version"])
    key = (path, tuple(verify), spec.get("expect", ""))
    if key in _IDENTITY_CACHE:
        return _IDENTITY_CACHE[key]
    try:
        proc = subprocess.run(verify, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as exc:
        verdict = (False, f"{binary!r} at {path} failed its version check: {exc}")
    else:
        blob = (proc.stdout or "") + (proc.stderr or "")
        expect = spec.get("expect", "")
        if expect.lower() in blob.lower():
            verdict = (True, path)
        else:
            verdict = (
                False,
                f"{binary!r} at {path} does not identify as {expect!r} — "
                f"wrong binary on PATH; got: {blob.strip().splitlines()[:1]}",
            )
    _IDENTITY_CACHE[key] = verdict
    return verdict


# --------------------------------------------------------------------------
# Audit (§8) — hash-chained, written here and nowhere else
# --------------------------------------------------------------------------
def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _sha256(data) -> str:
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def _file_sha256(path) -> str | None:
    p = Path(path)
    if not p.exists():
        return None
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _record_hash(record: dict, prev_hash: str) -> str:
    body = {k: v for k, v in record.items() if k != "record_hash"}
    return _sha256(prev_hash + json.dumps(body, sort_keys=True, ensure_ascii=False))


def _audit_tail(ctx: Engagement) -> tuple[int, str]:
    path = ctx.audit_path
    if not path.exists():
        return 0, "genesis"
    seq, prev = 0, "genesis"
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        rec = json.loads(line)
        seq, prev = rec.get("seq", seq), rec.get("record_hash", prev)
    return seq, prev


def _audit(ctx: Engagement, record: dict) -> dict:
    seq, prev = _audit_tail(ctx)
    record = dict(record)
    record["seq"] = seq + 1
    record["prev_hash"] = prev
    record["record_hash"] = _record_hash(record, prev)
    ctx.audit_path.parent.mkdir(parents=True, exist_ok=True)
    with ctx.audit_path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, sort_keys=True, ensure_ascii=False) + "\n")
    return record


def audit_event(ctx: Engagement, **fields) -> dict:
    """Append a non-tool record — a gate decision, a phase boundary — to the
    same chain. Callers cannot set seq, prev_hash or record_hash."""
    record = {"ts": _now(), "run_id": ctx.run_id, "phase": ctx.phase,
              "actor": ctx.actor, "scope_sha256": ctx.scope.sha256(),
              "policy": ctx.scope.policy}
    record.update({k: v for k, v in fields.items()
                   if k not in ("seq", "prev_hash", "record_hash")})
    return _audit(ctx, record)


def verify_audit(ctx: Engagement) -> tuple[bool, str]:
    """Walk the chain. Appending is normal; editing history breaks it."""
    path = ctx.audit_path
    if not path.exists():
        return True, "no audit log"
    prev, expect_seq = "genesis", 1
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        rec = json.loads(line)
        if rec.get("seq") != expect_seq:
            return False, f"record {rec.get('seq')}: expected seq {expect_seq}"
        if rec.get("prev_hash") != prev:
            return False, f"record {rec.get('seq')}: prev_hash does not match record {expect_seq - 1}"
        if _record_hash(rec, prev) != rec.get("record_hash"):
            return False, f"record {rec.get('seq')}: content does not match its hash"
        prev, expect_seq = rec["record_hash"], expect_seq + 1
    return True, f"{expect_seq - 1} record(s) verified"


# --------------------------------------------------------------------------
# The one entry point
# --------------------------------------------------------------------------
def invoke(tool: str, params: dict, ctx: Engagement) -> Result:
    started = time.monotonic()
    spec = ctx.registry[tool]          # KeyError: unknown tool is a caller bug
    params = dict(params or {})
    scope_class = spec.get("scope_class", "active")
    policy = ctx.scope.policy

    def finish(result: Result, verdict: str, extra=None) -> Result:
        record = {
            "ts": _now(),
            "run_id": ctx.run_id,
            "phase": ctx.phase,
            "actor": ctx.actor,
            "tool": tool,
            "scope_class": scope_class,
            "params": {k: v for k, v in params.items()},
            "verdict": verdict,
            "policy": policy,
            "unverified_addr": bool((extra or {}).get("unverified_addr")),
            "scope_sha256": ctx.scope.sha256(),
            "argv_sha256": _sha256(json.dumps(list(result.argv))) if result.argv else None,
            "target_count": (extra or {}).get("target_count", 0),
            "status": result.status.value,
            "exit_code": (extra or {}).get("exit_code"),
            "duration_ms": result.duration_ms,
            "artifact": str(result.artifact) if result.artifact else None,
            "artifact_sha256": _file_sha256(result.artifact) if result.artifact else None,
            "reason": result.reason or None,
            "dry_run": ctx.dry_run,
        }
        _audit(ctx, record)
        return result

    def elapsed() -> int:
        return int((time.monotonic() - started) * 1000)

    # 1. kill switch, before anything else
    if is_halted(ctx):
        return finish(Result(Status.HALTED, reason="operator kill switch is engaged",
                             duration_ms=elapsed()), "halt")

    # 2. identity — presence is not identity (§13)
    ok, detail = assert_identity(spec)
    if not ok:
        status = Status.TOOL_MISSING if "not on PATH" in detail else Status.TOOL_IDENTITY
        return finish(Result(status, reason=detail, duration_ms=elapsed()), "error")

    # 3. engagement opt-ins
    if scope_class == "active-invasive" and not ctx.allow_invasive:
        return finish(Result(Status.DENIED_INVASIVE, duration_ms=elapsed(),
                             reason=f"{tool} is active-invasive and this engagement has not "
                                    f"opted in"), "deny")
    if spec.get("discloses_target") and not ctx.allow_disclosure:
        return finish(Result(Status.DENIED_DISCLOSURE, duration_ms=elapsed(),
                             reason=f"{tool} discloses the target to a third party and "
                                    f"disclosure is not permitted this engagement"), "deny")

    # 4. THE GATE — every target, re-authorized here regardless of adapter
    targets, unverified = [], False
    if scope_class in GATED_CLASSES:
        for pname, pspec in (spec.get("params") or {}).items():
            if pspec.get("type") == "artifact" and pname in params:
                targets += targets_from_artifact(params[pname])
        gate = ctx.gate_record()
        targets = [(host, addrs or gate.get(host, [])) for host, addrs in targets]
        for host, addrs in targets:
            verdict = S.authorize(host, addrs, ctx.scope, scope_class=scope_class)
            if not verdict.allowed:
                return finish(
                    Result(Status.DENIED_SCOPE, reason=f"{host}: {verdict.reason}",
                           proposal=verdict.proposal, duration_ms=elapsed()),
                    "deny", {"target_count": len(targets)})
            unverified = unverified or verdict.unverified_addr

    # 5. argv — over a tool-native input, not the canonical artifact
    try:
        argv = build_argv(tool, spec, _prepare_inputs(ctx, tool, spec, params))
    except ParamError as exc:
        return finish(Result(Status.MALFORMED, reason=str(exc), duration_ms=elapsed()),
                      "error", {"target_count": len(targets)})

    extra = {"target_count": len(targets), "unverified_addr": unverified}

    if ctx.dry_run:
        return finish(Result(Status.OK, argv=tuple(argv), duration_ms=elapsed(),
                             reason="dry run: argv built, nothing executed"), "allow", extra)

    # 6. rate limit, on resolved addresses
    rate = spec.get("rate") or {}
    rps = float(rate.get("per_target_rps", 0) or 0)
    if rps > 0:
        addrs = [a for _, addrs in targets for a in addrs]
        retry_ms = _take_tokens(ctx, addrs, rps)
        if retry_ms is not None:
            return finish(Result(Status.RATE_LIMITED, retry_after_ms=retry_ms,
                                 argv=tuple(argv), duration_ms=elapsed(),
                                 reason=f"per-target bucket exhausted for {tool}"),
                          "throttle", extra)

    # 7. exec — argv list, no shell, hard timeout
    timeout = int(spec.get("timeout", 600))
    stdout, stderr, exit_code, timed_out = _run(argv, timeout)
    extra["exit_code"] = exit_code

    # 8. normalize
    try:
        norm = N.normalize(stdout, parser=spec.get("parser", "jsonl"),
                           taint_fields=spec.get("taint_fields") or [])
    except N.NormalizeError as exc:
        raw = _write_artifact(ctx, tool, stdout, suffix="raw")
        return finish(Result(Status.MALFORMED, artifact=raw, reason=str(exc),
                             stderr_tail=_tail(stderr), duration_ms=elapsed()),
                      "allow", extra)

    stderr_tail = _tail(stderr)
    if not norm.rows:
        if exit_code != 0 or timed_out:
            status = Status.TIMEOUT if timed_out else Status.MALFORMED
            reason = (f"{tool} timed out after {timeout}s"
                      if timed_out else f"{tool} exited {exit_code} with no parseable rows")
            return finish(Result(status, reason=reason, stderr_tail=stderr_tail,
                                 argv=tuple(argv), duration_ms=elapsed()), "allow", extra)
        return finish(Result(Status.EMPTY, count=0, schema=norm.schema,
                             stderr_tail=stderr_tail, argv=tuple(argv),
                             duration_ms=elapsed(),
                             reason=f"{tool} ran cleanly and produced zero rows"),
                      "allow", extra)

    # 9. budget — the artifact is the result; the caller gets a reference (§7)
    artifact = _write_artifact(ctx, tool, norm.to_jsonl())
    sample = norm.rows[:SAMPLE_ROWS]
    status = Status.OK
    reason = ""
    if timed_out:
        status, reason = Status.TIMEOUT, f"{tool} timed out after {timeout}s; partial rows kept"
    elif norm.count > ctx.budget_rows:
        status = Status.BUDGET
        reason = (f"{norm.count} rows exceeds the {ctx.budget_rows}-row inline budget; "
                  f"reason over it with query/stats")
    return finish(Result(status, artifact=artifact, count=norm.count, sample=sample,
                         truncated=norm.count > len(sample), schema=norm.schema,
                         stderr_tail=stderr_tail, argv=tuple(argv),
                         duration_ms=elapsed(), reason=reason), "allow", extra)


def _run(argv, timeout):
    """Execute argv directly. No shell, ever — see the argv rule in lint.py."""
    env = dict(os.environ)
    env["NO_COLOR"] = "1"
    try:
        proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, env=env)
    except FileNotFoundError as exc:
        return "", str(exc), 127, False
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
        return stdout, stderr, proc.returncode, False
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        return stdout or "", stderr or "", proc.returncode, True


def _write_artifact(ctx: Engagement, tool: str, body: str, suffix: str = "jsonl") -> Path:
    ctx.scans_dir.mkdir(parents=True, exist_ok=True)
    seq, _ = _audit_tail(ctx)
    path = ctx.scans_dir / f"{tool}-{seq + 1:04d}.{suffix}"
    path.write_text(body, encoding="utf-8")
    return path


def _tail(text: str) -> str:
    if not text:
        return ""
    raw = text.encode("utf-8")[-STDERR_TAIL_BYTES:]
    return N.sanitize(raw.decode("utf-8", errors="ignore"), max_bytes=STDERR_TAIL_BYTES)
