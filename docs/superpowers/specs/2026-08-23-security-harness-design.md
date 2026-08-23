# Open Claw Security Harness — Design

**Date:** 2026-08-23
**Status:** Approved design, pre-implementation
**Author:** Henry Reed (with Claude)
**Supersedes:** nothing. **Fills:** the empty OSINT tier slot in `claude/mcp.json` (ADR-002).

---

## 1. Purpose

Expose the security toolchain to a local LLM as **typed, scope-gated, auditable tools** — so a
model running on this workstation can drive reconnaissance and web attack-surface discovery
against authorized targets, and so the same tool surface is available to Claude Code and any
other MCP client without a second implementation.

The design optimizes for one property above all: **new tooling is added declaratively.** Adding
a web recon tool is a YAML entry. Adding a flow is a YAML entry. The gate applies to both
without the author doing anything to opt in.

### Non-goals

- No web UI. No parallel `~/sec-tools` install tree — `scripts/install/security-toolchain.sh` is
  the installer.
- No autonomous exploitation chaining. TrustedSec's benchmark (4,800 runs, six local models)
  found **no local model completes multi-step exploitation**; building for it now is fiction.
- No replacement of `pre_tool_use.py`. That hook stays as an independent layer on the Bash path.

---

## 2. Evidence base

Decisions below rest on measurements taken on `bd790i` on 2026-08-23, not on recall.

| Finding | Source | Consequence |
|---|---|---|
| Local models emit clean tool calls for security tasks | Live probe: `huihui_ai/qwen3-abliterated:30b` produced correct `tool_calls` with valid enum + int args, no refusal, no preamble | The registry approach is viable; tool-calling is not the risk |
| "Typed tool interfaces alone improved penetration test agent performance by 14%" | TrustedSec benchmark | Schema quality is a bigger lever than model choice — justifies registry-first |
| Size ≠ performance; `qwen3:32b` scored worst (85.4%) *and* was 11× slower than `devstral-small-2:24b` | TrustedSec benchmark | Do not equate parameter count with capability; keep model swappable |
| No refusals observed across six stock models on offensive tasks | TrustedSec benchmark | The abliteration premium is unproven for this workload |
| `command -v` reported 4 tools present that were a Python library and 3 git aliases | Live inventory on `bd790i` | Preflight must assert binary **identity**, not presence |
| Kali packages ProjectDiscovery httpx as `httpx-toolkit` | kali.org/tools/httpx-toolkit | Package-name map is mandatory, not a nicety |

**Model selection.** Start with `huihui_ai/Qwen3.8-abliterated:27b` (18 GB, 256K context) — newest
generation, same footprint as the installed 30b, and the long context is what makes single-pass
synthesis over accumulated JSONL possible. **Gate:** re-run the tool-call probe against it before
making it the default; if abliteration degraded structured output, fall back to
`qwen3.5-abliterated:27b` or stock `qwen3.5:27b` (97.5% on the benchmark). The model is one config
value; the registry is model-agnostic by construction.

---

## 3. Architecture

```
  config/security/tools.yaml        ← declarative registry (source of truth)
  config/security/flows/*.yaml      ← declarative phase DAGs
                    │
  scripts/security/registry.py      ← the ONLY executor
    ├─ authorize()  → scope.txt, on name AND resolved address
    ├─ argv build   → list[], never a shell string
    ├─ exec         → timeout, no shell=True
    ├─ normalize    → stdout ⇒ canonical JSONL
    └─ audit        → $ENGAGEMENT_DIR/audit.jsonl
                    │
        ┌───────────┴───────────┐
  mcp_server.py            ollama_bridge.py
  (stdio MCP)              (/api/chat tools:)
        │                        │
  Claude Code, opencode    bin/pi → local model
```

### 3.1 Why the gate lives in the executor

`pre_tool_use.py` enforces scope by pattern-matching **Bash commands**. An MCP `tools/call` never
touches the Bash tool. A security MCP server with its gate in the adapter is therefore a clean
bypass around the hook already in place. Putting `authorize()` inside `registry.invoke()` means
the MCP path, the Ollama path, and every future adapter inherit identical default-deny with no
route around it.

### 3.2 Component boundaries

| Unit | Responsibility | Depends on | Testable without |
|---|---|---|---|
| `tools.yaml` | Declares tool surface. No logic. | — | everything |
| `flows/*.yaml` | Declares phase DAGs. No logic. | tools.yaml | everything |
| `scope.py` | `authorize(host, addrs, scope) → Verdict` | scope.txt | model, network |
| `registry.py` | gate → argv → exec → normalize → audit | scope.py, tools.yaml | model |
| `normalize.py` | per-tool stdout ⇒ canonical JSONL | — | model, network |
| `phases.py` | DAG execution, state markers, resume | registry | model |
| `mcp_server.py` | protocol translation only (~80 lines) | registry | model |
| `ollama_bridge.py` | agent loop only, model-agnostic | registry | — |
| `bin/pi` | CLI front door, mirrors `bin/hermes` | bridge, agents.toml | — |

