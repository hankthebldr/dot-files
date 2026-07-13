# Harness Sync & Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dotfiles repo the single portable source of truth for Henry's custom Claude harness — capture locally-made skills/commands/agents/plugins/MCP into the repo, and deploy them (plus a connector checklist) on any machine via `claw harness`.

**Architecture:** Extend the existing `claw harness` spine — `scripts/utils/harness.sh` (engine) + `scripts/setup/link-claude.sh` (deployer). Add one reverse verb, `capture`. Bash owns file moves + symlinks; a new `scripts/utils/harness-manifest.py` owns all JSON I/O in both directions (capture = local→repo, apply = repo→machine). No parallel dispatcher.

**Tech Stack:** Bash (`set -euo pipefail`), Python 3 (stdlib `json` only), bats-core tests, `git`.

## Global Constraints

- **One dispatcher / one deployer.** All work extends `harness.sh` + `link-claude.sh`; never add a second `claw()` or a parallel updater front door.
- **No secrets in git.** MCP `env` values matching a secret heuristic (`*_TOKEN`, `*_KEY`, `*_SECRET`, `*_PASSWORD`, or ≥24-char high-entropy) are rewritten to `${ORIGINAL_KEY}`. A literal secret that cannot be mapped is a hard error — nothing secret is written.
- **Idempotent + backup-before-write.** Every `mv` and every JSON write backs the target up to `~/.dotfiles-backups/<ts>/` first. Re-running any command already in sync is a no-op.
- **Never clobber machine state.** MCP merge and `enabledPlugins` are additive; existing same-name servers and existing keys are preserved. Marketplace registration is skip-if-present.
- **Capture acts by default; `--dry-run` previews.** Deploy also honors `--dry-run`.
- **Cross-platform.** Bash uses `$HOMEBREW_PREFIX` and `platform.zsh` shim conventions where relevant; JSON via `python3` (already a repo dependency). No `echo >>` into JSON — Python merges.
- **Engine honors `CLAUDE_HOME`/`CLAUDE_DST`** (already true) and `DOTFILES_DIR`, so tests run against a scratch home.
- **Commit style:** one-line, imperative, ≤72 chars, Co-Authored-By trailer. Stage by explicit path.

## File Structure

| File | Responsibility |
|---|---|
| `scripts/utils/harness.sh` | **Modify.** Add `harness_capture()` + `capture` dispatch; file move+symlink logic; calls the Python helper. |
| `scripts/utils/harness-manifest.py` | **Create.** All JSON I/O: `capture` (writes `manifest.json` + merges `claude/mcp.json`) and `apply` (registers marketplace, enables plugins, merges machine MCP, prints connector checklist). Stdlib only. |
| `scripts/setup/link-claude.sh` | **Modify.** After existing symlinking, call `harness-manifest.py apply`. |
| `claude/harness/manifest.json` | **Create (committed seed).** `{version, enabledPlugins:{}, connectors:[]}`. Hand-maintained `connectors`. |
| `claude/harness/marketplace/.claude-plugin/marketplace.json` | **Create.** Local marketplace descriptor listing bundled plugins. |
| `claude/harness/_templates/plugin/` | **Modify.** Update to real `.claude-plugin/plugin.json` shape. |
| `claude/harness/README.md` | **Modify.** Document `capture`, marketplace, manifest. |
| `tests/harness.bats` | **Modify.** Add capture/apply tests using the existing scratch-home harness. |
| `tests/fixtures/` | **Add as needed.** Seed configs for apply tests. |

**Phasing (each phase is independently landable + testable):**
- **Phase 1 — File capture + deploy** (skills/commands/agents). The shippable core.
- **Phase 2 — Local marketplace + enabledPlugins + connector checklist** (covers the vault-os example).
- **Phase 3 — MCP server capture** into `claude/mcp.json` with redaction.

---

## Phase 1 — File capture + symlink

### Task 1: `_capture_files` — detect & move real, untracked artifacts

**Files:**
- Modify: `scripts/utils/harness.sh` (add `harness_capture()`, `_capture_one_kind()`, `capture` in `main`)
- Test: `tests/harness.bats`

**Interfaces:**
- Consumes: existing engine vars `HARNESS`, `CLAUDE_DST`, `DOTFILES_DIR`, `log_*`.
- Produces: `harness_capture [--dry-run]`; for each real dir/file in `$CLAUDE_DST/{skills,commands,agents}` that is (a) not a symlink, (b) not `_`/`.`-prefixed, (c) not resolving inside the repo/`.agents`/`plugins/cache`, it backs up, `mv`s into `$HARNESS/<kind>/`, and replaces the original with a symlink to the repo path.

- [ ] **Step 1: Write the failing test** — real skill captured, symlink skipped

Add to `tests/harness.bats`:

