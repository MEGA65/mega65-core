#!/usr/bin/env python3
"""Assembler and instruction-set simulator for the hardware FAT32 engine's MCU
(MEGA65/mega65-core#766; design in docs/sdcard-native/fat32-engine.md).

    prog = assemble(open("src/fat32/engine.fs").read())
    m = Machine(prog, cards={1: "external.img", 0: "internal.img"})
    m.command(0x70, request=...)      # run one $D680 command to completion

THE MACHINE
  R0-R15   8-bit registers
  L0-L7    32-bit registers (clusters, LBAs, positions, sizes)
  X, Y     12-bit pointers into the sector buffer address space ($000-$FFF):
             $000-$7FF  the engine's tables      $800-$9FF  its sector slot
             $E00-$FFF  the CPU's SD sector buffer (requests, data)
  flags    Z (zero / equal), C (carry / less than), E (the last sector
           operation failed)
  stack    8 return addresses
  slot     the card (0 internal, 1 external) of sector operations

INSTRUCTIONS (r = R register, l = L register, n = number, lbl = label)
  ldi r,n  mov r,r  add r,r  addi r,n  sub r,r  subi r,n  and r,r  andi r,n
  or r,r  ori r,n  xor r,r  xori r,n  cmp r,r  cmpi r,n  shl r  shr r  inc r  dec r
  ld r,[x+n] ld r,[y+n] st r,[x+n] st r,[y+n] (n 0..255)  ldx r ([x], x+1)  sty r ([y]=r, y+1)
  lldi l,n  lmov l,l  ladd l,l  laddi l,n  lsub l,l  lsubi l,n  lcmp l,l  lcmpi l,n
  lshl l,n  lshr l,n  lshlr l,r  lshrr l,r (by a register)  land l,l  landi l,n
  lor l,l  lz l
  lld l,[x+n] lst l,[x+n] lld l,[y+n] lst l,[y+n] (4 bytes, little-endian)
  lldw l,[x+n] lstw l,[x+n] (2 bytes)  ltob r,l,k (byte k)  btol l,r
  xset n  yset n  xaddi n  yaddi n  xadd r  yadd r  xl l  yl l  lx l  ly l  xy (swap)
  jmp/jz/jnz/jc/jnc/je/jne lbl   call lbl   ret
  slot r                    sector operations use card r
  sread l   swrite l        the engine slot ($800) from / to sector l (absolute LBA)
  dread l   dwrite l        the CPU's buffer ($E00) from / to sector l
  fatnx l                   l = FAT entry l (FAT at L6, absolute LBA); Z = end of
                            chain (>= $0FFFFFF8), C = free or bad.  The FAT
                            sector is read into the engine slot ($800)
  fatset l,l                FAT entry = value, in R14 FATs of L5 sectors from L6
                            (each FAT sector through the engine slot)
  ncmp n                    compare n bytes [x] and [y], ASCII case-blind: Z
  scmp                      compare the 0-terminated strings at x and y, ASCII
                            case-blind: Z
  lfnput                    long-filename entry at x: its 13 characters as ASCII
                            (others '?') into [y + 13 * (sequence - 1)]
  lfnsum r                  r = the 8.3 checksum of the 11 bytes at x
  copy r                    r bytes (0 = 256) from [x] to [y]; x, y advance
  fill r                    r bytes (0 = 256) of R0 at [y]; y advances
  cmd r                     r = the $D680 command
  arg l    setarg l         l = $D681-$D684 / set them
  hyp                       C = hypervisor mode
  done     fail n  failr r  end the command: success / error n / error in r

  .equ NAME value   labels end with ':'   ';' comments   numbers: 12, $1F, %101
"""

import re

REGS_R = {"r%d" % i: i for i in range(16)}
REGS_L = {"l%d" % i: i for i in range(8)}


class AsmError(Exception):
    pass


