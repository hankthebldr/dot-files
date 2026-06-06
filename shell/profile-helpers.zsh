# shell/profile-helpers.zsh
# Tiny helpers shared across all 9 profiles. Sourced once from .zshrc before
# any profile load.

# _claw_guard <name> <tool> <command...>
#
# If <tool> is on PATH:        defines an alias `name=command...`
# If <tool> is NOT on PATH:    defines a function that prints a helpful
#                              install hint and returns 1.
#
# Usage:
#   _claw_guard nrecon nmap nmap -T4 -A -v
#   _claw_guard sqli  sqlmap sqlmap --batch --random-agent
#   _claw_guard pcap  tcpdump sudo tcpdump -i any
#
# Beats a raw "nmap: command not found" — surfaces the actual missing tool
# AND tells the user how to install it.
_claw_guard() {
    local name="$1" tool="$2"; shift 2
    if command -v "$tool" &>/dev/null; then
        alias "$name=$*"
    else
        eval "$name() {
            printf '  \\e[38;2;255;123;114m✗\\e[0m %s not installed — try: \\e[38;2;201;209;217mbrew install %s\\e[0m\\n' \"$tool\" \"$tool\" >&2
            return 1
        }"
    fi
}

# ── Generic profile tool-check ──────────────────────────────────────────────
# Fallback for profiles that declare PROFILE_KEY_TOOLS but no bespoke
# _<name>_tool_check (blackwell, brainstorm, deck, demo, design, homelab, pmo,
# tunnels). Reports installed/missing for the active profile's key tools.
_claw_profile_tool_check() {
    emulate -L zsh
    local list="${PROFILE_KEY_TOOLS:-}"
    if [[ -z "$list" ]]; then
        printf "  no key tools declared for %s\n" "${CLAW_ACTIVE_PROFILE:-profile}"
        return 0
    fi
    printf "  %s key tools:\n" "${CLAW_ACTIVE_PROFILE:-profile}"
    local bin
    for bin in ${(s: :)list}; do
        if command -v "$bin" &>/dev/null; then
            printf "    \e[38;2;63;185;80m✓\e[0m %s\n" "$bin"
        else
            printf "    \e[38;2;255;123;114m✗\e[0m %s ${CLAW_PROFILE_TOOLCHAIN:+— claw install ${CLAW_ACTIVE_PROFILE}}\n" "$bin"
        fi
    done
}
