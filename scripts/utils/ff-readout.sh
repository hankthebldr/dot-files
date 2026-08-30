#!/usr/bin/env bash
# ff-readout.sh — TWO-COLUMN system readout for the fastfetch startup dashboard,
# printed beside the system logo. Two fixed columns separated by a vertical rule
# (│) so the right column is justified on a vertical line regardless of the left
# value's length. Cross-platform (macOS + Linux); every field guarded ("n/a").
#
# NOTE: perfect vertical alignment assumes a *Mono* Nerd Font (glyphs = 1 cell),
# e.g. "JetBrainsMono Nerd Font Mono". Each row is its own one-line `command`
# module in config.jsonc, so nothing depends on multi-line module rendering.
#
# Fast fields only — GPU/Display/Brightness/Font/Theme need slow system_profiler
# calls on macOS and are intentionally omitted to keep startup instant.

set -u
is_mac() { [[ "$(uname -s)" == "Darwin" ]]; }

# Extract the SSID from `ipconfig getsummary <iface>` output (read on stdin).
# macOS 14.4+ removed the `airport` CLI and made `networksetup -getairportnetwork`
# always report "not associated" (SSID now needs a Location-Services entitlement
# the CLI lacks), so `ipconfig getsummary` is the reliable modern source. Matches
# the `SSID :` line only — anchored so the `BSSID :` line is never mistaken for it.
_ffr_ssid_from_summary() {
  awk '/^[[:space:]]*SSID[[:space:]]*:/{sub(/^[[:space:]]*SSID[[:space:]]*:[[:space:]]*/,"");print;exit}'
}

# ── Palette: per-type label colors sourced from the active Open Claw theme ───
# theme.sh exports CLAW_RGB_* for the active palette (GitHub-dark fallback keeps
# this script standalone). Labels are colored by type via cf(), mirroring the
# native base_modules() scheme in gen-fastfetch.py, so the readout keeps its
# "cool color by type" look AND follows a `claw theme` switch. (orange = amber.)
_ffr_dots="${DOTFILES_DIR:-$HOME/.dotfiles}"
# shellcheck source=/dev/null
[ -r "$_ffr_dots/scripts/utils/theme.sh" ] && . "$_ffr_dots/scripts/utils/theme.sh" 2>/dev/null
PURPLE=$'\033[38;2;'"${CLAW_RGB_PURPLE:-188;140;255}"'m'
BLUE=$'\033[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"'m'
GREEN=$'\033[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"'m'
ORANGE=$'\033[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"'m'
MUTED=$'\033[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"'m'
VAL=$'\033[38;2;'"${CLAW_RGB_FG:-201;209;217}"'m'      # light values
BAR=$'\033[38;2;'"${CLAW_RGB_DIVIDER:-48;54;61}"'m'    # column divider
RST=$'\033[0m'

