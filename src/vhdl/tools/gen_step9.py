"""Step 9 test: the vector element ops a build without the LLM units keeps
(has_vec): VADD, VMUL, VSUB, CVT16, VRECIP, VCVTI16, VMAX, VMIN, VPROJ16,
against the reference emulator in hardware-numerics mode; then one LLM op
(VEXP), which such a build refuses (ERR_OPCODE, PC on it)."""
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

B = I.HYPERRAM_BASE
rng = np.random.default_rng(2024)
mem = bytearray(0x2000)
F32 = np.float32


def put(off, data):
    mem[off:off + len(data)] = data


def nb(v):
    return np.nextafter(F32(v), F32(-100)), np.nextafter(F32(v), F32(100))


xa = np.linspace(-6, 6, 70).astype(F32)
xb = (rng.standard_normal(70) * 3).astype(F32)
xb[:3] = [0.0, 1e-30, -1e-30]
put(0x208, xa.tobytes()); put(0x348, xb.tobytes())
ct = np.array([-1.25, -0.75, -0.25, 0.25, 0.75, 1.25, 16383.75, -16384.25,
               1e10, -1e10, np.nan, np.inf], dtype=F32)
put(0x488, ct.tobytes())
mx = np.array([0.0, -0.0, 0.0, -0.0, 1.5, -2.0, 3.0, -1e-30], dtype=F32)
my = np.array([-0.0, 0.0, 0.0, -0.0, 1.5, -2.0, -3.0, 1e-30], dtype=F32)
put(0x4C0, mx.tobytes()); put(0x4E0, my.tobytes())
assert not any(mem[0x1000:]), "test data must stay below $1000 (the bench loads only that)"

A = Asm()
A(I.SETN, x=70);         A(I.VADD, x=B + 0x208, y=B + 0x348, z=B + 0x1004)
A(I.VMUL, x=B + 0x208, y=B + 0x348, z=B + 0x1124)
A(I.VSUB, x=B + 0x208, y=B + 0x348, z=B + 0x1244)
A(I.CVT16, x=B + 0x348, z=B + 0x1364)
A(I.VRECIP, x=B + 0x348, z=B + 0x1400)
A(I.VMAX, x=B + 0x208, y=B + 0x348, z=B + 0x1520)
A(I.VMIN, x=B + 0x208, y=B + 0x348, z=B + 0x1640)
A(I.SETN, x=70, z=I.f32_bits(1000.0)); A(I.VCVTI16, x=B + 0x348, z=B + 0x1760)
A(I.SETN, x=12, z=I.f32_bits(2.0));    A(I.VCVTI16, x=B + 0x488, z=B + 0x17F0)
A(I.SETN, x=8);          A(I.VMAX, x=B + 0x4C0, y=B + 0x4E0, z=B + 0x1810)
A(I.VMIN, x=B + 0x4C0, y=B + 0x4E0, z=B + 0x1830)
A(I.SETN, x=70, y=I.f32_bits(160.0), z=I.f32_bits(80.5)); A(I.VPROJ16, x=B + 0x208, y=B + 0x348, z=B + 0x1852)
A(I.SETN, x=8);
vexp_at = len(A.assemble(B))
A(I.VEXP, x=B + 0x208, z=B + 0xE00)      # (not compared: below $1000)
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


with open("step9_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package step9_pkg is\n")
    f.write("  type words9_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {m.pc};\n")
    f.write(f"  constant VEXP_PC : natural := {B + vexp_at};\n")
    for name, data in (("INIT", bytes(mem[:0x1000])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : words9_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
