# Harness Tooling Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `claw harness` scaffold any tool type, list tools richly, and sync across machines — via a new `scripts/utils/harness.sh` engine, with `bin/claw` reduced to a thin dispatcher.

**Architecture:** Extract all `harness` logic into `scripts/utils/harness.sh` (a standalone script invoked as `bash harness.sh <subcommand> [args]`, matching the `mcp-manager.sh`/`tunnel-manager.sh` engine pattern). `bin/claw cmd_harness` becomes `bash "$DOTFILES/scripts/utils/harness.sh" "$@"`. Templates for all four tool kinds live in `claude/harness/_templates/` (the `_` prefix keeps the deployer from linking them).

**Tech Stack:** Bash (engine), bats (tests), git (sync), `sed`/`awk` (templating + frontmatter parsing). Reuses `scripts/utils/logger.sh` and `scripts/setup/link-claude.sh`.

## Global Constraints

- Shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, guard tools with `command -v`. (verbatim repo convention)
- Output via `scripts/utils/logger.sh` (`log_info`/`log_success`/`log_warning`/`log_error`); no raw `echo` for status lines.
- Cross-platform: no raw `pbcopy`/`open`/`ipconfig`; `sed -i` must use the `sed -i.bak … && rm` form (BSD + GNU safe).
- `_`-prefixed dirs under `claude/harness/` are scaffolding and MUST be skipped by `link-claude.sh` (already true).
- Back-compat: existing `claw harness new <name>` (no kind → skill), `list`, `deploy`, `path` keep working.
- `bin/claw` stays a thin dispatcher — no business logic in `cmd_harness`.
- Engine resolves its own root: `DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"`; deploy target `CLAUDE_DST="${CLAUDE_HOME:-$HOME/.claude}"`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/utils/harness.sh` | **new** engine — `new`/`list`/`sync`/`deploy`/`path` dispatch + helpers |
| `bin/claw` | `cmd_harness` (lines 931–983) → one-line dispatch to the engine |
| `claude/harness/_templates/SKILL.md` | **moved** from `skills/_template/SKILL.md`, placeholder → `__NAME__` |
| `claude/harness/_templates/command.md` | **new** slash-command template |
| `claude/harness/_templates/agent.md` | **new** subagent template |
| `claude/harness/_templates/plugin/{plugin.json,README.md}` | **new** plugin skeleton |
| `tests/harness.bats` | **new** bats tests |
| `claude/harness/README.md` | document `new <kind>`, `list --all/--fzf`, `sync` |
| `docs/claw.md` | refresh the `claw harness` reference line |

---

### Task 1: Templates for all four tool kinds

**Files:**
- Create: `claude/harness/_templates/SKILL.md` (moved from `claude/harness/skills/_template/SKILL.md`)
- Create: `claude/harness/_templates/command.md`
- Create: `claude/harness/_templates/agent.md`
- Create: `claude/harness/_templates/plugin/plugin.json`
- Create: `claude/harness/_templates/plugin/README.md`
- Delete: `claude/harness/skills/_template/` (empty after the move)

**Interfaces:**
- Produces: a `_templates/` dir whose files all use the literal token `__NAME__` wherever the tool's name belongs. The engine (Task 2) substitutes `__NAME__` via `sed`.

- [ ] **Step 1: Move the skill template and switch its placeholder**

```bash
mkdir -p claude/harness/_templates
git mv claude/harness/skills/_template/SKILL.md claude/harness/_templates/SKILL.md
rmdir claude/harness/skills/_template 2>/dev/null || true
```

Then edit `claude/harness/_templates/SKILL.md` so line 2 reads `name: __NAME__` and the `# My Skill` heading becomes `# __NAME__`:

```markdown
---
name: __NAME__
description: >-
  Use when … (one-line trigger: name the task, its inputs, and the situation it
  applies to). This sentence is what the model reads to decide whether to load
  the skill.
---

# __NAME__

> Keep this tight — long or reference-heavy detail goes in `references/` files the
> model opens only when needed (progressive disclosure).

## When to use

- The concrete situations this skill handles.
- And the ones it explicitly does NOT — steer the model elsewhere.

## How it works

1. Step-by-step of what the model does when this skill fires.
2. Reference helper files like `references/DETAIL.md` instead of inlining everything.

## Examples

One worked example: input → action → output.
```

