# TUI v2 — Profile Action Contract & AI Cockpit

> Design spec / roadmap for the next-generation Open Claw welcome TUI.
> Brainstormed 2026-06-02. Extends the 18-profile architecture
> ([`docs/profiles/architecture.md`](../../profiles/architecture.md),
> [`2026-05-19-18-profile-architecture-design.md`](2026-05-19-18-profile-architecture-design.md))
> and depends on the Hermes/OpenRouter AI substrate
> ([`2026-05-06-hermes-openrouter-design.md`](2026-05-06-hermes-openrouter-design.md)).
>
> **Status:** draft, pending operator review. Not yet decomposed into an
> implementation plan. Tracked in Things project `dot-files` (group **E**).

---

## 1. The through-line

Today the welcome TUI is an **environment loader**: pick a profile → source its
aliases → render fastfetch art → print a help card. The profile system is rich
(17 profiles, per-OS sub-files, metadata-driven readouts), but the *interaction*
ends the moment the profile loads.

The entire v2 backlog points one direction: **turn the TUI into an action
launcher / ops cockpit** where each profile contributes three things —
**actions** (interactive workflows), **live state** (readiness), and an **AI
persona** (domain-scoped copilot) — through one uniform contract.

The homelab profile already proves the demand: `hstatus` / `bwstatus`
([`homelab/common.zsh`](../../../shell/profiles/homelab/common.zsh),
[`blackwell/common.zsh`](../../../shell/profiles/blackwell/common.zsh)) are text
dashboards straining to be live, interactive panes. Security already proves the
"engagement" primitive with `sec_engagement`. v2 generalizes both.

### Key enabler (why now)

The expensive infrastructure already exists in-repo:

- **Telemetry** — `~/.cache/claw/usage.tsv` logs every `fire`/`group`/`pick`
  ([`welcome-tui.zsh:20-33`](../../../shell/welcome-tui.zsh)). Unused for ranking.
- **Local + cloud AI** — `bin/hermes` (Ollama `hermes3:8b`) and `bin/openrouter`
  (`aichat`), plus an agent registry (`claw agent`). Activation is the current
  branch (`feat/hermes-openrouter-activation`).
- **Per-profile metadata** — `PROFILE_KEY_TOOLS`, `PROFILE_CLASS`, etc., already
  declared in every `meta.zsh`.

So most of v2 is **cheap glue over shipped substrate**, not new systems.

---

## 2. Converged architecture — the unified Profile + Engagement model

Three concepts the TUI manages **uniformly**:

| Concept | Definition | Lifecycle |
|---|---|---|
| **Profile** | A named *capability set* — aliases, tools, theme, AI persona | Loaded by sourcing; **must have no relocating side-effects** |
| **Engagement** | A named *working context/workspace* scoped to a profile | Created/entered **explicitly only** (`claw engage`); may `cd`, set env |
| **Session** | The active shell — the runtime binding of profile + engagement | Already tracked (`CLAW_ACTIVE_PROFILE`, `CLAW_ACTIVE_GROUP`, session banner) |

The critical consistency fix lives here: **loading a profile must never relocate
you or mutate the filesystem.** [security/common.zsh:13-15](../../../shell/profiles/security/common.zsh)
already enforces this ("footgun — selecting a profile shouldn't relocate you"),
but [cortex/common.zsh:11-14](../../../shell/profiles/cortex/common.zsh) still
`mkdir`s + `cd`s on load. The engagement concept resolves the tension: *entering
a working context is an explicit action, never a load side-effect.*

### 2.1 The Profile Action Contract

Extend the documented `meta.zsh` schema with one new field family. No parser, no
logic — pure declarations, consistent with the existing schema.

```zsh
# shell/profiles/<name>/meta.zsh  (new fields, all optional w/ sane defaults)

# ACTIONS — interactive workflows surfaced as TUI level-3 + fzf previews.
# Format: "key<TAB>label<TAB>command" — one per line. Commands are shell
# functions the profile already defines (or claw subcommands).
PROFILE_ACTIONS='
recon\tRecon (scope-gated)\tsec_recon
fuzz\tWeb fuzz\tfuzz
engage\tNew engagement\tclaw engage
'

# READINESS — function emitting live status for the picker preview pane.
# Defaults to _<name>_tool_check if unset.
PROFILE_READINESS="_security_tool_check"

# AI CONTEXT — domain system-prompt seed for the scoped persona. Defaults to
# a template built from PROFILE_CLASS + PROFILE_KEY_TOOLS + the help card.
PROFILE_AI_CONTEXT="You are a recon/exploitation assistant. Tools: ${PROFILE_KEY_TOOLS}. Prefer scope-safe, OPSEC-aware commands."

# ENGAGE — optional fn to create/enter an engagement. Defaults to a generic
# workspace under a per-profile root. security's sec_engagement is the model.
PROFILE_ENGAGE="sec_engagement"
```

### 2.2 The consumers

One contract, four consumers — each reads the same declarations:

1. **TUI level-3 actions** — after picking a profile, surface `PROFILE_ACTIONS`
   in fzf. "Load profile" and "New engagement" are always-present synthetic
   actions, so the existing load behavior is preserved as the default action.
