"""Assemble the step-1 test program, run it on the reference emulator, and
emit a VHDL package with the program, initial data and expected results."""
import os
import sys
sys.path.insert(0, os.environ.get("SSNAIL_TOOLS",
                os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ssnail_tools")))
import ssnail_isa as I
from ssnail_convert import Asm
import ssnail_sim as S

B = I.HYPERRAM_BASE
A = Asm()
A(I.LI, 1, z=0x12345678)
A(I.STR, 1, x=B + 0x600)
A(I.LI, 2, z=0)
A(I.LI, 3, z=5)
A.label("loop")
A(I.LEA, 0, 2, B + 0x610, z=4)
A(I.ADDI, 4, 2, z=100)
A(I.STR, 4, x=I.reg_addr(0))
A(I.ADDI, 2, 2, z=1)
A(I.BLT, 2, 3, "loop")
A(I.BEQ, 2, 3, "eq_ok")
A(I.LI, 5, z=0xBAD)                       # skipped
A.label("eq_ok")
A(I.BNE, 2, 3, "bad")                     # not taken
A(I.ADDI, 15, 2, z=7)                     # write to R15: ignored
A(I.STR, 15, x=B + 0x630)                 # stores 0
A(I.ADDI, 6, 15, z=0xFFFFFFFF)            # 0 - 1
A(I.STR, 6, x=B + 0x634)
A(I.LDR, 7, x=B + 0x614)                  # upper half of an 8-byte group
A(I.ADDI, 7, 7, z=1000)
A(I.STR, 7, x=B + 0x638)
A(I.LEA, 1, 3, B + 0x400, z=0x10)         # A1 = $8000450
A(I.COPY, x=I.reg_addr(1, 0x10), y=B + 0x640, z=16)   # register-relative source
A(I.STR, 5, x=B + 0x63C)                  # R5 never set: 0
A(I.LEA, 2, 3, I.reg_addr(1, 0x200), z=0x10)          # A2 = A1 + $200 + 5*$10
A(I.LI, 1, z=0xCAFEF00D)
A(I.STR, 1, x=I.reg_addr(2, 4))           # $80006A0 + 4
A(I.SETN, x=1, y=2, z=3)
A(I.HALT)
A.label("bad")
A(I.LI, 5, z=0xDEAD)
A(I.STR, 5, x=B + 0x63C)
A(I.HALT)
code = A.assemble(B)

mem = bytearray(0x2000)
mem[0:len(code)] = code
for i in range(16):
    mem[0x460 + i] = (0x30 + 7 * i) & 0xFF

m = S.Machine.__new__(S.Machine)
m.mem = bytearray(8 << 20)
m.mem[:len(mem)] = mem
m.R, m.A, m.N, m.pc = [0] * 16, [0] * 16, [0] * 3, 0
m.stats = dict(instructions=0, bytes_read=0, bytes_written=0)
m.on_argmax = m.on_sync = None
m.trace = False
m.temperature, m.top_k, m.rep_penalty, m.rep_window = 0.0, 0, 1.0, 64
m.run(B)
expect = bytes(m.mem[0x600:0x6C0])
print(f"program {len(code) // 16} instructions; emulator executed {m.stats['instructions']}",
      file=sys.stderr)
print(f"halt pc ${m.pc:07X}", file=sys.stderr)

def words(b):
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]

with open("step1_pkg.vhdl", "w") as f:
    f.write("library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\npackage step1_pkg is\n")
    f.write("  type words_t is array (natural range <>) of unsigned(15 downto 0);\n")
    for name, data in (("INIT", bytes(mem[:0x600])), ("EXPECT", expect)):
        w = words(data)
        f.write(f"  constant {name} : words_t(0 to {len(w) - 1}) := (\n")
        f.write(",\n".join("    x\"%04X\"" % v for v in w))
        f.write(");\n")
    f.write("end package;\n")
