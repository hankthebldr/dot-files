#!/usr/bin/env bash
# regen-logos.sh — regenerate ALL brand profile logos from their canonical
# simpleicons.org sources. Single source of truth for the brand mapping (the
# values that used to live only in commit 58060e1's message).
#
# For each profile it writes TWO assets into config/.config/fastfetch/:
#   logo-<profile>.png  — high-res raster (the Ghostty/Kitty/iTerm graphics logo
#                         the claw_ff shim shows on a live local TTY)
#   logo-<profile>.txt  — chafa quad-block 24-bit ANSI (the SSH/macOS-Terminal/
#                         tmux/dumb-terminal text fallback; font-safe block
#                         elements, NOT sextant/octant which tofu in the active
#                         JetBrainsMono Nerd Font)
#
# Usage:   bash scripts/utils/regen-logos.sh            # all profiles
#          bash scripts/utils/regen-logos.sh local ai   # only these
#          PNG_PX=768 W=36 H=18 bash scripts/utils/regen-logos.sh
#
# Requires: chafa, rsvg-convert (librsvg), curl  ->  brew install chafa librsvg
set -euo pipefail

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
LOGO_DIR="$DOTFILES/config/.config/fastfetch"
BG="${BG:-13131A}"          # GitHub-dark card background (matches the dashboards)
# chafa -s is a loose MAX (this build overshoots ~+6w/+1L), so -s 24x14 yields a
# ~30x13 visible text logo — close to the original 28x14 footprint and narrow
# enough not to wrap an 80-col SSH session. The GRAPHICS logo is sized exactly
# (28x14 cells) by the claw_ff shim's --logo-width/height, independent of this.
W="${W:-24}"; H="${H:-14}"
PNG_PX="${PNG_PX:-512}"     # raster size for the graphics logo

# profile   simpleicons-slug      brand-hex
MAP=(
  "claude    anthropic            d97757"
  "cloud     kubernetes           326CE5"
  "security  kalilinux            557c94"
  "devops    docker               2496ED"
  "ai        huggingface          ffd21e"
  "research  jupyter              f37726"
  "cortex    paloaltosoftware     fa582d"
  "local     raspberrypi          a22846"
)

need() { command -v "$1" >/dev/null 2>&1 || { echo "✗ missing required tool: $1 (brew install chafa librsvg)" >&2; exit 1; }; }
need chafa; need rsvg-convert; need curl

want=("$@")               # optional profile filter
wanted() { [[ ${#want[@]} -eq 0 ]] && return 0; local p; for p in "${want[@]}"; do [[ "$p" == "$1" ]] && return 0; done; return 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
n=0
for row in "${MAP[@]}"; do
  read -r prof slug color <<<"$row"
  wanted "$prof" || continue
  printf '  → %-9s %s #%s\n' "$prof" "$slug" "$color"
  curl -fsSL "https://cdn.simpleicons.org/$slug/$color" -o "$work/$prof.svg"
  # High-res raster on the GitHub-dark card bg -> the Kitty/iTerm graphics logo.
  rsvg-convert -w "$PNG_PX" -h "$PNG_PX" -b "#$BG" "$work/$prof.svg" -o "$LOGO_DIR/logo-$prof.png"
  # Quad-block text fallback rendered from the clean raster (-f symbols forces
  # text out even on a graphics terminal; quad = font-safe density over half).
  chafa -f symbols -s "${W}x${H}" --symbols=quad --colors=truecolor --bg="$BG" \
        "$LOGO_DIR/logo-$prof.png" > "$LOGO_DIR/logo-$prof.txt"
  n=$((n + 1))
done
echo "  ✓ regenerated $n logo(s): .png (graphics) + .txt (text fallback)"
