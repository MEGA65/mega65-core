#!/usr/bin/env python3
"""f3dos and f3test (src/tests) on the FAT32 engine's simulator
(MEGA65/mega65-core#766, docs/sdcard-native/f3dos.md).

    python3 src/tools/test_f3dos.py [-v]

Builds the host versions (cc -DHOST), makes the standard test image with
make_f3_testtree's tree in it (larger files fragmented), and runs through
f3bridge.py:
  - f3test on both partitions (4 KB and 512-byte clusters): no failures;
  - an f3dos session (DRIVES, DIR with wildcards, COPY across drives,
    MOVE, REN, DEL, MKFILE/CHECK, CRC, VERIFY of the tree, EXEC, ...),
    its output checked;
  - fsck.fat and the FSInfo free count after each.
If cl65 is there, the MEGA65 programs are built too (their sizes shown).
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import f3bridge  # noqa: E402
import fat32img  # noqa: E402
import make_f3_testtree  # noqa: E402

TESTS = os.path.join(HERE, "..", "tests")

SESSION = r"""
drives
dir
cd games
dir *.prg
cd "Arcade Classics"
stat "space invaders deluxe.d81"
cd /
type readme.txt
crc readme.txt
md tmp
write tmp/hello.txt hello there
append tmp/hello.txt second line
type tmp/hello.txt
mkfile tmp/pat.bin 70000 5
check tmp/pat.bin 5
copy tmp/pat.bin d:
check d:pat.bin 5
d:
dir
c:
copy lots/*7.txt tmp
dir tmp/*.txt
ren tmp/hello.txt "Hello Long Name.txt"
move tmp/*7.txt d:
dir d:*.txt
del d:*7.txt
del "tmp/Hello Long Name.txt"
trunc tmp/pat.bin 1000
check tmp/pat.bin 5
rd tmp
del tmp/pat.bin
rd tmp
attrib +r readme.txt
del readme.txt
attrib -r readme.txt
copy readme.txt readme.txt
verify f3tree/manifest.txt
write script.txt echo from a script
append script.txt dir games
exec script.txt
del script.txt
bench f3tree/big/big819200.bin
nonsense
exit
"""

# (text the session's output must hold, in order)
EXPECT = [
    "C: ext card, at 2048, 300 mb, 4 kb clusters",
    "D: ext card, at 616448, 40 mb, 512 b clusters",
    "README.TXT",
    "      768 --- SHORT.PRG",
    "1 file(s), 768 b, 0 dir(s)",
    "name:  Space Invaders Deluxe.d81",
    "short: SPACEI~1.D81",
    "size:  819200",
    "Hello from the MEGA65 FAT32 engine test image.",
    "%08x 47" % (zlib.crc32(b"Hello from the MEGA65 FAT32 engine test image.\n") & 0xFFFFFFFF),
    "hello there\nsecond line",
    "70000 bytes written",
    "70000 bytes ok",
    "tmp/pat.bin -> d:pat.bin",
    "70000 bytes ok",
    "    70000 --- pat.bin",
    "lots/file number 067.txt -> tmp/file number 067.txt",
    "file(s), ",
    "tmp/file number 067.txt -> d:file number 067.txt",
    "        8 --- file number 067.txt",
    "deleted d:file number 067.txt",
    "1000 bytes ok",
    "error 13: directory not empty",
    "deleted tmp/pat.bin",
    "README.TXT: read-only archive",
    "error 9: access denied",
    "README.TXT: archive",
    "readme.txt: the same file",
    "verify: %d ok, 0 bad",
    "> echo from a script",
    "from a script",
    "> dir games",
    "      768 --- SHORT.PRG",
    "$71 read   800 kb",
    "$74 sector 800 kb",
    "$76 quick  800 kb",
    "unknown command",
]


def build(work):
    out = {}
    for prog in ("f3dos", "f3test"):
        exe = os.path.join(work, prog + "_host")
        subprocess.run(["cc", "-DHOST", "-O2", "-Wall", "-o", exe,
                        os.path.join(TESTS, prog + ".c"), os.path.join(TESTS, "f3lib.c")], check=True)
        out[prog] = exe
    if shutil.which("cl65"):
        for prog in ("f3dos", "f3test"):
            prg = os.path.join(work, prog + ".prg")
            subprocess.run(["cl65", "-t", "c64", "-O", "-Os", "-o", prg,
                            os.path.join(TESTS, prog + ".c"), os.path.join(TESTS, "f3lib.c")],
                           check=True, cwd=work)
            print("%s.prg: %d bytes" % (prog, os.path.getsize(prg)))
    return out


def fsck(image, name):
    img = fat32img.Image(image)
    ok = True
    for i in range(len(img.partitions)):
        v = img.volume(i)
        if v.fsinfo_free() != v.free_count():
            print("%s: partition %d: FSInfo free count %d, really %d"
                  % (name, i, v.fsinfo_free(), v.free_count()))
            ok = False
    if not img.check(sync=False):
        ok = False
    img.close()
    print("%s: fsck.fat %s" % (name, "ok" if ok else "FAILED"))
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--keep", help="keep the work directory here")
    a = ap.parse_args()
    work = a.keep or tempfile.mkdtemp(prefix="f3dos")
    os.makedirs(work, exist_ok=True)
    exe = build(work)
    image = os.path.join(work, "card.img")
    fat32img.standard_image(image).close()
    files = make_f3_testtree.tree()
    make_f3_testtree.to_image(image, 0, "/F3TREE", files, True)
    ok = True

    for drive in ("c", "d"):
        code, out, _ = f3bridge.run([exe["f3test"], drive], {1: image}, stdin="")
        if a.verbose:
            print(out)
        last = out.strip().splitlines()[-1] if out.strip() else ""
        good = code == 0 and " 0 failed" in last
        print("f3test %s: %s" % (drive, last))
        if not good:
            print(out)
        ok = fsck(image, "after f3test " + drive) and good and ok

    code, out, _ = f3bridge.run([exe["f3dos"]], {1: image}, stdin=SESSION.lstrip())
    if a.verbose:
        print(out)
    at = 0
    missing = []
    for want in EXPECT:
        if "%d ok" in want:
            want = want % len(files)
        k = out.find(want, at)
        if k < 0:
            missing.append(want)
        else:
            at = k + len(want)
    print("f3dos session: %d of %d expected outputs" % (len(EXPECT) - len(missing), len(EXPECT)))
    for m in missing:
        print("  missing (in order): %r" % m)
    if missing and not a.verbose:
        print(out)
    ok = fsck(image, "after the f3dos session") and not missing and code == 0 and ok
    print("ALL F3DOS TESTS PASSED" if ok else "F3DOS TESTS FAILED")
    if not a.keep:
        shutil.rmtree(work)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
