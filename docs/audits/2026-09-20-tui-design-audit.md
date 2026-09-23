---
title: Open Claw TUI — Design Audit
project: dot-files
status: complete
created: 2026-09-20
tags: [open-claw, tui, audit, ux]
method: 7-lens parallel audit (telemetry, latency, IA, visual, dual-impl, reliability, signal) + synthesizer with evidence spot-checks; 100 raw findings → 25 ranked
---

# Open Claw login TUI — design audit synthesis

**Date:** 2026-09-20
**Status:** AUDIT (read-only) — input to the redesign spec. No files in the repo were changed.
**Worktree:** `.claude/worktrees/dotfiles-tui-audit-2c7549` (HEAD 771869c, byte-identical to `~/.dotfiles` for every file on the login path).
**Method:** seven single-lens auditors (telemetry, latency, information architecture, visual, dual-implementation, reliability, signal) produced structured reports; this document dedupes them to one finding per root cause, spot-checks every cited line for the top findings against the worktree, re-derives the headline telemetry numbers, and ranks by impact × confidence × frequency of exposure (login ≈ 3-6×/day now; a group-screen defect is seen ≈ 2×/year).

**Disclosures.** All repo scripts were run with `CLAW_NO_LOG=1`; `usage.tsv` was not written by the audit. Two side effects from individual lenses are recorded, not hidden: `~/.cache/claw/homelab.json` exists (14:04 today) only because the reliability auditor ran `situation.sh homelab` in the foreground to prove F-05, and `~/.cache/claw/session.seq` advanced 805→825 because `exports.zsh:22` force-exports `XDG_CACHE_HOME`, so scratch-redirected test shells still hit the real counter (F-16).

---

## 1. Executive summary

The login TUI is a blocking two-level menu placed at `.zshrc` step 3, before oh-my-zsh, aliases, the `claw()` wrapper and the prompt exist. Four months of its own telemetry say it asks a question nobody is asking: 1223 fires, 181 outcomes, 154 of them (91%) `default`, 40% of those within two seconds of the fire. The remaining 85% of fires are shells nobody was looking at (Claude Code Desktop and IDE panels that open a pty, render the 0.64 s dashboard, launch three background probes and park at fzf) plus an unmeasured share of Ctrl-Cs that abort the rest of `.zshrc` and leave a shell with no aliases, no prompt theme and no `claw()`.

The dashboard is a hardware spec sheet whose two live numbers are wrong (uptime "20708d" from a greedy regex; a "CPU" bar that is load/ncpu and pins red at 100%), while every actionable signal the repo already computes is dead on arrival: pending updates are computed but never rendered and return "n/a" through a jq scope bug that also hides a broken Homebrew; the homelab fleet cache has never been written because the poller is tracked as non-executable and exec'd directly. Underneath, the three spine contracts in CLAUDE.md hold in name only: the theme engine is bypassed by 22-48 files, "one render path" is true for one profile in eighteen, the menu is hand-written in two languages with its item lists copied in six places, and `theme.sh` forks ~66 processes per load and is loaded five times per login.

What the redesign must achieve: (1) a zero-interaction default landing that renders once, sub-second and interruptibly; (2) a login payload that shows only what changed, from the cached JSON the repo already writes; (3) one registry driving menu, help, completion, stats and post-pick readout; (4) every color, box and glyph consuming the theme engine; (5) an instrument that distinguishes Henry from his agents and abandonment from choice, so the next decision is made on clean data.

---

## 2. Current state

