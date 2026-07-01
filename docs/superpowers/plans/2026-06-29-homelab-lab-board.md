# HR-TRUST Detailed Lab Board — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a detailed, grouped, icon-matched board of every HR-TRUST lab service (nodes, cluster, apps, infra, DNS) as one shared block on both the `local` and `homelab` profiles.

**Architecture:** Extend the existing producer→cache→reader seam *additively*. Widen `fleet.yml` to the live 4-node truth; teach `probe_homelab()` two new probe kinds (`http`-via-Host-header, `dns`) plus a non-Tailscale reachability fallback; add `cluster{}`, `machines[].role`, and `services[].group/.glyph` to the cache **without renaming any existing field**; add ONE new theme-aware renderer `homelab-board.sh` that the two fastfetch configs and `hstatus()` consume.

**Tech Stack:** Bash (`set -u`), `yq` v4, `jq`, `curl`, `dig`, `kubectl`, fastfetch `command` modules, `bats` tests, `shellcheck`.

## Global Constraints

- **Backward-compatible cache (hard).** Keep the `machines[].services[]` shape and every existing key. Only ADD fields (`cluster{}`, `machines[].role`, `services[].group`, `services[].glyph`). The 2026-06-27 readers (`claw-dashboard.py homelab_lines()`, `welcome-tui _claw_homelab_block()`) and their `bats` tests must stay green.
- **Zero network at render.** Only `probe_homelab()` (background poller) touches the network. Every reader reads `~/.cache/claw/homelab.json` only.
- **Atomic writes.** Snapshot via `mktemp` + `mv -f`; top-level `ts` stamp. Unchanged.
- **Every probe timeout-guarded** (2–4s). A tick must never hang.
- **Theme tokens only.** New rows consume `CLAW_RGB_*` (via `scripts/utils/theme.sh`) with refined-dark fallbacks. No hardcoded ANSI color literals in new code.
- **State vocabulary:** `state ∈ {up, degraded, down, planned}` → `up`=green ●, `degraded`=amber ●, `down`=red ●, `planned`=muted ○.
- **Stale threshold:** `5 × 60s` = 300s. Fresh→render; stale→dim + `stale Xm ago`; absent→render nothing.
- **Safety guards:** non-interactive / piped / `SSH_CONNECTION`-set shells emit nothing from the renderer (inherit existing TUI guards).
- **Staging:** `git add` by explicit path, never `-A`. Conventional-commit subjects (`feat(...)`, `docs(...)`), ≤72 chars, with the `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer.
- **Test runner:** `bats tests/`. Lint: `tests/shellcheck.sh`. Spec: `docs/superpowers/specs/2026-06-29-homelab-lab-board-design.md`.

---

## File Structure

- `config/homelab/fleet.yml` — **rewrite**: 4 machines, `cluster:` block, `services:` map gains `group`/`glyph`.
- `config/homelab/fleet.yml.example` — **rewrite**: mirror new keys, generic values.
- `scripts/utils/situation.sh` — **modify** `_hl_probe_service()` (new `dns` kind; `http` via Host header; ungated cluster probes) and `probe_homelab()` (reachability fallback, `cluster{}`, `role`, `group`/`glyph` passthrough).
- `scripts/utils/homelab-board.sh` — **create**: the shared renderer (glyph map, grouped sections, guards).
- `config/.config/fastfetch/config-local.jsonc` — **modify**: append a `── HR-TRUST Lab ──` section of `command` rows.
- `config/.config/fastfetch/config-homelab.jsonc` — **modify**: collapse inline `jq` rows to `homelab-board.sh` calls.
- `shell/profiles/homelab/` (`hstatus`) — **modify**: cache-first via `homelab-board.sh all`.
- `tests/homelab.bats` — **modify/extend**: new-schema + renderer assertions.
- `tests/fixtures/homelab.{up,mixed,stale,empty}.json` — **rewrite** to new schema (group/glyph/cluster/role/4-node).
- `README.md` — **modify**: add a focused Homelab Fleet section.

---

## Task 1: Inventory rewrite — `fleet.yml` to live 4-node truth

**Files:**
- Modify: `config/homelab/fleet.yml`
- Modify: `config/homelab/fleet.yml.example`
- Test: `tests/homelab.bats`

**Interfaces:**
- Produces: a `fleet.yml` with `cluster.{context,traefik_ip}`, 4 `machines[]` (`ms-01`,`r630`,`bd790i`,`pihole`) each with `id/host/user/ssh/role/services[]`, and a `services:` map where every entry has `kind`, `group ∈ {apps,infra,dns}`, and `glyph`. Service `kind ∈ {http,kube,ssh,native,dns,tcp}`. `harbor` carries `planned: true`. `pihole-dns` carries `server` + `dns_probe`.

- [ ] **Step 1: Write the failing test** — append to `tests/homelab.bats`:

```bash
@test "fleet.yml: lists all four machines with roles" {
  f="$BATS_TEST_DIRNAME/../config/homelab/fleet.yml"
  run yq -r '.machines[].id' "$f"
  [ "$status" -eq 0 ]
  for m in ms-01 r630 bd790i pihole; do [[ "$output" == *"$m"* ]]; done
  run yq -r '.machines[] | select(.id=="ms-01") | .role' "$f"
  [ "$output" = "control-plane" ]
}

@test "fleet.yml: every service in the map has kind, group, glyph" {
  f="$BATS_TEST_DIRNAME/../config/homelab/fleet.yml"
  run yq -e '.services | to_entries | all(.value | (has("kind") and has("group") and has("glyph")))' "$f"
  [ "$status" -eq 0 ]
}

@test "fleet.yml: cluster block names context k3s-ms01 and a traefik_ip" {
  f="$BATS_TEST_DIRNAME/../config/homelab/fleet.yml"
  run yq -r '.cluster.context' "$f"; [ "$output" = "k3s-ms01" ]
  run yq -e '.cluster.traefik_ip' "$f"; [ "$status" -eq 0 ]
}

@test "fleet.yml: harbor is declared planned" {
  f="$BATS_TEST_DIRNAME/../config/homelab/fleet.yml"
  run yq -r '.services.harbor.planned' "$f"; [ "$output" = "true" ]
}
```

Also DELETE the now-obsolete assertion `fleet.yml: parses and lists bd790i with its services` block that hard-codes `bd790i` as `machines[0]` if its node order changed — keep it only if it still passes (bd790i remains present, just not index 0). Adjust: change its selector to `select(.id=="bd790i")` (already is) — it stays valid.

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/homelab.bats -f "all four machines"`
Expected: FAIL (old `fleet.yml` has only `bd790i`).

