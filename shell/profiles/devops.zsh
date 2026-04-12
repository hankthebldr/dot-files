# DevOps Profile
# Loadout for Build, Deploy, Monitoring, and Incident Response
export CLAW_PROFILE_THEME="devops"

# ==========================================
# ENVIRONMENT VARIABLES
# ==========================================
export DEVOPS_WORKSPACE="$HOME/devops"
mkdir -p "$DEVOPS_WORKSPACE"

# ==========================================
# CATEGORIZED ALIASES & PIPELINES
# ==========================================

# --- CI/CD & Orchestration ---
alias dops-git="git status -s"
alias dops-docker="docker ps --format '{{json .}}' | jq -r '\"\(.ID) \(.Names) \(.Status)\"'"
alias dops-pod="podman ps"

# --- Infrastructure as Code ---
alias dops-tf="terraform plan -out=tfplan"
alias dops-tg="terragrunt run-all plan"
alias dops-ans="ansible-playbook"
alias dops-lint="shellcheck"

# --- Kubernetes ---
alias dops-k="kubectl get pods -A -o json | jq -r '.items[] | [.metadata.namespace, .metadata.name, .status.phase] | @csv' | csvkit"
alias dops-helm="helm list -A -o json"
alias dops-stern="stern"

# --- Observability ---
alias dops-watch="watch -n 1"
alias dops-top="btop"

# ==========================================
# HELPER FUNCTIONS
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
  echo -e "  ${bold}${green}CI/CD & Orchestration${reset}"
  echo -e "  ${white}dops-git${reset}      ${dim}Git status (short)${reset}"
  echo -e "  ${white}dops-docker${reset}   ${dim}Docker containers (json/jq)${reset}"
  echo -e "  ${white}dops-pod${reset}      ${dim}Podman containers${reset}"
  echo ""
  echo -e "  ${bold}${green}Infrastructure as Code${reset}"
  echo -e "  ${white}dops-tf${reset}       ${dim}Terraform plan${reset}"
  echo -e "  ${white}dops-tg${reset}       ${dim}Terragrunt run-all plan${reset}"
  echo -e "  ${white}dops-ans${reset}      ${dim}Ansible playbook${reset}"
  echo -e "  ${white}dops-lint${reset}     ${dim}ShellCheck linter${reset}"
  echo ""
  echo -e "  ${bold}${green}Kubernetes${reset}"
  echo -e "  ${white}dops-k${reset}        ${dim}All pods (json/csv)${reset}"
  echo -e "  ${white}dops-helm${reset}     ${dim}Helm releases (all namespaces)${reset}"
  echo -e "  ${white}dops-stern${reset}    ${dim}Stern log tailing${reset}"
  echo ""
  echo -e "  ${bold}${green}Observability${reset}"
  echo -e "  ${white}dops-watch${reset}    ${dim}Watch (1s interval)${reset}"
  echo -e "  ${white}dops-top${reset}      ${dim}btop system monitor${reset}"
  echo ""
}

_devops_tool_check() {
  local green='\e[38;2;63;185;80m'
  local red='\e[38;2;248;81;73m'
  local purple='\e[38;2;188;140;255m'
  local dim='\e[38;2;139;148;158m'
  local white='\e[38;2;201;209;217m'
  local bold='\e[1m'
  local reset='\e[0m'

  local tools=(docker podman kubectl helm terraform terragrunt ansible shellcheck gh argocd stern vault)
  local found=0
  local missing=0

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
