# Cloud Profile
# Loadout for AWS, GCP, Kubernetes, and Terraform
export CLAW_PROFILE_THEME="cloud"

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# ==========================================
# ALIASES — short, unprefixed, value-add only
# ==========================================
# (de-prefixed 2026-04-28: dropped cloud-* renames; kept compositions under
#  short mnemonics. AWS/GCP/Terraform/K8s tools are used as-is by their real
#  binary names — that's what muscle memory expects.)

# --- AWS (json output for downstream piping into jq) ---
alias awsj="aws --output json"
alias awssso="aws sso login"
alias s3ls="aws s3 ls --output json | jq ."

# --- GCP ---
alias gcj="gcloud --format=json"

# --- Terraform / Terragrunt ---
alias tff="terraform fmt -recursive"
alias tfv="terraform validate"
alias tfp="terraform plan -out=tfplan -json | jq ."
alias tgp="terragrunt run-all plan"
alias tfsecj="tfsec --format json"
alias checkovj="checkov -o json"

# --- Kubernetes (k=kubectl is global; only compositions here) ---
alias helmj="helm list -o json | jq ."
alias sternj="stern -o json"

# ==========================================
# QUICK REFERENCE
# ==========================================
cloud-help() {
  local cyan='\e[38;2;88;166;255m'
  local green='\e[38;2;63;185;80m'
  local purple='\e[38;2;188;140;255m'
  local orange='\e[38;2;210;153;34m'
  local dim='\e[38;2;139;148;158m'
  local white='\e[38;2;201;209;217m'
  local bold='\e[1m'
  local reset='\e[0m'

  echo ""
  echo "${cyan}  ${bold}╭──────────────────────────────────────────────────────────╮${reset}"
  echo "${cyan}  ${bold}│  CLOUD PROFILE — Quick Reference                         │${reset}"
  echo "${cyan}  ${bold}╰──────────────────────────────────────────────────────────╯${reset}"
  echo ""
  echo "  ${orange}${bold}AWS${reset}"
  echo "  ${green}awsj${reset}      ${dim}aws --output json${reset}"
  echo "  ${green}awssso${reset}    ${dim}aws sso login${reset}"
  echo "  ${green}s3ls${reset}      ${dim}aws s3 ls --output json | jq .${reset}"
  echo ""
  echo "  ${orange}${bold}GCP${reset}"
  echo "  ${green}gcj${reset}       ${dim}gcloud --format=json${reset}"
  echo ""
  echo "  ${orange}${bold}Kubernetes${reset}  ${dim}(k=kubectl is global; use kubectx/kubens/k9s/stern directly)${reset}"
  echo "  ${green}helmj${reset}     ${dim}helm list -o json | jq .${reset}"
  echo "  ${green}sternj${reset}    ${dim}stern -o json${reset}"
  echo ""
  echo "  ${orange}${bold}Infrastructure as Code${reset}"
  echo "  ${green}tff${reset}       ${dim}terraform fmt -recursive${reset}"
  echo "  ${green}tfv${reset}       ${dim}terraform validate${reset}"
  echo "  ${green}tfp${reset}       ${dim}terraform plan -json | jq .${reset}"
  echo "  ${green}tgp${reset}       ${dim}terragrunt run-all plan${reset}"
  echo "  ${green}tfsecj${reset}    ${dim}tfsec --format json${reset}"
  echo "  ${green}checkovj${reset}  ${dim}checkov -o json${reset}"
  echo ""
  echo "  ${purple}${bold}Diagnostics${reset}"
  echo "  ${green}cloud-help${reset}      ${dim}this card${reset}"
  echo "  ${green}_cloud_tool_check${reset} ${dim}toolchain status${reset}"
  echo ""
}

# ==========================================
# TOOL AVAILABILITY CHECK
# ==========================================
_cloud_tool_check() {
  local green='\e[38;2;63;185;80m'
  local red='\e[38;2;248;81;73m'
  local white='\e[38;2;201;209;217m'
  local cyan='\e[38;2;88;166;255m'
  local dim='\e[38;2;139;148;158m'
  local bold='\e[1m'
  local reset='\e[0m'

  local tools=(
    "aws:awscli" "kubectl:kubectl" "helm:helm"
    "terraform:terraform" "terragrunt:terragrunt"
    "k9s:k9s" "stern:stern" "gcloud:google-cloud-sdk"
    "eksctl:eksctl" "tfsec:tfsec" "checkov:checkov"
  )
  local found=0 missing=0
  local total=${#tools[@]}

  echo ""
  echo "${cyan}${bold}  Cloud Toolchain Status${reset}"
  echo "${dim}  ────────────────────────────────${reset}"
  for entry in "${tools[@]}"; do
    local cmd="${entry%%:*}"
    local pkg="${entry##*:}"
    if command -v "$cmd" &> /dev/null; then
      echo "  ${green}●${reset} ${white}${cmd}${reset}"
      ((found++))
    else
      echo "  ${red}✗${reset} ${white}${cmd}${reset}  ${dim}→ brew install ${pkg}${reset}"
      ((missing++))
    fi
  done
  echo "${dim}  ────────────────────────────────${reset}"
  echo "  ${green}${found}${reset}${dim}/${total} available${reset}  ${red}${missing} missing${reset}"
  echo ""
}

# Profile banner handled by fastfetch (config-cloud.jsonc)