def parse_num(tok, equ):
    tok = tok.strip()
    if tok.lower() in equ:
        return equ[tok.lower()]
    m = re.fullmatch(r"([^+\-]+)([+\-])(.+)", tok)
    if m and not tok.startswith(("$", "%", "-")):
        a, op, b = m.groups()
        a, b = parse_num(a, equ), parse_num(b, equ)
        return a + b if op == "+" else a - b
    if tok.startswith("$"):
        return int(tok[1:], 16)
    if tok.startswith("%"):
        return int(tok[1:], 2)
    if tok.startswith("'") and tok.endswith("'") and len(tok) == 3:
        return ord(tok[1])
    return int(tok, 0)


def assemble(source):
    """-> list of (op, operands tuple, source line number); labels resolved"""
    equ, labels, raw = {}, {}, []
    for lineno, line in enumerate(source.splitlines(), 1):
        line = line.split(";", 1)[0].strip()
        if not line:
            continue
        while ":" in line.split()[0] and not line.startswith("."):
            lab, _, line = line.partition(":")
            if lab.strip().lower() in labels:
                raise AsmError("line %d: label %s defined twice" % (lineno, lab.strip()))
            labels[lab.strip().lower()] = len(raw)
            line = line.strip()
            if not line:
                break
        if not line:
            continue
        if line.lower().startswith(".equ"):
            _, name, val = line.split(None, 2)
            equ[name.rstrip(",").lower()] = parse_num(val.lstrip(", "), equ)
            continue
        op, _, rest = line.partition(" ")
        args = [a.strip() for a in re.split(r",(?![^\[]*\])", rest)] if rest.strip() else []
        raw.append((op.lower(), args, lineno))
    prog = []
    for op, args, lineno in raw:
        try:
            prog.append((op, tuple(operand(a, equ, labels) for a in args), lineno))
        except (KeyError, ValueError) as e:
            raise AsmError("line %d: %s %s: %s" % (lineno, op, ",".join(args), e))
    for op, args, lineno in prog:
        if op not in OPS:
            raise AsmError("line %d: unknown instruction %s" % (lineno, op))
    return prog


def operand(a, equ, labels):
    al = a.lower()
    if al in REGS_R:
        return ("r", REGS_R[al])
    if al in REGS_L:
        return ("l", REGS_L[al])
    m = re.fullmatch(r"\[\s*([xy])\s*(?:\+\s*(.+))?\]", al)
    if m:
        return ("m", m.group(1), parse_num(m.group(2), equ) if m.group(2) else 0)
    if al in labels:
        return ("a", labels[al])
    return ("n", parse_num(a, equ))


class EngineError(Exception):
    pass


class Machine:
    def __init__(self, prog, cards, hypervisor=False):
        """cards: {slot: image file path}"""
        self.prog = prog
        self.files = {s: open(p, "r+b") for s, p in cards.items()}
        self.buf = bytearray(4096)
        self.r = [0] * 16
        self.l = [0] * 8
        self.x = self.y = 0
        self.z = self.c = self.e = False
        self.stack = []
        self.slot = 0
        self.hypervisor = hypervisor
        self.arg = 0
        self.cmdcode = 0
        self.steps = 0
        self.sector_ops = 0
        self.trace = None                   # start_trace(): for the RTL testbench

    # --- a transcript, replayed by tb_fat32_engine.vhdl ---
    def start_trace(self):
        self.trace = []
        self.trace_sectors = {}
        self._shadow = bytearray(4096)

    @staticmethod
    def _runs(old, new):
        i = 0
        while i < 4096:
            if old[i] == new[i]:
                i += 1
                continue
            j = i
            while j < 4096 and j - i < 64 and old[j] != new[j]:
                j += 1
            yield i, bytes(new[i:j])
            i = j

    def write_trace(self, path):
        with open(path, "w") as f:
            for (slot, lba), data in sorted(self.trace_sectors.items()):
                f.write("S %d %08X %s\n" % (slot, lba, data.hex().upper()))
            for line in self.trace:
                f.write(line + "\n")

    # --- the card ---
    def _sector(self, lba, data=None):
        f = self.files.get(self.slot)
        self.sector_ops += 1
        if f is None:
            self.e = True
            return bytes(512)
        f.seek(lba * 512)
        if data is None:
            d = f.read(512)
            self.e = len(d) != 512
            if self.trace is not None and not self.e:
                self.trace_sectors[(self.slot, lba)] = d
            return d.ljust(512, b"\0")
        f.write(data)
        self.e = False
        return None

    # --- running a command ---
    def command(self, code, arg=0, hypervisor=None, entry="start", limit=5_000_000):
        """run one command from label `entry`; -> (status, arg)"""
        if hypervisor is not None:
            self.hypervisor = hypervisor
        self.cmdcode, self.arg = code, arg
        if self.trace is not None:
            for a, d in self._runs(self._shadow, self.buf):
                self.trace.append("W %03X %s" % (a, d.hex().upper()))
            self.trace.append("C %02X %08X %d" % (code, arg, int(self.hypervisor)))
            before = bytes(self.buf)
        self.pc = 0
        self.stack = []
        self.result = None
        n = 0
        while self.result is None:
            if n > limit:
                raise EngineError("no end after %d steps (pc %d)" % (n, self.pc))
            self.step()
            n += 1
        self.steps += n
        self.last_steps = n
        if self.trace is not None:
            for a, d in self._runs(before, self.buf):
                self.trace.append("E %03X %s" % (a, d.hex().upper()))
            self.trace.append("R %02X %08X %X" % (self.result, self.arg, n))
            self._shadow = bytearray(self.buf)
        return self.result, self.arg

    def b(self, a):
        return self.buf[a & 0xFFF]

    def setb(self, a, v):
        self.buf[a & 0xFFF] = v & 0xFF

    def addr(self, m):
        return ((self.x if m[1] == "x" else self.y) + m[2]) & 0xFFF

    def step(self):
        op, a, lineno = self.prog[self.pc]
        self.pc += 1
        self.line = lineno
        OPS[op](self, *a)


