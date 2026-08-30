# claw update — one engine, phased daily ops · Implementation Plan

> **For agentic workers:** Tasks 1–5 have **disjoint file ownership** and are safe
> to implement in parallel. Do NOT run `git commit`/`git push` from a worker —
> the orchestrator commits after the integration gate (Task 6). Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the four update engines behind `claw update` into one
(topgrade-first `system-update.sh`), add a repo-sync phase so the dotfiles
update *themselves*, merge the parallel tool registry into
`config/manifest/tools.list`, and make update state visible (updates.json →
situation/ff-readout/doctor) with a receipt per run.

**Design:** `docs/superpowers/specs/2026-08-17-claw-update-one-engine-design.md`
(interfaces, JSON/TSV shapes, cadence table — normative; read it first).

## Global Constraints

- **bash 3.2 compatible** (stock macOS): no associative arrays, no `${var^^}`,
  no negative array offsets. Guard empty-array expansions.
- **Never hardcode colors** — theme via `theme.sh` (`CLAW_RGB_*`) and
  `claw-progress.sh` `_c`; streaming steps via `claw_step` (no `gum spin` on
  update paths).
- **No stdout pollution** from anything sourced/kicked in shell init.
- **Portability:** `timeout` needs the gtimeout shim (copy the `situation.sh`
  pattern); `date +%s` only (no `%N`); BSD vs GNU awk/sed-safe.
- **Cache/state paths:** `~/.cache/claw/` (`updates.json`, `updates.tsv`)
  via `${XDG_CACHE_HOME:-$HOME/.cache}/claw`.
- **Tests:** `bats tests/<suite>.bats`; fake external commands with PATH-stub
  dirs (see `tests/fixtures/`); `shellcheck -x` on every touched script.
- **Receipt row:** `ISO-ts \t trigger \t duration_s \t ok|fail \t detail`.

---

### Task 1: Engine — topgrade-first `system-update.sh` + sweep fixes

**Files:** `scripts/utils/system-update.sh` · Create: `config/topgrade.toml`,
`tests/update-engine.bats`

**Interfaces:** argv `--non-interactive`, `--dry-run`; env
`CLAW_UPDATE_TRIGGER` (default `manual`) stamped into the receipt; exit ≠0 iff
a step failed; appends one receipt row to `~/.cache/claw/updates.tsv`.

- [ ] `config/topgrade.toml`: conservative declarative config — disable
  `containers`, `git_repos`, `system` steps that duplicate repo-sync; keep
  brew/apt/npm/pipx/uv/cargo/rustup/gem/omz/flatpak/snap/firmware coverage
  aligned with today's sweep. Comment every disable with a why.
- [ ] Topgrade path: when `command -v topgrade`, render header via
  `claw_ui_header`, run ONE streamed step
  `claw_step "topgrade…" -- topgrade --config "$DOTFILES/config/topgrade.toml" -y`
  (plus `--dry-run` passthrough `-n`), footer, receipt, exit. Fallback: the
  existing sweep.
- [ ] Sweep fixes: `sudo -v` upfront (+ keepalive loop, killed on EXIT trap)
  only when apt/dnf/pacman/snap present and not `--dry-run`; drop
  `go clean -modcache` (keep a dim note); `gem update --system` →
  `gem update`; `--dry-run` prints each planned step (`claw_ui_skip`-style,
  no execution); `--non-interactive` keeps today's semantics (no clear/pause).
- [ ] Receipt: duration via `SECONDS`, detail like `engine=topgrade` /
  `engine=sweep steps=12 fail=1`.
- [ ] Tests (`tests/update-engine.bats`): topgrade stub gets invoked with the
  repo config; `--dry-run` executes nothing (stub records calls); receipt row
  appended with 5 tab-separated fields; failing stub → exit ≠0 + `fail` row;
  no `go clean` / `gem update --system` strings remain; shellcheck clean.

### Task 2: Front door phases + repo-sync + timer re-point

