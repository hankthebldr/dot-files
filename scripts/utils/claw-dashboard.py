#!/usr/bin/env python3
"""claw-dashboard — the Open Claw login dashboard (polished, centered).

A framed, horizontally-centered dashboard: the CRISP system logo (Apple on
macOS, distro on Linux — pulled straight from fastfetch, not a sparse ASCII
placeholder) beside a dense two-column info grid and btop-style resource bars
(CPU / Mem / Swap / Disk / Battery, green→amber→red gradient).

Data + utilization percentages come from scripts/utils/ff-readout.sh `fields`
(the same fast, cross-platform probe the shell readout uses). Colors follow the
active Open Claw theme (config/themes/<slug>.theme — single source of truth).

Usage: claw-dashboard.py        (auto width; degrades cleanly without color/tty)
"""
from __future__ import annotations
import os, re, shutil, subprocess, sys, datetime, platform, json, stat

DOTS = os.environ.get("DOTFILES_DIR", os.path.expanduser("~/.dotfiles"))

# ── Palette (active theme — single source of truth) ──────────────────────────
def rgb(r, g, b): return f"\033[38;2;{r};{g};{b}m"
RST = "\033[0m"; BOLD = "\033[1m"

def load_palette():
    state = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
    slug = "refined-dark"
    try:
        af = os.path.join(state, "claw", "theme")
        if os.path.isfile(af):
            slug = (open(af).read().strip() or slug).splitlines()[0]
    except Exception:
        pass
    # Theme palette path: prefer the subdir library layout
    # (config/themes/<slug>/palette.theme), fall back to the legacy flat file
    # (config/themes/<slug>.theme) so both layouts resolve.
    def _palette_path(s):
        nested = f"{DOTS}/config/themes/{s}/palette.theme"
        return nested if os.path.isfile(nested) else f"{DOTS}/config/themes/{s}.theme"
    # Session override (same precedence as theme.sh): CLAW_THEME env beats the
    # persisted state file — this is how profile loads re-theme the dashboard.
    env_slug = os.environ.get("CLAW_THEME", "").strip()
    if env_slug and os.path.isfile(_palette_path(env_slug)):
        slug = env_slug
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

_ANSI = re.compile(r"\033\[[0-9;?]*[A-Za-z]")
def vis(s): return len(_ANSI.sub("", s))                 # mono-cell display width
def pad(s, w): return s + " "*max(0, w-vis(s))
def _short(s, n): s = s or "—"; return s if len(s) <= n else s[:n-1]+"…"

# ── Nerd Font glyphs (Font Awesome — 1 cell in a *Mono Nerd Font) ────────────
G = dict(os="", host="", kernel="", uptime="", load="",
         shell="", term="", pkgs="", locale="", cpu="", cores="",
         mem="", disk="", ip="", wifi="", batt="", clock="", user="",
         git="", k8s="⎈", docker="",
         tailscale="", tunnel="", cloud="")

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

# ── Logo: the CRISP system logo straight from fastfetch (Apple/distro) ────────
def logo_lines():
    if platform.system() == "Darwin":
        cmd = ["fastfetch", "--logo-type", "builtin", "--logo", "macos", "-s", " "]
    else:                                            # auto-detect the distro logo
        cmd = ["fastfetch", "--logo-type", "builtin", "-s", " "]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=5).stdout
    except Exception:
        out = ""
    if out.strip():
        # strip cursor-positioning / erase escapes, KEEP SGR color (…m)
        cur = re.compile(r"\033\[\??[0-9;]*[A-Za-ln-z]")
        lines = [cur.sub("", ln).rstrip() for ln in out.split("\n")]
        while lines and not _ANSI.sub("", lines[0]).strip(): lines.pop(0)
        while lines and not _ANSI.sub("", lines[-1]).strip(): lines.pop()
        if lines:
            return lines
    # fallback mark if fastfetch is missing
    return [col(r"  /\_/\  ", C["muted"]), col(r" ( o.o ) ", C["muted"]),
            col(r"  > ^ <  ", C["muted"])]

# ── btop-style resource bars (green→amber→red gradient per cell) ──────────────
def _gyr(t, invert=False):
    if invert: t = 1.0 - t
    g=(63,185,80); a=(227,179,65); r=(255,123,114)
    if t < 0.5: u=t/0.5;       c=tuple(round(g[i]+(a[i]-g[i])*u) for i in range(3))
    else:       u=(t-0.5)/0.5; c=tuple(round(a[i]+(r[i]-a[i])*u) for i in range(3))
    return rgb(*c)