def _flags8(m, v):
    m.z = (v & 0xFF) == 0


def _r(op):
    return op[1]


def op_ldi(m, d, n): m.r[d[1]] = n[1] & 0xFF; _flags8(m, m.r[d[1]])
def op_mov(m, d, s): m.r[d[1]] = m.r[s[1]]; _flags8(m, m.r[d[1]])
def _arith(m, d, v, sub=False):
    a = m.r[d[1]]
    res = a - v if sub else a + v
    m.c = res < 0 if sub else res > 255
    m.r[d[1]] = res & 0xFF
    _flags8(m, res)
def op_add(m, d, s): _arith(m, d, m.r[s[1]])
def op_addi(m, d, n): _arith(m, d, n[1] & 0xFF)
def op_sub(m, d, s): _arith(m, d, m.r[s[1]], True)
def op_subi(m, d, n): _arith(m, d, n[1] & 0xFF, True)
def op_and(m, d, s): m.r[d[1]] &= m.r[s[1]]; _flags8(m, m.r[d[1]])
def op_andi(m, d, n): m.r[d[1]] &= n[1]; _flags8(m, m.r[d[1]])
def op_or(m, d, s): m.r[d[1]] |= m.r[s[1]]; _flags8(m, m.r[d[1]])
def op_ori(m, d, n): m.r[d[1]] = (m.r[d[1]] | n[1]) & 0xFF; _flags8(m, m.r[d[1]])
def op_xor(m, d, s): m.r[d[1]] ^= m.r[s[1]]; _flags8(m, m.r[d[1]])
def op_xori(m, d, n): m.r[d[1]] = (m.r[d[1]] ^ n[1]) & 0xFF; _flags8(m, m.r[d[1]])
def op_cmp(m, d, s): a, b = m.r[d[1]], m.r[s[1]]; m.z, m.c = a == b, a < b
def op_cmpi(m, d, n): a, b = m.r[d[1]], n[1] & 0xFF; m.z, m.c = a == b, a < b
def op_shl(m, d): v = m.r[d[1]] << 1; m.c = v > 255; m.r[d[1]] = v & 0xFF; _flags8(m, v)
def op_shr(m, d): v = m.r[d[1]]; m.c = bool(v & 1); m.r[d[1]] = v >> 1; _flags8(m, v >> 1)
def op_inc(m, d): m.r[d[1]] = (m.r[d[1]] + 1) & 0xFF; _flags8(m, m.r[d[1]])
def op_dec(m, d): m.r[d[1]] = (m.r[d[1]] - 1) & 0xFF; _flags8(m, m.r[d[1]])
def op_ld(m, d, a): m.r[d[1]] = m.b(m.addr(a)); _flags8(m, m.r[d[1]])
def op_st(m, s, a): m.setb(m.addr(a), m.r[s[1]])
def op_ldx(m, d): m.r[d[1]] = m.b(m.x); m.x = (m.x + 1) & 0xFFF; _flags8(m, m.r[d[1]])
def op_sty(m, s): m.setb(m.y, m.r[s[1]]); m.y = (m.y + 1) & 0xFFF

