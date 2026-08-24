#!/usr/bin/env python3
"""Static proof that the security registry cannot bypass the gate.

Three rules do the real work, and all three are checked before anything runs:

  Type rule (§6.2)   a gated tool may only consume types that descend from the
                     gate, so it is structurally unable to receive an
                     unauthorized target.
  Egress rule (§3.1) no destination may be sourced from model output.
  Argv rule          argv is a list of discrete elements with whole-element
                     slots — there is no string to interpolate and no shell.

`claw sec lint` is this module. Build fails, nothing runs.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
CONFIG_DIR = REPO / "config" / "security"
REGISTRY_PATH = CONFIG_DIR / "tools.yaml"
FLOWS_DIR = CONFIG_DIR / "flows"
SCHEMA_PATH = CONFIG_DIR / "registry.schema.json"

# §6.2 — the only types a gated tool may consume. Each is producible only
# downstream of `authorized_host`, which only the gate emits.
GATED_INPUT_TYPES = ("authorized_host", "endpoint", "url", "param", "wordlist")
GATED_CLASSES = ("active-light", "active", "active-invasive")
# §3.1 — parameter types that name somewhere bytes could be sent.
DESTINATION_TYPES = ("url", "hostname", "path")
TAINTING_CLASSES = ("passive", "active-light", "active", "active-invasive")

_SLOT_RE = re.compile(r"\{([A-Za-z0-9_]+)\}")
_SHELL_META = set(";|&$`<>\n\\\"'*?~()")


# --------------------------------------------------------------------------
# Loading
# --------------------------------------------------------------------------
def load_registry(path=REGISTRY_PATH) -> dict:
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{path}: registry must be a mapping of tool name to spec")
    return data


def load_flows(directory=FLOWS_DIR) -> list[dict]:
    d = Path(directory)
    return [yaml.safe_load(p.read_text(encoding="utf-8")) for p in sorted(d.glob("*.yaml"))]


def _schema():
    import json
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


# --------------------------------------------------------------------------
# Registry lint
# --------------------------------------------------------------------------
def lint_registry(registry: dict) -> list[str]:
    errors: list[str] = []
    errors += _lint_schema(registry)
    for name, spec in sorted(registry.items()):
        if not isinstance(spec, dict):
            errors.append(f"{name}: entry must be a mapping")
            continue
        errors += _lint_type_rule(name, spec)
        errors += _lint_egress_rule(name, spec)
        errors += _lint_argv(name, spec)
        errors += _lint_taint(name, spec)
    return errors


def _lint_schema(registry: dict) -> list[str]:
    try:
        import jsonschema
    except ImportError:  # pragma: no cover - environment guard
        return ["jsonschema is not installed; `claw sec lint` cannot validate the registry"]
    validator = jsonschema.Draft202012Validator(_schema())
    out = []
    for err in sorted(validator.iter_errors(registry), key=lambda e: list(e.absolute_path)):
        where = ".".join(str(p) for p in err.absolute_path) or "<registry>"
        out.append(f"{where}: {err.message}")
    return out


def _lint_type_rule(name: str, spec: dict) -> list[str]:
    out = []
    consumes = spec.get("consumes") or []
    if spec.get("scope_class") in GATED_CLASSES:
        for t in consumes:
            if t not in GATED_INPUT_TYPES:
                out.append(
                    f"{name}: type rule (§6.2) — gated tool consumes {t!r}, which is not "
                    f"downstream of the gate. Legal inputs: {', '.join(GATED_INPUT_TYPES)}"
                )
    for pname, p in (spec.get("params") or {}).items():
        if not isinstance(p, dict):
            continue
        if p.get("type") == "artifact":
            of = p.get("of")
            if of is None:
                out.append(f"{name}: param {pname!r} is an artifact but declares no 'of' type")
            elif of not in consumes:
                out.append(
                    f"{name}: param {pname!r} reads artifact type {of!r}, which the tool "
                    f"does not declare in consumes ({', '.join(consumes) or 'none'})"
                )
    return out


def _lint_egress_rule(name: str, spec: dict) -> list[str]:
    out = []
    for pname, p in (spec.get("params") or {}).items():
        if not isinstance(p, dict):
            continue
        if p.get("type") in DESTINATION_TYPES and p.get("source") == "model":
            out.append(
                f"{name}: egress rule (§3.1) — param {pname!r} is a destination "
                f"({p.get('type')}) sourced from the model. Destinations come from "
                f"config or a gated artifact, never from the conversation."
            )
    return out


def _lint_argv(name: str, spec: dict) -> list[str]:
    out = []
    argv = spec.get("argv") or []
    params = spec.get("params") or {}
    used = set()
    for element in argv:
        if not isinstance(element, str):
            out.append(f"{name}: argv elements must be strings, got {element!r}")
            continue
        slots = _SLOT_RE.findall(element)
        if slots and element != "{%s}" % slots[0]:
            out.append(
                f"{name}: argv element {element!r} embeds slot {slots[0]!r} inside a larger "
                f"string; a slot must be a whole argv element (no interpolation)"
            )
        for slot in slots:
            used.add(slot)
            if slot not in params:
                out.append(f"{name}: argv references undeclared slot {{{slot}}}")
        if _SHELL_META & set(element):
            out.append(
                f"{name}: argv element {element!r} contains a shell metacharacter; "
                f"argv is exec'd directly and never passes through a shell"
            )
    for pname in params:
        if pname not in used:
            out.append(f"{name}: param {pname!r} is declared but never used in argv")
    return out


def _lint_taint(name: str, spec: dict) -> list[str]:
    if spec.get("scope_class") not in TAINTING_CLASSES:
        return []
    if not spec.get("taint_fields"):
        return [
            f"{name}: declares no taint_fields, which asserts its output is trustworthy. "
            f"Output derived from target-controlled bytes must be marked (§3.2)."
        ]
    return []


# --------------------------------------------------------------------------
# Flow lint
# --------------------------------------------------------------------------
def lint_flow(flow: dict, registry: dict | None = None) -> list[str]:
    out: list[str] = []
    name = flow.get("name", "<unnamed>")
    phases = flow.get("phases") or []
    if not phases:
        return [f"{name}: flow declares no phases"]

    # ids: unique and ascending, so "ancestor" is well defined
    ids = [p.get("id") for p in phases]
    if ids != sorted(set(ids)) or len(set(ids)) != len(ids):
        out.append(f"{name}: phase id sequence must be unique and ascending, got {ids}")

    gates = [p for p in phases if p.get("gate")]
    if len(gates) != 1:
        out.append(f"{name}: exactly one phase must declare gate: true, found {len(gates)}")
    gate_id = gates[0].get("id") if gates else None

    produced: set[str] = set()
    for phase in phases:
        pid, pname = phase.get("id"), phase.get("name", "?")
        for t in phase.get("consumes") or []:
            if t not in produced:
                out.append(
                    f"{name}: phase {pid} ({pname}) consumes {t!r}, which no ancestor phase emits"
                )
        emits = phase.get("emits") or []
        if "authorized_host" in emits and not phase.get("gate"):
            out.append(
                f"{name}: phase {pid} ({pname}) emits 'authorized_host'; only the gate "
                f"phase may produce it (§6.2)"
            )
        fb = phase.get("feeds_back_to")
        if fb is not None and fb != gate_id:
            out.append(
                f"{name}: phase {pid} ({pname}) declares feeds_back_to: {fb}; a mid-run "
                f"discovery may only feed back to the gate (phase {gate_id})"
            )
        out += _lint_phase_tools(name, phase, registry)
        produced.update(emits)
    return out


def _lint_phase_tools(name: str, phase: dict, registry: dict | None) -> list[str]:
    out = []
    tools = phase.get("tools") or []
    consumes = set(phase.get("consumes") or [])
    emits = set(phase.get("emits") or [])
    for tname in tools:
        if registry is None:
            continue
        spec = registry.get(tname)
        if spec is None:
            out.append(f"{name}: phase {phase.get('id')} references unknown tool {tname!r}")
            continue
        missing_in = set(spec.get("consumes") or []) - consumes
        if missing_in:
            out.append(
                f"{name}: phase {phase.get('id')} runs {tname!r}, which consumes "
                f"{', '.join(sorted(missing_in))} not declared by the phase"
            )
        missing_out = set(spec.get("emits") or []) - emits
        if missing_out:
            out.append(
                f"{name}: phase {phase.get('id')} runs {tname!r}, which emits "
                f"{', '.join(sorted(missing_out))} not declared by the phase"
            )
    return out


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    registry = load_registry()
    errors = [("tools.yaml", e) for e in lint_registry(registry)]
    for flow in load_flows():
        errors += [(f"flows/{flow.get('name')}.yaml", e)
                   for e in lint_flow(flow, registry=registry)]
    if errors:
        for where, msg in errors:
            print(f"FAIL  {where}: {msg}", file=sys.stderr)
        print(f"\n{len(errors)} lint error(s)", file=sys.stderr)
        return 1
    n_tools, n_flows = len(registry), len(load_flows())
    print(f"OK    {n_tools} tool(s), {n_flows} flow(s) — type rule, egress rule, argv rule clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
