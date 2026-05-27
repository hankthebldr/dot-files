# shell/profiles/blackwell/linux.zsh
# Native mode: running ON the Blackwell host. Direct GPU access, no SSH.

_bw_nvidia_smi() { nvidia-smi "$@"; }
_bw_ollama()     { ollama "$@"; }
_bw_nvtop()      { nvtop; }

# Running GPU jobs — same query as the remote version but local.
_bw_running_jobs() {
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null \
        | awk -F', ' 'NF { printf "    %s  %s  %s\n", $1, $3, $2 }' \
        || echo "    (none / nvidia-smi unavailable)"
}

# vLLM server health — local port check via ss + OpenAI API probe.
_bw_vllm_health() {
    if ss -tln "sport = :$VLLM_PORT" 2>/dev/null | grep -q LISTEN; then
        printf "    \e[32m●\e[0m listening on :%s\n" "$VLLM_PORT"
        local model; model=$(curl -sS --max-time 2 "http://localhost:${VLLM_PORT}/v1/models" 2>/dev/null \
            | jq -r '.data[0].id' 2>/dev/null)
        [[ -n "$model" && "$model" != "null" ]] && printf "    \e[2mmodel: %s\e[0m\n" "$model"
    else
        printf "    \e[33m○\e[0m no vLLM server on :%s\n" "$VLLM_PORT"
    fi
}

# Ollama model count — local check.
_bw_ollama_count() {
    if command -v ollama &>/dev/null; then
        local n; n=$(ollama list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        printf "    \e[2m%s model(s) cached\e[0m\n" "$n"
    else
        printf "    \e[33m○\e[0m ollama not installed\n"
    fi
}

# Local vLLM serve — foreground by default; user can wrap with tmux/screen.
# Detached background via systemd-run --user --unit=...
_bw_vllm_serve() {
    local model="$1"
    if ! command -v vllm &>/dev/null && ! python3 -c 'import vllm' 2>/dev/null; then
        echo "vllm not installed — run: claw install ai-workstation" >&2
        return 1
    fi
    echo "▸ starting vLLM on :$VLLM_PORT  (model: $model)"
    echo "  Ctrl-C to stop, or run with: systemd-run --user --unit=vllm bwserve $model"
    python3 -m vllm.entrypoints.openai.api_server \
        --model "$model" \
        --port "$VLLM_PORT" \
        --host 0.0.0.0
}

# Kill a local PID — SIGTERM, wait, SIGKILL.
_bw_kill_pid() {
    local pid="$1"
    kill -TERM "$pid" 2>/dev/null && sleep 10 && kill -KILL "$pid" 2>/dev/null
    echo "done"
}

# bwtunnel is a no-op on Linux — the server IS local already.
bwtunnel() {
    echo "(already on the lab head — vLLM is on localhost:${VLLM_PORT})"
}

# bwtrain <config>  — kick off a training job under systemd-run so it
# survives shell exits and is killable by unit name.
bwtrain() {
    local config="${1:?usage: bwtrain <config.py-or-yaml>}"
    local unit="bw-train-$(date +%s)"
    systemd-run --user --unit="$unit" \
        --working-directory="$(pwd)" \
        python3 "$config" 2>&1 | head -5
    echo "▸ unit: $unit"
    echo "▸ tail logs: journalctl --user -u $unit -f"
    echo "▸ kill:      systemctl --user stop $unit"
}

# bwprofile <pid>  — attach Nsight Systems to a running training PID.
bwprofile() {
    local pid="${1:?usage: bwprofile <pid>}"
    local out="/tmp/nsys-$pid-$(date +%s).qdrep"
    if ! command -v nsys &>/dev/null; then
        echo "nsys not installed — run: claw install ai-workstation" >&2
        return 1
    fi
    echo "▸ profiling pid $pid → $out  (Ctrl-C to stop)"
    nsys profile --attach="$pid" --output="${out%.qdrep}"
}
