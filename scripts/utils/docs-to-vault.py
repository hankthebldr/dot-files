#!/usr/bin/env python3
"""docs-to-vault.py — transpose the repo's planning corpus into the Obsidian vault.

Mirrors specs / plans / ADRs / backlog / reference docs (from docs/) and the
Claude harness (from claude/) into Github-Projects/dot-files/<category>/ as
first-class vault notes with provenance frontmatter (product, source path,
source-sha). Idempotent: re-runs overwrite in place. Generates a planning index.

The cloud session can't reach the local vault, so docs live in the repo and this
runs on the operator's machine.  Entry: `bash scripts/utils/docs-to-vault.sh`
(or `claw docs-sync`).
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from pathlib import Path

PRODUCT = "Open Claw"
TODAY = "2026-06-20"
DATE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})")
H1_RE = re.compile(r"^#\s+(.+?)\s*$", re.MULTILINE)

# (src relative to repo root, dest subfolder, type, status, extra tags)
# Markdown docs get provenance frontmatter; non-md are copied verbatim.
MAPPING: list[tuple[str, str, str, str, list[str]]] = [
    # ── design specs ─────────────────────────────────────────────────────────
    ("docs/superpowers/specs/2026-04-25-claw-mvp-rewrite-design.md", "specs", "reference", "active", ["spec", "design"]),
    ("docs/superpowers/specs/2026-04-25-welcome-tui-overhaul-design.md", "specs", "reference", "active", ["spec", "design"]),
    ("docs/superpowers/specs/2026-05-06-hermes-openrouter-design.md", "specs", "reference", "active", ["spec", "design"]),
    ("docs/superpowers/specs/2026-05-19-18-profile-architecture-design.md", "specs", "reference", "active", ["spec", "design"]),
    ("docs/superpowers/specs/2026-06-01-session-name-banner-design.md", "specs", "reference", "active", ["spec", "design"]),
    ("docs/superpowers/specs/2026-06-02-tui-profile-action-contract-design.md", "specs", "reference", "active", ["spec", "design", "tui-v2"]),
    ("docs/plans/2026-03-05-ubuntu-installer-design.md", "specs", "reference", "active", ["spec", "design"]),
    ("docs/plans/2026-03-28-profile-fastfetch-design.md", "specs", "reference", "active", ["spec", "design"]),
    ("docs/plans/2026-03-30-ssh-tunnel-manager-design.md", "specs", "reference", "active", ["spec", "design"]),
    ("docs/superpowers/plans/2026-06-01-session-name-banner.md", "plans", "reference", "active", ["plan"]),
    ("docs/superpowers/plans/2026-06-02-hermes-openrouter-activation.md", "plans", "reference", "active", ["plan"]),
    ("docs/plans/2026-03-05-ubuntu-installer-plan.md", "plans", "reference", "active", ["plan"]),
    ("docs/plans/2026-07-11-next-gen-feature-brainstorming.md", "plans", "reference", "active", ["plan", "brainstorming"]),
    # ── decisions (ADRs) ──────────────────────────────────────────────────────
    ("docs/ADR-001-hybrid-model-stack.md", "decisions", "decision", "accepted", ["adr"]),
    ("docs/ADR-002-mcp-server-selection.md", "decisions", "decision", "accepted", ["adr"]),
    # ── backlog / roadmap ─────────────────────────────────────────────────────
    ("docs/FEATURE-BACKLOG.md", "backlog", "reference", "living", ["backlog", "roadmap"]),
    ("docs/ULTRAPLAN.md", "backlog", "reference", "living", ["backlog", "roadmap"]),
    ("docs/backlog/backend-tooling-backlog.md", "backlog", "reference", "living", ["backlog"]),
    ("docs/backlog/desktop-visual-backlog.md", "backlog", "reference", "living", ["backlog"]),
    # ── reference / architecture ──────────────────────────────────────────────
    ("docs/ARCHITECTURE.md", "reference", "reference", "active", ["architecture"]),
    ("docs/profiles/architecture.md", "reference", "reference", "active", ["architecture", "profiles"]),
    ("docs/claw.md", "reference", "reference", "active", ["guide"]),
    ("docs/ALIASES.md", "reference", "reference", "active", ["guide", "aliases"]),
    ("docs/UX-WALKTHROUGH.md", "reference", "reference", "active", ["ux"]),
    ("docs/spec-integration.md", "reference", "reference", "active", ["spec", "phases"]),
    ("docs/claude-config-boundaries.md", "reference", "reference", "active", ["claude", "boundaries"]),
    # ── claude harness (planning-bearing config) ──────────────────────────────
    ("claude/CLAUDE.md", "harness", "reference", "active", ["claude", "rules"]),
    ("claude/commands/handoff.md", "harness/commands", "reference", "active", ["claude", "command"]),
    ("claude/commands/recon.md", "harness/commands", "reference", "active", ["claude", "command"]),
    ("claude/commands/scope.md", "harness/commands", "reference", "active", ["claude", "command"]),
    ("claude/commands/sync-docs.md", "harness/commands", "reference", "active", ["claude", "command"]),
    ("claude/commands/threat-model.md", "harness/commands", "reference", "active", ["claude", "command"]),
    ("claude/skills/iocs-extract/SKILL.md", "harness/skills", "reference", "active", ["claude", "skill"]),
    ("claude/skills/nmap-scan-interpret/SKILL.md", "harness/skills", "reference", "active", ["claude", "skill"]),
    ("claude/skills/recon-methodology/SKILL.md", "harness/skills", "reference", "active", ["claude", "skill"]),
    ("claude/skills/report-writeup/SKILL.md", "harness/skills", "reference", "active", ["claude", "skill"]),
    ("claude/skills/stride-threat-model/SKILL.md", "harness/skills", "reference", "active", ["claude", "skill"]),
    ("claude/harness/README.md", "harness", "reference", "active", ["claude", "harness"]),
]

# Verbatim copies (no frontmatter): config + non-markdown provenance.
VERBATIM: list[tuple[str, str]] = [
    ("claude/mcp.toml", "harness"),
]


def pretty_title(stem: str) -> str:
    s = DATE_RE.sub("", stem).strip("-_ ")
    s = s.replace("-", " ").replace("_", " ").strip()
    return s[:1].upper() + s[1:] if s else stem


def derive_title(body: str, path: Path) -> str:
    m = H1_RE.search(body)
    if m:
        return m.group(1).strip()
    return pretty_title(path.stem)


def derive_created(path: Path) -> str:
    m = DATE_RE.search(path.name)
    return m.group(1) if m else TODAY


def has_frontmatter(text: str) -> bool:
    return text.lstrip().startswith("---")


def yq(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build_frontmatter(title: str, ftype: str, status: str, tags: list[str],
                      src_rel: str, sha: str, created: str) -> str:
    taglist = ["dot-files"] + tags
    lines = [
        "---",
        f"title: {yq(title)}",
        f"type: {ftype}",
        f"status: {status}",
        "area: development",
        f"product: {PRODUCT}",
        f"source: code: dot-files/{src_rel}",
        f"source-sha: {sha}",
        "tags: [" + ", ".join(taglist) + "]",
        "aliases: []",
        f"date-created: {created}",
        f"date-modified: {TODAY}",
        "---",
        "",
    ]
    return "\n".join(lines)


def transpose(repo: Path, dest_root: Path, sha: str) -> dict[str, list[str]]:
    written: dict[str, list[str]] = {}
    for src_rel, sub, ftype, status, tags in MAPPING:
        src = repo / src_rel
        if not src.is_file():
            print(f"  skip (missing): {src_rel}")
            continue
        body = src.read_text(encoding="utf-8", errors="replace")
        # Disambiguate generic filenames so they don't collide in a flat folder.
        out_name = src.name
        if out_name in {"README.md", "SKILL.md", "architecture.md", "CLAUDE.md"}:
            parent = src.parent.name
            out_name = f"{parent}-{src.name}"
        out_dir = dest_root / sub
        out_dir.mkdir(parents=True, exist_ok=True)
        out = out_dir / out_name
        if has_frontmatter(body):
            out.write_text(body, encoding="utf-8")  # already a note; copy verbatim
        else:
            title = derive_title(body, src)
            fm = build_frontmatter(title, ftype, status, tags, src_rel, sha, derive_created(src))
            out.write_text(fm + body, encoding="utf-8")
        written.setdefault(sub.split("/")[0], []).append(f"{sub}/{out_name}")
        print(f"  ✓ {src_rel} → {sub}/{out_name}")

    for src_rel, sub in VERBATIM:
        src = repo / src_rel
        if not src.is_file():
            continue
        out_dir = dest_root / sub
        out_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, out_dir / src.name)
        written.setdefault(sub.split("/")[0], []).append(f"{sub}/{src.name}")
        print(f"  ✓ {src_rel} → {sub}/{src.name} (verbatim)")

    # Archive: mirror docs/archive/** preserving relative path; .md get light
    # frontmatter, other files copied verbatim as attachments.
    arc_src = repo / "docs" / "archive"
    if arc_src.is_dir():
        for f in sorted(arc_src.rglob("*")):
            if not f.is_file():
                continue
            rel = f.relative_to(arc_src)
            out = dest_root / "archive" / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            if f.suffix == ".md":
                body = f.read_text(encoding="utf-8", errors="replace")
                if has_frontmatter(body):
                    out.write_text(body, encoding="utf-8")
                else:
                    title = derive_title(body, f)
                    fm = build_frontmatter(title, "reference", "archived", ["archive"],
                                           f"docs/archive/{rel}", sha, derive_created(f))
                    out.write_text(fm + body, encoding="utf-8")
            else:
                shutil.copy2(f, out)
            written.setdefault("archive", []).append(f"archive/{rel}")
            print(f"  ✓ docs/archive/{rel} → archive/{rel}")
    return written


def write_index(dest_root: Path, written: dict[str, list[str]], sha: str) -> Path:
    order = ["specs", "plans", "decisions", "backlog", "reference", "harness", "archive"]
    titles = {
        "specs": "Design Specs", "plans": "Plans", "decisions": "Decisions (ADRs)",
        "backlog": "Backlog & Roadmap", "reference": "Reference & Architecture",
        "harness": "Claude Harness", "archive": "Archive (pre-MVP)",
    }
    lines = [
        "---",
        "title: Open Claw — Planning Corpus Index",
        "type: reference",
        "status: active",
        "area: development",
        f"product: {PRODUCT}",
        "source: /repo-summary (docs-to-vault transpose)",
        f"source-sha: {sha}",
        "tags: [dot-files, index, planning, repo-summary]",
        "aliases: [Open Claw Planning, dot-files planning]",
        f"date-created: {TODAY}",
        f"date-modified: {TODAY}",
        "---",
        "",
        "# Open Claw — Planning Corpus",
        "",
        f"> Product: **{PRODUCT}**  ·  Repo: `dot-files`  ·  mirror @ `{sha}`",
        ">",
        "> Transposed from the repo's `docs/` + `claude/` trees by `claw docs-sync`",
        "> (`scripts/utils/docs-to-vault.py`). These are **mirrors** — the repo is the",
        "> source of truth. See [[SUMMARY]] for the full-depth repo snapshot.",
        "",
    ]
    for key in order:
        items = sorted(set(written.get(key, [])))
        if not items:
            continue
        lines.append(f"## {titles[key]}")
        lines.append("")
        for it in items:
            name = it.rsplit("/", 1)[-1]
            label = name[:-3] if name.endswith(".md") else name
            lines.append(f"- [[{label}]] — `{it}`")
        lines.append("")
    out = dest_root / "_planning-index.md"
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"  ✓ index → _planning-index.md")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dotfiles", required=True)
    ap.add_argument("--vault", required=True)
    args = ap.parse_args()
    repo = Path(args.dotfiles).resolve()
    dest_root = Path(args.vault) / "Github-Projects" / "dot-files"
    dest_root.mkdir(parents=True, exist_ok=True)
    try:
        sha = subprocess.check_output(
            ["git", "-C", str(repo), "rev-parse", "--short", "HEAD"],
            text=True).strip()
    except Exception:
        sha = "unknown"
    print(f"transposing planning corpus → {dest_root}  (@ {sha})")
    written = transpose(repo, dest_root, sha)
    write_index(dest_root, written, sha)
    total = sum(len(v) for v in written.values())
    print(f"done — {total} docs across {len([k for k in written if written[k]])} categories")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
