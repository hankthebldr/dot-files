# Hermes + OpenRouter Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish and activate the already-built Hermes (local Ollama) + OpenRouter (`aichat`) agents per the 2026-06-02 decisions — `claw hermes --serve` auto-starts the daemon, defaults are `hermes3:8b` / `claude-opus-4.7` — on BD790i first, then macOS.

**Architecture:** The agents shipped in `416f193` but were never activated. This plan closes a small set of deltas (a shared cross-platform ollama-daemon helper, a `--serve` branch, a `claw` arg-forwarding fix, two default-model swaps), then runs the existing `claw install ai` path on each host. Code deltas (Tasks 1–5) are host-agnostic and implemented in-repo; activation (Tasks 6–7) is a per-host operator runbook.

**Tech Stack:** Bash (the `bin/*` wrappers, `scripts/install/*`, `bin/claw`), Ollama, `aichat`, systemd (BD790i) / `brew services` (macOS), 1Password `op://` secrets via `shell/load-env.zsh`.

**Spec:** [docs/superpowers/specs/2026-05-06-hermes-openrouter-design.md](../specs/2026-05-06-hermes-openrouter-design.md) (decisions finalized 2026-06-02)

**Host staging:** BD790i (Ubuntu, systemd, heavier configs — may set `CLAW_HERMES_MODEL=hermes3:70b`) is activated first. macOS (Apple Silicon, Homebrew) follows.

---

## Current state (verified 2026-06-02)

| Piece | State |
|---|---|
| `bin/hermes`, `bin/openrouter` | ✓ exist; hermes lacks `--serve`; openrouter defaults to `sonnet-4.6` |
| `scripts/install/hermes.sh`, `openrouter.sh` | ✓ exist; hermes.sh Linux daemon-start ✓, macOS path only *instructs* |
| `scripts/install/ai-toolchain.sh` | ✓ calls both installers (step 10) |
| `bin/claw` `cmd_doctor` `[ai]` checks | ✓ present (ollama/hermes-model/aichat/key) |
| `bin/claw` agent dispatch | ✗ **drops args** — `cmd_run_agent "$1"` → `exec "$cmd"` (no `"$@"`) |
| `shell/load-env.zsh` `op://` resolver | ✓ resolves `OPENROUTER_API_KEY` |
| `config/.config/aichat/config.yaml.example` | ✓ opus-4.7 in models list; default line still `sonnet-4.6` |
| `~/.config/claw/agents.toml` (live) | only `[claude]` — hermes/openrouter not yet registered (added by installers) |
| `bin/` on PATH | ✓ `shell/path.zsh:27` |

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `scripts/utils/ollama.sh` | Cross-platform "bring the ollama daemon up" helper (selector + ensurer) | **Create** |
| `tests/agents.test.sh` | Bash unit tests for the helper + claw arg-forwarding | **Create** |
| `bin/hermes` | Add `--serve` (auto-start via helper) | Modify |
| `scripts/install/hermes.sh` | `ensure_daemon` delegates to the helper (real macOS start) | Modify |
| `bin/claw` | Forward `"$@"` to the dispatched agent | Modify (`cmd_run_agent` + dispatch) |
| `bin/openrouter` | Default model → `claude-opus-4.7` | Modify (1 line) |
| `config/.config/aichat/config.yaml.example` | Default `model:` → opus-4.7 | Modify (1 line) |
| `scripts/install/openrouter.sh` | Registry description → opus-4.7 | Modify (1 line) |
| `tests/test-runner.sh` | Run `tests/agents.test.sh` | Modify |

Conventions: `#!/usr/bin/env bash`; source `scripts/utils/logger.sh`/`detect-os.sh`; `command -v` guards; never run a daemon at *source* time (only when called).

---

## Task 1: Cross-platform ollama-daemon helper (TDD)

The `--serve` selection logic (which start command for which host) is the one piece worth isolating and testing — both `bin/hermes` and `scripts/install/hermes.sh` need it, and we can test *selection* without starting a real daemon.

