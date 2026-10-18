"""SHITE step 4 test: RECALC with F64 (IEEE double, round to nearest even,
subnormals flushed after rounding; specials, ties, cancellation, results at
the smallest normal, conversions from integers and fixed point, compares)
against the reference model (SSNAIL/shite.py, through the emulator)."""
import os
import struct
import sys
_here = os.path.dirname(os.path.abspath(__file__))
_tools = os.environ.get("SSNAIL_TOOLS")
if not _tools:
    for _c in (os.path.join(_here, "SSNAIL"), os.path.join(_here, "SSNAIL", "ssnail_tools")):
        if os.path.exists(os.path.join(_c, "ssnail_isa.py")):
            _tools = _c
            break
sys.path.insert(0, _tools or os.path.join(_here, "SSNAIL"))
import ssnail_isa as I
from ssnail_convert import Asm
import ssnail_sim as S
import shite as SH
from shite import F

B = I.HYPERRAM_BASE
MEM = 0x8000                                # the bench's memory: 32 KB


class Mem:
    def __init__(self):
        self.b = bytearray(MEM)

    def read(self, a, n):
        return bytes(self.b[a - B:a - B + n])

    def write(self, a, d):
        self.b[a - B:a - B + len(d)] = d


import math
import random
ADD, SUB, MUL, DIV, NEG = SH.OP_ADD, SH.OP_SUB, SH.OP_MUL, SH.OP_DIV, SH.OP_NEG
EQ, LT, GE, NE = SH.OP_EQ, SH.OP_LT, SH.OP_GE, SH.OP_NE
rnd = random.Random(2026)
inf, nan = float("inf"), float("nan")
MINN = 2.2250738585072014e-308
specials = [0.0, -0.0, inf, -inf, nan, 1.0, -1.0, 1.5, 2.0, 3.0, 0.1, 0.2, 0.3, 1e308, -1e308,
            1.7976931348623157e308, MINN, -MINN, MINN * 1.5, MINN * 2, 1e-300, 1e-154, 1.0000000000000002,
            0.9999999999999999, 2.0 ** 53, 2.0 ** 53 + 2, 123456789.123, -7.25, 2.0 ** -511,
            2.0 ** -511 * (1 - 2.0 ** -53), 2.0 ** -512 * 3, 1 / 3]


def rdouble():
    """A random finite normal double, any exponent."""
    while True:
        b = rnd.getrandbits(64)
        e = b >> 52 & 0x7FF
        if 0 < e < 0x7FF:
            return struct.unpack("<d", struct.pack("<Q", b))[0]


def rnear(e):
    """A random double with exponent near e."""
    return math.ldexp(1 + rnd.random(), e) * rnd.choice((1, -1))


cases = []
ops = [ADD, SUB, MUL, DIV]
for a in specials:                               # every special with a few others
    for b in rnd.sample(specials, 5):
        cases.append(F().f(a).f(b).op(rnd.choice(ops)).end())
for _ in range(90):                              # random, any exponents
    cases.append(F().f(rdouble()).f(rdouble()).op(rnd.choice(ops)).end())
for _ in range(60):                              # close exponents: cancellation, ties
    e = rnd.randint(-60, 60)
    cases.append(F().f(rnear(e)).f(rnear(e + rnd.randint(-2, 2))).op(rnd.choice([ADD, SUB])).end())
