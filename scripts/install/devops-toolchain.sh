#!/bin/bash

################################################################################
# DevOps Toolchain Installer
# Description: Installs DevOps, CI/CD, Container, and IaC tools
################################################################################

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[INFO]${NC} Installing DevOps Toolchain..."

brew tap homebrew/core || true
brew tap fluxcd/tap || true

tools=(
    "gh"
    "docker"
    "podman"
    "buildah"
    "skaffold"
    "argocd"
    "helm"
    "fluxcd/tap/flux"
    "ansible"
    "terragrunt"
    "terraform"
    "kubernetes-cli"
    "stern"
    "watch"
    "jq"
    "shellcheck"
    "go-task"
    "make"
    "vault"
    "consul"
    "nomad"
    "prometheus"
)

for tool in "${tools[@]}"; do
    if brew list "$tool" &>/dev/null; then
        echo -e "${BLUE}[INFO]${NC} $tool already installed."
    else
        echo -e "${BLUE}[INFO]${NC} Installing $tool..."
        brew install "$tool" || echo -e "${RED}[ERROR]${NC} Failed to install $tool"
    fi
done

echo -e "${GREEN}[SUCCESS]${NC} DevOps Toolchain installed."