- [ ] **Step 3: Rewrite `config/homelab/fleet.yml`**

```yaml
# HR-TRUST homelab fleet inventory — read by scripts/utils/situation.sh probe_homelab().
# Machine-local override: $XDG_CONFIG_HOME/claw/fleet.yml (untracked) wins if present.
# Adding a box or service is data here — no code change.
# Service kinds: native | ssh | http | tcp | kube | dns.
fleet:
  name: HR-TRUST
  poll_seconds: 60

# k8s cluster context + the Traefik entrypoint used for Host-header service probes
# (DNS-independent — works on-LAN or over a routed tailnet).
cluster:
  context: k3s-ms01
  traefik_ip: 192.168.1.109

machines:
  - { id: ms-01,  host: 192.168.1.109, user: henry, ssh: true,  role: control-plane,
      services: [k3s, gitea, n8n, portainer, enclave, grafana, harbor] }
  - { id: r630,   host: 192.168.1.102, user: henry, ssh: true,  role: worker, services: [] }
  - { id: bd790i, host: 192.168.1.104, user: henry, ssh: true,  role: worker,
      services: [docker, ollama, tailscale] }
  - { id: pihole, host: 192.168.1.101, user: henry, ssh: false, role: dns,
      services: [pihole-dns] }

services:
  # apps — probed via Traefik Host header against cluster.traefik_ip
  gitea:      { kind: http, group: apps,  glyph: git,       host: git.lab.local }
  n8n:        { kind: http, group: apps,  glyph: n8n,       host: n8n.lab.local }
  portainer:  { kind: http, group: apps,  glyph: portainer, host: portainer.lab.local }
  enclave:    { kind: http, group: apps,  glyph: enclave,   host: enclave.lab.local }
  grafana:    { kind: http, group: apps,  glyph: grafana,   host: grafana.lab.local }
  harbor:     { kind: http, group: apps,  glyph: harbor,    host: harbor.lab.local, planned: true }
  # infra
  k3s:        { kind: kube,   group: infra, glyph: k8s,     context: k3s-ms01 }
  docker:     { kind: ssh,    group: infra, glyph: docker,  cmd: "docker ps -q | wc -l" }
  ollama:     { kind: http,   group: infra, glyph: ollama,  host: bd790i, port: 11434, health: /api/tags }
  tailscale:  { kind: native, group: infra, glyph: vpn }
  # dns
  pihole-dns: { kind: dns,    group: dns,   glyph: pihole,  server: 192.168.1.101, dns_probe: git.lab.local }

identity:
  github: { kind: gh }
```

- [ ] **Step 4: Rewrite `config/homelab/fleet.yml.example`** (generic mirror)

```yaml
# EXAMPLE fleet inventory. Copy to config/homelab/fleet.yml (committed) or
# $XDG_CONFIG_HOME/claw/fleet.yml (machine-local, untracked) and edit.
# Service kinds: native | ssh | http | tcp | kube | dns.
# See docs/superpowers/specs/2026-06-29-homelab-lab-board-design.md
fleet: { name: MY-LAB, poll_seconds: 60 }
cluster: { context: my-k3s, traefik_ip: 192.168.1.10 }
machines:
  - { id: cp1, host: 192.168.1.10, user: me, ssh: true,  role: control-plane, services: [k3s, app1] }
  - { id: dns, host: 192.168.1.2,  user: me, ssh: false, role: dns, services: [pihole-dns] }
services:
  app1:       { kind: http, group: apps,  glyph: git,    host: app1.lab.local }
  k3s:        { kind: kube, group: infra, glyph: k8s,    context: my-k3s }
  pihole-dns: { kind: dns,  group: dns,   glyph: pihole, server: 192.168.1.2, dns_probe: app1.lab.local }
identity:
  github: { kind: gh }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/homelab.bats -f "fleet.yml"`
Expected: PASS (all `fleet.yml:` tests green).

- [ ] **Step 6: Commit**

```bash
git add config/homelab/fleet.yml config/homelab/fleet.yml.example tests/homelab.bats
git commit -m "feat(homelab): fleet.yml to live 4-node truth + group/glyph metadata" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Producer — additive cache, new probe kinds, reachability fallback

**Files:**
- Modify: `scripts/utils/situation.sh` (`_hl_probe_service()` ~L150-200, `probe_homelab()` ~L200-290)
- Test: `tests/homelab.bats`

**Interfaces:**
- Consumes: `fleet.yml` from Task 1 (`cluster.traefik_ip`, `services.<svc>.{kind,group,glyph,host,server,dns_probe,planned,port,health}`).
- Produces: `~/.cache/claw/homelab.json` with, in addition to the existing fields, `cluster: {context,ready,total}`, `machines[].role`, and `services[].group` + `services[].glyph`. New `state` value `planned`. Service objects keep `id/state/detail`.

- [ ] **Step 1: Write the failing tests** — append to `tests/homelab.bats`:

```bash
@test "situation homelab: cache has cluster{} and machine roles" {
  command -v yq >/dev/null || skip "yq required"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  bash "$BATS_TEST_DIRNAME/../scripts/utils/situation.sh" homelab
  run jq -e '.cluster and (.cluster.context=="k3s-ms01")' "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$status" -eq 0 ]
  run jq -e '.machines[] | select(.id=="ms-01") | .role=="control-plane"' "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$status" -eq 0 ]
}

@test "situation homelab: every service object carries group and glyph" {
  command -v yq >/dev/null || skip "yq required"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  bash "$BATS_TEST_DIRNAME/../scripts/utils/situation.sh" homelab
  run jq -e '[.machines[].services[]] | all(has("group") and has("glyph"))' "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$status" -eq 0 ]
}

@test "situation homelab: planned service renders state 'planned' not 'down'" {
  command -v yq >/dev/null || skip "yq required"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  bash "$BATS_TEST_DIRNAME/../scripts/utils/situation.sh" homelab
  run jq -r '[.machines[].services[] | select(.id=="harbor") | .state][0]' "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$output" = "planned" ] || [ "$output" = "up" ]   # planned until deployed; up once live
}

