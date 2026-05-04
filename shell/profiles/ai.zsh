# AI & LLM Profile
# Loadout for Model Ops, Embeddings, Local Inference, and AI Workflows
export CLAW_PROFILE_THEME="ai"

export AI_WORKSPACE="$HOME/ai_models"
mkdir -p "$AI_WORKSPACE" 2>/dev/null

# Note: Set API Keys in ~/.zshrc.local (e.g. OPENAI_API_KEY, ANTHROPIC_API_KEY)

# ==========================================
# ALIASES — short, unprefixed, value-add only
# ==========================================
# (de-prefixed 2026-04-28: pure renames like ai-llama=llama-cpp dropped.
#  Use the real binary names directly. Compositions get short mnemonics.)

# --- Ollama (compositions only — `ollama` itself is fine to type) ---
alias oserve="ollama serve"
alias opull="ollama pull"
alias orun="ollama run"

# --- API one-liners ---
alias oai="openai api chat.completions.create -m gpt-4o"
alias fab="fabric --pattern"

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
  printf "  ${purple}claw <name>${reset}    ${dim}any registered agent${reset}\n"
  printf "  ${purple}claw agent list${reset} ${dim}see all registered agents${reset}\n"
  printf "\n"
  printf "  ${bold}${green}Other tools${reset} ${dim}(use real binary names)${reset}\n"
  printf "  ${dim}llama-cpp · whisper-cpp · huggingface-cli · qdrant-cli · pinecone-cli${reset}\n"
  printf "  ${dim}langchain-cli · diffusers-cli · gpt4all-cli · cohere · adk · dvc${reset}\n"
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
  local tools=(ollama claude aider whisper-cpp python3 pip3 dvc mlflow huggingface-cli adk)

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