```
Login critical path today (default pick, Apple Terminal, COLUMNS=120; /usr/bin/time -p / hyperfine, CLAW_NO_LOG=1)

  zsh -i (login / new tab / IDE pty)
   │
   ├─ .zshrc step 1-2  PATH inline · platform.zsh · ghostty-terminfo · theme.sh [~85 ms, ~66 forks] · fastfetch.zsh   ≈100 ms
   │
   ├─ .zshrc step 3    claw_welcome_tui  (shell/welcome-tui.zsh)
   │    ├─ guards: !interactive │ !-t 0 │ SSH&&!-t 1 │ TERM=dumb │ CLAW_ACTIVE_PROFILE set  → return   (piped shells: 0 cost)
   │    ├─ [CLAW_TUI=1] → claw-tui (rust) → PROFILE/ACTION/NONE → _claw_apply_outcome → return   (no fire log, no bg jobs, no theme/art)
   │    ├─ _claw_tui_log fire                                        ← every pty: Claude Desktop tabs, IDE panels, humans alike
   │    ├─ &! tool-updater.sh (26 ms)  &! situation.sh homelab (mode 644 → "permission denied", swallowed)  &! update-status.sh --refresh (16 ms)
   │    │
   │    ├─ SCREEN 1  clear (\e[3J) → python3 claw-dashboard.py                                          ≈630 ms  ← Ctrl-C aborts steps 4-8
   │    │      ├─ bash ff-readout.sh fields (sources theme.sh again; ~140 forks)                            ≈250-300 ms
   │    │      │     uptime: sed '.*sec = ' captures usec → "20708d" · host = hw.model "Mac16,7" · term/locale from env · mem_pct twice
   │    │      ├─ fastfetch --logo-type builtin (piped → colors stripped)                                     ≈6 ms
   │    │      ├─ git rev-parse (fails in $HOME) · kubectl (22 ms) · docker ps -q (115 ms) · tailscale status --json (144 ms)
   │    │      └─ homelab_lines() ← ~/.cache/claw/homelab.json (never existed until today)
   │    │      88-cell frame, 16-cell grid (10 static, 4 dup), 5 bars (CPU = load1/ncpu clamped), refined-dark
   │    │
   │    ├─ L1 fzf (9 rows)  echo -e | column -t | fzf --height=~14  → awk '{print $1}'
   │    │      typed text = query; Enter on non-empty query = pick · ESC/Ctrl-C = "default" (header: "ESC shell")
   │    │      group → clear → L2 fzf (31 rows) → ESC back = full SCREEN 1 re-render (630 ms)
   │    │
   │    ├─ log pick:<key> | esc_to_default          (no row for abort / killed pty / render interrupt)
   │    ├─ export CLAW_ACTIVE_PROFILE; source profiles/<key>.zsh   (profile-helpers loaded AFTER → security loses _claw_guard aliases)
   │    ├─ claw_theme_apply_profile  (default → synthwave: all 8 keys flip)                                ≈85 ms
   │    ├─ SCREEN 2  clear → default: claw-dashboard.py --quickref (same probes again)                     ≈600 ms  ← Ctrl-C aborts 4-8
   │    │                     other 17 profiles: fastfetch -c config-<p>.jsonc (unframed, baked keys, own logo)   ≈30-150 ms
   │    ├─ _claw_profile_readout · _claw_profile_cd (default = "" → stays in $HOME)
   │    └─ return
   │
   ├─ step 5  oh-my-zsh (50 plugins; operator-sdk 67 ms, istioctl 67 ms, emoji 39 ms)                    ≈520 ms
   ├─ step 6  exports.zsh (theme.sh AGAIN, 92 ms) · aliases.zsh (kubectl/docker/helm/gh completions sync, 211 ms) · claw-fn · delight (fact card, lands last)
   ├─ step 7  zoxide · direnv · atuin                                                                       ≈24 ms
   ├─ step 8  p10k (gruvbox-pinned) · CLAW_ACTIVE_PROFILE inherited? → re-source + _claw_profile_cd (nested shells relocated)
   └─ PROMPT  ≈ 0.8 s init + 1.24 s renders + human ≥1 s ≈ 2.1 s machine time · stack ≈47 rows on a 40-row window

Other surfaces, each with its own taxonomy and palette: bin/claw (48 subcommands; help 45; completion 39; menu ~12) · toolkit.sh (numeric read -p, `git add .`, `docker system prune -af --volumes`) · tui-style.sh · cheatsheet.sh · help.sh (~/.dotfiles hardcoded) · tui/claw-tui (own build_categories, binary older than source, unbuildable here)

Telemetry (usage.tsv, 1706 rows, 2026-05-17 → 09-20): fire 1223 · pick:default 154 · pick:other 15 · esc 12 · group 8 · dark 1042 (85%)
fires/outcomes by month (UTC): May 271/4 · Jun 639/60 · Jul 116/42 · Aug 87/29 · Sep 110/46
```

---

## 3. What works (do not break)

- **Guard chain** (`welcome-tui.zsh:68-74, 99`): non-interactive, no-tty, SSH-piped, `TERM=dumb`, active-profile shells return before any work. Claude Code's Bash tool and snapshot shells have never produced a fire.
- **fzf is interrupt-safe.** Ctrl-C/ESC are keys (rc 130, empty selection); only the two render windows around it are exposed.
- **Outcome contract** `PROFILE\t<key> | ACTION\t<id> | NONE` applied by `_claw_apply_outcome` — the right seam for any future front-end.
- **`_claw_profile_cd` is the ONE start-dir applier**, called identically from three load paths; `PROFILE_START_DIR` is data and reversible.
- **`claw()` wrapper** rewrites `claw <profile>` → `claw load` only when the profile file exists; bare `claw` unsets the active profile before relaunch.
- **Theme engine contract**: one `palette.theme` per slug, identical precedence in bash/python/rust, `claw_theme_fzf` feeding both pickers, session override never touching the persisted choice. `bin/claw:24-30`'s `${CLAW_RGB_*:-…}` idiom is the model consumer.
- **`claw-dashboard.py frame()/vis()/_clip()`**: width-exact at 80-200 columns, ANSI-safe, shared `content_w`, NO_COLOR-clean, width clamp under test; every probe timeout-bounded.
- **Cache-then-render where it exists**: `update-status.sh` 6h throttle + mkdir lock + mktemp/mv; `homelab_lines()` pure read with an age suffix; `infra_lines` only-when-present segments.
- **`ff-readout.sh fields`** key=value contract with `<res>_pct`; its fastfetch `row()` drops empties.
- **Data-driven precedents**: `_claw_profile_readout` from meta.zsh, rust `discover_profiles()`, completion globs, `gen-fastfetch.py`, `claw profiles lint`.
- **Telemetry** exists, parses 1706/1706, three writers share the schema, all honor `CLAW_NO_LOG=1`; `claw tui-stats` already says KILL.
- **Cheap parts**: python3 startup ~20 ms, fastfetch logo 6 ms, fzf+column 10 ms, non-default fastfetch render 30-150 ms. The Python renderer can stay.
- **Background jobs** are `&!`-disowned, locked, throttled; the thefuck lazy-load stub (`.zshrc:134-136`) is the in-repo deferral idiom; `fastfetch.zsh:36` already switches on `TERM_PROGRAM`.

