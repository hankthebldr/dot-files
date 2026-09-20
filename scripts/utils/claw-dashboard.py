#!/usr/bin/env python3
"""claw-dashboard — the Open Claw login card and profile card.

ONE render engine (frame() / vis() / _clip()), two modes:

  --login          the daily card: header, segments, bars, attention
  --profile KEY    the profile card: profile logo, class/tag, key tools, bars

Data path (audit F-12): ONE "fastfetch --format json" call (~30 ms) instead of
ff-readout.sh fields (~250 ms / ~140 forks), plus pure cache reads. No live
docker / tailscale / kubectl probe ever runs here — tailscale comes from
situation.json, the fleet from homelab.json, both written by situation.sh.
--json-fixture PATH feeds a recorded payload (CI has no fastfetch); when
fastfetch is missing or fails, _stdlib_probe() fills in what the standard
library can see, and the card still renders.

Payload (audit F-09): presence-driven segment_rows() with a show_if per row
instead of a fixed 16-cell grid whose 10 static laptop facts now live in
"claw specs". Header is "user@nodename - model - net - date - time - up".

Colors follow the active Open Claw theme: CLAW_C_* from the environment when
theme.sh has already been loaded, else the palette file — never a literal.
"""
from __future__ import annotations
import argparse, datetime, json, os, platform, re, shutil, stat, subprocess, sys

DOTS = os.environ.get("DOTFILES_DIR", os.path.expanduser("~/.dotfiles"))
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME",
                                    os.path.expanduser("~/.cache")), "claw")

# ── Palette (active theme — single source of truth) ──────────────────────────
def rgb(r, g, b): return f"\033[38;2;{r};{g};{b}m"
RST = "\033[0m"; BOLD = "\033[1m"

_BASE = dict(blue=(88, 166, 255), green=(63, 185, 80), purple=(188, 140, 255),
             amber=(227, 179, 65), red=(255, 123, 114), muted=(139, 148, 158),
             fg=(201, 209, 217), cyan=(57, 197, 255))


def _hex2rgb(v):
    v = (v or "").strip().lstrip("#")
    if len(v) != 6:
        return None
    try:
        return (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))
    except ValueError:
        return None


def _palette_path(slug):
    """Prefer the subdir library layout, fall back to the legacy flat file."""
    nested = f"{DOTS}/config/themes/{slug}/palette.theme"
    return nested if os.path.isfile(nested) else f"{DOTS}/config/themes/{slug}.theme"