**Files:**
- Create: `scripts/utils/ollama.sh`
- Create: `tests/agents.test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/agents.test.sh`:

```bash
#!/usr/bin/env bash
# tests/agents.test.sh — unit tests for the Hermes/OpenRouter agent plumbing.
# Run standalone: bash tests/agents.test.sh
set -uo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$THIS_DIR/.." && pwd)"
pass=0; fail=0

assert_eq() { # assert_eq <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; ((pass++))
  else echo "  ✗ $1"; echo "      expected: [$2]"; echo "      actual:   [$3]"; ((fail++)); fi
}

# --- ollama_serve_cmd selection (pure, no daemon started) ---
source "$REPO/scripts/utils/ollama.sh"

# Prefix-assign the test seams directly on the function call so the function body
# sees them. (Assignments on a command-substitution's *arguments* would NOT reach
# the subshell — POSIX expands args before the prefix assignment takes effect.)
check_serve_cmd() { # <desc> <os> <systemctl> <brew> <expected>
  local actual
  actual="$(OS_TYPE="$2" _OLLAMA_HAS_SYSTEMCTL="$3" _OLLAMA_HAS_BREW="$4" ollama_serve_cmd)"
  assert_eq "$1" "$5" "$actual"
}

check_serve_cmd "linux+systemd → systemctl enable --now" ubuntu        1 0 "sudo systemctl enable --now ollama"
check_serve_cmd "macos+brew → brew services start"        macos         0 1 "brew services start ollama"
check_serve_cmd "fallback → nohup ollama serve"           linux-generic 0 0 "nohup ollama serve >/dev/null 2>&1 & disown"

echo "  ──"
echo "  ${pass} passed, ${fail} failed"
(( fail == 0 ))
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/agents.test.sh`
Expected: FAIL — `scripts/utils/ollama.sh: No such file or directory`, exit non-zero.

- [ ] **Step 3: Create `scripts/utils/ollama.sh`**

```bash
#!/usr/bin/env bash
# scripts/utils/ollama.sh — cross-platform ollama daemon helpers.
# Sourced by bin/hermes (--serve) and scripts/install/hermes.sh (ensure_daemon).
# ollama_serve_cmd  : echo the right "start the daemon" command for this host (pure).
# ollama_up         : true if the daemon answers on :11434.
# ollama_ensure_up  : probe → start (via ollama_serve_cmd) → re-probe.
#
# Test seams: OS_TYPE, _OLLAMA_HAS_SYSTEMCTL, _OLLAMA_HAS_BREW may be preset by tests.

ollama_up() {
  curl -fsS --max-time 3 http://localhost:11434/api/tags &>/dev/null
}

ollama_serve_cmd() {
  local os="${OS_TYPE:-}"
  local has_systemctl="${_OLLAMA_HAS_SYSTEMCTL:-$(command -v systemctl &>/dev/null && echo 1 || echo 0)}"
  local has_brew="${_OLLAMA_HAS_BREW:-$(command -v brew &>/dev/null && echo 1 || echo 0)}"

  case "$os" in
    ubuntu|debian|parrot|kali|linux-generic|linux)
      if [[ "$has_systemctl" == 1 ]]; then
        echo "sudo systemctl enable --now ollama"; return
      fi ;;
    macos)
      if [[ "$has_brew" == 1 ]]; then
        echo "brew services start ollama"; return
      fi ;;
  esac
  echo "nohup ollama serve >/dev/null 2>&1 & disown"
}

# Bring the daemon up if it isn't. Returns 0 if reachable afterwards.
ollama_ensure_up() {
  ollama_up && return 0
  local cmd; cmd="$(ollama_serve_cmd)"
  echo "ollama: starting daemon → $cmd" >&2
  eval "$cmd" || echo "ollama: start command returned non-zero (continuing)" >&2
  # Give the daemon a moment, then re-probe a few times.
  local i
  for i in 1 2 3 4 5; do
    ollama_up && return 0
    sleep 1
  done
  ollama_up
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/agents.test.sh`
Expected: PASS — `3 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/utils/ollama.sh tests/agents.test.sh
git commit -m "feat(ai): cross-platform ollama daemon helper (serve-cmd selector)"
```