**Files:** `bin/claw` (sole owner) · `scripts/utils/selfupdate.sh` · Create:
`scripts/utils/repo-sync.sh`, `tests/repo-sync.bats`

**Interfaces:** `repo-sync.sh [--dry-run]` per design (ff-only, conservative,
conditional regen, receipt row, prints `repo: …` status line);
`claw update` orchestrates repo→packages; `claw update --last` pretty-prints
the last ≤5 receipt rows.

- [ ] `repo-sync.sh`: dirty tree or no-upstream or diverged → `repo: skipped
  (<reason>)`, exit 0. Else fetch + `git pull --ff-only`; on change compute
  `git diff --name-only <old>..<new>` and run only matching regens:
  `scripts/utils/gen-fastfetch.py` → re-run generator (guard `command -v
  python3`); `shell/` → `stow -R shell` (failure → non-fatal hint
  `claw restore-shell`); `claude/` → `bash scripts/setup/link-claude.sh`;
  any pull → `bash scripts/utils/integrity.sh generate` quietly. All regens
  skipped under `--dry-run`.
- [ ] `bin/claw` `cmd_update`: flag routing —
  `--tools`/`--schedule` unchanged; `--repo` → repo-sync only; `--packages` →
  engine only; `--last` → receipt tail; `--dry-run`/`--non-interactive`
  forwarded to both phases; default = repo-sync then engine.
  Update `cmd_help`'s update line.
- [ ] `bin/claw` `cmd_doctor`: one `updates:` line from
  `update-status.sh read` (guarded — dim `n/a` when no cache; do NOT probe).
- [ ] `selfupdate.sh`: `su_now` + both timer definitions (plist ProgramArguments,
  systemd ExecStart) → `bin/claw update --non-interactive` with
  `CLAW_UPDATE_TRIGGER=timer`; on nonzero exit →
  `notify.sh send --crit --app CLAW --title "Self-update failed"` (engine
  absent → stderr fallback, never a crash). Timer unit wraps in `bash -c` so
  the exit path can notify.
- [ ] Tests (`tests/repo-sync.bats`): fixture origin+clone (like existing
  fixtures): behind-by-one ff-pulls and reports SHAs; dirty tree skips with
  reason; diverged skips; `--dry-run` pulls nothing; regen triggers only for
  changed paths (stub `python3`/`stow` in PATH-stub, assert call files);
  receipt row written. `bats tests/claw.bats` still green (help text asserts).

### Task 3: Registry merge — cadence-tagged `tools.list` drives the fast lane

**Files:** `scripts/utils/tool-updater.sh` · `config/manifest/tools.list` ·
`scripts/utils/pkg-manifest.sh` · Create: `tests/tool-updater.bats`

**Interfaces:** `tools.list` row `id|source[|cadence]`,
cadence ∈ `daily|weekly|biweekly|monthly` (86400/604800/1209600/2592000).
Only cadence-tagged rows enter the fast lane. Runner mapping by source:
`brew → brew upgrade <id>` · `pipx → pipx upgrade <id>` · `cargo → nice -n 19
cargo install <id>` · `go:<pkg> → go install <pkg>@latest`.

- [ ] `tool-updater.sh`: build categories by parsing cadence-tagged manifest
  rows grouped by (source, cadence) at startup; keep per-category cache
  keys/intervals; hardcoded `CATEGORIES` used ONLY when the manifest is
  missing/has no tagged rows (comment says so). Both silent and interactive
  modes consume the same parsed set.
- [ ] `tools.list`: tag today's curated set (design § seed): eza bat zoxide fd
  ripgrep zellij `|weekly`; add `bottom|brew|weekly`, `rovr|pipx|weekly`,
  `osint-d2|pipx|weekly`, `clawea|go:github.com/cladamos/clawea|biweekly`,
  `netwatch-tui|cargo|monthly`, `eilmeldung|cargo|monthly` (append missing
  rows; tag in place where the id already exists).
