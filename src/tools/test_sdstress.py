#!/usr/bin/env python3
"""sdstress (src/tests/sdstress.c) against its simulated card and controller
(MEGA65/mega65-core#890, docs/sdcard-native/sdstress.md).

    python3 src/tools/test_sdstress.py

Builds the host version (cc -DHOST) and checks that:
  - a clean stress run and a clean F011 compare find nothing;
  - each simulated fault is found, and classified as it should be: a write
    to the wrong sector, a lost write and a flipped byte as wrong on the
    card, a cache that kept old data as a stale cache, an F011 read of the
    wrong sector as a mismatch naming the sector it got;
  - a card with a valid MBR is refused.
If cl65 is there, the MEGA65 program is built too (its size shown).
"""

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "tests", "sdstress.c")

STRESS = "3\n0\n\n\n\nthis will destroy card contents\n"
F011 = "2\n\n"

# (what, fault, at, ops, script, text the output must hold, exit code)
CASES = [
    ("clean stress", 0, 0, 3000, STRESS,
     "errors: controller 0, stale cache 0, wrong on the card 0", 0),
    ("write to the wrong sector", 1, 20000, 3000, STRESS, "WRONG ON THE CARD: sector 4583 holds sector 4584", 1),
    ("lost write", 2, 20000, 3000, STRESS, "(stale or lost write)", 1),
    ("flipped byte", 3, 20000, 3000, STRESS, "1 bytes differ, first at 300", 1),
    ("stale cache", 4, 20000, 3000, STRESS, "STALE CACHE: sector 4584", 1),
    ("clean f011 compare", 0, 0, 200, F011, "0 mismatches, 0 rnf/stuck", 0),
    ("f011 reads the wrong sector", 5, 0, 30, F011, "the f011 data is image sector", 1),
    ("valid mbr refused", 9, 0, 0, STRESS, "that card has a valid mbr: refusing.", 1),
]


def main():
    work = tempfile.mkdtemp(prefix="sdstress")
    exe = os.path.join(work, "sdstress_host")
    subprocess.run(["cc", "-DHOST", "-O2", "-Wall", "-o", exe, SRC], check=True)
    if shutil.which("cl65"):
        prg = os.path.join(work, "sdstress.prg")
        subprocess.run(["cl65", "-t", "c64", "-O", "-Or", "-Oi", "-Os", "-o", prg, os.path.abspath(SRC)],
                       check=True, cwd=work)
        print("sdstress.prg: %d bytes" % os.path.getsize(prg))
    ok = True
    for what, fault, at, ops, script, want, code in CASES:
        r = subprocess.run([exe, str(fault), str(at), str(ops)], input=script, capture_output=True,
                           text=True, timeout=600)
        good = want in r.stdout and r.returncode == code
        print("%s %s" % ("PASS" if good else "FAIL", what))
        if not good:
            print("  wanted %r, exit %d (got exit %d)" % (want, code, r.returncode))
            print(r.stdout[-2000:])
            ok = False
    shutil.rmtree(work)
    print("ALL SDSTRESS TESTS PASSED" if ok else "SDSTRESS TESTS FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
