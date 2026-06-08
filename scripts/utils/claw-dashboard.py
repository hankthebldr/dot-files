#!/usr/bin/env python3
"""claw-dashboard — the Open Claw login dashboard.

A self-contained, fully-controlled replacement for the fastfetch command-module
readout (which rendered an ugly "Command" label on every row). Renders a framed,
icon-rich, multi-colored two-column system dashboard beside the system logo,
horizontally centered in the terminal. Data comes from
scripts/utils/ff-readout.sh `fields` (the same cross-platform probe the shell
readout uses). Colors come from the ACTIVE Open Claw theme
(config/themes/<slug>.theme) — the single source of truth. No fastfetch dep.

Usage: claw-dashboard.py            (auto-detects width; degrades without color)
"""
from __future__ import annotations
import os, re, shutil, subprocess, sys, datetime, platform

DOTS = os.environ.get("DOTFILES_DIR", os.path.expanduser("~/.dotfiles"))

# ── Palette (loaded from the active theme — single source of truth) ──────────
def rgb(r, g, b): return f"\033[38;2;{r};{g};{b}m"
RST = "\033[0m"; BOLD = "\033[1m"

def load_palette():
    """Resolve the active theme and parse its palette.theme → rgb dict.

    Each theme is a library dir: config/themes/<slug>/palette.theme. Falls back
    to the legacy flat config/themes/<slug>.theme for half-migrated checkouts.
    """
    state = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
    slug = "refined-dark"
    try:
        af = os.path.join(state, "claw", "theme")
        if os.path.isfile(af):
            slug = (open(af).read().strip() or slug).splitlines()[0]
    except Exception:
        pass

    def _palette_path(s):
        nested = f"{DOTS}/config/themes/{s}/palette.theme"
        return nested if os.path.isfile(nested) else f"{DOTS}/config/themes/{s}.theme"

    tf = _palette_path(slug)
    if not os.path.isfile(tf):
        tf = _palette_path("refined-dark")
    pal = {}
    try:
        for line in open(tf, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k in ("name", "slug"):
                continue
            v = v.strip().lstrip("#")
            if len(v) == 6:
                pal[k] = (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))
    except Exception:
        pass
    base = dict(blue=(88,166,255), green=(63,185,80), purple=(188,140,255),
                amber=(227,179,65), red=(255,123,114), muted=(139,148,158),
                fg=(201,209,217), cyan=(57,197,255))
    base.update(pal)
    return base

PAL = load_palette()
BLUE=PAL["blue"]; GREEN=PAL["green"]; PURPLE=PAL["purple"]; AMBER=PAL["amber"]
RED=PAL["red"]; MUTED=PAL["muted"]; FG=PAL["fg"]; CYAN=PAL["cyan"]
C = {k: rgb(*v) for k, v in dict(blue=BLUE, green=GREEN, purple=PURPLE, amber=AMBER,
                                 red=RED, muted=MUTED, fg=FG, cyan=CYAN).items()}
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
G = dict(os="", host="", kernel="", uptime="", load="",
         shell="", term="", pkgs="", cpu="", cores="",
         mem="", disk="", ip="", wifi="", batt="",
         clock="", user="", paw="")

def fields():
    try:
        out = subprocess.run(["bash", f"{DOTS}/scripts/utils/ff-readout.sh", "fields"],
                             capture_output=True, text=True, timeout=8).stdout
    except Exception:
        out = ""
    d = {}
    for line in out.splitlines():
        if "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d

# ── Logo: the SYSTEM logo (Apple on macOS, distro on Linux), gradient-colored ─
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
    # macOS → the Apple logo we already ship (logo-default.txt, $N placeholders).
    if platform.system() == "Darwin":
        p = f"{DOTS}/config/.config/fastfetch/logo-default.txt"
        if os.path.isfile(p):
            try: return [""] + _render_placeholder(p, APPLE_CMAP) + [""]
            except Exception: pass
    # Linux → a compact gradient Tux; other → minimal mark.
    tux = ["", grad("    .--.   ", FG, MUTED), grad("   |o_o |  ", FG, MUTED),
           grad("   |:_/ |  ", AMBER, AMBER), grad("  //   \\ \\ ", FG, MUTED),
           grad(" (|     | )", FG, MUTED), grad("/'\\_   _/`\\ ", AMBER, AMBER),
           grad("\\___)=(___/ ", AMBER, AMBER), ""]
    return tux

# ── Two-column info grid — one accent colour per LINE (multi-coloured rows) ──
def cell(glyph, label, value, accent):
    if not value or value == "n/a":
        value = col("—", C["muted"])
    else:
        value = col(value, C["fg"])
    return f"{col(glyph, accent)} {col(label.ljust(6), accent)} {value}"

def grid(d):
    # (glyph, label, field) for left & right columns; one accent per row so each
    # line reads in its own colour (blue→purple→cyan→green→amber→red).
    ROWS = [
        (("os","OS","os"),             ("cpu","CPU","cpu")),
        (("host","Host","host"),       ("cores","Cores","cores")),
        (("kernel","Kernel","kernel"), ("mem","Mem","mem")),
        (("uptime","Up","uptime"),     ("disk","Disk","disk")),
        (("shell","Shell","shell"),    ("ip","IP","ip")),
        (("term","Term","term"),       ("wifi","WiFi","wifi")),
    ]
    ACCENTS = [C["blue"], C["purple"], C["cyan"], C["green"], C["amber"], C["red"]]
    rows=[]; lw = 26  # left-cell display width before the divider
    for ((lg,ll,lf),(rg,rl,rf)), accent in zip(ROWS, ACCENTS):
        lc = cell(G[lg], ll, _short(d.get(lf,""),13), accent)
        rc = cell(G[rg], rl, _short(d.get(rf,""),15), accent)
        rows.append(pad(lc, lw) + col("│ ", C["muted"]) + rc)
    return rows

def _short(s, n): return s if len(s) <= n else s[:n-1]+"…"

def palette():
    dots = "".join(col("●", c) for c in (C["blue"],C["green"],C["purple"],C["amber"],
                                         C["red"],C["cyan"],C["muted"],C["fg"]))
    return "  " + dots

# ── Compose + frame + center ─────────────────────────────────────────────────
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
        merged.append(lft + rgt)

    width = max(vis(m) for m in merged) + 2
    title = grad(" OPEN CLAW ", BLUE, GREEN)
    tlen = vis(title)
    top = col("╭─", C["muted"]) + title + col("─"*(width-2-tlen) + "╮", C["muted"])
    bot = col("╰" + "─"*width + "╯", C["muted"])
    bar = col("│", C["muted"])

    # horizontal centering — pad every framed line to the terminal centre.
    term = shutil.get_terminal_size((80, 24)).columns
    box_w = width + 4                       # borders + the leading "│ "
    margin = " " * max(0, (term - box_w) // 2)

    print()
    print(margin + top)
    for m in merged:
        print(margin + bar + " " + pad(m, width-1) + bar)
    print(margin + bot)
    print()

if __name__ == "__main__":
    main()
