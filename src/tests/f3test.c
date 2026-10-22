/*
  f3test: a self-checking test of the hardware FAT32 engine on real cards.
  MEGA65/mega65-core#766 (docs/sdcard-native/f3dos.md).

  Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project.
  LGPL v3 (see LICENSE.txt).

  It asks nothing.  Part 1 only reads: on every drive, every file it finds
  (up to a budget) is read through the engine and compared with the card's
  raw sectors, found by f3test's own walk of the FAT from the boot sector,
  so the engine is checked against something that does not use it.  Part 2
  writes, inside /F3TEST.TMP on one drive (C: unless given; RUN:REM D on
  the MEGA65), and removes it again: files of awkward sizes written in odd
  pieces, read back four ways (and raw), seeks, append, overwrite, truncate,
  $75 and the quick commands, long and UTF-8 names, a directory grown past
  a cluster, nested directories and renames, the error cases, and all of it
  again after a rescan with the sector cache off.  Nothing outside
  /F3TEST.TMP is written.

  Build for the MEGA65:  cl65 -t c64 -O -Os -o f3test.prg f3test.c f3lib.c
  Build for a PC:        cc -DHOST -O2 -o f3test_host f3test.c f3lib.c
                         python3 src/tools/f3bridge.py --card1 card.img -- ./f3test_host [D]
*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include "f3lib.h"

#define DIRNAME "/f3test.tmp"
#define READ_BUDGET (4UL << 20)   /* part 1: bytes read per drive, at most */
#define FILE_BUDGET 512           /* ... and sectors per file */

static uint16_t passes, fails;
static const char *section;
static char pa[160], pb[160];
static uint8_t tmp[512];          /* a sector kept while buf is reused */

static void fail(const char *what, uint32_t v)
{
  fails++;
  if (fails <= 40)
    printf("fail: %s: %s (%lu)\n", section, what, (unsigned long)v);
}

#define CHECK(c, what, v) do { if (c) passes++; else fail(what, (uint32_t)(v)); } while (0)

/* an ASCII string from the engine equals one of ours */
static uint8_t aeq(const uint8_t *a, const char *l)
{
  for (; *l; a++, l++)
    if (*a != (uint8_t)to_ascii(*l)) return 0;
  return !*a;
}

static void begin(const char *s)
{
  section = s;
  printf("%s\n", s);
}

/* ------------------------------------------------------------------------ */
/* the card's own view: geometry from the boot sector, the FAT read raw      */
/* ------------------------------------------------------------------------ */

struct geo {
  uint8_t slot, spcl;
  uint32_t fat, fatsz, data, root, clusters;
  uint8_t nfats;
};
static struct geo g[8], *cg;
static uint8_t ndrives;
static uint8_t fatbuf[512];
static uint32_t fatbuf_lba = 0xFFFFFFFFUL;
static uint8_t fatbuf_slot;

static uint8_t raw(uint8_t slot, uint32_t lba)
{
  if (!sd_select(slot)) return E_IO;
  return sd_read(lba);
}

static uint8_t load_geometry(void)
{
  uint8_t i, *p;
  uint32_t lba;
  CHECK(!f3_op(OP_RESCAN, 0, 0, 0, 0), "rescan", buf[3]);
  CHECK(!f3_op(OP_PARTS, 0, 0, 0, 0), "partition list", buf[3]);
  ndrives = (uint8_t)f3_res0;
  CHECK(ndrives >= 1 && ndrives <= 8, "drives", ndrives);
  if (ndrives > 8) ndrives = 0;
  memcpy(tmp, buf, 16 + 16 * ndrives);
  for (i = 0; i < ndrives; i++) {
    p = tmp + 16 + 16 * i;
    CHECK(p[0] == i + 1, "drive numbers in order", p[0]);
    g[i].slot = p[1];
    g[i].spcl = p[3];
    lba = get32(p + 4);
    g[i].clusters = get32(p + 12);
    if (raw(p[1], lba)) {
      fail("raw boot sector read", lba);
      continue;
    }
    CHECK(buf[510] == 0x55 && buf[511] == 0xAA, "boot sector signature", i);
    CHECK(buf[11] == 0 && buf[12] == 2, "512-byte sectors", i);
    CHECK(buf[13] == (1 << p[3]), "sectors per cluster agree", buf[13]);
    g[i].nfats = buf[16];
    g[i].fat = lba + (buf[14] | (buf[15] << 8));
    g[i].fatsz = get32(buf + 36);
    g[i].root = get32(buf + 44);
    g[i].data = g[i].fat + g[i].nfats * g[i].fatsz;
  }
  return ndrives;
}