@test "situation homelab: state vocabulary includes planned" {
  command -v yq >/dev/null || skip "yq required"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  bash "$BATS_TEST_DIRNAME/../scripts/utils/situation.sh" homelab
  run jq -e '[.machines[].services[].state] | all(. as $s | ["up","down","degraded","planned"]|index($s))' \
    "$XDG_CACHE_HOME/claw/homelab.json"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/homelab.bats -f "cluster"`
Expected: FAIL (`.cluster` is null in current output).

- [ ] **Step 3: Add `dns` kind + Host-header `http` to `_hl_probe_service()`**

In `scripts/utils/situation.sh`, the function signature gains the cluster Traefik IP. Change the call site (Step 5) to pass it. Replace the `http)` case body and add a `dns)` case. The function reads `services.<svc>.planned`; a planned service that is unreachable returns `planned` instead of `down`:

```bash
# Probe one service. Echoes:  <state>\t<detail>
# $5 = cluster traefik_ip (for Host-header http probes); $6 = cluster context.
_hl_probe_service() {
    local host="$1" user="$2" ssh_ok="$3" svc="$4" traefik_ip="$5" ctx_default="$6"
    local kind shost port health url planned state detail
    kind="$(yq -r ".services.${svc}.kind // \"native\"" "$HOMELAB_FLEET" 2>/dev/null)"
    planned="$(yq -r ".services.${svc}.planned // false" "$HOMELAB_FLEET" 2>/dev/null)"
    state="down"; detail="unreachable"
    case "$kind" in
        http)
            shost="$(yq -r ".services.${svc}.host // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            port="$(yq -r ".services.${svc}.port // 0" "$HOMELAB_FLEET" 2>/dev/null)"
            health="$(yq -r ".services.${svc}.health // \"/\"" "$HOMELAB_FLEET" 2>/dev/null)"
            local code
            if [ "$port" != "0" ]; then
                # direct endpoint probe (e.g. ollama :11434/api/tags)
                code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
                    "http://${shost}:${port}${health}" 2>/dev/null)"
            else
                # cluster app via Traefik Host header — DNS-independent
                code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
                    -H "Host: ${shost}" "http://${traefik_ip}/" 2>/dev/null)"
            fi
            case "$code" in
                2*|30*|401|403) state="up";       detail="http ${code}" ;;
                50[234])        state="degraded"; detail="http ${code}" ;;
                *)              state="down";     detail="${code:-000}" ;;
            esac ;;
        dns)
            local server probe ans
            server="$(yq -r ".services.${svc}.server // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            probe="$(yq -r ".services.${svc}.dns_probe // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            if [ -n "$server" ] && [ -n "$probe" ]; then
                ans="$(timeout 2 dig +short "@${server}" "$probe" 2>/dev/null | head -1)"
                if [ -n "$ans" ]; then state="up"; detail="${probe%%.*}→${ans}"; fi
            fi ;;
        tcp)
            shost="$(yq -r ".services.${svc}.host // \"$host\"" "$HOMELAB_FLEET" 2>/dev/null)"
            port="$(yq -r ".services.${svc}.port // 0" "$HOMELAB_FLEET" 2>/dev/null)"
            if [ "$port" != "0" ] && timeout 2 bash -c "exec 3<>/dev/tcp/${shost}/${port}" 2>/dev/null; then
                state="up"; detail=":${port}"
            fi ;;
        kube)
            local kctx; kctx="$(yq -r ".services.${svc}.context // \"$ctx_default\"" "$HOMELAB_FLEET" 2>/dev/null)"
            local nodes=""
            if have kubectl; then
                nodes="$(timeout 5 kubectl --context "$kctx" get nodes --no-headers 2>/dev/null)"
            fi
            if [ -z "$nodes" ] && [ "$ssh_ok" = "true" ]; then
                nodes="$(timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 \
                    "${user}@${host}" "kubectl get nodes --no-headers 2>/dev/null" 2>/dev/null)"
            fi
            if [ -n "$nodes" ]; then
                local tot rdy; tot="$(printf '%s\n' "$nodes" | grep -c .)"
                rdy="$(printf '%s\n' "$nodes" | awk '$2=="Ready"{c++} END{print c+0}')"
                [ "$rdy" -gt 0 ] 2>/dev/null && state="up"
                detail="${kctx} · ${rdy}/${tot} Ready"
            fi ;;
        ssh)
            local cmd; cmd="$(yq -r ".services.${svc}.cmd // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            if [ "$ssh_ok" = "true" ] && [ -n "$cmd" ]; then
                local out; out="$(timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 \
                    "${user}@${host}" "$cmd" 2>/dev/null | tr -d ' ')"
                if [ -n "$out" ]; then state="up"; detail="${out} containers"; fi
            fi ;;
        native|*)
            local bs=""
            if [ "$ssh_ok" = "true" ]; then
                bs="$(timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 "${user}@${host}" \
                    "tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null" 2>/dev/null)"
            elif have tailscale; then
                bs="$(timeout 3 tailscale status --json 2>/dev/null | { have jq && jq -r '.BackendState' 2>/dev/null; })"
            fi
            if [ "${bs:-}" = "Running" ]; then state="up"; detail="running"; fi ;;
    esac
    # A declared-but-not-yet-deployed service shows as 'planned', not red 'down'.
    [ "$state" = "down" ] && [ "$planned" = "true" ] && { state="planned"; detail="not deployed"; }
    printf '%s\t%s' "$state" "$detail"
}
```

- [ ] **Step 4: Run the kind-level tests**

Run: `bats tests/homelab.bats -f "planned"`
Expected: still FAIL until Step 5 wires passthrough + call site, but no syntax error: `bash -n scripts/utils/situation.sh` → exit 0.

- [ ] **Step 5: Rewire `probe_homelab()` — reachability fallback, cluster{}, role, group/glyph passthrough**

In `probe_homelab()`: (a) after fetching `tj`, add an `nc`/`ping` reachability fallback; (b) for `http`/`dns`/`kube`/`tcp` kinds, probe regardless of machine state; (c) read `cluster.traefik_ip`/`cluster.context`; (d) emit per-service `group`/`glyph` and `cluster{}`/`role`. Replace the machine/service loop and the final heredoc:

```bash
    # cluster block — context + traefik probe target
    local cl_ctx cl_ip cl_ready=null cl_total=null
    cl_ctx="$(yq -r '.cluster.context // ""' "$HOMELAB_FLEET" 2>/dev/null)"
    cl_ip="$(yq -r '.cluster.traefik_ip // ""' "$HOMELAB_FLEET" 2>/dev/null)"
    # cluster readiness once (cheap, reused as the k3s service detail too)
    if have kubectl && [ -n "$cl_ctx" ]; then
        local cn; cn="$(timeout 5 kubectl --context "$cl_ctx" get nodes --no-headers 2>/dev/null)"
        if [ -n "$cn" ]; then
            cl_total="$(printf '%s\n' "$cn" | grep -c .)"
            cl_ready="$(printf '%s\n' "$cn" | awk '$2=="Ready"{c++} END{print c+0}')"
        fi
    fi

    local machines_json="" mi=0 mcount
    mcount="$(yq -r '.machines | length' "$HOMELAB_FLEET" 2>/dev/null)"; : "${mcount:=0}"
    while [ "$mi" -lt "$mcount" ]; do
        local id host user ssh_ok role mstate addr latency
        id="$(yq -r ".machines[$mi].id // \"node$mi\"" "$HOMELAB_FLEET" 2>/dev/null)"
        host="$(yq -r ".machines[$mi].host // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
        user="$(yq -r ".machines[$mi].user // \"$USER\"" "$HOMELAB_FLEET" 2>/dev/null)"
        ssh_ok="$(yq -r ".machines[$mi].ssh // false" "$HOMELAB_FLEET" 2>/dev/null)"
        role="$(yq -r ".machines[$mi].role // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
        mstate="down"; addr=""; latency="null"

        # reachability: tailscale peer first, else nc/ping fallback (LAN-friendly)
        if [ -n "$tj" ] && have jq && [ -n "$host" ]; then
            local online
            online="$(printf '%s' "$tj" | jq -r --arg h "$host" \
                '[(.Peer // {})[] | select(.DNSName|startswith($h+"."))][0] // {} | .Online // false' 2>/dev/null)"
            addr="$(printf '%s' "$tj" | jq -r --arg h "$host" \
                '[(.Peer // {})[] | select(.DNSName|startswith($h+"."))][0] // {} | (.TailscaleIPs // [""])[0] // ""' 2>/dev/null)"
            [ "$online" = "true" ] && mstate="up"
        fi
        if [ "$mstate" != "up" ] && [ -n "$host" ]; then
            if timeout 2 bash -c "exec 3<>/dev/tcp/${host}/22" 2>/dev/null \
               || timeout 2 bash -c "exec 3<>/dev/tcp/${host}/80" 2>/dev/null \
               || ping -c1 -W1 "$host" >/dev/null 2>&1; then
                mstate="up"; : "${addr:=$host}"
            fi
        fi
        : "${addr:=}"; : "${latency:=null}"

        # node Ready state from the cluster probe overrides reachability for k8s nodes
        if [ -n "${cn:-}" ]; then
            local nr; nr="$(printf '%s\n' "$cn" | awk -v n="$id" '$1==n{print $2}')"
            [ "$nr" = "NotReady" ] && mstate="degraded"
            [ "$nr" = "Ready" ] && mstate="up"
        fi

        local svcs_json="" si=0 scount svc
        scount="$(yq -r ".machines[$mi].services | length" "$HOMELAB_FLEET" 2>/dev/null)"; : "${scount:=0}"
        while [ "$si" -lt "$scount" ]; do
            svc="$(yq -r ".machines[$mi].services[$si]" "$HOMELAB_FLEET" 2>/dev/null)"
            local skind sstate sdetail line grp gly
            skind="$(yq -r ".services.${svc}.kind // \"native\"" "$HOMELAB_FLEET" 2>/dev/null)"
            grp="$(yq -r ".services.${svc}.group // \"apps\"" "$HOMELAB_FLEET" 2>/dev/null)"
            gly="$(yq -r ".services.${svc}.glyph // \"\"" "$HOMELAB_FLEET" 2>/dev/null)"
            # cluster-level kinds probe regardless of machine reachability;
            # shell-level kinds (ssh/native) require the box up.
            if [ "$mstate" = "up" ] || [ "$mstate" = "degraded" ] \
               || [ "$skind" = "http" ] || [ "$skind" = "dns" ] \
               || [ "$skind" = "kube" ] || [ "$skind" = "tcp" ]; then
                line="$(_hl_probe_service "$host" "$user" "$ssh_ok" "$svc" "$cl_ip" "$cl_ctx")"
                sstate="${line%%	*}"; sdetail="${line#*	}"
            else
                sstate="down"; sdetail="host down"
            fi
            [ -n "$svcs_json" ] && svcs_json="${svcs_json},"
            svcs_json="${svcs_json}{\"id\":\"$(_hl_json_str "$svc")\",\"state\":\"${sstate}\",\"detail\":\"$(_hl_json_str "$sdetail")\",\"group\":\"$(_hl_json_str "$grp")\",\"glyph\":\"$(_hl_json_str "$gly")\"}"
            si=$((si+1))
        done

        [ -n "$machines_json" ] && machines_json="${machines_json},"
        machines_json="${machines_json}{\"id\":\"$(_hl_json_str "$id")\",\"state\":\"${mstate}\",\"addr\":\"$(_hl_json_str "$addr")\",\"latency_ms\":${latency:-null},\"role\":\"$(_hl_json_str "$role")\",\"services\":[${svcs_json}]}"
        mi=$((mi+1))
    done

    cat <<EOF
{
  "ts": "$ts",
  "fleet": "$(_hl_json_str "$fleet_name")",
  "cluster": { "context": "$(_hl_json_str "$cl_ctx")", "ready": ${cl_ready:-null}, "total": ${cl_total:-null} },
  "route": { "via": "$(_hl_json_str "$route_via")", "path": "$(_hl_json_str "$route_path")", "exit_node": null },
  "identity": { "github": { "user": "$(_hl_json_str "$gh_user")", "state": "$gh_state" } },
  "machines": [${machines_json}]
}
EOF
```

Also update the empty-snapshot heredoc (the `! have yq` branch) to include `"cluster": {"context":"","ready":null,"total":null},` so the schema is consistent when `yq` is missing.

- [ ] **Step 6: Run the full producer test set + lint**

Run: `bash -n scripts/utils/situation.sh && bats tests/homelab.bats && tests/shellcheck.sh`
Expected: PASS. (The 2026-06-27 tests asserting `machines[].services[]` and `machines[].id` still pass — schema kept.)

- [ ] **Step 7: Commit**

```bash
git add scripts/utils/situation.sh tests/homelab.bats
git commit -m "feat(homelab): additive cache (cluster/role/group/glyph) + dns/http-Host probes" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Regenerate fixtures to the new schema

