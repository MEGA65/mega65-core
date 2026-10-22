/*
  f3dos: a small DOS-like shell on the hardware FAT32 engine, for trying it
  on real cards.  MEGA65/mega65-core#766 (docs/sdcard-native/f3dos.md).

  Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project.
  LGPL v3 (see LICENSE.txt).

  Drives C: to J: are the engine's drives 1 to 8 (the partitions, external
  card first).  Commands (HELP lists them): DRIVES, RESCAN, C: .. J:, DIR,
  CD, MD, RD, TYPE, DUMP, COPY, MOVE, REN, DEL, ATTRIB, STAT, WRITE, APPEND,
  MKFILE, CHECK, CRC, TRUNC, BENCH, VERIFY, CACHE, EXEC, ECHO, EXIT.
  COPY, MOVE, DEL and DIR take * and ? in the last part of a path, matched
  against the name DIR shows (never the 8.3 alias: *7.TXT would match
  FILENU~7.TXT).

  It runs as a program (user mode), so it has the programs' descriptors
  0-7, does not see SYSTEM entries, and the read-only policy applies.

  Build for the MEGA65:  cl65 -t c64 -O -Os -o f3dos.prg f3dos.c f3lib.c
  Build for a PC:        cc -DHOST -O2 -o f3dos_host f3dos.c f3lib.c
                         python3 src/tools/f3bridge.py --card1 card.img -- ./f3dos_host
*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include "f3lib.h"

#ifdef HOST
#include <unistd.h>
#else
#include <cbm.h>
#endif

#define MAXARGS 8

static char line[100];
static char *av[MAXARGS];
static uint8_t ac;
static char p1[160], p2[160], p3[160];   /* paths, in the program's characters */
static char nm[100];                     /* a name from a directory listing */
static uint8_t cur_drive = 1;
static uint8_t rows;                     /* lines shown since the last pause */
static uint8_t paging = 1;
static uint8_t failed;                   /* the last command failed */

/* ------------------------------------------------------------------------ */
/* output                                                                    */
/* ------------------------------------------------------------------------ */

static uint8_t report(uint8_t e)
{
  if (e) {
    printf("error %u: %s\n", e, f3_strerror(e));
    failed = 1;
  }
  return e;
}

static uint8_t neg(int16_t r)
{
  return r < 0 ? report((uint8_t)-r) : 0;
}

/* a line was shown: pause each screenful; -> 1 to stop */
static uint8_t more(void)
{
#ifndef HOST
  uint8_t c;
  if (paging && ++rows >= 23) {
    rows = 0;
    printf("-- more --");
    while (!(c = cbm_k_getin()))
      ;
    printf("\r          \r");
    if (c == 3 || c == 'q') f3_stopped = 1;
  }
#endif
  return f3_stop();
}

static void put_size(uint32_t n)
{
  if (n < 10000UL) printf("%lu b", (unsigned long)n);
  else if (n < 10240000UL) printf("%lu kb", (unsigned long)(n >> 10));
  else printf("%lu mb", (unsigned long)(n >> 20));
}

static void put_rate(uint32_t bytes, uint32_t t)
{
  if (!t) t = 1;
  printf(" in %lu.%lu s, %lu kb/s\n", (unsigned long)(t / 10), (unsigned long)(t % 10),
         (unsigned long)(bytes / 1024 * 10 / t));
}

/* ------------------------------------------------------------------------ */
/* paths and names                                                           */
/* ------------------------------------------------------------------------ */

static uint8_t has_wild(const char *s)
{
  return strchr(s, '*') != 0 || strchr(s, '?') != 0;
}

/* the drive a path names (or the current one) */
static uint8_t drive_of(const char *s)
{
  char c;
  if (s[0] && s[1] == ':') {
    c = lcase(s[0]);
    if (c >= 'c' && c <= 'j') return c - 'c' + 1;
    if (c >= '1' && c <= '8') return c - '0';
  }
  return cur_drive;
}

/* the start of the last part of a path */
static char *base(char *s)
{
  char *b = s, *p;
  for (p = s; *p; p++)
    if (*p == '/' || *p == '\\' || *p == ':') b = p + 1;
  return b;
}

/* dst = dir + "/" + name (no "/" after "", "X:" or "/") */
static void join(char *dst, const char *dir, const char *name)
{
  uint8_t n = strlen(dir);
  strcpy(dst, dir);
  if (n && dir[n - 1] != '/' && dir[n - 1] != ':' && dir[n - 1] != '\\') strcat(dst, "/");
  strcat(dst, name);
}

