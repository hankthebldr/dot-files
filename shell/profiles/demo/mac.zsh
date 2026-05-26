# shell/profiles/demo/mac.zsh
# macOS-only demo tooling — DND toggle, caffeinate, font/window control.

# Internal: called by dmstart to engage DND.
# Uses macOS Shortcuts if a "Toggle Do Not Disturb" shortcut is installed,
# else falls back to defaults writes (Sonoma+ Focus mode). Stays silent on
# error — DND is nice-to-have, not blocking.
_dm_engage_dnd() {
    if command -v shortcuts &>/dev/null; then
        shortcuts run "Toggle Do Not Disturb" 2>/dev/null && return 0
    fi
    # Older OS / no shortcut installed: try directly via osascript.
    osascript -e 'tell application "System Events" to keystroke "d" using {command down, control down}' \
        2>/dev/null
    # Caffeinate for 2 hours so screen never sleeps mid-demo.
    pgrep -x caffeinate &>/dev/null || caffeinate -dimsu -t 7200 &
}

# Internal: called by dmend to disengage DND + kill caffeinate.
_dm_disengage_dnd() {
    if command -v shortcuts &>/dev/null; then
        shortcuts run "Toggle Do Not Disturb" 2>/dev/null
    fi
    pkill -x caffeinate 2>/dev/null
}

# dmbig  — bump font size + center the window. Uses Terminal.app AppleScript;
# falls back to printing OSC if you're in iTerm/Alacritty/Wezterm.
dmbig() {
    if [[ "$TERM_PROGRAM" == "Apple_Terminal" ]]; then
        osascript <<'EOF' 2>/dev/null
tell application "Terminal"
    set fs to font size of selected tab of front window
    set font size of selected tab of front window to fs + 6
end tell
EOF
        echo "✓ Terminal.app font +6pt"
    elif [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
        # iTerm2 honors ESC ] 50;FontSize=NN BEL  — but it's read-only on
        # most builds. Recommend the user use Cmd-+ instead.
        echo "iTerm: use Cmd-+ to bump font (programmatic resize is restricted)"
    elif [[ -n "$WEZTERM_PANE" ]]; then
        # Wezterm honors a config-reload signal — no in-band CLI control though.
        echo "Wezterm: use Ctrl-+ to bump font"
    else
        echo "manual font bump in your terminal (Cmd-+ / Ctrl-+)"
    fi
}

# dmnormal  — restore default font.
dmnormal() {
    if [[ "$TERM_PROGRAM" == "Apple_Terminal" ]]; then
        osascript <<'EOF' 2>/dev/null
tell application "Terminal"
    set fs to font size of selected tab of front window
    set font size of selected tab of front window to fs - 6
end tell
EOF
        echo "✓ Terminal.app font -6pt"
    else
        echo "manual font restore (Cmd-0 / Ctrl-0)"
    fi
}

# dmmute  — system-wide mute (useful before screen-share with audio).
dmmute() {
    osascript -e 'set volume output muted true'
    echo "✓ muted"
}
dmunmute() {
    osascript -e 'set volume output muted false'
    echo "✓ unmuted"
}
