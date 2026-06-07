#!/usr/bin/env python3
"""Obsidian vault capture — deterministic _wip note writer.

Reconstructed from the `obsidian-vault-capture` SKILL.md spec, which ships
instruction-only (its scripts/ payload was never bundled into the materialized
skill). Drops a uniform, machine-readable capture note into the vault `_wip`
inbox so the vault pipeline (frontmatter coverage, MOCs, QuickAdd) can ingest it.

Body is read from STDIN; metadata via flags. Prints the final note path to
stdout on success (exit 0). On failure, prints a reason to stderr and exits:
    2 = bad arguments
    3 = filesystem / write error

Example:
    printf '## Findings\n- ...\n' | python3 capture_note.py \
        --title "XSIAM Ingest Findings" --tags "research, cortex, xsiam" \
        --source "cowork: one-cortex"
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from datetime import date as _date
from pathlib import Path

DEFAULT_WIP = "/Users/henry/hr-vault-main-pa/_wip"
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def slugify(text: str, max_len: int = 60) -> str:
    """lowercase, non-alphanumerics -> '-', collapse repeats, trim, length-cap."""
    s = re.sub(r"[^a-z0-9]+", "-", text.strip().lower())
    s = re.sub(r"-{2,}", "-", s).strip("-")
    if len(s) > max_len:
        s = s[:max_len].rstrip("-")
    return s or "note"


def parse_tags(raw: str) -> list:
    """Split on commas/whitespace, strip a leading '#', dedupe preserving order."""
    if not raw:
        return []
    out = []
    for p in re.split(r"[,\s]+", raw.strip()):
        t = p.lstrip("#").strip()
        if t and t not in out:
            out.append(t)
    return out


def _yaml_q(value) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def parse_extra(items) -> list:
    pairs = []
    for it in items or []:
        if "=" not in it:
            sys.stderr.write("error: --extra expects KEY=VALUE, got %r\n" % it)
            sys.exit(2)
        k, v = it.split("=", 1)
        if not k.strip():
            sys.stderr.write("error: --extra has empty key in %r\n" % it)
            sys.exit(2)
        pairs.append((k.strip(), v.strip()))
    return pairs


def build_note(title, date_str, tags, source, status, extra, body) -> str:
    fm = ["---", "title: %s" % _yaml_q(title), "date: %s" % date_str, "tags:"]
    fm += ["  - %s" % t for t in tags] if tags else ["  []"]
    fm += ["source: %s" % _yaml_q(source), "status: %s" % status]
    fm += ["%s: %s" % (k, _yaml_q(v)) for k, v in extra]
    fm.append("---")
    return "\n".join(fm) + "\n\n# %s\n\n%s\n" % (title, body.rstrip("\n"))


def unique_path(wip: Path, date_str: str, slug: str) -> Path:
    base = "%s-%s" % (date_str, slug)
    cand = wip / ("%s.md" % base)
    n = 2
    while cand.exists():
        cand = wip / ("%s-%d.md" % (base, n))
        n += 1
    return cand


def atomic_write(path: Path, content: str) -> None:
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".cn-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Write a capture note into the Obsidian vault _wip inbox."
    )
    ap.add_argument("--title", required=True, help="human-readable title; drives the slug")
    ap.add_argument("--tags", default="", help="comma/space separated; leading '#' stripped")
    ap.add_argument("--source", default="cowork", help="origin context")
    ap.add_argument("--status", default="wip", help="frontmatter status")
    ap.add_argument("--slug", default=None, help="override the auto slug")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD; defaults to today")
    ap.add_argument("--vault-wip", default=os.environ.get("VAULT_WIP", DEFAULT_WIP),
                    help="target _wip dir (default: %s)" % DEFAULT_WIP)
    ap.add_argument("--extra", action="append", default=[], metavar="KEY=VALUE",
                    help="extra frontmatter key (repeatable)")
    ap.add_argument("--print-only", action="store_true", help="compose + print; do not write")
    args = ap.parse_args(argv)

    if not args.title.strip():
        sys.stderr.write("error: --title must be non-empty\n")
        return 2

    date_str = args.date or _date.today().isoformat()
    if not _DATE_RE.match(date_str):
        sys.stderr.write("error: --date must be YYYY-MM-DD, got %r\n" % date_str)
        return 2

    tags = parse_tags(args.tags)
    extra = parse_extra(args.extra)
    slug = (args.slug or slugify(args.title)).strip("-") or "note"

    body = "" if sys.stdin.isatty() else sys.stdin.read()
    note = build_note(args.title, date_str, tags, args.source, args.status, extra, body)

    if args.print_only:
        sys.stdout.write(note)
        return 0

    wip = Path(args.vault_wip).expanduser()
    try:
        wip.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        sys.stderr.write("error: cannot prepare vault dir %s: %s\n" % (wip, e))
        return 3

    path = unique_path(wip, date_str, slug)
    try:
        atomic_write(path, note)
    except OSError as e:
        sys.stderr.write("error: write failed for %s: %s\n" % (path, e))
        return 3

    print(str(path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
