#!/usr/bin/env bash
# logo-from-image.sh — convert an image (URL or file) into a fastfetch-ready
# colored logo file using chafa (quad-block, 24-bit truecolor).
#
# Usage:
#   logo-from-image.sh <profile> <image-url-or-path>
#
# Examples:
#   logo-from-image.sh claude  https://cdn.simpleicons.org/anthropic/d97757
#   logo-from-image.sh cloud   https://cdn.simpleicons.org/amazonwebservices/ff9900
#   logo-from-image.sh devops  ~/Downloads/docker-whale.png
#
# Output:
#   - config/.config/fastfetch/logo-<profile>.txt   (raw chafa output)
#   - patches  config-<profile>.jsonc to use "type": "data" + new source
#
# Requirements: chafa, rsvg-convert (for SVG), curl

set -e

PROFILE="$1"
SOURCE="$2"

if [[ -z "$PROFILE" || -z "$SOURCE" ]]; then
    echo "usage: $0 <profile> <image-url-or-path>" >&2
    exit 1
fi

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
LOGO_DIR="$DOTFILES/config/.config/fastfetch"
LOGO_FILE="$LOGO_DIR/logo-$PROFILE.txt"
CONFIG_FILE="$LOGO_DIR/config-$PROFILE.jsonc"

[[ ! -f "$CONFIG_FILE" ]] && { echo "no config file for profile: $PROFILE ($CONFIG_FILE)" >&2; exit 1; }

# Tunables
WIDTH="${WIDTH:-28}"
HEIGHT="${HEIGHT:-14}"
BG="${BG:-13131A}"   # GitHub Dark bg

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

# 1. Fetch image (URL or local path)
if [[ "$SOURCE" =~ ^https?:// ]]; then
    echo "  → fetching $SOURCE"
    curl -sL "$SOURCE" -o "$WORK/source"
else
    cp "$SOURCE" "$WORK/source"
fi

# 2. Detect format and rasterize SVG → PNG if needed
KIND=$(file -b --mime-type "$WORK/source")
if [[ "$KIND" == "image/svg+xml" ]] || head -1 "$WORK/source" | grep -q '<svg\|<?xml'; then
    echo "  → rasterizing SVG → PNG (512x512, bg #$BG)"
    rsvg-convert -w 512 -h 512 -b "#$BG" "$WORK/source" -o "$WORK/image.png"
else
    cp "$WORK/source" "$WORK/image.png"
fi

# 3. chafa — QUAD blocks, truecolor, sized for fastfetch.
#   --symbols=quad uses the 2x2 quadrant block elements (U+2596..U+259F) for
#   4 sub-cells/glyph vs --symbols=half's 2 — roughly double the detail at the
#   same cell size, while staying within Unicode 1.1 block elements that every
#   terminal font ships (verified: JetBrainsMono Nerd Font covers them).
#   Deliberately NOT sextant/octant (U+1FB00 / U+1CC00): higher density but they
#   tofu in JetBrainsMono Nerd Font (the active Ghostty font) and over SSH.
#   -f symbols forces text output: without it chafa auto-detects a graphics
#   terminal (e.g. Ghostty) and would bake the kitty protocol into the .txt.
echo "  → converting to ${WIDTH}x${HEIGHT} quad-block ASCII (24-bit color)"
chafa -f symbols -s "${WIDTH}x${HEIGHT}" --symbols=quad --colors=truecolor --bg="$BG" "$WORK/image.png" > "$LOGO_FILE"

# 3b. Keep the high-res raster as the Ghostty/Kitty/iTerm graphics logo. The
#     claw_ff shim (shell/fastfetch.zsh) shows this on a live local graphics
#     terminal and falls back to the .txt above over SSH / tmux / dumb terminals.
cp "$WORK/image.png" "$LOGO_DIR/logo-$PROFILE.png"
echo "  → saved graphics logo logo-$PROFILE.png"

# 4. Patch config to use type=data + the new source path
echo "  → patching $CONFIG_FILE → type:data"
python3 - <<EOF
import json, re, sys
path = "$CONFIG_FILE"
with open(path) as f:
    raw = f.read()
# Strip jsonc line comments only when they start the line
# (avoid eating URLs like https://example.com)
clean = re.sub(r'(?m)^\s*//.*$', '', raw)
data = json.loads(clean)
data['logo'] = {
    'source': "~/.dotfiles/config/.config/fastfetch/logo-$PROFILE.txt",
    'type': 'file-raw',
    'padding': data.get('logo', {}).get('padding', {'top': 1, 'left': 2, 'right': 3})
}
# Preserve schema if present
if data.get('\$schema') is None:
    data['\$schema'] = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json"
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
EOF

echo "  ✓ $LOGO_FILE ($(wc -l < "$LOGO_FILE") lines)"
echo ""
echo "  preview with: fastfetch -c $CONFIG_FILE"
