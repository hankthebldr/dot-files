# HR-TRUST Fleet Availability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface live HR-TRUST homelab availability (machines + services, with access-level context and the Tailscale traffic route) at login, in the profile picker, in the fastfetch homelab dashboard, and in `hstatus` — all reading one background-refreshed cache, in the existing `icon → context → status` idiom.

**Architecture:** One producer (`probe_homelab()` added to `scripts/utils/situation.sh`) writes `~/.cache/claw/homelab.json` atomically; the existing 60s `situation tick` is extended to refresh it (free scheduling on Linux; launchd + login-kick on macOS). Four read-only surfaces render the cache, each in its surface's native status convention. The JSON cache is the single contract between producer and readers — no reader ever touches the network.

**Tech Stack:** Bash (`situation.sh`, `set -u`, jq-guarded), Python 3 (`claw-dashboard.py`), zsh (`welcome-tui.zsh`, homelab profile), fastfetch JSONC, yq v4 (mikefarah) for inventory, systemd `--user` timer (Linux) / launchd (macOS). Tests: **bats** + `zsh -n` + `py_compile` + `json.load`.

## Global Constraints

- **Theme:** never hardcode hex/ANSI in a new surface. Shell consumes `CLAW_RGB_*` (decimal `r;g;b`) via 24-bit SGR `\033[38;2;<triplet>m` with refined-dark `:-` fallbacks; Python consumes the `C[...]`/`G[...]` dicts. Canonical fallbacks: GREEN `63;185;80`, RED `255;123;114`, AMBER `227;179;65`, MUTED `139;148;158`, BLUE `88;166;255`, PURPLE `188;140;255`, FG `201;209;217`, CYAN `57;197;255`.
- **Status dot convention:** `●` green = up, `●` red = down, `●` amber = degraded/stale. (Today `_hl_status_*` uses amber `○` for down with no red — this plan introduces the red-down state.)
- **No network at render.** Every reader reads a file only; only the backgrounded poller probes. Readers self-skip (emit nothing) when the cache is absent, and dim with `stale Xm ago` when older than the stale threshold = **5 × poll interval = 5 min** at the 60s cadence. (Exception: the fastfetch surface in Task 5 is staleness-agnostic by design — documented there — because its jq one-liners can't do age math.)
- **SSH-safety / no-stdout-at-login:** surfaces run at interactive shell start; inherit the `welcome-tui` guards (`[[ ! -o interactive ]] && return`, `[[ ! -t 0 ]] && return`, `[[ -n "$SSH_CONNECTION" && ! -t 1 ]] && return`). Never block the prompt.
- **Spine contracts:** one dispatcher (`bin/claw` → `cmd_*`; never a second `claw()`), one theme engine (`theme.sh`), one render path (`claw-dashboard.py`); superseded scripts go to `legacy/`. `homelab.json` is a new producer on the **existing** `situation.sh` spine — not a new script/timer.
- **`set -u` is active in `situation.sh`** (no `set -e`): every variable must be pre-initialized or `:-`/`:=` guarded before use.
- **`config-homelab.jsonc` is HAND-MAINTAINED** — `gen-fastfetch.py` never touches it. Edit directly; do **not** run the generator.
- **grep alias bleed:** any new `.zsh` helper piping to grep must use `command grep` (aliases map grep→rg, zsh expands aliases inside `$()`).
- **Stage commits by name** (explicit paths), never `git add -A`. One commit per task. Co-authorship trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

## Canonical cache schema — `~/.cache/claw/homelab.json`

Every task references this exact shape. `state ∈ {"up","down","degraded"}`.

```json
{
  "ts": "2026-06-27T18:22:04Z",
  "fleet": "HR-TRUST",
  "route": { "via": "direct", "path": "→ bd790i", "exit_node": null },
  "identity": { "github": { "user": "hankthebldr", "state": "up" } },
  "machines": [
    {
      "id": "bd790i", "state": "up", "addr": "100.x.y.z", "latency_ms": 12,
      "services": [
        { "id": "k3s",       "state": "up",   "detail": "k3s-bd790i · 1/1 Ready" },
        { "id": "docker",    "state": "up",   "detail": "7 containers" },
        { "id": "gitea",     "state": "up",   "detail": "http 200" },
        { "id": "portainer", "state": "up",   "detail": ":9443" },
        { "id": "ollama",    "state": "down", "detail": "unreachable" }
      ]
    }
  ]
}
```

## File structure

| File | Create/Modify | Responsibility |
|---|---|---|
| `config/homelab/fleet.yml` | Create | Declarative HR-TRUST inventory (machines × services × identity). Committed (single-user repo). |
| `config/homelab/fleet.yml.example` | Create | Documented template (mirrors `tunnels.yml.example`). |
| `scripts/utils/situation.sh` | Modify | Add `probe_homelab()` producer, `cmd_homelab_poll()` atomic writer, `homelab` dispatch arm, fold homelab write into `cmd_tick`. |
| `scripts/utils/homelab.sh` | Modify | Thin non-interactive `poll`/`status` arms delegating to situation.sh; keep interactive fzf launcher as default. |
| `scripts/utils/claw-dashboard.py` | Modify | Add `homelab_lines()` (reuses `G['host']` glyph); one-line wire into `ctx`. |
| `shell/welcome-tui.zsh` | Modify | Add `_claw_homelab_block()`; call at login + hardware-group picker; add launchd-free login kick. |
| `config/.config/fastfetch/config-homelab.jsonc` | Modify | Daemon rows read the cache; add `── HR-TRUST Fleet ───` section. |
| `shell/profiles/homelab/common.zsh` | Modify | `hstatus()` cache-first; theme-migrate header. |
| `shell/profiles/homelab/mac.zsh`, `linux.zsh` | Modify | Theme-migrate `_hl_status_*` (raw ANSI → `CLAW_RGB_*`, add red-down). |
| `config/launchd/com.openclaw.situation.plist` | Create | macOS 60s cadence (no systemd). |
| `tests/homelab.bats` | Create | bats coverage for the poller + cache schema + readers. |
| `tests/fixtures/homelab.{up,mixed,stale,empty}.json` | Create | Cache fixtures for reader tests. |

---

## Task 1: Fleet inventory file + example

**Files:**
- Create: `config/homelab/fleet.yml`
- Create: `config/homelab/fleet.yml.example`
- Test: `tests/homelab.bats`

**Interfaces:**
- Produces: a YAML inventory read with `yq -r` (mikefarah v4). Machines under `.machines[]` each with `.id`, `.host`, `.user`, `.ssh` (bool), `.services` (list of service-id strings). Service definitions under `.services.<id>` with `.kind ∈ {native,ssh,http,tcp,kube}` and kind-specific fields. Identity probes under `.identity.<id>`.
- The producer in Task 2 consumes exactly these paths.

- [ ] **Step 1: Write the failing test**

Add to `tests/homelab.bats` (create the file with this header + test):

```bash
#!/usr/bin/env bats
# HR-TRUST homelab fleet status — poller + cache schema + readers. Run: bats tests/
setup() {
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR"; mkdir -p "$HOME"
}

@test "fleet.yml: parses and lists bd790i with its services" {
  run yq -r '.machines[] | select(.id=="bd790i") | .services[]' \
    "$BATS_TEST_DIRNAME/../config/homelab/fleet.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3s"* ]]
  [[ "$output" == *"tailscale"* ]]
}

@test "fleet.yml.example: is valid yaml" {
  run yq -e '.' "$BATS_TEST_DIRNAME/../config/homelab/fleet.yml.example"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/homelab.bats`
Expected: FAIL — `config/homelab/fleet.yml` does not exist (`yq` errors / no `k3s` in output).

- [ ] **Step 3: Create the inventory and example**

`config/homelab/fleet.yml` (committed; HR-TRUST is Henry's lab, single-user repo):

```yaml
# HR-TRUST homelab fleet inventory — read by scripts/utils/situation.sh probe_homelab().
# Machine-local override: $XDG_CONFIG_HOME/claw/fleet.yml (untracked) wins if present.
# Adding a box or service is data here — no code change.
fleet:
  name: HR-TRUST
  # poll_seconds is advisory; actual cadence is the situation timer (60s).
  poll_seconds: 60

machines:
  - id: bd790i
    host: bd790i            # tailscale MagicDNS name or IP; env BD790I_HOST overrides
    user: henry
    ssh: true               # allow deep checks (docker/kubectl/ollama over ssh)
    services: [tailscale, k3s, docker, gitea, portainer, ollama]

services:
  tailscale: { kind: native }                                   # BackendState on this box / via ssh
  k3s:       { kind: kube,  context: k3s-bd790i }               # node Ready count
  docker:    { kind: ssh,   cmd: "docker ps -q | wc -l" }       # container count
  gitea:     { kind: http,  url: "http://bd790i:3000", health: "/api/healthz" }
  portainer: { kind: tcp,   host: "bd790i", port: 9443 }
  ollama:    { kind: http,  url: "http://bd790i:11434", health: "/api/tags" }

identity:
  github: { kind: gh }       # gh auth status → login name (access-level context row)
```

`config/homelab/fleet.yml.example` — identical content but with the header line:

```yaml
# EXAMPLE fleet inventory. Copy to config/homelab/fleet.yml (committed) or
# $XDG_CONFIG_HOME/claw/fleet.yml (machine-local, untracked) and edit.
# Service kinds: native | ssh | http | tcp | kube. See docs/superpowers/specs/2026-06-27-homelab-fleet-status-design.md
fleet:
  name: MY-LAB
  poll_seconds: 60
machines:
  - id: box1
    host: box1.tailnet.ts.net
    user: me
    ssh: true
    services: [tailscale, docker]
services:
  tailscale: { kind: native }
  docker:    { kind: ssh, cmd: "docker ps -q | wc -l" }
identity:
  github: { kind: gh }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/homelab.bats`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add config/homelab/fleet.yml config/homelab/fleet.yml.example tests/homelab.bats
git commit -m "feat(homelab): declarative HR-TRUST fleet inventory" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `probe_homelab()` producer + cache + dispatch + tick integration

**Files:**
- Modify: `scripts/utils/situation.sh` (add after `probe_json()` ends ~L131; new path var ~L37; dispatch arm ~L319; tick fold ~L139)
- Test: `tests/homelab.bats`

**Interfaces:**
- Consumes: `config/homelab/fleet.yml` (Task 1), env `HOMELAB_HOST`/`BD790I_HOST`, helpers `have()`/`gf()`, path var `CACHE_DIR`.
- Produces: `~/.cache/claw/homelab.json` matching the canonical schema. New function names: `probe_homelab()`, `cmd_homelab_poll()`. New path var `HOMELAB_SNAP="$CACHE_DIR/homelab.json"`. New subcommand `situation homelab`. `cmd_tick()` now also writes `homelab.json`.

- [ ] **Step 1: Write the failing test**

Add to `tests/homelab.bats`:

```bash
@test "situation homelab: writes a schema-valid homelab.json" {
  command -v yq >/dev/null || skip "yq required to parse fleet.yml"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  run bash "$BATS_TEST_DIRNAME/../scripts/utils/situation.sh" homelab
  [ "$status" -eq 0 ]
  run jq -e '.ts and .fleet and (.machines|type=="array") and (.machines[0].id=="bd790i")' \
    "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$status" -eq 0 ]
  # service id is passed through verbatim from fleet.yml, which names it "k3s"
  run jq -e '.machines[0].services | map(.id) | index("k3s")' \
    "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$status" -eq 0 ]
}

@test "situation homelab: every service has a state in {up,down,degraded}" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  bash "$BATS_TEST_DIRNAME/../scripts/utils/situation.sh" homelab
  run jq -e '[.machines[].services[].state] | all(. as $s | ["up","down","degraded"]|index($s))' \
    "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/homelab.bats -f "situation homelab"`
Expected: FAIL — `situation homelab` falls through to the `usage:` error arm (`exit 1`); no `homelab.json` written.

- [ ] **Step 3: Add the `HOMELAB_SNAP` path var**

In `scripts/utils/situation.sh`, insert **after the `DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"` line (~L37)** — **not** after `ALERTS` (~L35). `HOMELAB_FLEET` references `$DOTFILES`, and `set -u` aborts the whole script ("DOTFILES: unbound variable") if it expands before `DOTFILES` is assigned. `CACHE_DIR`/`CONFIG_DIR` (L31-32) are already defined by L37, so all three lines resolve:

```bash
HOMELAB_SNAP="$CACHE_DIR/homelab.json"
HOMELAB_FLEET="$DOTFILES/config/homelab/fleet.yml"
[ -r "$CONFIG_DIR/fleet.yml" ] && HOMELAB_FLEET="$CONFIG_DIR/fleet.yml"   # machine-local override wins
```

- [ ] **Step 4: Implement `probe_homelab()` and `cmd_homelab_poll()`**

Insert immediately **after** `probe_json()` closes (the `}` at L131) and **before** `cmd_probe()` (L133):

```bash
# --- HR-TRUST fleet probe -------------------------------------------------
# Reads config/homelab/fleet.yml, probes each machine's reachability + its
# declared services, plus access-level identity + the tailscale traffic route.
# Emits the canonical homelab.json by string accumulation (NO jq for emission,
# matching probe_json); jq is used only (guarded) to PARSE tailscale/gh output.
# Every external call is timeout-bounded so a tick never hangs.

_hl_json_str() {                      # minimal JSON string escaper (quotes + backslash)
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Probe one service on one (already-reachable) machine. Echoes:  <state>\t<detail>
_hl_probe_service() {
    local host="$1" user="$2" ssh_ok="$3" svc="$4"
    local kind url health port shost cmd ctx state detail
    kind="$(yq -r ".services.${svc}.kind // \"native\"" "$HOMELAB_FLEET" 2>/dev/null)"
    state="down"; detail="unreachable"
    case "$kind" in
        http)
            url="$(yq -r ".services.${svc}.url // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            health="$(yq -r ".services.${svc}.health // \"/\"" "$HOMELAB_FLEET" 2>/dev/null)"
            if [ -n "$url" ] && curl -fsS --max-time 2 "${url}${health}" >/dev/null 2>&1; then
                state="up"; detail="http 200"
            fi ;;
        tcp)
            shost="$(yq -r ".services.${svc}.host // \"$host\"" "$HOMELAB_FLEET" 2>/dev/null)"
            port="$(yq -r ".services.${svc}.port // 0" "$HOMELAB_FLEET" 2>/dev/null)"
            if [ "$port" != "0" ] && timeout 2 bash -c "exec 3<>/dev/tcp/${shost}/${port}" 2>/dev/null; then
                state="up"; detail=":${port}"
            fi ;;
        kube)
            ctx="$(yq -r ".services.${svc}.context // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            if [ "$ssh_ok" = "true" ]; then
                local nodes; nodes="$(timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 \
                    "${user}@${host}" "kubectl get nodes --no-headers 2>/dev/null" 2>/dev/null)"
                if [ -n "$nodes" ]; then
                    local tot rdy; tot="$(printf '%s\n' "$nodes" | grep -c .)"
                    rdy="$(printf '%s\n' "$nodes" | awk '$2=="Ready"{c++} END{print c+0}')"
                    [ "$rdy" -gt 0 ] 2>/dev/null && state="up"
                    detail="${ctx:+$ctx · }${rdy}/${tot} Ready"
                fi
            fi ;;
        ssh)
            cmd="$(yq -r ".services.${svc}.cmd // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            if [ "$ssh_ok" = "true" ] && [ -n "$cmd" ]; then
                local out; out="$(timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 \
                    "${user}@${host}" "$cmd" 2>/dev/null | tr -d ' ')"
                if [ -n "$out" ]; then state="up"; detail="${out} containers"; fi
            fi ;;
        native|*)
            # tailscale BackendState — local if this box, else over ssh
            local bs
            if [ "$ssh_ok" = "true" ]; then
                bs="$(timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 "${user}@${host}" \
                    "tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null" 2>/dev/null)"
            elif have tailscale; then
                bs="$(timeout 3 tailscale status --json 2>/dev/null | { have jq && jq -r '.BackendState' 2>/dev/null; })"
            fi
            if [ "${bs:-}" = "Running" ]; then state="up"; detail="running"; fi ;;
    esac
    printf '%s\t%s' "$state" "$detail"
}

probe_homelab() {
    local ts fleet_name route_via route_path gh_user gh_state
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fleet_name="HR-TRUST"; route_via="unknown"; route_path=""; gh_user=""; gh_state="down"
    : "${USER:=$(id -un)}"          # set -u guard: USER feeds the per-machine default

    # Need yq + a fleet file, else emit an empty-but-valid snapshot.
    if ! have yq || [ ! -r "$HOMELAB_FLEET" ]; then
        cat <<EOF
{ "ts": "$ts", "fleet": "$fleet_name", "route": {"via":"unknown","path":"","exit_node":null},
  "identity": {}, "machines": [] }
EOF
        return 0
    fi
    fleet_name="$(yq -r '.fleet.name // "HR-TRUST"' "$HOMELAB_FLEET" 2>/dev/null)"

    # Access-level identity: github login via gh
    if have gh; then
        gh_user="$(timeout 4 gh api user --jq .login 2>/dev/null)"
        [ -n "$gh_user" ] && gh_state="up"
    fi

    # Tailscale status JSON, fetched ONCE — drives both the route and per-machine
    # reachability. (Uses `tailscale status --json`, the same proven invocation as
    # probe_json; deliberately NOT `tailscale ping`, whose count flag varies by
    # build. `startswith($h+".")` matches the MagicDNS name without regex metachar
    # surprises.)
    local tj=""; have tailscale && tj="$(timeout 3 tailscale status --json 2>/dev/null)"

    # Traffic route to the first machine: CurAddr present → direct; else Relay = DERP hop.
    local first_host; first_host="$(yq -r '.machines[0].host // ""' "$HOMELAB_FLEET" 2>/dev/null)"
    if [ -n "$tj" ] && have jq && [ -n "$first_host" ]; then
        local cur relay
        cur="$(printf '%s' "$tj" | jq -r --arg h "$first_host" \
            '[(.Peer // {})[] | select(.DNSName|startswith($h+"."))][0] // {} | .CurAddr // ""' 2>/dev/null)"
        relay="$(printf '%s' "$tj" | jq -r --arg h "$first_host" \
            '[(.Peer // {})[] | select(.DNSName|startswith($h+"."))][0] // {} | .Relay // ""' 2>/dev/null)"
        if [ -n "$cur" ]; then route_via="direct"; route_path="→ ${first_host}"
        elif [ -n "$relay" ]; then route_via="derp"; route_path="→ DERP(${relay}) → ${first_host}"
        else route_via="unknown"; route_path="→ ${first_host}"; fi
    fi

    # Machines × services
    local machines_json="" mi=0 mcount
    mcount="$(yq -r '.machines | length' "$HOMELAB_FLEET" 2>/dev/null)"; : "${mcount:=0}"
    while [ "$mi" -lt "$mcount" ]; do
        local id host user ssh_ok mstate addr latency
        id="$(yq -r ".machines[$mi].id // \"node$mi\"" "$HOMELAB_FLEET" 2>/dev/null)"
        host="$(yq -r ".machines[$mi].host // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
        user="$(yq -r ".machines[$mi].user // \"$USER\"" "$HOMELAB_FLEET" 2>/dev/null)"
        ssh_ok="$(yq -r ".machines[$mi].ssh // false" "$HOMELAB_FLEET" 2>/dev/null)"
        mstate="down"; addr=""; latency="null"

        # reachability from the shared tailscale status JSON: peer Online + its IP.
        # latency stays null (status doesn't measure RTT; no render needs it).
        if [ -n "$tj" ] && have jq && [ -n "$host" ]; then
            local online
            online="$(printf '%s' "$tj" | jq -r --arg h "$host" \
                '[(.Peer // {})[] | select(.DNSName|startswith($h+"."))][0] // {} | .Online // false' 2>/dev/null)"
            addr="$(printf '%s' "$tj" | jq -r --arg h "$host" \
                '[(.Peer // {})[] | select(.DNSName|startswith($h+"."))][0] // {} | (.TailscaleIPs // [""])[0] // ""' 2>/dev/null)"
            [ "$online" = "true" ] && mstate="up"
        fi
        : "${addr:=}"; : "${latency:=null}"

        # services for this machine (only probe if reachable)
        local svcs_json="" si=0 scount svc
        scount="$(yq -r ".machines[$mi].services | length" "$HOMELAB_FLEET" 2>/dev/null)"; : "${scount:=0}"
        while [ "$si" -lt "$scount" ]; do
            svc="$(yq -r ".machines[$mi].services[$si]" "$HOMELAB_FLEET" 2>/dev/null)"
            local sstate sdetail line
            if [ "$mstate" = "up" ]; then
                line="$(_hl_probe_service "$host" "$user" "$ssh_ok" "$svc")"
                sstate="${line%%	*}"; sdetail="${line#*	}"
            else
                sstate="down"; sdetail="host down"
            fi
            [ -n "$svcs_json" ] && svcs_json="${svcs_json},"
            svcs_json="${svcs_json}{\"id\":\"$(_hl_json_str "$svc")\",\"state\":\"${sstate}\",\"detail\":\"$(_hl_json_str "$sdetail")\"}"
            si=$((si+1))
        done

        [ -n "$machines_json" ] && machines_json="${machines_json},"
        machines_json="${machines_json}{\"id\":\"$(_hl_json_str "$id")\",\"state\":\"${mstate}\",\"addr\":\"$(_hl_json_str "$addr")\",\"latency_ms\":${latency:-null},\"services\":[${svcs_json}]}"
        mi=$((mi+1))
    done

    cat <<EOF
{
  "ts": "$ts",
  "fleet": "$(_hl_json_str "$fleet_name")",
  "route": { "via": "$(_hl_json_str "$route_via")", "path": "$(_hl_json_str "$route_path")", "exit_node": null },
  "identity": { "github": { "user": "$(_hl_json_str "$gh_user")", "state": "$gh_state" } },
  "machines": [${machines_json}]
}
EOF
}

cmd_homelab_poll() {
    local tmp; tmp="$(mktemp "${CACHE_DIR}/.hl.XXXXXX")" || return 1
    if probe_homelab >"$tmp" 2>/dev/null; then mv -f "$tmp" "$HOMELAB_SNAP"; else rm -f "$tmp"; return 1; fi
    return 0
}
```

- [ ] **Step 5: Fold the homelab write into `cmd_tick` and add the dispatch arm**

In `cmd_tick()`, after the `cmd_probe || return 1` line (L141), add:

```bash
    cmd_homelab_poll || true     # keep homelab.json fresh on the same timer (best-effort)
```

In the top-level dispatch `case` (L319-331), add an arm before the `*)` default:

```bash
    homelab|fleet)    cmd_homelab_poll ;;
```

And update the usage string on the `*)` line to include `homelab`:

```bash
    *) echo "usage: situation {probe|tick|show [--json]|alerts|homelab|install|uninstall}"; exit 1 ;;
```

Also add `homelab` to the header subcommand list (the comment block ~L15-24):

```bash
#   homelab          probe the HR-TRUST fleet -> ~/.cache/claw/homelab.json (atomic)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bats tests/homelab.bats -f "situation homelab"`
Expected: PASS (2 tests). On a machine without `yq`/`tailscale` the producer still emits a schema-valid snapshot (empty `machines` if yq missing) — assert shape, not liveness.

Run: `bash -n scripts/utils/situation.sh` → Expected: no output (syntax OK).
Run: `shellcheck -S error -e SC1090,SC1091 scripts/utils/situation.sh` → Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/utils/situation.sh tests/homelab.bats
git commit -m "feat(homelab): probe_homelab() fleet producer + homelab.json cache" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Dashboard `homelab_lines()` (login screen-1)

**Files:**
- Modify: `scripts/utils/claw-dashboard.py` (add `homelab="..."` to `G` ~L81-85; new function after `infra_lines()` ~L279; one-line wire at L296)
- Create: `tests/fixtures/homelab.{up,mixed,empty}.json`
- Test: `tests/homelab.bats`

**Interfaces:**
- Consumes: `~/.cache/claw/homelab.json` (Task 2 schema); helpers `col`, `_short`, `C[...]`, `G[...]`.
- Produces: `homelab_lines() -> list[str]` (0..N rows). Wired into `ctx` in `main()`.

- [ ] **Step 1: Write the fixtures**

`tests/fixtures/homelab.up.json`:

```json
{ "ts": "2099-01-01T00:00:00Z", "fleet": "HR-TRUST",
  "route": { "via": "direct", "path": "→ bd790i", "exit_node": null },
  "identity": { "github": { "user": "hankthebldr", "state": "up" } },
  "machines": [ { "id": "bd790i", "state": "up", "addr": "100.64.0.5", "latency_ms": 12,
    "services": [ {"id":"k3s","state":"up","detail":"1/1 Ready"}, {"id":"ollama","state":"up","detail":"3 models"} ] } ] }
```

`tests/fixtures/homelab.mixed.json` (note `ollama` down):

```json
{ "ts": "2099-01-01T00:00:00Z", "fleet": "HR-TRUST",
  "route": { "via": "derp", "path": "→ DERP(fra) → bd790i", "exit_node": null },
  "identity": { "github": { "user": "hankthebldr", "state": "up" } },
  "machines": [ { "id": "bd790i", "state": "up", "addr": "100.64.0.5", "latency_ms": 30,
    "services": [ {"id":"k3s","state":"up","detail":"1/1 Ready"}, {"id":"ollama","state":"down","detail":"unreachable"} ] } ] }
```

`tests/fixtures/homelab.empty.json`:

```json
{ "ts": "2099-01-01T00:00:00Z", "fleet": "HR-TRUST", "route": {"via":"unknown","path":"","exit_node":null}, "identity": {}, "machines": [] }
```

- [ ] **Step 2: Write the failing test**

Add to `tests/homelab.bats`:

```bash
@test "dashboard homelab_lines: renders host + service dots from cache" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/homelab.up.json" "$XDG_CACHE_HOME/claw/homelab.json"
  run env NO_COLOR=1 python3 -c "import sys; sys.argv=['d']; \
    import importlib.util as u; s=u.spec_from_file_location('d','$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py'); \
    m=u.module_from_spec(s); s.loader.exec_module(m); print('\n'.join(m.homelab_lines()))"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bd790i"* ]]
  [[ "$output" == *"k3s"* ]]
}

@test "dashboard homelab_lines: empty list when cache absent" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/none"
  run env NO_COLOR=1 python3 -c "import importlib.util as u; \
    s=u.spec_from_file_location('d','$BATS_TEST_DIRNAME/../scripts/utils/claw-dashboard.py'); \
    m=u.module_from_spec(s); s.loader.exec_module(m); print('LINES=%d'%len(m.homelab_lines()))"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LINES=0"* ]]
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bats tests/homelab.bats -f "dashboard homelab_lines"`
Expected: FAIL — `AttributeError: module has no attribute 'homelab_lines'`.

- [ ] **Step 4: Add the function (no `G` dict edit)**

Reuse the existing `G['host']` glyph for the machine row — do **not** edit the `G`
dict (a hand-retyped dict literal risks an empty/garbled glyph and an accidental
mutation of the `tailscale` value). `homelab_lines()` below references `G['host']`.

Insert after `infra_lines()` closes (after L279), before the `# ── Compose:` comment:

```python
def _homelab_cache():
    """Load the homelab fleet cache, or None. Pure file read; never raises."""
    try:
        cache = os.path.join(
            os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
            "claw", "homelab.json")
        with open(cache, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _age_suffix(ts):
    """' updated 23s ago' / ' stale 7m ago'; '' if unparseable. Stale > 5 min."""
    try:
        t = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=datetime.timezone.utc)
        secs = int((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds())
        secs = max(0, secs)
        human = f"{secs}s" if secs < 60 else f"{secs // 60}m"
        stale = secs > 300
        word = "stale" if stale else "updated"
        return (f" {word} {human} ago", stale)
    except Exception:
        return ("", False)


def homelab_lines():
    """Live HR-TRUST fleet rows read from ~/.cache/claw/homelab.json (no network).
    Returns [] when the cache is absent so the caller drops the block on machines
    that aren't homelab cockpits. Up=green ●, down=red ●, degraded/stale=amber ●."""
    data = _homelab_cache()
    if not data or not isinstance(data.get("machines"), list) or not data["machines"]:
        return []
    suffix, stale = _age_suffix(data.get("ts", ""))
    dot_up = col("●", C["amber"] if stale else C["green"])
    dot_down = col("●", C["red"])
    dot_deg = col("●", C["amber"])

    def dot(state):
        return dot_down if state == "down" else (dot_deg if state == "degraded" else dot_up)

    rows = []
    # access-level context line: github identity + tailscale route
    head = []
    gh = (data.get("identity") or {}).get("github") or {}
    if gh.get("user"):
        head.append(f"{col(G['git'], C['purple'])} {col(_short(gh['user'], 18), C['fg'])} {dot(gh.get('state'))}")
    route = data.get("route") or {}
    if route.get("path"):
        head.append(f"{col(G['tailscale'], C['green'])} {col(_short(route['path'], 28), C['fg'])}")
    if head:
        rows.append("   ".join(head))
    # one row per machine: host dot + nested service dots
    for m in data["machines"]:
        segs = [f"{col(G['host'], C['blue'])} {col(_short(m.get('id', '?'), 12), C['fg'])} {dot(m.get('state'))}"]
        for s in (m.get("services") or []):
            segs.append(f"{dot(s.get('state'))} {col(_short(s.get('id', '?'), 10), C['muted'])}")
        rows.append("  ".join(segs))
    if suffix:
        rows.append(col(suffix.strip(), C["muted"]))
    return rows
```

- [ ] **Step 5: Wire into `ctx`**

Change L296 from:

```python
    ctx = [l for l in context_lines() + infra_lines() if l]   # dev + infra rows
```

to:

```python
    ctx = [l for l in context_lines() + infra_lines() + homelab_lines() if l]   # dev + infra + homelab rows
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bats tests/homelab.bats -f "dashboard homelab_lines"` → Expected: PASS (2 tests).
Run: `python3 -m py_compile scripts/utils/claw-dashboard.py` → Expected: no output.
Run (smoke, real cache absent → unchanged dashboard): `DOTFILES_DIR="$PWD" python3 scripts/utils/claw-dashboard.py | head -5` → Expected: renders normally, no homelab rows.

- [ ] **Step 7: Commit**

```bash
git add scripts/utils/claw-dashboard.py tests/homelab.bats tests/fixtures/homelab.up.json tests/fixtures/homelab.mixed.json tests/fixtures/homelab.empty.json
git commit -m "feat(homelab): dashboard homelab_lines() reads fleet cache" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Welcome-TUI `_claw_homelab_block()` (hardware-group picker)

**Files:**
- Modify: `shell/welcome-tui.zsh` (define helper after `_claw_profile_readout` ~L569; call in the picker after L214 gated on `tok==hardware`). **Login screen-1 is owned by the dashboard's `homelab_lines()` (Task 3)** — this block is picker-only, to avoid rendering the fleet twice on login.
- Test: `tests/homelab.bats`

**Interfaces:**
- Consumes: `~/.cache/claw/homelab.json` (Task 2 schema); `CLAW_RGB_*` env (with `:-` fallbacks); `jq` (guarded).
- Produces: `_claw_homelab_block()` — prints a compact 1–2 line fleet summary, or nothing if cache absent. Top-level (re-derives its own colors) so it's testable in isolation.

- [ ] **Step 1: Write the failing test**

Add to `tests/homelab.bats`:

```bash
@test "welcome-tui _claw_homelab_block: prints fleet summary from cache" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/homelab.up.json" "$XDG_CACHE_HOME/claw/homelab.json"
  run zsh -c "source '$BATS_TEST_DIRNAME/../shell/welcome-tui.zsh'; _claw_homelab_block"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HR-TRUST"* ]]
  [[ "$output" == *"bd790i"* ]]
  [[ "$output" == *"2/2 up"* ]]   # proves the jq/read field-split works, not just a substring
}

@test "welcome-tui _claw_homelab_block: silent when cache absent" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/none"
  run zsh -c "source '$BATS_TEST_DIRNAME/../shell/welcome-tui.zsh'; _claw_homelab_block"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/homelab.bats -f "_claw_homelab_block"`
Expected: FAIL — `_claw_homelab_block: command not found`.

- [ ] **Step 3: Define the helper (top-level, theme-compliant)**

Append at the **end** of `shell/welcome-tui.zsh` (after `_claw_profile_readout` closes at L569), following the `CLAW_RGB_*`-with-fallback pattern (NOT the hardcoded-hex one):

```zsh
# _claw_homelab_block — compact HR-TRUST fleet summary for the login footer and
# the hardware-group picker. Reads ~/.cache/claw/homelab.json ONLY (the
# situation poller writes it); never probes the network. Silent if absent.
_claw_homelab_block() {
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json"
    [[ -r "$cache" ]] || return 0
    command -v jq &> /dev/null || return 0

    # Theme tokens (CLAW_RGB_* with refined-dark fallbacks — spine contract #2).
    local c_reset=$'\e[0m'
    local c_green=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    local c_red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    local c_amber=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    local c_dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local c_white=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
    local c_bold=$'\e[1m'

    # Fleet name + per-machine up/total service rollup + route + age.
    local fleet route ts up_total summary
    fleet=$(jq -r '.fleet // "fleet"' "$cache" 2>/dev/null)
    route=$(jq -r '.route.path // ""' "$cache" 2>/dev/null)
    ts=$(jq -r '.ts // ""' "$cache" 2>/dev/null)
    [[ -z "$fleet" || "$fleet" == "null" ]] && return 0

    # Build "host ●U/T" segments, dot colored by whether all services are up.
    summary=$(jq -r '
      .machines[]? |
      (.services | length) as $t |
      ([.services[]? | select(.state=="up")] | length) as $u |
      "\(.id)\u0001\(.state)\u0001\($u)\u0001\($t)"' "$cache" 2>/dev/null)

    # Staleness from ts (epoch diff); >300s → amber "stale".
    local age_label="" now then diff
    if [[ -n "$ts" && "$ts" != "null" ]]; then
        now=$(date -u +%s 2>/dev/null)
        then=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null \
               || date -u -d "$ts" +%s 2>/dev/null)
        if [[ -n "$then" ]]; then
            diff=$(( now - then )); (( diff < 0 )) && diff=0
            if (( diff < 60 )); then age_label="${diff}s ago"; else age_label="$(( diff / 60 ))m ago"; fi
            (( diff > 300 )) && age_label="stale ${age_label}"
        fi
    fi

    printf "  ${c_white}${c_bold}📡 %s${c_reset}" "$fleet"
    [[ -n "$route" ]] && printf "  ${c_dim}%s${c_reset}" "$route"
    [[ -n "$age_label" ]] && printf "  ${c_dim}· %s${c_reset}" "$age_label"
    printf "\n"

    local id st u t dot
    while IFS=$'\001' read -r id st u t; do
        [[ -z "$id" ]] && continue
        if [[ "$st" != "up" ]]; then dot="${c_red}●${c_reset}"
        elif [[ "$u" == "$t" ]]; then dot="${c_green}●${c_reset}"
        else dot="${c_amber}●${c_reset}"; fi
        printf "    %s ${c_white}%s${c_reset} ${c_dim}%s/%s up${c_reset}" "$dot" "$id" "$u" "$t"
    done <<< "$summary"
    printf "\n"
}
```

- [ ] **Step 4: (login footer is owned by the dashboard — no call here)**

Do NOT call `_claw_homelab_block` at the login footer. The login screen-1 fleet
rows are rendered by `claw-dashboard.py homelab_lines()` (Task 3); adding the
zsh block there too would render the fleet twice. This block is **picker-only**
(Step 5). No edit to `_claw_tui_header()` in this task.

- [ ] **Step 5: Call it in the hardware-group picker**

After the group-title `printf` at L214 and before `local sel2 itok` at L215, insert the gated call:

```zsh
            printf "\n  ${c_purple}${c_bold}Open Claw${c_reset} ${c_dim}▸${c_reset} ${c_white}%s${c_reset}\n\n" "${l2_title[$tok]}"
            [[ "$tok" == hardware ]] && _claw_homelab_block
            local sel2 itok
```

- [ ] **Step 6: Run tests + lint**

Run: `bats tests/homelab.bats -f "_claw_homelab_block"` → Expected: PASS (2 tests).
Run: `zsh -n shell/welcome-tui.zsh` → Expected: no output (syntax OK).

- [ ] **Step 7: Commit**

```bash
git add shell/welcome-tui.zsh tests/homelab.bats
git commit -m "feat(homelab): welcome-TUI fleet block at login + hardware picker" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: fastfetch `config-homelab.jsonc` — cache-backed rows + HR-TRUST Fleet section

**Files:**
- Modify: `config/.config/fastfetch/config-homelab.jsonc` (daemon rows → jq the cache; add fleet section before the closing rule at L34)
- Test: `tests/homelab.bats`

**Interfaces:**
- Consumes: `~/.cache/claw/homelab.json` (Task 2). fastfetch `command` modules `jq` the cache; color is self-emitted ANSI inside stdout (fastfetch can't colorize by exit code).
- Produces: a valid JSONC that `json.load` accepts (CI gate) and renders cache-backed rows.

- [ ] **Step 1: Write the failing test**

Add to `tests/homelab.bats`:

```bash
@test "config-homelab.jsonc: is valid json and references homelab.json cache" {
  run python3 -c "import json,sys; json.load(open(sys.argv[1]))" \
    "$BATS_TEST_DIRNAME/../config/.config/fastfetch/config-homelab.jsonc"
  [ "$status" -eq 0 ]
  run grep -c "homelab.json" "$BATS_TEST_DIRNAME/../config/.config/fastfetch/config-homelab.jsonc"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/homelab.bats -f "config-homelab.jsonc"`
Expected: FAIL — current file has zero `homelab.json` references (`grep -c` → 0, status 1).

- [ ] **Step 3: Replace the daemon rows and add the fleet section**

In `config/.config/fastfetch/config-homelab.jsonc`, replace the four `BD790i Daemons` command rows (L27-33) so each reads the cache instead of probing live, and add the `HR-TRUST Fleet` section before the closing rule (L34). The `modules` array becomes (from the `── BD790i Daemons ───` separator through the closing `colors`):

```jsonc
    { "type": "separator", "string": "── BD790i Daemons ───────" },
    { "type": "command", "key": "  Tailscale",
      "text": "jq -r '.machines[0].services[]|select(.id==\"tailscale\")|if .state==\"up\" then \"\\u001b[32m●\\u001b[0m \"+.detail else \"\\u001b[31m●\\u001b[0m \"+.detail end' \"${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json\" 2>/dev/null || echo 'no cache'" },
    { "type": "command", "key": "  Docker",
      "text": "jq -r '.machines[0].services[]|select(.id==\"docker\")|if .state==\"up\" then \"\\u001b[32m●\\u001b[0m \"+.detail else \"\\u001b[31m●\\u001b[0m \"+.detail end' \"${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json\" 2>/dev/null || echo 'no cache'" },
    { "type": "command", "key": "  K3s",
      "text": "jq -r '.machines[0].services[]|select(.id==\"k3s\" or .id==\"k8s\")|if .state==\"up\" then \"\\u001b[32m●\\u001b[0m \"+.detail else \"\\u001b[31m●\\u001b[0m \"+.detail end' \"${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json\" 2>/dev/null || echo 'no cache'" },
    { "type": "command", "key": "  Ollama",
      "text": "jq -r '.machines[0].services[]|select(.id==\"ollama\")|if .state==\"up\" then \"\\u001b[32m●\\u001b[0m \"+.detail else \"\\u001b[31m●\\u001b[0m \"+.detail end' \"${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json\" 2>/dev/null || echo 'no cache'" },
    { "type": "separator", "string": "── HR-TRUST Fleet ───────" },
    { "type": "command", "key": "  Route",
      "text": "jq -r '.route.path // \"n/a\"' \"${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json\" 2>/dev/null || echo 'no cache'" },
    { "type": "command", "key": "  GitHub",
      "text": "jq -r '.identity.github | if .state==\"up\" then \"\\u001b[32m●\\u001b[0m \"+.user else \"\\u001b[31m●\\u001b[0m offline\" end' \"${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json\" 2>/dev/null || echo 'no cache'" },
    { "type": "command", "key": "  Machines",
      "text": "jq -r '[.machines[]|if .state==\"up\" then \"\\u001b[32m●\\u001b[0m\"+.id else \"\\u001b[31m●\\u001b[0m\"+.id end]|join(\"  \")' \"${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json\" 2>/dev/null || echo 'no cache'" },
    { "type": "separator", "string": "─────────────────────────" },
    { "type": "colors", "paddingLeft": 2, "symbol": "circle" }
```

(The `\\u001b` escapes are JSON unicode for ESC; fastfetch passes the resulting bytes through, so the dot renders colored. JSON forbids literal double-quotes inside `text`, so the jq filters use `\"` — valid JSON string escaping — for the jq string literals.)

**Staleness exception (intentional):** unlike the dashboard / welcome-TUI / `hstatus` readers, this fastfetch surface is **staleness-agnostic** — it shows cache contents without an age check (jq one-liners can't cheaply do epoch-diff math and fastfetch can't colorize by age), and on a missing cache it prints a literal `no cache` row rather than self-skipping (fastfetch always renders its module list). This is the one reader that does not carry the stale signal; the Global Constraint's "dim when stale / self-skip when absent" rule is upheld by the other three surfaces. Acceptable because this dashboard only renders inside the `homelab` profile, where the poller is active.

- [ ] **Step 4: Run test + the CI JSON gate**

Run: `bats tests/homelab.bats -f "config-homelab.jsonc"` → Expected: PASS.
Run (the exact CI check): `python3 -c "import json,sys;json.load(open(sys.argv[1]))" config/.config/fastfetch/config-homelab.jsonc` → Expected: no output, exit 0.
Run (smoke, if a cache exists): `fastfetch -c config/.config/fastfetch/config-homelab.jsonc | grep -A2 "HR-TRUST"` → Expected: renders the fleet rows (or `no cache` lines if homelab.json absent — both acceptable).

- [ ] **Step 5: Commit**

```bash
git add config/.config/fastfetch/config-homelab.jsonc tests/homelab.bats
git commit -m "feat(homelab): fastfetch dashboard reads fleet cache + HR-TRUST section" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `hstatus` cache-first + theme-migrate `_hl_status_*`

**Files:**
- Modify: `shell/profiles/homelab/common.zsh` (`hstatus()` cache-first + header theme tokens)
- Modify: `shell/profiles/homelab/mac.zsh`, `shell/profiles/homelab/linux.zsh` (raw ANSI → `CLAW_RGB_*`, add red-down)
- Test: `tests/homelab.bats`

**Interfaces:**
- Consumes: `~/.cache/claw/homelab.json` (Task 2); `CLAW_RGB_*` env.
- Produces: `hstatus()` renders the cache when fresh (multi-machine), else falls back to live `_hl_status_*`. `_hl_status_*` now theme-token colored with a red-down state.

- [ ] **Step 1: Write the failing test**

Add to `tests/homelab.bats`:

```bash
@test "hstatus: renders cached fleet when homelab.json is fresh" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  # fresh ts = now, so cache-first path is taken
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sed "s/2099-01-01T00:00:00Z/$ts/" "$BATS_TEST_DIRNAME/fixtures/homelab.up.json" \
    > "$XDG_CACHE_HOME/claw/homelab.json"
  run zsh -c "source '$BATS_TEST_DIRNAME/../shell/profiles/homelab/common.zsh'; hstatus"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bd790i"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/homelab.bats -f "hstatus"`
Expected: FAIL — current `hstatus` ignores the cache and prints `(helper not loaded)` lines (no `bd790i`).

- [ ] **Step 3: Make `hstatus()` cache-first + migrate its header colors**

Replace `hstatus()` in `shell/profiles/homelab/common.zsh` (L21-28) with:

```zsh
hstatus() {
    local c_reset=$'\e[0m'
    local c_cyan=$'\e[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"$'m'
    local c_green=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    local c_red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    local c_amber=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    local c_dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local c_bold=$'\e[1m'

    # Cache-first: if the situation poller wrote a fresh homelab.json (<5min),
    # render the whole fleet from it (multi-machine). Else fall back to the live
    # single-host _hl_status_* probes.
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json"
    if [[ -r "$cache" ]] && command -v jq &> /dev/null; then
        local ts now then diff fresh=0
        ts=$(jq -r '.ts // ""' "$cache" 2>/dev/null)
        if [[ -n "$ts" && "$ts" != "null" ]]; then
            now=$(date -u +%s 2>/dev/null)
            then=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || date -u -d "$ts" +%s 2>/dev/null)
            [[ -n "$then" ]] && diff=$(( now - then )) && (( diff >= 0 && diff <= 300 )) && fresh=1
        fi
        if (( fresh )); then
            local fleet; fleet=$(jq -r '.fleet // "HR-TRUST"' "$cache" 2>/dev/null)
            printf "\n  ${c_cyan}▸${c_reset} ${c_bold}%s fleet${c_reset}  ${c_dim}(cached %ss ago)${c_reset}\n\n" "$fleet" "${diff:-0}"
            local id st u t svcid sst sdet dot
            jq -r '.machines[]? | "M\u0001\(.id)\u0001\(.state)", (.services[]? | "S\u0001\(.id)\u0001\(.state)\u0001\(.detail)")' "$cache" 2>/dev/null \
            | while IFS=$'\001' read -r kind a b c; do
                if [[ "$kind" == "M" ]]; then
                    [[ "$b" == "up" ]] && dot="${c_green}●${c_reset}" || dot="${c_red}●${c_reset}"
                    printf "  %s ${c_bold}%s${c_reset}\n" "$dot" "$a"
                else
                    case "$b" in up) dot="${c_green}●${c_reset}";; down) dot="${c_red}●${c_reset}";; *) dot="${c_amber}●${c_reset}";; esac
                    printf "      %s %-10s ${c_dim}%s${c_reset}\n" "$dot" "$a" "$c"
                fi
              done
            echo ""
            return 0
        fi
    fi

    # Live fallback (single host, on-demand probes).
    printf "\n  ${c_cyan}▸${c_reset} ${c_bold}BD790i homelab status${c_reset}  ${c_dim}(%s · live)${c_reset}\n\n" "$BD790I_HOST"
    if typeset -f _hl_status_tailscale &>/dev/null; then _hl_status_tailscale; else echo "  tailscale: (helper not loaded)"; fi
    if typeset -f _hl_status_docker    &>/dev/null; then _hl_status_docker;    else echo "  docker:    (helper not loaded)"; fi
    if typeset -f _hl_status_k3s       &>/dev/null; then _hl_status_k3s;       else echo "  k3s:       (helper not loaded)"; fi
    if typeset -f _hl_status_ollama    &>/dev/null; then _hl_status_ollama;    else echo "  ollama:    (helper not loaded)"; fi
    echo ""
}
```

- [ ] **Step 4: Theme-migrate the `_hl_status_*` helpers (mac + linux)**

In **both** `mac.zsh` and `linux.zsh`, add a shared color preamble at the top of each `_hl_status_*` body (or define once near the top of the file) and replace every `\e[32m` → green token, `\e[33m` → amber token, and use the red token for genuine down states. Define a helper at the top of each per-OS file:

```zsh
# Theme tokens for status dots (CLAW_RGB_* with refined-dark fallbacks).
_hl_c() {
    _HL_RESET=$'\e[0m'
    _HL_GREEN=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    _HL_RED=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    _HL_AMBER=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    _HL_DIM=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
}
```

Then rewrite each helper to call `_hl_c` and use the tokens. Replace **all eight** functions verbatim — up uses `${_HL_GREEN}●`, every down/inactive/not-installed/not-reachable state uses `${_HL_RED}●`, detail wrapped in `${_HL_DIM}`. The linux variants keep their `command -v` + `systemctl is-active` guards and the `tailscale ip` detail line; the mac variants keep their `_hl_ssh` remote-exec wrappers (note the `\$2` escape so awk's field expands remotely).

`mac.zsh` (cockpit / SSH-wrapped):

```zsh
_hl_status_tailscale() {
    _hl_c
    local out; out=$(_hl_ssh "tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null" 2>/dev/null)
    if [[ "$out" == "Running" ]]; then
        printf "  ${_HL_GREEN}●${_HL_RESET} tailscale  ${_HL_DIM}running${_HL_RESET}\n"
    else
        printf "  ${_HL_RED}●${_HL_RESET} tailscale  ${_HL_DIM}%s${_HL_RESET}\n" "${out:-unreachable}"
    fi
}
_hl_status_docker() {
    _hl_c
    local n; n=$(_hl_ssh "docker ps -q 2>/dev/null | wc -l" 2>/dev/null | tr -d ' ')
    if [[ -n "$n" && "$n" =~ ^[0-9]+$ ]]; then
        printf "  ${_HL_GREEN}●${_HL_RESET} docker     ${_HL_DIM}%s container(s)${_HL_RESET}\n" "$n"
    else
        printf "  ${_HL_RED}●${_HL_RESET} docker     ${_HL_DIM}unreachable${_HL_RESET}\n"
    fi
}
_hl_status_k3s() {
    _hl_c
    local ready; ready=$(_hl_ssh "kubectl get nodes --no-headers 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
    if [[ "$ready" == "Ready" ]]; then
        printf "  ${_HL_GREEN}●${_HL_RESET} k3s        ${_HL_DIM}node Ready${_HL_RESET}\n"
    else
        printf "  ${_HL_RED}●${_HL_RESET} k3s        ${_HL_DIM}%s${_HL_RESET}\n" "${ready:-unreachable}"
    fi
}
_hl_status_ollama() {
    _hl_c
    local n; n=$(_hl_ssh "ollama list 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null | tr -d ' ')
    if [[ -n "$n" && "$n" =~ ^[0-9]+$ ]]; then
        printf "  ${_HL_GREEN}●${_HL_RESET} ollama     ${_HL_DIM}%s model(s)${_HL_RESET}\n" "$n"
    else
        printf "  ${_HL_RED}●${_HL_RESET} ollama     ${_HL_DIM}unreachable${_HL_RESET}\n"
    fi
}
```

`linux.zsh` (native / local daemons):

```zsh
_hl_status_tailscale() {
    _hl_c
    if command -v tailscale &>/dev/null; then
        local state; state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null)
        if [[ "$state" == "Running" ]]; then
            local ip; ip=$(tailscale ip -4 2>/dev/null | head -1)
            printf "  ${_HL_GREEN}●${_HL_RESET} tailscale  ${_HL_DIM}running · %s${_HL_RESET}\n" "$ip"
        else
            printf "  ${_HL_RED}●${_HL_RESET} tailscale  ${_HL_DIM}%s${_HL_RESET}\n" "${state:-down}"
        fi
    else
        printf "  ${_HL_RED}●${_HL_RESET} tailscale  ${_HL_DIM}not installed${_HL_RESET}\n"
    fi
}
_hl_status_docker() {
    _hl_c
    if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
        local n; n=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
        printf "  ${_HL_GREEN}●${_HL_RESET} docker     ${_HL_DIM}%s container(s)${_HL_RESET}\n" "$n"
    else
        printf "  ${_HL_RED}●${_HL_RESET} docker     ${_HL_DIM}inactive${_HL_RESET}\n"
    fi
}
_hl_status_k3s() {
    _hl_c
    if command -v kubectl &>/dev/null && kubectl get nodes &>/dev/null; then
        local ready; ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}')
        printf "  ${_HL_GREEN}●${_HL_RESET} k3s        ${_HL_DIM}node %s${_HL_RESET}\n" "${ready:-?}"
    else
        printf "  ${_HL_RED}●${_HL_RESET} k3s        ${_HL_DIM}not reachable${_HL_RESET}\n"
    fi
}
_hl_status_ollama() {
    _hl_c
    if command -v ollama &>/dev/null && systemctl is-active ollama &>/dev/null; then
        local n; n=$(ollama list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        printf "  ${_HL_GREEN}●${_HL_RESET} ollama     ${_HL_DIM}%s model(s)${_HL_RESET}\n" "$n"
    else
        printf "  ${_HL_RED}●${_HL_RESET} ollama     ${_HL_DIM}inactive${_HL_RESET}\n"
    fi
}
```

- [ ] **Step 5: Run test + lint**

Run: `bats tests/homelab.bats -f "hstatus"` → Expected: PASS.
Run: `zsh -n shell/profiles/homelab/common.zsh shell/profiles/homelab/mac.zsh shell/profiles/homelab/linux.zsh` → Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add shell/profiles/homelab/common.zsh shell/profiles/homelab/mac.zsh shell/profiles/homelab/linux.zsh tests/homelab.bats
git commit -m "feat(homelab): hstatus cache-first + theme-migrate _hl_status_*" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: macOS scheduling (launchd plist) + login cache-warm kick + homelab.sh arm

**Files:**
- Create: `config/launchd/com.openclaw.situation.plist`
- Modify: `shell/welcome-tui.zsh` (add a self-backgrounded homelab-poll kick beside the tool-updater kick at L66)
- Modify: `scripts/utils/homelab.sh` (add non-interactive `poll`/`status` arms delegating to situation.sh)
- Test: `tests/homelab.bats`

**Interfaces:**
- Consumes: `scripts/utils/situation.sh homelab` (Task 2).
- Produces: a launchd plist that runs `situation tick` every 60s on macOS; a login-time kick that warms `homelab.json`; `claw homelab poll` / `claw homelab status` working via the existing `cmd_homelab` → `homelab.sh` route.

- [ ] **Step 1: Write the failing test**

Add to `tests/homelab.bats`:

```bash
@test "launchd plist: is valid xml/plist" {
  run plutil -lint "$BATS_TEST_DIRNAME/../config/launchd/com.openclaw.situation.plist"
  [ "$status" -eq 0 ]
}

@test "homelab.sh: poll subcommand delegates to situation.sh (writes cache)" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  run bash "$BATS_TEST_DIRNAME/../scripts/utils/homelab.sh" poll
  [ "$status" -eq 0 ]
  [ -f "$XDG_CACHE_HOME/claw/homelab.json" ]
}
```

(Note: `plutil` is macOS-only; on Linux CI this test is skipped — guard it, see Step 4.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/homelab.bats -f "launchd plist"` (on macOS)
Expected: FAIL — plist file does not exist.

- [ ] **Step 3: Create the launchd plist**

`config/launchd/com.openclaw.situation.plist` (StartInterval mirrors the 60s systemd timer; `~/.dotfiles` path matches the systemd unit's `%h/.dotfiles`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>com.openclaw.situation</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-lc</string>
        <string>"$HOME/.dotfiles/scripts/utils/situation.sh" tick</string>
    </array>
    <key>StartInterval</key>    <integer>60</integer>
    <key>RunAtLoad</key>        <true/>
    <!-- A LaunchAgent inherits launchd's minimal PATH (/usr/bin:/bin:...), which
         excludes Homebrew — so yq/jq/tailscale would be missing and probe_homelab
         would write an EMPTY snapshot, clobbering the good cache every 60s. This
         PATH (path_helper-style, Homebrew first) makes the tools resolve. -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StandardOutPath</key>  <string>/dev/null</string>
    <key>StandardErrorPath</key><string>/dev/null</string>
</dict>
</plist>
```

- [ ] **Step 4: Guard the macOS-only test**

Update the launchd test to skip where `plutil` is absent (Linux CI):

```bash
@test "launchd plist: is valid xml/plist" {
  command -v plutil >/dev/null || skip "plutil is macOS-only"
  run plutil -lint "$BATS_TEST_DIRNAME/../config/launchd/com.openclaw.situation.plist"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 5: Add the login cache-warm kick**

In `shell/welcome-tui.zsh`, immediately after the tool-updater kick (L66), add a sibling self-backgrounded homelab poll so first login warms the cache (zsh `&!` disown — no job-control noise):

```zsh
    "$_d/scripts/utils/tool-updater.sh" &>/dev/null &!
    # Warm the homelab fleet cache in the background (reads ~/.cache/claw/homelab.json
    # at render; this refreshes it). Cheap no-op off-tailnet; never blocks login.
    "$_d/scripts/utils/situation.sh" homelab &>/dev/null &!
```

- [ ] **Step 6: Add the `poll`/`status` arms to `homelab.sh`**

`scripts/utils/homelab.sh` currently runs its interactive fzf body unconditionally. Wrap the dispatch at the very top of the file (after the color/`SSH_CONFIG` setup, before the interactive banner) so a subcommand short-circuits:

```bash
# Non-interactive subcommands delegate to the situation poller.
# Bare `homelab.sh` (no args) keeps the interactive fzf topology launcher.
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
case "${1:-}" in
    poll)   exec bash "$DOTFILES_DIR/scripts/utils/situation.sh" homelab ;;
    status) # refresh the fleet cache, then pretty-print it (the HR-TRUST fleet,
            # NOT situation.json). Two separate commands — the poll must NOT be
            # `exec` (that would replace the process and the print never runs).
            bash "$DOTFILES_DIR/scripts/utils/situation.sh" homelab
            jq . "${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json" 2>/dev/null \
              || cat "${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json" 2>/dev/null \
              || echo "no homelab cache"
            exit 0 ;;
esac
```

(Place this block right after `SSH_CONFIG="$HOME/.ssh/config"` near the top, before the first `echo` banner. For `poll`, `exec` replaces the process so the interactive UI never runs. For `status`, the poll is a plain command — **not** `exec`, which would replace the process and skip the print — followed by a jq pretty-print of the *homelab* cache (the design's `claw homelab status` shows the fleet, not the system `situation.json`), then `exit 0`. `claw homelab poll`/`status` work through the existing `cmd_homelab` → `homelab.sh` route — no `bin/claw` change.)

- [ ] **Step 7: Run tests + lint**

Run: `bats tests/homelab.bats` → Expected: ALL pass (launchd test skipped on Linux).
Run: `zsh -n shell/welcome-tui.zsh` and `bash -n scripts/utils/homelab.sh` → Expected: no output.
Run: `shellcheck -S error -e SC1090,SC1091 scripts/utils/homelab.sh` → Expected: clean.

- [ ] **Step 8: Commit**

```bash
git add config/launchd/com.openclaw.situation.plist shell/welcome-tui.zsh scripts/utils/homelab.sh tests/homelab.bats
git commit -m "feat(homelab): macOS launchd cadence + login cache-warm + claw homelab poll" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification (run after all tasks)

- [ ] Full bats suite: `bats tests/` → all green.
- [ ] Lint parity with CI: `bash tests/shellcheck.sh` (and confirm `scripts/utils/situation.sh`, `scripts/utils/homelab.sh` are clean at error severity).
- [ ] zsh modules: `for f in shell/welcome-tui.zsh shell/profiles/homelab/*.zsh; do zsh -n "$f"; done`
- [ ] Python: `python3 -m py_compile scripts/utils/claw-dashboard.py`
- [ ] JSONC: `python3 -c "import json,sys;json.load(open(sys.argv[1]))" config/.config/fastfetch/config-homelab.jsonc`
- [ ] End-to-end on the BD790i cockpit (manual): `claw homelab poll && claw situation show && cat ~/.cache/claw/homelab.json | jq .` then open a fresh login shell → fleet block appears in the dashboard footer; `claw` → Hardware & Ops shows the block; `claw load homelab && hstatus` shows the cached fleet.
- [ ] Theme tracking: `claw theme set matrix` then re-render dashboard + `hstatus` → status dots adopt the palette (proves no hardcoded ANSI in new surfaces).

## Notes on decisions baked in

- **Inventory committed to the repo** (`config/homelab/fleet.yml`), per single-user-repo norm, with a machine-local `$XDG_CONFIG_HOME/claw/fleet.yml` override that wins. If HR-TRUST host/IP detail should stay untracked, move `fleet.yml` to the machine-local path and commit only `fleet.yml.example` (one-line change in Task 2's `HOMELAB_FLEET` resolution + drop `fleet.yml` from Task 1's commit).
- **Scheduling reuses the existing `situation` timer** on Linux (tick writes both caches); macOS gets a launchd plist + a login kick. No second timer/unit — spine-compliant.
- **`claw situation homelab`** is the canonical poll entrypoint; **`claw homelab poll`** is wired as a convenience via `homelab.sh` so the homelab front door behaves as the user expects.
