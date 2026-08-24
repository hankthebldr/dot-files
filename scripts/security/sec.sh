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
    printf "  ${C_OK}lint${C_OFF}              validate the registry and flows (type + egress + argv rules)\n"
    printf "  ${C_OK}doctor${C_OFF} [tool...]  assert binary identity, not presence\n"
    printf "  ${C_OK}tools${C_OFF}             list declared tools with scope class and types\n"
    printf "  ${C_OK}flows${C_OFF}             list declared flows and their phases\n"
    printf "  ${C_OK}scope${C_OFF} <target>    show the gate's verdict for a host\n"
    printf "  ${C_OK}audit${C_OFF} verify      walk the hash chain of an engagement\n"
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
    local target="${1:-}"
    [[ -n "$target" ]] || { printf "${C_WARN}usage: claw sec scope <host> [addr...]${C_OFF}\n"; return 2; }
    shift || true
    CLAW_SEC_TARGET="$target" CLAW_SEC_ADDRS="$*" py - <<'PY'
import os, scope as S
path = os.path.expanduser("~/.claude/scope.txt")
sc = S.Scope.from_files(path)
host = os.environ["CLAW_SEC_TARGET"]
addrs = os.environ.get("CLAW_SEC_ADDRS", "").split()
v = S.authorize(host, addrs, sc)
print(f"  scope file : {path}")
print(f"  policy     : {sc.policy}")
print(f"  verdict    : {'ALLOW' if v.allowed else 'DENY'}  ({v.reason})")
if v.unverified_addr:
    print("  note       : allowed without address verification")
if v.proposal:
    print(f"  proposal   : {v.proposal}")
raise SystemExit(0 if v.allowed else 1)
PY
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
    lint)            shift; py "$SEC_DIR/lint.py" "$@" ;;
    doctor)          shift; py "$SEC_DIR/doctor.py" "$@" ;;
    tools)           shift; cmd_tools "$@" ;;
    flows)           shift; cmd_flows "$@" ;;
    scope)           shift; cmd_scope "$@" ;;
    audit)           shift; cmd_audit "$@" ;;
    test)            shift; ( cd "$DOTFILES" && python3 -m unittest discover -s tests/security "$@" ) ;;
    help|-h|--help)  usage ;;
    *)               printf "${C_WARN}unknown: claw sec %s${C_OFF}\n\n" "$1"; usage; exit 2 ;;
esac
