# Backlog — Backend / Tooling Layer

> **Status:** partially shipped (see "Done this pass"). Remainder is future work.
> **Scope:** the non-visual AI/infra/tooling stack for the Blackwell AI workstation.
> Distinct from the [desktop/visual backlog](./desktop-visual-backlog.md).

## Done this pass (extended `scripts/install/ai-workstation-toolchain.sh`)

- ✅ **NVIDIA OpenShell** — kernel-isolated agent sandbox. Installed via
  `uv tool install -U openshell` (clean, no piped shell). Seeds a deny-by-default
  policy at `config/agentic/openshell/policy.yaml`.
- ✅ **NemoClaw** — documented opt-in install (Hermes agent via `NEMOCLAW_AGENT=hermes`).
  Not auto-piped: NVIDIA's installer URL isn't pinned publicly, so we follow the
  repo's "don't pipe an unverified installer" stance.
- ✅ **Nemotron 3 Nano Omni** — vLLM launcher at `config/ai/serve-nemotron-omni.sh`,
  tuned for RTX PRO Blackwell (`--moe-backend triton`, `--reasoning-parser nemotron_v3`).
  Flags `--agentic-only`, `--skip-agentic`, `--skip-data` added.
- ✅ **RAPIDS cuDF / cuOpt** + **Milvus** — documented install recipes (heavy
  wheels/containers printed, not auto-pulled).

Already present before this pass: `uv`, vLLM, NVIDIA k8s-device-plugin (v0.17.0),
OpenTofu, Qdrant, CUDA 12.8 / cuDNN, Anthropic SDK, Claude Code.

## Roadmap (phased)

### Phase 1 — Agentic runtime base ✅ (done this pass)
OpenShell installed & CLI-verified (`0.0.52`, `doctor check` green, Docker 29.5.2),
Nemotron launcher committed, policy template seeded, install flags wired.

---

### Phase 2 — OpenShell gateway bring-up (NEXT)
`sandbox`/`policy` commands are no-ops without an active **gateway** (the control
plane). `gateway` subcommands are `add | select | login | list | info` — i.e. you
register an *existing* endpoint; the gateway itself is a server you run.

**Tooling shipped:** `scripts/utils/openshell-gateway.sh`
(`check | register | status | sandbox | deploy-cluster`) — wraps the verified
client commands and injects the repo policy on `sandbox create`.

- [ ] **Decide where the gateway runs:** local-on-this-box (quickstart) vs on the
      homelab K3s cluster via Helm (`oci://ghcr.io/nvidia/openshell/helm-chart` —
      `deploy-cluster` subcommand, ⚠ chart values still need verifying).
      Cluster-hosted is preferred long-term so sandboxes land on the GPU node.
- [ ] Stand up a gateway, then `openshell-gateway.sh register <endpoint> homelab`
      (does `gateway add` + `select` + a `sandbox list` smoke check).
- [ ] **Reconcile the real policy schema:** `openshell policy get --global --full -o json`
      → rewrite `config/agentic/openshell/policy.yaml` to the authoritative schema,
      then `openshell policy prove <sandbox>` to validate properties.
- [ ] First sandbox: `openshell-gateway.sh sandbox create -- claude` (auto-injects
      `--gpu --policy …`); confirm `nvidia-smi` works *inside* the sandbox.
- [ ] Wire into the repo: `claw` alias + welcome-TUI entry; persist the endpoint
      via `OPENSHELL_GATEWAY=<name>` in `~/.dotfiles/.env`.

---

### Phase 3 — Homelab K3s GPU node (enable this Blackwell box as a worker)
**Goal:** join this box to the existing homelab K3s **server** as a GPU **agent**,
and make the RTX PRO 4000 Blackwell schedulable as `nvidia.com/gpu`.
**Current state (this box):** K3s absent · `nvidia-container-toolkit 1.19.1` present ·
driver R580 · server lives on another host.

**Tooling shipped:**
- `homelab-toolchain.sh --agent --server <url> --token-file <path>` — join as a
  GPU worker (auto-labels `nvidia.com/gpu.present=true`, token never hits ps/history).
- `config/k3s/gpu/{runtimeclass-nvidia,nvidia-device-plugin,gpu-test-pod}.yaml` —
  version-controlled manifests (device plugin pinned `v0.17.0`, nodeAffinity-gated
  to GPU nodes).
- `scripts/utils/k3s-gpu-enable.sh [--test --taint]` — **server-side** half: applies
  the manifests, labels/taints, verifies capacity, runs the smoke pod.

