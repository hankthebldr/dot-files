#!/usr/bin/env bash
################################################################################
# ai-services.sh — unified manager for self-hosted AI web stacks.
#
# One front-end (`claw ai-services …`) over a handful of Docker Compose stacks
# that don't share an install shape:
#
#   open-webui   local compose   :3000   ChatGPT-style UI for Ollama
#   langfuse     local compose   :3001   LLM observability / tracing
#   dify         upstream clone   :8080   LLM app-builder platform
#   ragflow      upstream clone   :8081   RAG engine w/ deep-doc parsing (GPU)
#
#   • local    — compose file shipped in the repo at config/<svc>/.
#   • upstream — shallow git clone of the project's repo into the per-machine
#                data dir; we run THEIR compose (version-coupled to their images)
#                and layer non-destructive port/GPU overrides on top so a later
#                `git pull` in the clone stays clean.
#
# Clones + volumes live under $XDG_DATA_HOME/claw/ai-services (NOT in the repo).
# Each stack runs under a `claw-<svc>` compose project so containers are
# namespaced and never collide with hand-started ones.
#
# Usage:
#   ai-services.sh list                 # registry + status table
#   ai-services.sh status [svc...]      # running/stopped + reachability
#   ai-services.sh up [svc...]          # prepare + docker compose up -d
#   ai-services.sh down [svc...]        # docker compose down
#   ai-services.sh restart [svc...]
#   ai-services.sh pull [svc...]        # docker compose pull (refresh images)
#   ai-services.sh logs <svc>           # follow logs
#   ai-services.sh prepare <svc>        # clone/seed only, don't start
#   ai-services.sh url <svc>            # print the local URL
#
# With no svc args, up/down/status/pull act on ALL registered services.
################################################################################

set -uo pipefail

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/claw/ai-services"
mkdir -p "$DATA_HOME"

# ── Palette (follow the active claw theme if available, else GitHub-dark) ─────
if [[ -r "$DOTFILES/scripts/utils/theme.sh" ]]; then
    # shellcheck disable=SC1091
    source "$DOTFILES/scripts/utils/theme.sh" 2>/dev/null || true
fi
_c() { printf '\033[38;2;%sm' "$1"; }
C_BLUE="$(_c "${CLAW_RGB_BLUE:-88;166;255}")"
C_GREEN="$(_c "${CLAW_RGB_GREEN:-63;185;80}")"
C_RED="$(_c "${CLAW_RGB_RED:-255;123;114}")"
C_AMBER="$(_c "${CLAW_RGB_AMBER:-227;179;65}")"
C_MUTED="$(_c "${CLAW_RGB_MUTED:-139;148;158}")"
C_BOLD=$'\033[1m'; C_RST=$'\033[0m'

