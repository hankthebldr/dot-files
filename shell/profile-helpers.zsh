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
