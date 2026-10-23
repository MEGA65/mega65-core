#!/usr/bin/env python3
"""RECALC's microcode against the reference model on random sheets: numbers
(integers with fixed points, decimal and binary, F64 at their edges), text,
blanks, and formulas of random operators, functions, aggregates over ranges
and cell lists, IFs and references (some off the sheet); rounds with BEGIN
and END.  Each sheet recalculated by the model (SSNAIL/shite.py) and by the
microcode (tools/shite_usim.py) from the same memory; the first difference
reported with its seed.

    shite_ufuzz.py [--sheets N] [--seed S] [--asm FILE] [--max-ops N] [-v]"""
import argparse
import math
import os
import random
import struct
import sys

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
sys.path.insert(0, os.environ.get("SSNAIL_TOOLS") or os.path.join(os.path.dirname(here), "SSNAIL"))
import shite as SH
import shite_usim as US

B = 0x8000000
SIZE = 0x40000


class Mem:
    def __init__(self, b=None):
        self.b = bytearray(b) if b is not None else bytearray(SIZE)

    def read(self, a, n):
        o = a - B
        if not 0 <= o <= SIZE - n:
            raise US.UError(f"address ${a:07X}")
        return bytes(self.b[o:o + n])

    def write(self, a, d):
        o = a - B
        if not 0 <= o <= SIZE - len(d):
            raise US.UError(f"address ${a:07X}")
        self.b[o:o + len(d)] = d


EDGE_F = [0.0, -0.0, 1.0, -1.0, 0.5, 2.5, -2.5, 1e300, -1e300, 1e-300, 5e-324, 2.2250738585072014e-308,
          math.inf, -math.inf, math.nan, 1e16, 9007199254740993.0, 0.1, 1 / 3, 123456.789, -0.75, 4e18]
EDGE_I = [0, 1, -1, 2, 7, -7, 100, 127, -128, 32767, 1 << 31, -(1 << 31), (1 << 62), -(1 << 62),
          (1 << 63) - 1, -(1 << 63), 10 ** 18, -10 ** 18, 999999999999]


def fmt(k):
    return bytes([1, 2, k, 0, 0, 0, random.randrange(16), 0])


def rand_k():
    r = random.random()
    if r < 0.5:
        return 0
    if r < 0.8:
        return random.choice([1, 2, 3, 6, 18, 19])
    return 0x80 | random.choice([1, 4, 16, 62, 63])


class Gen:
    def __init__(self, nrows, ncols):
        self.nrows, self.ncols = nrows, ncols

    def ref(self, f, row, col, rng_ok=True):
        tr = random.randrange(self.nrows + (2 if random.random() < 0.1 else 0))
        tc = random.randrange(self.ncols + (2 if random.random() < 0.1 else 0))
        rabs, cabs = random.random() < 0.3, random.random() < 0.3
        lng = random.random() < 0.3
        f.ref(tr if rabs else tr - row, tc if cabs else tc - col, rabs, cabs, long=lng)

    def corner(self, row, col):
        tr, tc = random.randrange(self.nrows), random.randrange(self.ncols)
        rabs, cabs = random.random() < 0.4, random.random() < 0.4
        return (tr if rabs else tr - row, tc if cabs else tc - col, rabs, cabs)

    def expr(self, f, row, col, d):
        """an expression's bytecode onto f; returns the values it leaves (1)"""
        r = random.random()
        if d <= 0 or r < 0.3:
            k = random.random()
            if k < 0.35:
                self.ref(f, row, col)
            elif k < 0.6:
                v = random.choice(EDGE_I) if random.random() < 0.5 else random.randrange(-1000, 1000)
                f.i(v)
                if random.random() < 0.3:
                    f.fix(rand_k())
            elif k < 0.85:
                x = random.choice(EDGE_F) if random.random() < 0.5 else random.uniform(-1e6, 1e6)
                f.f(x)
            else:
                f.i(random.randrange(-5, 50))
            return
        r = random.random()
        if r < 0.45:                                     # a binary operator
            self.expr(f, row, col, d - 1)
            self.expr(f, row, col, d - 1)
            f.op(random.choice([SH.OP_ADD, SH.OP_SUB, SH.OP_MUL, SH.OP_DIV, SH.OP_EQ, SH.OP_NE,
                                SH.OP_LT, SH.OP_LE, SH.OP_GT, SH.OP_GE, SH.OP_POW]))
        elif r < 0.55:                                   # unary
            self.expr(f, row, col, d - 1)
            f.op(random.choice([SH.OP_NEG, SH.OP_PCT]))
        elif r < 0.75:                                   # a scalar function
            fid = random.choice([SH.FN_ABS, SH.FN_INT, SH.FN_TRUNC, SH.FN_ROUND, SH.FN_SIGN, SH.FN_SQRT,
                                 SH.FN_MOD, SH.FN_NOT, SH.FN_POWER])
            n = SH.ARITY[fid]
            if random.random() < 0.05:
                n = random.choice([1, 2, 3])               # (the wrong count: #VALUE!)
            for i in range(n):
                if fid == SH.FN_ROUND and i == 1 and random.random() < 0.8:
                    f.i(random.randrange(-20, 21))
                elif fid == SH.FN_POWER and i == 1 and random.random() < 0.8:
                    f.i(random.randrange(-6, 70))
                else:
                    self.expr(f, row, col, d - 1)
            f.call(fid, n)
        elif r < 0.92:                                   # an aggregate
            fid = random.choice(SH.AGGREGATES)
            n = random.randrange(1, 4)
            for _ in range(n):
                k = random.random()
                if k < 0.4:
                    f.rect(self.corner(row, col), self.corner(row, col))
                elif k < 0.6:
                    f.cells([self.corner(row, col) for _ in range(random.randrange(1, 4))])
                else:
                    self.expr(f, row, col, d - 1)
            f.call(fid, n)
        else:                                            # IF
            self.expr(f, row, col, d - 1)
            j = f.jz()
            self.expr(f, row, col, d - 1)
            j2 = f.jmp()
            f.patch(j)
            self.expr(f, row, col, d - 1)
            f.patch(j2)

    def sheet(self):
        sh = SH.Sheet(self.nrows, self.ncols)
        for r in range(self.nrows):
            if random.random() < 0.1:
                continue                                 # (a row with no cells)
            for c in range(self.ncols):
                k = random.random()
                if k < 0.12:
                    continue
                if k < 0.35:
                    v = random.choice(EDGE_I) if random.random() < 0.3 else random.randrange(-10 ** 6, 10 ** 6)
                    kk = rand_k()
                    sh.number(r, c, v, fmt=fmt(kk) if kk or random.random() < 0.2 else None)
                elif k < 0.45:
                    sh.number(r, c, random.randrange(-(1 << 31), 1 << 31), kind=SH.K_I32,
                              fmt=fmt(rand_k()) if random.random() < 0.3 else None)
                elif k < 0.6:
                    x = random.choice(EDGE_F) if random.random() < 0.4 else random.uniform(-1e9, 1e9)
                    sh.number(r, c, x)
                elif k < 0.65:
                    sh.text(r, c, "t%d" % c)
                else:
                    f = SH.F()
                    self.expr(f, r, c, random.randrange(1, 5))
                    kk = rand_k() if random.random() < 0.3 else 0
                    sh.formula(r, c, f.end(), fmt=fmt(kk) if kk else bytes(8))
        return sh


