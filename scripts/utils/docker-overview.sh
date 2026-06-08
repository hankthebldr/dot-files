#!/usr/bin/env bash
################################################################################
# docker-overview.sh — at-a-glance view of every Docker container, grouped by
# compose project, with state, published host ports, and live CPU/MEM.
#
# `claw docker` → this. Read-only summary. For interaction use:
#   lzd                          lazydocker TUI (logs / exec / graphs)
#   ctop                         live per-container metrics (top-like)
#   claw ai-services up portainer  Portainer web UI (:9443)
#
# Usage: docker-overview.sh [-a]    (-a / --all also shows stopped containers)
################################################################################
set -uo pipefail

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
[[ -r "$DOTFILES/scripts/utils/theme.sh" ]] && source "$DOTFILES/scripts/utils/theme.sh" 2>/dev/null || true
_c() { printf '\033[38;2;%sm' "$1"; }
C_BLUE="$(_c "${CLAW_RGB_BLUE:-125;174;163}")"; C_GREEN="$(_c "${CLAW_RGB_GREEN:-169;182;101}")"
C_RED="$(_c "${CLAW_RGB_RED:-234;105;98}")";    C_AMBER="$(_c "${CLAW_RGB_AMBER:-216;166;87}")"
C_MUTED="$(_c "${CLAW_RGB_MUTED:-146;131;116}")"; C_PURPLE="$(_c "${CLAW_RGB_PURPLE:-211;134;155}")"
C_BOLD=$'\033[1m'; C_RST=$'\033[0m'

command -v docker &>/dev/null || { printf '  %sdocker not installed%s\n' "$C_RED" "$C_RST" >&2; exit 1; }
docker info &>/dev/null || { printf '  %sdocker daemon not reachable%s\n' "$C_RED" "$C_RST" >&2; exit 1; }

PS_FLAGS=(); [[ "${1:-}" == "-a" || "${1:-}" == "--all" ]] && PS_FLAGS=(-a)

# Snapshot live CPU/MEM once (running containers only) into a name→"cpu|mem" map.
declare -A STAT
while IFS=$'\t' read -r _n _cpu _mem; do
    [[ -n "$_n" ]] && STAT["$_n"]="$_cpu|$_mem"
done < <(docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' 2>/dev/null)

# Collect containers: project \t name \t state \t status \t ports
mapfile -t ROWS < <(docker ps "${PS_FLAGS[@]}" \
    --format '{{.Label "com.docker.compose.project"}}'$'\t''{{.Names}}'$'\t''{{.State}}'$'\t''{{.Status}}'$'\t''{{.Ports}}' \
    2>/dev/null | sort)

[[ ${#ROWS[@]} -gt 0 ]] || { printf '\n  %sno containers%s (try -a for stopped)\n\n' "$C_MUTED" "$C_RST"; exit 0; }

# Pull just the published host ports out of docker's verbose ports string.
_hostports() {
    printf '%s' "$1" | grep -oE '(0\.0\.0\.0|\[::\]|127\.0\.0\.1):[0-9]+' \
        | grep -oE '[0-9]+$' | sort -un | paste -sd, - 2>/dev/null
}

printf '\n  %s%sDocker — %d container(s)%s\n' "$C_BOLD" "$C_BLUE" "${#ROWS[@]}" "$C_RST"

cur_proj=""; total_running=0
for row in "${ROWS[@]}"; do
    IFS=$'\t' read -r proj name state status ports <<<"$row"
    [[ -z "$proj" ]] && proj="(standalone)"
    if [[ "$proj" != "$cur_proj" ]]; then
        printf '\n  %s%s▸ %s%s\n' "$C_BOLD" "$C_PURPLE" "$proj" "$C_RST"
        cur_proj="$proj"
    fi
    # State dot.
    local_dot="$C_MUTED●$C_RST"
    case "$state" in
        running) local_dot="$C_GREEN●$C_RST"; ((total_running++)) ;;
        restarting|paused) local_dot="$C_AMBER●$C_RST" ;;
        exited|dead) local_dot="$C_RED●$C_RST" ;;
    esac
    # Ports + stats.
    hp="$(_hostports "$ports")"; [[ -n "$hp" ]] && hp=":$hp" || hp=""
    cpu=""; mem=""
    if [[ -n "${STAT[$name]:-}" ]]; then cpu="${STAT[$name]%%|*}"; mem="${STAT[$name]##*|}"; fi
    printf '    %b %-26s %s%-22s%s' "$local_dot" "$name" "$C_MUTED" "${status:0:22}" "$C_RST"
    [[ -n "$hp" ]]  && printf ' %s%s%s'  "$C_BLUE"  "$hp"  "$C_RST"
    [[ -n "$cpu" ]] && printf ' %s%s %s%s' "$C_AMBER" "$cpu" "${mem%% *}" "$C_RST"
    printf '\n'
done

printf '\n  %s%d running%s · %slzd%s tui · %sctop%s metrics · %sclaw ai-services up portainer%s web\n\n' \
    "$C_GREEN" "$total_running" "$C_RST" "$C_MUTED" "$C_RST" "$C_MUTED" "$C_RST" "$C_MUTED" "$C_RST"
