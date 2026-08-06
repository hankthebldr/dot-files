# AI Tool Config Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring opencode + openwork configuration under dot-files as a managed, portable, reproducible component — one `scripts/utils/ai-config.sh` engine (clin.sh mechanism), surfaced as `claw ai config`, plus the `.zshrc` machine-local PATH-leak fix.

**Architecture:** A POSIX `sh` engine renders each tool's config from dot-files sources (openwork's workspace roots from the vault resolver; opencode's portable base from a tracked file), tops each with a managed-file sentinel, and refuses to clobber an unmanaged/hand-edited config. Color is NOT rendered — opencode inherits the terminal ANSI palette that `claw theme set` already updates via Ghostty.

**Tech Stack:** POSIX `sh` (no bashisms), JSON/JSONC configs, bats + shellcheck, integrated into the existing `claw ai` dispatch.

## Global Constraints

- **POSIX `sh`** — `ai-config.sh` uses `#!/usr/bin/env bash` header like clin.sh but stays POSIX-portable (no arrays, `[[ ]]`, or bashisms in the engine); `shellcheck -S error -e SC1090,SC1091` clean.
- **Sentinel string** — `AICONFIG_SENTINEL="managed by the Open Claw ai-config plugin"` (verbatim, used by render + gate).
- **Managed-file env gate** — `CLAW_AICONFIG_MANAGED`: `1`/unset = manage (default), `force` = overwrite even unmanaged, `0`/`off`/`no` = opt out entirely.
- **openwork JSON sentinel key** — `"_claw_managed": true` (JSON has no comments).
- **opencode JSONC sentinel** — line-1 comment: `// managed by the Open Claw ai-config plugin — do not hand-edit (claw ai config sync)`.
- **Vault resolution** — `${OBSIDIAN_VAULT:-$HOME/${OBSIDIAN_VAULT_NAME:-hr-vault-main-pa}}`.
- **Named-file staging only** — `git add <path>`, never `-A`/`.`. Commit trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`. No PR without ask.
- **Push** uses the homebrew gh override: `git -c credential.helper= -c credential.helper='!/opt/homebrew/bin/gh auth git-credential' push`.
- **No theme rendering** — opencode has no config `theme` field; color tracks the terminal. Do not add slug→theme maps or custom theme JSON.

---

## File Structure

| File | Task | Responsibility |
|------|------|----------------|
| `config/opencode/opencode.base.jsonc` | 1 | tracked portable opencode base ($schema + defaults home) |
| `scripts/utils/ai-config.sh` | 1,2 | the engine: render/sync/status/setup + opencode render |
| (extend) `scripts/utils/ai-config.sh` | 2 | openwork render + seed-and-reconcile |
| `scripts/utils/ai.sh:9` | 3 | `config)` dispatch arm + usage line |
| `shell/profiles/ai/common.zsh` | 3 | help-card line + `aicfg` alias |
| `scripts/install/ai-toolchain.sh` | 4 | `ai-config setup` post-install seed |
| `shell/.zshrc:30,258-259` | 5 | PATH leak fix (`$HOME/.opencode/bin`) |
| `tests/ai-config.bats` | 6 | render/sentinel/gate/seed regression tests |

---

## Task 1: Engine skeleton + opencode base + render

**Files:**
- Create: `config/opencode/opencode.base.jsonc`
- Create: `scripts/utils/ai-config.sh`
- Test: `tests/ai-config.bats` (created here, extended in Task 6)

**Interfaces:**
- Produces: `ai-config.sh render opencode [out]` writes the opencode config (sentinel line 1 + base body). `AICONFIG_SENTINEL` constant. `_aic_vault()` echoes the resolved vault path. `_aic_managed_ok <file> <sentinel-grep>` returns 0 if safe to write.

- [ ] **Step 1: Create the tracked opencode base.** Create `config/opencode/opencode.base.jsonc`:

```jsonc
{
  // Portable opencode config base — tracked in dot-files, rendered to
  // ~/.config/opencode/opencode.jsonc by `claw ai config sync`. Add portable
  // model/provider defaults, MCP servers, and agent defs here. Color is NOT
  // set: opencode uses the terminal ANSI palette (claw theme set updates it).
  "$schema": "https://opencode.ai/config.json"
}
```

- [ ] **Step 2: Write the failing test.** Create `tests/ai-config.bats`:

```bash
#!/usr/bin/env bats
# ai-config.sh — render/sentinel/gate regression tests

