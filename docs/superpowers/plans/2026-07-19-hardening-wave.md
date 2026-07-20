# Hardening Wave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish-wire ten confirmed defects where a declared contract was never wired end-to-end (dead hooks, bypassed scope check, latent shell-killer, duplicate functions, broken profile nudges, broken fresh-Mac install, manifest poisoning, theme split-brain).

**Architecture:** Seven independent sections, security-first. Each section is one or more commits touching disjoint files; sections never share a file, so they can land in any order after Section 1. Every code change lands with its regression test where cheap; shell tiers are enforced at edit time by the post-edit lint hook and in CI.

**Tech Stack:** zsh + bash shell modules, Python 3.12 (Claude Code hooks), Rust (ratatui TUI), bats + shellcheck + `zsh -n` + cargo clippy in CI.

## Global Constraints

- **Named-file staging only** — `git add <path>`, never `-A`/`.`/`-a`. One commit per coherent change.
- **Commit message style** — first line ≤ 72 chars, imperative; append `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **No PR** unless explicitly asked.
- **Cross-platform** — shell uses `platform.zsh` shims (`clip_copy`/`claw_open`/`local_ip`), `$HOMEBREW_PREFIX` not `/opt/homebrew`, `command grep` inside functions (aliases map grep→rg), no stdout during non-interactive init.
- **Spine invariants** — one `claw()` (shell/claw-fn.zsh only), one theme engine (theme.sh, `CLAW_C_*`/`CLAW_RGB_*`), one render path (claw-dashboard.py).
- **Green per commit** — `bats tests/`, `zsh -n` on changed `.zsh`, `shellcheck -S error -e SC1090,SC1091` on changed `.sh`, `cargo clippy -- -D warnings` for rust changes.
- **git push** uses the homebrew gh credential override: `git -c credential.helper= -c credential.helper='!/opt/homebrew/bin/gh auth git-credential' push` (memory: reference_dotfiles_git_push).

---

## File Structure

| File | Section | Responsibility |
|------|---------|----------------|
| `claude/install-hooks.sh` | 1a | register the edit-tool PreToolUse matcher |
| `claude/hooks/pre_tool_use.py` | 1a,1b | Bash-branch generated-file check; segment-aware recon scan |
| `tests/hooks.bats` (new) | 1a,1b | hook regression cases |
| `shell/load-env.zsh` | 1c | eval secret exports from a subprocess |
| `scripts/utils/secret.sh` | 1c | new `env-export` subcommand emitting `export` lines |
| `shell/aliases.zsh` | 2 | delete dead `claw()` + SMART FUNCTIONS duplicates |
| `tests/aliases-dedupe.bats` (new) | 2 | single-definition guard |
| `shell/profile-helpers.zsh` | 3 | fix `CLAW_PROFILE_TOOLCHAIN` typo |
| `shell/claw-fn.zsh` | 3 | derive install slug from `PROFILE_TOOLCHAIN` |
| `shell/welcome-tui.zsh` | 3 | show runnable install command |
| `shell/profiles/{brainstorm,vault}/meta.zsh` | 3 | clear phantom toolchain decls |
| `scripts/utils/profiles-lint.sh` (new) | 3 | `claw profiles lint` engine |
| `bin/claw` | 3 | dispatch `claw profiles lint` |
| `tests/profiles-lint.bats` (new) | 3 | lint pass/fail cases |
| `bootstrap.sh` | 4 | version-aware brew-bash gate |
| `scripts/install/provision.sh` | 4 | eval brew shellenv |
| `scripts/install/cloud-toolchain.sh` | 4 | kubectl/aws-iam-authenticator → none |
| `scripts/install/lib/toolchain-runner.sh` | 4 | `cargo:<crate>` fallback |
| `scripts/utils/pkg-manifest.sh` | 5 | skip shim symlinks; `manual` not `eget` |
| `config/themes/{matrix,synthwave,vhs,dosbbs}/` | 6 | migrate flat → dir layout |
| `scripts/utils/theme.sh` | 6 | two-path list/build resolution |
| `tui/claw-tui/src/theme.rs` | 6 | two-path palette read |
| `tui/claw-tui/src/main.rs` | 6 | `skip` → `Outcome::None` |
| `docs/ULTRAPLAN.md`, `CLAUDE.md`, `DEFERRED.md` | 7 | truth-up |

---

## Section 1a: Hook registration + Bash-branch guard

**Files:**
- Modify: `claude/install-hooks.sh` (the two `ensure(...)` calls)
- Modify: `claude/hooks/pre_tool_use.py` (Bash branch, after the exfil sensors)
- Test: `tests/hooks.bats` (create)

**Interfaces:**
- Produces: nothing consumed by later tasks (self-contained).

- [ ] **Step 1: Register the edit-tool matcher.** In `claude/install-hooks.sh`, after the existing line `changed |= ensure("PreToolUse", "Bash", "python3 ~/.claude/hooks/pre_tool_use.py")`, add:

```python
changed |= ensure("PreToolUse", "Edit|Write|MultiEdit|NotebookEdit", "python3 ~/.claude/hooks/pre_tool_use.py")
```

- [ ] **Step 2: Add the Bash-branch generated-file check.** In `claude/hooks/pre_tool_use.py`, inside `main()`, immediately after the `EXFIL_OBFUSCATED` loop (the `for pat in EXFIL_OBFUSCATED:` block that ends with `deny(... "obfuscated credential-exfil pattern ...")`) and before the recon block, add a check that catches shell-side edits (`sed -i`, `tee`, `>`) to the generated configs:

```python
    # Generated-fastfetch guard for shell-side edits (sed -i / tee / redirect).
    for gen in GENERATED_FASTFETCH:
        if gen in cmd and re.search(r"(sed\s+-i|tee|>>?)\b", cmd) and "fastfetch" in cmd:
            deny(
                tool, cmd,
                f"{gen} is generated by scripts/utils/gen-fastfetch.py",
                hint="Edit the generator, then re-run: python3 scripts/utils/gen-fastfetch.py",
            )
