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
def op_laddi(m, d, n): v = m.l[d[1]] + n[1]; m.c = v > M32; m.l[d[1]] = v & M32; _lflags(m, v)
def op_lsub(m, d, s): v = m.l[d[1]] - m.l[s[1]]; m.c = v < 0; m.l[d[1]] = v & M32; _lflags(m, v)
def op_lsubi(m, d, n): v = m.l[d[1]] - n[1]; m.c = v < 0; m.l[d[1]] = v & M32; _lflags(m, v)
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
def op_sread(m, s): m.buf[0x800:0xA00] = m._sector(m.l[s[1]])
def op_swrite(m, s): m._sector(m.l[s[1]], bytes(m.buf[0x800:0xA00]))
def op_dread(m, s): m.buf[0xE00:0x1000] = m._sector(m.l[s[1]])
def op_dwrite(m, s): m._sector(m.l[s[1]], bytes(m.buf[0xE00:0x1000]))
def op_fatnx(m, d):
    c = m.l[d[1]]
    sec = m._sector(m.l[6] + (c >> 7))
    m.buf[0x800:0xA00] = sec                # (it goes through the engine slot)
    o = (c & 127) * 4
    v = int.from_bytes(sec[o:o + 4], "little") & 0x0FFFFFFF
    m.l[d[1]] = v
    m.z = v >= 0x0FFFFFF8
    m.c = v == 0 or v == 0x0FFFFFF7 or (1 <= v < 2)
def op_fatset(m, a, v):
    c = m.l[a[1]]
    for k in range(max(1, m.r[14])):
        lba = m.l[6] + k * m.l[5] + (c >> 7)
        sec = bytearray(m._sector(lba))
        o = (c & 127) * 4
        old = int.from_bytes(sec[o:o + 4], "little")
        sec[o:o + 4] = ((old & 0xF0000000) | (m.l[v[1]] & 0x0FFFFFFF)).to_bytes(4, "little")
        m._sector(lba, bytes(sec))
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
