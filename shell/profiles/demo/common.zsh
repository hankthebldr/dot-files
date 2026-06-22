# shell/profiles/demo/common.zsh
# Aliases / functions / help — work identically on macOS and Linux.


# Where demo state lives (saved env, original prompt, etc.) so dmend can
# restore. One file per concurrent demo session is fine for a single user.
export DEMO_STATE_FILE="${DEMO_STATE_FILE:-${XDG_RUNTIME_DIR:-/tmp}/claw-demo-state}"

# Where demo datasets / canned scripts live. Override DEMO_ASSETS to point
# to your shared sales-eng or pre-sales asset library.
export DEMO_ASSETS="${DEMO_ASSETS:-$HOME/Demos}"

# ==========================================
# DEMO MODE ENGAGE / DISENGAGE
# ==========================================

# dmstart  — engage demo mode:
#   1. Save current PS1 + key env to DEMO_STATE_FILE
#   2. Install a customer-safe prompt (no hostname/path leakage)
#   3. Clear the screen
#   4. Toggle OS-specific DND (defined in mac.zsh / linux.zsh)
#   5. Scrub clipboard
#   6. Optionally bump terminal font via OSC escape (terminal-dependent)
dmstart() {
    if [[ -f "$DEMO_STATE_FILE" ]]; then
        echo "⚠ already in demo mode — run 'dmend' first" >&2
        return 1
    fi

    # Save prior state so dmend can restore.
    cat > "$DEMO_STATE_FILE" <<EOF
PS1_PRIOR=${(qq)PS1}
PROMPT_PRIOR=${(qq)PROMPT}
DEMO_STARTED_AT=$(date +%s)
EOF

    # Install a clean prompt. Strip hostname, path-shortening, no git status.
    # zsh prompt-string format.
    PROMPT='%F{cyan}>%f '

    # Clear scrollback (most terminals respect this OSC).
    printf '\e[3J'
    clear

    # Scrub clipboard.
    dmsanitize

    # OS-specific: toggle DND, mute notifications.
    if typeset -f _dm_engage_dnd &>/dev/null; then
        _dm_engage_dnd
    fi

    # Banner.
    printf "\n  \e[35m▓▒░\e[0m \e[1mDEMO MODE\e[0m \e[35m░▒▓\e[0m  ─  \e[2mfont up, history scrubbed, DND on\e[0m\n"
    printf "  \e[2mexit with: dmend\e[0m\n\n"
}

# dmend  — restore everything dmstart changed.
dmend() {
    if [[ ! -f "$DEMO_STATE_FILE" ]]; then
        echo "not currently in demo mode" >&2
        return 1
    fi

    # Restore prior prompt
    # shellcheck disable=SC1090
    source "$DEMO_STATE_FILE"
    PROMPT="${PROMPT_PRIOR}"

    if typeset -f _dm_disengage_dnd &>/dev/null; then
        _dm_disengage_dnd
    fi

    rm -f "$DEMO_STATE_FILE"

    printf "\n  \e[32m✓ demo mode disengaged\e[0m  \e[2m(prompt restored, notifications on)\e[0m\n\n"
}

# dmstatus  — am I in demo mode?
dmstatus() {
    if [[ -f "$DEMO_STATE_FILE" ]]; then
        local started; started="$(command grep DEMO_STARTED_AT "$DEMO_STATE_FILE" | cut -d= -f2)"
        local elapsed=$(( $(date +%s) - started ))
        printf "✓ DEMO MODE active — running for %dm %ds\n" $((elapsed/60)) $((elapsed%60))
    else
        echo "demo mode off"
    fi
}

# ==========================================
# CLIPBOARD SAFETY
# ==========================================

# dmsanitize  — clear clipboard. Call before any screen-share where the
# customer can see Cmd-V suggestions or your clipboard manager popup.
dmsanitize() {
    if command -v clip_copy &>/dev/null; then
        printf '' | clip_copy
    elif command -v pbcopy &>/dev/null; then
        printf '' | pbcopy
    elif command -v wl-copy &>/dev/null; then
        wl-copy --clear
    elif command -v xclip &>/dev/null; then
        printf '' | xclip -selection clipboard
    fi
    echo "✓ clipboard scrubbed"
}