---

## 4. The extension contract

This section is the spec's centre of gravity. Everything else exists to make this cheap.

### 4.1 Typed artifact vocabulary

A closed set of artifact types flows between tools:

| Type | Meaning | Produced by |
|---|---|---|
| `domain` | registrable root | engagement init |
| `hostname` | a DNS name, unresolved | passive enumeration |
| `host` | hostname + resolved addresses | resolution |
| **`authorized_host`** | **host that passed the gate** | **the gate, and only the gate** |
| `endpoint` | scheme://host:port + fingerprint | HTTP probing |
| `url` | full URL, optional params | crawling, historical mining |
| `param` | parameter name/value | crawling, fuzzing |
| `cert` | TLS certificate + SANs | TLS probing |
| `finding` | vulnerability signal | scanning |
| `secret` | credential or key material | secret scanning |
| `wordlist` | local file path | local |

### 4.2 The typing rule that enforces the gate

> A tool whose `scope_class` is `active` or `active-invasive` **may only declare**
> `consumes: [authorized_host, endpoint, url, param, wordlist]`.
>
> `hostname`, `host` and `domain` are **not** legal inputs to an active tool.

`authorized_host` is emitted by exactly one component — the gate. `endpoint`, `url` and `param`
are only producible from an `authorized_host`. Therefore an active tool is **structurally unable**
to receive an unauthorized target, and `claw sec lint` proves it statically before anything runs.

This is why extensibility is safe here: the author of a new tool does not opt into the gate, and
cannot opt out of it. The type of their input decides.

### 4.3 Adding a tool — the whole procedure

```bash
claw sec tool new katana        # scaffolds a stub, probes --help, opens $EDITOR
claw sec lint                   # schema + type check
claw sec doctor katana          # binary identity assertion
```

```yaml
# config/security/tools.yaml
katana:
  description: >-              # LLM-facing. This text is the 14% lever — write it for the model.
    Crawl a live web endpoint and enumerate reachable routes, JavaScript-referenced
    endpoints, and form parameters. Use after fingerprinting, before fuzzing.
  binary: katana
  scope_class: active
  consumes: [endpoint]
  emits: [url, param]
  packages:
    kali: katana
    debian: "go:github.com/projectdiscovery/katana/cmd/katana@latest"
    darwin: katana
  verify: ["katana", "-version"]
  expect: "projectdiscovery"
  argv:                          # flat list; {braces} are typed slots, never interpolated strings
    - "-list"
    - "{input_file}"
    - "-json"
    - "-jc"
    - "-depth"
    - "{depth}"
    - "-concurrency"
    - "{concurrency}"
  params:
    depth:       { type: integer, default: 3,  min: 1, max: 6 }
    concurrency: { type: integer, default: 10, min: 1, max: 50 }
  parser: jsonl
  timeout: 900
  needs_root: false
```

**No Python was written.** The MCP `tools/list` entry, the Ollama tool schema, the argv builder,
the gate binding, and four conformance tests are all generated from this.

### 4.4 Adding a flow

```yaml
# config/security/flows/webrecon.yaml
name: webrecon
description: Authorized web application attack-surface discovery
phases:
  - { id: 0, name: init,      scope_class: local,   emits: [domain] }
  - { id: 1, name: passive,   tools: [subfinder, gau, amass_intel], emits: [hostname, url] }
  - { id: 2, name: resolve,   tools: [dnsx],        consumes: [hostname], emits: [host] }
  - { id: 3, name: gate,      gate: true,           consumes: [host], emits: [authorized_host] }
  - { id: 4, name: live,      tools: [naabu, httpx, tlsx], consumes: [authorized_host],
              emits: [endpoint, cert], feeds_back_to: 3 }
  - { id: 5, name: content,   tools: [wafw00f, katana, ffuf], consumes: [endpoint], emits: [url, param] }
  - { id: 6, name: signal,    tools: [nuclei, dalfox, testssl], consumes: [endpoint, url], emits: [finding] }
  - { id: 7, name: synthesis, scope_class: local,   consumes: [finding], emits: [report] }
```

`claw sec lint` verifies every phase's `consumes` is produced by an ancestor, that exactly one
phase declares `gate: true`, and that no `active` phase is reachable from the DAG root without
passing through it.

### 4.5 Normalizers — the only place Python is ever required

Named parser registry: `jsonl`, `json`, `lines`, `kv`, `nmap-xml`, `regex:<name>`, `py:<module>`.
Modern tooling needs `jsonl` and zero code. A tool with idiosyncratic output adds one function to
`normalize.py` and references it as `parser: py:my_parser`. This is the *only* extension path that
touches code, and it is deliberately narrow.

