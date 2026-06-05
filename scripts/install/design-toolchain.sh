#!/usr/bin/env bash
################################################################################
# Design Toolchain — Cross-Platform
# Asset creation: diagrams, palettes, ASCII art, image manipulation.
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toolchain-runner.sh"

TOOLCHAIN_TITLE="DESIGN  TOOLCHAIN"
TOOLCHAIN_CLASS="FRAME-SMITH  LOADOUT"
TOOLCHAIN_TAG="palette chosen at 2am · pixel-grid alignment is not negotiable"

# ── TOOL MAPPING ───────────────────────────────────────────────────────────
TOOLCHAIN_MAP=(
    # ── 01. Diagram rendering ──────────────────────────────────────────────
    "mmdc|?|?|npm:@mermaid-js/mermaid-cli|mermaid → SVG/PNG"
    "d2|d2|?|curl:https://d2lang.com/install.sh|Terrastruct d2 diagram language"

    # ── 02. Image manipulation ─────────────────────────────────────────────
    "convert|imagemagick|imagemagick|none|imagemagick — palette extraction, resize"
    "jp2a|jp2a|jp2a|none|image → ASCII art"

    # ── 03. SVG / vector (Linux primarily) ─────────────────────────────────
    "inkscape|inkscape|inkscape|skip-linux|SVG editor (CLI works on Linux; Mac uses GUI)"
)

declare -A TOOLCHAIN_SECTIONS=(
    [0]="01|Diagram  Rendering"
    [2]="02|Image  Manipulation"
    [4]="03|SVG  /  Vector"
)

toolchain_preflight_extras() {
    if ! command -v npm &>/dev/null; then
        log_warning "npm not found — mmdc (mermaid-cli) will fail. Install Node.js first."
    fi
}

toolchain_run
