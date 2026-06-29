# HR-TRUST Detailed Lab Board — Design

**Date:** 2026-06-29
**Status:** Draft (awaiting review)
**Topic:** A detailed, grouped, icon-matched view of every HR-TRUST lab service —
machines, cluster, apps, infra, DNS — surfaced as a *shared* render block on both
the `local` and `homelab` profiles, in the existing
`icon → context → status` dashboard idiom.
**Builds on:** [`2026-06-27-homelab-fleet-status-design.md`](2026-06-27-homelab-fleet-status-design.md)
(the producer/cache/reader seam this extends).

## Problem

The fleet-status work (2026-06-27) established the seam: a background poller
(`situation.sh probe_homelab()`) writes one cache (`~/.cache/claw/homelab.json`),
and render surfaces read it with **zero network**. But the current state has two
gaps against what the user wants:

1. **The inventory is stale and thin.** `config/homelab/fleet.yml` models a
   *single* box `bd790i` with k8s context `k3s-bd790i` and six services. Live
   ground-truth (verified `2026-06-29`) is a **3-node cluster** `k3s-ms01`
   (`ms-01` .109 control-plane, `r630` .102, `bd790i` .104), a **Raspberry Pi
   Pi-hole** at `.101` serving `*.lab.local`, and more services than listed.
2. **No detailed view, and not on `local`.** Status today is a handful of rows
   only on the `homelab` subprofile, with hand-rolled `jq` baked into the
   `.jsonc`. The user wants a *detailed* board of **all** lab services, rendered
   the same way on **both** the `local` profile and the `homelab` subprofile.

The user also called out that the dashboard's per-entity **iconography** (e.g.
the cloud-account brand glyphs in the cloud profile) is a feature to match: each
service should carry its own brand glyph in the established scheme.

## Live ground-truth (verified 2026-06-29)

Cluster `k3s-ms01`, all nodes `Ready`:

| Node     | IP            | Role          |
|----------|---------------|---------------|
| `ms-01`  | 192.168.1.109 | control-plane |
| `r630`   | 192.168.1.102 | worker        |
| `bd790i` | 192.168.1.104 | worker        |
| `pihole` | 192.168.1.101 | DNS (Raspberry Pi) |

Traefik ingresses (HTTP :80), confirmed live:

| Service   | Host                  | Notes |
|-----------|-----------------------|-------|
| gitea     | `git.lab.local`       | helm release `gitea` |
| n8n       | `n8n.lab.local`       | also has an IngressRoute (live Ingress table showed `n8n.lab` — possible misconfig on that Ingress object; verify on-LAN) |
| portainer | `portainer.lab.local` | in-cluster (not standalone docker) |
| enclave   | `enclave.lab.local`   | ns `enclave`, `enclave-console` |
| grafana   | `grafana.lab.local`   | ns `monitoring` (found live; included) |
| harbor    | `harbor.lab.local`    | **not deployed** — declared `planned: true` |

Pi-hole at `.101` resolves `git.lab.local → .109` ✅. Node-local on `bd790i`:
`docker`, `ollama`. `tailscale` is **not installed on the macOS cockpit**, so its
route/native row reads `n/a` when the poller runs from the Mac (guarded; the
nodes themselves run it).

## Architecture

Unchanged seam from 2026-06-27 — this work widens the **inventory** (data), adds
probe **kinds** to the producer, and adds **one shared reader** consumed by three
surfaces:

```
fleet.yml (data)  ──►  probe_homelab()  ──►  homelab.json  ──►  homelab-board.sh
  nodes/services        new kinds:            +nodes[]            (ONE renderer)
  + group + url         http-via-Host,        +cluster{}            │
                        dns, kube             +group/state    ┌─────┼─────────────┐
                                                              ▼     ▼             ▼
                                                   config-local  config-homelab  hstatus()
```

The cache JSON remains the single contract. `homelab-board.sh` is the new
isolation unit: understandable and testable against a fixture cache without the
poller; swappable without touching any `.jsonc`.

