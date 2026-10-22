/*
  f3lib: the hardware FAT32 engine's interface, for f3dos and f3test.
  MEGA65/mega65-core#766.  See f3lib.h.

  Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project.
  LGPL v3 (see LICENSE.txt).
*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "f3lib.h"

uint8_t *buf;
uint32_t f3_res0, f3_res1;
uint8_t f3_resfd;
uint8_t f3_stopped;
static uint8_t cur_slot;

uint32_t get32(const uint8_t *p)
{
  return p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

void put32(uint8_t *p, uint32_t v)
{
  p[0] = v;
  p[1] = v >> 8;
  p[2] = v >> 16;
  p[3] = v >> 24;
}

/* ------------------------------------------------------------------------ */
/* the controller: a pipe to f3bridge.py, or the MEGA65's registers          */
/* ------------------------------------------------------------------------ */

#ifdef HOST

#include <time.h>
#include <unistd.h>

static uint8_t host_buf[512];
static int br_in = -1, br_out = -1;

static void xfer(int fd, uint8_t *p, int n, int out)
{
  while (n > 0) {
    int k = out ? write(fd, p, n) : read(fd, p, n);
    if (k <= 0) {
      fprintf(stderr, "f3lib: the bridge went away\n");
      exit(2);
    }
    p += k;
    n -= k;
  }
}

/* message: code, arg (4), slot, the buffer (512) -> status, arg (4), the buffer */
static uint8_t bridge(uint8_t code, uint32_t arg)
{
  uint8_t m[6];
  m[0] = code;
  put32(m + 1, arg);
  m[5] = cur_slot;
  xfer(br_out, m, 6, 1);
  xfer(br_out, host_buf, 512, 1);
  xfer(br_in, m, 5, 0);
  xfer(br_in, host_buf, 512, 0);
  f3_res0 = get32(m + 1);
  return m[0];
}

void f3_init(void)
{
  const char *e = getenv("F3_BRIDGE");
  if (!e || sscanf(e, "%d,%d", &br_in, &br_out) != 2) {
    fprintf(stderr, "run this under src/tools/f3bridge.py\n");
    exit(2);
  }
  buf = host_buf;
  crc_init();
}

uint8_t f3_cmd(uint8_t code, uint32_t arg)
{
  return bridge(code, arg);
}

uint8_t sd_select(uint8_t slot)
{
  cur_slot = slot;
  return 1;
}

uint8_t sd_read(uint32_t sector)
{
  return bridge(0x02, sector);
}

void sd_cache(uint8_t on)
{
  bridge(on ? 0x25 : 0x26, 0);
}

uint32_t ticks(void)
{
  return (uint32_t)(clock() / (CLOCKS_PER_SEC / 10));
}

uint8_t f3_stop(void)
{
  return f3_stopped;
}

void f3_putc(char c)
{
  putchar(c);
}

#else  /* the MEGA65 */

#define POKE(a, v) (*((volatile uint8_t *)(a)) = (uint8_t)(v))
#define PEEK(a) (*((volatile uint8_t *)(a)))

void f3_init(void)
{
  POKE(0xD02F, 0x47);                 /* VIC-IV registers */
  POKE(0xD02F, 0x53);
  POKE(0, 65);                        /* full speed */
  POKE(0xD680, 0x81);                 /* sector buffer at $DE00 */
  POKE(0xD689, 0x80);                 /* ... the SD card half of it */
  buf = (uint8_t *)0xDE00;
  putchar(14);                        /* upper and lower case */
  crc_init();
}

/* wait for the controller (bit 0; an error keeps the legacy busy bit 1):
   about 30 s at most, as deleting a large file can take a while */
static uint8_t sd_wait(void)
{
  uint16_t a, b;
  for (a = 0; a < 30000; a++)
    for (b = 0; b < 1000; b++)
      if (!(PEEK(0xD680) & 0x01))
        return 1;
  return 0;
}

