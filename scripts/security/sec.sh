#!/usr/bin/env bash
# claw sec — front door to the security harness.
#
# Routes to the Python layers under scripts/security/. Everything that touches
# a target goes through registry.invoke(), which holds the scope gate; nothing
# here reimplements authorization.
set -euo pipefail

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
[[ -d "$DOTFILES/scripts/security" ]] || DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEC_DIR="$DOTFILES/scripts/security"

# One theme engine — consume CLAW_C_* with refined-dark fallbacks (spine rule 2).
if [[ -f "$DOTFILES/scripts/utils/theme.sh" ]]; then
    # shellcheck disable=SC1091
    source "$DOTFILES/scripts/utils/theme.sh" 2>/dev/null || true
fi
# CLAW_RGB_* are "r;g;b" triplets from the palette; refined-dark is the
# fallback, exactly as every other surface does it.
C_HEAD="\033[38;2;${CLAW_RGB_BLUE:-88;166;255}m"
C_OK="\033[38;2;${CLAW_RGB_GREEN:-63;185;80}m"
C_WARN="\033[38;2;${CLAW_RGB_AMBER:-227;179;65}m"
C_MUTED="\033[38;2;${CLAW_RGB_MUTED:-139;148;158}m"
C_OFF="\033[0m"

py() { PYTHONPATH="$SEC_DIR${PYTHONPATH:+:$PYTHONPATH}" python3 "$@"; }

usage() {
    printf "${C_HEAD}claw sec${C_OFF} — scope-gated security harness\n\n"
    printf "  ${C_OK}run${C_OFF} <flow>        execute a flow (--domain X [--dry-run] [--engagement DIR])\n"
    printf "  ${C_OK}demo${C_OFF}              full offline run on fixture tools — no toolchain needed\n"
    printf "  ${C_OK}drill${C_OFF} <target>    end-to-end rehearsal on the REAL chain ${C_MUTED}[--live]${C_OFF}\n"
    printf "  ${C_OK}lint${C_OFF}              validate the registry and flows (type + egress + argv rules)\n"
    printf "  ${C_OK}doctor${C_OFF} [tool...]  assert binary identity, not presence\n"
    printf "  ${C_OK}tools${C_OFF}             list declared tools with scope class and types\n"
    printf "  ${C_OK}flows${C_OFF}             list declared flows and their phases\n"
    printf "  ${C_OK}scope${C_OFF} <target>    show the gate's verdict for a host\n"
    printf "  ${C_OK}scope add${C_OFF} <t>     authorize a target — engagement overlay, ${C_MUTED}--global${C_OFF} for durable\n"
    printf "  ${C_OK}scope show${C_OFF}        both scope layers and the effective policy\n"
    printf "  ${C_OK}audit${C_OFF} verify      walk the hash chain of an engagement\n"
    printf "  ${C_OK}mcp${C_OFF}               serve the tool surface over MCP stdio\n"
    printf "  ${C_OK}test${C_OFF}              run the harness test suite\n\n"
    printf "  ${C_MUTED}Registry:  config/security/tools.yaml${C_OFF}\n"
    printf "  ${C_MUTED}Flows:     config/security/flows/${C_OFF}\n"
    printf "  ${C_MUTED}Spec:      docs/superpowers/specs/2026-08-23-security-harness-design.md${C_OFF}\n"
}

cmd_tools() {
    py - <<'PY'
import lint as L
reg = L.load_registry()
width = max(len(n) for n in reg)
for name in sorted(reg):
    s = reg[name]
    print(f"  {name:<{width}}  {s['scope_class']:<16} "
          f"{', '.join(s['consumes']) or '-':<20} -> {', '.join(s['emits']) or '-'}")
print(f"\n  {len(reg)} tool(s)")
PY
}

cmd_flows() {
    py - <<'PY'
import lint as L
for flow in L.load_flows():
    print(f"  {flow['name']}: {flow.get('description', '')}")
    for p in flow["phases"]:
        mark = " [GATE]" if p.get("gate") else ""
        tools = ", ".join(p.get("tools") or []) or p.get("scope_class", "-")
        print(f"    {p['id']}  {p['name']:<12} {tools}{mark}")
PY
}

cmd_scope() {
    case "${1:-}" in
        add)  shift; cmd_scope_add "$@"; return $? ;;
        show|"") cmd_scope_show; return $? ;;
    esac

    local target="$1"; shift || true
    CLAW_SEC_TARGET="$target" CLAW_SEC_ADDRS="$*" py - <<'PY'
