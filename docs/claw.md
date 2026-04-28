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
claw load <profile>   source a profile in current shell
claw off              unset active profile
claw <agent>          launch a registered agent (claude, hermes, …)
claw agent list       list registered agents
claw agent add        claw agent add <name> <command> [profile]
claw install <tc>     opt-in toolchain installer (cloud/security/…)
claw help             this list
```

`claw` lives at `bin/claw` in this repo and is auto-added to `PATH` via
`shell/path.zsh`. Open any new shell after install and you're good.

---

## Profiles

Nine profiles ship in `shell/profiles/`. Pick one from the welcome menu
on shell login, or load on demand with `claw load <name>`:

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

### Adding a new agent

Either edit the TOML directly or use:

```bash
claw agent add hermes hermes-cli ai
claw agent add aider  aider     ai
claw agent add gemini gemini    ai
```

Then launch:

```bash
claw hermes        # loads ai profile dashboard, then exec hermes-cli
claw aider         # same pattern
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

Each profile's fastfetch dashboard renders an ASCII rendition of a real
brand logo via `chafa`. To swap:

```bash
bash scripts/utils/logo-from-image.sh <profile> <url-or-path>

# Examples:
bash scripts/utils/logo-from-image.sh claude  https://cdn.simpleicons.org/anthropic/d97757
bash scripts/utils/logo-from-image.sh cloud   ~/Downloads/aws-logo.png
```

The helper:
1. Fetches the URL or copies the local file
2. Rasterizes SVG → PNG (400×400, GitHub Dark bg) via `rsvg-convert`
3. Converts to 28×14 half-block 24-bit ASCII via `chafa`
4. Writes `config/.config/fastfetch/logo-<profile>.txt`
5. Patches `config-<profile>.jsonc` to use `logo.type=file-raw`

Tunables: `WIDTH=`, `HEIGHT=`, `BG=` (hex without `#`).

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
