# Cortex Profile (Palo Alto Networks Toolset)
# Loadout for Cortex XSOAR, XSIAM, XDR, and PAN-OS APIs

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
alias pan-docs="claw_open https://pan.dev"
alias cortex-docs="claw_open https://docs.paloaltonetworks.com/cortex"
alias xsoar-docs="claw_open https://xsoar.pan.dev"

# ==========================================
# HELPER FUNCTIONS
# ==========================================

# Styled reference card for all cortex/xsoar/pan aliases
cortex-help() {
  local or='\e[38;2;255;102;0m'      # orange-red (primary)
  local rd='\e[38;2;255;123;114m'     # red (borders)
  local dm='\e[38;2;139;148;158m'     # dim
  local wh='\e[38;2;201;209;217m'     # white
  local bd='\e[1m'                    # bold
  local rs='\e[0m'                    # reset

  echo ""
  echo -e "  ${rd}╭──────────────────────────────────────────────────────────╮${rs}"
  echo -e "  ${rd}│${rs}  ${bd}${or}CORTEX PROFILE${rs} ${dm}— Quick Reference${rs}                        ${rd}│${rs}"
  echo -e "  ${rd}╰──────────────────────────────────────────────────────────╯${rs}"
  echo ""
  echo -e "  ${bd}${or}Cortex CLI${rs}"
  echo -e "  ${wh}cortex-scan${rs}       ${dm}CWP compute scan${rs}"
  echo -e "  ${wh}cortex-api${rs}        ${dm}API security scan${rs}"
  echo -e "  ${wh}cortex-auth${rs}       ${dm}Set authentication config${rs}"
  echo -e "  ${wh}cortex-update${rs}     ${dm}Update cortexcli${rs}"
  echo ""
  echo -e "  ${bd}${or}XSOAR / XSIAM${rs}"
  echo -e "  ${wh}xsoar-format${rs}      ${dm}Format content items${rs}"
  echo -e "  ${wh}xsoar-lint${rs}        ${dm}Lint content items${rs}"
  echo -e "  ${wh}xsoar-pull${rs}        ${dm}Download from server${rs}"
  echo -e "  ${wh}xsoar-upload${rs}      ${dm}Upload content items${rs}"
  echo -e "  ${wh}xsoar-validate${rs}    ${dm}Validate content items${rs}"
  echo ""
  echo -e "  ${bd}${or}PAN-OS SDK${rs}"
  echo -e "  ${wh}pan-fw${rs}            ${dm}panos-cli firewall interface${rs}"
  echo -e "  ${wh}pan-connect${rs}       ${dm}Activate PAN-OS Python venv${rs}"
  echo ""
  echo -e "  ${bd}${or}Documentation${rs}"
  echo -e "  ${wh}pan-docs${rs}          ${dm}Open pan.dev${rs}"
  echo -e "  ${wh}cortex-docs${rs}       ${dm}Open Cortex documentation${rs}"
  echo -e "  ${wh}xsoar-docs${rs}        ${dm}Open XSOAR developer docs${rs}"
  echo ""
  echo -e "  ${bd}${or}AI helpers${rs} ${dm}(via claw registry — available from any profile)${rs}"
  echo -e "  ${wh}claw claude${rs}       ${dm}Anthropic Claude Code${rs}"
  echo -e "  ${wh}claw gemini${rs}       ${dm}Google Gemini CLI${rs}"
  echo ""
}

# Check availability of cortex profile toolchain dependencies
_cortex_tool_check() {
  local gn='\e[38;2;63;185;80m'       # green
  local rd='\e[38;2;255;123;114m'     # red
  local or='\e[38;2;255;102;0m'       # orange-red
  local dm='\e[38;2;139;148;158m'     # dim
  local wh='\e[38;2;201;209;217m'     # white
  local bd='\e[1m'                    # bold
  local rs='\e[0m'                    # reset

  local found=0
  local total=5

  echo ""
  echo -e "  ${bd}${or}Cortex Toolchain Status${rs}"
  echo -e "  ${dm}─────────────────────────────${rs}"

  # demisto-sdk
  if command -v demisto-sdk &> /dev/null; then
    echo -e "  ${gn}\u25cf${rs} ${wh}demisto-sdk${rs}"
    ((found++))
  else
    echo -e "  ${rd}\u2717${rs} ${dm}demisto-sdk${rs}"
  fi

  # cortexcli / cortex-cli
  if command -v cortexcli &> /dev/null || command -v cortex-cli &> /dev/null; then
    echo -e "  ${gn}\u25cf${rs} ${wh}cortexcli${rs}"
    ((found++))
  else
    echo -e "  ${rd}\u2717${rs} ${dm}cortexcli${rs}"
  fi

  # python3
  if command -v python3 &> /dev/null; then
    echo -e "  ${gn}\u25cf${rs} ${wh}python3${rs}"
    ((found++))
  else
    echo -e "  ${rd}\u2717${rs} ${dm}python3${rs}"
  fi

  # pan-os-python
  if python3 -c "import panos" 2>/dev/null; then
    echo -e "  ${gn}\u25cf${rs} ${wh}pan-os-python${rs}"
    ((found++))
  else
    echo -e "  ${rd}\u2717${rs} ${dm}pan-os-python${rs}"
  fi

  # panos-cli
  if command -v panos-cli &> /dev/null; then
    echo -e "  ${gn}\u25cf${rs} ${wh}panos-cli${rs}"
    ((found++))
  else
    echo -e "  ${rd}\u2717${rs} ${dm}panos-cli${rs}"
  fi

  echo ""
  echo -e "  ${wh}${found}${rs}${dm}/${total} tools available${rs}"
  echo ""
}

# Profile banner handled by fastfetch (config-cortex.jsonc)