M32 = 0xFFFFFFFF
def _lflags(m, v): m.z = (v & M32) == 0
def op_lldi(m, d, n): m.l[d[1]] = n[1] & M32; _lflags(m, m.l[d[1]])
def op_lmov(m, d, s): m.l[d[1]] = m.l[s[1]]; _lflags(m, m.l[d[1]])
def op_ladd(m, d, s): v = m.l[d[1]] + m.l[s[1]]; m.c = v > M32; m.l[d[1]] = v & M32; _lflags(m, v)
def op_laddi(m, d, n): v = m.l[d[1]] + (n[1] & M32); m.c = v > M32; m.l[d[1]] = v & M32; _lflags(m, v)
def op_lsub(m, d, s): v = m.l[d[1]] - m.l[s[1]]; m.c = v < 0; m.l[d[1]] = v & M32; _lflags(m, v)
def op_lsubi(m, d, n): v = m.l[d[1]] - (n[1] & M32); m.c = v < 0; m.l[d[1]] = v & M32; _lflags(m, v)
def op_lcmp(m, d, s): a, b = m.l[d[1]], m.l[s[1]]; m.z, m.c = a == b, a < b
def op_lcmpi(m, d, n): a, b = m.l[d[1]], n[1] & M32; m.z, m.c = a == b, a < b
def op_lshl(m, d, n): m.l[d[1]] = (m.l[d[1]] << n[1]) & M32; _lflags(m, m.l[d[1]])
def op_lshr(m, d, n): m.l[d[1]] >>= n[1]; _lflags(m, m.l[d[1]])
def op_lshlr(m, d, s): m.l[d[1]] = (m.l[d[1]] << (m.r[s[1]] & 31)) & M32; _lflags(m, m.l[d[1]])
def op_lshrr(m, d, s): m.l[d[1]] >>= (m.r[s[1]] & 31); _lflags(m, m.l[d[1]])
def op_land(m, d, s): m.l[d[1]] &= m.l[s[1]]; _lflags(m, m.l[d[1]])
def op_landi(m, d, n): m.l[d[1]] &= n[1]; _lflags(m, m.l[d[1]])
def op_lor(m, d, s): m.l[d[1]] |= m.l[s[1]]; _lflags(m, m.l[d[1]])
def op_lz(m, d): _lflags(m, m.l[d[1]])
def op_lld(m, d, a):
    p = m.addr(a)
    m.l[d[1]] = sum(m.b(p + i) << (8 * i) for i in range(4)); _lflags(m, m.l[d[1]])
def op_lst(m, s, a):
    p = m.addr(a)
    for i in range(4):
        m.setb(p + i, m.l[s[1]] >> (8 * i))
def op_lldw(m, d, a):
    p = m.addr(a)
    m.l[d[1]] = m.b(p) | m.b(p + 1) << 8; _lflags(m, m.l[d[1]])
def op_lstw(m, s, a):
    p = m.addr(a)
    m.setb(p, m.l[s[1]]); m.setb(p + 1, m.l[s[1]] >> 8)
def op_ltob(m, d, s, k): m.r[d[1]] = (m.l[s[1]] >> (8 * k[1])) & 0xFF; _flags8(m, m.r[d[1]])
def op_btol(m, d, s): m.l[d[1]] = m.r[s[1]]; _lflags(m, m.l[d[1]])

