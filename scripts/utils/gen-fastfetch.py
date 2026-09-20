#!/usr/bin/env python3
"""Generate icon-rich fastfetch dashboards for the OPEN CLAW profiles.

One shared base layout (System / Desktop / Hardware / Network) is rendered for
every profile, then each profile layers its own domain "Tooling" section on
top. Keys carry Nerd Font glyphs (Font Awesome codepoints, stable across Nerd
Font builds) and the GitHub macOS Dark palette. fastfetch silently skips any
module with no data, so each machine (macOS or Linux, desktop or headless)
auto-populates only what it has.

Run:  python3 scripts/utils/gen-fastfetch.py
Writes config.jsonc, config-default.jsonc and config-{profile}.jsonc into
config/.config/fastfetch/.
"""

import json
import os

# ── Nerd Font glyphs (Font Awesome / Devicon codepoints) ─────────────────────
I = {
    # section headers
    "s_sys": "", "s_desk": "", "s_hw": "",
    "s_net": "", "s_tool": "",
    # system
    "os": "", "host": "", "kernel": "", "uptime": "",
    "load": "", "proc": "", "pkg": "", "shell": "",
    "editor": "",
    # desktop
    "de": "", "wm": "", "wmtheme": "", "theme": "",
    "icons": "", "cursor": "", "font": "", "term": "",
    "termfont": "",
    # hardware
    "cpu": "", "gpu": "", "display": "", "bright": "",
    "mem": "", "swap": "", "disk": "", "drive": "",
    "batt": "", "power": "", "sound": "", "bt": "",
    # network
    "localip": "", "wifi": "", "locale": "", "date": "",
    # tooling
    "aws": "", "k8s": "", "tf": "", "docker": "",
    "git": "", "ansible": "", "ollama": "", "python": "",
    "pip": "", "claude": "", "jq": "", "rg": "",
    "xsoar": "", "cortex": "", "vpn": "", "nmap": "",
    "pubip": "",
}

# Refined GitHub Dark palette (truecolor ANSI) — matches config/themes/refined-dark/palette.theme.
# The default Open Claw theme; the gruvbox-y gold (#d29922) is replaced by a
# cooler amber (#e3b341). fastfetch configs are static so they bake the default
# palette; the live dashboard (claw-dashboard.py) follows `claw theme` instead.
PURPLE = "38;2;188;140;255"
BLUE   = "38;2;88;166;255"
GREEN  = "38;2;63;185;80"
ORANGE = "38;2;227;179;65"
RED    = "38;2;255;123;114"
MUTED  = "38;2;139;148;158"

SCHEMA = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json"
VPN_CMD = ("if command -v scutil >/dev/null; then if scutil --nwi 2>/dev/null | "
           "grep -q utun; then echo 'connected'; else echo 'off'; fi; elif ip "
           "link show 2>/dev/null | grep -qE 'tun0|wg0'; then echo 'connected'; "
           "else echo 'off'; fi")


def k(icon, label):
    return f"{icon}  {label}"


def hdr(icon, word):
    dashes = "─" * max(4, 30 - len(word))
    return {"type": "custom", "format": f"{icon}  {word} {dashes}"}


def mod(t, icon, label, color, **extra):
    m = {"type": t, "key": k(I[icon], label), "keyColor": color}
    m.update(extra)
    return m