/* the FAT entry of cluster c (FAT copy k) */
static uint32_t fat_next(uint32_t c, uint8_t k)
{
  uint32_t lba = cg->fat + k * cg->fatsz + (c >> 7);
  if (lba != fatbuf_lba || cg->slot != fatbuf_slot) {
    if (raw(cg->slot, lba)) {
      fail("raw fat read", lba);
      return 0x0FFFFFFFUL;
    }
    memcpy(fatbuf, buf, 512);
    fatbuf_lba = lba;
    fatbuf_slot = cg->slot;
  }
  return get32(fatbuf + ((uint16_t)(c & 127) << 2)) & 0x0FFFFFFFUL;
}

/* a raw walk of a file: rw_sector() gives its sectors in turn */
static uint32_t rw_cl;
static uint16_t rw_s;
static uint8_t rw_bad;

static void rw_start(uint32_t first)
{
  fatbuf_lba = 0xFFFFFFFFUL;              /* (the engine may have written it) */
  rw_cl = first;
  rw_s = 0;
  rw_bad = 0;
}

/* the next sector's LBA, or 0 */
static uint32_t rw_sector(void)
{
  uint32_t lba;
  if (rw_cl < 2 || rw_cl >= 0x0FFFFFF8UL || rw_cl > cg->clusters + 1) {
    rw_bad = 1;
    return 0;
  }
  lba = cg->data + ((rw_cl - 2) << cg->spcl) + rw_s;
  if (++rw_s == (1 << cg->spcl)) {
    rw_s = 0;
    rw_cl = fat_next(rw_cl, 0);
  }
  return lba;
}

/* the chain of a file of `size` bytes: its length, its end, both FATs equal */
static void check_chain(uint32_t first, uint32_t size)
{
  uint32_t c = first, n = 0, want, csize = 512UL << cg->spcl;
  uint8_t same = 1;
  fatbuf_lba = 0xFFFFFFFFUL;
  want = (size + csize - 1) / csize;
  if (!size) {
    CHECK(first == 0, "an empty file has no cluster", first);
    return;
  }
  while (c >= 2 && c < 0x0FFFFFF8UL && n <= want) {
    if (cg->nfats > 1 && fat_next(c, 1) != fat_next(c, 0)) same = 0;
    c = fat_next(c, 0);
    n++;
  }
  CHECK(n == want, "chain length", n);
  CHECK(c >= 0x0FFFFFF8UL, "chain ends", c);
  CHECK(same, "both fats agree", first);
}

/* ------------------------------------------------------------------------ */
/* part 1: everything read, on every drive                                   */
/* ------------------------------------------------------------------------ */

static uint32_t budget, files_read, bytes_read;
static uint16_t entries;          /* ... and entries listed per drive */

/* the file at pa (entry at tmp: size, first): read through $71 512 at a
   time and through $74, each sector compared with the card's */
static void scan_file(uint32_t size, uint32_t first)
{
  int16_t fd, n;
  uint32_t k = 0, lba, off = 0;
  uint8_t e;
  fd = f3_open(pa, 0);
  if (fd < 0) {
    fail("open a listed file", -fd);
    printf("  %s\n", pa);
    return;
  }
  rw_start(first);
  while (off < size && k < FILE_BUDGET && budget) {
    n = f3_read(fd, 512);
    if (n != (int16_t)(size - off > 512 ? 512 : size - off)) {
      fail("$71 count", n);
      break;
    }
    memcpy(tmp, buf, n);
    lba = rw_sector();
    if (!lba || raw(cg->slot, lba)) {
      fail("raw walk", k);
      break;
    }
    if (memcmp(tmp, buf, n)) {
      fail("$71 data differs from the card", k);
      printf("  %s\n", pa);
      break;
    }
    if (n == 512 && (k & 7) == 0) {          /* $74: every 8th sector */
      e = f3_cmd(0x74, ((uint32_t)fd << 24) | k);
      CHECK(!e && !memcmp(tmp, buf, 512), "$74 data", k);
    }
    off += n;
    k++;
    budget = budget > (uint32_t)n ? budget - n : 0;
    bytes_read += n;
  }
  if (off == size && size % 512) {
    e = f3_cmd(0x74, ((uint32_t)fd << 24) | (size >> 9));
    CHECK(e != 0, "$74 across the end refused", size);
  }
  if (off == size) {
    n = f3_read(fd, 512);
    CHECK(n == 0, "read at the end gives 0", n);
  }
  f3_close(fd);
  files_read++;
}

