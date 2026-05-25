# shell/profiles/deck/linux.zsh
# Linux deck tooling — Wayland-first with X11 fallback. Sourced after common.zsh.

# Detect display server once.
_deck_display_server() {
    if [[ "$XDG_SESSION_TYPE" == "wayland" ]] || [[ -n "$WAYLAND_DISPLAY" ]]; then
        echo "wayland"
    else
        echo "x11"
    fi
}

# Quick screenshot to clipboard — interactive region select.
# Wayland: grim + slurp + wl-copy. X11: maim/scrot + xclip.
dshot() {
    case "$(_deck_display_server)" in
        wayland)
            if command -v grim &>/dev/null && command -v slurp &>/dev/null; then
                grim -g "$(slurp)" - | wl-copy
                echo "✓ screenshot copied (Wayland)"
            else
                echo "missing grim/slurp — sudo apt install grim slurp wl-clipboard" >&2
                return 1
            fi
            ;;
        x11)
            if command -v maim &>/dev/null && command -v xclip &>/dev/null; then
                maim -s | xclip -selection clipboard -t image/png
                echo "✓ screenshot copied (X11)"
            elif command -v scrot &>/dev/null; then
                scrot -s -e 'xclip -selection clipboard -t image/png -i $f && rm $f'
                echo "✓ screenshot copied (X11 via scrot)"
            else
                echo "missing maim/scrot — sudo apt install maim xclip" >&2
                return 1
            fi
            ;;
    esac
}

# Screenshot to file — writes into ./assets if present, else ~/Pictures.
dshot-file() {
    local target_dir
    if [[ -d ./assets ]]; then
        target_dir="./assets"
    else
        target_dir="$HOME/Pictures"
    fi
    local file="$target_dir/screenshot-$(date +%Y%m%d-%H%M%S).png"
    case "$(_deck_display_server)" in
        wayland) grim -g "$(slurp)" "$file" ;;
        x11)     maim -s "$file" ;;
    esac
    echo "✓ $file"
}

# Start screen recording. peek (GIF-native) preferred for slide assets;
# wf-recorder for full Wayland sessions; ffmpeg X11grab as fallback.
dscreenrec() {
    if command -v peek &>/dev/null; then
        echo "▶ launching peek (GIF recorder)"
        peek &
        return 0
    fi
    case "$(_deck_display_server)" in
        wayland)
            if command -v wf-recorder &>/dev/null; then
                local file="./assets/screenrec-$(date +%Y%m%d-%H%M%S).mp4"
                mkdir -p ./assets
                echo "▶ recording to: $file  (Ctrl-C to stop)"
                wf-recorder -f "$file"
            else
                echo "no recorder — sudo apt install wf-recorder OR install peek" >&2
                return 1
            fi
            ;;
        x11)
            local file="./assets/screenrec-$(date +%Y%m%d-%H%M%S).mp4"
            mkdir -p ./assets
            echo "▶ recording X11 root to: $file  (Ctrl-C to stop)"
            ffmpeg -video_size "$(xdpyinfo | awk '/dimensions/ {print $2}')" \
                -framerate 25 -f x11grab -i :0.0 "$file"
            ;;
    esac
}

# Presentation mode: tmux + bigger font hint via OSC sequence (terminal-dependent).
dpresent() {
    if command -v tmux &>/dev/null; then
        tmux new-session -A -s present \
            "echo 'PRESENTATION MODE — Ctrl-+ to bump font in your terminal'; exec zsh"
    else
        echo "tmux not installed — opening a plain new shell instead"
        exec zsh
    fi
}

# Open the latest .pptx in LibreOffice Impress.
dpptx-open() {
    local latest
    latest="$(ls -t ./*.pptx 2>/dev/null | head -1)"
    if [[ -z "$latest" ]]; then
        echo "no .pptx in CWD — run: dexport slides.md pptx" >&2
        return 1
    fi
    libreoffice --impress "$latest" &>/dev/null &
}

# Reveal target in default file manager (Nautilus / Dolphin / Thunar).
dreveal() {
    local target="${1:-.}"
    xdg-open "$(dirname "$(realpath "$target")")" 2>/dev/null
}