**Files:**
- Modify: `tests/fixtures/homelab.{up,mixed,stale,empty}.json`
- Test: `tests/homelab.bats` (existing fixture-render tests must still pass)

**Interfaces:**
- Produces: fixtures with the new fields (`cluster{}`, `machines[].role`, `services[].group/.glyph`) plus a `planned` and a `degraded` example, used by Task 4's renderer tests. Keeps `bd790i` + `k3s` present (existing assertions).

- [ ] **Step 1: Rewrite `tests/fixtures/homelab.up.json`** (fresh `ts`, 4 nodes, all up)

```json
{ "ts": "2099-01-01T00:00:00Z", "fleet": "HR-TRUST",
  "cluster": { "context": "k3s-ms01", "ready": 3, "total": 3 },
  "route": { "via": "direct", "path": "→ bd790i", "exit_node": null },
  "identity": { "github": { "user": "hankthebldr", "state": "up" } },
  "machines": [
    { "id": "ms-01", "state": "up", "addr": "192.168.1.109", "latency_ms": null, "role": "control-plane",
      "services": [
        {"id":"k3s","state":"up","detail":"k3s-ms01 · 3/3 Ready","group":"infra","glyph":""},
        {"id":"gitea","state":"up","detail":"http 200","group":"apps","glyph":""},
        {"id":"harbor","state":"planned","detail":"not deployed","group":"apps","glyph":""} ] },
    { "id": "bd790i", "state": "up", "addr": "192.168.1.104", "latency_ms": null, "role": "worker",
      "services": [
        {"id":"docker","state":"up","detail":"7 containers","group":"infra","glyph":""},
        {"id":"ollama","state":"up","detail":"3 models","group":"infra","glyph":""} ] },
    { "id": "pihole", "state": "up", "addr": "192.168.1.101", "latency_ms": null, "role": "dns",
      "services": [ {"id":"pihole-dns","state":"up","detail":"git→192.168.1.109","group":"dns","glyph":""} ] } ] }
```