def bar(p, width=12, invert=False):
    try: p = max(0, min(100, int(p)))
    except Exception: p = 0
    filled = round(p/100*width)
    if NOCOLOR:
        return "[" + "█"*filled + "░"*(width-filled) + "]"
    cells = []
    for i in range(width):
        t = i/(width-1) if width > 1 else 0
        cells.append((_gyr(t, invert) if i < filled else C["muted"]) +
                     ("█" if i < filled else "░"))
    return col("[", C["muted"]) + "".join(cells) + RST + col("]", C["muted"])

def bar_rows(d):
    SPEC = [("cpu","CPU",False), ("mem","Mem",False), ("swap","Swap",False),
            ("disk","Disk",False), ("batt","Batt",True)]   # batt: full = green
    rows = []
    for f, label, inv in SPEC:
        raw = d.get(f+"_pct", "")
        try: p = int(raw)
        except Exception: p = 0
        rows.append(f"{col(G.get(f,''),C['muted'])} {col(label.ljust(5),C['fg'])} "
                    f"{bar(p, 12, inv)} {col(str(p).rjust(3)+'%', C['muted'])}")
    return rows

# ── Dense two-column info grid (one accent colour per row) ───────────────────
def info_rows(d):
    L = [("os","OS"),("host","Host"),("kernel","Kernel"),("uptime","Up"),
         ("shell","Shell"),("term","Term"),("pkgs","Pkgs"),("locale","Locale")]
    R = [("cpu","CPU"),("cores","Cores"),("mem","Mem"),("disk","Disk"),
         ("ip","IP"),("wifi","WiFi"),("batt","Batt"),("load","Load")]
    ACC = [C["blue"],C["purple"],C["cyan"],C["green"],C["amber"],C["red"],C["blue"],C["green"]]
    rows = []; LW = 25
    for (lf,ll),(rf,rl),acc in zip(L, R, ACC):
        lc = f"{col(G.get(lf,''),acc)} {col(ll.ljust(6),acc)} {col(_short(d.get(lf,''),13),C['fg'])}"
        rc = f"{col(G.get(rf,''),acc)} {col(rl.ljust(5),acc)} {col(_short(d.get(rf,''),14),C['fg'])}"
        rows.append(pad(lc, LW) + col("│ ", C["muted"]) + rc)
    return rows

def palette_dots():
    dots = "".join(col("●", c) for c in (C["blue"],C["green"],C["purple"],C["amber"],
                                         C["red"],C["cyan"],C["muted"],C["fg"]))
    return "  " + dots

# ── Dev context (git / k8s / docker) — only what's present, fast & guarded ────
def _run(cmd, timeout=1.5):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""

def context_lines():
    """One line of live dev context: current git branch (+ dirty marker), the
    active kube-context, and running-container count. Each segment is emitted
    only when its tool/state is actually present, so the row stays empty (and is
    skipped by the caller) on a bare machine."""
    parts = []
    branch = _run(["git", "rev-parse", "--abbrev-ref", "HEAD"])
    if branch and branch != "HEAD":
        dirty = _run(["git", "status", "--porcelain"])
        mark = col("●", C["amber"]) if dirty else col("✓", C["green"])
        parts.append(f"{col(G['git'], C['purple'])} {col(_short(branch, 22), C['fg'])} {mark}")
    if shutil.which("kubectl") and os.path.isfile(os.path.expanduser("~/.kube/config")):
        kctx = _run(["kubectl", "config", "current-context"])
        if kctx:
            parts.append(f"{col(G['k8s'], C['blue'])} {col(_short(kctx, 20), C['fg'])}")
    if shutil.which("docker"):
        ids = _run(["docker", "ps", "-q"])
        if ids:
            n = len([x for x in ids.splitlines() if x.strip()])
            parts.append(f"{col(G['docker'], C['cyan'])} {col(f'{n} running', C['fg'])}")
    return ["   ".join(parts)] if parts else []

# ── Infra context (tailscale / ssh tunnels / cloud identity) ─────────────────
# All local-state reads: a tailscale daemon query (no internet hop), a socket
# stat, and cloud *config files* — never a `sts`/`gcloud`/`az` API round-trip.
def _tunnel_count():
    """Live ControlMaster sockets the tunnel-manager opens in /tmp/ssh-tunnels.
    Counts actual sockets (S_ISSOCK), so plain files left behind don't inflate."""
    d = "/tmp/ssh-tunnels"
    try:
        return sum(1 for f in os.listdir(d)
                   if stat.S_ISSOCK(os.stat(os.path.join(d, f)).st_mode))
    except Exception:
        return 0