/* a directory at pa (depth: the descriptors it holds) */
static void scan_dir(uint8_t depth)
{
  int16_t fd;
  uint8_t e, attr, l;
  uint32_t size, first;
  static char name[100];
  if (f3_path(pa) || f3_op(OP_OPENDIR, 0, 0, 0, 0)) {
    fail("opendir", buf[3]);
    printf("  %s\n", pa);
    return;
  }
  fd = f3_resfd;
  l = strlen(pa);
  for (;;) {
    e = f3_op(OP_READDIR, fd, 0, 0, 0);
    if (e) break;
    if (buf[ENT_SHORT] == '.') continue;
    if (++entries > 3000) break;
    attr = buf[ENT_ATTR];
    size = get32(buf + ENT_SIZE);
    first = get32(buf + ENT_FIRST);
    /* the name to use: the short one (it is always ASCII) */
    ascii_to_local(name, buf + ENT_SHORT, sizeof(name));
    if (l + strlen(name) + 2 >= sizeof(pa)) continue;
    if (pa[l - 1] != '/') strcat(pa, "/");
    strcat(pa, name);
    /* stat agrees with readdir */
    memcpy(tmp, buf + 16, 16);
    e = f3_stat(pa);
    CHECK(!e && !memcmp(tmp, buf + 16, 12), "stat agrees with readdir", e);
    if (attr & A_DIR) {
      if (depth < 5) scan_dir(depth + 1);
    } else if (budget) {
      if (size <= (READ_BUDGET >> 2)) check_chain(first, size);
      scan_file(size, first);
    }
    pa[l] = 0;
    if (f3_stop()) break;
  }
  CHECK(e == E_END || entries > 3000 || f3_stopped, "readdir ends with E_END", e);
  f3_close(fd);
}

static void part1(void)
{
  uint8_t i;
  begin("part 1: every drive read, checked against the card");
  for (i = 0; i < ndrives; i++) {
    cg = &g[i];
    budget = READ_BUDGET;
    files_read = bytes_read = 0;
    entries = 0;
    sprintf(pa, "%c:/", 'c' + i);
    scan_dir(1);
    printf("  %c: %lu files, %lu kb\n", 'c' + i, (unsigned long)files_read,
           (unsigned long)(bytes_read >> 10));
    if (f3_stop()) return;
  }
}

/* ------------------------------------------------------------------------ */
/* part 2: writing                                                           */
/* ------------------------------------------------------------------------ */

static uint32_t csize;
static const uint16_t wchunks[] = { 1, 7, 100, 511, 512, 300, 512, 33, 512, 2 };
static const uint16_t rchunks[] = { 512, 3, 200, 509, 512, 64, 1, 512 };

/* write `size` bytes of pattern `seed` at the position, in odd pieces */
static uint8_t write_pat(uint8_t fd, uint32_t off, uint32_t size, uint8_t seed)
{
  uint8_t i = 0;
  uint16_t n;
  int16_t w;
  uint32_t end = off + size;
  while (off < end) {
    n = wchunks[i++ % 10];
    if (end - off < n) n = end - off;
    pat_fill(buf, off, n, seed);
    w = f3_write(fd, n);
    if (w != (int16_t)n) {
      fail("write", w);
      return 1;
    }
    off += n;
  }
  return 0;
}

static uint32_t stat_size(const char *path)
{
  if (f3_stat(path)) return 0xFFFFFFFFUL;
  return get32(buf + ENT_SIZE);
}

/* a file: size, its contents pattern `seed` (bytes [from, to) of seed2
   instead), read through $71 in odd pieces, $74, seeks and raw */