/* ASCII, case-blind, * and ? (s is ASCII: numbers, not character
   literals, which the compiler translates) */
static uint8_t match(const char *pat, const uint8_t *s)
{
  uint8_t a, b;
  while (*pat) {
    if (*pat == '*') {
      pat++;
      if (!*pat) return 1;
      for (; *s; s++)
        if (match(pat, s)) return 1;
      return 0;
    }
    if (!*s) return 0;
    a = to_ascii(*pat);
    b = *s;
    if (a >= 0x41 && a <= 0x5A) a += 32;
    if (b >= 0x41 && b <= 0x5A) b += 32;
    if (*pat != '?' && a != b) return 0;
    pat++;
    s++;
  }
  return !*s;
}

/* the entry at buf as a name to use in a path: the long name, or the short
   one if the long one has characters we cannot type */
static void entry_name(char *dst)
{
  const uint8_t *s = buf + ENT_LONG;
  for (; *s; s++)
    if (*s >= 0x80) break;
  ascii_to_local(dst, *s ? buf + ENT_SHORT : buf + ENT_LONG, 100);
}

static uint8_t is_dir(const char *path)
{
  uint8_t n = strlen(path);
  if (!n || path[n - 1] == ':' || path[n - 1] == '/') return 1;
  return !f3_stat(path) && (buf[ENT_ATTR] & A_DIR);
}

/* split a pattern "dir/pat" into p3 (dir) and the pattern (returned) */
static char *split_wild(const char *spec)
{
  static char pat[100];
  char *b;
  strcpy(p3, spec);
  b = base(p3);
  strcpy(pat, b);
  *b = 0;
  return pat;
}

typedef uint8_t (*each_fn)(const char *path);

/* fn on each file a spec names (dirs: only when it is one name) -> errors */
static uint8_t for_each(const char *spec, each_fn fn)
{
  char *pat;
  uint8_t fd, e, errors = 0, any = 0;
  static char full[160];
  if (!has_wild(spec)) return fn(spec) ? 1 : 0;
  pat = split_wild(spec);
  e = f3_path(p3[0] ? p3 : ".");
  if (!e && p3[0] && p3[strlen(p3) - 1] == ':') {
    strcat(p3, ".");
    e = f3_path(p3);
    p3[strlen(p3) - 1] = 0;
  }
  if (!e) e = f3_op(OP_OPENDIR, 0, 0, 0, 0);
  if (report(e)) return 1;
  fd = f3_resfd;
  for (;;) {
    e = f3_op(OP_READDIR, fd, 0, 0, 0);
    if (e) break;
    if (buf[ENT_ATTR] & A_DIR) continue;
    if (!match(pat, buf + ENT_LONG)) continue;
    entry_name(nm);
    join(full, p3, nm);
    any = 1;
    if (fn(full)) errors++;
    if (f3_stop()) break;
  }
  if (e && e != E_END) report(e);
  f3_close(fd);
  if (!any) {
    printf("no files match\n");
    failed = 1;
  }
  return errors;
}

/* ------------------------------------------------------------------------ */
/* commands                                                                  */
/* ------------------------------------------------------------------------ */

static void show_prompt(void)
{
  if (!f3_op(OP_GETCWD, 0, 0, 0, 0)) {
    cur_drive = (uint8_t)f3_res0;
    printf("%c:", 'C' + cur_drive - 1);
    f3_show(buf + 16);
  } else {
    printf("?:");
  }
  printf("> ");
}

static void cmd_drives(void)
{
  uint8_t i, n, *p;
  uint32_t mb;
  if (report(f3_op(OP_PARTS, 0, 0, 0, 0))) return;
  n = (uint8_t)f3_res0;
  if (!n) printf("no fat32 partitions\n");
  for (i = 0; i < n; i++) {
    p = buf + 16 + 16 * i;
    mb = get32(p + 8) >> 11;
    printf("%c: %s card, at %lu, ", 'C' + p[0] - 1, p[1] ? "ext" : "int",
           (unsigned long)get32(p + 4));
    if (mb < 10000) printf("%lu mb", (unsigned long)mb);
    else printf("%lu gb", (unsigned long)(mb >> 10));
    if (p[3]) printf(", %u kb clusters\n", (1 << p[3]) / 2);
    else printf(", 512 b clusters\n");
  }
}

