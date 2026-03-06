#!/usr/bin/env bash
# scripts/utils/mac-ui-automate.sh
# macOS OS Automation Bridge for Agentic Interaction
# Allows MCP servers and agents to trigger native OS GUI actions

c_reset=$'\e[0m'
c_cyan=$'\e[38;2;88;166;255m'
c_red=$'\e[38;2;255;123;114m'

usage() {
    echo "Usage: $0 [command] [args]"
    echo "Commands:"
    echo "  notify <title> <message>      Display a native macOS notification"
    echo "  open_app <app_name>           Launch a GUI application by name"
    echo "  type_text <text>              Type text using emulated keystrokes into the active window"
    echo "  click <x_cord> <y_cord>       Click the screen (Requires cliclick)"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

COMMAND=$1

case "$COMMAND" in
    notify)
        if [[ $# -lt 3 ]]; then
            echo "${c_red}Usage: $0 notify <title> <message>${c_reset}"
            exit 1
        fi
        TITLE=$2
        # Use shift to capture the rest of the arguments as the message
        shift 2
        MESSAGE="$*"
        osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\""
        echo "${c_cyan}✅ Notification sent: $TITLE${c_reset}"
        ;;
    open_app)
        if [[ $# -lt 2 ]]; then
            echo "${c_red}Usage: $0 open_app <app_name>${c_reset}"
            exit 1
        fi
        APP_NAME=$2
        open -a "$APP_NAME"
        echo "${c_cyan}✅ Opened Application: $APP_NAME${c_reset}"
        ;;
    type_text)
        if [[ $# -lt 2 ]]; then
            echo "${c_red}Usage: $0 type_text <text>${c_reset}"
            exit 1
        fi
        shift 1
        TEXT_TO_TYPE="$*"
        osascript -e "tell application \"System Events\" to keystroke \"$TEXT_TO_TYPE\""
        echo "${c_cyan}✅ Typed text.${c_reset}"
        ;;
    click)
        if [[ $# -lt 3 ]]; then
            echo "${c_red}Usage: $0 click <x> <y>${c_reset}"
            exit 1
        fi
        X=$2
        Y=$3
        if command -v cliclick &> /dev/null; then
            cliclick c:"$X,$Y"
            echo "${c_cyan}✅ Clicked at ($X, $Y)${c_reset}"
        else
            echo "${c_red}Error: 'cliclick' is not installed. Run brew install cliclick.${c_reset}"
        fi
        ;;
    *)
        usage
        ;;
esac
