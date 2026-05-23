# Profile Architecture — Per-OS Sub-Files

> Reference doc for the 18-profile architecture introduced in
> [`docs/superpowers/specs/2026-05-19-18-profile-architecture-design.md`](../superpowers/specs/2026-05-19-18-profile-architecture-design.md).
> Read this first if you're adding a new profile or migrating an existing one.

## Mental model

A profile is a *named workflow*. Same purpose on Mac and Linux, divergent tools per OS. The directory layout makes that explicit:

```
shell/profiles/
├── cloud.zsh                  ← 4-line dispatcher (entry point)
└── cloud/                     ← profile assets
    ├── meta.zsh               ← metadata (class, theme, tag, OS support, toolchain)
    ├── common.zsh             ← aliases/exports/help that run on every OS
    ├── mac.zsh                ← macOS-only aliases and tool checks
    ├── linux.zsh              ← Linux-only aliases and tool checks
    └── logo.txt               ← ASCII splash referenced by fastfetch + claw load
```

The dispatcher (`cloud.zsh`) is the entry point that `welcome-tui.zsh`, `claw load`, and `.zshrc` all source. It chains together the assets in the right order. You touch the dispatcher only when adding/removing per-OS sub-files.

## Dispatcher template

Copy this template verbatim for every new profile. Replace `cloud` with your profile name.

```zsh
# shell/profiles/cloud.zsh — dispatcher
_PROFILE_DIR="${0:A:h}/cloud"
source "${_PROFILE_DIR}/meta.zsh"          # declare PROFILE_* metadata
source "${_PROFILE_DIR}/common.zsh"        # shared aliases/exports/help fn
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
```

Four lines. `${0:A:h}` resolves to the dispatcher's own directory regardless of how it was sourced (`source ...`, dot, symlink). `OS_FAMILY` is exported by `shell/platform.zsh` — values are `mac`, `linux`, or `generic`.

## `meta.zsh` schema

Pure bash variable assignments — no parser, no logic. Every field is required unless marked optional.

```zsh
# shell/profiles/cloud/meta.zsh

# IDENTITY
PROFILE_NAME="cloud"                          # must match the dispatcher filename
PROFILE_CLASS="SKYSURFER"                     # RPG-style class (consistent w/ onboarding _profile_class)
PROFILE_TIER="2"                              # 1=general, 2=domain, 3=agent, 4=knowledge, 5=customer, 6=hardware

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="synthwave"             # synthwave | matrix | dosbbs | vhs
PROFILE_TAG="boots up clusters before breakfast"
PROFILE_FLAIR="owns 4 TLDs you've never heard of"

# OS SUPPORT
# Values describe the *role* of each OS for this profile:
#   "mac+linux"             — full parity, slightly different tools
#   "mac=remote, linux=native"  — Linux runs real workload; Mac is the cockpit
#   "mac-primary"           — Mac is the only fully-supported OS (e.g. Things 3)
#   "linux-primary"         — Linux is the only fully-supported OS (e.g. CUDA)
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="cloud-toolchain.sh"        # script name in scripts/install/, empty if N/A
PROFILE_KEY_TOOLS="kubectl terraform aws gcloud az helm"   # space-separated, used by `claw doctor`
```

### Field reference

| Field | Purpose | Consumers |
|---|---|---|
| `PROFILE_NAME` | Canonical identifier | dispatcher, claw load, welcome TUI |
| `PROFILE_CLASS` | RPG-style class name | claw load ceremony, onboarding verdict |
| `PROFILE_TIER` | Menu grouping (1-6) | welcome TUI menu generator |
| `PROFILE_THEME_DEFAULT` | Default cinematic theme | claw load splash, fastfetch palette |
| `PROFILE_TAG` | One-line description | menus, fastfetch subtitle, claw doctor |
| `PROFILE_FLAIR` | Roast-y subtitle | onboarding box reveal, claw load ceremony |
| `PROFILE_OS_SUPPORT` | OS-role declaration | claw doctor warnings, welcome TUI filter |
| `PROFILE_TOOLCHAIN` | Install script name | `claw install <profile>` dispatch |
| `PROFILE_KEY_TOOLS` | Tools to probe for health | `claw doctor` |

## `common.zsh` — shared aliases / exports / help

Things that work identically on both OSes. Usually:

- High-level aliases that resolve to `platform.zsh` shims (`alias copy='clip_copy'`)
- Environment exports that don't depend on per-OS tool paths
- The profile's `help` function (`cloud-help`, `security-help`, etc.)
- Theme/color preferences