---

## 4. Findings

Class: **quick-win** = isolated fix, no design decision · **structural** = changes the architecture, design phase decides · **taste** = Henry's call. Confidence: verified (reproduced/measured), likely (strong code evidence), hypothesis.

### 4.1 P0 — breaks the shell or misleads daily

**F-01 · Ctrl-C during either ~0.6 s render aborts the rest of .zshrc** — structural · verified · lenses telemetry-03, ia-08, reliability-01
`.zshrc:59` calls `claw_welcome_tui`; renders at `welcome-tui.zsh:190` and `:356` run inside the sourcing shell. Three independent pty harnesses: `\x03` at t≈1 s → steps 4-8 never run (no omz, no aliases, no `claw()`, no p10k); control run fine; `trap ':' INT` around the call lets the rc finish while python dies rc 130. Writes no telemetry; the only trace is 3 bare `menu` rows reachable only when `claw()` was never defined. Recovery is `exec zsh`, which nothing says.
→ Mitigate now with the INT trap and one printed line; structurally, define the shell before any blocking render (or run the picker from a one-shot precmd). Pty bats test.

**F-02 · Tool-spawned terminals fire the TUI, render, launch three probes and park at fzf** — structural · verified · telemetry-01/10/11, latency-06
`welcome-tui.zsh:70` (`-t 0`) is the only presence check. Claude Code Desktop opens `zsh -l` per session, Antigravity restores terminals; each has a pty. Five such shells were parked during the audit, each `lstart` matching a fire row to the second. ≈1042 dark fires × 0.64 s ≈ 11 min of dashboards to nobody, ~7.3k probe subprocesses, ~3.1k background launches (`situation.sh homelab` alone 4.8 s / 1.3 CPU-s / a `gh api user` call, unthrottled). Recent volume is 3-6 fires/day, not ~10; 75% of all-time fires are May-June build-out.
→ Allow-list human terminals via `TERM_PROGRAM` (precedent `fastfetch.zsh:36`) or make login non-blocking (F-03); start probes only after an outcome, niced, throttled; log `TERM_PROGRAM`/actor per fire.

**F-03 · The gate asks a known question, then draws the identical dashboard twice in two palettes** — structural · verified · telemetry-04/05, latency-04, ia-01, visual-04, signal-08
154/169 picks default; 61 within 2 s; 28/31 L2 entries never picked; `claw load` 0 rows since instrumented. Screen 1 631 ms + `--quickref` 629 ms, byte-identical modulo live numbers, recolored refined-dark → synthwave (`default/meta.zsh:10`) with only an 11-row static card added (drawn 154+ times). Docker/tailscale/kubectl/git probed twice. Stack ≈47 rows on a 40-row window. `bin/claw:376` already prints KILL.
→ Auto-load the frecency/pinned profile with no interaction, resolve the palette before one render, append the delta beneath the frame, bare `claw` is the menu, `tui:autoload:<key>` replaces `tui:fire`.

**F-04 · Uptime reads '20708d'** — quick-win · verified · visual-01, reliability-05, signal-01
`ff-readout.sh:67` `sed -E 's/.*sec = ([0-9]+).*/\1/'` is greedy and matches `usec = 747253`; reproduced now against `kern.boottime = { sec = 1789924702, usec = 747253 }`. Shown twice (header `:394`, grid `:174`); fastfetch on the same machine says 1 h 46 m.
→ Anchor the regex; bats assert Darwin uptime < 3650 d; show once, ideally as a conditional badge.

**F-05 · `situation.sh` is 100644 and exec'd directly by the login kick and the launchd plist — fleet cache never written; fixing it exposes off-LAN probing** — quick-win (exec bit) with a structural companion · verified · reliability-02/10/15, signal-03/09
`welcome-tui.zsh:138` execs by path; `git ls-tree` (re-run) shows 100644 since creation; `com.openclaw.situation.plist:10` has the same shape; `bin/claw:642` prefixes `bash` and masks it. 334 fires since the kick landed, zero `homelab.json` until today's audit side effect; `homelab_lines()`/`_claw_homelab_block` dead code; `claw situation install` on macOS would fail every 60 s. Once fixed, `situation.sh:365` TCP-probes 192.168.1.x on :22/:80, ICMPs, ssh BatchMode and resolves `*.lab.local` from whatever network the laptop is on; tailscale matching by DNSName never hits an IP host; k3s null on macOS (`:51`); `timeout` shim is a no-op without coreutils.
→ Land together: chmod/`bash` prefix + lint for every directly-exec'd script; on-LAN gate (gateway/SSID/tailscale peer), never resolve `.local` off-LAN, `ssh -n`, `ts:` names in fleet.yml, KUBECONFIG default `~/.kube/config`; `claw doctor` shows cache age. Then decide timer vs login-refresh (see §7).

