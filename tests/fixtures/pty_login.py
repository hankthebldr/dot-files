#!/usr/bin/env python3
"""pty login harness for the Open Claw .zshrc (tests/login.bats).

Forks `zsh -i` under a pseudo-terminal with ZDOTDIR pointing at a GENERATED rc
that sources the repo's shell/.zshrc inside a hermetic HOME, optionally sends
Ctrl-C (\\x03) at a given millisecond and/or types text at t=0, waits for the
`__PROMPT__` marker printed by a precmd hook, then types every --probe command
followed by `exit` and prints all captured bytes to stdout.

Stdlib only (pty, select, os). Never hangs: select() reads under a hard
--timeout; on expiry the child is hung up and killed and the exit status is 124.

    python3 tests/fixtures/pty_login.py --repo . --send-int-at 300 \
        --probe 'print "CLAW_FN=$(typeset -f claw >/dev/null 2>&1 && echo yes || echo no)"'

Hermetic environment built per run (all under --zdotdir, or a mkdtemp):
  HOME            <zdotdir>/home  (XDG_* redirected beneath it, CLAW_NO_LOG=1)
  $HOME/.dotfiles shadow tree: every repo entry symlinked, except scripts/utils
                  which is a real dir of symlinks with the three login-time
                  background probes (tool-updater.sh, situation.sh,
                  update-status.sh) replaced by stubs that append to
                  $HOME/probes.log and exit 0 — so no test ever spawns them.
                  scripts/utils/claw-dashboard.py is ALSO a stub there: it
                  logs argv to $HOME/dash.log and sleeps --dash-sleep-ms (dies
                  by SIGINT like the real one) -- stubbing the file, not
                  python3, survives .zshrc step 1 re-prepending brew to PATH.
  generated rc    defines an in-shell `fzf` function that logs to $HOME/fzf.log
                  and returns 130 (ESC) so the picker never blocks, regardless
                  of PATH order.
  <zdotdir>/stub  first on PATH (until .zshrc prepends brew): `fzf` with the
                  same behaviour for hosts without fzf (CI), `eza` no-op so the
                  guarded ll/la aliases exist on CI too.
  --omz PATH      symlink $HOME/.oh-my-zsh -> PATH with ZSH_CACHE_DIR in the
                  temp HOME and the update stamp pre-seeded (no network, no
                  writes outside the temp tree).
  --pre ZSH       lines inserted into the generated rc BEFORE the repo's .zshrc
                  is sourced (stand-in for ~/.zshenv, e.g. an array export).
  --env K=V       extra environment for the child (repeatable).
  --setup-only    build the environment, print `export ...` lines, exit 0.

Exit status: 0 marker seen and child exited / 124 timeout / 2 setup error.
A one-line summary goes to stderr; captured bytes go to stdout (CR stripped
unless --raw).
"""
from __future__ import annotations

import argparse
import errno
import fcntl
import os
import pty
import select
import shutil
import signal
import struct
import sys
import tempfile
import termios
import time
from pathlib import Path

MARKER = b"__PROMPT__"
BG_PROBES = ("tool-updater.sh", "situation.sh", "update-status.sh")
# Env the child must NOT inherit: the harness owns login mode, theme, profile
# and actor detection. CLAUDECODE is set when bats runs under Claude Code and
# would flip the (T1) agent gate; TERM_PROGRAM selects /etc/zshrc_Apple_Terminal.
DROP_PREFIXES = ("CLAW_", "CLAUDE", "SSH_", "TERM_PROGRAM", "PROFILE_",
                 "POWERLEVEL9K_", "ZSH", "XDG_", "BATS_", "P9K_")
DROP_EXACT = {"DOTFILES_DIR", "VAULT_PATH", "HOME", "ZDOTDIR", "TERM",
              "COLUMNS", "LINES", "TMUX", "STY", "NO_COLOR"}


def die(msg: str, code: int = 2) -> None:
    print(f"pty_login: {msg}", file=sys.stderr)
    sys.exit(code)


