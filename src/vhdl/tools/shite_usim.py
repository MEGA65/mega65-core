#!/usr/bin/env python3
"""SHITE's microcode engine (shite_useq.vhdl) as a Python model, op for op:
for running shite_ucode.asm against the reference model (SSNAIL/shite.py)
without a simulator, and for tracing it.  Cycle counts are not modelled.

    sim = USim()                        # assembles src/vhdl/shite_ucode.asm
    err, wr, result = sim.run(op, a, b, c, d, z, x, mem)

mem: read(addr, n) -> bytes and write(addr, data) (the 28-bit local address
space SHITE sees: the caller maps it).  The registers and the data RAM
persist from run to run, as the engine's do.  sim.trace = True prints each
op; sim.ops counts them."""
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _here)
import shite_uasm as UA

M64 = (1 << 64) - 1
O = UA.OPS
C = UA.CONDS


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


class UError(Exception):
    pass


class USim:
    def __init__(self, source=None, asm=None):
        if asm is None:
            asm = UA.Asm()
            asm.assemble(open(source or os.path.join(os.path.dirname(_here), "shite_ucode.asm")).read())
        self.asm = asm
        self.words = asm.words
        self.labels = asm.labels
        self.at = {v: k for k, v in asm.labels.items()}
        self.rf = [0] * UA.NREGS
        for r, v in asm.reg_init.items():
            self.rf[r] = v
        self.dm = [0] * UA.DATA_WORDS
        for a, v in asm.data.items():
            self.dm[a] = v
        self.trace = False
        self.ops = 0
        self.dvh = 0
        self.mulhi = self.divqh = self.divr = self.sqrh = 0
        self.x_out = {}                 # OUT ports (the codec jobs): not modelled
        self.max_ops = 50_000_000
        self.profile = None             # {label: ops} when a dict
        self.memops = 0

    def where(self, pc):
        """label+offset of a ROM address."""
        best = max((a for a in self.at if a <= pc), default=None)
        return f"{self.at[best]}+{pc - best}" if best is not None else str(pc)

    def run(self, op, a, b, c, d, z, x, mem, abort=False):
        rf, dm = self.rf, self.dm
        src = {0: op, 1: a, 2: b, 3: c, 4: d, 5: z, 6: x & 0xFFFFFFF}
        pc, sp, stk = 0, 0, [0] * 16
        result, wr = 0, False
        n = 0
        while True:
            w = self.words[pc]
            n += 1
            if self.profile is not None:
                lab = self.where(pc).split("+")[0]
                self.profile[lab] = self.profile.get(lab, 0) + 1
            if n > self.max_ops:
                raise UError(f"no END after {n} ops, at {self.where(pc)}")
            o, rd = w.op, w.rd
            va, vb = rf[w.ra], rf[w.rb]
            imm = sx(w.imm, UA.IMM_BITS)
            bv = imm & M64 if w.bimm else vb
            res = 0
            carry = ovf = False
            tgt = w.target if isinstance(w.target, int) else (self.labels[w.target] if w.target else 0)
            if o in (O["ADD"], O["SUB"]):
                bb = bv if o == O["ADD"] else (~bv) & M64
                s = va + bb + (1 if o == O["SUB"] else 0)
                carry = s >> 64 == 1
                res = s & M64
                ovf = (va >> 63 == bb >> 63) and (res >> 63 != va >> 63)
            elif o == O["AND"]:
                res = va & bv
            elif o == O["OR"]:
                res = va | bv
            elif o == O["XOR"]:
                res = va ^ bv
            elif o == O["ANDN"]:
                res = va & ~bv & M64
            elif o == O["SHL"]:
                res = (va << (bv & 63)) & M64
            elif o == O["SHR"]:
                res = va >> (bv & 63)
            elif o == O["SAR"]:
                res = (sx(va, 64) >> (bv & 63)) & M64
            elif o in (O["EXT"], O["EXTS"], O["INS"]):
                lo, wd = imm & 63, (imm >> 8) & 63
                wd = wd or 64
                m = (1 << wd) - 1
                if o == O["EXT"]:
                    res = (va >> lo) & m
                elif o == O["EXTS"]:
                    res = sx((va >> lo) & m, wd) & M64
                else:
                    mm = (m << lo) & M64
                    res = (vb & ~mm & M64) | ((va << lo) & mm)
            elif o == O["HI"]:
                res = ((bv & 0xFFFFFFFF) << 32) | (va & 0xFFFFFFFF)
            elif o == O["CLZ"]:
                res = 64 - va.bit_length()
            elif o == O["MOVX"]:
                s = imm & 15
                res = {7: sp, 8: self.mulhi, 9: self.divqh, 10: self.divr, 11: self.sqrh}.get(s, src.get(s, 0)) & M64
            elif o == O["MUL"]:
                p = va * vb
                res, self.mulhi = p & M64, p >> 64
            elif o == O["DIV"]:
                if vb == 0:
                    raise UError(f"divide by zero at {self.where(pc)}")
                nn = (self.dvh << 64) | va
                q, r = divmod(nn, vb)
                q &= (1 << 128) - 1
                res, self.divqh, self.divr = q & M64, q >> 64, r & M64
            elif o == O["SQRT"]:
                nn = (self.dvh << 64) | va
                rem, root = 0, 0
                for _ in range(64):                 # (as the engine: the remainder's top bits dropped)
                    t = ((rem & M64) << 2) | (nn >> 126)
                    nn = (nn << 2) & ((1 << 128) - 1)
                    q = (root << 2) | 1
                    if t >= q:
                        rem, root = t - q, ((root << 1) | 1) & M64
                    else:
                        rem, root = t, (root << 1) & M64
                res, self.divr, self.sqrh = root, rem & M64, rem >> 64
            elif o in (O["LDB"], O["LDH"], O["LDL"], O["LDQ"], O["LDD"]):
                sc = (imm >> 26) & 3
                off = sx(imm, 26)
                ad = (va + ((vb << (0, 2, 3, 4)[sc]) & 0xFFFFFFF) + off) & 0xFFFFFFF
                if o == O["LDD"]:
                    res = dm[ad & (UA.DATA_WORDS - 1)]
                else:
                    self.memops += 1
                    g = int.from_bytes(mem.read(ad & ~7, 8), "little")
                    sh = g >> ((ad & 7) * 8)
                    res = sh & {O["LDB"]: 0xFF, O["LDH"]: 0xFFFF, O["LDL"]: 0xFFFFFFFF, O["LDQ"]: M64}[o]
            elif o in (O["STB"], O["STH"], O["STL"], O["STQ"]):
                ad = (va + imm) & 0xFFFFFFF
                nb = {O["STB"]: 1, O["STH"]: 2, O["STL"]: 4, O["STQ"]: 8}[o]
                k = ad & 7
                if k + nb > 8:
                    nb = 8 - k                  # (the hardware truncates at the group)
                mem.write(ad, (vb & ((1 << (8 * nb)) - 1)).to_bytes(nb, "little"))
            elif o == O["STD"]:
                ad = (va + imm) & 0xFFFFFFF
                dm[ad & (UA.DATA_WORDS - 1)] = vb
            elif o == O["RES"]:
                result, wr = va & 0xFFFFFFFF, True
            elif o == O["END"]:
                self.ops += n
                return imm & 0xFF, wr, result
            elif o == O["SETSP"]:
                sp = va & 15
            elif o == O["OUT"]:
                if imm & 63 == 32:
                    self.dvh = va
                else:
                    self.x_out[imm & 63] = va
            elif o in (O["IN"], O["JOB"]):
                raise UError(f"codec units not modelled ({self.where(pc)})")
            if self.trace:
                print(f"  {pc:4d} {self.where(pc):18s} {w.src:40s} -> {res:#x}", file=sys.stderr)
            if rd:
                rf[rd] = res & M64
            cond = w.cond
            z_ = res == 0
            nf = (res >> 63) == 1
            take = {C["JMP"]: True, C["CALL"]: True, C["Z"]: z_, C["NZ"]: not z_, C["UGE"]: carry,
                    C["ULT"]: not carry, C["LT"]: nf != ovf, C["GE"]: nf == ovf, C["MI"]: nf, C["PL"]: not nf,
                    C["ABT"]: abort, C["NABT"]: not abort}.get(cond, False)
            if cond == C["CALL"]:
                stk[sp] = pc + 1
                sp = (sp + 1) & 15
                pc = tgt
            elif cond == C["RET"]:
                sp = (sp - 1) & 15
                pc = stk[sp]
            elif cond == C["JTAB"]:
                pc = (tgt + res) & 0xFFF
            elif take:
                pc = tgt
            else:
                pc += 1
