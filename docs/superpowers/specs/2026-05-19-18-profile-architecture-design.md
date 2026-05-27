# 18-Profile Architecture + Cinematic Coverage + VHS Captures

**Date:** 2026-05-19
**Status:** Pending review
**Builds on:** `2026-04-25-claw-mvp-rewrite-design.md` (kept 9 profiles, agent registry, `claw` entry point)

## Summary

Expand from 9 profiles to **18**, restructure each into per-OS sub-files (Mac/Linux), propagate the existing cinematic theme system to every visual surface (profile activation, welcome TUI, fastfetch, toolchain installers, `claw doctor`), and ship a **VHS terminal-capture suite** that triple-duties as documentation, user guidance, and visual regression testing for terminal UX.

The 9 new profiles fill workflow gaps the current set doesn't serve (Obsidian knowledge work, customer-facing deck/demo prep, BD790i homelab ops, Blackwell GPU/ML, SSH/tunnel orchestration, project management, ideation, visual design). The architecture change accepts that the same profile (`cloud`, `security`, etc.) needs slightly different tools on Mac vs Linux while preserving identical *purpose*.

## Problem

Six concrete gaps in the current state:

1. **Workflow coverage gaps** — 5-6 menu items in `welcome-tui.zsh` (`vault`, `homelab`, `tunnels`, `mcp`, `agents`) are profile-shaped but never got promoted: no class, no logo, no fastfetch dashboard, no toolchain installer. Plus four genuinely missing profiles (deck, design, demo, blackwell, brainstorm, pmo) tied to actual daily workflows.
2. **Single-OS assumption per profile** — existing profile files assume macOS-ish defaults with `platform.zsh` shims for primitives. Tools that diverge in name (`netcat` brew vs `ncat` apt, `gnu-sed` vs `sed`, `john-jumbo` vs `john`) get no per-OS treatment.
3. **Aesthetic coverage stops at onboarding** — the theme + animation system (`onboarding.sh`) only fires once per first-run. Profile activation (`claw load X`), welcome TUI, toolchain installers, fastfetch dashboards, `claw doctor` are all visually inert.
4. **No deliverable that proves the polish shipped** — claims like "cinematic profile activation" have no artifact a reviewer can watch. Pre-merge polish reviews are gut-feel rather than evidence.
5. **No regression detection for terminal UX** — a one-character change in `_anim_drumroll` could silently break the class reveal animation. No way to notice short of running the full onboarding flow manually.
6. **Mac-as-cockpit is implicit** — Tailscale is configured, SSH ControlMaster works, but no profile encodes "I'm on the Mac, the work runs on the BD790i, route accordingly." Homelab and Blackwell profiles need to mean different things on each end.

## Goals

1. **18 fully-realized profiles**, each with: dedicated class name, distinct visual identity, per-OS tool variant, fastfetch dashboard, optional toolchain installer.
2. **Per-OS sub-file architecture** — same profile purpose on Mac and Linux, divergent tool sets handled cleanly via `shell/profiles/<name>/{mac,linux}.zsh`.
3. **Theme propagation to every visual surface** — onboarding, profile activation, welcome TUI, fastfetch, toolchain banners, `claw doctor`.
4. **VHS capture suite** rendering ~32 deterministic GIFs covering all profiles, themes, and aesthetic improvements. Captures triple-duty as: GitHub-rendered docs, user-guidance gallery, and visual regression test fixtures.
5. **Backward compatibility** — existing 9 profile files keep working during migration. New 9 ship in the new pattern from day one; existing 9 migrate lazily.

## Non-Goals

- Full Tailscale ACL / subnet-routing optimization — deferred to a follow-up spec (`2026-05-XX-mac-as-cockpit-design.md`). This spec notes the requirement and leaves hooks for it but does not implement it.
- Adding a TOML/YAML manifest parser to the shell load path (the manifest stays as `meta.zsh` — pure bash, no parser dependency).
- Multi-agent composition (`claw claude+hermes`) — same defer as the prior MVP spec.
- Removing or renaming any existing profile.
- Building a GUI/web interface for profile selection (CLI-only).

## Design

### § 1 · Per-OS Sub-File Architecture

Each profile becomes a *directory* plus a thin dispatcher file:

```
shell/profiles/
├── cloud.zsh                  # ← 4-line dispatcher
└── cloud/                     # ← profile assets
    ├── meta.zsh               # PROFILE_CLASS, _THEME, _TAG, _OS_SUPPORT, _TOOLCHAIN
    ├── common.zsh             # shared aliases/exports/help fn
    ├── mac.zsh                # macOS-only aliases + tool checks
    ├── linux.zsh              # Linux-only aliases + tool checks
    └── logo.txt               # ASCII splash (referenced by fastfetch + claw load)
```