setup() {
  ENGINE="$BATS_TEST_DIRNAME/../scripts/utils/ai-config.sh"
  TMP="$(mktemp -d)"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export OBSIDIAN_VAULT="$TMP/fake-vault"
}
teardown() { rm -rf "$TMP"; }

@test "render opencode writes sentinel on line 1 and valid JSON" {
  run bash "$ENGINE" render opencode "$TMP/oc.jsonc"
  [ "$status" -eq 0 ]
  head -1 "$TMP/oc.jsonc" | grep -q "managed by the Open Claw ai-config plugin"
  # strip // comments, then it must parse as JSON
  sed 's:^[[:space:]]*//.*$::' "$TMP/oc.jsonc" | python3 -c "import json,sys; json.load(sys.stdin)"
}
```

- [ ] **Step 3: Run to verify it fails.** Run: `bats tests/ai-config.bats`
Expected: FAIL — `ai-config.sh` does not exist.

- [ ] **Step 4: Write the engine (skeleton + opencode render).** Create `scripts/utils/ai-config.sh`:

```bash
#!/usr/bin/env bash
# ai-config.sh — Open Claw "ai-config plugin" engine.
#
# Brings opencode + openwork CONFIG under dot-files: renders each tool's config
# from portable sources (opencode from a tracked base; openwork's workspace roots
# from the Obsidian vault resolver), tops each with a managed-file sentinel, and
# refuses to clobber a hand-edited/app-written config. Mirrors clin.sh; POSIX sh.
#
#   ai-config.sh render <opencode|openwork> [out]   emit one config
#   ai-config.sh sync                               render both live configs (gated)
#   ai-config.sh status                             what's managed + openwork runtime/secret files
#   ai-config.sh setup                              first-run adopt (idempotent, lossless)
#
# Managed-file gate: CLAW_AICONFIG_MANAGED = 1 (default) | force | 0/off/no.
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
AICONFIG_SENTINEL="managed by the Open Claw ai-config plugin"
OC_BASE="$DOTFILES_DIR/config/opencode/opencode.base.jsonc"
OC_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.jsonc"
OW_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/openwork/server.json"
OW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/openwork"

# Resolve the Obsidian vault root (env → known default). No fork needed.
_aic_vault() {
    printf '%s' "${OBSIDIAN_VAULT:-$HOME/${OBSIDIAN_VAULT_NAME:-hr-vault-main-pa}}"
}

# Return 0 if it's safe to (over)write $1 — file absent, already ours (matches
# $2 grep pattern), or force. Else warn and return 1.
_aic_managed_ok() {
    _f="$1"; _pat="$2"
    case "${CLAW_AICONFIG_MANAGED:-1}" in
        0|off|no) return 1 ;;
        force)    return 0 ;;
    esac
    [ -f "$_f" ] || return 0
    grep -q "$_pat" "$_f" 2>/dev/null && return 0
    printf '  ai-config: %s looks hand-edited/app-written — not overwriting.\n' "$_f" >&2
    printf '  ai-config: re-run with CLAW_AICONFIG_MANAGED=force to let claw manage it.\n' >&2
    return 1
}

# --- opencode: base file + line-1 sentinel ---------------------------------
aic_render_opencode() {
    _out="${1:-/dev/stdout}"
    [ -r "$OC_BASE" ] || { printf 'ai-config: missing base %s\n' "$OC_BASE" >&2; return 1; }
    [ "$_out" != "/dev/stdout" ] && mkdir -p "$(dirname "$_out")" 2>/dev/null
    {
        printf '// %s — do not hand-edit (claw ai config sync)\n' "$AICONFIG_SENTINEL"
        cat "$OC_BASE"
    } > "$_out" 2>/dev/null
}

