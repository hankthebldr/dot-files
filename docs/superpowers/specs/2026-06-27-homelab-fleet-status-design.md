# HR-TRUST Fleet Availability — Design

**Date:** 2026-06-27
**Status:** Draft (awaiting review)
**Topic:** Surface live availability of the HR-TRUST homelab (machines + services)
at login and in the profile-selection TUI, in the existing
`icon → context → status` design idiom.

## Problem

The homelab (HR-TRUST) has no ambient availability readout. The existing
`hstatus` function probes a *single* host (`BD790I_HOST`) on demand and prints
four service lines, but:

- It is single-host; HR-TRUST is multiple machines.
- It only runs when explicitly invoked — nothing at login or in the picker.
- It hardcodes ANSI colors (`\e[32m`/`\e[33m`), violating the theme contract.
- It shows service liveness but no **access-level context** (which k8s context,
  which GitHub identity, which Gitea/Portainer instance) and no **traffic route**.

The user wants availability surfaced in the same icon-prefixed, theme-colored,
green/red column idiom already used across the dashboard — covering both
machines and services — plus a Tailscale row showing the route traffic takes.

## Key prior-art discovery

`scripts/utils/situation.sh` is already a complete background poller:
`probe → atomic-JSON cache → tick(diff)/notify → show`. It already probes
tailscale / k3s / ollama / gpu / disk / homelab-ping into
`~/.cache/claw/situation.json` with a top-level `ts` freshness stamp, written
atomically (`mktemp` + `mv -f`), on a 60s systemd timer
(`config/systemd/claw-situation.{timer,service}`).

**But nothing reads that cache ambiently** — it is notify-on-transition only.
So this feature is primarily: (1) widen the poller to a machine×service fleet
writing a second cache, and (2) add the first cache-reading *render* surfaces.
We are not building a poller from scratch.

**Decision (confirmed):** extend `situation.sh` rather than add a sibling
poller — honors the spine's "one X" contracts, reuses the proven
atomic-write / age / single-flight machinery, and keeps one timer + one cockpit
(`claw situation`).

## Architecture

```
┌─ PRODUCER (background; NEVER runs at login) ─────────────────────────┐
│ situation.sh                                                          │
│   probe_json()      existing → situation.json                         │
│   probe_homelab()   NEW      → homelab.json                           │
│     · reads fleet inventory (machines × services)                     │
│     · reuses _hl_status_* probe bodies + new context probes           │
│     · every probe timeout-guarded; atomic mktemp + mv -f; "ts" stamp  │
│   `claw situation tick`  →  writes BOTH caches                        │
│   `claw homelab poll`    →  alias that ticks just the homelab cache   │
│ cadence: systemd timer (Linux) · launchd plist + login-kick (macOS)   │
└──────────────────────────────────────────────────────────────────────┘
        │  readers json.load() / jq the cache — ZERO network at render
        ▼
┌─ READERS (icon → context → status; each in its surface's idiom) ─────┐
│ 1. claw-dashboard.py   homelab_lines()         — LOGIN screen-1       │
│ 2. welcome-tui.zsh     _claw_homelab_block()    — hardware-group pick │
│ 3. config-homelab.jsonc  command rows jq cache  — fastfetch profile   │
│ 4. hstatus()           reads cache if fresh, live-probes if stale     │
└──────────────────────────────────────────────────────────────────────┘
```

The cache JSON is the **single contract** between producer and every reader —
the isolation boundary. A reader can be understood, changed, and tested against
a fixture cache without touching the poller.

## Components

### 1. Fleet inventory (declarative)

New file `config/homelab/fleet.yml` (committed; dotfiles is single-user) with a
machine-local override at `$XDG_CONFIG_HOME/claw/fleet.yml` (untracked, wins if
present). Parsed with `yq` v4 (already a bootstrap dependency). Shipped
`fleet.yml.example` mirrors the `tunnels.yml.example` convention.