def base_modules():
    return [
        hdr(I["s_sys"], "System"),
        mod("os", "os", "OS", PURPLE),
        mod("host", "host", "Host", PURPLE),
        mod("kernel", "kernel", "Kernel", BLUE),
        mod("uptime", "uptime", "Uptime", BLUE),
        mod("loadavg", "load", "Load", BLUE),
        mod("processes", "proc", "Processes", BLUE),
        mod("packages", "pkg", "Packages", GREEN),
        mod("shell", "shell", "Shell", GREEN),
        mod("editor", "editor", "Editor", GREEN),

        hdr(I["s_desk"], "Desktop"),
        mod("de", "de", "DE", ORANGE),
        mod("wm", "wm", "WM", ORANGE),
        mod("wmtheme", "wmtheme", "WM Theme", ORANGE),
        mod("theme", "theme", "Theme", RED),
        mod("icons", "icons", "Icons", RED),
        mod("cursor", "cursor", "Cursor", RED),
        mod("font", "font", "Font", BLUE),
        mod("terminal", "term", "Terminal", PURPLE),
        mod("terminalfont", "termfont", "Term Font", BLUE),

        hdr(I["s_hw"], "Hardware"),
        mod("cpu", "cpu", "CPU", BLUE),
        mod("gpu", "gpu", "GPU", GREEN),
        mod("display", "display", "Display", PURPLE),
        mod("brightness", "bright", "Brightness", PURPLE),
        mod("memory", "mem", "Memory", GREEN),
        mod("swap", "swap", "Swap", GREEN),
        mod("disk", "disk", "Disk", ORANGE, showReadOnly=False),
        # NOTE: physicaldisk is intentionally omitted. It enumerates /sys/block
        # with no mount filter, so on snap/container hosts it floods the readout
        # with dozens of squashfs/loop devices ([Virtual, Fixed, Read-only]).
        # The `disk` module above already conveys storage on macOS + Linux.
        mod("battery", "batt", "Battery", ORANGE),
        mod("poweradapter", "power", "Power", ORANGE),
        mod("sound", "sound", "Sound", RED),
        mod("bluetooth", "bt", "Bluetooth", BLUE),

        hdr(I["s_net"], "Network"),
        mod("localip", "localip", "Local IP", MUTED),
        mod("wifi", "wifi", "Wi-Fi", MUTED),
        mod("locale", "locale", "Locale", MUTED),
        {"type": "command", "key": k(I["date"], "Date"), "keyColor": MUTED,
         "text": "date '+%A, %b %d  %H:%M'"},
    ]


def tooling(items):
    out = [hdr(I["s_tool"], "Tooling")]
    for icon, label, text in items:
        out.append({"type": "command", "key": k(I[icon], label), "text": text})
    return out


def footer():
    return [
        {"type": "custom", "format": "─" * 32},
        {"type": "colors", "paddingLeft": 2, "symbol": "circle"},
    ]


def build(logo, keys_color, title_color, tool_items):
    modules = [
        {"type": "title", "format": "{user-name-colored}@{host-name-colored}",
         "key": " "}
    ]
    modules += base_modules()
    if tool_items:
        modules += tooling(tool_items)
    modules += footer()
    return {
        "$schema": SCHEMA,
        "logo": logo,
        "display": {"separator": " → ",
                    "color": {"keys": keys_color, "title": title_color}},
        "modules": modules,
    }


def auto_logo(top):
    return {"type": "auto", "padding": {"top": top, "left": 2, "right": 3}}


def file_logo(profile):
    """Pre-rendered truecolor ANSI art (chafa-style). Printed verbatim."""
    return {
        "source": f"~/.dotfiles/config/.config/fastfetch/logo-{profile}.txt",
        "type": "file-raw",
        "padding": {"top": 1, "left": 2, "right": 3},
    }


def placeholder_logo(filename, colors, top=1):
    """Branded ASCII art using fastfetch $1..$N color placeholders.

    Needs type:file (which substitutes the `color` map) — NOT file-raw, which
    would print the literal "$1". This is how the pre-menu OPEN CLAW header
    (logo.txt) and the Apple default logo (logo-default.txt) get their color.
    """
    return {
        "source": f"~/.dotfiles/config/.config/fastfetch/{filename}",
        "type": "file",
        "color": colors,
        "padding": {"top": top, "left": 2, "right": 3},
    }


# OPEN CLAW pre-menu header (logo.txt): frame / OPEN / accent / CLAW
OPENCLAW_COLORS = {"1": MUTED, "2": BLUE, "3": PURPLE, "4": GREEN}
# Apple default logo (logo-default.txt): six rainbow bands, top → bottom
APPLE_COLORS = {
    "1": "38;2;255;140;0",    # orange  (mid band + bite)
    "2": "38;2;245;200;66",   # yellow  (upper body)
    "3": GREEN,               # green   (leaf / top)
    "4": RED,                 # red
    "5": PURPLE,              # purple
    "6": BLUE,                # blue    (bottom)
}


