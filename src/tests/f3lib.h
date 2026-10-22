/*
  f3lib: the hardware FAT32 engine's interface, for f3dos and f3test.
  MEGA65/mega65-core#766 (docs/sdcard-native/fat32-engine.md).

  Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project.
  LGPL v3 (see LICENSE.txt).

  On the MEGA65 it drives $D680-$D687 and the SD half of the sector buffer
  at $DE00.  Built with -DHOST it sends each command through a pipe to
  src/tools/f3bridge.py, which runs the engine's firmware on the
  instruction-set simulator against disk image files.

  Strings: the program's own strings are in its compiler's character set
  (PETSCII on the MEGA65, with cc65's mapping); the engine's are ASCII and
  UTF-8.  f3_path() and f3_show() convert at that boundary.
*/

#ifndef F3LIB_H
#define F3LIB_H

#include <stdint.h>

/* errors (the engine's status codes) */
#define E_NOENT   1
#define E_NOTDIR  2
#define E_ISDIR   3
#define E_BADFD   4
#define E_NFILE   5
#define E_NODRV   6
#define E_IO      7
#define E_END     8
#define E_ACCESS  9
#define E_BADREQ 10
#define E_LONG   11
#define E_EXIST  12
#define E_NOTEMPTY 13
#define E_NOSPC  14
#define E_ROFS   15
#define E_STALE  16
#define E_BUSY   17
#define E_FRAG   18
#define E_TIMEOUT 0xFE          /* (f3lib's own: the controller never finished) */

/* $70 operations */
#define OP_RESCAN   0x01
#define OP_PARTS    0x02
#define OP_SETDRIVE 0x03
#define OP_OPENDIR  0x10
#define OP_READDIR  0x11
#define OP_CHDIR    0x12
#define OP_GETCWD   0x13
#define OP_MKDIR    0x14
#define OP_RMDIR    0x15
#define OP_OPEN     0x20
#define OP_CREATE   0x21
#define OP_CLOSE    0x22
#define OP_SEEK     0x23
#define OP_STAT     0x24
#define OP_DELETE   0x25
#define OP_RENAME   0x26
#define OP_SETATTR  0x27
#define OP_TRUNCATE 0x28
#define OP_FLUSH    0x29

/* open flags */
#define O_WRITE  0x01
#define O_APPEND 0x02
#define O_USEFD  0x80

/* attributes */
#define A_RO   0x01
#define A_HID  0x02
#define A_SYS  0x04
#define A_DIR  0x10
#define A_ARC  0x20

/* a readdir / stat response (offsets in buf) */
#define ENT_ATTR   16
#define ENT_SIZE   20
#define ENT_FIRST  24
#define ENT_TIME   28
#define ENT_SHORT  32
#define ENT_LONG   48

extern uint8_t *buf;            /* the SD half of the sector buffer (512 bytes) */
extern uint32_t f3_res0, f3_res1;   /* results: $D681-$D684, or arg0/arg1 of a $70 */
extern uint8_t f3_resfd;        /* the response's fd byte */
extern uint8_t f3_stopped;      /* RUN/STOP seen by f3_stop() */

void f3_init(void);
uint32_t get32(const uint8_t *p);
void put32(uint8_t *p, uint32_t v);

/* one command; arg in $D681-$D684 -> the status (0 = ok), f3_res0 = $D681-$D684 */
uint8_t f3_cmd(uint8_t code, uint32_t arg);
/* a $70 request: put the path(s) in first (f3_path), then f3_op */
uint8_t f3_op(uint8_t op, uint8_t fd, uint8_t flags, uint32_t a0, uint32_t a1);
/* a path, in the program's characters, into the request at +16 (or after
   the first one: f3_path2): drive letters C: to J: become 1: to 8:, \ becomes /.
   -> 0, or E_LONG */
uint8_t f3_path(const char *p);
uint8_t f3_path2(const char *p);
/* raw bytes (UTF-8) as the path */
void f3_rawpath(const uint8_t *p, uint16_t n);

/* conveniences: >= 0 the result, < 0 -(error) */
int16_t f3_open(const char *path, uint8_t flags);
int16_t f3_create(const char *path, uint8_t attr);
uint8_t f3_close(uint8_t fd);
int16_t f3_read(uint8_t fd, uint16_t n);     /* the bytes are at buf */
int16_t f3_write(uint8_t fd, uint16_t n);    /* from buf */
uint8_t f3_seek(uint8_t fd, uint32_t off, uint8_t whence);   /* f3_res0 = the position */
uint8_t f3_stat(const char *path);           /* the entry at buf+16 */
uint8_t f3_simple(uint8_t op, const char *path);              /* mkdir, chdir, delete, ... */

/* characters */
char to_ascii(char c);          /* the program's character -> ASCII */
char from_ascii(char c);        /* ASCII -> the program's (0: none) */
void f3_show(const uint8_t *s); /* print an ASCII / UTF-8 string from the engine */
void f3_shown(const uint8_t *s, uint8_t width);   /* ... padded to width */
void ascii_to_local(char *dst, const uint8_t *src, uint8_t n);
char lcase(char c);             /* lower case, in the program's characters */
const char *f3_strerror(uint8_t e);

/* raw sectors (for checking the engine against the card) */
uint8_t sd_select(uint8_t slot);
uint8_t sd_read(uint32_t sector);
void sd_cache(uint8_t on);

/* time, in tenths of a second */
uint32_t ticks(void);
uint8_t f3_stop(void);          /* RUN/STOP pressed? (sets f3_stopped) */
void f3_putc(char c);

/* test data: byte o of a file with this seed */
void pat_fill(uint8_t *p, uint32_t off, uint16_t n, uint8_t seed);
int16_t pat_check(const uint8_t *p, uint32_t off, uint16_t n, uint8_t seed);   /* -1 or the first bad index */

/* CRC-32 (as zlib) */
void crc_init(void);
uint32_t crc_update(uint32_t crc, const uint8_t *p, uint16_t n);

#endif
