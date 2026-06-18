#!/usr/bin/env bash

################################################################################
# AI Workstation Toolchain — Blackwell-optimized (Linux only)
#
# Target hardware: NVIDIA Blackwell GPUs (RTX PRO 4000/6000 Blackwell, RTX 5090,
# B100/B200). Defaults are tuned for RTX PRO 4000 (24GB GDDR7, 8960 CUDA cores,
# 5th-gen Tensor cores with FP4 Transformer Engine).
#
# Stack:
#   - NVIDIA driver R570+ (Blackwell requires R570 or later)
#   - CUDA Toolkit 12.8 (first release with full Blackwell + FP4 support)
#   - cuDNN 9.7+
#   - nvidia-container-toolkit (Docker/K3s GPU passthrough)
#   - K3s NVIDIA device plugin (DaemonSet)
#   - Local inference: vLLM, llama.cpp CUDA, Ollama (auto-GPU)
#   - Serving helper: config/ai/serve-nemotron-omni.sh (Nemotron 3 Nano Omni,
#     multimodal 30B-A3B MoE — vLLM tuned for RTX PRO Blackwell)
#   - Agentic runtime: NVIDIA OpenShell (kernel-isolated agent sandbox) +
#     NemoClaw (self-evolving "claw" orchestration on top of OpenShell)
#   - GPU data (CUDA-X): RAPIDS cuDF / cuOpt skills, Milvus GPU vector DB
#   - Monitoring: nvtop, gpustat, nvitop, NVIDIA DCGM exporter
#   - Profiling: NVIDIA Nsight Systems, py-spy, scalene
#
# Flags:
#   --driver-only        install only the driver + CUDA toolkit, skip the rest
#   --inference-only     assume driver/CUDA already work, install vLLM/llama.cpp/etc.
#   --agentic-only       install only the OpenShell + NemoClaw runtime layer
#   --skip-k3s           don't install the K3s device plugin
#   --skip-agentic       don't install the OpenShell / NemoClaw agentic runtime
#   --skip-data          don't print/install the RAPIDS (cuDF/cuOpt) + Milvus stack
#   --skip-reboot-prompt skip the post-driver-install reboot prompt
#   --dry-run            print actions without executing
#   --help
#
# Post-install: ALWAYS run `nvidia-smi` to verify driver loaded. If the kernel
# module fails to build (DKMS), `sudo dmesg | grep -i nvidia` is the next step.
################################################################################

# pipefail so a failed `curl` in a `curl | gpg --dearmor` keyring import is not
# masked by gpg's success — matches lib/toolchain-runner.sh's convention.
set -eo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"

# ── Flag parsing (before OS gate so --help works on Mac) ──
INSTALL_DRIVER=true
INSTALL_INFERENCE=true
INSTALL_K3S_PLUGIN=true
INSTALL_MONITORING=true
INSTALL_AGENTIC=true
INSTALL_DATA=true
PROMPT_REBOOT=true
DRY_RUN=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --driver-only)        INSTALL_INFERENCE=false; INSTALL_AGENTIC=false; INSTALL_DATA=false ;;
        --inference-only)     INSTALL_DRIVER=false ;;
        --agentic-only)       INSTALL_DRIVER=false; INSTALL_INFERENCE=false
                              INSTALL_K3S_PLUGIN=false; INSTALL_MONITORING=false; INSTALL_DATA=false ;;
        --skip-k3s)           INSTALL_K3S_PLUGIN=false ;;
        --skip-agentic)       INSTALL_AGENTIC=false ;;
        --skip-data)          INSTALL_DATA=false ;;
        --skip-reboot-prompt) PROMPT_REBOOT=false ;;
        --dry-run)            DRY_RUN=true ;;
        --help|-h)
            awk '
                NR == 1 && /^#!/    { next }
                /^####*$/           { next }
                /^# / || /^#$/      { sub(/^# ?/, ""); print; next }
                NF == 0             { print ""; next }
                { exit }
            ' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) log_error "Unknown flag: $1"; exit 1 ;;
    esac
    shift
done

detect_os

