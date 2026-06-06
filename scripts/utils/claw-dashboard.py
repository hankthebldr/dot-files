#!/usr/bin/env python3
"""claw-dashboard — the Open Claw login dashboard.

A self-contained, fully-controlled replacement for the fastfetch command-module
readout (which rendered an ugly "Command" label on every row). Renders a framed,
icon-rich, gradient two-column system dashboard with a logo. Data comes from
scripts/utils/ff-readout.sh `fields` (the same cross-platform probe the shell
readout uses). No fastfetch dependency.

Usage: claw-dashboard.py            (auto-detects width; degrades without color)
"""
from __future__ import annotations
import os, re, shutil, subprocess, sys, datetime

# ── GitHub macOS Dark palette ────────────────────────────────────────────────
def rgb(r, g, b): return f"\033[38;2;{r};{g};{b}m"
RST = "\033[0m"; BOLD = "\033[1m"
BLUE=(88,166,255); GREEN=(63,185,80); PURPLE=(188,140,255); ORANGE=(210,153,34)
RED=(255,123,114); MUTED=(139,148,158); FG=(201,209,217); CYAN=(57,200,255)
C = {k: rgb(*v) for k, v in dict(blue=BLUE,green=GREEN,purple=PURPLE,orange=ORANGE,
                                 red=RED,muted=MUTED,fg=FG,cyan=CYAN).items()}
NOCOLOR = bool(os.environ.get("NO_COLOR")) or not sys.stdout.isatty()
def col(s, c): return s if NOCOLOR else f"{c}{s}{RST}"
def grad(text, a, b):
    if NOCOLOR or not text: return text
    n = max(1, len(text)-1); out=[]
    for i, ch in enumerate(text):
        t=i/n; r=round(a[0]+(b[0]-a[0])*t); g=round(a[1]+(b[1]-a[1])*t); bl=round(a[2]+(b[2]-a[2])*t)
        out.append(rgb(r,g,bl)+ch)
    return "".join(out)+RST

_ANSI = re.compile(r"\033\[[0-9;]*m")
def vis(s): return len(_ANSI.sub("", s))                  # mono-cell display width
def pad(s, w): return s + " "*max(0, w-vis(s))

# ── Nerd Font glyphs (Font Awesome — 1 cell in a *Mono Nerd Font) ────────────
G = dict(os="", host="", kernel="", uptime="", load="",
         shell="", term="", pkgs="", cpu="", cores="",
         mem="", disk="", ip="", wifi="", batt="",
         clock="", user="", paw="")

def fields():
    dots = os.environ.get("DOTFILES_DIR", os.path.expanduser("~/.dotfiles"))
    try:
        out = subprocess.run(["bash", f"{dots}/scripts/utils/ff-readout.sh", "fields"],
                             capture_output=True, text=True, timeout=8).stdout
    except Exception:
        out = ""
    d = {}
    for line in out.splitlines():
        if "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d

# ── Logo: the SYSTEM logo (Apple on macOS, distro on Linux), gradient-colored ─
import platform
APPLE_CMAP = {"1":(255,140,0), "2":(245,200,66), "3":GREEN, "4":RED, "5":PURPLE, "6":BLUE}
_PLACE = re.compile(r"\$([1-9])")

def _render_placeholder(path, cmap):
    """Render a fastfetch $N-placeholder logo file into truecolor ANSI lines."""
    raw = open(path, encoding="utf-8").read().rstrip("\n")
    out = []
    for ln in raw.split("\n"):
        if NOCOLOR:
            out.append(_PLACE.sub("", ln)); continue
        out.append(_PLACE.sub(lambda m: rgb(*cmap.get(m.group(1), FG)), ln) + RST)
    return out

