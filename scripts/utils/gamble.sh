#!/usr/bin/env bash
# gamble.sh — THE CLAW MACHINE 🎰 · an honest arcade slot machine.
#
# The anti-casino: every mechanic a real slot machine hides, this one prints.
#   - Tokens are EARNED (5/day of real `claw` use, mined from usage.tsv) and
#     can never be bought. `claw gamble buy` delivers a lecture, not tokens.
#   - The odds and the negative expected value are stamped on the machine
#     (`claw gamble odds`). The house edge is a teaching tool, not a secret.
#   - Hard daily cap (5 spins). After that the machine dims and tells you to
#     go build something.
#   - Pairs pay out KNOWLEDGE: a random alias from shell/aliases.zsh you
#     probably forgot you own.
# No real money. No purchases. Nothing of value is at stake — by design.
#
# Usage: claw gamble [spin|wallet|odds|ledger|stats|ethics|help]
# State: $XDG_STATE_HOME/claw/gamble/ (ledger.tsv, last-credit, unlocks)
set -uo pipefail

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claw/gamble"
LEDGER="$STATE_DIR/ledger.tsv"          # ts \t event \t delta \t balance \t note
LAST_CREDIT="$STATE_DIR/last-credit"    # last UTC day usage was converted to tokens
UNLOCKS="$STATE_DIR/unlocks"            # cosmetic unlocks (jackpot badge)
USAGE_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/claw/usage.tsv"

DAILY_SPIN_CAP=5
TOKENS_PER_ACTIVE_DAY=5
SPIN_COST=1

# ── theme (CLAW_RGB_* from theme.sh; refined-dark fallbacks) ─────────────────
# shellcheck source=/dev/null
[ -r "$DOTFILES/scripts/utils/theme.sh" ] && . "$DOTFILES/scripts/utils/theme.sh" 2>/dev/null || true
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"$'m'
c_green=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
c_purple=$'\e[38;2;'"${CLAW_RGB_PURPLE:-188;140;255}"$'m'
c_orange=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
c_red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
c_dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
c_white=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
c_bold=$'\e[1m'

err()  { printf "  ${c_red}✗${c_reset} %s\n" "$*" >&2; }
info() { printf "  ${c_cyan}●${c_reset} %s\n" "$*"; }
ok()   { printf "  ${c_green}✓${c_reset} %s\n" "$*"; }

