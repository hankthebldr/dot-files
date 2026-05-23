# shell/profiles/brainstorm/linux.zsh — Linux-specific ideation extras

# --- Audio capture via sox ---
# Quick 60s voice memo, stored in brainstorm root, auto-named.
bmrecord() {
    if ! command -v sox &>/dev/null && ! command -v arecord &>/dev/null; then
        echo "needs sox or arecord — sudo apt install sox or alsa-utils" >&2
        return 1
    fi
    mkdir -p "$BRAINSTORM_ROOT/audio"
    local out="$BRAINSTORM_ROOT/audio/$(date +%Y%m%d-%H%M%S).wav"
    local secs="${1:-60}"
    echo "recording ${secs}s to $out  (Ctrl-C to stop early)"
    if command -v sox &>/dev/null; then
        sox -d "$out" trim 0 "$secs"
    else
        arecord -d "$secs" -f cd "$out" 2>/dev/null
    fi
    echo "→ $out"
}

# --- whisper-cpp transcription if installed locally ---
bmtranscribe() {
    local audio="${1:?usage: bmtranscribe <audio-file>}"
    if ! command -v whisper-cpp &>/dev/null; then
        echo "needs whisper-cpp built locally — see ai-toolchain.sh" >&2
        return 1
    fi
    mkdir -p "$BRAINSTORM_ROOT"
    local log="$BRAINSTORM_ROOT/$(date +%Y-%m-%d).md"
    {
        printf '\n## transcript · %s · %s\n\n' "$(date +%H:%M)" "$(basename "$audio")"
        whisper-cpp -f "$audio" 2>/dev/null | sed -E 's/\[.*\]//g'
    } >> "$log"
    echo "→ $log"
}

# --- Granola hint (Mac-only tool) ---
alias bmgranola='echo "granola is macOS-only — use bmrecord on Linux, transcribe later"'

# --- Mind-map render via mermaid-cli (terminal-friendly) ---
# Already covered by `mindmap` in common.zsh (markmap). This is a fallback.

_brainstorm_install_hint() {
    case "$1" in
        ripgrep|fzf|glow|bat|sox)
            echo "sudo apt install $1"
            ;;
        gum)
            echo "see scripts/install/devops-toolchain.sh (charm vendor)"
            ;;
        markmap|markmap-cli)
            echo "sudo npm install -g markmap-cli"
            ;;
        mermaid|mmdc)
            echo "sudo npm install -g @mermaid-js/mermaid-cli"
            ;;
        whisper-cpp)
            echo "build from source — see scripts/install/ai-toolchain.sh"
            ;;
        *)
            echo "claw install brainstorm"
            ;;
    esac
}