def logo_lines():
    dots = os.environ.get("DOTFILES_DIR", os.path.expanduser("~/.dotfiles"))
    # macOS → the Apple logo we already ship (logo-default.txt, $N placeholders).
    if platform.system() == "Darwin":
        p = f"{dots}/config/.config/fastfetch/logo-default.txt"
        if os.path.isfile(p):
            try: return [""] + _render_placeholder(p, APPLE_CMAP) + [""]
            except Exception: pass
    # Linux → a compact gradient Tux; other → minimal mark.
    tux = ["", grad("    .--.   ", FG, MUTED), grad("   |o_o |  ", FG, MUTED),
           grad("   |:_/ |  ", ORANGE, ORANGE), grad("  //   \\ \\ ", FG, MUTED),
           grad(" (|     | )", FG, MUTED), grad("/'\\_   _/`\\ ", ORANGE, ORANGE),
           grad("\\___)=(___/ ", ORANGE, ORANGE), ""]
    return tux

# ── Two-column info grid ─────────────────────────────────────────────────────
def cell(glyph, label, value, accent):
    if not value or value == "n/a":
        value = col("—", C["muted"])
    else:
        value = col(value, C["fg"])
    return f"{col(glyph, accent)} {col(label.ljust(6), C['muted'])} {value}"

def grid(d):
    # (glyph, label, field, accent) — left col / right col
    L = [("os","OS","os",C["purple"]), ("host","Host","host",C["purple"]),
         ("kernel","Kernel","kernel",C["blue"]), ("uptime","Up","uptime",C["blue"]),
         ("shell","Shell","shell",C["green"]), ("term","Term","term",C["green"])]
    R = [("cpu","CPU","cpu",C["blue"]), ("cores","Cores","cores",C["blue"]),
         ("mem","Mem","mem",C["green"]), ("disk","Disk","disk",C["orange"]),
         ("ip","IP","ip",C["cyan"]), ("wifi","WiFi","wifi",C["cyan"])]
    rows=[]
    lw = 26  # left-cell display width before the divider
    for (lg,ll,lf,la),(rg,rl,rf,ra) in zip(L,R):
        lc = cell(G[lg], ll, _short(d.get(lf,""),13), la)
        rc = cell(G[rg], rl, _short(d.get(rf,""),15), ra)
        rows.append(pad(lc, lw) + col("│ ", C["muted"]) + rc)
    return rows

def _short(s, n): return s if len(s) <= n else s[:n-1]+"…"

def palette():
    dots = "".join(col("●", c) for c in (C["blue"],C["green"],C["purple"],C["orange"],
                                         C["red"],C["cyan"],C["muted"],C["fg"]))
    return "  " + dots

# ── Compose + frame ──────────────────────────────────────────────────────────
def main():
    d = fields()
    user = os.environ.get("USER","")
    host = d.get("host","") or os.uname().nodename
    when = datetime.datetime.now().strftime("%a %b %d · %H:%M")
    up = d.get("uptime","")

    logo = logo_lines()
    header = [
        f"{col(G['user'],C['green'])} {grad(f'{user}@{host}', GREEN, CYAN)}",
        f"{col(G['clock'],C['muted'])} {col(when, C['muted'])}" + (f"  {col('· up '+up, C['muted'])}" if up else ""),
        col("─"*42, C["muted"]),
    ]
    body = header + grid(d) + ["", palette()]

    # merge logo (left) with body (right), row by row
    lw = max(vis(l) for l in logo) + 2
    n = max(len(logo), len(body))
    merged=[]
    for i in range(n):
        lft = pad(logo[i] if i < len(logo) else "", lw)
        rgt = body[i] if i < len(body) else ""
        merged.append("  " + lft + rgt)

    width = max(vis(m) for m in merged) + 2
    title = grad(" OPEN CLAW ", BLUE, GREEN)
    tlen = vis(title)
    top = col("╭─", C["muted"]) + title + col("─"*(width-2-tlen) + "╮", C["muted"])
    bot = col("╰" + "─"*width + "╯", C["muted"])
    bar = col("│", C["muted"])
    print()
    print("  " + top)
    for m in merged:
        print("  " + bar + " " + pad(m[2:], width-1) + bar)
    print("  " + bot)
    print()

if __name__ == "__main__":
    main()
