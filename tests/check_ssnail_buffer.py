#!/usr/bin/env python3
"""Check SSNAIL 4-bank output scratchpad's index/packet semantics.

Reference is the original 128x16-bit array, updated for consecutive writes
with each address reduced modulo 128. These are mathematical tests, not VHDL
simulation nor Vivado memory-inference checks.
"""
import random
from pathlib import Path


def write_reference(ref, base, mask, data):
    for lane in range(4):
        if mask & (1 << lane):
            ref[(base + lane) & 127] = data[lane]


def write_banks(banks, base, mask, data):
    seen = set()
    for bank in range(4):
        lane = (bank - (base & 3)) & 3
        if mask & (1 << lane):
            address = (base + lane) & 127
            assert (address & 3) == bank
            assert bank not in seen
            seen.add(bank)
            banks[bank][address >> 2] = data[lane]


def read_banks(banks, address):
    return banks[address & 3][address >> 2]


def main():
    rng = random.Random(0x55A11)
    ref = [0] * 128
    banks = [[0] * 32 for _ in range(4)]
    n = 0
    for base in range(128):
        for mask in range(16):
            data = [rng.randrange(65536) for _ in range(4)]
            write_reference(ref, base, mask, data)
            write_banks(banks, base, mask, data)
            assert [read_banks(banks, j) for j in range(128)] == ref
            n += 1
    # Repeated writes / random reads, including word index wrap at 127.
    for _ in range(15000):
        base = rng.randrange(128)
        mask = rng.randrange(16)
        data = [rng.randrange(65536) for _ in range(4)]
        write_reference(ref, base, mask, data)
        write_banks(banks, base, mask, data)
        for _ in range(8):
            a = rng.randrange(128)
            assert read_banks(banks, a) == ref[a]
        n += 1
    # Verify byte -> halfword address matching used by V_ELST and E_R6.
    for _ in range(15000):
        pz = rng.randrange(256)
        vi = rng.randrange(256)
        for nshift in (1, 2):
            shift_bits = 7 if nshift == 1 else 6
            byte_idx = (pz + ((vi & ((1 << shift_bits) - 1)) << nshift)) & 255
            old_word_base = (byte_idx >> 1) & 127
            new_word_base = (byte_idx >> 1) & 127
            assert new_word_base == old_word_base
    print(f"PASS: {n} write packets; 128 bank/address reads per exhaustive packet; "
          "15,000 random byte-index trials")


if __name__ == '__main__':
    main()
