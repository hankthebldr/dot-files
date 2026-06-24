# `claw` — Open Claw user guide

The single command that surfaces every workflow in this dotfiles repo.

```
claw                  open the welcome menu (FZF)
claw doctor           system + active-profile health
claw update           full system update (brew/npm/pip/etc)
claw tools            interactive curated CLI tool refresh
claw tun              SSH tunnel manager
claw mcp              MCP server manager
claw homelab          homelab SSH topology
claw toolkit          Open Claw workflow launcher
claw skills           browse Claude skills
claw harness <cmd>    custom agentic tooling: new <kind> <name> · list [--all|--fzf] · sync · deploy · path
claw ai-services <c>  manage local AI service stacks (litellm, llama-swap, …)
claw gateway <c>      OpenShell sandbox / gateway manager
claw load <profile>   source a profile in current shell
claw off              unset active profile
claw <agent>          launch a registered agent (claude, hermes, …)
claw agent list       list registered agents
claw agent add        claw agent add <name> <command> [profile]
claw install <tc>     opt-in toolchain installer (cloud/security/…)
claw output           display settings (mode/frame/banner, persisted)
claw help             this list
```

`claw` lives at `bin/claw` in this repo and is auto-added to `PATH` via
`shell/path.zsh`. Open any new shell after install and you're good.

---

## Profiles

18 profiles ship in `shell/profiles/` (8 core + 10 specialized). Pick one
from the welcome menu on shell login, or load on demand with `claw load <name>`:

| Profile  | What it's for                           | Logo brand        |
|----------|-----------------------------------------|-------------------|
| default  | Daily-driver shell                      | Apple (current OS)|
| claude   | Anthropic Claude Code workspace         | Anthropic         |
| cloud    | AWS · GCP · Kubernetes · Terraform      | Kubernetes        |
| security | Pentesting · DFIR · reverse engineering | Kali Linux        |
| devops   | CI/CD · monitoring · IaC                | Docker            |
| ai       | Ollama · LLMs · MLOps                   | HuggingFace       |
| research | Scraping · text analytics · OSINT       | Jupyter           |
| cortex   | Palo Alto XSOAR · XSIAM · PAN-OS        | Cortex orange     |
| local    | Custom-built CLI tools                  | Raspberry Pi      |

Each profile sets `CLAW_PROFILE_THEME`, defines its own `<profile>-help`
function, and ships a profile-specific fastfetch dashboard
(`config/.config/fastfetch/config-<profile>.jsonc`).

**Aliases are unprefixed** — `cloud-k`, `osint-nmap`, etc. were dropped
in favor of typing `kubectl` / `nmap` directly. What survived is short
mnemonics for genuine compositions (e.g. `tff` = `terraform fmt -recursive`,
`nrecon` = `nmap -T4 -A -v`). See `<profile>-help` inside each profile
for the surviving aliases.

### Activating a profile

- **From the welcome menu** — pick the profile row; `welcome-tui.zsh`
  sources it for that shell.
