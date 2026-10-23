#!/usr/bin/env python3
"""The microcode (shite_ucode.asm, through tools/shite_usim.py) against the
reference model, instruction by instruction, on a bench's program: each
SHITE instruction the emulator runs is run on the microcode model too,
from the same memory, and the two compared (memory, R[a], the error).

    shite_ucheck.py gen_shite5.py [--trace N] [--all] [--profile] [--asm FILE]

Stops at the first difference (--all: goes on), with the bytes that differ;
--trace N prints the micro-ops of instruction N (from 0)."""
import argparse
import os
import runpy
import struct
import sys

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
vhdl = os.path.dirname(here)
tools = os.environ.get("SSNAIL_TOOLS") or os.path.join(vhdl, "SSNAIL")
sys.path.insert(0, tools)
import ssnail_isa as I
import ssnail_sim as S
import shite_usim as US

ERRS = {"ERR_FORMAT": 6, "ERR_ADDRESS": 2, "ERR_READ": 4, "ERR_ABORTED": 5, "ERR_OPCODE": 1}


class Copy:
    """A copy of the emulator's memory, as SHITE sees it."""

    def __init__(self, mem):
        self.mem = bytearray(mem)

    def read(self, a, n):
        o = a - I.HYPERRAM_BASE
        if not 0 <= o <= len(self.mem) - n:
            raise US.UError(f"address ${a:07X} outside the memory")
        return bytes(self.mem[o:o + n])

    def write(self, a, d):
        o = a - I.HYPERRAM_BASE
        if not 0 <= o <= len(self.mem) - len(d):
            raise US.UError(f"address ${a:07X} outside the memory")
        self.mem[o:o + len(d)] = d


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("generator")
    ap.add_argument("--trace", type=int, default=-1)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--profile", action="store_true", help="micro-ops by label")
    ap.add_argument("--asm", help="the microcode source (default: src/vhdl/shite_ucode.asm)")
    args = ap.parse_args()
    sim = US.USim(args.asm)
    if args.profile:
        sim.profile = {}
    orig = S.Machine.shite
    count = [0]
    bad = [0]

    def shite(self, op, a, b, desc):
        k = count[0]
        count[0] += 1
        ins = self.read(self.pc, 16)
        c = ins[3]
        z = struct.unpack("<I", ins[12:16])[0]
        cp = Copy(self.mem)
        sim.trace = k == args.trace
        try:
            err, wr, res = sim.run(op, self.reg(a), self.reg(b), self.reg(c & 15), self.reg(c >> 4), z,
                                   desc, cp)
        except US.UError as e:
            err, wr, res = -1, False, str(e)
        sim.trace = False
        merr, mres = 0, None
        try:
            orig(self, op, a, b, desc)
            mres = self.R[a] if a != I.RZERO else None
        except S.SsnailError as e:
            merr = next((v for k2, v in ERRS.items() if k2 in str(e)), -2)
            exc = e
        else:
            exc = None
        diff = [i for i in range(len(cp.mem)) if cp.mem[i] != self.mem[i]] if cp.mem != self.mem else []
        ok = not diff and err == merr and (merr or mres is None or not wr or res == mres)
        if not ok:
            bad[0] += 1
            print(f"instruction {k}: op ${op:02X} at ${self.pc:07X}: microcode err {err} R {res!r} wr {wr}; "
                  f"model err {merr} R {mres!r}", file=sys.stderr)
            for i in diff[:24]:
                print(f"   ${i + I.HYPERRAM_BASE:07X}: microcode ${cp.mem[i]:02X}, model ${self.mem[i]:02X}",
                      file=sys.stderr)
            if len(diff) > 24:
                print(f"   ... {len(diff)} bytes differ", file=sys.stderr)
            if not args.all:
                sys.exit(1)
        if exc:
            raise exc

    S.Machine.shite = shite
    old = os.getcwd()
    os.chdir(os.environ.get("TMPDIR", "/tmp"))
    try:
        runpy.run_path(os.path.join(here, args.generator) if not os.path.exists(args.generator)
                       else args.generator, run_name="__main__")
    finally:
        os.chdir(old)
    print(f"{count[0]} SHITE instructions, {bad[0]} differing; {sim.ops} micro-ops", file=sys.stderr)
    if args.profile:
        for lab, n in sorted(sim.profile.items(), key=lambda x: -x[1])[:40]:
            print(f"  {n:9d} {100 * n / sim.ops:5.1f}%  {lab}", file=sys.stderr)
    sys.exit(1 if bad[0] else 0)


if __name__ == "__main__":
    main()
