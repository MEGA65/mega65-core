#!/usr/bin/env python3
"""Operation scripts for tb_ascon_aead128 (#965), from netsd_crypto (whose
C and Python Ascon-AEAD128 test_netsd.py checks against pyascon).

    gen_ascon_vectors.py OUT [CASES]

Each case encrypts and then decrypts one message, byte by byte, as the
hardware will (header-sized AD, sector-sized and odd-sized payloads, empty
AD, empty payload).  Lines (bytes as hex strings, "-" for none):

    I key nonce        (16 bytes each)
    A ad               then ad_end
    E plaintext ciphertext
    D ciphertext plaintext
    T tag              final, then check every tag byte
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import netsd_crypto as nc  # noqa: E402


def h(b):
    return b.hex() if b else "-"


def case(rnd, adlen, ptlen, lines):
    k, n = rnd.randbytes(16), rnd.randbytes(16)
    ad, pt = rnd.randbytes(adlen), rnd.randbytes(ptlen)
    ct = nc.encrypt(k, n, ad, pt)
    body, tag = ct[:-16], ct[-16:]
    for direction in "ED":
        lines.append("I %s %s" % (h(k), h(n)))
        lines.append("A %s" % h(ad))
        if direction == "E":
            lines.append("E %s %s" % (h(pt), h(body)))
        else:
            lines.append("D %s %s" % (h(body), h(pt)))
        lines.append("T %s" % h(tag))


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