# ── Gate: Linux only ─────────────────────────────────────
if [[ "$OS_TYPE" == "macos" ]]; then
    log_error "AI workstation toolchain is Linux-only (Blackwell + CUDA + K3s)"
    log_info  "On macOS, use MLX (Apple Silicon) — Blackwell drivers don't exist for macOS"
    exit 1
fi
if [[ "$PKG_MANAGER" != "apt" ]]; then
    log_warning "Only apt path is supported right now (Ubuntu/Debian/Parrot/Kali)"
    log_warning "On $PKG_MANAGER, install NVIDIA driver + CUDA from your distro's docs, then re-run with --inference-only"
    [[ "$INSTALL_DRIVER" == "true" ]] && exit 1
fi

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf '  [DRY] %s\n' "$*"
    else
        eval "$@"
    fi
}

# Helper: does nvidia-smi work and return a Blackwell device?
gpu_visible() {
    command -v nvidia-smi &>/dev/null && nvidia-smi -L 2>/dev/null | grep -q 'GPU '
}

# Capability string (e.g. "sm_120" for Blackwell, "sm_89" for Ada)
gpu_compute_cap() {
    command -v nvidia-smi &>/dev/null || return 1
    nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1
}

log_info "── AI Workstation install (OS: $OS_TYPE, pkg: $PKG_MANAGER) ──"
gpu_visible && log_success "GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)" \
    || log_info "No working GPU yet — driver install will fix this"

# ─────────────────────────────────────────────
# 1. NVIDIA driver + CUDA 12.8 via NVIDIA's own APT repo
# ─────────────────────────────────────────────
install_driver_and_cuda() {
    [[ "$INSTALL_DRIVER" == "false" ]] && { log_info "skip: driver/CUDA install"; return 0; }

    log_info "Installing NVIDIA driver R570 + CUDA Toolkit 12.8..."
    # Choose repo based on Ubuntu version. NVIDIA publishes per-distro repos at:
    #   https://developer.download.nvidia.com/compute/cuda/repos/<distro>/<arch>/
    local distro_id arch
    . /etc/os-release
    case "$VERSION_ID" in
        24.04) distro_id="ubuntu2404" ;;
        22.04) distro_id="ubuntu2204" ;;
        20.04) distro_id="ubuntu2004" ;;
        *)
            # Parrot/Kali piggyback on Debian — use the Debian repo
            distro_id="debian12"
            log_warning "Detected $ID $VERSION_ID — using debian12 repo (may need manual adjustment)"
            ;;
    esac
    arch=$(uname -m)
    [[ "$arch" == "x86_64" ]] && arch="x86_64"

    local repo_url="https://developer.download.nvidia.com/compute/cuda/repos/${distro_id}/${arch}"
    local pin_file="cuda-${distro_id}.pin"

    # Pin file ensures the NVIDIA repo wins over Ubuntu's older nvidia packages
    run "wget -qO /tmp/$pin_file '${repo_url}/cuda-${distro_id}.pin'"
    run "sudo mv /tmp/$pin_file /etc/apt/preferences.d/cuda-repository-pin-600"

    # Keyring
    run "wget -qO /tmp/cuda-keyring.deb '${repo_url}/cuda-keyring_1.1-1_all.deb'"
    run "sudo dpkg -i /tmp/cuda-keyring.deb"

    run "sudo apt-get update -qq"

    # Driver branch — open-source kernel modules (required for Blackwell on kernel 6.6+).
    # The "open" variant uses the GPL-compatible kernel module Nvidia upstreamed.
    log_info "Installing nvidia-open-570 (open kernel modules — required for Blackwell)..."
    run "sudo apt-get install -y nvidia-open-570 cuda-drivers-570"

    # CUDA Toolkit 12.8 (full toolkit — includes nvcc, libraries, samples)
    log_info "Installing CUDA Toolkit 12.8..."
    run "sudo apt-get install -y cuda-toolkit-12-8"

    # cuDNN 9.x (Blackwell-aware)
    log_info "Installing cuDNN 9..."
    run "sudo apt-get install -y libcudnn9-cuda-12 libcudnn9-dev-cuda-12"

    # NCCL — multi-GPU comms (also useful with K3s GPU sharing)
    run "sudo apt-get install -y libnccl2 libnccl-dev"

    # Append CUDA paths to /etc/profile.d so all shells see them after reboot
    log_info "Writing /etc/profile.d/cuda.sh..."
    run "echo 'export PATH=/usr/local/cuda-12.8/bin:\$PATH' | sudo tee /etc/profile.d/cuda.sh >/dev/null"
    run "echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:\$LD_LIBRARY_PATH' | sudo tee -a /etc/profile.d/cuda.sh >/dev/null"
    run "sudo chmod +x /etc/profile.d/cuda.sh"

    log_success "Driver + CUDA install commands queued."
    if [[ "$PROMPT_REBOOT" == "true" && "$DRY_RUN" == "false" ]]; then
        log_warning "REBOOT REQUIRED before GPU is usable."
        printf "\n  Reboot now? [y/N] "
        read -r reply
        [[ "$reply" == "y" || "$reply" == "Y" ]] && sudo reboot
    fi
}