# ── reels ────────────────────────────────────────────────────────────────────
# 8 uniform symbols → the whole probability space is 8³ = 512, small enough
# to print exactly. 🦞 is the jackpot symbol (of course it is).
SYMBOLS=(🦞 🔐 ☁️ 🧠 🛡️ 🚀 📡 🎨)
N=${#SYMBOLS[@]}

PAY_JACKPOT=100   # 🦞🦞🦞               1/512
PAY_TRIPLE=15     # any other triple      7/512
PAY_PAIR=1        # any pair (stake back) 168/512  + a wildcard tip
#                   bust                  336/512

today_utc() { date -u +%Y-%m-%d; }
now_utc()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ── ledger / wallet ──────────────────────────────────────────────────────────
_ensure_state() { mkdir -p "$STATE_DIR" 2>/dev/null || true; }

balance() {  # last ledger line carries the running balance
    [ -s "$LEDGER" ] || { printf '0'; return; }
    awk -F'\t' 'END { print ($4 == "" ? 0 : $4) }' "$LEDGER"
}

ledger_append() {  # ledger_append <event> <delta> <note>
    _ensure_state
    local bal; bal=$(( $(balance) + $2 ))
    printf '%s\t%s\t%s\t%s\t%s\n' "$(now_utc)" "$1" "$2" "$bal" "${3:-}" >> "$LEDGER"
}

# Convert real usage into tokens: TOKENS_PER_ACTIVE_DAY for every distinct UTC
# day in usage.tsv newer than the last-credit marker. Spamming commands within
# a day earns nothing extra — only showing up on a new day does.
credit_usage() {
    _ensure_state
    [ -s "$USAGE_LOG" ] || return 0
    local since=""; [ -f "$LAST_CREDIT" ] && since=$(cat "$LAST_CREDIT" 2>/dev/null)
    local days
    days=$(cut -f1 "$USAGE_LOG" | cut -c1-10 | sort -u | \
        awk -v s="$since" '$0 > s' | grep -c . || true)
    if [ "${days:-0}" -gt 0 ]; then
        local earned=$(( days * TOKENS_PER_ACTIVE_DAY ))
        ledger_append earn "$earned" "${days} active day(s) of real work"
        cut -f1 "$USAGE_LOG" | cut -c1-10 | sort -u | tail -1 > "$LAST_CREDIT"
        printf "  ${c_green}+%s${c_reset} ${c_dim}tokens · %s day(s) you actually used your tools${c_reset}\n" "$earned" "$days"
    fi
}

spins_today() {
    [ -s "$LEDGER" ] || { printf '0'; return; }
    grep -c "^$(today_utc).*	spin	" "$LEDGER" 2>/dev/null || true
}

has_unlock() { [ -f "$UNLOCKS" ] && grep -q "^$1" "$UNLOCKS" 2>/dev/null; }

# ── payout helpers ───────────────────────────────────────────────────────────
wildcard_tip() {  # a pair pays out knowledge: one of your own forgotten aliases
    local f="$DOTFILES/shell/aliases.zsh" line
    [ -r "$f" ] || return 0
    line=$(grep -E "^alias [a-zA-Z0-9_-]+=" "$f" | awk -v seed="$RANDOM" \
        'BEGIN{srand(seed)} {a[NR]=$0} END{if (NR) print a[int(rand()*NR)+1]}')
    [ -n "$line" ] || return 0
    printf "  ${c_purple}◆ wildcard tip${c_reset} ${c_dim}— from your own aliases.zsh:${c_reset}\n"
    printf "    ${c_white}%s${c_reset}\n" "$line"
}

# ── the machine ──────────────────────────────────────────────────────────────
draw_reels() {  # draw_reels <a> <b> <c> <frame-color>
    printf "    %s┌──────┬──────┬──────┐%s\n" "$4" "$c_reset"
    printf "    %s│%s  %s  %s│%s  %s  %s│%s  %s  %s│%s\n" \
        "$4" "$c_reset" "${SYMBOLS[$1]}" "$4" "$c_reset" "${SYMBOLS[$2]}" \
        "$4" "$c_reset" "${SYMBOLS[$3]}" "$4" "$c_reset"
    printf "    %s└──────┴──────┴──────┘%s\n" "$4" "$c_reset"
}

cmd_spin() {
    credit_usage
    local bal; bal=$(balance)
    local used; used=$(spins_today)

    if [ "$used" -ge "$DAILY_SPIN_CAP" ]; then
        printf "\n  ${c_dim}The Claw Machine dims. %s/%s spins today.${c_reset}\n" "$used" "$DAILY_SPIN_CAP"
        printf "  ${c_orange}🌅 Go build something. The machine will be here tomorrow.${c_reset}\n\n"
        return 0
    fi
    if [ "$bal" -lt "$SPIN_COST" ]; then
        printf "\n  ${c_dim}Wallet: %s tokens — a spin costs %s.${c_reset}\n" "$bal" "$SPIN_COST"
        info "tokens are earned, never bought: +${TOKENS_PER_ACTIVE_DAY}/day of real claw use"
        printf "  ${c_dim}  come back after a day of actual work · claw gamble ethics${c_reset}\n\n"
        return 0
    fi

    local badge=""
    has_unlock high-roller && badge=" ${c_orange}★ HIGH ROLLER${c_reset}"
    printf "\n  ${c_purple}${c_bold}🎰 THE CLAW MACHINE${c_reset}${badge}  ${c_dim}stake %s · wallet %s · spin %s/%s today${c_reset}\n\n" \
        "$SPIN_COST" "$bal" "$(( used + 1 ))" "$DAILY_SPIN_CAP"

    local a b c i
    # animate only on a real terminal; plain single draw otherwise
    if [ -t 1 ]; then
        printf '\e[?25l'
        for i in 1 2 3 4 5 6 7 8; do
            a=$(( RANDOM % N )); b=$(( RANDOM % N )); c=$(( RANDOM % N ))
            draw_reels "$a" "$b" "$c" "$c_dim"
            sleep 0.12
            [ "$i" -lt 8 ] && printf '\e[3A'
        done
        printf '\e[3A'
    fi
    a=$(( RANDOM % N )); b=$(( RANDOM % N )); c=$(( RANDOM % N ))

    local win=0 event=bust note="${SYMBOLS[$a]}${SYMBOLS[$b]}${SYMBOLS[$c]}"
    if [ "$a" -eq "$b" ] && [ "$b" -eq "$c" ]; then
        if [ "$a" -eq 0 ]; then win=$PAY_JACKPOT; event=jackpot; else win=$PAY_TRIPLE; event=triple; fi
    elif [ "$a" -eq "$b" ] || [ "$b" -eq "$c" ] || [ "$a" -eq "$c" ]; then
        win=$PAY_PAIR; event=pair
    fi

    case "$event" in
        jackpot) draw_reels "$a" "$b" "$c" "$c_orange" ;;
        triple)  draw_reels "$a" "$b" "$c" "$c_green"  ;;
        pair)    draw_reels "$a" "$b" "$c" "$c_cyan"   ;;
        *)       draw_reels "$a" "$b" "$c" "$c_dim"    ;;
    esac
    [ -t 1 ] && printf '\e[?25h'

    local net=$(( win - SPIN_COST ))
    ledger_append spin "$net" "$event $note"

    case "$event" in
        jackpot)
            printf "\n  ${c_orange}${c_bold}🦞🦞🦞 CLAW JACKPOT — +%s tokens${c_reset}\n" "$win"
            if ! has_unlock high-roller; then
                _ensure_state; printf 'high-roller\t%s\n' "$(now_utc)" >> "$UNLOCKS"
                printf "  ${c_orange}★ unlocked: HIGH ROLLER badge${c_reset} ${c_dim}(cosmetic, worthless, magnificent)${c_reset}\n"
            fi
            ;;
        triple)
            printf "\n  ${c_green}${c_bold}✦ TRIPLE — +%s tokens${c_reset}\n" "$win"
            ;;
        pair)
            printf "\n  ${c_cyan}✧ pair — stake back${c_reset} ${c_dim}(net 0)${c_reset}\n"
            wildcard_tip
            ;;
        *)
            printf "\n  ${c_dim}✗ bust — the house keeps your token.${c_reset}\n"
            printf "  ${c_dim}  (it said it would: claw gamble odds)${c_reset}\n"
            ;;
    esac
    printf "  ${c_dim}wallet: %s tokens${c_reset}\n\n" "$(balance)"
}