```zsh
# shell/profiles/cloud/common.zsh
export CLAW_PROFILE_THEME="synthwave"

alias k='kubectl'                          # works the same on both OSes
alias tf='terraform'
alias tg='terragrunt'

cloud-help() {
    cat <<EOF
${c_pink}─── ☁️  Cloud profile ───${c_reset}
  k <args>      kubectl
  tf <args>     terraform
  ...
EOF
}
```

## `mac.zsh` — macOS-only

Aliases / tool-check functions / env that only make sense on Darwin. Common reasons something lives here:

- A tool with a different name on macOS than Linux (`brew install netcat` ⇒ `nc`; Linux apt ships `ncat`)
- A macOS-only command path (`/usr/libexec/PlistBuddy`, `osascript`)
- A "remote control" wrapper when the profile is `mac=remote, linux=native`
- iCloud / Spotlight / Finder integration

```zsh
# shell/profiles/cloud/mac.zsh
alias awsl='aws sso login'
alias kctx='kubectx'                          # brew installs kubectx as standalone
alias openconsole='open -a "Safari"'
```

## `linux.zsh` — Linux-only

Same idea, for Linux. Common reasons something lives here:

- A tool with a different name on Linux (`microk8s kubectl` instead of `kubectl`)
- An apt-specific path (`/var/log/journal`, `journalctl`)
- A native Linux capability that has no Mac equivalent (`nvtop`, `systemctl`)
- A different invocation style (`xdg-open` instead of `open`)

```zsh
# shell/profiles/cloud/linux.zsh
alias awsl='aws sso login --no-browser'       # apt path needs the flag
alias kctx='kubectl config use-context'       # no standalone kubectx on apt
alias openconsole='xdg-open https://console.aws.amazon.com'
```

## `logo.txt`

The ASCII splash for this profile. Used by:
- Fastfetch (`config-<profile>.jsonc` references it via `source` field)
- `claw load <profile>` activation ceremony (printed during splash)
- `claw demo <profile>` preview

Keep it ≤22 lines tall and ≤72 columns wide to fit standard terminals.

```
config/.config/fastfetch/config-cloud.jsonc:
  "logo": {
    "source": "~/.dotfiles/shell/profiles/cloud/logo.txt",
    "type": "file"
  }
```

## Loading order

When the dispatcher runs:

1. `meta.zsh` declares `PROFILE_*` globals — pure data, no functions defined yet.
2. `common.zsh` defines aliases, exports, and the profile help function.
3. `${OS_FAMILY}.zsh` overrides or adds OS-specific aliases.

The OS-specific file is sourced **last** so it can override `common.zsh` aliases when needed (e.g., redefining `alias k='microk8s kubectl'` on Linux).

If no `${OS_FAMILY}.zsh` file exists, the profile still loads — just without OS-specific extras. This is the right behavior for profiles like `claude` (agent workflow) that have nothing OS-specific.

## Backward compatibility

A profile can ship as either:

- **New pattern**: `<name>.zsh` dispatcher + `<name>/` directory with sub-files
- **Legacy pattern**: just `<name>.zsh` with everything inline (the original 9 profiles)

The dispatcher's existence check (`[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]]`) gracefully no-ops if the directory doesn't exist. Migration from legacy to new pattern is one profile at a time, no breaking change.

## Adding a new profile — checklist

1. **Create the directory:** `mkdir -p shell/profiles/<name>`
2. **Write `meta.zsh`:** all required fields, see schema above
3. **Write `common.zsh`:** shared aliases + `<name>-help` function
4. **Write `mac.zsh` and/or `linux.zsh`:** OS-specific bits
5. **Write the dispatcher:** copy the 4-line template, replace name
6. **Add `logo.txt`:** ASCII splash, ≤22×72
7. **Add to welcome TUI:** the menu auto-populates from `meta.zsh` once that's wired up (Phase D); until then, manually add a `choices+=` line in `shell/welcome-tui.zsh`
8. **Optional: add toolchain installer:** `scripts/install/<name>-toolchain.sh` following the [`toolchain-runner.sh`](../../scripts/install/lib/toolchain-runner.sh) pattern
9. **Optional: add fastfetch dashboard:** `config/.config/fastfetch/config-<name>.jsonc`
10. **Test on Mac AND Linux:** `claw load <name>` on each, verify help fn + key aliases work

## See also

- [`shell/platform.zsh`](../../shell/platform.zsh) — `OS_FAMILY` derivation
- [`scripts/utils/cinematic.sh`](../../scripts/utils/cinematic.sh) — shared themes, animation primitives
- [`scripts/install/lib/toolchain-runner.sh`](../../scripts/install/lib/toolchain-runner.sh) — install script pattern
- [Spec doc](../superpowers/specs/2026-05-19-18-profile-architecture-design.md) — full design rationale