---

## Task 2: `bin/hermes --serve` auto-start

**Files:**
- Modify: `bin/hermes`

- [ ] **Step 1: Add the `--serve` branch**

In `bin/hermes`, replace the daemon-probe block (currently lines 22–31, the `if ! curl ... :11434 ... exit 1` block) with a version that honors `--serve`. The new block resolves `DOTFILES`, sources the helper, and — if `--serve` was passed — auto-starts; otherwise keeps the old instruct-and-exit behavior:

```bash
# Parse a leading --serve flag (auto-start the daemon instead of just instructing)
SERVE=0
if [[ "${1:-}" == "--serve" ]]; then SERVE=1; shift; fi

# Resolve repo + source the shared ollama helper + OS detection
DOTFILES="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$DOTFILES/scripts/utils/detect-os.sh"; detect_os
source "$DOTFILES/scripts/utils/ollama.sh"

# Ensure the daemon is reachable
if ! ollama_up; then
    if (( SERVE )); then
        ollama_ensure_up || { echo "hermes: could not start ollama daemon" >&2; exit 1; }
    else
        echo "hermes: ollama daemon not reachable at :11434" >&2
        echo "        auto-start it:  claw hermes --serve   (or: hermes --serve)" >&2
        exit 1
    fi
fi
```

(Leave the `command -v ollama` check above it and the `ollama list` model check + final `exec ollama run` below it unchanged. `shift` after `--serve` means the remaining `"$@"`/`"$*"` still feed the one-shot/REPL exec.)

- [ ] **Step 2: Syntax check**

Run: `bash -n bin/hermes`
Expected: exit 0, no output.

- [ ] **Step 3: Behavioral check — `--serve` is stripped, prompt survives**

Run (no daemon needed — we stub `ollama` and the helper probe):
```bash
PATH="$PWD/.tmptest:$PATH"; mkdir -p .tmptest
cat > .tmptest/ollama <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list) printf 'NAME\nhermes3:8b\n' ;;
  run)  shift; echo "RUN_ARGS:[$*]" ;;
esac
EOF
chmod +x .tmptest/ollama
# Force "daemon up" so no start is attempted:
curl() { return 0; }; export -f curl 2>/dev/null || true
CLAW_HERMES_MODEL=hermes3:8b bash bin/hermes --serve "explain TLS" 2>/dev/null
rm -rf .tmptest
```
Expected: prints `RUN_ARGS:[explain TLS]` — confirming `--serve` was consumed and the prompt forwarded. (If your shell can't `export -f curl`, run on a host where ollama is actually up.)

- [ ] **Step 4: Commit**

```bash
git add bin/hermes
git commit -m "feat(ai): hermes --serve auto-starts ollama (hybrid, enable-at-boot)"
```

---

## Task 3: `hermes.sh` `ensure_daemon` delegates to the helper

**Files:**
- Modify: `scripts/install/hermes.sh`

- [ ] **Step 1: Replace the inline `ensure_daemon` body**

Replace the entire `ensure_daemon() { ... }` function (currently lines 55–84) with a thin wrapper over the shared helper, so macOS actually runs `brew services start ollama` instead of only printing a hint:

```bash
ensure_daemon() {
    source "$DOTFILES_DIR/scripts/utils/ollama.sh"
    if ollama_ensure_up; then
        log_success "ollama daemon reachable at :11434"
    else
        log_warning "ollama daemon still unreachable — model pull may fail; re-run later"
    fi
}
```

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/install/hermes.sh`
Expected: exit 0.

- [ ] **Step 3: Selection check (no daemon started)**

Run:
```bash
source scripts/utils/ollama.sh
OS_TYPE=macos _OLLAMA_HAS_SYSTEMCTL=0 _OLLAMA_HAS_BREW=1 ollama_serve_cmd
```
Expected: prints `brew services start ollama`.

- [ ] **Step 4: Commit**

```bash
git add scripts/install/hermes.sh
git commit -m "fix(ai): hermes.sh ensure_daemon starts ollama on macOS too"
```

---

## Task 4: `claw` forwards args to the dispatched agent (TDD)

Without this, `claw hermes --serve` and `claw openrouter "prompt"` drop everything after the agent name.

**Files:**
- Modify: `bin/claw` (`cmd_run_agent` ~lines 646–672; dispatch `*)` ~line 716)
- Modify: `tests/agents.test.sh` (add a forwarding test)

- [ ] **Step 1: Write the failing test**

Append to `tests/agents.test.sh`, immediately before the final `echo "  ──"` summary block:

```bash
# --- claw forwards extra args to the agent ---
claw_tmp="$(mktemp -d)"
mkdir -p "$claw_tmp/cfg/claw" "$claw_tmp/bin"
cat > "$claw_tmp/bin/recorder" <<'EOF'
#!/usr/bin/env bash
printf 'ARGS:[%s]\n' "$*"
EOF
chmod +x "$claw_tmp/bin/recorder"
cat > "$claw_tmp/cfg/claw/agents.toml" <<'EOF'
[rec]
command = "recorder"
EOF
got="$(XDG_CONFIG_HOME="$claw_tmp/cfg" PATH="$claw_tmp/bin:$PATH" \
        bash "$REPO/bin/claw" rec --serve "hi there" 2>/dev/null | grep '^ARGS:')"
