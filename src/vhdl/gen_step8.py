"""Step 8 test: Mamba-2's VEXP, SOFTPLUS and SSMUPD (Falcon-H1) against the
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


xe = np.linspace(-18, 2, 80).astype(F32)                   # VEXP: across the table
xe[:8] = [-16, 0, *nb(-16), *nb(0), -1e-30, 1e-30]
xp = np.linspace(-14, 14, 80).astype(F32)                  # SOFTPLUS
xp[:6] = [-12, 12, *nb(-12), *nb(12)]
R1, C1 = 70, 6                                             # SSMUPD: two groups of a, u
h1 = rng.standard_normal((R1, C1)).astype(F32)
a1 = rng.uniform(0.2, 1.0, R1).astype(F32)
u1 = (0.5 * rng.standard_normal(R1)).astype(F32)
b1 = rng.standard_normal(C1).astype(F32)
put(0x208, xe.tobytes()); put(0x348, xp.tobytes())
put(0x488, h1.tobytes()); put(0xB18, a1.tobytes()); put(0xC30, u1.tobytes()); put(0xD48, b1.tobytes())
H1, H2 = B + 0x1288, B + 0x1928                            # h: copied out (COPY: 8-aligned), updated in place
put(0xD60, struct.pack("<4I", H1, B + 0xB18, B + 0xC30, B + 0xD48))
# 2 rows x 80 (rows cross 256-byte blocks): h = xp twice over, B = xe
put(0xD70, struct.pack("<4I", H2, B + 0xB18, B + 0xC30, B + 0x208))
assert not any(mem[0x1000:]), "test data must stay below $1000 (the bench loads only that)"

A = Asm()
A(I.SETN, x=80);         A(I.VEXP, x=B + 0x208, z=B + 0x1004)
A(I.SETN, x=80);         A(I.SOFTPLUS, x=B + 0x348, z=B + 0x1144)
A(I.COPY, x=B + 0x488, y=H1, z=4 * R1 * C1)
A(I.SETN, x=C1, y=R1);   A(I.SSMUPD, x=B + 0xD60)
A(I.COPY, x=B + 0x348, y=H2, z=640)
A(I.SETN, x=80, y=2);    A(I.SSMUPD, x=B + 0xD70)
A(I.SETN, x=80, y=2);    A(I.SSMUPD, x=B + 0xD70)                # again: h from SSMUPD
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


with open("step8_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
            "package step8_pkg is\n")
    f.write("  type words8_t is array (natural range <>) of unsigned(15 downto 0);\n")
    f.write(f"  constant HALT_PC : natural := {m.pc};\n")
    for name, data in (("INIT", bytes(mem[:0x1000])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : words8_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