# ─────────────────────────────────────────────
# 2. nvidia-container-toolkit — host-level Docker/containerd GPU support
# ─────────────────────────────────────────────
install_container_toolkit() {
    # Pure --agentic-only / --skip-data layering onto an already-set-up box
    # shouldn't reconfigure the Docker runtime and bounce the daemon.
    if [[ "$INSTALL_DRIVER" == "false" && "$INSTALL_INFERENCE" == "false" ]]; then
        log_info "skip: container toolkit (runtime-layer-only run)"
        return 0
    fi
    if command -v nvidia-ctk &>/dev/null; then
        log_info "nvidia-container-toolkit already installed ($(nvidia-ctk --version 2>&1 | head -1))"
    else
        log_info "Installing nvidia-container-toolkit..."
        run "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
        run "curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null"
        run "sudo apt-get update -qq"
        run "sudo apt-get install -y nvidia-container-toolkit"
    fi

    # Configure Docker runtime (if docker is present)
    if command -v docker &>/dev/null; then
        log_info "Configuring docker to use nvidia runtime..."
        run "sudo nvidia-ctk runtime configure --runtime=docker"
        run "sudo systemctl restart docker"
    fi

    # Configure containerd (used by K3s) — different config path
    if [[ -d /var/lib/rancher/k3s ]]; then
        log_info "Configuring K3s containerd to use nvidia runtime..."
        # K3s reads /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
        # nvidia-ctk knows how to patch it if pointed at the right config.
        local k3s_tmpl="/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl"
        if [[ ! -f "$k3s_tmpl" ]]; then
            # K3s autogenerates config.toml from this template if it exists.
            # Seed it with the current generated config so our patch survives.
            run "sudo cp /var/lib/rancher/k3s/agent/etc/containerd/config.toml '$k3s_tmpl' 2>/dev/null || true"
        fi
        run "sudo nvidia-ctk runtime configure --runtime=containerd --config='$k3s_tmpl' --set-as-default"
        run "sudo systemctl restart k3s"
    fi
}

# ─────────────────────────────────────────────
# 3. K3s NVIDIA device plugin (DaemonSet) + RuntimeClass
# ─────────────────────────────────────────────
install_k3s_gpu_plugin() {
    [[ "$INSTALL_K3S_PLUGIN" == "false" ]] && { log_info "skip: K3s device plugin"; return 0; }
    if [[ ! -d /var/lib/rancher/k3s ]]; then
        log_info "K3s not detected — skipping device plugin install (run claw install homelab first)"
        return 0
    fi
    if ! command -v kubectl &>/dev/null; then
        log_warning "kubectl not on PATH — install via claw install devops, then re-run --inference-only"
        return 0
    fi

    log_info "Applying NVIDIA RuntimeClass + device plugin DaemonSet to K3s..."

    # Manifests are version-controlled in config/k3s/gpu/ (no longer generated
    # inline). For multi-node clusters prefer the dedicated server-side helper —
    # scripts/utils/k3s-gpu-enable.sh — which also labels/taints and verifies.
    local manifest_dir="$DOTFILES_DIR/config/k3s/gpu"
    if [[ ! -f "$manifest_dir/nvidia-device-plugin.yaml" ]]; then
        log_error "Missing $manifest_dir/nvidia-device-plugin.yaml — checkout incomplete?"
        return 1
    fi

    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    run "kubectl apply -f '$manifest_dir/runtimeclass-nvidia.yaml'"
    run "kubectl apply -f '$manifest_dir/nvidia-device-plugin.yaml'"

    log_success "Device plugin applied. Verify with: kubectl describe node | grep nvidia.com/gpu"
}