assert_eq "claw forwards args to agent" "ARGS:[--serve hi there]" "$got"
rm -rf "$claw_tmp"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/agents.test.sh`
Expected: FAIL — `claw forwards args to agent` actual is `ARGS:[]` (args dropped), exit non-zero.

- [ ] **Step 3: Forward args in `bin/claw`**

(a) Change the dispatch fallthrough. Replace:

```bash
    *)              cmd_run_agent "$1" ;;
```
with:
```bash
    *)              cmd_run_agent "$@" ;;
```

(b) In `cmd_run_agent`, capture the name, shift, and forward the rest to `exec`. Replace the opening:

```bash
cmd_run_agent() {
    local agent="$1"
    ensure_agents_toml
```
with:
```bash
cmd_run_agent() {
    local agent="$1"; shift || true
    ensure_agents_toml
```

…and replace the final hand-off line:

```bash
    # Hand off — exec replaces the claw process with the agent
    exec "$cmd"
}
```
with:
```bash
    # Hand off — exec replaces the claw process with the agent, forwarding args
    exec "$cmd" "$@"
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/agents.test.sh`
Expected: PASS — `4 passed, 0 failed`, exit 0.

Run: `bash -n bin/claw`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add bin/claw tests/agents.test.sh
git commit -m "fix(claw): forward args to dispatched agent (enables hermes --serve)"
```

---

## Task 5: Default OpenRouter model → `claude-opus-4.7`

**Files:**
- Modify: `bin/openrouter`, `config/.config/aichat/config.yaml.example`, `scripts/install/openrouter.sh`

- [ ] **Step 1: Swap the three defaults**

(a) `bin/openrouter` — replace:
```bash
MODEL="${CLAW_OPENROUTER_MODEL:-openrouter:anthropic/claude-sonnet-4.6}"
```
with:
```bash
MODEL="${CLAW_OPENROUTER_MODEL:-openrouter:anthropic/claude-opus-4.7}"
```

(b) `config/.config/aichat/config.yaml.example` — replace:
```yaml
model: openrouter:anthropic/claude-sonnet-4.6
```
with:
```yaml
model: openrouter:anthropic/claude-opus-4.7
```

(c) `scripts/install/openrouter.sh` — in `register_agent`, replace:
```bash
description = "OpenRouter via aichat (default: anthropic/claude-sonnet-4.6)"
```
with:
```bash
description = "OpenRouter via aichat (default: anthropic/claude-opus-4.7)"
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -n "claude-opus-4.7" bin/openrouter config/.config/aichat/config.yaml.example scripts/install/openrouter.sh
bash -n bin/openrouter scripts/install/openrouter.sh
```
Expected: three matches (one per file); syntax OK. `opus-4.7` is already present in the config's `models:` list, so no provider-list edit is needed.

- [ ] **Step 3: Commit**

```bash
git add bin/openrouter config/.config/aichat/config.yaml.example scripts/install/openrouter.sh
git commit -m "feat(ai): default OpenRouter model → claude-opus-4.7"
```

---

## Task 6: Wire `agents.test.sh` into the suite + final code verification

**Files:**
- Modify: `tests/test-runner.sh`

- [ ] **Step 1: Register the test**

After the `test_session_identity` registration in `main()` (the `run_test "Session Identity" ...` line), add:

```bash
    run_test "Agents (hermes/openrouter)" test_agents || ((failures++))
```

And add the function after `test_session_identity()`:

```bash
test_agents() {
    log_info "Testing agent plumbing..."
    bash "$(dirname "${BASH_SOURCE[0]}")/agents.test.sh" || return 1
}
```

- [ ] **Step 2: Run the full suite**

Run: `bash tests/test-runner.sh`
Expected: "All tests passed!"; the "Agents (hermes/openrouter)" line reports `4 passed, 0 failed`.

- [ ] **Step 3: Commit**

```bash
git add tests/test-runner.sh
git commit -m "test: run agents suite in test-runner"
```

> **Code deltas complete.** The repo is now "prepared to activate." Tasks 7–8 run on the actual hosts.

---

## Task 7: Activate on BD790i (operator runbook — HITL)

Run on BD790i (Ubuntu, systemd). Heavier config: optionally `export CLAW_HERMES_MODEL=hermes3:70b` in `~/.dotfiles/.env` first.

- [ ] **Step 1: Pull the branch & deploy**

```bash
cd ~/.dotfiles && git fetch origin && git checkout feat/hermes-openrouter-activation && git pull
./bootstrap.sh --minimal   # re-stows bin/, shell/ — safe, idempotent
```
Expected: symlinks refreshed; `command -v claw hermes openrouter` all resolve.

- [ ] **Step 2: Configure the OpenRouter key (1Password primary)**

In `~/.dotfiles/.env` (gitignored), add **one** of:
```bash
OPENROUTER_API_KEY=op://Personal/OpenRouter/api_key   # preferred — needs `op` signed in
# OPENROUTER_API_KEY=sk-or-...                          # literal fallback
```
Then: `exec zsh` (reload) and verify:
```bash
[[ -n "$OPENROUTER_API_KEY" && "$OPENROUTER_API_KEY" != op://* ]] && echo "key resolved" || echo "NOT resolved — check: op signin / .env"
```
Expected: `key resolved`. (If using `op://`, `op` must be authenticated: `eval "$(op signin)"`.)

- [ ] **Step 2.5 (REQUEST FOR OPERATOR INPUT): heavier-config knobs**

Before running install, decide the BD790i-specific overrides. In `~/.dotfiles/.env`, set the values you want — this is where your "heavier config" intent becomes concrete:

```bash
# --- BD790i heavier config (edit to taste) ---
CLAW_HERMES_MODEL=hermes3:70b                 # 8b default is fine on CPU; 70b needs ~40GB RAM
# CLAW_OPENROUTER_MODEL=openrouter:anthropic/claude-opus-4.7   # already the default; override if desired
```
**Why this matters:** BD790i is your always-on box, so it's the right place to run a larger local model — but `hermes3:70b` is ~40GB and will OOM if the box can't hold it. Pick `8b` (safe), `70b` (if RAM allows), or `nous-hermes2-mixtral` (~26GB MoE). Leave `CLAW_HERMES_MODEL` unset to accept the `8b` default.

- [ ] **Step 3: Run the installer**

```bash
claw install ai
```
Expected: ollama present/installed; daemon started via systemd (`enable --now`); Hermes model pulled; `aichat` installed; `[hermes]` and `[openrouter]` appended to `~/.config/claw/agents.toml`.

- [ ] **Step 4: Verify with `claw doctor`**

```bash
claw doctor | grep -A1 -iE 'ollama|hermes|aichat|OPENROUTER'
claw agent list
```
Expected: all four `[ai]` lines green; `claw agent list` now shows `claude`, `hermes`, `openrouter`.

- [ ] **Step 5: Smoke both agents (the Phase 5 gate)**

```bash
claw hermes --serve "say hi in one short sentence"
claw openrouter "say hi in one short sentence"
git -C ~/.dotfiles status --short   # must show NO secrets
```
Expected: Hermes returns a local response (daemon auto-started if it was down); OpenRouter returns an opus-4.7 response; clean `git status`.

---

## Task 8: Activate on macOS (operator runbook — follow-on)

Run on the Mac (Apple Silicon, Homebrew). Same shape; `brew` paths instead of systemd.

- [ ] **Step 1: Deploy the branch**

```bash
cd ~/Github/Github_desktop/dot-files && git checkout feat/hermes-openrouter-activation && git pull
```

- [ ] **Step 2: Key + install**

```bash
# ~/.dotfiles/.env already has OPENROUTER_API_KEY if synced; else add as in Task 7 Step 2
claw install ai
```
Expected: `brew install ollama aichat`; `ensure_daemon` runs `brew services start ollama`; model pulled (default `hermes3:8b` — keep small on a laptop); agents registered.

- [ ] **Step 3: Verify + smoke**

```bash
claw doctor | grep -iE 'ollama|hermes|aichat|OPENROUTER'
claw hermes --serve "say hi"
claw openrouter "say hi"
```
Expected: green doctor; both agents respond. On macOS `--serve` runs `brew services start ollama` if the daemon is down.

- [ ] **Step 4: Open the PR**

```bash
git push -u origin feat/hermes-openrouter-activation   # use the gh credential-helper override if needed
gh pr create --base master --title "feat(ai): activate Hermes + OpenRouter (Phase 5)" \
  --body "Closes the build→activate gap. Decisions: hermes3:8b, claude-opus-4.7, --serve auto-start (enable-at-boot), macOS parity. See docs/superpowers/specs/2026-05-06-hermes-openrouter-design.md."
```

---

## Acceptance criteria (Phase 5 gate — from the spec)

- [ ] `claw install ai` runs to completion on BD790i, leaves both agents registered.
- [ ] `claw doctor` prints all four `[ai]` lines green (both hosts).
- [ ] `claw hermes --serve "hi"` returns a Hermes response, auto-starting the daemon if down.
- [ ] `claw openrouter "hi"` returns a `claude-opus-4.7` response.
- [ ] Re-running `claw install ai` is a no-op (no re-pulls, no duplicate registry entries).
- [ ] No secrets in `git status` after install (key via `op://` or gitignored `.env`).
- [ ] `bash tests/test-runner.sh` green (includes the new agents suite).

## Self-Review

**1. Spec coverage**

| Decision / delta | Task |
|---|---|
| `--serve` auto-start, hybrid + enable-at-boot | Tasks 1, 2 |
| macOS `brew services start` in install | Tasks 1, 3 |
| `claw hermes --serve` reaches the wrapper (arg forwarding) | Task 4 |
| default `hermes3:8b` (+ BD790i `70b` override) | Existing default; Task 7 Step 2.5 |
| default OpenRouter `claude-opus-4.7` | Task 5 |
| `op://` secrets, BD790i first | Task 7 Step 2 (resolver already exists) |
| macOS parity, staged | Task 8 |
| roadmap + design doc updated | Done pre-plan (commit `0c41360`) |

No gaps.

**2. Placeholder scan:** No TBD/TODO. Every code step shows complete code; every run step has a command + expected result. Task 7 Step 2.5 is an explicit operator-input request (heavier-config knobs), not a placeholder.

**3. Name/path consistency:** `ollama_serve_cmd` / `ollama_up` / `ollama_ensure_up` are spelled identically across `scripts/utils/ollama.sh`, `bin/hermes`, `scripts/install/hermes.sh`, and `tests/agents.test.sh`. Test pass-counts are cumulative (3 → 4). `OS_TYPE` is the variable `detect-os.sh` sets (confirmed in existing `hermes.sh`).
