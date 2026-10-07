"""Step 5 test: ROPE, ARGMAX, ATTN (F16 and F32 KV, grouped-query) against
the reference emulator in hardware-numerics mode."""
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
rng = np.random.default_rng(555)
mem = bytearray(0x2000)
F32 = np.float32


def put(off, data):
    mem[off:off + len(data)] = data


# ROPE: 64 elements, head dim 16 (the cos/sin row wraps 4 times)
xr = (rng.standard_normal(64) * 2).astype(F32)
ang = rng.uniform(-3, 3, 8)
cs = np.stack([np.cos(ang), np.sin(ang)], -1).reshape(-1).astype(F32)
put(0x208, xr.tobytes()); put(0x308, cs.tobytes())
# ARGMAX: tie for the maximum -- the first must win
xa = (rng.standard_normal(100)).astype(F32)
xa[17] = xa[63] = F32(9.5)
put(0x404, xa.tobytes())
# ATTN 1: F16 KV, 4 heads sharing 2 KV heads, head dim 16, positions 0..5
k1 = (rng.standard_normal((6, 2 * 16))).astype(np.float16)
v1 = (rng.standard_normal((6, 2 * 16))).astype(np.float16)
q1 = (rng.standard_normal(4 * 16) * 2).astype(F32)
put(0x5A0, k1.tobytes()); put(0x720, v1.tobytes()); put(0x8A0, q1.tobytes())
put(0x9A0, struct.pack("<8I", B + 0x5A0, B + 0x720, 4, 2, 16, 1, 0, 0))
# ATTN 2: F32 KV, 2 heads, head dim 8, positions 0..3
k2 = (rng.standard_normal((4, 2 * 8))).astype(F32)
v2 = (rng.standard_normal((4, 2 * 8))).astype(F32)
q2 = (rng.standard_normal(2 * 8)).astype(F32)
put(0xA00, k2.tobytes()); put(0xB00, v2.tobytes()); put(0xC00, q2.tobytes())
put(0xC80, struct.pack("<8I", B + 0xA00, B + 0xB00, 2, 2, 8, 0, 0, 0))
assert not any(mem[0x1000:]), "test data must stay below $1000 (the bench loads only that)"

A = Asm()
A(I.SETN, x=64, y=16);   A(I.ROPE, x=B + 0x208, y=B + 0x308)
A(I.COPY, x=B + 0x208, y=B + 0x1008, z=256)          # keep the rotated vector
A(I.SETN, x=100);        A(I.ARGMAX, 3, x=B + 0x404)
A(I.STR, 3, x=B + 0x1000)
A(I.LI, 5, z=5)
A(I.ATTN, 5, x=B + 0x9A0, y=B + 0x8A0, z=B + 0x1204)   # 4-aligned, crosses $1300
A(I.LI, 5, z=3)
A(I.ATTN, 5, x=B + 0xC80, y=B + 0xC00, z=B + 0x1400)
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


with open("step5_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package step5_pkg is\n")
    f.write("  type words5_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {m.pc};\n")
    for name, data in (("INIT", bytes(mem[:0x1000])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : words5_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
