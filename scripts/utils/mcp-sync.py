#!/usr/bin/env python3
"""mcp-sync — render one MCP registry into every harness's native config.

Reads ~/.agents/mcp.toml (source of truth) and renders each server into:
  • Claude Code  — emits `claude mcp add ... --scope user` commands (run them)
  • Gemini CLI   — merges mcpServers{} into ~/.gemini/settings.json
  • Claude Desktop (macOS) — merges into claude_desktop_config.json

$VARS stay symbolic (both Gemini and Claude expand them); we never inline
secrets. Mirrors the gen-fastfetch.py "one source → many renders" pattern.

Usage: mcp-sync.py [--dry-run] [--only claude|gemini|desktop]
"""
from __future__ import annotations
import json, os, sys, platform, shutil, subprocess
from pathlib import Path

# Help guard FIRST — without it, `--help` (or any unrecognized flag) left
# DRY=False and main() performed a REAL sync (claude mcp remove/add, JSON
# overwrites). Show usage and exit before any state is touched.
if any(a in ("-h", "--help") for a in sys.argv[1:]):
    print(__doc__ or "mcp-sync — usage: mcp-sync [--dry-run] [--only NAME] [--profile P] [--all]")
    sys.exit(0)

try:
    import tomllib  # py3.11+
except ModuleNotFoundError:
    print("✗ python3.11+ (tomllib) required for mcp-sync", file=sys.stderr); sys.exit(1)

REGISTRY = Path(os.environ.get("AGENTS_HOME", Path.home() / ".agents")) / "mcp.toml"
# fall back to the repo copy if the deployed one is absent
if not REGISTRY.exists():
    REGISTRY = Path(os.environ.get("DOTFILES_DIR", Path.home() / ".dotfiles")) / "claude" / "mcp.toml"
GEMINI = Path.home() / ".gemini" / "settings.json"
DESKTOP = Path.home() / "Library" / "Application Support" / "Claude" / "claude_desktop_config.json"

DRY = "--dry-run" in sys.argv
ONLY = next((sys.argv[i+1] for i, a in enumerate(sys.argv) if a == "--only" and i+1 < len(sys.argv)), None)
# Profile gating: a server tagged `profile = "X"` syncs only when X matches the
# requested/active profile, or with --all. Untagged servers always sync.
PROFILE = next((sys.argv[i+1] for i, a in enumerate(sys.argv) if a == "--profile" and i+1 < len(sys.argv)),
               os.environ.get("CLAW_ACTIVE_PROFILE"))
ALL = "--all" in sys.argv
IS_MAC = platform.system() == "Darwin"

def load():
    if not REGISTRY.exists():
        print(f"✗ registry not found: {REGISTRY}", file=sys.stderr); sys.exit(1)
    return tomllib.loads(REGISTRY.read_text()).get("servers", {})

def applicable(name, spec):
    if spec.get("os") == "macos" and not IS_MAC:
        return False
    # profile-gated servers only sync for the matching profile (or --all)
    prof = spec.get("profile")
    if prof and not ALL and prof != PROFILE:
        return False
    return True

def render_claude(servers):
    if not shutil.which("claude"):
        print("· claude CLI absent — skipping Claude Code"); return
    for name, spec in servers.items():
        if "claude" not in spec.get("targets", []) or not applicable(name, spec):
            continue
        cmd = ["claude", "mcp", "add", name, "--scope", "user"]
        for k, v in (spec.get("env") or {}).items():
            cmd += ["-e", f"{k}={v}"]
        cmd += ["--", spec["command"], *spec.get("args", [])]
        if DRY:
            print("  DRY:", " ".join(cmd))
        else:
            subprocess.run(["claude", "mcp", "remove", name, "--scope", "user"],
                           capture_output=True)
            r = subprocess.run(cmd, capture_output=True, text=True)
            print(f"  {'✓' if r.returncode == 0 else '!'} claude ← {name}")

def merge_json(path: Path, servers, key="mcpServers"):
    data = {}
    if path.exists():
        try: data = json.loads(path.read_text())
        except Exception: data = {}
    block = data.setdefault(key, {})
    for name, spec in servers.items():
        entry = {"command": spec["command"], "args": spec.get("args", [])}
        if spec.get("env"): entry["env"] = spec["env"]
        block[name] = entry
    if DRY:
        print(f"  DRY: would write [{', '.join(servers)}] → {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"  ✓ {path.name} ← {', '.join(servers)}")

def main():
    servers = load()
    print(f"\n  mcp-sync — {len(servers)} servers from {REGISTRY}{'  (dry-run)' if DRY else ''}\n")
    if ONLY in (None, "claude"):
        print("  ◆ Claude Code"); render_claude(servers)
    if ONLY in (None, "gemini"):
        g = {n: s for n, s in servers.items() if "gemini" in s.get("targets", []) and applicable(n, s)}
        print("  ◆ Gemini CLI"); merge_json(GEMINI, g)
    if (ONLY in (None, "desktop")) and IS_MAC:
        d = {n: s for n, s in servers.items() if "desktop" in s.get("targets", []) and applicable(n, s)}
        print("  ◆ Claude Desktop (macOS)"); merge_json(DESKTOP, d)
    print("\n  done. restart the harness to pick up changes.\n")

if __name__ == "__main__":
    main()