import os, scope as S, scope_edit as E
info = E.describe_layers()
sc = info["scope"]
host = os.environ["CLAW_SEC_TARGET"]
addrs = os.environ.get("CLAW_SEC_ADDRS", "").split()
v = S.authorize(host, addrs, sc)
name_ok = (not sc.denied(host, [])) and sc.name_allows(host)
print(f"  global     : {info['global_path']}")
print(f"  overlay    : {info['overlay_path']}"
      f"{'' if info['overlay_active'] else '  (none)'}")
print(f"  policy     : {sc.policy}")
print(f"  verdict    : {'ALLOW' if v.allowed else 'DENY'}  ({v.reason})")
if v.unverified_addr:
    print("  note       : allowed without address verification")
# This command does not resolve DNS — it answers from the files alone. Under
# `enforce` a name with no address is refused here but may well pass at run
# time, when phases.py resolves it for real. Say which of the two happened
# rather than leaving an operator who just added the name staring at DENY.
if name_ok and not v.allowed and not addrs and sc.policy == "enforce":
    print("  name       : authorized — the DENY above is the address check")
    print(f"  check one  : claw sec scope {host} <addr>   (a run resolves it for you)")
elif not name_ok:
    print(f"  authorize  : claw sec scope add {S._norm_host(host)}"
          "        (engagement overlay)")
    print(f"               claw sec scope add {S._norm_host(host)} --global"
          "  (durable)")
if v.proposal and addrs:
    print(f"  proposal   : {v.proposal}")
raise SystemExit(0 if v.allowed else 1)
PY
}

cmd_scope_show() {
    py - <<'PY'
import scope_edit as E
info = E.describe_layers()
f = info["facts"]
print(f"  global     : {info['global_path']}")
print(f"  overlay    : {info['overlay_path']}"
      f"{'' if info['overlay_active'] else '  (none — nothing added this engagement)'}")
print(f"  policy     : {f['policy']}")
for label, key in (("allow name", "allow_names"), ("allow addr", "allow_addrs"),
                   ("DENY name", "deny_names"), ("DENY addr", "deny_addrs")):
    for entry in f[key]:
        print(f"  {label:<10} : {entry}")
PY
}

# Overlay adds are unattended by design (§5.7) — on-demand targets churn, and
# ceremony there just pushes people back to hand-editing the durable file.
# A --global add is standing authority, so it always confirms; with no TTY it
# refuses rather than assuming consent, and --yes is the explicit override.
cmd_scope_add() {
    local to_global=0 assume_yes=0 entry=""
    while (( $# )); do
        case "$1" in
            --global) to_global=1 ;;
            --yes|-y) assume_yes=1 ;;
            -h|--help)
                printf "usage: claw sec scope add <target> [--global] [--yes]\n"
                printf "  default target file: \$CLAW_SEC_ENGAGEMENT/scope.local\n"
                return 0 ;;
            -*) printf "${C_WARN}unknown flag: %s${C_OFF}\n" "$1"; return 2 ;;
            *)  [[ -z "$entry" ]] || { printf "${C_WARN}one target per add${C_OFF}\n"; return 2; }
                entry="$1" ;;
        esac
        shift
    done
    [[ -n "$entry" ]] || { printf "${C_WARN}usage: claw sec scope add <target> [--global]${C_OFF}\n"; return 2; }

    if (( to_global )) && (( ! assume_yes )); then
        local dest; dest="${CLAW_SEC_SCOPE_FILE:-$HOME/.claude/scope.txt}"
        if [[ ! -t 0 ]]; then
            printf "${C_WARN}refusing to amend %s without confirmation${C_OFF}\n" "$dest"
            printf "  ${C_MUTED}no TTY to prompt on — re-run with --yes if this is intended${C_OFF}\n"
            return 2
        fi
        printf "  ${C_HEAD}durable authority${C_OFF} — add ${C_OK}%s${C_OFF} to %s?\n" "$entry" "$dest"
        local reply; read -r -p "  type 'yes' to confirm: " reply
        [[ "$reply" == "yes" ]] || { printf "  ${C_MUTED}unchanged${C_OFF}\n"; return 1; }
    fi

    CLAW_SEC_ENTRY="$entry" CLAW_SEC_GLOBAL="$to_global" py - <<'PY'