uint8_t f3_cmd(uint8_t code, uint32_t arg)
{
  POKE(0xD681, arg);
  POKE(0xD682, arg >> 8);
  POKE(0xD683, arg >> 16);
  POKE(0xD684, arg >> 24);
  POKE(0xD680, code);
  if (!sd_wait()) return E_TIMEOUT;
  f3_res0 = PEEK(0xD681) | ((uint16_t)PEEK(0xD682) << 8) | ((uint32_t)PEEK(0xD683) << 16)
          | ((uint32_t)PEEK(0xD684) << 24);
  if (!(PEEK(0xD680) & 0x40)) return 0;
  return PEEK(0xD687) ? PEEK(0xD687) : E_IO;
}

uint8_t sd_select(uint8_t slot)
{
  cur_slot = slot;
  POKE(0xD680, slot ? 0xC1 : 0xC0);
  if ((PEEK(0xD686) & 1) && !(PEEK(0xD680) & 0x43)) return 1;
  POKE(0xD680, 0x00);
  POKE(0xD680, 0x01);
  sd_wait();
  return !(PEEK(0xD680) & 0x40) && (PEEK(0xD686) & 1);
}

uint8_t sd_read(uint32_t sector)
{
  return f3_cmd(0x02, sector);
}

void sd_cache(uint8_t on)
{
  f3_cmd(on ? 0x25 : 0x26, 0);
}

/* CIA 1 time of day, in tenths of a second (it runs from power-on) */
uint32_t ticks(void)
{
  uint8_t t, s, m, h;
  h = PEEK(0xDC0B) & 0x1f;            /* reading the hours latches the clock */
  m = PEEK(0xDC0A);
  s = PEEK(0xDC09);
  t = PEEK(0xDC08);                   /* ... reading tenths releases it */
  return t + 10UL * ((s >> 4) * 10 + (s & 15))
           + 600UL * ((m >> 4) * 10 + (m & 15))
           + 36000UL * ((h >> 4) * 10 + (h & 15));
}

uint8_t f3_stop(void)
{
  if (PEEK(0x91) == 0x7F) f3_stopped = 1;     /* the KERNAL's STOP key flag */
  return f3_stopped;
}

void f3_putc(char c)
{
  putchar(c);
}

#endif

/* ------------------------------------------------------------------------ */
/* requests                                                                  */
/* ------------------------------------------------------------------------ */

static uint16_t path_end;       /* where f3_path2 goes */

uint8_t f3_op(uint8_t op, uint8_t fd, uint8_t flags, uint32_t a0, uint32_t a1)
{
  uint8_t s;
  buf[0] = 0x46;                      /* "F3", in ASCII whatever the compiler's set */
  buf[1] = 0x33;
  buf[2] = 1;
  buf[3] = op;
  buf[4] = fd;
  buf[5] = flags;
  put32(buf + 6, a0);
  put32(buf + 10, a1);
  s = f3_cmd(0x70, 0);
  if (s == E_TIMEOUT) return s;
  /* the status is in the response too: it is the one that counts */
  s = buf[3];
  f3_resfd = buf[4];
  f3_res0 = get32(buf + 6);
  f3_res1 = get32(buf + 10);
  return s;
}

static uint8_t put_path(uint16_t at, const char *p)
{
  uint16_t i = at;
  char c;
  if (p[0] && p[1] == ':') {
    c = lcase(p[0]);
    if (c >= 'c' && c <= 'j') {
      buf[i++] = 0x31 + (c - 'c');
      buf[i++] = ':';
      p += 2;
    }
  }
  while (*p) {
    if (i >= 510) return E_LONG;
    c = to_ascii(*p++);
    buf[i++] = c == 0x5C ? 0x2F : c;           /* \ -> / (ASCII: not literals, which cc65 translates) */
  }
  buf[i++] = 0;
  path_end = i;
  return 0;
}

uint8_t f3_path(const char *p)
{
  return put_path(16, p);
}

