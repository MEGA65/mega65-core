#!/usr/bin/env python3
"""Tests for netsd.py / netsd_vfat.py (SD card over Ethernet, #965).

    python3 src/tools/test_netsd.py [-v]

Needs fsck.fat (dosfstools).  The virtual card is checked against an
independent FAT32 reader and writer (fat32img.py): what the card serves must
be a clean volume holding the host files, and changes made to it with a
FAT32 writer must come back out on the host tree.
"""

import asyncio
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fat32img  # noqa: E402
import netsd  # noqa: E402
import netsd_vfat as vfat  # noqa: E402

SECTOR = 512
SIZE_MB = 48          # the system partition takes 11 MB; FAT32 needs >= 65525 clusters
SPC = 1


def make_tree(root):
    os.makedirs(os.path.join(root, "GAMES"))
    os.makedirs(os.path.join(root, "a long directory name", "nested"))
    os.makedirs(os.path.join(root, "empty"))
    files = {
        "MEGA65.D81": os.urandom(819200),
        "GAMES/ELITE.D81": os.urandom(100000),
        "a long directory name/Read Me.txt": b"hello\n",
        "a long directory name/nested/x.prg": os.urandom(1234),
        "zero.bin": b"",
        "lower.prg": os.urandom(513),
    }
    for i in range(40):                        # a directory over one cluster
        files["GAMES/game number %02d.prg" % i] = os.urandom(100 + i)
    for rel, data in files.items():
        with open(os.path.join(root, rel), "wb") as f:
            f.write(data)
    os.symlink("/etc/passwd", os.path.join(root, "passwd"))
    os.mkfifo(os.path.join(root, "fifo"))
    return files


def host_files(root):
    out = {}
    for d, dirs, names in os.walk(root):
        for n in names:
            p = os.path.join(d, n)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            with open(p, "rb") as f:
                out[os.path.relpath(p, root)] = f.read()
    return out


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="netsd-test-")
        self.root = os.path.join(self.tmp, "tree")
        os.makedirs(self.root)
        self.files = make_tree(self.root)
        self.logs = []

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def card(self, **kw):
        kw.setdefault("size_mb", SIZE_MB)
        kw.setdefault("spc", SPC)
        kw.setdefault("overlay_path", os.path.join(self.tmp, "overlay"))
        c = vfat.VirtualCard(self.root, log=self.logs.append, **kw)
        self.addCleanup(c.close)
        return c

    def dump(self, card, name="card.img"):
        path = os.path.join(self.tmp, name)
        vfat.dump(card, path)
        return path

    def volume(self, path):
        f = open(path, "r+b")
        self.addCleanup(f.close)
        return fat32img.Volume(f, vfat.FAT_START)