- [x] **(code gap) agent-join in `homelab-toolchain.sh`** — done.
- [x] **Commit GPU manifests** + nodeAffinity-gate to GPU nodes — done.
- [x] **Split server-side vs agent-side** — `k3s-gpu-enable.sh` (server) vs the
      agent-side runtime config in `ai-workstation-toolchain.sh` — done.
- [x] **Label + taint** GPU nodes — handled by join (label) + `--taint` flag.
- [x] **Verify scheduling** — `k3s-gpu-enable.sh --test` + `gpu-test-pod.yaml`.
- [ ] **Inputs required (to actually run):** server API URL `https://<server>:6443`
      + node token from the server's `/var/lib/rancher/k3s/server/node-token`.
- [ ] Join this box as an agent; confirm from the server: `kubectl get nodes -o wide`.
- [ ] **(agent-side, on this box after join)** `ai-workstation-toolchain.sh
      --inference-only --skip-agentic --skip-data` to configure the nvidia
      containerd runtime; restart `k3s-agent`.
- [ ] **(server-side)** `claw gpu --test` to apply + verify.
- [x] **Serve on-cluster (manifest):** `config/k3s/serving/nemotron-omni-vllm.yaml`
      — Namespace + PVC (80Gi HF cache) + Deployment (`nvidia.com/gpu: 1`,
      `runtimeClassName: nvidia`, NVFP4 model, `/dev/shm`, health probes) + Service.
      Apply after the GPU node is live + an `hf-token` secret exists.
- [ ] Route OpenShell gateway / NemoClaw inference at `nemotron-omni.ai-serving:8000`.

**CLI surface:** `claw gpu` → `k3s-gpu-enable.sh`, `claw gateway` →
`openshell-gateway.sh`, `claw install ai-workstation --agentic-only` (extra args
pass through). All in `claw help` under "AI Workstation".

---

### Later / unsequenced — agentic hardening
- [ ] Verify & pin NemoClaw's real installer URL; promote to a guarded auto-install.
- [ ] Tighten the OpenShell policy per profile (security vs ai vs cloud).
- [ ] Hermes integration: confirm `nemohermes` lines up with existing `hermes.sh`.

### Local inference / models
- [x] **vLLM verified working** on this box (0.22.0). A live `nvidia/Qwen3-8B-NVFP4`
      server (`--quantization modelopt --kv-cache-dtype fp8`) on :8000 returned a
      valid completion; EngineCore resident at ~19.7GB on the Blackwell.
- [x] **Aligned launcher + serving manifest to the proven NVFP4 config** —
      added `--quantization modelopt` (overridable via `QUANT=`/`QUANT=""`).
- [ ] **Persist the running server:** it's ad-hoc (no systemd unit) → won't
      survive reboot. Add a `--user` unit (or k8s Deployment once the node joins).
- [ ] Investigate the pre-existing `:8001` listener (unidentified; left untouched).
- [ ] Confirm the NVFP4 Nemotron variant repo id (24GB-friendly) once published;
      default the launcher to it on a detected 24GB card.
- [ ] Optional NIM container path for Nemotron (NGC) as an alternative to vLLM.
- [ ] TensorRT-LLM / SGLang serving variants for max Blackwell throughput.

### RAG / data
- [ ] First-class Milvus-vs-Qdrant decision for local RAG over the Obsidian vault.
- [ ] GPU-accelerated embedding + knowledge-graph build pipeline (cuDF/cuVS).
- [ ] Expose cuDF/cuOpt to agents as registered "skills" (not just installed libs).

### Infra-as-code
- [ ] OpenTofu modules that declare the whole workstation stack (driver, K3s,
      device plugin, vLLM/NIM services) reproducibly.
- [ ] DCGM exporter → Prometheus/Grafana dashboards for GPU telemetry.

### Tooling-system improvements
- [x] `claw doctor ai` readiness check (`scripts/utils/ai-readiness.sh`, `--deep`
      runs container GPU passthrough). Current box: 8 pass / 3 warn (warns are all
      pre-SSH: vLLM, gateway, cluster) / 0 fail.
- [ ] **Reconcile CUDA pins:** this box runs **CUDA 13.3 + driver R580**, but
      `ai-workstation-toolchain.sh` still pins **CUDA 12.8 + nvidia-open-570**.
      Update the installer (or gate `--driver-only` to skip when a newer stack is
      present) so it can't downgrade a working box. The serving manifest's CUDA-13
      vLLM image is already correct for R580.
- [ ] Integrity-manifest coverage for new `config/ai/`, `config/agentic/`,
      `config/k3s/` assets.
- [ ] Master-setup / onboarding entries for the agentic runtime layer.