uint8_t f3_path2(const char *p)
{
  return put_path(path_end, p);
}

void f3_rawpath(const uint8_t *p, uint16_t n)
{
  memcpy(buf + 16, p, n);
  buf[16 + n] = 0;
  path_end = 17 + n;
}

int16_t f3_open(const char *path, uint8_t flags)
{
  uint8_t s = f3_path(path);
  if (!s) s = f3_op(OP_OPEN, 0, flags, 0, 0);
  return s ? -(int16_t)s : f3_resfd;
}

int16_t f3_create(const char *path, uint8_t attr)
{
  uint8_t s = f3_path(path);
  if (!s) s = f3_op(OP_CREATE, 0, 0, attr, 0);
  return s ? -(int16_t)s : f3_resfd;
}

uint8_t f3_close(uint8_t fd)
{
  return f3_op(OP_CLOSE, fd, 0, 0, 0);
}

int16_t f3_read(uint8_t fd, uint16_t n)
{
  uint8_t s = f3_cmd(0x71, ((uint32_t)fd << 24) | n);
  return s ? -(int16_t)s : (int16_t)(f3_res0 & 0xFFFF);
}

int16_t f3_write(uint8_t fd, uint16_t n)
{
  uint8_t s = f3_cmd(0x72, ((uint32_t)fd << 24) | n);
  return s ? -(int16_t)s : (int16_t)(f3_res0 & 0xFFFF);
}

uint8_t f3_seek(uint8_t fd, uint32_t off, uint8_t whence)
{
  return f3_op(OP_SEEK, fd, whence, off, 0);
}

uint8_t f3_stat(const char *path)
{
  uint8_t s = f3_path(path);
  return s ? s : f3_op(OP_STAT, 0, 0, 0, 0);
}

uint8_t f3_simple(uint8_t op, const char *path)
{
  uint8_t s = f3_path(path);
  return s ? s : f3_op(op, 0, 0, 0, 0);
}

/* ------------------------------------------------------------------------ */
/* characters                                                                */
/* ------------------------------------------------------------------------ */

#ifdef HOST

char to_ascii(char c) { return c; }
char from_ascii(char c) { return c; }
char lcase(char c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }

void ascii_to_local(char *dst, const uint8_t *src, uint8_t n)
{
  strncpy(dst, (const char *)src, n);
  dst[n - 1] = 0;
}

void f3_show(const uint8_t *s)
{
  fputs((const char *)s, stdout);
}

#else

/* cc65's c64 character set: a-z $41-$5A, A-Z $C1-$DA, _ $A4, ~ $B1,
   \ $BF, ` $AD, { $B3, | $DD, } $AB (other printable ASCII as it is) */
char to_ascii(char c)
{
  uint8_t u = c;
  if (u >= 0x41 && u <= 0x5A) return u + 0x20;
  if (u >= 0xC1 && u <= 0xDA) return u - 0x80;
  if (u >= 0x61 && u <= 0x7A) return u - 0x20;
  switch (u) {
  case 0xA4: case 0x5F: return 0x5F;
  case 0xB1: return 0x7E;
  case 0xBF: case 0x5C: return 0x5C;
  case 0xAD: return 0x60;
  case 0xB3: return 0x7B;
  case 0xDD: return 0x7C;
  case 0xAB: return 0x7D;
  }
  return c;
}

char from_ascii(char c)
{
  uint8_t u = c;
  if (u >= 0x61 && u <= 0x7A) return u - 0x20;
  if (u >= 0x41 && u <= 0x5A) return u + 0x80;
  switch (u) {
  case 0x5F: return 0xA4;
  case 0x7E: return 0xB1;
  case 0x5C: return 0xBF;
  case 0x60: return 0xAD;
  case 0x7B: return 0xB3;
  case 0x7C: return 0xDD;
  case 0x7D: return 0xAB;
  }
  if (u < 0x20 || u > 0x7E) return 0;
  return c;
}

