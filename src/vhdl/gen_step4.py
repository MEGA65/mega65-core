"""Step 4 test: RMSNORM, LAYERNORM, SILUMUL, GELU, MEANROWS against the
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
rng = np.random.default_rng(2024)
mem = bytearray(0x2000)
F32 = np.float32


def put(off, data):
    mem[off:off + len(data)] = data


def nb(v):
    return np.nextafter(F32(v), F32(-100)), np.nextafter(F32(v), F32(100))


xr = (rng.standard_normal(100) * 3).astype(F32)            # RMSNORM
gr = (1 + 0.1 * rng.standard_normal(100)).astype(F32)
xl = (rng.standard_normal(96) * 2 + 1).astype(F32)         # LAYERNORM
gl = (1 + 0.1 * rng.standard_normal(96)).astype(F32)
bl = (0.1 * rng.standard_normal(96)).astype(F32)
xs = np.linspace(-15, 15, 120).astype(F32)                 # SILUMUL: across the table
xs[:8] = [-12, 12, *nb(-12), *nb(12), -1e-30, 0]
ys = (rng.standard_normal(120)).astype(F32)
xg = np.linspace(-8, 8, 80).astype(F32)                    # GELU
xg[:6] = [-6, 6, *nb(-6), *nb(6)]
mrows = (rng.standard_normal((2, 40))).astype(F32)         # MEANROWS
put(0x204, xr.tobytes()); put(0x394, gr.tobytes())
put(0x524, xl.tobytes()); put(0x6A4, gl.tobytes()); put(0x824, bl.tobytes())
put(0x9A4, xs.tobytes()); put(0xB84, ys.tobytes())
put(0xD64, xg.tobytes())
put(0xEA4, mrows[:2].tobytes())                           # MEANROWS: 2 rows x 40 (320 bytes)
assert not any(mem[0x1000:]), "test data must stay below $1000 (the bench loads only that)"

eps = I.f32_bits(1e-5)
A = Asm()
A(I.SETN, x=100, z=eps); A(I.RMSNORM, x=B + 0x204, y=B + 0x394, z=B + 0x1004)
A(I.SETN, x=96, z=eps);  A(I.LAYERNORM, x=B + 0x524, y=B + 0x6A4, z=B + 0x11A4)
A(I.SETN, x=120);        A(I.SILUMUL, x=B + 0x9A4, y=B + 0xB84, z=B + 0x1324)
A(I.SETN, x=80);         A(I.GELU, x=B + 0xD64, z=B + 0x1504)
A(I.LI, 2, z=2)
A(I.SETN, x=40);         A(I.MEANROWS, 2, x=B + 0xEA4, z=B + 0x1644)
A(I.SETN, x=120);        A(I.SILUMUL, x=B + 0x1324, y=B + 0xB84, z=B + 0x1324)   # in place
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


with open("step4_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package step4_pkg is\n")
    f.write("  type words4_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {m.pc};\n")
    for name, data in (("INIT", bytes(mem[:0x1000])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : words4_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
