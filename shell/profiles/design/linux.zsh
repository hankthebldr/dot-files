# shell/profiles/design/linux.zsh
# Linux design tooling — Wayland-first GUI bridges.

# Open file via xdg-open (respects user's default app).
fopen() {
    local target="${1:?usage: fopen <file>}"
    xdg-open "$target" &>/dev/null &
}

# Figma — no Linux desktop app, so always go web.
ffigma() {
    xdg-open "https://www.figma.com/files/" &>/dev/null &
}

# Excalidraw — web version on Linux (no desktop app).
fexcalidraw() {
    local file="${1:-}"
    if [[ -n "$file" && -f "$file" ]]; then
        echo "open the file in https://excalidraw.com (no Linux app)" >&2
        xdg-open "https://excalidraw.com" &>/dev/null &
    else
        xdg-open "https://excalidraw.com" &>/dev/null &
    fi
}

# Eye-dropper — gpick if installed, else grim+pixel pickup on Wayland.
fpick() {
    if command -v gpick &>/dev/null; then
        gpick --pick
    elif [[ "$XDG_SESSION_TYPE" == "wayland" ]] && command -v grim &>/dev/null && command -v slurp &>/dev/null; then
        # 1x1 selection → pixel sample
        local color
        color="$(grim -g "$(slurp -p)" -t png - | convert - -resize 1x1\! -format '#%[hex:p{0,0}]' info: 2>/dev/null)"
        if [[ -n "$color" ]]; then
            echo "$color" | wl-copy
            echo "✓ $color (copied)"
        else
            echo "couldn't sample pixel" >&2
            return 1
        fi
    else
        echo "install gpick or grim+slurp for screen color picking" >&2
        return 1
    fi
}

# Reveal target in default file manager.
freveal() {
    local target="${1:-.}"
    xdg-open "$(dirname "$(realpath "$target")")" &>/dev/null &
}

# Inkscape CLI shortcut — useful for SVG → PNG batch conversion.
finkpng() {
    local input="${1:?usage: finkpng <input.svg> [width]}"
    local width="${2:-1920}"
    local output="${input%.svg}.png"
    if ! command -v inkscape &>/dev/null; then
        echo "inkscape not installed — sudo apt install inkscape" >&2
        return 1
    fi
    inkscape -w "$width" "$input" -o "$output"
    echo "✓ $output"
}