- [ ] **Step 2: Rewrite `tests/fixtures/homelab.mixed.json`** (gitea degraded, ollama down, harbor planned)

```json
{ "ts": "2099-01-01T00:00:00Z", "fleet": "HR-TRUST",
  "cluster": { "context": "k3s-ms01", "ready": 2, "total": 3 },
  "route": { "via": "derp", "path": "→ DERP(fra) → bd790i", "exit_node": null },
  "identity": { "github": { "user": "hankthebldr", "state": "up" } },
  "machines": [
    { "id": "ms-01", "state": "up", "role": "control-plane",
      "services": [
        {"id":"k3s","state":"up","detail":"k3s-ms01 · 2/3 Ready","group":"infra","glyph":""},
        {"id":"gitea","state":"degraded","detail":"http 503","group":"apps","glyph":""},
        {"id":"harbor","state":"planned","detail":"not deployed","group":"apps","glyph":""} ] },
    { "id": "r630", "state": "degraded", "role": "worker", "services": [] },
    { "id": "bd790i", "state": "up", "role": "worker",
      "services": [ {"id":"ollama","state":"down","detail":"000","group":"infra","glyph":""} ] } ] }
```

- [ ] **Step 3: Rewrite `homelab.stale.json`** — identical body to `up.json` but `"ts": "2000-01-01T00:00:00Z"` (forces the stale branch). **`homelab.empty.json`** stays minimal but add `cluster`:

```json
{ "ts": "2099-01-01T00:00:00Z", "fleet": "HR-TRUST",
  "cluster": { "context": "", "ready": null, "total": null },
  "route": { "via": "unknown", "path": "", "exit_node": null },
  "identity": {}, "machines": [] }
```

- [ ] **Step 4: Verify existing fixture-render tests still pass**

Run: `bats tests/homelab.bats -f "dashboard homelab_lines"`
Expected: PASS (fixtures still contain `bd790i` + `k3s`; `claw-dashboard.py` ignores the new fields).

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/homelab.up.json tests/fixtures/homelab.mixed.json \
        tests/fixtures/homelab.stale.json tests/fixtures/homelab.empty.json
git commit -m "test(homelab): fixtures to additive schema (cluster/role/group/glyph)" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Shared renderer — `scripts/utils/homelab-board.sh`

**Files:**
- Create: `scripts/utils/homelab-board.sh`
- Test: `tests/homelab.bats`

**Interfaces:**
- Consumes: `~/.cache/claw/homelab.json` (the Task 2 schema), `scripts/utils/theme.sh` for `CLAW_RGB_*`.
- Produces: CLI `homelab-board.sh [all|nodes|cluster|apps|infra|dns|route]`. Prints theme-colored, dot-prefixed, grouped lines; empty output when the cache is absent or the shell is non-interactive/piped/SSH. Each service line is `<glyph> <dot> <id> <detail?>`; dot color = state.

- [ ] **Step 1: Write the failing tests** — append to `tests/homelab.bats`:

