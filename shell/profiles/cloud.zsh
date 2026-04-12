# Cloud Profile
# Loadout for AWS, GCP, Kubernetes, and Terraform
export CLAW_PROFILE_THEME="cloud"

# Cloud specific environment variables
export KUBECONFIG="$HOME/.kube/config"

# ==========================================
# CATEGORIZED ALIASES & PIPELINES
# ==========================================

# --- AWS Outputs ---
alias cloud-aws="aws --output json"
alias cloud-aws-sso="aws sso login"
alias cloud-s3="aws s3 ls --output json | jq ."

# --- GCP Outputs ---
alias cloud-gcp="gcloud --format=json"

# --- Infrastructure ---
alias cloud-tff="terraform fmt -recursive"
alias cloud-tfv="terraform validate"
alias cloud-tfp="terraform plan -out=tfplan -json | jq ."
alias cloud-tg="terragrunt run-all plan"
alias cloud-tfsec="tfsec --format json"
alias cloud-checkov="checkov -o json"

# --- Kubernetes ---
alias cloud-k="kubectl"
alias cloud-kctx="kubectx"
alias cloud-kns="kubens"
alias cloud-k9s="k9s"
alias cloud-helm="helm list -o json | jq ."
alias cloud-stern="stern -o json"

# ==========================================
# HELPER FUNCTIONS
# ==========================================

# --- Quick Reference Card ---
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
  echo "  ${green}cloud-aws${reset}        ${dim}aws --output json${reset}"
  echo "  ${green}cloud-aws-sso${reset}    ${dim}aws sso login${reset}"
  echo "  ${green}cloud-s3${reset}         ${dim}aws s3 ls --output json | jq .${reset}"
  echo ""

  echo "  ${orange}${bold}GCP${reset}"
  echo "  ${green}cloud-gcp${reset}        ${dim}gcloud --format=json${reset}"
  echo ""

  echo "  ${orange}${bold}Kubernetes${reset}"
  echo "  ${green}cloud-k${reset}          ${dim}kubectl${reset}"
  echo "  ${green}cloud-kctx${reset}       ${dim}kubectx${reset}"
  echo "  ${green}cloud-kns${reset}        ${dim}kubens${reset}"
  echo "  ${green}cloud-k9s${reset}        ${dim}k9s${reset}"
  echo "  ${green}cloud-helm${reset}       ${dim}helm list -o json | jq .${reset}"
  echo "  ${green}cloud-stern${reset}      ${dim}stern -o json${reset}"
  echo ""

  echo "  ${orange}${bold}Infrastructure as Code${reset}"
  echo "  ${green}cloud-tff${reset}        ${dim}terraform fmt -recursive${reset}"
  echo "  ${green}cloud-tfv${reset}        ${dim}terraform validate${reset}"
  echo "  ${green}cloud-tfp${reset}        ${dim}terraform plan -out=tfplan -json | jq .${reset}"
  echo "  ${green}cloud-tg${reset}         ${dim}terragrunt run-all plan${reset}"
  echo "  ${green}cloud-tfsec${reset}      ${dim}tfsec --format json${reset}"
  echo "  ${green}cloud-checkov${reset}    ${dim}checkov -o json${reset}"
  echo ""

  echo "  ${purple}${bold}Utilities${reset}"
  echo "  ${green}cloud-help${reset}       ${dim}Show this reference card${reset}"
  echo "  ${green}_cloud_tool_check${reset} ${dim}Verify tool availability${reset}"
  echo ""
}

# --- Tool Availability Check ---
_cloud_tool_check() {
  local green='\e[38;2;63;185;80m'
  local red='\e[38;2;248;81;73m'
  local white='\e[38;2;201;209;217m'
  local cyan='\e[38;2;88;166;255m'
  local dim='\e[38;2;139;148;158m'
  local bold='\e[1m'
  local reset='\e[0m'

  local tools=(
    "aws:awscli"
    "kubectl:kubectl"
    "helm:helm"
    "terraform:terraform"
    "terragrunt:terragrunt"
    "k9s:k9s"
    "stern:stern"
    "gcloud:google-cloud-sdk"
    "eksctl:eksctl"
    "tfsec:tfsec"
    "checkov:checkov"
  )

  local found=0
  local missing=0
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

  echo ""
  echo "${dim}  ────────────────────────────────${reset}"
  echo "  ${green}${found}${reset}${dim}/${total} available${reset}  ${red}${missing} missing${reset}"
  echo ""
}

# Profile banner handled by fastfetch (config-cloud.jsonc)