static void verify(const char *path, uint32_t size, uint8_t seed, uint32_t from, uint32_t to, uint8_t seed2)
{
  int16_t fd, n, bad;
  uint32_t off = 0, first, k, lba;
  uint8_t i = 0, s, e;
  CHECK(stat_size(path) == size, "size", stat_size(path));
  first = get32(buf + ENT_FIRST);
  fd = f3_open(path, 0);
  if (fd < 0) {
    fail("open", -fd);
    return;
  }
  /* $71, odd pieces */
  for (;;) {
    n = f3_read(fd, rchunks[i++ % 8]);
    if (n <= 0) break;
    if (off + n <= from || off >= to) {
      bad = pat_check(buf, off, n, seed);
    } else {
      for (bad = -1, k = 0; k < (uint32_t)n && bad < 0; k++) {
        s = (off + k >= from && off + k < to) ? seed2 : seed;
        if (pat_check(buf + k, off + k, 1, s) >= 0) bad = k;
      }
    }
    if (bad >= 0) {
      fail("$71 data", off + bad);
      break;
    }
    off += n;
  }
  CHECK(n == 0 && off == size, "$71 read to the end", off);
  /* seeks */
  if (size > 10) {
    e = f3_seek(fd, size / 3, 0);
    n = f3_read(fd, 5);
    CHECK(!e && n == 5 && (from != to || pat_check(buf, size / 3, 5, seed) < 0), "seek from the start", size / 3);
    e = f3_seek(fd, 3, 1);
    CHECK(!e && f3_res0 == size / 3 + 8, "seek from the position", f3_res0);
    e = f3_seek(fd, (uint32_t)-4L, 2);
    n = f3_read(fd, 100);
    CHECK(!e && n == 4 && (from != to || pat_check(buf, size - 4, 4, seed) < 0), "seek from the end", n);
  }
  /* $74 and raw, whole sectors */
  rw_start(first);
  for (k = 0; k < (size >> 9); k++) {
    e = f3_cmd(0x74, ((uint32_t)fd << 24) | k);
    if (e) {
      fail("$74", k);
      break;
    }
    memcpy(tmp, buf, 512);
    lba = rw_sector();
    if (!lba || raw(cg->slot, lba) || memcmp(tmp, buf, 512)) {
      fail("$74 / raw sector", k);
      break;
    }
    if (from == to && pat_check(tmp, k << 9, 512, seed) >= 0) {
      fail("$74 data", k);
      break;
    }
  }
  f3_close(fd);
  check_chain(first, size);
}

static uint8_t mkpat(const char *path, uint32_t size, uint8_t seed)
{
  int16_t fd = f3_create(path, 0);
  uint8_t e;
  if (fd < 0) {
    fail("create", -fd);
    return 1;
  }
  e = write_pat(fd, 0, size, seed);
  CHECK(!f3_close(fd), "close", 0);
  return e;
}

/* remove a tree (ours) at pb */
static void rm_tree(void)
{
  int16_t fd;
  uint8_t l = strlen(pb), again = 1;
  static char name[20];
  while (again) {
    again = 0;
    if (f3_path(pb) || f3_op(OP_OPENDIR, 0, 0, 0, 0)) return;
    fd = f3_resfd;
    while (!f3_op(OP_READDIR, fd, 0, 0, 0)) {
      if (buf[ENT_SHORT] == '.') continue;
      ascii_to_local(name, buf + ENT_SHORT, sizeof(name));
      strcat(pb, "/");
      strcat(pb, name);
      if (buf[ENT_ATTR] & A_DIR) {
        f3_close(fd);
        rm_tree();
        again = 1;
        pb[l] = 0;
        break;
      }
      if (buf[ENT_ATTR] & A_RO) {
        f3_path(pb);
        f3_op(OP_SETATTR, 0, 0, 0, 0);
      }
      f3_simple(OP_DELETE, pb);
      pb[l] = 0;
    }
    if (!again) f3_close(fd);
  }
  f3_simple(OP_RMDIR, pb);
}

static void t_sizes(void)
{
  static uint32_t sizes[14];
  uint8_t i, j, n = 0;
  begin("sizes");
  sizes[n++] = 0; sizes[n++] = 1; sizes[n++] = 511; sizes[n++] = 512; sizes[n++] = 513;
  sizes[n++] = 1025; sizes[n++] = csize - 1; sizes[n++] = csize; sizes[n++] = csize + 1;
  sizes[n++] = 2 * csize + 7; sizes[n++] = 5 * csize + 300; sizes[n++] = 300000UL;
  for (i = 0; i < n; i++) {
    for (j = 0; j < i && sizes[j] != sizes[i]; j++)
      ;
    if (j < i) continue;                      /* (small clusters: 511, 512, 513 again) */
    sprintf(pa, "size%lu.bin", (unsigned long)sizes[i]);
    if (mkpat(pa, sizes[i], i)) continue;
    verify(pa, sizes[i], i, 0, 0, 0);
    if (f3_stop()) return;
  }
}