def _aws_profile():
    p = os.environ.get("AWS_PROFILE") or os.environ.get("AWS_DEFAULT_PROFILE")
    if p:
        return p
    # No env override → "default" only if a config actually defines it.
    if os.path.isfile(os.path.expanduser("~/.aws/config")) or \
       os.path.isfile(os.path.expanduser("~/.aws/credentials")):
        return "default"
    return ""

def _gcp_project():
    base = os.path.expanduser("~/.config/gcloud")
    try:
        name = open(os.path.join(base, "active_config")).read().strip()
        if not name:
            return ""
        for line in open(os.path.join(base, "configurations", f"config_{name}")):
            if line.strip().startswith("project"):
                return line.split("=", 1)[1].strip()
    except Exception:
        pass
    return ""

def _az_subscription():
    try:
        # azureProfile.json is UTF-8 *with BOM* — utf-8-sig strips it.
        data = json.loads(open(os.path.expanduser("~/.azure/azureProfile.json"),
                               encoding="utf-8-sig").read())
        for s in data.get("subscriptions", []):
            if s.get("isDefault"):
                return s.get("name", "")
    except Exception:
        pass
    return ""

def infra_lines():
    parts = []
    if shutil.which("tailscale"):
        out = _run(["tailscale", "status", "--json"], timeout=1.0)
        if out:
            try:
                ts = json.loads(out)
                if ts.get("BackendState") == "Running":
                    peers = ts.get("Peer") or {}
                    online = sum(1 for p in peers.values() if p.get("Online"))
                    seg = f"{col(G['tailscale'], C['green'])} {col(f'{online}/{len(peers)}', C['fg'])}"
                    if (ts.get("ExitNodeStatus") or {}).get("Online"):
                        seg += col(" ⇄exit", C["amber"])
                    parts.append(seg)
            except Exception:
                pass
    n = _tunnel_count()
    if n:
        parts.append(f"{col(G['tunnel'], C['blue'])} {col(f'{n} tun', C['fg'])}")
    clouds = []
    aws = _aws_profile()
    if aws:               clouds.append(f"aws:{_short(aws, 14)}")
    gcp = _gcp_project()
    if gcp:               clouds.append(f"gcp:{_short(gcp, 18)}")
    az = _az_subscription()
    if az:                clouds.append(f"az:{_short(az, 16)}")
    if clouds:
        parts.append(f"{col(G['cloud'], C['cyan'])} {col('  '.join(clouds), C['fg'])}")
    return ["   ".join(parts)] if parts else []

