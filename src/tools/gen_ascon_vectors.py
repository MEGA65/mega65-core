#!/usr/bin/env python3
"""Operation scripts for tb_ascon_aead128 (#965), from netsd_crypto (whose
C and Python Ascon-AEAD128 test_netsd.py checks against pyascon).

    gen_ascon_vectors.py OUT [CASES]

Each case encrypts and then decrypts one message, block by block, as the
hardware will (header-sized AD, sector-sized and odd-sized payloads, empty
AD, empty payload).  Lines:

    I key nonce     A len blk     S     E len blk expect     D len blk expect
    F tag

Blocks are 16 bytes as a little-endian 128-bit number in hex.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import netsd_crypto as nc  # noqa: E402


def h(b):
    return "%032x" % int.from_bytes(b.ljust(16, b"\0"), "little")


def blocks(data):
    """16-byte blocks, ending with a short (maybe empty) one, as Ascon pads"""
    out = [data[i:i + 16] for i in range(0, len(data) - len(data) % 16, 16)]
    out.append(data[len(data) - len(data) % 16:])
    return out


def case(rnd, adlen, ptlen, lines):
    k, n = rnd.randbytes(16), rnd.randbytes(16)
    ad, pt = rnd.randbytes(adlen), rnd.randbytes(ptlen)
    ct = nc.encrypt(k, n, ad, pt)
    body, tag = ct[:-16], ct[-16:]
    for direction in "ED":
        lines.append("I %s %s" % (h(k), h(n)))
        if ad:
            for b in blocks(ad):
                lines.append("A %d %s" % (len(b), h(b)))
        lines.append("S")
        off = 0
        for b in blocks(pt):
            c = body[off:off + len(b)]
            if direction == "E":
                lines.append("E %d %s %s" % (len(b), h(b), h(c)))
            else:
                lines.append("D %d %s %s" % (len(c), h(c), h(b)))
            off += len(b)
        lines.append("F %s" % h(tag))


def main():
    out = sys.argv[1]
    cases = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    rnd = random.Random(965)
    lines = []
    shapes = [(0, 0), (16, 0), (16, 512), (32, 0), (16, 16), (1, 1), (15, 17), (17, 31), (0, 33)]
    for adlen, ptlen in shapes:
        case(rnd, adlen, ptlen, lines)
    for _ in range(cases):
        case(rnd, rnd.randrange(0, 40), rnd.choice([0, 1, 15, 16, 17, 100, 512]), lines)
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
