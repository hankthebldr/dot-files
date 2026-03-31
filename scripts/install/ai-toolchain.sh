#!/bin/bash

################################################################################
# AI / LLM Toolchain Installer
# Description: Installs GenAI models, vector dbs, inference CLIs and orchestrators
################################################################################

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[INFO]${NC} Installing AI Toolchain..."

brew_tools=(
    "llama.cpp"
    "whisper-cpp"
    "ffmpeg"
    "qdrant-cli"
    "ollama"
    "cliclick"
    "jq"
    "yq"
    "dasel"
)

for tool in "${brew_tools[@]}"; do
    if brew list "$tool" &>/dev/null; then
        echo -e "${BLUE}[INFO]${NC} $tool already installed."
    else
        echo -e "${BLUE}[INFO]${NC} Installing $tool..."
        brew install "$tool" || echo -e "${RED}[ERROR]${NC} Failed to install $tool"
    fi
done

# Python based AI tools
echo -e "${BLUE}[INFO]${NC} Installing Python AI Tools via pipx..."
if ! command -v pipx &> /dev/null; then
    brew install pipx
    pipx ensurepath
fi

pipx_tools=(
    "openai"
    "anthropic"
    "cohere"
    "huggingface-hub"
    "langchain-cli"
    "dvc"
    "mlflow"
    "aider-chat"
    "google-adk"
)

# Node-based AI tools (Claude Agent SDK)
echo -e "${BLUE}[INFO]${NC} Installing Node AI Tools..."
if command -v npm &> /dev/null; then
    for pkg in "@anthropic-ai/claude-agent-sdk"; do
        if npm list -g "$pkg" &>/dev/null 2>&1; then
            echo -e "${BLUE}[INFO]${NC} $pkg already installed globally."
        else
            echo -e "${BLUE}[INFO]${NC} Installing $pkg globally..."
            npm install -g "$pkg" || echo -e "${RED}[ERROR]${NC} Failed to install $pkg"
        fi
    done
else
    echo -e "${RED}[ERROR]${NC} npm not found — install Node.js first (S4)"
fi

for tool in "${pipx_tools[@]}"; do
    echo -e "${BLUE}[INFO]${NC} Ensuring pipx install for $tool..."
    pipx install "$tool" || echo -e "${RED}[ERROR]${NC} Failed to install $tool via pipx"
done

echo -e "${GREEN}[SUCCESS]${NC} AI Toolchain installed."
