"""Step 3 test: GEMV (Q8_0, Q4_0; accumulate; F16 output) against the
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
rng = np.random.default_rng(99)
mem = bytearray(0x2000)


def put(off, data):
    mem[off:off + len(data)] = data


def qmat(rows, cols, fmt):
    return np.asarray(quantize((rng.standard_normal((rows, cols)) * 0.2).astype(np.float32), fmt)).tobytes()


w1 = qmat(20, 96, Q.Q8_0)                        # 2040 bytes
w2 = qmat(13, 64, Q.Q4_0)                        # 468 bytes
w3 = qmat(9, 32, Q.Q8_0)                         # 306 bytes
x1 = (rng.standard_normal(96) * 3).astype(np.float32)
x1[32:64] = 0                                    # all-zero block: d = 0, id = 0
x1[64] = np.float32(127.0)                       # block where x * id hits the
x1[65] = np.nextafter(np.float32(0.5), np.float32(0))   # roundf edge
x2 = (rng.standard_normal(64) * 0.7).astype(np.float32)
acc = (rng.standard_normal(13) * 5).astype(np.float32)
put(0x203, w1)
put(0xA03, w2)
put(0xC04, x1.tobytes())
put(0xD88, x2.tobytes())
put(0xE8B, w3)
put(0xFC0, acc.tobytes())

A = Asm()
A(I.SETN, x=96, y=20); A(I.GEMV, I.FMT_Q8_0, x=B + 0x203, y=B + 0xC04, z=B + 0x10F8)
A(I.COPY, x=B + 0xFC0, y=B + 0x1200, z=56)       # existing outputs for the accumulate
A(I.SETN, x=64, y=13); A(I.GEMV, I.FMT_Q4_0, I.GEMV_ACC, x=B + 0xA03, y=B + 0xD88, z=B + 0x1200)
A(I.SETN, x=32, y=9);  A(I.GEMV, I.FMT_Q8_0, I.GEMV_F16OUT, x=B + 0xE8B, y=B + 0xD88, z=B + 0x1302)
A(I.SETN, x=32, y=0);  A(I.GEMV, I.FMT_Q8_0, x=B + 0xE8B, y=B + 0xD88, z=B + 0x1400)   # no rows
A(I.HALT)
code = A.assemble(B)
assert len(code) <= 0x200
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


with open("step3_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package step3_pkg is\n")
    f.write("  type words3_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {m.pc};\n")
    for name, data in (("INIT", bytes(mem[:0x1000])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : words3_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