```

- [ ] **Step 3: Write the failing test.** Create `tests/hooks.bats`:

```bash
#!/usr/bin/env bats
# Regression tests for claude/hooks/pre_tool_use.py

HOOK="$BATS_TEST_DIRNAME/../claude/hooks/pre_tool_use.py"

# helper: run the hook with a JSON payload on stdin, capture exit code
run_hook() { run bash -c "printf '%s' '$1' | python3 '$HOOK'"; }

@test "edit to generated fastfetch config is denied" {
  run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/x/config/.config/fastfetch/config-ai.jsonc"}}'
  [ "$status" -eq 2 ]
}

@test "sed -i on a generated config via Bash is denied" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ config/.config/fastfetch/config-cortex.jsonc"}}'
  [ "$status" -eq 2 ]
}

@test "edit to a hand-maintained fastfetch config is allowed" {
  run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/x/config/.config/fastfetch/config-pmo.jsonc"}}'
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 4: Run the tests.** Run: `bats tests/hooks.bats`
Expected: 3 passing (the guard code from this morning + Step 2 make them pass; if the Bash-branch test fails, Step 2 is mis-placed).

- [ ] **Step 5: Re-run the installer** so the deployed settings pick up the new matcher. Run: `bash claude/install-hooks.sh`
Expected: `✓ hooks merged` (or `= hooks already present` on a second run). Verify: `python3 -c "import json;print([e['matcher'] for e in json.load(open('$HOME/.claude/settings.json'))['hooks']['PreToolUse']])"` lists both `Bash` and `Edit|Write|MultiEdit|NotebookEdit`.

- [ ] **Step 6: Commit.**

```bash
git add claude/install-hooks.sh claude/hooks/pre_tool_use.py tests/hooks.bats
git commit -m "fix(hooks): register edit-tool matcher + guard shell-side generated edits"
```

---

## Section 1b: Recon scope — segment-aware, prefix-stripped

**Files:**
- Modify: `claude/hooks/pre_tool_use.py` (recon block ~line 146-160)
- Test: `tests/hooks.bats` (append)

**Interfaces:**
- Consumes: existing `RECON_TOOLS`, `extract_targets`, `in_scope`, `deny`, `allow` from `_lib` and the module.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing tests.** Append to `tests/hooks.bats` (these require `~/.claude/scope.txt` to NOT contain `evil.com`; the hook default-denies unknown targets):

```bash
@test "sudo-prefixed recon tool is scope-checked (denied out of scope)" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"sudo nmap evil.com"}}'
  [ "$status" -eq 2 ]
}

@test "chained recon tool is scope-checked (denied out of scope)" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"true; nmap evil.com"}}'
  [ "$status" -eq 2 ]
}

@test "env-assignment-prefixed recon tool is scope-checked (denied out of scope)" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"FOO=bar nmap evil.com"}}'
  [ "$status" -eq 2 ]
}

@test "piped recon tool is scope-checked (denied out of scope)" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"echo x | nmap evil.com"}}'
  [ "$status" -eq 2 ]
}

@test "non-recon command still allowed" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run to verify failure.** Run: `bats tests/hooks.bats`
Expected: the four bypass tests FAIL (exit 0, currently allowed); `ls` test passes.

- [ ] **Step 3: Add a segment-splitting helper.** In `claude/hooks/pre_tool_use.py`, add near the top of the module (after the imports):

```python
# Wrapper commands and env-assignment prefixes to strip before matching a
# segment's leading binary against RECON_TOOLS.
_WRAPPERS = {"sudo", "doas", "env", "command", "nohup", "timeout", "nice", "xargs"}


def _recon_segments(cmd: str) -> list[str]:
    """Split a command line into statement/pipeline segments for recon scanning."""
    # Break on ; && || | and command-substitution boundaries.
    return [s for s in re.split(r"(?:\|\||&&|[;|]|\$\(|\)|`)", cmd) if s.strip()]


def _leading_bin(segment: str) -> str:
    """First real binary in a segment, past env-assignments and wrappers."""
    try:
        argv = shlex.split(segment, posix=True)
    except ValueError:
        argv = segment.split()
    i = 0
    while i < len(argv):
        tok = argv[i]
        if "=" in tok and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
            i += 1  # env assignment
            continue
        base = tok.rsplit("/", 1)[-1]
        if base in _WRAPPERS:
            i += 1  # wrapper command
            continue
        return base
    return ""
```

- [ ] **Step 4: Replace the recon block.** Replace the existing recon block in `main()` (from `try:\n        argv = shlex.split(...)` down through the final `allow(tool, cmd)`) with:

```python
    # 3. Recon scope check — scan every pipeline/statement segment, stripping
    #    sudo/env/wrapper prefixes so `sudo nmap` and `x; nmap` can't bypass.
    hit_recon = False
    for seg in _recon_segments(cmd):
        if _leading_bin(seg) in RECON_TOOLS:
            hit_recon = True
            targets = extract_targets(seg)
            if not targets:
                deny(tool, cmd, f"recon tool in {seg.strip()!r} invoked with no parseable target")
            for t in targets:
                if not in_scope(t):
                    deny(tool, cmd, f"target {t!r} not in ~/.claude/scope.txt (default-deny)", targets=targets)
    if hit_recon:
        allow(tool, cmd, reason="recon-in-scope")

    allow(tool, cmd)
```

- [ ] **Step 5: Run to verify pass.** Run: `bats tests/hooks.bats`
Expected: all tests pass. Also run `python3 -m py_compile claude/hooks/pre_tool_use.py` → no output.

- [ ] **Step 6: Wire hooks.bats into CI.** In `.github/workflows/ci.yml`, the python job — add a step after `py_compile`:

```yaml
      - name: hook regression tests
        run: sudo apt-get install -y bats && bats tests/hooks.bats
```

- [ ] **Step 7: Commit.**

```bash
git add claude/hooks/pre_tool_use.py tests/hooks.bats .github/workflows/ci.yml
git commit -m "fix(hooks): scope-check every command segment, defeating prefix/chain bypass"
```

---

## Section 1c: secret.sh option-leak fix

**Files:**
- Modify: `scripts/utils/secret.sh` (add `env-export` subcommand)
- Modify: `shell/load-env.zsh` (eval the subprocess output)

**Interfaces:**
- Produces: `secret.sh env-export` prints `export KEY=VAL` lines to stdout, exit 0 even when no env exists.

- [ ] **Step 1: Add the `env-export` function.** In `scripts/utils/secret.sh`, after `sec_load_env()` (ends ~line 74), add:

```bash
# Emit `export KEY=VAL` lines for eval by a caller that must NOT inherit this
# script's `set -uo pipefail` (load-env.zsh sources into the interactive shell).
sec_env_export() {
    [[ -f "$SOPS_ENV" ]] && command -v sops &>/dev/null || return 0
    local line k v
    while IFS= read -r line; do
        k="${line%%=*}"; v="${line#*=}"
        [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -n "$v" ]] && printf 'export %s=%q\n' "$k" "$v"
    done < <(sops -d "$SOPS_ENV" 2>/dev/null)
}
```

- [ ] **Step 2: Register the subcommand.** In `secret.sh`, in the `case "${1:-doctor}"` dispatch, add a line after `load)         sec_load_env ;;`:

```bash
    env-export)   sec_env_export ;;