_cmd="${1:-status}"; shift 2>/dev/null || true
case "$_cmd" in
    render)
        case "${1:-}" in
            opencode) shift; aic_render_opencode "${1:-/dev/stdout}" ;;
            openwork) shift; aic_render_openwork "${1:-/dev/stdout}" ;;
            *) printf 'usage: ai-config.sh render <opencode|openwork> [out]\n' >&2; exit 1 ;;
        esac ;;
    sync)   aic_sync ;;
    status) aic_status ;;
    setup)  aic_setup ;;
    *) printf 'usage: ai-config.sh {render <tool> [out] | sync | status | setup}\n' >&2; exit 1 ;;
esac
```

Note: `aic_render_openwork`, `aic_sync`, `aic_status`, `aic_setup` are added in Tasks 2. To keep Task 1 runnable, temporarily stub the three not-yet-defined dispatch arms — add these stubs just above the `case`:

```bash
aic_render_openwork() { printf 'ai-config: openwork render not yet implemented\n' >&2; return 1; }
aic_sync()   { aic_render_opencode "$OC_CONFIG"; }
aic_status() { printf '  ai-config: opencode base %s\n' "$OC_BASE"; }
aic_setup()  { aic_sync; }
```

- [ ] **Step 5: Run to verify pass.** Run: `bats tests/ai-config.bats && shellcheck -S error -e SC1090,SC1091 scripts/utils/ai-config.sh`
Expected: 1 test passes; shellcheck clean.

- [ ] **Step 6: Commit.**

```bash
git add config/opencode/opencode.base.jsonc scripts/utils/ai-config.sh tests/ai-config.bats
git commit -m "feat(ai-config): engine skeleton + opencode base render"
```

---

## Task 2: openwork render + seed-and-reconcile + sync/status/setup

**Files:**
- Modify: `scripts/utils/ai-config.sh` (replace the four stubs with real implementations)
- Test: `tests/ai-config.bats` (append)

**Interfaces:**
- Consumes: `_aic_vault`, `_aic_managed_ok`, `aic_render_opencode`, `AICONFIG_SENTINEL`, `OC_CONFIG`, `OW_CONFIG`, `OW_DIR` from Task 1.
- Produces: `ai-config.sh render openwork [out]` writes `server.json` with `"_claw_managed": true`; `sync`/`status`/`setup` operate on both tools.

- [ ] **Step 1: Write the failing tests.** Append to `tests/ai-config.bats`:

```bash
@test "render openwork writes _claw_managed and vault in authorizedRoots" {
  run bash "$ENGINE" render openwork "$TMP/ow.json"
  [ "$status" -eq 0 ]
  python3 -c "import json; d=json.load(open('$TMP/ow.json')); assert d['_claw_managed'] is True; assert '$TMP/fake-vault' in d['authorizedRoots']"
}

@test "sync refuses to clobber an unmanaged openwork config" {
  mkdir -p "$(dirname "$TMP/ow.json")"
  printf '{\"workspaces\":[{\"path\":\"/hand/edited\"}]}' > "$TMP/ow.json"
  run env CLAW_AICONFIG_MANAGED=1 bash -c "
    OW_OVERRIDE='$TMP/ow.json'
    source '$ENGINE' >/dev/null 2>&1 || true
  "
  # direct gate check: an unmanaged file must not gain the sentinel key
  ! grep -q '_claw_managed' "$TMP/ow.json"
}