```yaml
# config/homelab/fleet.yml
fleet:
  name: HR-TRUST
machines:
  - id: bd790i
    host: bd790i            # tailscale MagicDNS name or IP; env-overridable
    user: henry
    ssh: true               # deep checks allowed (systemctl/docker/kubectl)
    services: [tailscale, k3s, docker, gitea, portainer, ollama]
services:                   # how to probe each service kind
  k3s:       { kind: kube,  context: k3s-bd790i }
  gitea:     { kind: http,  url: "http://bd790i:3000",  health: "/api/healthz" }
  portainer: { kind: tcp,   port: 9443 }
  docker:    { kind: ssh,   cmd: "docker ps -q | wc -l" }
  ollama:    { kind: http,  url: "http://bd790i:11434", health: "/api/tags" }
  tailscale: { kind: native }
identity:                   # access-level context rows (not host-bound)
  github: { probe: "gh auth status" }   # → hankthebldr
```

Adding a box or service becomes data, not code — replacing the baked-in
single-`BD790I_HOST` assumption.

### 2. Poller extension — `probe_homelab()` in `situation.sh`

- Iterates `machines[]`; for each, a fast reachability probe first
  (`tailscale ping --timeout 2s` or `nc -z -w2 host port`); if unreachable,
  mark host `down`, skip its service probes (no hang).
- For reachable hosts with `ssh: true`, reuse the existing `_hl_status_*` probe
  *bodies* (tailscale BackendState, `docker ps -q | wc -l`, kube node Ready,
  ollama model count) over the established ControlMaster socket
  (`/tmp/ssh-bd790i-…`, `ControlPersist=10m`). `http`/`tcp` services probed
  without SSH (curl `--max-time 2` / `nc -z`).
- Context probes (run from the laptop, cheap, no SSH): `kubectl config
  current-context`, `gh auth status` → login, `git config user.name`.
- Tailscale **route**: from `tailscale status --json`, derive per-peer
  `Relay`/`CurAddr` (direct vs DERP region) and any `ExitNodeStatus`, producing
  a human path string `mbp-m4 → direct → bd790i` or `… → DERP(fra) → …`.
- All probes `timeout`-guarded (2–4s); whole snapshot written atomically.

### 3. Cache schema — `~/.cache/claw/homelab.json`

```json
{
  "ts": "2026-06-27T18:22:04Z",
  "fleet": "HR-TRUST",
  "route": { "via": "direct", "path": "mbp-m4 → direct → bd790i", "exit_node": null },
  "identity": { "github": { "user": "hankthebldr", "state": "up" } },
  "machines": [
    { "id": "bd790i", "state": "up", "addr": "100.x.y.z", "latency_ms": 12,
      "services": [
        { "id": "k8s",       "state": "up",   "ctx": "k3s-bd790i", "detail": "1 node Ready" },
        { "id": "gitea",     "state": "up",   "detail": "http 200" },
        { "id": "portainer", "state": "up",   "detail": ":9443" },
        { "id": "docker",    "state": "up",   "detail": "7 containers" },
        { "id": "ollama",    "state": "down", "detail": "unreachable" }
      ] }
  ]
}
```

`state ∈ {up, down, degraded}`. `ts` drives the age/staleness suffix every
reader shows. **Stale threshold:** `5 × poll interval` (= 5 min at the 60s
cadence). Within threshold → render normally with `updated Xs ago`; beyond →
render dimmed/amber with `stale Xm ago`; absent → render nothing.

### 4. Readers

Each renders the same cache in its surface's native status convention (the
surface map confirmed these differ; we match, not unify):

- **`claw-dashboard.py` → `homelab_lines()`** (login screen-1). Modeled exactly
  on `infra_lines()`. Returns a list of lines (one per machine + nested service
  segments). Wired by extending L296:
  `ctx = [l for l in context_lines() + infra_lines() + homelab_lines() if l]`.
  Colors via the `C[]` dict (`C['green']/C['red']/C['amber']`), glyphs via the
  `G` dict (add `server`, reuse `k8s`⎈/`docker`/`git`/`tailscale`). Status dot
  reuses the existing git-marker idiom `col('●', C['green'])`. Width auto-aligns
  via `vis()`/`pad()`. Reads `homelab.json` only — never SSHes. If cache absent
  or stale beyond threshold, the block dims (amber) and shows `stale Xm ago`;
  if absent entirely, renders nothing (graceful skip).
- **`welcome-tui.zsh` → `_claw_homelab_block()`**. Printed (a) in
  `_claw_tui_header()` before the trailing blank (login), and (b) after the
  hardware-group header (L214) when `tok == hardware` (picker). Reads the cache;
  colors via the `c_*` locals already captured from `CLAW_RGB_*` at the top of
  `claw_welcome_tui` (so it *does* retheme, unlike the hardcoded quickref).
  Inherits the function's SSH-safety guards automatically.