```

- [ ] **Step 3: Replace the leaky source in load-env.zsh.** In `shell/load-env.zsh`, replace the final block:

```zsh
# Decrypt sops-managed secrets into the env (silent, guarded — see claw secret).
[[ -f "$DOTFILES_DIR/config/secrets/.env.sops" ]] && command -v sops &>/dev/null && \
    source "$DOTFILES_DIR/scripts/utils/secret.sh" load 2>/dev/null || true
```

with:

```zsh
# Decrypt sops-managed secrets into the env. secret.sh runs `set -uo pipefail`;
# run it as a SUBPROCESS emitting `export` lines and eval them, so those options
# never leak into this interactive shell (they would make every later unset-var
# expansion fatal). Silent + guarded.
if [[ -f "$DOTFILES_DIR/config/secrets/.env.sops" ]] && command -v sops &>/dev/null; then
    eval "$(bash "$DOTFILES_DIR/scripts/utils/secret.sh" env-export 2>/dev/null)"
fi
```

- [ ] **Step 4: Verify no option leak.** Run:

```bash
zsh -c 'setopt no_unset 2>/dev/null; source shell/load-env.zsh; [[ -o nounset ]] && echo LEAKED || echo CLEAN'
```

Expected: `CLEAN` (nounset not set in the calling shell). Also `zsh -n shell/load-env.zsh` → no output; `shellcheck -S error -e SC1090,SC1091 scripts/utils/secret.sh` → clean.

- [ ] **Step 5: Verify export path works with a fixture.** Run:

```bash
printf 'FOO=bar\nBAZ=qux=with=eq\n' > /tmp/claw-sec-test.env
bash -c 'SOPS_ENV=/tmp/claw-sec-test.env; source scripts/utils/secret.sh env-export 2>/dev/null' 2>/dev/null || true
```

(This is a smoke check — real path needs sops; the point is no crash. Remove `/tmp/claw-sec-test.env` after.)

- [ ] **Step 6: Commit.**

```bash
git add scripts/utils/secret.sh shell/load-env.zsh
git commit -m "fix(shell): confine secret.sh set -u/pipefail to a subprocess (no shell leak)"
```

---

## Section 2: aliases.zsh dedupe

**Files:**
- Modify: `shell/aliases.zsh` (delete legacy `claw()` ~446-496 and SMART FUNCTIONS duplicates)
- Test: `tests/aliases-dedupe.bats` (create)

**Interfaces:**
- Produces: exactly one definition each of `claw`, `extract`, `fkill`, `serve`, `mkcd` across `shell/`.

- [ ] **Step 1: Write the failing guard test.** Create `tests/aliases-dedupe.bats`:

```bash
#!/usr/bin/env bats
# Guards spine-invariant #1 and the twice-defined-function regressions.

SHELL_DIR="$BATS_TEST_DIRNAME/../shell"

# count function-definition sites (name followed by '()') across shell/
defcount() { grep -rEc "^\s*$1\s*\(\)" "$SHELL_DIR" | awk -F: '{s+=$2} END {print s}'; }