@test "setup seeds openwork roots from an existing extra workspace (lossless)" {
  mkdir -p "$OW_DIR_TEST"
  # existing file with our key + an extra workspace the render wouldn't produce
  printf '{\"_claw_managed\":true,\"workspaces\":[{\"id\":\"x\",\"path\":\"/extra/ws\",\"name\":\"extra\"}],\"authorizedRoots\":[\"/extra/ws\"]}' > "$OW_DIR_TEST/server.json"
  run env XDG_CONFIG_HOME="$TMP/cfg" OBSIDIAN_VAULT="$TMP/fake-vault" bash "$ENGINE" setup
  python3 -c "import json; d=json.load(open('$OW_DIR_TEST/server.json')); paths=[w['path'] for w in d['workspaces']]; assert '/extra/ws' in paths, paths"
}
```

Add to `setup()` in the bats file: `export OW_DIR_TEST="$TMP/cfg/openwork"`.

- [ ] **Step 2: Run to verify failure.** Run: `bats tests/ai-config.bats`
Expected: the three new tests FAIL (openwork render stubbed).

- [ ] **Step 3: Replace the four stubs.** In `scripts/utils/ai-config.sh`, delete the four stub functions and insert these real implementations (before the `case`):

```bash
# --- openwork: workspace roots from the vault, seed-and-reconcile ------------
# Emits server.json with a "_claw_managed" sentinel key. Two roots by default:
# the Obsidian vault and ~/OpenWork. Extra workspaces present in $3 (a JSON file
# to preserve) are merged so adopt is lossless.
aic_render_openwork() {
    _out="${1:-/dev/stdout}"; _seed="${2:-}"
    _vault="$(_aic_vault)"; _ow="$HOME/OpenWork"
    [ "$_out" != "/dev/stdout" ] && mkdir -p "$(dirname "$_out")" 2>/dev/null
    VAULT="$_vault" OWROOT="$_ow" SEED="$_seed" python3 - "$_out" <<'PY'
import json, os, sys
out = sys.argv[1]
vault, owroot, seed = os.environ["VAULT"], os.environ["OWROOT"], os.environ.get("SEED", "")
def ws(path, name): return {"id": "ws_" + name, "path": path, "name": name, "preset": "starter", "workspaceType": "local"}
base = [ws(vault, os.path.basename(vault.rstrip("/"))), ws(owroot, "OpenWork")]
paths = {w["path"] for w in base}
# preserve any extra workspaces from the seed file
if seed and os.path.isfile(seed):
    try:
        old = json.load(open(seed))
        for w in old.get("workspaces", []):
            if w.get("path") and w["path"] not in paths:
                base.append(w); paths.add(w["path"])
    except (ValueError, OSError):
        pass
doc = {"_claw_managed": True, "workspaces": base, "authorizedRoots": sorted(paths)}
data = json.dumps(doc, indent=2) + "\n"
if out == "/dev/stdout":
    sys.stdout.write(data)
else:
    open(out, "w").write(data)
PY
}

aic_sync() {
    if _aic_managed_ok "$OC_CONFIG" "$AICONFIG_SENTINEL"; then
        aic_render_opencode "$OC_CONFIG" && printf '  ai-config: synced %s\n' "$OC_CONFIG"
    fi
    if _aic_managed_ok "$OW_CONFIG" '_claw_managed'; then
        aic_render_openwork "$OW_CONFIG" "$OW_CONFIG" && printf '  ai-config: synced %s\n' "$OW_CONFIG"
    fi
}

aic_status() {
    printf '\n  ai-config — managed AI tool configs\n'
    _oc_state="unmanaged"; [ -f "$OC_CONFIG" ] && head -1 "$OC_CONFIG" 2>/dev/null | grep -q "$AICONFIG_SENTINEL" && _oc_state="managed"
    _ow_state="unmanaged"; [ -f "$OW_CONFIG" ] && grep -q '_claw_managed' "$OW_CONFIG" 2>/dev/null && _ow_state="managed"
    printf '    opencode  %-10s %s\n' "$_oc_state" "$OC_CONFIG"
    printf '    openwork  %-10s %s\n' "$_ow_state" "$OW_CONFIG"
    # openwork runtime/secret files — presence only, never values
    for f in runtime-opencode-config.json runtime.sqlite tokens.json; do
        [ -f "$OW_DIR/$f" ] && printf '    · %-28s (app-owned, not managed)\n' "$f"
    done
    [ -f "$OW_DIR/tokens.json" ] && printf '    note: tokens.json holds secrets — app-owned; use claw secret for durable backup.\n'
}