### 4.6 Generated conformance tests

Every registry entry automatically yields four tests — so adding a tool adds its own coverage and
the surface cannot rot:

1. **Identity** — binary runs and its version string matches `expect`.
2. **Schema** — entry validates against the registry JSON schema.
3. **Argv** — dry-run argv build against fixture params produces a stable snapshot.
4. **Denial** — invoking the tool with an out-of-scope target returns `Verdict.DENY`.

Test 4 is the safety regression suite. It grows automatically with the tool surface.

---

## 5. Scope semantics

```
local            no target                    → no gate
passive          third-party data only        → logged, not gated
active-light     non-intrusive fingerprinting → gated
active           scanning / fuzzing           → gated + rate-limit + audit
active-invasive  exploitation                 → gated + per-engagement opt-in;
                                                NEVER exposed to the agent loop by default
```

### 5.1 Authorization is on the resolved address

Gating on the domain is the industry norm and it is wrong. `status.acme.com` CNAMEs to a status
vendor; `shop.acme.com` resolves into Shopify; `cdn.acme.com` is Fastly. Scanning them is scanning
a third party who never signed the authorization.

```python
def authorize(host: str, addrs: list[str], scope: Scope) -> Verdict:
    if not scope.name_allows(host):
        return Verdict.DENY("name not in scope.txt", propose=host)

    stray = [a for a in addrs if not scope.addr_allows(a)]
    if stray:                                   # one stray address denies the host
        return Verdict.DENY(f"resolves off-scope: {stray}", propose=stray)

    if scope.denied(host, addrs):               # explicit deny beats any allow
        return Verdict.DENY("explicit deny entry", propose=None)

    return Verdict.ALLOW
```

A `DENY` returns **structured text the model can read**, carrying a ready-to-paste `/scope`
amendment. Refusals are reported, never silently dropped — a control that is invisible is a
control people learn to route around.

### 5.2 Invasive tools are invisible, not refused

`active-invasive` entries are filtered out of `tools/list` and the Ollama tool schema unless the
operator sets the per-engagement opt-in. The agent cannot call a tool it cannot see — strictly
stronger than seeing it and being told no.

### 5.3 Scope snapshot

Phase 0 hashes and copies `scope.txt` into the engagement. The report can prove which allowlist
was in force, and a mid-run edit invalidates the run rather than silently widening it.

---

## 6. Tool inventory

Selection criterion: **JSONL-native output is first-class.** An LLM loop consumes structured data;
prose-only tools need a parser and burn context.

### Tier 0 — recon → web chain

`subfinder` (passive) · `dnsx` (passive) · `tlsx` (active-light) · `naabu` (active) · `httpx`
(active) · `katana` (active) · `nuclei` (active) · `interactsh-client` (infra) · `notify` (local)

### Tier 1 — web application depth

`ffuf` · `feroxbuster` · `dalfox` · `wafw00f` (active-light) · `testssl.sh` (active-light) ·
`nikto` / `whatweb` (active-light, text output) · `sqlmap` (**active-invasive**)

### Tier 2 — passive OSINT

`amass intel` · `theHarvester` · `gau` + `waybackurls` (highest-yield web surface source) ·
`shodan` / `censys` · `trufflehog` + `gitleaks`

### Tier 3 — glue, exposed as registry primitives

`anew` · `unfurl` · `qsreplace` · `gf`. The model calls `dedupe(list)` by name and never composes
a pipeline — this removes shell injection from the agent path rather than filtering for it.

### Already present on `bd790i`

`garak 0.15.1`, `inspect-ai 0.3.239` (pipx), plus the Playwright MCP — a real webapp recon
primitive for authenticated crawling that `katana` cannot reach behind a login.

### Reference MCP servers — mine for schemas, do not adopt

`0x4m4/hexstrike-ai` (150+ tools; injection validation and whitelisting, **no scope gate**) ·
`openbashok/pentest-mcp` · `gokulapap/bugbounty-mcp-server` · `chfle/Pentest-MCP-Server`.
None enforce target authorization, and HexStrike's fork proliferation is a supply-chain smell on
something granted shell execution.

---

## 7. Kali provisioning

Three of these fail **quietly**, producing an empty result set that reads as "clean target."

| Tool | Kali package | Trap |
|---|---|---|
| `httpx` | `httpx-toolkit` | Name collision — `apt`/`pipx install httpx` installs the Python HTTP client and shadows the binary. Observed on `bd790i`. |
| `seclists` | `seclists` | Installs to `/usr/share/seclists` with a lowercase symlink; the security profile's `WORDLISTS` default is capitalized `SecLists`. **Verify on target; fix in `security/linux.zsh`.** |
| `naabu` | `naabu` | Needs `libpcap-dev` + `CAP_NET_RAW`; silently degrades to connect scan otherwise. |
| `nuclei` | `nuclei` | Apt templates lag upstream — `-update-templates` is mandatory in Phase 0. |
| `subfinder` | `subfinder` | Yield collapses without `provider-config.yaml` API keys. Fails open and quiet. |
| `katana` | `katana` | Headless pulls Chromium on first run. |