_power = SH.power


def power(a, b):
    """the model's POWER, but an integer to a power past 63 (|a| > 1) out of
    range at once, as it ends up (the model works out a^n first: slow)"""
    x, y = SH.as_num(a), SH.as_num(b)
    if (x.kind == "i" and y.kind == "i" and y.k & 0x7F == 0 and y.v > 63 and abs(x.v) > 1
            and x.k & 0x7F == 0):
        return SH.err(SH.E_NUM)
    return _power(a, b)


SH.power = power


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sheets", type=int, default=200)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--asm")
    ap.add_argument("--max-ops", type=int, default=3_000_000, help="a RECALC's micro-ops at most (a hang)")
    ap.add_argument("-v", action="store_true", help="each sheet's micro-ops")
    args = ap.parse_args()
    sim = US.USim(args.asm)
    sim.max_ops = args.max_ops
    bad = 0
    for s in range(args.seed, args.seed + args.sheets):
        random.seed(s)
        g = Gen(random.randrange(2, 9), random.randrange(2, 9))
        sh = g.sheet()
        m = Mem()
        try:
            desc = sh.layout(m, B + 0x100, slack=random.randrange(3), change_cap=random.choice([0, 3, 64]))
        except Exception as e:
            print(f"seed {s}: layout: {e}", file=sys.stderr)
            continue
        for rnd in range(3):
            r1, r2 = 0, 0xFFFFFFFF
            c1, c2 = 0, 0xFFFFFFFF
            if random.random() < 0.3:
                r1, r2 = sorted(random.randrange(g.nrows + 1) for _ in range(2))
            if random.random() < 0.3:
                c1, c2 = sorted(random.randrange(g.ncols + 1) for _ in range(2))
            begin, end = random.random() < 0.7, random.random() < 0.7
            mm, mu = Mem(m.b), Mem(m.b)
            merr, mres = 0, None
            try:
                mres = SH.recalc(mm, desc, r1, r2, c1, c2, begin=begin, end=end)
            except SH.ShiteFormatError as e:
                merr = 6
                if mm.read(desc, 4) == SH.MAGIC:
                    SH.put32(mm, desc + SH.D_BADROW, e.row)
            try:
                uerr, wr, ures = sim.run(0x40, r1, r2, c1, c2, int(begin) | int(end) << 1, desc, mu)
            except US.UError as e:
                uerr, wr, ures = -1, False, str(e)
            if mm.b != mu.b or uerr != merr or (merr == 0 and ures != (mres & 0xFFFFFFFF)):
                bad += 1
                diff = [i for i in range(SIZE) if mm.b[i] != mu.b[i]]
                print(f"seed {s} round {rnd}: model err {merr} R {mres}, microcode err {uerr} R {ures}; "
                      f"{len(diff)} bytes differ", file=sys.stderr)
                for i in diff[:12]:
                    print(f"   ${B + i:07X}: microcode ${mu.b[i]:02X}, model ${mm.b[i]:02X}", file=sys.stderr)
                break
            m = mm
        if args.v:
            print(f"seed {s}: {sim.ops} micro-ops so far", file=sys.stderr)
    print(f"{args.sheets} sheets, {bad} differing; {sim.ops} micro-ops", file=sys.stderr)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
