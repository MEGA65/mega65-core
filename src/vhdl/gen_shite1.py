"""SHITE step 1 test: REBALANCE_ROW and FIND_CELL (as SSNAIL instructions)
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
import numpy as np
import ssnail_isa as I
from ssnail_convert import Asm
import ssnail_sim as S
import shite as SH

B = I.HYPERRAM_BASE
MEM = 0x2000                                # the bench's memory: 8 KB
rng = np.random.default_rng(1949)


class Mem:
    def __init__(self):
        self.b = bytearray(MEM)

    def read(self, a, n):
        return bytes(self.b[a - B:a - B + n])

    def write(self, a, d):
        self.b[a - B:a - B + len(d)] = d


# A sheet with rows in any column order, holes, empty rows, long cells
NROWS = 12
sh = SH.Sheet(NROWS, SH.MAX_COLS)
cells = []
for r in range(NROWS):
    if r in (2, 7):
        continue
    n = [0, 1, 2, 9, 14][r % 5]
    for i, c in enumerate(rng.choice(200, size=n, replace=False)):
        c = int(c) << 14 | int(c) if i % 4 == 1 else int(c)    # some columns in the millions
        if i == 3:
            sh.free(r, 2)
        if i % 3 == 0:
            sh.number(r, c, int(rng.integers(-99, 99)))
        elif i % 3 == 1:
            sh.number(r, c, float(rng.standard_normal()), fmt=bytes([1, 3, 0, 0, 0, 0, 0, 0]))
        else:
            sh.text(r, c, "cell %d,%d" % (r, c) + "!" * int(rng.integers(0, 20)))
        cells.append((r, c))
m = Mem()
desc = sh.layout(m, B + 0x200, slack=1, balanced=False, change_cap=16)
end = max(SH.Descriptor(m, desc).row_block(r) or 0 for r in range(NROWS)) - B
assert end < 0x1900, "sheet too big for the bench"

# FIND_CELL probes: every cell, some misses, rows beyond the sheet; a loop
# over tables of rows (at $1A00) and columns ($1C00), results at $1E00
probes = list(cells) + [(r, 199 - r) for r in range(NROWS) if (r, 199 - r) not in cells]
probes += [(r, (1 << 24) - 1) for r in (0, 4)]
probes += [(NROWS, 0), (500, 3), (2, 5)]
assert len(probes) <= 128, len(probes)
m.write(B + 0x1A00, struct.pack(f"<{len(probes)}I", *[r for r, _ in probes]))
m.write(B + 0x1C00, struct.pack(f"<{len(probes)}I", *[c for _, c in probes]))
a_ = [I.reg_addr(i) for i in range(16)]
A = Asm()
A(I.LI, 1, z=0); A(I.LI, 2, z=NROWS - 1); A(I.REBALANCE, 1, 2, x=desc)
A(I.LI, 5, z=0); A(I.LI, 6, z=len(probes))
A.label("loop")
A(I.LEA, 0, 5, B + 0x1A00, z=4); A(I.LEA, 1, 5, B + 0x1C00, z=4); A(I.LEA, 2, 5, B + 0x1E00, z=4)
A(I.LDR, 3, x=a_[0]); A(I.LDR, 4, x=a_[1])
A(I.FINDCELL, 3, 4, x=desc)
A(I.STR, 3, x=a_[2])
A(I.ADDI, 5, 5, z=1)
A(I.BLT, 5, 6, "loop")
A(I.HALT)
code = A.assemble(B)
assert len(code) <= 0x200, f"program too long ({len(code)} bytes)"
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
found = sum(1 for k in range(len(probes)) if struct.unpack("<I", expect[0x1E00 + 4 * k:0x1E04 + 4 * k])[0])
assert found == len(cells), (found, len(cells))
print(f"program {len(code) // 16} instructions; {len(cells)} cells, {len(probes)} probes; "
      f"halt pc ${mach.pc:07X}", file=sys.stderr)


def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


with open("shite1_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package shite1_pkg is\n")
    f.write("  type wordsh_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {mach.pc};\n")
    for name, data in (("INIT", bytes(init)), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : wordsh_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