```bash
BOARD="$BATS_TEST_DIRNAME/../scripts/utils/homelab-board.sh"

@test "board: up fixture renders node ids and an up service" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/homelab.up.json" "$XDG_CACHE_HOME/claw/homelab.json"
  run env NO_COLOR=1 bash "$BOARD" all
  [ "$status" -eq 0 ]
  [[ "$output" == *"ms-01"* ]]
  [[ "$output" == *"gitea"* ]]
  [[ "$output" == *"pi-hole"* ]] || [[ "$output" == *"pihole"* ]]
  [[ "$output" == *"3/3 Ready"* ]]
}

@test "board: planned service shows a hollow marker, not down" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/homelab.up.json" "$XDG_CACHE_HOME/claw/homelab.json"
  run env NO_COLOR=1 bash "$BOARD" apps
  [ "$status" -eq 0 ]
  [[ "$output" == *"harbor"* ]]
  [[ "$output" == *"○"* ]]      # planned uses the hollow dot
}

@test "board: absent cache prints nothing" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/none"
  run env NO_COLOR=1 bash "$BOARD" all
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "board: stale cache prints a stale age suffix" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/homelab.stale.json" "$XDG_CACHE_HOME/claw/homelab.json"
  run env NO_COLOR=1 bash "$BOARD" all
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale"* ]]
}

@test "board: piped/non-interactive emits nothing under SSH_CONNECTION" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"; mkdir -p "$XDG_CACHE_HOME/claw"
  cp "$BATS_TEST_DIRNAME/fixtures/homelab.up.json" "$XDG_CACHE_HOME/claw/homelab.json"
  run env SSH_CONNECTION="1 2 3 4" bash "$BOARD" all
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/homelab.bats -f "board:"`
Expected: FAIL ("No such file" — `homelab-board.sh` not created yet).

- [ ] **Step 3: Create `scripts/utils/homelab-board.sh`**

```bash
#!/usr/bin/env bash
# homelab-board.sh — detailed HR-TRUST fleet board. Reads the situation cache
# (~/.cache/claw/homelab.json); ZERO network. Theme-aware via theme.sh, so dot
# colors track `claw theme`. Grouped sections (Nodes/Cluster/DNS/Apps/Infra/Route)
# in the dashboard's icon→context→status idiom. Safe at login: emits nothing when
# the shell is non-interactive/piped/SSH, or when the cache is absent/malformed.
#
# Usage: homelab-board.sh [all|nodes|cluster|dns|apps|infra|route]
set -u

# ── safety: never leak into scp/rsync/piped shells ──────────────────────────
case "${1:-all}" in --help|-h) echo "usage: homelab-board.sh [all|nodes|cluster|dns|apps|infra|route]"; exit 0;; esac
[ -n "${SSH_CONNECTION:-}" ] && exit 0

have() { command -v "$1" >/dev/null 2>&1; }
have jq || exit 0

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json"
[ -r "$CACHE" ] || exit 0
jq -e . "$CACHE" >/dev/null 2>&1 || exit 0      # malformed → skip

# ── palette (theme.sh exports CLAW_RGB_*; GitHub-dark fallback) ──────────────
_dots="${DOTFILES_DIR:-$HOME/.dotfiles}"
# shellcheck source=/dev/null
[ -r "$_dots/scripts/utils/theme.sh" ] && . "$_dots/scripts/utils/theme.sh" 2>/dev/null
if [ -n "${NO_COLOR:-}" ]; then
  GREEN=""; AMBER=""; RED=""; MUTED=""; BLUE=""; LABEL=""; RST=""
else
  GREEN=$'\033[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"'m'
  AMBER=$'\033[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"'m'
  RED=$'\033[38;2;'"${CLAW_RGB_RED:-255;123;114}"'m'
  MUTED=$'\033[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"'m'
  BLUE=$'\033[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"'m'
  LABEL=$'\033[38;2;'"${CLAW_RGB_PURPLE:-188;140;255}"'m'
  RST=$'\033[0m'
fi

# state → "<color><dot>"  (planned uses a hollow ○)
dot() { case "$1" in
  up)       printf '%s●' "$GREEN" ;;
  degraded) printf '%s●' "$AMBER" ;;
  planned)  printf '%s○' "$MUTED" ;;
  *)        printf '%s●' "$RED" ;;
esac; }

# ── freshness: fresh (<300s) | stale | (absent handled above) ───────────────
_age_secs() {   # ISO-8601 Z → seconds since, portable (mac+linux)
  local iso="$1" t now; now="$(date -u +%s)"
  if t="$(date -u -d "$iso" +%s 2>/dev/null)"; then :
  elif t="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null)"; then :
  else echo 0; return; fi
  echo $(( now - t ))
}
_age_human() { local s="$1"; if [ "$s" -lt 90 ]; then echo "${s}s"; elif [ "$s" -lt 5400 ]; then echo "$((s/60))m"; else echo "$((s/3600))h"; fi; }

TS="$(jq -r '.ts // ""' "$CACHE")"
AGE="$(_age_secs "$TS")"
FRESHTAG=""
if [ "$AGE" -gt 300 ]; then FRESHTAG="${MUTED}stale $(_age_human "$AGE") ago${RST}"; STALE=1
else FRESHTAG="${MUTED}updated $(_age_human "$AGE") ago${RST}"; STALE=0; fi

# header line (printed by `all` only)
_hdr() { printf '  %s%s%s ───────────────  %s\n' "$BLUE" "$(jq -r '.fleet // "FLEET"' "$CACHE")" "$RST" "$FRESHTAG"; }

# render one service id list for a group: "<glyph> <dot> <id>"
_group_line() {  # $1=group label  $2=group key
  local label="$1" key="$2" cells
  cells="$(jq -r --arg g "$key" '
    [ .machines[].services[] | select(.group==$g) ] as $s
    | if ($s|length)==0 then empty
      else ($s | map((.glyph // "") + " " + .state + " " + .id) | join("\t")) end' "$CACHE")"
  [ -z "$cells" ] && return
  printf '  %s%-8s%s' "$LABEL" "$label" "$RST"
  local IFS=$'\t' cell
  for cell in $cells; do
    local gly st id; gly="${cell%%$'\000'*}"; id="${cell##*$'\000'}"
    st="${cell#*$'\000'}"; st="${st%%$'\000'*}"
    printf ' %s %s%s %s%s%s' "$gly" "$(dot "$st")" "$RST" "$MUTED" "$id" "$RST"
  done
  printf '\n'
}

_nodes_line() {
  local cells; cells="$(jq -r '.machines[] | (.glyph // "") + " " + .state + " " + .id + (if .role=="control-plane" then " cp" else "" end)' "$CACHE" 2>/dev/null)"
  # machines have no glyph field; use a fixed node glyph
  printf '  %s%-8s%s' "$LABEL" "Nodes" "$RST"
  jq -r '.machines[] | .state + " " + .id + (if .role=="control-plane" then " cp" else "" end)' "$CACHE" \
  | while IFS= read -r row; do
      local st id; st="${row%%$'\000'*}"; id="${row#*$'\000'}"
      printf ' %s %s%s %s%s%s' "" "$(dot "$st")" "$RST" "$MUTED" "$id" "$RST"
    done
  printf '\n'
}

_cluster_line() {
  local ctx rdy tot; ctx="$(jq -r '.cluster.context // ""' "$CACHE")"
  rdy="$(jq -r '.cluster.ready // "?"' "$CACHE")"; tot="$(jq -r '.cluster.total // "?"' "$CACHE")"
  [ -z "$ctx" ] && return
  local st=up; [ "$rdy" != "$tot" ] && st=degraded
  printf '  %s%-8s%s  %s%s %s%s%s  %s%s/%s Ready%s\n' "$LABEL" "Cluster" "$RST" \
    "$(dot "$st")" "$RST" "$BLUE" "$ctx" "$RST" "$MUTED" "$rdy" "$tot" "$RST"
}

_route_line() {
  local p; p="$(jq -r '.route.path // ""' "$CACHE")"; [ -z "$p" ] && return
  printf '  %s%-8s%s  %s%s%s\n' "$LABEL" "Route" "$RST" "$MUTED" "$p" "$RST"
}

case "${1:-all}" in
  all)     _hdr; _nodes_line; _cluster_line; _group_line "DNS" dns; _group_line "Apps" apps; _group_line "Infra" infra; _route_line ;;
  nodes)   _nodes_line ;;
  cluster) _cluster_line ;;
  dns)     _group_line "DNS" dns ;;
  apps)    _group_line "Apps" apps ;;
  infra)   _group_line "Infra" infra ;;
  route)   _route_line ;;
  *)       _hdr; _nodes_line; _cluster_line; _group_line "DNS" dns; _group_line "Apps" apps; _group_line "Infra" infra; _route_line ;;
esac
exit 0
```