import os, sys, scope as S, scope_edit as E
try:
    r = E.add_entry(os.environ["CLAW_SEC_ENTRY"],
                    to_global=os.environ["CLAW_SEC_GLOBAL"] == "1")
except S.ScopeParseError as exc:
    print(f"  refused: {exc}")
    sys.exit(2)
if r.status == "denied":
    print(f"  refused: {r.entry} — {r.detail}")
    print("  a deny entry outranks any allow; edit the scope file to change that")
    sys.exit(2)
verb = "added" if r.status == "added" else "already present"
print(f"  {verb}: {r.entry}  [{r.layer}]")
print(f"  file : {r.path}")
PY
}

# `claw sec drill <target>` — exercise the LIVE path end to end: real registry,
# real Tier 0 binaries, real gate, real audit chain. `demo` proves the machinery
# with fixtures; `drill` proves this box.
#
# It deliberately does NOT authorize the target for you. A command that both
# grants authority and then uses it is a gate with a hole in it, so drill
# refuses an unauthorized target and tells you to run `scope add` — the
# deliberate, separate act. Dry run is the default; --live executes.
cmd_drill() {
    local target="" live=0 keep=0
    while (( $# )); do
        case "$1" in
            --live) live=1 ;;
            --keep) keep=1 ;;
            -h|--help)
                printf "usage: claw sec drill <target> [--live] [--keep]\n"
                printf "  default is a dry run — the gate decides, nothing executes\n"
                printf "  the target must already be authorized (claw sec scope add)\n"
                return 0 ;;
            -*) printf "${C_WARN}unknown flag: %s${C_OFF}\n" "$1"; return 2 ;;
            *)  [[ -z "$target" ]] || { printf "${C_WARN}one target per drill${C_OFF}\n"; return 2; }
                target="$1" ;;
        esac
        shift
    done
    [[ -n "$target" ]] || { printf "${C_WARN}usage: claw sec drill <target> [--live]${C_OFF}\n"; return 2; }

    printf "${C_HEAD}drill${C_OFF}      %s%s\n\n" "$target" \
        "$( (( live )) && printf '  (LIVE — tools will execute)' || printf '  (dry run)' )"

    # 1. Authorization is a precondition, never a side effect.
    #    The precondition is *name* authority only. Under resolve-policy
    #    enforce the full verdict also needs resolved addresses, which the run
    #    itself supplies — demanding them here would refuse every freshly added
    #    name and make the drill unusable for exactly its intended case.
    printf "${C_HEAD}1. gate${C_OFF}\n"
    if ! CLAW_SEC_TARGET="$target" py - <<'PY'
import os, sys, scope_edit as E
sc = E.describe_layers()["scope"]
host = os.environ["CLAW_SEC_TARGET"]
sys.exit(0 if (not sc.denied(host, [])) and sc.name_allows(host) else 1)
PY
    then
        cmd_scope "$target" || true
        printf "\n  ${C_WARN}not authorized — drill will not add it for you${C_OFF}\n"
        printf "  ${C_MUTED}authorize it deliberately, then re-run:${C_OFF}\n"
        printf "    claw sec scope add %s\n" "$target"
        return 2
    fi
    printf "  ${C_OK}name authorized${C_OFF}  %s ${C_MUTED}(addresses verified at run time)${C_OFF}\n\n" "$target"

    # 2. Identity, not presence — a missing or shadowed binary is a finding.
    printf "${C_HEAD}2. toolchain${C_OFF}\n"
    cmd_doctor || printf "  ${C_WARN}some tools failed identity — phases using them will report tool_missing${C_OFF}\n"
    printf "\n"

    # 3. The run itself, in its own engagement so a drill never mixes with real work.
    local eng="${CLAW_SEC_DRILL_DIR:-${TMPDIR:-/tmp}/claw-sec-drill}"
    if [[ -e "$eng" && ! -f "$eng/.claw-sec-drill" ]]; then
        printf "${C_WARN}%s exists and was not created by 'claw sec drill'.${C_OFF}\n" "$eng"
        return 2
    fi
    command rm -rf "${eng:?}"
    mkdir -p "$eng"
    : > "$eng/.claw-sec-drill"

    printf "${C_HEAD}3. flow${C_OFF}\n"
    local rc=0
    local args=(webrecon --domain "$target" --engagement "$eng")
    (( live )) || args+=(--dry-run)
    py "$SEC_DIR/run.py" "${args[@]}" || rc=$?

    printf "\n${C_HEAD}4. evidence${C_OFF}\n"
    printf "  ${C_MUTED}artifacts:${C_OFF} %s\n" "$eng"
    printf "  ${C_MUTED}gate:${C_OFF}      %s\n" "$eng/gate/"
    printf "  ${C_MUTED}audit:${C_OFF}     %s\n" "$eng/audit.jsonl"
    (( keep )) || printf "  ${C_MUTED}(next drill resets this directory; --keep is advisory only)${C_OFF}\n"
    return $rc
}

