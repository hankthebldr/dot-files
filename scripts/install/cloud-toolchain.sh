#!/bin/bash

################################################################################
# Cloud Toolchain Installer
# Description: Installs all AWS, GCP, Azure, and K8s configuration tools
################################################################################

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[INFO]${NC} Installing Cloud Toolchain..."

brew tap hashicorp/tap || true

tools=(
    "awscli"
    "azure-cli"
    "google-cloud-sdk"
    "eksctl"
    "kubernetes-cli"
    "openshift-cli"
    "stern"
    "helm"
    "hashicorp/tap/terraform"
    "terragrunt"
    "aws-iam-authenticator"
    "k9s"
    "tfsec"
    "checkov"
    "falco"
    "kube-hunter"
    "jq"
)

for tool in "${tools[@]}"; do
    if brew list "$tool" &>/dev/null; then
        echo -e "${BLUE}[INFO]${NC} $tool already installed."
    else
        echo -e "${BLUE}[INFO]${NC} Installing $tool..."
        brew install "$tool" || echo -e "${RED}[ERROR]${NC} Failed to install $tool"
    fi
done

echo -e "${GREEN}[SUCCESS]${NC} Cloud Toolchain installed."