/* both cards initialised again (a card just put in is not, until then),
   then the engine's rescan: open files follow their volumes, or go stale */
static void cmd_rescan(void)
{
  uint8_t i, n;
  sd_init_both();
  if (report(f3_op(OP_RESCAN, 0, 0, 0, 0)))
    return;
  printf("%lu drive(s)", (unsigned long)f3_res0);
  for (i = n = 0; i < 10; i++)
    if (f3_res1 & (1 << i)) n++;
  if (n) printf(", %u open file(s) now stale", n);
  printf("\n");
}

static void cmd_setdrive(uint8_t d)
{
  report(f3_op(OP_SETDRIVE, 0, 0, d, 0));
}

static void cmd_cd(void)
{
  if (ac < 2) {
    if (!report(f3_op(OP_GETCWD, 0, 0, 0, 0))) {
      printf("%c:", 'C' + (uint8_t)f3_res0 - 1);
      f3_show(buf + 16);
      printf("\n");
    }
    return;
  }
  if (av[1][0] && av[1][1] == ':' && !av[1][2]) {
    cmd_setdrive(drive_of(av[1]));
    return;
  }
  report(f3_simple(OP_CHDIR, av[1]));
}

static void dir_line(void)
{
  uint8_t a = buf[ENT_ATTR];
  if (a & A_DIR) printf("    <dir>");
  else printf("%9lu", (unsigned long)get32(buf + ENT_SIZE));
  printf(" %c%c%c ", (a & A_RO) ? 'r' : '-', (a & A_HID) ? 'h' : '-', (a & A_SYS) ? 's' : '-');
  f3_show(buf + ENT_LONG);
  printf("\n");
}

static void cmd_dir(void)
{
  const char *spec = ac > 1 ? av[1] : "";
  char *pat = 0;
  uint8_t fd, e;
  uint16_t files = 0, dirs = 0;
  uint32_t bytes = 0;
  if (has_wild(spec)) {
    pat = split_wild(spec);
  } else {
    strcpy(p3, spec);
  }
  if (!p3[0]) strcpy(p3, ".");
  else if (p3[strlen(p3) - 1] == ':') strcat(p3, ".");
  e = f3_path(p3);
  if (!e) e = f3_op(OP_OPENDIR, 0, 0, 0, 0);
  if (report(e)) return;
  fd = f3_resfd;
  rows = 0;
  for (;;) {
    e = f3_op(OP_READDIR, fd, 0, 0, 0);
    if (e) break;
    if (pat && !match(pat, buf + ENT_LONG)) continue;
    if (buf[ENT_ATTR] & A_DIR) dirs++;
    else {
      files++;
      bytes += get32(buf + ENT_SIZE);
    }
    dir_line();
    if (more()) break;
  }
  if (e && e != E_END) report(e);
  f3_close(fd);
  printf("%u file(s), ", files);
  put_size(bytes);
  printf(", %u dir(s)\n", dirs);
}

static void cmd_type(void)
{
  int16_t fd, n, i;
  uint8_t c;
  if ((fd = f3_open(av[1], 0)) < 0) {
    neg(fd);
    return;
  }
  rows = 0;
  while ((n = f3_read(fd, 512)) > 0) {
    for (i = 0; i < n; i++) {
      c = buf[i];
      if (c == 10) {
        f3_putc('\n');
        if (more()) break;
      } else if (c == 9) {
        f3_putc(' ');
      } else if (c >= 0x20 && c < 0x7F) {
        f3_putc(from_ascii(c));
      } else if (c != 13 && (c < 0x80 || c >= 0xC0)) {
        f3_putc('.');
      }
    }
    if (f3_stopped) break;
  }
  neg(n);
  f3_close(fd);
  f3_putc('\n');
}

static void cmd_dump(void)
{
  int16_t fd, n;
  uint32_t off = ac > 2 ? strtoul(av[2], 0, 0) : 0;
  uint16_t len = ac > 3 ? (uint16_t)strtoul(av[3], 0, 0) : 256, i, j;
  static uint8_t tmp[512];
  char c;
  if ((fd = f3_open(av[1], 0)) < 0) {
    neg(fd);
    return;
  }
  if (!report(f3_seek(fd, off, 0))) {
    rows = 0;
    while (len) {
      n = f3_read(fd, len > 512 ? 512 : len);
      if (n <= 0) break;
      memcpy(tmp, buf, n);
      for (i = 0; i < (uint16_t)n; i += 8) {
        printf("%06lx", (unsigned long)(off + i));
        for (j = 0; j < 8; j++)
          if (i + j < (uint16_t)n) printf(" %02x", tmp[i + j]);
          else printf("   ");
        printf(" ");
        for (j = 0; j < 8 && i + j < (uint16_t)n; j++) {
          c = tmp[i + j] >= 0x20 && tmp[i + j] < 0x7F ? from_ascii(tmp[i + j]) : 0;
          f3_putc(c ? c : '.');
        }
        printf("\n");
        if (more()) break;
      }
      off += n;
      len -= n;
      if (f3_stopped) break;
    }
    neg(n);
  }
  f3_close(fd);
}

