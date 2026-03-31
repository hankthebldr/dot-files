# Cortex Profile (Palo Alto Networks Toolset)
# Loadout for Cortex XSOAR, XSIAM, XDR, and PAN-OS APIs
export CLAW_PROFILE_THEME="cortex"

# ==========================================
# ENVIRONMENT VARIABLES
# ==========================================
export CORTEX_WORKSPACE="$HOME/.cortex"

# Auto-create workspace directory structure
mkdir -p "$CORTEX_WORKSPACE"/{playbooks,scripts,loot,config}

# Automatically jump to the workspace directory
cd "$CORTEX_WORKSPACE" || true

# ==========================================
# CORTEX CLI ALIASES
# ==========================================
# Wrapper around cortexcli for Cloud Workload Protection (CWP) and API Security
alias cortex-scan="cortexcli compute scan"
alias cortex-api="cortexcli api scan"
alias cortex-auth="cortexcli config set auth"
alias cortex-update="cortexcli update"

# ==========================================
# CORTEX XSOAR / XSIAM (demisto-sdk) ALIASES
# ==========================================
# Formatting, linting, syncing, and deploying playbooks/scripts
alias xsoar-format="demisto-sdk format -i"
alias xsoar-lint="demisto-sdk lint -i"
alias xsoar-pull="demisto-sdk download"
alias xsoar-upload="demisto-sdk upload -i"
alias xsoar-validate="demisto-sdk validate -i"

# ==========================================
# PALO ALTO SDK SCRIPTS
# ==========================================
# Quick access to panos-cli for firewall interactions
alias pan-fw="panos-cli"

# Python SDK Helpers (Make sure you have an environment with pan-os-python/panapi)
alias pan-connect="source $CORTEX_WORKSPACE/venv/bin/activate && echo 'PAN-OS Python Environment Activated'"

# ==========================================
# DOCUMENTATION & PAN.DEV SHORTCUTS
# ==========================================
alias pan-docs="open https://pan.dev"
alias cortex-docs="open https://docs.paloaltonetworks.com/cortex"
alias xsoar-docs="open https://xsoar.pan.dev"

# Profile banner handled by fastfetch (config-cortex.jsonc)