**F-06 · Text typed into a fresh tab is swallowed by fzf and accepted as a pick** — structural · verified · telemetry-02
Exact flags from `:277-281` on a pty: `git status⏎` → default; `cd ~/work⏎` → **claude** (would re-theme and relocate). An unknown share of the 61 fast "default picks" may be keystrokes.
→ Disappears with F-03; any remaining picker requires an explicit key and treats Enter on an unmatched query as a no-op; log the fzf query.

### 4.2 P1

**F-07 · Pending-updates glance dead three times over** — quick-win · verified · signal-02, reliability-06, latency-08
Never rendered (`claw-dashboard.py:174-177` has no `updates`; `ff-readout.sh:179` computes it, ~39 ms); `update-status.sh:146` indexes `.repo_behind` after a pipe where `.` is an array — reproduced: `Cannot index array with string ("repo_behind")` rc 5 → `n/a`; `:66` discards brew's stderr, so today's `brew outdated` rc 1 (Xcode license) is stored as `null` = "absent manager". `tests/update-status.bats:196` passes through the error path.
→ `. as $in | …`; bats case for brew=null,apt=null,repo_behind=0 → `current`; record `brew_err`; render as an attention item only when non-ok.

**F-08 · 'CPU' bar is load1/ncpu clamped at 100%** — quick-win · verified · visual-02, signal-04
`ff-readout.sh:150`; measured 26.8/14 → 100% red vs 29% real; 8.1/14 → 58% vs 26%. Same metric duplicated as a truncated text cell.
→ Relabel/rescale as Load with a neutral palette or sample real utilisation in the background; badge only above threshold.

**F-09 · Payload is a spec sheet: 10/16 static, 4 duplicates, `henry@Mac16,7`, placeholder leaks** — structural · verified · signal-05, visual-07/11/12, signal-11
`claw-dashboard.py:174-177` fixed grid; `ff-readout.sh:63` host = `hw.model`; `:73/:76` term/locale from env (LANG set at step 6, after render); `_short(…,13/14)` truncates Load/`Apple_Terminal`/3-octet IPs while the box stays 88 cells at COLUMNS=200; glyph collisions ip/tailscale, shell/term, uptime/clock; AWS "default" whenever `~/.aws/config` exists.
→ Presence-driven segment list with `show_if`; header `user@hostname · model · net · time`; static facts to `claw doctor`; content-sized columns.

**F-10 · No attention surface; the landing ignores what Henry does next** — structural · verified · signal-06/07, telemetry-06
`situation.sh:6` ships the interrupt renderer only (`:443` transition-only notify); nothing at login reads `situation.json`; the p10k segment was scoped out (2026-08-17 spec:143); `.p10k.zsh` has 0 references to the active profile. `default/meta.zsh:18` lands in `$HOME`; atuin's first command per session: `claude` 22, `cd <repo>` 13+5, `cd hr-vault-main-pa` 7. Measured cheap signals: Things Today 51 / Inbox 26 (<5 ms sqlite ro), last handoff (`.remember/remember.md`, PR #73 open), 31/65 dirty repos (1.33 s, cache it), 3 worktrees, 5 claude sessions (~10 ms).
→ One attention strip (+ optional p10k segment) from cached JSON in <1 ms, non-OK items only, tier color + age, `all clear · checked 2m ago` when empty; `situation.sh evaluate` shared by strip and notifier; `local.json` for operator signals; default landing resumes last cwd / top zoxide / recent worktree and surfaces `claude` and recent projects.

**F-11 · theme.sh forks ~66 processes per load, loaded 5× per login and on every `claw` call; three parsers** — quick-win · verified · latency-01, dual-08
`theme.sh:60` (`cut -c3-4`, `cut -c5-6`), `:77` (`tr`); load sites `.zshrc:49`, `exports.zsh:52`, `ff-readout.sh:33` (×2 renders), `welcome-tui.zsh:337`, `bin/claw:22`. 80-90 ms each (re-timed 0.08 s); `claw help` 99 ms, `claw theme current` 190 ms. `claw-dashboard.py:24` and `theme.rs:50` re-implement precedence; `theme.rs` has no `cyan`.
→ Fork-free load or a rendered `palette.env`; delete `exports.zsh:52`; skip when `CLAW_THEME_SLUG` is exported; dashboard reads `CLAW_C_*` from env.

