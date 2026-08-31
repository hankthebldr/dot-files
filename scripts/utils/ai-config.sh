#!/usr/bin/env bash
# ai-config.sh — Open Claw "ai-config plugin" engine.
#
# Brings opencode + openwork CONFIG under dot-files: renders each tool's config
# from portable sources (opencode from a tracked base; openwork's workspace roots
# from the Obsidian vault resolver), tops each with a managed-file sentinel, and
# refuses to clobber a hand-edited/app-written config. Mirrors clin.sh; POSIX sh.
#
#   ai-config.sh render <opencode|openwork> [out]   emit one config
#   ai-config.sh sync                               render both live configs (gated)
#   ai-config.sh status                             what's managed + openwork runtime/secret files
#   ai-config.sh setup                              first-run adopt (idempotent, lossless)
#
# Managed-file gate: CLAW_AICONFIG_MANAGED = 1 (default) | force | 0/off/no.
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
AICONFIG_SENTINEL="managed by the Open Claw ai-config plugin"
OC_BASE="$DOTFILES_DIR/config/opencode/opencode.base.jsonc"
OC_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.jsonc"
OW_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/openwork/server.json"
OW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/openwork"
AC_BASE="$DOTFILES_DIR/config/agent-canvas/agent-canvas.llm.json"
AC_CONFIG="$HOME/.openhands/settings.json"

# Resolve the Obsidian vault root (env → known default). No fork needed.
_aic_vault() {
    printf '%s' "${OBSIDIAN_VAULT:-$HOME/${OBSIDIAN_VAULT_NAME:-hr-vault-main-pa}}"
}

# Return 0 if it's safe to (over)write $1 — file absent, already ours (matches
# $2 grep pattern), or force. Else warn and return 1.
_aic_managed_ok() {
    _f="$1"; _pat="$2"
    case "${CLAW_AICONFIG_MANAGED:-1}" in
        0|off|no) return 1 ;;
        force)    return 0 ;;
    esac
    [ -f "$_f" ] || return 0
    grep -q "$_pat" "$_f" 2>/dev/null && return 0
    printf '  ai-config: %s looks hand-edited/app-written — not overwriting.\n' "$_f" >&2
    printf '  ai-config: re-run with CLAW_AICONFIG_MANAGED=force to let claw manage it.\n' >&2
    return 1
}

# --- opencode: base file + line-1 sentinel ---------------------------------
aic_render_opencode() {
    _out="${1:-/dev/stdout}"
    [ -r "$OC_BASE" ] || { printf 'ai-config: missing base %s\n' "$OC_BASE" >&2; return 1; }
    [ "$_out" != "/dev/stdout" ] && mkdir -p "$(dirname "$_out")" 2>/dev/null
    {
        printf '// %s — do not hand-edit (claw ai config sync)\n' "$AICONFIG_SENTINEL"
        cat "$OC_BASE"
    } > "$_out" 2>/dev/null
}

# --- openwork: workspace roots from the vault, seed-and-reconcile ------------
# Emits server.json with a "_claw_managed" sentinel key. Two roots by default:
# the Obsidian vault and ~/OpenWork. Extra workspaces present in $3 (a JSON file
# to preserve) are merged so adopt is lossless.
aic_render_openwork() {
    _out="${1:-/dev/stdout}"; _seed="${2:-}"
    _vault="$(_aic_vault)"; _ow="$HOME/OpenWork"
    [ "$_out" != "/dev/stdout" ] && mkdir -p "$(dirname "$_out")" 2>/dev/null
    VAULT="$_vault" OWROOT="$_ow" SEED="$_seed" python3 - "$_out" <<'PY'
import json, os, sys
out = sys.argv[1]
vault, owroot, seed = os.environ["VAULT"], os.environ["OWROOT"], os.environ.get("SEED", "")
def ws(path, name): return {"id": "ws_" + name, "path": path, "name": name, "preset": "starter", "workspaceType": "local"}
base = [ws(vault, os.path.basename(vault.rstrip("/"))), ws(owroot, "OpenWork")]
paths = {w["path"] for w in base}
# preserve any extra workspaces from the seed file
if seed and os.path.isfile(seed):
    try:
        old = json.load(open(seed))
        for w in old.get("workspaces", []):
            if w.get("path") and w["path"] not in paths:
                base.append(w); paths.add(w["path"])
    except (ValueError, OSError):
        pass
doc = {"_claw_managed": True, "workspaces": base, "authorizedRoots": sorted(paths)}
data = json.dumps(doc, indent=2) + "\n"
if out == "/dev/stdout":
    sys.stdout.write(data)
else:
    open(out, "w").write(data)
PY
}

