#!/usr/bin/env python3
"""
capture_note.py — write a structured Obsidian capture note into the vault.

Deterministic note creation for the obsidian-vault-capture skill. This is the
Claude Code (direct-filesystem) mirror of the vault-os `vault_create_note` MCP
tool: it emits the SAME frontmatter schema, the SAME note_type vocabulary, and
honors the SAME write decision (assert a seam via --dest, or omit it to stage in
_wip/ for the router). A note written by this script and a note written by the
MCP are byte-compatible for the linter and the wip-router.

Frontmatter key order follows the vault linter spec (identical to the MCP):
  title -> type -> status -> area -> period -> product -> source ->
  informed-by -> tags -> aliases -> date-created -> date-modified

Routing model (matches wip-router.py behavior):
  * The router classifies _wip/ notes on the `area:` frontmatter key.
    area:cortex-cloud -> CORTEX/Cortex Cloud, area:panw-gtm -> PANW GTM,
    area:cortex-xdr -> CORTEX/XDR, area:lab -> _agents, etc.
  * A note with no recognized `area` returns "no routing signal" and stalls in
    _wip/. So: for a domain note you want auto-routed, ALWAYS pass --area.
  * The explicit seams (_research, _projects, github-projects/<repo>) are NOT
    produced by the router. Assert them at write time with --dest; the router is
    skipped entirely for those.

Body content is read from stdin (preferred, avoids shell-escaping issues) or from
--body / --body-file. Prints the final note path on success.

Exit codes:
  0  success
  2  bad arguments
  3  filesystem/write error
"""

import argparse
import datetime as _dt
import os
import re
import sys
import unicodedata

DEFAULT_VAULT_ROOT = os.path.expanduser(
    os.environ.get("VAULT_PATH", "/Users/henry/hr-vault-main-pa")
)
DEFAULT_DEST = "_wip"
MAX_SLUG_LEN = 60

# Must match the vault-os vault_create_note enum exactly.
VALID_NOTE_TYPES = (
    "working-note",
    "research",
    "reference",
    "meeting",
    "demo",
    "discovery",
)


def slugify(text: str) -> str:
    """Lowercase kebab slug, ASCII-folded, safe for filenames."""
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    text = text.lower().strip()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    text = re.sub(r"-{2,}", "-", text).strip("-")
    if len(text) > MAX_SLUG_LEN:
        text = text[:MAX_SLUG_LEN].rstrip("-")
    return text or "untitled"


def parse_tags(raw):
    """Accept comma- or space-separated tags; strip a leading '#'; dedupe, keep order."""
    if not raw:
        return []
    parts = re.split(r"[,\s]+", raw.strip())
    seen, out = set(), []
    for p in parts:
        t = p.lstrip("#").strip()
        if t and t not in seen:
            seen.add(t)
            out.append(t)
    return out


def parse_list(raw):
    """Comma-separated list values (informed-by wikilinks, aliases). Keep order, dedupe."""
    if not raw:
        return []
    parts = [p.strip() for p in raw.split(",")]
    seen, out = set(), []
    for p in parts:
        if p and p not in seen:
            seen.add(p)
            out.append(p)
    return out


def yaml_escape(value: str) -> str:
    """Quote a scalar if YAML might misread it."""
    if value == "" or re.search(r"[:#\[\]{}&*!|>'\"%@`,]", value) or value.strip() != value:
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return value


def _emit_scalar(lines, key, value):
    if value is None or value == "":
        lines.append(f"{key}:")
    else:
        lines.append(f"{key}: {yaml_escape(str(value))}")


def _emit_list(lines, key, items):
    if items:
        lines.append(f"{key}:")
        for it in items:
            lines.append(f"  - {yaml_escape(str(it))}")
    else:
        lines.append(f"{key}: []")


def build_frontmatter(
    title, note_type, status, area, period, product, source,
    informed_by, tags, aliases, date_created, date_modified, extra,
):
    """Emit frontmatter in the canonical linter key order (matches the MCP)."""
    lines = ["---"]
    _emit_scalar(lines, "title", title)
    _emit_scalar(lines, "type", note_type)
    _emit_scalar(lines, "status", status)
    _emit_scalar(lines, "area", area)
    _emit_scalar(lines, "period", period)
    _emit_scalar(lines, "product", product)
    _emit_scalar(lines, "source", source)
    _emit_list(lines, "informed-by", informed_by)
    _emit_list(lines, "tags", tags)
    _emit_list(lines, "aliases", aliases)
    _emit_scalar(lines, "date-created", date_created)
    _emit_scalar(lines, "date-modified", date_modified)
    for k, v in (extra or {}).items():
        _emit_scalar(lines, k, v)
    lines.append("---")
    return "\n".join(lines)