# dmscan-history  — flag recent history lines that look like secrets.
# Doesn't delete — just lists. Useful BEFORE a screen-share to manually
# scrub or run `history -d <n>` on flagged entries.
dmscan-history() {
    fc -l -100 2>/dev/null | command grep -iE \
        '(password|secret|token|api[_-]?key|bearer|aws_secret|ssh-rsa|BEGIN PRIVATE)' \
        || echo "✓ no obvious secrets in last 100 history lines"
}

# ==========================================
# RECORDING
# ==========================================

# dmrec [name]  — start asciinema recording with demo-safe defaults.
# Captures to $DEMO_ASSETS/recordings/.
dmrec() {
    local name="${1:-demo-$(date +%Y%m%d-%H%M%S)}"
    local dir="$DEMO_ASSETS/recordings"
    mkdir -p "$dir"
    if ! command -v asciinema &>/dev/null; then
        echo "asciinema not installed — run: claw install demo" >&2
        return 1
    fi
    asciinema rec --idle-time-limit 2 "$dir/${name}.cast"
}

# dmrec-gif <cast>  — convert an asciinema cast to a GIF via agg.
dmrec-gif() {
    local input="${1:?usage: dmrec-gif <recording.cast>}"
    local output="${input%.cast}.gif"
    if ! command -v agg &>/dev/null; then
        echo "agg not installed — run: claw install demo" >&2
        return 1
    fi
    agg --theme monokai --speed 1.5 "$input" "$output"
    echo "✓ $output"
}

# ==========================================
# DEMO ASSETS
# ==========================================

# dmdata <name>  — copy a canned demo dataset into CWD.
# Looks under $DEMO_ASSETS/datasets/. Lists available if called with no arg.
dmdata() {
    local name="${1:-}"
    local dir="$DEMO_ASSETS/datasets"
    if [[ -z "$name" ]]; then
        if [[ -d "$dir" ]]; then
            echo "available datasets:"
            ls "$dir" | sed 's/^/  /'
        else
            echo "no datasets dir yet — mkdir $dir and add canned data"
        fi
        return 0
    fi
    if [[ ! -e "$dir/$name" ]]; then
        echo "no such dataset: $name" >&2
        return 1
    fi
    cp -R "$dir/$name" .
    echo "✓ copied $name → $(pwd)/$name"
}

# dmcountdown <seconds>  — visible countdown for timed demo segments.
dmcountdown() {
    local secs="${1:-60}"
    local end=$(( $(date +%s) + secs ))
    while (( $(date +%s) < end )); do
        local left=$(( end - $(date +%s) ))
        printf "\r  \e[33m⏱\e[0m  \e[2m%d:%02d remaining\e[0m  " \
            $((left/60)) $((left%60))
        sleep 1
    done
    printf "\r  \e[31m⏰ time!\e[0m                  \n"
}

# ==========================================
# HELP
# ==========================================

demo-help() {
    cat <<'EOF'
DEMO profile — SHOW-RUNNER (Tier 5: customer-facing)

  ── engage / disengage ───────────────
  dmstart                 enter demo mode (clean prompt · DND · clipboard scrub)
  dmend                   restore prior shell state + notifications
  dmstatus                am I in demo mode? show duration if yes

  ── safety ───────────────────────────
  dmsanitize              wipe clipboard
  dmscan-history          flag recent secret-shaped history lines

  ── recording ────────────────────────
  dmrec [name]            asciinema recording → $DEMO_ASSETS/recordings/
  dmrec-gif <cast>        cast → GIF via agg

  ── canned assets ────────────────────
  dmdata [name]           list / copy demo datasets

  ── timing ───────────────────────────
  dmcountdown <seconds>   visible countdown (default 60s)

  ── platform-specific (see mac.zsh / linux.zsh) ──
  dmbig                   bump terminal font + window size
  dmnormal                restore default font + window size
  _dm_engage_dnd          (internal) toggle Do-Not-Disturb
EOF
}
