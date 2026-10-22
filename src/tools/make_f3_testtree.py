#!/usr/bin/env python3
"""A tree of test files with a manifest, for f3dos's VERIFY
(MEGA65/mega65-core#766, docs/sdcard-native/f3dos.md).

    python3 src/tools/make_f3_testtree.py /media/sdcard/F3TREE     (a mounted card)
    python3 src/tools/make_f3_testtree.py --image card.img [--drive 0] [--fragment]

then on the MEGA65, in f3dos:  verify c:/f3tree/manifest.txt

The files are deterministic (a seed): sizes around sector and cluster
boundaries, long, mixed-case and UTF-8 names, nested directories, one
directory with many entries, and a few larger files.  manifest.txt has a
line "crc32 size path" for each (the path from the manifest's directory,
UTF-8).  With --image the files go straight into the image's partition
(fat32img), --fragment splitting the larger ones into pieces.
"""

import argparse
import os
import random
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def tree(seed=1, many=150):
    """-> [(path, bytes)], directories implied"""
    rnd = random.Random(seed)
    files = []

    def data(n):
        return bytes(rnd.getrandbits(8) for _ in range(n)) if n < 4096 else rnd.randbytes(n)

    for n in (0, 1, 2, 100, 511, 512, 513, 1023, 1024, 1025, 4095, 4096, 4097,
              32767, 32768, 32769, 65535, 65536, 65537):
        files.append(("sizes/size%06d.bin" % n, data(n)))
    files.append(("names/A long file name with spaces.txt", b"spaces\n"))
    files.append(("names/MixedCase.Txt", b"mixed case\n"))
    files.append(("names/a.b.c.d.e", b"dots\n"))
    files.append(("names/UPPER.TXT", b"upper\n"))
    files.append(("names/lower.txt", b"lower\n"))
    files.append(("names/Gr\u00fc\u00dfe \u2013 \u2713.txt", "unicode\n".encode()))
    for i in range(12):
        files.append(("names/Same Long Prefix %d.dat" % i, data(i * 37)))
    files.append(("deep/one/two/three/four/five/six/deep.bin", data(3000)))
    for i in range(many):
        files.append(("many/entry number %04d.txt" % i, ("entry %d\n" % i).encode()))
    for n in (300 * 1024, 819200, 2 * 1024 * 1024 + 123):
        files.append(("big/big%d.bin" % n, data(n)))
    return files


def manifest(files):
    return "".join("%08x %d %s\n" % (zlib.crc32(d) & 0xFFFFFFFF, len(d), p)
                   for p, d in files).encode()


def to_dir(root, files):
    for p, d in files:
        full = os.path.join(root, *p.split("/"))
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as f:
            f.write(d)
    with open(os.path.join(root, "manifest.txt"), "wb") as f:
        f.write(manifest(files))


def to_image(image, drive, root, files, fragment):
    import fat32img
    img = fat32img.Image(image)
    v = img.volume(drive)
    made = set()

    def mkdirs(path):
        parts = path.split("/")[:-1]
        for i in range(1, len(parts) + 1):
            d = "/".join(parts[:i])
            if d and d not in made:
                v.mkdir(d)
                made.add(d)

    for p, d in files:
        full = root + "/" + p
        mkdirs(full)
        v.write_file(full, d, fragments=3 if fragment and len(d) > 65536 else 1)
    v.write_file(root + "/manifest.txt", manifest(files))
    assert img.check(), "fsck.fat failed"
    img.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", nargs="?", help="where to write the tree (a mounted card)")
    ap.add_argument("--image", help="write into this image instead")
    ap.add_argument("--drive", type=int, default=0, help="the image's partition (0 first)")
    ap.add_argument("--root", default="/F3TREE", help="the tree's directory in the image")
    ap.add_argument("--fragment", action="store_true", help="split the larger files (image)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--many", type=int, default=150, help="files in many/")
    a = ap.parse_args()
    files = tree(a.seed, a.many)
    if a.image:
        to_image(a.image, a.drive, a.root, files, a.fragment)
    elif a.dir:
        to_dir(a.dir, files)
    else:
        ap.error("a directory or --image")
    print("%d files, %d bytes" % (len(files), sum(len(d) for _, d in files)))


if __name__ == "__main__":
    main()