class TestImage(Base):
    def test_clean_volume_with_host_files(self):
        card = self.card()
        img = self.dump(card)
        part = os.path.join(self.tmp, "part.img")
        with open(img, "rb") as f, open(part, "wb") as g:
            f.seek(vfat.FAT_START * SECTOR)
            g.write(f.read(card.fat_sectors_total * SECTOR))
        r = subprocess.run(["fsck.fat", "-n", "-v", part], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn("Auto-", r.stdout)
        vol = self.volume(img)
        for rel, data in self.files.items():
            self.assertEqual(vol.read_file(rel), data, rel)
        names = [e[0] for e in vol.listdir(vol.root)]
        self.assertNotIn("passwd", names)
        self.assertNotIn("fifo", names)
        self.assertTrue(any("skipping" in m and "passwd" in m for m in self.logs))

    def test_mbr_and_system_partition(self):
        card = self.card()
        mbr = card.read_sector(0)
        self.assertEqual(mbr[510:], b"\x55\xaa")
        t1, s1, n1 = mbr[0x1C2], *struct.unpack_from("<II", mbr, 0x1C6)
        t2, s2, n2 = mbr[0x1D2], *struct.unpack_from("<II", mbr, 0x1D6)
        self.assertEqual((t1, s1), (0x0C, vfat.FAT_START))
        self.assertEqual(t2, 0x41)
        self.assertEqual(s1 + n1, s2)
        self.assertEqual(s2 + n2, card.total)
        hdr = card.read_sector(s2)
        self.assertEqual(hdr[:11], b"MEGA65SYS00")
        slots = struct.unpack_from("<H", hdr, 0x1C)[0]
        self.assertEqual(slots, 4)
        shared_start = struct.unpack_from("<I", hdr, 0x30)[0]
        freeze_end = 2048 + struct.unpack_from("<I", hdr, 0x14)[0]
        self.assertLessEqual(freeze_end, shared_start)
        self.assertEqual(card.read_sector(1), bytes(SECTOR))       # no config sector

    def test_short_names(self):
        used = set()
        self.assertEqual(vfat.make_short("MEGA65.D81", used), (b"MEGA65  D81", False))
        self.assertEqual(vfat.make_short("mega65.d81", used), (b"MEGA65~1D81", True))
        self.assertEqual(vfat.make_short("A long name.prg", used), (b"ALONGN~1PRG", True))
        self.assertEqual(vfat.make_short("A long nameX.prg", used), (b"ALONGN~2PRG", True))
        self.assertEqual(vfat.make_short(".hidden", used), (b"HIDDEN~1   ", True))

    def test_too_small(self):
        with self.assertRaises(vfat.CardError):
            self.card(size_mb=8)


class TestWrites(Base):
    def replay(self, card, before, after):
        """Write every sector that differs between two images to the card."""
        n = 0
        with open(before, "rb") as a, open(after, "rb") as b:
            lba = 0
            while True:
                x, y = a.read(SECTOR), b.read(SECTOR)
                if not x:
                    break
                if x != y:
                    card.write_sector(lba, y)
                    n += 1
                lba += 1
        return n

    def test_readonly(self):
        card = self.card()
        with self.assertRaises(PermissionError):
            card.write_sector(vfat.FAT_START + 100, bytes(SECTOR))
        card.write_sector(card.sys_start + 5000, b"\x5a" * SECTOR)  # freeze slot
        self.assertEqual(card.read_sector(card.sys_start + 5000), b"\x5a" * SECTOR)
        self.assertEqual(card.reconcile(), [])

    def test_write_back(self):
        card = self.card(writable=True)
        before = self.dump(card, "before.img")
        after = os.path.join(self.tmp, "after.img")
        shutil.copy(before, after)
        vol = self.volume(after)
        new_prg = os.urandom(5000)
        changed = os.urandom(100000)
        vol.mkdir("/NEWDIR")
        vol.write_file("/NEWDIR/NEW.PRG", new_prg, fragments=3)
        vol.write_file("/NEWDIR/A Long New Name.seq", b"long")
        # Overwrite ELITE.D81 in place, as a disk image write would
        attr, first, size = vol.lookup("/GAMES/ELITE.D81")
        for i, c in enumerate(vol.chain(first)):
            vol.write_sector(vol.cluster_lba(c), changed[i * 512:(i + 1) * 512].ljust(512, b"\0"))
        # Rename MEGA65.D81 -> RENAMED.D81 by its directory entry
        for raw, lba, off in vol.dir_entries(vol.root):
            if raw[:11] == b"MEGA65  D81":
                s = bytearray(vol.read_sector(lba))
                s[off:off + 11] = b"RENAMED D81"
                vol.write_sector(lba, bytes(s))
                break
        vol.f.flush()
        self.assertGreater(self.replay(card, before, after), 0)
        actions = card.reconcile()
        host = host_files(self.root)
        self.assertEqual(host["NEWDIR/NEW.PRG"], new_prg, actions)
        self.assertEqual(host["NEWDIR/A Long New Name.seq"], b"long")
        self.assertEqual(host["GAMES/ELITE.D81"][:100000], changed[:100000])
        self.assertEqual(host["RENAMED.D81"], self.files["MEGA65.D81"])
        self.assertNotIn("MEGA65.D81", host)
        self.assertNotIn(".netsd-tmp", " ".join(host))
        # The card still reads back the MEGA65's view
        vol2 = self.volume(self.dump(card, "again.img"))
        self.assertEqual(vol2.read_file("/NEWDIR/NEW.PRG"), new_prg)
        # Nothing more to do
        self.assertEqual(card.reconcile(), [])

    def test_delete_only_when_asked(self):
        for delete in (False, True):
            with self.subTest(delete=delete):
                card = self.card(writable=True, delete=delete,
                                 overlay_path=os.path.join(self.tmp, "ov%d" % delete))
                before = self.dump(card, "b%d.img" % delete)
                after = before + ".after"
                shutil.copy(before, after)
                vol = self.volume(after)
                slots = list(vol.dir_entries(vol.root))
                for i, (raw, lba, off) in enumerate(slots):
                    if raw[:11] == b"ZERO~1  BIN":
                        j = i
                        while True:          # the entry and its long name entries
                            _, l2, o2 = slots[j]
                            s = bytearray(vol.read_sector(l2))
                            s[o2] = 0xE5
                            vol.write_sector(l2, bytes(s))
                            j -= 1
                            if j < 0 or slots[j][0][11] != 0x0F:
                                break
                        break
                else:
                    self.fail("zero.bin's entry not found")
                vol.f.flush()
                self.replay(card, before, after)
                card.reconcile()
                self.assertEqual(os.path.exists(os.path.join(self.root, "zero.bin")), not delete)
                card.close()

    def put_root_entries(self, card, entries):
        """Write raw directory entries into the root directory's first free
        slots."""
        lba = vfat.FAT_START + card.data_start
        while True:
            s = bytearray(card.read_sector(lba))
            for off in range(0, SECTOR, 32):
                if s[off] == 0:
                    for e in entries:
                        s[off:off + 32] = e
                        off += 32
                    card.write_sector(lba, bytes(s))
                    return
            lba += 1

    def test_hostile_entries(self):
        card = self.card(writable=True)
        outside = os.path.join(self.tmp, "outside")
        os.makedirs(outside)
        # A symlinked directory planted on the host after the scan
        os.symlink(outside, os.path.join(self.root, "TRAP"))
        free = card.next_free + 10
        # Mark a cluster used so the entries have something to point at
        fat_lba = vfat.FAT_START + vfat.RESERVED + free // 128
        s = bytearray(card.read_sector(fat_lba))
        struct.pack_into("<I", s, (free % 128) * 4, vfat.EOC)
        card.write_sector(fat_lba, bytes(s))
        bad_lfn = vfat.lfn_entries("../../evil", b"EVIL       ")
        entries = [
            vfat.dir_entry(b"TRAP       ", 0x10, free, 0),             # dir over the symlink
            vfat.dir_entry(b"A/B     PRG", 0x20, free, 10),            # slash in a short name
        ] + bad_lfn + [vfat.dir_entry(b"EVIL       ", 0x20, free, 10)]
        self.put_root_entries(card, entries)
        # TRAP's directory holds a file, which must not land in outside/
        cl = vfat.FAT_START + card.data_start + (free - 2) * card.spc
        card.write_sector(cl, vfat.dir_entry(b"PWNED   TXT", 0x20, free, 10) + bytes(480))
        card.reconcile()
        self.assertEqual(os.listdir(outside), [])
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "evil")))
        self.assertTrue(os.path.islink(os.path.join(self.root, "TRAP")))
        self.assertTrue(any("not a valid name" in m for m in self.logs))

    def test_fat_loop(self):
        card = self.card(writable=True)
        c = card.next_free + 5
        fat_lba = vfat.FAT_START + vfat.RESERVED + c // 128
        s = bytearray(card.read_sector(fat_lba))
        struct.pack_into("<I", s, (c % 128) * 4, c)                   # points at itself
        card.write_sector(fat_lba, bytes(s))
        self.put_root_entries(card, [vfat.dir_entry(b"LOOP       ", 0x10, c, 0),
                                     vfat.dir_entry(b"BIG     BIN", 0x20, c, 1 << 20)])
        card.write_sector(vfat.FAT_START + card.data_start + (c - 2) * card.spc,
                          vfat.dir_entry(b"LOOP       ", 0x10, c, 0) + bytes(480))
        card.reconcile()                    # must finish
        self.assertEqual(os.path.getsize(os.path.join(self.root, "BIG.BIN")), 1 << 20)