Preflight asserts **identity**, never presence — `command -v` found four false positives here.

---

## 8. Spine wiring

| Surface | Change |
|---|---|
| `bin/claw` | `sec)` → `scripts/security/sec.sh`; subcommands `tools · flows · run · doctor · lint · scope · tool new · mcp` |
| `bin/pi` | New agent front door, mirrors `bin/hermes` (`--serve`, `--model`) |
| `~/.config/claw/agents.toml` | `claw agent add pi` → `profile = "security"` |
| `claude/mcp.json` | Register `claw-sec` stdio server — fills the ADR-002 OSINT tier slot |
| `shell/profiles/security/common.zsh` | `pi`, `wr` aliases; `sec-help` rows; guarded on `command -v` |
| `shell/profiles/security/meta.zsh` | Extend `PROFILE_KEY_TOOLS` with the Tier 0 chain |
| `scripts/install/security-toolchain.sh` | Add Tier 0/1 with the Kali package map |
| `claw validate` | Harness readiness rows (registry lint, doctor, MCP reachability) |
| `claude/harness/skills/webrecon/` | Skill teaching Claude Code to drive the flow; deployed by `link-claude.sh` |
| `config/integrity/manifest.sha256` | Regenerate after implementation |

**Invariants respected:** one dispatcher (`claw sec` routes through `bin/claw`, no second `claw()`);
one theme engine (all output consumes `CLAW_C_*` with refined-dark fallbacks); one render path
(no new dashboard). Nothing is superseded, so `legacy/` is untouched.

---

## 9. Testing strategy

No live scanning in CI, ever.

| Layer | Test | Notes |
|---|---|---|
| `scope.py` | Table-driven `authorize()` against fixture scope files | Highest-value surface. Cases: CNAME to third party, wildcard, explicit deny, partial address match, IPv6, one-stray-address-denies |
| `tools.yaml` | Schema validation + type-rule check | Fails the build if an `active` tool consumes `hostname` |
| `flows/*.yaml` | DAG lint — ancestry, single gate, no active path bypassing it | Static |
| `registry.py` | Argv snapshot tests; `shell=True` grep assertion | No exec |
| `normalize.py` | Golden fixtures of real tool output → canonical JSONL | Captured once, replayed |
| `mcp_server.py` | `tools/list` golden; invasive-filtering assertion | No model |
| `ollama_bridge.py` | Recorded transcript replay | No model |
| Integration | Full flow `--dry-run` against fixtures, asserting **no `active` tool ever receives a target absent from `in-scope.txt`** | The safety regression test |

`bats` is not installed on `bd790i` — shell-level tests follow the existing `tests/*.test.sh`
pattern; Python layers use `pytest`.

---

## 10. Agent boundaries

**Decides:** passive source selection · wordlist and concurrency from fingerprint + WAF verdict ·
nuclei template sets · whether a discovered SAN warrants re-gating · finding correlation and
exploitability ranking · when the surface is exhausted.

**Structurally unable to:** compose a shell string (argv is a fixed template with typed slots) ·
name a target outside the gate's output (type system) · see an `active-invasive` tool without
opt-in (filtered from `tools/list`) · read or write `scope.txt` · skip the gate on a mid-run
discovery (`feeds_back_to`) · suppress an audit record (the executor writes it, not the caller).

None of these are enforced by prompting.

---

## 11. Build order

1. `scope.py` + its test table. Nothing else is safe to build first.
2. Registry schema, `tools.yaml` for the Tier 0 chain, `claw sec lint`.
3. `registry.py` — gate, argv, exec, normalize, audit. Generated conformance tests.
4. `claw sec doctor` + `kali-packages.yaml` identity assertions.
5. `phases.py` + `flows/webrecon.yaml`; `--dry-run` integration test.
6. `mcp_server.py`; register in `claude/mcp.json`; verify from Claude Code.
7. `ollama_bridge.py` + `bin/pi`; probe model tool-call fidelity; register in `agents.toml`.
8. Toolchain, profile surface, `claw validate` rows, `webrecon` harness skill.
9. Regenerate integrity manifest.

Steps 1–4 deliver a gated, testable tool surface with no model involved. That is the checkpoint
worth reaching before anything agentic runs.

---

## Appendix — companion artifact

The `webrecon` flow is documented visually at the Kali Recon Orchestrator artifact:
`https://claude.ai/code/artifact/bf35bfdd-ef05-4452-a93e-04c4170f8c17`