def op_xset(m, n): m.x = n[1] & 0xFFF
def op_yset(m, n): m.y = n[1] & 0xFFF
def op_xaddi(m, n): m.x = (m.x + n[1]) & 0xFFF
def op_yaddi(m, n): m.y = (m.y + n[1]) & 0xFFF
def op_xadd(m, s): m.x = (m.x + m.r[s[1]]) & 0xFFF
def op_yadd(m, s): m.y = (m.y + m.r[s[1]]) & 0xFFF
def op_xl(m, s): m.x = m.l[s[1]] & 0xFFF
def op_yl(m, s): m.y = m.l[s[1]] & 0xFFF
def op_lx(m, d): m.l[d[1]] = m.x
def op_ly(m, d): m.l[d[1]] = m.y
def op_xy(m): m.x, m.y = m.y, m.x

def _jump(m, a, cond):
    if cond:
        m.pc = a[1]
def op_jmp(m, a): _jump(m, a, True)
def op_jz(m, a): _jump(m, a, m.z)
def op_jnz(m, a): _jump(m, a, not m.z)
def op_jc(m, a): _jump(m, a, m.c)
def op_jnc(m, a): _jump(m, a, not m.c)
def op_je(m, a): _jump(m, a, m.e)
def op_jne(m, a): _jump(m, a, not m.e)
def op_call(m, a):
    if len(m.stack) == 8:
        raise EngineError("stack overflow at line %d" % m.line)
    m.stack.append(m.pc); m.pc = a[1]
def op_ret(m):
    if not m.stack:
        raise EngineError("stack underflow at line %d" % m.line)
    m.pc = m.stack.pop()

def op_slot(m, s): m.slot = m.r[s[1]] & 1
def _read_into(m, lba, at):
    d = m._sector(lba)
    if not m.e:                             # (a failed read leaves the buffer)
        m.buf[at:at + 512] = d
def op_sread(m, s): _read_into(m, m.l[s[1]], 0x800)
def op_swrite(m, s): m._sector(m.l[s[1]], bytes(m.buf[0x800:0xA00]))
def op_dread(m, s): _read_into(m, m.l[s[1]], 0xE00)
def op_dwrite(m, s): m._sector(m.l[s[1]], bytes(m.buf[0xE00:0x1000]))
def op_fatnx(m, d):
    c = m.l[d[1]]
    _read_into(m, m.l[6] + (c >> 7), 0x800)  # (it goes through the engine slot)
    o = 0x800 + (c & 127) * 4
    v = int.from_bytes(m.buf[o:o + 4], "little") & 0x0FFFFFFF
    m.l[d[1]] = v
    m.z = v >= 0x0FFFFFF8
    m.c = v == 0 or v == 0x0FFFFFF7 or (1 <= v < 2)
def op_fatset(m, a, v):
    c = m.l[a[1]]
    for k in range(max(1, m.r[14])):
        lba = m.l[6] + k * m.l[5] + (c >> 7)
        _read_into(m, lba, 0x800)               # (through the engine slot)
        if m.e:
            return
        o = 0x800 + (c & 127) * 4
        old = int.from_bytes(m.buf[o:o + 4], "little")
        m.buf[o:o + 4] = ((old & 0xF0000000) | (m.l[v[1]] & 0x0FFFFFFF)).to_bytes(4, "little")
        m._sector(lba, bytes(m.buf[0x800:0xA00]))
def op_ncmp(m, n):
    up = lambda c: c - 32 if 97 <= c <= 122 else c
    m.z = all(up(m.b(m.x + i)) == up(m.b(m.y + i)) for i in range(n[1]))
def op_scmp(m):
    up = lambda c: c - 32 if 97 <= c <= 122 else c
    i = 0
    while True:
        a, b = up(m.b(m.x + i)), up(m.b(m.y + i))
        if a != b:
            m.z = False
            return
        if a == 0:
            m.z = True
            return
        i += 1
def op_lfnput(m):
    seq = m.b(m.x) & 0x1F
    if not 1 <= seq <= 20:
        return
    pos = [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30]
    for i, p in enumerate(pos):
        u = m.b(m.x + p) | m.b(m.x + p + 1) << 8
        ch = 0 if u in (0, 0xFFFF) else (u if u < 128 else ord("?"))
        m.setb(m.y + 13 * (seq - 1) + i, ch)
