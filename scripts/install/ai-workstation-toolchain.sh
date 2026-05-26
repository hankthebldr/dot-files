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
#   - Monitoring: nvtop, gpustat, nvitop, NVIDIA DCGM exporter
#   - Profiling: NVIDIA Nsight Systems, py-spy, scalene
#
# Flags:
#   --driver-only        install only the driver + CUDA toolkit, skip inference
#   --inference-only     assume driver/CUDA already work, install vLLM/llama.cpp/etc.
#   --skip-k3s           don't install the K3s device plugin
#   --skip-reboot-prompt skip the post-driver-install reboot prompt
#   --dry-run            print actions without executing
#   --help
#
# Post-install: ALWAYS run `nvidia-smi` to verify driver loaded. If the kernel
# module fails to build (DKMS), `sudo dmesg | grep -i nvidia` is the next step.
################################################################################

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"

# ── Flag parsing (before OS gate so --help works on Mac) ──
INSTALL_DRIVER=true
INSTALL_INFERENCE=true
INSTALL_K3S_PLUGIN=true
PROMPT_REBOOT=true
DRY_RUN=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --driver-only)        INSTALL_INFERENCE=false ;;
        --inference-only)     INSTALL_DRIVER=false ;;
        --skip-k3s)           INSTALL_K3S_PLUGIN=false ;;
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

    local manifest_dir="$DOTFILES_DIR/config/k3s/gpu"
    mkdir -p "$manifest_dir"

    # RuntimeClass — tells K8s to use the nvidia containerd runtime for these pods
    cat > "$manifest_dir/runtimeclass-nvidia.yaml" <<'EOF'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF

    # Device plugin DaemonSet — advertises nvidia.com/gpu as a schedulable resource.
    # Pinned to v0.17.0 (released March 2026, first version with Blackwell + MIG 2.0 support).
    cat > "$manifest_dir/nvidia-device-plugin.yaml" <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      runtimeClassName: nvidia
      priorityClassName: system-node-critical
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
      containers:
        - name: nvidia-device-plugin-ctr
          image: nvcr.io/nvidia/k8s-device-plugin:v0.17.0
          env:
            - name: FAIL_ON_INIT_ERROR
              value: "false"
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: device-plugin
              mountPath: /var/lib/kubelet/device-plugins
      volumes:
        - name: device-plugin
          hostPath:
            path: /var/lib/kubelet/device-plugins
EOF

    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    run "kubectl apply -f '$manifest_dir/runtimeclass-nvidia.yaml'"
    run "kubectl apply -f '$manifest_dir/nvidia-device-plugin.yaml'"

    log_success "Device plugin applied. Verify with: kubectl describe node | grep nvidia.com/gpu"
}

# ─────────────────────────────────────────────
# 4. Monitoring + profiling — nvtop, gpustat, nvitop, dcgm-exporter, nsight
# ─────────────────────────────────────────────
install_monitoring() {
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
print_summary

log_success "AI workstation toolchain install complete."
