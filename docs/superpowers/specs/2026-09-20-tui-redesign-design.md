---
title: Open Claw login — decide, then render
project: dot-files
status: approved-for-implementation
created: 2026-09-20
tags: [open-claw, tui, design, spec]
audit: docs/audits/2026-09-20-tui-design-audit.md
method: judge panel — 3 approaches (surgical / registry-first / instant) × 3 judges (operator / maintainer / skeptic) → synthesis; tally 138/140/121
---

# Open Claw login — decide, then render (design)

**Date:** 2026-09-20
**Status:** Design → plan in `plan` (T0/T1/T2)
**Author:** Henry + Claude
**Related:** `docs/audits/2026-09-20-tui-design-audit.md` (evidence; 25 findings), `docs/superpowers/specs/2026-08-17-claw-update-one-engine-design.md` (update-status contract this reuses), CLAUDE.md "The Spine"
**Verified against:** HEAD ddb0ba5 (F-04/F-05/F-07/F-22 already landed; this spec does not re-ship them)

## Goal

A new tab reaches a fully defined prompt in ≈0.45 s having asked nothing, printed only what is non-OK (from cached JSON, <1 ms), and never being crippled by Ctrl-C. Choice moves to one on-demand palette (`claw`, ^G) over one registry that also generates help, completion and stats. Every colour comes from `theme.sh`, loaded once, fork-free. Telemetry tells Henry from his agents.

## Non-goals

No new front-end, daemon, language or runtime dependency. No frecency-chosen login profile. No compiled palette artifact or registry cache. No 60 s timer by default on the Mac. No change to guard semantics for non-interactive/no-tty/SSH-piped/dumb shells. No deletion of `tui/claw-tui`. No rewrite of the 13 help cards, onboarding copy or `gen-fastfetch.py`. No `docker system prune -af --volumes` or `git add . && push` surviving anywhere.

## Evidence (audit §4-5, re-checked on this branch)

- 1223 fires · 154/169 picks default · 40% within 2 s · 85% dark (agent/IDE ptys).
- Two identical 0.63 s renders in two palettes on ~0.8 s init; `zsh -ic exit` = 0.60-0.62 s today (measured on ddb0ba5).
- Ctrl-C in either render aborts .zshrc steps 4-8 (pty-reproduced); `trap ':' INT` lets the rc finish.
- `theme.sh` sourced 5×/login at 80-86 ms each (22 `cut` + 11 `tr`); 45 gruvbox literals in `.p10k.zsh`; 32-48 files with `38;2;` literals; 0 `COLORTERM` probes.
- 6 copies of the 18-profile list; `PROFILE_TIER` declared 18×, read 0×; completion missing 10 subcommands incl. `harness`.
- `situation.sh homelab` finally runs (exec bit landed) but `cmd_homelab_poll` has no throttle/lock; nothing at login reads any cache.
- Verified here: a precmd hook registered at .zshrc step 2b prints above the first p10k prompt (byte 124 vs 1790).

## Experience (a day)

