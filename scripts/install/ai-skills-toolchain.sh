#!/usr/bin/env bash

################################################################################
# AI Development Skills Toolchain — 2026 SOTA
#
# Curated, opinionated set of tools for building production AI/agent apps.
# Tiered so you can skip layers you don't need.
#
# Tiers:
#   1. Core: uv, LiteLLM, Pydantic v2, msgspec, Instructor, Outlines
#   2. Agents+RAG: LangGraph, Pydantic AI, LlamaIndex, DSPy, smolagents
#   3. Observability: Phoenix (Arize), Langfuse (self-host), OpenLLMetry
#   4. Data+notebooks: marimo, Polars, DuckDB, fastembed
#   5. Code intelligence: ast-grep, aider, sourcebot hint
#   6. Fine-tuning (GPU only): unsloth, axolotl, trl, accelerate, bitsandbytes
#
# Flags:
#   --tier 1|2|3|4|5|6   install only one tier
#   --skip-fine-tuning   skip tier 6 (the GPU/heavy install)
#   --langfuse-compose   write config/langfuse/docker-compose.yml only
#   --dry-run
#   --help
#
# Cross-platform: macOS (brew + pipx) and Linux (apt + pipx). Tier 6 is
# Linux-only since it requires CUDA.
################################################################################

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"

ONLY_TIER=""
SKIP_FINE_TUNING=false
LANGFUSE_ONLY=false
DRY_RUN=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --tier)              ONLY_TIER="$2"; shift ;;
        --skip-fine-tuning)  SKIP_FINE_TUNING=true ;;
        --langfuse-compose)  LANGFUSE_ONLY=true ;;
        --dry-run)           DRY_RUN=true ;;
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

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf '  [DRY] %s\n' "$*"
    else
        eval "$@"
    fi
}

# Run a tier only when --tier flag matches (or no filter given)
should_run_tier() {
    [[ -z "$ONLY_TIER" || "$ONLY_TIER" == "$1" ]]
}

# pipx wrapper that prefers `pipx upgrade` over re-install
pipx_install() {
    local pkg="$1"
    if pipx list 2>/dev/null | grep -q "package $pkg "; then
        log_info "$pkg already installed (upgrading)..."
        run "pipx upgrade '$pkg' 2>/dev/null || true"
    else
        log_info "Installing $pkg via pipx..."
        run "pipx install '$pkg' || log_warning '$pkg install failed'"
    fi
}

# venv wrapper for heavy stacks (vLLM, axolotl, etc.) — keeps deps off system Python
venv_install() {
    local name="$1"; shift
    local venv_dir="$HOME/.ai/$name"
    [[ -d "$venv_dir" ]] && { log_info "venv $name already exists at $venv_dir"; return 0; }
    log_info "Creating venv '$name' at $venv_dir..."
    run "mkdir -p '$venv_dir'"
    run "python3 -m venv '$venv_dir'"
    run "'$venv_dir/bin/pip' install --upgrade pip"
    run "'$venv_dir/bin/pip' install $*"
    log_info "Activate with: source $venv_dir/bin/activate"
}

# ── Langfuse compose file generator (used by --langfuse-compose) ──
write_langfuse_compose() {
    local dir="$DOTFILES_DIR/config/langfuse"
    mkdir -p "$dir"
    cat > "$dir/docker-compose.yml" <<'EOF'
# Langfuse self-hosted — LLM observability behind Tailscale.
# Reachable at: http://<bd790i.tailnet>:3000 after `docker compose up -d`.
# Default admin signup is enabled; lock down after first user.
services:
  langfuse-db:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_USER: langfuse
      POSTGRES_PASSWORD: ${LANGFUSE_DB_PASSWORD:-changeme}
      POSTGRES_DB: langfuse
    volumes:
      - langfuse-db-data:/var/lib/postgresql/data
  langfuse:
    image: langfuse/langfuse:3
    restart: unless-stopped
    depends_on: [langfuse-db]
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://langfuse:${LANGFUSE_DB_PASSWORD:-changeme}@langfuse-db:5432/langfuse
      NEXTAUTH_URL: ${LANGFUSE_PUBLIC_URL:-http://localhost:3000}
      NEXTAUTH_SECRET: ${LANGFUSE_NEXTAUTH_SECRET:-CHANGE_ME_RUN_openssl_rand_base64_32}
      SALT: ${LANGFUSE_SALT:-CHANGE_ME_RUN_openssl_rand_base64_32}
      TELEMETRY_ENABLED: "false"
volumes:
  langfuse-db-data:
EOF
    log_success "wrote $dir/docker-compose.yml"
    log_info "Generate secrets: openssl rand -base64 32"
    log_info "Deploy on BD790i: cd $dir && docker compose up -d"
}

# Short-circuit for Langfuse-only mode
if [[ "$LANGFUSE_ONLY" == "true" ]]; then
    write_langfuse_compose
    exit 0
fi

log_info "── AI Skills toolchain install (OS: $OS_TYPE, pkg: $PKG_MANAGER) ──"

# Ensure pipx + uv are present — both are foundational
if ! command -v pipx &>/dev/null; then
    log_info "Installing pipx..."
    case "$PKG_MANAGER" in
        brew) run "brew install pipx" ;;
        apt)  run "sudo apt-get install -y pipx || python3 -m pip install --user pipx" ;;
        *)    run "python3 -m pip install --user pipx" ;;
    esac
    command -v pipx &>/dev/null && run "pipx ensurepath"
