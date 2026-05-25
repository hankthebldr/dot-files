# shell/profiles/design/mac.zsh
# macOS-only design tooling — native viewers + Figma/Excalidraw integration.

# Open a file in the default macOS app (Preview, Pixelmator, Acorn, etc.)
fopen() {
    local target="${1:?usage: fopen <file>}"
    open "$target"
}

# Launch Figma desktop app (preferred over web for performance).
# Falls back to figma.com in default browser if app isn't installed.
ffigma() {
    if [[ -d "/Applications/Figma.app" ]]; then
        open -a "Figma"
    else
        open "https://www.figma.com/files/"
    fi
}

# Excalidraw — prefer the macOS app via .excalidraw association,
# fall back to excalidraw.com.
fexcalidraw() {
    local file="${1:-}"
    if [[ -n "$file" && -f "$file" ]]; then
        open "$file"
    else
        open "https://excalidraw.com"
    fi
}

# Quick eye-dropper — pick a color from anywhere on screen and copy to
# clipboard as hex. Uses macOS' Digital Color Meter via CLI if available,
# else the more reliable applescript hack.
fpick() {
    if command -v ColorSync &>/dev/null; then
        echo "use Digital Color Meter (Cmd-Shift-C copies)"
        open -a "Digital Color Meter"
    else
        osascript -e 'choose color' \
            | awk -F',' '{ printf "#%02x%02x%02x\n", $1/256, $2/256, $3/256 }' \
            | tee /dev/stderr | pbcopy
        echo "✓ copied to clipboard"
    fi
}

# Reveal-in-Finder helper, design-flavored.
freveal() {
    local target="${1:-.}"
    open -R "$target"
}