static void t_modify(void)
{
  int16_t fd, r, j;
  uint8_t e;
  uint32_t n, nz;
  begin("append, overwrite, truncate");
  /* append (flag), to a file of 513 */
  fd = f3_open("size513.bin", O_APPEND);
  CHECK(fd >= 0, "open for appending", -fd);
  if (fd >= 0) {
    f3_seek(fd, 0, 0);                        /* (appending goes to the end anyway) */
    write_pat(fd, 513, 1000, 4);
    f3_close(fd);
    verify("size513.bin", 1513, 4, 0, 0, 0);
  }
  /* overwrite in the middle */
  fd = f3_open("size1025.bin", O_WRITE);
  CHECK(fd >= 0, "open for writing", -fd);
  if (fd >= 0) {
    f3_seek(fd, 700, 0);
    write_pat(fd, 700, 300, 99);
    f3_close(fd);
    verify("size1025.bin", 1025, 5, 700, 1000, 99);
  }
  /* writing at the end grows the file */
  fd = f3_open("size512.bin", O_WRITE);
  if (fd >= 0) {
    f3_seek(fd, 0, 2);
    write_pat(fd, 512, 600, 3);
    f3_close(fd);
    verify("size512.bin", 1112, 3, 0, 0, 0);
  }
  /* truncate shorter, then longer (zeros) */
  n = 5 * csize + 300;
  sprintf(pa, "size%lu.bin", (unsigned long)n);
  fd = f3_open(pa, O_WRITE);
  if (fd >= 0) {
    e = f3_op(OP_TRUNCATE, fd, 0, 100, 0);
    CHECK(!e, "truncate shorter", e);
    e = f3_op(OP_TRUNCATE, fd, 0, 2 * csize + 50, 0);
    CHECK(!e, "truncate longer", e);
    f3_seek(fd, 100, 0);
    n = nz = 0;
    while ((r = f3_read(fd, 512)) > 0) {
      for (j = 0; j < r; j++)
        if (buf[j]) nz++;
      n += r;
    }
    CHECK(nz == 0, "the grown part is zeros", nz);
    CHECK(n == 2 * csize + 50 - 100, "the grown part's length", n);
    f3_close(fd);
    fd = f3_open(pa, 0);
    if (fd >= 0) {
      f3_read(fd, 100);
      CHECK(pat_check(buf, 0, 100, 10) < 0, "truncated: the start kept", 0);
      f3_close(fd);
    }
    CHECK(stat_size(pa) == 2 * csize + 50, "truncated size", stat_size(pa));
    check_chain(get32(buf + ENT_FIRST), 2 * csize + 50);
  }
  /* close every descriptor the truncate test left (bad fds are refused) */
  for (e = 0; e < 8; e++) f3_close(e);
}

static void t_sectors(void)
{
  int16_t fd;
  uint8_t e;
  begin("$75, $76-$79");
  mkpat("sect.bin", 4 * 512, 20);
  fd = f3_open("sect.bin", O_WRITE);
  CHECK(fd >= 0, "open", -fd);
  if (fd >= 0) {
    pat_fill(buf, 1024, 512, 21);
    e = f3_cmd(0x75, ((uint32_t)fd << 24) | 2);
    CHECK(!e, "$75 sector 2", e);
    pat_fill(buf, 0, 512, 0);
    e = f3_cmd(0x75, ((uint32_t)fd << 24) | 4);
    CHECK(e != 0, "$75 past the end refused", e);
    f3_close(fd);
    verify("sect.bin", 2048, 20, 1024, 1536, 21);
  }
  /* quick: fd 0 read, fd 1 write */
  fd = f3_open("size300000.bin", O_USEFD);
  CHECK(fd == 0, "open as fd 0", fd);
  f3_path("quick.bin");
  e = f3_op(OP_CREATE, 1, O_USEFD, 0, 0);
  CHECK(!e && f3_resfd == 1, "create as fd 1", e);
  for (fd = 0; fd < 8; fd++) {
    e = f3_cmd(0x76, 0);
    if (e || f3_res0 != 512 || pat_check(buf, (uint32_t)fd << 9, 512, 11) >= 0) {
      fail("$76", fd);
      break;
    }
    e = f3_cmd(0x79, 0);
    if (e) {
      fail("$79", e);
      break;
    }
  }
  f3_close(0);
  f3_close(1);
  verify("quick.bin", 4096, 11, 0, 0, 0);
}

