"""SHITE step 6 test: RECALC with IF (JZ / JMP), %, AND OR NOT, PRODUCT,
COUNTA, ABS SIGN INT TRUNC MOD, against the reference model
(SSNAIL/shite.py, through the emulator)."""
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


sh = SH.Sheet(12, 64)
FN = SH
sh.number(0, 0, 3); sh.number(0, 1, -7); sh.number(0, 2, 0); sh.text(0, 3, "t")
sh.add(0, 4, SH.K_EMPTY, bytes(8)); sh.number(0, 5, -2.5); sh.number(0, 6, 1999, fmt=fmt(2))
sh.add(0, 7, SH.K_ERROR, struct.pack("<Q", SH.E_NA)); sh.number(0, 8, -125, fmt=fmt(2))
sh.number(0, 9, 25, fmt=fmt(0x82))           # 6.25 binary
A_ = lambda c: (0, c, True, True)


def IF(c, t, e):
    """IF(c, t, e) by the canonical pattern: c, t, e are F builders' bytes
    (without END)."""
    f = F()
    f.b += c
    jz = f.jz()
    f.b += t
    jm = f.jmp()
    f.patch(jz)
    f.b += e
    f.patch(jm)
    return f


def frag(build):
    return bytes(build(F()).b)


fs = [
    IF(frag(lambda f: f.i(1)), frag(lambda f: f.i(10)), frag(lambda f: f.i(20))).end(),
    IF(frag(lambda f: f.ref(*A_(2))), frag(lambda f: f.i(10)), frag(lambda f: f.i(20))).end(),   # 0: else
    IF(frag(lambda f: f.ref(*A_(4))), frag(lambda f: f.i(10)), frag(lambda f: f.i(1).i(0).op(DIV))).end(),  # blank: else, #DIV/0!
    IF(frag(lambda f: f.f(-0.0)), frag(lambda f: f.i(1).i(0).op(DIV)), frag(lambda f: f.i(2))).end(),    # the untaken branch's error unseen: 2
    IF(frag(lambda f: f.ref(*A_(7))), frag(lambda f: f.i(1)), frag(lambda f: f.i(2))).end(),     # #N/A
    IF(frag(lambda f: f.ref(*A_(3))), frag(lambda f: f.i(1)), frag(lambda f: f.i(2))).end(),     # text: #VALUE!
    IF(frag(lambda f: f.b.extend(IF(frag(lambda g: g.i(0)), frag(lambda g: g.i(1)), frag(lambda g: g.i(0))).b) or f),
       frag(lambda f: f.b.extend(IF(frag(lambda g: g.i(1)), frag(lambda g: g.i(5)), frag(lambda g: g.i(6))).b) or f),
       frag(lambda f: f.i(7))).i(100).op(ADD).end(),                                          # nested: 107
    F().i(5).op(SH.OP_PCT).end(), F().ref(*A_(6)).op(SH.OP_PCT).end(), F().f(50.0).op(SH.OP_PCT).end(),
    F().ref(*A_(9)).op(SH.OP_PCT).end(),                                                    # binary: F64
    F().i(5).fix(17).op(SH.OP_PCT).end(),                                                   # k 19: F64
    F().ref(*A_(0)).ref(*A_(2)).call(FN.FN_AND, 2).end(), F().ref(*A_(0)).ref(*A_(1)).call(FN.FN_AND, 2).end(),
    F().ref(*A_(2)).ref(*A_(4)).call(FN.FN_OR, 2).end(), F().ref(*A_(3)).ref(*A_(4)).call(FN.FN_OR, 2).end(),  # #VALUE!
    F().rect(A_(0), A_(6)).call(FN.FN_OR, 1).end(), F().ref(*A_(0)).ref(*A_(7)).call(FN.FN_AND, 2).end(),
    F().rect(A_(0), A_(1)).call(FN.FN_PRODUCT, 1).end(), F().rect(A_(0), A_(9)).call(FN.FN_COUNTA, 1).end(),
    F().rect(A_(0), A_(6)).call(FN.FN_PRODUCT, 1).end(), F().call(FN.FN_PRODUCT, 0).end(),
    F().i(1 << 40).i(1 << 30).call(FN.FN_PRODUCT, 2).end(),                                 # #NUM!
    F().ref(*A_(1)).call(FN.FN_ABS, 1).end(), F().ref(*A_(8)).call(FN.FN_ABS, 1).end(),
    F().i(-(1 << 62)).i(2).op(MUL).call(FN.FN_ABS, 1).end(), F().ref(*A_(5)).call(FN.FN_ABS, 1).end(),
    F().ref(*A_(1)).call(FN.FN_SIGN, 1).end(), F().f(-0.0).call(FN.FN_SIGN, 1).end(), F().ref(*A_(5)).call(FN.FN_SIGN, 1).end(),
    F().ref(*A_(8)).call(FN.FN_INT, 1).end(), F().ref(*A_(8)).call(FN.FN_TRUNC, 1).end(),    # -1.25: -2, -1
    F().ref(*A_(5)).call(FN.FN_INT, 1).end(), F().ref(*A_(5)).call(FN.FN_TRUNC, 1).end(),    # -3.0, -2.0
    F().f(-0.25).call(FN.FN_TRUNC, 1).end(), F().f(-0.0).call(FN.FN_INT, 1).end(),           # -0.0
    F().ref(*A_(9)).call(FN.FN_INT, 1).end(), F().f(1e300).call(FN.FN_INT, 1).end(),
    F().i(7).i(3).call(FN.FN_MOD, 2).end(), F().i(-7).i(3).call(FN.FN_MOD, 2).end(), F().i(7).i(-3).call(FN.FN_MOD, 2).end(),
    F().ref(*A_(6)).i(3).call(FN.FN_MOD, 2).end(), F().f(5.5).f(-2.0).call(FN.FN_MOD, 2).end(),
    F().i(5).i(0).call(FN.FN_MOD, 2).end(), F().ref(*A_(5)).ref(*A_(6)).call(FN.FN_MOD, 2).end(),
    F().ref(*A_(2)).call(FN.FN_NOT, 1).end(), F().ref(*A_(0)).call(FN.FN_NOT, 1).end(), F().ref(*A_(4)).call(FN.FN_NOT, 1).end(),
    F().i(1).i(2).call(FN.FN_ABS, 2).end(), F().rect(A_(0), A_(1)).call(FN.FN_ABS, 1).end(),   # #VALUE!
    F().i(1).call(FN.FN_SQRT, 1).end(),                                                     # (not yet) #NAME?
]
for c, code in enumerate(fs):
    sh.formula(1 + c // 20, c % 20, code, fmt=fmt(0) if c != 8 else fmt(4))
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


with open("shite6_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package shite6_pkg is\n")
    f.write("  type wordsh_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {mach.pc};\n")
    for name, data in (("INIT", bytes(init)), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : wordsh_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
