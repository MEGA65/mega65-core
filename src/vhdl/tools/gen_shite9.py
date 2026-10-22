"""SHITE step 9 test: MOVE_CELLS and CELLS_MOVED (as SSNAIL instructions)
against the reference model (SSNAIL/shite.py, through the emulator).
Four jobs, run in turn: the moves (a row inserted, a block cut and pasted
over itself, a row deleted, columns moved off the sheet's edge, a move
fixing only some rows, an empty source; CELLS_MOVED after a move made by
hand), then three that fail and must leave the sheet as it was (a heap
too small; a reference too far for its form, by each instruction)."""
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
import numpy as np
import ssnail_isa as I
from ssnail_convert import Asm
import ssnail_sim as S
import shite as SH

B = I.HYPERRAM_BASE
MEM = 0x20000                               # the bench's memory: 128 KB
ALL = 0xFFFFFFFF


class Mem:
    def __init__(self):
        self.b = bytearray(MEM)

    def read(self, a, n):
        return bytes(self.b[a - B:a - B + n])

    def write(self, a, d):
        self.b[a - B:a - B + len(d)] = d


def sheet(rng, nrows=14, ncols=16, filled=12):
    """Numbers in columns 0-3, formulas in 4-9 referring to them and to each
    other: every reference kind and form, and every opcode the walk skips."""
    sh = SH.Sheet(nrows, ncols)
    for r in range(filled):
        for c in range(4):
            if (r + c) % 5:
                sh.number(r, c, int(rng.integers(-50, 50)))
    F = SH.F
    for r in range(filled):
        R = lambda: int(rng.integers(0, filled))
        C = lambda: int(rng.integers(0, 4))
        for c in range(4, 10):
            k = (r * 7 + c) % 8
            if k == 0:
                rr, cc = R(), C()
                f = F().ref(rr - r, cc - c).ref(rr, cc, True, True).op(SH.OP_ADD)
            elif k == 1:
                rr, cc = R(), C()
                f = F().ref(rr - r, cc, False, True, long=True).ref(rr, cc - c, True, False).op(SH.OP_SUB)
            elif k == 2:
                a, b = sorted((R(), R()))
                f = F().rect((a - r, 0 - c, False, False), (b, 3, True, True, True)).call(0, 1)
            elif k == 3:
                f = F().cells([(R() - r, C() - c, False, False), (R(), C(), True, True, True),
                               (R() - r, C() - c, False, False)]).call(0, 1)
            elif k == 4:
                f = F().host("HOST(%d)" % r, R(), C())
            elif k == 5:                             # IF: jumps over references
                rr = R()
                f = F().ref(rr - r, 0 - c).i(0).op(SH.OP_GT)
                j = f.jz(); f.ref(rr - r, 4 - c); j2 = f.jmp(); f.patch(j); f.i(-1); f.patch(j2)
            elif k == 6:                             # constants of every size, STR, FIX
                f = F().i(1000000).fix(2).ref(R() - r, C() - c).op(SH.OP_MUL).f(1.5) \
                    .ref(R() - r, C() - c).op(SH.OP_ADD).op(SH.OP_ADD).i(1 << 40).ref(R(), C(), True, False) \
                    .op(SH.OP_ADD).op(SH.OP_ADD)
                f.b += bytes([SH.OP_STR, 3]) + b"abc"
                f.ref(R() - r, C() - c).op(SH.OP_CONCAT).op(SH.OP_CONCAT).i(7).op(SH.OP_ADD)
            else:                                    # a long-form RECT, a long count
                f = F().rect((R() - r, 0 - c, False, False, True), (R(), C(), True, False)).call(0, 1)
                f.b += bytes([SH.OP_CALL, 0x80, 0x00, 0x01])
            sh.formula(r, c, f.end())
    # bytecode the walk must stop in: an unknown opcode before a reference,
    # and a reference cut short by the bytecode's length
    sh.formula(filled - 1, 10, bytes([0x30]) + F().ref(-1, -10).end())
    sh.formula(filled - 2, 10, F().ref(-1, -10).end()[:3])
    return sh


rng = np.random.default_rng(953)
m = Mem()
PROG, PB, RES = B, B + 0x800, B + 0xC00          # jobs; parameter blocks; results
HEAP = B + 0x10000                               # each move's heap: 6 KB
desc_a = sheet(rng).layout(m, B + 0x1000, slack=1)
rng = np.random.default_rng(77)
sb = sheet(rng)
# sheet B: the cells of rows 3-8, columns 1-6 copied by hand (bytecode as
# it was) to rows 6-11, columns 3-8, for CELLS_MOVED
src_b, dst_b = (3, 1, 8, 6), (6, 3)
rows = {}
for r, cl in sb.rows.items():
    for col, kf, body in cl:
        if 3 <= r <= 8 and 1 <= col <= 6:
            rows.setdefault(r + 3, []).append((col + 2, kf | SH.F_CHANGED, body))
        elif not (6 <= r <= 11 and 3 <= col <= 8):
            rows.setdefault(r, []).append((col, kf, body))
