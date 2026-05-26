# shell/profiles/demo/linux.zsh
# Linux demo tooling — dunst DND, caffeine-style sleep prevention, pactl mute.

# Internal: engage DND. Tries dunstctl (most popular notification daemon),
# falls back to GNOME's notifications schema if dunst isn't running.
_dm_engage_dnd() {
    if command -v dunstctl &>/dev/null; then
        dunstctl set-paused true 2>/dev/null
    elif command -v gsettings &>/dev/null; then
        # GNOME's "show banners" toggle — false means no popups.
        gsettings set org.gnome.desktop.notifications show-banners false 2>/dev/null
    fi
    # Prevent screen blank via systemd-inhibit (covers wayland + X11).
    if command -v systemd-inhibit &>/dev/null && ! pgrep -f "systemd-inhibit.*claw-demo" &>/dev/null; then
        nohup systemd-inhibit --what=idle --who="claw-demo" --why="presales demo" \
            sleep 7200 >/dev/null 2>&1 &
    fi
}

# Internal: disengage DND + kill the inhibitor.
_dm_disengage_dnd() {
    if command -v dunstctl &>/dev/null; then
        dunstctl set-paused false 2>/dev/null
    elif command -v gsettings &>/dev/null; then
        gsettings set org.gnome.desktop.notifications show-banners true 2>/dev/null
    fi
    pkill -f "systemd-inhibit.*claw-demo" 2>/dev/null
}

# dmbig  — Linux terminals each have their own font escape sequence.
# Most modern terminals (Kitty, Alacritty, Wezterm, Foot) ignore in-band
# resize requests. Document the keybindings instead.
dmbig() {
    local term="${TERM_PROGRAM:-${TERMINAL:-$TERM}}"
    case "$term" in
        *kitty*)
            # Kitty has remote control if enabled in config.
            if command -v kitty &>/dev/null; then
                kitty @ set-font-size +6 2>/dev/null && echo "✓ kitty font +6"
            fi
            ;;
        *alacritty*|*wezterm*|*)
            echo "manual font bump in your terminal (Ctrl-+ / Ctrl-Shift-=)"
            ;;
    esac
}

dmnormal() {
    if [[ "${TERM_PROGRAM:-$TERM}" == *kitty* ]] && command -v kitty &>/dev/null; then
        kitty @ set-font-size 0 2>/dev/null && echo "✓ kitty font reset"
    else
        echo "manual font restore (Ctrl-0)"
    fi
}

# dmmute  — system audio mute via pactl (PipeWire / PulseAudio).
dmmute() {
    if command -v pactl &>/dev/null; then
        pactl set-sink-mute @DEFAULT_SINK@ 1 && echo "✓ muted"
    elif command -v amixer &>/dev/null; then
        amixer -q set Master mute && echo "✓ muted (alsa)"
    else
        echo "no audio tool — install pulseaudio-utils or alsa-utils" >&2
        return 1
    fi
}

dmunmute() {
    if command -v pactl &>/dev/null; then
        pactl set-sink-mute @DEFAULT_SINK@ 0 && echo "✓ unmuted"
    elif command -v amixer &>/dev/null; then
        amixer -q set Master unmute && echo "✓ unmuted (alsa)"
    fi
}