def op_lfnsum(m, d):
    s = 0
    for i in range(11):
        s = (((s & 1) << 7) + (s >> 1) + m.b(m.x + i)) & 0xFF
    m.r[d[1]] = s
def op_copy(m, s):
    n = m.r[s[1]] or 256
    for _ in range(n):
        m.setb(m.y, m.b(m.x)); m.x = (m.x + 1) & 0xFFF; m.y = (m.y + 1) & 0xFFF
def op_fill(m, s):
    n = m.r[s[1]] or 256
    for _ in range(n):
        m.setb(m.y, m.r[0]); m.y = (m.y + 1) & 0xFFF
def op_cmd(m, d): m.r[d[1]] = m.cmdcode
def op_arg(m, d): m.l[d[1]] = m.arg
def op_setarg(m, s): m.arg = m.l[s[1]]
def op_hyp(m): m.c = m.hypervisor
def op_done(m): m.result = 0
def op_fail(m, n): m.result = n[1]
def op_failr(m, s): m.result = m.r[s[1]] or 0xFF

OPS = {name[3:]: fn for name, fn in globals().items() if name.startswith("op_")}


# ---- the instruction word ------------------------------------------------------
# 24 bits: [23:17] opcode, [16:13] register A, [12:9] register B (an L register
# uses the low 3 bits of its field), immediates in the low bits:
#   n8 [7:0]   s13/u13 [12:0] (L-register immediates: lldi/lcmpi/landi zero-
#   extend, laddi/lsubi sign-extend)   n5 [4:0] (long shifts)   u12/s12 [11:0]
#   (pointers)   k2 [1:0] (ltob)   a11 [10:0] (jumps)
#   memory operands: [12] 0 = X, 1 = Y; offset n8 [7:0]
# Operand kinds: r/l take the next register field; anything else is the
# immediate.
ENCODING = [
    # (mnemonic, operand kinds, immediate format)
    ("ldi", "rn", "n8"), ("addi", "rn", "n8"), ("subi", "rn", "n8"), ("andi", "rn", "n8"),
    ("ori", "rn", "n8"), ("xori", "rn", "n8"), ("cmpi", "rn", "n8"),
    ("mov", "rr", None), ("add", "rr", None), ("sub", "rr", None), ("and", "rr", None),
    ("or", "rr", None), ("xor", "rr", None), ("cmp", "rr", None),
    ("shl", "r", None), ("shr", "r", None), ("inc", "r", None), ("dec", "r", None),
    ("ld", "rm", "m"), ("st", "rm", "m"), ("ldx", "r", None), ("sty", "r", None),
    ("lldi", "ln", "u13"), ("lcmpi", "ln", "u13"), ("landi", "ln", "u13"),
    ("laddi", "ln", "s13"), ("lsubi", "ln", "s13"),
    ("lmov", "ll", None), ("ladd", "ll", None), ("lsub", "ll", None), ("lcmp", "ll", None),
    ("land", "ll", None), ("lor", "ll", None),
    ("lshl", "ln", "n5"), ("lshr", "ln", "n5"), ("lshlr", "lr", None), ("lshrr", "lr", None),
    ("lz", "l", None),
    ("lld", "lm", "m"), ("lst", "lm", "m"), ("lldw", "lm", "m"), ("lstw", "lm", "m"),
    ("ltob", "rln", "k2"), ("btol", "lr", None),
    ("xset", "n", "u12"), ("yset", "n", "u12"), ("xaddi", "n", "s12"), ("yaddi", "n", "s12"),
    ("xadd", "r", None), ("yadd", "r", None), ("xl", "l", None), ("yl", "l", None),
    ("lx", "l", None), ("ly", "l", None), ("xy", "", None),
    ("jmp", "a", "a11"), ("jz", "a", "a11"), ("jnz", "a", "a11"), ("jc", "a", "a11"),
    ("jnc", "a", "a11"), ("je", "a", "a11"), ("jne", "a", "a11"), ("call", "a", "a11"),
    ("ret", "", None),
    ("slot", "r", None), ("sread", "l", None), ("swrite", "l", None), ("dread", "l", None),
    ("dwrite", "l", None), ("fatnx", "l", None), ("fatset", "ll", None),
    ("ncmp", "n", "n8"), ("scmp", "", None), ("lfnput", "", None), ("lfnsum", "r", None),
    ("copy", "r", None), ("fill", "r", None),
    ("cmd", "r", None), ("arg", "l", None), ("setarg", "l", None), ("hyp", "", None),
    ("done", "", None), ("fail", "n", "n8"), ("failr", "r", None),
]
OPCODE = {name: i for i, (name, _, _) in enumerate(ENCODING)}
assert len(OPCODE) <= 128 and set(OPCODE) == set(OPS), set(OPS) ^ set(OPCODE)