info()  { printf '  %s•%s %s\n' "$C_BLUE"  "$C_RST" "$*"; }
ok()    { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RST" "$*"; }
warn()  { printf '  %s!%s %s\n' "$C_AMBER" "$C_RST" "$*"; }
die()   { printf '  %s✗%s %s\n' "$C_RED"   "$C_RST" "$*" >&2; exit 1; }

# ── Registry ─────────────────────────────────────────────────────────────────
# name|kind|port|description|spec
#   local    spec = absolute path to the compose file in the repo
#   upstream spec = <git-url>::<subdir>::<compose-file>
SERVICES=(
  "litellm|local|4000|Unified LLM gateway (ollama+vLLM+llama-swap+cloud)|$DOTFILES/config/litellm/docker-compose.yml"
  "open-webui|local|3000|ChatGPT-style UI for Ollama|$DOTFILES/config/open-webui/docker-compose.yml"
  "langfuse|local|3001|LLM observability / tracing|$DOTFILES/config/langfuse/docker-compose.yml"
  "portainer|local|9443|Docker management web UI|$DOTFILES/config/portainer/docker-compose.yml"
  "caddy|local|80|Reverse proxy (containers.local → portainer)|$DOTFILES/config/caddy/docker-compose.yml"
  "dify|upstream|8080|LLM app-builder platform|https://github.com/langgenius/dify::docker::docker-compose.yaml"
  "ragflow|upstream|8081|RAG engine + deep-doc parsing|https://github.com/infiniflow/ragflow::docker::docker-compose.yml"
)

_row() { local n="$1"; local r; for r in "${SERVICES[@]}"; do [[ "${r%%|*}" == "$n" ]] && { printf '%s\n' "$r"; return 0; }; done; return 1; }
_field() { _row "$1" | awk -F'|' -v i="$2" '{print $i}'; }
_all_names() { local r; for r in "${SERVICES[@]}"; do printf '%s\n' "${r%%|*}"; done; }

_have_gpu() { command -v nvidia-smi &>/dev/null && nvidia-smi -L 2>/dev/null | grep -q 'GPU'; }

# Upsert KEY=VALUE in an env file (append if missing, replace in place if present).
_set_env() {
    local file="$1" key="$2" val="$3"
    touch "$file"
    if grep -qE "^${key}=" "$file" 2>/dev/null; then
        sed -i.bak "s|^${key}=.*|${key}=${val}|" "$file" && rm -f "$file.bak"
    else
        printf '%s=%s\n' "$key" "$val" >> "$file"
    fi
}

# Echo the compose dir and the -f flags for a service; clones/seeds upstreams.
# Sets globals: SVC_DIR, SVC_FLAGS (array).
_resolve() {
    local name="$1" prepare="${2:-0}"
    local kind spec; kind="$(_field "$name" 2)"; spec="$(_field "$name" 5)"
    [[ -n "$kind" ]] || die "unknown service: $name  (try: ai-services list)"
    SVC_FLAGS=()
    if [[ "$kind" == "local" ]]; then
        [[ -f "$spec" ]] || die "$name: compose file missing — $spec"
        SVC_DIR="$(dirname "$spec")"
        SVC_FLAGS=(-f "$spec")
        return 0
    fi

    # upstream
    local url subdir cfile
    url="${spec%%::*}"; spec="${spec#*::}"
    subdir="${spec%%::*}"; cfile="${spec#*::}"
    local clone="$DATA_HOME/$name"

    if [[ ! -d "$clone/.git" ]]; then
        [[ "$prepare" == 1 ]] || die "$name not prepared — run: claw ai-services prepare $name"
        info "cloning $name → $clone"
        git clone --depth 1 "$url" "$clone" >/dev/null 2>&1 || die "git clone failed for $name"
        ok "cloned $name"
    fi

    SVC_DIR="$clone/$subdir"
    [[ -d "$SVC_DIR" ]] || die "$name: expected subdir '$subdir' not found in clone"
    [[ -f "$SVC_DIR/$cfile" ]] || die "$name: compose file '$cfile' not found in $SVC_DIR"
    SVC_FLAGS=(-f "$cfile")

    # Seed .env from the upstream example on first prepare.
    if [[ "$prepare" == 1 && -f "$SVC_DIR/.env.example" && ! -f "$SVC_DIR/.env" ]]; then
        cp "$SVC_DIR/.env.example" "$SVC_DIR/.env"
        info "$name: seeded .env from .env.example"
    fi

    # Per-service tweaks.
    case "$name" in
        dify)
            if [[ "$prepare" == 1 ]]; then
                _set_env "$SVC_DIR/.env" EXPOSE_NGINX_PORT 8080
                _set_env "$SVC_DIR/.env" EXPOSE_NGINX_SSL_PORT 8443
                ok "dify: UI pinned to :8080 (EXPOSE_NGINX_PORT)"
            fi
            ;;
        ragflow)
            # RagFlow parameterizes its UI host port via .env (SVR_WEB_HTTP_PORT),
            # and selects the ragflow-cpu / ragflow-gpu service through the DEVICE
            # profile (COMPOSE_PROFILES=${DOC_ENGINE},${DEVICE}). No compose
            # override needed — just drive the env.
            if [[ "$prepare" == 1 ]]; then
                _set_env "$SVC_DIR/.env" SVR_WEB_HTTP_PORT 8081
                _set_env "$SVC_DIR/.env" SVR_WEB_HTTPS_PORT 8444  # 8443 is Dify's
                ok "ragflow: UI pinned to :8081 (SVR_WEB_HTTP_PORT)"
                if _have_gpu; then
                    _set_env "$SVC_DIR/.env" DEVICE gpu
                    ok "ragflow: GPU acceleration enabled (DEVICE=gpu)"
                else
                    _set_env "$SVC_DIR/.env" DEVICE cpu
                    info "ragflow: no GPU detected — CPU mode"
                fi
            fi
            ;;
    esac
    return 0
}

