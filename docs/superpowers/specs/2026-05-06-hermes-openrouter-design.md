# Hermes + OpenRouter Agent Integration — Design

**Date:** 2026-05-06 · **Decisions finalized & approved:** 2026-06-02
**Status:** ✅ Approved — code ~90% built (commit `416f193`, 2026-05-07); remaining deltas + activation tracked in [`docs/superpowers/plans/2026-06-02-hermes-openrouter-activation.md`](../plans/2026-06-02-hermes-openrouter-activation.md)
**Builds on:** `2026-04-25-claw-mvp-rewrite-design.md` (claw agent registry)
**Phase:** 5 (Hermes) + new Phase (OpenRouter)
**Target host:** BD790i (Ubuntu Linux, AMD x86_64) — activated first; macOS (Apple Silicon) parity pass follows.

---

## Status & Decisions (2026-06-02)

The agents were **implemented but never activated**. As of 2026-06-02 the wrappers, install scripts, `claw doctor` checks, the `op://` secret resolver, and `.env.example` scaffolding all exist on disk; what remains is a small set of deltas (below) plus running the installer. The live registry (`~/.config/claw/agents.toml`) still holds only `[claude]`.

**Open questions — resolved by operator:**

| # | Question | Decision |
|---|---|---|
| 1 | Default Hermes model | **`hermes3:8b`** (override `$CLAW_HERMES_MODEL` → `hermes3:70b` on BD790i's heavier config) |
| 2 | `claw hermes --serve` — auto-start daemon or instruct? | **Auto-start, hybrid + enable-at-boot.** Linux: `sudo systemctl enable --now ollama`. macOS: `brew services start ollama`. Fallback: `nohup ollama serve & disown`. |
| 3 | Default OpenRouter model | **`anthropic/claude-opus-4.7`** (was `sonnet-4.6`) |
| 4 | macOS parity or Linux-only? | **Full parity**, staged: **BD790i first** (heavier configs), macOS local pass next |

**Secrets:** `OPENROUTER_API_KEY` via **1Password `op://` reference** (primary, per operator OPSEC) resolved by `shell/load-env.zsh`; literal in `~/.dotfiles/.env` is the fallback. Configured on both hosts, BD790i first.

**Delta discovered 2026-06-02 (correctness):** `bin/claw`'s `cmd_run_agent` does `exec "$cmd"` with **no argument forwarding**, and dispatch passes only `"$1"`. So `claw hermes --serve` (and one-shot prompts like `claw hermes "explain X"`) silently drop everything after the agent name. The dispatcher must forward `"$@"` to the agent for `--serve` to work *through* `claw`. See plan Task 1.

**Remaining deltas (all in the plan):** (a) `claw` arg-forwarding; (b) `--serve` branch in `bin/hermes`; (c) macOS `brew services start` in `hermes.sh` `ensure_daemon`; (d) default-model swap to `opus-4.7` in `bin/openrouter` + `config.yaml.example` + `openrouter.sh` registry description; (e) activation via `claw install ai` + `claw doctor` verification on each host.

## Problem

Two agents called out in the global operator profile and `docs/claw.md` are documented but not implemented:

- **Hermes agent** — referenced as the route for refusal-prone prompts (legitimate red-team / threat-modeling) that hit Anthropic's hard refusal directions. Currently a `# Example future entry` comment in `bin/claw`.
- **OpenRouter** — never implemented. No env-var scaffolding, no CLI wrapper, no agent registration.

The `claw <agent>` dispatcher already exists and works. What's missing is the **install path**, the **runtime wiring**, and the **secret-handling discipline** for both.

## Goals

1. **`claw hermes`** — works on a fresh BD790i install after `bootstrap.sh` + `claw install ai`. Backed by a local Ollama model, configurable via `$CLAW_HERMES_MODEL`.
2. **`claw openrouter`** — works on the same install. Backed by [`aichat`](https://github.com/sigoden/aichat) configured for OpenRouter as a provider; default model **`anthropic/claude-opus-4.7`** (operator decision 2026-06-02; was `sonnet-4.6`).
3. **Sustainable secrets** — `OPENROUTER_API_KEY` lives in `~/.dotfiles/.env` (gitignored) by default; optional 1Password CLI pass-through if `op` is available. No hard dependency on any proprietary tool.
4. **Linux-first install path** — `scripts/install/ai-toolchain.sh` handles Parrot/Ubuntu cleanly without brew. macOS install path remains parallel.
5. **Idempotent** — re-running `claw install ai` is safe; `command -v` and model-presence guards before every install/pull.
6. **`claw doctor` coverage** — adds checks for `ollama` daemon, configured Hermes model, `aichat` binary, and `OPENROUTER_API_KEY` presence.

## Non-Goals

- Building Hermes from source. Ollama already packages Nous Research's Hermes models; we use those.
- Multi-agent composition (`claw hermes+claude` — defer).
- A custom Python/curl OpenRouter wrapper. `aichat` is the open-source, sustainable choice.
- Per-profile model selection (one default per agent; override via env var).
- Cloud-hosted Hermes (e.g., Nous Forge). Local-only on BD790i.
- GPU detection / model auto-tuning. User picks model size; we don't second-guess.

## Design

### 1. Hermes agent (local, Ollama-backed)

**Runtime:** Ollama. On BD790i it's already installed. On any other host, `scripts/install/hermes.sh` installs it idempotently:

```bash
# Linux
command -v ollama || curl -fsSL https://ollama.com/install.sh | sh

# macOS (parity, less common path)
command -v ollama || brew install ollama
```

**Default model:** `hermes3:8b` (~5GB, runs comfortably on CPU). Override via `$CLAW_HERMES_MODEL` — set in `~/.dotfiles/.env` or `~/.zshrc.local`. Examples:

```bash
export CLAW_HERMES_MODEL="hermes3:70b"            # bigger, needs ~40GB RAM
export CLAW_HERMES_MODEL="nous-hermes2-mixtral"   # ~26GB, mixture-of-experts
```

**Pull step (in `hermes.sh`):**

```bash
local model="${CLAW_HERMES_MODEL:-hermes3:8b}"
if ! ollama list 2>/dev/null | grep -q "^${model%%:*}"; then
    log_info "Pulling Hermes model: $model"
    ollama pull "$model"
else
    log_success "Hermes model present: $model"
fi
```

**Wrapper:** new `bin/hermes` (~30 lines bash):

```bash
#!/usr/bin/env bash
# hermes — local Hermes agent via Ollama
set -e
MODEL="${CLAW_HERMES_MODEL:-hermes3:8b}"

# Ensure ollama daemon is reachable
if ! curl -fsS http://localhost:11434/api/tags &>/dev/null; then
    echo "ollama daemon not running. start with: ollama serve" >&2
    exit 1
fi

if [[ $# -eq 0 ]]; then
    exec ollama run "$MODEL"
else
    exec ollama run "$MODEL" "$*"
fi
```

**Registry:** `hermes.sh` appends to `~/.config/claw/agents.toml` if `[hermes]` not present:

```toml
[hermes]
command = "hermes"
profile = "ai"
description = "Local Hermes (Nous Research) via Ollama"
```

**Result:** `claw hermes` loads the `ai` profile dashboard, then `exec`s the wrapper.

### 2. OpenRouter agent (`aichat` backed)

**Runtime:** [`aichat`](https://github.com/sigoden/aichat) — Rust CLI, MIT-licensed, native multi-provider support (OpenRouter, Anthropic, OpenAI, Ollama, …). Streaming, sessions, RAG, tool-use all built-in.

**Install (Linux):**

```bash
# Prefer prebuilt release binary (faster, no rust toolchain required)
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  AC_TARGET="x86_64-unknown-linux-musl" ;;
    aarch64) AC_TARGET="aarch64-unknown-linux-musl" ;;
esac
LATEST=$(curl -fsSL https://api.github.com/repos/sigoden/aichat/releases/latest | grep tag_name | cut -d'"' -f4)
curl -fsSL "https://github.com/sigoden/aichat/releases/download/${LATEST}/aichat-${LATEST}-${AC_TARGET}.tar.gz" \
  | tar -xz -C /usr/local/bin aichat
```

**Install (macOS):**

```bash
brew install aichat
```

**Config template:** ship `config/.config/aichat/config.yaml.example` with:

```yaml
model: openrouter:anthropic/claude-sonnet-4.6
clients:
  - type: openai-compatible
    name: openrouter
    api_base: https://openrouter.ai/api/v1
    api_key: ${env:OPENROUTER_API_KEY}
    models:
      - name: anthropic/claude-sonnet-4.6
      - name: anthropic/claude-opus-4.7
      - name: meta-llama/llama-3.3-70b-instruct
      - name: deepseek/deepseek-chat
```

`scripts/install/openrouter.sh` symlinks this to `~/.config/aichat/config.yaml` if no user config exists (never overwrites).

**Wrapper:** new `bin/openrouter` (~20 lines bash):

```bash
#!/usr/bin/env bash
# openrouter — chat via OpenRouter, default model claude-sonnet-4.6
set -e
[[ -z "$OPENROUTER_API_KEY" ]] && { echo "OPENROUTER_API_KEY not set" >&2; exit 1; }
MODEL="${CLAW_OPENROUTER_MODEL:-openrouter:anthropic/claude-sonnet-4.6}"

if [[ $# -eq 0 ]]; then
    exec aichat -m "$MODEL"
else
    exec aichat -m "$MODEL" "$@"
fi
```

**Registry entry:**

```toml
[openrouter]
command = "openrouter"
profile = "ai"
description = "OpenRouter (default: claude-sonnet-4.6)"
```

### 3. Secret handling — sustainable, open, optional 1Password

**Default path: `.env` file.** `~/.dotfiles/.env` is already loaded via `shell/load-env.zsh` (silent, gitignored). Users add:

```bash
OPENROUTER_API_KEY=sk-or-...
# Optional: pin a different default model
CLAW_OPENROUTER_MODEL=openrouter:meta-llama/llama-3.3-70b-instruct
CLAW_HERMES_MODEL=hermes3:70b
```

A `.env.example` snippet documents these.

**Optional path: 1Password CLI.** If `op` is on PATH, the user can replace the literal in `.env` with:

```bash
OPENROUTER_API_KEY="op://Personal/OpenRouter/api_key"
```

…and add a tiny resolver in `shell/load-env.zsh`:

```zsh
# Resolve op:// references via 1Password CLI when available
if command -v op &>/dev/null; then
    [[ "$OPENROUTER_API_KEY" == op://* ]] && export OPENROUTER_API_KEY="$(op read "$OPENROUTER_API_KEY" 2>/dev/null)"
fi
```

This is the **only** non-default integration; everything else works without `op`. No hard dependency, sustainable for the next operator.

**Never:** API keys in `claude/mcp.json`, `aichat/config.yaml` (uses `${env:...}` expansion), or anywhere git-tracked.

### 4. Install orchestration

`scripts/install/ai-toolchain.sh` gets two new top-level steps appended (idempotent, gated):

```bash
# After existing ollama/llama-cpp steps:
log_info "→ Hermes agent"
bash "$DOTFILES_DIR/scripts/install/hermes.sh"

log_info "→ OpenRouter (aichat)"
bash "$DOTFILES_DIR/scripts/install/openrouter.sh"
```

Both new scripts:
- Use `scripts/utils/detect-os.sh` for OS branching
- Use `scripts/utils/logger.sh` for output
- Exit early with `log_warning` (non-fatal) if a prerequisite is missing
- Append agent registry entries only if not already present

### 5. `claw doctor` checks

Add to `cmd_doctor()` in `bin/claw`:

```
[ai] ollama daemon         : ✓ reachable at :11434
[ai] hermes model          : ✓ hermes3:8b (5.1 GB)
[ai] aichat                : ✓ v0.x.y
[ai] OPENROUTER_API_KEY    : ✓ set (op:// resolved)
```

Each check is independent — a missing one prints a single hint line, doesn't abort.

### 6. Welcome TUI integration

The existing `agents` row in `welcome-tui.zsh` already pulls from `agents.toml` via FZF. After `hermes` and `openrouter` are registered, they appear automatically in that picker. **No menu code changes needed.**

## File changes

| File | Action |
|---|---|
| `scripts/install/hermes.sh` | **NEW** — installs ollama + pulls model + registers agent |
| `scripts/install/openrouter.sh` | **NEW** — installs aichat + symlinks config + registers agent |
| `scripts/install/ai-toolchain.sh` | **EDIT** — call the two new scripts |
| `bin/hermes` | **NEW** — wrapper script |
| `bin/openrouter` | **NEW** — wrapper script |
| `config/.config/aichat/config.yaml.example` | **NEW** — template config |
| `shell/load-env.zsh` | **EDIT** — optional `op://` resolver (4 lines, guarded) |
| `bin/claw` | **EDIT** — add 4 doctor checks |
| `.env.example` | **EDIT** — document new env vars |
| `docs/claw.md` | **EDIT** — document `claw hermes` / `claw openrouter` |
| `docs/superpowers/specs/2026-05-06-hermes-openrouter-design.md` | **NEW** (this file) |

## Acceptance criteria (Phase 5 + OpenRouter Phase Gate)

On a fresh BD790i clone of this repo:

1. `./bootstrap.sh` completes without error.
2. `claw install ai` runs to completion, leaves both agents registered.
3. `claw doctor` prints all four `[ai]` lines green.
4. `OPENROUTER_API_KEY=sk-or-... claw openrouter "say hi"` returns a Sonnet response.
5. `claw hermes "say hi"` (with daemon running) returns a Hermes response.
6. Re-running `claw install ai` is a no-op (no re-pulls, no duplicate registry entries).
7. `bin/hermes` and `bin/openrouter` exit 1 with a clear message when prerequisite is missing (daemon down, key unset).
8. No secrets in `git status` after install.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Ollama install script changes upstream | Pin documented version in script header; `command -v` guard means re-running just verifies |
| OpenRouter model IDs drift | Config example flags this; user can override via `CLAW_OPENROUTER_MODEL` |
| `aichat` release binary URL changes | `hermes.sh`/`openrouter.sh` log version on install for traceability; falls back to `cargo install aichat` if release fetch fails |
| Hermes 70b OOMs the box | Default is `hermes3:8b`; doc calls out RAM cost of larger models |
| 1Password resolver runs on every shell | Guarded by `op://*` prefix check; no `op` call unless prefix matches |

## Open questions for review — ✅ RESOLVED 2026-06-02

All four are resolved in the **Status & Decisions** section at the top of this doc:

1. Default Hermes model → **`hermes3:8b`** (BD790i may override to `70b`).
2. `claw hermes --serve` → **auto-start, hybrid + enable-at-boot** (systemd on Linux, `brew services` on macOS, `nohup` fallback). This *overrides* the original "instruct (less magic)" spec position.
3. Default OpenRouter model → **`anthropic/claude-opus-4.7`**.
4. macOS branch → **full parity**, BD790i activated first.