cf() {  # cf <field> → ANSI color for that field's label (color-by-type)
  case "$1" in
    os|host|term)                 printf '%s' "$PURPLE" ;;
    kernel|uptime|load|cpu|cores) printf '%s' "$BLUE" ;;
    shell|pkgs|mem|swap|clis)     printf '%s' "$GREEN" ;;
    disk|batt)                    printf '%s' "$ORANGE" ;;
    *)                            printf '%s' "$MUTED" ;;
  esac
}
I_OS=$''; I_HOST=$''; I_KERN=$''; I_UP=$''; I_LOAD=$''
I_SH=$''; I_TERM=$''; I_PKG=$''; I_LOC=$''
I_CPU=$''; I_CORE=$''; I_MEM=$''; I_SWAP=$''; I_DISK=$''
I_IP=$''; I_WIFI=$''; I_BATT=$''; I_DATE=$''
# Local-profile rows reuse existing glyphs (terminal = CLI repos, chip = tools).
I_CLIS="$I_TERM"; I_TOOLS="$I_KERN"

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
    load)   if is_mac; then sysctl -n vm.loadavg 2>/dev/null | awk '{printf "%s %s %s",$2,$3,$4}'
            else cut -d' ' -f1-3 /proc/loadavg 2>/dev/null; fi ;;
    shell)  echo "${SHELL##*/} $(zsh --version 2>/dev/null | awk '{print $2}')" ;;
    term)   echo "${TERM_PROGRAM:-${TERM:-tty}}" ;;
    pkgs)   if is_mac; then echo "$(ls "$(brew --prefix 2>/dev/null)/Cellar" 2>/dev/null | wc -l | tr -d ' ') brew"
            else echo "$(dpkg --get-selections 2>/dev/null | wc -l | tr -d ' ') dpkg"; fi ;;
    locale) echo "${LANG:-${LC_ALL:-n/a}}" ;;
    cpu)    if is_mac; then sysctl -n machdep.cpu.brand_string 2>/dev/null
            else awk -F: '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//'; fi ;;
    cores)  if is_mac; then sysctl -n hw.ncpu 2>/dev/null; else nproc 2>/dev/null; fi ;;
    mem)    if is_mac; then echo "$(( $(sysctl -n hw.memsize 2>/dev/null) / 1073741824 )) GiB"
            else awk '/MemTotal/{printf "%.0f GiB", $2/1048576}' /proc/meminfo 2>/dev/null; fi ;;
    mem_pct) if is_mac; then memory_pressure 2>/dev/null | awk -F: '/free percentage/{gsub(/[ %]/,"",$2); print 100-$2}'
            else free 2>/dev/null | awk '/^Mem:/{a=($7!=""?$7:$4); if($2>0) printf "%d", ($2-a)/$2*100}'; fi ;;
    swap)   if is_mac; then sysctl -n vm.swapusage 2>/dev/null | sed -E 's/.*used = ([0-9.]+[KMG]).*/\1 used/'
            else free -h 2>/dev/null | awk '/Swap/{print $3" / "$2}'; fi ;;
    disk)   df -H / 2>/dev/null | awk 'NR==2{print $3" / "$2}' ;;
    disk_pct) df -H / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}' ;;
    ip)     if is_mac; then ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null
            else hostname -I 2>/dev/null | awk '{print $1}'; fi ;;
    wifi)   if is_mac; then
              # Resolve the Wi-Fi interface (en0 on ~all Macs), read its SSID via
              # ipconfig getsummary, and fall back to link state so an unknown SSID
              # never reads as "offline" while we're actually associated.
              local _w _s
              _w=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{getline;print $2;exit}'); _w=${_w:-en0}
              _s=$(ipconfig getsummary "$_w" 2>/dev/null | _ffr_ssid_from_summary)
              if [ -n "$_s" ]; then echo "$_s"
              elif ifconfig "$_w" 2>/dev/null | grep -q 'status: active'; then echo "connected"
              else echo "offline"; fi
            else iwgetid -r 2>/dev/null; fi ;;
    batt)   if is_mac; then pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1
            else local c; c=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null); [[ -n "$c" ]] && echo "$c%"; fi ;;
    clis)   local d="${LOCAL_CLI_DIR:-$HOME/Github/local-clis}" t=0 s=0 x
            [[ -d "$d" ]] || return
            for x in "$d"/*/; do [[ -d "$x" ]] || continue; t=$((t+1)); [[ -f "${x}.clistartup" ]] && s=$((s+1)); done
            (( t > 0 )) && printf '%d repos · %d load' "$t" "$s" || printf 'none yet' ;;
    tools)  local out='' t
            for t in git make tmux nvim fzf; do command -v "$t" >/dev/null 2>&1 && out="$out $t"; done
            printf '%s' "${out# }" ;;
    date)   date '+%a %b %d  %H:%M' ;;
    updates) # Pending-update glance ("12 pkg · repo ↓3" / "current") rendered
            # by update-status.sh `read` — a pure cache read of updates.json
            # (the welcome-TUI kick refreshes it; this NEVER probes). Guarded:
            # no cache / no jq / no script → empty, so the field drops out.
            # Muted label color via cf()'s default class.
            local uf="${XDG_CACHE_HOME:-$HOME/.cache}/claw/updates.json"
            local us="$_ffr_dots/scripts/utils/update-status.sh"
            command -v jq >/dev/null 2>&1 || return 0
            [[ -r "$uf" && -r "$us" ]] || return 0
            bash "$us" read 2>/dev/null ;;
  esac
}

# row <licon> <llabel> <lfield>   <ricon> <rlabel> <rfield>
# Labels are colored by type (cf). Fields with no data drop out so the dashboard
# adapts per machine: if the RIGHT field is empty the divider + right cell are
# omitted; if BOTH are empty the row prints nothing and fastfetch silently skips
# the module — no "n/a" clutter on headless servers or batteryless desktops.
row() {
  local lv rv lc rc; lv=$(g "$3"); rv=$(g "$6"); lc=$(cf "$3"); rc=$(cf "$6")
  [[ -z "$lv" && -z "$rv" ]] && return
  if [[ -n "$rv" ]]; then
    # left cell padded to a fixed width, then the vertical rule, then the right
    # cell — the rule lands on the same column every row.
    printf "  ${lc}%s %-7s${RST}${VAL}%-18.18s${RST}${BAR}│${RST}  ${rc}%s %-7s${RST}${VAL}%.18s${RST}\n" \
           "$1" "$2" "${lv:-n/a}" "$4" "$5" "$rv"
  else
    printf "  ${lc}%s %-7s${RST}${VAL}%-.18s${RST}\n" "$1" "$2" "${lv:-n/a}"
  fi
}

# pct <resource> → integer 0-100 utilization (fast, best-effort) for the
# btop-style bars in claw-dashboard.py. CPU is load1/ncpu (an instant proxy —
# true instantaneous CPU% needs slow sampling that would defeat instant startup).
pct() {
  case "$1" in
    cpu)  local l n
          if is_mac; then l=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}'); n=$(sysctl -n hw.ncpu 2>/dev/null)
          else l=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null); n=$(nproc 2>/dev/null); fi
          [[ -n "$l" && "${n:-0}" -gt 0 ]] && awk -v l="$l" -v n="$n" 'BEGIN{v=l/n*100; if(v>100)v=100; printf "%d",v+0.5}' ;;
    mem)  if is_mac; then
            local t; t=$(sysctl -n hw.memsize 2>/dev/null)
            vm_stat 2>/dev/null | awk -v t="$t" '
              /page size of/{ps=$8}
              /Pages active/{gsub(/\./,"",$3);a=$3}
              /Pages wired/{gsub(/\./,"",$4);w=$4}
              /occupied by compressor/{gsub(/\./,"",$5);c=$5}
              END{ps=ps?ps:16384; if(t>0)printf "%d",(a+w+c)*ps*100/t+0.5}'
          else
            awk '/MemTotal/{t=$2} /MemAvailable/{m=$2} END{if(t)printf "%d",(t-m)*100/t+0.5}' /proc/meminfo 2>/dev/null
          fi ;;
    swap) if is_mac; then
            sysctl -n vm.swapusage 2>/dev/null \
              | sed -E 's/.*total = ([0-9.]+)M.*used = ([0-9.]+)M.*/\1 \2/' \
              | awk '{if($1>0)printf "%d",$2*100/$1+0.5; else print 0}'
          else
            free 2>/dev/null | awk '/Swap/{if($2>0)printf "%d",$3*100/$2+0.5; else print 0}'
          fi ;;
    disk) df -H / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5);print $5}' ;;
    batt) if is_mac; then pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%'
          else cat /sys/class/power_supply/BAT0/capacity 2>/dev/null; fi ;;
  esac
}

