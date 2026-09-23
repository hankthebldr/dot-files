#!/usr/bin/env bash
################################################################################
# specs.sh — copy-pasteable system specs (`claw specs`).
#
# Static hardware/OS facts ONLY — the stuff you paste into a bug report, ticket,
# Slack thread, or Obsidian note to describe a machine. Deliberately omits
# transient status (uptime, load, battery, date) and network identifiers
# (IP, Wi-Fi SSID) — those are `claw doctor`/`situation` territory and leaking
# them into a paste is bad OPSEC.
#
# Data comes from ONE `ff-readout.sh fields` call (the single system-readout
# source), plus GPU + arch that the startup path intentionally skips for speed
# but which matter for an on-demand specs dump.
#
# The rendered block is pure (no ANSI); the decorative header prints to stderr,
# so `claw specs | pbcopy` and `claw specs --copy` capture only the clean block.
#
# Usage:
#   specs.sh              markdown table (default)
#   specs.sh --plain      aligned key: value (monospace-friendly)
#   specs.sh --json       machine-readable object
#   specs.sh --copy       also copy the rendered block to the clipboard
#   specs.sh --help
################################################################################
set -uo pipefail

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
FFR="$DOTFILES/scripts/utils/ff-readout.sh"
is_mac() { [[ "$(uname -s)" == "Darwin" ]]; }

# ── Palette (header only; the copyable block is never colored) ───────────────
# shellcheck source=/dev/null
[[ -r "$DOTFILES/scripts/utils/theme.sh" ]] && . "$DOTFILES/scripts/utils/theme.sh" 2>/dev/null
_c() { printf '\033[38;2;%sm' "$1"; }
C_PURPLE="$(_c "${CLAW_RGB_PURPLE:-188;140;255}")"
C_GREEN="$(_c "${CLAW_RGB_GREEN:-63;185;80}")"
C_MUTED="$(_c "${CLAW_RGB_MUTED:-139;148;158}")"
C_BOLD=$'\033[1m'; C_RST=$'\033[0m'

# ── Args ─────────────────────────────────────────────────────────────────────
fmt="md"; copy=0
for a in "$@"; do
    case "$a" in
        --plain|-p)  fmt="plain" ;;
        --json|-j)   fmt="json" ;;
        --md|--markdown) fmt="md" ;;
        --copy|-c)   copy=1 ;;
        --help|-h)
            sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) printf 'specs: unknown option: %s (try --help)\n' "$a" >&2; exit 2 ;;
    esac
done

# ── Gather: one ff-readout call, then pull fields out of the captured dump ───
# (No associative array — macOS ships bash 3.2, which lacks `declare -A`.)
FIELDS=""
[[ -r "$FFR" ]] && FIELDS="$(DOTFILES_DIR="$DOTFILES" bash "$FFR" fields 2>/dev/null)"
f() {  # f <key> → value for that key= line (strips only the first `key=`)
    printf '%s\n' "$FIELDS" | awk -v k="$1" 'index($0,k"=")==1{sub(/^[^=]*=/,"");print;exit}'
}

# GPU + arch — on-demand (slow system_profiler / lspci is fine here).
_gpu() {
    if is_mac; then
        system_profiler SPDisplaysDataType 2>/dev/null \
            | awk -F': ' '/Chipset Model/{gsub(/^ +/,"",$2); print $2; exit}'
    elif command -v lspci &>/dev/null; then
        lspci 2>/dev/null | grep -iE 'vga|3d controller|display' \
            | sed -E 's/.*(VGA compatible controller|3D controller|Display controller): //' \
            | paste -sd '; ' -
    elif command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | paste -sd '; ' -
    fi
}

# Disk: ff-readout gives "used / total"; specs wants capacity → keep the total.
_disk_total="$(f disk)"
[[ "$_disk_total" == */* ]] && _disk_total="${_disk_total##*/ }"
_host="$(f host)"

# ── Ordered rows: "Label|value" (empty/na values still render as n/a) ────────
ROWS=(
    "OS|$(f os)"
    "Host|$_host"
    "Arch|$(uname -m)"
    "Kernel|$(f kernel)"
    "CPU|$(f cpu)"
    "Cores|$(f cores)"
    "GPU|$(_gpu)"
    "Memory|$(f mem)"
    "Disk|$_disk_total"
    "Shell|$(f shell)"
)

# Normalize blanks to n/a.
for i in "${!ROWS[@]}"; do
    lbl="${ROWS[$i]%%|*}"; val="${ROWS[$i]#*|}"
    [[ -z "$val" ]] && ROWS[i]="$lbl|n/a"
done

# ── Renderers → OUT ──────────────────────────────────────────────────────────
render_md() {
    printf '### System specs\n\n'
    printf '| Spec | Value |\n| --- | --- |\n'
    local lbl val
    for r in "${ROWS[@]}"; do lbl="${r%%|*}"; val="${r#*|}"; printf '| %s | %s |\n' "$lbl" "$val"; done
}

render_plain() {
    local lbl w=0
    for r in "${ROWS[@]}"; do lbl="${r%%|*}"; (( ${#lbl} > w )) && w=${#lbl}; done
    local val
    for r in "${ROWS[@]}"; do lbl="${r%%|*}"; val="${r#*|}"; printf '%-*s  %s\n' "$w" "$lbl" "$val"; done
}

render_json() {
    # Minimal escaping (values are plain strings — escape " and \).
    printf '{\n'
    local n=${#ROWS[@]} i=0 lbl val key
    for r in "${ROWS[@]}"; do
        lbl="${r%%|*}"; val="${r#*|}"
        key="$(printf '%s' "$lbl" | tr '[:upper:] ' '[:lower:]_')"
        val="${val//\\/\\\\}"; val="${val//\"/\\\"}"
        i=$((i+1))
        printf '  "%s": "%s"%s\n' "$key" "$val" "$([[ $i -lt $n ]] && echo ,)"
    done
    printf '}\n'
}

case "$fmt" in
    md)    OUT="$(render_md)" ;;
    plain) OUT="$(render_plain)" ;;
    json)  OUT="$(render_json)" ;;
esac

# ── Emit: header → stderr (stays out of a pipe/copy), block → stdout ─────────
printf '\n  %s%s system specs%s  %s· %s%s\n\n' \
    "$C_BOLD" "$C_PURPLE" "$C_RST" "$C_MUTED" "${_host:-$(uname -n)}" "$C_RST" >&2
printf '%s\n' "$OUT"

# ── Clipboard (--copy) ───────────────────────────────────────────────────────
if [[ "$copy" == 1 ]]; then
    _clip() {
        if is_mac && command -v pbcopy &>/dev/null; then pbcopy
        elif command -v xclip &>/dev/null; then xclip -selection clipboard
        elif command -v xsel  &>/dev/null; then xsel --clipboard --input
        elif command -v wl-copy &>/dev/null; then wl-copy
        else return 1; fi
    }
    if printf '%s\n' "$OUT" | _clip 2>/dev/null; then
        printf '\n  %s✓%s copied to clipboard\n\n' "$C_GREEN" "$C_RST" >&2
    else
        printf '\n  %s!%s no clipboard tool found (install xclip / xsel / wl-clipboard)\n\n' "$C_MUTED" "$C_RST" >&2
    fi
fi