```
07:40  Apple Terminal, first tab.  ~0.45 s: prompt.  Above it, once today, the framed card:
       ╭─ OPEN CLAW ──────────────────────────────────────────────────╮
       │  (apple)  henry@MacBook-Pro-10 · MacBook Pro 16 · HR-TRUST   │
       │           Sat Sep 20 · 07:40 · up 2h49m                      │
       │           Mem ████████▓▓▓▓ 72%   Disk ██████████▓▓ 82%   load 2.2/14
       │  ├─ attention ───────────────────────────────────────────────┤
       │  ● k3s 2/3 Ready · ms-01                     since 03:12 · 4h│
       │  ● brew ✗ xcode-license · sudo xcodebuild -license    3d     │
       │  ○ dotfiles ↓3 · claw update                          6h     │
       │  Things 26 inbox · 51 today   handoff "pty live output" 2d   │
       │  5 claude sessions · 31/65 repos dirty        checked 2m ago │
       ╰──────────────────────────────────────────────────────────────╯
       [ ~ ][ ⚑2 ] ❯          ← p10k: ⚑ in red, persists after scrollback
09:15  10th tab.  Prompt at ~0.45 s.  One line above it:  ● k3s 2/3 Ready · ms-01  (since 03:12 · 5h)
       Nothing else.  He typed `cd ~/Github/x⏎` before the prompt — it ran.
09:20  Claude Desktop pty: CLAUDECODE=1 → profile exported, no hook, 0 bytes, 0 probes, one `tui:login:agent` row.
10:02  tmux split: inherits CLAW_ACTIVE_PROFILE → aliases, no cd, no strip.
11:30  ^G → palette: security · vault · claude · default · homelab · update · doctor · tunnels …  `sec⏎` →
       `claw load security`: helpers already loaded (20/20 aliases), matrix palette, OSC bg (Ghostty), ONE frame
       with the security logo, `NIGHTHACKER · thinks your password is cute`, `✓ nmap ✓ ffuf ✗ msfconsole → claw install security`,
       `↳ ~/pentest (cd - to go back)`.  frecency.tsv bumped.
14:10  ssh bd790i (GNOME Terminal): remote claw_login → default, strip from that box's caches, no card, no OSC.
16:45  k3s r630 NotReady. No timer on the Mac → detected by the next login's kick; `since` = that probe.
       (With `claw situation install`: notification at 16:45, `since 16:45` on every later tab.)  `claw ack k3s --hours 4` hides it.
```

## Architecture

```
zsh -i
 ├─ 1  PATH inline · trap ':' INT                                             (rc-scoped INT guard)
 ├─ 2  platform · ghostty-terminfo
 ├─ 2b source shell/claw-login.zsh; claw_login            ← DECIDE (pure zsh, ~1 ms, 0 forks, 0 bytes)
 │      guards → _claw_login_mode → resolve profile → export CLAW_ACTIVE_PROFILE CLAW_THEME CLAW_ACTIVE_GROUP
 │      _CLAW_FRESH_LOGIN=1 (not exported) → add-zsh-hook precmd _claw_login_render   (not for mode=agent)
 ├─ 2c theme.sh  — ONE fork-free load, already the profile palette
 ├─ 5  oh-my-zsh (−istioctl −operator-sdk −emoji)
 ├─ 6  exports (no theme re-source, XDG :=) · aliases · profile-helpers · claw-fn (+_claw_load_profile) ·
 │      claw-palette (+^G widget) · completion (registry) · security · obsidian · clin · progress · delight
 ├─ 7  zoxide · direnv · atuin
 ├─ 8  source profile (PROFILE_NAME unset) · _claw_profile_cd only if _CLAW_FRESH_LOGIN · p10k (palette via claw_theme_emit p10k)
 ├─    trap - INT                                                           ═══ shell complete ≈ 0.45 s ═══
 └─ first precmd → _claw_login_render                     ← RENDER (after the shell exists)
        add-zsh-hook -d precmd _claw_login_render; trap - INT (belt)
        setopt localtraps; trap '_claw_tlog tui:abort:render; return 130' INT
        strip:  _claw_attention_strip   (zsh, reads attention.tsv, ≤3 lines, silent when clear)
        card:   mode=human && CLAW_LOGIN_CARD=daily && stamp≠today (zsystem flock) → python3 claw-dashboard.py --login
        kicks:  mode=human|ssh: nice -n 10 bash situation.sh homelab · situation.sh local · update-status.sh --refresh  (&!, locked, throttled)
        osc:    mode=human && allow-listed terminal → claw_theme_emit osc
        log:    tui:login:<mode>:<profile>  term= actor= shell= items= strip= card=

 palette:  claw | claw menu | ^G → claw_palette → fzf over `registry.sh palette` → PROFILE\t<k> | ACTION\t<k> | NONE → _claw_apply_outcome
 registry: shell/profiles/*/meta.zsh + config/claw/actions.tsv → registry.sh → palette · help · completion · tui-stats · doctor
 state:    situation.sh {probe,homelab,local} → *.json → situation.sh evaluate → attention.{tsv,json,count} → strip · card · p10k ⚑ · notifier
 theme:    theme.sh (load once) → CLAW_C_*/CLAW_RGB_* → claw_theme_emit {p10k,tui,fzf,osc} → prompt · bash TUIs · fzf · terminal chrome
```

