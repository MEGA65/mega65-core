"""SHITE step 3 test: RECALC with fixed point (alignment, rescaling to the
cell's format, division, binary fixed point, FIX, overflow, bad fixed
points) against the reference model (SSNAIL/shite.py, through the emulator)."""
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
MEM = 0x2000


class Mem:
    def __init__(self):
        self.b = bytearray(MEM)

    def read(self, a, n):
        return bytes(self.b[a - B:a - B + n])

    def write(self, a, d):
        self.b[a - B:a - B + len(d)] = d


ADD, SUB, MUL, DIV, NEG = SH.OP_ADD, SH.OP_SUB, SH.OP_MUL, SH.OP_DIV, SH.OP_NEG
EQ, LT = SH.OP_EQ, SH.OP_LT


def fmt(k):
    return bytes([1, k & 0x7F, k, 0, 0, 0, 0, 0])


sh = SH.Sheet(4, 64)
# row 0: fixed-point values
sh.number(0, 0, 1999, fmt=fmt(2))            # 19.99
sh.number(0, 1, 3)
sh.number(0, 2, 15, fmt=fmt(1))              # 1.5
sh.number(0, 3, 150, fmt=fmt(2))             # 1.50
sh.number(0, 4, 1234, fmt=fmt(3))            # 1.234
sh.number(0, 5, 1000, fmt=fmt(2))            # 10.00
sh.number(0, 6, 300, fmt=fmt(2))             # 3.00
sh.number(0, 7, 24, fmt=fmt(0x84))           # 1.5 (binary, 2^-4)
sh.number(0, 8, 1, fmt=fmt(0x82))            # 0.25 (binary, 2^-2)
sh.number(0, 9, -200, fmt=fmt(2))            # -2.00
sh.number(0, 10, 100, fmt=fmt(2))            # 1.00
sh.number(0, 11, 800, fmt=fmt(2))            # 8.00
sh.number(0, 12, 0, fmt=fmt(2))              # 0.00
sh.number(0, 13, 1 << 62)
sh.number(0, 14, 7, fmt=fmt(19))             # bad data: k 19
A_ = lambda c: (0, c, True, True)
fs = [
    (F().ref(*A_(0)).ref(*A_(1)).op(MUL).end(), 2),          # 59.97
    (F().ref(*A_(0)).i(1).op(ADD).end(), 2),                 # 20.99
    (F().ref(*A_(0)).ref(*A_(4)).op(ADD).end(), 2),          # 21.224 -> 21.22
    (F().ref(*A_(0)).ref(*A_(4)).op(SUB).end(), 3),          # 18.756
    (F().ref(*A_(0)).end(), 4),                              # 19.9900
    (F().ref(*A_(1)).end(), 2),                              # 3.00
    (F().ref(*A_(2)).ref(*A_(3)).op(EQ).end(), 0),           # 1.5 = 1.50: 1
    (F().ref(*A_(4)).ref(*A_(2)).op(LT).end(), 0),           # 1.234 < 1.5: 1
    (F().ref(*A_(0)).ref(*A_(0)).op(MUL).end(), 2),          # 399.6001 -> 399.60
    (F().ref(*A_(5)).ref(*A_(6)).op(DIV).end(), 2),          # 3.33
    (F().ref(*A_(9)).ref(*A_(6)).op(DIV).end(), 2),          # -0.67
    (F().ref(*A_(10)).ref(*A_(11)).op(DIV).end(), 2),        # 0.125 -> 0.13
    (F().ref(*A_(10)).ref(*A_(11)).op(DIV).op(NEG).end(), 2),  # -0.13
    (F().ref(*A_(5)).ref(*A_(12)).op(DIV).end(), 2),         # #DIV/0!
    (F().ref(*A_(7)).ref(*A_(8)).op(ADD).end(), 0x84),       # 1.75: 28 / 16
    (F().ref(*A_(7)).i(2).op(MUL).end(), 0x84),              # 3.0: 48
    (F().i(1999).fix(2).end(), 2),                           # 19.99
    (F().i(1999).fix(2).ref(*A_(6)).op(ADD).end(), 2),       # 22.99
    (F().ref(0, 0).fix(2).end(), 2),                         # blank: #VALUE!
    (F().i(1).i(0).op(DIV).fix(2).end(), 2),                 # the error stays: #DIV/0!
    (F().ref(*A_(13)).i(1).fix(18).op(ADD).end(), 18),       # 2^62 x 10^18: #NUM!
    (F().ref(*A_(13)).end(), 2),                             # 2^62 x 100 into k 2: #NUM!
    (F().i(7).fix(19).i(1).op(ADD).end(), 2),                # k 19: #NUM!
    (F().ref(*A_(14)).end(), 2),                             # a cell with k 19: #NUM!
    (F().i(5).end(), 19),                                    # into a cell with k 19: #NUM!
    (F().i(-5).fix(0x80 | 63).op(NEG).end(), 0x84),          # binary k 63: #NUM!
    (F().ref(*A_(9)).ref(*A_(6)).op(MUL).end(), 2),          # -6.00
    (F().i(-125).fix(3).end(), 2),                           # -0.125 -> -0.13 (half away)
]
for c, (code, k) in enumerate(fs):
    sh.formula(1, c, code, fmt=fmt(k))
m = Mem()
desc = sh.layout(m, B + 0x200, slack=0, change_cap=8)
end = max(SH.Descriptor(m, desc).row_block(r) or 0 for r in range(4)) - B
assert end < 0x1C00, hex(end)

ALL = 0xFFFFFFFF
A = Asm()
A(I.LI, 1, z=0); A(I.LI, 2, z=ALL); A(I.LI, 3, z=0); A(I.LI, 4, z=ALL)
A(I.RECALC, 5, 2, x=desc, z=3, c=3 | 4 << 4)
A(I.STR, 5, x=B + 0x1F00)
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
counts = struct.unpack("<I", expect[0x1F00:0x1F04])
print(f"program {len(code) // 16} instructions; {len(fs)} formulas; changed {counts}; "
      f"halt pc ${mach.pc:07X}", file=sys.stderr)


def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


with open("shite3_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package shite3_pkg is\n")
    f.write("  type wordsh_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {mach.pc};\n")
    for name, data in (("INIT", bytes(init)), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : wordsh_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