case "${1:-all}" in
  # Machine-readable dump for claw-dashboard.py (one key=value per line),
  # plus <res>_pct utilization values that feed the resource bars.
  fields)
    for _f in os host kernel uptime load shell term pkgs locale cpu cores mem mem_pct swap disk disk_pct ip wifi batt date updates; do
        printf '%s=%s\n' "$_f" "$(g "$_f")"
    done
    for _p in cpu mem swap disk batt; do
        printf '%s_pct=%s\n' "$_p" "$(pct "$_p")"
    done ;;
  field) shift; g "${1:-os}" ;;
  r1) row "$I_OS"   "OS"     os      "$I_CPU"  "CPU"   cpu ;;
  r2) row "$I_HOST" "Host"   host    "$I_CORE" "Cores" cores ;;
  r3) row "$I_KERN" "Kernel" kernel  "$I_MEM"  "Mem"   mem ;;
  r4) row "$I_UP"   "Uptime" uptime  "$I_SWAP" "Swap"  swap ;;
  r5) row "$I_LOAD" "Load"   load    "$I_DISK" "Disk"  disk ;;
  r6) row "$I_SH"   "Shell"  shell   "$I_IP"   "IP"    ip ;;
  r7) row "$I_TERM" "Term"   term    "$I_WIFI" "Wi-Fi" wifi ;;
  r8) row "$I_PKG"  "Pkgs"   pkgs    "$I_BATT" "Batt"  batt ;;
  r9) row "$I_LOC"  "Locale" locale  "$I_DATE" "Date"  date ;;
  # Local profile (config-local.jsonc): compact CLI-dev two-column readout.
  l1) row "$I_OS"   "OS"     os      "$I_UP"    "Up"    uptime ;;
  l2) row "$I_KERN" "Kernel" kernel  "$I_CPU"   "CPU"   cpu ;;
  l3) row "$I_MEM"  "Mem"    mem     "$I_DISK"  "Disk"  disk ;;
  l4) row "$I_IP"   "IP"     ip      "$I_SH"    "Shell" shell ;;
  l5) row "$I_CLIS" "CLIs"   clis    "$I_TOOLS" "Tools" tools ;;
  all)
    for r in r1 r2 r3 r4 r5 r6 r7 r8 r9; do "$0" "$r"; done ;;
esac
