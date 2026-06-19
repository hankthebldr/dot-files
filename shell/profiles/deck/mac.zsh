# shell/profiles/deck/mac.zsh
# macOS-only deck tooling. Sourced by the dispatcher after common.zsh.

# Quick screenshot to clipboard — interactive region select, no file written.
# Cmd-Shift-4 equivalent from the shell.
dshot() {
    screencapture -i -c
    echo "✓ screenshot copied to clipboard"
}

# Quick screenshot to file — falls back to ~/Desktop if no current deck.
dshot-file() {
    local target_dir
    if [[ -d ./assets ]]; then
        target_dir="./assets"
    else
        target_dir="$HOME/Desktop"
    fi
    local file="$target_dir/screenshot-$(date +%Y%m%d-%H%M%S).png"
    screencapture -i "$file"
    echo "✓ $file"
}

# Start a screen recording. Defaults to writing into ./assets if present,
# else ~/Desktop. macOS native recorder; press Cmd-Ctrl-Esc to stop.
dscreenrec() {
    local target_dir
    if [[ -d ./assets ]]; then
        target_dir="./assets"
    else
        target_dir="$HOME/Desktop"
    fi
    local file="$target_dir/screenrec-$(date +%Y%m%d-%H%M%S).mov"
    echo "▶ recording to: $file"
    echo "  stop with: Cmd-Ctrl-Esc"
    screencapture -v "$file"
}

# Presentation mode: full-screen tmux + larger font hint. Most users will
# present in actual slide software, but this is for "live demo from the
# terminal" sessions.
dpresent() {
    if command -v tmux &>/dev/null; then
        # Set a friendlier scrollback + larger appearance for the demo session
        tmux new-session -A -s present \
            "echo 'PRESENTATION MODE — Cmd-+ to bump font in Terminal.app'; exec zsh"
    else
        echo "tmux not installed — opening a plain new shell instead"
        exec zsh
    fi
}

# Office365 / PPTX from marp output. Opens the latest .pptx in PowerPoint.
dpptx-open() {
    local latest
    latest="$(command ls -t ./*.pptx 2>/dev/null | head -1)"
    if [[ -z "$latest" ]]; then
        echo "no .pptx in CWD — run: dexport slides.md pptx" >&2
        return 1
    fi
    open -a "Microsoft PowerPoint" "$latest" 2>/dev/null \
        || open "$latest"
}

# Quick reveal in Finder — useful when a customer wants the source files.
dreveal() {
    local target="${1:-.}"
    open -R "$target"
}
