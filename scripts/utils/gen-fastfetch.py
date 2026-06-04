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

# GitHub macOS Dark palette (truecolor ANSI)
PURPLE = "38;2;188;140;255"
BLUE   = "38;2;88;166;255"
GREEN  = "38;2;63;185;80"
ORANGE = "38;2;210;153;34"
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
        mod("physicaldisk", "drive", "Drive", ORANGE),
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
CONFIGS = {
    "config.jsonc":         (placeholder_logo("logo.txt", OPENCLAW_COLORS), BLUE, PURPLE, None),
    "config-default.jsonc": (placeholder_logo("logo-default.txt", APPLE_COLORS), BLUE, GREEN, None),
    "config-cloud.jsonc":   (file_logo("cloud"),    ORANGE,            PURPLE, CLOUD),
    "config-security.jsonc":(file_logo("security"),  RED,              PURPLE, SECURITY),
    "config-devops.jsonc":  (file_logo("devops"),    GREEN,            PURPLE, DEVOPS),
    "config-ai.jsonc":      (file_logo("ai"),        PURPLE,           GREEN,  AI),
    "config-research.jsonc":(file_logo("research"),  ORANGE,           BLUE,   RESEARCH),
    "config-cortex.jsonc":  (file_logo("cortex"),    "38;2;255;102;0", RED,    CORTEX),
    "config-local.jsonc":   (file_logo("local"),     GREEN,            BLUE,   None),
}


def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "..",
                           "config", ".config", "fastfetch")
    out_dir = os.path.abspath(out_dir)
    for name, (logo, keys, title, tools) in CONFIGS.items():
        cfg = build(logo, keys, title, tools)
        path = os.path.join(out_dir, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"wrote {name}")


if __name__ == "__main__":
    main()
