"""Test vectors for ssnail_fpu: random bit patterns, random values with close
exponents (cancellation), and edge cases; expected results from numpy, the
same arithmetic the emulator's hardware-numerics mode uses."""
import numpy as np

rng = np.random.default_rng(1234)
F32 = np.float32
lines = []


def f32b(v):
    return int(np.asarray(v, dtype=F32).view(np.uint32))


def add(op, a, b, exp):
    lines.append(f"{op} {a & 0xFFFFFFFF:08X} {b & 0xFFFFFFFF:08X} {exp & 0xFFFFFFFF:08X}")


edges = [0x00000000, 0x80000000, 0x00000001, 0x80000001, 0x007FFFFF, 0x00800000,
         0x7F7FFFFF, 0xFF7FFFFF, 0x7F800000, 0xFF800000, 0x7FC00000, 0x3F800000,
         0xBF800000, 0x33800000, 0x34000000, 0x3F800001, 0x4B000000, 0x00400000,
         0x0D000000, 0x72000000]
rand_bits = list(rng.integers(0, 2 ** 32, 3000, dtype=np.uint64).astype(int))


def close_pairs(n):
    out = []
    for _ in range(n):
        e = rng.integers(-30, 30)
        a = F32(rng.standard_normal() * 2.0 ** e)
        b = F32(-a * (1 + rng.integers(-3, 4) * 2.0 ** -23)) if rng.random() < 0.5 \
            else F32(rng.standard_normal() * 2.0 ** (e + rng.integers(-26, 27)))
        out.append((f32b(a), f32b(b)))
    return out


with np.errstate(all="ignore"):
    pairs = [(a, b) for a in edges for b in edges]
    pairs += list(zip(rand_bits[:1500], rand_bits[1500:3000]))
    pairs += close_pairs(1500)
    # ties: 1 + 2^-24 (exact half ulp), and neighbours
    pairs += [(0x3F800000, 0x33800000), (0x3F800001, 0x33800000), (0x3F800000, 0xB3800000)]
    for a, b in pairs:
        fa = np.array([a], dtype=np.uint32).view(F32)[0]
        fb = np.array([b], dtype=np.uint32).view(F32)[0]
        add(0, a, b, f32b(fa + fb))
        add(1, a, b, f32b(fa * fb))
    # small-magnitude products (subnormal results)
    for _ in range(500):
        fa = F32(rng.standard_normal() * 2.0 ** rng.integers(-80, -40))
        fb = F32(rng.standard_normal() * 2.0 ** rng.integers(-80, -40))
        add(1, f32b(fa), f32b(fb), f32b(fa * fb))
    # F16 -> F32: every F16 value
    for h in range(65536):
        v = np.array([h], dtype=np.uint16).view(np.float16)[0]
        add(2, h, 0, f32b(F32(v)))
    # F32 -> F16
    vals = edges + rand_bits[:2000]
    vals += [f32b(F32(rng.standard_normal() * 2.0 ** rng.integers(-30, 20))) for _ in range(3000)]
    vals += [f32b(F32(np.float16(h).item())) + d for h in range(0, 30000, 37) for d in (-1, 1)]
    for a in vals:
        fa = np.array([a & 0xFFFFFFFF], dtype=np.uint32).view(F32)[0]
        add(3, a, 0, int(np.asarray(fa.astype(np.float16)).view(np.uint16)))
    # BF16 -> F32
    for h in list(range(0, 65536, 97)) + [0x7FC0, 0xFF80, 0x0001]:
        add(4, h, 0, h << 16)
    # int32 -> F32
    ints = [0, 1, -1, 127, -128, 2 ** 24, 2 ** 24 + 1, 2 ** 24 + 3, -(2 ** 31), 2 ** 31 - 1]
    ints += list(rng.integers(-2 ** 31, 2 ** 31, 2000))
    ints += list(rng.integers(-600000, 600000, 1000))
    for i in ints:
        add(5, int(i) & 0xFFFFFFFF, 0, f32b(F32(int(i))))

open("fpu_vectors.txt", "w").write("\n".join(lines) + "\n")
print(f"{len(lines)} vectors")