/* copy one file to dst (a file or a directory) */
static const char *copy_dst;

static uint8_t copy_one(const char *src)
{
  int16_t in, out, n = 0, w;
  uint32_t first, total = 0, t;
  uint8_t e;
  static char dst[160];
  e = f3_stat(src);
  if (report(e)) return e;
  if (buf[ENT_ATTR] & A_DIR) return report(E_ISDIR);
  first = get32(buf + ENT_FIRST);
  strcpy(dst, copy_dst);
  if (is_dir(dst)) join(dst, copy_dst, base((char *)src));
  e = f3_stat(dst);
  if (!e) {
    if (buf[ENT_ATTR] & A_DIR) return report(E_ISDIR);
    if (first && get32(buf + ENT_FIRST) == first && drive_of(src) == drive_of(dst)) {
      printf("%s: the same file\n", src);
      failed = 1;
      return E_EXIST;
    }
  } else if (e != E_NOENT) {
    return report(e);
  }
  printf("%s -> %s", src, dst);
  if ((in = f3_open(src, 0)) < 0) return neg(in);
  out = e ? f3_create(dst, 0) : f3_open(dst, O_WRITE);
  if (out < 0) {
    f3_close(in);
    printf("\n");
    return neg(out);
  }
  e = e ? 0 : f3_op(OP_TRUNCATE, out, 0, 0, 0);
  t = ticks();
  while (!e && (n = f3_read(in, 512)) > 0) {
    w = f3_write(out, n);
    if (w != n) {
      e = w < 0 ? (uint8_t)-w : E_NOSPC;
      break;
    }
    total += n;
    if (f3_stop()) break;
  }
  if (n < 0) e = (uint8_t)-n;
  f3_close(in);
  if (!e) e = f3_close(out);
  else f3_close(out);
  put_rate(total, ticks() - t);
  return report(e);
}

static void cmd_copy(void)
{
  if (has_wild(av[1]) && !is_dir(av[2])) {
    printf("the destination must be a directory\n");
    failed = 1;
    return;
  }
  copy_dst = av[2];
  for_each(av[1], copy_one);
}

/* move: a rename on one drive, else a copy and a delete */
static uint8_t move_one(const char *src)
{
  uint8_t e;
  static char dst[160];
  strcpy(dst, copy_dst);
  if (is_dir(dst)) join(dst, copy_dst, base((char *)src));
  if (drive_of(src) == drive_of(dst)) {
    e = f3_path(src);
    if (!e) e = f3_path2(dst);
    if (!e) e = f3_op(OP_RENAME, 0, 0, 0, 0);
    if (!e) printf("%s -> %s\n", src, dst);
    return report(e);
  }
  e = copy_one(src);
  if (!e) e = report(f3_simple(OP_DELETE, src));
  return e;
}

static void cmd_move(void)
{
  if (has_wild(av[1]) && !is_dir(av[2])) {
    printf("the destination must be a directory\n");
    failed = 1;
    return;
  }
  copy_dst = av[2];
  for_each(av[1], move_one);
}

/* REN dir/old new: the new name stays in dir */
static void cmd_ren(void)
{
  uint8_t e;
  char *b;
  strcpy(p1, av[1]);
  b = base(p1);
  if (base(av[2]) == av[2]) {
    *b = 0;
    join(p2, p1, av[2]);
  } else {
    strcpy(p2, av[2]);
  }
  e = f3_path(av[1]);
  if (!e) e = f3_path2(p2);
  if (!e) e = f3_op(OP_RENAME, 0, 0, 0, 0);
  report(e);
}

static uint8_t del_one(const char *path)
{
  uint8_t e = f3_simple(OP_DELETE, path);
  if (!e) printf("deleted %s\n", path);
  return report(e);
}