# docker compose for a resolved service, namespaced under claw-<name>.
_compose() {
    local name="$1"; shift
    ( cd "$SVC_DIR" && docker compose -p "claw-$name" "${SVC_FLAGS[@]}" "$@" )
}

_port_up() { local p="$1"; { exec 3<>"/dev/tcp/127.0.0.1/$p"; } 2>/dev/null && { exec 3>&-; return 0; }; return 1; }
_scheme() { case "$1" in 9443|8443|443) printf 'https' ;; *) printf 'http' ;; esac; }

# ── Commands ─────────────────────────────────────────────────────────────────
cmd_list() {
    printf '\n  %s%sOpen Claw — AI services%s\n\n' "$C_BOLD" "$C_BLUE" "$C_RST"
    printf '  %-12s %-10s %-7s %s\n' "SERVICE" "KIND" "PORT" "DESCRIPTION"
    printf '  %s%s%s\n' "$C_MUTED" "──────────────────────────────────────────────────────────────" "$C_RST"
    local r n k p d
    for r in "${SERVICES[@]}"; do
        IFS='|' read -r n k p d _ <<<"$r"
        local dot="$C_MUTED●$C_RST"
        _port_up "$p" && dot="$C_GREEN●$C_RST"
        printf '  %b %-10s %-10s %-7s %s%s%s\n' "$dot" "$n" "$k" ":$p" "$C_MUTED" "$d" "$C_RST"
    done
    printf '\n  %sup:%s claw ai-services up [svc]   %surl:%s claw ai-services url <svc>\n\n' \
        "$C_MUTED" "$C_RST" "$C_MUTED" "$C_RST"
}

