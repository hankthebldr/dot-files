#!/usr/bin/env bash
# ============================================
# OPEN CLAW — Gamified 80s Onboarding TUI
# ============================================
# A retro arcade-style character-creation flow that asks the user a few
# personality questions, scores their answers against the 8 workflow
# profiles (cloud / security / devops / ai / research / cortex / claude /
# local), and offers to install + activate the winning profile.
#
# Visual aesthetic: hot pink / neon cyan / synthwave purple, chunky ASCII
# banners, 80s arcade vocabulary ("INSERT COIN", "PRESS START", "CHOOSE
# YOUR FIGHTER"). Designed to be funny — it will roast the user gently
# based on their answers.
#
# Subcommands:
#   start              run the full character-creation flow (default)
#   replay             clear saved state + run again
#   show               print last saved profile choice
#
# State: $XDG_DATA_HOME/claw/onboarding.tsv  (one row per completed run)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claw"
STATE_FILE="$STATE_DIR/onboarding.tsv"

# ============================================
# 80s NEON PALETTE (true-color, falls back to ANSI on dumb terminals)
# ============================================
# Hot pink #ff2e88, neon cyan #00f5ff, synthwave purple #b537f2, sunset
# orange #ff6f3c, neon green #39ff14, dim grid #4a4a8a, retro white #fdf6e3.
if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
    c_reset=$'\e[0m'
    c_pink=$'\e[38;2;255;46;136m'
    c_cyan=$'\e[38;2;0;245;255m'
    c_purple=$'\e[38;2;181;55;242m'
    c_orange=$'\e[38;2;255;111;60m'
    c_green=$'\e[38;2;57;255;20m'
    c_yellow=$'\e[38;2;255;230;46m'
    c_grid=$'\e[38;2;74;74;138m'
    c_white=$'\e[38;2;253;246;227m'
    c_dim=$'\e[38;2;139;148;158m'
    c_bold=$'\e[1m'
    c_blink=$'\e[5m'
else
    c_reset='' c_pink='' c_cyan='' c_purple='' c_orange='' c_green=''
    c_yellow='' c_grid='' c_white='' c_dim='' c_bold='' c_blink=''
fi

# Optional gum (pretty prompts). We don't require it — fallback uses
# stdlib read so onboarding works on a minimal install (the whole point of
# bootstrapping the dotfiles).
HAS_GUM=false
command -v gum &>/dev/null && HAS_GUM=true

# ============================================
# ART
# ============================================
# Splash. The CRT divider lines use ▀▄▀ for that "scanline" feel.
_splash() {
    clear
    cat <<EOF
${c_purple}
            ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
            ▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄
${c_reset}
${c_pink}             ██████╗ ██████╗ ███████╗███╗   ██╗${c_reset}    ${c_cyan}        ${c_reset}
${c_pink}            ██╔═══██╗██╔══██╗██╔════╝████╗  ██║${c_reset}    ${c_cyan} ▄▄▄▄▄  ${c_reset}
${c_pink}            ██║   ██║██████╔╝█████╗  ██╔██╗ ██║${c_reset}    ${c_cyan} █ ╳ █  ${c_reset}
${c_pink}            ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║${c_reset}    ${c_cyan} ▀▄▄▄▀  ${c_reset}
${c_pink}            ╚██████╔╝██║     ███████╗██║ ╚████║${c_reset}    ${c_cyan}        ${c_reset}
${c_pink}             ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝${c_reset}
${c_cyan}                ▄████▄   ██▓     ▄▄▄       █     █░${c_reset}
${c_cyan}               ▒██▀ ▀█  ▓██▒    ▒████▄    ▓█░ █ ░█░${c_reset}
${c_cyan}               ▒▓█    ▄ ▒██░    ▒██  ▀█▄  ▒█░ █ ░█ ${c_reset}
${c_cyan}               ▒▓▓▄ ▄██▒▒██░    ░██▄▄▄▄██ ░█░ █ ░█ ${c_reset}
${c_cyan}               ▒ ▓███▀ ░░██████▒ ▓█   ▓██▒░░██▒██▓ ${c_reset}
${c_purple}
            ▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄
            ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
${c_reset}
              ${c_yellow}${c_blink}»»»${c_reset}  ${c_white}${c_bold}CHARACTER  SELECT${c_reset}  ${c_yellow}${c_blink}«««${c_reset}
                  ${c_dim}rad new wave dotfiles, c.1986${c_reset}

EOF
}

