# shell/profiles/deck/common.zsh
# Aliases / functions / help — work identically on macOS and Linux.
# OS-specific bits (screencapture / spectacle / office365 / libreoffice) live
# in mac.zsh and linux.zsh.


# Where new deck drafts live. Override via DECK_HOME in shell env if you
# keep customer-facing material elsewhere (e.g. a synced Drive folder).
export DECK_HOME="${DECK_HOME:-$HOME/Decks}"

# Cortex deck template root — your repo of canonical Cortex deck templates.
# Auto-discovered if you keep them in the standard location; override the
# env var to point elsewhere.
export CORTEX_DECK_TEMPLATES="${CORTEX_DECK_TEMPLATES:-$HOME/.dotfiles/templates/cortex-decks}"

# ==========================================
# DECK CREATION
# ==========================================

# dnew <name> [template]  — create a new deck dir from a template
# Templates default to `cortex-default` if not specified. Lists available
# templates if you call `dnew` with no args.
dnew() {
    local name="${1:-}"
    local template="${2:-cortex-default}"
    if [[ -z "$name" ]]; then
        echo "usage: dnew <name> [template]" >&2
        if [[ -d "$CORTEX_DECK_TEMPLATES" ]]; then
            echo ""
            echo "available templates:"
            ls "$CORTEX_DECK_TEMPLATES" 2>/dev/null | sed 's/^/  /'
        fi
        return 1
    fi
    local dest="$DECK_HOME/$(date +%Y-%m-%d)-$name"
    mkdir -p "$DECK_HOME"
    if [[ -d "$CORTEX_DECK_TEMPLATES/$template" ]]; then
        cp -R "$CORTEX_DECK_TEMPLATES/$template" "$dest"
        echo "✓ created: $dest"
    else
        # Fallback: empty scaffold
        mkdir -p "$dest"/{assets,exports}
        cat > "$dest/slides.md" <<'EOF'
---
marp: true
theme: default
paginate: true
size: 16:9
---

# Title

> subtitle / customer / date

---

## Section

content here

EOF
        echo "✓ created empty scaffold: $dest"
    fi
    cd "$dest" || return 1
}

# dls — list recent deck drafts
dls() {
    if [[ ! -d "$DECK_HOME" ]]; then
        echo "no decks yet — try: dnew <name>"
        return 0
    fi
    if command -v eza &>/dev/null; then
        eza --long --sort=modified --reverse "$DECK_HOME" | head -20
    else
        ls -lt "$DECK_HOME" | head -20
    fi
}

# dgoto <pattern>  — fuzzy-jump into a deck dir
dgoto() {
    local pattern="${1:?usage: dgoto <pattern>}"
    local match
    match="$(find "$DECK_HOME" -maxdepth 1 -type d -iname "*${pattern}*" 2>/dev/null | head -1)"
    if [[ -z "$match" ]]; then
        echo "no match for: $pattern" >&2
        return 1
    fi
    cd "$match" || return 1
    pwd
}

# ==========================================
# RENDERING / PREVIEW
# ==========================================

# dpreview [file]  — live marp preview server. Reload on save.
dpreview() {
    local target="${1:-slides.md}"
    if [[ ! -f "$target" ]]; then
        echo "no slides.md in CWD — cd into a deck dir first" >&2
        return 1
    fi
    if ! command -v marp &>/dev/null; then
        echo "marp-cli not installed — run: claw install deck" >&2
        return 1
    fi
    marp --server --watch "$target"
}

# dexport [file] [format]  — export to pdf / pptx / html
dexport() {
    local target="${1:-slides.md}"
    local format="${2:-pdf}"
    if ! command -v marp &>/dev/null; then
        echo "marp-cli not installed — run: claw install deck" >&2
        return 1
    fi
    local out
    case "$format" in
        pdf)  out="${target%.md}.pdf";  marp --pdf "$target" -o "$out" ;;
        pptx) out="${target%.md}.pptx"; marp --pptx "$target" -o "$out" ;;
        html) out="${target%.md}.html"; marp --html "$target" -o "$out" ;;
        *)
            echo "unknown format: $format (use pdf/pptx/html)" >&2
            return 1
            ;;
    esac
    echo "✓ exported: $out"
}

# ==========================================
# RECORDING / GIFs
# ==========================================

# dasciinema [name]  — start a fresh asciinema recording
# Saved to ./assets/<name>.cast in the current deck dir.
dasciinema() {
    local name="${1:-$(date +%Y%m%d-%H%M%S)}"
    if ! command -v asciinema &>/dev/null; then
        echo "asciinema not installed — run: claw install deck" >&2
        return 1
    fi
    mkdir -p assets
    asciinema rec "assets/${name}.cast"
}

# dgif <input> [output]  — convert mp4/mov to optimized GIF for slides
# Uses gifski for high-quality output. Caps at 1280px wide, 15 fps.
dgif() {
    local input="${1:?usage: dgif <input.mp4> [output.gif]}"
    local output="${2:-${input%.*}.gif}"
    if ! command -v ffmpeg &>/dev/null || ! command -v gifski &>/dev/null; then
        echo "needs ffmpeg + gifski — run: claw install deck" >&2
        return 1
    fi
    local tmpdir; tmpdir="$(mktemp -d)"
    ffmpeg -i "$input" -vf "fps=15,scale=1280:-1:flags=lanczos" "$tmpdir/frame_%04d.png" 2>/dev/null
    gifski -o "$output" --fps 15 --quality 80 "$tmpdir"/frame_*.png
    rm -rf "$tmpdir"
    echo "✓ $output  ($(command du -h "$output" | cut -f1))"
}

# ==========================================
# HELP
# ==========================================

deck-help() {
    cat <<'EOF'
DECK profile — DECK-SMITH (Tier 5: customer-facing)

  ── creation ─────────────────────────
  dnew <name> [tpl]    new deck dir (Cortex template by default)
  dls                  recent decks
  dgoto <pattern>      fuzzy-jump into a deck

  ── render ───────────────────────────
  dpreview [file]      live marp preview server
  dexport [file] [fmt] export to pdf | pptx | html (default pdf)

  ── recording ────────────────────────
  dasciinema [name]    record terminal to ./assets/<name>.cast
  dgif <in> [out]      mp4/mov → optimized GIF (≤ 1280px, 15fps)

  ── platform-specific (see mac.zsh / linux.zsh) ──
  dshot                quick screenshot to clipboard
  dscreenrec           start screen recording
  dpresent             enter presentation mode
EOF
}