cmd_status() {
    local names; names=("$@"); [[ ${#names[@]} -eq 0 ]] && mapfile -t names < <(_all_names)
    local n
    for n in "${names[@]}"; do
        local port; port="$(_field "$n" 3)"
        local kind; kind="$(_field "$n" 2)"
        [[ -n "$kind" ]] || { warn "unknown: $n"; continue; }
        # Container count is the source of truth for "is THIS stack up" — more
        # reliable than a bare port probe (a stack can be mid-restart). Each
        # stack now has a distinct host port, but only this stack's own claw-<n>
        # compose project counts here.
        local running=0
        if [[ "$kind" == "local" || -d "$DATA_HOME/$n/.git" ]]; then
            _resolve "$n" 0 2>/dev/null && running="$(_compose "$n" ps -q 2>/dev/null | grep -c .)" || running=0
        fi
        if [[ "$running" -gt 0 ]]; then
            if _port_up "$port"; then
                ok "$(printf '%-11s' "$n") ${C_MUTED}reachable → $(_scheme "$port")://localhost:$port  (${running} container(s))${C_RST}"
            else
                warn "$(printf '%-11s' "$n") ${C_MUTED}${running} container(s) up, port $port not answering yet${C_RST}"
            fi
        elif [[ "$kind" == "upstream" && ! -d "$DATA_HOME/$n/.git" ]]; then
            printf '  %s·%s %-11s %snot prepared (claw ai-services up %s)%s\n' "$C_MUTED" "$C_RST" "$n" "$C_MUTED" "$n" "$C_RST"
        elif _port_up "$port"; then
            # Not our containers, but the port answers → another stack owns it.
            printf '  %s·%s %-11s %sstopped (port %s busy — another stack)%s\n' "$C_MUTED" "$C_RST" "$n" "$C_MUTED" "$port" "$C_RST"
        else
            printf '  %s·%s %-11s %sstopped%s\n' "$C_MUTED" "$C_RST" "$n" "$C_MUTED" "$C_RST"
        fi
    done
}

cmd_up() {
    local names; names=("$@"); [[ ${#names[@]} -eq 0 ]] && mapfile -t names < <(_all_names)
    command -v docker &>/dev/null || die "docker not installed"
    docker info &>/dev/null || die "docker daemon not reachable (is it running / are you in the docker group?)"
    local n
    for n in "${names[@]}"; do
        printf '\n  %s%s▸ %s%s\n' "$C_BOLD" "$C_BLUE" "$n" "$C_RST"
        _resolve "$n" 1
        info "pulling images (first run can take several minutes)…"
        _compose "$n" pull 2>&1 | tail -3 || warn "$n: pull reported issues (continuing)"
        info "starting…"
        if _compose "$n" up -d; then
            ok "$n up → $(_scheme "$(_field "$n" 3)")://localhost:$(_field "$n" 3)"
        else
            warn "$n: compose up reported errors — check: claw ai-services logs $n"
        fi
    done
    printf '\n'
}

cmd_down() {
    local names; names=("$@"); [[ ${#names[@]} -eq 0 ]] && mapfile -t names < <(_all_names)
    local n
    for n in "${names[@]}"; do
        if [[ "$(_field "$n" 2)" == "upstream" && ! -d "$DATA_HOME/$n/.git" ]]; then
            info "$n not prepared — nothing to stop"; continue
        fi
        _resolve "$n" 0 2>/dev/null || { warn "$n: cannot resolve — skipping"; continue; }
        info "stopping $n…"
        _compose "$n" down && ok "$n stopped" || warn "$n: down reported errors"
    done
}

cmd_restart() { cmd_down "$@"; cmd_up "$@"; }

cmd_pull() {
    local names; names=("$@"); [[ ${#names[@]} -eq 0 ]] && mapfile -t names < <(_all_names)
    local n
    for n in "${names[@]}"; do
        _resolve "$n" 1 || continue
        info "pulling $n images…"; _compose "$n" pull && ok "$n images refreshed"
    done
}

cmd_logs() {
    local n="${1:-}"; [[ -n "$n" ]] || die "usage: ai-services logs <svc>"
    _resolve "$n" 0; _compose "$n" logs -f --tail=100
}

cmd_prepare() {
    local n="${1:-}"; [[ -n "$n" ]] || die "usage: ai-services prepare <svc>"
    _resolve "$n" 1; ok "$n prepared (start with: claw ai-services up $n)"
}

cmd_url() {
    local n="${1:-}"; [[ -n "$n" ]] || die "usage: ai-services url <svc>"
    local p; p="$(_field "$n" 3)"; [[ -n "$p" ]] || die "unknown service: $n"
    printf '%s://localhost:%s\n' "$(_scheme "$p")" "$p"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
sub="${1:-list}"; shift 2>/dev/null || true
case "$sub" in
    list|ls)        cmd_list ;;
    status|st)      cmd_status "$@" ;;
    up|start)       cmd_up "$@" ;;
    down|stop)      cmd_down "$@" ;;
    restart)        cmd_restart "$@" ;;
    pull|update)    cmd_pull "$@" ;;
    logs|log)       cmd_logs "$@" ;;
    prepare|prep)   cmd_prepare "$@" ;;
    url|open)       cmd_url "$@" ;;
    *) die "unknown command: $sub  (list|status|up|down|restart|pull|logs|prepare|url)" ;;
esac