char lcase(char c)
{
  uint8_t u = c;
  if (u >= 0xC1 && u <= 0xDA) return u - 0x80;
  if (u >= 0x61 && u <= 0x7A) return u - 0x20;
  return c;
}

/* non-ASCII characters: '?' (one per character) */
void ascii_to_local(char *dst, const uint8_t *src, uint8_t n)
{
  uint8_t i = 0;
  char c;
  while (*src && i < n - 1) {
    if (*src >= 0x80 && *src < 0xC0) {         /* a continuation byte */
      src++;
      continue;
    }
    c = *src >= 0x80 ? 0 : from_ascii(*src);
    dst[i++] = c ? c : '?';
    src++;
  }
  dst[i] = 0;
}

void f3_show(const uint8_t *s)
{
  char c;
  for (; *s; s++) {
    if (*s >= 0x80 && *s < 0xC0) continue;
    c = *s >= 0x80 ? 0 : from_ascii(*s);
    putchar(c ? c : '?');
  }
}

#endif

/* (the width counts characters, not bytes) */
void f3_shown(const uint8_t *s, uint8_t width)
{
  uint8_t n = 0;
  const uint8_t *p;
  for (p = s; *p; p++)
    if (*p < 0x80 || *p >= 0xC0) n++;
  f3_show(s);
  while (n++ < width) f3_putc(' ');
}

static const char *const errs[] = {
  "ok", "not found", "not a directory", "is a directory", "bad descriptor",
  "too many open files", "no such drive", "i/o error", "end", "access denied",
  "bad request", "name too long", "exists", "directory not empty", "disk full",
  "read-only", "stale descriptor", "busy", "fragmented"
};

const char *f3_strerror(uint8_t e)
{
  if (e == E_TIMEOUT) return "controller timeout";
  if (e < sizeof(errs) / sizeof(errs[0])) return errs[e];
  return "unknown error";
}

/* ------------------------------------------------------------------------ */
/* test data and checksums                                                   */
/* ------------------------------------------------------------------------ */

/* byte o: o ^ (o >> 8) * 31 ^ (o >> 16) * 101 ^ seed, so a sector or a
   cluster in the wrong place shows */
static uint8_t pat_hi(uint32_t off, uint8_t seed)
{
  return (uint8_t)(((uint8_t)(off >> 8)) * 31) ^ (uint8_t)(((uint8_t)(off >> 16)) * 101) ^ seed;
}

void pat_fill(uint8_t *p, uint32_t off, uint16_t n, uint8_t seed)
{
  uint8_t hi = pat_hi(off, seed), lo = off;
  while (n--) {
    *p++ = lo ^ hi;
    if (!++lo) {
      off = (off | 0xFF) + 1;
      hi = pat_hi(off, seed);
    }
  }
}

int16_t pat_check(const uint8_t *p, uint32_t off, uint16_t n, uint8_t seed)
{
  uint8_t hi = pat_hi(off, seed), lo = off;
  uint16_t i;
  for (i = 0; i < n; i++) {
    if (p[i] != (uint8_t)(lo ^ hi)) return i;
    if (!++lo) {
      off = (off | 0xFF) + 1;
      hi = pat_hi(off, seed);
    }
  }
  return -1;
}

static uint32_t crc_table[256];

void crc_init(void)
{
  uint16_t i;
  uint8_t k;
  uint32_t c;
  for (i = 0; i < 256; i++) {
    c = i;
    for (k = 0; k < 8; k++)
      c = (c & 1) ? 0xEDB88320UL ^ (c >> 1) : c >> 1;
    crc_table[i] = c;
  }
}

/* start with 0xFFFFFFFF, finish with ^ 0xFFFFFFFF */
uint32_t crc_update(uint32_t crc, const uint8_t *p, uint16_t n)
{
  while (n--)
    crc = crc_table[(uint8_t)crc ^ *p++] ^ (crc >> 8);
  return crc;
}
