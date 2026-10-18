"""SHITE step 5 test: RECALC with ranges, cell lists, the aggregates (SUM,
AVERAGE, MIN, MAX, COUNT), host calls and the operators not built yet,
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
MEM = 0x2000


class Mem:
    def __init__(self):
        self.b = bytearray(MEM)

    def read(self, a, n):
        return bytes(self.b[a - B:a - B + n])

    def write(self, a, d):
        self.b[a - B:a - B + len(d)] = d


ADD, SUB, MUL, DIV, NEG = SH.OP_ADD, SH.OP_SUB, SH.OP_MUL, SH.OP_DIV, SH.OP_NEG
SUM, AVG, MIN, MAX, COUNT = SH.FN_SUM, SH.FN_AVERAGE, SH.FN_MIN, SH.FN_MAX, SH.FN_COUNT
BIG = 1 << 22                                 # a column past 64K


def fmt(k):
    return bytes([1, k & 0x7F, k, 0, 0, 0, 0, 0])


sh = SH.Sheet(12, 1 << 24)
# rows 0-4: data, with gaps, text, blanks, F64, fixed point, a far column
sh.number(0, 0, 1); sh.number(0, 1, 2); sh.number(0, 2, 3); sh.text(0, 3, "x"); sh.number(0, BIG, 1000)
sh.number(1, 0, 10); sh.add(1, 1, SH.K_EMPTY, bytes(8)); sh.number(1, 2, 2.5); sh.number(1, 3, 125, fmt=fmt(2))
# row 2: empty
sh.number(3, 0, -4); sh.number(3, 2, 7); sh.number(3, 3, -0.5)
sh.number(4, 0, (1 << 62)); sh.number(4, 1, (1 << 62)); sh.number(4, 2, 1)
sh.add(4, 3, SH.K_ERROR, struct.pack("<Q", SH.E_NA))
sh.number(5, 0, 5); sh.number(5, 1, 0)
sh.number(10, 50, 77)                         # a host call's result cell
A_ = lambda r, c: (r, c, True, True)
fs = [
    F().rect(A_(0, 0), A_(1, 3)).call(SUM, 1).end(),           # 1+2+3+10+2.5+1.25
    F().rect(A_(0, 0), A_(3, 2)).call(COUNT, 1).end(),         # 1,2,3,10,2.5,-4,7: 7
    F().rect(A_(0, 0), A_(3, 3)).call(MIN, 1).end(),           # -4
    F().rect(A_(0, 0), A_(3, 3)).call(MAX, 1).end(),           # 10
    F().rect(A_(0, 0), A_(3, 3)).call(AVG, 1).end(),
    F().rect(A_(3, 3), A_(0, 0)).call(SUM, 1).end(),           # reversed corners
    F().rect(A_(0, 0), A_(0, BIG)).call(SUM, 1).end(),         # + the far column
    F().rect(A_(2, 0), A_(2, 9)).call(SUM, 1).end(),           # an empty row: 0
    F().rect(A_(2, 0), A_(2, 9)).call(AVG, 1).end(),           # #DIV/0!
    F().rect(A_(2, 0), A_(2, 9)).call(MIN, 1).end(),           # 0
    F().rect(A_(2, 0), A_(2, 9)).call(COUNT, 1).end(),         # 0
    F().rect(A_(0, 0), A_(4, 3)).call(SUM, 1).end(),           # #N/A in the range
    F().rect(A_(4, 0), A_(4, 2)).call(SUM, 1).end(),           # 2^62 + 2^62: #NUM!
    F().rect(A_(4, 0), A_(4, 3)).call(SUM, 1).end(),           # overflow, then #N/A: #N/A
    F().rect(A_(0, 0), A_(30, 3)).call(SUM, 1).end(),          # off the sheet: #REF!
    F().ref(-6, -15).ref(-6, -14).i(5).call(SUM, 3).end(),     # values and references
    F().ref(-6, -13).ref(-6, -12).call(COUNT, 2).end(),        # text from a reference skipped: 1
    F().ref(-5, -16).call(COUNT, 1).end(),                     # a blank: 0
    F().ref(-5, -17).call(COUNT, 1).end(),                     # B2 is EMPTY: 0
    F().cells([A_(0, c) for c in (0, 1, 2)] * 13 + [A_(1, 0)]).call(SUM, 1).end(),   # 40 cells
    F().cells([A_(0, 0), A_(40, 0)]).call(SUM, 1).end(),       # #REF! in the list
    F().rect(A_(0, 0), A_(0, 2)).rect(A_(3, 0), A_(3, 2)).call(SUM, 2).call(SUM, 1).end(),  # nested
    F().rect(A_(0, 0), A_(1, 0)).call(MAX, 1).rect(A_(3, 0), A_(3, 3)).call(MIN, 1).op(SUB).end(),
    F().i(1).i(2).call(7, 2).i(5).op(ADD).end(),                # ABS (not yet): #NAME?
    F().i(1).call(SUM, 2).end(),                                # too few arguments: #STACK!
    F().call(SUM, 0).end(),                                     # no arguments: 0
    F().call(AVG, 0).end(),                                     # #DIV/0!
    F().host("LOOKUP(A1)", 10, 50).i(1).op(ADD).end(),          # 78
    F().host("X()", 10, 51).end(),                              # an empty result cell: 0
    F().i(2).i(3).op(SH.OP_POW).end(),                          # #NAME?
    F().i(1).op(SH.OP_PCT).end(),                               # #NAME?
    F().i(1).op(SH.OP_PCT).i(2).end(),                          # two values: #STACK!
    F().i(1).i(2).op(SH.OP_CONCAT).end(),                       # #NAME?
    bytes([SH.OP_STR, 3]) + b"abc" + bytes([SH.OP_END]),        # #NAME?
    F().rect(A_(5, 0), A_(5, 1)).call(MIN, 1).end(),            # 0
    F().rect(A_(1, 2), A_(3, 3)).call(MIN, 1).end(),            # -0.5 (F64) vs 1.25 (fixed), 7
    F().rect(A_(1, 2), A_(3, 3)).call(MAX, 1).end(),
    F().rect(A_(0, 0), A_(5, 2)).call(COUNT, 1).i(2).op(MUL).end(),
]
for c, code in enumerate(fs):
    sh.formula(6 + c // 20, c % 20, code)
m = Mem()
desc = sh.layout(m, B + 0x200, slack=0, change_cap=8)
end = max(SH.Descriptor(m, desc).row_block(r) or 0 for r in range(12)) - B
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


with open("shite5_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package shite5_pkg is\n")
    f.write("  type wordsh_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {mach.pc};\n")
    for name, data in (("INIT", bytes(init)), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : wordsh_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
