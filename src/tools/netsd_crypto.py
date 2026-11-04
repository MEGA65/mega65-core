#!/usr/bin/env python3
"""Ascon-AEAD128 (NIST SP 800-232) for netsd.py (MEGA65/mega65-core#965).

    ct_and_tag = encrypt(key, nonce, ad, pt)
    pt = decrypt(key, nonce, ad, ct_and_tag)     # None if the tag is wrong

Uses netsd_ascon.c, compiled on first use into ~/.cache/netsd (needs a C
compiler), and falls back to the pure-Python version below (correct, but
only ~100 KB/s).  BACKEND says which is in use.
"""

import ctypes
import hashlib
import os
import subprocess
import sys

M64 = (1 << 64) - 1
IV = bytes([0x01, 0x00, 0x8C, 0x80, 0x00, 0x10, 0x00, 0x00])


# ---- pure Python -------------------------------------------------------------

def _ror(x, n):
    return ((x >> n) | (x << (64 - n))) & M64


def _permute(s, rounds):
    for r in range(12 - rounds, 12):
        x0, x1, x2, x3, x4 = s
        x2 ^= 0xF0 - r * 0x0F
        x0 ^= x4
        x4 ^= x3
        x2 ^= x1
        t0 = ~x0 & x1
        t1 = ~x1 & x2
        t2 = ~x2 & x3
        t3 = ~x3 & x4
        t4 = ~x4 & x0
        x0 ^= t1
        x1 ^= t2
        x2 ^= t3
        x3 ^= t4
        x4 ^= t0
        x1 ^= x0
        x0 ^= x4
        x3 ^= x2
        x2 = ~x2 & M64
        x0 &= M64
        x1 &= M64
        x3 &= M64
        x4 &= M64
        s[0] = x0 ^ _ror(x0, 19) ^ _ror(x0, 28)
        s[1] = x1 ^ _ror(x1, 61) ^ _ror(x1, 39)
        s[2] = x2 ^ _ror(x2, 1) ^ _ror(x2, 6)
        s[3] = x3 ^ _ror(x3, 10) ^ _ror(x3, 17)
        s[4] = x4 ^ _ror(x4, 7) ^ _ror(x4, 41)


def _le(b):
    return int.from_bytes(b, "little")


def _start(key, nonce, ad):
    k0, k1 = _le(key[:8]), _le(key[8:])
    s = [_le(IV), k0, k1, _le(nonce[:8]), _le(nonce[8:])]
    _permute(s, 12)
    s[3] ^= k0
    s[4] ^= k1
    if ad:
        padded = ad + b"\x01" + bytes(15 - len(ad) % 16)
        for i in range(0, len(padded), 16):
            s[0] ^= _le(padded[i:i + 8])
            s[1] ^= _le(padded[i + 8:i + 16])
            _permute(s, 8)
    s[4] ^= 1 << 63
    return s


def _finish(s, key):
    k0, k1 = _le(key[:8]), _le(key[8:])
    s[2] ^= k0
    s[3] ^= k1
    _permute(s, 12)
    return ((s[3] ^ k0).to_bytes(8, "little") + (s[4] ^ k1).to_bytes(8, "little"))


def py_encrypt(key, nonce, ad, pt):
    s = _start(key, nonce, ad)
    out = bytearray()
    padded = pt + b"\x01" + bytes(15 - len(pt) % 16)
    for i in range(0, len(padded), 16):
        s[0] ^= _le(padded[i:i + 8])
        s[1] ^= _le(padded[i + 8:i + 16])
        out += s[0].to_bytes(8, "little") + s[1].to_bytes(8, "little")
        if i + 16 < len(padded):
            _permute(s, 8)
    return bytes(out[:len(pt)]) + _finish(s, key)


def py_decrypt(key, nonce, ad, ct):
    if len(ct) < 16:
        return None
    ct, tag = ct[:-16], ct[-16:]
    s = _start(key, nonce, ad)
    out = bytearray()
    full = len(ct) - len(ct) % 16
    for i in range(0, full, 16):
        c0, c1 = _le(ct[i:i + 8]), _le(ct[i + 8:i + 16])
        out += (s[0] ^ c0).to_bytes(8, "little") + (s[1] ^ c1).to_bytes(8, "little")
        s[0], s[1] = c0, c1
        _permute(s, 8)
    ks = bytearray(s[0].to_bytes(8, "little") + s[1].to_bytes(8, "little"))
    rest = ct[full:]
    out += bytes(a ^ b for a, b in zip(ks, rest))
    ks[:len(rest)] = rest
    ks[len(rest)] ^= 0x01
    s[0], s[1] = _le(ks[:8]), _le(ks[8:])
    want = _finish(s, key)
    diff = 0
    for a, b in zip(want, tag):
        diff |= a ^ b
    return None if diff else bytes(out)


# ---- the C version -----------------------------------------------------------

def _load_c():
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "netsd_ascon.c")
    try:
        with open(src, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()[:16]
        cache = os.path.join(os.path.expanduser("~"), ".cache", "netsd")
        so = os.path.join(cache, "netsd_ascon-%s.so" % digest)
        if not os.path.exists(so):
            os.makedirs(cache, exist_ok=True)
            tmp = so + ".%d" % os.getpid()
            subprocess.run([os.environ.get("CC", "cc"), "-O2", "-shared", "-fPIC", "-o", tmp, src],
                           check=True, capture_output=True)
            os.replace(tmp, so)
        lib = ctypes.CDLL(so)
    except (OSError, subprocess.CalledProcessError) as ex:
        print("netsd_crypto: using pure Python Ascon (%s)" % ex, file=sys.stderr)
        return None
    p, n = ctypes.c_char_p, ctypes.c_size_t
    lib.netsd_ascon_encrypt.argtypes = [p, p, p, n, p, n, ctypes.c_void_p]
    lib.netsd_ascon_encrypt.restype = None
    lib.netsd_ascon_decrypt.argtypes = [p, p, p, n, p, n, ctypes.c_void_p]
    lib.netsd_ascon_decrypt.restype = ctypes.c_int
    return lib


_lib = None if os.environ.get("NETSD_PURE_PYTHON") else _load_c()
BACKEND = "C" if _lib else "Python"


def encrypt(key, nonce, ad, pt):
    assert len(key) == 16 and len(nonce) == 16
    if _lib is None:
        return py_encrypt(bytes(key), bytes(nonce), bytes(ad), bytes(pt))
    out = ctypes.create_string_buffer(len(pt) + 16)
    _lib.netsd_ascon_encrypt(bytes(key), bytes(nonce), bytes(ad), len(ad), bytes(pt), len(pt), out)
    return out.raw


def decrypt(key, nonce, ad, ct):
    assert len(key) == 16 and len(nonce) == 16
    if _lib is None:
        return py_decrypt(bytes(key), bytes(nonce), bytes(ad), bytes(ct))
    if len(ct) < 16:
        return None
    out = ctypes.create_string_buffer(max(1, len(ct) - 16))
    if _lib.netsd_ascon_decrypt(bytes(key), bytes(nonce), bytes(ad), len(ad), bytes(ct), len(ct), out):
        return None
    return out.raw[:len(ct) - 16]