# ─────────────────────────────────────────────
# 4. Monitoring + profiling — nvtop, gpustat, nvitop, dcgm-exporter, nsight
# ─────────────────────────────────────────────
install_monitoring() {
    [[ "$INSTALL_MONITORING" == "false" ]] && { log_info "skip: monitoring tools"; return 0; }
    log_info "Installing GPU monitoring tools..."
    run "sudo apt-get install -y nvtop"

    if command -v pipx &>/dev/null; then
        for tool in gpustat nvitop py-spy scalene; do
            log_info "Installing $tool via pipx..."
            run "pipx install '$tool' 2>/dev/null || pipx upgrade '$tool' 2>/dev/null || true"
        done
    else
        log_warning "pipx missing — skipping gpustat/nvitop/py-spy (run packages/dev-tools.sh first)"
    fi

    # DCGM exporter (Prometheus metrics) — only if user has Prometheus/Grafana
    log_info "DCGM exporter container: nvcr.io/nvidia/k8s/dcgm-exporter:3.3.7-3.5.0-ubuntu22.04"
    log_info "  Apply with: kubectl apply -f https://github.com/NVIDIA/dcgm-exporter/raw/main/dcgm-exporter.yaml"

    # Nsight Systems — system-wide GPU profiling. Big install (~500 MB), gate behind flag later.
    log_info "Optional: NVIDIA Nsight Systems (system profiler) — install with:"
    log_info "  sudo apt-get install -y nsight-systems-cli"
}