@test "exactly one claw() definition (spine invariant #1)" {
  # claw() lives ONLY in claw-fn.zsh
  [ "$(defcount claw)" -eq 1 ]
}

@test "exactly one extract() definition" {
  [ "$(defcount extract)" -eq 1 ]
}

@test "exactly one fkill() definition" {
  [ "$(defcount fkill)" -eq 1 ]
}
```

- [ ] **Step 2: Run to verify failure.** Run: `bats tests/aliases-dedupe.bats`
Expected: all three FAIL (claw=2, extract=2, fkill=2 currently).

- [ ] **Step 3: Delete the legacy `claw()` block.** In `shell/aliases.zsh`, delete the entire `claw() { ... }` function (starts `# Profile switching (inline, no restart needed)` / `claw() {` at ~446, ends at the closing `}` before `alias aliases=` at ~496). Keep the `alias zshrc`/`alias reload` above it and `alias aliases`/`alias vim` below it.

- [ ] **Step 4: Delete the SMART FUNCTIONS duplicates.** In `shell/aliases.zsh`, in the `# SMART FUNCTIONS` block (~757+), delete the second definitions of `mkcd()`, `extract()`, `fkill()`, and `serve()` — the weaker copies. KEEP the unique functions in that block (`psgrep`, `dcleanup`, `kctx-switch`, `kns-switch`, `awsp`, `tfw-switch`, `ff`, `fif`, etc.). The earlier copies (extract ~528, fkill ~594, serve ~526, mkcd ~552) are the stronger ones that stay.

- [ ] **Step 5: Run to verify pass.** Run: `bats tests/aliases-dedupe.bats && zsh -n shell/aliases.zsh`
Expected: 3 passing, no syntax error.

- [ ] **Step 6: Smoke-test the surviving functions.** Run:

```bash
zsh -c 'source shell/aliases.zsh 2>/dev/null; typeset -f extract | grep -q "tar.zst" && echo EXTRACT-OK; typeset -f fkill | grep -q "fzf -m" && echo FKILL-OK'
```

Expected: `EXTRACT-OK` and `FKILL-OK` (proves the strong copies won).

- [ ] **Step 7: Wire the guard into CI.** In `.github/workflows/ci.yml` the shell job already runs `bats tests/` — no change needed (new file is picked up automatically). Verify locally: `bats tests/`.

- [ ] **Step 8: Commit.**

```bash
git add shell/aliases.zsh tests/aliases-dedupe.bats
git commit -m "fix(shell): delete dead legacy claw() and weaker duplicate functions"
```

---

## Section 3: Profiles contract + `claw profiles lint`

**Files:**
- Modify: `shell/profile-helpers.zsh:47`
- Modify: `shell/claw-fn.zsh` (~line 86 nudge)
- Modify: `shell/welcome-tui.zsh:583`
- Modify: `shell/profiles/brainstorm/meta.zsh`, `shell/profiles/vault/meta.zsh`
- Create: `scripts/utils/profiles-lint.sh`
- Modify: `bin/claw` (dispatch)
- Test: `tests/profiles-lint.bats` (create)

**Interfaces:**
- Produces: `claw profiles lint` exits 0 when all 18 metas are valid, 1 + report on any violation. Helper `_toolchain_slug()` strips `-toolchain.sh` from `PROFILE_TOOLCHAIN`.

- [ ] **Step 1: Fix the typo'd variable in profile-helpers.zsh.** In `shell/profile-helpers.zsh:47`, change the printf's suffix so it derives the runnable slug from `PROFILE_TOOLCHAIN` (not the never-set `CLAW_PROFILE_TOOLCHAIN`) and suppresses when empty:

```zsh
            printf "    \e[38;2;255;123;114m✗\e[0m %s${PROFILE_TOOLCHAIN:+ — claw install ${PROFILE_TOOLCHAIN%-toolchain.sh}}\n" "$bin"
```

- [ ] **Step 2: Fix the claw-fn.zsh nudge.** In `shell/claw-fn.zsh` (~line 86), replace the miss-count nudge line so it uses the real toolchain slug and only nudges when a toolchain is declared:

```zsh
                if (( ${#_miss[@]} )); then
                    local _tc="${PROFILE_TOOLCHAIN%-toolchain.sh}"
                    if [[ -n "$_tc" ]]; then
                        printf "  ${_amb}●${_rst} ${_dim}%d tool(s) missing (%s) — ${_fg}claw install %s${_rst}\n" "${#_miss[@]}" "${_miss[*]}" "$_tc"
                    else
                        printf "  ${_amb}●${_rst} ${_dim}%d tool(s) missing (%s)${_rst}\n" "${#_miss[@]}" "${_miss[*]}"
                    fi
                fi
```

(Replaces the single `(( ${#_miss[@]} )) && printf ... "$p"` line.)

- [ ] **Step 3: Fix the welcome-tui install label.** In `shell/welcome-tui.zsh:583`, change the `refs+=` line to show a runnable command, only when the toolchain script exists:

```zsh
    if [[ -n "${PROFILE_TOOLCHAIN:-}" && -f "${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/install/${PROFILE_TOOLCHAIN}" ]]; then
        refs+=("${c_green}claw install ${PROFILE_TOOLCHAIN%-toolchain.sh}${c_reset} ${c_dim}install${c_reset}")
    fi
```