static void cmd_del(void)
{
  for_each(av[1], del_one);
}

static void show_attr(uint8_t a)
{
  printf("%s%s%s%s%s", (a & A_RO) ? " read-only" : "", (a & A_HID) ? " hidden" : "",
         (a & A_SYS) ? " system" : "", (a & A_ARC) ? " archive" : "", (a & A_DIR) ? " dir" : "");
}

static void cmd_attrib(void)
{
  uint8_t i, a, bit;
  const char *path = av[ac - 1];
  char c;
  if (report(f3_stat(path))) return;
  a = buf[ENT_ATTR];
  for (i = 1; i < ac - 1; i++) {
    c = lcase(av[i][1]);
    bit = c == 'r' ? A_RO : c == 'h' ? A_HID : c == 's' ? A_SYS : c == 'a' ? A_ARC : 0;
    if (!bit || (av[i][0] != '+' && av[i][0] != '-')) {
      printf("attributes: +r -r +h -h +s -s +a -a\n");
      failed = 1;
      return;
    }
    if (av[i][0] == '+') a |= bit;
    else a &= ~bit;
  }
  if (ac > 2) {
    if (report(f3_path(path))) return;
    if (report(f3_op(OP_SETATTR, 0, 0, a & 0x27, 0))) return;
    if (report(f3_stat(path))) return;
  }
  f3_show(buf + ENT_LONG);
  printf(":");
  show_attr(buf[ENT_ATTR]);
  printf("\n");
}

static void cmd_stat(void)
{
  uint32_t t;
  if (report(f3_stat(av[1]))) return;
  t = get32(buf + ENT_TIME);
  printf("name:  ");
  f3_show(buf + ENT_LONG);
  printf("\nshort: ");
  f3_show(buf + ENT_SHORT);
  printf("\nsize:  %lu\nfirst cluster: %lu\n", (unsigned long)get32(buf + ENT_SIZE),
         (unsigned long)get32(buf + ENT_FIRST));
  printf("time:  %04u-%02u-%02u %02u:%02u:%02u\nattr: ",
         (unsigned)(1980 + (t >> 25)), (unsigned)((t >> 21) & 15), (unsigned)((t >> 16) & 31),
         (unsigned)((t >> 11) & 31), (unsigned)((t >> 5) & 63), (unsigned)((t & 31) * 2));
  show_attr(buf[ENT_ATTR]);
  printf("\n");
}

/* WRITE / APPEND file text...: the words, then a newline (LF) */
static void cmd_write(uint8_t append)
{
  int16_t fd;
  uint16_t n = 0;
  uint8_t i, e = 0;
  char *s;
  fd = f3_open(av[1], append ? O_WRITE | O_APPEND : O_WRITE);
  if (fd == -E_NOENT) fd = f3_create(av[1], 0);
  else if (fd >= 0 && !append) e = f3_op(OP_TRUNCATE, fd, 0, 0, 0);
  if (neg(fd)) return;
  for (i = 2; i < ac; i++) {
    for (s = av[i]; *s; s++) buf[n++] = to_ascii(*s);
    if (i + 1 < ac) buf[n++] = ' ';
  }
  buf[n++] = 10;
  if (!e && f3_write(fd, n) != (int16_t)n) e = E_IO;
  report(e);
  f3_close(fd);
}

/* MKFILE file size [seed]: test data (pat_fill) */
static void cmd_mkfile(void)
{
  int16_t fd, w;
  uint32_t size = strtoul(av[2], 0, 0), off = 0, t;
  uint8_t seed = ac > 3 ? (uint8_t)strtoul(av[3], 0, 0) : 0;
  uint16_t n;
  fd = f3_open(av[1], O_WRITE);
  if (fd == -E_NOENT) fd = f3_create(av[1], 0);
  else if (fd >= 0) f3_op(OP_TRUNCATE, fd, 0, 0, 0);
  if (neg(fd)) return;
  t = ticks();
  while (off < size) {
    n = size - off > 512 ? 512 : (uint16_t)(size - off);
    pat_fill(buf, off, n, seed);
    w = f3_write(fd, n);
    if (w != (int16_t)n) {
      report(w < 0 ? (uint8_t)-w : E_NOSPC);
      break;
    }
    off += n;
    if (f3_stop()) break;
  }
  f3_close(fd);
  printf("%lu bytes written", (unsigned long)off);
  put_rate(off, ticks() - t);
}