def write_exec(path: Path, body: str) -> None:
    path.write_text(body)
    path.chmod(0o755)


DASH_STUB = '''#!/usr/bin/env python3
# pty_login.py stub -- the dashboard render becomes a fixed sleep that dies by
# SIGINT (rc 130) exactly like the real claw-dashboard.py.
import os, signal, sys, time
signal.signal(signal.SIGINT, signal.SIG_DFL)
with open(os.path.join(os.environ["HOME"], "dash.log"), "a") as f:
    f.write(" ".join(sys.argv[1:]) or "-")
    f.write("\\n")
sys.stdout.flush()
time.sleep({sleep:.3f})
'''


def build_shadow_repo(repo: Path, home: Path, dash_sleep_ms: int) -> Path:
    """$HOME/.dotfiles: symlink farm with scripts/utils materialised so the
    login-time background probes and the dashboard can be stubbed by name."""
    shadow = home / ".dotfiles"
    shadow.mkdir(parents=True, exist_ok=True)
    for entry in repo.iterdir():
        if entry.name in (".git", "scripts"):
            continue
        target = shadow / entry.name
        if not target.exists() and not target.is_symlink():
            target.symlink_to(entry)
    scripts = shadow / "scripts"
    scripts.mkdir(exist_ok=True)
    for entry in (repo / "scripts").iterdir():
        if entry.name == "utils":
            continue
        target = scripts / entry.name
        if not target.exists() and not target.is_symlink():
            target.symlink_to(entry)
    utils = scripts / "utils"
    utils.mkdir(exist_ok=True)
    for entry in (repo / "scripts" / "utils").iterdir():
        target = utils / entry.name
        if target.exists() or target.is_symlink():
            continue
        if entry.name == "claw-dashboard.py":
            write_exec(target, DASH_STUB.format(sleep=dash_sleep_ms / 1000))
        elif entry.name in BG_PROBES:
            write_exec(target, "#!/usr/bin/env bash\n"
                       "# pty_login.py stub -- records the call, never probes.\n"
                       'printf "%s %s\\n" "$(basename "$0")" "$*" >> "${HOME:?}/probes.log"\n'
                       "exit 0\n")
        else:
            target.symlink_to(entry)
    return shadow


def build_stubs(stub: Path) -> None:
    stub.mkdir(parents=True, exist_ok=True)
    write_exec(stub / "fzf", "#!/usr/bin/env bash\n"
               "# pty_login.py stub -- ESC immediately (rc 130), never blocks.\n"
               'printf "fzf %s\\n" "$*" >> "${HOME:?}/fzf.log"\n'
               "cat >/dev/null 2>&1\n"
               "exit 130\n")
    write_exec(stub / "eza", "#!/usr/bin/env bash\nexit 0\n")


def build_omz(home: Path, omz: Path) -> dict:
    link = home / ".oh-my-zsh"
    if not link.exists() and not link.is_symlink():
        link.symlink_to(omz)
    cache = home / ".cache" / "oh-my-zsh"
    (cache / "completions").mkdir(parents=True, exist_ok=True)
    (cache / ".zsh-update").write_text(f"LAST_EPOCH={int(time.time()) // 86400}\n")
    return {"ZSH_CACHE_DIR": str(cache), "DISABLE_AUTO_UPDATE": "true"}


def write_rc(zdotdir: Path, pre: list[str]) -> None:
    # The marker hook is armed BEFORE the repo rc so an aborted rc (the F-01
    # failure mode) still reaches an observable prompt instead of a timeout.
    lines = ["# generated by tests/fixtures/pty_login.py -- do not edit",
             "_m() { print __PROMPT__ }",
             "precmd_functions+=(_m)",
             # In-shell picker stub: wins over any PATH order the rc sets up.
             'fzf() { print -r -- "fzf $*" >> "$HOME/fzf.log"; cat >/dev/null 2>&1; return 130 }']
    lines += pre
    lines += ['source "$HOME/.dotfiles/shell/.zshrc"',
              "(( ${precmd_functions[(I)_m]} )) || precmd_functions+=(_m)"]
    (zdotdir / ".zshrc").write_text("\n".join(lines) + "\n")