**F-12 · Render data path is ~75% of a render** — structural · verified · latency-02/03, signal-10, dual-03
`ff-readout.sh fields` 246-294 ms / ~140 spawns vs `fastfetch --format json -s …` 30.5 ms; `mem_pct` emitted twice (34 vs 60, `:82` dead); swap/date/updates computed and dropped. `claw-dashboard.py:214-215` docker 115 ms, `:272` tailscale 144 ms — hiding both: 590 → 311 ms. Rust shells to a config-less fastfetch whose modules are all `command` rows → 0 usable, env dump.
→ One data contract (fastfetch JSON or `fields --json`) for every renderer; docker/tailscale/k8s via the TTL-cache pattern with age suffix; tier fields static/slow/live; never write a cache from a `TERM=dumb` render.

**F-13 · Theme engine honored by a minority of surfaces; misnamed variables; no color-depth probe** — structural · verified · visual-05/16/17/18, dual-07, reliability-12
`tui-style.sh:23-28` own palette (so system-update/tool-updater/integrity ignore `claw theme`); `welcome-tui.zsh:490` hardcoded fzf colors 20 lines below the themed call; `:148/:150` `c_cyan←BLUE`, `c_pink←RED`; `.p10k.zsh:62` gruvbox; `exports.zsh:57` EZA decoupled; onboarding's "synthwave" ≠ the library's; `theme.sh:102/:151` confirm in refined-dark; 32-48 files with `38;2;` literals depending on regex, 0 `COLORTERM` anywhere; FZF_DEFAULT_OPTS loads at step 6 so login and relaunch menus differ.
→ tui-style.sh sources theme.sh first; theme.sh becomes the generator (p10k, EZA, fzf, tui-style, fastfetch keys, OSC 10/11); palette-key names; `CLAW_COLOR_DEPTH`; `_claw_fzf` wrapper; lint on literals.

**F-14 · Daily driver forces synthwave; refined-dark is a phantom default** — **taste** · verified · visual-06/13
`default/meta.zsh:10` vs `theme.sh:26`; `:254` override wins per session; 18 profiles → 4/10 palettes; `muted` fails 4.5:1 in five palettes and carries 52% of colored text.
→ Henry decides (§7). Either way: OSC bg/fg on theme change, `muted` for chrome only, contrast lint.

