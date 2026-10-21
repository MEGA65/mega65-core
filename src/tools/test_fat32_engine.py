#!/usr/bin/env python3
"""Tests of the FAT32 engine firmware (src/fat32/engine.fs) on the instruction
set simulator, against the fat32img test image (MEGA65/mega65-core#766).

    python3 src/tools/test_fat32_engine.py [--image test.img] [-v] [--rtl [--short]]

The image is built if it does not exist (needs sfdisk, mkfs.fat, fsck.fat).
Every result is checked against fat32img's own reading of the image.
--rtl then replays the run's transcript through fat32_engine.vhdl in GHDL
(tb_fat32_engine), which must match the simulator exactly.
"""

import argparse
import os
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fat32img  # noqa: E402
import fat32sim  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
FIRMWARE = os.path.join(HERE, "..", "fat32", "engine.fs")

E_NOENT, E_NOTDIR, E_ISDIR, E_BADFD, E_NFILE, E_NODRV, E_IO, E_END = range(1, 9)
E_ACCESS, E_BADREQ, E_LONG, E_ROFS = 9, 10, 11, 15


class Engine:
    def __init__(self, image, hypervisor=False):
        prog = fat32sim.assemble(open(FIRMWARE).read())
        fat32sim.encode(prog)               # (it must fit the instruction word)
        self.m = fat32sim.Machine(prog, cards={1: image}, hypervisor=hypervisor)

    def req(self, op, fd=0, flags=0, arg0=0, arg1=0, path=b""):
        """a $70 request -> (status, the response block)"""
        if isinstance(path, str):
            path = path.encode()
        blk = bytearray(512)
        blk[0:6] = b"F3" + bytes([1, op, fd, flags])
        blk[6:10] = struct.pack("<I", arg0)
        blk[10:14] = struct.pack("<I", arg1)
        blk[16:16 + len(path)] = path
        self.m.buf[0xE00:0x1000] = blk
        status, _ = self.m.command(0x70)
        return status, bytes(self.m.buf[0xE00:0x1000])

    def ok(self, *a, **k):
        status, r = self.req(*a, **k)
        if status:
            raise AssertionError("request %r failed: status %d (line %d)"
                                 % ((a, k), status, self.m.line))
        return r

    def read(self, fd, n):
        status, count = self.m.command(0x71, arg=(fd << 24) | n)
        if status:
            raise AssertionError("read failed: %d" % status)
        return bytes(self.m.buf[0xE00:0xE00 + count])

    def readsector(self, fd, k):
        status, _ = self.m.command(0x74, arg=(fd << 24) | k)
        return status, bytes(self.m.buf[0xE00:0x1000])


def entry(r):
    """a readdir / stat response -> (long name, short name, attr, size, first)"""
    d = r[16:]
    attr = d[0]
    size, first = struct.unpack("<II", d[4:12])
    short = d[16:29].split(b"\0")[0].decode()
    long = d[32:].split(b"\0")[0].decode()
    return long, short, attr, size, first


def shown(name):
    """a long name as the engine gives it: UTF-8, 255 bytes at most (longer:
    cut at a character, then an ellipsis)"""
    b = name.encode()
    if len(b) <= 255:
        return name
    while len(b) > 252:
        name = name[:-1]
        b = name.encode()
    return name + "\u2026"


def u32(r, o):
    return struct.unpack("<I", r[o:o + 4])[0]


