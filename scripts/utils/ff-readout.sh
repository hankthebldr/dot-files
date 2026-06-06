#!/usr/bin/env bash
# ff-readout.sh — compact TWO-COLUMN system readout for the fastfetch startup
# dashboard. Printed by a single `command` module in config.jsonc, so it renders
# to the right of the Apple/distro logo. Cross-platform (macOS + Linux), every
# field independently guarded so a missing tool just shows "n/a".
#
# Layout (fits ~120x30):
#    OS        …      CPU     …
#    Host      …      Cores   …
#    Kernel    …      Memory  …
#    Uptime    …      Disk    …
#    Shell     …      IP      …
#    Terminal  …      Date    …

set -u
is_mac() { [[ "$(uname -s)" == "Darwin" ]]; }

# ── GitHub-dark palette + Nerd Font glyphs ───────────────────────────────────
KEY=$'\033[38;2;88;166;255m'    # blue labels
VAL=$'\033[38;2;201;209;217m'   # light values
DIM=$'\033[38;2;139;148;158m'
RST=$'\033[0m'
I_OS=$''; I_HOST=$''; I_KERN=$''; I_UP=$''
I_SH=$''; I_TERM=$''; I_CPU=$''; I_CORE=$''
I_MEM=$''; I_DISK=$''; I_IP=$''; I_DATE=$''

g() {  # g <field> → value (best-effort, fast, never errors)
  case "$1" in
    os)     if is_mac; then echo "macOS $(sw_vers -productVersion 2>/dev/null)"
            else . /etc/os-release 2>/dev/null; echo "${NAME:-Linux} ${VERSION_ID:-}"; fi ;;
    host)   if is_mac; then sysctl -n hw.model 2>/dev/null
            else cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || uname -n; fi ;;
    kernel) uname -sr ;;
    uptime) local s now b
            if is_mac; then b=$(sysctl -n kern.boottime 2>/dev/null | sed -E 's/.*sec = ([0-9]+).*/\1/'); now=$(date +%s); s=$(( now - ${b:-now} ))
            else s=$(cut -d. -f1 /proc/uptime 2>/dev/null); fi
            s=${s:-0}; printf '%dd %dh %dm' $((s/86400)) $((s%86400/3600)) $((s%3600/60)) ;;
    shell)  echo "${SHELL##*/} $(zsh --version 2>/dev/null | awk '{print $2}')" ;;
    term)   echo "${TERM_PROGRAM:-${TERM:-tty}}" ;;
    cpu)    if is_mac; then sysctl -n machdep.cpu.brand_string 2>/dev/null
            else awk -F: '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//'; fi ;;
    cores)  if is_mac; then sysctl -n hw.ncpu 2>/dev/null; else nproc 2>/dev/null; fi ;;
    mem)    if is_mac; then echo "$(( $(sysctl -n hw.memsize 2>/dev/null) / 1073741824 )) GiB"
            else awk '/MemTotal/{printf "%.0f GiB", $2/1048576}' /proc/meminfo 2>/dev/null; fi ;;
    disk)   df -H / 2>/dev/null | awk 'NR==2{print $3" / "$2}' ;;
    ip)     if is_mac; then ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null
            else hostname -I 2>/dev/null | awk '{print $1}'; fi ;;
    date)   date '+%a %b %d  %H:%M' ;;
  esac
}

# row <licon> <llabel> <lfield>   <ricon> <rlabel> <rfield>
row() {
  local lv rv; lv=$(g "$3"); rv=$(g "$6"); : "${lv:=n/a}" "${rv:=n/a}"
  printf "  ${KEY}%s %-8s${RST}${VAL}%-20.20s${RST}  ${KEY}%s %-7s${RST}${VAL}%.22s${RST}\n" \
         "$1" "$2" "$lv" "$4" "$5" "$rv"
}

# Each row is addressable so config.jsonc can render it as its own one-line
# `command` module (no reliance on multi-line module output). No arg → all rows.
case "${1:-all}" in
  r1) row "$I_OS"   "OS"     os      "$I_CPU"  "CPU"   cpu ;;
  r2) row "$I_HOST" "Host"   host    "$I_CORE" "Cores" cores ;;
  r3) row "$I_KERN" "Kernel" kernel  "$I_MEM"  "Mem"   mem ;;
  r4) row "$I_UP"   "Uptime" uptime  "$I_DISK" "Disk"  disk ;;
  r5) row "$I_SH"   "Shell"  shell   "$I_IP"   "IP"    ip ;;
  r6) row "$I_TERM" "Term"   term    "$I_DATE" "Date"  date ;;
  all)
    row "$I_OS"   "OS"     os      "$I_CPU"  "CPU"   cpu
    row "$I_HOST" "Host"   host    "$I_CORE" "Cores" cores
    row "$I_KERN" "Kernel" kernel  "$I_MEM"  "Mem"   mem
    row "$I_UP"   "Uptime" uptime  "$I_DISK" "Disk"  disk
    row "$I_SH"   "Shell"  shell   "$I_IP"   "IP"    ip
    row "$I_TERM" "Term"   term    "$I_DATE" "Date"  date ;;
esac