def load_palette():
    """The active palette as {key: (r,g,b)}.

    Env first (audit F-11): when theme.sh has already exported the palette into
    this process (CLAW_C_BG present), read CLAW_C_* and fork/parse nothing.
    Otherwise parse the palette file with theme.sh's own precedence
    (CLAW_THEME session override, persisted state, refined-dark).
    """
    pal = {}
    if os.environ.get("CLAW_C_BG"):
        for k in _BASE:
            c = _hex2rgb(os.environ.get("CLAW_C_" + k.upper(), ""))
            if c:
                pal[k] = c
        if pal:
            return dict(_BASE, **pal)
    state = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
    slug = "refined-dark"
    try:
        af = os.path.join(state, "claw", "theme")
        if os.path.isfile(af):
            slug = (open(af).read().strip() or slug).splitlines()[0]
    except Exception:
        pass
    env_slug = os.environ.get("CLAW_THEME", "").strip()
    if env_slug and os.path.isfile(_palette_path(env_slug)):
        slug = env_slug
    tf = _palette_path(slug)
    if not os.path.isfile(tf):
        tf = _palette_path("refined-dark")
    try:
        for line in open(tf, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k in ("name", "slug"):
                continue
            c = _hex2rgb(v)
            if c:
                pal[k] = c
    except Exception:
        pass
    return dict(_BASE, **pal)


PAL = load_palette()
C = {k: rgb(*v) for k, v in PAL.items()}
NOCOLOR = bool(os.environ.get("NO_COLOR")) or not sys.stdout.isatty()
def col(s, c): return s if NOCOLOR else f"{c}{s}{RST}"

_ANSI = re.compile(r"\033\[[0-9;?]*[A-Za-z]")
# cursor-positioning / erase codes; everything that is NOT SGR (...m)
_CURSOR = re.compile(r"\033\[\??[0-9;]*[A-Za-ln-z]")
def vis(s): return len(_ANSI.sub("", s))                 # mono-cell display width
def pad(s, w): return s + " " * max(0, w - vis(s))


def _short(s, n):
    s = "—" if s in (None, "") else str(s)
    return s if len(s) <= n else s[:n - 1] + "…"


def _clip(s, w):
    """Truncate s to w VISIBLE cells, preserving ANSI escapes (never cut a code
    mid-sequence) and closing color with a reset if anything was dropped. Lets a
    box degrade gracefully on a terminal narrower than its natural content."""
    if vis(s) <= w:
        return s
    out, shown, i = [], 0, 0
    while i < len(s) and shown < w:
        m = _ANSI.match(s, i)
        if m:
            out.append(m.group()); i = m.end(); continue
        out.append(s[i]); shown += 1; i += 1
    # close any color the cut left open — but not in NOCOLOR (keeps piped output clean)
    return "".join(out) + ("" if NOCOLOR else RST)


# ── Nerd Font glyphs (Font Awesome — 1 cell in a *Mono Nerd Font) ────────────
_OS_GLYPH = "" if platform.system() == "Darwin" else ""
G = dict(os=_OS_GLYPH, machine="", kernel="", uptime="",
         load="", shell="", term="", pkgs="",
         locale="", cpu="", cores="", mem="\U000f035b",
         swap="\U000f035b", disk="", ip="", wifi="",
         batt="", clock="", user="", git="",
         k8s="⎈", docker="", tailscale="", tunnel="",
         cloud="", aws="", gcp="", azure="",
         tool="", book="")


# ── Data: ONE fastfetch JSON call, stdlib fallback ───────────────────────────
FF_MODULES = ("OS:Host:Kernel:Uptime:Shell:CPU:Memory:Swap:Disk:"
              "LocalIp:Wifi:Battery:Loadavg")


def _pct(used, total):
    try:
        used = float(used); total = float(total)
        if total <= 0:
            return None
        return max(0, min(100, int(round(used / total * 100))))
    except Exception:
        return None


def _human_bytes(n):
    try:
        n = float(n)
    except Exception:
        return ""
    for unit in ("B", "K", "M", "G", "T"):
        if n < 1024 or unit == "T":
            return f"{n:.0f}{unit}" if unit in ("B", "K") else f"{n:.1f}{unit}"
        n /= 1024
    return ""


def fmt_uptime(secs):
    """'2h49m' / '3d4h' / '41m'. Seconds in, never the raw kern.boottime text
    that F-04's greedy regex turned into '20708d'."""
    try:
        s = int(secs)
    except Exception:
        return ""
    if s < 0:
        return ""
    d, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    m = s // 60
    if d:
        return f"{d}d{h}h"
    if h:
        return f"{h}h{m}m"
    return f"{m}m"


def _ff_raw(fixture=None):
    """The fastfetch JSON payload as a list, or [] when unavailable."""
    if fixture:
        try:
            with open(fixture, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []
    if not shutil.which("fastfetch"):
        return []
    try:
        r = subprocess.run(["fastfetch", "--format", "json", "-s", FF_MODULES],
                           capture_output=True, text=True, timeout=3)
        return json.loads(r.stdout) if r.stdout.strip() else []
    except Exception:
        return []


def _stdlib_probe():
    """What the standard library alone can see. Used when fastfetch is missing
    (Ubuntu CI) or fails. Partial data is fine — the card still renders."""
    d = {}
    try:
        un = os.uname()
        d["host"] = un.nodename
        d["kernel"] = un.release
        d["os"] = f"{un.sysname} {un.release}"
    except Exception:
        pass
    d["ncpu"] = os.cpu_count() or 0
    try:
        d["load1"] = round(os.getloadavg()[0], 2)
    except Exception:
        pass
    try:
        du = shutil.disk_usage("/")
        d["disk_pct"] = _pct(du.used, du.total)
    except Exception:
        pass
    if platform.system() == "Linux":
        try:
            meminfo = {}
            for line in open("/proc/meminfo"):
                k, _, v = line.partition(":")
                meminfo[k.strip()] = int(v.strip().split()[0])
            total = meminfo.get("MemTotal", 0)
            avail = meminfo.get("MemAvailable", meminfo.get("MemFree", 0))
            d["mem_pct"] = _pct(total - avail, total)
            d["swap_used"] = (meminfo.get("SwapTotal", 0)
                              - meminfo.get("SwapFree", 0)) * 1024
        except Exception:
            pass
        try:
            d["uptime_s"] = int(float(open("/proc/uptime").read().split()[0]))
        except Exception:
            pass
    elif platform.system() == "Darwin":
        # ONE sysctl call for both facts. "sec =" is anchored with \b so it
        # cannot match "usec =" — that greedy match was audit F-04.
        try:
            out = subprocess.run(["sysctl", "-n", "hw.memsize", "kern.boottime"],
                                 capture_output=True, text=True, timeout=2).stdout
            lines = out.splitlines()
            if lines and lines[0].strip().isdigit():
                d["mem_total"] = int(lines[0].strip())
            m = re.search(r"\bsec\s*=\s*(\d+)", out)
            if m:
                import time
                d["uptime_s"] = max(0, int(time.time()) - int(m.group(1)))
        except Exception:
            pass
    return d


def ff_json(fixture=None):
    """The render's single system-facts dict.

    Keys: os model host kernel uptime_s uptime shell cpu ncpu cores mem_pct
    swap_used swap_pct disk_pct ip ssid batt_pct batt_status load1 load
    load_ratio. Every access into the fastfetch payload uses .get with a
    default, so a module fastfetch could not answer simply goes missing.
    """
    raw = _ff_raw(fixture)
    mods = {}
    for entry in raw if isinstance(raw, list) else []:
        if isinstance(entry, dict) and "type" in entry:
            mods[entry["type"]] = entry.get("result")

    d = {}
    if not mods:
        d.update(_stdlib_probe())
    else:
        osr = mods.get("OS") or {}
        d["os"] = osr.get("prettyName") or osr.get("name") or ""
        d["model"] = (mods.get("Host") or {}).get("name") or ""
        # F-09: the header name is the NODENAME, never hw.model — the grid read
        # "henry@Mac16,7" because ff-readout sourced it from the hardware id.
        try:
            d["host"] = os.uname().nodename
        except Exception:
            d["host"] = platform.node()
        d["kernel"] = (mods.get("Kernel") or {}).get("release") or ""
        # Uptime.uptime is MILLISECONDS.
        upms = (mods.get("Uptime") or {}).get("uptime")
        if isinstance(upms, (int, float)):
            d["uptime_s"] = int(upms // 1000)
        sh = mods.get("Shell") or {}
        d["shell"] = sh.get("prettyName") or sh.get("exeName") or ""
        cpu = mods.get("CPU") or {}
        d["cpu"] = cpu.get("cpu") or ""
        cores = cpu.get("cores") or {}
        d["ncpu"] = cores.get("logical") or cores.get("online") or os.cpu_count() or 0
        mem = mods.get("Memory") or {}
        d["mem_pct"] = _pct(mem.get("used"), mem.get("total"))
        d["mem_total"] = mem.get("total")
        swaps = mods.get("Swap") or []
        if isinstance(swaps, dict):
            swaps = [swaps]
        if swaps:
            d["swap_used"] = swaps[0].get("used") or 0
            d["swap_pct"] = _pct(swaps[0].get("used"), swaps[0].get("total"))
        disks = mods.get("Disk") or []
        for entry in disks if isinstance(disks, list) else []:
            if entry.get("mountpoint") == "/":
                b = entry.get("bytes") or {}
                d["disk_pct"] = _pct(b.get("used"), b.get("total"))
                break
        ips = mods.get("LocalIp") or []
        for entry in ips if isinstance(ips, list) else []:
            dr = entry.get("defaultRoute")
            ok = dr is True or (isinstance(dr, dict) and dr.get("ipv4"))
            if ok and entry.get("ipv4"):
                d["ip"] = str(entry["ipv4"]).split("/")[0]
                break
        wifi = mods.get("Wifi") or []
        if isinstance(wifi, list) and wifi:
            d["ssid"] = ((wifi[0].get("conn") or {}).get("ssid") or "")
        batt = mods.get("Battery") or []
        if isinstance(batt, list) and batt:
            cap = batt[0].get("capacity")
            if isinstance(cap, (int, float)):
                d["batt_pct"] = int(round(cap))
            st = batt[0].get("status")
            d["batt_status"] = (st[0] if isinstance(st, list) and st else (st or "")) or ""
        la = mods.get("Loadavg") or []
        if isinstance(la, list) and la:
            try:
                d["load1"] = round(float(la[0]), 2)
            except Exception:
                pass

    # ── derived / legacy keys the bar + load renderers consume ──────────────
    if d.get("uptime_s") is not None:
        d["uptime"] = fmt_uptime(d["uptime_s"])
    ncpu = d.get("ncpu") or 0
    d["cores"] = str(ncpu) if ncpu else ""
    if d.get("load1") is not None:
        d["load"] = str(d["load1"])
        if ncpu:
            d["load_ratio"] = f"{d['load1'] / ncpu:.2f}"
    if d.get("batt_pct") is not None:
        d["batt"] = f"{d['batt_pct']}%" + (f" {d['batt_status']}" if d.get("batt_status") else "")
    if d.get("swap_used") and not d.get("swap_pct"):
        d["swap_pct"] = 0
    return d


# ── Cached state (situation.sh writes these; the render only reads) ──────────
def _cache_json(name):
    """Read the named JSON out of the claw cache dir, or None. Never raises."""
    try:
        with open(os.path.join(CACHE, name), encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _run(cmd, timeout=1.5):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


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
    # No env override: "default" only if a config actually defines it.
    base = os.path.join(os.path.expanduser("~"), ".aws")
    if os.path.isfile(os.path.join(base, "config")) or \
       os.path.isfile(os.path.join(base, "credentials")):
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


def _git_ctx():
    """'<branch> dot|check' when cwd is inside a repo that is not the home dir,
    else ''. Two short git calls, and only then — the old context_lines() ran
    them on every render alongside docker/kubectl/tailscale (audit F-12)."""
    try:
        cwd = os.getcwd()
    except Exception:
        return ""
    home = os.path.expanduser("~")
    try:
        if os.path.realpath(cwd) == os.path.realpath(home):
            return ""
    except Exception:
        pass
    p = cwd
    while True:
        if os.path.exists(os.path.join(p, ".git")):
            break
        nxt = os.path.dirname(p)
        if nxt == p:
            return ""
        p = nxt
    branch = _run(["git", "rev-parse", "--abbrev-ref", "HEAD"], timeout=1)
    if not branch or branch == "HEAD":
        return ""
    dirty = _run(["git", "status", "--porcelain"], timeout=1)
    return f"{_short(branch, 28)} {'●' if dirty else '✓'}"


def _tailscale_seg():
    """peers_online/peers_total out of situation.json — never a live
    "tailscale status" call (144 ms on the render path, audit F-12)."""
    s = _cache_json("situation.json") or {}
    ts = s.get("tailscale") or {}
    state = ts.get("state")
    if not state or state in ("null", "unknown"):
        return ""
    if state != "Running":
        return str(state)
    on, tot = ts.get("peers_online"), ts.get("peers_total")
    if not tot:
        return "Running"
    return f"{on}/{tot}"


# ── Presence-driven segments (audit F-09) ────────────────────────────────────
def segment_rows(d):
    """[(key, glyph, value, show_if)] — the card's whole variable payload.

    Every row declares its own show_if; the renderer prints only the true ones.
    Nothing static (OS, kernel, CPU model, locale, package counts) is here —
    "claw specs" owns the spec sheet.
    """
    ssid, ip = d.get("ssid", ""), d.get("ip", "")
    batt_pct = d.get("batt_pct")
    batt_status = (d.get("batt_status") or "")
    swap_used = d.get("swap_used") or 0
    tun = _tunnel_count()
    gitv = _git_ctx()
    tsv = _tailscale_seg()
    aws, gcp, az = _aws_profile(), _gcp_project(), _az_subscription()
    return [
        ("model", G["machine"], _short(d.get("model", ""), 42), bool(d.get("model"))),
        ("net", G["wifi"] if ssid else G["ip"], ssid or ip, bool(ssid or ip)),
        ("batt", G["batt"], d.get("batt", ""),
         batt_pct is not None and (batt_pct < 100 or batt_status == "Discharging")),
        ("swap", G["swap"], _human_bytes(swap_used), bool(swap_used)),
        ("git", G["git"], gitv, bool(gitv)),
        ("tun", G["tunnel"], f"{tun} tun", tun > 0),
        ("ts", G["tailscale"], tsv, bool(tsv)),
        ("aws", G["aws"], _short(aws, 20), bool(aws)),
        ("gcp", G["gcp"], _short(gcp, 24), bool(gcp)),
        ("az", G["azure"], _short(az, 22), bool(az)),
    ]


SEG_LABEL = dict(model="Model", net="Net", batt="Batt", swap="Swap", git="Git",
                 tun="Tun", ts="Tailnet", aws="AWS", gcp="GCP", az="Azure")
SEG_ACCENT = dict(model="purple", net="green", batt="amber", swap="cyan",
                  git="purple", tun="blue", ts="green", aws="amber",
                  gcp="blue", az="cyan")


def render_segments(rows, two_col=False, skip=()):
    """Segment cells, content-sized. Two columns only at >=100 cols."""
    cells = []
    for key, glyph, value, show in rows:
        if not show or key in skip:
            continue
        acc = C[SEG_ACCENT.get(key, "blue")]
        cells.append(f"{col(glyph, acc)} {col(SEG_LABEL.get(key, key).ljust(7), acc)} "
                     f"{col(str(value), C['fg'])}")
    if not cells:
        return []
    if not two_col or len(cells) < 2:
        return cells
    half = (len(cells) + 1) // 2
    left, right = cells[:half], cells[half:]
    lw = max(vis(c) for c in left) + 2
    out = []
    for i in range(half):
        r = right[i] if i < len(right) else ""
        out.append((pad(left[i], lw) + (col("│ ", C["muted"]) + r if r else "")).rstrip())
    return out


# ── Logo: the CRISP system logo straight from fastfetch (Apple/distro) ───────
def _strip_cursor(text):
    """Drop cursor-positioning / erase codes, KEEP SGR color (...m)."""
    lines = [_CURSOR.sub("", ln).rstrip() for ln in text.split("\n")]
    while lines and not _ANSI.sub("", lines[0]).strip():
        lines.pop(0)
    while lines and not _ANSI.sub("", lines[-1]).strip():
        lines.pop()
    return lines


def _decolor(lines):
    """NO_COLOR strips SGR from art too — a captured card must be escape-free."""
    return [_ANSI.sub("", ln).rstrip() for ln in lines] if NOCOLOR else lines


def profile_logo(key):
    """The profile's art, SGR-first (audit F-23).

    Two trees carry profile logos: config/.config/fastfetch/logo-<key>.txt (9
    profiles) and shell/profiles/<key>/logo.txt (all 18). Take the first that
    exists AND already carries colour; failing that, tint the first that exists
    with the palette's blue; failing that, the builtin OS mark.
    """
    cands = [os.path.join(DOTS, "config", ".config", "fastfetch", f"logo-{key}.txt"),
             os.path.join(DOTS, "shell", "profiles", key, "logo.txt")]
    first = None
    for p in cands:
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except Exception:
            continue
        if "\033[" in text:
            return _decolor(_strip_cursor(text))
        if first is None:
            first = text
    if first is not None:
        return [col(ln, C["blue"]) for ln in _strip_cursor(first)]
    return builtin_logo()


def builtin_logo():
    """The builtin OS mark. "--pipe false" keeps fastfetch's colour when stdout
    is not a tty (the login card is often captured)."""
    if not shutil.which("fastfetch"):
        return _fallback_mark()
    cmd = ["fastfetch", "--logo-type", "builtin", "--pipe", "false", "-s", " "]
    if platform.system() == "Darwin":
        cmd[3:3] = ["--logo", "macos"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=3).stdout
    except Exception:
        out = ""
    lines = _decolor(_strip_cursor(out)) if out.strip() else []
    return lines or _fallback_mark()


logo_lines = builtin_logo          # kept: the login card's logo entry point


def _fallback_mark():
    return [col(r"  /\_/\  ", C["muted"]), col(r" ( o.o ) ", C["muted"]),
            col(r"  > ^ <  ", C["muted"])]


# ── btop-style resource bars (green to amber to red gradient per cell) ───────
def _gyr(t, invert=False):
    if invert: t = 1.0 - t
    g = PAL["green"]; a = PAL["amber"]; r = PAL["red"]
    if t < 0.5: u = t / 0.5;         c = tuple(round(g[i] + (a[i] - g[i]) * u) for i in range(3))
    else:       u = (t - 0.5) / 0.5; c = tuple(round(a[i] + (r[i] - a[i]) * u) for i in range(3))
    return rgb(*c)


def bar(p, width=12, invert=False):
    try: p = max(0, min(100, int(p)))
    except Exception: p = 0
    filled = round(p / 100 * width)
    if NOCOLOR:
        return "[" + "█" * filled + "░" * (width - filled) + "]"
    cells = []
    for i in range(width):
        t = i / (width - 1) if width > 1 else 0
        cells.append((_gyr(t, invert) if i < filled else C["muted"]) +
                     ("█" if i < filled else "░"))
    return col("[", C["muted"]) + "".join(cells) + RST + col("]", C["muted"])


def load_row(d):
    """Load as TEXT, never a bar (audit F-08: load1/ncpu clamped at 100% drew a
    full red 'CPU' bar at 26.8/14). `Load  <load1>/<ncpu>` in fg; the value turns
    amber at ratio >= 1.0 and red at >= 2.0 — tones from the loaded palette."""
    load1 = (str(d.get("load", "")).split() or [""])[0]
    ncpu = d.get("cores", "")
    try: ratio = float(d.get("load_ratio", ""))
    except Exception: ratio = None
    tone = C["fg"]
    if ratio is not None:
        if ratio >= 2.0:   tone = C["red"]
        elif ratio >= 1.0: tone = C["amber"]
    val = f"{load1}/{ncpu}" if load1 and ncpu else "—"
    return f"{col(G['load'],C['muted'])} {col('Load'.ljust(5),C['fg'])} {col(val, tone)}"


def bar_rows(d, width=12, fields=None):
    """Load text row + one bar per present resource. `fields` restricts the set
    (the profile card shows Mem/Disk only) and drops the Load row."""
    SPEC = [("mem", "Mem", False), ("swap", "Swap", False),
            ("disk", "Disk", False), ("batt", "Batt", True)]   # batt: full = green
    rows = [load_row(d)]
    if fields is not None:
        SPEC = [s for s in SPEC if s[0] in fields]
        rows = []
    for f, label, inv in SPEC:
        raw = d.get(f + "_pct", "")
        if raw in (None, ""):
            continue
        try: p = int(raw)
        except Exception: p = 0
        rows.append(f"{col(G.get(f,''),C['muted'])} {col(label.ljust(5),C['fg'])} "
                    f"{bar(p, width, inv)} {col(str(p).rjust(3)+'%', C['muted'])}")
    return rows


def palette_dots():
    dots = "".join(col("●", C[k]) for k in ("blue", "green", "purple", "amber",
                                            "red", "cyan", "muted", "fg"))
    return "  " + dots


# ── Homelab fleet (read-only cache; never network) ───────────────────────────
def _homelab_cache():
    return _cache_json("homelab.json")


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


# Per-implementation icons for the homelab fleet — each service renders with its
# own glyph (not a generic dot). Keys are matched case-insensitively against the
# service id from fleet.yml. To add/retune a service icon, edit ONLY this map.
SERVICE_GLYPHS = {
    "tailscale": "", "k3s": "⎈", "k8s": "⎈",
    "kubernetes": "⎈", "docker": "", "gitea": "",
    "git": "", "forgejo": "", "ollama": "", "n8n": "",
    "portainer": "", "grafana": "", "prometheus": "",
    "postgres": "", "postgresql": "", "redis": "",
    "mariadb": "", "mysql": "", "caddy": "", "nginx": "",
    "traefik": "", "jellyfin": "", "plex": "",
    "vaultwarden": "", "home-assistant": "", "homeassistant": "",
    "_default": "",   # nf-fa-server
}


def homelab_lines():
    """Live HR-TRUST fleet rows read from the homelab.json cache (no network).
    Returns [] when the cache is absent so the caller drops the block on machines
    that aren't homelab cockpits. Up=green, down=red, degraded/stale=amber."""
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
    head = []
    gh = (data.get("identity") or {}).get("github") or {}
    if gh.get("user"):
        head.append(f"{col(chr(0xF09B), C['purple'])} {col(_short(gh['user'], 18), C['fg'])} {dot(gh.get('state'))}")
    route = data.get("route") or {}
    if route.get("path"):
        head.append(f"{col(chr(0xF0E8), C['green'])} {col(_short(route['path'], 28), C['fg'])}")
    if head:
        rows.append("   ".join(head))
    for m in data["machines"]:
        segs = [f"{col(chr(0xF233), C['blue'])} {col(_short(m.get('id', '?'), 12), C['fg'])} {dot(m.get('state'))}"]
        for s in (m.get("services") or []):
            sid = s.get('id', '?')
            sg = SERVICE_GLYPHS.get(sid.lower(), SERVICE_GLYPHS["_default"])
            segs.append(f"{dot(s.get('state'))} {col(sg, C['cyan'])} {col(_short(sid, 10), C['muted'])}")
        rows.append("  ".join(segs))
    if suffix:
        rows.append(col(suffix.strip(), C["muted"]))
    return rows


# ── Attention (audit F-10) ───────────────────────────────────────────────────
# situation.sh evaluate writes attention.json; the render only reads it. Nothing
# here probes, and nothing here writes.
ATTENTION_MAX = 6
TIER_TONE = {"crit": "red", "warn": "amber", "info": "blue"}
TIER_MARK = {"crit": "!", "warn": "~", "info": "i"}


def _epoch(v):
    """Epoch seconds from a number or an ISO-8601 string; None when unusable."""
    if isinstance(v, (int, float)):
        return int(v)
    if isinstance(v, str) and v.strip():
        s = v.strip()
        if s.isdigit():
            return int(s)
        try:
            return int(datetime.datetime.strptime(
                s, "%Y-%m-%dT%H:%M:%SZ").replace(
                    tzinfo=datetime.timezone.utc).timestamp())
        except Exception:
            return None
    return None


def _age(epoch):
    """'12s' / '4m' / '2h' / '3d' — the age of a cached fact, never a duration."""
    e = _epoch(epoch)
    if e is None:
        return ""
    import time
    secs = max(0, int(time.time()) - e)
    if secs < 60:
        return f"{secs}s"
    if secs < 3600:
        return f"{secs // 60}m"
    if secs < 86400:
        return f"{secs // 3600}h"
    return f"{secs // 86400}d"


def _dot(tier):
    """Tier marker. NO_COLOR keeps the tiers apart with `!` / `~` / `i`,
    because a colourless bullet says nothing."""
    if NOCOLOR:
        return TIER_MARK.get(tier, "i")
    return col("●", C[TIER_TONE.get(tier, "blue")])


def _context_rows(checked_age):
    """The operator context: Things, the last handoff, live claude sessions and
    dirty repos, out of local.json — plus how old the newest probe is."""
    loc = _cache_json("local.json") or {}
    r1, r2 = [], []
    things = loc.get("things") or {}
    bits = []
    if things.get("inbox"):
        bits.append(f"{things['inbox']} inbox")
    if things.get("today"):
        bits.append(f"{things['today']} today")
    if bits:
        r1.append(col("Things ", C["muted"]) + col(" · ".join(bits), C["fg"]))
    ho = loc.get("handoff") or {}
    if ho.get("title") and (ho.get("age_s") or 0) < 7 * 86400:
        age = _age(int(__import__("time").time()) - int(ho.get("age_s") or 0))
        r1.append(col("handoff ", C["muted"])
                  + col(f'"{_short(ho["title"], 28)}"', C["fg"])
                  + col(f" {age}", C["muted"]))
    if loc.get("claude_sessions"):
        r2.append(col(f"{loc['claude_sessions']} claude sessions", C["fg"]))
    repos = loc.get("repos") or {}
    if repos.get("dirty"):
        r2.append(col(f"{repos['dirty']}/{repos.get('total', '?')} repos dirty", C["fg"]))
    if checked_age:
        r2.append(col(f"checked {checked_age} ago", C["muted"]))
    rows = []
    if r1:
        rows.append(col(" · ", C["muted"]).join(r1))
    if r2:
        rows.append(col(" · ", C["muted"]).join(r2))
    return rows


def attention_lines(max_items=ATTENTION_MAX):
    """The card's attention block.

    No attention.json at all -> `no state yet · claw situation probe`.
    No items -> `✓ all clear · checked Nm ago`.
    Otherwise one row per item (acked ones hidden), capped, then the context.
    """
    data = _cache_json("attention.json")
    if data is None:
        return [col("no state yet", C["muted"]) + col(" · ", C["muted"])
                + col("claw situation probe", C["fg"])]
    checked = [e for e in (_epoch(v) for v in (data.get("checked") or {}).values())
               if e is not None]
    checked_age = _age(max(checked)) if checked else ""
    items = [i for i in (data.get("items") or [])
             if isinstance(i, dict) and (i.get("hint") or "") != "acked"]

    rows = []
    for it in items[:max_items]:
        src = _epoch(it.get("src_ts"))
        since = _epoch(it.get("since"))
        parts = [_dot(it.get("tier", "info")), col(str(it.get("text", "")), C["fg"])]
        if it.get("hint"):
            parts.append(col(str(it["hint"]), C["muted"]))
        tail = []
        if since is not None and src is not None and since != src:
            tail.append("since " + datetime.datetime.fromtimestamp(since).strftime("%H:%M"))
        age = _age(src)
        if age:
            tail.append(age)
        if tail:
            parts.append(col(" · ".join(tail), C["muted"]))
        rows.append("  ".join(parts))
    extra = len(items) - len(rows)
    if extra > 0:
        rows.append(col(f"+{extra} more", C["muted"]) + col(" · ", C["muted"])
                    + col("claw doctor", C["fg"]))
    if not items:
        clear = col("✓ all clear", C["green"])
        if checked_age:
            clear += col(f" · checked {checked_age} ago", C["muted"])
        rows.append(clear)
        checked_age = ""      # already stated on the all-clear line
    return rows + _context_rows(checked_age)


# ── Frame (the ONE render primitive) ─────────────────────────────────────────
RULE = "\x00rule\x00"          # sentinel row, expanded by frame() to a divider


def rule(label):
    """A divider row that spans the frame: the label sits in a horizontal rule
    drawn with the same geometry as the title border."""
    return RULE + label


def frame(lines, title_text, content_w, margin):
    """Print one framed, centered box. All boxes in a run share content_w."""
    inner = content_w + 2
    title = _clip(col(title_text, C["green"]), max(0, inner - 1))
    dash = max(0, inner - 1 - vis(title))
    bar_ch = col("│", C["muted"])
    print(margin + col("╭─", C["muted"]) + title + col("─" * dash + "╮", C["muted"]))
    for m in lines:
        if m.startswith(RULE):
            lbl = _clip(col(f" {m[len(RULE):]} ", C["muted"]), max(0, inner - 1))
            d2 = max(0, inner - 1 - vis(lbl))
            print(margin + col("├─", C["muted"]) + lbl + col("─" * d2 + "┤", C["muted"]))
            continue
        print(margin + bar_ch + " " + pad(_clip(m, content_w), content_w) + " " + bar_ch)
    print(margin + col("╰" + "─" * inner + "╯", C["muted"]))


def render(rows, logo, title_text, term):
    """Frame `rows` (optionally beside `logo`), centered and clamped to `term`."""
    if logo:
        lw = max((vis(l) for l in logo), default=0) + 3
        # Rule rows span the whole frame, so they take no logo line with them —
        # only the ordinary rows pair up with the art, and the shorter of the
        # two columns is centred against the other.
        nb = sum(1 for r in rows if not r.startswith(RULE))
        logo_off = max(0, (nb - len(logo)) // 2)
        body_off = max(0, (len(logo) - nb) // 2)

        def _logo_at(i):
            j = i - logo_off
            return logo[j] if 0 <= j < len(logo) else ""

        merged, i = [], 0
        while i < body_off:
            merged.append(pad(_logo_at(i), lw).rstrip())
            i += 1
        for r in rows:
            if r.startswith(RULE):
                merged.append(r)
                continue
            merged.append((pad(_logo_at(i), lw) + r).rstrip())
            i += 1
        while 0 <= i - logo_off < len(logo):
            merged.append(pad(_logo_at(i), lw).rstrip())
            i += 1
    else:
        merged = list(rows)

    content_w = max((vis(m) for m in merged if not m.startswith(RULE)), default=20)
    content_w = min(content_w, max(20, term - 4))
    margin = " " * max(0, (term - (content_w + 4)) // 2)
    print()
    frame(merged, title_text, content_w, margin)


# ── Modes ────────────────────────────────────────────────────────────────────
def header_rows(d, narrow):
    """user@nodename - model - net  /  date - time - up. At <80 cols the model
    and the network drop to segment rows instead of wrapping."""
    user = os.environ.get("USER", "") or os.environ.get("LOGNAME", "")
    host = d.get("host", "") or platform.node()
    sep = col(" · ", C["muted"])
    first = [col(f"{user}@{host}", C["green"])]
    if not narrow:
        if d.get("model"):
            first.append(col(_short(d["model"], 42), C["fg"]))
        net = d.get("ssid") or d.get("ip")
        if net:
            first.append(col(net, C["fg"]))
    now = datetime.datetime.now()
    second = [col(now.strftime("%a %b %d"), C["muted"]),
              col(now.strftime("%H:%M"), C["muted"])]
    if d.get("uptime"):
        second.append(col("up " + d["uptime"], C["muted"]))
    return [f"{col(G['user'], C['green'])} " + sep.join(first),
            f"{col(G['clock'], C['muted'])} " + sep.join(second)]


def login_rows(d, term):
    """header · segments · bars · `attention` rule · attention · homelab · dots."""
    narrow = term < 80
    wide = term >= 100
    rows = header_rows(d, narrow)
    # the header already carries model + net at >=80 cols; don't repeat them
    skip = () if narrow else ("model", "net")
    segs = render_segments(segment_rows(d), two_col=wide, skip=skip)
    if segs:
        rows += [""] + segs
    bars = bar_rows(d, width=8 if narrow else 12)
    if bars:
        rows += [""] + bars
    rows += [rule("attention")] + attention_lines()
    hl = homelab_lines()
    if hl:
        rows += [""] + hl
    rows += ["", palette_dots()]
    return rows


PROFILE_TOOL_CAP = 8


def profile_rows(key, d, term):
    """class · tag · key-tool presence · help pointer · Mem/Disk · attention.

    Every PROFILE_* value arrives through the environment — `claw load` sources
    the profile's meta.zsh and exports them before calling this, so nothing here
    parses zsh.
    """
    narrow = term < 80
    env = os.environ.get
    klass = env("PROFILE_CLASS", "") or key.upper()
    glyph = env("PROFILE_GLYPH", "")
    tag = env("PROFILE_TAG", "")

    head = (f"{col(glyph, C['purple'])} " if glyph else "") + col(klass, C["green"])
    if tag:
        head += col(" · ", C["muted"]) + col(tag, C["fg"])
    rows = [head]

    tools = (env("PROFILE_KEY_TOOLS", "") or "").split()[:PROFILE_TOOL_CAP]
    if tools:
        present = {t: bool(shutil.which(t)) for t in tools}
        rows.append("  ".join(
            (col("✓ ", C["green"]) + col(t, C["fg"])) if present[t]
            else (col("✗ ", C["red"]) + col(t, C["muted"]))
            for t in tools))
        chain = env("PROFILE_TOOLCHAIN", "")
        if chain and not all(present.values()):
            name = chain[:-len("-toolchain.sh")] if chain.endswith("-toolchain.sh") else chain
            rows.append(col("→ ", C["muted"]) + col(f"claw install {name}", C["amber"]))

    rows.append(col(env("PROFILE_HELP_CMD", "") or f"{key}-help", C["fg"])
                + col(" · reference", C["muted"]))

    bars = bar_rows(d, width=8 if narrow else 12, fields=("mem", "disk"))
    if bars:
        rows += [""] + bars
    rows += [rule("attention")] + attention_lines()
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(prog="claw-dashboard",
                                 description="Open Claw login / profile card")
    ap.add_argument("--login", action="store_true",
                    help="the daily login card (default)")
    ap.add_argument("--profile", metavar="KEY", help="render the profile card for KEY")
    ap.add_argument("--quickref", action="store_true",
                    help="deprecated alias of --login")
    ap.add_argument("--json-fixture", dest="json_fixture", metavar="PATH",
                    help="read the fastfetch payload from PATH instead of probing")
    args = ap.parse_args(argv)

    term = shutil.get_terminal_size((100, 30)).columns
    d = ff_json(args.json_fixture)
    if args.profile:
        key = args.profile
        title = f" OPEN CLAW · {os.environ.get('PROFILE_CLASS') or key} "
        render(profile_rows(key, d, term),
               profile_logo(key) if term >= 100 else [], title, term)
    else:
        render(login_rows(d, term), builtin_logo() if term >= 100 else [],
               " OPEN CLAW ", term)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