class TestServer(Base):
    def run_session(self, fn, write=False):
        args = types.SimpleNamespace(
            subnet="127.0.0.0/8", server_ip="127.0.0.1", client=[], default=self.root,
            write=write, delete=False, size=SIZE_MB, spc=SPC, sys_slots=4, quiet=0.1,
            state_dir=os.path.join(self.tmp, "state"))

        async def go():
            loop = asyncio.get_running_loop()
            transport, server = await loop.create_datagram_endpoint(
                lambda: netsd.Server(args, self.logs.append), local_addr=("127.0.0.1", 0))
            port = transport.get_extra_info("sockname")[1]
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.bind(("127.0.0.1", 0))
            sock.setblocking(False)

            async def xfer(frame, n=1):
                await loop.sock_sendto(sock, frame, ("127.0.0.1", port))
                out = []
                for _ in range(n):
                    out.append(await asyncio.wait_for(loop.sock_recv(sock, 2048), 2))
                return out

            try:
                await fn(xfer, server)
            finally:
                for c in server.clients.values():
                    c.card.close()
                transport.close()
                sock.close()
        asyncio.run(go())

    def test_hello_read_write(self):
        mac = bytes.fromhex("024753656566")

        async def fn(xfer, server):
            sess = 0x12345678
            (r,) = await xfer(netsd.header(0, netsd.OP_HELLO, sess, 1, 0)
                              + mac + bytes([0, 0]) + os.urandom(8))
            flags, op, s, seq, lba, p = netsd.parse(r)
            self.assertEqual((flags, op, s, seq), (netsd.F_RESPONSE, netsd.OP_HELLO, sess, 1))
            total, writable, maxread = struct.unpack_from("<IBB", p, 8)
            card = server.clients[mac].card
            self.assertEqual((total, writable, maxread), (card.total, 0, 8))
            self.assertEqual(p[24:30], mac)
            # An 8-sector read across the boot sector and FSInfo
            frames = await xfer(netsd.header(0, netsd.OP_READ, sess, 2, vfat.FAT_START)
                                + bytes([8]) + bytes(15), 8)
            for i, f in enumerate(frames):
                flags, op, s, seq, lba, p = netsd.parse(f)
                self.assertEqual((op, seq, lba), (netsd.OP_READ, 2, vfat.FAT_START + i))
                self.assertEqual(p, card.read_sector(lba))
            # Read-only: a FAT32 write is refused, a system partition write isn't
            (r,) = await xfer(netsd.header(0, netsd.OP_WRITE, sess, 3, vfat.FAT_START + 600)
                              + bytes(512))
            self.assertEqual(netsd.parse(r)[5][0], netsd.ST_READONLY)
            (r,) = await xfer(netsd.header(0, netsd.OP_WRITE, sess, 4, card.sys_start + 3000)
                              + b"\xaa" * 512)
            self.assertEqual(netsd.parse(r)[5][0], netsd.ST_OK)
            # A repeated write is answered, not applied again
            (r2,) = await xfer(netsd.header(0, netsd.OP_WRITE, sess, 4, card.sys_start + 3000)
                               + b"\xaa" * 512)
            self.assertEqual(r, r2)
            self.assertEqual(server.stats["writes"], 1)
            # Wrong session, out of range, bad count, auth flag
            (r,) = await xfer(netsd.header(0, netsd.OP_READ, sess + 1, 5, 0) + bytes([1]) + bytes(15))
            self.assertEqual(netsd.parse(r)[1:2] + (netsd.parse(r)[5][0],), (netsd.OP_NAK, netsd.ST_SESSION))
            (r,) = await xfer(netsd.header(0, netsd.OP_READ, sess, 6, card.total - 2) + bytes([4]) + bytes(15))
            self.assertEqual(netsd.parse(r)[5][0], netsd.ST_RANGE)
            (r,) = await xfer(netsd.header(0, netsd.OP_READ, sess, 7, 0) + bytes([9]) + bytes(15))
            self.assertEqual(netsd.parse(r)[5][0], netsd.ST_BAD)
            (r,) = await xfer(netsd.header(netsd.F_AUTH, netsd.OP_READ, sess, 8, 0) + bytes(32))
            self.assertEqual(netsd.parse(r)[5][0], netsd.ST_AUTH)
            # Junk is ignored, and the server keeps going
            await xfer(b"not a frame", 0)
            (r,) = await xfer(netsd.header(0, netsd.OP_READ, sess, 9, 0) + bytes([1]) + bytes(15))
            self.assertEqual(netsd.parse(r)[5], card.read_sector(0))
        self.run_session(fn)

    def test_write_mode(self):
        mac = bytes.fromhex("024753656567")

        async def fn(xfer, server):
            sess = 7
            await xfer(netsd.header(0, netsd.OP_HELLO, sess, 1, 0) + mac + bytes(10))
            card = server.clients[mac].card
            # Overwrite the first sector of lower.prg
            attr_first = [n for n in vfat.walk(card.tree) if n.name == "lower.prg"][0].first
            lba = vfat.FAT_START + card.data_start + (attr_first - 2) * card.spc
            (r,) = await xfer(netsd.header(0, netsd.OP_WRITE, sess, 2, lba) + b"\x42" * 512)
            self.assertEqual(netsd.parse(r)[5][0], netsd.ST_OK)
            await asyncio.sleep(0.6)
            with open(os.path.join(self.root, "lower.prg"), "rb") as f:
                data = f.read()
            self.assertEqual(data[:512], b"\x42" * 512)
            self.assertEqual(data[512:], self.files["lower.prg"][512:])

        async def with_housekeeping(xfer, server):
            task = asyncio.ensure_future(server.housekeeping())
            try:
                await fn(xfer, server)
            finally:
                task.cancel()
        self.run_session(with_housekeeping, write=True)


if __name__ == "__main__":
    unittest.main()
