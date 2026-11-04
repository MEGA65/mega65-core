#!/usr/bin/env python3
"""Virtual SD card for SD-over-Ethernet (MEGA65/mega65-core#965).

A VirtualCard presents a host directory tree as a whole SD card:

    LBA 0           MBR: partition 1 FAT32 (0x0C), partition 2 MEGA65 system (0x41)
    LBA 1           config sector: always zeros (Hyppo has already read the
                    real card's)
    LBA 2048 ...    FAT32 partition, generated sector by sector on demand
    end of card     MEGA65 system partition: a valid MEGA65SYS00 header,
                    everything else zero until written

Nothing is generated up front except the cluster allocation: each host
directory and file gets a contiguous run of clusters, in tree order.  Boot
sector, FSInfo, FAT sectors and directory clusters are built when read, file
data is read from the host file when read.

Writes go to a per-card overlay (a sparse file), so the MEGA65 always reads
back what it wrote.  Writes into the system partition are always allowed
(the freezer writes there) and never reach the host tree.  Writes into the
FAT32 partition are refused unless the card is writable; when it is,
reconcile() parses the FAT32 volume as the MEGA65 left it and applies new
directories, new and changed files and renames to the host tree (deletes only
if asked), through directory file descriptors, so nothing can land outside
the root.

The MEGA65 never sends names for reads, only sector numbers, and host files
are only ever opened from the card's own scan.  Names that come from the
MEGA65's directory entries are checked before they touch the host.
"""

import bisect
import errno
import os
import stat
import struct
import time

SECTOR = 512
EOC = 0x0FFFFFFF
FAT_START = 2048                 # first FAT32 partition sector (1 MiB aligned)
RESERVED = 568                   # FAT32 reserved sectors, as FDISK makes them
NUM_FATS = 2
MIN_CLUSTERS = 65525
MAX_CLUSTERS = 0x0FFFFFF5 - 2
MAX_DIR_ENTRIES = 65536          # FAT limit: 2 MB of directory
SYS_MAGIC = b"MEGA65SYS00"

ZERO = bytes(SECTOR)

# Characters FAT allows in a short name besides A-Z and 0-9
SHORT_EXTRA = set("!#$%&'()-@^_`{}~")
# Characters FAT never allows in a long name
LFN_BAD = set('\\/:*?"<>|')


class CardError(Exception):
    pass


# --------------------------------------------------------------------------
# Names
# --------------------------------------------------------------------------

def lfn_checksum(name11):
    s = 0
    for c in name11:
        s = (((s & 1) << 7) + (s >> 1) + c) & 0xFF
    return s


def valid_long_name(name):
    """Whether name may be a FAT long name (and so a host name we serve or
    accept from the MEGA65)."""
    if not name or name in (".", "..") or len(name) > 255:
        return False
    if name[-1] in ". ":
        return False
    for ch in name:
        if ord(ch) < 0x20 or ch in LFN_BAD or 0xD800 <= ord(ch) <= 0xDFFF:
            return False
    try:
        if len(name.encode("utf-16-le")) > 510:
            return False
    except UnicodeEncodeError:
        return False
    return True


def _short_char(ch):
    if ("A" <= ch <= "Z") or ("0" <= ch <= "9") or ch in SHORT_EXTRA:
        return ch
    return "_"


def plain_83(name):
    """name packed as 11 bytes if it is already an upper-case 8.3 name that
    needs no long name, else None"""
    if name != name.upper():
        return None
    base, dot, ext = name.partition(".")
    if dot and "." in ext:
        return None
    if not base or len(base) > 8 or len(ext) > 3:
        return None
    for ch in base + ext:
        if _short_char(ch) != ch:
            return None
    return (base.ljust(8) + ext.ljust(3)).encode("ascii")


