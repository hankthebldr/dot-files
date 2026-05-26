#!/usr/bin/env bash
################################################################################
# Demo Toolchain — Cross-Platform
# Presales mode tooling: terminal recording, GIF conversion, polished TUI prompts.
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toolchain-runner.sh"

TOOLCHAIN_TITLE="DEMO  TOOLCHAIN"
TOOLCHAIN_CLASS="SHOW-RUNNER  LOADOUT"
TOOLCHAIN_TAG="big font · clean prompt · DND on · clipboard scrubbed"

# ── TOOL MAPPING ───────────────────────────────────────────────────────────
TOOLCHAIN_MAP=(
    # ── 01. Terminal recording ─────────────────────────────────────────────
    "asciinema|asciinema|asciinema|pipx|terminal session recorder"
    "agg|?|?|cargo|asciinema → animated GIF"

    # ── 02. Polished TUI ──────────────────────────────────────────────────
    "gum|gum|?|go:github.com/charmbracelet/gum|Charm's polished prompt + spinner toolkit"

    # ── 03. Quick prompt tweaks ────────────────────────────────────────────
    "starship|starship|?|curl:https://starship.rs/install.sh|fast, customizable prompt"
)

declare -A TOOLCHAIN_SECTIONS=(
    [0]="01|Terminal  Recording"
    [2]="02|Polished  TUI"
    [3]="03|Prompts"
)

toolchain_run