# ─────────────────────────────────────────────
# 5. Inference stack — vLLM, llama.cpp CUDA, Ollama, TGI
# ─────────────────────────────────────────────
install_inference_stack() {
    [[ "$INSTALL_INFERENCE" == "false" ]] && { log_info "skip: inference stack"; return 0; }

    if ! gpu_visible; then
        log_warning "GPU not visible (nvidia-smi failing) — install inference stack anyway, but it'll fall back to CPU"
        log_warning "Reboot and re-run if you just installed the driver."
    fi

    # vLLM — high-throughput LLM serving with PagedAttention. Needs CUDA 12.x + PyTorch 2.6+.
    if command -v pipx &>/dev/null; then
        # vLLM via pipx is fragile (massive deps); use uv if available, else pip in a venv.
        if command -v uv &>/dev/null; then
            log_info "Installing vLLM via uv..."
            run "uv tool install vllm --python 3.12"
        else
            log_info "Creating vLLM venv at ~/.ai/vllm..."
            run "python3 -m venv ~/.ai/vllm"
            run "~/.ai/vllm/bin/pip install --upgrade pip"
            run "~/.ai/vllm/bin/pip install vllm"
            log_info "Launch with: source ~/.ai/vllm/bin/activate && vllm serve <model>"
        fi
    fi

    # llama.cpp with CUDA backend — best for quantized inference, beats vLLM on low VRAM
    if command -v brew &>/dev/null; then
        log_info "Installing llama.cpp (CUDA build) via brew..."
        run "brew install llama.cpp"
        log_warning "Note: brew's llama.cpp is CPU-only. For CUDA, build from source:"
        log_warning "  git clone https://github.com/ggerganov/llama.cpp && cd llama.cpp && cmake -B build -DGGML_CUDA=ON && cmake --build build --config Release -j"
    else
        log_info "llama.cpp: build from source for CUDA backend (no apt package with GPU support)"
    fi

    # llama-swap — one OpenAI endpoint that hot-swaps models + frees VRAM on TTL.
    # Distributed as prebuilt Go binaries (release tags like v228 aren't valid Go
    # module semver, so `go install` won't take them — fetch the release asset).
    if command -v llama-swap &>/dev/null; then
        log_info "llama-swap present ($(llama-swap --version 2>&1 | head -1))"
    else
        local lsver="v228"
        log_info "Installing llama-swap $lsver → ~/.local/bin ..."
        run "curl -sL -o /tmp/llama-swap.tgz 'https://github.com/mostlygeek/llama-swap/releases/download/${lsver}/llama-swap_${lsver#v}_linux_amd64.tar.gz'"
        run "tar xzf /tmp/llama-swap.tgz -C /tmp llama-swap && install -m 0755 /tmp/llama-swap ~/.local/bin/llama-swap && rm -f /tmp/llama-swap.tgz /tmp/llama-swap"
    fi
    # Bootstrap the systemd --user unit so `claw ai-services {up,down} llama-swap`
    # works. Symlinked (not copied) so repo edits propagate. Idempotent.
    run "mkdir -p ~/.config/systemd/user"
    run "ln -sf '$DOTFILES_DIR/config/systemd/llama-swap.service' ~/.config/systemd/user/llama-swap.service"
    run "systemctl --user daemon-reload && systemctl --user enable llama-swap.service"
    log_info "llama-swap: start with 'claw ai-services up llama-swap' (config: config/llama-swap/config.yaml, :8090)"
    log_info "  headless/no-login boot? run once: loginctl enable-linger \"\$USER\""

    # Ollama — auto-detects GPU. Already installed by homelab-toolchain, just remind.
    if command -v ollama &>/dev/null; then
        log_info "Ollama detected — restart to pick up new GPU: sudo systemctl restart ollama"
    fi

    # PyTorch 2.6+ wheels for CUDA 12.8 — install hint, don't auto-install (huge, user choice)
    log_info "PyTorch 2.6+ (CUDA 12.8) install hint:"
    log_info "  pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128"
    log_info "  or for nightly with FP4 + cu130: pip install --pre torch --index-url https://download.pytorch.org/whl/nightly/cu130"

    # TGI (HuggingFace Text Generation Inference) — best run as container
    log_info "HuggingFace TGI: run as container —"
    log_info "  docker run --gpus all -p 8080:80 ghcr.io/huggingface/text-generation-inference:latest --model-id <model>"

    # Triton Inference Server — production-grade
    log_info "NVIDIA Triton Inference Server (production):"
    log_info "  docker run --gpus all -p 8000:8000 -p 8001:8001 -p 8002:8002 nvcr.io/nvidia/tritonserver:25.02-py3 tritonserver --model-repository=/models"

    # Nemotron 3 Nano Omni — NVIDIA's open multimodal 30B-A3B MoE (vision+audio+
    # text→text). Drop a launcher into config/ai/ so the serving flags (incl. the
    # RTX-Pro `--moe-backend triton` FlashInfer workaround) are version-controlled.
    local ai_cfg="$DOTFILES_DIR/config/ai"
    if [[ -f "$ai_cfg/serve-nemotron-omni.sh" ]]; then
        log_info "Nemotron Omni launcher present → config/ai/serve-nemotron-omni.sh"
    else
        log_info "Nemotron Omni launcher: config/ai/serve-nemotron-omni.sh (committed in repo)"
    fi
    log_info "  Serve:  MODEL=<repo-id> ~/.dotfiles/config/ai/serve-nemotron-omni.sh"
    log_warning "  24GB RTX PRO 4000: FP8 weights (~30GB) won't fit — use the NVFP4 variant."
}