# ── Per-profile domain tooling ───────────────────────────────────────────────
CLOUD = [
    ("aws", "AWS", "aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'not authenticated'"),
    ("k8s", "K8s", "kubectl config current-context 2>/dev/null || echo 'none'"),
    ("tf", "Terraform", "terraform version -json 2>/dev/null | jq -r '.terraform_version' || terraform --version 2>/dev/null | head -1 | awk '{print $2}' || echo 'n/a'"),
    ("docker", "Docker", "echo \"$(docker ps -q 2>/dev/null | wc -l | tr -d ' ') containers running\""),
]
SECURITY = [
    ("nmap", "Nmap", "nmap --version 2>/dev/null | head -1 | awk '{print $3}' || echo 'n/a'"),
    ("pubip", "Public IP", "curl -s --max-time 2 ifconfig.me 2>/dev/null || echo 'offline'"),
    ("vpn", "VPN", VPN_CMD),
]
DEVOPS = [
    ("docker", "Docker", "echo \"$(docker ps -q 2>/dev/null | wc -l | tr -d ' ') containers running\""),
    ("k8s", "K8s", "kubectl config current-context 2>/dev/null || echo 'none'"),
    ("git", "Git", "git --version 2>/dev/null | awk '{print $3}' || echo 'n/a'"),
    ("tf", "Terraform", "terraform --version 2>/dev/null | head -1 | awk '{print $2}' || echo 'n/a'"),
    ("ansible", "Ansible", "ansible --version 2>/dev/null | head -1 | awk '{print $2}' | tr -d '[]' || echo 'n/a'"),
]
AI = [
    ("ollama", "Ollama", "ollama list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ' | xargs -I{} echo '{} local models' || echo 'not running'"),
    ("python", "Python", "python3 --version 2>/dev/null | awk '{print $2}' || echo 'n/a'"),
    ("pip", "Pip Pkgs", "pip3 list 2>/dev/null | tail -n +3 | wc -l | tr -d ' ' | xargs -I{} echo '{} packages' || echo 'n/a'"),
    ("claude", "Claude", "claude --version 2>/dev/null | head -1 || echo 'n/a'"),
]
RESEARCH = [
    ("python", "Python", "python3 --version 2>/dev/null | awk '{print $2}' || echo 'n/a'"),
    ("jq", "jq", "jq --version 2>/dev/null | tr -d 'jq-' || echo 'n/a'"),
    ("rg", "ripgrep", "rg --version 2>/dev/null | head -1 | awk '{print $2}' || echo 'n/a'"),
]
CORTEX = [
    ("xsoar", "XSOAR", "demisto-sdk --version 2>/dev/null || echo 'not installed'"),
    ("cortex", "Cortex", "cortexcli version 2>/dev/null || echo 'not installed'"),
    ("python", "Python", "python3 --version 2>/dev/null | awk '{print $2}' || echo 'n/a'"),
    ("vpn", "VPN", VPN_CMD),
]

# profile -> (logo, keys/accent color, title color, tooling)
#
# NOTE: this generator owns ONLY the 9 configs below. The 10 specialized
# profiles (claude, blackwell, brainstorm, deck, demo, design, homelab, pmo,
# tunnels, vault) ship hand-maintained config-<name>.jsonc files that this
# script never reads or overwrites — edit those directly. See CLAUDE.md
# ("Fastfetch Profile Configs"). Running this generator will NOT touch them.
CONFIGS = {
    # Startup + default: use the real system icon (Apple on macOS, distro on
    # Linux) — cleaner and more recognizable than the ASCII OPEN CLAW header.
    "config.jsonc":         (auto_logo(1), BLUE,   PURPLE, None),
    "config-default.jsonc": (auto_logo(0), BLUE,   GREEN,  None),
    "config-cloud.jsonc":   (file_logo("cloud"),    ORANGE,            PURPLE, CLOUD),
    "config-security.jsonc":(file_logo("security"),  RED,              PURPLE, SECURITY),
    "config-devops.jsonc":  (file_logo("devops"),    GREEN,            PURPLE, DEVOPS),
    "config-ai.jsonc":      (file_logo("ai"),        PURPLE,           GREEN,  AI),
    "config-research.jsonc":(file_logo("research"),  ORANGE,           BLUE,   RESEARCH),
    "config-cortex.jsonc":  (file_logo("cortex"),    "38;2;255;102;0", RED,    CORTEX),
    # local is special-cased in main() -> build_local_readout() (compact
    # two-column readout, no physicaldisk flood); this tuple is unused for it.
    "config-local.jsonc":   (file_logo("local"),     GREEN,            BLUE,   None),
}


# Vertical centering: the readout is title + 9 rows + colors ≈ 11 lines, while
# the auto system logo (Apple on macOS) is ~17. Prepend this many `break`
# modules to drop the block down so it sits centered against the logo's full
# height. One knob — raise to push lower, lower to push up. Different OS logos
# vary slightly in height; tuned for the macOS Apple logo (primary).
READOUT_VCENTER = 3


