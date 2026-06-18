# AI & LLM Profile
# Loadout for Model Ops, Embeddings, Local Inference, and AI Workflows
export CLAW_PROFILE_THEME="ai"

export AI_WORKSPACE="$HOME/ai_models"
mkdir -p "$AI_WORKSPACE" 2>/dev/null

# Note: Set API Keys in ~/.zshrc.local (e.g. OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY)

# ==========================================
# ALIASES — short, unprefixed, value-add only
# ==========================================
# (de-prefixed 2026-04-28: pure renames like ai-llama=llama-cpp dropped.
#  Use the real binary names directly. Compositions get short mnemonics.)

# --- Ollama (compositions only — `ollama` itself is fine to type) ---
alias oserve="ollama serve"
alias opull="ollama pull"
alias orun="ollama run"

# --- Local Hermes (refusal-prone fallback; Nous Hermes via Ollama) ---
# Shorthand for the `hermes` wrapper (bin/hermes). One-shot: lhermes "prompt"
# REPL: lhermes. Override model with CLAW_HERMES_MODEL (default hermes3:8b).
alias lhermes="hermes"

# --- API one-liners ---
alias oai="openai api chat.completions.create -m gpt-4o"
alias fab="fabric --pattern"

# --- LiteLLM gateway + llama-swap (now claw ai-services, not host CLIs) ---
alias llmgw="claw ai-services up litellm"           # unified OpenAI gateway :4000
alias swapup="claw ai-services up llama-swap"        # model hot-swap proxy   :8090
alias swapdown="claw ai-services down llama-swap"
alias mar="marimo new"
alias mart="marimo tutorial"

# --- Self-hosted AI web stacks (open-webui / dify / ragflow / langfuse) ---
alias aisvc="claw ai-services"
alias aisup="claw ai-services up"
alias aisdown="claw ai-services down"
alias aisst="claw ai-services status"
alias owui="claw ai-services up open-webui"     # ChatGPT-style Ollama UI :3000

# --- Agent frameworks (CLIs via pipx; libs are per-project) ---
alias crew="crewai"                              # CrewAI multi-agent CLI
alias lchain="langchain"                         # LangChain CLI (avoids colorls `lc`)

# --- GPU / Blackwell workstation ---
# nvidia-smi shortcut + watch mode
alias smi="nvidia-smi"
alias smiw="nvidia-smi -l 2"                                          # refresh every 2s
alias gpus="nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits"
# Interactive monitors (auto-fall back if not installed)
alias gtop="nvtop"                                                    # apt: nvtop
alias gtop2="nvitop"                                                  # pipx: nvitop (richer UI)
alias gprof='py-spy top --pid'                                        # py-spy top --pid <pid>
# Container GPU smoke test
alias gpudock="docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi"
# K3s GPU check
alias gpuk8s="kubectl describe node | grep -E 'nvidia.com/gpu|Allocated|Capacity:' | head -20"

# --- Quick venv activators (created by ai-skills.sh tier 6) ---
alias venv-training='source ~/.ai/training/bin/activate'
alias venv-unsloth='source ~/.ai/unsloth/bin/activate'
alias venv-vllm='source ~/.ai/vllm/bin/activate'

# Note: agents (claude, aider, hermes, etc.) are launched via `claw <agent>`
# from the registry at ~/.config/claw/agents.toml — not duplicated here.