aic_sync() {
    if _aic_managed_ok "$OC_CONFIG" "$AICONFIG_SENTINEL"; then
        aic_render_opencode "$OC_CONFIG" && printf '  ai-config: synced %s\n' "$OC_CONFIG"
    fi
    if _aic_managed_ok "$OW_CONFIG" '_claw_managed'; then
        aic_render_openwork "$OW_CONFIG" "$OW_CONFIG" && printf '  ai-config: synced %s\n' "$OW_CONFIG"
    fi
    if _aic_managed_ok "$AC_CONFIG" '_claw_managed'; then
        aic_render_agent_canvas "$AC_CONFIG" && printf '  ai-config: synced %s\n' "$AC_CONFIG"
    fi
}

aic_status() {
    printf '\n  ai-config — managed AI tool configs\n'
    _oc_state="unmanaged"; [ -f "$OC_CONFIG" ] && head -1 "$OC_CONFIG" 2>/dev/null | grep -q "$AICONFIG_SENTINEL" && _oc_state="managed"
    _ow_state="unmanaged"; [ -f "$OW_CONFIG" ] && grep -q '_claw_managed' "$OW_CONFIG" 2>/dev/null && _ow_state="managed"
    printf '    opencode  %-10s %s\n' "$_oc_state" "$OC_CONFIG"
    printf '    openwork  %-10s %s\n' "$_ow_state" "$OW_CONFIG"
    _ac_state="unmanaged"; [ -f "$AC_CONFIG" ] && grep -q '_claw_managed' "$AC_CONFIG" 2>/dev/null && _ac_state="managed"
    [ -f "$AC_CONFIG" ] || _ac_state="absent"
    _ac_prof=$(python3 -c "import json;print(json.load(open('$AC_CONFIG')).get('_claw_profile',''))" 2>/dev/null)
    printf '    agent-canvas %-7s %s %s\n' "$_ac_state" "$AC_CONFIG" "${_ac_prof:+[$_ac_prof]}"
    # openwork runtime/secret files — presence only, never values
    for f in runtime-opencode-config.json runtime.sqlite tokens.json; do
        [ -f "$OW_DIR/$f" ] && printf '    · %-28s (app-owned, not managed)\n' "$f"
    done
    [ -f "$OW_DIR/tokens.json" ] && printf '    note: tokens.json holds secrets — app-owned; use claw secret for durable backup.\n'
}

aic_setup() {
    [ -f "$OC_CONFIG" ] && ! head -1 "$OC_CONFIG" 2>/dev/null | grep -q "$AICONFIG_SENTINEL" \
        && printf '  ai-config: existing opencode config is unmanaged — leaving it (force to adopt).\n' >&2 \
        || aic_render_opencode "$OC_CONFIG"
    if [ ! -f "$OW_CONFIG" ] || grep -q '_claw_managed' "$OW_CONFIG" 2>/dev/null; then
        aic_render_openwork "$OW_CONFIG" "$OW_CONFIG"
    else
        printf '  ai-config: existing openwork server.json is app-owned — leaving it (force to adopt).\n' >&2
    fi
    if [ ! -f "$AC_CONFIG" ] || grep -q '_claw_managed' "$AC_CONFIG" 2>/dev/null; then
        aic_render_agent_canvas "$AC_CONFIG"
    else
        printf '  ai-config: existing agent-canvas config.json is app-owned — leaving it (force to adopt).\n' >&2
    fi
    aic_status
}

