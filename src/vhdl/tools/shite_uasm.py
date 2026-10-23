#!/usr/bin/env python3
"""SHITE's microcode assembler: shite_ucode.asm -> shite_ucode_pkg.vhdl
(the ROM, the registers' first values and the encoding's constants, for
shite_useq.vhdl).  docs/shite/MICROCODE.md describes the micro-ops.

    shite_uasm.py [source] [-o package] [--list listing] [--check committed]

With no arguments: src/vhdl/shite_ucode.asm to ./shite_ucode_pkg.vhdl; made
anywhere but src/vhdl, it fails unless src/vhdl's (the one Vivado reads)
is the same.
--check FILE: fail if FILE (the committed package) is not what the source
assembles to.

The source, a line at a time (';' to the end of the line is a comment):

    .equ NAME = expr          a constant, for expressions
    .reg a, b, c              registers named (r1 upwards)
    .const NAME = expr        a register holding expr from the start (r127 down)
    .scope / .endscope        the registers named between: freed at the end
                              (for routines never running at once)
    label:                    (may share its line with an op)
    op operands [| cond [target]]

Registers: r0-r127, the names given, _ (r0: reads 0, writes lost).
Immediates: #expr (29 bits, sign-extended; labels are addresses in
expressions).  Memory: [reg], [reg+expr], [reg-expr].  The ops and the
pseudo-ops are below (Asm.op)."""
import argparse
import os
import re
import sys

ROM_WORDS = 2048
DATA_WORDS = 2048
NREGS = 128
IMM_BITS = 29

OPS = dict(ADD=0, SUB=1, AND=2, OR=3, XOR=4, ANDN=5, SHL=6, SHR=7, SAR=8, EXT=9, EXTS=10,
           INS=11, HI=12, SETSP=13, MOVX=14, LDB=16, LDH=17, LDL=18, LDQ=19, STB=20, STH=21, STL=22,
           STQ=23, LDD=24, STD=25, RES=26, END=27, OUT=28, IN=29, JOB=30)
CONDS = dict(NONE=0, JMP=1, CALL=2, RET=3, JTAB=4, Z=5, NZ=6, UGE=7, ULT=8, LT=9, GE=10,
             MI=11, PL=12, ABT=13, NABT=14)
MOVX_SRC = dict(OP=0, RA=1, RB=2, RC=3, RD=4, RZ=5, X=6, SP=7)
ALU3 = ("ADD", "SUB", "AND", "OR", "XOR", "ANDN", "SHL", "SHR", "SAR", "HI")
LOADS = ("LDB", "LDH", "LDL", "LDQ", "LDD")
STORES = ("STB", "STH", "STL", "STQ", "STD")


class AsmError(Exception):
    pass


class Word:
    def __init__(self, src, line):
        self.op, self.rd, self.ra, self.rb, self.bimm = 0, 0, 0, 0, 0
        self.cond, self.target, self.imm = 0, None, 0
        self.src, self.line = src, line

    def encode(self, labels):
        t = 0
        if isinstance(self.target, int):
            t = self.target
        elif self.target is not None:
            if self.target not in labels:
                raise AsmError(f"line {self.line}: no label {self.target}")
            t = labels[self.target]
        imm = self.imm & ((1 << IMM_BITS) - 1)
        return ((self.op << 66) | (self.rd << 59) | (self.ra << 52) | (self.rb << 45)
                | (self.bimm << 44) | (self.cond << 40) | (t << 29) | imm)