def encode(prog):
    """-> list of 24-bit instruction words"""
    out = []
    for op, args, lineno in prog:
        name, kinds, imm = ENCODING[OPCODE[op]]
        if len(args) != len(kinds):
            raise AsmError("line %d: %s takes %d operands" % (lineno, op, len(kinds)))
        w = OPCODE[op] << 17
        regs = 0
        for kind, a in zip(kinds, args):
            if kind in "rl":
                if a[0] != kind:
                    raise AsmError("line %d: %s: operand should be %s register" % (lineno, op, kind.upper()))
                w |= a[1] << (13 - 4 * regs)
                regs += 1
                continue
            if kind == "m":
                if a[0] != "m" or not 0 <= a[2] <= 255:
                    raise AsmError("line %d: %s: needs [x+0..255] / [y+0..255]" % (lineno, op))
                w |= (a[1] == "y") << 12 | a[2]
                continue
            v = a[1]
            bits, signed = {"n8": (8, False), "u13": (13, False), "s13": (13, True),
                            "n5": (5, False), "u12": (12, False), "s12": (12, True),
                            "k2": (2, False), "a11": (11, False)}[imm]
            lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if signed else (0, (1 << bits) - 1)
            if kind == "n" and imm == "n8" and -128 <= v < 0:
                v &= 0xFF                       # (byte immediates: either sign)
            if not lo <= v <= hi:
                raise AsmError("line %d: %s: %d does not fit %s" % (lineno, op, v, imm))
            w |= v & ((1 << bits) - 1)
        out.append(w)
    if len(out) > 2048:
        raise AsmError("program too long: %d instructions" % len(out))
    return out


def decode_imm(op, w):
    """the immediate of word w as the hardware sees it (for checking encode)"""
    imm = ENCODING[OPCODE[op]][2]
    if imm == "m":
        return w & 0xFF
    bits, signed = {"n8": (8, False), "u13": (13, False), "s13": (13, True), "n5": (5, False),
                    "u12": (12, False), "s12": (12, True), "k2": (2, False), "a11": (11, False)}[imm]
    v = w & ((1 << bits) - 1)
    return v - (1 << bits) if signed and v >> (bits - 1) else v


def vhdl_rom(prog, name="fat32_rom_pkg"):
    words = encode(prog)
    lines = ["-- Generated by src/tools/fat32sim.py from the FAT32 engine firmware",
             "-- (MEGA65/mega65-core#766).  Do not edit.",
             "library ieee;", "use ieee.std_logic_1164.all;", "",
             "package %s is" % name,
             "  constant FAT32_ROM_SIZE : natural := %d;" % len(words),
             "  type t_fat32_rom is array(0 to 2047) of std_logic_vector(23 downto 0);",
             "  constant FAT32_ROM : t_fat32_rom := ("]
    for i, (w, (op, args, lineno)) in enumerate(zip(words, prog)):
        lines.append('    %4d => x"%06X",  -- %s (line %d)' % (i, w, op, lineno))
    lines.append('    others => x"%06X");' % (OPCODE["fail"] << 17 | 0xFF))
    for i, (n, _, _) in enumerate(ENCODING):
        lines.append("  constant OP_%s : natural := %d;" % (n.upper(), i))
    lines.append("end package;")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3:
        sys.exit("usage: fat32sim.py firmware.fs rom_package.vhdl")
    prog = assemble(open(sys.argv[1]).read())
    open(sys.argv[2], "w").write(vhdl_rom(prog))
    print("%d instructions" % len(prog))
