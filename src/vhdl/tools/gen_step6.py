"""Step 6 test: GEMV and DEQROW with super-block weights (Q2_K .. Q6_K,
IQ4_XS, TQ2_0; GEMV of IQ2_XXS, IQ2_XS, IQ2_S, IQ3_XXS, IQ3_S) against the
reference emulator in hardware-numerics mode."""
import os
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
import ssnail_hw as H
from ssnail_convert import Asm
import ssnail_sim as S

B = I.HYPERRAM_BASE
rng = np.random.default_rng(66)
mem = bytearray(0x10000)
D_OFF = {10: [80, 82], 11: [108], 12: [0, 2], 13: [0, 2], 14: [208], 23: [0], 35: [64],
         16: [0], 17: [0], 22: [0], 18: [0], 21: [0]}


def put(off, data):
    mem[off:off + len(data)] = data


def kmat(fmt, rows, cols):
    """random super-blocks (gguf-py has no K-quant quantisers), sane d / dmin"""
    n = rows * cols // 256
    b = rng.integers(0, 256, (n, H.K_BYTES[fmt]), dtype=np.uint8)
    for o in D_OFF[fmt]:
        b[:, o:o + 2] = (rng.standard_normal((n, 1)) * 0.01).astype(np.float16).view(np.uint8)
    return b.tobytes()


x1 = (rng.standard_normal(512) * 3).astype(np.float32)
x1[300] = np.float32(-40.0)                      # one large element
x2 = (rng.standard_normal(512) * 0.5).astype(np.float32)
x2[:256] = 0                                     # all-zero super-block: d = 0
acc = (rng.standard_normal(8) * 5).astype(np.float32)
put(0x400, x1.tobytes())
put(0xC00, x2.tobytes())
put(0x1400, acc.tobytes())

A = Asm()
off, outs = 0x1803, 0x6000
k_at = {}
for fmt in (10, 11, 12, 13, 14, 23, 35):         # 3 rows x 2 super-blocks
    w = kmat(fmt, 3, 512)
    put(off, w)
    k_at[fmt] = off
    A(I.SETN, x=512, y=3); A(I.GEMV, fmt, x=B + off, y=B + 0x400, z=B + outs)
    off += len(w) + 0x11
    outs += 0x20
w = kmat(12, 7, 256)                             # Q4_K, 7 rows of 1: the halves turn over
put(off, w)
A(I.SETN, x=256, y=7); A(I.GEMV, 12, x=B + off, y=B + 0x400, z=B + 0x6100)
A(I.COPY, x=B + 0x1400, y=B + 0x6200, z=32)     # existing outputs for the accumulate
A(I.SETN, x=512, y=3); A(I.GEMV, 14, I.GEMV_ACC, x=B + 0x1803 + 0, y=B + 0xC00, z=B + 0x6200)
A(I.SETN, x=512, y=3); A(I.GEMV, 10, I.GEMV_F16OUT, x=B + 0x1803, y=B + 0xC00, z=B + 0x6302)
off += len(w) + 0x11
# the codebook formats (IQ front end): 3 rows x 2 super-blocks, and IQ3_S
# with the all-zero x super-block
for i, fmt in enumerate((16, 17, 22, 18, 21)):
    w = kmat(fmt, 3, 512)
    put(off, w)
    A(I.SETN, x=512, y=3); A(I.GEMV, fmt, x=B + off, y=B + 0x400, z=B + 0x8C00 + 0x20 * i)
    if fmt == 21:
        A(I.SETN, x=512, y=3); A(I.GEMV, fmt, x=B + off, y=B + 0xC00, z=B + 0x8CC0)
    off += len(w) + 0x11
assert off < 0x6000, hex(off)
# DEQROW: one super-block of each (Q4_K: two)
for i, fmt in enumerate((10, 11, 13, 14)):
    A(I.SETN, x=256); A(I.DEQROW, fmt, x=B + k_at[fmt], z=B + 0x6400 + 0x400 * i)
A(I.SETN, x=512); A(I.DEQROW, 12, x=B + k_at[12], z=B + 0x7400)
A(I.SETN, x=512); A(I.DEQROW, 23, x=B + k_at[23], z=B + 0x8000)
A(I.SETN, x=256); A(I.DEQROW, 35, x=B + k_at[35], z=B + 0x8800)
A(I.HALT)
code = A.assemble(B)
assert len(code) <= 0x400
put(0, code)

m = S.Machine.__new__(S.Machine)
m.mem = bytearray(8 << 20)
m.mem[:len(mem)] = mem
m.R, m.A, m.N, m.pc = [0] * 16, [0] * 16, [0] * 3, 0
m.stats = dict(instructions=0, bytes_read=0, bytes_written=0)
m.on_argmax = m.on_sync = None
m.trace = False
m.temperature, m.top_k, m.rep_penalty, m.rep_window = 0.0, 0, 1.0, 64
m.hw = True
m.run(B)
expect = bytes(m.mem[0x6000:0x10000])
print(f"program {len(code) // 16} instructions; halt pc ${m.pc:07X}", file=sys.stderr)


def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


with open("step6_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package step6_pkg is\n")
    f.write("  type words3_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {m.pc};\n")
    for name, data in (("INIT", bytes(mem[:0x6000])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : words3_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
