#!/usr/bin/env bash
################################################################################
# Deck Toolchain — Cross-Platform
# Customer-facing artifacts: marp slides, screenshots, GIFs, recordings.
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toolchain-runner.sh"

TOOLCHAIN_TITLE="DECK  TOOLCHAIN"
TOOLCHAIN_CLASS="DECK-SMITH  LOADOUT"
TOOLCHAIN_TAG="every screenshot crops itself · every GIF stays under 4 MB"

# ── TOOL MAPPING ───────────────────────────────────────────────────────────
TOOLCHAIN_MAP=(
    # ── 01. Slide rendering ────────────────────────────────────────────────
    "marp|marp-cli|?|npm:@marp-team/marp-cli|markdown → slides (HTML/PDF/PPTX)"
    "pandoc|pandoc|pandoc|none|universal doc converter"

    # ── 02. Recording ──────────────────────────────────────────────────────
    "asciinema|asciinema|asciinema|pipx|terminal session recorder"
    "agg|?|?|cargo|asciinema → animated GIF"
    "gifski|gifski|?|cargo|high-quality GIF from frames"
    "ffmpeg|ffmpeg|ffmpeg|none|video transcoding"

    # ── 03. Image manipulation ─────────────────────────────────────────────
    "convert|imagemagick|imagemagick|none|imagemagick — resize, crop, convert"

    # ── 04. Microsoft Office (mac only) ────────────────────────────────────
    "powerpoint|?|?|skip-linux|MS PowerPoint — separate install on Mac App Store"
)

declare -A TOOLCHAIN_SECTIONS=(
    [0]="01|Slide  Rendering"
    [2]="02|Recording"
    [6]="03|Image  Manipulation"
    [7]="04|MS  Office"
)

toolchain_preflight_extras() {
    # marp-cli ships only via npm; make sure node is available.
    if ! command -v npm &>/dev/null; then
        log_warning "npm not found — marp-cli will fail. Install Node.js first."
    fi
}

toolchain_run