def resolve_collision(path: str) -> str:
    """If path exists, append -2, -3, ... before the extension."""
    if not os.path.exists(path):
        return path
    base, ext = os.path.splitext(path)
    n = 2
    while os.path.exists(f"{base}-{n}{ext}"):
        n += 1
    return f"{base}-{n}{ext}"


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Write an Obsidian capture note into the vault (Claude Code mirror of vault_create_note)."
    )
    ap.add_argument("--title", required=True, help="Human-readable note title; also drives the slug.")
    ap.add_argument("--slug", default=None, help="Override the kebab slug (defaults to slugified title).")
    ap.add_argument("--type", dest="note_type", default="working-note",
                    help="Frontmatter type: " + " | ".join(VALID_NOTE_TYPES) + " (default: working-note).")
    ap.add_argument("--status", default="wip", help="Frontmatter status (default: wip).")
    ap.add_argument("--area", default=None,
                    help="Routing area the wip-router keys on, e.g. cortex-cloud | cortex-xdr | "
                         "xsiam | prisma-cloud | panw-gtm | lab | personal. Required for router auto-routing.")
    ap.add_argument("--period", default=None, help="Frontmatter period, e.g. FY27-Q1.")
    ap.add_argument("--product", default=None, help="Product refinement, e.g. XDR | XSIAM | CDR.")
    ap.add_argument("--source", default="cowork", help="Provenance: project/cowork/code + identifier, or a URL.")
    ap.add_argument("--informed-by", dest="informed_by", default="",
                    help="Comma-separated wikilinks, e.g. '[[_MOC XSIAM]],[[Cortex Index]]'.")
    ap.add_argument("--tags", default="", help="Comma/space separated tags, e.g. 'research,cortex,xsiam'.")
    ap.add_argument("--aliases", default="", help="Comma-separated aliases.")
    ap.add_argument("--dest", default=DEFAULT_DEST,
                    help="Destination folder relative to vault root. Default '_wip' lets the router "
                         "classify by area. Pass a seam folder (e.g. '_research', '_projects', "
                         "'github-projects/<repo>', 'CORTEX/Cortex Cloud') to write directly and skip routing.")
    ap.add_argument("--vault-root", default=DEFAULT_VAULT_ROOT, help="Vault root (default: $VAULT_PATH).")
    ap.add_argument("--date", default=None, help="Override date for created/modified (YYYY-MM-DD). Defaults to today.")
    ap.add_argument("--body", default=None, help="Note body as a string.")
    ap.add_argument("--body-file", default=None, help="Read note body from this file.")
    ap.add_argument("--extra", action="append", default=[], metavar="KEY=VALUE",
                    help="Extra trailing frontmatter key=value (repeatable).")
    ap.add_argument("--print-only", action="store_true",
                    help="Print the composed note to stdout instead of writing it (dry run).")
    args = ap.parse_args(argv)

    if args.note_type not in VALID_NOTE_TYPES:
        print(f"error: --type must be one of {', '.join(VALID_NOTE_TYPES)}; got {args.note_type!r}",
              file=sys.stderr)
        return 2

    date_str = args.date or _dt.date.today().isoformat()
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", date_str):
        print(f"error: --date must be YYYY-MM-DD, got {date_str!r}", file=sys.stderr)
        return 2

    # Body precedence: --body > --body-file > stdin
    if args.body is not None:
        body = args.body
    elif args.body_file:
        try:
            with open(args.body_file, "r", encoding="utf-8") as fh:
                body = fh.read()
        except OSError as e:
            print(f"error: cannot read --body-file: {e}", file=sys.stderr)
            return 3
    elif not sys.stdin.isatty():
        body = sys.stdin.read()
    else:
        body = ""

    extra = {}
    for item in args.extra:
        if "=" not in item:
            print(f"error: --extra must be KEY=VALUE, got {item!r}", file=sys.stderr)
            return 2
        k, v = item.split("=", 1)
        extra[k.strip()] = v.strip()

    tags = parse_tags(args.tags)
    informed_by = parse_list(args.informed_by)
    aliases = parse_list(args.aliases)
    slug = slugify(args.slug if args.slug else args.title)
    filename = f"{date_str}-{slug}.md"

    frontmatter = build_frontmatter(
        title=args.title,
        note_type=args.note_type,
        status=args.status,
        area=args.area,
        period=args.period,
        product=args.product,
        source=args.source,
        informed_by=informed_by,
        tags=tags,
        aliases=aliases,
        date_created=date_str,
        date_modified=date_str,
        extra=extra,
    )
    note = frontmatter + "\n\n" + (f"# {args.title}\n\n" if body and not body.lstrip().startswith("#") else "") + body
    if not note.endswith("\n"):
        note += "\n"

    if args.print_only:
        sys.stdout.write(note)
        return 0

    target_dir = os.path.join(args.vault_root, args.dest)
    try:
        os.makedirs(target_dir, exist_ok=True)
    except OSError as e:
        print(f"error: cannot create vault dir {target_dir!r}: {e}", file=sys.stderr)
        return 3

    target = resolve_collision(os.path.join(target_dir, filename))
    tmp = target + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(note)
        os.replace(tmp, target)  # atomic on same filesystem
    except OSError as e:
        print(f"error: write failed: {e}", file=sys.stderr)
        try:
            if os.path.exists(tmp):
                os.remove(tmp)
        except OSError:
            pass
        return 3

    print(target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