2. **Readiness preview** — fzf `--preview` at level-2 renders `PROFILE_READINESS`
   output live (cached per-shell, TTL'd). The picker becomes a *readiness board*.
3. **AI persona** — the NL palette + `claw agent` inject `PROFILE_AI_CONTEXT`
   when a profile is active. 17 env-presets become 17 scoped copilots for ~free.
4. **`claw doctor` / tests** — already reads `PROFILE_KEY_TOOLS`; extend to
   validate that every `PROFILE_ACTIONS` command resolves (smoke test).

### 2.3 Why this shape

- **Isolation:** one bounded schema-field family + a small set of consumers. A
  profile author declares; the TUI renders. Neither knows the other's internals.
- **Uniformity:** all 17 profiles benefit from one mechanism — no bespoke
  per-profile TUI code.
- **Graceful degradation:** every field is optional. A profile with no
  `PROFILE_ACTIONS` behaves exactly as today (load + readout). No fzf / no Ollama
  / no fastfetch all keep working — a current strength we preserve.

---

## 3. Diverged per-profile flows

What each profile's `PROFILE_ACTIONS` + engagement + AI persona should be. (All
grounded in functions/aliases that already exist in the profile's `common.zsh`.)

| Profile (class) | Actions (level-3) | Engagement | AI persona |
|---|---|---|---|
| **security** (NIGHTHACKER) | recon (scope-gated) · subdomain enum · web fuzz · **similar-site pivot** · new engagement | pentest workspace (`sec_engagement` — already exists) | recon/exploit assistant, OPSEC-aware |
| **cloud** (SKYSURFER) | switch AWS profile (fzf) · k8s context (fzf) · `tfp` plan · cost snapshot | account+region+cluster context | IaC / k8s troubleshooter |
| **cortex** (GHOST-IN-THE-XSIAM) | `xsoar-validate`/`upload` · `pan-connect` · open pan.dev docs · build deck | **customer tenant workspace** (replaces auto-cd footgun) | XSOAR/XSIAM playbook author (ties to `cortex-deck-builder` skill) |
| **homelab** (RACK-WIZARD) | live ops dashboard · `hstatus` (single-call) · **AI health triage** · service launcher · `hwake` | logged "change window" | SRE / ops responder |
| **blackwell** (PHOSPHOR-GHOST) | `bwstatus` · `bwtop` (nvtop) · `bwserve <model>` · GPU job kill | GPU job session | ML-infra assistant |
| **ai** (NEUROMANCER) | chat (host-routed) · model pull · embeddings index | inference context | — (is the persona engine) |
| **vault** (KNOWLEDGE-KEEPER) | capture note · **`claw recap`** (session → vault) · backlinks | active vault project | research/notes synthesizer |
| **pmo** (SCRIBE-OPERATOR) | Things sync · sprint view · capture todo | active sprint | planning assistant |

`vault` + `pmo` are the **compounding sinks**: every other profile's engagement
can emit findings to the vault / Things, so domain work becomes durable knowledge.

---

## 4. Full feature backlog (by axis)

The keystone (§2) makes most of these small, uniform additions.

### Visual
- **Live AI status row** in the header — Ollama up? model loaded? OpenRouter
  reachable? last Hermes latency. One fastfetch `command` module.
- **fzf preview pane** on hover — readiness (§2.2) + a one-line "use this when…".
- **Sixel/Kitty-graphics profile art** for modern terminals; ASCII fallback by `$TERM`.

### Practical
- **★ Natural-language command palette** — `claw do "…"` → local Hermes
  structured-output → maps to a `claw`/shell command → shows → confirm → run.
  Offline, zero-egress (OPSEC-clean).
- **Similar-site recon pivot** (security) — seed domain → related infra (crt.sh
  certs, favicon hash via Shodan, shared analytics/tracker IDs, ASN). **scope.txt
  gated** per default-deny policy → emit to vault `20-IOCs/`. (Depends on Phase 6
  OSINT MCPs.) *Marketing reading — "sites like X" via the connected SimilarWeb
  MCP — is a separate, smaller `research`/`pmo` action.*
- **Semantic alias/command search** — `claw find "copy to clipboard"` over
  `aliases.zsh` + profile fns + `claw` subcommands via local embeddings
  (`nomic-embed-text`).
- **`claw recap`** — summarize the shell session (history + `usage.tsv`) → vault note.

### Performance
- **★ Telemetry-driven menu ordering** — rank L1/L2 entries by `usage.tsv`
  frequency (most-used float up). Pure data, no model. Biggest daily-velocity win.
- **Instant-login budget (ADR)** — formalize login <100 ms; AI is lazy-on-invoke
  or background-warmed (bg-ping Ollama so first NL query is hot). Pattern exists
  in `tool-updater.sh`'s self-backgrounding.
- **Host/GPU-aware AI routing** — small/sensitive → local Hermes; large/complex →
  OpenRouter Opus; GPU-heavy → BD790i when `bwfree` shows VRAM. Both providers
  already wired.

---

## 5. Optimize · Compound · Mature

### 5.1 Optimize (performance)
- **Single-call homelab status** — `hstatus` currently fires **4 sequential SSH
  round-trips** ([homelab/mac.zsh:20-54](../../../shell/profiles/homelab/mac.zsh):
  `_hl_status_{tailscale,docker,k3s,ollama}` each call `_hl_ssh`). Collapse into
  one remote heredoc returning all four. 4×→1× latency. Same for `bwstatus`.
- **Cached, TTL'd readiness** — the picker preview must be instant; cache
  `_tool_check` output per shell with a short TTL, refresh in background.
- **Login budget guardrail** — nothing AI/network runs at login unless explicitly
  invoked (already true; make it an enforced ADR + a startup-time test).

### 5.2 Compound (capabilities that multiply each other)
- **Telemetry flywheel:** usage logging → menu ranking → AI "suggested next
  action." More use → better ranking → better suggestions.
- **Engagement → knowledge:** every domain engagement can emit to vault/Things,
  so recon/ops/cloud work compounds into a searchable corpus (feeds Smart
  Connections + `claw recap` + semantic search).
- **One AI-context → 17 copilots:** `PROFILE_AI_CONTEXT` gives every profile a
  scoped assistant from a single mechanism.
- **MCP leverage:** SimilarWeb / Shodan MCPs + Hermes compound the recon-pivot;
  the same routing serves the NL palette.

### 5.3 Mature (product hardening)
- **Fix the auto-cd inconsistency** — cortex (and any other) must not relocate on
  load; relocation moves to explicit engagement.
- **Dedup the copy-pasted renderers** — every profile hand-rolls
  `_<name>_tool_check` (identical ANSI + loop) and a `-help` card (re-declares
  colors + box-drawing). Extract `_claw_tool_check` + `_claw_help_card` into
  [`scripts/utils/tui-style.sh`](../../../scripts/utils/tui-style.sh); profiles
  feed a tool list + sections. Every profile gets thinner *and* consistent; new
  profiles get cheaper (compounding).
- **Contract validation in `test-runner`** — smoke-test that every profile's
  `PROFILE_ACTIONS` commands resolve and `PROFILE_READINESS` runs. Folds into the
  existing S9 quality-gate backlog (Things group B).
- **Graceful failure** — unreachable BD790i → clear message + offer `hwake`,
  never a silent hang.
- **Versioned contract + docs** — bump `docs/profiles/architecture.md` with the
  new schema fields; treat the contract as a stable interface.

---

## 6. Phased roadmap (gated)

Matches the repo's phase-gate convention. Each phase ships independently.

| Phase | Scope | Gate (done = ) | Depends on |
|---|---|---|---|
| **TUI-1 Foundation** *(keystone)* | `PROFILE_ACTIONS` schema · 3-level TUI · readiness preview · shared renderers · fix auto-cd | every profile exposes ≥1 action; picker preview shows live readiness; no profile relocates on load; tool-check/help dedup'd | — |
| **TUI-2 Engagement & telemetry** | unified `claw engage` · telemetry-driven menu ordering · login-budget ADR | engagement explicit + uniform; menu reorders by usage; login <100 ms measured | TUI-1 |
| **TUI-3 AI layer** | NL command palette · profile-scoped persona · host/GPU routing | NL→command works offline; persona scoped per profile; routing picks local/BD790i/OpenRouter correctly | Hermes activation (spec-integration Phase 5) |
| **TUI-4 Domain flows** | homelab ops cockpit · similar-site recon pivot · semantic alias search · `claw recap` | each flow demoed E2E; recon-pivot respects `scope.txt` | TUI-3; OSINT MCPs (Phase 6) for recon |
| **TUI-5 Visual polish** | AI status row · Sixel/Kitty art | graceful fallback verified on non-graphics terminals | TUI-1 |

**Sequencing note:** TUI-1 is the keystone — ~70% of the backlog rides the
contract. TUI-3/4 align with the existing spec-integration Phase 5/6 gates, so
the AI substrate and OSINT MCPs land before the features that need them.

---

## 7. Open questions (for operator review)

1. **Similar-site:** confirm the **recon-pivot** (security/OSINT) reading is
   primary, with the SimilarWeb "competitive" reading as a secondary `research`
   action? (Assumed yes given the OPSEC/recon lean.)
2. **Level-3 UX:** a true third fzf level, or preview-with-keybindings at level-2
   (`enter` = load, `ctrl-a` = actions menu)? Affects keystroke economy.
3. **Gating:** does TUI v2 wait behind the S9 quality gates (Things group B), or
   proceed in parallel with the contract-validation test as its own gate?
4. **Engagement ↔ session banner:** should `claw engage` feed the existing
   session-name banner (`CLAW_ACTIVE_GROUP` + tmux identity) so the active
   engagement shows in the prompt/title?

---

## 8. Non-goals (YAGNI)

- No rewrite of the existing two-level TUI — v2 is **additive** per
  `spec-integration.md` §4 ("welcome TUI / claw functions / fastfetch profiles
  stay as-is; new functions register alongside").
- No community/multi-user features — this is single-operator (per project memory).
- No new daemon — AI runs through the already-wired `bin/hermes` / `bin/openrouter`.