# Synthwave horizon between sections — purely decorative.
_horizon() {
    printf "${c_purple}  ════════════════════════════════════════════════════════${c_reset}\n"
    printf "${c_cyan}    ░▒▓█  ${c_pink}LEVEL  %s${c_cyan}  █▓▒░${c_reset}\n" "$1"
    printf "${c_purple}  ════════════════════════════════════════════════════════${c_reset}\n\n"
}

# ============================================
# PROFILE METADATA
# ============================================
# Each profile gets a class name (RPG-style), a one-liner roast, and an
# install hook (the toolchain script under scripts/install). The class
# names are deliberately tongue-in-cheek.
_profile_class() {
    case "$1" in
        cloud)    echo "SKYSURFER" ;;
        security) echo "NIGHTHACKER" ;;
        devops)   echo "WRENCH-MAGE" ;;
        ai)       echo "NEUROMANCER" ;;
        research) echo "DATA-DJ" ;;
        cortex)   echo "GHOST-IN-THE-XSIAM" ;;
        claude)   echo "PROMPT-RIDER" ;;
        local)    echo "GARAGE-HACKER" ;;
        default)  echo "PIXEL-DRIFTER" ;;
        *)        echo "UNKNOWN-WANDERER" ;;
    esac
}
_profile_flair() {
    case "$1" in
        cloud)    echo "boots up clusters before breakfast. owns 4 TLDs you've never heard of." ;;
        security) echo "thinks your password is cute. has been in your router since Tuesday." ;;
        devops)   echo "speaks fluent YAML. has opinions about Kubernetes. strong opinions." ;;
        ai)       echo "prompted their way out of a parking ticket. has a 70B model on a thumb drive." ;;
        research) echo "scraped the entire internet last weekend. now organizing it by vibe." ;;
        cortex)   echo "knows what XSOAR stands for. actually likes it." ;;
        claude)   echo "talks to AI more than humans. their git history is 90 percent agent commits." ;;
        local)    echo "compiles everything from source. owns 11 unfinished CLI tools." ;;
        default)  echo "the chill one. just wants a nice prompt and \`z\` to work." ;;
    esac
}

# ============================================
# Q&A ENGINE
# ============================================
# Each question prints a numbered menu; the user types 1..N or picks via
# gum choose. Each option declares which profiles it tilts the score
# toward (space-separated; appears in the OPTS array). After the run we
# tally and pick the highest scorer.
#
# Conventions:
#   OPTS=("label::profile1 profile2 weight" ...)
#   weight is omitted → 1; if present, it adds N to the named profiles.
declare -A SCORES
for p in cloud security devops ai research cortex claude local default; do
    SCORES[$p]=0
done