for _ in range(40):                              # products and quotients near the smallest normal
    e = rnd.randint(-530, -495)
    cases.append(F().f(rnear(e)).f(rnear(-1022 - e + rnd.randint(-2, 2))).op(MUL).end())
    cases.append(F().f(rnear(-1022 + e // 8)).f(rnear(e // 8 + rnd.randint(-1, 1))).op(DIV).end())
for a, b in ((2.0 ** 53, 1.0), (2.0 ** 53, 3.0), (2.0 ** 52 + 1, 0.5), (1.0, 2.0 ** -53), (1.0, 2.0 ** -53 * 1.5)):
    cases.append(F().f(a).f(b).op(ADD).end())
for v in (2 ** 53 + 1, 2 ** 53 + 3, 2 ** 63 - 1, -2 ** 63, 2 ** 60 + 12345, -987654321987, 7):
    cases.append(F().i(v).f(0.0).op(ADD).end())                  # integers to F64
for v, k in ((1999, 2), (-1, 18), (123456789012345678, 18), (5, 1), (-31415926535, 10)):
    cases.append(F().i(v).fix(k).f(1.0).op(MUL).end())           # decimal fixed point to F64
    cases.append(F().i(v).fix(k).end())                          # stored without a fixed point
for v, k in ((24, 0x84), (-(2 ** 62), 0x80 | 62), (12345, 0x80 | 40), (3, 0x81)):
    cases.append(F().i(v).fix(k).f(0.0).op(ADD).end())           # binary fixed point to F64
    cases.append(F().i(v).fix(k).end())
for _ in range(20):                              # comparisons, mixed
    cmp = rnd.choice([EQ, LT, GE, NE])
    a, b = rnd.choice(specials + [rdouble()]), rnd.choice(specials + [rdouble()])
    cases.append(F().f(a).f(b).op(cmp).end())
for _ in range(10):                              # comparisons, integer with F64
    cases.append(F().i(rnd.randint(-5, 5)).f(rnd.choice([-0.0, 0.0, 2.5, -2.5, nan, inf])).op(rnd.choice([EQ, LT, GE, NE])).end())
for _ in range(20):                              # chains through infinities and NaN
    cases.append(F().f(rnd.choice(specials)).f(rnd.choice(specials)).op(rnd.choice(ops))
                 .f(rnd.choice(specials)).op(rnd.choice(ops)).f(0.5).op(LT).end())
# at the smallest normal: a tie that rounds up to it (kept), and just below
# it (a subnormal: flushed), by MUL and by DIV
for x, y, o in ((2.0 ** -511, 2.0 ** -511 * (1 - 2.0 ** -53), MUL),
                (2.0 ** -511, 2.0 ** -511 * (1 - 2.0 ** -52), MUL),
                (-(2.0 ** -1021) * (1 - 2.0 ** -53), 2.0, DIV),
                (2.0 ** -1021 * (1 - 2.0 ** -52), 2.0, DIV),
                (2.0 ** -1000, 2.0 ** -22 * (1 - 2.0 ** -53), MUL),
                (2.0 ** -1021, 4.0, DIV),
                (2.0 ** -1022 * (1 + 2.0 ** -52), 0.5, MUL)):
    cases.append(F().f(x).f(y).op(o).end())
cases.append(F().i(10).i(4).op(DIV).end())       # integers divided: F64 2.5
cases.append(F().i(1).f(0.0).op(DIV).end())      # #DIV/0!
cases.append(F().f(1.0).f(-0.0).op(DIV).end())   # #DIV/0!
cases.append(F().f(5e-324).end())                # a subnormal constant: 0
cases.append(F().f(2.0).op(NEG).end())
PER_ROW = 48
NROWS = (len(cases) + PER_ROW - 1) // PER_ROW
sh = SH.Sheet(NROWS, 64)
for n, code in enumerate(cases):
    sh.formula(n // PER_ROW, n % PER_ROW, code)
m = Mem()
desc = sh.layout(m, B + 0x200, slack=0, change_cap=8)
end = max(SH.Descriptor(m, desc).row_block(r) or 0 for r in range(NROWS)) - B
assert end < 0x7C00, hex(end)

ALL = 0xFFFFFFFF
A = Asm()
A(I.LI, 1, z=0); A(I.LI, 2, z=ALL); A(I.LI, 3, z=0); A(I.LI, 4, z=ALL)
A(I.RECALC, 5, 2, x=desc, z=3, c=3 | 4 << 4)
A(I.STR, 5, x=B + 0x7F00)
A(I.HALT)
code = A.assemble(B)
assert len(code) <= 0x200, len(code)
init = bytearray(m.b)
init[:len(code)] = code

mach = S.Machine.__new__(S.Machine)
mach.mem = bytearray(8 << 20)
mach.mem[:MEM] = init
mach.R, mach.A, mach.N, mach.pc = [0] * 16, [0] * 16, [0] * 3, 0
mach.stats = dict(instructions=0, bytes_read=0, bytes_written=0)
mach.on_argmax = mach.on_sync = None
mach.trace = False
mach.hw = True
mach.run(B)
expect = bytes(mach.mem[:MEM])
counts = struct.unpack("<I", expect[0x7F00:0x7F04])
print(f"program {len(code) // 16} instructions; {len(cases)} formulas; changed {counts}; "
      f"halt pc ${mach.pc:07X}", file=sys.stderr)


def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


with open("shite4_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package shite4_pkg is\n")
    f.write("  type wordsh_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {mach.pc};\n")
    for name, data in (("INIT", bytes(init)), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : wordsh_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