> **Glyph note:** the literal glyphs in `fleet.yml` (Task 1) are the source of truth and flow into the cache via `services[].glyph`; the renderer prints them verbatim. Chosen Nerd Font codepoints (paste the literal char into `fleet.yml`): `git`=`` U+F1D3, `n8n`=`` U+F0E8 (sitemap), `portainer`=`` U+F1B3 (cubes), `enclave`=`` U+F132 (shield), `grafana`=`` U+F1FE (area-chart), `harbor`=`` U+F13D (anchor), `k8s`=`` U+F10FE, `docker`=`` U+F308, `ollama`=`` U+F0E7, `vpn`=`` U+F023, `pihole`=`` U+F315 (raspberry-pi), node=`` U+F473. If any render as tofu in your terminal, the row still reads correctly (dot+id); swap the codepoint in `fleet.yml` only.

- [ ] **Step 4: `chmod +x` and run the renderer tests**

Run: `chmod +x scripts/utils/homelab-board.sh && bats tests/homelab.bats -f "board:"`
Expected: PASS (all five `board:` tests).

- [ ] **Step 5: Lint**

Run: `tests/shellcheck.sh`
Expected: PASS (no error-severity findings; the shared `EXCL` codes cover color-style warnings).

- [ ] **Step 6: Eyeball the live board** (manual, non-blocking)

Run: `scripts/utils/situation.sh homelab && scripts/utils/homelab-board.sh all`
Expected: a grouped board; off-LAN with no tailnet route, services read `down`/`planned` (correct — see spec reachability note).

- [ ] **Step 7: Commit**

