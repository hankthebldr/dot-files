# shell/profiles/design/common.zsh
# Aliases / functions / help — work identically on macOS and Linux.


# Where new design assets land if no current project context. Override via
# DESIGN_HOME if you keep assets elsewhere.
export DESIGN_HOME="${DESIGN_HOME:-$HOME/Design}"

# ==========================================
# DIAGRAM RENDERING
# ==========================================

# fmm <input.md|input.mmd> [output.svg]  — render mermaid diagram
# Auto-extracts ```mermaid blocks from markdown if input is .md.
fmm() {
    local input="${1:?usage: fmm <input.md|mmd> [output.svg]}"
    local output="${2:-${input%.*}.svg}"
    if ! command -v mmdc &>/dev/null; then
        echo "mermaid-cli not installed — run: claw install design" >&2
        echo "  (npm install -g @mermaid-js/mermaid-cli)" >&2
        return 1
    fi
    if [[ "$input" == *.md ]]; then
        # Extract first mermaid block to a tempfile, then render.
        local tmp; tmp="$(mktemp --suffix=.mmd 2>/dev/null || mktemp -t mermaid).mmd"
        awk '/^```mermaid$/,/^```$/' "$input" | sed '/^```/d' > "$tmp"
        if [[ ! -s "$tmp" ]]; then
            echo "no mermaid block found in $input" >&2
            rm -f "$tmp"
            return 1
        fi
        mmdc -i "$tmp" -o "$output" -b transparent
        rm -f "$tmp"
    else
        mmdc -i "$input" -o "$output" -b transparent
    fi
    echo "✓ $output"
}

# fd2 <input.d2> [output.svg]  — render d2 diagram
# d2 is Terrastruct's modern diagram language — nicer than graphviz for arch diagrams.
fd2() {
    local input="${1:?usage: fd2 <input.d2> [output.svg]}"
    local output="${2:-${input%.*}.svg}"
    if ! command -v d2 &>/dev/null; then
        echo "d2 not installed — run: claw install design" >&2
        return 1
    fi
    d2 --theme=200 "$input" "$output"     # theme 200 = "Origami"; tweak per taste
    echo "✓ $output"
}

# fnew <type> [name]  — scaffold a new design asset
# Types: diagram (mermaid stub) · d2 (d2 stub) · palette (color spec) · poster (canva stub)
fnew() {
    local type="${1:?usage: fnew <diagram|d2|palette|poster> [name]}"
    local name="${2:-$(date +%Y%m%d-%H%M%S)}"
    mkdir -p "$DESIGN_HOME"
    case "$type" in
        diagram|mermaid)
            local file="$DESIGN_HOME/${name}.mmd"
            cat > "$file" <<'EOF'
graph LR
    A[Start] --> B{Decision}
    B -->|Yes| C[End]
    B -->|No| D[Loop]
    D --> A
EOF
            echo "✓ $file"
            ;;
        d2)
            local file="$DESIGN_HOME/${name}.d2"
            cat > "$file" <<'EOF'
# d2 diagram — see https://d2lang.com
direction: right

users -> api: HTTPS
api -> database: SQL
database.shape: cylinder
EOF
            echo "✓ $file"
            ;;
        palette)
            local file="$DESIGN_HOME/${name}-palette.md"
            cat > "$file" <<'EOF'
# Palette — TBD

| Role          | Hex      | Notes |
|---------------|----------|-------|
| primary       | #58a6ff  | links, focus rings |
| primary-bold  | #1f6feb  | hover states |
| accent        | #3fb950  | success, positive |
| warning       | #e3b341  | mild attention |
| danger        | #ff7b72  | errors, destructive |
| bg-base       | #0d1117  | main background |
| bg-elevated   | #161b22  | cards, panels |
| text-primary  | #c9d1d9  | body text |
| text-muted    | #8b949e  | secondary text |
EOF
            echo "✓ $file"
            ;;
        poster)
            local dir="$DESIGN_HOME/${name}-poster"
            mkdir -p "$dir"/{src,exports}
            echo "✓ $dir (scaffold)"
            ;;
        *)
            echo "unknown type: $type" >&2
            echo "supported: diagram | d2 | palette | poster" >&2
            return 1
            ;;
    esac
}

# ==========================================
# COLOR / PALETTE
# ==========================================

