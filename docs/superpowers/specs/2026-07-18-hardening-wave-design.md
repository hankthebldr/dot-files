# Hardening Wave — Finish-Wire the Declared Contracts

- **Status:** Approved (operator, 2026-07-18)
- **Provenance:** ultracode audit pass 2026-07-18 (23 agents: 8 subsystem
  auditors + backlog miner + consolidator + 3-lens judge panel + 10 adversarial
  verifiers; all 10 improvement claims CONFIRMED, zero refuted).
- **Theme:** every defect below is a contract that exists but was never wired
  end-to-end. Seven sections, each independently committable, security first.
- **Sequencing:** this wave lands before the fast-first login-perf feature spec
  (ranked #1 by the judge panel; designed separately).

## 1. Hook integrity (security-critical)

### 1a. Registration fix — the generated-file guard is dead code
`claude/install-hooks.sh:43` registers PreToolUse with matcher `"Bash"` only,
so the Edit/Write guard added in `dfa26d6` (pre_tool_use.py:132-141) never
fires. Verified against the deployed `~/.claude/settings.json`.

- Add a second `ensure()` call: PreToolUse, matcher
  `Edit|Write|MultiEdit|NotebookEdit`, same command. `ensure()` is already
  additive/idempotent.
- Re-run the installer so the deployed settings pick it up.
- Add the same generated-fastfetch path check to the **Bash branch** of
  `pre_tool_use.py` (catches `sed -i .../config-ai.jsonc` shell-side edits).

### 1b. Recon scope bypass — prefix/chaining defeats the check
`pre_tool_use.py` scope-checks only when `argv[0]` is a recon tool. Verified
bypasses: `sudo nmap evil.com`, `true; nmap evil.com`, `VAR=x nmap evil.com`.

Rewrite the check to:
1. Split the command into segments on `;`, `&&`, `||`, `|`, `$(…)`, backticks.
2. Per segment, strip leading `VAR=value` env assignments and wrapper commands
   (`sudo`, `env`, `command`, `nohup`, `timeout`, `nice`, `xargs`, `doas`).
3. Match each segment's resulting first token (basename) against `RECON_TOOLS`;
   any hit triggers target extraction + scope validation for that segment.

Regression tests: the three verified bypass shapes plus a pipeline case
(`echo x | nmap …`), piped as JSON to the hook, asserting exit 2. Wire into
CI's python job.

### 1c. secret.sh option leak — armed shell-killer
`shell/load-env.zsh:44-45` sources `scripts/utils/secret.sh`, which runs
`set -uo pipefail` (line 16); the options persist in the interactive shell
(verified by live repro). Latent only because `config/secrets/.env.sops`
doesn't exist yet — the first `claw secret env` arms it, after which every
new shell runs under nounset and dies on the first unset-param expansion.

Fix: `load-env.zsh` stops sourcing; it runs the secret decrypt as a
**subprocess that emits `export KEY=VAL` lines** and `eval`s the output.
`set -uo pipefail` stays confined to the subprocess. (Verifier-endorsed;
save/restore-options in zsh is the rejected fiddlier alternative.)

## 2. aliases.zsh dedupe

`shell/aliases.zsh` carries a dead legacy `claw()` (~lines 446-496, dead-
shadowed by claw-fn.zsh — spine-invariant-#1 violation) and a "SMART
FUNCTIONS" block (~761-852) whose duplicate definitions win over earlier,
stronger copies: `extract()` (live regression — `.tar.xz`/`.tar.zst` broken
today), `fkill()` (lost multi-select/preview/theming), `serve()`/`mkcd()`
(equivalent, cosmetic).

- Delete the legacy `claw()` block and the SMART FUNCTIONS duplicates,
  keeping the earlier stronger copies.
- Bats guard test: exactly one definition each of `claw`, `extract`, `fkill`
  across `shell/` (greps definition sites, not call sites).

## 3. Profiles contract + `claw profiles lint`

Confirmed breaks (honest severity: medium — guidance UX, nothing crashes):
- `shell/profile-helpers.zsh:47` gates the install hint on
  `CLAW_PROFILE_TOOLCHAIN` — a variable set nowhere (metas set
  `PROFILE_TOOLCHAIN`). Hint never renders for the 8 generic-check profiles.
- `shell/claw-fn.zsh:86` nudges `claw install <profile>` assuming
  slug == profile name — wrong for blackwell (`ai-workstation-toolchain.sh`),
  nonexistent for default/local/claude/pmo/tunnels.
- `brainstorm`/`vault` metas declare toolchain scripts that don't exist.
- `shell/welcome-tui.zsh:583` prints the raw filename as a non-runnable
  "install" command.

Fixes:
- Correct the variable name at profile-helpers.zsh:47.
- Both nudge surfaces derive the install slug from `PROFILE_TOOLCHAIN`
  (strip `-toolchain.sh`), and suppress entirely when empty or the script is
  missing.
- Clear the phantom brainstorm/vault declarations (set `""`).
- **`claw profiles lint`** (new subcommand, rides the fix wave at S-effort):
  mechanically validates all 18 metas — declared toolchain resolves on disk,
  help cmd defined, tool_check defined, no unread fields (PROFILE_FLAIR /
  PROFILE_TIER get either a consumer or removal — default: keep, document as
  reserved). Run in CI so the bug class stays dead.

## 4. Install path repairs

- `bootstrap.sh:280` — gate `brew install bash` on **version** (probe
  `BASH_VERSINFO[0] >= 4`), not `command -v bash` (always true on macOS).
  Without this every `claw install <toolchain>` hard-fails on a fresh Mac.
- `scripts/install/provision.sh:36` — eval `brew shellenv` (with the
  absolute-path fallback) immediately after installing Homebrew, mirroring
  bootstrap.sh:166-176's documented fix.
- `scripts/install/cloud-toolchain.sh:40` — kubectl fallback
  `curl:https://dl.k8s.io/release/stable.txt` installs a version-string text
  file as the kubectl binary, then self-masks (`command -v` succeeds forever
  after). Change to `none`, matching devops-toolchain.sh:56.
- `cloud-toolchain.sh:60` — aws-iam-authenticator URL 404s. Set `none` (fails
  loudly today, but the row is dead weight).
- `scripts/install/lib/toolchain-runner.sh` — implement the `cargo:<crate>`
  fallback case (grammar is used by clin-rs and tealdeer rows but the runner
  only matches literal `cargo)`). Un-deads the documented clin install path.
- git-delta probe: probe the real binary name `delta` (kills the no-op brew
  re-invocation every run).

## 5. pkg track de-poisoning

Root cause of the parked `tools.list` stash (memory:
`project_tools_list_capture_noise`), confirmed end-to-end:
- `scripts/utils/pkg-manifest.sh:80` `_discover` — skip executables whose
  symlink target resolves under `~/.local/pipx/`, `~/.local/share/uv/`,
  `~/.local/share/claude/` (entry-point shims, not standalone tools).
- `pkg-manifest.sh:142` `_infer_source` — unknown user-dir binaries get
  tagged `manual`, never bare `eget` (eget requires `owner/repo`; bare
  invocations can never install).
- `pkg-manifest.sh:190` `_install_via` — `manual` rows are skip-with-note.
- Then drop the poisoned stash **with operator sign-off** (the wave's one
  destructive step; the committed tools.list is still clean).

## 6. Theme split-brain repair (defect half only)

- Migrate the 4 flat `.theme` files (matrix / synthwave / vhs / dosbbs — the
  themes every one of the 18 profiles declares via PROFILE_THEME_DEFAULT)
  into the `config/themes/<slug>/palette.theme` directory layout. Slugs are
  unchanged → zero profile-meta edits. Render each `ghostty.conf` via
  `theme.sh ghostty <slug>`.
- Make the three single-path readers two-path resolvers, matching
  `_claw_theme_file`: `tui/claw-tui/src/theme.rs:63`, `claw_theme_list`
  (theme.sh:96), `claw_theme_build` (theme.sh:199). A straggler flat file can
  then never go invisible again. Add a rust `#[test]` for both layouts.
- TUI exit fix: "skip" emits `Outcome::None` instead of `ACTION skip`
  (main.rs:226 / confirm()) — kills the "unknown subcommand or agent: skip"
  error on the explicit exit item.

Out of this section (deferred to the theme feature spec): fzf live-swatch
picker, NO_COLOR/CLICOLOR_FORCE degradation contract, fastfetch accent
parameterization.

## 7. Docs truth-up

- ULTRAPLAN.md: check the three stale-done boxes (selfupdate timer,
  capture-tasks, /handoff skill); annotate TUI M2 as mostly-landed.
- CLAUDE.md: update the profile-system section to the directory-per-profile
  reality (meta/common/mac/linux behind a 5-line dispatcher).
- knowledge-base/: bump `updated` on any note the wave's changes touch.
- DEFERRED.md: log anything deliberately not fixed here.

## Testing

Per-section regression tests where cheap (hook bypass JSON cases, alias
single-definition guard, profiles lint in CI, theme two-path bats + rust
test). Every commit keeps `bats tests/`, `zsh -n`, shellcheck error tier, and
`cargo clippy -D warnings` green. The post-edit lint hook (64c25ef) enforces
the shell tiers at edit time.

## Out of scope

Fast-first login perf (next spec), telemetry surfacing, `claw harness doctor`,
update-loop unification, TUI M2 polish, `claw intro`, Ghostty experience
overhaul (separate spec, in design).

## Commit plan

One commit per section minimum; section 1 splits into 1a/1b/1c. Named-file
staging throughout. No PR until asked.