- [ ] **Step 2: Create the command template**

`claude/harness/_templates/command.md`:

```markdown
---
description: One-line description of the /__NAME__ command — this is its trigger.
---

Do <X> for the current context. The user's input is in `$ARGUMENTS`.

Steps:

1. …
2. …

Output: <what the command should produce>.
```

- [ ] **Step 3: Create the agent template**

`claude/harness/_templates/agent.md`:

```markdown
---
name: __NAME__
description: Use this agent when … (what should trigger delegation to it).
tools: Read, Grep, Glob, Bash
---

You are <role>. Your job is to <single clear responsibility>.

When invoked:

1. …
2. …

Return to the caller: <exactly what this subagent reports back>.
```

- [ ] **Step 4: Create the plugin skeleton**

`claude/harness/_templates/plugin/plugin.json`:

```json
{
  "name": "__NAME__",
  "description": "One-line plugin description.",
  "version": "0.1.0"
}
```

`claude/harness/_templates/plugin/README.md`:

```markdown
# __NAME__ plugin

Describe what this plugin bundles (commands, agents, MCP servers, hooks) and how to
register it. Plugins are **referenced, not auto-linked** by `claw harness deploy` —
wire it up via its own manifest.
```

- [ ] **Step 5: Verify the deployer still skips `_templates`**

Run: `DRY_RUN=1 bash scripts/setup/link-claude.sh | grep -i _templates || echo "skipped ok"`
Expected: prints `skipped ok` (the `_`-prefixed dir is never linked).

- [ ] **Step 6: Commit**

```bash
git add claude/harness/_templates
git rm -r --cached claude/harness/skills/_template 2>/dev/null || true
git add -A claude/harness/skills/_template
git commit -m "feat(harness): templates for skill/command/agent/plugin in _templates/"
```

---

### Task 2: `harness.sh` engine — dispatch, `new <kind>`, `path`, `deploy`, basic `list`

**Files:**
- Create: `scripts/utils/harness.sh`
- Create: `tests/harness.bats`

**Interfaces:**
- Consumes: templates from Task 1 (`$TEMPLATES/SKILL.md`, `command.md`, `agent.md`, `plugin/`).
- Produces (functions other tasks extend): `harness_new`, `harness_list`, `harness_deploy`, `harness_path`, and the `main` dispatch. `_scaffold_file <tpl> <dest> <name>` and `_valid_name <name>` helpers. Env contract: `DOTFILES_DIR`, `CLAUDE_HOME`/`CLAUDE_DST`, `HARNESS="$DOTFILES_DIR/claude/harness"`, `TEMPLATES="$HARNESS/_templates"`.

- [ ] **Step 1: Write the failing test file**

`tests/harness.bats`:

```bash
#!/usr/bin/env bats
# Tests for the `claw harness` engine (scripts/utils/harness.sh).

setup() {
  export DF="$BATS_TEST_TMPDIR/df"
  mkdir -p "$DF/scripts/utils" "$DF/scripts/setup" \
           "$DF/claude/harness/"{skills,commands,agents,plugins,_templates}
  cp "$BATS_TEST_DIRNAME/../scripts/utils/harness.sh" "$DF/scripts/utils/"
  cp "$BATS_TEST_DIRNAME/../scripts/utils/logger.sh"  "$DF/scripts/utils/"
  cp -R "$BATS_TEST_DIRNAME/../claude/harness/_templates/." "$DF/claude/harness/_templates/"
  printf '#!/usr/bin/env bash\necho "LINK_CLAUDE_RAN $*"\n' > "$DF/scripts/setup/link-claude.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/"{skills,commands,agents,plugins}
  export H="$DF/scripts/utils/harness.sh"
}

run_h() { run env DOTFILES_DIR="$DF" bash "$H" "$@"; }

@test "new skill: bare name defaults to skill and substitutes __NAME__" {
  run_h new foo
  [ "$status" -eq 0 ]
  [ -f "$DF/claude/harness/skills/foo/SKILL.md" ]
  grep -q "^name: foo$" "$DF/claude/harness/skills/foo/SKILL.md"
}

@test "new command/agent/plugin each scaffold the right file" {
  run_h new command bar; [ "$status" -eq 0 ]; [ -f "$DF/claude/harness/commands/bar.md" ]
  run_h new agent baz;   [ "$status" -eq 0 ]; [ -f "$DF/claude/harness/agents/baz.md" ]
  grep -q "^name: baz$" "$DF/claude/harness/agents/baz.md"
  run_h new plugin qux;  [ "$status" -eq 0 ]; [ -f "$DF/claude/harness/plugins/qux/plugin.json" ]
  grep -q '"name": "qux"' "$DF/claude/harness/plugins/qux/plugin.json"
}

@test "new: refuses to clobber an existing tool" {
  run_h new foo; [ "$status" -eq 0 ]
  run_h new foo; [ "$status" -ne 0 ]; [[ "$output" == *"already exists"* ]]
}

@test "new: rejects an invalid name" {
  run_h new "bad name/with slash"
  [ "$status" -ne 0 ]; [[ "$output" == *"invalid name"* ]]
}

@test "path: prints the harness root" {
  run_h path
  [ "$status" -eq 0 ]; [[ "$output" == *"/claude/harness"* ]]
}

@test "deploy: delegates to link-claude.sh" {
  run_h deploy --dry-run
  [ "$status" -eq 0 ]; [[ "$output" == *"LINK_CLAUDE_RAN --dry-run"* ]]
}

@test "list: shows a scaffolded skill with a not-deployed marker" {
  run_h new foo
  run_h list
  [ "$status" -eq 0 ]; [[ "$output" == *"foo"* ]]; [[ "$output" == *"○"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/harness.bats`
Expected: all fail (e.g. `cp: .../harness.sh: No such file or directory` / non-zero) — `harness.sh` does not exist yet.

- [ ] **Step 3: Write `scripts/utils/harness.sh`**