**Dispatcher template** (`shell/profiles/cloud.zsh`, 4 lines):

```zsh
_PROFILE_DIR="${0:A:h}/cloud"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
```

`OS_FAMILY` is a new global exported by `shell/platform.zsh`, derived once from existing `OS_TYPE`:

```zsh
case "$OS_TYPE" in
    macos)                       export OS_FAMILY="mac" ;;
    ubuntu|debian|parrot|kali)   export OS_FAMILY="linux" ;;
    fedora|rhel|centos|arch)     export OS_FAMILY="linux" ;;
    *)                           export OS_FAMILY="generic" ;;
esac
```

### § 2 · Manifest Schema (`meta.zsh`)

Pure bash — no parser dependency. Each profile declares:

```zsh
# shell/profiles/cloud/meta.zsh
PROFILE_NAME="cloud"
PROFILE_CLASS="SKYSURFER"
PROFILE_THEME_DEFAULT="synthwave"        # synthwave | matrix | dosbbs | vhs
PROFILE_TAG="boots up clusters before breakfast"
PROFILE_FLAIR="owns 4 TLDs you've never heard of"
PROFILE_OS_SUPPORT="mac linux"           # which OSes have a full implementation
PROFILE_TOOLCHAIN="cloud-toolchain.sh"   # script name; empty if N/A
PROFILE_KEY_TOOLS="kubectl terraform aws gcloud az helm"  # for `claw doctor`
PROFILE_TIER="2"                         # 1=general, 2=domain, 3=agent, 4=knowledge, 5=customer, 6=hardware
```

Consumers:
- `claw doctor` introspects `PROFILE_KEY_TOOLS` to render health
- `claw load <name>` reads `PROFILE_CLASS`, `PROFILE_THEME_DEFAULT`, `PROFILE_TAG`, `PROFILE_FLAIR` for the activation ceremony
- Welcome TUI auto-populates menu from `meta.zsh` files (replaces hand-written `choices+=` block)
- Fastfetch config can `$()` interpolate the class name into its module strings

### § 3 · 18-Profile Roster

| # | Profile | Class | Theme | OS Support | Toolchain | Tier |
|---|---|---|---|---|---|---|
| 1 | default | PIXEL-DRIFTER | synthwave | mac+linux | — | 1 |
| 2 | local | GARAGE-HACKER | dosbbs | mac+linux | — | 1 |
| 3 | cloud | SKYSURFER | synthwave | mac+linux | ✅ cloud | 2 |
| 4 | devops | WRENCH-MAGE | synthwave | mac+linux | ✅ devops | 2 |
| 5 | security | NIGHTHACKER | matrix | mac+linux | ✅ security | 2 |
| 6 | cortex | GHOST-IN-THE-XSIAM | matrix | mac+linux | ✅ cortex | 2 |
| 7 | ai | NEUROMANCER | matrix | mac+linux | ✅ ai | 2 |
| 8 | research | DATA-DJ | dosbbs | mac+linux | ✅ research | 2 |
| 9 | claude | PROMPT-RIDER | synthwave | mac+linux | — | 3 |
| 10 | **vault** | **KNOWLEDGE-KEEPER** | dosbbs | mac+linux | **NEW** vault | 4 |
| 11 | **brainstorm** | **SPARK-CATCHER** | vhs | mac+linux | **NEW** brainstorm | 4 |
| 12 | **pmo** | **SCRIBE-OPERATOR** | dosbbs | mac-primary | **NEW** pmo | 4 |
| 13 | **deck** | **DECK-SMITH** | vhs | mac+linux | **NEW** deck | 5 |
| 14 | **design** | **FRAME-SMITH** | vhs | mac+linux | **NEW** design | 5 |
| 15 | **demo** | **SHOW-RUNNER** | synthwave | mac+linux | **NEW** demo | 5 |
| 16 | **homelab** | **RACK-WIZARD** | matrix | mac=remote, linux=native | **NEW** homelab | 6 |
| 17 | **blackwell** | **PHOSPHOR-GHOST** | matrix | mac=remote, linux=native | **NEW** blackwell | 6 |
| 18 | **tunnels** | **PORT-RUNNER** | matrix | mac+linux | **NEW** tunnels | 6 |

