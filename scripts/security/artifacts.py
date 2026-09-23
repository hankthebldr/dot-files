#!/usr/bin/env python3
"""Artifact access: the only way a model reads scan data (spec §7).

Tools return references, not payloads. A crawl yields 10k+ rows; a template
scan across a few hundred hosts yields megabytes. Neither fits in context, and
pasting either into the conversation is the widest available injection surface.

Two primitives, and no third:

    query(artifact, where, fields, limit)   constrained row selection
    stats(artifact, group_by, metric)       aggregate reasoning over the whole
                                            file without reading a row of it

`where` is a list of typed predicates — {"field", "op", "value"} — not an
expression string. There is no evaluator here to inject into, and a string
passed where a predicate list belongs is a typed error rather than something
that gets `eval`'d.
"""
from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path

__all__ = ["query", "stats", "index", "QueryError", "ArtifactNotFound", "MAX_LIMIT"]

MAX_LIMIT = 200
DEFAULT_LIMIT = 50

_OPS = ("eq", "ne", "lt", "lte", "gt", "gte", "contains", "startswith",
        "endswith", "in", "exists")


class QueryError(ValueError):
    """A malformed query. Never degrades into a permissive one."""


class ArtifactNotFound(FileNotFoundError):
    pass


# --------------------------------------------------------------------------
def _read(path) -> list[dict]:
    p = Path(path)
    if not p.exists():
        raise ArtifactNotFound(f"no artifact at {p}")
    rows = []
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def _check_predicates(where):
    if where is None:
        return []
    if not isinstance(where, list):
        raise QueryError(
            "`where` must be a list of {field, op, value} predicates; "
            "expression strings are not supported and are not evaluated"
        )
    for pred in where:
        if not isinstance(pred, dict):
            raise QueryError(f"predicate must be an object, got {type(pred).__name__}")
        if not pred.get("field"):
            raise QueryError(f"predicate is missing 'field': {pred!r}")
        op = pred.get("op", "eq")
        if op not in _OPS:
            raise QueryError(f"unknown operator {op!r}; expected one of {', '.join(_OPS)}")
        if op != "exists" and "value" not in pred:
            raise QueryError(f"predicate {pred['field']!r} with op {op!r} needs a value")
    return where


def _matches(row: dict, pred: dict) -> bool:
    field, op = pred["field"], pred.get("op", "eq")
    if op == "exists":
        return field in row
    if field not in row:
        return False
    actual, expected = row[field], pred.get("value")
    try:
        if op == "eq":
            return actual == expected
        if op == "ne":
            return actual != expected
        if op == "lt":
            return actual < expected
        if op == "lte":
            return actual <= expected
        if op == "gt":
            return actual > expected
        if op == "gte":
            return actual >= expected
        if op == "in":
            return actual in (expected or [])
        text = actual if isinstance(actual, str) else json.dumps(actual)
        if op == "contains":
            return str(expected) in text
        if op == "startswith":
            return text.startswith(str(expected))
        if op == "endswith":
            return text.endswith(str(expected))
    except TypeError:
        return False
    return False


# --------------------------------------------------------------------------
def query(artifact, where=None, fields=None, limit: int = DEFAULT_LIMIT,
          provenance: bool = False) -> dict:
    """Select rows by typed predicate. Returns at most MAX_LIMIT rows, with the
    full match count so the caller knows what it did not see."""
    predicates = _check_predicates(where)
    limit = max(1, min(int(limit), MAX_LIMIT))
    rows = _read(artifact)

    matched = []
    for idx, row in enumerate(rows):
        if all(_matches(row, p) for p in predicates):
            matched.append((idx, row))

    page = []
    for idx, row in matched[:limit]:
        out = {k: v for k, v in row.items() if not fields or k in fields}
        if provenance:
            out["provenance"] = {"artifact": str(artifact), "row": idx}
        page.append(out)

    return {
        "artifact": str(artifact),
        "count": len(matched),
        "rows": page,
        "truncated": len(matched) > len(page),
        "limit": limit,
    }


def stats(artifact, group_by: str, metric: str = "count") -> dict:
    """Aggregate over every row without returning any. This is what lets a
    model reason about 11k URLs — it asks for counts by status and technology,
    not for the rows."""
    rows = _read(artifact)
    if metric == "count":
        distinct_field = None
    elif metric.startswith("count_distinct:"):
        distinct_field = metric.split(":", 1)[1]
        if not distinct_field:
            raise QueryError("count_distinct needs a field: count_distinct:<field>")
    else:
        raise QueryError(f"unknown metric {metric!r}; expected count or count_distinct:<field>")

    counts = Counter()
    distinct = defaultdict(set)
    for row in rows:
        if group_by not in row:
            continue
        value = row[group_by]
        keys = value if isinstance(value, list) else [value]
        for key in keys:
            if isinstance(key, (dict, list)):
                key = json.dumps(key, sort_keys=True)
            counts[key] += 1
            if distinct_field and distinct_field in row:
                distinct[key].add(json.dumps(row[distinct_field], sort_keys=True))

    groups = []
    for key, count in sorted(counts.items(), key=lambda kv: (-kv[1], str(kv[0]))):
        entry = {group_by: key, "count": count}
        if distinct_field:
            entry[f"count_distinct_{distinct_field}"] = len(distinct[key])
        groups.append(entry)

    return {
        "artifact": str(artifact),
        "group_by": group_by,
        "metric": metric,
        "total": len(rows),
        "groups": groups,
    }


def index(engagement_root) -> list[dict]:
    """What this engagement has collected: one entry per artifact, with row
    count and schema, so the model can pick a file to query without opening one."""
    root = Path(engagement_root)
    scans = root / "scans" if (root / "scans").exists() else root
    if not scans.exists():
        return []
    entries = []
    for path in sorted(scans.glob("*.jsonl")):
        rows = _read(path)
        schema: dict = {}
        tainted = False
        for row in rows:
            for key in row:
                schema.setdefault(key, None)
            tainted = tainted or bool(row.get("tainted"))
        entries.append({
            "artifact": str(path),
            "name": path.name,
            "count": len(rows),
            "schema": list(schema),
            "tainted": tainted,
            "bytes": path.stat().st_size,
        })
    return entries