# ─────────────────────────────────────────────
# 6. Agentic runtime — NVIDIA OpenShell sandbox + NemoClaw orchestration
# ─────────────────────────────────────────────
# OpenShell (GTC 2026) runs each agent inside its own kernel-isolated sandbox
# — seccomp syscall filtering, Landlock filesystem restrictions, and network
# namespaces — governed by declarative YAML policy enforced at the system layer,
# out of reach of the agent. NemoClaw sits on top of OpenShell and orchestrates
# self-evolving "claw" agents (task decomposition, memory, multi-agent
# delegation), routing inference to local Nemotron (via NIM) or to cloud
# frontier models within the policy guardrails.
install_agentic_runtime() {
    [[ "$INSTALL_AGENTIC" == "false" ]] && { log_info "skip: agentic runtime"; return 0; }

    # OpenShell needs a container / virtualization backend for its sandbox.
    if ! command -v docker &>/dev/null && ! command -v podman &>/dev/null; then
        log_warning "OpenShell needs Docker or Podman for its sandbox — install one first (claw install homelab)"
    fi

    # ── OpenShell ──
    if command -v openshell &>/dev/null; then
        log_info "OpenShell already installed ($(openshell --version 2>&1 | head -1))"
    elif command -v uv &>/dev/null; then
        # Prefer `uv tool install` — lands in $HOME, no root, no piped shell.
        log_info "Installing OpenShell via uv tool install..."
        run "uv tool install -U openshell"
    else
        # Fall back to NVIDIA's official installer. Per repo policy we don't
        # silently pipe curl|sh — print it and let the user opt in.
        log_warning "uv not found — install OpenShell manually (NVIDIA's installer):"
        log_warning "  curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh"
        log_warning "  (or install uv first via 'claw install ai-skills', then re-run --agentic-only)"
    fi

    # Seed a deny-by-default sandbox policy in the repo so it's version-controlled.
    local policy_dir="$DOTFILES_DIR/config/agentic/openshell"
    mkdir -p "$policy_dir"
    if [[ ! -f "$policy_dir/policy.yaml" ]]; then
        cat > "$policy_dir/policy.yaml" <<'EOF'
# OpenShell sandbox policy — STARTER TEMPLATE (illustrative, deny-by-default).
#
# ⚠️  SCHEMA NOT YET VERIFIED against the shipped CLI (openshell 0.0.52). The keys
#     below express *intent* — read-only repo, deny egress, block dangerous
#     syscalls — but were drafted from NVIDIA's announcement, not the live schema.
#     Dump the authoritative schema from a running gateway and reconcile:
#         openshell policy get --global --full -o json
#         openshell policy prove <sandbox> ...      # formally check properties
#
# Prereq — a gateway must be active before any sandbox/policy command:
#     openshell doctor check
#     openshell gateway add <endpoint> && openshell gateway select <name>
#
# Apply at sandbox creation (verified flag):
#     openshell sandbox create --gpu --policy config/agentic/openshell/policy.yaml -- claude
# Or update a live sandbox:
#     openshell policy set <sandbox> --policy config/agentic/openshell/policy.yaml
#
# Docs: https://docs.nvidia.com/openshell/latest/
filesystem:
  readOnly:
    - ~/.dotfiles
  readWrite:
    - ~/.ai/workspace
network:
  defaultAction: deny
  allow:
    - host: localhost          # local vLLM / NIM (e.g. Nemotron Omni on :8000)
    - host: api.anthropic.com  # cloud frontier fallback (privacy router)
process:
  blockSyscalls: [ptrace, mount, "socket(AF_PACKET)"]
EOF
        log_success "Wrote starter OpenShell policy → config/agentic/openshell/policy.yaml"
    fi

    # ── NemoClaw ──
    # NemoClaw's bootstrap is an interactive, GPU- and network-heavy installer
    # (selects an agent, pulls NIM images). The exact installer URL isn't pinned
    # in NVIDIA's public README, so — matching this repo's "don't pipe an
    # unverified installer" stance — we document it rather than auto-running it.
    if command -v nemoclaw &>/dev/null; then
        log_info "NemoClaw already installed ($(nemoclaw --version 2>&1 | head -1))"
    else
        log_info "NemoClaw (orchestration on OpenShell) — install when ready:"
        log_info "  • Quickstart: https://docs.nvidia.com/nemoclaw/latest/get-started/quickstart.html"
        log_info "  • Default agent is OpenClaw. Your repo ships Hermes — select it with:"
        log_info "      NEMOCLAW_AGENT=hermes  (post-install alias: nemohermes)"
        log_info "  • Prereqs: OpenShell + Docker + GPU + NIM for routed local inference."
    fi
}

