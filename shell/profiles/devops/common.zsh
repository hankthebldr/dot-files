# DevOps Profile
# Loadout for Build, Deploy, Monitoring, and Incident Response
export CLAW_PROFILE_THEME="devops"

export DEVOPS_WORKSPACE="$HOME/devops"
mkdir -p "$DEVOPS_WORKSPACE" 2>/dev/null

# ==========================================
# ALIASES — short, unprefixed, value-add only
# ==========================================
# (de-prefixed 2026-04-28: pure renames like dops-helm=helm dropped.
#  Compositions get short mnemonics. Use git/docker/kubectl/etc. directly.)

# --- Compositions worth keeping ---
alias dpsj="docker ps --format '{{json .}}' | jq -r '\"\(.ID) \(.Names) \(.Status)\"'"
alias kpodsj="kubectl get pods -A -o json | jq -r '.items[] | [.metadata.namespace, .metadata.name, .status.phase] | @csv'"
alias helmj="helm list -A -o json"
alias tfplan="terraform plan -out=tfplan"
alias tgplan="terragrunt run-all plan"

# Note: btop, watch, stern, podman, ansible-playbook etc. are used by their
# real binary names. `g`, `gst`, `gco`, `glg` etc. live in shell/aliases.zsh
# (global) so they're available everywhere, not just under devops.

# ==========================================
# QUICK REFERENCE
# ==========================================
devops-help() {
  local green='\e[38;2;63;185;80m'
  local purple='\e[38;2;188;140;255m'
  local dim='\e[38;2;139;148;158m'
  local white='\e[38;2;201;209;217m'
  local bold='\e[1m'
  local reset='\e[0m'

  echo ""
  echo -e "  ${purple}╭──────────────────────────────────────────────────────────╮${reset}"
  echo -e "  ${purple}│${reset}  ${bold}${green}DEVOPS PROFILE${reset} ${dim}— Quick Reference${reset}                        ${purple}│${reset}"
  echo -e "  ${purple}╰──────────────────────────────────────────────────────────╯${reset}"
  echo ""
  echo -e "  ${bold}${green}Container & K8s pipelines${reset}"
  echo -e "  ${white}dpsj${reset}      ${dim}docker ps as parsed JSON line${reset}"
  echo -e "  ${white}kpodsj${reset}    ${dim}all pods as namespace,name,phase CSV${reset}"
  echo -e "  ${white}helmj${reset}     ${dim}helm list -A -o json${reset}"
  echo ""
  echo -e "  ${bold}${green}Infrastructure as Code${reset}"
  echo -e "  ${white}tfplan${reset}    ${dim}terraform plan -out=tfplan${reset}"
  echo -e "  ${white}tgplan${reset}    ${dim}terragrunt run-all plan${reset}"
  echo ""
  echo -e "  ${bold}${green}Use directly${reset} ${dim}(no need for prefix aliases)${reset}"
  echo -e "  ${dim}docker · podman · kubectl · helm · terraform · ansible-playbook${reset}"
  echo -e "  ${dim}stern · shellcheck · btop · watch · gh · vault${reset}"
  echo ""
}

# ==========================================
# TOOL AVAILABILITY CHECK
# ==========================================
_devops_tool_check() {
  local green='\e[38;2;63;185;80m'
  local red='\e[38;2;248;81;73m'
  local purple='\e[38;2;188;140;255m'
  local dim='\e[38;2;139;148;158m'
  local white='\e[38;2;201;209;217m'
  local bold='\e[1m'
  local reset='\e[0m'

  local tools=(docker podman kubectl helm terraform terragrunt ansible shellcheck gh argocd stern vault)
  local found=0 missing=0

  echo ""
  echo -e "  ${bold}${purple}DevOps Toolchain Status${reset}"
  echo -e "  ${dim}──────────────────────────${reset}"
  for tool in "${tools[@]}"; do
    if command -v "$tool" &> /dev/null; then
      echo -e "  ${green}●${reset} ${white}${tool}${reset}"
      ((found++))
    else
      echo -e "  ${red}✗${reset} ${dim}${tool}${reset}"
      ((missing++))
    fi
  done
  echo -e "  ${dim}──────────────────────────${reset}"
  echo -e "  ${green}${found}${reset} ${dim}found${reset}  ${red}${missing}${reset} ${dim}missing${reset}"
  echo ""
}

# Profile banner handled by fastfetch (config-devops.jsonc)