/* CHECK file [seed]: compare with MKFILE's data */
static void cmd_check(void)
{
  int16_t fd, n, bad;
  uint32_t off = 0, t;
  uint8_t seed = ac > 2 ? (uint8_t)strtoul(av[2], 0, 0) : 0;
  if ((fd = f3_open(av[1], 0)) < 0) {
    neg(fd);
    return;
  }
  t = ticks();
  while ((n = f3_read(fd, 512)) > 0) {
    bad = pat_check(buf, off, n, seed);
    if (bad >= 0) {
      printf("wrong at %lu: %02x\n", (unsigned long)(off + bad), buf[bad]);
      failed = 1;
      break;
    }
    off += n;
    if (f3_stop()) break;
  }
  neg(n);
  f3_close(fd);
  if (!failed) {
    printf("%lu bytes ok", (unsigned long)off);
    put_rate(off, ticks() - t);
  }
}

static uint8_t crc_file(const char *path, uint32_t *crc, uint32_t *size)
{
  int16_t fd, n;
  uint32_t c = 0xFFFFFFFFUL, len = 0;
  if ((fd = f3_open(path, 0)) < 0) return (uint8_t)-fd;
  while ((n = f3_read(fd, 512)) > 0) {
    c = crc_update(c, buf, n);
    len += n;
  }
  f3_close(fd);
  *crc = c ^ 0xFFFFFFFFUL;
  *size = len;
  return n < 0 ? (uint8_t)-n : 0;
}

static void cmd_crc(void)
{
  uint32_t crc = 0, size = 0;
  if (!report(crc_file(av[1], &crc, &size)))
    printf("%08lx %lu\n", (unsigned long)crc, (unsigned long)size);
}

static void cmd_trunc(void)
{
  int16_t fd = f3_open(av[1], O_WRITE);
  if (neg(fd)) return;
  report(f3_op(OP_TRUNCATE, fd, 0, strtoul(av[2], 0, 0), 0));
  f3_close(fd);
}

/* BENCH file: the same file read three ways */
static void cmd_bench(void)
{
  int16_t fd;
  uint32_t t, k, n, total;
  uint8_t way, e;
  if (report(f3_stat(av[1]))) return;
  n = get32(buf + ENT_SIZE) >> 9;
  if (!n) {
    printf("too small\n");
    return;
  }
  for (way = 0; way < 3; way++) {
    fd = f3_open(av[1], way == 2 ? O_USEFD : 0);
    if (fd < 0) {
      printf("%s: ", way == 2 ? "$76" : "open");
      neg(fd);
      continue;
    }
    t = ticks();
    total = 0;
    e = 0;
    for (k = 0; k < n && !e; k++) {
      if (way == 0) e = f3_read(fd, 512) == 512 ? 0 : E_IO;
      else if (way == 1) e = f3_cmd(0x74, ((uint32_t)fd << 24) | k);
      else e = f3_cmd(0x76, 0);
      total += 512;
      if (f3_stop()) break;
    }
    f3_close(fd);
    printf("%s ", way == 0 ? "$71 read  " : way == 1 ? "$74 sector" : "$76 quick ");
    if (report(e)) continue;
    put_size(total);
    put_rate(total, ticks() - t);
  }
}

static void cmd_cache(void)
{
  uint8_t on = ac < 2 || lcase(av[1][1]) == 'n';
  sd_cache(on);
  printf("cache %s\n", on ? "on" : "off");
}

/* ------------------------------------------------------------------------ */
/* reading text files a line at a time (VERIFY, EXEC)                        */
/* ------------------------------------------------------------------------ */

static uint8_t lr_data[512];
static int16_t lr_fd = -1;
static uint16_t lr_n, lr_pos;

/* the next line (ASCII, without its end) into s -> 0 at the end */
static uint8_t lr_line(char *s, uint8_t max)
{
  uint8_t i = 0, any = 0;
  int16_t n;
  for (;;) {
    if (lr_pos == lr_n) {
      n = f3_read(lr_fd, 512);
      if (n <= 0) break;
      memcpy(lr_data, buf, n);
      lr_n = n;
      lr_pos = 0;
    }
    any = 1;
    if (lr_data[lr_pos] == 10) {
      lr_pos++;
      break;
    }
    if (lr_data[lr_pos] != 13 && i < max - 1) s[i++] = lr_data[lr_pos];
    lr_pos++;
  }
  s[i] = 0;
  return any;
}

