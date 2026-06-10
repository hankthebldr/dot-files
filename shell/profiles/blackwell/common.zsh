# shell/profiles/blackwell/common.zsh
# Cross-platform aliases for Blackwell GPU/ML workflows.
# Per-OS divergence (SSH wrappers vs native CUDA tooling) lives in mac.zsh / linux.zsh.


# Same identity convention as homelab — both point to the BD790i by default.
export BD790I_HOST="${BD790I_HOST:-bd790i}"
export BD790I_USER="${BD790I_USER:-henry}"

# Default vLLM server port on the Blackwell host. Override for multi-server setups.
export VLLM_PORT="${VLLM_PORT:-8000}"

# Local model cache hint — Ollama default. Read-only on Mac (cockpit), writeable on Linux.
export OLLAMA_MODELS_DIR="${OLLAMA_MODELS_DIR:-/usr/share/ollama/.ollama/models}"

# ==========================================
# GPU STATUS / MONITORING
# ==========================================

# bwgpu  — quick one-line GPU status (utilization · VRAM · temp · power)
bwgpu() {
    if typeset -f _bw_nvidia_smi &>/dev/null; then
        _bw_nvidia_smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
            --format=csv,noheader,nounits 2>/dev/null \
            | awk -F', ' '{
                printf "  \033[36m●\033[0m %s\n  \033[2m   util %s%%  ·  mem %s/%s MiB  ·  %s°C  ·  %sW\033[0m\n", \
                       $1, $2, $3, $4, $5, $6
            }'
    fi
}

# bwstatus  — extended health pane (GPU + running jobs + ollama models + vLLM server)
bwstatus() {
    printf "\n  \e[36m▸\e[0m \e[1mBlackwell health\e[0m  \e[2m(%s)\e[0m\n\n" "$BD790I_HOST"
    bwgpu
    echo ""
    if typeset -f _bw_running_jobs &>/dev/null; then
        printf "  \e[2m── training jobs ──\e[0m\n"
        _bw_running_jobs
        echo ""
    fi
    if typeset -f _bw_vllm_health &>/dev/null; then
        printf "  \e[2m── vllm server ──\e[0m\n"
        _bw_vllm_health
        echo ""
    fi
    if typeset -f _bw_ollama_count &>/dev/null; then
        printf "  \e[2m── ollama ──\e[0m\n"
        _bw_ollama_count
        echo ""
    fi
}

# bwtop  — interactive nvtop session. Mac mode opens an SSH session running
# nvtop on the BD790i; Linux mode runs locally.
bwtop() {
    if typeset -f _bw_nvtop &>/dev/null; then
        _bw_nvtop
    fi
}

# bwfree  — VRAM free in MiB (useful in scripts that want to gate by mem)
bwfree() {
    _bw_nvidia_smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | tr -d ' '
}

# ==========================================
# vLLM INFERENCE SERVER
# ==========================================

# bwserve <model>  — start a vLLM OpenAI-compatible server for <model>.
# On Mac, this triggers the start remotely via SSH; on Linux it runs in
# the foreground unless backgrounded explicitly.
bwserve() {
    local model="${1:?usage: bwserve <model-id>  (e.g. meta-llama/Llama-3.1-8B-Instruct)}"
    if typeset -f _bw_vllm_serve &>/dev/null; then
        _bw_vllm_serve "$model"
    fi
}

# bwclient [endpoint]  — pipe a prompt to the vLLM server via curl.
# Usage: echo "what is the capital of France?" | bwclient
bwclient() {
    local endpoint="${1:-http://${BD790I_HOST}:${VLLM_PORT}/v1/chat/completions}"
    local prompt; prompt="$(cat)"
    curl -sS "$endpoint" \
        -H "Content-Type: application/json" \
        -d "$(jq -nc --arg p "$prompt" '{model:"default",messages:[{role:"user",content:$p}]}')" \
        | jq -r '.choices[0].message.content'
}

# bwbench <model>  — quick throughput benchmark (tokens/sec) against a model.
bwbench() {
    local model="${1:?usage: bwbench <model>}"
    if typeset -f _bw_vllm_bench &>/dev/null; then
        _bw_vllm_bench "$model"
    else
        # Generic fallback — issue 10 short prompts, time them
        local n=10 total=0
        for i in $(seq 1 $n); do
            local start=$(date +%s%N)
            echo "Count from 1 to 5." | bwclient >/dev/null
            local end=$(date +%s%N)
            local elapsed=$(( (end - start) / 1000000 ))
            total=$(( total + elapsed ))
            printf "  prompt %d: %dms\n" "$i" "$elapsed"
        done
        printf "  \e[36mavg: %dms\e[0m\n" $(( total / n ))
    fi
}

# ==========================================
# MODELS
# ==========================================

# bwmodels  — list models known to Ollama on the lab head
bwmodels() {
    if typeset -f _bw_ollama &>/dev/null; then
        _bw_ollama list
    fi
}

# bwpull <model>  — pull a new Ollama model on the lab head
bwpull() {
    local model="${1:?usage: bwpull <model>}"
    if typeset -f _bw_ollama &>/dev/null; then
        _bw_ollama pull "$model"
    fi
}

# ==========================================
# JOBS
# ==========================================

# bwjobs  — list running training/inference processes on the GPU
bwjobs() {
    if typeset -f _bw_running_jobs &>/dev/null; then
        _bw_running_jobs
    fi
}

# bwkill <pid>  — kill a specific GPU job. Sends SIGTERM, then SIGKILL after 10s.
bwkill() {
    local pid="${1:?usage: bwkill <pid>}"
    if typeset -f _bw_kill_pid &>/dev/null; then
        _bw_kill_pid "$pid"
    fi
}

# ==========================================
# HELP
# ==========================================

blackwell-help() {
    cat <<EOF
BLACKWELL profile — PHOSPHOR-GHOST (Tier 6: hardware & ops)

  identity:  BD790I_HOST=$BD790I_HOST  ·  VLLM_PORT=$VLLM_PORT

  ── GPU status ───────────────────────
  bwgpu                util · VRAM · temp · power (one line)
  bwstatus             full pane: GPU + jobs + vLLM + ollama
  bwtop                interactive nvtop
  bwfree               VRAM free in MiB (scriptable)

  ── inference (vLLM) ─────────────────
  bwserve <model>      start vLLM server
  bwclient [endpoint]  pipe prompt to vLLM (reads stdin)
  bwbench <model>      quick throughput benchmark

  ── models ───────────────────────────
  bwmodels             list ollama models on the lab head
  bwpull <model>       pull a new model

  ── jobs ─────────────────────────────
  bwjobs               running GPU processes
  bwkill <pid>         terminate a GPU job (SIGTERM → SIGKILL)

  override BD790I_HOST in env to point at a Tailscale IP or other hostname
EOF
}