fi
if ! command -v uv &>/dev/null; then
    log_info "Installing uv (Astral's fast Python package manager)..."
    case "$PKG_MANAGER" in
        brew) run "brew install uv" ;;
        *)    run "curl -fsSL https://astral.sh/uv/install.sh | sh" ;;
    esac
fi

# ─────────────────────────────────────────────
# Tier 1 — Core: structured output, multi-provider proxy
# ─────────────────────────────────────────────
if should_run_tier 1; then
    log_info "── Tier 1: Core ──"
    # LiteLLM — single unified API for 100+ LLM providers. Also a proxy server.
    pipx_install litellm
    pipx_install instructor
    # Pydantic / msgspec are library deps; install in venvs only when needed.
    # Outlines — constrained generation (regex/JSON schema/CFG).
    pipx_install outlines-core 2>/dev/null || pipx_install outlines
fi

# ─────────────────────────────────────────────
# Tier 2 — Agents + RAG
# ─────────────────────────────────────────────
if should_run_tier 2; then
    log_info "── Tier 2: Agents + RAG ──"
    # Pydantic AI — type-safe agents (Pydantic v2 native, by the Pydantic team)
    pipx_install pydantic-ai-slim
    # LangGraph — graph-based agent orchestration (most active framework in 2026)
    pipx_install langgraph-cli
    # LlamaIndex — RAG (CLI tools; library installs into project venvs)
    pipx_install llama-index-cli
    # DSPy — programmatic LLM optimization
    pipx_install dspy-ai 2>/dev/null || pipx_install dspy
    # smolagents — HuggingFace's code-first agent framework
    pipx_install smolagents
    # Aider — terminal AI pair programmer (idempotent: openrouter.sh may have installed already)
    pipx_install aider-chat
fi

# ─────────────────────────────────────────────
# Tier 3 — Observability + eval (self-hostable preferred)
# ─────────────────────────────────────────────
if should_run_tier 3; then
    log_info "── Tier 3: Observability + eval ──"
    # Phoenix — Arize's OSS observability/eval. CLI for local mode; production runs as Docker.
    pipx_install arize-phoenix
    # Inspect AI — UK AISI eval framework (well-engineered, becoming the standard for agent evals)
    pipx_install inspect-ai
    # OpenLLMetry — OpenTelemetry SDK for LLM apps
    pipx_install traceloop-sdk 2>/dev/null || log_warning "traceloop-sdk install failed (library-only, not a CLI)"
    # Langfuse — self-hosted observability; deploy via docker-compose
    write_langfuse_compose
fi

# ─────────────────────────────────────────────
# Tier 4 — Data + reactive notebooks
# ─────────────────────────────────────────────
if should_run_tier 4; then
    log_info "── Tier 4: Data + notebooks ──"
    # marimo — reactive Python notebooks (Jupyter replacement for new dev)
    pipx_install marimo
    # DuckDB CLI — analytical SQL on local files (Parquet/CSV/JSON)
    case "$PKG_MANAGER" in
        brew) command -v duckdb &>/dev/null || run "brew install duckdb" ;;
        apt)
            if ! command -v duckdb &>/dev/null; then
                # No apt package; install via official binary
                arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
                tmp=$(mktemp -d)
                run "curl -fsSL 'https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-${arch}.zip' -o '$tmp/duckdb.zip'"
                run "unzip -q '$tmp/duckdb.zip' -d '$tmp'"
                run "sudo install -m 0755 '$tmp/duckdb' /usr/local/bin/duckdb"
                run "rm -rf '$tmp'"
            fi
            ;;
    esac
    # Polars CLI — fast dataframe CLI (Rust binary)
    pipx_install polars-cli 2>/dev/null || log_warning "polars-cli pipx install failed (use `cargo install polars-cli` or skip)"
    # fastembed — ONNX-based local embeddings (no GPU required)
    pipx_install fastembed 2>/dev/null || log_warning "fastembed is library-only (install in project venv)"