class Asm:
    def __init__(self):
        self.equ = {}
        self.regs = {"_": 0}
        self.reg_init = {}
        self.next_reg, self.next_const = 1, NREGS - 1
        self.words = []
        self.labels = {}
        self.line = 0
        self.scopes = []
        self.all_labels = {}

    def err(self, msg):
        raise AsmError(f"line {self.line}: {msg}")

    def value(self, e):
        e = e.strip()
        if e.startswith("#"):
            e = e[1:]
        try:
            return int(eval(e, {"__builtins__": {}}, {**self.all_labels, **self.equ}))
        except Exception as x:
            self.err(f"bad expression {e!r} ({x})")

    def reg(self, s):
        s = s.strip()
        if s in self.regs:
            return self.regs[s]
        m = re.fullmatch(r"r(\d+)", s)
        if m and int(m.group(1)) < NREGS:
            return int(m.group(1))
        self.err(f"not a register: {s!r}")

    def is_reg(self, s):
        s = s.strip()
        return s in self.regs or re.fullmatch(r"r\d+", s) is not None

    def imm32(self, v):
        if not -(1 << (IMM_BITS - 1)) <= v < (1 << (IMM_BITS - 1)):
            self.err(f"immediate {v:#x} past {IMM_BITS} bits signed: use a .const")
        return v

    def operand_b(self, w, s):
        """rb, or #imm."""
        s = s.strip()
        if s.startswith("#"):
            w.bimm, w.imm = 1, self.imm32(self.value(s))
        else:
            w.rb = self.reg(s)

    SCALES = {1: 0, 4: 1, 8: 2, 16: 3}

    def mem(self, w, s, index=False):
        """[ra], [ra +- off]; a load also [ra + rb + off], [ra + rb*N + off]
        (N 1, 4, 8, 16: imm bits 28-27, the offset 27 bits)."""
        s = s.strip()
        if not (s.startswith("[") and s.endswith("]")):
            self.err(f"not a memory operand: {s!r}")
        terms = re.findall(r"([+-]?)\s*([^+-]+)", s[1:-1])
        if not terms or terms[0][0] or not self.is_reg(terms[0][1]):
            self.err(f"not a memory operand: {s!r}")
        w.ra = self.reg(terms[0][1])
        rest = terms[1:]
        scale = None
        if rest:
            sign, t = rest[0]
            m = re.fullmatch(r"([A-Za-z_]\w*)\s*(?:\*\s*(\d+))?", t.strip())
            if sign == "+" and m and self.is_reg(m.group(1)):
                if not index:
                    self.err(f"only a load is indexed: {s!r}")
                n = int(m.group(2) or 1)
                if n not in self.SCALES:
                    self.err(f"scale {n}: 1, 4, 8 or 16")
                w.rb, scale = self.reg(m.group(1)), self.SCALES[n]
                rest = rest[1:]
        off = self.value("".join(sg + t for sg, t in rest)) if rest else 0
        if scale is None and not index:
            w.imm = self.imm32(off)
        else:
            if not -(1 << 26) <= off < (1 << 26):
                self.err(f"offset {off:#x} past 27 bits")
            w.imm = (off & ((1 << 27) - 1)) | ((scale or 0) << 27)

    def emit(self, w):
        if len(self.words) >= ROM_WORDS:
            self.err("the ROM is full")
        self.words.append(w)

    def split(self, s):
        """Operands split at commas outside brackets."""
        out, depth, cur = [], 0, ""
        for ch in s:
            if ch == "[":
                depth += 1
            elif ch == "]":
                depth -= 1
            if ch == "," and depth == 0:
                out.append(cur.strip())
                cur = ""
            else:
                cur += ch
        if cur.strip():
            out.append(cur.strip())
        return out

    def op(self, src, mn, args, cond, target):
        mn = mn.upper()
        a = self.split(args)
        w = Word(src, self.line)

        def nargs(n):
            if len(a) != n:
                self.err(f"{mn.lower()}: {n} operands, not {len(a)}")

        def branch(c, tgt):
            if cond is not None:
                self.err(f"{mn.lower()} already branches")
            w.cond, w.target = CONDS[c], tgt

        if mn in ALU3:
            nargs(3)
            w.op, w.rd, w.ra = OPS[mn], self.reg(a[0]), self.reg(a[1])
            self.operand_b(w, a[2])
        elif mn in ("EXT", "EXTS"):
            nargs(4)
            w.op, w.rd, w.ra = OPS[mn], self.reg(a[0]), self.reg(a[1])
            lo, wd = self.value(a[2]), self.value(a[3])
            if not (0 <= lo < 64 and 1 <= wd <= 64 and lo + wd <= 64):
                self.err(f"bad field {lo}, {wd}")
            w.imm = lo | ((wd & 63) << 8)
        elif mn == "INS":
            nargs(5)
            w.op, w.rd, w.ra, w.rb = OPS[mn], self.reg(a[0]), self.reg(a[1]), self.reg(a[2])
            lo, wd = self.value(a[3]), self.value(a[4])
            if not (0 <= lo < 64 and 1 <= wd <= 64 and lo + wd <= 64):
                self.err(f"bad field {lo}, {wd}")
            w.imm = lo | ((wd & 63) << 8)
        elif mn == "MOVX":
            nargs(2)
            if a[1].upper() not in MOVX_SRC:
                self.err(f"movx: no source {a[1]}")
            w.op, w.rd, w.imm = OPS[mn], self.reg(a[0]), MOVX_SRC[a[1].upper()]
        elif mn in LOADS:
            nargs(2)
            w.op, w.rd = OPS[mn], self.reg(a[0])
            self.mem(w, a[1], index=True)
        elif mn in STORES:
            nargs(2)
            w.op, w.rb = OPS[mn], self.reg(a[1])
            self.mem(w, a[0])
        elif mn == "OUT":            # out #port, ra: a codec job's input
            nargs(2)
            w.op, w.imm, w.ra = OPS[mn], self.value(a[0]) & 63, self.reg(a[1])
        elif mn == "IN":             # in rd, #port: a codec unit's result
            nargs(2)
            w.op, w.rd, w.imm = OPS[mn], self.reg(a[0]), self.value(a[1]) & 63
        elif mn == "JOB":            # job #unit: run it (0 codec, 1 renderer, 2 PARSE)
            nargs(1)
            w.op, w.imm = OPS[mn], self.value(a[0]) & 3
        elif mn == "SETSP":
            nargs(1)
            w.op, w.ra = OPS[mn], self.reg(a[0])
        elif mn == "RES":
            nargs(1)
            w.op, w.ra = OPS[mn], self.reg(a[0])
        elif mn == "END":
            w.op = OPS[mn]
            if a:
                nargs(1)
                w.imm = self.value(a[0]) & 0xFF
        # the pseudo-ops
        elif mn == "NOP":
            nargs(0)
        elif mn == "MOV":
            nargs(2)
            w.op, w.rd, w.ra = OPS["OR"], self.reg(a[0]), self.reg(a[1])
        elif mn == "LI":
            nargs(2)
            w.op, w.rd, w.bimm = OPS["OR"], self.reg(a[0]), 1
            w.imm = self.imm32(self.value(a[1]))
        elif mn in ("JMP", "CALL"):
            nargs(1)
            branch(mn, a[0])
        elif mn == "RET":
            nargs(0)
            branch("RET", None)
        elif mn == "JTAB":           # jtab reg, table: to table + reg (bits 10-0)
            nargs(2)
            w.op, w.ra = OPS["OR"], self.reg(a[0])
            branch("JTAB", a[1])
        elif mn == "JR":             # jr reg: to the address in reg
            nargs(1)
            w.op, w.ra = OPS["OR"], self.reg(a[0])
            if cond is not None:
                self.err("jr already branches")
            w.cond, w.target = CONDS["JTAB"], 0
        elif mn == "BABT":
            nargs(1)
            branch("ABT", a[0])
        elif mn in ("BZ", "BNZ"):
            nargs(2)
            w.op, w.ra = OPS["OR"], self.reg(a[0])
            branch("Z" if mn == "BZ" else "NZ", a[1])
        elif mn in ("BEQ", "BNE", "BLTU", "BGEU", "BGTU", "BLEU", "BLT", "BGE", "BGT", "BLE"):
            nargs(3)
            x, y, tgt = a
            c = dict(BEQ="Z", BNE="NZ", BLTU="ULT", BGEU="UGE", BLT="LT", BGE="GE")
            w.op = OPS["SUB"]
            if mn in c:
                w.ra = self.reg(x)
                self.operand_b(w, y)
                branch(c[mn], tgt)
            else:
                # x > y: y < x; x <= y: y >= x (with an immediate: x >= y + 1, x < y + 1)
                if y.strip().startswith("#"):
                    w.ra, w.bimm = self.reg(x), 1
                    w.imm = self.imm32(self.value(y) + 1)
                    branch(dict(BGTU="UGE", BLEU="ULT", BGT="GE", BLE="LT")[mn], tgt)
                else:
                    w.ra, w.rb = self.reg(y), self.reg(x)
                    branch(dict(BGTU="ULT", BLEU="UGE", BGT="LT", BLE="GE")[mn], tgt)
        else:
            self.err(f"no op {mn.lower()}")
        if cond is not None:
            c = cond.upper()
            if c not in CONDS:
                self.err(f"no condition {cond}")
            w.cond = CONDS[c]
            if c == "RET":
                if target:
                    self.err("ret has no target")
            elif c != "NONE":
                if not target:
                    self.err(f"{cond}: a target")
                w.target = target
        self.emit(w)

    def line_in(self, raw):
        s = raw.split(";", 1)[0].rstrip()
        if not s.strip():
            return
        m = re.match(r"\s*([A-Za-z_]\w*):(.*)", s)
        if m:
            name = m.group(1)
            if name in self.labels:
                self.err(f"label {name} again")
            self.labels[name] = len(self.words)
            s = m.group(2)
            if not s.strip():
                return
        s = s.strip()
        if s.startswith("."):
            d, _, rest = s.partition(" ")
            d = d.lower()
            if d == ".equ":
                n, _, e = rest.partition("=")
                self.equ[n.strip()] = self.value(e)
            elif d == ".scope":
                self.scopes.append((self.next_reg, set(self.regs)))
            elif d == ".endscope":
                if not self.scopes:
                    self.err(".endscope without .scope")
                self.next_reg, names = self.scopes.pop()
                self.regs = {k: v for k, v in self.regs.items() if k in names}
            elif d == ".reg":
                for n in (x.strip() for x in rest.split(",")):
                    if n in self.regs:
                        self.err(f"register {n} again")
                    if self.next_reg > self.next_const:
                        self.err("out of registers")
                    self.regs[n] = self.next_reg
                    self.next_reg += 1
            elif d == ".const":
                if self.scopes:
                    self.err(".const in a scope")
                n, _, e = rest.partition("=")
                n = n.strip()
                if n in self.regs:
                    self.err(f"register {n} again")
                if self.next_reg > self.next_const:
                    self.err("out of registers")
                self.regs[n] = self.next_const
                self.reg_init[self.next_const] = self.value(e) & ((1 << 64) - 1)
                self.next_const -= 1
            else:
                self.err(f"no directive {d}")
            return
        cond = target = None
        if "|" in s:
            s, _, c = s.partition("|")
            c = c.split()
            cond = c[0]
            target = c[1] if len(c) > 1 else None
            if len(c) > 2:
                self.err("one target")
        mn, _, args = s.strip().partition(" ")
        self.op(s.strip(), mn, args, cond, target)

    def assemble(self, text):
        # first the labels (every op is one word), for expressions
        n = 0
        for raw in text.splitlines():
            s = raw.split(";", 1)[0].strip()
            m = re.match(r"([A-Za-z_]\w*):(.*)", s)
            if m:
                self.labels[m.group(1)] = n
                s = m.group(2).strip()
            if s and not s.startswith("."):
                n += 1
        first, self.labels = self.labels, {}
        self.all_labels = first
        for i, raw in enumerate(text.splitlines(), 1):
            self.line = i
            self.line_in(raw)
        assert self.labels == first
        if self.scopes:
            raise AsmError(".scope without .endscope")
        return [w.encode(self.labels) for w in self.words]