**Tier conventions** for menu grouping:
- 1: general-purpose dev (always available)
- 2: domain expertise (cloud / security / etc.)
- 3: agent / IDE workflow (claude)
- 4: knowledge & ideation (vault / brainstorm / pmo)
- 5: customer-facing & visual (deck / design / demo)
- 6: hardware & ops (homelab / blackwell / tunnels)

**OS-support semantics:**
- `mac+linux` — full parity, slightly different toolsets
- `mac=remote, linux=native` — Linux runs the real workload; Mac variant is the cockpit (SSH wrappers, status panes, remote launchers). Applies to homelab + blackwell.
- `mac-primary` — primary OS only; other OSes get a stub with explanatory help (applies to pmo because Things 3 is macOS-only)

### § 4 · Theme Propagation Matrix

Every visual surface gets cinematic treatment:

| Surface | Theme awareness | Animations | Implementation |
|---|---|---|---|
| Onboarding (`onboarding.sh`) | ✅ existing | ✅ existing | already shipped |
| `claw load <profile>` | NEW | NEW | sources `cinematic-lite` helpers; reads `PROFILE_THEME_DEFAULT`; supports `CLAW_THEME=matrix claw load cloud` override |
| Welcome TUI (`welcome-tui.zsh`) | NEW | NEW | typewriter section headers, palette inherits from `CLAW_THEME` env or saved onboarding choice |
| Toolchain installers (15 total) | ✅ existing | ✅ existing | already done via `toolchain-runner.sh` |
| Fastfetch (18 configs) | NEW (per-theme palette) | N/A (static) | generated configs per `(profile, theme)` pair = 72 variants; saved at `config/.config/fastfetch/config-<profile>-<theme>.jsonc` |
| `claw doctor` | NEW | NEW (optional) | themed section headers, animated tool-status checks |
| Integrity check | NEW | NEW (optional) | forensic-style "AUDIT REPORT" framing, themed |

**Cinematic helper extraction:** Currently `onboarding.sh` and `toolchain-runner.sh` each have their own copies of `_anim_type`, `_anim_pause`, `_banner`, etc. With this expansion adding 4+ more consumers, extract to `scripts/utils/cinematic.sh` — single source of truth, sourced by all consumers.

**Theme defaults vs. user override:** Each profile declares a *preferred* theme in `meta.zsh` (`PROFILE_THEME_DEFAULT`). User overrides via `CLAW_THEME=matrix` env (one-shot) or via onboarding's persisted theme choice (sticky).

### § 5 · VHS Capture System

Captures triple-duty as **docs**, **user guidance**, and **visual regression tests** for terminal UX. Modeled on Playwright's record/replay pattern.

#### Layout

```
captures/
├── tapes/                                # source — committed
│   ├── onboarding/
│   │   ├── full.tape                     # ~90s arcade flow
│   │   ├── theme-synthwave.tape          # splash variants per theme
│   │   ├── theme-matrix.tape
│   │   ├── theme-dosbbs.tape
│   │   └── theme-vhs.tape
│   ├── profiles/
│   │   ├── cloud.tape                    # 18 profile activations
│   │   └── ... (18 total)
│   ├── toolchains/
│   │   ├── cloud.tape                    # 9 toolchain installer banners
│   │   └── ... (9 total)
│   ├── showcase/
│   │   ├── glitch-transition.tape
│   │   ├── animated-scoreboard.tape
│   │   ├── drumroll-reveal.tape
│   │   ├── crt-boot.tape
│   │   └── score-bar-fill.tape
│   └── welcome-tui.tape                  # themed FZF dashboard
├── gifs/                                 # rendered output — committed (via git-lfs)
│   ├── onboarding/full.gif
│   ├── profiles/cloud.gif
│   └── ... (~37 total)
├── render-all.sh                         # local + CI rendering
├── diff-against-baseline.sh              # regression detection
└── README.md                             # gallery for GitHub Pages
```

#### Tape file conventions

Every profile-activation tape follows the same structural arc:

```bash
# captures/tapes/profiles/vault.tape
Output captures/gifs/profiles/vault.gif
Set FontSize 16
Set Width 1200
Set Height 700
Set TypingSpeed 50ms
Set Theme "Dracula"

# 1. Cold prompt
Type "claw load vault"
Sleep 500ms
Enter

# 2. Activation ceremony plays
Sleep 5s

# 3. Fastfetch dashboard
Sleep 2s

# 4. Signature command — proves the profile does its job
Type "vault search 'cortex deck system'"
Sleep 1s
Enter
Sleep 3s

Sleep 1s
```

A `captures/tapes/lib/profile-template.tape` defines a reusable header so individual tapes stay compact.

