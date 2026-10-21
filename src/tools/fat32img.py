#!/usr/bin/env python3
"""FAT32 disk images for testing the hardware FAT32 engine (MEGA65/mega65-core#766).

Makes an MBR-partitioned image, formats the partition(s) with mkfs.fat, and
adds directories and files itself (no mounting, no mtools):

    img = Image.create("card.img", size_mb=345, partitions=[(2048, 300, 8)])  # start, MB, spc
    vol = img.volume(0)
    vol.mkdir("/GAMES")
    vol.write_file("/GAMES/A Long File Name.d81", data, fragments=3)
    img.check()        # fsck.fat on every partition

The same classes read images back (list directories, follow cluster chains,
read files), as a reference to check the engine's results against.

Limits: 512-byte sectors, FAT32 only, ASCII names.  Long filenames get
8.3 aliases of the NAME~N.EXT form.
"""

import os
import struct
import subprocess
import tempfile

SECTOR = 512
EOC = 0x0FFFFFFF


def lfn_checksum(name11):
    s = 0
    for c in name11:
        s = (((s & 1) << 7) + (s >> 1) + c) & 0xFF
    return s


def is_83(name):
    """name fits 8.3 as it is (upper case, legal characters)"""
    if name in (".", ".."):
        return True
    if name != name.upper():
        return False
    base, dot, ext = name.partition(".")
    if not base or len(base) > 8 or len(ext) > 3 or "." in ext:
        return False
    legal = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$%'-_@~`!(){}^#&")
    return all(c in legal for c in base + ext)


def pack83(name):
    if name in (".", ".."):
        return name.encode().ljust(11, b" ")
    base, _, ext = name.partition(".")
    return base.encode().ljust(8, b" ") + ext.encode().ljust(3, b" ")


def unpack83(raw):
    base = raw[:8].decode("ascii", "replace").rstrip()
    ext = raw[8:11].decode("ascii", "replace").rstrip()
    return base + ("." + ext if ext else "")