**F-15 · Five taxonomies, two menu models, six profile-list copies, PROFILE_TIER unconsumed, toolkit.sh as a third menu with `git add .` and `prune -af --volumes`** — structural · verified · dual-01/05/06/13/14, ia-02/03/13/15, telemetry-13
`welcome-tui.zsh:211-268` vs `main.rs:197-234` (3/6 group names differ, 9/16 actions shared, alphabetical vs curated); `architecture.md:78` names a menu generator that reads `PROFILE_TIER` — 0 consumers; list copies at `welcome-tui.zsh:328`, `claw-fn.zsh:58`, `onboarding.sh:474/648/667`, `main.rs:208-212`, `bin/claw:317-320` (vault/homelab picks mis-bucketed); 48 subcommands, help 45, completion 39 (missing `harness`, Henry's #1), menu ~12; `toolkit.sh:54/:72/:103`; `help.sh:7` hardcodes `~/.dotfiles`.
→ One registry (meta.zsh + `actions.tsv`) → emitter → fzf palette, native front-end, help, completion, cheatsheet, onboarding copy, tui-stats; one `_claw_action`; fold toolkit leaves with a danger flag, delete the two destructive entries; bats coverage test.

**F-16 · Telemetry blind to abandonment and actor; tui-stats miscounts; CLI volume is agent loops; session.seq counts every rc source** — quick-win · verified · telemetry-07/08/11/12, ia-12, signal-12, dual-06
`bin/claw:371` excludes dark fires (13% vs 85%); `:317/:320` hardcoded regexes; `welcome-tui.zsh:129` fire row has no TERM_PROGRAM/actor and the rust branch returns before it; 195/294 CLI rows are `upgrade→harness→harness→output` every ~2 min on 3 days; atuin: 13 hand-typed `claw`; `exports.zsh:22` force-export.
→ Fire row with TERM_PROGRAM + actor (CLAUDECODE present → agent) + shell id; `tui:abort:<phase>` from TRAPINT/zshexit; `tui:render` with item count + wall time; classify by profile file on disk; trailing 30-60 d window; honor pre-set XDG vars.

**F-17 · Navigation is hierarchy-as-gate, not search; no frecency; glyph reuse; L1 contradicts usage; `claw <profile>` undocumented** — structural · verified · ia-04/06/07/09/10/14, visual-08, latency-09
`:280` header never says "type"; 0 `--bind/--expect`; `:214` descriptors leak child names ('sec' → 5/9 rows, 'security' → domain only); `:282` L1 shows the raw key column; `:275` header re-rendered every loop (ESC at L2 = 0.64 s); 0 frecency implementations next to atuin/zoxide in the same rc; `claw-fn.zsh:36-37` shorthand appears in 0 docs and completion; `default/common.zsh:46` teaches `source ~/.zshrc`; 🧠×3, 📡×3, 📓×3; twins share glyph and group; 7 VS16 rows shift the description column (likely, not screenshot-verified).
→ Flat, fuzzy, frecency-ranked list of leaves with facet column and `--with-nth`; unique glyph + kind prefix; `--expect` accelerators; `frecency.tsv` written on every pick/load; promote `claw <profile>` and complete it.

**F-18 · Entry/exit semantics inconsistent** — quick-win · verified · ia-05/11, telemetry-09, reliability-08/09/13
ESC = default in fzf (header "shell"), bare shell in rust, `skip` buried under the never-entered `system` group (0 uses); `bin/claw:261` child inherits `CLAW_ACTIVE_PROFILE` and `:99` returns → `claw menu` silent no-op after any pick; `:74`/`:160` bail paths load no profile while SSH (`:85`) loads default; `:278` `--height=~14` exits 2 on fzf <0.34 → read as ESC; `clear` (`:186/:321/:350`) emits `\e[3J` on Apple Terminal/Ghostty, so mid-session `claw` wipes scrollback.
→ One ESC contract in every footer; single bail function; `env -u` in cmd_menu or a claw-fn case; fail loud on fzf rc 2; `printf '\e[H\e[2J'`.

**F-19 · Rust front-end is structurally second-class** — **taste** · likely · dual-02/03/04/16, visual-19, reliability-11
Returns at `:105-108` before the logger and warmers; apply skips theme/art/readout; six offered ACTION ids hit `*) :` (`:62`); readout probe inert; binary 2026-07-11 vs source 2026-07-19; crate does not link here (Xcode license); no Ctrl-C handling in raw mode, no panic hook; parity spec gated since July.
→ Henry decides freeze vs thin-renderer (§7). In both cases move logger/warmers above the branch and share `_claw_after_pick`.

**F-20 · Profile load order and error handling** — quick-win · verified · reliability-03/07
`:333` sources the profile, `:375-377` lazy-loads profile-helpers after → `security` gets 13 aliases not 20 and 10× `command not found: _claw_guard`; `:329` exports before an unchecked `source`; `.zshrc:193` sentinel set by meta.zsh so a mid-file failure is never retried.
→ Helpers before profile; check `source` rc in all three paths; `zsh -n` in `claw profiles lint`; parity bats test.

**F-21 · Nested shells inheriting CLAW_ACTIVE_PROFILE are relocated** — structural · verified · reliability-04
`.zshrc:193/:200` re-source and cd in every child interactive zsh; reproduced `cd /tmp; CLAW_ACTIVE_PROFILE=vault zsh -ic pwd` → vault root; defeats `tmux.conf:20` `pane_current_path`; 16/18 profiles declare a start dir.
→ Apply the cd only for a fresh login (PWD = HOME or an explicit picked-marker); bats nested-shell case.

**F-22 · aliases.zsh regenerates four completions synchronously (211 ms) that omz already regenerates in the background; omz 522 ms** — quick-win · verified · latency-05/07
`aliases.zsh:850-865`; `.zshrc:95-96` plugin list; operator-sdk/istioctl 67 ms each, emoji 39 ms.
→ Delete `aliases.zsh:845-866`; lazy-load or drop the three plugins; target omz ≤200 ms, `zsh -ic exit` ~330 ms.

**F-23 · "One render path" holds for 1/18 profiles; fastfetch configs split 9/10; logos duplicated and diverged; Apple logo monochrome** — structural · verified · visual-03/09, dual-10/11/12
`welcome-tui.zsh:355-357`; `gen-fastfetch.py:46-50` bakes refined-dark; `logo-security.txt:1` #121219 slab; pty render of `config-security.jsonc`: 96 cells, unframed, refined keys, different hostname/uptime; 8/9 logo pairs differ between two directories with two preference orders; `claw-dashboard.py:120/124` pipes fastfetch → 0 SGR in the logo column (`--pipe false` → 16).
→ `claw-dashboard.py --profile <key>`; one logo per profile with a color map in meta.zsh; render the Apple mark from theme accents.

### 4.3 P2

**F-24 · Visual primitives fragmented** — structural · verified · dual-09, visual-10/14/15
Six box implementations (`tui-style.sh:56/:59` ragged by 1-2 cells on every integrity/update header; `_claw_default_quickref` reads a `dash_box` file nothing writes), four ANSI strippers, five width probes, 13 hand-padded help cards; at COLUMNS=80 data cells are hard-cut while the logo survives; ~25 PUA glyphs with no ASCII fallback and a font known to revert to SF Mono.
→ `claw card` from `frame()`; responsive breakpoints; `CLAW_GLYPHS=nerd|ascii` resolved once; `claw doctor` checks the font.

**F-25 · Zero tests on the menu, pick/ESC/outcome paths, uptime, or parity** — quick-win · verified · reliability-14, dual-15
`grep -rlE 'claw_welcome_tui|_claw_apply_outcome|CLAW_TUI' tests/` → nothing (re-run). None of F-01/04/05/06/07/18/20 would have been caught.
→ `tests/welcome-tui.bats` with stub PATH; pty Ctrl-C test; exec-bit assertion; uptime bound; registry coverage.

### 4.4 Folded / P3 backlog
`fact-YYYYMMDD` zero-byte stamps accumulate (63) with no pruning (latency-10); fact-of-the-day repeats by day 8 with p≈0.47 (signal-08); AWS identity shown from file presence (signal-11); `timeout` shim silent no-op without coreutils (reliability-15, hypothesis) — all belong in the cache-hygiene / `claw doctor` work of F-12 and F-05.

---

## 5. Measurements

| What | Value | How |
|---|---|---|
| Screen-1 render (claw-dashboard.py, non-tty, COLUMNS=120) | 590-640 ms (hyperfine 631 ± 18; re-run 0.64/0.57 s); `--quickref` 629 ± 16 ms; outputs identical modulo live numbers | hyperfine -N ×8; /usr/bin/time -p; DOTFILES_DIR=worktree, CLAW_NO_LOG=1 |
| ff-readout.sh fields | 246-294 ms; 161 ms without line-33 theme source; ~140 spawns | hyperfine on original vs `sed '33d'` copy; grep -o counts |
| fastfetch --format json (16 modules) | 30.5 ± 0.9 ms | hyperfine -N ×6 |
| Context probes from $HOME | docker ps -q 115 ms; tailscale status --json 144 ms; kubectl 22 ms; git 8.5 ms (fails); dashboard 590 → 311 ms with docker+tailscale hidden | hyperfine -N -i; restricted PATH |
| theme.sh source | 80-90 ms zsh / 99-100 ms bash; 22 cut + 11 tr per load; 5 loads/login + 1 per `claw` call | hyperfine ×10; re-run 0.08 s ×2; bash -x |
| `.zshrc` with TUI skipped | 0.78 s steady (cold 1.72 s); default login ≈ 0.8 + 0.63 + 0.60 + 0.085 s + human | /usr/bin/time -p zsh -ic exit, CLAW_ACTIVE_PROFILE=default |
| Steps 5-8 by module | omz 522 ms (operator-sdk 67.5, istioctl 67.1, emoji 38.7); aliases.zsh 211 (docker 115, helm 35, gh 34, kubectl 26); exports.zsh 91; tool init 24; p10k+fzf 12 | hyperfine on excerpts; xtrace with EPOCHREALTIME; zprof |
| bin/claw invocation tax | help 99 ms; version 118 ms; theme current 190 ms | hyperfine ×8 |
| situation.sh homelab (when it runs) | 4.8-5.3 s wall, 1.3 CPU-s, 11.6k ctx switches, `gh api user` 330 ms; unthrottled | /usr/bin/time -l, XDG_CACHE_HOME to scratch |
| Telemetry totals (1706 rows) | fire 1223 · pick:default 154 · other picks 15 · esc 12 · group 8 · dark 1042 (85%) · CLI 294 | awk uniq -c (re-run) |
| Fires/outcomes by month (UTC) | May 271/4 · Jun 639/60 · Jul 116/42 · Aug 87/29 · Sep 110/46; last 30 d 5.8/day; last 7 d 2.9/day; 75% of fires 05-27→06-30 | awk substr; git log by month |
| Fire → outcome gap (n=171) | median 4 s; p90 267 s; default within 2 s 61/154 (40%), within 5 s 88/154 | python3 gap analysis |
| Hand-typed vs agent `claw` | atuin 13 commands in 4 months; 195/294 CLI rows = scripted cycle on 3 days | sqlite3 ro; python3 dump |
| First command per session (175) | claude 22 · cd Github/… 13 · ls 10 · cd hr-vault-main-pa 7 | sqlite3 ro |
| Shells parked at fzf during audit | 5, lstart = fire row ±1 s; fzf 5-6.6 MB + zsh 1.5 MB RSS each | ps -o lstart; lsof cwd; ps -o rss |
| Uptime defect | sed on `{ sec = 1789924702, usec = 747253 }` → 747253 → 20708 d; true 1 h 43 m | sysctl \| sed (re-run) |
| Updates glance | jq → `Cannot index array` rc 5 → `n/a`; brew rc 1 (Xcode license) stored null | re-ran filter; brew outdated |
| situation.sh mode | 100644 at every commit since 505bce8; direct exec rc 126; 334 fires since kick; 11 scripts in scripts/utils are 100644 | git ls-tree (re-run); pty capture |
| CPU bar | 26.8/14 → 100% vs 29% real; 8.1/14 → 58% vs 26% | ff-readout pct; ps sum; top |
| mem_pct | 34 then 60 in one dump | ff-readout fields |
| Menu | 9 + 31 rows / 40 labels; 28/31 L2 never picked; 'sec' → 5/9 rows; 0 binds; 0 frecency | grep; fzf --filter |
| Taxonomies | 48 subcommands / 78 names; help 45; completion 39 (10 missing); menu ~12; rust 13 vs zsh 16 actions (9 shared); profile list ×6; PROFILE_TIER consumers 0 | grep/awk/comm |
| Hardcoded colors | 32 files (`38;2;` literals; 27 with 0 theme refs) — 48 with a broader grep; 22 own palette blocks; 39 with the refined blue literal; 0 COLORTERM; 3 palette parsers | grep -rlE variants |
| Palettes / contrast | 18 profiles → 4/10 palettes; default pick flips 8/8 keys; muted on bg: tokyo-night 2.76, rose-pine 3.42, matrix 3.92, dosbbs 4.35, gruvbox 4.47 | uniq -c; luminance calc |
| Frame | 88 cells fixed ≥100 cols; hard-cut at 80; 27/37/≈47 rows; tui_header 58 vs 56/57; Apple logo 0 SGR piped / 16 with --pipe false | EAW measurer; pty slice |
| security via TUI vs load | 13 vs 20 aliases; 10× `_claw_guard` not found | zsh -fc alias count |
| Nested relocation | CLAW_ACTIVE_PROFILE=vault zsh -ic pwd from /tmp → vault root | real ~/.zshrc |
| Ctrl-C under pty | during `$(…)`: later steps skipped, shell alive; at fzf: rc 130, continues; with `trap ':' INT`: continues | python3 pty.fork ×3 harnesses |
| Rust state | binary 07-11 vs src 07-19; cargo link fails (exit 69); 0/10 WANT modules from config-less fastfetch (0.20 s); 6 ACTION ids unhandled | ls; git log; cargo; json count |
| Cheap signals | Things 51/26 <5 ms; handoff file free; 31/65 dirty repos 1.33 s; 3 worktrees; 5 claude procs ~10 ms; situation probe 0.20 s | sqlite3; find; timed loop; pgrep |
| Test coverage | 0 tests reference the TUI entry points; 3 dashboard render tests | grep -rlE tests/ (re-run) |

---

## 6. North star

1. **Never ask a question whose answer is known.** 154/169 picks are default, 61 within 2 s, ESC also means default, `skip` has 0 uses. Login auto-loads; the picker is `claw`; `claw <profile>` is the verb; no keystroke on the first-prompt path is ever a pick.
2. **One render, sub-second, interruptible.** Today 0.64 + 0.60 s in two palettes on ~0.8 s of init, with a Ctrl-C window that cripples the shell. Target one framed render ≤0.5 s (cache docker/tailscale, one fastfetch JSON call, theme loaded once, completions not regenerated), under an INT trap.
3. **Show what changed, not what is.** 10/16 cells static, 4 duplicates, 2 wrong; updates/fleet/handoff/Things/sessions all cheap and unshown. An attention strip from cached JSON in <1 ms with an age suffix; the spec sheet moves to `claw doctor`.
4. **One registry, many surfaces.** Two menu models, five taxonomies, six list copies, an unconsumed `PROFILE_TIER`, ≥22 private palettes. meta.zsh + actions.tsv generate palette, help, completion, stats and readout; theme.sh generates every color; a bats test enforces coverage.
5. **Instrument the actor and the abandonment before deciding.** 85% dark fires indistinguishable from human ones; tui-stats says 13%; CLI volume is an agent loop. Log TERM_PROGRAM/actor, `tui:abort`, `tui:render`; classify from disk; trailing 30-60 d window.

---

## 7. Open questions for Henry (taste items — not presumed)

1. **Daily palette (F-14).** Should `default`/`local`/`claude` inherit the persisted `claw theme` (making refined-dark the real default and `claw theme set` meaningful), with synthwave/matrix/dosbbs/vhs reserved for domain profiles — or is neon synthwave the intended everyday look? Should the theme also set the terminal background (OSC 11) so Apple Terminal stops showing a fourth palette?
2. **Rust front-end (F-19).** Freeze `tui/claw-tui` to `legacy/` and mark M3-M5 won't-do, or keep it strictly as a thin renderer of the registry TSV + readout JSON with a versioned, doctor-checked binary? Telemetry shows no demand for a richer picker; the crate does not currently build on this Mac.
3. **Where the default landing drops you (F-10).** Resume last cwd, top zoxide dir, most recent worktree, or stay in `$HOME`? Should `claude` and "recent projects" be first-class actions on the landing?
4. **Fleet polling on the Mac (F-05).** Once the exec bit is fixed, run the 60 s launchd timer (5 s of network per tick, only when provably at home) or refresh at login with a staleness badge?
5. **Human-terminal allow-list vs non-blocking login (F-02/F-03).** Gate the picker on `TERM_PROGRAM` (Apple_Terminal, ghostty, iTerm.app, WezTerm, kitty) or remove the gate entirely and rely on `claw`? Both are compatible; the allow-list is a fallback if any blocking picker survives.
6. **Menu pruning (F-17).** Collapse the login palette to the entries with any use (default, claude, vault, local, homelab) plus verbs, with the other 13 profiles reachable by name — or keep all 18 visible behind a facet?
7. **Quickref and fact card (F-03/F-24).** Show the Daily Driver card once per day / after `claw update` only, and move the fact into the frame? Or drop both from login?
8. **Contrast policy (F-14).** Raise `muted` to ≥4.5:1 in tokyo-night, rose-pine, matrix, dosbbs, gruvbox-material (changing their look) or add a `muted_text` key and keep chrome dim?
9. **Agent-first CLI (F-16).** Given agents are the real `claw` volume, should the redesign budget include stable exit codes and machine-readable output (`claw output`) as a first-class surface alongside the login TUI?