def make_short(name, used):
    """An 11-byte short name for name, unique in used (a set of 11-byte
    names, which this adds to); and whether a long name is needed."""
    packed = plain_83(name)
    if packed is not None and packed not in used:
        used.add(packed)
        return packed, False
    if name.startswith("."):
        base, ext = name.lstrip("."), ""
    else:
        base, _, ext = name.rpartition(".") if "." in name else (name, "", "")
    clean = lambda s: "".join(_short_char(c) for c in s.upper() if c not in " .")
    b = clean(base) or "_"
    e = clean(ext)[:3]
    for n in range(1, 1000000):
        tail = "~%d" % n
        cand = (b[:8 - len(tail)] + tail).ljust(8) + e.ljust(3)
        packed = cand.encode("ascii")
        if packed not in used:
            used.add(packed)
            return packed, True
    raise CardError("no short name left for %r" % name)


def short_to_name(raw, case_flags=0):
    base = raw[:8].decode("latin-1").rstrip()
    ext = raw[8:11].decode("latin-1").rstrip()
    if base and base[0] == "\x05":
        base = "\xe5" + base[1:]
    if case_flags & 0x08:
        base = base.lower()
    if case_flags & 0x10:
        ext = ext.lower()
    return base + ("." + ext if ext else "")


def fat_datetime(t):
    lt = time.localtime(t)
    year = min(max(lt.tm_year, 1980), 2107)
    date = ((year - 1980) << 9) | (lt.tm_mon << 5) | lt.tm_mday
    tod = (lt.tm_hour << 11) | (lt.tm_min << 5) | (lt.tm_sec // 2)
    return date, tod


def dir_entry(name11, attr, first, size, mtime=None):
    date, tod = fat_datetime(mtime if mtime is not None else time.time())
    return struct.pack("<11sBBBHHHHHHHI", name11, attr, 0, 0, tod, date, date,
                       first >> 16, tod, date, first & 0xFFFF, size)


def lfn_entries(name, name11):
    """The long name entries for name, in on-disk order (last part first)"""
    units = list(struct.unpack("<%dH" % (len(name.encode("utf-16-le")) // 2),
                               name.encode("utf-16-le")))
    parts = [units[i:i + 13] for i in range(0, len(units), 13)]
    if len(parts[-1]) < 13:
        parts[-1] = parts[-1] + [0] + [0xFFFF] * (12 - len(parts[-1]))
    csum = lfn_checksum(name11)
    out = []
    for seq in range(len(parts), 0, -1):
        u = parts[seq - 1]
        order = seq | (0x40 if seq == len(parts) else 0)
        out.append(struct.pack("<B5HBBB6HH2H", order, *u[0:5], 0x0F, 0, csum,
                               *u[5:11], 0, *u[11:13]))
    return out


# --------------------------------------------------------------------------
# Host tree
# --------------------------------------------------------------------------

class Node:
    __slots__ = ("name", "rel", "is_dir", "size", "mtime", "children",
                 "parent", "first", "nclusters", "short", "need_lfn", "blob")

    def __init__(self, name, rel, is_dir, size=0, mtime=0.0, parent=None):
        self.name = name
        self.rel = rel                # tuple of path components from the root
        self.is_dir = is_dir
        self.size = size
        self.mtime = mtime
        self.children = []
        self.parent = parent
        self.first = 0
        self.nclusters = 0
        self.short = None
        self.need_lfn = False
        self.blob = None              # directory contents, built on demand


def scan_tree(root, log=None, max_files=1000000):
    """Scan root into a Node tree.  Only regular files and directories are
    taken; symlinks, devices, FIFOs and sockets are skipped, as are names FAT
    can't hold and names that collide with another ignoring case."""
    log = log or (lambda msg: None)
    rootnode = Node("", (), True, mtime=os.stat(root).st_mtime)
    count = 0
    stack = [(rootnode, root)]
    while stack:
        node, path = stack.pop()
        try:
            entries = sorted(os.scandir(path), key=lambda e: (e.name.upper(), e.name))
        except OSError as ex:
            log("skipping directory %s: %s" % (path, ex))
            continue
        seen = set()
        for e in entries:
            if not valid_long_name(e.name):
                log("skipping %r: not a valid FAT name" % os.path.join(path, e.name))
                continue
            if e.name.upper() in seen:
                log("skipping %r: differs from another name only in case"
                    % os.path.join(path, e.name))
                continue
            try:
                st = e.stat(follow_symlinks=False)
            except OSError as ex:
                log("skipping %s: %s" % (e.path, ex))
                continue
            if stat.S_ISDIR(st.st_mode):
                child = Node(e.name, node.rel + (e.name,), True, mtime=st.st_mtime, parent=node)
                stack.append((child, e.path))
            elif stat.S_ISREG(st.st_mode):
                if st.st_size > 0xFFFFFFFF:
                    log("skipping %s: larger than 4 GB" % e.path)
                    continue
                child = Node(e.name, node.rel + (e.name,), False, size=st.st_size,
                             mtime=st.st_mtime, parent=node)
            else:
                log("skipping %s: not a regular file or directory" % e.path)
                continue
            seen.add(e.name.upper())
            node.children.append(child)
            count += 1
            if count > max_files:
                raise CardError("more than %d files under %s" % (max_files, root))
        if len(node.children) * 21 + 2 > MAX_DIR_ENTRIES:
            raise CardError("too many entries in %s" % path)
    return rootnode


def walk(node):
    yield node
    for c in node.children:
        if c.is_dir:
            yield from walk(c)
        else:
            yield c


# --------------------------------------------------------------------------
# Overlay of written sectors
# --------------------------------------------------------------------------

class Overlay:
    """Written sectors, kept in a sparse file so that large writes (freeze
    slots, big files) don't sit in memory."""

    def __init__(self, path):
        self.path = path
        self.f = open(path, "w+b")
        self.written = set()

    def get(self, lba):
        if lba not in self.written:
            return None
        self.f.seek(lba * SECTOR)
        return self.f.read(SECTOR)

    def put(self, lba, data):
        self.f.seek(lba * SECTOR)
        self.f.write(data)
        self.written.add(lba)

    def close(self):
        self.f.close()
        try:
            os.unlink(self.path)
        except OSError:
            pass


# --------------------------------------------------------------------------
# The card
# --------------------------------------------------------------------------

class VirtualCard:
    def __init__(self, root, size_mb=4096, spc=8, sys_slots=4, writable=False,
                 delete=False, overlay_path=None, log=None, volume_id=None):
        self.root = os.path.abspath(root)
        self.log = log or (lambda msg: None)
        self.writable = writable
        self.delete = delete
        self.spc = spc
        self.cluster_bytes = spc * SECTOR

        # System partition, sized as FDISK sizes it for sys_slots slots:
        # 1 MB reserved, then sys_slots freeze and service slots of 512 KB
        # plus their directories, then as much again for shared resources.
        self.slot_sectors = 1024
        self.sys_slots = sys_slots
        self.dir_sectors = (sys_slots >> 2) + 1
        shared = 2048 + sys_slots * (2 * self.slot_sectors + 1)
        self.sys_sectors = ((2 * shared) + 2047) & ~2047
        self.total = (size_mb * 1024 * 1024) // SECTOR
        self.fat_sectors_total = self.total - FAT_START - self.sys_sectors
        self.sys_start = FAT_START + self.fat_sectors_total
        if self.fat_sectors_total <= RESERVED + 2:
            raise CardError("card too small")

        # FAT32 geometry, as FDISK works it out
        avail = self.fat_sectors_total - RESERVED
        clusters = avail // spc
        while True:
            fatsz = (clusters + 2 + 127) // 128
            if NUM_FATS * fatsz + clusters * spc <= avail:
                break
            clusters -= 1
        if not (MIN_CLUSTERS <= clusters <= MAX_CLUSTERS):
            raise CardError("%d clusters is not a FAT32 volume: change --size or --spc" % clusters)
        self.clusters = clusters
        self.fatsz = fatsz
        self.data_start = RESERVED + NUM_FATS * fatsz          # partition-relative
        self.volume_id = volume_id if volume_id is not None else (int(time.time()) & 0xFFFFFFFF)

        self.tree = scan_tree(self.root, self.log)
        self._allocate()
        self.overlay = Overlay(overlay_path) if overlay_path else None
        self._overlay_tmp = None
        if self.overlay is None:
            import tempfile
            fd, p = tempfile.mkstemp(prefix="netsd-overlay-")
            os.close(fd)
            self.overlay = Overlay(p)
        self.dirty = set()
        self.fds = {}
        self.model = None             # last reconciled view of the volume
        if writable:
            self.model = self.parse_volume(base_only=True)

    # ---- allocation --------------------------------------------------------

    def _allocate(self):
        """Give every directory and file a contiguous cluster run, in tree
        order, and short names."""
        nxt = 2
        self.extents = []         # sorted (first cluster, count, node)

        def place(node, n):
            nonlocal nxt
            node.first, node.nclusters = nxt, n
            self.extents.append((nxt, n, node))
            nxt += n

        def dir_entries_needed(node):
            used = set()
            n = 0 if not node.rel else 2
            for c in node.children:
                c.short, c.need_lfn = make_short(c.name, used)
                n += 1 + (((len(c.name.encode("utf-16-le")) // 2) + 12) // 13 if c.need_lfn else 0)
            return n

        stack = [self.tree]
        while stack:
            d = stack.pop(0)
            nent = dir_entries_needed(d)
            if nent > MAX_DIR_ENTRIES:
                raise CardError("directory %s has too many entries" % "/".join(d.rel))
            place(d, max(1, (nent * 32 + self.cluster_bytes - 1) // self.cluster_bytes))
            for c in d.children:
                if c.is_dir:
                    stack.append(c)
                elif c.size:
                    place(c, (c.size + self.cluster_bytes - 1) // self.cluster_bytes)
            if nxt - 2 > self.clusters:
                raise CardError("host tree does not fit in a %d MB card" % (self.total // 2048))
        self.next_free = nxt
        self.used_clusters = nxt - 2
        self.ext_starts = [e[0] for e in self.extents]

    def _extent(self, cluster):
        i = bisect.bisect_right(self.ext_starts, cluster) - 1
        if i >= 0:
            first, n, node = self.extents[i]
            if cluster < first + n:
                return first, n, node
        return None

    # ---- generated sectors ---------------------------------------------------

    def _mbr(self):
        s = bytearray(SECTOR)

        def part(off, ptype, start, count):
            s[off:off + 16] = struct.pack("<B3sB3sII", 0x00, b"\xfe\xff\xff", ptype,
                                          b"\xfe\xff\xff", start, count)
        part(0x1BE, 0x0C, FAT_START, self.fat_sectors_total)
        part(0x1CE, 0x41, self.sys_start, self.sys_sectors)
        s[0x1B8:0x1BC] = struct.pack("<I", self.volume_id)
        s[510:512] = b"\x55\xaa"
        return bytes(s)

    def _boot(self):
        s = bytearray(SECTOR)
        s[0:3] = b"\xeb\x58\x90"
        s[3:11] = b"MEGA65r1"
        struct.pack_into("<HBHBHHBHHHII", s, 11, SECTOR, self.spc, RESERVED, NUM_FATS,
                         0, 0, 0xF8, 0, 0, 0, FAT_START, self.fat_sectors_total)
        struct.pack_into("<IHHIHH", s, 0x24, self.fatsz, 0, 0, 2, 1, 6)
        s[0x40] = 0x80
        s[0x42] = 0x29
        struct.pack_into("<I", s, 0x43, self.volume_id)
        s[0x47:0x52] = b"NO NAME    "
        s[0x52:0x5A] = b"FAT32   "
        s[510:512] = b"\x55\xaa"
        return bytes(s)

    def _fsinfo(self):
        s = bytearray(SECTOR)
        s[0:4] = b"RRaA"
        s[484:488] = b"rrAa"
        free = self.clusters - self.used_clusters
        struct.pack_into("<II", s, 488, free, self.next_free)
        s[508:512] = b"\x00\x00\x55\xaa"
        return bytes(s)

    def _sys_header(self):
        s = bytearray(SECTOR)
        s[0:11] = SYS_MAGIC
        n, slot, d = self.sys_slots, self.slot_sectors, self.dir_sectors
        area = slot * n + d
        shared = self.sys_sectors >> 1
        struct.pack_into("<IIIHH", s, 0x10, 0, area, slot, n, d)
        struct.pack_into("<IIIHH", s, 0x20, area, area, slot, n, d)
        struct.pack_into("<II", s, 0x30, shared, shared)
        return bytes(s)

    def _fat_sector(self, k):
        base = k * 128
        vals = [0] * 128
        c = base
        while c < base + 128:
            if c < 2:
                vals[c - base] = 0x0FFFFFF8 if c == 0 else EOC
                c += 1
                continue
            if c >= self.clusters + 2:
                break
            ext = self._extent(c)
            if ext is None:
                i = bisect.bisect_right(self.ext_starts, c)
                stop = self.ext_starts[i] if i < len(self.ext_starts) else base + 128
                c = min(stop, base + 128)
                continue
            first, n, _ = ext
            end = min(first + n, base + 128)
            for cc in range(c, end):
                vals[cc - base] = cc + 1 if cc + 1 < first + n else EOC
            c = end
        return struct.pack("<128I", *vals)

    def _dir_blob(self, node):
        if node.blob is None:
            out = bytearray()
            if node.rel:
                parent = node.parent.first if node.parent.rel else 0
                out += dir_entry(b".          ", 0x10, node.first, 0, node.mtime)
                out += dir_entry(b"..         ", 0x10, parent, 0, node.mtime)
            for c in node.children:
                if c.need_lfn:
                    for e in lfn_entries(c.name, c.short):
                        out += e
                out += dir_entry(c.short, 0x10 if c.is_dir else 0x20,
                                 c.first, 0 if c.is_dir else c.size, c.mtime)
            out += bytes(node.nclusters * self.cluster_bytes - len(out))
            node.blob = bytes(out)
        return node.blob

    def _file_fd(self, node):
        fd = self.fds.get(id(node))
        if fd is None:
            if len(self.fds) >= 64:
                for f in self.fds.values():
                    os.close(f)
                self.fds.clear()
            fd = open_in_root(self.root, node.rel)
            self.fds[id(node)] = fd
        return fd

    def _data_sector(self, rel):
        idx = rel - self.data_start
        cluster = idx // self.spc + 2
        if cluster >= self.clusters + 2:
            return ZERO
        ext = self._extent(cluster)
        if ext is None:
            return ZERO
        first, n, node = ext
        off = ((cluster - first) * self.spc + idx % self.spc) * SECTOR
        if node.is_dir:
            return self._dir_blob(node)[off:off + SECTOR]
        try:
            data = os.pread(self._file_fd(node), SECTOR, off)
        except OSError as ex:
            self.log("read %s: %s" % ("/".join(node.rel), ex))
            raise CardError("host read failed")
        return data + bytes(SECTOR - len(data))

    def base_sector(self, lba):
        """The sector as generated from the host tree, ignoring writes."""
        if lba == 0:
            return self._mbr()
        if FAT_START <= lba < self.sys_start:
            rel = lba - FAT_START
            if rel in (0, 6):
                return self._boot()
            if rel in (1, 7):
                return self._fsinfo()
            if rel == 2 or rel == 8:
                return ZERO[:510] + b"\x55\xaa"
            if rel < RESERVED:
                return ZERO
            if rel < self.data_start:
                return self._fat_sector((rel - RESERVED) % self.fatsz)
            return self._data_sector(rel)
        if lba == self.sys_start:
            return self._sys_header()
        return ZERO

    # ---- block device interface -------------------------------------------

    def read_sector(self, lba):
        if not 0 <= lba < self.total:
            raise CardError("sector %d out of range" % lba)
        data = self.overlay.get(lba)
        return data if data is not None else self.base_sector(lba)

    def in_sys(self, lba):
        return self.sys_start <= lba < self.total

    def write_allowed(self, lba):
        return 0 <= lba < self.total and (self.in_sys(lba) or self.writable)

    def write_sector(self, lba, data):
        if len(data) != SECTOR:
            raise CardError("bad sector length")
        if not 0 <= lba < self.total:
            raise CardError("sector %d out of range" % lba)
        if not self.write_allowed(lba):
            raise PermissionError("card is read-only")
        self.overlay.put(lba, data)
        if FAT_START <= lba < self.sys_start:
            self.dirty.add(lba)

    def close(self):
        for fd in self.fds.values():
            os.close(fd)
        self.fds.clear()
        self.overlay.close()

    # ---- reading the volume back ---------------------------------------------

    def parse_volume(self, base_only=False):
        """{path tuple: (is_dir, first cluster, size, chain)} for the FAT32
        volume as it now stands (or as generated, with base_only)."""
        rd = self.base_sector if base_only else self.read_sector
        fat_cache = {}

        def fat(c):
            k = c // 128
            if k not in fat_cache:
                fat_cache[k] = rd(FAT_START + RESERVED + k)
            return struct.unpack_from("<I", fat_cache[k], (c % 128) * 4)[0] & 0x0FFFFFFF

        def chain(c, limit):
            out, seen = [], set()
            while 2 <= c < self.clusters + 2 and c not in seen and len(out) < limit:
                seen.add(c)
                out.append(c)
                c = fat(c)
            return out

        def cluster_bytes(c):
            lba = FAT_START + self.data_start + (c - 2) * self.spc
            return b"".join(rd(lba + i) for i in range(self.spc))

        tree = {(): (True, 2, 0, None)}
        visited = set()
        todo = [((), 2)]
        while todo:
            path, first = todo.pop()
            if first in visited:
                continue
            visited.add(first)
            raw = b"".join(cluster_bytes(c) for c in chain(first, MAX_DIR_ENTRIES * 32 // self.cluster_bytes))
            lfn = {}
            lfn_sum = None
            names_here = set()
            for off in range(0, len(raw), 32):
                e = raw[off:off + 32]
                if e[0] == 0:
                    break
                if e[0] == 0xE5:
                    lfn, lfn_sum = {}, None
                    continue
                attr = e[11]
                if attr == 0x0F:
                    seq = e[0] & 0x1F
                    if e[0] & 0x40:
                        lfn, lfn_sum = {}, e[13]
                    if e[13] != lfn_sum or not 1 <= seq <= 20:
                        lfn, lfn_sum = {}, None
                        continue
                    u = struct.unpack_from("<5H", e, 1) + struct.unpack_from("<6H", e, 14) \
                        + struct.unpack_from("<2H", e, 28)
                    lfn[seq] = u
                    continue
                if attr & 0x08:
                    lfn, lfn_sum = {}, None
                    continue
                name11 = e[0:11]
                name = None
                if lfn and lfn_sum == lfn_checksum(name11) and sorted(lfn) == list(range(1, len(lfn) + 1)):
                    units = []
                    for s in range(1, len(lfn) + 1):
                        units.extend(lfn[s])
                    if 0 in units:
                        units = units[:units.index(0)]
                    try:
                        name = struct.pack("<%dH" % len(units), *units).decode("utf-16-le")
                    except (UnicodeDecodeError, struct.error):
                        name = None
                lfn, lfn_sum = {}, None
                if name is None:
                    name = short_to_name(name11, e[12])
                if name in (".", ".."):
                    continue
                if not valid_long_name(name):
                    self.log("ignoring entry %r in /%s: not a valid name" % (name, "/".join(path)))
                    continue
                first_c = (struct.unpack_from("<H", e, 20)[0] << 16) | struct.unpack_from("<H", e, 26)[0]
                size = struct.unpack_from("<I", e, 28)[0]
                p = path + (name,)
                if name.upper() in names_here:
                    self.log("ignoring duplicate entry %r in /%s" % (name, "/".join(path)))
                    continue
                names_here.add(name.upper())
                if attr & 0x10:
                    tree[p] = (True, first_c, 0, None)
                    if first_c >= 2:
                        todo.append((p, first_c))
                else:
                    need = (size + self.cluster_bytes - 1) // self.cluster_bytes
                    ch = chain(first_c, need) if size else []
                    tree[p] = (False, first_c, size, ch)
        self._cluster_reader = cluster_bytes
        return tree

    # ---- applying the MEGA65's changes to the host -------------------------

    def reconcile(self):
        """Apply the MEGA65's changes since the last call to the host tree.
        Returns a list of the actions taken (for logging)."""
        if not self.writable or not self.dirty:
            return []
        dirty_clusters = set()
        for lba in self.dirty:
            rel = lba - FAT_START - self.data_start
            if rel >= 0:
                dirty_clusters.add(rel // self.spc + 2)
        self.dirty = set()
        new = self.parse_volume()
        read_cluster = self._cluster_reader
        old = dict(self.model)
        actions = []
        host = SafeRoot(self.root)
        try:
            # Renames and moves: the same first cluster under another path
            by_first = {v[1]: k for k, v in old.items() if v[1] >= 2 and k}
            for p in sorted(new, key=len):
                if not p or p in old:
                    continue
                q = by_first.get(new[p][1])
                if q is None or q in new or q not in old or old[q][0] != new[p][0]:
                    continue
                try:
                    host.rename(q, p)
                    actions.append("rename /%s -> /%s" % ("/".join(q), "/".join(p)))
                except OSError as ex:
                    actions.append("rename /%s -> /%s failed: %s" % ("/".join(q), "/".join(p), ex))
                    continue
                for k in [k for k in old if k[:len(q)] == q]:
                    old[p + k[len(q):]] = old.pop(k)
                by_first = {v[1]: k for k, v in old.items() if v[1] >= 2 and k}
            # New directories
            for p in sorted((p for p in new if p and new[p][0] and p not in old), key=len):
                try:
                    host.mkdir(p)
                    actions.append("mkdir /%s" % "/".join(p))
                except OSError as ex:
                    actions.append("mkdir /%s failed: %s" % ("/".join(p), ex))
            # New and changed files
            for p, (is_dir, first, size, ch) in sorted(new.items()):
                if is_dir:
                    continue
                o = old.get(p)
                changed = (o is None or o[0] or o[1] != first or o[2] != size
                           or any(c in dirty_clusters for c in ch))
                if not changed:
                    continue
                try:
                    in_the_way = o is None and host.exists_unknown(p, old)
                except OSError as ex:
                    actions.append("not writing /%s: %s" % ("/".join(p), ex))
                    continue
                if in_the_way:
                    actions.append("not writing /%s: a host file the card doesn't know is in the way"
                                   % "/".join(p))
                    continue

                def chunks():
                    left = size
                    for c in ch:
                        b = read_cluster(c)
                        yield b[:left]
                        left -= len(b[:left])
                        if left <= 0:
                            break
                    if left > 0:
                        yield bytes(left)
                try:
                    host.write_file(p, chunks())
                    actions.append("write /%s (%d bytes)" % ("/".join(p), size))
                except OSError as ex:
                    actions.append("write /%s failed: %s" % ("/".join(p), ex))
            # Deletions
            gone = [p for p in old if p and p not in new]
            for p in sorted(gone, key=len, reverse=True):
                if not self.delete:
                    actions.append("not deleting /%s (no --delete)" % "/".join(p))
                    continue
                try:
                    host.remove(p, old[p][0])
                    actions.append("delete /%s" % "/".join(p))
                except OSError as ex:
                    actions.append("delete /%s failed: %s" % ("/".join(p), ex))
        finally:
            host.close()
        self.model = new
        for a in actions:
            self.log(a)
        return actions


# --------------------------------------------------------------------------
# Host access confined to the root
# --------------------------------------------------------------------------

def _check_parts(rel):
    for part in rel:
        if not valid_long_name(part) or "/" in part or "\0" in part:
            raise PermissionError(errno.EPERM, "unsafe name %r" % (part,))


def open_in_root(root, rel):
    """Open root/rel read-only without following any symlink on the way."""
    _check_parts(rel)
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in rel[:-1]:
            nfd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = nfd
        f = os.open(rel[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        if not stat.S_ISREG(os.fstat(f).st_mode):
            os.close(f)
            raise PermissionError(errno.EPERM, "not a regular file")
        return f
    finally:
        os.close(fd)


class SafeRoot:
    """Changes to the host tree, every path walked from the root through
    directory fds with O_NOFOLLOW, so a symlink can't lead outside it."""

    def __init__(self, root):
        self.rootfd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)

    def close(self):
        os.close(self.rootfd)

    def _dir(self, rel):
        _check_parts(rel)
        fd = os.dup(self.rootfd)
        for part in rel:
            try:
                nfd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            finally:
                os.close(fd)
            fd = nfd
        return fd

    def _lstat(self, dfd, name):
        try:
            return os.stat(name, dir_fd=dfd, follow_symlinks=False)
        except FileNotFoundError:
            return None

    def exists_unknown(self, rel, known):
        dfd = self._dir(rel[:-1])
        try:
            return self._lstat(dfd, rel[-1]) is not None and rel not in known
        finally:
            os.close(dfd)

    def mkdir(self, rel):
        _check_parts(rel)
        dfd = self._dir(rel[:-1])
        try:
            st = self._lstat(dfd, rel[-1])
            if st is not None:
                if stat.S_ISDIR(st.st_mode):
                    return
                raise FileExistsError(errno.EEXIST, "exists and is not a directory")
            os.mkdir(rel[-1], 0o755, dir_fd=dfd)
        finally:
            os.close(dfd)

    def write_file(self, rel, chunks):
        _check_parts(rel)
        dfd = self._dir(rel[:-1])
        try:
            st = self._lstat(dfd, rel[-1])
            if st is not None and not stat.S_ISREG(st.st_mode):
                raise PermissionError(errno.EPERM, "exists and is not a regular file")
            tmp = ".netsd-tmp-%d-%d" % (os.getpid(), time.monotonic_ns())
            f = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644,
                        dir_fd=dfd)
            try:
                for b in chunks:
                    os.write(f, b)
                os.close(f)
                f = None
                os.replace(tmp, rel[-1], src_dir_fd=dfd, dst_dir_fd=dfd)
            except BaseException:
                if f is not None:
                    os.close(f)
                try:
                    os.unlink(tmp, dir_fd=dfd)
                except OSError:
                    pass
                raise
        finally:
            os.close(dfd)

    def rename(self, src, dst):
        _check_parts(src)
        _check_parts(dst)
        sfd = self._dir(src[:-1])
        try:
            dfd = self._dir(dst[:-1])
            try:
                if self._lstat(dfd, dst[-1]) is not None:
                    raise FileExistsError(errno.EEXIST, "destination exists")
                st = self._lstat(sfd, src[-1])
                if st is None or not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)):
                    raise FileNotFoundError(errno.ENOENT, "source missing")
                os.rename(src[-1], dst[-1], src_dir_fd=sfd, dst_dir_fd=dfd)
            finally:
                os.close(dfd)
        finally:
            os.close(sfd)

    def remove(self, rel, is_dir):
        _check_parts(rel)
        dfd = self._dir(rel[:-1])
        try:
            st = self._lstat(dfd, rel[-1])
            if st is None:
                return
            if is_dir and stat.S_ISDIR(st.st_mode):
                os.rmdir(rel[-1], dir_fd=dfd)          # only if empty
            elif not is_dir and stat.S_ISREG(st.st_mode):
                os.unlink(rel[-1], dir_fd=dfd)
            else:
                raise PermissionError(errno.EPERM, "type changed on the host")
        finally:
            os.close(dfd)


def dump(card, path, last=None):
    """Write the card (up to sector last, default all) to an image file."""
    last = card.total if last is None else last
    with open(path, "wb") as f:
        for lba in range(last):
            data = card.read_sector(lba)
            if data == ZERO:
                f.seek(SECTOR, 1)
            else:
                f.write(data)
        f.truncate(last * SECTOR)
