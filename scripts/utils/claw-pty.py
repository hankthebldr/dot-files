#!/usr/bin/env python3
"""claw-pty — run a command under a pseudo-terminal and relay its output.

Used by scripts/utils/system-update.sh (claw_pty) so progress-aware tools see a
TTY inside a `claw_step` pipeline. Why not pty.spawn():

  After ONE failed write to stdout — its consumer went away because Ctrl-C
  killed the pipeline, or bin/claw died — CPython's copy loop sets
  stdout_avail=False, stops reading the master, and parks in
  select([], [], []) forever. The child then blocks on its next write to the
  pty. Zero CPU, frozen log, no receipt, until the deadline fires.
  2026-09-18, `npm update -g` + Ctrl-C: reproduced exactly.

This loop does the opposite: a dead consumer tears the child down (SIGTERM,
then SIGKILL after a short grace), and INT/TERM/HUP are forwarded to the
child's process group so a deadline or an operator still reaches it. Exit
status is the child's (128+N when it died by signal). Stdin is relayed only
when it is a terminal; the engine hands steps /dev/null.
"""
import os
import pty
import select
import signal
import sys
import time

GRACE = 2.0  # seconds between SIGTERM and SIGKILL on teardown


def _write_all(fd, data):
    while data:
        n = os.write(fd, data)
        data = data[n:]


def _kill_tree(pid, sig):
    # pty.fork() made the child a session and process-group leader.
    try:
        os.killpg(pid, sig)
    except ProcessLookupError:
        pass
    except PermissionError:
        try:
            os.kill(pid, sig)
        except OSError:
            pass


def _reap(pid, timeout):
    """waitpid with a deadline: the wait status, or None if still running."""
    end = time.monotonic() + timeout
    while True:
        wpid, status = os.waitpid(pid, os.WNOHANG)
        if wpid == pid:
            return status
        if time.monotonic() >= end:
            return None
        time.sleep(0.05)


def main(argv):
    if not argv:
        sys.stderr.write("usage: claw-pty.py <command> [args...]\n")
        return 2

    pid, master = pty.fork()
    if pid == 0:  # child: the slave is its controlling tty; exec the command
        # Python ignores SIGPIPE and SIG_IGN survives exec — give the tool the
        # default back so `foo | head` style plumbing inside it behaves.
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
        try:
            os.execvp(argv[0], argv)
        except OSError as e:
            sys.stderr.write(f"claw-pty: {argv[0]}: {e.strerror}\n")
            os._exit(127)

    def forward(signum, _frame):
        _kill_tree(pid, signum)

    for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(s, forward)

    relay_stdin = os.isatty(0)
    consumer_gone = False
    while True:
        rfds = [master] + ([0] if relay_stdin else [])
        r, _, _ = select.select(rfds, [], [])
        if master in r:
            try:
                data = os.read(master, 65536)
            except OSError:  # EIO: slave side closed, the child has exited
                data = b""
            if not data:
                break
            try:
                _write_all(1, data)
            except OSError:  # EPIPE: nobody is listening any more
                consumer_gone = True
                break
        if relay_stdin and 0 in r:
            try:
                data = os.read(0, 4096)
            except OSError:
                data = b""
            if not data:
                relay_stdin = False
            else:
                try:
                    _write_all(master, data)
                except OSError:
                    pass

    status = None
    if consumer_gone:
        _kill_tree(pid, signal.SIGTERM)
        status = _reap(pid, GRACE)
        if status is None:
            _kill_tree(pid, signal.SIGKILL)
            status = _reap(pid, GRACE)
    try:
        os.close(master)
    except OSError:
        pass
    if status is None:
        try:
            _, status = os.waitpid(pid, 0)
        except ChildProcessError:
            return 0
    rc = os.waitstatus_to_exitcode(status)
    return rc if rc >= 0 else 128 - rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
