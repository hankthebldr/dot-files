# AI & LLM Profile
# Loadout for Model Ops, Embeddings, Local Inference, and AI Workflows
export CLAW_PROFILE_THEME="ai"

# ==========================================
# ENVIRONMENT VARIABLES
# ==========================================
export AI_WORKSPACE="$HOME/ai_models"
mkdir -p "$AI_WORKSPACE"

# Note: Set API Keys in your secure vault (e.g. 1Password/AWS Vault)
# export OPENAI_API_KEY="..."
# export ANTHROPIC_API_KEY="..."

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

echo -e "\n\033[0;32m[!] AI Profile Loaded. Initialized Workspace: $AI_WORKSPACE\033[0m\n"
