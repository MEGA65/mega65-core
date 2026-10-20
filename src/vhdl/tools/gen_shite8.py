"""SHITE step 8 test: the codec units through SSNAIL's instructions:
COMPILE / DECOMPILE (cases from the codec's own test generator,
tests/test_shite_codec.py), RENDER, PARSE and FORMAT_CELLS (hand-computed
screen text), checked in the regions they write (a mask: the units may
leave working bytes in their buffers and scratch)."""
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
sys.path.insert(0, os.path.join(_here, "..", "..", "tests"))
import ssnail_isa as I
from ssnail_convert import Asm
import shite as SH
import test_shite_codec as TC

B = I.HYPERRAM_BASE
MEM = 0x8000
mem = bytearray(MEM)
mask = bytearray(MEM)                         # 1: the bench checks this byte
expect = None


class Mem:
    def read(self, a, n):
        return bytes(mem[a - B:a - B + n])

    def write(self, a, d):
        mem[a - B:a - B + len(d)] = d


m = Mem()


def fmt(style=0, dec=0, k=0, flags=0, colour=0):
    return bytes([style, dec, k, flags, 0, 0, colour, 0])


# a small sheet for FORMAT_CELLS
sh = SH.Sheet(3, 8)
sh.number(0, 0, 42); sh.text(0, 1, "Hi"); sh.number(0, 2, -150, fmt=fmt(1, 2, 2, 0, 0x52), flags=SH.F_CHANGED)
sh.number(1, 0, 1234567, flags=SH.F_CHANGED); sh.number(1, 2, 7)
desc = sh.layout(m, B + 0x0800, slack=0, change_cap=4)
NAMES = B + 0x2000
m.write(NAMES, TC.name_table())
m.write(desc + SH.D_NAMES, struct.pack("<IBB", NAMES, ord("."), ord(",")))
assert max(SH.Descriptor(m, desc).row_block(r) or 0 for r in range(3)) - B < 0x1F00

A = Asm()
RES = B + 0x7C00                              # each instruction's R[a], stored
nres = 0


def store_result(expected_r):
    global nres
    a = RES + 4 * nres
    A(I.STR, 1, x=a)
    final[a - B:a - B + 4] = struct.pack("<I", expected_r & 0xFFFFFFFF)
    mask[a - B:a - B + 4] = b"\1\1\1\1"
    nres += 1


final = {}
final = bytearray(MEM)                        # the expected bytes where masked

# --- COMPILE / DECOMPILE ----------------------------------------------------------
jobs = [j for j in TC.jobs() if j.error == 0 and not j.german and j.capacity == 8192
        and not j.abort_after and not j.memory_fault]
pick = jobs[:24] + [j for j in jobs if b"\x0a" in (j.source + j.expected)][:6] \
    + [j for j in jobs if b"\x09" in (j.source + j.expected)][:4] \
    + [j for j in jobs if b"\x0d" in (j.source + j.expected)][:4]
src, out, blk = B + 0x2400, B + 0x3000, B + 0x5000
ncodec = 0
for j in pick:
    want = j.expected                         # (compiled: ending with END, $00)
    if src + len(j.source) > B + 0x3000 or out + 256 > B + 0x5000 or len(want) > 240:
        continue
    m.write(src, j.source)
    m.write(blk, struct.pack("<IIHHIII", desc, src, len(j.source), 256, j.origin[0], j.origin[1], out) + bytes(8))
    A(I.LI, 1, z=0)
    A(I.COMPILE if j.mode == 0 else I.DECOMPILE, 1, x=blk)
    store_result(len(want))
    final[out - B:out - B + len(want)] = want
    mask[out - B:out - B + len(want)] = b"\1" * len(want)
    # the result fields: length, error 0, host calls, position (bytes 24-29)
    final[blk + 24 - B:blk + 28 - B] = struct.pack("<HBB", len(want), 0, j.host_calls if j.mode == 0 else 0)
    mask[blk + 24 - B:blk + 28 - B] = b"\1\1\1\1"
    src += (len(j.source) + 15) & ~15
    out += 256
    blk += 32
    ncodec += 1

# --- RENDER --------------------------------------------------------------------------
SC = lambda t: bytes(SH_SCREEN(c) for c in t)


def SH_SCREEN(c):
    """README 6's ASCII to screen codes (lower-case set)."""
    o = ord(c)
    if c == "@":
        return 0
    if "a" <= c <= "z":
        return o - 96
    if 0x20 <= o <= 0x3F or "A" <= c <= "Z":
        return o
    return {"[": 27, "]": 29, "^": 30, "_": 100, "|": 93, "`": 39}.get(c, 63)


SCRATCH = B + 0x7000
dst = B + 0x6000
renders = [  # (kind, k, width, value bytes, format, expected text)
    (4, 0, 6, struct.pack("<q", 42), fmt(), "    42"),
    (4, 2, 8, struct.pack("<q", -150), fmt(1, 2, 2), "   -1.50"),
    (3, 0, 7, struct.pack("<d", 2.5), fmt(1, 3), "  2.500"),
    (4, 0, 9, struct.pack("<q", 1234567), fmt(4, 0, 0, 1), "1,234,567"),
    (4, 0, 3, struct.pack("<q", 123456), fmt(4), "###"),
]
for kind, k, w, val, f, text in renders:
    m.write(blk, struct.pack("<IBBBB", desc, kind, k, w, 1) + val + f + struct.pack("<II", dst, SCRATCH))
    A(I.LI, 1, z=0)
    A(I.RENDER, 1, x=blk)
    A(I.STR, 1, x=RES + 4 * nres); nres += 1         # (R[a]: the colour; not checked)
    final[dst - B:dst - B + w] = SC(text)
    mask[dst - B:dst - B + w] = b"\1" * w
    dst += 16
    blk += 32