```bash
@test "capture: moves a real local skill into the repo and symlinks it back" {
  mkdir -p "$HOME/.claude/skills/mine"
  printf -- '---\nname: mine\ndescription: Use when mine.\n---\n' > "$HOME/.claude/skills/mine/SKILL.md"
  run_h capture
  [ "$status" -eq 0 ]
  [ -f "$DF/claude/harness/skills/mine/SKILL.md" ]        # now in repo
  [ -L "$HOME/.claude/skills/mine" ]                      # original is a symlink
  [ "$(readlink "$HOME/.claude/skills/mine")" = "$DF/claude/harness/skills/mine" ]
}

@test "capture: skips symlinks and _/.-prefixed and marketplace dirs" {
  ln -s /tmp "$HOME/.claude/skills/linked"
  mkdir -p "$HOME/.claude/skills/_scratch"
  run_h capture
  [ "$status" -eq 0 ]
  [ ! -e "$DF/claude/harness/skills/linked" ]
  [ ! -e "$DF/claude/harness/skills/_scratch" ]
  [ -L "$HOME/.claude/skills/linked" ]                    # untouched
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/harness.bats -f capture`
Expected: FAIL — `capture` is an unknown subcommand.

- [ ] **Step 3: Implement `harness_capture` + dispatch**

In `scripts/utils/harness.sh`, add before `main()`:

```bash
# _resolve <path> — realpath with a portable fallback (no coreutils on macOS).
_resolve(){ cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"; }

# _is_managed <realpath> — true if it belongs to the repo or a marketplace.
_is_managed(){
  case "$1" in
    "$DOTFILES_DIR"/*) return 0 ;;
    */.agents/*)       return 0 ;;
    */plugins/cache/*) return 0 ;;
    *) return 1 ;;
  esac
}

# _capture_one_kind <kind> <dry> — capture real untracked entries of one kind.
_capture_one_kind(){
  local kind="$1" dry="$2" src="$CLAUDE_DST/$1" e name real ts
  [[ -d "$src" ]] || return 0
  ts="$(date +%Y%m%d-%H%M%S)"
  for e in "$src"/*; do
    [[ -e "$e" ]] || continue
    name="$(basename "$e")"
    [[ "$name" == _* || "$name" == .* ]] && continue
    [[ -L "$e" ]] && continue                     # already a symlink → skip
    real="$(_resolve "$e")"
    _is_managed "$real" && continue
    if [[ "$dry" -eq 1 ]]; then
      log_info "would capture: $kind '$name'"
      continue
    fi
    local dst="$HARNESS/$kind/$name"
    [[ -e "$dst" ]] && { log_warning "skip $kind '$name': already in repo"; continue; }
    local bkp="$HOME/.dotfiles-backups/$ts/claude/$kind"
    mkdir -p "$bkp" "$HARNESS/$kind"
    cp -R "$e" "$bkp/$name"
    mv "$e" "$dst"
    ln -s "$dst" "$e"
    log_success "captured $kind '$name' → claude/harness/$kind/$name"
  done
}

harness_capture(){
  local dry=0 a; for a in "$@"; do [[ "$a" == "--dry-run" || "$a" == "-n" ]] && dry=1; done
  local kind
  for kind in skills commands agents; do _capture_one_kind "$kind" "$dry"; done
}
```

Add to the `case` in `main()`:

```bash
    capture)      harness_capture "$@" ;;
```

And update the `--help` usage line to include `capture`.

- [ ] **Step 4: Run to verify it passes**

Run: `bats tests/harness.bats -f capture`
Expected: PASS (both tests).

- [ ] **Step 5: Run the full harness suite (no regressions)**

Run: `bats tests/harness.bats`
Expected: all existing + 2 new tests PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/utils/harness.sh tests/harness.bats
git commit -m "feat(harness): capture real local skills/cmds/agents into repo"
```

### Task 2: `--dry-run` preview + commands/agents coverage

**Files:**
- Modify: `scripts/utils/harness.sh` (already handles all three kinds + dry-run from Task 1)
- Test: `tests/harness.bats`

**Interfaces:**
- Consumes: `harness_capture` from Task 1.
- Produces: verified dry-run (mutates nothing) and command/agent (file, not dir) capture.

- [ ] **Step 1: Write the failing tests**

```bash
@test "capture --dry-run: previews without moving anything" {
  mkdir -p "$HOME/.claude/skills/mine"
  printf -- '---\nname: mine\ndescription: x\n---\n' > "$HOME/.claude/skills/mine/SKILL.md"
  run_h capture --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would capture: skills 'mine'"* ]]
  [ ! -e "$DF/claude/harness/skills/mine" ]        # nothing moved
  [ ! -L "$HOME/.claude/skills/mine" ]             # still a real dir
}