static void t_names(void)
{
  /* "Grüße ✓.txt" in UTF-8 (bytes: cc65 translates string literals, escapes too) */
  static const uint8_t utf8[] = { 0x47, 0x72, 0xC3, 0xBC, 0xC3, 0x9F, 0x65, 0x20, 0xE2, 0x9C,
                                  0x93, 0x2E, 0x74, 0x78, 0x74, 0 };
  static const char *const longs[] = {
    "A long file name.txt", "mixedCase.Txt", "a.b.c.d", "spaces  inside.x", "x" };
  uint8_t i, e, found;
  int16_t fd;
  static char shorts[12][13];
  begin("names");
  for (i = 0; i < 5; i++) {
    CHECK(!mkpat(longs[i], 10 + i, i), "create", i);
    /* (any case finds it) */
    strcpy(pa, longs[i]);
    for (e = 0; pa[e]; e++) pa[e] = lcase(pa[e]);
    CHECK(stat_size(pa) == 10UL + i, "found ignoring case", i);
  }
  /* ten names with one alias stem: aliases all different */
  for (i = 0; i < 12; i++) {
    sprintf(pa, "Same Long Prefix %u.dat", i);
    mkpat(pa, i, i);
    f3_stat(pa);
    memcpy(shorts[i], buf + ENT_SHORT, 13);
    for (e = 0; e < i; e++)
      if (!strcmp(shorts[e], shorts[i])) fail("aliases differ", i);
  }
  /* UTF-8 */
  f3_rawpath(utf8, sizeof(utf8) - 1);
  e = f3_op(OP_CREATE, 0, 0, 0, 0);
  CHECK(!e, "create a UTF-8 name", e);
  if (!e) f3_close(f3_resfd);
  f3_path(".");
  f3_op(OP_OPENDIR, 0, 0, 0, 0);
  fd = f3_resfd;
  found = 0;
  while (!f3_op(OP_READDIR, fd, 0, 0, 0))
    if (!strcmp((char *)buf + ENT_LONG, (const char *)utf8)) found++;
  f3_close(fd);
  CHECK(found == 1, "listed once with its UTF-8 name", found);
  /* bad names */
  e = f3_create("a*b", 0) < 0;
  CHECK(e, "a name with * refused", 0);
  e = f3_create("trailing.", 0) < 0;
  CHECK(e, "a name ending in . refused", 0);
  memset(buf + 16, 'n', 260);
  buf[16 + 260] = 0;
  e = f3_op(OP_CREATE, 0, 0, 0, 0);
  CHECK(e == E_LONG, "a 260-byte name refused", e);
}

static void t_bigdir(void)
{
  uint16_t i, n, count;
  int16_t fd;
  uint8_t e;
  static uint8_t seen[160];
  begin("a directory past a cluster");
  /* three entries a file (two long-name entries): enough to fill a cluster */
  n = csize / 96 + 20;
  if (n > 1200) n = 1200;
  CHECK(!f3_simple(OP_MKDIR, "many"), "mkdir", 0);
  for (i = 0; i < n; i++) {
    sprintf(pa, "many/entry number %04u.txt", i);
    fd = f3_create(pa, 0);
    if (fd < 0) {
      fail("create", i);
      break;
    }
    f3_close(fd);
    if (f3_stop()) return;
  }
  for (e = 0; e < 2; e++) {
    memset(seen, 0, sizeof(seen));
    count = 0;
    f3_path("many");
    f3_op(OP_OPENDIR, 0, 0, 0, 0);
    fd = f3_resfd;
    while (!f3_op(OP_READDIR, fd, 0, 0, 0)) {
      if (buf[ENT_LONG] == '.') continue;
      i = atoi((char *)buf + ENT_LONG + 13);
      if (i < n && !(seen[i >> 3] & (1 << (i & 7)))) {
        seen[i >> 3] |= 1 << (i & 7);
        count++;
      } else {
        fail("listed twice, or unknown", i);
      }
    }
    f3_close(fd);
    CHECK(count == (e ? n / 2 : n), "every entry listed once", count);
    if (!e) {
      /* delete the even ones, then list again: the odd ones remain */
      for (i = 0; i < n; i += 2) {
        sprintf(pa, "many/entry number %04u.txt", i);
        if (f3_simple(OP_DELETE, pa)) fail("delete", i);
      }
    }
  }
  /* (the even ones' places are free again: reuse some) */
  for (i = 0; i < 20; i += 2) {
    sprintf(pa, "many/entry number %04u.txt", i);
    fd = f3_create(pa, 0);
    CHECK(fd >= 0, "create in a freed place", i);
    if (fd >= 0) f3_close(fd);
  }
}

