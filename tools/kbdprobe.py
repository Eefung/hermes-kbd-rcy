#!/usr/bin/env python3
"""kbdprobe — inspect and repair kitty keyboard-protocol (CSI-u) state, per screen.

kitty keeps SEPARATE CSI-u stacks for the main and the alternate screen. TUIs
that push `CSI >1u` INSIDE the alt screen and exit without popping leak the
ALT stack: the shell prompt (main screen) looks fine while alt-screen apps
(vi/micro/nano/less) receive CSI-u fragments like "113;5u". This tool reports
flags per screen via `CSI ?u`, can reproduce the leak, and can apply the
two-screen cleanup.

Usage:
  kbdprobe.py                     report flags on main + alt screens
  kbdprobe.py --simulate          push flags=1 inside the alt screen first
                                  (recreates the leak on purpose)
  kbdprobe.py --simulate --fix    reproduce, repair, verify
  kbdprobe.py --fix               apply the two-screen cleanup, then re-report
  kbdprobe.py --json              machine-readable output

Note: --simulate really does dirty the alt-screen stack; pair it with --fix.
"""
import json
import os
import re
import select
import sys
import termios
import time

# The leak is the ALT screen's setting, so the fix visits that screen only:
# enter alt -> pop once + zero flags -> leave alt.
FIX_SEQ = '\x1b[?1049h\x1b[=0u\x1b[?1049l'

SIM_SEQ = '\x1b[?1049h\x1b[>1u\x1b[?1049l'  # push inside alt, exit without pop

REPLY_RE = re.compile(rb'\x1b\[\?(\d+)u')


def parse_flags(buf):
    """Parse a ``CSI ? flags u`` reply out of ``buf``; None when absent.

    Kept as a module-level function so the reply parsing is unit-testable
    without a pty (see tests/test-probe.py).
    """
    m = REPLY_RE.search(buf)
    return int(m.group(1)) if m else None


def query(fd, ttyfd):
    """Current screen's CSI-u flags via CSI ? u. Returns int or None."""
    termios.tcflush(fd, termios.TCIFLUSH)
    os.write(ttyfd, b'\x1b[?u')
    buf = b''
    deadline = time.time() + 0.8
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            buf += os.read(fd, 128)
            if b'u' in buf:
                break
    return parse_flags(buf)


def fmt(screen, flags):
    if flags is None:
        return f'{screen:16} ?    (no reply — terminal does not answer CSI ?u)'
    if flags == 0:
        return f'{screen:16} {flags:<3}  OK (legacy key encoding)'
    return (f'{screen:16} {flags:<3}  STUCK — alt-screen apps (vi/micro/nano) '
            f'will see CSI-u fragments like "113;5u"')


def main():
    args = sys.argv[1:]
    do_sim = '--simulate' in args
    do_fix = '--fix' in args
    as_json = '--json' in args

    import tty
    fd = sys.stdin.fileno()
    ttyfd = os.open('/dev/tty', os.O_WRONLY)  # sequences must go to the real tty

    def w(s):
        os.write(ttyfd, s.encode('latin1'))

    old = termios.tcgetattr(fd)
    data = {}
    try:
        tty.setraw(fd)
        if do_sim:
            w(SIM_SEQ)
        data['main'] = query(fd, ttyfd)
        w('\x1b[?1049h')
        data['alt'] = query(fd, ttyfd)
        w('\x1b[?1049l')
        if do_fix:
            w(FIX_SEQ)
            data['main_after_fix'] = query(fd, ttyfd)
            w('\x1b[?1049h')
            data['alt_after_fix'] = query(fd, ttyfd)
            w('\x1b[?1049l')
        # leave the terminal sane
        w('\x1b[>4m\x1b[?1004l\x1b[?2004l\x1b[?25h\x1b[r')
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    if as_json:
        print(json.dumps(data, indent=2))
    else:
        for k, v in data.items():
            print(fmt(k, v))


if __name__ == '__main__':
    main()