_cmd="${1:-status}"; shift 2>/dev/null || true
# --- agent-canvas: merge LLM routing into the app-owned settings.json -------
# Agent Canvas owns ~/.openhands/settings.json (56 llm keys + schema it bumps
# itself). We patch ONLY the routing keys from the tracked base and preserve
# everything else, so an app upgrade that adds fields survives a sync.
# Profile chosen by $CLAW_CANVAS_PROFILE, else the base's default_profile.
# Refuses to write while the app is running — it holds .settings.lock and
# rewrites the file on exit, which would silently discard the sync.
aic_render_agent_canvas() {
    _out="${1:-/dev/stdout}"
    [ -r "$AC_BASE" ] || { printf 'ai-config: missing base %s\n' "$AC_BASE" >&2; return 1; }
    if [ "$_out" != "/dev/stdout" ] && pgrep -f 'OpenHands Agent Canvas/agent-canvas' >/dev/null 2>&1; then
        printf '  ai-config: Agent Canvas is RUNNING — close it before syncing (it rewrites settings.json on exit).\n' >&2
        return 1
    fi
    [ "$_out" != "/dev/stdout" ] && mkdir -p "$(dirname "$_out")" 2>/dev/null
    # One source of truth for the gateway key: config/litellm/.env (gitignored,
    # 0600, and what docker compose itself reads). Only fall back to it when the
    # var is not already exported, so a caller can still override per-invocation.
    if [ -z "${LITELLM_MASTER_KEY:-}" ] && [ -r "$DOTFILES_DIR/config/litellm/.env" ]; then
        LITELLM_MASTER_KEY=$(sed -n 's/^LITELLM_MASTER_KEY=//p' "$DOTFILES_DIR/config/litellm/.env" | head -1)
        export LITELLM_MASTER_KEY
    fi
    BASE="$AC_BASE" CUR="$AC_CONFIG" python3 - "$_out" <<'PY2'
import json, os, sys
out  = sys.argv[1]
base = json.load(open(os.environ["BASE"]))
cur  = os.environ["CUR"]

name = os.environ.get("CLAW_CANVAS_PROFILE") or base["default_profile"]
if name not in base["profiles"]:
    sys.exit("ai-config: unknown CLAW_CANVAS_PROFILE %r (have: %s)"
             % (name, ", ".join(base["profiles"])))

patch = {k: v for k, v in base["profiles"][name].items() if not k.startswith("_")}
if patch.pop("api_key_env", None):
    patch["api_key"] = os.environ.get("LITELLM_MASTER_KEY", "sk-local-changeme")
patch.update({k: v for k, v in base.get("common", {}).items() if not k.startswith("_")})

# Start from the app's existing settings so unknown//new keys survive.
try:
    doc = json.load(open(cur))
except (OSError, ValueError):
    doc = {"agent_settings": {"llm": {}}}
doc.setdefault("agent_settings", {}).setdefault("llm", {}).update(patch)
doc["_claw_managed"] = True
doc["_claw_profile"] = name

data = json.dumps(doc, indent=2) + "\n"
if out == "/dev/stdout":
    sys.stdout.write(data)
else:
    open(out, "w").write(data)
    os.chmod(out, 0o600)          # settings.json carries the gateway key
PY2
}

case "$_cmd" in
    render)
        case "${1:-}" in
            opencode) shift; aic_render_opencode "${1:-/dev/stdout}" ;;
            openwork) shift; aic_render_openwork "${1:-/dev/stdout}" ;;
            agent-canvas) shift; aic_render_agent_canvas "${1:-/dev/stdout}" ;;
            *) printf 'usage: ai-config.sh render <opencode|openwork|agent-canvas> [out]\n' >&2; exit 1 ;;
        esac ;;
    sync)   aic_sync ;;
    status) aic_status ;;
    setup)  aic_setup ;;
    *) printf 'usage: ai-config.sh {render <tool> [out] | sync | status | setup}\n' >&2; exit 1 ;;
esac