_ask() {
    local title="$1"
    shift
    local opts=("$@")

    echo ""
    printf "  ${c_pink}${c_bold}▸ %s${c_reset}\n" "$title"
    echo ""

    local i=1
    local labels=()
    for opt in "${opts[@]}"; do
        local label="${opt%%::*}"
        labels+=("$label")
        printf "    ${c_cyan}[${c_bold}%d${c_reset}${c_cyan}]${c_reset} ${c_white}%s${c_reset}\n" "$i" "$label"
        ((i++)) || true
    done
    echo ""

    local choice=""
    if $HAS_GUM; then
        choice="$(printf '%s\n' "${labels[@]}" | gum choose \
            --cursor.foreground="#ff2e88" \
            --selected.foreground="#00f5ff" \
            --header="  pick one >" 2>/dev/null)"
    fi

    # Fallback / gum failure → numeric read loop.
    if [[ -z "$choice" ]]; then
        local n=""
        while true; do
            printf "  ${c_yellow}>${c_reset} "
            IFS= read -r n
            # Default to 1 if they just hit enter — friendly behaviour.
            [[ -z "$n" ]] && n=1
            if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#opts[@]} )); then
                choice="${labels[$((n-1))]}"
                break
            fi
            printf "  ${c_orange}!${c_reset} ${c_dim}come on, just 1..%d${c_reset}\n" "${#opts[@]}"
        done
    fi

    # Find the chosen option and apply its score delta.
    local picked=""
    for opt in "${opts[@]}"; do
        local label="${opt%%::*}"
        if [[ "$label" == "$choice" ]]; then
            picked="$opt"
            break
        fi
    done
    if [[ -z "$picked" ]]; then
        printf "  ${c_orange}(skipped — no match)${c_reset}\n"
        return
    fi

    local payload="${picked#*::}"
    # Parse: "prof1 prof2 [N]" — last field is weight iff it's numeric.
    local fields=($payload)
    local weight=1
    local last="${fields[${#fields[@]}-1]}"
    if [[ "$last" =~ ^[0-9]+$ ]]; then
        weight=$last
        unset 'fields[${#fields[@]}-1]'
    fi
    for prof in "${fields[@]}"; do
        SCORES[$prof]=$(( ${SCORES[$prof]:-0} + weight ))
    done

    printf "  ${c_green}✓${c_reset} ${c_dim}logged: %s${c_reset}\n" "$choice"
}

# ============================================
# THE QUIZ
# ============================================
# Six questions: enough signal to pick a profile, few enough to stay fun.
# Each option tilts the score toward 1–3 profiles. I keep one "joke" option
# per question that scores `default` — for users who want the basic shell.
_run_quiz() {
    _horizon 1

    _ask "WHEN does your best code happen?" \
        "3 AM — neon hours::security ai 2" \
        "9-to-5, fueled by enterprise coffee::devops cloud" \
        "weekend marathon, no sleep::ai research" \
        "whenever the linter stops yelling::default"

    _horizon 2

    _ask "Your terminal is mostly running…" \
        "kubectl + terraform plan::cloud devops 2" \
        "nmap + burp + a Wireshark capture::security 2" \
        "ollama serve + a python repl::ai research" \
        "XSOAR playbook + a frantic incident chan::cortex 2" \
        "claude code in --dangerously-skip-permissions::claude 2" \
        "vim + tmux + makefile + tears::local default"

    _horizon 3

    _ask "Pick your weapon" \
        "a freshly-rotated SSH key::security devops" \
        "a perfect IAM policy::cloud" \
        "a fine-tuned 13B you trained in the garage::ai" \
        "a regex that took 3 hours but works once::research" \
        "a Helm chart you wrote yourself::devops cloud" \
        "an alias. just a really good alias::default local"

    _horizon 4

    _ask "Production just exploded. You…" \
        "open the runbook you actually wrote::devops cortex 2" \
        "tail logs while quietly cursing::devops default" \
        "ask Claude what happened::claude ai" \
        "are already three pivots deep in someone else's network::security" \
        "git blame, then pretend it wasn't you::default" \
        "scrape postmortems from every similar outage::research"

    _horizon 5

    _ask "Your dream homelab is…" \
        "a rack of mini-PCs running k3s::cloud devops" \
        "an air-gapped lab full of CTF VMs::security 2" \
        "a single big GPU and a 70B model::ai 2" \
        "a Cortex XSIAM tenant + 4 data lakes::cortex 2" \
        "a notebook server humming with web scrapers::research" \
        "one quiet thinkpad and a tiling WM::local default"

    _horizon 6

    _ask "Which prompt does your soul live in?" \
        "the silent one — info on demand::default local" \
        "k8s context + AWS profile + git branch::cloud devops 2" \
        "a tiny skull emoji::security 2" \
        "model name + token count::ai claude 2" \
        "a paper count + arxiv id::research" \
        "the one your XSIAM tenant gave you::cortex"
}

# ============================================
# RESULT
# ============================================
_winner() {
    local best="default"
    local best_score=-1
    # zsh-vs-bash safe iteration: list keys explicitly.
    for p in cloud security devops ai research cortex claude local default; do
        local s=${SCORES[$p]:-0}
        if (( s > best_score )); then
            best_score=$s
            best="$p"
        fi
    done
    echo "$best"
}

