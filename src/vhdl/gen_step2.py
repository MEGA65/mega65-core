"""Step 2 test: DEQROW (all formats), VADD, VMUL, CVT16, against the
reference emulator in hardware-numerics mode."""
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
from gguf import GGMLQuantizationType as Q
from gguf.quants import quantize
import ssnail_isa as I
from ssnail_convert import Asm
import ssnail_sim as S

B = I.HYPERRAM_BASE
rng = np.random.default_rng(42)
mem = bytearray(0x2000)


def put(off, data):
    mem[off:off + len(data)] = data


def f32vals(n):
    v = (rng.standard_normal(n) * 10.0 ** rng.integers(-3, 4, n)).astype(np.float32)
    v[0] = np.float32(-0.0)
    v[1] = np.array([0x00000005], dtype=np.uint32).view(np.float32)[0]   # subnormal
    v[2] = np.float32(1e30)
    return v


q8 = np.asarray(quantize(rng.standard_normal((1, 96)).astype(np.float32), Q.Q8_0)).tobytes()
q4 = np.asarray(quantize(rng.standard_normal((1, 64)).astype(np.float32), Q.Q4_0)).tobytes()
f16 = (rng.standard_normal(50) * 100).astype(np.float16)
f16[3] = np.float16(6e-6)                                  # F16 subnormal
bf16 = (rng.integers(0, 65536, 20)).astype(np.uint16)
bf16[bf16 & 0x7F80 == 0x7F80] = 0x3F80                     # no NaN/inf patterns
x = f32vals(101)
y = f32vals(101)[::-1].copy()
put(0x403, q8)
put(0x505, q4)
put(0x602, f16.tobytes())
put(0x680, bf16.tobytes())
put(0x6C4, f32vals(30).tobytes())
put(0x704, x.tobytes())
put(0x8A8, y.tobytes())

A = Asm()
A(I.SETN, x=96);  A(I.DEQROW, I.FMT_Q8_0, x=B + 0x403, z=B + 0x10E4)
A(I.SETN, x=64);  A(I.DEQROW, I.FMT_Q4_0, x=B + 0x505, z=B + 0x1204)
A(I.SETN, x=50);  A(I.DEQROW, I.FMT_F16, x=B + 0x602, z=B + 0x1300)
A(I.SETN, x=20);  A(I.DEQROW, I.FMT_BF16, x=B + 0x680, z=B + 0x1408)
A(I.SETN, x=30);  A(I.DEQROW, I.FMT_F32, x=B + 0x6C4, z=B + 0x14C4)
A(I.SETN, x=100); A(I.VADD, x=B + 0x704, y=B + 0x8A8, z=B + 0x1604)
A(I.SETN, x=60);  A(I.VMUL, x=B + 0x704, y=B + 0x88C, z=B + 0x18FC)
A(I.SETN, x=101); A(I.CVT16, x=B + 0x704, z=B + 0x1A02)
A(I.SETN, x=0);   A(I.VADD, x=B + 0x704, y=B + 0x8A8, z=B + 0x1B00)   # no-op
A(I.LI, 1, z=0)
A(I.LEA, 1, 1, B + 0x1C00, z=0)
A(I.SETN, x=40);  A(I.VADD, x=B + 0x8A8, y=B + 0x704, z=I.reg_addr(1, 0x14))
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
expect = bytes(m.mem[0x1000:0x2000])
print(f"program {len(code) // 16} instructions; halt pc ${m.pc:07X}", file=sys.stderr)


def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


with open("step2_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package step2_pkg is\n")
    f.write("  type words2_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {m.pc};\n")
    for name, data in (("INIT", bytes(mem[:0x1000])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : words2_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