- **`config-homelab.jsonc`** (hand-maintained). The existing
  `── BD790i Daemons ───` command rows change from live `ssh`/`tailscale` calls
  to `jq` reads of `homelab.json`, each echoing an ANSI-wrapped `●` (fastfetch
  command modules can't colorize by exit code — color must be emitted inside the
  command's stdout; the status word + colored dot convey up/down). A new
  `── HR-TRUST Fleet ───` section adds machine rows. Glyphs prepended to keys to
  fix the current glyph-less rows.
- **`hstatus()`** (homelab profile). Becomes cache-first: if
  `homelab.json` is fresh, render it (multi-machine now); else fall back to the
  current live per-OS `_hl_status_*` probes. Migrated off hardcoded `\e[32m` to
  `CLAW_RGB_*` tokens (introduces a real red-down state; today down is amber).

### 5. Dispatch & scheduling

- `bin/claw`: add `claw homelab poll|status` cases next to `cmd_situation()`
  (`poll` ticks the cache; `status` prints `hstatus`). One dispatcher — no second
  `claw()`.
- Linux: extend the existing `claw-situation.service` tick to also write
  `homelab.json` (same 60s timer — no new unit).
- macOS (no systemd): a `launchd` plist
  (`config/launchd/com.openclaw.situation.plist`, `StartInterval=60`) on the
  same cadence, **plus** a login self-backgrounded kick (`… &!` in the TUI,
  exactly as `tool-updater.sh` is launched at line 66) so first boot warms the
  cache without blocking. The Mac poller SSHes BD790i via the existing
  ControlMaster.

## Error handling & safety

- **No network at render.** Every reader reads a file; only the backgrounded
  poller touches the network. Enforces the login-latency / SSH-safety rule.
- **Stale-but-present** cache → render dimmed with `stale Xm ago`. **Absent**
  cache → render nothing. **Malformed** cache → guarded parse, skip block, never
  break login.
- **Unreachable host** → `down`, service probes skipped (no per-service hang).
- **Atomic + single-flight** via the existing `mktemp`+`mv -f` and the
  `tool-updater` mkdir-lock idiom, so concurrent logins don't tear the JSON.
- **Theme:** all new rows consume `C[]`/`CLAW_RGB_*` with refined-dark
  fallbacks. Targeted fix: migrate the homelab `_hl_status_*` helpers off raw
  ANSI as part of this work (they're being touched anyway).

## Testing

- **Poller:** unit-test `probe_homelab` against a stub fleet (a fake host that's
  down, one service that 200s, one that refuses) → assert JSON shape, `state`
  values, atomic write, `ts` present. Run with a 0-machine inventory → empty
  `machines: []`, no error.
- **Schema fixtures:** check in `test/fixtures/homelab.{up,mixed,stale,empty}.json`.
- **Readers:** render each surface against the fixtures (set cache path via env),
  assert: up→green dot, down→red dot, stale→amber + age suffix, absent→no output.
  Snapshot the dashboard frame to confirm width alignment holds.
- **Safety:** non-interactive / piped / `SSH_CONNECTION` shell → readers emit
  nothing (inherit existing TUI guards); verify no stdout in a `scp` simulation.
- **Theme:** `claw theme set matrix` then render → dot colors track palette
  (proves no hardcoded ANSI in the new rows).

## Build order

1. Inventory schema + `fleet.yml.example` + loader (yq).
2. `probe_homelab()` + cache schema + `claw homelab poll` + fixtures. (Foundation.)
3. `claw-dashboard.py homelab_lines()` (the primary surface).
4. `welcome-tui.zsh` block (login + picker).
5. `config-homelab.jsonc` cache-backed rows + new fleet section.
6. `hstatus()` cache-first + theme-token migration of `_hl_status_*`.
7. Scheduling: Linux timer extension + macOS launchd + login kick.

## Out of scope (YAGNI)

- Historical/uptime graphing — this is a point-in-time availability snapshot.
- Remote control actions (start/stop services) — read-only status only.
- Auto-discovery of services — inventory is declarative.
- The rust `claw-tui` front-end reader — it reads the same state files, so a
  cache-backed block is portable to it later, but wiring it is a follow-up.