# ─────────────────────────────────────────────
# 7. GPU data acceleration — RAPIDS cuDF/cuOpt (CUDA-X) + Milvus vector DB
# ─────────────────────────────────────────────
# CUDA-X libraries let agents offload structured-data work (cuDF dataframes) and
# combinatorial routing/optimization (cuOpt) straight to the GPU instead of
# writing CPU-bound Python. Milvus is a GPU-accelerated vector DB for local RAG
# over large corpora (e.g. an Obsidian vault). These are heavy CUDA wheels /
# containers, so we print the recipes rather than auto-pulling gigabytes.
install_gpu_data_stack() {
    [[ "$INSTALL_DATA" == "false" ]] && { log_info "skip: GPU data stack"; return 0; }

    log_info "RAPIDS cuDF / cuOpt (CUDA-X) — GPU dataframes + optimization as agent skills:"
    log_info "  uv pip install --extra-index-url=https://pypi.nvidia.com cudf-cu12 cuopt-cu12"
    log_info "  (or conda: conda install -c rapidsai -c conda-forge -c nvidia cudf cuopt)"

    if command -v docker &>/dev/null; then
        log_info "Milvus (GPU vector DB) — standalone via the embed script:"
        log_info "  curl -fsSL https://raw.githubusercontent.com/milvus-io/milvus/master/scripts/standalone_embed.sh -o standalone_embed.sh"
        log_info "  bash standalone_embed.sh start   # GPU build: milvusdb/milvus:*-gpu"
    else
        log_info "Milvus: install Docker first (claw install homelab), then run the standalone embed script."
    fi
    log_info "Note: Qdrant CLI is already provided by 'claw install ai' (ai-toolchain.sh)."
}

# ─────────────────────────────────────────────
# Post-install summary + verification commands
# ─────────────────────────────────────────────
print_summary() {
    cat <<EOF

  ───────────────────────────────────────────────────────
  AI workstation install complete. Verify with:
  ───────────────────────────────────────────────────────

  Driver / CUDA:
    nvidia-smi                           # should list your Blackwell card
    nvcc --version                       # should report 12.8
    cat /proc/driver/nvidia/version      # kernel module version

  Container runtime:
    docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi

  K3s GPU scheduling:
    kubectl describe node | grep nvidia.com/gpu   # should show 'nvidia.com/gpu: 1'
    kubectl run gpu-test --image=nvidia/cuda:12.8.0-base-ubuntu22.04 \\
      --restart=Never --rm -it --overrides='{"spec":{"runtimeClassName":"nvidia",\\
      "containers":[{"name":"gpu-test","image":"nvidia/cuda:12.8.0-base-ubuntu22.04",\\
      "command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}'

  Local inference smoke test:
    ollama pull llama3.1:8b && ollama run llama3.1:8b "hello"
    nvtop                          # watch GPU during inference

  Multimodal serving (Nemotron 3 Nano Omni):
    MODEL=nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-NVFP4 \\
      ~/.dotfiles/config/ai/serve-nemotron-omni.sh   # NVFP4 fits 24GB RTX PRO 4000

  Agentic runtime (OpenShell + NemoClaw):
    openshell doctor check                           # verify Docker/host prereqs
    openshell gateway add <endpoint> && openshell gateway select <name>   # control plane
    openshell sandbox create --gpu \\
      --policy config/agentic/openshell/policy.yaml -- claude   # kernel-isolated agent
    openshell sandbox list                           # see running sandboxes
    # NemoClaw: see https://docs.nvidia.com/nemoclaw/latest/ (NEMOCLAW_AGENT=hermes)

  Blackwell-specific (FP4 / Transformer Engine):
    python -c "import torch; print(torch.cuda.get_device_capability())"  # → (12, 0) for Blackwell
    python -c "import transformer_engine.pytorch as te; print(te.__version__)"

  Profiling:
    nvitop                         # interactive top-style monitor
    py-spy top --pid <pid>         # per-process Python CPU/wall time
    nsys profile python script.py  # full NVIDIA Nsight trace

  Next steps:
    claw install ai-skills         # 2026 SOTA agent/RAG/eval toolkit
    claw doctor                    # verifies GPU + CUDA + container toolkit

EOF
}

# ── Main ─────────────────────────────────────────────────
install_driver_and_cuda
install_container_toolkit
install_k3s_gpu_plugin
install_monitoring
install_inference_stack
install_agentic_runtime
install_gpu_data_stack
print_summary

log_success "AI workstation toolchain install complete."
