# shell/profiles/brainstorm/mac.zsh — macOS-specific ideation extras

# --- Voice Memos integration ---
# macOS Voice Memos stores recordings in this location. Surface recent ones
# so you can grab a transcript via granola or whisper.
VOICE_MEMOS_DIR="$HOME/Library/Application Support/com.apple.voicememos/Recordings"
[[ -d "$VOICE_MEMOS_DIR" ]] && alias bmvoice='ls -lt "$VOICE_MEMOS_DIR" | head -20'

# --- Granola transcripts ---
# If you use Granola for meeting/idea capture, its transcripts live here.
GRANOLA_DIR="$HOME/Library/Application Support/Granola/transcripts"
[[ -d "$GRANOLA_DIR" ]] && alias bmgranola='ls -lt "$GRANOLA_DIR" | head -20'

# --- Whisper-cli transcription ---
# Drop a voice memo path in, get markdown back into today's brainstorm log.
bmtranscribe() {
    local audio="${1:?usage: bmtranscribe <audio-file>}"
    if ! command -v whisper-cli &>/dev/null && ! command -v whisper-cpp &>/dev/null; then
        echo "needs whisper-cli or whisper-cpp (brew install whisper-cpp)" >&2
        return 1
    fi
    local cmd=$(command -v whisper-cli || command -v whisper-cpp)
    mkdir -p "$BRAINSTORM_ROOT"
    local log="$BRAINSTORM_ROOT/$(date +%Y-%m-%d).md"
    {
        printf '\n## transcript · %s · %s\n\n' "$(date +%H:%M)" "$(basename "$audio")"
        "$cmd" -f "$audio" 2>/dev/null | sed -E 's/\[.*\]//g'
    } >> "$log"
    echo "→ $log"
}

# --- Hammerspoon hotkey hint ---
# If you wire a Hammerspoon hotkey to invoke `spark "<prompt-text>"`, you can
# capture without switching windows. Sample config left as a note here:
#
# In ~/.hammerspoon/init.lua:
#   hs.hotkey.bind({"cmd","alt"}, "B", function()
#     local text = hs.dialog.textPrompt("spark", "what's the thought?", "", "ok", "cancel")
#     if text and text ~= "" then
#       hs.execute("zsh -ic 'source ~/.zshrc; spark \"" .. text .. "\"'", true)
#     end
#   end)

_brainstorm_install_hint() {
    case "$1" in
        ripgrep|fzf|glow|gum|bat|whisper-cpp)
            echo "brew install $1"
            ;;
        markmap|markmap-cli)
            echo "npm install -g markmap-cli"
            ;;
        mermaid|mmdc)
            echo "npm install -g @mermaid-js/mermaid-cli"
            ;;
        *)
            echo "claw install brainstorm"
            ;;
    esac
}
