# shell/profiles/blackwell/mac.zsh
# Cockpit mode: every operation reaches into the BD790i via SSH.
# Common.zsh calls _bw_* helpers — defined here as SSH wrappers.

_bw_ssh() {
    ssh -o ControlMaster=auto \
        -o ControlPath="/tmp/ssh-bd790i-%r@%h:%p" \
        -o ControlPersist=10m \
        "${BD790I_USER}@${BD790I_HOST}" "$@"
}

# Delegate to remote tools. Use bash -lc so PATH includes ~/.local/bin etc.
_bw_nvidia_smi() { _bw_ssh "nvidia-smi $*"; }
_bw_ollama()     { _bw_ssh "ollama $*"; }

# nvtop is interactive — needs a full PTY (-t).
_bw_nvtop() {
    ssh -t -o ControlPath="/tmp/ssh-bd790i-%r@%h:%p" \
        "${BD790I_USER}@${BD790I_HOST}" "nvtop"
}

# Running GPU jobs — list PIDs holding GPU memory, with process names.
_bw_running_jobs() {
    _bw_ssh "nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader" 2>/dev/null \
        | awk -F', ' 'NF { printf "    %s  %s  %s\n", $1, $3, $2 }' \
        || echo "    (none / nvidia-smi unreachable)"
}

# vLLM server health — check if anything's listening on $VLLM_PORT on the lab head
_bw_vllm_health() {
    if _bw_ssh "ss -tln sport = :$VLLM_PORT 2>/dev/null | grep -q LISTEN"; then
        printf "    \e[32m●\e[0m listening on :%s\n" "$VLLM_PORT"
        # Quick model probe via the OpenAI API
        local model; model=$(curl -sS --max-time 2 "http://${BD790I_HOST}:${VLLM_PORT}/v1/models" 2>/dev/null \
            | jq -r '.data[0].id' 2>/dev/null)
        [[ -n "$model" && "$model" != "null" ]] && printf "    \e[2mmodel: %s\e[0m\n" "$model"
    else
        printf "    \e[33m○\e[0m no vLLM server on :%s\n" "$VLLM_PORT"
    fi
}

# Ollama model count.
_bw_ollama_count() {
    local n; n=$(_bw_ssh "ollama list 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null | tr -d ' ')
    if [[ -n "$n" && "$n" =~ ^[0-9]+$ ]]; then
        printf "    \e[2m%s model(s) cached\e[0m\n" "$n"
    else
        printf "    \e[33m○\e[0m ollama unreachable\n"
    fi
}

# Start a vLLM server remotely via systemd-run user unit (transient, auto-cleanup).
# Falls back to nohup if systemd-run isn't available.
_bw_vllm_serve() {
    local model="$1"
    echo "▸ starting vLLM remotely on $BD790I_HOST  (model: $model)"
    _bw_ssh "systemd-run --user --unit=vllm-$$\
      -- python3 -m vllm.entrypoints.openai.api_server \
      --model '$model' --port $VLLM_PORT --host 0.0.0.0" 2>&1 | tail -5
    echo "▸ check: bwstatus  ·  hit: bwclient"
}

# Kill a remote PID — SIGTERM, wait 10s, then SIGKILL.
_bw_kill_pid() {
    local pid="$1"
    _bw_ssh "kill -TERM $pid 2>/dev/null && sleep 10 && kill -KILL $pid 2>/dev/null; echo done"
}

# Tunnel the vLLM port to localhost — convenience for hitting it from Mac
# without configuring TLS / Tailscale ACLs.
bwtunnel() {
    echo "▸ forwarding localhost:${VLLM_PORT} → ${BD790I_HOST}:${VLLM_PORT}"
    ssh -N -L "${VLLM_PORT}:localhost:${VLLM_PORT}" \
        -o ControlPath="/tmp/ssh-bd790i-vllm-%r@%h:%p" \
        -o ControlPersist=yes \
        "${BD790I_USER}@${BD790I_HOST}"
}