# --- PARSE --------------------------------------------------------------------------
parses = [("19.99", 4, 1999, 2), ("1.5E3", 3, struct.unpack("<q", struct.pack("<d", 1500.0))[0], 0),
          ("-42", 4, -42, 0), ("abc", 0, 0, 0)]
for text, kind, value, k in parses:
    t = text.encode("ascii")
    m.write(src, t)
    m.write(blk, struct.pack("<IIH", desc, src, len(t)) + bytes(22))
    A(I.LI, 1, z=0)
    A(I.PARSE, 1, x=blk)
    store_result(kind)
    final[blk + 16 - B:blk + 26 - B] = struct.pack("<qBB", value if kind else 0, kind, k)
    mask[blk + 16 - B:blk + 26 - B] = b"\1" * 10
    src += 16
    blk += 32

# --- FORMAT_CELLS ---------------------------------------------------------------------
WIDTHS = B + 0x2300
m.write(WIDTHS, bytes([7, 3, 0, 8]))         # columns A-D: C hidden (width 0)
FD, FC = B + 0x6400, B + 0x6600              # screen, colours: 2 lines of 40
# row 0: A1 42 (general, width 7), B1 "Hi" (width 3), C1 hidden, D1 no cell (width 8)
# row 1: A2 1234567, B2 no cell, C2 hidden, D2 no cell
line0 = "     42" + "Hi " + " " * 8
line1 = "1234567" + "   " + " " * 8
for blk_flags, lines in ((0, (line0, line1)),):
    m.write(blk, struct.pack("<IIIIIIIHBBIHBBII", desc, 0, 1, 0, 3, WIDTHS, FD, 40, 1, blk_flags,
                             FC, 40, 0x0E, 0, SCRATCH, 0))
    A(I.FORMATCELLS, x=blk)
    for r, text in enumerate(lines):
        a = FD + 40 * r
        final[a - B:a - B + len(text)] = SC(text)
        mask[a - B:a - B + len(text)] = b"\1" * len(text)
        a = FC + 40 * r
        final[a - B:a - B + len(text)] = bytes([0x0E]) * len(text)
        mask[a - B:a - B + len(text)] = b"\1" * len(text)
    blk += 48
# again: 16-bit characters, only cells with CHANGED (A2), CHANGED cleared
FD2, FC2 = B + 0x6800, B + 0x6A00
m.write(blk, struct.pack("<IIIIIIIHBBIHBBII", desc, 0, 1, 0, 3, WIDTHS, FD2, 80, 2, 3,
                         FC2, 40, 0x0E, 0, SCRATCH, 0))
A(I.FORMATCELLS, x=blk)
for a, n in ((FD2, 80 * 2), (FC2, 40 * 2)):    # (all else untouched: zero)
    mask[a - B:a - B + n] = b"\1" * n
a = FD2 + 80                                  # A2: "1234567" as (code, 0) pairs
final[a - B:a - B + 14] = b"".join(bytes([c, 0]) for c in SC("1234567"))
final[FC2 + 40 - B:FC2 + 47 - B] = bytes([0x0E]) * 7
c = SH.find_cell(m, desc, 1, 0)               # A2's CHANGED cleared
final[c + 3 - B] = mem[c + 3 - B] & ~SH.F_CHANGED & 0xFF
mask[c + 3 - B] = 1
c = SH.find_cell(m, desc, 0, 2)               # C1 hidden: its CHANGED kept
final[c + 3 - B] = mem[c + 3 - B]
mask[c + 3 - B] = 1
A(I.HALT)
code = A.assemble(B)
assert len(code) <= 0x800, len(code)
mem[:len(code)] = code
init = bytes(mem)
expect = bytearray(init)
for i in range(MEM):
    if mask[i]:
        expect[i] = final[i]
print(f"program {len(code) // 16} instructions; {ncodec} codec jobs, {len(renders)} renders, "
      f"{len(parses)} parses, FORMAT_CELLS; {sum(mask)} bytes checked", file=sys.stderr)


def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


with open("shite8_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package shite8_pkg is\n")
    f.write("  type wordsh_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {B + len(code) - 16};\n")
    mw = [(1 if mask[i] else 0) | (2 if mask[i + 1] else 0) for i in range(0, MEM, 2)]
    for name, data in (("INIT", init), ("EXPECT", bytes(expect))):
        w = words(data)
        f.write(f"  constant {name} : wordsh_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write(f"  type mask_t is array (natural range <>) of natural range 0 to 3;\n")
    f.write(f"  constant MASK : mask_t(0 to {len(mw) - 1}) := (\n")
    f.write(",\n".join("    %d" % v for v in mw))
    f.write(");\n")
    f.write("end package;\n")