def package(asm, code, name):
    o = ["-- Made by tools/shite_uasm.py from %s: do not edit" % name,
         "library ieee;", "use ieee.std_logic_1164.all;", "use ieee.numeric_std.all;",
         "package shite_ucode_pkg is"]
    for k, v in OPS.items():
        o.append(f"  constant UOP_{k} : natural := {v};")
    for k, v in CONDS.items():
        o.append(f"  constant UC_{k} : natural := {v};")
    o.append(f"  constant UC_DATA_WORDS : natural := {DATA_WORDS};")
    o.append(f"  type uc_rom_t is array (0 to {ROM_WORDS - 1}) of std_logic_vector(71 downto 0);")
    o.append(f"  type uc_regs_t is array (0 to {NREGS - 1}) of unsigned(63 downto 0);")
    o.append("  type uc_data_t is array (0 to UC_DATA_WORDS - 1) of unsigned(63 downto 0);")
    o.append(f"  -- {len(code)} words")
    o.append("  constant UCODE : uc_rom_t := (")
    at = {v: k for k, v in asm.labels.items()}
    for i, (w, c) in enumerate(zip(asm.words, code)):
        lab = (at[i] + ": ") if i in at else ""
        o.append(f'    {i} => x"{c:018X}",  -- {lab}{w.src}')
    o.append("    others => (others => '0'));")
    o.append("  constant UC_REGS_INIT : uc_regs_t := (")
    names = {v: k for k, v in asm.regs.items()}
    for r, v in sorted(asm.reg_init.items()):
        o.append(f'    {r} => x"{v:016X}",  -- {names[r]}')
    o.append("    others => (others => '0'));")
    o.append("end package;")
    return "\n".join(o) + "\n"


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))     # src/vhdl
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", nargs="?", default=os.path.join(here, "shite_ucode.asm"))
    ap.add_argument("-o", "--out", default="shite_ucode_pkg.vhdl")
    ap.add_argument("--list", help="a listing: address, word, source")
    ap.add_argument("--check", nargs="?", const=os.path.join(here, "shite_ucode_pkg.vhdl"),
                    help="fail unless this package (default: the committed one) is current")
    args = ap.parse_args()
    asm = Asm()
    try:
        code = asm.assemble(open(args.source).read())
    except AsmError as e:
        sys.exit(f"{args.source}: {e}")
    pkg = package(asm, code, os.path.basename(args.source))
    if args.check:
        if not os.path.exists(args.check) or open(args.check).read() != pkg:
            sys.exit(f"{args.check} is not what {os.path.basename(args.source)} assembles to: "
                     f"run tools/shite_uasm.py in src/vhdl")
    committed = os.path.join(here, "shite_ucode_pkg.vhdl")
    if (not args.check and os.path.abspath(args.out) != committed
            and (not os.path.exists(committed) or open(committed).read() != pkg)):
        # (the test runner's build: the package Vivado reads must be this one)
        sys.exit(f"{committed} is not what {os.path.basename(args.source)} assembles to: "
                 f"run tools/shite_uasm.py in src/vhdl")
    open(args.out, "w").write(pkg)
    if args.list:
        at = {v: k for k, v in asm.labels.items()}
        with open(args.list, "w") as f:
            for i, (w, c) in enumerate(zip(asm.words, code)):
                if i in at:
                    f.write(f"{at[i]}:\n")
                f.write(f"{i:4d}  {c:018X}  {w.src}\n")
    print(f"{len(code)} words, {asm.next_reg - 1} registers, {NREGS - 1 - asm.next_const} constants",
          file=sys.stderr)


if __name__ == "__main__":
    main()