#### Rendering

- `render-all.sh` — single command, renders all 37 tapes to `captures/gifs/`. Estimated 5-10 min on Mac (~30s per GIF average).
- CI workflow renders on PR, posts a comment with the gallery, fails if a tape errors out.
- `render-all.sh --only profiles/cloud` for incremental work.

#### Regression detection

- `diff-against-baseline.sh` runs `imagemagick compare -metric AE` on every (current, baseline) pair, prints divergence as % pixels differing.
- > 5% diff = flagged for human review (intentional or regression?).
- New tape or intentional change → reviewer runs `update-baseline.sh <tape>` to bless it.
- This is *visual regression testing for terminal UX*. The same engineering rigor applied to Playwright web tests, applied to CLI.

#### Distribution

1. **In-tree** — `.tape` source + rendered `.gif` committed (with `git-lfs` for GIFs > 1 MB). Repo size impact estimated < 20 MB.
2. **GitHub Releases** — every tagged release attaches the full `captures/gifs/` directory as a release asset. Direct linkable.
3. **GitHub Pages** — `captures/README.md` becomes the "Profile Gallery" page on `henryreed.github.io/dot-files/captures/`. Public-facing user guidance.
4. **Welcome TUI preview** — hovering a menu item opens the matching GIF via `kitty +kitten icat captures/gifs/profiles/<name>.gif` (or `imgcat` on iTerm). Inline visual onboarding.
5. **`claw demo <profile>`** subcommand — opens the GIF in the system viewer.

### § 6 · Mac-as-Cockpit (Note, Defer to Follow-up Spec)

User intent: Mac is the operator's seat; BD790i (and any future workstation) is where workloads run; Tailscale is the spine. Profiles like `homelab` and `blackwell` on Mac should be *remote-control variants* that SSH/Tailscale into the real machine.

**In scope for this spec:**
- `PROFILE_OS_SUPPORT="mac=remote, linux=native"` semantic encoded in `meta.zsh`
- `homelab/mac.zsh` and `blackwell/mac.zsh` files exist and contain SSH-wrapper aliases (`alias nvtop='ssh bd790i nvtop'`, `alias k='ssh bd790i microk8s kubectl'`)
- `tunnels` profile gets first-class treatment

**Deferred to `2026-05-XX-mac-as-cockpit-design.md`:**
- Optimized Tailscale ACL configuration
- Subnet route advertisement strategy
- Centralized known-host registry (`~/.config/claw/workstations.toml`)
- `claw remote <workstation> <command>` subcommand
- File sync helpers (rsync over tailscale, mutagen)
- Mosh integration for high-latency control

That spec gets brainstormed separately so this one doesn't drag.

### § 7 · Migration Plan

**Phase A — Foundation (1 session)**
- Add `OS_FAMILY` derivation to `shell/platform.zsh`
- Extract cinematic helpers to `scripts/utils/cinematic.sh`
- Write dispatcher template + manifest schema docs
- Migrate `cloud` (existing) to per-OS sub-files as reference
- Migrate `security` (existing) — second proof, matrix theme variant
- Update `.zshrc` profile-loading logic if needed (dispatcher should be drop-in)

**Phase B — New profiles (3-4 sessions, batch by tier)**
- B1: Tier 4 — vault, brainstorm, pmo (knowledge/ideation)
- B2: Tier 5 — deck, design, demo (customer-facing)
- B3: Tier 6 — homelab, blackwell, tunnels (hardware/ops)

Each profile delivers:
- `meta.zsh` + `common.zsh` + `mac.zsh` + `linux.zsh` + `logo.txt`
- Fastfetch config + per-theme variants
- Toolchain installer (where applicable)
- Welcome TUI menu entry
- Onboarding quiz hooks (so the quiz can route users to new profiles)

**Phase C — Migrate remaining 7 existing (2 sessions)**
- default, local, devops, cortex, ai, research, claude → per-OS pattern

**Phase D — Aesthetic propagation + VHS captures (2-3 sessions)**
- `claw load <profile>` ceremony
- Welcome TUI theming
- Fastfetch per-theme palette generation
- `claw doctor` themed sections
- VHS capture suite (37 tapes rendered + diff-baseline scripted)
- GitHub Pages gallery setup

### § 8 · Backward Compatibility

The new pattern is **additive**, not breaking:

