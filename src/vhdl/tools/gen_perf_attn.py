"""Attention performance check: one ATTN (4 heads sharing 2 KV heads, head
dim 64, 32 positions, F16 cache), results checked against the emulator,
and the run time held to a limit."""
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
from gguf import GGMLQuantizationType as Q
from gguf.quants import quantize
import ssnail_isa as I
from ssnail_convert import Asm
import ssnail_sim as S
PERF_LIMIT_NS = 290000   # 232 us measured; +25%
PERF_WHAT = "ATTN, 4 heads (2 KV) x 64, 32 positions, F16 KV"
PKG = "perf_attn"

B = I.HYPERRAM_BASE
rng = np.random.default_rng(31337)
mem = bytearray(0x7000)


def put(off, data):
    mem[off:off + len(data)] = data


def qmat(rows, cols, fmt):
    return np.asarray(quantize((rng.standard_normal((rows, cols)) * 0.2).astype(np.float32), fmt)).tobytes()


T, NH, NKV, HD = 32, 4, 2, 64                     # F16 KV cache
k = (rng.standard_normal((T, NKV * HD))).astype(np.float16)
v = (rng.standard_normal((T, NKV * HD))).astype(np.float16)
q = (rng.standard_normal(NH * HD)).astype(np.float32)
put(0x0400, k.tobytes()); put(0x2400, v.tobytes()); put(0x4400, q.tobytes())
put(0x4800, struct.pack("<8I", B + 0x0400, B + 0x2400, NH, NKV, HD, 1, 0, 0))
A = Asm()
A(I.LI, 5, z=T - 1)
A(I.ATTN, 5, x=B + 0x4800, y=B + 0x4400, z=B + 0x6000)
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
expect = bytes(m.mem[0x6000:0x7000])
print(f"program {len(code) // 16} instructions; halt pc ${m.pc:07X}", file=sys.stderr)


def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


with open(f"{PKG}_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            f"package {PKG}_pkg is\n")
    f.write("  type wordsp_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {m.pc};\n")
    f.write(f"  constant PERF_LIMIT_NS : natural := {PERF_LIMIT_NS};\n")
    f.write(f"  constant PERF_WHAT : string := \"{PERF_WHAT}\";\n")
    for name, data in (("INIT", bytes(mem[:0x6000])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : wordsp_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