- [ ] **Step 4: Clear phantom toolchain declarations.** In `shell/profiles/brainstorm/meta.zsh` and `shell/profiles/vault/meta.zsh`, set the toolchain to empty (these scripts don't exist):

```zsh
PROFILE_TOOLCHAIN=""
```

- [ ] **Step 5: Write the failing lint test.** Create `tests/profiles-lint.bats`:

```bash
#!/usr/bin/env bats
LINT="$BATS_TEST_DIRNAME/../scripts/utils/profiles-lint.sh"

@test "profiles lint passes on the real tree" {
  run bash "$LINT"
  [ "$status" -eq 0 ]
}

@test "profiles lint fails when a meta declares a missing toolchain" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shell/profiles/ghost" "$tmp/scripts/install"
  cat > "$tmp/shell/profiles/ghost/meta.zsh" <<'EOF'
PROFILE_NAME="ghost"
PROFILE_TOOLCHAIN="ghost-toolchain.sh"
PROFILE_KEY_TOOLS="ls"
EOF
  run env DOTFILES_DIR="$tmp" bash "$LINT"
  [ "$status" -eq 1 ]
  rm -rf "$tmp"
}
```

- [ ] **Step 6: Run to verify failure.** Run: `bats tests/profiles-lint.bats`
Expected: FAIL — `profiles-lint.sh` does not exist yet.

- [ ] **Step 7: Write the lint engine.** Create `scripts/utils/profiles-lint.sh`:

```bash
#!/usr/bin/env bash
# claw profiles lint — mechanically validate all profile meta.zsh files.
# Checks: declared PROFILE_TOOLCHAIN resolves on disk (or is empty), a help cmd
# is discoverable, PROFILE_KEY_TOOLS or a bespoke tool_check exists.
set -uo pipefail
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
PROFILES_DIR="$DOTFILES/shell/profiles"
INSTALL_DIR="$DOTFILES/scripts/install"

fail=0
note() { printf '  ✗ %s: %s\n' "$1" "$2" >&2; fail=1; }

for meta in "$PROFILES_DIR"/*/meta.zsh; do
    [[ -f "$meta" ]] || continue
    name="$(basename "$(dirname "$meta")")"
    # Extract declared values without sourcing (avoid zsh-only syntax under bash).
    tc="$(sed -n 's/^PROFILE_TOOLCHAIN="\(.*\)"/\1/p' "$meta" | head -1)"
    keytools="$(sed -n 's/^PROFILE_KEY_TOOLS="\(.*\)"/\1/p' "$meta" | head -1)"
    helpcmd="$(sed -n 's/^PROFILE_HELP_CMD="\(.*\)"/\1/p' "$meta" | head -1)"

    if [[ -n "$tc" && ! -f "$INSTALL_DIR/$tc" ]]; then
        note "$name" "declares PROFILE_TOOLCHAIN=$tc but $INSTALL_DIR/$tc is missing"
    fi
    if [[ -z "$keytools" && -z "$helpcmd" ]]; then
        # profile must offer at least a key-tool list or an explicit help cmd
        common="$PROFILES_DIR/$name/common.zsh"
        grep -qE "^\s*${name}-help\s*\(\)|_${name}_tool_check\s*\(\)" "$common" 2>/dev/null \
            || note "$name" "no PROFILE_KEY_TOOLS, PROFILE_HELP_CMD, or ${name}-help/_${name}_tool_check"
    fi
done

if (( fail )); then
    printf '\n  profiles lint: FAIL\n' >&2
    exit 1
fi
printf '  profiles lint: all profiles valid\n'
```

- [ ] **Step 8: Dispatch it from bin/claw.** In `bin/claw`, add a `cmd_profiles` function near `cmd_install` and route it. Add the function:

```bash
cmd_profiles() {
    case "${1:-}" in
        lint) DOTFILES_DIR="$DOTFILES" bash "$DOTFILES/scripts/utils/profiles-lint.sh" ;;
        *)    err "usage: claw profiles lint"; return 1 ;;
    esac
}
```

Then find the main dispatch `case` in `bin/claw` (where `install)` routes to `cmd_install`) and add:

```bash
        profiles)  shift; cmd_profiles "$@" ;;
```

- [ ] **Step 9: Run to verify pass.** Run: `bats tests/profiles-lint.bats`
Expected: both pass. Also `shellcheck -S error -e SC1090,SC1091 scripts/utils/profiles-lint.sh` and `bash scripts/utils/profiles-lint.sh` → "all profiles valid".

- [ ] **Step 10: Wire lint into CI.** In `.github/workflows/ci.yml` shell job, add after the bats step:

```yaml
      - name: profiles lint
        run: DOTFILES_DIR="$PWD" bash scripts/utils/profiles-lint.sh
```

- [ ] **Step 11: Verify the shell fixes syntax-check.** Run: `zsh -n shell/profile-helpers.zsh shell/claw-fn.zsh shell/welcome-tui.zsh shell/profiles/brainstorm/meta.zsh shell/profiles/vault/meta.zsh`
Expected: no output.

- [ ] **Step 12: Commit.**

```bash
git add shell/profile-helpers.zsh shell/claw-fn.zsh shell/welcome-tui.zsh \
  shell/profiles/brainstorm/meta.zsh shell/profiles/vault/meta.zsh \
  scripts/utils/profiles-lint.sh bin/claw tests/profiles-lint.bats .github/workflows/ci.yml
git commit -m "fix(profiles): repair toolchain-install contract + add claw profiles lint"
```

---

## Section 4: Install path repairs

**Files:**
- Modify: `bootstrap.sh` (~line 280 brew_extras loop)
- Modify: `scripts/install/provision.sh` (~line 35, after Homebrew install)
- Modify: `scripts/install/cloud-toolchain.sh` (kubectl + aws-iam-authenticator rows)
- Modify: `scripts/install/lib/toolchain-runner.sh` (`cargo:*` fallback case)

**Interfaces:**
- Produces: `cargo:<crate>` fallback now installs via `cargo install <crate>`.

- [ ] **Step 1: Version-aware brew-bash gate.** In `bootstrap.sh`, in the `brew_extras` loop (~281-288), the `bash` entry is gated on `! command -v "$tool"` which is always false. Special-case bash by version. Replace the loop body:

```bash
        for tool in "${brew_extras[@]}"; do
            if [[ "$tool" == bash ]]; then
                # /bin/bash 3.2 always resolves; gate on the BREW bash existing,
                # not `command -v bash` (which the system bash always satisfies).
                if [[ ! -x "$(brew --prefix)/bin/bash" ]]; then
                    log_info "Installing modern bash via brew..."
                    brew install bash 2>/dev/null || log_warning "Failed to install bash"
                else
                    log_success "modern bash already installed"
                fi
                continue
            fi
            if ! command -v "$tool" &>/dev/null; then
                log_info "Installing $tool via brew..."
                brew install "$tool" 2>/dev/null || log_warning "Failed to install $tool"
            else
                log_success "$tool already installed"
            fi
        done
```

(Confirmed: `HOMEBREW_PREFIX` is NOT set in bootstrap.sh scope — this step correctly uses `brew --prefix`, which is on PATH by the time this loop runs since it's guarded by `command -v brew`.)

- [ ] **Step 2: provision.sh evals brew shellenv.** In `scripts/install/provision.sh`, in the `# 1. Package manager` section, after the Homebrew install line, add the shellenv eval (mirroring bootstrap.sh:166-176):

```bash
    # Put brew on PATH for the rest of this run (fresh installs land in a shell
    # that hasn't sourced .zprofile yet — the exact bug bootstrap.sh fixes).
    if ! have brew; then
        for _b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
            [[ -x "$_b" ]] && eval "$("$_b" shellenv)" && break
        done
    fi
```

- [ ] **Step 3: Fix the kubectl + aws-iam-authenticator rows.** In `scripts/install/cloud-toolchain.sh`, change the kubectl fallback from `curl:https://dl.k8s.io/release/stable.txt` to `none` (the curl target is a version string, not a binary — it self-masks). And aws-iam-authenticator from its 404ing `curl:` URL to `none`:

```bash
    "kubectl|kubernetes-cli|kubectl|none|k8s CLI — apt/brew; use official repo on bare Ubuntu"
```
```bash
    "aws-iam-authenticator|aws-iam-authenticator|?|none|AWS IAM → k8s auth — install via official release page"
```

- [ ] **Step 4: Implement the `cargo:<crate>` fallback.** In `scripts/install/lib/toolchain-runner.sh`, the `case "$fb"` in `_install_one` has a `cargo)` arm (bare) but no `cargo:*` arm (the grammar clin-rs/tealdeer rows use). Add before the `cargo)` line:

```bash
        cargo:*)          command -v cargo &>/dev/null && _run cargo install "${fb#cargo:}" && { log_success "$id (cargo)"; RESULT_INSTALLED+=("$id"); } || { log_warning "$id (cargo unavailable)"; RESULT_FAILED+=("$id"); } ;;
```

- [ ] **Step 5: Syntax + shellcheck.** Run:

```bash
bash -n bootstrap.sh scripts/install/provision.sh scripts/install/cloud-toolchain.sh scripts/install/lib/toolchain-runner.sh
shellcheck -S error -e SC1090,SC1091 scripts/install/lib/toolchain-runner.sh scripts/install/provision.sh
```

Expected: no output / clean.

- [ ] **Step 6: Dry-run the cloud toolchain to confirm no kubectl text-file install.** Run: `DRY_RUN=1 DOTFILES_DIR="$PWD" bash scripts/install/cloud-toolchain.sh 2>&1 | grep -i kubectl`
Expected: kubectl shows a `no install path` / manual note, NOT a curl fetch of stable.txt.

- [ ] **Step 7: Commit.**

```bash
git add bootstrap.sh scripts/install/provision.sh scripts/install/cloud-toolchain.sh scripts/install/lib/toolchain-runner.sh
git commit -m "fix(install): fresh-Mac bash gate, provision brew PATH, dead toolchain rows"
```

---

## Section 5: pkg track de-poisoning

**Files:**
- Modify: `scripts/utils/pkg-manifest.sh` (`_discover` ~80, `_infer_source` ~142, `_install_via` ~194)

**Interfaces:**
- Produces: `manual`-tagged rows are skip-with-note in `_install_via`.

- [ ] **Step 1: Skip shim symlinks in `_discover`.** In `scripts/utils/pkg-manifest.sh`, in `_discover` (~80-86), change the inner loop to skip executables whose realpath resolves into a pipx/uv/claude shim dir:

```bash
    local d f tgt
    for d in "$HOME/.local/bin" "$HOME/go/bin"; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*; do
            [[ -f "$f" && -x "$f" ]] || continue
            # Skip entry-point shims managed by pipx/uv/claude — not standalone tools.
            tgt="$(readlink -f "$f" 2>/dev/null || realpath "$f" 2>/dev/null || echo "$f")"
            case "$tgt" in
                *"/.local/pipx/"*|*"/.local/share/uv/"*|*"/.local/share/claude/"*|*"/pipx/venvs/"*) continue ;;
            esac
            printf '%s\n' "${f##*/}"
        done
    done
```

- [ ] **Step 2: Tag unknowns `manual`, not `eget`.** In `_infer_source` (~142), change the user-binary line from assuming eget to `manual`:

```bash
    [[ -x "$HOME/.local/bin/$id" || -x "$HOME/go/bin/$id" ]] && { echo manual; return; }   # user binary of unknown origin — needs manual review, not a blind eget
    echo manual
```

- [ ] **Step 3: `manual` is skip-with-note in `_install_via`.** Confirm the existing `manual)  return 10 ;;` line in `_install_via` (~194) already treats manual as skip — it does. No change needed; note it in the commit.

- [ ] **Step 4: Syntax + shellcheck.** Run: `bash -n scripts/utils/pkg-manifest.sh && shellcheck -S error -e SC1090,SC1091 scripts/utils/pkg-manifest.sh`
Expected: clean.

- [ ] **Step 5: Verify discovery no longer emits pipx shims.** Run:

```bash
DOTFILES_DIR="$PWD" bash -c 'source scripts/utils/pkg-manifest.sh 2>/dev/null; _discover_clean' 2>/dev/null | grep -iE '^(flask|uvicorn|httpx|f2py|plotly)$' && echo "STILL-POISONED" || echo "CLEAN"
```

Expected: `CLEAN` (the shim entry-points are gone). If your `~/.local/bin` has none of those, the check trivially passes — inspect the full list manually.

- [ ] **Step 6: Commit.**

```bash
git add scripts/utils/pkg-manifest.sh
git commit -m "fix(pkg): skip pipx/uv/claude shims and tag unknown binaries manual not eget"
```

- [ ] **Step 7: Drop the poisoned stash — REQUIRES OPERATOR SIGN-OFF.** Show the operator `git stash list` and the poisoned diff (`git stash show -p stash@{0} | head -30`). Only on explicit approval: `git stash drop stash@{0}`. This is the wave's one destructive step; do NOT do it autonomously.

---

## Section 6: Theme split-brain repair

**Files:**
- Migrate: `config/themes/{matrix,synthwave,vhs,dosbbs}.theme` → `config/themes/<slug>/palette.theme`
- Modify: `scripts/utils/theme.sh` (`claw_theme_list` ~96, `claw_theme_build` ~199)
- Modify: `tui/claw-tui/src/theme.rs` (~63 path)
- Modify: `tui/claw-tui/src/main.rs` (`skip` → `Outcome::None`)

**Interfaces:**
- Consumes: `_claw_theme_file <slug>` already does two-path resolution (dir `palette.theme` → flat `.theme`).
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Migrate the four flat theme files.** For each slug in matrix synthwave vhs dosbbs:

```bash
for s in matrix synthwave vhs dosbbs; do
  mkdir -p "config/themes/$s"
  git mv "config/themes/$s.theme" "config/themes/$s/palette.theme"
done
```

- [ ] **Step 2: Render their ghostty.conf artifacts.** Run:

```bash
for s in matrix synthwave vhs dosbbs; do DOTFILES_DIR="$PWD" bash scripts/utils/theme.sh ghostty "$s"; done
```

Expected: four `✓ <slug>/ghostty.conf` lines. Verify `ls config/themes/matrix/` shows `palette.theme` + `ghostty.conf`.

- [ ] **Step 3: Confirm list/build now see them.** Run: `DOTFILES_DIR="$PWD" bash scripts/utils/theme.sh list`
Expected: matrix/synthwave/vhs/dosbbs now appear (they glob `*/` and resolve via `_claw_theme_file`). Since they're now directories, `claw_theme_list`/`claw_theme_build` already pick them up — the migration alone fixes the shell side. No theme.sh code change needed if all four are migrated; keep the two-path resolver work as belt-and-suspenders in Step 4.

- [ ] **Step 4: Harden theme.sh against a future stray flat file.** In `scripts/utils/theme.sh`, `claw_theme_list` and `claw_theme_build` iterate `"$CLAW_THEME_DIR"/*/` (dirs only). Add a second pass over flat `.theme` files so a straggler can't vanish. In `claw_theme_list`, after the existing `for _td in "$CLAW_THEME_DIR"/*/; do ... done` loop, add:

```bash
    for _tf in "$CLAW_THEME_DIR"/*.theme; do
        [ -e "$_tf" ] || continue
        _s="$(basename "$_tf" .theme)"
        [ -d "$CLAW_THEME_DIR/$_s" ] && continue   # already shown as a dir
        _n="$(sed -n 's/^name=//p' "$_tf" | head -n1)"
        printf '    \033[38;2;215;58;58m%-18s %s (flat — migrate)\033[0m\n' "$_s" "$_n"
    done
```

(Apply the analogous guard to `claw_theme_build`.)

- [ ] **Step 5: Two-path read in the rust palette loader.** In `tui/claw-tui/src/theme.rs`, replace the single-path read (`let Ok(body) = std::fs::read_to_string(format!("{dots}/config/themes/{slug}.theme"))`) with a dir-first, flat-fallback resolver:

```rust
    let dir_path = format!("{dots}/config/themes/{slug}/palette.theme");
    let flat_path = format!("{dots}/config/themes/{slug}.theme");
    let Ok(body) = std::fs::read_to_string(&dir_path)
        .or_else(|_| std::fs::read_to_string(&flat_path))
    else {
        return p;
    };
```

- [ ] **Step 6: Add a rust test for both layouts.** In `tui/claw-tui/src/theme.rs`, add under `#[cfg(test)]` (create the module if absent):

```rust
#[cfg(test)]
mod theme_tests {
    #[test]
    fn hex_parses_six_digit() {
        // guards the palette hex parser used by both layouts
        assert!(super::hex("#58a6ff").is_some());
        assert!(super::hex("nope").is_none());
    }
}
```

(If `hex` isn't `pub(crate)`-visible to the test module, it's in the same file so `super::hex` resolves. Adjust if the fn is named differently — verify with `grep -n 'fn hex' tui/claw-tui/src/theme.rs`.)

- [ ] **Step 7: Fix the TUI skip action.** In `tui/claw-tui/src/main.rs`, `confirm()` (~155) maps `Kind::Action` → `Outcome::Action(key)`. Special-case `skip` to emit `Outcome::None`:

```rust
    fn confirm(&mut self) {
        if let Some(it) = self.current_item() {
            self.outcome = match it.kind {
                Kind::Profile => Outcome::Profile(it.key.clone()),
                Kind::Action if it.key == "skip" => Outcome::None,
                Kind::Action => Outcome::Action(it.key.clone()),
                Kind::Header => return,
            };
        }
        self.quit = true;
    }
```

- [ ] **Step 8: Build + test the rust crate.** Run (in `tui/claw-tui`): `cargo test && cargo clippy -- -D warnings`
Expected: tests pass, clippy clean.

- [ ] **Step 9: Verify TUI skip no longer errors.** Run: `cd tui/claw-tui && echo | CLAW_TUI=1 cargo run 2>/dev/null` — navigate to skip, Enter; confirm the emitted line is `NONE` not `ACTION\tskip` (or inspect via a unit assertion if headless).

- [ ] **Step 10: Commit.**

```bash
git add config/themes/matrix config/themes/synthwave config/themes/vhs config/themes/dosbbs \
  scripts/utils/theme.sh tui/claw-tui/src/theme.rs tui/claw-tui/src/main.rs
git commit -m "fix(theme): migrate flat themes to dir layout, two-path readers, TUI skip=None"
```

---

## Section 7: Docs truth-up

**Files:**
- Modify: `docs/ULTRAPLAN.md` (check 3 stale boxes, annotate M2)
- Modify: `CLAUDE.md` (profile-system section → directory-per-profile)
- Modify: `DEFERRED.md` (log wave)

**Interfaces:** none.

- [ ] **Step 1: Check the stale-done ULTRAPLAN boxes.** In `docs/ULTRAPLAN.md`, change `[ ]` → `[x]` for: pkg self-update timer (Wave 2), `claw capture-tasks` (Wave 3), `/handoff` skill (Wave 3). Annotate the TUI M2 line as "mostly landed (categorized dual-pane + 13 actions); parity gaps: Clin Notes, AI Toolkit, toolkit launcher".

- [ ] **Step 2: Update CLAUDE.md profile section.** In `CLAUDE.md`, the Profile System section describes single-file `shell/profiles/<name>.zsh`. Update to the directory-per-profile reality: a 5-line dispatcher `shell/profiles/<name>.zsh` sourcing `<name>/{meta,common,mac|linux}.zsh`. Note `claw profiles lint` validates the contract.

- [ ] **Step 3: Log the wave in DEFERRED.md.** Under `## Open`, note anything deliberately not fixed here (e.g. the theme fzf picker + NO_COLOR contract deferred to the theme feature spec; the poisoned stash pending sign-off if not yet dropped).

- [ ] **Step 4: Verify no broken KB references.** Run: `bash -n /dev/null; grep -rl 'directory-per-profile' knowledge-base/ && echo "KB already current"`
Expected: KB profile-directory-contract note already describes this (from earlier session) — bump its `updated` field to 2026-07-19 if the wave changed the contract it documents (it added `claw profiles lint`).

- [ ] **Step 5: Commit.**

```bash
git add docs/ULTRAPLAN.md CLAUDE.md DEFERRED.md knowledge-base/topics/profiles/profile-directory-contract.md
git commit -m "docs: truth-up ULTRAPLAN boxes, profile-system section, hardening-wave log"
```

---

## Final verification (all sections)

- [ ] **Run the full suite.** Run: `bats tests/ && for f in $(git ls-files 'shell/**/*.zsh' 'shell/.zshrc'); do zsh -n "$f"; done && (cd tui/claw-tui && cargo test && cargo clippy -- -D warnings)`
Expected: all green.

- [ ] **Portability review.** Dispatch the `portability-reviewer` agent over the branch diff (`git diff master...HEAD`) to catch any raw-command / hardcoded-color / stdout-pollution regressions introduced by the wave.

- [ ] **Push.** `git -c credential.helper= -c credential.helper='!/opt/homebrew/bin/gh auth git-credential' push`

---

## Self-Review notes (author)

- **Spec §1a-c, §2-§7** each map to a section above. §3's "PROFILE_FLAIR/TIER get a consumer or removal" is resolved as "keep, documented as reserved" — the lint doesn't flag them (spec left the call to the plan; keeping avoids churn across 18 files).
- **§6 fzf picker / NO_COLOR** are explicitly OUT (deferred to theme feature spec) — no task, matches spec's out-of-scope.
- **Type consistency:** `_toolchain_slug` behavior is expressed inline as `${PROFILE_TOOLCHAIN%-toolchain.sh}` everywhere (helpers, claw-fn, welcome-tui, lint) — one idiom, no drift.
- **Ghostty spec** is a separate plan (follow-on), per the writing-plans scope check — this plan is the hardening wave only.