static uint8_t lr_open(const char *path)
{
  lr_fd = f3_open(path, 0);
  lr_n = lr_pos = 0;
  if (lr_fd < 0) {
    neg(lr_fd);
    lr_fd = -1;
    return 0;
  }
  return 1;
}

static void lr_close(void)
{
  f3_close(lr_fd);
  lr_fd = -1;
}

/* an ASCII number (base 16 or 10) at *s, which moves past it and the spaces
   after it */
static uint32_t anum(char **s, uint8_t base)
{
  uint32_t v = 0;
  uint8_t c, d;
  for (;;) {
    c = (uint8_t)**s;
    if (c >= 0x30 && c <= 0x39) d = c - 0x30;
    else if (base == 16 && (c | 0x20) >= 0x61 && (c | 0x20) <= 0x66) d = (c | 0x20) - 0x61 + 10;
    else break;
    v = v * base + d;
    (*s)++;
  }
  while (**s == 0x20) (*s)++;
  return v;
}

/* VERIFY [manifest]: each line "crc32 size path" (path from the manifest's
   directory, UTF-8), as make_f3_testtree.py writes it */
static void cmd_verify(void)
{
  static char ln[200];
  static uint8_t raw[300];
  char *q;
  uint16_t dl, n;
  uint32_t want_crc, want_size, crc, size, good = 0, bad = 0, total = 0, t;
  uint8_t e;
  strcpy(p1, ac > 1 ? av[1] : "manifest.txt");
  if (!lr_open(p1)) return;
  *base(p1) = 0;
  /* the directory, as the engine has it */
  f3_path(p1);
  dl = strlen((char *)buf + 16);
  memcpy(raw, buf + 16, dl);
  if (dl && raw[dl - 1] != '/' && raw[dl - 1] != ':') raw[dl++] = '/';
  t = ticks();
  while (lr_line(ln, sizeof(ln))) {
    if (!ln[0] || ln[0] == '#') continue;
    q = ln;
    want_crc = anum(&q, 16);
    want_size = anum(&q, 10);
    n = strlen(q);
    memcpy(raw + dl, q, n);
    raw[dl + n] = 0;
    f3_rawpath(raw, dl + n);
    e = f3_op(OP_OPEN, 0, 0, 0, 0);
    if (!e) {
      int16_t fd = f3_resfd, k;
      crc = 0xFFFFFFFFUL;
      size = 0;
      while ((k = f3_read(fd, 512)) > 0) {
        crc = crc_update(crc, buf, k);
        size += k;
      }
      if (k < 0) e = (uint8_t)-k;
      f3_close(fd);
      crc ^= 0xFFFFFFFFUL;
    }
    if (e || crc != want_crc || size != want_size) {
      bad++;
      f3_show((uint8_t *)q);
      if (e) printf(": error %u: %s\n", e, f3_strerror(e));
      else printf(": %08lx %lu, not %08lx %lu\n", (unsigned long)crc, (unsigned long)size,
                    (unsigned long)want_crc, (unsigned long)want_size);
    } else {
      good++;
      total += size;
    }
    if (f3_stop()) break;
  }
  lr_close();
  printf("verify: %lu ok, %lu bad, ", (unsigned long)good, (unsigned long)bad);
  put_size(total);
  put_rate(total, ticks() - t);
  if (bad) failed = 1;
}

/* ------------------------------------------------------------------------ */
/* the command line                                                          */
/* ------------------------------------------------------------------------ */

static void split(char *s)
{
  ac = 0;
  while (*s && ac < MAXARGS) {
    while (*s == ' ') s++;
    if (!*s) break;
    if (*s == '"') {
      av[ac++] = ++s;
      while (*s && *s != '"') s++;
    } else {
      av[ac++] = s;
      while (*s && *s != ' ') s++;
    }
    if (*s) *s++ = 0;
  }
}

static uint8_t is(const char *a, const char *b)
{
  while (*a && lcase(*a) == *b) {
    a++;
    b++;
  }
  return !*a && !*b;
}

static const char help[] =
  "drives  rescan  c: .. j:  cd [dir]\n"
  "dir [spec]  md dir  rd dir\n"
  "type f  dump f [off [len]]  stat f\n"
  "copy spec dst  move spec dst\n"
  "ren old new  del spec\n"
  "attrib [+r|-r|+h|-h|+a|-a] f\n"
  "write f text  append f text\n"
  "mkfile f size [seed]  check f [seed]\n"
  "crc f  trunc f len  bench f\n"
  "verify [manifest]  cache on|off\n"
  "exec f  echo text  exit\n"
  "spec: * and ? in the last part\n";