def tests(image, verbose, trace=None, short=False):
    img = fat32img.Image(image)
    vol = img.volume(0)
    e = Engine(image)
    if trace:
        e.m.start_trace()
    passed = []

    def check(name, cond, detail=""):
        if not cond:
            raise AssertionError("%s %s" % (name, detail))
        passed.append(name)
        if verbose:
            print("  ok", name, "(%d steps, %d sector ops so far)" % (e.m.last_steps, e.m.sector_ops))

    # drives
    r = e.ok(1)
    check("rescan finds 2 drives", u32(r, 6) == 2, u32(r, 6))
    r = e.ok(2)
    parts = [r[16 + 16 * i:32 + 16 * i] for i in range(u32(r, 6))]
    starts = [u32(p, 4) for p in parts]
    check("partition list", starts == [p[1] for p in img.partitions] and parts[0][0] == 1
          and parts[0][1] == 1 and parts[0][3] == 3 and parts[1][3] == 0, (starts, img.partitions))
    check("bad drive", e.req(3, arg0=5)[0] == E_NODRV)

    # directories
    def listing(path):
        st, r = e.req(0x10, path=path)
        assert st == 0, "opendir %s: %d" % (path, st)
        fd = r[4]
        out = []
        while True:
            st, r = e.req(0x11, fd=fd)
            if st == E_END:
                break
            assert st == 0, "readdir: %d" % st
            out.append(entry(r))
        st, _ = e.req(0x11, fd=fd)
        assert st == E_END, "readdir after the end: %d" % st
        e.ok(0x22, fd=fd)
        return out

    def expect(cluster, hidden_system=True):
        out = []
        for long, short, attr, first, size in vol.listdir(cluster):
            if hidden_system and attr & 0x04:
                continue
            out.append((shown(long), short, attr, size, first))
        return out

    got = listing("/")
    want = expect(vol.root)
    check("root listing", [(l, s, a, z, f) for l, s, a, z, f in got] == want, (got, want))
    got = listing("/LOTS")
    want = expect(vol.lookup("/LOTS")[1])
    check("70 long names over several sectors", got == want and len(got) == 72, len(got))
    got = listing("/MEGA65")
    check("SYSTEM files hidden", [g[0] for g in got] == [".", ".."], got)
    got = listing("/GAMES/Arcade Classics")
    check("long directory names in the path", any(g[0] == "Space Invaders Deluxe.d81" for g in got), got)
    got = listing("/games/arcade classics/../SHORT.PRG/..".rsplit("/", 2)[0])
    check("case-blind, ..", any(g[0] == "SHORT.PRG" for g in got), got)

    got = listing("/UNICODE")
    want = expect(vol.lookup("/UNICODE")[1])
    check("UTF-8 long names (a surrogate pair, a 304-byte name cut short)",
          got == want and any(g[0].endswith("\u2026") for g in got), (got, want))
    fd = e.ok(0x20, path="/unicode/grüße – ✓ 😀.txt")[4]
    check("open a UTF-8 name", e.read(fd, 100) == b"Unicode name\n")
    e.ok(0x22, fd=fd)
    fd = e.ok(0x20, path="/UNICODE/" + shown("✓" * 100 + ".txt"))[4]
    check("open a long name by its shortened form", e.read(fd, 100) == b"a long UTF-8 name\n")
    e.ok(0x22, fd=fd)
    check("a 304-byte path component", e.req(0x20, path="/UNICODE/" + "✓" * 100 + ".txt")[0] == E_LONG)

    check("opendir of a file", e.req(0x10, path="/README.TXT")[0] == E_NOTDIR)
    check("not found", e.req(0x10, path="/NOPE")[0] == E_NOENT)
    check("a file in the middle of a path", e.req(0x24, path="/README.TXT/X")[0] == E_NOTDIR)

    # chdir, relative paths, drive prefixes
    e.ok(0x12, path="/GAMES")
    r = e.ok(0x24, path="SHORT.PRG")
    check("relative to the current directory", entry(r)[3] == 768, entry(r))
    r = e.ok(0x13)
    check("getcwd", r[16:].split(b"\0")[0] == b"/GAMES", r[16:40])
    e.ok(0x12, path="Arcade Classics")
    r = e.ok(0x13)
    check("getcwd with a long name", r[16:].split(b"\0")[0] == b"/GAMES/Arcade Classics", r[16:48])
    e.ok(0x12, path="../..")
    r = e.ok(0x13)
    check("getcwd at the root", r[16:].split(b"\0")[0] == b"/", r[16:40])
    e.ok(0x12, path="/GAMES")
    e.ok(0x12, path="..")
    r = e.ok(0x24, path="README.TXT")
    check("chdir ..", entry(r)[1] == "README.TXT", entry(r))
    r = e.ok(0x24, path="2:/SECOND.TXT")
    check("drive prefix", entry(r)[3] == 17, entry(r))
    e.ok(3, arg0=2)
    r = e.ok(0x24, path="SECOND.TXT")
    check("setdrive", entry(r)[3] == 17, entry(r))
    e.ok(3, arg0=1)
    r = e.ok(0x24, path="/")
    check("stat of the root", entry(r)[2] == 0x10)

    # files
    st, _ = e.req(0x20, path="/MEGA65/HICKUP.M65")
    check("SYSTEM file closed to programs", st == E_NOENT, st)
    check("open a directory", e.req(0x20, path="/GAMES")[0] == E_ISDIR)
    check("phase 1 is read-only", e.req(0x20, flags=1, path="/README.TXT")[0] == E_ROFS)

    fd = e.ok(0x20, path="/README.TXT")[4]
    check("first descriptor is 0", fd == 0, fd)
    data = e.read(fd, 512)
    check("read a small file", data == vol.read_file("/README.TXT"), data)
    check("read at the end", e.read(fd, 100) == b"")
    e.ok(0x22, fd=fd)

    big = vol.read_file("/GAMES/Arcade Classics/Space Invaders Deluxe.d81")
    fd = e.ok(0x20, path="/GAMES/Arcade Classics/Space Invaders Deluxe.d81")[4]
    got = bytearray()
    n = 0
    for size in [1, 7, 512, 300, 512, 511, 2]:
        got += e.read(fd, size)
    while len(got) < 3 * 4096 + 100:
        got += e.read(fd, 512)
    check("odd-sized reads", bytes(got) == big[:len(got)])
    # seeks into the fragments, back and forth
    for pos in [819200 - 10, 5, 409600 + 3, 204800, 0, 614400 - 1]:
        r = e.ok(0x23, fd=fd, arg0=pos)
        d = e.read(fd, 50)
        check("seek to %d" % pos, d == big[pos:pos + 50] and u32(r, 6) == pos, (pos, len(d)))
    e.ok(0x23, fd=fd, arg0=1000)
    e.ok(0x23, fd=fd, flags=1, arg0=24)
    check("seek from the position", e.read(fd, 4) == big[1024:1028])
    e.ok(0x23, fd=fd, flags=2, arg0=(-4) & 0xFFFFFFFF)
    check("seek from the end", e.read(fd, 100) == big[-4:])
    for k in [0, 1, 799, 1599, 800, 3]:
        st, d = e.readsector(fd, k)
        check("sector %d" % k, st == 0 and d == big[512 * k:512 * k + 512], st)
    check("sector past the end", e.readsector(fd, 1600)[0] == E_END)
    e.m.sector_ops = 0
    e.ok(0x23, fd=fd, arg0=0)
    n = 64 if short else 1600
    for k in range(n):
        e.read(fd, 512)
    check("a whole file reads one sector per sector, plus FAT steps",
          e.m.sector_ops <= n + n // 8, e.m.sector_ops)
    e.ok(0x22, fd=fd)

    # descriptors
    fds = [e.ok(0x20, path="/README.TXT")[4] for _ in range(8)]
    check("descriptors 0-7", fds == list(range(8)), fds)
    check("no free descriptor", e.req(0x20, path="/README.TXT")[0] == E_NFILE)
    for f in fds:
        e.ok(0x22, fd=f)
    check("no descriptor 8", e.req(0x22, fd=8)[0] == E_BADFD)
    check("programs cannot reach the hypervisor's", e.req(0x22, fd=0x80)[0] == E_BADFD)
    r = e.ok(0x20, fd=5, flags=0x80, path="/README.TXT")
    check("a descriptor asked for", r[4] == 5)
    e.ok(0x22, fd=5)
    check("read on a closed descriptor", e.m.command(0x71, arg=(5 << 24) | 10)[0] == E_BADFD)

    # the hypervisor sees SYSTEM files and has descriptors 0 and 1
    e.m.hypervisor = True
    got = listing("/MEGA65")
    check("hypervisor sees SYSTEM files", any(g[0] == "HICKUP.M65" for g in got), got)
    e.m.hypervisor = False
    ufd = e.ok(0x20, path="/README.TXT")[4]             # the program's 0
    e.m.hypervisor = True
    fd = e.ok(0x20, fd=0, flags=0x80, path="/MEGA65/HICKUP.M65")[4]
    check("hypervisor descriptor H0", fd == 0 and e.read(0, 11) == b"system file")
    check("H0 is not the program's 0", e.read(0x80, 5) == b"Hello")
    check("hypervisor: two descriptors", e.ok(0x20, path="/README.TXT")[4] == 1
          and e.req(0x20, path="/README.TXT")[0] == E_NFILE)
    e.ok(0x22, fd=0)
    e.ok(0x22, fd=1)
    e.m.hypervisor = False
    check("the program's 0 unaffected", e.read(ufd, 6) == b" from ")
    e.ok(0x22, fd=ufd)

    if trace:
        e.m.write_trace(trace)
    print("%d checks passed, %d engine steps, %d instructions of firmware"
          % (len(passed), e.m.steps, len(e.m.prog)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--trace", help="write a transcript for tb_fat32_engine.vhdl")
    ap.add_argument("--short", action="store_true", help="read 64 sectors, not the whole file")
    ap.add_argument("--rtl", action="store_true", help="replay the run through fat32_engine.vhdl (GHDL)")
    a = ap.parse_args()
    if a.image and os.path.exists(a.image):
        image = a.image
    else:
        image = a.image or os.path.join(tempfile.mkdtemp(prefix="fat32eng"), "test.img")
        fat32img.standard_image(image).close()
    work = tempfile.mkdtemp(prefix="fat32rtl") if a.rtl else None
    trace = a.trace or (os.path.join(work, "trace.txt") if a.rtl else None)
    tests(image, a.verbose, trace, a.short)
    if a.rtl:
        sys.exit(0 if rtl(trace, work) else 1)


def rtl(trace, work):
    vhdl = os.path.join(HERE, "..", "vhdl")
    files = [os.path.join(vhdl, f) for f in ("fat32_rom.vhdl", "fat32_engine.vhdl", "tb_fat32_engine.vhdl")]
    # (the ROM must be the current firmware)
    prog = fat32sim.assemble(open(FIRMWARE).read())
    if open(files[0]).read() != fat32sim.vhdl_rom(prog):
        print("fat32_rom.vhdl is stale: python3 src/tools/fat32sim.py src/fat32/engine.fs src/vhdl/fat32_rom.vhdl")
        return False
    ok = True
    for cmd in (["ghdl", "-a", "--std=08", "-fsynopsys"] + files,
                ["ghdl", "-e", "--std=08", "-fsynopsys", "tb_fat32_engine"]):
        p = subprocess.run(cmd, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if p.returncode:
            print(p.stdout)
            return False
    for lat in (1, 2):
        p = subprocess.run(["ghdl", "-r", "--std=08", "-fsynopsys", "tb_fat32_engine",
                            "-gG_TRACE=" + trace, "-gG_RD_LAT=%d" % lat],
                           cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        lines = [l.split("): ")[-1] for l in p.stdout.splitlines() if "):" in l]
        good = "ALL FAT32 ENGINE TESTS PASSED" in p.stdout and "(report error)" not in p.stdout
        print("RTL, read latency %d: %s" % (lat, "pass" if good else "FAIL"))
        for l in (lines if not good else lines[-2:-1]):
            print("  " + l)
        ok = ok and good
    return ok


if __name__ == "__main__":
    main()