```bash
#!/usr/bin/env bash
# scripts/utils/harness.sh — engine for `claw harness`.
# bin/claw cmd_harness is a thin dispatcher: `bash harness.sh "$@"`.
# Subcommands: new <kind> <name> | list [--all] [--fzf] | sync [--dry-run]
#            | deploy [--dry-run] | path
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
HARNESS="$DOTFILES_DIR/claude/harness"
TEMPLATES="$HARNESS/_templates"
CLAUDE_DST="${CLAUDE_HOME:-$HOME/.claude}"

if [[ -f "$DOTFILES_DIR/scripts/utils/logger.sh" ]]; then
  # shellcheck disable=SC1091
  source "$DOTFILES_DIR/scripts/utils/logger.sh"
else
  log_info(){ printf '  • %s\n' "$*"; }
  log_success(){ printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
  log_warning(){ printf '  ! %s\n' "$*" >&2; }
  log_error(){ printf '  \033[0;31m✗\033[0m %s\n' "$*" >&2; }
fi

_valid_name(){ [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]]; }

# _scaffold_file <template> <dest> <name> — copy a template, substitute __NAME__.
_scaffold_file(){
  local tpl="$1" dest="$2" name="$3"
  [[ -f "$tpl" ]] || { log_error "template missing: $tpl"; return 1; }
  [[ -e "$dest" ]] && { log_error "already exists: $dest"; return 1; }
  mkdir -p "$(dirname "$dest")"
  sed "s/__NAME__/$name/g" "$tpl" > "$dest"
}

harness_new(){
  local kind name
  if [[ $# -eq 1 ]]; then kind="skill"; name="$1"
  elif [[ $# -ge 2 ]]; then kind="$1"; name="$2"
  else log_error "usage: claw harness new [skill|command|agent|plugin] <name>"; return 1; fi
  _valid_name "$name" || { log_error "invalid name: '$name' (use [a-zA-Z0-9._-])"; return 1; }
  case "$kind" in
    skill)
      [[ -e "$HARNESS/skills/$name" ]] && { log_error "already exists: $HARNESS/skills/$name"; return 1; }
      _scaffold_file "$TEMPLATES/SKILL.md" "$HARNESS/skills/$name/SKILL.md" "$name" || return 1
      log_success "scaffolded skill: claude/harness/skills/$name/SKILL.md" ;;
    command)
      _scaffold_file "$TEMPLATES/command.md" "$HARNESS/commands/$name.md" "$name" || return 1
      log_success "scaffolded command: claude/harness/commands/$name.md" ;;
    agent)
      _scaffold_file "$TEMPLATES/agent.md" "$HARNESS/agents/$name.md" "$name" || return 1
      log_success "scaffolded agent: claude/harness/agents/$name.md" ;;
    plugin)
      [[ -e "$HARNESS/plugins/$name" ]] && { log_error "already exists: $HARNESS/plugins/$name"; return 1; }
      cp -R "$TEMPLATES/plugin" "$HARNESS/plugins/$name"
      find "$HARNESS/plugins/$name" -type f -exec sed -i.bak "s/__NAME__/$name/g" {} \; -exec rm -f {}.bak \;
      log_success "scaffolded plugin: claude/harness/plugins/$name/ (register manually)" ;;
    *)
      log_error "unknown kind: '$kind' (skill|command|agent|plugin)"; return 1 ;;
  esac
  log_info "edit it, then: claw harness deploy"
}

# Basic listing — names + deploy state. Enriched in a later task.
harness_list(){
  printf "\n  Custom agentic harness (%s)\n\n" "$HARNESS"
  local kind dir e name found
  for kind in skills commands agents plugins; do
    dir="$HARNESS/$kind"; printf "  %s\n" "$kind"; found=0
    if [[ -d "$dir" ]]; then
      while IFS= read -r e; do
        name="$(basename "$e")"; [[ "$name" == _* || "$name" == .* ]] && continue
        found=1
        if [[ -e "$CLAUDE_DST/$kind/$name" || -e "$CLAUDE_DST/$kind/${name%.md}" ]]; then
          printf "    ✓ %s\n" "$name"
        else
          printf "    ○ %s\n" "$name"
        fi
      done < <(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | sort)
    fi
    [[ $found -eq 0 ]] && printf "    (none yet)\n"
  done
}

harness_deploy(){ bash "$DOTFILES_DIR/scripts/setup/link-claude.sh" "$@"; }
harness_path(){ echo "$HARNESS"; }

main(){
  local sub="${1:-list}"; shift || true
  case "$sub" in
    new)          harness_new "$@" ;;
    list|ls)      harness_list "$@" ;;
    deploy|link)  harness_deploy "$@" ;;
    path)         harness_path ;;
    -h|--help|help) printf "usage: claw harness <new|list|sync|deploy|path>\n" ;;
    *) log_error "unknown: claw harness $sub"
       printf "  subcommands: new <kind> <name> · list · sync · deploy · path\n"; return 1 ;;
  esac
}
main "$@"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/harness.bats`
Expected: all 7 tests PASS.

- [ ] **Step 5: Syntax check**

Run: `bash -n scripts/utils/harness.sh && echo ok`
Expected: `ok`

- [ ] **Step 6: Commit**

```bash
git add scripts/utils/harness.sh tests/harness.bats
git commit -m "feat(harness): harness.sh engine — new <kind>, path, deploy, basic list"
```

---

### Task 3: Wire `bin/claw cmd_harness` to the engine

**Files:**
- Modify: `bin/claw` (the `cmd_harness()` body, currently lines ~931–983)

**Interfaces:**
- Consumes: `scripts/utils/harness.sh main` (Task 2). `bin/claw` already exposes `$DOTFILES`.
- Produces: `claw harness <args>` routes verbatim to the engine.

- [ ] **Step 1: Write the failing test (append to `tests/harness.bats`)**

```bash
@test "claw harness: routes new/list/path through the engine" {
  cp "$BATS_TEST_DIRNAME/../bin/claw" "$DF/bin-claw" 2>/dev/null || true
  run env DOTFILES_DIR="$DF" bash "$BATS_TEST_DIRNAME/../bin/claw" harness new skill plumbed
  [ "$status" -eq 0 ]
  [ -f "$DF/claude/harness/skills/plumbed/SKILL.md" ]
  run env DOTFILES_DIR="$DF" bash "$BATS_TEST_DIRNAME/../bin/claw" harness path
  [[ "$output" == *"/claude/harness"* ]]
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bats tests/harness.bats -f "routes new/list/path"`
Expected: FAIL — the old inline `cmd_harness` writes to `$DOTFILES/claude/harness` but does not know `new <kind>` and may not honor the temp `_templates`.