class Volume:
    """one FAT32 partition of an image"""

    def __init__(self, f, start):
        self.f = f
        self.start = start
        bs = self.read_sector(0)
        (self.bps, self.spc, self.reserved, self.nfats) = struct.unpack_from("<HBHB", bs, 11)
        self.total = struct.unpack_from("<I", bs, 32)[0]
        self.fatsz = struct.unpack_from("<I", bs, 36)[0]
        self.root = struct.unpack_from("<I", bs, 44)[0]
        self.fsinfo = struct.unpack_from("<H", bs, 48)[0]
        assert self.bps == SECTOR, "512-byte sectors only"
        self.fat_lba = self.reserved
        self.data_lba = self.reserved + self.nfats * self.fatsz
        self.nclusters = (self.total - self.data_lba) // self.spc + 2
        self.next_free = 3

    # --- sectors and clusters (sector numbers relative to the partition) ---
    def read_sector(self, n):
        self.f.seek((self.start + n) * SECTOR)
        return self.f.read(SECTOR)

    def write_sector(self, n, data):
        assert len(data) == SECTOR
        self.f.seek((self.start + n) * SECTOR)
        self.f.write(data)

    def cluster_lba(self, c):
        return self.data_lba + (c - 2) * self.spc

    def fat_get(self, c):
        s, off = divmod(c * 4, SECTOR)
        return struct.unpack_from("<I", self.read_sector(self.fat_lba + s), off)[0] & 0x0FFFFFFF

    def fat_set(self, c, v):
        s, off = divmod(c * 4, SECTOR)
        for k in range(self.nfats):
            lba = self.fat_lba + k * self.fatsz + s
            sec = bytearray(self.read_sector(lba))
            old = struct.unpack_from("<I", sec, off)[0]
            struct.pack_into("<I", sec, off, (old & 0xF0000000) | (v & 0x0FFFFFFF))
            self.write_sector(lba, bytes(sec))

    def chain(self, c):
        out = []
        while 2 <= c < 0x0FFFFFF8:
            out.append(c)
            c = self.fat_get(c)
        return out

    def alloc(self, n, fragments=1):
        """n clusters, in about `fragments` pieces (gaps of one free cluster)"""
        got = []
        per = max(1, -(-n // fragments))
        c = self.next_free
        while len(got) < n:
            assert c < self.nclusters, "volume full"
            if self.fat_get(c) == 0:
                got.append(c)
                if len(got) % per == 0 and len(got) < n:
                    c += 1                      # leave a hole
            c += 1
        for a, b in zip(got, got[1:]):
            self.fat_set(a, b)
        self.fat_set(got[-1], EOC)
        self.next_free = c
        for cl in got:
            for k in range(self.spc):
                self.write_sector(self.cluster_lba(cl) + k, bytes(SECTOR))
        return got

    def free_count(self):
        """the free clusters, counted in the FAT"""
        self.f.seek((self.start + self.fat_lba) * SECTOR)
        fat = self.f.read(self.fatsz * SECTOR)
        return sum(1 for c in range(2, self.nclusters)
                   if struct.unpack_from("<I", fat, c * 4)[0] & 0x0FFFFFFF == 0)

    def fsinfo_free(self):
        """the free cluster count FSInfo claims"""
        return struct.unpack_from("<I", self.read_sector(self.fsinfo), 488)[0]

    def sync_fsinfo(self):
        """FSInfo: the free cluster count and the next-free hint"""
        self.f.seek((self.start + self.fat_lba) * SECTOR)
        fat = self.f.read(self.fatsz * SECTOR)
        free = 0
        first = None
        for c in range(2, self.nclusters):
            if struct.unpack_from("<I", fat, c * 4)[0] & 0x0FFFFFFF == 0:
                free += 1
                if first is None:
                    first = c
        sec = bytearray(self.read_sector(self.fsinfo))
        struct.pack_into("<II", sec, 488, free, first or 0xFFFFFFFF)
        self.write_sector(self.fsinfo, bytes(sec))

    # --- directories ---
    def dir_entries(self, cluster):
        """(raw 32 bytes, sector, offset) of every entry slot"""
        for cl in self.chain(cluster):
            for k in range(self.spc):
                lba = self.cluster_lba(cl) + k
                sec = self.read_sector(lba)
                for off in range(0, SECTOR, 32):
                    yield sec[off:off + 32], lba, off

    def listdir(self, cluster):
        """[(long name, 8.3 name, attr, first cluster, size)] (no deleted ones)"""
        out, lfn = [], {}
        for raw, _, _ in self.dir_entries(cluster):
            if raw[0] == 0:
                break
            if raw[0] == 0xE5:
                lfn = {}
                continue
            if raw[11] & 0x08 and raw[11] != 0x0F:
                lfn = {}                        # the volume label
                continue
            if raw[11] == 0x0F:
                seq = raw[0] & 0x1F
                lfn[seq] = raw[1:11] + raw[14:26] + raw[28:32]
                continue
            short = unpack83(raw[:11])
            long = short
            if lfn:
                units = b"".join(lfn[k] for k in sorted(lfn))
                end = len(units)
                for i in range(0, len(units), 2):
                    if units[i:i + 2] in (b"\0\0", b"\xff\xff"):
                        end = i
                        break
                long = units[:end].decode("utf-16-le", errors="replace")
            lfn = {}
            first = struct.unpack_from("<H", raw, 20)[0] << 16 | struct.unpack_from("<H", raw, 26)[0]
            size = struct.unpack_from("<I", raw, 28)[0]
            out.append((long, short, raw[11], first, size))
        return out

    def lookup(self, path):
        """(attr, first cluster, size) of a path, or None"""
        cl, attr, size = self.root, 0x10, 0
        for part in [p for p in path.split("/") if p]:
            for long, short, a, first, sz in self.listdir(cl):
                if part.upper() in (long.upper(), short.upper()):
                    cl, attr, size = first or self.root, a, sz
                    break
            else:
                return None
        return attr, cl, size

    def read_file(self, path):
        attr, cl, size = self.lookup(path)
        data = b""
        for c in self.chain(cl):
            for k in range(self.spc):
                data += self.read_sector(self.cluster_lba(c) + k)
        return data[:size]

    def _free_slots(self, cluster, n):
        """n consecutive free entry slots in the directory (grows it)"""
        run = []
        for raw, lba, off in self.dir_entries(cluster):
            if raw[0] in (0, 0xE5):
                run.append((lba, off))
                if len(run) == n:
                    return run
            else:
                run = []
        last = self.chain(cluster)[-1]
        new = self.alloc(1)[0]
        self.fat_set(last, new)
        return self._free_slots(cluster, n)

    def _alias(self, cluster, name):
        base, _, ext = name.upper().rpartition(".") if "." in name else (name.upper(), "", "")
        clean = lambda s: "".join(c if c.isascii() and (c.isalnum() or c in "$%'-_@~`!(){}^#&") else "_"
                                  for c in s if c not in " .")
        base, ext = clean(base), clean(ext)[:3]
        existing = {short for _, short, _, _, _ in self.listdir(cluster)}
        for n in range(1, 1000):
            tail = "~%d" % n
            cand = base[:8 - len(tail)] + tail + ("." + ext if ext else "")
            if cand not in existing:
                return cand
        raise RuntimeError("no alias")

    def _add_entry(self, cluster, name, attr, first, size):
        if is_83(name):
            short, lfn_parts = name, []
        else:
            short = self._alias(cluster, name)
            b = name.encode("utf-16-le")
            u = list(struct.unpack("<%dH" % (len(b) // 2), b))
            assert len(u) <= 255, "name too long"
            lfn_parts = [u[i:i + 13] for i in range(0, len(u), 13)]
        name11 = pack83(short)
        slots = self._free_slots(cluster, len(lfn_parts) + 1)
        csum = lfn_checksum(name11)
        for i, part in enumerate(lfn_parts):
            seq = i + 1
            chars = [c for c in part] + ([0] if len(part) < 13 else [])
            chars += [0xFFFF] * (13 - len(chars))
            e = bytearray(32)
            e[0] = seq | (0x40 if seq == len(lfn_parts) else 0)
            e[11], e[13] = 0x0F, csum
            pos = [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30]
            for p, ch in zip(pos, chars):
                struct.pack_into("<H", e, p, ch)
            lba, off = slots[len(lfn_parts) - 1 - i]
            sec = bytearray(self.read_sector(lba))
            sec[off:off + 32] = e
            self.write_sector(lba, bytes(sec))
        e = bytearray(32)
        e[0:11] = name11
        e[11] = attr
        struct.pack_into("<HH", e, 20, first >> 16, 0)
        struct.pack_into("<H", e, 26, first & 0xFFFF)
        struct.pack_into("<I", e, 28, size)
        struct.pack_into("<HH", e, 22, 0x6000, 0x5A55)      # 12:00, 2025-02-21
        struct.pack_into("<H", e, 16, 0x5A55)
        lba, off = slots[-1]
        sec = bytearray(self.read_sector(lba))
        sec[off:off + 32] = e
        self.write_sector(lba, bytes(sec))

    def _parent(self, path):
        parts = [p for p in path.split("/") if p]
        parent = "/" + "/".join(parts[:-1])
        found = self.lookup(parent)
        assert found and found[0] & 0x10, "no directory " + parent
        return found[1], parts[-1]

    def mkdir(self, path, attr=0x10):
        pcl, name = self._parent(path)
        cl = self.alloc(1)[0]
        dot = bytearray(32)
        dot[0:11], dot[11] = pack83("."), 0x10
        struct.pack_into("<HH", dot, 20, cl >> 16, 0)
        struct.pack_into("<H", dot, 26, cl & 0xFFFF)
        dotdot = bytearray(32)
        dotdot[0:11], dotdot[11] = pack83(".."), 0x10
        p = 0 if pcl == self.root else pcl
        struct.pack_into("<HH", dotdot, 20, p >> 16, 0)
        struct.pack_into("<H", dotdot, 26, p & 0xFFFF)
        self.write_sector(self.cluster_lba(cl), bytes(dot + dotdot) + bytes(SECTOR - 64))
        self._add_entry(pcl, name, attr, cl, 0)
        return cl

    def write_file(self, path, data, fragments=1, attr=0x20):
        pcl, name = self._parent(path)
        csize = self.spc * SECTOR
        n = max(1, -(-len(data) // csize))
        chain = self.alloc(n, fragments) if data else []
        for i, c in enumerate(chain):
            blk = data[i * csize:(i + 1) * csize].ljust(csize, b"\0")
            for k in range(self.spc):
                self.write_sector(self.cluster_lba(c) + k, blk[k * SECTOR:(k + 1) * SECTOR])
        self._add_entry(pcl, name, attr, chain[0] if chain else 0, len(data))
        return chain


class Image:
    def __init__(self, path):
        self.path = path
        self.f = open(path, "r+b")
        mbr = self.read_sector(0)
        assert mbr[510:512] == b"\x55\xAA", "no MBR"
        self.partitions = []
        for i in range(4):
            e = mbr[446 + 16 * i:462 + 16 * i]
            if e[4]:
                self.partitions.append((e[4], struct.unpack_from("<I", e, 8)[0],
                                        struct.unpack_from("<I", e, 12)[0]))

    def read_sector(self, n):
        self.f.seek(n * SECTOR)
        return self.f.read(SECTOR)

    @classmethod
    def create(cls, path, size_mb, partitions):
        """partitions: [(start sector, size in MB, sectors per cluster)], each
        formatted FAT32 (choose sizes with at least 65525 clusters)"""
        with open(path, "wb") as f:
            f.truncate(size_mb * 1024 * 1024)
        table = "label: dos\n" + "".join(
            "start=%d, size=%d, type=c\n" % (s, mb * 2048) for s, mb, _ in partitions)
        subprocess.run(["sfdisk", "--no-reread", "-q", path], input=table, text=True, check=True,
                       stdout=subprocess.DEVNULL)
        for s, mb, spc in partitions:
            subprocess.run(["mkfs.fat", "-F", "32", "-S", "512", "-s", str(spc),
                            "--offset", str(s), "-n", "M65TEST", path, str(mb * 1024)],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return cls(path)

    def volume(self, i):
        return Volume(self.f, self.partitions[i][1])

    def check(self, sync=True):
        """fsck.fat each partition (on a copy of its bytes); sync: FSInfo
        brought up to date first"""
        if sync:
            for i in range(len(self.partitions)):
                self.volume(i).sync_fsinfo()
        self.f.flush()
        ok = True
        for _, start, size in self.partitions:
            with tempfile.NamedTemporaryFile(suffix=".img") as t:
                self.f.seek(start * SECTOR)
                remaining = size * SECTOR
                while remaining:
                    chunk = self.f.read(min(remaining, 1 << 20))
                    t.write(chunk)
                    remaining -= len(chunk)
                t.flush()
                r = subprocess.run(["fsck.fat", "-n", t.name], stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True)
                if r.returncode != 0:
                    print(r.stdout)
                    ok = False
        return ok

    def close(self):
        self.f.close()


def standard_image(path):
    """The test fixture: two partitions, nested directories, long names,
    fragmented files, a SYSTEM file, many directory entries."""
    # 300 MB with 4 KB clusters (about 76k clusters), 40 MB with 512-byte
    # clusters (about 80k): both genuinely FAT32 by cluster count
    img = Image.create(path, size_mb=345, partitions=[(2048, 300, 8), (2048 + 300 * 2048, 40, 1)])
    v = img.volume(0)
    v.write_file("/README.TXT", b"Hello from the MEGA65 FAT32 engine test image.\n")
    v.mkdir("/GAMES")
    v.mkdir("/GAMES/Arcade Classics")
    v.write_file("/GAMES/Arcade Classics/Space Invaders Deluxe.d81",
                 b"".join(struct.pack("<I", (i * 2654435761 + 12345) & 0xFFFFFFFF) for i in range(204800)), fragments=4)
    v.write_file("/GAMES/SHORT.PRG", bytes(range(256)) * 3)
    v.mkdir("/MEGA65")
    v.write_file("/MEGA65/HICKUP.M65", b"system file" * 50, attr=0x24)
    v.mkdir("/LOTS")
    for i in range(70):
        v.write_file("/LOTS/file number %03d.txt" % i, ("file %d\n" % i).encode())
    v.mkdir("/UNICODE")
    v.write_file("/UNICODE/Grüße – ✓ 😀.txt", "Unicode name\n".encode())
    v.write_file("/UNICODE/" + "✓" * 100 + ".txt", b"a long UTF-8 name\n")
    v2 = img.volume(1)
    v2.write_file("/SECOND.TXT", b"second partition\n")
    assert img.check(), "fsck.fat failed"
    return img


if __name__ == "__main__":
    import sys
    path = sys.argv[1] if len(sys.argv) > 1 else "fat32test.img"
    img = standard_image(path)
    v = img.volume(0)
    for long, short, attr, first, size in v.listdir(v.root):
        print("%-30s %-12s %02x %8d %8d" % (long, short, attr, first, size))
    print("partitions:", img.partitions)
