"""Test vectors for the pipelined F32 adder and multiplier (ssnail_fpipe):
random bit patterns, cancellation, subnormal results, overflow and
rounding ties, in fpu_vectors.txt's format (op 0 add, 1 multiply);
expected results from numpy float32."""
import numpy as np

rng = np.random.default_rng(777)
F32 = np.float32
N = 20000


def u(v):
    return np.asarray(v, dtype=F32).view(np.uint32).astype(np.int64)


def rbits(n):
    return rng.integers(0, 2 ** 32, n, dtype=np.uint64).astype(np.uint32).view(F32)


cases = []
with np.errstate(all="ignore"):
    def both(a, b):
        a = np.asarray(a, dtype=F32)
        b = np.asarray(b, dtype=F32)
        cases.append((0, a, b, a + b))
        cases.append((1, a, b, a * b))

    both(rbits(N), rbits(N))
    e = rng.integers(-149, 128, N)
    a = (rng.standard_normal(N) * 2.0 ** e).astype(F32)
    both(a, (-a * (1 + rng.integers(-4, 5, N) * 2.0 ** -23)).astype(F32))   # cancellation
    both(a, (rng.standard_normal(N) * 2.0 ** (e + rng.integers(-30, 31, N))).astype(F32))
    # products near and in the subnormal range, and near overflow
    both((rng.standard_normal(N) * 2.0 ** rng.integers(-149, -40, N)).astype(F32),
         (rng.standard_normal(N) * 2.0 ** rng.integers(-60, 20, N)).astype(F32))
    both((rng.standard_normal(N) * 2.0 ** rng.integers(40, 128, N)).astype(F32),
         (rng.standard_normal(N) * 2.0 ** rng.integers(0, 90, N)).astype(F32))
    # subnormal operands
    sub = rng.integers(1, 2 ** 23, N, dtype=np.uint64).astype(np.uint32).view(F32)
    both(sub, rbits(N))
    both(sub, rng.integers(1, 2 ** 23, N, dtype=np.uint64).astype(np.uint32).view(F32))
    # additions that tie: x + half an ulp of x (and a little more or less)
    x = (rng.standard_normal(N) * 2.0 ** rng.integers(-120, 120, N)).astype(F32)
    h = (np.spacing(x) / 2).astype(F32)
    cases.append((0, x, h, x + h))
    cases.append((0, x, (h * F32(1.5)).astype(F32), x + (h * F32(1.5)).astype(F32)))

with open("fpipe_vectors.txt", "w") as f:
    for op, a, b, r in cases:
        for p, q, s in zip(u(a), u(b), u(r)):
            f.write(f"{op} {p:08X} {q:08X} {s:08X}\n")
print(f"wrote fpipe_vectors.txt ({sum(len(c[1]) for c in cases)} vectors)")