# fpal <image>  — extract dominant color palette from an image
# Uses imagemagick's `convert -kmeans` clustering for accurate dominant colors.
fpal() {
    local input="${1:?usage: fpal <image>}"
    local n="${2:-6}"
    if ! command -v convert &>/dev/null; then
        echo "imagemagick not installed — run: claw install design" >&2
        return 1
    fi
    convert "$input" -resize 200x200 -dither None -colors "$n" -unique-colors \
        -depth 8 txt: 2>/dev/null \
        | tail -n +2 \
        | awk '{print $3}' \
        | sort -u
}

# fpal-card <image>  — render the palette as a horizontal swatch strip
fpal-card() {
    local input="${1:?usage: fpal-card <image>}"
    local output="${2:-${input%.*}-palette.png}"
    convert "$input" -resize 100x100 -dither None -colors 6 -unique-colors \
        -scale 800x100\! "$output"
    echo "✓ $output"
}

# ==========================================
# IMAGE MANIPULATION
# ==========================================

# fresize <image> <size>  — imagemagick resize wrapper
# Examples: fresize foo.png 800x   fresize foo.png 50%
fresize() {
    local input="${1:?usage: fresize <image> <size>}"
    local size="${2:?missing size — e.g. 800x or 50%}"
    local output="${input%.*}-resized.${input##*.}"
    convert "$input" -resize "$size" "$output"
    echo "✓ $output  ($(command du -h "$output" | cut -f1))"
}

# foptim <image>  — optimize for web (strip metadata, resize to max 1920, recompress)
foptim() {
    local input="${1:?usage: foptim <image>}"
    local output="${input%.*}-optim.${input##*.}"
    convert "$input" -strip -resize "1920x1920>" -quality 85 "$output"
    local before; before="$(command du -k "$input" | cut -f1)"
    local after; after="$(command du -k "$output" | cut -f1)"
    printf "✓ %s  (%dk → %dk · %d%% smaller)\n" \
        "$output" "$before" "$after" "$(( 100 - (after * 100 / before) ))"
}

# fcrop <image> <geom>  — crop to a specific WxH+X+Y region
# Examples: fcrop foo.png 800x600+100+50
fcrop() {
    local input="${1:?usage: fcrop <image> <geometry>}"
    local geom="${2:?missing geometry — e.g. 800x600+100+50}"
    local output="${input%.*}-crop.${input##*.}"
    convert "$input" -crop "$geom" "$output"
    echo "✓ $output"
}

# ==========================================
# ASCII ART
# ==========================================

# fascii <image> [width]  — convert image to ASCII art (great for splash logos)
# Uses jp2a if available, falls back to imagemagick text rendering.
fascii() {
    local input="${1:?usage: fascii <image> [width]}"
    local width="${2:-80}"
    if command -v jp2a &>/dev/null; then
        jp2a --width="$width" --colors "$input"
    elif command -v convert &>/dev/null; then
        # imagemagick fallback — coarser but works without extra deps.
        convert "$input" -resize "${width}x" -depth 1 txt: \
            | awk 'NR>1 { c=$3=="black"?"#":" "; r=int($1); split($1,a,","); print a[1] }'
    else
        echo "needs jp2a or imagemagick — run: claw install design" >&2
        return 1
    fi
}

# ==========================================
# HELP
# ==========================================

design-help() {
    cat <<'EOF'
DESIGN profile — FRAME-SMITH (Tier 5: customer-facing)

  ── diagrams ─────────────────────────
  fmm <in.md|mmd> [out]    render mermaid (auto-extracts from .md)
  fd2 <in.d2> [out]        render d2 diagram

  ── scaffold ─────────────────────────
  fnew <type> [name]       diagram | d2 | palette | poster

  ── palette ──────────────────────────
  fpal <image> [n]         extract dominant colors (n=6 default)
  fpal-card <image>        render palette as 800x100 swatch strip

  ── images ───────────────────────────
  fresize <img> <size>     imagemagick resize (800x or 50%)
  foptim <img>             web optimize (strip meta, max 1920, q=85)
  fcrop <img> <geom>       crop to WxH+X+Y

  ── ASCII ────────────────────────────
  fascii <img> [width]     image → ASCII art (default 80 wide)

  ── platform-specific (see mac.zsh / linux.zsh) ──
  fopen <file>             open in native default app
  ffigma                   open Figma desktop / web
  fexcalidraw              open Excalidraw
EOF
}
