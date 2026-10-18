"""SHITE step 2 test: RECALC with integer formulas (constants, short and
long references, blank / text / error / uncompiled / F64 cells, ADD SUB MUL
NEG and the comparisons, overflow, stack errors, rounds, regions, change
lists) against the reference model (SSNAIL/shite.py, through the emulator)."""
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


ADD, SUB, MUL, NEG = SH.OP_ADD, SH.OP_SUB, SH.OP_MUL, SH.OP_NEG
sh = SH.Sheet(8, 1 << 20)
# row 0: values
sh.number(0, 0, 10); sh.number(0, 1, -32); sh.number(0, 2, 7, kind=SH.K_I32)
sh.number(0, 3, -5, kind=SH.K_I32); sh.number(0, 4, (1 << 62) + 1)
sh.add(0, 5, SH.K_EMPTY, bytes(8))
sh.text(0, 6, "abc")
sh.add(0, 7, SH.K_ERROR, struct.pack("<Q", SH.E_NA))
sh.add(0, 8, SH.K_UNCOMPILED, bytes(8) + struct.pack("<BBHHH", 0, 0, 0, 2, 0) + b"=?")
sh.number(0, 9, 2.5)
sh.number(0, 10, 5e-310)                     # subnormal: read as 0
sh.number(0, 70000, 1000)                    # a column only the long form reaches
# row 1: formulas
fs = [
    F().ref(-1, 0).ref(-1, 1).op(ADD).end(),                 # -22
    F().ref(-1, -1).ref(-1, 1).op(SUB).end(),                # 10-7 = 3 (relative: A1, C1)
    F().ref(0, 0, True, True).ref(0, 3, True, True).op(MUL).end(),   # 10 * -5
    F().ref(-1, 1).op(NEG).end(),                            # C1 = 7 -> -7
    F().ref(0, 4, True, True).ref(0, 4, True, True).op(ADD).end(),   # 2^63 + 2: #NUM!
    F().ref(0, 4, True, True).i(4).op(MUL).end(),            # #NUM!
    F().i(-(1 << 62)).i(2).op(MUL).end(),                    # -2^63 exactly
    F().i(-(1 << 62)).i(2).op(MUL).op(NEG).end(),            # #NUM!
    F().ref(0, 5, True, True).i(3).op(ADD).end(),            # empty: 0 + 3
    F().ref(0, 11, True, True).i(4).op(SUB).end(),           # no cell: 0 - 4
    F().ref(0, 6, True, True).i(1).op(ADD).end(),            # text: #VALUE!
    F().ref(0, 7, True, True).ref(0, 6, True, True).op(ADD).end(),   # #N/A first
    F().ref(0, 8, True, True).end(),                         # #COMPILE!
    F().ref(0, 9, True, True).end(),                         # F64 2.5 as the result
    F().ref(0, 10, True, True).end(),                        # 0.0
    F().ref(0, 70000, True, True).end(),                     # the long form: 1000
    F().ref(0, 70000, True, True, long=True).i(1).op(ADD).end(),
    F().ref(5, 0).end(),                                     # row 6: off the sheet? (8 rows: no)
    F().ref(20, 0).end(),                                    # #REF!
    F().i(1).i(2).end(),                                     # two values: #STACK!
    F().i(3).op(ADD).end(),                                  # one operand: #STACK!
    bytes([SH.OP_I8, 5]),                                    # no END: #STACK!
    bytes([0x40, SH.OP_END]),                                # unknown opcode: #STACK!
    F().i(2).i(3).op(SH.OP_POW).end(),                       # #NAME? (not yet)
    F().i(5).i(5).op(SH.OP_EQ).i(4).i(5).op(SH.OP_LT).op(ADD)
       .i(4).i(5).op(SH.OP_GE).op(ADD).i(-1).i(1).op(SH.OP_GT).op(ADD).end(),   # 1+1+0+0
    F().i(1 << 40).i(1 << 23).op(MUL).end(),                 # 2^63: #NUM!
    F().i(-(1 << 31)).i(-(1 << 31)).op(MUL).end(),           # 2^62
    F().ref(-1, -27).ref(0, -27).op(MUL).end(),              # A1 * A2 (a formula's result)
]
for c, code in enumerate(fs):
    sh.formula(1, c, code)
# forward references, an oscillation, a chain
sh.formula(2, 0, F().ref(2, 1).i(1).op(ADD).end())           # = B5 + 1
sh.formula(4, 1, F().ref(-3, 0).end())                       # = B2 = 3
sh.formula(3, 0, F().ref(0, 1).i(1).op(SUB).op(NEG).end())   # A4 = -(B4 - 1)
sh.formula(3, 1, F().ref(0, -1).end())                       # B4 = A4
for r in range(5, 8):
    sh.formula(r, 0, F().ref(-1, 0).i(2).op(MUL).end())
m = Mem()
desc = sh.layout(m, B + 0x200, slack=0, change_cap=8)
end = max(SH.Descriptor(m, desc).row_block(r) or 0 for r in range(8)) - B
assert end < 0x1C00, hex(end)

ALL = 0xFFFFFFFF
A = Asm()
A(I.LI, 1, z=0); A(I.LI, 2, z=ALL); A(I.LI, 3, z=0); A(I.LI, 4, z=ALL)
for k in range(3):                          # three whole-sheet rounds
    A(I.RECALC, 5, 2, x=desc, z=3, c=3 | 4 << 4)
    A(I.STR, 5, x=B + 0x1F00 + 4 * k)
    A(I.LI, 5, z=0)
# one round in two calls: rows 0-2 (BEGIN), then rows 3-7, columns 0-0 (END)
A(I.LI, 6, z=2); A(I.LI, 7, z=3)
A(I.RECALC, 5, 6, x=desc, z=1, c=3 | 4 << 4)
A(I.STR, 5, x=B + 0x1F10)
A(I.LI, 5, z=3); A(I.LI, 8, z=0)
A(I.RECALC, 5, 2, x=desc, z=2, c=3 | 8 << 4)
A(I.STR, 5, x=B + 0x1F14)
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
counts = struct.unpack("<5I", expect[0x1F00:0x1F0C] + expect[0x1F10:0x1F18])
print(f"program {len(code) // 16} instructions; {len(fs)} + 7 formulas; changed per call {counts}; "
      f"halt pc ${mach.pc:07X}", file=sys.stderr)


def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


with open("shite2_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package shite2_pkg is\n")
    f.write("  type wordsh_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {mach.pc};\n")
    for name, data in (("INIT", bytes(init)), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : wordsh_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
