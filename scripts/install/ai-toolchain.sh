#!/usr/bin/env bash
################################################################################
# AI / LLM Toolchain — Cross-Platform
#
# Local inference (llama.cpp, ollama), vector DBs, transcription, GenAI SDKs
# (Anthropic / OpenAI / Cohere / HuggingFace), agentic frameworks (langchain,
# aider, ADK), and the Claude Agent SDK. Many tools have heterogeneous install
# paths — system pkg, pipx, npm, vendor curl scripts. The lib + extras hybrid
# handles all four cleanly.
#
# Spec: docs/superpowers/specs/2026-05-06-hermes-openrouter-design.md
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toolchain-runner.sh"

TOOLCHAIN_TITLE="AI  TOOLCHAIN"
TOOLCHAIN_CLASS="NEUROMANCER  LOADOUT"
TOOLCHAIN_TAG="prompted their way out of a parking ticket · 70B model on a thumb drive"

case "$(uname -m)" in
    x86_64|amd64) _arch="amd64" ;;
    aarch64|arm64) _arch="arm64" ;;
    *) _arch="amd64" ;;
esac

# ── TOOL MAPPING ───────────────────────────────────────────────────────────
# >>> HENRY: ollama on Linux is `curl https://ollama.com/install.sh | sh` —
#     the lib's curl: fallback would download the script as a binary, which
#     is wrong. Kept as manual: so you decide whether to trust the pipe. If
#     you want auto-install, switch to toolchain_extras and run the curl-sh
#     pattern there.
TOOLCHAIN_MAP=(
    # ── 01. Local Inference ────────────────────────────────────────────────
    "llama-cli|llama.cpp|?|manual:https://github.com/ggerganov/llama.cpp#build|local LLM inference (apt: build from source)"
    "whisper-cli|whisper-cpp|?|manual:https://github.com/ggerganov/whisper.cpp#quick-start|speech-to-text (apt: build from source)"
    "ollama|ollama|?|manual:https://ollama.com/install.sh|local LLM runtime — Linux: curl install.sh | sh"

    # ── 02. Vector / Storage ───────────────────────────────────────────────
    "qdrant|qdrant-cli|?|manual:https://qdrant.tech/documentation/cloud/quickstart-cloud/|vector DB CLI"

    # ── 03. Media / Audio ──────────────────────────────────────────────────
    "ffmpeg|ffmpeg|ffmpeg|none|video/audio toolkit"

    # ── 04. Data Utilities ─────────────────────────────────────────────────
    "jq|jq|jq|none|JSON swiss army knife"
    "yq|yq|?|curl:https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${_arch}|YAML jq"
    "dasel|dasel|?|go:github.com/tomwright/dasel/v2/cmd/dasel|JSON/YAML/XML/TOML parser"

    # ── 05. Terminal Chat ──────────────────────────────────────────────────
    "aichat|aichat|?|cargo|multi-provider terminal chat client"

    # ── 06. macOS-only ─────────────────────────────────────────────────────
    "cliclick|cliclick|?|skip-linux|macOS-only mouse/keyboard automation"

    # ── 07. Build Toolchain (Linux) ────────────────────────────────────────
    "gcc|?|build-essential|none|compiler — required for llama.cpp/whisper.cpp builds"
)

declare -A TOOLCHAIN_SECTIONS=(
    [0]="01|Local  Inference"
    [3]="02|Vector  /  Storage"
    [4]="03|Media  /  Audio"
    [5]="04|Data  Utilities"
    [8]="05|Terminal  Chat"
    [9]="06|macOS-only  Helpers"
    [10]="07|Build  Toolchain"
)

# ── Pre-install hook: ensure pipx is available (heavy pipx use in extras) ─
toolchain_preflight_extras() {
    if ! command -v pipx &>/dev/null; then
        log_info "installing pipx (required for AI SDK installs)"
        case "$PKG_MANAGER" in
            brew) brew install pipx && pipx ensurepath ;;
            apt)
                sudo apt-get install -y pipx 2>/dev/null \
                    || python3 -m pip install --user pipx
                command -v pipx &>/dev/null && pipx ensurepath
                ;;
            *) python3 -m pip install --user pipx ;;
        esac
    fi
}

# ── Post-install: pipx SDKs, npm SDKs, hermes, openrouter ────────────────
toolchain_extras() {
    # ── pipx SDKs ──────────────────────────────────────────────────────────
    _section 8 "Python  AI  SDKs  (pipx)"
    if ! command -v pipx &>/dev/null; then
        log_error "pipx not available — skipping Python SDKs"
        RESULT_FAILED+=("python-sdks")
    else
        local pipx_tools=(
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
        local tool
        for tool in "${pipx_tools[@]}"; do
            if pipx list 2>/dev/null | grep -q "package $tool "; then
                log_skip "$tool — already installed via pipx"
                RESULT_SKIPPED+=("$tool")
            else
                log_info "pipx install $tool"
                if pipx install "$tool" 2>/dev/null || pipx upgrade "$tool" 2>/dev/null; then
                    RESULT_INSTALLED+=("$tool (pipx)")
                else
                    log_warning "failed: $tool"
                    RESULT_FAILED+=("$tool")
                fi
            fi
        done
    fi

    # ── Agent CLIs (npm) ──────────────────────────────────────────────────
    _section 9 "Agent  CLIs  (npm)"
    if ! command -v npm &>/dev/null; then
        log_warning "npm not found — skipping npm-based agent CLIs (install Node.js first)"
        RESULT_SKIPPED+=("npm-agent-clis (no npm)")
    else
        local npm_agents=(
            "@anthropic-ai/claude-agent-sdk"
            "@google/gemini-cli"
        )
        local pkg
        for pkg in "${npm_agents[@]}"; do
            if npm list -g "$pkg" &>/dev/null 2>&1; then
                log_skip "$pkg already installed globally"
                RESULT_SKIPPED+=("$pkg")
            else
                log_info "npm install -g $pkg"
                if npm install -g "$pkg"; then
                    RESULT_INSTALLED+=("$pkg")
                else
                    RESULT_FAILED+=("$pkg")
                fi
            fi
        done
    fi

    # ── Hermes + OpenRouter (local installers) ────────────────────────────
    _section 10 "Hermes  +  OpenRouter"
    local hermes="$SCRIPT_DIR/hermes.sh"
    local openrouter="$SCRIPT_DIR/openrouter.sh"

    if [[ -f "$hermes" ]]; then
        log_info "→ running hermes.sh"
        if bash "$hermes"; then
            RESULT_INSTALLED+=("hermes")
        else
            log_warning "hermes install reported errors"
            RESULT_FAILED+=("hermes")
        fi
    else
        log_skip "hermes.sh not found — skipping"
    fi

    if [[ -f "$openrouter" ]]; then
        log_info "→ running openrouter.sh"
        if bash "$openrouter"; then
            RESULT_INSTALLED+=("openrouter")
        else
            log_warning "openrouter install reported errors"
            RESULT_FAILED+=("openrouter")
        fi
    else
        log_skip "openrouter.sh not found — skipping"
    fi
}

toolchain_run
