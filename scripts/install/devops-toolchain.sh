#!/usr/bin/env bash
################################################################################
# DevOps Toolchain — Cross-Platform
#
# Containers, CI/CD, IaC, k8s ops, observability, build tools. Some tools are
# shared with cloud-toolchain (helm, terraform, kubectl) — re-running is
# idempotent because the lib's `command -v` probe skips already-installed.
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toolchain-runner.sh"

TOOLCHAIN_TITLE="DEVOPS  TOOLCHAIN"
TOOLCHAIN_CLASS="WRENCH-MAGE  LOADOUT"
TOOLCHAIN_TAG="speaks fluent YAML · has opinions about Kubernetes · strong opinions"

case "$(uname -m)" in
    x86_64|amd64) _arch="amd64" ;;
    aarch64|arm64) _arch="arm64" ;;
    *) _arch="amd64" ;;
esac

# ── TOOL MAPPING ───────────────────────────────────────────────────────────
# >>> HENRY: vault/consul/nomad install on Ubuntu typically wants the
#     Hashicorp apt repo — see toolchain_preflight_extras below. The MAP
#     rows assume the repo is already configured; if not, install falls back
#     to manual URLs.
TOOLCHAIN_MAP=(
    # ── 01. Git / VCS ──────────────────────────────────────────────────────
    "gh|gh|gh|manual:https://github.com/cli/cli/blob/trunk/docs/install_linux.md|GitHub CLI — apt pkg from GitHub repo"

    # ── 02. Containers ─────────────────────────────────────────────────────
    "docker|docker|docker.io|manual:https://docs.docker.com/engine/install/|prefer docker-ce repo over apt's docker.io"
    "podman|podman|podman|none|rootless container runtime"
    "buildah|buildah|buildah|none|OCI image builder"
    "lazydocker|lazydocker|?|manual:https://github.com/jesseduffield/lazydocker#installation|docker TUI — logs/exec/graphs (alias: lzd)"
    "ctop|ctop|?|manual:https://github.com/bcicen/ctop#install|live per-container metrics, top-like (alias: cto)"

    # ── 03. CI/CD & Config Mgmt ────────────────────────────────────────────
    "skaffold|skaffold|?|curl:https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-${_arch}|k8s dev workflow"
    "argocd|argocd|?|curl:https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-${_arch}|GitOps CD"
    "flux|fluxcd/tap/flux|?|curl:https://fluxcd.io/install.sh|GitOps toolkit"
    "ansible|ansible|ansible|pipx|infra config mgmt"

    # ── 04. Hashicorp Stack ────────────────────────────────────────────────
    "terraform|hashicorp/tap/terraform|terraform|manual:https://developer.hashicorp.com/terraform/install|needs Hashicorp apt repo"
    "terragrunt|terragrunt|?|manual:https://terragrunt.gruntwork.io/docs/getting-started/install|terraform orchestrator"
    "vault|vault|vault|manual:https://developer.hashicorp.com/vault/install|secrets mgmt — Hashicorp repo"
    "consul|consul|consul|manual:https://developer.hashicorp.com/consul/install|service mesh — Hashicorp repo"
    "nomad|nomad|nomad|manual:https://developer.hashicorp.com/nomad/install|workload scheduler — Hashicorp repo"

    # ── 05. Kubernetes ─────────────────────────────────────────────────────
    "kubectl|kubernetes-cli|kubectl|none|k8s CLI"
    "helm|helm|helm|curl:https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3|chart pkg manager"
    "stern|stern|?|go:github.com/stern/stern|multi-pod log tailer"

    # ── 06. Observability ──────────────────────────────────────────────────
    "prometheus|prometheus|prometheus|manual:https://prometheus.io/download/|metrics — apt version often old"

    # ── 07. Build & Lint ───────────────────────────────────────────────────
    "task|go-task|?|go:github.com/go-task/task/v3/cmd/task|Taskfile runner"
    "make|make|build-essential|none|GNU make"
    "shellcheck|shellcheck|shellcheck|none|shell linter"
    "watch|watch|procps|none|periodic command runner (apt: procps)"
    "jq|jq|jq|none|JSON swiss army knife"
)

declare -A TOOLCHAIN_SECTIONS=(
    [0]="01|Git  /  VCS"
    [1]="02|Containers"
    [4]="03|CI/CD  &  Config  Mgmt"
    [8]="04|Hashicorp  Stack"
    [13]="05|Kubernetes"
    [16]="06|Observability"
    [17]="07|Build  &  Lint"
)

# ── Pre-install hook: add taps/repos ──────────────────────────────────────
toolchain_preflight_extras() {
    case "$PKG_MANAGER" in
        brew)
            brew tap hashicorp/tap 2>/dev/null || true
            brew tap fluxcd/tap 2>/dev/null || true
            ;;
        apt)
            # Ubuntu/Debian: Hashicorp products need their apt repo to install
            # via system pkg manager. If not configured, MAP rows fall back to
            # manual URLs. Uncomment the block below to auto-configure:
            #
            #   curl -fsSL https://apt.releases.hashicorp.com/gpg | \
            #       sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
            #   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
            #       https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
            #       sudo tee /etc/apt/sources.list.d/hashicorp.list
            #   sudo apt-get update -qq
            #
            # >>> HENRY: enable the above if you want auto-repo on the BD790i,
            #     or run it once manually. Leaving disabled by default so the
            #     script never adds repos without explicit consent.
            :
            ;;
    esac
}

toolchain_run
