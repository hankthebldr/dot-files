#!/usr/bin/env bash
################################################################################
# Cloud Toolchain — Cross-Platform
#
# AWS, GCP, Azure, Kubernetes, and IaC tools. Most cloud CLIs don't ship in
# apt — they live in vendor repos or GitHub releases. The MAP below uses
# `curl:URL` and `manual:URL` fallbacks heavily on Linux.
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toolchain-runner.sh"

TOOLCHAIN_TITLE="CLOUD  TOOLCHAIN"
TOOLCHAIN_CLASS="SKYSURFER  LOADOUT"
TOOLCHAIN_TAG="boots up clusters before breakfast · owns 4 TLDs you've never heard of"

# Detect arch once for binary URLs below.
case "$(uname -m)" in
    x86_64|amd64) _arch="amd64" ;;
    aarch64|arm64) _arch="arm64" ;;
    *) _arch="amd64" ;;
esac

# ── TOOL MAPPING ───────────────────────────────────────────────────────────
# >>> HENRY: many of these have vendor install scripts that pin a version OR
#     install dependencies. The `manual:URL` fallback just prints the URL; if
#     you want the script to actually run those installers (apt repo setup,
#     etc.), change `manual:` to `curl:` with the binary URL, or add custom
#     logic in toolchain_extras.
TOOLCHAIN_MAP=(
    # ── 01. Hyperscaler CLIs ───────────────────────────────────────────────
    "aws|awscli|awscli|manual:https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html|AWS v2 — apt has v1 only, prefer official installer"
    "az|azure-cli|azure-cli|manual:https://docs.microsoft.com/cli/azure/install-azure-cli-linux-apt|Azure CLI — needs Microsoft apt repo"
    "gcloud|google-cloud-sdk|google-cloud-cli|manual:https://cloud.google.com/sdk/docs/install#linux|GCP SDK — needs Google apt repo"

    # ── 02. Kubernetes CLIs ────────────────────────────────────────────────
    "kubectl|kubernetes-cli|kubectl|none|k8s CLI — apt/brew; use official repo on bare Ubuntu"
    "eksctl|eksctl|?|curl:https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_${_arch}.tar.gz|AWS EKS provisioner"
    "oc|openshift-cli|?|manual:https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html|OpenShift CLI"

    # ── 03. Kubernetes Ops ─────────────────────────────────────────────────
    "helm|helm|helm|curl:https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3|chart pkg manager"
    "k9s|k9s|?|go:github.com/derailed/k9s|terminal UI"
    "stern|stern|?|go:github.com/stern/stern|multi-pod log tailer"

    # ── 04. Infrastructure as Code ─────────────────────────────────────────
    "terraform|hashicorp/tap/terraform|terraform|manual:https://developer.hashicorp.com/terraform/install|needs Hashicorp apt repo on Linux"
    "terragrunt|terragrunt|?|manual:https://terragrunt.gruntwork.io/docs/getting-started/install|terraform orchestrator"

    # ── 05. Cloud Security ─────────────────────────────────────────────────
    "tfsec|tfsec|?|go:github.com/aquasecurity/tfsec/cmd/tfsec|terraform static analysis"
    "checkov|checkov|?|pipx|IaC policy scanner"
    "falco|falco|?|manual:https://falco.org/docs/install-operate/installation/|k8s runtime security — needs apt repo"
    "kube-hunter|kube-hunter|?|pipx|k8s pen-test scanner"

    # ── 06. Auth / Utilities ───────────────────────────────────────────────
    "aws-iam-authenticator|aws-iam-authenticator|?|none|AWS IAM → k8s auth — install via official release page"
    "jq|jq|jq|none|JSON swiss army knife"
)

declare -A TOOLCHAIN_SECTIONS=(
    [0]="01|Hyperscaler  CLIs"
    [3]="02|Kubernetes  CLIs"
    [6]="03|Kubernetes  Ops"
    [9]="04|Infrastructure  as  Code"
    [11]="05|Cloud  Security"
    [15]="06|Auth  /  Utilities"
)

# ── Pre-install hook: add Homebrew taps if on macOS ────────────────────────
toolchain_preflight_extras() {
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        brew tap hashicorp/tap 2>/dev/null || true
    fi
}

toolchain_run