static void t_dirs(void)
{
  uint8_t e;
  int16_t fd;
  begin("directories, renames");
  CHECK(!f3_simple(OP_MKDIR, "a"), "mkdir a", 0);
  CHECK(!f3_simple(OP_MKDIR, "a/b"), "mkdir a/b", 0);
  CHECK(!f3_simple(OP_MKDIR, "a/b/c"), "mkdir a/b/c", 0);
  CHECK(!mkpat("a/b/c/deep.bin", 3000, 30), "a file deep down", 0);
  CHECK(!f3_simple(OP_CHDIR, "a/b/c"), "chdir down", 0);
  e = f3_op(OP_GETCWD, 0, 0, 0, 0);
  CHECK(!e && aeq(buf + 16, DIRNAME "/a/b/c"), "getcwd deep", e);
  CHECK(stat_size("deep.bin") == 3000, "relative path", 0);
  CHECK(stat_size("../../b/c/deep.bin") == 3000, "a path with ..", 0);
  CHECK(!f3_simple(OP_MKDIR, "e"), "mkdir e", 0);
  CHECK(!f3_simple(OP_CHDIR, "e"), "chdir e", 0);
  CHECK(f3_simple(OP_RMDIR, DIRNAME "/a/b/c/e") == E_BUSY, "rmdir of the current directory", 0);
  CHECK(!f3_simple(OP_CHDIR, ".."), "chdir ..", 0);
  CHECK(!f3_simple(OP_RMDIR, "e"), "rmdir e", 0);
  CHECK(!f3_simple(OP_CHDIR, "../.."), "chdir ../..", 0);
  CHECK(f3_simple(OP_RMDIR, "b") == E_NOTEMPTY, "rmdir of a full directory", 0);
  /* rename a file into another directory, and a directory */
  f3_path("b/c/deep.bin");
  f3_path2("moved.bin");
  CHECK(!f3_op(OP_RENAME, 0, 0, 0, 0), "rename a file to another directory", buf[3]);
  verify("moved.bin", 3000, 30, 0, 0, 0);
  f3_path("b");
  f3_path2("../renamed dir");
  CHECK(!f3_op(OP_RENAME, 0, 0, 0, 0), "rename (move) a directory", buf[3]);
  CHECK(!f3_simple(OP_CHDIR, "../renamed dir/c"), "chdir into the moved directory", 0);
  CHECK(!f3_simple(OP_CHDIR, "../.."), "its .. follows", 0);
  e = f3_op(OP_GETCWD, 0, 0, 0, 0);
  CHECK(!e && aeq(buf + 16, DIRNAME), "getcwd after", e);
  mkpat("other.bin", 5, 1);
  f3_path("other.bin");
  f3_path2("a/moved.bin");
  CHECK(f3_op(OP_RENAME, 0, 0, 0, 0) == E_EXIST, "rename onto a file refused", buf[3]);
  CHECK(!f3_simple(OP_RMDIR, "renamed dir/c"), "rmdir", 0);
  CHECK(!f3_simple(OP_RMDIR, "renamed dir"), "rmdir", 0);
  /* attributes */
  f3_path("other.bin");
  CHECK(!f3_op(OP_SETATTR, 0, 0, A_RO | A_HID, 0), "setattr", 0);
  f3_stat("other.bin");
  CHECK((buf[ENT_ATTR] & 0x27) == (A_RO | A_HID), "attributes", buf[ENT_ATTR]);
  CHECK(f3_open("other.bin", O_WRITE) == -E_ACCESS, "a read-only file refuses writing", 0);
  CHECK(f3_simple(OP_DELETE, "other.bin") == E_ACCESS, "a read-only file is not deleted", 0);
  fd = f3_open("other.bin", 0);
  CHECK(fd >= 0, "a read-only file opens for reading", -fd);
  if (fd >= 0) f3_close(fd);
  f3_path("other.bin");
  f3_op(OP_SETATTR, 0, 0, 0, 0);
}

static void t_errors(void)
{
  int16_t fd, fds[8];
  uint8_t i, n;
  begin("errors");
  CHECK(f3_open("nope.bin", 0) == -E_NOENT, "not found", 0);
  CHECK(f3_open("nope/x", 0) == -E_NOENT, "a missing directory", 0);
  CHECK(f3_open("a", 0) == -E_ISDIR, "open a directory as a file", 0);
  CHECK(f3_simple(OP_CHDIR, "other.bin") == E_NOTDIR, "chdir to a file", 0);
  CHECK(f3_simple(OP_MKDIR, "a") == E_EXIST, "mkdir of an existing name", 0);
  CHECK(f3_create("other.bin", 0) == -E_EXIST, "create of an existing name", 0);
  CHECK(f3_open("9:/x", 0) == -E_NODRV, "no such drive", 0);
  fd = f3_open("sect.bin", O_WRITE);
  CHECK(f3_simple(OP_DELETE, "sect.bin") == E_BUSY, "delete an open file", 0);
  CHECK(f3_open("sect.bin", O_WRITE) == -E_BUSY, "a second writer", 0);
  i = f3_open("sect.bin", 0) >= 0;
  CHECK(i, "a reader beside the writer", 0);
  for (n = 0; n < 8; n++) f3_close(n);
  CHECK(f3_close(7) == 0, "close of a closed descriptor is harmless", 0);
  CHECK(f3_close(8) == E_BADFD, "close of descriptor 8", 0);
  CHECK(f3_read(7, 10) == -E_BADFD, "read of a closed descriptor", 0);
  CHECK(f3_read(8, 10) == -E_BADFD, "descriptor 8", 0);
  for (n = 0; n < 8; n++) {
    fds[n] = f3_open("sect.bin", 0);
    if (fds[n] < 0) break;
  }
  CHECK(n == 8, "eight descriptors", n);
  CHECK(f3_open("sect.bin", 0) == -E_NFILE, "a ninth", 0);
  for (i = 0; i < n; i++) f3_close(fds[i]);
  fd = f3_open("sect.bin", 0);
  CHECK(fd >= 0 && f3_write(fd, 1) == -E_ACCESS, "write to a read-only descriptor", 0);
  f3_close(fd);
}