def build_readout():
    """Startup dashboard: system icon + a compact TWO-COLUMN readout.

    The long ~40-row module list didn't fit the screen, so config.jsonc renders
    the icon-rich two-column block from scripts/utils/ff-readout.sh instead —
    each row is its own one-line `command` module (so it never depends on
    multi-line module output), shown to the right of the auto system logo.
    """
    rows = [
        {"type": "command", "key": " ",
         "text": f"~/.dotfiles/scripts/utils/ff-readout.sh r{i}"}
        for i in range(1, 10)
    ]
    leading = [{"type": "break"} for _ in range(READOUT_VCENTER)]
    return {
        "$schema": SCHEMA,
        # right:1 (was 3) pulls the two columns in toward the logo instead of
        # floating them off to the right.
        "logo": {"type": "auto", "padding": {"top": 1, "left": 2, "right": 1}},
        "display": {"separator": "", "color": {"keys": BLUE, "title": PURPLE},
                    "key": {"width": 0}},
        "modules": [
            # `break` spacers push the block down to vertically center it beside
            # the logo (see READOUT_VCENTER).
            *leading,
            # key:" " (a single blank, NOT "") — fastfetch renders an empty-string
            # key as the module's type name ("Command"/"Title"), but a blank space
            # with keyWidth:0 prints nothing. The readout rows + this title each
            # carry their own 2-space indent so they line up with the box below.
            {"type": "title",
             "format": "  {user-name-colored}@{host-name-colored}", "key": " "},
            *rows,
            {"type": "colors", "paddingLeft": 2, "symbol": "circle"},
        ],
    }


# The local readout (title + blank + 5 rows + colors ≈ 8 lines) sits beside the
# 14-line raspberry-pi logo; ~3 leading `break`s drop it down to center.
LOCAL_VCENTER = 3


def build_local_readout():
    """Local profile: raspberry-pi logo + compact TWO-COLUMN readout.

    The shared base_modules() layout (~45 rows) overflowed far past the 14-line
    logo AND its `physicaldisk` module flooded the screen with every snap/loop
    squashfs device ([Virtual, Fixed, Read-only]). Local instead renders the
    two-column engine from scripts/utils/ff-readout.sh (rows l1..l5 — OS/Uptime,
    Kernel/CPU, Mem/Disk, IP/Shell, local-CLIs/key-tools). The `disk` field is
    `df -H /` (root only), so no container/loop volumes appear, and the block is
    vertically centered against the logo. Each row is its own one-line `command`
    module so nothing depends on multi-line module output.
    """
    rows = [
        {"type": "command", "key": " ",
         "text": f"~/.dotfiles/scripts/utils/ff-readout.sh {r}"}
        for r in ("l1", "l2", "l3", "l4", "l5")
    ]
    # HR-TRUST lab board: cache-only reads via homelab-board.sh (zero network at
    # render — see docs/superpowers/specs/2026-06-29-homelab-lab-board-design.md).
    # fastfetch skips command modules with no output, so a box with no cache
    # (or an SSH session) simply omits the section.
    lab_rows = [
        {"type": "custom", "format": "  ── HR-TRUST Lab ─────────"},
        *[{"type": "command", "key": " ",
           "text": f"~/.dotfiles/scripts/utils/homelab-board.sh {sect}"}
          for sect in ("nodes", "cluster", "dns", "apps", "infra")],
    ]
    leading = [{"type": "break"} for _ in range(LOCAL_VCENTER)]
    return {
        "$schema": SCHEMA,
        "logo": file_logo("local"),
        "display": {"separator": "", "color": {"keys": GREEN, "title": BLUE},
                    "key": {"width": 0}},
        "modules": [
            *leading,
            # key:" " + keyWidth:0 prints nothing; the title and each readout row
            # carry their own 2-space indent so they line up (see build_readout).
            {"type": "title",
             "format": "  {user-name-colored}@{host-name-colored}", "key": " "},
            {"type": "break"},  # blank line under the title
            *rows,
            *lab_rows,
            {"type": "colors", "paddingLeft": 2, "symbol": "circle"},
        ],
    }


def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "..",
                           "config", ".config", "fastfetch")
    out_dir = os.path.abspath(out_dir)
    for name, (logo, keys, title, tools) in CONFIGS.items():
        if name in ("config.jsonc", "config-default.jsonc"):
            cfg = build_readout()
        elif name == "config-local.jsonc":
            cfg = build_local_readout()
        else:
            cfg = build(logo, keys, title, tools)
        path = os.path.join(out_dir, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"wrote {name}")


if __name__ == "__main__":
    main()