- [ ] `pkg-manifest.sh`: `pkg_update` → delegate to
  `system-update.sh` (print one info line "one engine — routing to claw
  update --packages"); verify all parsers tolerate the third field (`_m_ids`,
  `_m_source`, `pkg_install` loop) — adjust only if a test proves breakage.
- [ ] Tests (`tests/tool-updater.bats`): 3-field rows parse (id/source/cadence);
  2-field rows are ignored by the fast lane; fallback activates on
  cadence-less manifest; go-source maps to `go install …@latest`; interactive
  run with stubbed brew upgrades only due categories; `pkg update` delegates
  (stub `system-update.sh`, assert called). `_m_source` on a 3-field row
  still returns bare source.

### Task 4: Visibility — updates.json, situation, ff-readout, login kick

**Files:** Create: `scripts/utils/update-status.sh`, `tests/update-status.bats`
· Modify: `scripts/utils/situation.sh`, `scripts/utils/ff-readout.sh`,
`shell/welcome-tui.zsh`

**Interfaces:** design § interfaces (JSON shape; `--refresh` throttled 6h,
`--force`, `read [--json]`). Null means "manager absent", never 0.

- [ ] `update-status.sh`: probes — brew: `brew outdated --quiet | wc -l`;
  apt: `apt-get -s upgrade` parse (no sudo); repo: `git fetch -q` (timeout 10)
  + `rev-list --count` both directions vs upstream; `last_run` = epoch of last
  receipt row. Atomic write (mktemp+mv, `situation.sh` pattern), mkdir-lock
  single-flight, every probe `timeout`-guarded (gtimeout shim), `read` never
  probes. `read` plain output: `12 pkg · repo ↓3` / `current` / `n/a`.
- [ ] `situation.sh`: `probe_json` merges `.updates` from updates.json when
  fresh (<24h) else nulls; `cmd_tick` info-notify on rising edge of
  `repo_behind` 0/null→N (config `UPDATES_NOTIFY=info|off` in situation.env);
  `cmd_show` appends ` updates:N repo:↓N` when present.
- [ ] `ff-readout.sh`: add `updates` key (muted color class; reads cache only,
  <1ms, jq-guarded) to `g()` and the `fields` loop output.
- [ ] `welcome-tui.zsh`: beside the two existing `&!` kicks, add
  `"$_d/scripts/utils/update-status.sh" --refresh &>/dev/null &!`.
- [ ] Tests (`tests/update-status.bats`): JSON shape with stubbed brew/apt
  (missing manager → null); 6h throttle honored, `--force` overrides;
  `read` renders the three states; atomicity (no partial file on killed
  probe); `situation.sh probe` merges `.updates`; `ff-readout.sh fields`
  emits `updates=` line; welcome-tui kick present (grep assert, style of
  existing dashboard.bats).

### Task 5: Docs

**Files:** `CLAUDE.md` · `docs/claw.md` · `CHANGELOG.md`

- [ ] CLAUDE.md spine bullet ("`claw update` is the one updater front door")
  rewritten: phases (repo-sync → engine), topgrade-first + `config/topgrade.toml`,
  receipt + `--last`, registry merge (cadence field in tools.list), updates.json
  visibility chain. Update the tool-updater line in Interactive TUI section.
- [ ] `docs/claw.md`: update the update-path table + login-daemon note.
- [ ] CHANGELOG.md: one `## [Unreleased]`-style block for the feature set.
- [ ] Accuracy check: every claim in the edits must match an interface in the
  design doc (no invented flags).

### Task 6: Integration gate (orchestrator)

- [ ] `bats tests/*.bats` — new suites green, pre-existing suites no worse
  than the baseline snapshot.
- [ ] `shellcheck -x` on every touched script; `zsh -n shell/welcome-tui.zsh`.
- [ ] Smoke: `bin/claw update --dry-run` end-to-end in the sandbox (stubbed
  managers) — phases render, nothing executes, receipt row written.
- [ ] Adversarial review (correctness · cross-platform/bash-3.2 · spine/UX
  contract), fix confirmed findings, re-run gate.
- [ ] Commit per task-sized chunk; push; draft PR.
