"""GEMV performance check: a Q8_0 and a Q4_0 GEMV (48 x 256 each), results
checked against the emulator, and the run time held to a limit."""
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
PERF_LIMIT_NS = 185000   # GEMV v2 measured 147 us of simulated time; +25%

B = I.HYPERRAM_BASE
rng = np.random.default_rng(31337)
mem = bytearray(0x7000)


def put(off, data):
    mem[off:off + len(data)] = data


def qmat(rows, cols, fmt):
    return np.asarray(quantize((rng.standard_normal((rows, cols)) * 0.2).astype(np.float32), fmt)).tobytes()


w8 = qmat(48, 256, Q.Q8_0)                      # 13056 bytes
w4 = qmat(48, 256, Q.Q4_0)                      #  6912 bytes
x = (rng.standard_normal(256)).astype(np.float32)
put(0x0400, w8)
put(0x3800, w4)
put(0x5800, x.tobytes())
A = Asm()
A(I.SETN, x=256, y=48); A(I.GEMV, I.FMT_Q8_0, x=B + 0x0400, y=B + 0x5800, z=B + 0x6000)
A(I.SETN, x=256, y=48); A(I.GEMV, I.FMT_Q4_0, x=B + 0x3800, y=B + 0x5800, z=B + 0x6100)
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


with open("perf_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package perf_pkg is\n")
    f.write("  type wordsp_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {m.pc};\n")
    f.write(f"  constant PERF_LIMIT_NS : natural := {PERF_LIMIT_NS};\n")
    for name, data in (("INIT", bytes(mem[:0x6000])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : wordsp_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