## Components

**shell/claw-login.zsh** (new, ~200 lines). `claw_login`, `_claw_login_mode`, `_claw_actor`, `_claw_meta_field <p> <VAR>` (pure-zsh scan of meta.zsh: `^VAR="…"` with optional trailing `# comment`), `_claw_login_render`, `_claw_attention_strip`, `_claw_tlog`. Sourced at .zshrc step 2b. Env: `CLAW_LOGIN_PROFILE`, `CLAW_LOGIN_CARD=always|daily|never`, `CLAW_LOGIN_RENDER=0`, `CLAW_ACTOR`, `CLAW_LOGIN_TERMS`, `CLAW_NO_LOG`.

**shell/claw-palette.zsh** (new, ~140 lines). `claw_palette [--src=cmd|chord]`, `_claw_apply_outcome` (moved verbatim from welcome-tui.zsh:6-64, ACTION branch → `_claw_action`), `_claw_action <id>` (flags: `!` confirm via gum/`read -q`, `x` external, `l:<mod>` lazy-source `shell/<mod>.zsh`), `_claw_frecency_bump <id>`, `_claw_palette_widget` (`zle -I; claw_palette --src=chord; zle reset-prompt`), bindkey in emacs/viins/vicmd to `${CLAW_PALETTE_KEY:-^G}`. Sourced at step 6 after claw-fn.zsh.

**shell/claw-fn.zsh** (modified). `""`/`menu` → `claw_palette`; `load` → `_claw_load_profile <p>` (helpers-first, `source … || { warn; unset CLAW_ACTIVE_PROFILE PROFILE_NAME; return 1 }`, theme apply, OSC, `claw-dashboard.py --profile`, `_claw_profile_cd`, frecency, log); `dash` → `claw-dashboard.py --login`; `pin|ack|registry` pass through. The hardcoded list at :58 → `registry.sh ids profiles`.

**scripts/utils/registry.sh** (new, ~130 lines bash+awk) + **config/claw/actions.tsv** (new). See Data contracts.

**scripts/utils/theme.sh** (modified). Fork-free load, idempotent guard, `claw_theme_emit`, `claw_theme_depth`, `claw_theme_set` applies live. **shell/.p10k.zsh**: `eval "$(claw_theme_emit p10k)"` + `prompt_claw_attention`. **scripts/utils/tui-style.sh**, **cheatsheet.sh**: source theme.sh, derive colours.

**scripts/utils/claw-dashboard.py** (modified). `ff_json()`, `segment_rows()`, `attention_lines()`, `--login`, `--profile <key>`, `--card <title>` (T2), env-first palette, breakpoints ≥100 / 80-99 / <80. `frame()/vis()/_clip()` untouched.

**scripts/utils/situation.sh** (modified). `evaluate`, `local`, throttle+lock on `homelab`, generic transition diff in `tick`, `ts:` names, `ssh -n`, KUBECONFIG default `~/.kube/config` when the k3s path is absent. **config/homelab/fleet.yml**: `lan_gateway` accepts a list, optional `lan_ssid: [HR-TRUST]`, `machines[*].ts`.

**bin/claw** (modified). `registry`, `pin`, `ack`, `dash` arms; `cmd_help` Profiles + verbs from `registry.sh help`; `cmd_menu` prints a one-line hint (never spawns a child zsh); `cmd_tui_stats` rewrite; `log_usage` 5th column; doctor prints cache ages + attention count. **shell/claw-completion.zsh**: `top` from `registry.sh completion` (cached in a zsh global on first Tab).

