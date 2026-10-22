#!/usr/bin/env python3
"""Run a host build of f3dos or f3test (src/tests, built with -DHOST) against
the FAT32 engine's firmware on the instruction-set simulator
(MEGA65/mega65-core#766).

    python3 src/tools/f3bridge.py --card1 ext.img [--card0 int.img] [--hyp] -- ./f3dos_host [args]

The program's stdin and stdout are its own.  Each controller command comes
through a pipe (the F3_BRIDGE environment variable names its two ends):
code, arg (4 bytes), slot, the 512-byte SD buffer; the answer is the status,
the arg ($D681-$D684 afterwards) and the buffer.  Codes $70-$7F run the
engine; $02/$03 read and write a raw sector of the selected card; $25/$26
(the sector cache) do nothing.
"""

import argparse
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fat32sim  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
FIRMWARE = os.path.join(HERE, "..", "fat32", "engine.fs")


def read_exact(f, n):
    d = b""
    while len(d) < n:
        k = os.read(f, n - len(d))
        if not k:
            return None
        d += k
    return d


def serve(machine, rfd, wfd):
    """answer commands until the program closes its end -> commands run"""
    n = 0
    while True:
        m = read_exact(rfd, 6 + 512)
        if m is None:
            return n
        code, arg, slot = m[0], int.from_bytes(m[1:5], "little"), m[5]
        machine.buf[0xE00:0x1000] = m[6:]
        status = 0
        if 0x70 <= code <= 0x7F:
            status, arg = machine.command(code, arg=arg)
        elif code in (0x02, 0x03):
            machine.slot = slot & 1
            if code == 0x02:
                d = machine._sector(arg)
                if machine.e:
                    status = 7
                else:
                    machine.buf[0xE00:0x1000] = d
            else:
                machine._sector(arg, bytes(machine.buf[0xE00:0x1000]))
        elif code in (0x25, 0x26, 0x2B):
            pass
        else:
            status = 10
        os.write(wfd, bytes([status]) + (arg & 0xFFFFFFFF).to_bytes(4, "little")
                 + bytes(machine.buf[0xE00:0x1000]))
        n += 1


def run(program, cards, stdin=None, hypervisor=False, machine=None, timeout=None):
    """run program (a list) with cards {slot: image}; -> (exit code, stdout,
    the machine).  stdin: text, or None for this process's own."""
    if machine is None:
        prog = fat32sim.assemble(open(FIRMWARE).read())
        machine = fat32sim.Machine(prog, cards=cards, hypervisor=hypervisor)
    c_r, p_w = os.pipe()                    # program -> bridge
    p_r, c_w = os.pipe()                    # bridge -> program
    env = dict(os.environ, F3_BRIDGE="%d,%d" % (p_r, p_w))
    capture = stdin is not None
    proc = subprocess.Popen(program, env=env, pass_fds=(p_r, p_w),
                            stdin=subprocess.PIPE if capture else None,
                            stdout=subprocess.PIPE if capture else None, text=True)
    os.close(p_r)
    os.close(p_w)
    if capture:
        import threading
        out = []
        t = threading.Thread(target=lambda: out.append(proc.communicate(stdin, timeout=timeout)[0]))
        t.start()
    serve(machine, c_r, c_w)
    os.close(c_r)
    os.close(c_w)
    if capture:
        t.join()
        machine.flush()
        return proc.returncode, out[0] if out else "", machine
    proc.wait()
    machine.flush()
    return proc.returncode, None, machine


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--card1", help="the external card's image (drives found first)")
    ap.add_argument("--card0", help="the internal card's image")
    ap.add_argument("--hyp", action="store_true", help="hypervisor mode")
    ap.add_argument("program", nargs="+")
    a = ap.parse_args()
    cards = {}
    if a.card1:
        cards[1] = a.card1
    if a.card0:
        cards[0] = a.card0
    code, _, _ = run(a.program, cards, hypervisor=a.hyp)
    sys.exit(code)


if __name__ == "__main__":
    main()