cmd_wallet() {
    credit_usage
    local badge=""
    has_unlock high-roller && badge="  ${c_orange}★ HIGH ROLLER${c_reset}"
    printf "\n  ${c_purple}${c_bold}claw gamble wallet${c_reset}${badge}\n"
    printf "  ${c_dim}─────────────────────────────────────${c_reset}\n"
    printf "  ${c_white}${c_bold}%s${c_reset} ${c_dim}tokens · %s/%s spins used today${c_reset}\n" \
        "$(balance)" "$(spins_today)" "$DAILY_SPIN_CAP"
    printf "\n  ${c_dim}earning: +%s tokens per distinct day of real claw use (usage.tsv)${c_reset}\n" "$TOKENS_PER_ACTIVE_DAY"
    printf "  ${c_dim}tokens cannot be bought. that is the whole point.${c_reset}\n\n"
}

cmd_odds() {
    cat <<EOF

  ${c_purple}${c_bold}🎰 THE CLAW MACHINE — printed odds${c_reset}
  ${c_dim}─────────────────────────────────────────────────────${c_reset}
  ${c_dim}3 reels · 8 uniform symbols · 8³ = 512 equally likely outcomes${c_reset}
  ${c_dim}stake per spin: ${SPIN_COST} token${c_reset}

  ${c_orange}🦞🦞🦞 jackpot${c_reset}   pays ${c_white}${PAY_JACKPOT}${c_reset}   ${c_dim}  1/512  (0.20%)${c_reset}
  ${c_green}✦ other triple${c_reset}  pays ${c_white}${PAY_TRIPLE}${c_reset}    ${c_dim}  7/512  (1.37%)${c_reset}
  ${c_cyan}✧ any pair${c_reset}      pays ${c_white}${PAY_PAIR}${c_reset}     ${c_dim}168/512 (32.81%) + a wildcard tip${c_reset}
  ${c_dim}✗ bust          pays 0     336/512 (65.62%)${c_reset}

  ${c_white}${c_bold}Expected value per spin:${c_reset}
    ${c_dim}(1×100 + 7×15 + 168×1) / 512 − 1 = 373/512 − 1 ≈ ${c_reset}${c_red}−0.27 tokens${c_reset}
    ${c_red}${c_bold}house edge ≈ 27%${c_reset} ${c_dim}— mathematically, you lose. every casino works
    this way; this one just prints it on the machine.${c_reset}

  ${c_dim}the only positive-EV move is the pair's wildcard tip: it teaches you
  an alias you already own. knowledge doesn't depreciate.${c_reset}

EOF
}

