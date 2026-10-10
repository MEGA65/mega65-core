#!/usr/bin/env python3
"""Check exact modulo semantics of ssnail_optimized.vhdl address refactors.
Algorithmic arithmetic comparison only; not a replacement for RTL simulation.
"""
import random

rng = random.Random(0x55AA65)
M28 = (1 << 28) - 1
M32 = (1 << 32) - 1

def test_meanrows():
    for _ in range(10000):
        bx = rng.getrandbits(28)
        n0 = rng.getrandbits(32)
        rows = rng.randrange(1, 200)
        ptr = bx
        for r in range(1, rows):
            ptr = (ptr + ((n0 & ((1<<26)-1)) << 2)) & M28
            old = (bx + ((r & ((1<<26)-1)) * ((n0 & ((1<<26)-1)) << 2))) & M28
            assert ptr == old

def test_attn():
    for _ in range(10000):
        ea_y = rng.getrandbits(28)
        hd = rng.randrange(1, 257)  # checked by A_RS0
        head = 65535 if _ == 0 else rng.randrange(0, 256)
        current = (ea_y + head * hd * 4) & M28
        ptr = ea_y
        for _unused in range(head):
            ptr = (ptr + hd*4) & M28
        assert ptr == current
        kvh = rng.randrange(0, 65536)
        rowaddr = rng.getrandbits(28)
        for scale in (2, 4):
            # Repeated group advances add the head stride one time.
            kv_offset = (kvh * (hd * scale)) & M28
            old = (rowaddr + (kvh * hd * scale)) & M28
            assert (rowaddr + kv_offset) & M28 == old

def test_gemv():
    for _ in range(100000):
        rows = rng.getrandbits(32)
        nb = rng.getrandbits(8)
        nbytes = rng.choice((18, 34))
        # Old VHDL:
        old_p32 = (rows * nb) & M32
        old_p28 = ((rows & ((1 << 20) - 1)) * nb * nbytes) & M28
        # New serial multiplier:
        a32 = rows
        a28 = (rows & ((1 << 20) - 1)) * nbytes & M28
        b = nb
        p32 = p28 = 0
        while True:
            if b & 1:
                p32 = (p32 + a32) & M32
                p28 = (p28 + a28) & M28
            a32 = (a32 << 1) & M32
            a28 = (a28 << 1) & M28
            b >>= 1
            if b == 0:
                break
        assert (p32, p28) == (old_p32, old_p28)

test_meanrows()
test_attn()
test_gemv()
print('PASS: 10,000 MEANROWS cases, 10,000 ATTN cases, 100,000 GEMV cases')
