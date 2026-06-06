#!/usr/bin/env bash
################################################################################
# Next-Gen CLI Toolchain — the "best-in-class 2026" pack
#
# Curated modern CLI/TUI tools that complement (do NOT duplicate) the base
# modern-cli set. Bootstraps `eget` first so a fresh Linux box can fetch the
# GitHub-release binary tier in one pass, then installs everything via
# apt/brew → eget/cargo/go/pipx fallbacks.
#
#   claw install nextgen
#   DRY_RUN=1 claw install nextgen        # preview
#   TOOLCHAIN_ONLY="just k9s pv" claw install nextgen   # subset
################################################################################
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toolchain-runner.sh"

TOOLCHAIN_TITLE="NEXT-GEN  CLI  PACK"
TOOLCHAIN_CLASS="SWISS-ARMY  LOADOUT"
TOOLCHAIN_TAG="progress bars · k8s cockpit · task runner · secrets · self-update · delight"

# Format: "id|brew|apt|fallback|notes"
TOOLCHAIN_MAP=(
    # ── 01. Progress / Download UX ─────────────────────────────────────────
    "pv|pv|pv|none|pipe viewer — progress bar for any pipe (cp/dd/backup)"
    "aria2c|aria2|aria2|none|multi-connection downloader (segmented, fast)"
    "xh|xh|?|eget:ducaale/xh|HTTPie in Rust — friendly HTTP, static binary"
    "gtrash|gtrash|?|eget:umlx5h/gtrash|XDG-compliant trash with restore TUI (safe rm)"
    "chafa|chafa|chafa|none|best image/GIF → terminal graphics"

    # ── 02. TUI cockpits ───────────────────────────────────────────────────
    "k9s|k9s|?|eget:derailed/k9s|Kubernetes cluster TUI (the homelab cockpit)"
    "oxker|oxker|?|eget:mrjackwills/oxker|at-a-glance Docker container TUI"
    "trip|trippy|?|eget:fujiapple852/trippy|ping+traceroute TUI (mtr successor)"
    "gdu|gdu|?|eget:dundee/gdu|fastest interactive disk-usage TUI (SSD-tuned)"
    "doggo|doggo|?|eget:mr-karan/doggo|modern DNS client (DoH/DoT/DoQ) — replaces dog"
    "sshs|sshs|?|eget:quantumsheep/sshs|fzf-style SSH picker over ~/.ssh/config"

    # ── 03. Shell productivity ─────────────────────────────────────────────
    "just|just|just|eget:casey/just|modern task runner (justfile)"
    "mise|mise|?|curl:https://mise.run|unified runtime+env+task mgr (fnm/pyenv/direnv)"
    "watchexec|watchexec|?|eget:watchexec/watchexec|run a cmd on file change (entr++)"
    "hyperfine|hyperfine|hyperfine|eget:sharkdp/hyperfine|statistical CLI benchmarking"
    "sd|sd|?|eget:chmln/sd|intuitive find-and-replace (sed for the 90%)"
    "jless|jless|?|eget:PaulJuliusMartinez/jless|interactive JSON/YAML pager TUI"
    "qsv|qsv|?|eget:dathere/qsv|blazing CSV toolkit (xsv successor)"
    "gron|gron|gron|none|greppable JSON"

    # ── 04. Secrets foundation ─────────────────────────────────────────────
    "age|age|age|eget:FiloSottile/age|modern file encryption (GPG-free)"
    "sops|sops|?|eget:getsops/sops|encrypt only the VALUES in yaml/json/env"
    "keychain|keychain|keychain|none|ssh-agent lifecycle across shells"

    # ── 05. System ops / self-update ───────────────────────────────────────
    "topgrade|topgrade|?|eget:topgrade-rs/topgrade|update EVERYTHING in one command"
    "gh|gh|gh|none|GitHub CLI"

    # ── 06. Useful delight ─────────────────────────────────────────────────
    "onefetch|onefetch|?|eget:o2sh/onefetch|git repo dashboard (neofetch for repos)"
    "tte|terminaltexteffects|?|pipx|animated text effects engine"
)

declare -A TOOLCHAIN_SECTIONS=(
    [0]="01|Progress  /  Download  UX"
    [5]="02|TUI  Cockpits"
    [11]="03|Shell  Productivity"
    [19]="04|Secrets  Foundation"
    [22]="05|System  Ops  /  Self-Update"
    [24]="06|Useful  Delight"
)

# ── Preflight: bootstrap `eget` so the binary tier resolves on a fresh box ──
toolchain_preflight_extras() {
    if command -v eget &>/dev/null; then log_skip "eget (present)"; return; fi
    log_info "bootstrapping ${c_white}eget${c_reset} (GitHub-binary fetcher)..."
    [[ "$DRY_RUN" == "1" ]] && { log_info "DRY: install eget"; return; }
    if command -v go &>/dev/null; then
        go install github.com/zyedidia/eget@latest 2>/dev/null && return
    fi
    # Official installer drops ./eget in cwd.
    local tmp; tmp="$(mktemp -d)"
    if (cd "$tmp" && curl -fsSL https://zyedidia.github.io/eget.sh | sh) 2>/dev/null; then
        install -m755 "$tmp/eget" "$HOME/.local/bin/eget" && export PATH="$HOME/.local/bin:$PATH"
    else
        log_warning "eget bootstrap failed — binary-tier tools will be skipped"
    fi
    rm -rf "$tmp"
}

# ── Linux-only homelab TUIs (graceful no-op on macOS) ──────────────────────
toolchain_extras() {
    [[ "$PKG_MANAGER" != "apt" ]] && return 0
    _section 7 "Linux  Homelab  TUIs"
    local pairs=( "bandwhich:bandwhich/bandwhich" "impala:pythops/impala"
                  "bluetui:pythops/bluetui" "systemctl-tui:rgwood/systemctl-tui" )
    local p id repo
    for p in "${pairs[@]}"; do
        id="${p%%:*}"; repo="${p#*:}"
        command -v "$id" &>/dev/null && { log_skip "$id (present)"; RESULT_SKIPPED+=("$id"); continue; }
        command -v eget &>/dev/null || { log_warning "$id (needs eget)"; RESULT_FAILED+=("$id"); continue; }
        _run eget "$repo" --to "$HOME/.local/bin/$id" \
            && { log_success "$id (eget)"; RESULT_INSTALLED+=("$id"); } \
            || { log_warning "$id (eget failed)"; RESULT_FAILED+=("$id"); }
    done
}

toolchain_run