sb.rows = rows
end_a = max(SH.Descriptor(m, desc_a).row_block(r) or 0 for r in range(14))
desc_b = sb.layout(m, (end_a + 0x400) & ~15, slack=1)
# sheet C: a formula with an absolute column past 8191 and a relative one
# past 4096 away: moving their targets 500 columns on leaves the short form
sc = SH.Sheet(4, 1 << 24)
sc.number(1, 16000, 5)
sc.number(2, 8100, 6)
sc.formula(0, 0, SH.F().ref(1, 16000, True, True).ref(2, 8100).op(SH.OP_ADD).end())
end_b = max(SH.Descriptor(m, desc_b).row_block(r) or 0 for r in range(14))
desc_c = sc.layout(m, (end_b + 0x400) & ~15, slack=1)
end_c = max(SH.Descriptor(m, desc_c).row_block(r) or 0 for r in range(4))
assert end_c + 0x400 < HEAP, "sheets too big for the bench"


def params(k, desc, src, dst, fix=(0, ALL), heap=None):
    a = PB + 64 * k
    h = heap or (HEAP + 0x1800 * k, HEAP + 0x1800 * (k + 1))
    m.write(a, struct.pack("<12I", desc, *src, *dst, *fix, *h, 0x55555555) + b"\xAA" * 16)
    return a


jobs = []                                         # (address, assembler)
A = Asm()
jobs.append((PROG, A))
moves = [
    (desc_a, (5, 0, ALL, ALL), (6, 0), (0, ALL)),          # insert a row
    (desc_a, (2, 1, 6, 5), (4, 3), (0, ALL)),              # a block over itself
    (desc_a, (4, 0, ALL, ALL), (3, 0), (0, ALL)),          # delete a row
    (desc_a, (0, 6, ALL, ALL), (0, 12), (0, ALL)),         # columns off the edge
    (desc_a, (1, 0, 2, 3), (9, 0), (8, 10)),               # fixing rows 8-10 only
    (desc_a, (7, 5, 6, 9), (0, 0), (0, ALL)),              # an empty source
]
for k, (d, src, dst, fix) in enumerate(moves):
    A(I.MOVECELLS, 3, x=params(k, d, src, dst, fix))
    A(I.STR, 3, x=RES + 4 * k)
A(I.CELLSMOVED, 3, x=params(6, desc_b, src_b, dst_b))
A(I.STR, 3, x=RES + 4 * 6)
A(I.HALT)
for k, (d, src, dst) in enumerate([
        (desc_a, (0, 0, ALL, ALL), (1, 0)),               # a heap too small
        (desc_c, (1, 16000, 2, 16000), (1, 16500)),       # too far: MOVE_CELLS
        (desc_c, (1, 16000, 2, 16000), (1, 16500))]):     # and CELLS_MOVED
    A = Asm()
    jobs.append((PROG + 0x200 * (k + 1), A))
    heap = (HEAP + 0x1800 * 7, HEAP + 0x1800 * 7 + 0x100) if k == 0 else None
    p = params(7 + k, d, src, dst, heap=heap)
    A(I.LI, 3, z=0x1234)
    A(I.MOVECELLS if k < 2 else I.CELLSMOVED, 3, x=p)
    A(I.STR, 3, x=RES + 0x40 + 4 * k)               # (not reached)
    A(I.HALT)
for a, asm in jobs:
    code = asm.assemble(a)
    assert len(code) <= 0x200, f"job too long ({len(code)} bytes)"
    m.write(a, code)
init = bytes(m.b)

mach = S.Machine.__new__(S.Machine)
mach.mem = bytearray(8 << 20)
mach.mem[:MEM] = init
mach.R, mach.A, mach.N, mach.pc = [0] * 16, [0] * 16, [0] * 3, 0
mach.stats = dict(instructions=0, bytes_read=0, bytes_written=0)
mach.on_argmax = mach.on_sync = None
mach.trace = False
mach.hw = True
results = []                                      # (address, error, PC at the end)
for a, _ in jobs:
    try:
        mach.run(a)
        results.append((a, 0, mach.pc))
    except S.SsnailError as e:
        assert "ERR_FORMAT" in str(e), e
        results.append((a, 6, mach.pc))
        print(f"job ${a:07X}: {e}", file=sys.stderr)
expect = bytes(mach.mem[:MEM])
got = struct.unpack("<7I", expect[RES - B:RES - B + 28])
print(f"MOVE_CELLS: {got[:6]} cells moved; CELLS_MOVED: {got[6]} formulas changed", file=sys.stderr)
assert got[0] > 0 and got[1] > 0 and got[5] == 0 and got[6] > 0, got
assert [e for _, e, _ in results] == [0, 6, 6, 6], results
for k in range(7, 10):
    why = struct.unpack("<I", expect[PB - B + 64 * k + 48:PB - B + 64 * k + 52])[0]
    assert why == (SH.MV_HEAP if k == 7 else SH.MV_FAR), (k, why)


def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


with open("shite9_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package shite9_pkg is\n")
    f.write("  type wordsh_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write("  type naturals_t is array (natural range <>) of natural;\n")
    f.write(f"  constant JOBS : natural := {len(results)};\n")
    for name, i in (("JOB_PC", 0), ("JOB_ERR", 1), ("JOB_END", 2)):
        f.write(f"  constant {name} : naturals_t(0 to {len(results) - 1}) := ("
                + ", ".join(str(r[i] - (B if i != 1 else 0)) for r in results) + ");\n")
    for name, data in (("INIT", init), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : wordsh_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