/* -> 0 to leave */
static uint8_t run_line(char *s)
{
  static const char *const need[] = {
    "type", "dump", "stat", "md", "mkdir", "rd", "rmdir", "del", "crc", "check", "bench", "exec", 0 };
  uint8_t i, n;
  split(s);
  if (!ac || av[0][0] == '#' || av[0][0] == ';') return 1;
  failed = 0;
  f3_stopped = 0;
  for (i = 0; need[i]; i++)
    if (is(av[0], need[i]) && ac < 2) goto usage;
  if ((is(av[0], "copy") || is(av[0], "move") || is(av[0], "ren") || is(av[0], "mkfile")
       || is(av[0], "trunc")) && ac < 3) goto usage;
  if ((is(av[0], "write") || is(av[0], "append") || is(av[0], "attrib")) && ac < 2) goto usage;
  n = strlen(av[0]);
  if (n == 2 && av[0][1] == ':') cmd_setdrive(drive_of(av[0]));
  else if (is(av[0], "exit") || is(av[0], "quit")) return 0;
  else if (is(av[0], "help") || av[0][0] == '?') printf("%s", help);
  else if (is(av[0], "drives")) cmd_drives();
  else if (is(av[0], "rescan")) cmd_rescan();
  else if (is(av[0], "cd") || is(av[0], "chdir") || is(av[0], "pwd")) cmd_cd();
  else if (is(av[0], "dir") || is(av[0], "ls")) cmd_dir();
  else if (is(av[0], "md") || is(av[0], "mkdir")) report(f3_simple(OP_MKDIR, av[1]));
  else if (is(av[0], "rd") || is(av[0], "rmdir")) report(f3_simple(OP_RMDIR, av[1]));
  else if (is(av[0], "type") || is(av[0], "cat")) cmd_type();
  else if (is(av[0], "dump")) cmd_dump();
  else if (is(av[0], "copy") || is(av[0], "cp")) cmd_copy();
  else if (is(av[0], "move") || is(av[0], "mv")) cmd_move();
  else if (is(av[0], "ren") || is(av[0], "rename")) cmd_ren();
  else if (is(av[0], "del") || is(av[0], "rm")) cmd_del();
  else if (is(av[0], "attrib")) cmd_attrib();
  else if (is(av[0], "stat")) cmd_stat();
  else if (is(av[0], "write")) cmd_write(0);
  else if (is(av[0], "append")) cmd_write(1);
  else if (is(av[0], "mkfile")) cmd_mkfile();
  else if (is(av[0], "check")) cmd_check();
  else if (is(av[0], "crc")) cmd_crc();
  else if (is(av[0], "trunc")) cmd_trunc();
  else if (is(av[0], "bench")) cmd_bench();
  else if (is(av[0], "verify")) cmd_verify();
  else if (is(av[0], "cache")) cmd_cache();
  else if (is(av[0], "echo")) {
    for (i = 1; i < ac; i++) printf(i + 1 < ac ? "%s " : "%s", av[i]);
    printf("\n");
  } else if (is(av[0], "exec")) {
    static char ln[100];
    if (lr_fd >= 0) {
      printf("exec does not nest\n");
      return 1;
    }
    if (!lr_open(av[1])) return 1;
    while (lr_line(ln, sizeof(ln))) {
      ascii_to_local(line, (uint8_t *)ln, sizeof(line));
      show_prompt();
      printf("%s\n", line);
      if (!run_line(line)) break;
    }
    lr_close();
  } else {
    printf("unknown command (help lists them)\n");
    failed = 1;
  }
  return 1;
usage:
  printf("%s: missing arguments (help)\n", av[0]);
  failed = 1;
  return 1;
}

int main(int argc, char **argv)
{
  (void)argc;
  (void)argv;
  f3_init();
#ifdef HOST
  paging = 0;
#endif
  printf("f3dos: the hardware fat32 engine\n");
  if (!report(f3_op(OP_RESCAN, 0, 0, 0, 0)))
    cmd_drives();
  for (;;) {
    show_prompt();
    if (!fgets(line, sizeof(line), stdin)) break;
    line[strcspn(line, "\r\n")] = 0;
#ifdef HOST
    if (!isatty(0)) printf("%s\n", line);
#endif
    if (!run_line(line)) break;
  }
  printf("\n");
  return 0;
}