cmd_audit() {
    local sub="${1:-verify}" root="${2:-$PWD}"
    [[ "$sub" == "verify" ]] || { printf "${C_WARN}usage: claw sec audit verify [dir]${C_OFF}\n"; return 2; }
    CLAW_SEC_ROOT="$root" py - <<'PY'
import os, pathlib, registry as R, scope as S
root = pathlib.Path(os.environ["CLAW_SEC_ROOT"])
ctx = R.Engagement(root=root, run_id="verify", scope=S.Scope.from_text(""), registry={})
ok, detail = R.verify_audit(ctx)
print(("  ok    " if ok else "  BROKEN") + f"  {root/'audit.jsonl'}: {detail}")
raise SystemExit(0 if ok else 1)
PY
}

cmd_demo() {
    # A complete run with none of the real chain installed: fixture binaries
    # stand in for the tool surface, so the gate, the audit chain and the taint
    # marking are all exercised for real against a documentation-range scope.
    local fx="$DOTFILES/tests/security/fixtures"
    local eng="${1:-${TMPDIR:-/tmp}/claw-sec-demo}"
    # Only ever reset a directory this command created. A demo must not be a
    # way to delete an arbitrary path someone passed by mistake.
    if [[ -e "$eng" ]]; then
        if [[ -f "$eng/.claw-sec-demo" ]]; then
            command rm -rf "${eng:?}"
        else
            printf "${C_WARN}%s exists and was not created by 'claw sec demo'.${C_OFF}\n" "$eng"
            printf "  Remove it yourself, or pass a different path.\n"
            return 2
        fi
    fi
    mkdir -p "$eng"
    : > "$eng/.claw-sec-demo"
    cat > "$eng/scope.demo" <<'SCOPE'
# Demo scope. RFC 5737 documentation range — nothing here is routable.
resolve-policy: enforce
*.lab.internal
192.0.2.0/24
SCOPE
    printf "${C_HEAD}demo${C_OFF}       fixture tool chain, no network, no toolchain\n"
    PATH="$fx/bin:$PATH" py "$SEC_DIR/run.py" fxrecon \
        --domain lab.internal \
        --engagement "$eng" \
        --registry "$fx/registry.yaml" \
        --flows-dir "$fx/flows" \
        --scope "$eng/scope.demo" "$@"
    local rc=$?
    printf "\n  ${C_MUTED}artifacts:${C_OFF} %s\n" "$eng"
    printf "  ${C_MUTED}gate:${C_OFF}      %s\n" "$eng/gate/"
    printf "  ${C_MUTED}audit:${C_OFF}     %s\n" "$eng/audit.jsonl"
    return $rc
}

case "${1:-help}" in
    run)             shift; py "$SEC_DIR/run.py" "$@" ;;
    demo)            shift; cmd_demo "$@" ;;
    drill)           shift; cmd_drill "$@" ;;
    lint)            shift; py "$SEC_DIR/lint.py" "$@" ;;
    doctor)          shift; py "$SEC_DIR/doctor.py" "$@" ;;
    tools)           shift; cmd_tools "$@" ;;
    flows)           shift; cmd_flows "$@" ;;
    scope)           shift; cmd_scope "$@" ;;
    audit)           shift; cmd_audit "$@" ;;
    mcp)             shift; py "$SEC_DIR/mcp_server.py" "$@" ;;
    test)            shift; ( cd "$DOTFILES" && python3 -m unittest discover -s tests/security "$@" ) ;;
    help|-h|--help)  usage ;;
    *)               printf "${C_WARN}unknown: claw sec %s${C_OFF}\n\n" "$1"; usage; exit 2 ;;
esac