# ==========================================
# QUICK REFERENCE
# ==========================================
ai-help() {
  local purple='\e[38;2;188;140;255m'
  local green='\e[38;2;63;185;80m'
  local dim='\e[38;2;139;148;158m'
  local white='\e[38;2;201;209;217m'
  local bold='\e[1m'
  local reset='\e[0m'

  printf "\n"
  printf "  ${purple}╭──────────────────────────────────────────────────────────╮${reset}\n"
  printf "  ${purple}│${reset}  ${bold}${white}AI PROFILE — Quick Reference${reset}                            ${purple}│${reset}\n"
  printf "  ${purple}╰──────────────────────────────────────────────────────────╯${reset}\n"
  printf "\n"

  printf "  ${bold}${green}Ollama${reset}\n"
  printf "  ${purple}oserve${reset}    ${dim}ollama serve${reset}\n"
  printf "  ${purple}opull${reset}     ${dim}ollama pull <model>${reset}\n"
  printf "  ${purple}orun${reset}      ${dim}ollama run <model>${reset}\n"
  printf "\n"
  printf "  ${bold}${green}One-liners${reset}\n"
  printf "  ${purple}oai${reset}       ${dim}openai chat.completions (gpt-4o)${reset}\n"
  printf "  ${purple}fab${reset}       ${dim}fabric --pattern <name>${reset}\n"
  printf "\n"
  printf "  ${bold}${green}Agents${reset} ${dim}(via claw registry — not aliases)${reset}\n"
  printf "  ${purple}claw claude${reset}    ${dim}Anthropic Claude Code${reset}\n"
  printf "  ${purple}claw gemini${reset}    ${dim}Google Gemini CLI (@google/gemini-cli)${reset}\n"
  printf "  ${purple}claw opencode${reset}  ${dim}terminal AI coding agent (opencode.ai)${reset}\n"
  printf "  ${purple}claw openwork${reset}  ${dim}headless OpenWork (Cowork alt, on opencode)${reset}\n"
  printf "  ${purple}claw <name>${reset}    ${dim}any registered agent${reset}\n"
  printf "  ${purple}claw agent list${reset} ${dim}see all registered agents${reset}\n"
  printf "\n"
  printf "  ${bold}${green}Gateways & serving${reset} ${dim}(claw ai-services)${reset}\n"
  printf "  ${purple}llmgw${reset}     ${dim}LiteLLM unified OpenAI gateway      :4000${reset}\n"
  printf "  ${purple}swapup${reset}    ${dim}llama-swap model hot-swap proxy     :8090${reset}\n"
  printf "  ${purple}aisst${reset}     ${dim}claw ai-services status (all)${reset}\n"
  printf "\n"
  printf "  ${bold}${green}LLM security / eval${reset} ${dim}(also in security profile)${reset}\n"
  printf "  ${purple}garak${reset}     ${dim}NVIDIA LLM vuln scanner (offline probes)${reset}\n"
  printf "  ${purple}promptfoo${reset} ${dim}eval + red-team as config (CI)${reset}\n"
  printf "\n"
  printf "  ${bold}${green}Other tools${reset} ${dim}(use real binary names)${reset}\n"
  printf "  ${dim}llama-cpp · whisper-cpp · huggingface-cli · qdrant-cli · pinecone-cli${reset}\n"
  printf "  ${dim}langchain-cli · diffusers-cli · gpt4all-cli · cohere · adk · dvc${reset}\n"
  printf "\n"

  printf "  ${bold}${green}GPU / Blackwell${reset}\n"
  printf "  ${purple}smi${reset}      ${dim}nvidia-smi (one-shot)${reset}\n"
  printf "  ${purple}smiw${reset}     ${dim}nvidia-smi -l 2 (live)${reset}\n"
  printf "  ${purple}gpus${reset}     ${dim}terse one-line GPU stats${reset}\n"
  printf "  ${purple}gtop${reset}     ${dim}nvtop (htop-style)${reset}\n"
  printf "  ${purple}gtop2${reset}    ${dim}nvitop (richer UI)${reset}\n"
  printf "  ${purple}gpudock${reset}  ${dim}docker GPU smoke test${reset}\n"
  printf "  ${purple}gpuk8s${reset}   ${dim}kubectl GPU resource view${reset}\n"
  printf "\n"

  printf "  ${bold}${green}2026 SOTA${reset} ${dim}(installed via: claw install ai-skills)${reset}\n"
  printf "  ${purple}aider${reset}        ${dim}terminal AI pair programmer${reset}\n"
  printf "  ${purple}mar${reset}          ${dim}marimo (reactive notebooks)${reset}\n"
  printf "  ${purple}langgraph${reset}    ${dim}graph-based agent orchestration${reset}\n"
  printf "  ${purple}inspect${reset}      ${dim}Inspect AI (eval framework)${reset}\n"
  printf "  ${purple}phoenix${reset}      ${dim}Arize Phoenix (observability)${reset}\n"
  printf "\n"
}

# ==========================================
# TOOL AVAILABILITY CHECK
# ==========================================
_ai_tool_check() {
  local green='\e[38;2;63;185;80m'
  local red='\e[38;2;248;81;73m'
  local white='\e[38;2;201;209;217m'
  local dim='\e[38;2;139;148;158m'
  local bold='\e[1m'
  local reset='\e[0m'
  local found=0 missing=0
  local tools=(
    ollama claude gemini aider whisper-cpp python3 pip3 dvc mlflow huggingface-cli adk
    # 2026 SOTA additions
    uv litellm marimo langgraph instructor inspect phoenix
    # agents + gateways + LLM security (added 2026-06)
    opencode openwork llama-swap garak promptfoo
    # Blackwell / GPU
    nvidia-smi nvcc nvtop nvitop nvidia-ctk
  )

  printf "\n  ${bold}${white}AI Toolchain Status${reset}\n\n"
  for tool in "${tools[@]}"; do
    if command -v "$tool" &> /dev/null; then
      printf "  ${green}●${reset}  ${white}%-18s${reset} ${dim}found${reset}\n" "$tool"
      ((found++))
    else
      printf "  ${red}✗${reset}  ${white}%-18s${reset} ${dim}not found${reset}\n" "$tool"
      ((missing++))
    fi
  done
  printf "\n  ${dim}Summary: ${green}${found} installed${reset} ${dim}/ ${red}${missing} missing${reset} ${dim}(${#tools[@]} total)${reset}\n\n"
}

# Profile banner handled by fastfetch (config-ai.jsonc)