## Components

### A. Inventory — `config/homelab/fleet.yml` (rewrite to live truth)

Each service carries a **`group`** (for sectioning) and a **`host`/`url`** (the
probe target). Adding/moving a service stays a pure data edit.

```yaml
fleet: { name: HR-TRUST }
cluster: { context: k3s-ms01, traefik_ip: 192.168.1.109 }   # Host-header probe target
nodes:                                   # group: nodes
  - { id: ms-01,  ip: 192.168.1.109, role: control-plane }
  - { id: r630,   ip: 192.168.1.102, role: worker }
  - { id: bd790i, ip: 192.168.1.104, role: worker }
  - { id: pihole, ip: 192.168.1.101, role: dns, kind: dns, dns_probe: git.lab.local }
services:
  gitea:     { group: apps,  glyph: git,       host: git.lab.local,       kind: http }
  n8n:       { group: apps,  glyph: n8n,       host: n8n.lab.local,       kind: http }
  portainer: { group: apps,  glyph: portainer, host: portainer.lab.local, kind: http }
  enclave:   { group: apps,  glyph: enclave,   host: enclave.lab.local,   kind: http }
  grafana:   { group: apps,  glyph: grafana,   host: grafana.lab.local,   kind: http }
  harbor:    { group: apps,  glyph: harbor,    host: harbor.lab.local,    kind: http, planned: true }
  k3s:       { group: infra, glyph: k8s,       kind: kube }
  docker:    { group: infra, glyph: docker,    host: bd790i, kind: ssh,  cmd: "docker ps -q | wc -l" }
  ollama:    { group: infra, glyph: ollama,    host: bd790i, kind: http, port: 11434, health: /api/tags }
  tailscale: { group: infra, glyph: vpn,       kind: native }
```

`config/homelab/fleet.yml.example` is updated to mirror the new schema
(generic `MY-LAB` values) per the `tunnels.yml.example` convention. Machine-local
override at `$XDG_CONFIG_HOME/claw/fleet.yml` still wins if present.

### B. Producer — `probe_homelab()` in `situation.sh` (extend)

Three probe-kind additions; every probe `timeout`-guarded (2–4s); whole snapshot
still written atomically (`mktemp` + `mv -f`) with a top-level `ts`:

- **`http` via node-IP + `Host` header** — DNS-independent, so it works on-LAN
  *and* over Tailscale (Pi-hole isn't always the resolver):
  `curl -s -o /dev/null -w '%{http_code}' --max-time 2 -H "Host: <host>" http://<traefik_ip>/`.
  Status map: `2xx/3xx/401/403 → up` (Traefik routed), `502/503/504 → degraded`
  (route exists, backend down), `404/000 → down`. A service with `planned: true`
  that returns `404` renders **`planned`** (dim ○), not red — so harbor shows as
  intended-but-not-yet, and flips to `up` automatically once deployed.
  (Services with an explicit `port`/`health`, e.g. ollama, probe that endpoint
  on their `host` directly instead of via Traefik.)
  > **Reachability:** `traefik_ip` is a private LAN address (`192.168.1.x`).
  > It's reachable only when the poller's host is on the home LAN **or** on
  > Tailscale with that subnet routed (or `traefik_ip` overridden to a tailnet
  > MagicDNS name). Off-LAN with no tailnet route, every probe times out and the
  > board honestly renders everything `down` — the correct signal, not a bug.
  > `cluster.context` (kubeconfig) similarly needs the API server reachable.
- **`dns`** (Pi-hole) — `dig +short @<ip> <dns_probe>` returns an A record → `up`;
  empty/timeout → `down`.
- **`kube`** — `kubectl --context <cluster.context> get nodes` → `ready/total`
  and per-node `Ready`/`NotReady`, feeding both the `cluster{}` object and each
  `nodes[]` entry's `state`.

`route` and `identity.github` probes are unchanged.

### C. Cache schema — `~/.cache/claw/homelab.json` (additions)

```json
{
  "ts": "2026-06-29T18:22:04Z",
  "fleet": "HR-TRUST",
  "cluster": { "context": "k3s-ms01", "ready": 3, "total": 3 },
  "nodes": [
    { "id": "ms-01",  "ip": "192.168.1.109", "role": "control-plane", "state": "up" },
    { "id": "r630",   "ip": "192.168.1.102", "role": "worker", "state": "up" },
    { "id": "bd790i", "ip": "192.168.1.104", "role": "worker", "state": "up" },
    { "id": "pihole", "ip": "192.168.1.101", "role": "dns", "state": "up" }
  ],
  "services": [
    { "id": "gitea", "group": "apps", "glyph": "git", "state": "up", "detail": "git.lab.local" },
    { "id": "harbor", "group": "apps", "glyph": "harbor", "state": "planned", "detail": "not deployed" }
  ],
  "route": { "via": "direct", "path": "mbp-m4 → direct → bd790i", "exit_node": null },
  "identity": { "github": { "user": "hankthebldr", "state": "up" } }
}
```

`state ∈ {up, degraded, down, planned}`. `ts` drives the age/staleness suffix.
**Stale threshold** unchanged: `5 × poll interval` (≈5 min at 60s cadence).

### D. Shared renderer — `scripts/utils/homelab-board.sh` (NEW; the "shared block")

One theme-aware reader. Sources `scripts/utils/theme.sh` for `CLAW_RGB_*`
(GitHub-dark fallback) exactly like `ff-readout.sh`, so it retracks `claw theme`.
Reads `homelab.json` only — **zero network**. Carries a service→glyph map that
matches `gen-fastfetch.py`'s `I` dict (Nerd Font Font Awesome / Devicon
codepoints), reusing existing brand glyphs (`git`, `k8s` ⎈, `docker`, `ollama`,
`vpn`) and adding brand glyphs for `n8n`, `portainer`, `enclave`, `grafana`,
`harbor`, `pihole`. Dot color encodes state: `up→green ●`, `degraded→amber ●`,
`down→red ●`, `planned→muted ○`.

Output — grouped, dot-prefixed board (illustrative):

```
 HR-TRUST ───────────────────────────  updated 14s ago
   Nodes     ● ms-01 cp   ● r630   ● bd790i      Cluster  ⎈ k3s-ms01 3/3 Ready
   DNS       ● pi-hole .101  *.lab.local
   Apps      ● gitea   ● n8n   ● portainer   ● enclave   ● grafana   ○ harbor (planned)
   Infra     ● tailscale   ● docker 7ctr   ● ollama 3mdl
   Route     mbp-m4 → direct → bd790i
```

CLI contract: `homelab-board.sh [all|nodes|dns|apps|infra|route]`. `all` prints
the whole board; a section arg prints one line/group — letting each `.jsonc`
place groups as individual `command` modules (mirroring how `config-local.jsonc`
already calls `ff-readout.sh l1..l5`). Width auto-aligns. Guards:
- **Stale-but-present** cache → render dimmed with `stale Xm ago`.
- **Absent** cache → print nothing (graceful skip; fastfetch drops the module).
- **Malformed** cache → guarded `jq`, skip, never break login.
- Non-interactive / piped / `SSH_CONNECTION` shell → emit nothing (inherit TUI
  safety guards), so it never leaks into `scp`/`rsync` sessions.

### E. Surfaces (three; DRY consolidation)

1. **`config-local.jsonc`** — add a `── HR-TRUST Lab ──` separator followed by
   `command` rows calling `homelab-board.sh <section>`. The existing
   `ff-readout.sh l1..l5` system rows stay; the lab board appends beneath them.
2. **`config-homelab.jsonc`** — its current hand-rolled inline `jq` rows
   (Tailscale/Docker/K3s/Ollama/Route/GitHub/Machines) **collapse** to
   `homelab-board.sh` calls. This removes the duplicated jq-in-jsonc and makes
   the renderer the single source of board layout.