- [ ] **Step 3: Replace the `cmd_harness` body in `bin/claw`**

Replace the entire `cmd_harness()` function (keep the `# HARNESS …` banner comment above it) with:

```bash
cmd_harness() {
    bash "$DOTFILES/scripts/utils/harness.sh" "$@"
}
```

- [ ] **Step 4: Run the harness test + the existing claw suite**

Run: `bats tests/harness.bats && bats tests/claw.bats`
Expected: all PASS (no regression in `claw.bats`).

- [ ] **Step 5: Smoke-test against the real repo (read-only)**

Run: `bash bin/claw harness list`
Expected: the real harness listing renders (your 5 captured skills under `skills`, `(none yet)` under commands/agents/plugins).

- [ ] **Step 6: Commit**

```bash
git add bin/claw tests/harness.bats
git commit -m "refactor(claw): cmd_harness is now a thin dispatch to harness.sh"
```

---

### Task 4: Rich discovery — descriptions, `--all`, `--fzf`

**Files:**
- Modify: `scripts/utils/harness.sh` (replace `harness_list`, add `_desc`)
- Modify: `tests/harness.bats` (add description tests)

**Interfaces:**
- Consumes: scaffolded tools (Task 2). `claw_theme_fzf` if present (optional; plain `fzf` fallback).
- Produces: `_desc <file>` → one-line frontmatter description; `harness_list [--all] [--fzf]`.

- [ ] **Step 1: Write the failing tests (append to `tests/harness.bats`)**

```bash
@test "list: shows the skill's description, not just its name" {
  run_h new foo
  run_h list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Use when"* ]]   # from the template description
}

@test "list --all: also walks claude/skills and claude/agent-skills" {
  mkdir -p "$DF/claude/skills/sec-skill" "$DF/claude/agent-skills/vend-skill"
  printf -- '---\nname: sec-skill\ndescription: Use when security.\n---\n' > "$DF/claude/skills/sec-skill/SKILL.md"
  printf -- '---\nname: vend-skill\ndescription: Use when vendored.\n---\n' > "$DF/claude/agent-skills/vend-skill/SKILL.md"
  run_h list --all
  [[ "$output" == *"sec-skill"* ]]
  [[ "$output" == *"vend-skill"* ]]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/harness.bats -f "description|--all"`
Expected: FAIL — basic `harness_list` prints names only and ignores `--all`.

- [ ] **Step 3: Add `_desc` and replace `harness_list`**

Add the helper above `harness_list`:

```bash
# _desc <file> — extract the YAML frontmatter `description:` as one trimmed line.
# Handles inline (`description: text`) and folded (`description: >-` then indented).
_desc(){
  awk '
    /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
    fm==1 {
      if ($0 ~ /^description:/) {
        sub(/^description:[[:space:]]*/, "")
        if ($0 ~ /^[>|]-?[[:space:]]*$/) { folded=1; next }   # folder marker only
        print; exit
      }
      if (folded) {
        if ($0 ~ /^[A-Za-z0-9_-]+:/) exit                     # next key ends it
        sub(/^[[:space:]]+/, ""); printf "%s ", $0
      }
    }
  ' "$1" 2>/dev/null | tr -s ' ' | sed 's/[[:space:]]*$//' | cut -c1-72
}
```

Replace `harness_list` with:

```bash
# _list_dir <kind> <dir> <descfile-fn> — print one section.
_emit_item(){  # <kind> <name> <descfile>
  local kind="$1" name="$2" df="$3" mark="○"
  [[ -e "$CLAUDE_DST/$kind/$name" || -e "$CLAUDE_DST/$kind/${name%.md}" ]] && mark="✓"
  local d; d="$(_desc "$df" 2>/dev/null)"; [[ -z "$d" ]] && d="(no description)"
  printf "    %s %-22s %s\n" "$mark" "$name" "$d"
}

harness_list(){
  local all=0 use_fzf=0 a
  for a in "$@"; do case "$a" in --all) all=1 ;; --fzf) use_fzf=1 ;; esac; done

  _walk(){  # emits "kind\tname\tdescfile" rows
    local kind dir e name df
    for kind in skills commands agents plugins; do
      dir="$HARNESS/$kind"; [[ -d "$dir" ]] || continue
      while IFS= read -r e; do
        name="$(basename "$e")"; [[ "$name" == _* || "$name" == .* ]] && continue
        if [[ -d "$e" ]]; then df="$e/SKILL.md"; else df="$e"; fi
        printf '%s\t%s\t%s\n' "$kind" "$name" "$df"
      done < <(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | sort)
    done
    if [[ $all -eq 1 ]]; then
      for kind in skills agent-skills; do
        dir="$DOTFILES_DIR/claude/$kind"; [[ -d "$dir" ]] || continue
        while IFS= read -r e; do
          name="$(basename "$e")"; [[ "$name" == _* || "$name" == .* ]] && continue
          printf '%s\t%s\t%s\n' "repo:$kind" "$name" "$e/SKILL.md"
        done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
      done
    fi
  }

  if [[ $use_fzf -eq 1 ]] && command -v fzf >/dev/null 2>&1; then
    local fzf_opts=(); command -v claw_theme_fzf >/dev/null 2>&1 && IFS=' ' read -r -a fzf_opts <<< "$(claw_theme_fzf 2>/dev/null)"
    _walk | awk -F'\t' '{printf "%s\t%s\t%s\n",$1,$2,$3}' \
      | fzf --with-nth=1,2 --delimiter='\t' "${fzf_opts[@]}" \
            --preview 'cat {3} 2>/dev/null' --preview-window=right:60%
    return 0
  fi

  printf "\n  Custom agentic harness (%s)\n\n" "$HARNESS"
  local last="" kind name df
  while IFS=$'\t' read -r kind name df; do
    [[ "$kind" != "$last" ]] && { printf "  %s\n" "$kind"; last="$kind"; }
    _emit_item "${kind#repo:}" "$name" "$df"
  done < <(_walk)
}
```

- [ ] **Step 4: Run the tests**

Run: `bats tests/harness.bats`
Expected: all PASS (including the two new ones).

- [ ] **Step 5: Syntax check + real smoke test**

Run: `bash -n scripts/utils/harness.sh && bash bin/claw harness list --all | head`
Expected: `ok`-clean parse; listing shows descriptions for your real skills + the `--all` sources.

- [ ] **Step 6: Commit**

```bash
git add scripts/utils/harness.sh tests/harness.bats
git commit -m "feat(harness): rich list — descriptions, deploy state, --all, --fzf"
```

---

### Task 5: Cross-machine `sync`

**Files:**
- Modify: `scripts/utils/harness.sh` (add `harness_sync`; add `sync)` to `main`)
- Modify: `tests/harness.bats` (add sync tests)

**Interfaces:**
- Consumes: `git`, `scripts/setup/link-claude.sh` (stubbed in tests).
- Produces: `harness_sync [--dry-run]`.

- [ ] **Step 1: Write the failing tests (append to `tests/harness.bats`)**

```bash
@test "sync: errors clearly when DOTFILES_DIR is not a git repo" {
  run_h sync
  [ "$status" -ne 0 ]; [[ "$output" == *"not a git repo"* ]]
}

@test "sync --dry-run: in a git repo with no upstream, mutates nothing" {
  ( cd "$DF" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
  before="$(git -C "$DF" rev-parse HEAD)"
  run_h sync --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"LINK_CLAUDE_RAN --dry-run"* ]]
  after="$(git -C "$DF" rev-parse HEAD)"
  [ "$before" = "$after" ]            # no new commit
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/harness.bats -f "sync"`
Expected: FAIL — `sync` is an unknown subcommand (`main` has no `sync)` arm).

- [ ] **Step 3: Add `harness_sync` and the dispatch arm**

Add the function (above `main`):

