#!/usr/bin/env bash
# scripts/utils/tool-updater.sh
# Background auto-updater for integrated CLI tools
# Runs silently in the background with staggered updates to minimize CPU impact.
#
# Strategy:
#   - Brew tools: weekly (pre-built binaries, fast)
#   - Pipx tools: weekly (Python wheels, fast)
#   - Go tools: bi-weekly (binary download, fast)
#   - Cargo tools: monthly + nice'd (compile from source, CPU heavy)

CACHE_DIR="$HOME/.cache/claw-updates"
mkdir -p "$CACHE_DIR"

CURRENT_TIME=$(date +%s)

# Check if a category needs updating based on its own interval
needs_update() {
    local cache_file="$CACHE_DIR/$1"
    local interval_seconds="$2"
    if [[ ! -f "$cache_file" ]]; then
        return 0  # Never run, needs update
    fi
    local last=$(cat "$cache_file")
    local diff=$((CURRENT_TIME - last))
    [[ $diff -ge $interval_seconds ]]
}

mark_updated() {
    echo "$CURRENT_TIME" > "$CACHE_DIR/$1"
}

# All output is silenced. Each category runs only if its interval has elapsed.
(
    # --- Brew (weekly = 604800s) - Pre-built binaries, lightweight ---
    if needs_update "brew" 604800; then
        if command -v brew &> /dev/null; then
            brew upgrade eza bat zoxide fd ripgrep bottom zellij 2>/dev/null
        fi
        mark_updated "brew"
    fi

    # --- Pipx (weekly = 604800s) - Python wheels, fast ---
    if needs_update "pipx" 604800; then
        if command -v pipx &> /dev/null; then
            pipx upgrade rovr 2>/dev/null
            pipx upgrade osint-d2 2>/dev/null
        fi
        mark_updated "pipx"
    fi

    # --- Go (bi-weekly = 1209600s) - Binary downloads, moderate ---
    if needs_update "go" 1209600; then
        if command -v go &> /dev/null; then
            go install github.com/cladamos/clawea@latest 2>/dev/null
        fi
        mark_updated "go"
    fi

    # --- Cargo (monthly = 2592000s) - Compiles from source, CPU heavy ---
    # Runs at lowest CPU priority (nice 19) to avoid impacting interactive use
    if needs_update "cargo" 2592000; then
        if command -v cargo &> /dev/null; then
            nice -n 19 cargo install netwatch-tui 2>/dev/null
            nice -n 19 cargo install eilmeldung 2>/dev/null
        fi
        mark_updated "cargo"
    fi

) &> /dev/null &