3. **`hstatus()`** (homelab profile shell fn) — when the cache is fresh, becomes
   `homelab-board.sh all`; falls back to the existing live `_hl_status_*` probes
   only when the cache is stale/absent. Completes the theme-token migration off
   raw `\e[32m` ANSI started in the 2026-06-27 design.

(The `welcome-tui.zsh` `_claw_homelab_block()` and `claw-dashboard.py
homelab_lines()` from the prior design are unchanged here; they may later call
`homelab-board.sh` too, but that is out of scope for this iteration.)

### F. README — focused Homelab Fleet section

Add one section to the dotfiles root `README.md` (rest untouched):
- The `fleet.yml` inventory model (nodes / services / groups / glyphs).
- The poller → cache → render seam (one diagram), and **zero-network-at-render**.
- The live service list and `*.lab.local` / Pi-hole DNS note.
- `claw homelab poll|status` usage and where the board appears (`local` +
  `homelab` profiles, `hstatus`).

## Iconography (matches the cloud-profile idiom)

Service glyphs extend `gen-fastfetch.py`'s `I` dict philosophy — Nerd Font
codepoints, stable across Nerd Font builds, colored by state via the dot (not the
glyph). Reused: `git`, `k8s` (⎈), `docker`, `ollama`, `vpn` (tailscale). New
brand glyphs added for `n8n`, `portainer`, `enclave`, `grafana`, `harbor`,
`pihole`. The exact codepoints are finalized during implementation against the
installed JetBrainsMono Nerd Font; the map lives in `homelab-board.sh` (one
place), not scattered across `.jsonc` files.

## Error handling & safety

- **No network at render** — every surface reads the file; only the backgrounded
  poller touches the network.
- **Unreachable host / cluster** → that node/service `down`, no per-probe hang
  (timeout-guarded), board still renders the rest.
- **Atomic + single-flight** writes unchanged (`mktemp` + `mv -f`).
- **Theme** — all rows consume `CLAW_RGB_*` with refined-dark fallback; no
  hardcoded ANSI in the new renderer.

## Testing

- **Renderer:** check in `test/fixtures/homelab.{up,mixed,stale,empty}.json`;
  render `homelab-board.sh all` against each and assert: up→green ●, degraded→
  amber ●, down→red ●, planned→muted ○, stale→`stale Xm ago` suffix, absent→no
  output. Snapshot the `all` frame to confirm group alignment holds.
- **Producer:** unit-test `probe_homelab` against a stub fleet (one http 404, one
  502 degraded, pihole dig empty, one node NotReady) → assert JSON shape, `state`
  values, `cluster.ready/total`, atomic write, `ts` present. 0-node inventory →
  empty arrays, no error.
- **Safety:** piped / `SSH_CONNECTION` shell → renderer emits nothing.
- **Theme:** `claw theme set matrix` then render → dot colors track palette
  (proves no hardcoded ANSI).

## Build order

1. `fleet.yml` rewrite + `fleet.yml.example` + verify `yq` loads it.
2. `probe_homelab()` new kinds (`http`-via-Host, `dns`, `kube` cluster/nodes) +
   cache schema additions + fixtures. (Foundation.)
3. `homelab-board.sh` renderer + glyph map + section CLI. (Primary surface.)
4. Wire `config-local.jsonc` (new lab section) + `config-homelab.jsonc` (collapse
   inline jq to the renderer).
5. `hstatus()` cache-first via `homelab-board.sh all`.
6. README Homelab Fleet section.

## Out of scope (YAGNI)

- Uptime / history graphing — point-in-time snapshot only.
- Start/stop/remote-control actions — read-only status.
- Service auto-discovery — inventory stays declarative.
- Wiring the rust `claw-tui`, `welcome-tui` block, and `claw-dashboard.py` to the
  new renderer — they read the same cache, so portable later; follow-up.
- Harbor deployment itself — tracked separately; the board only declares it.