def child_env(home: Path, zdotdir: Path, stub: Path, extra: dict) -> dict:
    env = {k: v for k, v in os.environ.items()
           if k not in DROP_EXACT and not k.startswith(DROP_PREFIXES)}
    env.update({
        "HOME": str(home),
        "ZDOTDIR": str(zdotdir),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_STATE_HOME": str(home / ".local" / "state"),
        "XDG_DATA_HOME": str(home / ".local" / "share"),
        "CLAW_NO_LOG": "1",
        "TERM": "xterm-256color",
        "PATH": f"{stub}:{os.environ.get('PATH', '/usr/bin:/bin')}",
    })
    env.setdefault("LANG", "en_US.UTF-8")
    env.update(extra)
    return env


def parse_kv(items: list[str]) -> dict:
    out = {}
    for item in items:
        if "=" not in item:
            die(f"--env expects K=V, got {item!r}")
        k, v = item.split("=", 1)
        out[k] = v
    return out


def run(args, env: dict, zdotdir: Path) -> int:
    probes_line = ("; ".join(args.probe + ["exit"]) + "\r").encode()
    pid, fd = pty.fork()
    if pid == 0:  # child
        try:
            os.execvpe("zsh", ["zsh", "-i"], env)
        except OSError as e:  # pragma: no cover
            os.write(2, f"exec zsh failed: {e}\n".encode())
            os._exit(127)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", args.rows, args.cols, 0, 0))
    t0 = time.monotonic()
    deadline = t0 + args.timeout
    buf = bytearray()
    int_sent = args.send_int_at is None
    typed = not args.type
    probes_sent = False
    marker_at = None
    eof = False
    timed_out = False

    def elapsed_ms() -> int:
        return int((time.monotonic() - t0) * 1000)

    while not eof:
        now = time.monotonic()
        if now >= deadline:
            timed_out = True
            break
        # Scheduled input.
        if not typed:
            os.write(fd, args.type.encode())
            typed = True
        if not int_sent and elapsed_ms() >= args.send_int_at:
            os.write(fd, b"\x03")
            int_sent = True
        if marker_at is not None and not probes_sent and now >= marker_at + 0.05:
            os.write(fd, probes_line)
            probes_sent = True
        # Wake-ups: next scheduled event or 50 ms.
        wait = 0.05
        if not int_sent:
            wait = min(wait, max(0.0, args.send_int_at / 1000 - (now - t0)))
        r, _, _ = select.select([fd], [], [], min(wait, max(0.0, deadline - now)))
        if not r:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError as e:
            if e.errno == errno.EIO:  # slave closed (Linux); child gone
                eof = True
                break
            raise
        if not chunk:  # macOS reports EOF as an empty read
            eof = True
            break
        buf += chunk
        if marker_at is None and MARKER in buf:
            marker_at = time.monotonic()

    if timed_out:
        try:
            os.kill(pid, signal.SIGHUP)
            time.sleep(0.1)
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    # Reap (bounded).
    rc = None
    reap_deadline = time.monotonic() + 2.0
    while time.monotonic() < reap_deadline:
        wpid, status = os.waitpid(pid, os.WNOHANG)
        if wpid == pid:
            rc = os.waitstatus_to_exitcode(status)
            break
        time.sleep(0.02)
    if rc is None:
        try:
            os.kill(pid, signal.SIGKILL)
            _, status = os.waitpid(pid, 0)
            rc = os.waitstatus_to_exitcode(status)
        except (ProcessLookupError, ChildProcessError):
            rc = -1
    os.close(fd)

    out = bytes(buf) if args.raw else bytes(buf).replace(b"\r", b"")
    sys.stdout.buffer.write(out)
    if out and not out.endswith(b"\n"):
        sys.stdout.buffer.write(b"\n")
    sys.stdout.buffer.flush()
    print(f"pty_login: rc={rc} marker={'yes' if marker_at is not None else 'no'} "
          f"probes={'sent' if probes_sent else 'not-sent'} timeout={'yes' if timed_out else 'no'} "
          f"elapsed={elapsed_ms()}ms zdotdir={zdotdir}", file=sys.stderr)
    if timed_out:
        return 124
    return 0 if marker_at is not None else 1


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--repo", help="dotfiles checkout to test (default: CLAW_REPO or this file's repo)")
    p.add_argument("--zdotdir", help="directory for the generated rc + HOME (default: mkdtemp, removed after)")
    p.add_argument("--home", help="HOME for the child (default: <zdotdir>/home)")
    p.add_argument("--send-int-at", type=int, metavar="MS", help="send Ctrl-C at this many ms after fork")
    p.add_argument("--type", metavar="TEXT", help="type TEXT into the pty at t=0")
    p.add_argument("--timeout", type=float, default=20.0, metavar="S", help="hard wall-clock limit (default 20)")
    p.add_argument("--env", action="append", default=[], metavar="K=V", help="extra child env (repeatable)")
    p.add_argument("--probe", action="append", default=[], metavar="CMD",
                   help="zsh command typed after the first prompt (repeatable; `exit` is appended)")
    p.add_argument("--pre", action="append", default=[], metavar="ZSH",
                   help="rc line inserted before the repo .zshrc is sourced (repeatable)")
    p.add_argument("--dash-sleep-ms", type=int, default=400, help="stub dashboard render duration (default 400)")
    p.add_argument("--omz", metavar="PATH", help="link $HOME/.oh-my-zsh to this checkout (hermetic cache)")
    p.add_argument("--rows", type=int, default=40)
    p.add_argument("--cols", type=int, default=120)
    p.add_argument("--raw", action="store_true", help="keep CR bytes in the captured output")
    p.add_argument("--keep", action="store_true", help="keep a mkdtemp zdotdir")
    p.add_argument("--setup-only", action="store_true", help="build the env, print export lines, exit")
    args = p.parse_args()

    if not shutil.which("zsh"):
        die("zsh not found on PATH")
    repo = Path(args.repo or os.environ.get("CLAW_REPO") or Path(__file__).resolve().parents[2]).resolve()
    if not (repo / "shell" / ".zshrc").is_file():
        die(f"{repo} has no shell/.zshrc")

    own_tmp = args.zdotdir is None
    zdotdir = Path(args.zdotdir).resolve() if args.zdotdir else Path(tempfile.mkdtemp(prefix="pty_login."))
    zdotdir.mkdir(parents=True, exist_ok=True)
    home = Path(args.home).resolve() if args.home else zdotdir / "home"
    for d in (".cache/claw", ".config", ".local/state", ".local/share"):
        (home / d).mkdir(parents=True, exist_ok=True)
    stub = zdotdir / "stub"

    build_shadow_repo(repo, home, args.dash_sleep_ms)
    build_stubs(stub)
    extra = parse_kv(args.env)
    if args.omz:
        omz = Path(args.omz).resolve()
        if not (omz / "oh-my-zsh.sh").is_file():
            die(f"{omz} has no oh-my-zsh.sh")
        extra = {**build_omz(home, omz), **extra}
    write_rc(zdotdir, args.pre)
    env = child_env(home, zdotdir, stub, extra)

    if args.setup_only:
        for k in ("HOME", "ZDOTDIR", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME",
                  "XDG_DATA_HOME", "CLAW_NO_LOG", "TERM", "PATH", *extra.keys()):
            v = env[k].replace("'", "'\\''")
            print(f"export {k}='{v}'")
        return 0

    try:
        return run(args, env, zdotdir)
    finally:
        if own_tmp and not args.keep:
            shutil.rmtree(zdotdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