cmd_ethics() {
    cat <<EOF

  ${c_purple}${c_bold}the house rules — gambling ethics, printed on the machine${c_reset}
  ${c_dim}─────────────────────────────────────────────────────${c_reset}
  ${c_green}1.${c_reset} ${c_white}nothing of value is at stake.${c_reset} ${c_dim}tokens are worthless by design
     and can never be bought, sold, or transferred.${c_reset}
  ${c_green}2.${c_reset} ${c_white}the odds are public.${c_reset} ${c_dim}claw gamble odds — full table, exact EV,
     disclosed house edge. no mystery boxes.${c_reset}
  ${c_green}3.${c_reset} ${c_white}hard daily cap.${c_reset} ${c_dim}${DAILY_SPIN_CAP} spins, then the machine sends you back to work.
     no streak-shaming, no "one more spin" dark patterns.${c_reset}
  ${c_green}4.${c_reset} ${c_white}the currency is showing up.${c_reset} ${c_dim}tokens come from days you actually
     used your tools — the machine funds itself with your productivity.${c_reset}
  ${c_green}5.${c_reset} ${c_white}the ledger is append-only and yours.${c_reset} ${c_dim}claw gamble ledger — every
     spin, every payout, forever. transparency beats regret.${c_reset}

  ${c_dim}real slot machines hide all five of these. that's the lesson.${c_reset}
  ${c_dim}if real gambling stops being fun: 1-800-GAMBLER (US) · begambleaware.org${c_reset}

EOF
}

cmd_buy() {
    printf "\n  ${c_red}✗ no.${c_reset}\n"
    printf "  ${c_dim}the moment tokens can be bought, this stops being a toy and starts
  being a casino. the machine takes exactly one currency: ${c_reset}${c_white}days of real work${c_reset}${c_dim}.
  see: claw gamble ethics${c_reset}\n\n"
}