# ── Homelab fleet (read-only cache; never network) ────────────────────────────
def _homelab_cache():
    """Load the homelab fleet cache, or None. Pure file read; never raises."""
    try:
        cache = os.path.join(
            os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
            "claw", "homelab.json")
        with open(cache, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _age_suffix(ts):
    """' updated 23s ago' / ' stale 7m ago'; '' if unparseable. Stale > 5 min."""
    try:
        t = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=datetime.timezone.utc)
        secs = int((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds())
        secs = max(0, secs)
        human = f"{secs}s" if secs < 60 else f"{secs // 60}m"
        stale = secs > 300
        word = "stale" if stale else "updated"
        return (f" {word} {human} ago", stale)
    except Exception:
        return ("", False)


def homelab_lines():
    """Live HR-TRUST fleet rows read from ~/.cache/claw/homelab.json (no network).
    Returns [] when the cache is absent so the caller drops the block on machines
    that aren't homelab cockpits. Up=green ●, down=red ●, degraded/stale=amber ●."""
    data = _homelab_cache()
    if not data or not isinstance(data.get("machines"), list) or not data["machines"]:
        return []
    suffix, stale = _age_suffix(data.get("ts", ""))
    dot_up = col("●", C["amber"] if stale else C["green"])
    dot_down = col("●", C["red"])
    dot_deg = col("●", C["amber"])

    def dot(state):
        return dot_down if state == "down" else (dot_deg if state == "degraded" else dot_up)

    rows = []
    # access-level context line: github identity + tailscale route
    head = []
    gh = (data.get("identity") or {}).get("github") or {}
    if gh.get("user"):
        head.append(f"{col(G['git'], C['purple'])} {col(_short(gh['user'], 18), C['fg'])} {dot(gh.get('state'))}")
    route = data.get("route") or {}
    if route.get("path"):
        head.append(f"{col(G['tailscale'], C['green'])} {col(_short(route['path'], 28), C['fg'])}")
    if head:
        rows.append("   ".join(head))
    # one row per machine: host dot + nested service dots
    for m in data["machines"]:
        segs = [f"{col(G['host'], C['blue'])} {col(_short(m.get('id', '?'), 12), C['fg'])} {dot(m.get('state'))}"]
        for s in (m.get("services") or []):
            segs.append(f"{dot(s.get('state'))} {col(_short(s.get('id', '?'), 10), C['muted'])}")
        rows.append("  ".join(segs))
    if suffix:
        rows.append(col(suffix.strip(), C["muted"]))
    return rows

# ── Compose: logo | (header + info + bars), framed, centered ─────────────────
def main():
    d = fields()
    user = os.environ.get("USER", "")
    host = d.get("host", "") or os.uname().nodename
    when = datetime.datetime.now().strftime("%a %b %d · %H:%M")
    up = d.get("uptime", "")

    logo = logo_lines()
    header = [
        f"{col(G['user'],C['green'])} {col(f'{user}@{host}', C['green'])}",
        f"{col(G['clock'],C['muted'])} {col(when, C['muted'])}"
        + (f"  {col('· up '+up, C['muted'])}" if up else ""),
    ]
    body = header + [""] + info_rows(d) + [""] + bar_rows(d)
    ctx = [l for l in context_lines() + infra_lines() + homelab_lines() if l]   # dev + infra + homelab rows
    if ctx:
        body += [""] + ctx
    body += ["", palette_dots()]

    # merge logo (left) with body (right), vertically centered against each other
    lw = max((vis(l) for l in logo), default=0) + 3
    pad_top = max(0, (len(body) - len(logo)) // 2)
    lpad_top = max(0, (len(logo) - len(body)) // 2)
    n = max(len(logo) + lpad_top, len(body) + pad_top)
    merged = []
    for i in range(n):
        li = i - lpad_top
        bi = i - pad_top
        lft = pad(logo[li] if 0 <= li < len(logo) else "", lw)
        rgt = body[bi] if 0 <= bi < len(body) else ""
        merged.append((lft + rgt).rstrip())

    # One inner width shared by all three borders so the right edge lines up:
    # content row = "│" + " " + content(content_w) + " " + "│"  → inner = content_w + 2
    # top         = "╭" + "─" + title + "─"*dash + "╮"          → inner = content_w + 2
    # bottom      = "╰" + "─"*inner + "╯"                        → inner = content_w + 2
    quickref = "--quickref" in sys.argv
    qr = quickref_rows() if quickref else []
    # shared width across BOTH boxes so the quickref frame aligns flush with
    # the dashboard frame above it.
    content_w = max((vis(m) for m in merged + qr), default=20)

    term = shutil.get_terminal_size((100, 30)).columns
    margin = " " * max(0, (term - (content_w + 4)) // 2)

    print()
    frame(merged, " OPEN CLAW ", content_w, margin)
    if quickref:
        frame(qr, " Daily Driver ", content_w, margin)

def frame(lines, title_text, content_w, margin):
    """Print one framed, centered box. All boxes in a run share content_w."""
    inner = content_w + 2
    title = col(title_text, C["green"])
    dash = max(0, inner - 1 - vis(title))
    bar_ch = col("│", C["muted"])
    print(margin + col("╭─", C["muted"]) + title + col("─"*dash + "╮", C["muted"]))
    for m in lines:
        print(margin + bar_ch + " " + pad(m, content_w) + " " + bar_ch)
    print(margin + col("╰" + "─"*inner + "╯", C["muted"]))

def quickref_rows():
    """The Daily Driver quick-reference, rendered with the dashboard's own
    width engine (replaces the hand-padded zsh box whose right edge jittered)."""
    SECTIONS = [
        ("Navigate", C["green"],  [("z","smart cd"),("Ctrl+R","history"),("Ctrl+T","find files")]),
        ("Files",    C["blue"],   [("ls","eza"),("cat","bat"),("find","fd"),("grep","rg"),("diff","delta")]),
        ("Network",  C["amber"],  [("netcheck","diag"),("ports","listen"),("myip",""),("dns",""),("headers","")]),
        ("Tools",    C["red"],    [("tun","tunnels"),("glg","lazygit"),("lzd","docker"),("fkill","")]),
        ("System",   C["purple"], [("top","btop"),("df","duf"),("du","dust"),("reload",""),("update","")]),
    ]
    rows = [""]
    for label, accent, pairs in SECTIONS:
        cells = "  ".join(
            col(cmd, C["fg"]) + (f" {col(desc, C['muted'])}" if desc else "")
            for cmd, desc in pairs
        )
        rows.append(f"{col(label.ljust(9), accent)} {cells}")
    rows += ["", col("type ", C["muted"]) + col("default-help", C["fg"]) + col(" for the full reference", C["muted"])]
    return rows

if __name__ == "__main__":
    main()