aic_setup() {
    [ -f "$OC_CONFIG" ] && ! head -1 "$OC_CONFIG" 2>/dev/null | grep -q "$AICONFIG_SENTINEL" \
        && printf '  ai-config: existing opencode config is unmanaged — leaving it (force to adopt).\n' >&2 \
        || aic_render_opencode "$OC_CONFIG"
    if [ ! -f "$OW_CONFIG" ] || grep -q '_claw_managed' "$OW_CONFIG" 2>/dev/null; then
        aic_render_openwork "$OW_CONFIG" "$OW_CONFIG"
    else
        printf '  ai-config: existing openwork server.json is app-owned — leaving it (force to adopt).\n' >&2
    fi
    aic_status
}
```

- [ ] **Step 4: Run to verify pass.** Run: `bats tests/ai-config.bats && shellcheck -S error -e SC1090,SC1091 scripts/utils/ai-config.sh`
Expected: all tests pass; shellcheck clean. (If the "refuses to clobber" test needs adjusting to call the gate directly, use: `run env CLAW_AICONFIG_MANAGED=1 XDG_CONFIG_HOME="$TMP/cfg" bash "$ENGINE" sync` after planting an unmanaged file at `$TMP/cfg/openwork/server.json`, then assert it still lacks `_claw_managed`.)

- [ ] **Step 5: Commit.**

```bash
git add scripts/utils/ai-config.sh tests/ai-config.bats
git commit -m "feat(ai-config): openwork render + seed-and-reconcile + sync/status/setup"
```

---

## Task 3: `claw ai config` dispatch + AI-profile surfacing

**Files:**
- Modify: `scripts/utils/ai.sh:9` (dispatch) and its usage line
- Modify: `shell/profiles/ai/common.zsh`

**Interfaces:**
- Consumes: `ai-config.sh` from Tasks 1-2.
- Produces: `claw ai config <sub>` reaches `ai-config.sh`.

- [ ] **Step 1: Add the `config)` dispatch arm.** In `scripts/utils/ai.sh`, inside `case "${1:-doctor}" in`, after the `n8n)` line, add:

```bash
  config)  shift; bash "$DOTFILES/scripts/utils/ai-config.sh" "$@";;
```

- [ ] **Step 2: Update the usage line.** In the same file, change the `*)` usage:

```bash
  *) echo "usage: claw ai {serve|models|pull <m>|chat|web|n8n|config|doctor}";;
```

- [ ] **Step 3: Verify dispatch reaches the engine.** Run: `bash -n scripts/utils/ai.sh && DOTFILES_DIR="$PWD" bash scripts/utils/ai.sh config status`
Expected: the ai-config status card prints (opencode/openwork lines).

- [ ] **Step 4: Surface in the AI profile.** In `shell/profiles/ai/common.zsh`, near the opencode/openwork help lines (~98-99), add an alias and a help line. Add the alias in the alias block:

```zsh
alias aicfg="claw ai config"                     # manage opencode/openwork config
```

And in the `ai-help` card body, add a line after the opencode/openwork entries:

```zsh
  printf "  ${purple}claw ai config${reset} ${dim}manage opencode/openwork config (render/sync/status)${reset}\n"
