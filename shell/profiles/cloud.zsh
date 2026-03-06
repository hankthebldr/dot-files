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