cmd_ledger() {
    if [ ! -s "$LEDGER" ]; then info "ledger empty — pull the lever: claw gamble"; return 0; fi
    printf "\n  ${c_purple}${c_bold}claw gamble ledger${c_reset}  ${c_dim}%s${c_reset}\n\n" "$LEDGER"
    tail -20 "$LEDGER" | awk -F'\t' \
        -v g="$c_green" -v r="$c_red" -v d="$c_dim" -v w="$c_white" -v x="$c_reset" '{
            col = ($3 + 0 >= 0) ? g : r
            printf "  %s%s%s  %s%-8s%s %s%+5d%s  %sbal %s%s  %s%s%s\n", d, substr($1,1,16), x, w, $2, x, col, $3, x, d, $4, x, d, $5, x
        }'
    printf "\n"
}

cmd_stats() {
    if [ ! -s "$LEDGER" ]; then info "no spins yet — claw gamble"; return 0; fi
    printf "\n  ${c_purple}${c_bold}claw gamble stats${c_reset}\n"
    printf "  ${c_dim}─────────────────────────────────────${c_reset}\n"
    awk -F'\t' -v cap="$DAILY_SPIN_CAP" \
        -v g="$c_green" -v r="$c_red" -v d="$c_dim" -v w="$c_white" -v x="$c_reset" '
        $2 == "spin" { spins++; net += $3; if ($3 > best) best = $3
                       if ($5 ~ /^jackpot/) jp++ }
        $2 == "earn" { earned += $3 }
        END {
            if (!spins) { printf "  %sno spins yet%s\n", d, x; exit }
            printf "  %sspins%s          %s%d%s\n", d, x, w, spins, x
            printf "  %searned (work)%s  %s+%d%s\n", d, x, g, earned, x
            col = (net >= 0) ? g : r
            printf "  %snet (machine)%s  %s%+d%s\n", d, x, col, net, x
            printf "  %sbest spin%s      %s%+d%s\n", d, x, g, best, x
            printf "  %sjackpots%s       %s%d%s\n", d, x, w, jp, x
            printf "  %srealized edge%s  %s%.1f%%%s %s(printed edge: 27%%)%s\n", d, x, w, (spins ? -net*100.0/spins : 0), x, d, x
        }' "$LEDGER"
    printf "\n  ${c_dim}the longer you play, the closer realized edge crawls to 27%%.
  that convergence is the entire gambling industry. class dismissed.${c_reset}\n\n"
}

cmd_help() {
    cat <<EOF

  ${c_purple}${c_bold}claw gamble${c_reset} — THE CLAW MACHINE 🎰 ${c_dim}(an honest arcade)${c_reset}

  ${c_white}claw gamble${c_reset}          ${c_dim}pull the lever (costs ${SPIN_COST} token · ${DAILY_SPIN_CAP}/day cap)${c_reset}
  ${c_white}claw gamble wallet${c_reset}   ${c_dim}balance + how tokens are earned${c_reset}
  ${c_white}claw gamble odds${c_reset}     ${c_dim}the printed odds table + exact EV${c_reset}
  ${c_white}claw gamble stats${c_reset}    ${c_dim}lifetime spins · realized house edge${c_reset}
  ${c_white}claw gamble ledger${c_reset}   ${c_dim}append-only history of every spin${c_reset}
  ${c_white}claw gamble ethics${c_reset}   ${c_dim}the house rules (read these once)${c_reset}

  ${c_dim}tokens: +${TOKENS_PER_ACTIVE_DAY} per distinct day of real claw use · never purchasable${c_reset}

EOF
}

case "${1:-spin}" in
    spin|pull|"")        cmd_spin ;;
    wallet|balance|bal)  cmd_wallet ;;
    odds|table)          cmd_odds ;;
    ethics|rules)        cmd_ethics ;;
    buy|deposit|topup|purchase) cmd_buy ;;
    ledger|history|log)  cmd_ledger ;;
    stats)               cmd_stats ;;
    help|-h|--help)      cmd_help ;;
    *)                   err "unknown gamble subcommand: $1"; cmd_help; exit 1 ;;
esac