/* everything written again, after a rescan, cache off then on */
static void t_again(void)
{
  uint8_t k;
  int16_t fd;
  uint32_t n = 2 * csize + 7;
  begin("again: rescan, cache off");
  for (k = 0; k < 2; k++) {
    sd_cache(k);
    fatbuf_lba = 0xFFFFFFFFUL;
    /* a file open across the rescan reads on (its volume is found again) */
    fd = f3_open("size300000.bin", 0);
    CHECK(fd >= 0 && f3_read(fd, 512) == 512, "open before the rescan", fd);
    CHECK(!f3_op(OP_RESCAN, 0, 0, 0, 0), "rescan", 0);
    CHECK(f3_res1 == 0, "rescan: nothing stale", f3_res1);
    if (fd >= 0) {
      CHECK(f3_read(fd, 512) == 512 && pat_check(buf, 512, 512, 11) < 0,
            "a file open across the rescan reads on", 0);
      f3_close(fd);
    }
    f3_op(OP_SETDRIVE, 0, 0, (cg - g) + 1, 0);
    CHECK(!f3_simple(OP_CHDIR, DIRNAME), "chdir after the rescan", 0);
    sprintf(pa, "size%lu.bin", (unsigned long)n);
    verify(pa, n, 9, 0, 0, 0);
    verify("size300000.bin", 300000UL, 11, 0, 0, 0);
    verify("sect.bin", 2048, 20, 1024, 1536, 21);
    verify("a/moved.bin", 3000, 30, 0, 0, 0);
  }
}

static uint8_t sections = 0xFF;

static void part2(uint8_t d)
{
  uint8_t e;
  cg = &g[d];
  csize = 512UL << cg->spcl;
  printf("part 2: writing in %c:%s (%lu-byte clusters)\n", 'c' + d, DIRNAME, (unsigned long)csize);
  sprintf(pb, "%c:" DIRNAME, 'c' + d);
  if (!f3_stat(pb)) rm_tree();
  e = f3_simple(OP_MKDIR, pb);
  if (e) {
    fail("mkdir " DIRNAME, e);
    return;
  }
  f3_op(OP_SETDRIVE, 0, 0, d + 1, 0);
  CHECK(!f3_simple(OP_CHDIR, DIRNAME), "chdir", 0);
  /* (the later sections use files of the earlier ones) */
  if (sections & 1) t_sizes();
  if ((sections & 2) && !f3_stop()) t_modify();
  if ((sections & 4) && !f3_stop()) t_sectors();
  if ((sections & 8) && !f3_stop()) t_names();
  if ((sections & 16) && !f3_stop()) t_bigdir();
  if ((sections & 32) && !f3_stop()) t_dirs();
  if ((sections & 64) && !f3_stop()) t_errors();
  if ((sections & 128) && !f3_stop()) t_again();
  begin("clean up");
  sd_cache(1);
  f3_simple(OP_CHDIR, "/");
  rm_tree();
  CHECK(f3_stat(pb) == E_NOENT, DIRNAME " removed", 0);
}

int main(int argc, char **argv)
{
  uint8_t d = 0;
  uint32_t t;
  f3_init();
  printf("f3test: the hardware fat32 engine\n");
  if (argc > 1) d = lcase(argv[1][0]) - 'c';
  if (argc > 2) sections = (uint8_t)strtoul(argv[2], 0, 0);   /* (bits: part 2's sections) */
  t = ticks();
  if (load_geometry()) {
    part1();
    if (d < ndrives && !f3_stop()) part2(d);
    else if (d >= ndrives) fail("no such drive for part 2", d);
  }
  printf("\nf3test: %u passed, %u failed (%lu s)%s\n", passes, fails,
         (unsigned long)((ticks() - t) / 10), f3_stopped ? ", stopped" : "");
  return fails ? 1 : 0;
}