fi

# ─────────────────────────────────────────────
# Tier 5 — Code intelligence
# ─────────────────────────────────────────────
if should_run_tier 5; then
    log_info "── Tier 5: Code intelligence ──"
    # ast-grep — semantic find/replace (better than grep for code refactors)
    case "$PKG_MANAGER" in
        brew) command -v ast-grep &>/dev/null || run "brew install ast-grep" ;;
        apt)
            if ! command -v ast-grep &>/dev/null; then
                if command -v brew &>/dev/null; then
                    run "brew install ast-grep"
                elif command -v cargo &>/dev/null; then
                    run "cargo install ast-grep --locked"
                else
                    log_warning "ast-grep needs Linuxbrew or cargo (skipping)"
                fi
            fi
            ;;
    esac
    # tree-sitter CLI — language grammars for code parsing
    if command -v npm &>/dev/null; then
        run "npm install -g tree-sitter-cli 2>/dev/null || sudo npm install -g tree-sitter-cli"
    fi
    log_info "Sourcebot (code search) — self-host on K3s:"
    log_info "  kubectl apply -f https://docs.sourcebot.dev/install/k8s.yaml"
fi

# ─────────────────────────────────────────────
# Tier 6 — Fine-tuning (Blackwell GPU required)
# ─────────────────────────────────────────────
if should_run_tier 6; then
    if [[ "$SKIP_FINE_TUNING" == "true" ]]; then
        log_info "skip: tier 6 (--skip-fine-tuning)"
    elif [[ "$OS_TYPE" == "macos" ]]; then
        log_warning "Tier 6 is GPU/Linux only. Use MLX on Mac instead:"
        log_warning "  pip install mlx mlx-lm"
    elif ! command -v nvidia-smi &>/dev/null; then
        log_warning "Tier 6 needs an NVIDIA GPU. Run: claw install ai-workstation first."
    else
        log_info "── Tier 6: Fine-tuning (GPU stack) ──"
        # Put each stack in its own venv — they have heavy/conflicting deps.
        # PyTorch nightly with cu128 is recommended on Blackwell for FP4.
        venv_install training \
            "torch torchvision --index-url https://download.pytorch.org/whl/cu128" \
            "transformers datasets accelerate peft trl bitsandbytes wandb"

        venv_install unsloth \
            "torch --index-url https://download.pytorch.org/whl/cu128" \
            "'unsloth[cu128-torch260] @ git+https://github.com/unslothai/unsloth.git'"

        log_info "Axolotl — config-driven fine-tuning. Install:"
        log_info "  python3 -m venv ~/.ai/axolotl && source ~/.ai/axolotl/bin/activate"
        log_info "  pip install axolotl[flash-attn,deepspeed]"
    fi
fi

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
cat <<EOF

  ───────────────────────────────────────────────────────
  AI skills toolchain install complete.
  ───────────────────────────────────────────────────────

  Try it:
    litellm --model claude-haiku-4-5 --message "hello"           # multi-provider proxy
    aider --model anthropic/claude-opus-4-7                       # AI pair programmer
    marimo new                                                    # reactive notebook
    instructor jobs view                                          # structured output CLI

  Self-hosted observability (Langfuse) on BD790i:
    cd $DOTFILES_DIR/config/langfuse
    openssl rand -base64 32  # use for LANGFUSE_NEXTAUTH_SECRET + LANGFUSE_SALT
    docker compose up -d
    # then open http://<bd790i.tailnet>:3000

  Build an agent (LangGraph):
    langgraph dev    # local studio at http://localhost:8123

  RAG project (LlamaIndex):
    llamaindex-cli rag --create-llama
    llamaindex-cli rag --question "what is X?" --files docs/*.md

  Eval an agent (Inspect AI — UK AISI):
    inspect eval my_task.py --model anthropic/claude-opus-4-7

  Fine-tune (tier 6, GPU):
    source ~/.ai/training/bin/activate
    # use trl SFTTrainer or unsloth notebook examples

EOF

log_success "AI skills install complete."
