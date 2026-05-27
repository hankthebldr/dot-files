# shell/profiles/cloud/linux.zsh — Linux-only cloud-profile bits
# Sourced after common.zsh, so it can override aliases freely.

# On headless Linux (or SSH sessions), AWS SSO can't auto-open a browser.
# --no-browser prints the URL+code so the operator can complete on Mac.
alias awssso="aws sso login --no-browser"

# Console openers via xdg-open. Works locally; over SSH, prints the URL.
alias console-aws='xdg-open https://console.aws.amazon.com 2>/dev/null || echo https://console.aws.amazon.com'
alias console-gcp='xdg-open https://console.cloud.google.com 2>/dev/null || echo https://console.cloud.google.com'
alias console-azure='xdg-open https://portal.azure.com 2>/dev/null || echo https://portal.azure.com'

# Install hints: prefer apt where available, fall back to Hashicorp/Google
# vendor instructions for tools that don't live in apt.
_cloud_install_hint() {
    case "$1" in
        awscli|kubectl|helm|terraform|jq|google-cloud-sdk|gcloud)
            echo "sudo apt install $1"
            ;;
        terragrunt|k9s|stern|eksctl|tfsec|checkov)
            echo "see scripts/install/cloud-toolchain.sh (or vendor URL)"
            ;;
        *)
            echo "claw install cloud"
            ;;
    esac
}