_show_scoreboard() {
    echo ""
    printf "  ${c_pink}${c_bold}═══ SCOREBOARD ═══${c_reset}\n\n"
    # Sort descending by score. We pre-emit lines then sort -k2 -nr.
    {
        for p in cloud security devops ai research cortex claude local default; do
            printf "%s\t%d\n" "$p" "${SCORES[$p]:-0}"
        done
    } | sort -k2 -nr | while IFS=$'\t' read -r p s; do
        # Bar graph: each point = one █.
        local bar=""
        local i=0
        while (( i < s )); do
            bar+="█"
            ((i++)) || true
        done
        printf "    ${c_cyan}%-10s${c_reset}  ${c_pink}%s${c_reset}${c_dim}%s${c_reset}  ${c_white}%d${c_reset}\n" \
            "$p" "$bar" "$(printf '%.s·' $(seq 1 $((10 - s)) 2>/dev/null))" "$s"
    done
    echo ""
}

_announce() {
    local profile="$1"
    local class flair
    class="$(_profile_class "$profile")"
    flair="$(_profile_flair "$profile")"

    echo ""
    printf "${c_purple}  ┌────────────────────────────────────────────────────────┐${c_reset}\n"
    printf "${c_purple}  │${c_reset}                                                        ${c_purple}│${c_reset}\n"
    printf "${c_purple}  │${c_reset}   ${c_yellow}${c_bold}>>>  YOU ARE THE  %-31s${c_reset}${c_purple}│${c_reset}\n" "$class  <<<"
    printf "${c_purple}  │${c_reset}                                                        ${c_purple}│${c_reset}\n"
    printf "${c_purple}  │${c_reset}   ${c_cyan}class:${c_reset}    ${c_white}%-44s${c_reset}${c_purple}│${c_reset}\n" "$class"
    printf "${c_purple}  │${c_reset}   ${c_cyan}profile:${c_reset}  ${c_white}%-44s${c_reset}${c_purple}│${c_reset}\n" "$profile"
    printf "${c_purple}  │${c_reset}                                                        ${c_purple}│${c_reset}\n"
    # Wrap the flair so it fits in the box (54 chars usable).
    local line
    while IFS= read -r line; do
        printf "${c_purple}  │${c_reset}   ${c_dim}%-52s${c_reset}${c_purple}│${c_reset}\n" "$line"
    done < <(printf '%s\n' "$flair" | fold -s -w 52)
    printf "${c_purple}  │${c_reset}                                                        ${c_purple}│${c_reset}\n"
    printf "${c_purple}  └────────────────────────────────────────────────────────┘${c_reset}\n"
    echo ""
}

# ============================================
# INSTALL HOOK
# ============================================
# Maps a profile to its toolchain installer. Some profiles have one, some
# don't (default/local/claude have no separate toolchain). For those we
# just activate the profile.
_install_for() {
    local profile="$1"
    local script="$REPO_ROOT/scripts/install/${profile}-toolchain.sh"
    if [[ -f "$script" ]]; then
        printf "  ${c_cyan}▸${c_reset} running ${c_white}%s${c_reset}\n" "$script"
        bash "$script" || printf "  ${c_orange}!${c_reset} toolchain finished with errors — check log\n"
    else
        printf "  ${c_dim}no toolchain script for '%s' — profile-only setup${c_reset}\n" "$profile"
    fi
}

_persist_state() {
    local profile="$1"
    mkdir -p "$STATE_DIR"
    # ISO timestamp · profile · OS · user
    printf '%s\t%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$profile" \
        "$(uname -s)" \
        "${USER:-unknown}" \
        >> "$STATE_FILE"
}