- **Manually** — `claw load cloud` prints the exact command you need
  to run in your *current* shell (claw itself runs in a subshell and
  can't mutate your interactive shell directly).
- **Auto-launch agents** — see Agents below.

### Switching off

`claw off` prints the unload command. The cleanest way to fully reset is
`exec zsh` from any prompt.

---

## Agents

Agents are coding/AI binaries you launch from the registry at
`~/.config/claw/agents.toml`. Created on first run of any `claw agent` or
`claw <agent>` invocation, with `[claude]` pre-registered:

```toml
[claude]
command = "claude"
profile = "claude"        # optional — auto-load this profile before launch
description = "Anthropic Claude Code"
```

### Pre-built agents

`claw install ai` (see Toolchain installers below) installs and registers two
agents out of the box:

| Agent | Backed by | Default model | Override env var |
|---|---|---|---|
| `claw hermes` | Local Ollama | `hermes3:8b` | `CLAW_HERMES_MODEL` |
| `claw openrouter` | [`aichat`](https://github.com/sigoden/aichat) → OpenRouter | `anthropic/claude-sonnet-4.6` | `CLAW_OPENROUTER_MODEL` |

Both work as REPLs (`claw hermes`) or one-shots (`claw hermes "explain X"`).

`claw openrouter` requires `OPENROUTER_API_KEY` in `~/.dotfiles/.env`. The
key may be a literal or a `op://Vault/Item/field` reference resolved via
1Password CLI when `op` is on PATH (see `shell/load-env.zsh`).

`claw doctor` reports status of all four AI components (ollama daemon,
hermes model, aichat, key) — independent checks, none fatal.

### Adding a new agent

`[claude]` and `[gemini]` are pre-registered out of the box. To add
another, either edit `~/.config/claw/agents.toml` directly or use:

```bash
claw agent add aider   aider       ai
claw agent add hermes  hermes-cli  ai
```

Then launch:

```bash
claw aider         # loads ai profile dashboard, then exec aider
claw gemini        # pre-registered — works immediately after install
```

### Listing

```bash
claw agent list
```

Renders each registered agent with its command, profile binding, and
description.

### Why a registry instead of bespoke menu entries

Every new agent used to need a new welcome-TUI row + case branch +
documentation. Now: edit one TOML file. The `claw <name>` dispatcher
resolves the entry, optionally renders the matching profile's fastfetch
dashboard, then `exec`s the binary. Replacement-shell handoff — no
nested-shell weirdness.

---

## AI services & gateways

`claw ai-services` manages the local AI service stacks — start/stop/inspect
them uniformly regardless of how each one actually runs:

```bash
claw ai-services list                 # registry + live port status
claw ai-services up   [svc...]        # start (no args = all)
claw ai-services down [svc...]        # stop
claw ai-services restart [svc...]
claw ai-services status [svc...]
claw ai-services logs <svc>           # follow logs
claw ai-services url  <svc>           # print the localhost URL
```

The registry (`scripts/utils/ai-services.sh`) supports three service **kinds**:

| Kind       | Backed by                          | Examples                          |
|------------|------------------------------------|-----------------------------------|
| `local`    | docker compose file in this repo   | litellm, open-webui, langfuse     |
| `upstream` | cloned compose repo (git)          | dify, ragflow                     |
| `host`     | systemd `--user` unit (no docker)  | llama-swap                        |

`up`/`down`/`status`/`logs` dispatch on the kind, so a compose stack and a
host daemon are driven by the same commands.

| Service      | Port  | What it is                                              |
|--------------|-------|---------------------------------------------------------|
| `litellm`    | 4000  | Unified OpenAI-compatible gateway → ollama, vLLM, llama-swap, cloud. Config `config/litellm/config.yaml`; master key `LITELLM_MASTER_KEY` (set in `.env`). Image **pinned** (`v1.89.2`) — see the OPSEC note in the compose file. |
| `llama-swap` | 8090  | Hot-swaps vLLM models behind one endpoint, frees VRAM on an idle TTL — the 24 GB juggling fix. Host binary `~/.local/bin/llama-swap`, systemd `--user` unit, config `config/llama-swap/config.yaml`. |
| `open-webui` | 3000  | ChatGPT-style UI for ollama                             |
| `langfuse`   | 3001  | LLM observability / tracing                             |
| `dify`       | 8080  | LLM app-builder platform (upstream)                     |
| `ragflow`    | 8081  | RAG engine + deep-doc parsing (upstream)                |

**llama-swap as a host service:** the `ai-workstation-toolchain.sh` installer
fetches the binary and symlinks `config/systemd/llama-swap.service` into
`~/.config/systemd/user/`, so `claw ai-services up llama-swap` just runs
`systemctl --user start`. For it to survive logout on a headless box, run once:
`loginctl enable-linger "$USER"`.

**Related, not services:** agentic coding CLIs (`claw opencode`, `claw openwork`)
live in the agent registry; LLM red-team/eval tools (`garak`, `promptfoo`) ship
with the `security` profile. All are installed by the toolchain installers.

---

## Tool refresh

Two-tier system:

- **`claw update`** — the heavy hammer. Iterates every package manager
  on the system (brew/npm/yarn/pnpm/uv/pipx/pip3/gem/rustup/go/oh-my-zsh)
  and refreshes everything. Use after a fresh install or once a month.
- **`claw tools`** — curated refresh of just the CLI tools this repo
  cares about (`eza`, `bat`, `zoxide`, `fd`, `ripgrep`, `bottom`, `zellij`,
  `rovr`, `osint-d2`, `clawea`, `netwatch-tui`, `eilmeldung`). Cache
  granularity is per-category (brew/pipx/go/cargo) with sane intervals
  (weekly/weekly/bi-weekly/monthly). Add `--force` to override the
  cache.

The silent background variant of `tool-updater.sh` still fires once on
shell init via `welcome-tui.zsh` — you'll never notice it. The
`--interactive` mode is what `claw tools` invokes.

---

## Output settings

`claw output` persists how claw surfaces render. State lives at
`${XDG_STATE_HOME:-~/.local/state}/claw/output`; resolution mirrors the theme
engine — `CLAW_OUTPUT_*` env (session override) → state file → built-in default.

```bash
claw output                       # same as `status` — show the resolved settings
claw output status
claw output mode auto|rich|plain  # auto = rich on a TTY, plain over SSH/CI
claw output frame viewfinder|none # ⌜⌝⌞⌟ corner brackets vs. a plain rule
claw output banner on|off
claw output get <key>             # print one resolved value (mode | frame | banner)
```

Defaults: `mode=auto`, `frame=viewfinder`, `banner=on`. `mode plain` forces clean
log lines everywhere (handy in scripts); `frame none` swaps the viewfinder brackets
for a single horizontal rule. Backed by `scripts/utils/claw-output.sh`.

---

## Live progress panel

Long-running single-process claw ops (`claw pkg install` / `track` / `scan`)
render an inline, themed, phase-driven status panel framed in viewfinder corner
brackets (`⌜⌝⌞⌟`): a progress bar, ok/fail/skip tallies, elapsed time, and the
current item + phase. Raw tool output is captured off-screen to
`${XDG_STATE_HOME:-~/.local/state}/claw/logs/<op>-<t0>.log` so the panel stays
clean — `tail` that file to see what a command actually printed.

Rich mode renders only when **all** of these hold:

- stdout is a TTY
- `CLAW_PROGRESS_ENABLED` ≠ `0` (see the master switch below)
- `TERM` ≠ `dumb`
- `CI` is unset
- resolved `claw output mode` ≠ `plain`

Otherwise it degrades to plain, append-only log lines (the SSH/CI path). Force
either end with `claw output mode rich|plain`. Engine: `scripts/utils/claw-progress.sh`.

### Master switch — `progress`

`progress` is a shell function (`shell/progress.zsh`) that toggles
`CLAW_PROGRESS_ENABLED`, the master on/off for the live panel:

```bash
progress status   # show state + thresholds
progress off      # disable the live panel
progress on       # re-enable
```

`progress on|off` **exports** `CLAW_PROGRESS_ENABLED`, so the child `bash` that
draws the panel honors the toggle.

---

## Where each TUI lives

`claw` is a thin dispatcher. The actual work happens in:

| Subcommand    | Implementation                                  |
|---------------|-------------------------------------------------|
| `claw`        | `shell/welcome-tui.zsh` (sourced via subshell)  |
| `claw doctor` | inline in `bin/claw` (cmd_doctor)               |
| `claw update` | `scripts/utils/system-update.sh`                |
| `claw tools`  | `scripts/utils/tool-updater.sh --interactive`   |
| `claw tun`    | `scripts/utils/tunnel-manager.sh`               |
| `claw mcp`    | `scripts/utils/mcp-manager.sh`                  |
| `claw homelab`| `scripts/utils/homelab.sh`                      |
| `claw toolkit`| `scripts/utils/toolkit.sh`                      |
| `claw skills` | inline in `bin/claw` (FZF over `~/.claude/skills`) |
| `claw output` | `scripts/utils/claw-output.sh`                  |
| live progress panel | `scripts/utils/claw-progress.sh` (sourced by `pkg-manifest.sh`) |

If a subcommand misbehaves, debug the underlying script directly — `claw`
just routes argv to it.

---

## Toolchain installers (opt-in)

Per-profile toolchain installers live at `scripts/install/<name>-toolchain.sh`.
They are NOT auto-run on profile switch. To install:

```bash
claw install cloud      # AWS, kubectl, terraform, helm, k9s, …
claw install security   # nmap, sqlmap, hashcat, …
claw install devops     # docker, kubectl, helm, ansible, …
claw install ai         # ollama, llama-cpp, huggingface-cli, …
claw install research   # csvkit, scrapy, pandoc, yt-dlp, …
claw install cortex     # demisto-sdk, panos-cli, …
```

Each script is idempotent (`command -v` guards before each install).
Re-running just upgrades what's installed.

---

## Customizing logos

Each brand profile ships **two** logo assets so the dashboard looks its best in
a graphics terminal while still degrading gracefully:

- `logo-<profile>.png` — high-res raster (the **graphics logo**). On a live
  local Ghostty / Kitty / iTerm tty the `claw_ff` shim (`shell/fastfetch.zsh`)
  renders it via the kitty/iterm image protocol, pinned to 28×14 cells.
- `logo-<profile>.txt` — `chafa` **quad-block** 24-bit ANSI (the **text
  fallback**). Used over SSH, in tmux, on dumb/`linux`/`screen` terminals, or
  when piped. fastfetch's `--logo-type auto` does *not* detect graphics support
  or fall back, so the shim scripts the choice.

> Quad blocks (U+2596–259F), not half-blocks — ~2× the detail and font-safe.
> Sextant/octant are denser still but tofu in `JetBrainsMono Nerd Font` and over
> SSH, so the recipe deliberately avoids them.

Regenerate **all** brand logos (both tiers) from their canonical sources:

```bash
bash scripts/utils/regen-logos.sh            # all profiles
bash scripts/utils/regen-logos.sh local ai   # just these
```

`regen-logos.sh` is the single source of truth for the brand mapping
(`claude→anthropic`, `cloud→kubernetes`, `security→kalilinux`, `devops→docker`,
`ai→huggingface`, `research→jupyter`, `cortex→paloaltosoftware`,
`local→raspberrypi`). Tunables: `W=`, `H=`, `PNG_PX=`, `BG=`.

Swap a **single** profile to new art (writes both `.png` and `.txt`, patches the
config to `file-raw`):

```bash
bash scripts/utils/logo-from-image.sh <profile> <url-or-path>
bash scripts/utils/logo-from-image.sh claude  https://cdn.simpleicons.org/anthropic/d97757
bash scripts/utils/logo-from-image.sh cloud   ~/Downloads/aws-logo.png
```

Requires `chafa` and `librsvg` (`brew install chafa librsvg`).

---

## Common gotchas

- **`claw load X` doesn't actually load** — by design. Subshells can't
  mutate the parent interactive shell. The command prints the source
  invocation; copy/paste it.
- **Welcome TUI fires on every shell** — by design. If you don't want it
  for a one-off, ESC out (drops to plain default) or open a non-interactive
  shell (`bash -c '...'` doesn't trigger it).
- **`claw <agent>` exits the shell when the agent quits** — `exec`
  replaces the shell process. Open a new tab to come back to a normal
  prompt.
- **Old `cloud-k` / `osint-nmap` / `dops-helm` aliases are gone** — type
  `kubectl` / `nmap` / `helm` directly. See per-profile `*-help` for the
  short mnemonics that survived.
- **Security profile no longer auto-creates `~/pentest/<date>_engagement/`** —
  loading the profile is now non-destructive. Run `sec_engagement [name]`
  to create + cd into a new engagement workspace.
- **`agents.toml` not auto-found?** — set `XDG_CONFIG_HOME` if you keep
  it elsewhere; defaults to `~/.config/claw/agents.toml`.

---

## See also

- `docs/superpowers/specs/2026-04-25-claw-mvp-rewrite-design.md` — full
  design spec for this MVP
- `CLAUDE.md` — overall repo conventions
- `bin/claw` — the dispatcher source (~250 lines, well-commented)
- `scripts/utils/tui-style.sh` — shared theme + helper vocab used by
  every claw TUI script
