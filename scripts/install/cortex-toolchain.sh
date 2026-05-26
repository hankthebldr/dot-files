#!/usr/bin/env bash
################################################################################
# Cortex Toolchain — Cross-Platform (Palo Alto Networks)
#
# demisto-sdk (XSOAR), pan-os-python (panapi), panos-cli (Go), Cortex CLI.
# This toolchain is mostly sequential procedural setup rather than a flat
# package list, so most of the work lives in toolchain_extras().
#
# >>> HENRY: you work on this product family — please review extras logic.
#     The Cortex CLI in particular is tenant-specific and the install URL
#     pattern in your console may differ from what's stubbed here.
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toolchain-runner.sh"

TOOLCHAIN_TITLE="CORTEX  TOOLCHAIN"
TOOLCHAIN_CLASS="GHOST-IN-THE-XSIAM"
TOOLCHAIN_TAG="knows what XSOAR stands for · actually likes it"

CORTEX_WORKSPACE="${CORTEX_WORKSPACE:-$HOME/.cortex}"

# Most tools here are Python or Go — the MAP is intentionally short. The
# heavy lifting happens in toolchain_extras().
TOOLCHAIN_MAP=(
    # ── 01. Standalone CLI Tools ───────────────────────────────────────────
    "demisto-sdk|?|?|pipx|XSOAR content development SDK"
    "panos-cli|?|?|go:github.com/PaloAltoNetworks/panos-cli|PAN-OS Go CLI"
)

declare -A TOOLCHAIN_SECTIONS=(
    [0]="01|Standalone  CLI  Tools"
)

# ── Pre-install hook ──────────────────────────────────────────────────────
toolchain_preflight_extras() {
    # pipx: required for demisto-sdk + most other PANW python tools.
    if ! command -v pipx &>/dev/null; then
        log_info "installing pipx (required for demisto-sdk)"
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

    # Go: required for panos-cli. If missing, that MAP row will fail-fast.
    if ! command -v go &>/dev/null; then
        log_warning "go not found — panos-cli will be skipped"
        log_info "install golang: ${c_cyan}brew install go${c_reset} or ${c_cyan}sudo apt-get install golang${c_reset}"
    fi
}

# ── Post-install: workspace + Python venv + Cortex CLI hint ───────────────
toolchain_extras() {
    _section 2 "Cortex  Workspace"
    if [[ -d "$CORTEX_WORKSPACE" ]]; then
        log_skip "workspace exists: $CORTEX_WORKSPACE"
        RESULT_SKIPPED+=("cortex-workspace")
    else
        log_info "creating workspace at ${c_white}${CORTEX_WORKSPACE}${c_reset}"
        mkdir -p "$CORTEX_WORKSPACE"
        RESULT_INSTALLED+=("cortex-workspace")
    fi

    _section 3 "PAN-OS  Python  Venv"
    local venv_dir="$CORTEX_WORKSPACE/venv"
    if [[ -d "$venv_dir" && -f "$venv_dir/bin/pip" ]]; then
        log_skip "venv already exists at $venv_dir"
        RESULT_SKIPPED+=("pan-os-python venv")
    else
        log_info "creating Python venv at ${c_white}${venv_dir}${c_reset}"
        if python3 -m venv "$venv_dir" 2>/dev/null; then
            log_info "installing pan-os-python + panapi into venv..."
            if "$venv_dir/bin/pip" install --upgrade pip --quiet \
                && "$venv_dir/bin/pip" install pan-os-python panapi --quiet; then
                RESULT_INSTALLED+=("pan-os-python venv")
                log_success "venv ready — activate with: source $venv_dir/bin/activate"
            else
                RESULT_FAILED+=("pan-os-python venv")
            fi
        else
            log_error "python3 -m venv failed — ensure python3-venv is installed"
            RESULT_FAILED+=("pan-os-python venv")
        fi
    fi

    _section 4 "Cortex  CLI"
    if command -v cortexcli &>/dev/null; then
        log_skip "cortexcli already installed: $(cortexcli -v 2>/dev/null || echo installed)"
        RESULT_SKIPPED+=("cortexcli")
    else
        log_warning "Cortex CLI is tenant-specific — download from your console:"
        log_info "  ${c_cyan}Settings → Code Security → Integrations → Cortex CLI${c_reset}"
        log_info "  ${c_dim}or paste the curl command your tenant provides${c_reset}"
        RESULT_SKIPPED+=("cortexcli (tenant-specific)")
    fi
}

toolchain_run