# ============================================
# CONFIRM + INSTALL
# ============================================
_offer_install() {
    local profile="$1"
    echo ""
    printf "  ${c_pink}${c_bold}INSERT COIN TO CONTINUE${c_reset}\n"
    printf "  ${c_dim}I can install the %s toolchain and activate the profile now.${c_reset}\n" "$profile"
    printf "  ${c_dim}(or skip — you can always run \`claw load %s\` later)${c_reset}\n\n" "$profile"

    local answer=""
    if $HAS_GUM; then
        answer="$(gum choose --header="  go time?" \
            --cursor.foreground="#ff2e88" \
            "[Y] yes — install + activate" \
            "[N] no — just activate the profile" \
            "[S] skip — i'll do it myself" 2>/dev/null)"
        # Normalise to first letter.
        answer="${answer:1:1}"
        answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    else
        printf "  ${c_yellow}>${c_reset} [Y]es install · [N]o just activate · [S]kip: "
        IFS= read -r answer
        answer="$(printf '%s' "${answer:0:1}" | tr '[:upper:]' '[:lower:]')"
        [[ -z "$answer" ]] && answer="y"
    fi

    case "$answer" in
        y)
            printf "\n  ${c_green}${c_bold}>>> INSTALLING %s TOOLCHAIN <<<${c_reset}\n\n" "$profile"
            _install_for "$profile"
            ;;
        n)
            printf "\n  ${c_cyan}${c_bold}>>> ACTIVATING PROFILE <<<${c_reset}\n\n"
            ;;
        *)
            printf "\n  ${c_dim}skipped install. saved your class anyway.${c_reset}\n"
            _persist_state "$profile"
            return 0
            ;;
    esac

    _persist_state "$profile"

    printf "\n  ${c_purple}${c_bold}GAME COMPLETE${c_reset}  ${c_dim}— to activate in your CURRENT shell, run:${c_reset}\n"
    printf "    ${c_white}export CLAW_ACTIVE_PROFILE=%s && source \$DOTFILES_DIR/shell/profiles/%s.zsh${c_reset}\n" \
        "$profile" "$profile"
    printf "  ${c_dim}or open a new shell and run:${c_reset}\n"
    printf "    ${c_white}claw load %s${c_reset}\n\n" "$profile"
}

# ============================================
# SUBCOMMANDS
# ============================================
cmd_start() {
    _splash
    # Beat-the-CRT moment — wait for ENTER so the user reads the splash.
    printf "        ${c_yellow}${c_blink}»  PRESS  ENTER  TO  START  «${c_reset}"
    IFS= read -r _ || true
    clear

    printf "${c_cyan}  initializing character creation matrix...${c_reset}\n"
    printf "${c_dim}  this takes about 90 seconds. answer honestly — or don't, it's a game.${c_reset}\n"

    _run_quiz

    _show_scoreboard
    local winner
    winner="$(_winner)"
    _announce "$winner"
    _offer_install "$winner"
}

cmd_replay() {
    rm -f "$STATE_FILE"
    cmd_start
}

cmd_show() {
    if [[ ! -s "$STATE_FILE" ]]; then
        printf "  ${c_dim}no onboarding runs yet. try: claw onboard${c_reset}\n"
        return 0
    fi
    printf "\n  ${c_purple}${c_bold}past character runs${c_reset}\n"
    printf "  ${c_dim}─────────────────────────${c_reset}\n"
    awk -F'\t' '{ printf "    %s  %s  (%s)\n", $1, $2, $3 }' "$STATE_FILE"
    echo ""
}

cmd_help() {
    cat <<EOF

  ${c_pink}${c_bold}claw onboard${c_reset} — ${c_dim}80s arcade character creation, picks your profile${c_reset}

  ${c_white}claw onboard${c_reset}            ${c_dim}run the character-creation flow${c_reset}
  ${c_white}claw onboard replay${c_reset}     ${c_dim}wipe saved state and run again${c_reset}
  ${c_white}claw onboard show${c_reset}       ${c_dim}list past runs + profiles chosen${c_reset}

  ${c_dim}State: $STATE_FILE${c_reset}
EOF
}

case "${1:-start}" in
    start|run|play|"")  cmd_start ;;
    replay|reset)       cmd_replay ;;
    show|list|history)  cmd_show ;;
    help|-h|--help)     cmd_help ;;
    *)
        printf "  ${c_orange}?${c_reset} unknown subcommand: %s\n" "$1"
        cmd_help
        exit 1
        ;;
esac