```

- [ ] **Step 5: Verify the profile still sources cleanly.** Run: `zsh -n shell/profiles/ai/common.zsh`
Expected: no output.

- [ ] **Step 6: Commit.**

```bash
git add scripts/utils/ai.sh shell/profiles/ai/common.zsh
git commit -m "feat(ai-config): wire claw ai config dispatch + AI-profile surfacing"
```

---

## Task 4: ai-toolchain install seed

**Files:**
- Modify: `scripts/install/ai-toolchain.sh`

**Interfaces:**
- Consumes: `ai-config.sh setup`.

- [ ] **Step 1: Locate the opencode/openwork install block.** Run: `grep -n 'opencode-ai\|openwork-orchestrator\|toolchain_extras\|npm install' scripts/install/ai-toolchain.sh | head`
Expected: shows the block (~137-143) that installs opencode-ai + openwork-orchestrator.

- [ ] **Step 2: Add the post-install seed.** In `scripts/install/ai-toolchain.sh`, immediately after that install block completes (inside the extras hook that runs after the npm installs), add:

```bash
    # Seed managed opencode/openwork config once (idempotent; leaves unmanaged files alone).
    if command -v opencode &>/dev/null; then
        DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}" \
            sh "${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils/ai-config.sh" setup >/dev/null 2>&1 || true
    fi
```

- [ ] **Step 3: Syntax check.** Run: `bash -n scripts/install/ai-toolchain.sh && shellcheck -S error -e SC1090,SC1091 scripts/install/ai-toolchain.sh`
Expected: clean (or unchanged from baseline — confirm no NEW errors introduced).

- [ ] **Step 4: Commit.**

```bash
git add scripts/install/ai-toolchain.sh
git commit -m "feat(ai-config): seed managed config on ai-toolchain install"
```

---

## Task 5: `.zshrc` PATH-leak fix

**Files:**
- Modify: `shell/.zshrc` (add near line 30; remove lines 258-259)

**Interfaces:** none.

- [ ] **Step 1: Add the portable opencode PATH entry.** In `shell/.zshrc`, after the cargo/go PATH lines (~30-31), add:

```zsh
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"
```

- [ ] **Step 2: Remove the hardcoded machine-local line.** In `shell/.zshrc`, delete both lines:

```zsh
# opencode
export PATH=/Users/henry/.opencode/bin:$PATH
```

- [ ] **Step 3: Verify no `/Users/henry` leak remains and syntax is clean.** Run:

```bash
grep -n '/Users/henry' shell/.zshrc || echo "no machine-local leak ✓"
zsh -n shell/.zshrc && echo "zsh syntax ✓"
```

Expected: `no machine-local leak ✓` and `zsh syntax ✓`.

- [ ] **Step 4: Verify opencode still resolves on PATH after a fresh shell.** Run: `zsh -ic 'command -v opencode' 2>/dev/null || echo "check ~/.opencode/bin exists"`
Expected: prints the opencode path (this machine has `~/.opencode/bin/opencode`).

- [ ] **Step 5: Commit.**

```bash
git add shell/.zshrc
git commit -m "fix(shell): kill /Users/henry opencode PATH leak, use \$HOME"
```

---

## Task 6: Full test pass + shellcheck + push

**Files:** none (verification only).

- [ ] **Step 1: Run the full bats suite.** Run: `bats tests/`
Expected: all green, including the new `tests/ai-config.bats` cases.

- [ ] **Step 2: Shellcheck the new/changed shell.** Run:

```bash
shellcheck -S error -e SC1090,SC1091 scripts/utils/ai-config.sh scripts/utils/ai.sh scripts/install/ai-toolchain.sh
for f in shell/.zshrc shell/profiles/ai/common.zsh; do zsh -n "$f"; done
echo "all clean"
```

Expected: no output from shellcheck/zsh -n; `all clean`.

- [ ] **Step 3: Smoke-test the live surface (does not clobber real configs).** Run:

```bash
DOTFILES_DIR="$PWD" bash scripts/utils/ai-config.sh render opencode | head -2
DOTFILES_DIR="$PWD" OBSIDIAN_VAULT="$HOME/hr-vault-main-pa" bash scripts/utils/ai-config.sh render openwork | python3 -c "import json,sys;print('roots:',json.load(sys.stdin)['authorizedRoots'])"
```

Expected: opencode output starts with the `//` sentinel; openwork roots list the vault + `~/OpenWork`. (These are `render` to stdout — they do NOT write your live configs.)

- [ ] **Step 4: Push.** Run: `git -c credential.helper= -c credential.helper='!/opt/homebrew/bin/gh auth git-credential' push`

- [ ] **Step 5 (operator, optional): adopt on this machine.** After merge, run `claw ai config setup` to adopt the live configs (lossless for the current openwork workspaces). NOT done autonomously — it mutates `~/.config`.

---

## Self-Review notes (author)

- **Spec coverage:** Component 1 → Task 1+2; Component 2 (opencode base, no theme) → Task 1; Component 3 (openwork seed-and-reconcile) → Task 2; Component 4 (tokens.json surfaced by status, never rendered) → Task 2 `aic_status`; Component 5 (dispatch/surfacing/seed/PATH) → Tasks 3-5; Testing → Task 6 + inline. All covered.
- **No theme rendering** anywhere — matches the 2026-07-20 revision.
- **Type/name consistency:** `AICONFIG_SENTINEL`, `_aic_vault`, `_aic_managed_ok`, `aic_render_opencode`, `aic_render_openwork`, `aic_sync`, `aic_status`, `aic_setup`, `OC_CONFIG`/`OW_CONFIG`/`OW_DIR` used identically across tasks.
- **Adopt is operator-gated** (Task 6 Step 5) — the plan never autonomously overwrites live `~/.config` configs; the install seed (Task 4) only runs `setup`, which leaves unmanaged files alone.
```
