"""SHITE step 7 test: RECALC with SQRT (correctly rounded), POW / POWER
(exact integers and fixed point, F64 square and multiply) and ROUND (fixed
point and F64 exactly) against the reference model
(SSNAIL/shite.py, through the emulator)."""
import os
import struct
import sys
_here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # src/vhdl
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


POW, ROUND, SQRT, POWER = SH.OP_POW, SH.FN_ROUND, SH.FN_SQRT, SH.FN_POWER


def fmt(k):
    return bytes([1, k & 0x7F, k, 0, 0, 0, 0, 0])


cases = []
for _ in range(120):                             # square roots, any exponent
    cases.append(F().f(abs(rdouble())).call(SQRT, 1).end())
for _ in range(40):
    cases.append(F().f(rnd.random() * 10 ** rnd.randint(-5, 5)).call(SQRT, 1).end())
for x in (0.0, -0.0, 4.0, 2.0, inf, -inf, nan, -1.0, MINN, 1.7976931348623157e308):
    cases.append(F().f(x).call(SQRT, 1).end())
for v in (2, 144, 10 ** 18, -4, 0):
    cases.append(F().i(v).call(SQRT, 1).end())
cases.append(F().i(1999).fix(2).call(SQRT, 1).end())
# powers: exact integers and fixed point, F64 by square and multiply
for a, n in ((2, 10), (-3, 5), (2, 62), (2, 63), (-2, 63), (10, 18), (10, 19), (1, 10 ** 12), (-1, 10 ** 12 + 1),
             (0, 5), (0, 0), (0, -1), (7, 0), (3, 40), (-1, 0)):
    cases.append(F().i(a).i(n).op(POW).end())
for a, k, n in ((125, 2, 2), (15, 1, 3), (5, 6, 3), (12, 0x82, 3), (3, 9, 2), (3, 10, 2), (25, 1, 19)):
    cases.append(F().i(a).fix(k).i(n).op(POW).end())
for a, n in ((2.0, 10), (1.5, -3), (0.1, 7), (-2.5, 5), (10.0, 400), (10.0, -400), (1e-200, 2), (-0.0, 3),
             (-0.0, -3), (inf, 2), (inf, -2), (nan, 2), (3.0, 2 ** 40 + 1), (1.0000001, 10 ** 9), (2, -2)):
    cases.append(F().f(a).i(n).call(POWER, 2).end() if isinstance(a, float) else F().i(a).i(n).call(POWER, 2).end())
cases.append(F().i(2).f(0.5).op(POW).end())      # a fractional exponent: #NAME? (for now)
cases.append(F().i(2).call(POWER, 1).end())      # #VALUE!
# ROUND: decimal fixed point exactly, F64 through F64(10^n)
for v, k, n in ((12345, 3, 1), (12345, 3, 2), (-12345, 3, 2), (125, 2, 1), (-125, 2, 1), (99, 0, -1), (-95, 0, -1),
                (123456789, 0, -3), (5, 0, -1), (1999, 2, 5), (1999, 2, 0), (7, 0, 18), (9, 0, -18),
                (4999999999999999999 // 1, 0, -18), (12345, 3, -19), (1, 0, -2)):
    cases.append(F().i(v).fix(k).i(n).call(ROUND, 2).end())
for x, n in ((2.675, 2), (2.5, 0), (-2.5, 0), (0.5, 0), (0.49999999999999994, 0), (1234.5678, -2), (-1234.5678, 1),
             (1e300, 2), (1e-300, 5), (inf, 1), (nan, 1), (-0.25, 0), (123456789012345.67, 1), (0.1, 15), (5.5e15, 0)):
    cases.append(F().f(x).i(n).call(ROUND, 2).end())
for x, n in ((1.005, 2), (0.125, 2), (-0.125, 2), (1e-20, 3), (-1e-20, 3), (4503599627370495.5, 0),
             (2.0 ** 52 + 0.5, 0), (1e15 + 0.3, 1), (9.2e18, -2), (-9.2e18, -1), (1e19, -1), (0.0049, 2),
             (-0.0051, 2), (123.456, -1), (55.0, -2), (-45.0, -1), (2.0 ** -1074 * 2 ** 52, 3)):
    cases.append(F().f(x).i(n).call(ROUND, 2).end())
cases.append(F().f(1.5).i(19).call(ROUND, 2).end())        # #NUM!
cases.append(F().f(1.5).f(1.0).call(ROUND, 2).end())       # n not an integer: #NUM!
cases.append(F().i(25).fix(0x82).i(1).call(ROUND, 2).end())  # binary fixed point: F64
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


with open("shite7_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package shite7_pkg is\n")
    f.write("  type wordsh_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {mach.pc};\n")
    for name, data in (("INIT", bytes(init)), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : wordsh_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