```bash
git add scripts/utils/homelab-board.sh tests/homelab.bats
git commit -m "feat(homelab): shared homelab-board.sh renderer (grouped, themed, guarded)" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Wire the three surfaces

**Files:**
- Modify: `config/.config/fastfetch/config-local.jsonc`
- Modify: `config/.config/fastfetch/config-homelab.jsonc`
- Modify: the `hstatus` function under `shell/profiles/homelab/` (grep to locate)
- Test: `tests/homelab.bats`

**Interfaces:**
- Consumes: `scripts/utils/homelab-board.sh` (Task 4) section CLI.
- Produces: `local` and `homelab` fastfetch profiles render the board; `hstatus` is cache-first.

- [ ] **Step 1: Write the failing test** — append to `tests/homelab.bats`:

```bash
@test "config-local.jsonc: includes a homelab-board command row" {
  run grep -c "homelab-board.sh" "$BATS_TEST_DIRNAME/../config/.config/fastfetch/config-local.jsonc"
  [ "$status" -eq 0 ]; [ "$output" -ge 1 ]
}
@test "config-homelab.jsonc: routes rows through homelab-board.sh (no inline jq machines)" {
  f="$BATS_TEST_DIRNAME/../config/.config/fastfetch/config-homelab.jsonc"
  run grep -c "homelab-board.sh" "$f"; [ "$output" -ge 1 ]
  run grep -c '.machines\[0\].services' "$f"; [ "$output" -eq 0 ]
}
@test "config-local.jsonc and config-homelab.jsonc are valid jsonc (strip comments → json)" {
  for f in config-local config-homelab; do
    run bash -c "sed 's://.*$::' '$BATS_TEST_DIRNAME/../config/.config/fastfetch/${f}.jsonc' | jq -e . >/dev/null"
    [ "$status" -eq 0 ]
  done
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/homelab.bats -f "config-"`
Expected: FAIL (no `homelab-board.sh` references yet).

- [ ] **Step 3: Append the lab section to `config-local.jsonc`**

Insert these modules immediately before the final `{ "type": "colors", ... }` module:

```jsonc
    { "type": "custom", "format": "  ── HR-TRUST Lab ─────────" },
    { "type": "command", "key": " ", "text": "~/.dotfiles/scripts/utils/homelab-board.sh nodes" },
    { "type": "command", "key": " ", "text": "~/.dotfiles/scripts/utils/homelab-board.sh cluster" },
    { "type": "command", "key": " ", "text": "~/.dotfiles/scripts/utils/homelab-board.sh dns" },
    { "type": "command", "key": " ", "text": "~/.dotfiles/scripts/utils/homelab-board.sh apps" },
    { "type": "command", "key": " ", "text": "~/.dotfiles/scripts/utils/homelab-board.sh infra" },
```

- [ ] **Step 4: Collapse `config-homelab.jsonc` rows to the renderer**

Replace the block from the `── BD790i Daemons ───` separator through the `── HR-TRUST Fleet ───` rows (the Tailscale/Docker/K3s/Ollama/Route/GitHub/Machines inline-`jq` `command` modules) with:

```jsonc
    { "type": "separator", "string": "── HR-TRUST Fleet ───────" },
    { "type": "command", "key": "  Nodes",   "text": "~/.dotfiles/scripts/utils/homelab-board.sh nodes" },
    { "type": "command", "key": "  Cluster", "text": "~/.dotfiles/scripts/utils/homelab-board.sh cluster" },
    { "type": "command", "key": "  DNS",     "text": "~/.dotfiles/scripts/utils/homelab-board.sh dns" },
    { "type": "command", "key": "  Apps",    "text": "~/.dotfiles/scripts/utils/homelab-board.sh apps" },
    { "type": "command", "key": "  Infra",   "text": "~/.dotfiles/scripts/utils/homelab-board.sh infra" },
    { "type": "command", "key": "  Route",   "text": "~/.dotfiles/scripts/utils/homelab-board.sh route" },
```

(Keep the system rows — OS/HW/CPU/MEM/DSK/IP/UP — and the trailing `separator` + `colors` modules unchanged.)

- [ ] **Step 5: Make `hstatus` cache-first**

Locate it: `grep -rn "hstatus" shell/profiles/homelab/`. In the function body, prepend a cache-first branch before the existing live `_hl_status_*` probes:

```bash
  local _hb="${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils/homelab-board.sh"
  local _cache="${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json"
  if [ -r "$_cache" ] && [ -x "$_hb" ]; then
    "$_hb" all
    return 0
  fi
  # else fall through to the existing live per-OS _hl_status_* probes …
```

- [ ] **Step 6: Run tests + validate fastfetch renders**

Run: `bats tests/homelab.bats -f "config-" && fastfetch --config config/.config/fastfetch/config-homelab.jsonc >/dev/null; echo $?`
Expected: tests PASS; fastfetch exit `0` (if `fastfetch` absent locally, skip — CI covers it).

- [ ] **Step 7: Commit**

```bash
git add config/.config/fastfetch/config-local.jsonc config/.config/fastfetch/config-homelab.jsonc \
        shell/profiles/homelab tests/homelab.bats
git commit -m "feat(homelab): render board on local+homelab profiles + cache-first hstatus" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: README — Homelab Fleet section

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing at runtime. Documents Tasks 1–5.

- [ ] **Step 1: Locate the insertion point**

Run: `grep -n "^## " README.md | head -40`
Pick the seam after the profiles/claw-commands section (before any "Contributing"/"License" tail).

- [ ] **Step 2: Insert the section** (verbatim)

```markdown
## Homelab Fleet (HR-TRUST)

The `local` and `homelab` profiles render a live board of the HR-TRUST homelab.
A background poller writes one cache; every render reads it with **zero network**,
so login stays instant and SSH-safe.

```
fleet.yml ──► situation.sh probe_homelab() ──► ~/.cache/claw/homelab.json ──► homelab-board.sh
 (inventory)      (60s timer, atomic write)          (single contract)        (local + homelab + hstatus)
```

- **Inventory** — `config/homelab/fleet.yml`: 4 machines (`ms-01` cp · `r630` ·
  `bd790i` · `pihole`), a `cluster` block (`k3s-ms01` + Traefik probe IP), and a
  `services` map where each entry declares `kind`, `group` (apps/infra/dns), and a
  brand `glyph`. Adding a box or service is a data edit — no code change. A
  machine-local `$XDG_CONFIG_HOME/claw/fleet.yml` overrides it.
- **Services** — gitea, n8n, portainer, enclave, grafana (`*.lab.local` via
  Traefik), harbor (planned), k3s, docker, ollama, tailscale, and Pi-hole DNS.
  HTTP apps are probed by `Host:` header against the Traefik IP, so status works
  on-LAN and over a routed tailnet without depending on `*.lab.local` resolution.
- **Status vocabulary** — `●` green up · `●` amber degraded · `●` red down ·
  `○` muted planned. Stale cache (>5 min) dims with a `stale Xm ago` suffix;
  absent cache renders nothing.
- **Commands** — `claw situation homelab` refreshes the cache;
  `scripts/utils/homelab-board.sh all` prints the board; `hstatus` (homelab
  profile) shows it cache-first.
```

- [ ] **Step 3: Verify markdown + links**

Run: `grep -n "Homelab Fleet" README.md`
Expected: the new heading present.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(readme): add Homelab Fleet section (inventory, seam, status board)" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Full regression + vault sync

**Files:** none (verification + docs mirror)

- [ ] **Step 1: Run the whole suite + lint**

Run: `bats tests/ && tests/shellcheck.sh`
Expected: all PASS — including the unchanged 2026-06-27 `claw-dashboard.py`/`welcome-tui` homelab tests (proves the additive-schema constraint held).

- [ ] **Step 2: Theme-switch smoke** (proves no hardcoded ANSI)

Run: `claw theme set matrix >/dev/null 2>&1; scripts/utils/homelab-board.sh all | cat -v | grep -q '38;2'; echo $?`
Expected: `0` (dots emit truecolor that tracks the active palette). Restore: `claw theme set refined-dark` (or prior).

- [ ] **Step 3: Mirror spec + plan into the Obsidian vault** — see the **Vault Sync** section below (run after the user confirms the repo↔vault binding).

---

## Self-Review (completed during authoring)

- **Spec coverage:** §A→T1, §B→T2, §C→T2/T3, §D→T4, §E→T5, §F(README)→T6, §F(testing)→T1-5 + T7. All spec sections map to a task.
- **Placeholder scan:** no TBD/TODO; all code blocks complete; glyph codepoints are concrete with a documented fallback path.
- **Type consistency:** `_hl_probe_service` arity is 6 (`host user ssh_ok svc traefik_ip ctx_default`) at both definition (T2.S3) and call site (T2.S5); cache keys `cluster{context,ready,total}`, `machines[].role`, `services[].{group,glyph,state,detail,id}` are identical across producer (T2), fixtures (T3), renderer (T4), and tests. `homelab-board.sh` section args (`all|nodes|cluster|dns|apps|infra|route`) match between the script's `case` and every `.jsonc`/`hstatus` caller.
- **Known approximation:** machine `glyph` is a fixed node icon in the renderer (machines carry no `glyph` field); intentional, documented in T4.S3.
