# AI & LLM Profile
# Loadout for Model Ops, Embeddings, Local Inference, and AI Workflows
export CLAW_PROFILE_THEME="ai"

# ==========================================
# ENVIRONMENT VARIABLES
# ==========================================
export AI_WORKSPACE="$HOME/ai_models"
mkdir -p "$AI_WORKSPACE"

# Note: Set API Keys in ~/.zshrc.local or secure vault (e.g. 1Password/AWS Vault)
# export OPENAI_API_KEY="..."
# export ANTHROPIC_API_KEY="..."
# export GOOGLE_API_KEY="..."
# export GOOGLE_CLOUD_PROJECT="..."

# ==========================================
# CATEGORIZED ALIASES & PIPELINES
# ==========================================

# --- Local & API Models ---
alias ai-llama="llama-cpp"
alias ai-gpt4all="gpt4all-cli"
alias ai-openai="openai api chat.completions.create -m gpt-4o"
alias ai-claude="anthropic"
alias ai-serve="ollama serve"
alias ai-pull="ollama pull"
alias ai-run="ollama run"

# --- Embeddings & Vector DBs ---
alias ai-cohere="cohere"
alias ai-qdrant="qdrant-cli"
alias ai-pine="pinecone-cli"

# --- Audio & Generative ---
alias ai-whisper="whisper-cpp"
alias ai-diff="diffusers-cli"

# --- MLOps Pipeline ---
alias ai-hf="huggingface-cli"
alias ai-dvc="dvc status"
alias ai-lang="langchain-cli"

# --- Pair Programming & Shell Native AI ---
alias aider="aider"
alias ai-fab="fabric --pattern"

# --- Agent SDKs ---
alias ai-claude-sdk="claude"
alias ai-adk="adk"
alias ai-adk-web="adk web"
alias ai-adk-run="adk run"
alias ai-adk-eval="adk eval"
alias ai-adk-deploy="adk deploy"

# ==========================================
# HELPER FUNCTIONS
# ==========================================

# Styled quick-reference card for all ai-* aliases
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

  printf "  ${bold}${green}Local & API Models${reset}\n"
  printf "  ${purple}ai-serve${reset}       ${dim}Start ollama server${reset}\n"
  printf "  ${purple}ai-pull${reset}        ${dim}Pull an ollama model${reset}\n"
  printf "  ${purple}ai-run${reset}         ${dim}Run an ollama model${reset}\n"
  printf "  ${purple}ai-llama${reset}       ${dim}llama-cpp inference${reset}\n"
  printf "  ${purple}ai-gpt4all${reset}     ${dim}GPT4All CLI${reset}\n"
  printf "  ${purple}ai-openai${reset}      ${dim}OpenAI GPT-4o chat${reset}\n"
  printf "  ${purple}ai-claude${reset}      ${dim}Anthropic CLI${reset}\n"
  printf "\n"

  printf "  ${bold}${green}Embeddings & Vector DBs${reset}\n"
  printf "  ${purple}ai-cohere${reset}      ${dim}Cohere CLI${reset}\n"
  printf "  ${purple}ai-qdrant${reset}      ${dim}Qdrant vector DB CLI${reset}\n"
  printf "  ${purple}ai-pine${reset}        ${dim}Pinecone CLI${reset}\n"
  printf "\n"

  printf "  ${bold}${green}Audio & Generative${reset}\n"
  printf "  ${purple}ai-whisper${reset}     ${dim}Whisper.cpp transcription${reset}\n"
  printf "  ${purple}ai-diff${reset}        ${dim}Diffusers CLI${reset}\n"
  printf "\n"

  printf "  ${bold}${green}MLOps Pipeline${reset}\n"
  printf "  ${purple}ai-hf${reset}          ${dim}Hugging Face CLI${reset}\n"
  printf "  ${purple}ai-dvc${reset}         ${dim}DVC status${reset}\n"
  printf "  ${purple}ai-lang${reset}        ${dim}LangChain CLI${reset}\n"
  printf "\n"

  printf "  ${bold}${green}Pair Programming${reset}\n"
  printf "  ${purple}aider${reset}          ${dim}Aider AI pair programmer${reset}\n"
  printf "  ${purple}ai-fab${reset}         ${dim}Fabric pattern runner${reset}\n"
  printf "\n"

  printf "  ${bold}${green}Agent SDKs${reset}\n"
  printf "  ${purple}ai-claude-sdk${reset}  ${dim}Claude Code CLI${reset}\n"
  printf "  ${purple}ai-adk${reset}         ${dim}Google ADK${reset}\n"
  printf "  ${purple}ai-adk-web${reset}     ${dim}ADK web interface${reset}\n"
  printf "  ${purple}ai-adk-run${reset}     ${dim}ADK run agent${reset}\n"
  printf "  ${purple}ai-adk-eval${reset}    ${dim}ADK eval${reset}\n"
  printf "  ${purple}ai-adk-deploy${reset}  ${dim}ADK deploy${reset}\n"
  printf "\n"
}

# Check availability of core AI toolchain binaries
_ai_tool_check() {
  local green='\e[38;2;63;185;80m'
  local red='\e[38;2;248;81;73m'
  local white='\e[38;2;201;209;217m'
  local dim='\e[38;2;139;148;158m'
  local bold='\e[1m'
  local reset='\e[0m'
  local found=0
  local missing=0
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
