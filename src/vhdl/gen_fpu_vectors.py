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

    # division: same operand pairs, plus tiny/huge and exact cases
    divs = pairs[:4000] + [(f32b(F32(rng.standard_normal() * 2.0 ** rng.integers(-140, 128))),
                            f32b(F32(rng.standard_normal() * 2.0 ** rng.integers(-140, 128))))
                           for _ in range(1500)]
    divs += [(f32b(F32(v)), 0x42FE0000) for v in rng.standard_normal(300) * 50]   # x / 127
    divs += [(0x3F800000, f32b(F32(v))) for v in rng.standard_normal(300)]        # 1 / x
    for a, b in divs:
        fa = np.array([a], dtype=np.uint32).view(F32)[0]
        fb = np.array([b], dtype=np.uint32).view(F32)[0]
        add(6, a, b, f32b(fa / fb))
    # roundf, exactly as gguf-py / llama.cpp (half away from zero), saturating
    def roundf_ref(v):
        if np.isnan(v):
            return 0
        if np.isinf(v):
            return 2 ** 31 - 1 if v > 0 else -2 ** 31
        a_ = abs(float(v))
        r = int(np.floor(a_)) + (1 if a_ - np.floor(a_) >= 0.5 else 0)
        r = -r if v < 0 else r
        return max(-2 ** 31, min(2 ** 31 - 1, r))
    rvals = [f32b(F32(v)) for v in rng.standard_normal(2000) * 100]
    rvals += [f32b(F32(k + 0.5)) for k in range(-130, 130)]                 # exact halves
    rvals += [f32b(np.nextafter(F32(k + 0.5), F32(k))) for k in range(-130, 130)]
    rvals += [f32b(np.nextafter(F32(k + 0.5), F32(k + 1))) for k in range(-130, 130)]
    rvals += edges + rand_bits[:1000]
    for a in rvals:
        fa = np.array([a & 0xFFFFFFFF], dtype=np.uint32).view(F32)[0]
        add(7, a, 0, roundf_ref(fa) & 0xFFFFFFFF)

    # square root: random bits (negatives, NaN, inf included), every scale,
    # exact squares, subnormals
    svals = rand_bits[:2000] + edges
    svals += [f32b(F32(abs(rng.standard_normal()) * 2.0 ** rng.integers(-149, 128))) for _ in range(2000)]
    svals += [f32b(F32(k * k)) for k in range(0, 3000, 7)]
    svals += [f32b(np.nextafter(F32(k * k), F32(1e9))) for k in range(1, 300)]
    svals += list(range(1, 2000, 13)) + [0x007FFFFF, 0x00000001]
    for a in svals:
        fa = np.array([a & 0xFFFFFFFF], dtype=np.uint32).view(F32)[0]
        add(8, a, 0, f32b(np.sqrt(fa)))
    # truncate toward zero, saturating (table segment index)
    def trunc_ref(v):
        if np.isnan(v):
            return 0
        if np.isinf(v):
            return 2 ** 31 - 1 if v > 0 else -2 ** 31
        r = int(np.trunc(float(v)))
        return max(-2 ** 31, min(2 ** 31 - 1, r))
    tvals = [f32b(F32(v)) for v in rng.standard_normal(2000) * 300]
    tvals += [f32b(F32(k)) for k in range(-300, 300)]
    tvals += [f32b(np.nextafter(F32(k), F32(0))) for k in range(-300, 300) if k]
    tvals += edges + rand_bits[:800]
    for a in tvals:
        fa = np.array([a & 0xFFFFFFFF], dtype=np.uint32).view(F32)[0]
        add(9, a, 0, trunc_ref(fa) & 0xFFFFFFFF)

open("fpu_vectors.txt", "w").write("\n".join(lines) + "\n")
print(f"{len(lines)} vectors")
