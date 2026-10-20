"""Step 7 test: GEMV with float weights (F16, BF16, F32: the float lane;
accumulate; F16 output) against the reference emulator in hardware-numerics
mode (ssnail_hw.dot8)."""
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
from ssnail_convert import Asm
import ssnail_sim as S

B = I.HYPERRAM_BASE
rng = np.random.default_rng(77)
mem = bytearray(0x10000)


def put(off, data):
    mem[off:off + len(data)] = data


x1 = (rng.standard_normal(256) * 3).astype(np.float32)
x1[5] = np.float32(0.0)
x1[6] = np.float32(-0.0)
x1[7] = np.float32(1e-40)                          # subnormal x
x2 = (rng.standard_normal(64) * 0.5).astype(np.float32)
acc = (rng.standard_normal(8) * 5).astype(np.float32)
put(0x400, x1.tobytes())
put(0x800, x2.tobytes())
put(0x900, acc.tobytes())

w16 = (rng.standard_normal((7, 256)) * 0.2).astype(np.float16)
w16[0, 3] = np.float16(6e-6)                       # F16 subnormal weight
w16[1, :] = -w16[1, :]
wbf = (rng.standard_normal((5, 64)).astype(np.float32).view(np.uint32) >> 16).astype(np.uint16)
w32 = (rng.standard_normal((6, 64)) * 2.0 ** rng.integers(-20, 20, (6, 64))).astype(np.float32)
w32[2, :] = (w32[2, :] * 1e30).astype(np.float32)  # big products, cancelling sums
put(0x1002, w16.tobytes())                         # 2 mod 8: a word to skip
put(0x2006, wbf.tobytes())                         # 6 mod 8: three
put(0x2404, w32.tobytes())                         # 4 mod 8 (F32: 4-aligned)

A = Asm()
A(I.SETN, x=256, y=7); A(I.GEMV, I.FMT_F16, x=B + 0x1002, y=B + 0x400, z=B + 0x6000)
A(I.SETN, x=64, y=5);  A(I.GEMV, I.FMT_BF16, x=B + 0x2006, y=B + 0x800, z=B + 0x6100)
A(I.SETN, x=64, y=6);  A(I.GEMV, I.FMT_F32, x=B + 0x2404, y=B + 0x800, z=B + 0x6200)
A(I.COPY, x=B + 0x900, y=B + 0x6300, z=32)       # existing outputs for the accumulate
A(I.SETN, x=256, y=7); A(I.GEMV, I.FMT_F16, I.GEMV_ACC, x=B + 0x1002, y=B + 0x400, z=B + 0x6300)
A(I.SETN, x=64, y=6);  A(I.GEMV, I.FMT_F32, I.GEMV_F16OUT, x=B + 0x2404, y=B + 0x800, z=B + 0x6402)
A(I.SETN, x=256, y=1); A(I.GEMV, I.FMT_F16, x=B + 0x1002 + 512 * 6, y=B + 0x400, z=B + 0x6500)
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


with open("step7_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package step7_pkg is\n")
    f.write("  type words3_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {m.pc};\n")
    for name, data in (("INIT", bytes(mem[:0x6000])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : words3_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
