"""SHITE step 10 test: REBALANCE_ROW and FIND_CELL refusing malformed sheets
(as SSNAIL instructions) against the reference model (SSNAIL/shite.py,
through the emulator).  A sheet laid out nine times, each copy but the
first with one fault: the descriptor's magic; a row's number, its first
free granule (0; past the block: in the last block in memory, a free cell
from the old one to it, so that walked without the check the row would
rebalance), its
block's length (past 4096, its cells fine); a cell's length (0: a free
one's, so that unchecked the walk never ends; past the free granule); two cells in one column.  The first copy: rows with no
block, rows past the sheet, then FIND_CELL of cells, misses, a row with
no block and one past the sheet.  Each job REBALANCE_ROWs its
sheet (the rows before the fault rebalanced, the fault's row in the
descriptor) or, for the magic, FIND_CELLs too."""
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
SHEET = 0x2000                              # each copy's room
NROWS = 12


class Mem:
    def __init__(self):
        self.b = bytearray(MEM)

    def read(self, a, n):
        return bytes(self.b[a - B:a - B + n])

    def write(self, a, d):
        self.b[a - B:a - B + len(d)] = d


def sheet():
    rng = np.random.default_rng(1953)
    sh = SH.Sheet(NROWS, SH.MAX_COLS)
    for r in range(NROWS):
        if r in (2, 7):
            continue
        n = [0, 1, 2, 9, 14][r % 5]
        for i, c in enumerate(rng.choice(200, size=n, replace=False)):
            c = int(c)
            if i == 3:
                sh.free(r, 2)
            if i % 2:
                sh.number(r, c, int(rng.integers(-99, 99)))
            else:
                sh.text(r, c, "cell %d,%d" % (r, c) + "!" * int(rng.integers(0, 12)))
    return sh


m = Mem()
u16 = lambda a: struct.unpack("<H", m.read(a, 2))[0]
put16 = lambda a, v: m.write(a, struct.pack("<H", v))
put32 = lambda a, v: m.write(a, struct.pack("<I", v))
descs = []
for k in range(9):
    base = B + 0x2000 + SHEET * k
    d = sheet().layout(m, base, slack=1, balanced=False)
    end = max(SH.Descriptor(m, d).row_block(r) or 0 for r in range(NROWS))
    assert end + 0x200 < base + SHEET, "a sheet too big for its room"
    descs.append(d)
blk = lambda k, r: SH.Descriptor(m, descs[k]).row_block(r)
cell1 = lambda k, r: blk(k, r) + 16             # (its first granule: a cell)
put32(descs[1], 0x31544854)                     # 1: the magic
put32(blk(2, 3) + SH.R_ROW, 9)                  # 2: row 3's number
put16(blk(3, 4) + SH.R_FREE, 0)                 # 3: row 4's first free granule 0
last = max(range(NROWS), key=lambda r: blk(4, r) or 0)   # 4: past its block
b4, n4 = blk(4, last), u16(blk(4, last) + SH.R_LEN)
f4 = u16(b4 + SH.R_FREE)                        # (a free cell from there past the block)
put16(b4 + SH.R_FREE, n4 + 2)
m.write(b4 + 16 * f4, bytes([0, 0, 0, SH.K_FREE, n4 + 2 - f4, 0, 0, 0]))
put16(blk(5, 8) + SH.R_LEN, 4097)               # 5: row 8's block too long
def free_cell(k, r):                            # (a free cell's granule)
    b, g = blk(k, r), 1
    while m.read(b + 16 * g + 3, 1)[0] & 15 != SH.K_FREE:
        g += m.read(b + 16 * g + 4, 1)[0]
    return b + 16 * g
m.write(free_cell(6, 9) + 4, b"\x00")           # 6: a free cell's length 0 (unchecked: no end)
m.write(cell1(7, 11) + 4, bytes([u16(blk(7, 11) + SH.R_FREE)]))   # 7: past the free granule
h = m.read(cell1(8, 3), 3)                      # 8: two cells in row 3 in one column
g2 = 1 + m.read(cell1(8, 3) + 4, 1)[0]
m.write(blk(8, 3) + 16 * g2, h)

PROG, RES = B, B + 0x1F00
jobs = []
for k, (first, last) in enumerate([(0, NROWS + 5)] + [(0, NROWS - 1)] * 8):
    A = Asm()
    A(I.LI, 1, z=first); A(I.LI, 2, z=last)
    if k == 1:                                  # FIND_CELL refuses it too
        A(I.LI, 3, z=1); A(I.LI, 4, z=5); A(I.FINDCELL, 3, 4, x=descs[k])
    A(I.REBALANCE, 1, 2, x=descs[k])
    if k == 0:                                  # the cells found after
        rows = sheet().rows
        probes = [(r, rows[r][-1][0]) for r in (1, 3, 4)] + [(4, 200), (2, 0), (NROWS, 1)]
        for j, (r, c) in enumerate(probes):
            A(I.LI, 3, z=r); A(I.LI, 4, z=c); A(I.FINDCELL, 3, 4, x=descs[k])
            A(I.STR, 3, x=RES + 4 * j)
    A(I.HALT)
    code = A.assemble(PROG + 0x200 * k)
    assert len(code) <= 0x200, f"job too long ({len(code)} bytes)"
    m.write(PROG + 0x200 * k, code)
    jobs.append(PROG + 0x200 * k)
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
for a in jobs:
    try:
        mach.run(a)
        results.append((a, 0, mach.pc))
    except S.SsnailError as e:
        assert "ERR_FORMAT" in str(e), e
        results.append((a, 6, mach.pc))
        print(f"job ${a:07X}: {e}", file=sys.stderr)
expect = bytes(mach.mem[:MEM])
assert [e for _, e, _ in results] == [0] + [6] * 8, results
for k, row in enumerate([0, 3, 4, last, 8, 9, 11, 3], 1):            # (1: nothing written)
    got = struct.unpack("<I", expect[descs[k] - B + 48:descs[k] - B + 52])[0]
    assert got == row, (k, got, row)
found = struct.unpack("<6I", expect[RES - B:RES - B + 24])
assert all(found[:3]) and not any(found[3:]), found
print(f"FIND_CELL after: {[hex(f) for f in found]}", file=sys.stderr)


def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


with open("shite10_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package shite10_pkg is\n")
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
