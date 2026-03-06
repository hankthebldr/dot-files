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

echo -e "\n\033[0;35m[!] DevOps Profile Loaded. Initialized Workspace: $DEVOPS_WORKSPACE\033[0m\n"