```bash
harness_sync(){
  local dry=0; [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && dry=1
  git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 \
    || { log_error "$DOTFILES_DIR is not a git repo"; return 1; }

  if [[ $dry -eq 1 ]]; then
    log_info "fetching origin…"
    git -C "$DOTFILES_DIR" fetch --quiet 2>/dev/null || log_warning "fetch failed (offline?)"
    if git -C "$DOTFILES_DIR" rev-parse '@{u}' >/dev/null 2>&1; then
      local n; n="$(git -C "$DOTFILES_DIR" rev-list --count HEAD..'@{u}' 2>/dev/null || echo 0)"
      log_info "$n commit(s) incoming:"
      git -C "$DOTFILES_DIR" log --oneline HEAD..'@{u}' 2>/dev/null || true
    else
      log_warning "no upstream tracking branch — nothing to pull"
    fi
    log_info "deploy preview:"
    bash "$DOTFILES_DIR/scripts/setup/link-claude.sh" --dry-run
    return 0
  fi

  log_info "pulling (ff-only)…"
  if ! git -C "$DOTFILES_DIR" pull --ff-only; then
    log_error "can't fast-forward (branch diverged). Reconcile manually, then re-run."
    return 1
  fi
  bash "$DOTFILES_DIR/scripts/setup/link-claude.sh"
  log_success "harness synced + deployed"
}
```

Add to `main`'s `case`, after the `new)` line:

```bash
    sync)         harness_sync "$@" ;;
```

- [ ] **Step 4: Run the tests**

Run: `bats tests/harness.bats`
Expected: all PASS.

- [ ] **Step 5: Syntax check**

Run: `bash -n scripts/utils/harness.sh && echo ok`
Expected: `ok`

- [ ] **Step 6: Commit**

```bash
git add scripts/utils/harness.sh tests/harness.bats
git commit -m "feat(harness): sync — git pull --ff-only + redeploy (+ --dry-run)"
```

---

### Task 6: Documentation

**Files:**
- Modify: `claude/harness/README.md`
- Modify: `docs/claw.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Update `claude/harness/README.md` Workflow section**

Replace the `## Workflow` fenced block with:

```bash
claw harness new <kind> <name>   # scaffold skill|command|agent|plugin from _templates/
claw harness new <name>          # bare = skill (back-compat)
claw harness list [--all] [--fzf]# names + descriptions + deploy state
claw harness sync [--dry-run]    # git pull --ff-only + redeploy in one step
claw harness deploy [--dry-run]  # symlink it all into ~/.claude (idempotent)
claw harness path                # print the harness root
```

And add one line under it: `Templates live in` `_templates/` `(skipped by the deployer). The engine is` `scripts/utils/harness.sh`; `cmd_harness in bin/claw is a thin dispatch to it.`

- [ ] **Step 2: Update the `claw harness` line in `docs/claw.md`**

Find the `claw harness` reference and ensure it reads:
`claw harness <cmd>   custom agentic tooling: new <kind> <name> · list [--all|--fzf] · sync · deploy · path`

- [ ] **Step 3: Commit**

```bash
git add claude/harness/README.md docs/claw.md
git commit -m "docs(harness): document new <kind>, list --all/--fzf, sync"
```

---

## Self-Review

**Spec coverage:**
- Scaffold any type → Tasks 1–2 (templates + `new <kind>`), wired in Task 3. ✓
- Rich discovery (`list --all/--fzf` + descriptions) → Task 4. ✓
- Cross-machine sync (`pull --ff-only` + redeploy, `--dry-run`) → Task 5. ✓
- Engine extraction + thin dispatcher → Tasks 2–3. ✓
- Back-compat (`new <name>`, `list`, `deploy`, `path`) → covered by Task 2 tests + Task 3 claw.bats regression. ✓
- Out-of-scope items (validation gate, `~/.agents` capture, plugin auto-deploy) → not implemented, as specified. ✓

**Placeholder scan:** No `TBD`/`TODO`/"handle errors appropriately" — every step has concrete code, commands, and expected output. ✓

**Type/name consistency:** `harness_new`/`harness_list`/`harness_sync`/`harness_deploy`/`harness_path`, helpers `_scaffold_file`/`_valid_name`/`_desc`/`_emit_item`, env `DOTFILES_DIR`/`CLAUDE_DST`/`HARNESS`/`TEMPLATES`, and the `__NAME__` token are used identically across Tasks 1–6. ✓