- Dispatcher `shell/profiles/<name>.zsh` continues to be the source-target — existing `.zshrc` profile-loading code doesn't change.
- If a profile dir doesn't exist yet (migration incomplete), the flat `<name>.zsh` file works as it does today.
- `welcome-tui.zsh` auto-populates from `meta.zsh` files **if present**; falls back to the hand-written `choices+=` block otherwise.
- Existing tests / Things 3 backlog / docs referencing the 9 profiles by name remain accurate.

### § 9 · Risks & Open Questions

| Risk | Severity | Mitigation |
|---|---|---|
| 18 profiles is sprawl, some won't get daily use | Medium | Tier system makes light-use profiles discoverable but not obtrusive; defer-on-demand activation means no perf cost from non-active profiles |
| Per-OS sub-files = 18 × 4 = 72 small files, harder to grep | Low | `claw doctor` shows the active profile's full asset tree; `meta.zsh` headers make purpose obvious |
| VHS regression diffing produces false positives on font/terminal-emulator differences | Medium | Pin VHS terminal emulator version in `render-all.sh`; baseline gets a "rendered on" header for reproducibility audits |
| Cinematic everywhere becomes annoying on repeat use | Medium | All animations honor `CLAW_NO_ANIM=1` env opt-out; non-tty runs already skip animations |
| Theme + class + tier × 18 profiles creates a combinatorial nightmare for documentation | Low | Single source of truth in `meta.zsh`; docs auto-generated by `claw doctor list` |

**Open questions** (answer during Phase A):
1. Should `meta.zsh` be sourced into the *current* shell or via subshell? (sourcing pollutes env; subshell loses speed)
2. Does fastfetch support our 4-theme palette swap via a single config + env vars, or do we genuinely need 72 generated files? (preliminary research suggests latter — confirm)
3. Where does the user override `CLAW_THEME` persistently? `~/.config/claw/theme` flat file or zsh export in `.zshrc`?

## Follow-up Work

After this spec ships:

- **`2026-05-XX-mac-as-cockpit-design.md`** — Tailscale ACLs, `claw remote`, workstation registry, file sync
- **`2026-06-XX-onboarding-routing-design.md`** — onboarding quiz updated to route to all 18 profiles (currently routes to 9)
- **`2026-07-XX-profile-marketplace-design.md`** — eventually: community-contributed profiles, plugin pattern (not committed to)

## Implementation Plan Decomposition

This spec is too large for a single implementation plan. It produces **four phase-scoped plans**, each independently shippable:

| Plan | Source phase | Estimated effort | Acceptance gate |
|---|---|---|---|
| `2026-05-XX-phase-a-foundation-plan.md` | Phase A (§7) | 1 session | `cloud` + `security` migrated, `OS_FAMILY` shipped, cinematic helpers extracted, docs landed |
| `2026-05-XX-phase-b-new-profiles-plan.md` | Phase B (§7) | 3-4 sessions | All 9 new profiles ship: meta/common/mac/linux/logo + toolchain + fastfetch + welcome-tui entry |
| `2026-05-XX-phase-c-migrate-existing-plan.md` | Phase C (§7) | 2 sessions | Remaining 7 existing profiles use per-OS pattern |
| `2026-05-XX-phase-d-aesthetic-vhs-plan.md` | Phase D (§7) | 2-3 sessions | `claw load` ceremony · welcome TUI theme · `claw doctor` · 37 VHS captures · GitHub Pages live |

The `writing-plans` skill should be invoked **once per phase** as work progresses. Phase A's plan gets written immediately after this spec ships; Phase B's plan gets written after Phase A's acceptance gate clears; and so on. This avoids planning ahead of validated assumptions.

## Acceptance Criteria

This spec is considered shipped when:

- [ ] All 18 profiles have full directory structure with `meta.zsh` + `common.zsh` + `mac.zsh` + `linux.zsh` + `logo.txt`
- [ ] 9 new toolchain installers live in `scripts/install/` following the established `toolchain-runner.sh` pattern
- [ ] `claw doctor` reports correctly for any active profile on Mac and Linux
- [ ] `claw load <profile>` plays the cinematic activation ceremony on a tty, falls through silently otherwise
- [ ] Welcome TUI auto-populates from `meta.zsh` files
- [ ] All 37 VHS captures render successfully via `render-all.sh`
- [ ] `diff-against-baseline.sh` reports zero unexpected diffs on a clean build
- [ ] GitHub Pages gallery is live at the project's pages URL
- [ ] BD790i validates: running `claw load homelab` from Mac SSHes correctly and shows live K3s/Tailscale status

---

**Author:** Henry Reed (collaboratively with Claude)
**Reviewers:** Henry (single-user project)
**License:** Same as repo
