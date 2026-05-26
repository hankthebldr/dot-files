# shell/profiles/cloud/mac.zsh — macOS-only cloud-profile bits
# Sourced after common.zsh, so it can override aliases freely.

# AWS SSO opens browser by default on Mac — works smoothly with Safari/Chrome
alias awssso="aws sso login"

# Open the AWS Console in Safari (or default browser)
alias console-aws='open https://console.aws.amazon.com'
alias console-gcp='open https://console.cloud.google.com'
alias console-azure='open https://portal.azure.com'

# Install-hint suffix shown by _cloud_tool_check
_cloud_install_hint() {
    echo "brew install $1"
}