**Retired to legacy/**: `shell/welcome-tui.zsh` (end of T1), `tui/claw-tui` (T2, flagged).

## Data contracts

### Registry source 1 — `shell/profiles/<p>/meta.zsh` (grammar lint-enforced)
Each non-comment line: `PROFILE_[A-Z_]+="…"` optionally followed by `# comment`. Two new required fields:
```zsh
PROFILE_GLYPH="󰒃"                              # one glyph, unique across the registry, no VS16
PROFILE_DESC="pentest · OSINT · scope-gated harness"   # ≤40 chars, never names a sibling profile
```
Group from `PROFILE_TIER`: 1 core · 2 domain · 3 agent · 4 knowledge · 5 customer · 6 hardware. F-14: `default|local|claude` set `PROFILE_THEME_DEFAULT=""`.

### Registry source 2 — `config/claw/actions.tsv`
Tab-separated, `#` comments, `-` = empty. Columns: `id  aliases  group  glyph  label  desc  run  flags`.
```
# id	aliases	group	glyph	label	desc	run	flags
update	upgrade	system		Update	repo sync then packages	command claw update	-
doctor	-	system		Doctor	system + attention detail	command claw doctor	-
dash	-	system		Dashboard	framed card now	command claw dash	-
tun	tunnel|tunnels	tools		Tunnels	SSH tunnel manager	command claw tun	x
homelab	-	tools		Homelab	SSH topology · fleet	command claw homelab	x
mcp	-	tools		MCP	server manager	command claw mcp	x
agent	agents	tools		Agents	registered agent picker	command claw agent list	-
vault-open	-	tools		Open Vault	Obsidian → active vault	ov	l:obsidian
clin	-	tools		Clin Notes	note TUI in the profile folder	cl	l:obsidian,l:clin
handoff	-	tools		Handoff	session note → vault inbox	command claw handoff	-
harness	-	tools		Harness	custom skills: list|new|deploy	command claw harness list	-
tmux	-	system		tmux	attach or new session	tmux attach 2>/dev/null || tmux new-session	x
yazi	-	system		yazi	file browser	yazi	x
top	-	system		Monitor	btop	btop	x
integrity	verify|check	system		Integrity	verify install	command claw integrity audit	-
onboard	onboarding|character	system		Onboarding	arcade profile picker	command claw onboard	-
gamble	slots|casino	system		Claw Machine	honest slot machine	command claw gamble	-
theme	themes|colors	system		Theme	pick a palette	command claw theme fzf-pick	-
off	-	system		Off	unload profile, keep shell	claw off	-
ai-services	aisvc|services	tools	-	ai-services	self-hosted stacks	command claw ai-services	hidden
docker	containers|dps	tools	-	docker	container overview	command claw docker	hidden
```
Every remaining `bin/claw` dispatch arm gets a `hidden` row so coverage is total. Flags: `!` confirm · `x` external (no shell mutation) · `l:<mod>` lazy-source · `hidden` (help/completion only). `run` is eval'd in the current zsh by `_claw_action`; `ov` and `cl` are existing functions in obsidian.zsh/clin.zsh (no `_claw_vault_open` exists).

### Emitter — `registry.sh`
```
registry.sh rows        → kind\tid\taliases\tgroup\tglyph\tlabel\tdesc\trun\tflags      (profiles by tier,name; then actions in file order)
  profile\tsecurity\t-\tdomain\t󰒃\tsecurity\tpentest · OSINT · scope-gated harness\tclaw load security\ttheme=matrix;start=${PENTEST_WORKSPACE:-$HOME/pentest}|@vault-folder;class=NIGHTHACKER;help=sec-help
registry.sh palette     → id\tkind\t<glyph> <label>\t<desc>\t<group>   frecency-sorted (score = count×w(age): 4 <1h · 2 <1d · 1 <7d · 0.5 <30d · 0.25), then rows order; `hidden` excluded
registry.sh help        → grouped themed text (CLAW_RGB_* fallbacks) for cmd_help Profiles/verbs sections
registry.sh completion  → `id:desc` lines incl. aliases + profiles
registry.sh ids [--with-aliases] [profiles|actions]
registry.sh run <id>    → run snippet ;  registry.sh show <id> → pretty row (palette preview, T2)
registry.sh check       → exit 1: bad column count · duplicate id/alias/glyph across BOTH sources · missing PROFILE_GLYPH/PROFILE_DESC · `command claw <sub>` whose <sub> is not a dispatch arm · unknown flag
```
Env: `DOTFILES_DIR`, `XDG_STATE_HOME` (frecency), `CLAW_NOW` (test override; BSD awk has no systime). ~15 ms. Never on the login path.

### State files (all under `${XDG_CACHE_HOME:-~/.cache}/claw`, mktemp+mv)
- `situation.json` (existing): `{ts, host, tailscale:{state,peers_online,peers_total}, ollama:{up,models}, gpu:{present,util,temp,…}, disk_root_pct, k3s:{ready,total}, homelab_reachable, updates:{…}}`
- `homelab.json` (existing + `state` gains `unknown`): `{ts, fleet, cluster:{context,ready,total}, route:{via,path,exit_node}, identity:{github:{user,state}}, machines:[{id,state:up|degraded|down|unknown,addr,latency_ms,services:[{id,state,detail}]}]}`
- `updates.json` (existing, landed): `{ts, brew, brew_err, apt, repo_behind, repo_ahead, last_run}`
- `local.json` (new, `situation.sh local`, 10-min throttle): `{ts, things:{today,inbox}|null, handoff:{title,path,age_s}|null, repos:{dirty,total,sample:[…3]}, worktrees, claude_sessions, cwd_repo:{branch,dirty}|null}`
- `attention.json` (new, `situation.sh evaluate`): `{v:1, checked:{situation,homelab,updates,local}, items:[{id, tier:crit|warn|info, text, hint, since, src_ts}]}`
- `attention.tsv` (same items, zsh-readable): `tier\tid\ttext\thint\tsince_epoch\tsrc_epoch` sorted crit→warn→info, then since asc
- `attention.count`: one line `<n> <worst_tier>` (n counts crit+warn only), for the p10k segment
- `card.stamp`: one line `YYYYMMDD` (local date) — the daily card guard (T2 also folds fact-* into it)

State under `${XDG_STATE_HOME:-~/.local/state}/claw`: `frecency.tsv` (`id\tcount\tlast_epoch`), `acks.tsv` (`id\tuntil_epoch`), `theme` (existing). Config: `~/.config/claw/login-profile` (one line; written by `claw pin`).

### Attention rules (`situation.sh evaluate`, jq, one place)
```
crit  tailscale.state != Running                    → tailscale down
crit  k3s.ready < k3s.total                         → k3s R/T Ready · <ctx>
crit  disk_root_pct ≥ DISK_WARN_PCT                 → disk N%
crit  gpu.temp ≥ GPU_TEMP_WARN                      → gpu N°C
crit  machine.state == down (never `unknown`)       → <id> down
warn  service.state != up on an up machine          → <svc> on <id>
warn  brew_err/apt_err non-null                     → brew ✗ <err> · hint
warn  load1/ncpu ≥ LOAD_WARN_X (2.0)                → load N on C cores
warn  any source age > 2×TTL                        → <source> stale Nh   (items from that source are dropped, not shown as current)
info  repo_behind > 0                               → dotfiles ↓N · claw update
info  brew+apt > 0                                  → N pkg pending · claw update
context (always, one row, never a tier): Things inbox/today (THINGS_SHOW=nonzero) · handoff <7d · claude sessions >0 · dirty repos >0
`since` = previous item's since when the id persists, else now.  Acked ids (until > now) are written with tier=info,hint=acked — strip/card hide them, tick still diffs them.
```
`cmd_tick` = probe → homelab (throttled) → evaluate → diff previous attention.json ids by tier → `notify crit|info` on appearance/clearance. The seven hand-rolled transitions and their env gates collapse into this diff (UPDATES_NOTIFY still gates the repo-behind info item).

### Strip and card rendering
Strip (zsh): for each crit/warn row and each info row with a hint: `● text  hint  (age)` — dot in CLAW_RGB_RED/AMBER/BLUE, text FG, hint MUTED, age from src_epoch as `12s|4m|2h|3d`, `· since HH:MM` when since ≠ src. Max 3 rows then `+N more · claw dash`. Nothing when empty. NO_COLOR → `! ~ i` prefixes.
Card (python `--login`): header · segments · bars · `├─ attention ─┤` rule · all items (max 6, then `+N more · claw doctor`) · context row · `✓ all clear · checked 2m ago` when empty · `no state yet · claw situation probe` when attention.json is absent.

### Palette artifact (`claw_theme_emit`)
```
p10k → typeset -g POWERLEVEL9K_DIR_BACKGROUND='#<blue>' …DIR_FOREGROUND='#<bg>' VCS_CLEAN_BACKGROUND='#<green>' VCS_MODIFIED_BACKGROUND='#<amber>' VCS_CONFLICTED_BACKGROUND='#<red>' OS_ICON_BACKGROUND='#<muted>' KUBECONTEXT/TERRAFORM_BACKGROUND='#<purple>' AWS_BACKGROUND='#<amber>' GCLOUD_BACKGROUND='#<cyan>' STATUS_ERROR_BACKGROUND='#<red>' PROMPT_CHAR_OK_*_FOREGROUND='#<green>' PROMPT_CHAR_ERROR_*_FOREGROUND='#<red>' (all *_FOREGROUND on blocks = '#<bg>')
tui  → c_reset c_bold c_blue c_green c_purple c_amber c_red c_muted c_fg  +  legacy aliases c_cyan(=blue) c_orange c_yellow(=amber) c_dim(=muted) c_white(=fg)   as $'\e[38;2;R;G;Bm'
fzf  → the existing claw_theme_fzf string (CLAW_FZF_COLOR stays the exported name)
osc  → printf '\e]10;#<fg>\e\\\e]11;#<bg>\e\\\e]12;#<blue>\e\\'  only when -t 1, no SSH_*, no TMUX, TERM_PROGRAM ∈ ghostty|iTerm.app|WezTerm|kitty or VTE_VERSION, CLAW_THEME_OSC≠0
depth → CLAW_COLOR_DEPTH = 0 | 24 | 256 | 8  (Apple_Terminal → 256)
```
Fallback idiom everywhere remains `${CLAW_RGB_X:-refined-dark}` (bin/claw:24-30).

### Telemetry row
`ISO-ts \t event \t argc \t profile [\t k=v;k=v]` — the 4-column readers still parse. Payload keys: `term actor shell ms items strip card q rank src kind`. Events listed in Decisions/Telemetry.

## Interrupt safety

1. **Construction.** `claw_login` is pure zsh; the hook runs after steps 4-8 (verified ordering under p10k). SIGINT during the render kills python (rc 130) inside a shell that already has aliases, `claw()`, completion and p10k.
2. **rc guard.** `.zshrc` step 1 sets `trap ':' INT`; the last line and the hook both run `trap - INT`. Ctrl-C during oh-my-zsh no longer skips steps.
3. **Hook.** First statement `add-zsh-hook -d precmd _claw_login_render` (cannot fire twice); `setopt localtraps; trap '_claw_tlog tui:abort:render; return 130' INT` — the log call is inside the trap string because `return` aborts the function. `tui:abort:init` from a `zshexit` hook armed by `claw_login` and disarmed by the render hook.
4. **F-02.** mode=agent registers no hook, launches nothing; kicks are human/ssh-only, `nice -n 10`, `&!`, mkdir-locked, throttled.
5. **F-06.** No stdin reader on the login path; the palette opens only on `claw`/`claw menu`/^G after a prompt exists; unmatched Enter → NONE; the outcome parser rejects ids absent from the registry.

## Theme

Fork-free single load (see Decisions). `claw_theme_apply_profile` is a no-op when `PROFILE_THEME_DEFAULT=""` — so with the F-14 default the daily shell shows the persisted palette (refined-dark until `claw theme set`). `claw theme set <slug>` in the zsh wrapper: `claw_theme_load; eval "$(claw_theme_emit p10k)"; (( $+functions[p10k] )) && p10k reload; claw_theme_emit osc`. `claw load`/`claw off` emit OSC on palette change. `muted` is chrome only (borders, ages, hints); values render in `fg`. Contrast lint (report-only) is T2.

## Render

One engine (`frame()/vis()/_clip()`), three modes in T1: `--login` (card), `--profile <key>`, default (= `--login`). Data = one `fastfetch --format json` call (30 ms; Uptime.uptime ms; host from `os.uname().nodename`; model from `Host.name`) + pure cache reads + `git rev-parse`/`status --porcelain` only when cwd is a repo ≠ $HOME. Breakpoints: ≥100 cols logo+body · 80-99 body only · <80 single column, 8-cell bars. Load shown as text, never a red bar. Logo resolution per Decisions (SGR-first, tint fallback, `--pipe false` for the builtin mark). Targets: `--login` ≤120 ms warm, `--profile` ≤150 ms; the strip <1 ms.

## Palette

`registry.sh palette` → fzf (`--delimiter=$'\t' --with-nth=3.. --nth=2,3,4 --tiebreak=index --layout=reverse --border --ansi --prompt='claw ▸ ' --expect=ctrl-p --color="$CLAW_FZF_COLOR"`, `--height=~60%` when fzf ≥0.34 else `--height=60%`; rc 2 prints fzf's stderr). Output parsed by line position (expect key, selection). `ctrl-p` → `claw pin <id>` (profiles only). Selection → `PROFILE\t<id>` | `ACTION\t<id>`; empty → `NONE`. `_claw_apply_outcome` is the ONE applier (palette, `claw <p>`, any future front-end).

## Attention

Persistent tier = strip (every fresh human/ide/ssh/unknown login) + p10k `⚑N` (every prompt, one `zstat` on attention.count, re-read on mtime change, `$(<file)` fork-free, hidden at 0). Interrupt tier = `situation.sh tick` notifications (unchanged engine, now driven by the evaluate diff). Timer stays opt-in; the doc says so honestly: without it `since` is the first post-login probe.

## Telemetry

See Data contracts. `claw tui-stats [--days 30|60] [--actor human|agent|all]`: logins by mode, abort rate (`tui:abort:*` ÷ human logins), palette opens per human login, top picks, top no-pick queries, autoload accuracy (human logins followed by `load:<other>` within 5 min), agent shells suppressed. Verdict thresholds apply to the palette on human rows only.

## Tiers

- **T0** (remaining quick-wins on HEAD): F-01 rc trap + pty harness, F-08 load bar, F-11 fork-free theme, F-13 tui-style/cheatsheet consume theme, F-16 XDG `:=` + term/actor on the fire row, F-18/F-20 partial fixes in the existing TUI, F-15 toolkit rows, F-22 plugin trim.
- **T1**: registry + meta fields + F-14 default; theme generator + p10k (incl. ⚑); situation evaluate/local/homelab; dashboard data path + `--login` + `--profile`; claw-login.zsh; claw-palette.zsh + claw-fn; bin/claw + completion; retire welcome-tui.zsh; docs.
- **T2**: OSC for Apple Terminal/tmux passthrough; `--card` + tui_header; glyph fallback + doctor font check; depth 256/8; lints; onboarding/cheatsheet lists; toolkit → actions; rust → legacy (flagged); logo dedupe + Apple mark; cache hygiene; `@recent` (flagged); palette preview.

## Testing strategy

All bats use the existing idiom (stub PATH dir, `HOME=$BATS_TEST_TMPDIR`, `XDG_*` redirected, `DOTFILES_DIR=$BATS_TEST_DIRNAME/..`, `CLAW_NO_LOG=1`). CI is ubuntu-latest with zsh + bats, no fzf/fastfetch/yq: every test that needs them stubs or `skip`s. New pty harness `tests/fixtures/pty_login.py` (python `pty.fork`, `ZDOTDIR` pointing at a generated rc that sources the repo's `.zshrc` with stubs on PATH) is shared by `login.bats`. Fork-count assertions trace the FUNCTION (`zsh -fc 'source theme.sh; unset CLAW_THEME_SLUG; set -x; claw_theme_load' 2>&1 | grep -cE "^\+.*\b(cut|tr|head|sed)\b"` = 0), not the file, because theme.sh:265 swallows xtrace. Registry coverage: dispatch arms ⊆ ids∪aliases, profile dirs = profile rows, no surviving 18-name list, run resolution. Dashboard: fixture `tests/fixtures/fastfetch.json`, width-exact at 58/80/100/120/200, `--profile` for all 18 rc 0 with no `n/a`/`dumb` leaks, uptime from ms. Attention: fixture JSON sets → expected items/tiers/since carry-over/ack/stale-drop. Perf smoke prints (never fails CI). Existing tests touched: homelab.bats, update-status.bats, session-identity.test.zsh, dashboard.bats, ff-readout.bats, profiles-lint.bats.

## Risks

| Risk | Mitigation |
|---|---|
| Blank ~0.45 s before the strip/prompt where a dashboard used to start at 0.1 s | Measured with the harness; if it reads slow, `claw_login` prints a one-line themed `open claw ▸ <profile>` (<1 ms). Henry decides after a week. |
| `trap ':' INT` left armed if .zshrc errors before its last line | The render hook also resets it on the first prompt; login.bats asserts `trap` shows no INT handler after the prompt. |
| fastfetch JSON differs on Ubuntu package versions | `dict.get` defaults per module, stdlib fallback, fixture pins the 2.68 shape, `claw doctor` reports which data path ran. |
| awk meta parser vs zsh line reader disagree (6 files carry trailing comments, START_DIR carries `${VAR:-…}`) | Lint grammar `^PROFILE_[A-Z_]+="[^"]*"( *#.*)?$`; both readers strip identically; registry.bats cross-checks `registry.sh rows` against `zsh -fc 'source meta.zsh'` for all 18. |
| F-14 visible daily change | Own commit; `claw theme set synthwave` restores neon and persists. |
| OSC on a terminal that half-applies it | Allow-list only; never tmux/SSH; CLAW_THEME_OSC=0; Apple Terminal via osascript in T2 after a manual check. |
| Registry lint makes new profiles harder | Two fields, lint says exactly what to add; net edits per new profile 6 files → 1. |
| Concurrent writers (ten tabs) | mktemp+mv, append-only TSV, mkdir locks, zsystem flock on card.stamp; the render never writes. |
| Dropping istioctl/operator-sdk/emoji | Overridable via CLAW_OMZ_EXTRA_PLUGINS; documented in the commit. |
| Deleting the picker hides 15 rarely used profiles | Bare `claw`/^G, `claw help`, completion of profile names; tui-stats shows whether palette use replaces the old L2 picks. |

## Decisions & overrides

See `decisions` (structured). Taste items: F-14 default `PROFILE_THEME_DEFAULT=""` for default/local/claude (revert: one line or `claw theme set synthwave`); F-19 rust untouched through T1, T2 flagged move to legacy/ + ci.yml (say "keep" for the thin-renderer alternative); login card `daily` (CLAW_LOGIN_CARD=always|never); landing dir unchanged (Q3 open).

## Open questions

1. Q3 landing dir — `@recent` token wanted? 2. Q4 timer on the Mac — install once the LAN gate/`ts:` names land? 3. Q7 fact card — keep delight.zsh's fact after the prompt, fold into the daily card, or drop? 4. Q8 contrast — raise `muted` in five palettes or add `muted_text`? 5. Q9 agent-first `claw output` exit codes — in scope? 6. Blank-then-strip vs a one-line acknowledgement at 0 ms — decide after a week of use.