@test "capture: handles single-file commands and agents" {
  printf -- '---\nname: c1\ndescription: cmd\n---\nbody\n' > "$HOME/.claude/commands/c1.md"
  printf -- '---\nname: a1\ndescription: agent\n---\nbody\n' > "$HOME/.claude/agents/a1.md"
  run_h capture
  [ "$status" -eq 0 ]
  [ -f "$DF/claude/harness/commands/c1.md" ]; [ -L "$HOME/.claude/commands/c1.md" ]
  [ -f "$DF/claude/harness/agents/a1.md" ];   [ -L "$HOME/.claude/agents/a1.md" ]
}
```

- [ ] **Step 2: Run to verify**

Run: `bats tests/harness.bats -f capture`
Expected: The two new tests PASS (logic already covers files + dry-run from Task 1). If the file-glob `for e in "$src"/*` fails on the `.md` files, fix by confirming `-e "$e"` guard handles them (it does).

- [ ] **Step 3: Idempotency test**

```bash
@test "capture: second run is a no-op" {
  mkdir -p "$HOME/.claude/skills/mine"
  printf -- '---\nname: mine\ndescription: x\n---\n' > "$HOME/.claude/skills/mine/SKILL.md"
  run_h capture; [ "$status" -eq 0 ]
  run_h capture; [ "$status" -eq 0 ]
  [[ "$output" != *"captured skills 'mine'"* ]]    # nothing re-captured (already a symlink)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bats tests/harness.bats -f capture`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/harness.bats
git commit -m "test(harness): capture dry-run, file-kind, and idempotency"
```

---

## Phase 2 — Local marketplace, enabledPlugins, connector checklist

### Task 3: Verify the local-marketplace source schema

**Files:** none (investigation task producing a confirmed fact recorded in the plan/PR notes)

**Interfaces:** Produces the confirmed `marketplace.json` per-plugin `source` shape for a **local directory** marketplace, and the exact `known_marketplaces.json` local-source key used by `apply` (Task 5).

- [ ] **Step 1: Register a throwaway local marketplace and inspect**

Run (interactive Claude Code session, or inspect docs):
```bash
mkdir -p /tmp/mkt/.claude-plugin /tmp/mkt/demo/.claude-plugin
printf '{"name":"demo","description":"d"}\n' > /tmp/mkt/demo/.claude-plugin/plugin.json
printf '{"name":"local-demo","plugins":[{"name":"demo","source":"./demo"}]}\n' > /tmp/mkt/.claude-plugin/marketplace.json
# In an interactive CC session: /plugin marketplace add /tmp/mkt   then inspect:
python3 -c "import json;print(json.dumps(json.load(open('$HOME/.claude/plugins/known_marketplaces.json')),indent=1))"
```
Expected: a new key whose `source` encodes a local directory. **Record the exact JSON shape** (e.g. `{"source":{"source":"directory","path":"/tmp/mkt"}}` vs `{"source":{"source":"local","path":...}}`).

- [ ] **Step 2: Record the confirmed shapes**

Write the confirmed `marketplace.json` plugin-`source` value and the `known_marketplaces.json` local-source object into a comment block at the top of `scripts/utils/harness-manifest.py` (created in Task 4) so Task 5 writes the correct shape. If registration is unavailable in this environment, default to `{"source":{"source":"directory","path":"<abs repo marketplace dir>"}}` and per-plugin `"source":"./<name>"`, and flag for manual confirmation.

- [ ] **Step 3: Clean up**

```bash
rm -rf /tmp/mkt
```

### Task 4: `harness-manifest.py capture` — enabledPlugins → manifest

**Files:**
- Create: `scripts/utils/harness-manifest.py`
- Create: `claude/harness/manifest.json` (committed seed)
- Test: `tests/harness.bats`

**Interfaces:**
- Consumes: `--claude-home <dir>` (source of `settings.json`), `--repo <dir>` (dest of `manifest.json`).
- Produces: `python3 harness-manifest.py capture --claude-home H --repo R [--dry-run]` — reads `H/settings.json` `enabledPlugins`, merges into `R/claude/harness/manifest.json` (preserving existing `connectors`), prints a one-line summary. Exit 0.

- [ ] **Step 1: Seed the committed manifest**

Create `claude/harness/manifest.json`:
```json
{
  "version": 1,
  "enabledPlugins": {},
  "connectors": []
}
```

- [ ] **Step 2: Write the failing test**

```bash
@test "manifest capture: records enabledPlugins from settings.json" {
  mkdir -p "$HOME/.claude"
  printf '{"enabledPlugins":{"code-review@claude-plugins-official":true}}\n' > "$HOME/.claude/settings.json"
  printf '{"version":1,"enabledPlugins":{},"connectors":[]}\n' > "$DF/claude/harness/manifest.json"
  run python3 "$BATS_TEST_DIRNAME/../scripts/utils/harness-manifest.py" capture --claude-home "$HOME/.claude" --repo "$DF"
  [ "$status" -eq 0 ]
  run python3 -c "import json;print(json.load(open('$DF/claude/harness/manifest.json'))['enabledPlugins'].get('code-review@claude-plugins-official'))"
  [[ "$output" == "True" ]]
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `bats tests/harness.bats -f "manifest capture"`
Expected: FAIL — file `harness-manifest.py` does not exist.

- [ ] **Step 4: Implement the capture command**

Create `scripts/utils/harness-manifest.py`:
```python
#!/usr/bin/env python3
"""harness-manifest.py — JSON I/O for `claw harness` capture/apply.

capture: local ~/.claude state  -> repo (manifest.json + claude/mcp.json)
apply:   repo manifest/registry -> machine (marketplace, enabledPlugins, mcp)

Local-marketplace shapes (confirmed in Task 3):
  known_marketplaces.json entry: {"source": {"source": "directory", "path": ABS}}
  marketplace.json plugin entry: {"name": N, "source": "./N"}
"""
import argparse, json, os, sys

def _load(path, default):
    try:
        with open(path) as f: return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return default

def _dump(path, obj, dry):
    if dry:
        print(f"would write {path}"); return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2); f.write("\n")

def cmd_capture(a):
    settings = _load(os.path.join(a.claude_home, "settings.json"), {})
    mpath = os.path.join(a.repo, "claude", "harness", "manifest.json")
    manifest = _load(mpath, {"version": 1, "enabledPlugins": {}, "connectors": []})
    enabled = settings.get("enabledPlugins", {})
    manifest["enabledPlugins"] = {**manifest.get("enabledPlugins", {}), **enabled}
    _dump(mpath, manifest, a.dry_run)
    print(f"enabledPlugins: {len(manifest['enabledPlugins'])} recorded")
    return 0

def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("capture", "apply"):
        s = sub.add_parser(name)
        s.add_argument("--claude-home", required=True)
        s.add_argument("--repo", required=True)
        s.add_argument("--dry-run", action="store_true")
    a = p.parse_args()
    return {"capture": cmd_capture}.get(a.cmd, lambda _:_unimpl(a.cmd))(a)

def _unimpl(cmd):
    print(f"{cmd}: not implemented", file=sys.stderr); return 1

if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Run to verify it passes**

Run: `bats tests/harness.bats -f "manifest capture"`
Expected: PASS.

- [ ] **Step 6: Wire capture into `harness_capture`**

In `scripts/utils/harness.sh`, at the end of `harness_capture()` (before its closing brace), after the file loop:
```bash
  if command -v python3 >/dev/null 2>&1; then
    local dflag=(); [[ "$dry" -eq 1 ]] && dflag=(--dry-run)
    python3 "$DOTFILES_DIR/scripts/utils/harness-manifest.py" capture \
      --claude-home "$CLAUDE_DST" --repo "$DOTFILES_DIR" "${dflag[@]}" || log_warning "manifest capture failed"
  fi
```

- [ ] **Step 7: Test the wired path**

```bash
@test "capture: also records enabledPlugins via the manifest helper" {
  printf '{"enabledPlugins":{"figma@claude-plugins-official":true}}\n' > "$HOME/.claude/settings.json"
  printf '{"version":1,"enabledPlugins":{},"connectors":[]}\n' > "$DF/claude/harness/manifest.json"
  run_h capture
  [ "$status" -eq 0 ]
  grep -q "figma@claude-plugins-official" "$DF/claude/harness/manifest.json"
}
```
Run: `bats tests/harness.bats -f capture`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/utils/harness-manifest.py scripts/utils/harness.sh claude/harness/manifest.json tests/harness.bats
git commit -m "feat(harness): capture enabledPlugins into tracked manifest.json"
```

### Task 5: `harness-manifest.py apply` — register marketplace, enable plugins, connector checklist

**Files:**
- Modify: `scripts/utils/harness-manifest.py` (add `cmd_apply`)
- Modify: `scripts/setup/link-claude.sh` (call `apply` after symlinking)
- Create: `claude/harness/marketplace/.claude-plugin/marketplace.json`
- Test: `tests/harness.bats`

**Interfaces:**
- Consumes: `manifest.json` (`enabledPlugins`, `connectors`), `marketplace/.claude-plugin/marketplace.json`.
- Produces: `python3 harness-manifest.py apply --claude-home H --repo R [--dry-run]` — registers the local marketplace in `H/plugins/known_marketplaces.json` (skip-if-present), sets each manifest `enabledPlugins` key `true` in `H/settings.json` (additive, backs up first), prints `⚠ enable '<name>' via <reenable>` for each connector. Exit 0.

- [ ] **Step 1: Seed the local marketplace descriptor**

Create `claude/harness/marketplace/.claude-plugin/marketplace.json` (use the shape confirmed in Task 3):
```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "henry-harness",
  "description": "Henry's custom harness plugins (local, dotfiles-tracked).",
  "owner": { "name": "Henry" },
  "plugins": []
}
```

- [ ] **Step 2: Write the failing test**

```bash
@test "manifest apply: registers marketplace, enables plugins, lists connectors" {
  mkdir -p "$HOME/.claude/plugins"
  printf '{}\n' > "$HOME/.claude/plugins/known_marketplaces.json"
  printf '{"enabledPlugins":{"existing@mkt":true}}\n' > "$HOME/.claude/settings.json"
  cat > "$DF/claude/harness/manifest.json" <<'JSON'
{"version":1,"enabledPlugins":{"code-review@claude-plugins-official":true},
 "connectors":[{"name":"vault-os","reenable":"claude.ai → Settings → Connectors"}]}
JSON
  run python3 "$BATS_TEST_DIRNAME/../scripts/utils/harness-manifest.py" apply --claude-home "$HOME/.claude" --repo "$DF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"vault-os"* ]]                                   # connector checklist
  grep -q "henry-harness" "$HOME/.claude/plugins/known_marketplaces.json"  # marketplace registered
  run python3 -c "import json;s=json.load(open('$HOME/.claude/settings.json'));print(s['enabledPlugins'].get('existing@mkt'),s['enabledPlugins'].get('code-review@claude-plugins-official'))"
  [[ "$output" == "True True" ]]                                   # additive: old + new
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `bats tests/harness.bats -f "manifest apply"`
Expected: FAIL — `apply: not implemented`.

- [ ] **Step 4: Implement `cmd_apply`**

In `scripts/utils/harness-manifest.py`, replace the dispatch dict and add the function:
```python
def cmd_apply(a):
    manifest = _load(os.path.join(a.repo, "claude", "harness", "manifest.json"),
                     {"enabledPlugins": {}, "connectors": []})
    # 1. Register local marketplace (skip-if-present).
    mkt_dir = os.path.join(a.repo, "claude", "harness", "marketplace")
    mkt_json = os.path.join(mkt_dir, ".claude-plugin", "marketplace.json")
    if os.path.exists(mkt_json):
        km_path = os.path.join(a.claude_home, "plugins", "known_marketplaces.json")
        km = _load(km_path, {})
        name = _load(mkt_json, {}).get("name", "henry-harness")
        if name not in km:
            km[name] = {"source": {"source": "directory", "path": mkt_dir}}
            _dump(km_path, km, a.dry_run)
            print(f"marketplace: registered {name}")
        else:
            print(f"marketplace: {name} already registered")
    # 2. Enable plugins (additive).
    s_path = os.path.join(a.claude_home, "settings.json")
    settings = _load(s_path, {})
    ep = settings.setdefault("enabledPlugins", {})
    added = [k for k, v in manifest.get("enabledPlugins", {}).items() if ep.get(k) is not True]
    for k in added: ep[k] = True
    if added: _dump(s_path, settings, a.dry_run)
    print(f"enabledPlugins: {len(added)} newly enabled")
    # 3. Connector checklist (cannot auto-wire remote connectors).
    for c in manifest.get("connectors", []):
        print(f"⚠ enable '{c['name']}' via {c.get('reenable','claude.ai connectors')}")
    return 0

def main():
    ...
    a = p.parse_args()
    return {"capture": cmd_capture, "apply": cmd_apply}[a.cmd](a)
```
(Delete the `_unimpl` fallback.)

- [ ] **Step 5: Run to verify it passes**

Run: `bats tests/harness.bats -f "manifest apply"`
Expected: PASS.

- [ ] **Step 6: Wire `apply` into `link-claude.sh`**

Find where `link-claude.sh` finishes symlinking harness items and add, respecting its existing `--dry-run` variable (inspect the script for its dry-run flag name first):
```bash
if command -v python3 >/dev/null 2>&1 && [[ -f "$DOTFILES/scripts/utils/harness-manifest.py" ]]; then
  py_dry=(); [[ "${DRY_RUN:-0}" -eq 1 ]] && py_dry=(--dry-run)
  python3 "$DOTFILES/scripts/utils/harness-manifest.py" apply \
    --claude-home "${CLAUDE_HOME:-$HOME/.claude}" --repo "$DOTFILES" "${py_dry[@]}" || true
fi
```
Adjust `$DOTFILES` / `$DRY_RUN` to the script's actual variable names.

- [ ] **Step 7: Test the wired deploy path**

```bash
@test "deploy: apply step runs and prints the connector checklist" {
  # real link-claude.sh (not the stub) for this test:
  cp "$BATS_TEST_DIRNAME/../scripts/setup/link-claude.sh" "$DF/scripts/setup/link-claude.sh"
  cp "$BATS_TEST_DIRNAME/../scripts/utils/harness-manifest.py" "$DF/scripts/utils/"
  mkdir -p "$HOME/.claude/plugins"; printf '{}\n' > "$HOME/.claude/plugins/known_marketplaces.json"
  printf '{}\n' > "$HOME/.claude/settings.json"
  cat > "$DF/claude/harness/manifest.json" <<'JSON'
{"version":1,"enabledPlugins":{},"connectors":[{"name":"vault-os","reenable":"claude.ai → Settings → Connectors"}]}
JSON
  run env DOTFILES_DIR="$DF" CLAUDE_HOME="$HOME/.claude" bash "$DF/scripts/setup/link-claude.sh"
  [[ "$output" == *"vault-os"* ]]
}
```
Note: this test replaces the `link-claude.sh` stub from `setup()`; if the real script has heavy prerequisites, keep the stub and instead unit-test `apply` directly (Step 2 already does). Prefer the direct `apply` test if the real deployer is not hermetic.

Run: `bats tests/harness.bats`
Expected: PASS (all).

- [ ] **Step 8: Commit**

```bash
git add scripts/utils/harness-manifest.py scripts/setup/link-claude.sh \
        claude/harness/marketplace/.claude-plugin/marketplace.json tests/harness.bats
git commit -m "feat(harness): deploy registers local marketplace + connector checklist"
```

### Task 6: `harness new plugin` → local marketplace shape

**Files:**
- Modify: `scripts/utils/harness.sh` (`harness_new` plugin branch)
- Modify: `claude/harness/_templates/plugin/` → `.claude-plugin/plugin.json`
- Test: `tests/harness.bats` (update the existing plugin-scaffold test)

**Interfaces:**
- Consumes: `TEMPLATES`, `HARNESS`.
- Produces: `harness new plugin <name>` scaffolds `marketplace/<name>/.claude-plugin/plugin.json` and appends `{name, source: "./<name>"}` to `marketplace/.claude-plugin/marketplace.json`.

- [ ] **Step 1: Update the plugin template**

Move `claude/harness/_templates/plugin/plugin.json` → `claude/harness/_templates/plugin/.claude-plugin/plugin.json` with:
```json
{ "name": "__NAME__", "description": "One-line plugin description." }
```

- [ ] **Step 2: Update the failing test** (existing test expects `plugins/qux/plugin.json`)

Replace the plugin assertion in `tests/harness.bats` "new command/agent/plugin…" test:
```bash
  run_h new plugin qux;  [ "$status" -eq 0 ]
  [ -f "$DF/claude/harness/marketplace/qux/.claude-plugin/plugin.json" ]
  grep -q '"name": "qux"' "$DF/claude/harness/marketplace/qux/.claude-plugin/plugin.json"
  grep -q '"source": "./qux"' "$DF/claude/harness/marketplace/.claude-plugin/marketplace.json"
```

- [ ] **Step 3: Run to verify it fails**

Run: `bats tests/harness.bats -f "new command/agent/plugin"`
Expected: FAIL — old path used.

- [ ] **Step 4: Rewrite the plugin branch of `harness_new`**

```bash
    plugin)
      local mroot="$HARNESS/marketplace" mjson
      mjson="$mroot/.claude-plugin/marketplace.json"
      [[ -e "$mroot/$name" ]] && { log_error "already exists: $mroot/$name"; return 1; }
      mkdir -p "$mroot/$name"
      cp -R "$TEMPLATES/plugin/." "$mroot/$name/"
      find "$mroot/$name" -type f -exec sed -i.bak "s/__NAME__/$name/g" {} \; -exec rm -f {}.bak \;
      [[ -f "$mjson" ]] || printf '{"$schema":"https://anthropic.com/claude-code/marketplace.schema.json","name":"henry-harness","description":"Henry'\''s custom harness plugins.","owner":{"name":"Henry"},"plugins":[]}\n' > "$mjson"
      python3 - "$mjson" "$name" <<'PY'
import json,sys
p,n=sys.argv[1],sys.argv[2]
d=json.load(open(p)); d.setdefault("plugins",[])
if not any(x.get("name")==n for x in d["plugins"]):
    d["plugins"].append({"name":n,"source":f"./{n}"})
json.dump(d,open(p,"w"),indent=2); open(p,"a").write("\n")
PY
      log_success "scaffolded plugin: claude/harness/marketplace/$name/ (added to marketplace.json)" ;;
```

- [ ] **Step 5: Run to verify it passes**

Run: `bats tests/harness.bats -f "new command/agent/plugin"`
Expected: PASS.

- [ ] **Step 6: Full suite**

Run: `bats tests/harness.bats`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/utils/harness.sh claude/harness/_templates tests/harness.bats
git commit -m "feat(harness): new plugin scaffolds into local marketplace"
```

---

## Phase 3 — MCP server capture (into `claude/mcp.json`) with redaction

### Task 7: Redact + capture local MCP servers

**Files:**
- Modify: `scripts/utils/harness-manifest.py` (extend `cmd_capture` to read local MCP defs, write `claude/mcp.json`)
- Test: `tests/harness.bats`

**Interfaces:**
- Consumes: `H/../.claude.json` (global `mcpServers`) — path passed as `--user-config`; and `R/claude/mcp.json`.
- Produces: `cmd_capture` also merges local (`command`+`args`) MCP servers into `R/claude/mcp.json` under `mcpServers`, redacting secret-looking `env` values to `${KEY}`. A literal unmappable secret → stderr error + exit 2, nothing written for that server.

- [ ] **Step 1: Add the `--user-config` arg** to both subparsers in `main()`:
```python
        s.add_argument("--user-config", default="")
```

- [ ] **Step 2: Write the failing tests**

```bash
@test "mcp capture: records a local server and redacts a token" {
  printf '{"mcpServers":{"demo":{"command":"npx","args":["-y","x"],"env":{"DEMO_TOKEN":"${DEMO_TOKEN}"}}}}\n' > "$HOME/user.json"
  printf '{"mcpServers":{}}\n' > "$DF/claude/mcp.json"
  printf '{"version":1,"enabledPlugins":{},"connectors":[]}\n' > "$DF/claude/harness/manifest.json"
  printf '{}\n' > "$HOME/.claude/settings.json"
  run python3 "$BATS_TEST_DIRNAME/../scripts/utils/harness-manifest.py" capture \
      --claude-home "$HOME/.claude" --repo "$DF" --user-config "$HOME/user.json"
  [ "$status" -eq 0 ]
  grep -q '"demo"' "$DF/claude/mcp.json"
  grep -q '${DEMO_TOKEN}' "$DF/claude/mcp.json"
}

@test "mcp capture: aborts on a literal secret value" {
  printf '{"mcpServers":{"bad":{"command":"npx","args":[],"env":{"BAD_TOKEN":"sk-literalsecretvalue123456"}}}}\n' > "$HOME/user.json"
  printf '{"mcpServers":{}}\n' > "$DF/claude/mcp.json"
  printf '{"version":1,"enabledPlugins":{},"connectors":[]}\n' > "$DF/claude/harness/manifest.json"
  printf '{}\n' > "$HOME/.claude/settings.json"
  run python3 "$BATS_TEST_DIRNAME/../scripts/utils/harness-manifest.py" capture \
      --claude-home "$HOME/.claude" --repo "$DF" --user-config "$HOME/user.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BAD_TOKEN"* ]]
  run python3 -c "import json;print(len(json.load(open('$DF/claude/mcp.json'))['mcpServers']))"
  [[ "$output" == "0" ]]                               # nothing written
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `bats tests/harness.bats -f "mcp capture"`
Expected: FAIL — `--user-config` unknown / no MCP handling.

- [ ] **Step 4: Extend `cmd_capture`**

Add near the top of `harness-manifest.py`:
```python
import re
_SECRET_KEY = re.compile(r"(TOKEN|KEY|SECRET|PASSWORD|PASS)$", re.I)

def _redact_env(server, warnings):
    env = server.get("env") or {}
    out = {}
    for k, v in env.items():
        if isinstance(v, str) and v.startswith("${") and v.endswith("}"):
            out[k] = v                                   # already a ref
        elif _SECRET_KEY.search(k) or (isinstance(v, str) and len(v) >= 24 and " " not in v):
            # Map to an env ref if the value equals the env var's value; else it's a literal.
            if v == os.environ.get(k):
                out[k] = "${%s}" % k
            else:
                warnings.append(k); out[k] = None
        else:
            out[k] = v
    return out
```
Extend `cmd_capture` before its `return 0`:
```python
    warnings = []
    if a.user_config:
        uc = _load(a.user_config, {})
        servers = {n: s for n, s in uc.get("mcpServers", {}).items() if "command" in s}
        if servers:
            reg_path = os.path.join(a.repo, "claude", "mcp.json")
            reg = _load(reg_path, {"mcpServers": {}})
            reg.setdefault("mcpServers", {})
            for n, s in servers.items():
                new = {"command": s["command"], "args": s.get("args", [])}
                red = _redact_env(s, warnings)
                if s.get("env"): new["env"] = {k: v for k, v in red.items() if v is not None}
                reg["mcpServers"][n] = new
            if warnings:
                print("literal secret(s) in MCP env, refusing to write: " + ", ".join(sorted(set(warnings))), file=sys.stderr)
                return 2
            _dump(reg_path, reg, a.dry_run)
            print(f"mcpServers: {len(servers)} recorded in claude/mcp.json")
```

- [ ] **Step 5: Run to verify they pass**

Run: `bats tests/harness.bats -f "mcp capture"`
Expected: PASS (both).

- [ ] **Step 6: Wire `--user-config` from the engine**

In `harness.sh` `harness_capture`, extend the python capture call:
```bash
      --claude-home "$CLAUDE_DST" --repo "$DOTFILES_DIR" \
      --user-config "$HOME/.claude.json" "${dflag[@]}" || log_warning "manifest capture failed"
```

- [ ] **Step 7: Full suite**

Run: `bats tests/harness.bats`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/utils/harness-manifest.py scripts/utils/harness.sh tests/harness.bats
git commit -m "feat(harness): capture local MCP servers into mcp.json with redaction"
```

### Task 8: Docs + help + shellcheck

**Files:**
- Modify: `claude/harness/README.md`, `scripts/utils/harness.sh` (`--help`)
- Verify: `tests/shellcheck.sh`

**Interfaces:** none (docs).

- [ ] **Step 1: Document capture/marketplace/manifest in README**

Add a "Capture (local → repo)" section to `claude/harness/README.md` covering `claw harness capture [--dry-run]`, the `manifest.json` schema (with the hand-maintained `connectors[]`), the local `marketplace/`, and the "vault-os = connector checklist" behavior. Update the Workflow code block to list `capture`.

- [ ] **Step 2: Update `--help` text** in `harness.sh` `main()`:
```bash
    -h|--help|help) printf "usage: claw harness <new|list|capture|sync|deploy|path>\n" ;;
```
and the `bin/claw` help line at `bin/claw:241` to mention `capture`.

- [ ] **Step 3: Run shellcheck**

Run: `bash tests/shellcheck.sh` (or `shellcheck scripts/utils/harness.sh scripts/setup/link-claude.sh`)
Expected: no new warnings on changed files.

- [ ] **Step 4: Final full suite + manual smoke**

Run: `bats tests/harness.bats`
Expected: all PASS.

Manual smoke (real machine, safe — dry runs first):
```bash
claw harness capture --dry-run     # preview
claw harness capture               # capture for real
git -C ~/.dotfiles status          # review what moved
claw harness deploy --dry-run      # preview apply
```

- [ ] **Step 5: Commit**

```bash
git add claude/harness/README.md scripts/utils/harness.sh bin/claw
git commit -m "docs(harness): document capture, marketplace, and manifest"
```

---

## Self-Review

**Spec coverage:**
- Capture skills/cmds/agents → Tasks 1–2 ✓
- File-based plugins (local marketplace) → Tasks 3, 5, 6 ✓
- MCP server configs → Task 7 ✓ (into `claude/mcp.json`, a refinement over the spec's manifest block — recorded below)
- Marketplace plugin list (enabledPlugins) → Tasks 4–5 ✓
- Remote connectors as re-install manifest → Tasks 4–5 (hand-maintained `connectors[]` + checklist) ✓
- Deploy extension (marketplace/enable/mcp/checklist) → Task 5 (+ Task 7 mcp is capture-side; machine MCP write deferred — see note) ✓
- Dry-run/backups/idempotent/no-secrets → Tasks 1,2,7 + Global Constraints ✓

**Spec deviation (intentional, simpler):** MCP servers are captured into the existing `claude/mcp.json` registry rather than duplicated in `manifest.json`, because the repo already declares `claude/mcp.json` the source of truth for `~/.claude/mcp.json`. The manifest holds only `enabledPlugins` + `connectors`.

**Deferred (flagged, not silently dropped):** *Machine-side* MCP merge (writing captured servers onto a second machine) depends on confirming which file Claude Code reads (`~/.claude.json` vs `~/.claude/mcp.json`) — Task 3-style verification. Phase 3 lands the **capture** half (repo gets the servers, redacted); the deploy-side MCP write is a follow-up once the read surface is confirmed. This keeps Phase 3 shippable without guessing an unverified write target. If desired, add it to `cmd_apply` mirroring the `enabledPlugins` additive-merge pattern.

**Placeholder scan:** none — every code step has real bash/python/bats.

**Type/name consistency:** `harness_capture`, `_capture_one_kind`, `_is_managed`, `_resolve`, `cmd_capture`, `cmd_apply`, `_redact_env`, `_load`, `_dump` are consistent across all tasks. Subcommand names `capture`/`apply` and flags `--claude-home`/`--repo`/`--dry-run`/`--user-config` match between the Python parser and every caller.
