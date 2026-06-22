#!/usr/bin/env bash
################################################################################
# Research Toolchain — Cross-Platform
#
# OSINT-adjacent data wrangling: HTTP clients, text processors, web scrapers,
# NLP tooling, reference tools. Many entries are Python (pipx) since most of
# the scraping/NLP stack ships on PyPI rather than system pkg managers.
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toolchain-runner.sh"

TOOLCHAIN_TITLE="RESEARCH  TOOLCHAIN"
TOOLCHAIN_CLASS="DATA-DJ  LOADOUT"
TOOLCHAIN_TAG="scraped the entire internet last weekend · now organizing it by vibe"

# ── TOOL MAPPING ───────────────────────────────────────────────────────────
TOOLCHAIN_MAP=(
    # ── 01. HTTP / Network ─────────────────────────────────────────────────
    "curl|curl|curl|none|HTTP client"
    "wget|wget|wget|none|recursive downloader"
    "http|httpie|httpie|pipx|human-friendly HTTP client"
    "aria2c|aria2|aria2|none|multi-connection downloader"

    # ── 02. Text Processing ────────────────────────────────────────────────
    "rg|ripgrep|ripgrep|cargo|fast grep replacement"
    "awk|awk|gawk|none|brew has bsd awk; apt has gnu awk"
    "gsed|gnu-sed|sed|none|GNU sed (linux sed is already GNU)"
    "jq|jq|jq|none|JSON swiss army knife"
    "csvsql|csvkit|?|pipx|csvkit — pipx since it's python"

    # ── 03. Web Scraping ───────────────────────────────────────────────────
    "pup|pup|?|go:github.com/ericchiang/pup|HTML parser for CLI"
    "htmlq|htmlq|?|cargo|HTML jq equivalent"
    "yt-dlp|yt-dlp|yt-dlp|pipx|video/audio scraper"
    "scrapy|?|python3-scrapy|pipx|web scraping framework"

    # ── 04. NLP / Data ─────────────────────────────────────────────────────
    "wordfreq|?|?|pipx|word frequency lib"
    "textract|?|?|pipx|extract text from many formats"
    "polyglot|?|?|pipx|multilingual NLP (has C deps — may need libicu-dev)"

    # ── 05. Docs / Reference ───────────────────────────────────────────────
    "tldr|tldr|tldr|cargo:tealdeer|fast tldr in Rust"
    "pandoc|pandoc|pandoc|none|universal doc converter"
    "fzf|fzf|fzf|none|fuzzy finder"
    "clin|?|?|cargo:clin-rs|Obsidian-style note TUI (clin plugin)"
)

declare -A TOOLCHAIN_SECTIONS=(
    [0]="01|HTTP  /  Network"
    [4]="02|Text  Processing"
    [9]="03|Web  Scraping"
    [13]="04|NLP  /  Data"
    [16]="05|Docs  /  Reference"
)

# ── Pre-install hook: ensure pipx is installed (heavy pipx use) ───────────
toolchain_preflight_extras() {
    if ! command -v pipx &>/dev/null; then
        log_info "research toolchain leans heavily on pipx — installing it first"
        case "$PKG_MANAGER" in
            brew) brew install pipx && pipx ensurepath ;;
            apt)
                sudo apt-get install -y pipx 2>/dev/null \
                    || python3 -m pip install --user pipx
                command -v pipx &>/dev/null && pipx ensurepath
                ;;
            *) python3 -m pip install --user pipx ;;
        esac
    fi
}

toolchain_run
