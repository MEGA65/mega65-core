/*
  sdstress: stress test of the SD controller's command sequences, for the
  MEGA65.  MEGA65/mega65-core#890 (native SD controller), #953 (sector cache).

  Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project.
  LGPL v3 (see LICENSE.txt).

  sdtest checks that sectors get written and read back; sdstress checks the
  orders in which real software issues commands, where the bugs live:

  1. INIT REPORT (reads only): for each slot, initialise the card normally
     and at default speed ($24), and show $D686/$D687, the bus it ended up
     on, its CID, and why the native bus was given up if it was (the
     controller's init record, $D6CE/$D6CF bytes 17-23).

  2. F011 COMPARE (reads only, any card): with a D81 mounted on drive 0 (the
     usual way), read its sectors through the F011 and compare each with a
     raw read of the same card sector, in the orders a disk loader uses
     (whole tracks, both sides) and at random, with other raw reads, cache
     changes and multi-sector reads mixed in.

  3. STRESS (DESTRUCTIVE, a scratch card): a region of 4096 sectors gets
     random sequences of operations, with random delays (none, short, long)
     before each command:
       - single reads ($02), runs of single reads (the cache's read-ahead
         stream), multi-sector reads ($07/$08/$09), left open or ended with
         $0A or by the next command;
       - single writes ($03), multi-sector writes ($04/$05/$06), some ended
         early;
       - "freeze": a run of reads (stream open), then at once a long
         multi-sector write and the range read back, as Hyppo's freeze and
         resume do;
       - a write into the middle of an open multi-sector read;
       - cache on/off/empty ($25/$26/$27), $2A, and now and then a reset in
         the middle of an open transfer.
     Every sector says what it is (as in sdtest: "SDT1", its sector, the
     stage that wrote it, the seed, a checksum, then a pseudo-random
     stream), and a table holds the stage each sector should have.  On a
     mismatch the sector is read again with the cache emptied, which tells
     a stale cache (right data on the card) from a wrong card, and the last
     operations are listed.  The whole region is checked every 500
     operations, cache on and cache off.  Any key stops it.

  Load it with m65 over JTAG.  STRESS only runs on a card whose sector 0 is
  not a valid MBR (or holds sdtest/sdstress data), after "this will destroy
  card contents" is typed in.

  Build for the MEGA65:  cl65 -t c64 -O -Or -Oi -Os -o sdstress.prg sdstress.c
  Build for a PC (a simulated card and controller, with faults to find):
                         cc -DHOST -O2 -o sdstress_host sdstress.c
     ./sdstress_host FAULT AT < script    (src/tools/test_sdstress.py)
*/

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

#define REGION 4096U            /* sectors under test */

static uint8_t *buf;            /* the sector buffer at $DE00 (SD or F011 half) */

/* ------------------------------------------------------------------------ */
/* the card: MEGA65 registers, or a simulation                               */
/* ------------------------------------------------------------------------ */

#ifdef HOST

/* A simulated card and controller.  sim_fault selects a fault for the test
   to find, at the sim_fault_at'th write (from 1):
     1 the write goes to the sector before   2 the write is lost
     3 a byte of it is flipped               4 the cache keeps the old data
                                               of that sector (until $26/$27/$2A)
     5 F011 reads return the next sector of the image
   sim_fault 9: no fault, but sector 0 holds a valid MBR. */
#define SIM_SECTORS 32768UL
#define SIM_IMAGE 20000UL       /* a D81 image here */
static uint8_t *sim_card;
static uint8_t sim_sbuf[512], sim_fbuf[512];
static int sim_fault = 0;
static uint32_t sim_fault_at = 0, sim_writes = 0;
static uint32_t sim_stale = 0xFFFFFFFFUL;
static uint8_t sim_stale_data[512];
static uint32_t sim_sector, sim_open = 0xFFFFFFFFUL;
static int sim_cache = 1;
static uint8_t regs[256], fregs[16];

static void sim_write(uint32_t s)
{
  sim_writes++;
  if (sim_fault && sim_writes == sim_fault_at) {
    if (sim_fault == 1) s--;
    else if (sim_fault == 2) return;
    else if (sim_fault == 3) { memcpy(sim_card + s * 512, sim_sbuf, 512); sim_card[s * 512 + 300] ^= 0x40; return; }
    else if (sim_fault == 4) { sim_stale = s; memcpy(sim_stale_data, sim_card + s * 512, 512); }
  }
  if (s < SIM_SECTORS) memcpy(sim_card + s * 512, sim_sbuf, 512);
}

static void sim_read(uint32_t s)
{
  if (s == sim_stale && sim_cache) memcpy(sim_sbuf, sim_stale_data, 512);
  else if (s < SIM_SECTORS) memcpy(sim_sbuf, sim_card + s * 512, 512);
  else memset(sim_sbuf, 0, 512);
}

static void POKE(uint16_t a, uint8_t v)
{
  if (a >= 0xD080 && a <= 0xD086) {
    fregs[a & 15] = v;
    if (a == 0xD081 && v == 0x40) {
      uint32_t s = SIM_IMAGE + fregs[4] * 20UL + fregs[6] * 10UL + fregs[5] - 1;
      if (sim_fault == 5) s++;
      memcpy(sim_fbuf, sim_card + s * 512, 512);
    }
    return;
  }
  if (a == 0xD689) { buf = (v & 0x80) ? sim_sbuf : sim_fbuf; return; }
  if (a == 0xD6CE || a == 0xD6DC) { regs[a & 0xff] = v; return; }
  if (a >= 0xD681 && a <= 0xD684) {
    regs[a & 0xff] = v;
    sim_sector = regs[0x81] | ((uint32_t)regs[0x82] << 8) | ((uint32_t)regs[0x83] << 16) | ((uint32_t)regs[0x84] << 24);
    return;
  }
  if (a != 0xD680) return;
  switch (v) {
  case 0x02: case 0x0B: sim_read(sim_sector); break;
  case 0x07: sim_open = sim_sector; sim_read(sim_open); break;
  case 0x08: sim_read(++sim_open); break;
  case 0x09: sim_read(++sim_open); sim_open = 0xFFFFFFFFUL; break;
  case 0x03: sim_write(sim_sector); break;
  case 0x04: sim_open = sim_sector; sim_write(sim_open); break;
  case 0x05: sim_write(++sim_open); break;
  case 0x06: sim_write(++sim_open); sim_open = 0xFFFFFFFFUL; break;
  case 0x0A: sim_open = 0xFFFFFFFFUL; break;
  case 0x25: sim_cache = 1; break;
  case 0x26: sim_cache = 0; sim_stale = 0xFFFFFFFFUL; break;
  case 0x27: case 0x2A: case 0x00: case 0x24: sim_stale = 0xFFFFFFFFUL; break;
  case 0x2D: memset(sim_sbuf, 0, 512); memcpy(sim_sbuf, "\x03SDSL16G\x80", 9); break;
  default: break;
  }
}

static uint8_t PEEK(uint16_t a)
{
  if (a == 0xD680) return 0x00;          /* never busy, no error */
  if (a == 0xD686) return 0x0F;          /* ready, native, high speed, SDHC */
  if (a == 0xD687) return 0;
  if (a == 0xD682 || a == 0xD683 || a == 0xD684 || a == 0xD681) return regs[a & 0xff];
  if (a == 0xD68A) return 0x00;          /* the image is on the internal card */
  if (a == 0xD68B) return 0x03;          /* drive 0: image, present */
  if (a >= 0xD68C && a <= 0xD68F) return (uint8_t)(SIM_IMAGE >> (8 * (a - 0xD68C)));
  if (a == 0xD6CC) return 0x53;
  if (a == 0xD6D9) return 0xA3;          /* capacity known, limit on */
  if (a == 0xD6DD) return (uint8_t)((SIM_SECTORS - 1) >> (8 * (regs[0xDC] & 3)));
  return 0;                               /* $D082: never busy, found */
}

static void hw_init(void)
{
  uint32_t i;
  sim_card = calloc(SIM_SECTORS, 512);
  if (!sim_card) { printf("no memory for the simulated card\n"); exit(1); }
  for (i = 0; i < 1600 * 512UL; i++) sim_card[SIM_IMAGE * 512 + i] = (uint8_t)(i * 7 + (i >> 9));
  for (i = 0; i < 1600; i++) memcpy(sim_card + (SIM_IMAGE + i) * 512, &i, sizeof(i));
  buf = sim_sbuf;
}
static void spin(uint16_t n) { (void)n; }
static uint8_t key_pressed(void) { return 0; }
static char *read_line(char *s, int n) { if (!fgets(s, n, stdin)) s[0] = 0; s[strcspn(s, "\r\n")] = 0; return s; }

#else  /* the MEGA65 */

#define POKE(a, v) (*((volatile uint8_t *)(a)) = (uint8_t)(v))
#define PEEK(a) (*((volatile uint8_t *)(a)))

static void hw_init(void)
{
  POKE(0xD02F, 0x47);                 /* VIC-IV registers */
  POKE(0xD02F, 0x53);
  POKE(0, 65);                        /* full speed */
  POKE(0xD680, 0x81);                 /* sector buffer at $DE00 */
  POKE(0xD689, 0x80);                 /* ... the SD card half of it */
  buf = (uint8_t *)0xDE00;
  putchar(14);                        /* upper and lower case */
}

static void spin(uint16_t n)
{
  volatile uint16_t i;
  for (i = 0; i < n; i++) ;
}

/* a key in the hardware queue (taken out of it) */
static uint8_t key_pressed(void)
{
  if (!PEEK(0xD610)) return 0;
  POKE(0xD610, 0);
  return 1;
}

static char *read_line(char *s, int n)
{
  fgets(s, n, stdin);
  s[strcspn(s, "\r\n")] = 0;
  return s;
}

#endif

/* after a progress line (one screen row, begun with \r): on the MEGA65 a
   new line and the cursor back up to it (PETSCII 145), so that the next one
   overwrites it, and a report (which begins with a new line) goes below it;
   \r does nothing there ($0A) */
static void progress_end(void)
{
#ifdef HOST
  fflush(stdout);
#else
  putchar('\n');
  putchar(145);
#endif
}

/* forget the keys typed so far, and any still arriving for a moment (the
   RETURN of the last answer can reach the queue after it was read) */
static void drain_keys(void)
{
  uint8_t i;
  for (i = 0; i < 50; i++) {
    while (key_pressed()) ;
    spin(10000);
  }
}

/* ------------------------------------------------------------------------ */
/* random numbers                                                            */
/* ------------------------------------------------------------------------ */

static uint32_t rnd_state = 1;
static uint32_t rnd(void)
{
  rnd_state ^= rnd_state << 13;
  rnd_state ^= rnd_state >> 17;
  rnd_state ^= rnd_state << 5;
  return rnd_state;
}
static uint8_t rnd8(void) { return (uint8_t)rnd(); }

/* a random pause before a command: mostly none, some short, a few long
   (up to some milliseconds) */
static void pause(void)
{
  uint8_t r = rnd8();
  if (r < 140) return;
  if (r < 230) spin(r & 63);
  else spin((uint16_t)(r & 15) << 10);
}

/* ------------------------------------------------------------------------ */
/* SD controller commands                                                    */
/* ------------------------------------------------------------------------ */

static uint8_t sd_error;

/* wait for the controller; an empty slot can leave BUSY set, so give up
   after a while (several seconds) */
static void sd_wait(void)
{
  uint16_t a, b;
  for (a = 0; a < 2000; a++) {
    for (b = 0; b < 1000; b++) {
      if (!(PEEK(0xD680) & 0x03)) {
        if (PEEK(0xD680) & 0x40) sd_error = 1;
        return;
      }
    }
  }
  sd_error = 2;
}

static void sd_set_sector(uint32_t s)
{
  POKE(0xD681, s & 0xff);
  POKE(0xD682, (s >> 8) & 0xff);
  POKE(0xD683, (s >> 16) & 0xff);
  POKE(0xD684, (s >> 24) & 0xff);
}

static void sd_cmd(uint8_t c)
{
  POKE(0xD680, c);
  sd_wait();
}

/* a write command, with the write gate opened first */
static void sd_wcmd(uint8_t c)
{
  POKE(0xD680, 0x57);
  POKE(0xD680, c);
  sd_wait();
}

static void sd_reset(uint8_t how)
{
  sd_error = 0;
  if (how) {
    POKE(0xD680, how);
  } else {
    POKE(0xD680, 0x00);
    POKE(0xD680, 0x01);
  }
  sd_wait();
}

/* select a card; initialise it only if it is not ready */
static uint8_t sd_select(uint8_t slot)
{
  POKE(0xD680, slot ? 0xC1 : 0xC0);
  sd_error = 0;
  if ((PEEK(0xD686) & 1) && !(PEEK(0xD680) & 0x43)) return 1;
  sd_reset(0);
  return !sd_error && (PEEK(0xD686) & 1);
}

static void sd_buffer_sd(void) { POKE(0xD689, 0x80); }
static void sd_buffer_f011(void) { POKE(0xD689, 0x00); }

/* ------------------------------------------------------------------------ */
/* 1. init report                                                            */
/* ------------------------------------------------------------------------ */

static uint8_t diag_byte(uint8_t i)
{
  POKE(0xD6CE, i);
  return PEEK(0xD6CF);
}

/* the first data block since the card's last init whose CRC or end bit
   was wrong (diagnostic bytes 32-55; latch with $d6ce = $80 first) */
static void show_blk(void)
{
  uint8_t l, f = diag_byte(32);
  if (f & 32) printf("  dat0 went low alone while a block was awaited (busy)\n");
  if (!(f & 1)) return;
  printf("  failed block: set $%02x%02x lat %u #%u end $%x\n", diag_byte(35), diag_byte(34),
         diag_byte(36) | (diag_byte(37) << 8), diag_byte(33), (f >> 1) & 15);
  printf("  crc got/want:");
  for (l = 0; l < 4; l++) {
    if (l == 2) printf("\n               ");
    printf(" %02x%02x/%02x%02x", diag_byte(39 + 2 * l), diag_byte(38 + 2 * l),
           diag_byte(47 + 2 * l), diag_byte(46 + 2 * l));
  }
  printf("\n  first bytes %02x %02x\n", diag_byte(55), diag_byte(54));
}

static const char *step_name(uint8_t s)
{
  switch (s) {
  case 4: return "cmd55 (no sd-mode answer)";
  case 5: return "acmd41 (power-up)";
  case 7: return "cmd2 (cid)";
  case 8: return "cmd3 (rca)";
  case 21: return "cmd9 (csd)";
  case 10: return "cmd7 (select)";
  case 11: return "cmd55 before acmd6";
  case 12: return "acmd6 (4-bit bus)";
  case 15: return "cmd16 (block length)";
  case 13: return "the test read of block 0";
  default: return "?";
  }
}

static void show_status(void)
{
  uint8_t st = PEEK(0xD686), f, i;
  printf("  $d686=$%02x $d687=$%02x: %s%s%s%s\n", st, PEEK(0xD687),
         st & 1 ? "ready, " : "not ready, ", st & 2 ? "4-bit" : "spi",
         st & 4 ? ", high speed" : "", st & 8 ? ", sdhc" : "");
  if (PEEK(0xD6CC) != 0x53) return;
  POKE(0xD6CE, 0x80);                 /* latch the diagnostics */
  f = diag_byte(18);
  if (f & 1) {
    printf("  native bus given up at step %u: %s\n", diag_byte(17), step_name(diag_byte(17)));
    if (f & 2) printf("  - no response\n");
    else if (!(f & 4)) printf("  - response bad (crc, index or header)\n");
    printf("  - last response bits 39..8: $");
    for (i = 23; i >= 20; i--) printf("%02x", diag_byte(i));
    printf("\n");
  }
  if (f & 8) printf("  test read failed at high speed (error $%02x), retried at default speed\n", diag_byte(19));
  if (f & 16) printf("  test read failed at default speed (error $%02x)\n", diag_byte(19));
  if (f & 32) printf("  high speed not granted by the card\n");
  if (f & 64) printf("  native init failed once, tried again\n");
  if (f & 128) printf("  - its busy (dat0 low) did not end\n");
  show_blk();
}

static void show_cid(void)
{
  uint8_t i;
  sd_buffer_sd();
  sd_cmd(0x2D);
  if (sd_error) { printf("  (no cid)\n"); sd_error = 0; return; }
  printf("  cid: mid $%02x oid %c%c name ", buf[0], buf[1], buf[2]);
  for (i = 3; i < 8; i++) printf("%c", buf[i] >= 32 && buf[i] < 127 ? buf[i] : '.');
  printf(" rev %u.%u serial %02x%02x%02x%02x date %u/%u\n", buf[8] >> 4, buf[8] & 15,
         buf[9], buf[10], buf[11], buf[12], 2000 + ((buf[13] & 15) << 4) + (buf[14] >> 4), buf[14] & 15);
}

static void init_report(void)
{
  uint8_t slot;
  for (slot = 0; slot < 2; slot++) {
    printf("\nslot %u (%s):\n", slot, slot ? "micro-sd" : "full-size sd");
    POKE(0xD680, slot ? 0xC1 : 0xC0);
    /* first as booted: the init the hypervisor did, untouched */
    printf(" as booted: $d680=$%02x\n", PEEK(0xD680));
    show_status();
    printf(" normal init:\n");
    sd_reset(0);
    if (sd_error == 2) { printf("  no answer (empty slot?)\n"); continue; }
    show_status();
    if (!(PEEK(0xD686) & 1)) continue;
    show_cid();
    printf(" default speed init ($24):\n");
    sd_reset(0x24);
    show_status();
    printf(" normal init again:\n");
    sd_reset(0);
    show_status();
  }
}

/* ------------------------------------------------------------------------ */
/* test sectors (as sdtest)                                                  */
/* ------------------------------------------------------------------------ */

static uint32_t run_seed;
/* mode 3 resets the card in the middle of open reads (a card can be left
   needing a power cycle by that: it can be turned off) */
static uint8_t mid_resets = 1;
/* mode 3 stops at the first error, without the recovery after a
   controller error, so that the controller can be looked at as it is */
static uint8_t stop_first, stop_now;
/* mode 3 checks the card after every operation: the cache emptied, one
   sector read from the card (a card hung by an operation is found right
   after it, not at the next check of the region) */
static uint8_t check_each;

static uint8_t ga, gb, gc, gx;
#define GEN() (++gx, ga ^= gc ^ gx, gb += ga, gc = (uint8_t)((gc + (gb >> 1)) ^ ga))
static uint8_t gen(void)
{
  return GEN();
}

static void gen_key(uint32_t sector, uint16_t stage)
{
  uint32_t k = run_seed ^ (sector * 2654435761UL) ^ ((uint32_t)stage << 16) ^ stage;
  ga = k;
  gb = k >> 8;
  gc = k >> 16;
  gx = k >> 24;
  gen(); gen(); gen(); gen(); gen(); gen(); gen(); gen();
}

static uint16_t hdr_sum(const uint8_t *p)
{
  uint16_t s = 0x5A5A;
  uint8_t i;
  for (i = 0; i < 14; i++) s = (uint16_t)((s << 1) | (s >> 15)) ^ p[i];
  return s;
}

static void make_sector(uint8_t *p, uint32_t sector, uint16_t stage)
{
  uint16_t i, s;
  p[0] = 'S'; p[1] = 'D'; p[2] = 'T'; p[3] = '1';
  p[4] = sector; p[5] = sector >> 8; p[6] = sector >> 16; p[7] = sector >> 24;
  p[8] = stage; p[9] = stage >> 8;
  p[10] = run_seed; p[11] = run_seed >> 8; p[12] = run_seed >> 16; p[13] = run_seed >> 24;
  s = hdr_sum(p);
  p[14] = s; p[15] = s >> 8;
  gen_key(sector, stage);
  for (i = 16; i < 512; i++) p[i] = GEN();
}

/* 0: right, 1: another sector's data, 2: this sector, other stage,
   3: bytes differ, 4: not test data */
static uint16_t bad_bytes, first_bad;
static uint8_t sector_state(uint32_t sector, uint8_t stage)
{
  uint16_t i;
  uint32_t hs;
  if (!(buf[0] == 'S' && buf[1] == 'D' && buf[2] == 'T' && buf[3] == '1'
        && (buf[14] | (buf[15] << 8)) == hdr_sum(buf))) return 4;
  hs = buf[4] | ((uint32_t)buf[5] << 8) | ((uint32_t)buf[6] << 16) | ((uint32_t)buf[7] << 24);
  if (hs != sector) return 1;
  if (buf[8] != stage || buf[9] != 0) return 2;
  gen_key(sector, stage);
  bad_bytes = 0;
  for (i = 16; i < 512; i++) {
    if (buf[i] != GEN()) {
      if (!bad_bytes) first_bad = i;
      bad_bytes++;
    }
  }
  return bad_bytes ? 3 : 0;
}

static void describe(uint8_t state)
{
  switch (state) {
  case 1: printf("holds sector %lu stage %u",
                 (unsigned long)(buf[4] | ((uint32_t)buf[5] << 8) | ((uint32_t)buf[6] << 16) | ((uint32_t)buf[7] << 24)),
                 buf[8]); break;
  case 2: printf("holds stage %u (stale or lost write)", buf[8]); break;
  case 3: printf("%u bytes differ, first at %u", bad_bytes, first_bad); break;
  default: printf("not test data (%02x %02x %02x %02x)", buf[0], buf[1], buf[2], buf[3]); break;
  }
}

/* ------------------------------------------------------------------------ */
/* 3. stress                                                                 */
/* ------------------------------------------------------------------------ */

static uint32_t base;           /* first sector of the region */
static uint8_t stage_of[REGION];
static uint8_t cur_stage = 1;
static uint8_t cache_state = 1; /* 1 on, 0 off */

static uint32_t n_ops, n_read, n_written;
static uint32_t e_ctrl, e_cache, e_card;

/* the last operations */
#define HIST 12
static uint8_t h_op[HIST], h_len[HIST], h_flags[HIST];
static uint16_t h_sec[HIST];
static uint8_t h_at;
static const char *const op_names[] = {
  "read1", "readseq", "readmulti", "write1", "writemulti", "freeze",
  "cache", "clear", "reset", "verify", "write-in-read", "sweep"
};
enum { O_READ1, O_READSEQ, O_READMULTI, O_WRITE1, O_WRITEMULTI, O_FREEZE,
       O_CACHE, O_CLEAR, O_RESET, O_VERIFY, O_WRITEINREAD, O_SWEEP };

static void log_op(uint8_t op, uint16_t sec, uint8_t len, uint8_t flags)
{
  h_op[h_at] = op; h_sec[h_at] = sec; h_len[h_at] = len; h_flags[h_at] = flags;
  h_at = (h_at + 1) % HIST;
}

static void show_history(void)
{
  uint8_t i, k;
  printf("  last operations (oldest first):\n");
  for (i = 0; i < HIST; i++) {
    k = (h_at + i) % HIST;
    if (h_op[k] == 0xFF) continue;
    printf("   %s %lu+%u", op_names[h_op[k]], (unsigned long)(base + h_sec[k]), h_len[k]);
    if (h_flags[k]) printf(" (%s)", h_flags[k] == 1 ? "left open" : h_flags[k] == 2 ? "ended with $0a"
                           : h_flags[k] == 3 ? "cache off" : h_flags[k] == 4 ? "cache on" : "cache emptied");
    printf("\n");
  }
}

static uint8_t next_stage(void)
{
  if (++cur_stage == 0) cur_stage = 1;
  return cur_stage;
}

/* a sector of the region: half the time among the first 64 (so sectors are
   cached, rewritten and read again), else anywhere */
static uint16_t pick(uint16_t len)
{
  uint16_t lim = REGION - len;
  if (rnd8() & 1) return (uint16_t)(rnd() % (64 < lim ? 64 : lim));
  return (uint16_t)(rnd() % lim);
}

static void controller_error(const char *what, uint16_t rel)
{
  e_ctrl++;
  if (e_ctrl <= 10) {
    printf("\nCONTROLLER ERROR (%s, sector %lu): $d680=$%02x $d686=$%02x $d687=$%02x\n", what,
           (unsigned long)(base + rel),
           PEEK(0xD680), PEEK(0xD686), PEEK(0xD687));
    if (PEEK(0xD6CC) == 0x53) { POKE(0xD6CE, 0x80); show_blk(); }
    show_history();
  }
  if (stop_first) {
    /* leave the controller as it is, to be looked at */
    stop_now = 1;
    return;
  }
  /* recover: clear, else a reset */
  sd_error = 0;
  sd_cmd(0x2A);
  if (sd_error) sd_reset(0);
  sd_error = 0;
}

/* rewrite a sector with a new stage (after it was found wrong, or after a
   failed write left it unknown) */
static void repair(uint16_t rel)
{
  sd_buffer_sd();
  stage_of[rel] = next_stage();
  make_sector(buf, base + rel, stage_of[rel]);
  sd_set_sector(base + rel);
  sd_wcmd(0x03);
  sd_error = 0;
}

/* the buffer should hold sector rel */
static void check(uint16_t rel)
{
  uint8_t st = sector_state(base + rel, stage_of[rel]), st2;
  n_read++;
  if (!st) return;
  /* again, from the card: empty the cache first */
  sd_cmd(0x27);
  sd_set_sector(base + rel);
  sd_cmd(0x02);
  st2 = sd_error ? 9 : sector_state(base + rel, stage_of[rel]);
  if (!st2) e_cache++;
  else e_card++;
  if (stop_first) stop_now = 1;
  if (e_cache + e_card <= 20) {
    printf("\n%s: sector %lu ", st2 ? "WRONG ON THE CARD" : "STALE CACHE", (unsigned long)(base + rel));
    describe(st);
    if (!st2) printf("; from the card: right");
    else if (st2 != 9 && st2 != st) { printf("; from the card: "); describe(st2); }
    printf("\n");
    show_history();
  }
  if (st2) repair(rel);
  if (!cache_state) sd_cmd(0x26);
}

static void read1(uint16_t rel)
{
  pause();
  sd_set_sector(base + rel);
  sd_cmd(0x02);
  if (sd_error) controller_error("read", rel);
  else check(rel);
}

static void read_seq(uint16_t rel, uint8_t n)
{
  uint8_t i;
  for (i = 0; i < n; i++) read1(rel + i);
}

/* how: 0 read all and end with $09, 1 leave open, 2 end with $0a */
static void read_multi(uint16_t rel, uint8_t n, uint8_t how)
{
  uint8_t i, m = how ? 1 + rnd8() % n : n;
  for (i = 0; i < m; i++) {
    pause();
    if (i == 0) { sd_set_sector(base + rel); sd_cmd(n == 1 ? 0x02 : 0x07); }
    else sd_cmd(i == n - 1 && !how ? 0x09 : 0x08);
    if (sd_error) { controller_error("multi-read", rel + i); return; }
    check(rel + i);
  }
  if (how == 2 && n > 1) {
    pause();
    sd_cmd(0x0A);
    if (sd_error) controller_error("$0a after a read", rel);
  }
}

static void write1(uint16_t rel)
{
  stage_of[rel] = next_stage();
  make_sector(buf, base + rel, stage_of[rel]);
  pause();
  sd_set_sector(base + rel);
  sd_wcmd(0x03);
  n_written++;
  if (sd_error) { controller_error("write", rel); repair(rel); }
}

/* how: 0 write all ($06 last), 1 leave open, 2 end early with $0a;
   quick: no pauses (as the freeze) */
static void write_multi(uint16_t rel, uint16_t n, uint8_t how, uint8_t quick)
{
  uint16_t i, m = how ? 1 + rnd() % n : n;
  uint8_t stage = next_stage();
  for (i = 0; i < m; i++) {
    make_sector(buf, base + rel + i, stage);
    stage_of[rel + i] = stage;
    if (!quick) pause();
    if (n == 1) { sd_set_sector(base + rel); sd_wcmd(0x03); }
    else if (i == 0) { sd_set_sector(base + rel); sd_wcmd(0x04); }
    else sd_wcmd(i == n - 1 && !how ? 0x06 : 0x05);
    n_written++;
    if (sd_error) {
      controller_error("multi-write", rel + i);
      /* what got written is unknown: write it all again */
      for (; i != 0xFFFF; i--) repair(rel + i);
      return;
    }
  }
  if (how == 2 && n > 1) {
    pause();
    sd_cmd(0x0A);
    if (sd_error) controller_error("$0a after a write", rel);
  }
}

static void cache_op(void)
{
  uint8_t r = rnd8() % 3;
  if (r == 0) { sd_cmd(0x26); cache_state = 0; log_op(O_CACHE, 0, 0, 3); }
  else if (r == 1) { sd_cmd(0x25); cache_state = 1; log_op(O_CACHE, 0, 0, 4); }
  else { sd_cmd(0x27); log_op(O_CACHE, 0, 0, 5); }
  if (sd_error) controller_error("cache command", 0);
}

/* the whole region: in runs of 64, single reads (cache on: the read-ahead
   stream) or multi-sector reads */
static void sweep(void)
{
  uint16_t r;
  uint8_t k;
  for (k = 0; k < 2; k++) {
    sd_cmd(k ? 0x26 : 0x25);
    for (r = 0; r < REGION; r += 64) {
      if (k) read_multi(r, 64, 0);
      else read_seq(r, 64);
      /* (a key, or the first error when stopping there, ends it: a check
         whose reads each time out can take a long time) */
      if (stop_now || key_pressed()) { stop_now = 1; return; }
    }
  }
  sd_cmd(cache_state ? 0x25 : 0x26);
}

static void stress_op(void)
{
  uint8_t r = rnd8() & 31, n;
  uint16_t rel, len;
  n_ops++;
  sd_buffer_sd();
  if (r < 6) {
    rel = pick(1); log_op(O_READ1, rel, 1, 0); read1(rel);
  } else if (r < 10) {
    n = 1 + rnd8() % 40; rel = pick(n); log_op(O_READSEQ, rel, n, 0); read_seq(rel, n);
  } else if (r < 14) {
    n = 1 + rnd8() % 40; rel = pick(n);
    r = rnd8() % 4; if (r == 3) r = 0;
    log_op(O_READMULTI, rel, n, r); read_multi(rel, n, r);
  } else if (r < 18) {
    rel = pick(1); log_op(O_WRITE1, rel, 1, 0); write1(rel);
  } else if (r < 22) {
    n = 1 + rnd8() % 40; rel = pick(n);
    r = rnd8() % 4; if (r == 3) r = 0;
    log_op(O_WRITEMULTI, rel, n, r); write_multi(rel, n, r, 0);
  } else if (r < 24) {
    /* freeze: a stream open, then a long write at once, then read back */
    n = 4 + rnd8() % 30; rel = pick(n);
    read_seq(rel, n);
    len = 20 + rnd8() % 200; rel = pick(len);
    log_op(O_FREEZE, rel, (uint8_t)len, 0);
    write_multi(rel, len, 0, 1);
    for (len = len; len; len--, rel++) {
      sd_set_sector(base + rel);
      sd_cmd(0x02);
      if (sd_error) { controller_error("read after freeze", rel); break; }
      check(rel);
    }
  } else if (r < 26) {
    cache_op();
  } else if (r == 26) {
    log_op(O_CLEAR, 0, 0, 0); pause(); sd_cmd(0x2A);
    if (sd_error) controller_error("$2a", 0);
  } else if (r == 27) {
    if (mid_resets && rnd8() < 32) {
      /* a reset in the middle of an open multi-sector read */
      n = 8; rel = pick(n);
      log_op(O_RESET, rel, n, 0);
      sd_set_sector(base + rel); sd_cmd(0x07); sd_cmd(0x08);
      pause();
      sd_reset(0);
      if (sd_error) controller_error("reset", 0);
      if (!cache_state) sd_cmd(0x26);
    }
  } else if (r < 30) {
    n = 16; rel = pick(n); log_op(O_VERIFY, rel, n, 5);
    sd_cmd(0x27);
    read_multi(rel, n, 0);
  } else {
    /* a write into the middle of an open multi-sector read */
    n = 16; rel = pick(n);
    log_op(O_WRITEINREAD, rel, n, 1);
    read_multi(rel, n, 1);
    write1(rel + rnd8() % n);
    read_seq(rel, n);
  }
}

static void stress(uint32_t max_ops)
{
  uint16_t i, k;
  memset(h_op, 0xFF, sizeof(h_op));
  printf("\nwriting the region (%u sectors from %lu)...", REGION, (unsigned long)base);
  for (i = 0; i < REGION; i += 128) write_multi(i, 128, 0, 1);
  printf("\nchecking it...");
  sweep();
  printf(" errors: controller %lu, cache %lu, card %lu\n", (unsigned long)e_ctrl,
         (unsigned long)e_cache, (unsigned long)e_card);
  printf("stressing (any key stops)\n");
  drain_keys();
  for (k = 0; !max_ops || n_ops < max_ops; k++) {
    stress_op();
    if (check_each && !stop_now) {
      uint16_t rel = (uint16_t)(n_ops % REGION);
      sd_cmd(0x27);
      sd_set_sector(base + rel);
      sd_cmd(0x02);
      if (sd_error) controller_error("check after the operation", rel);
      else check(rel);
    }
    if (n_ops % 100 == 0) {
      printf("\rops %lu errors %lu/%lu/%lu  ", (unsigned long)n_ops,
             (unsigned long)e_ctrl, (unsigned long)e_cache, (unsigned long)e_card);
      progress_end();
    }
    if (stop_now) { printf("\nstopped at the first error (op %lu)\n", (unsigned long)n_ops); break; }
    if (n_ops % 500 == 0) { log_op(O_SWEEP, 0, 0, 0); sweep(); }
    if (key_pressed() || stop_now) break;
  }
  sweep();
  printf("\n\ndone: %lu operations, %lu sectors read, %lu written\n"
         "errors: controller %lu, stale cache %lu, wrong on the card %lu\n",
         (unsigned long)n_ops, (unsigned long)n_read, (unsigned long)n_written,
         (unsigned long)e_ctrl, (unsigned long)e_cache, (unsigned long)e_card);
}

/* ------------------------------------------------------------------------ */
/* 2. F011 compare                                                           */
/* ------------------------------------------------------------------------ */

static uint8_t fcopy[512];
static uint32_t img_start;
static uint32_t f_reads, f_bad, f_rnf;

/* read track/side/sector (1..10) through the F011, into fcopy */
static uint8_t f011_read(uint8_t track, uint8_t side, uint8_t sector)
{
  uint16_t t;
  POKE(0xD080, side ? 0x28 : 0x20);   /* drive 0, motor, side */
  POKE(0xD084, track);
  POKE(0xD085, sector);
  POKE(0xD086, side);
  POKE(0xD081, 0x40);
  for (t = 0; t < 60000U && (PEEK(0xD082) & 0x80); t++) ;
  if (PEEK(0xD082) & 0x80) return 2;
  if (PEEK(0xD082) & 0x10) return 1;
  sd_buffer_f011();
  memcpy(fcopy, buf, 512);
  sd_buffer_sd();
  return 0;
}

static void f011_check(uint8_t track, uint8_t side, uint8_t sector)
{
  uint32_t s = img_start + track * 20UL + side * 10 + sector - 1;
  uint8_t r;
  uint16_t i;
  f_reads++;
  pause();
  r = f011_read(track, side, sector);
  if (r) {
    f_rnf++;
    if (f_rnf <= 10) printf("\nF011 %s: track %u side %u sector %u\n", r == 2 ? "STUCK BUSY" : "RNF",
                            track, side, sector);
    return;
  }
  pause();
  sd_set_sector(s);
  sd_cmd(0x02);
  if (sd_error) { controller_error("raw read for f011", 0); return; }
  for (i = 0; i < 512 && fcopy[i] == buf[i]; i++) ;
  if (i == 512) return;
  f_bad++;
  if (f_bad <= 10) {
    uint32_t k;
    printf("\nF011 MISMATCH: track %u side %u sector %u (card sector %lu), first at byte %u\n",
           track, side, sector, (unsigned long)s, i);
    /* is it another sector of the image? */
    for (k = 0; k < 1600; k++) {
      sd_set_sector(img_start + k);
      sd_cmd(0x02);
      if (!memcmp(fcopy, buf, 512)) {
        printf("  the f011 data is image sector %lu (want %lu)\n", (unsigned long)k,
               (unsigned long)(s - img_start));
        break;
      }
    }
  }
}

static void f011_compare(uint32_t max_rounds)
{
  uint32_t round;
  uint8_t t, sd, sc, r;
  uint8_t slot = (PEEK(0xD68A) >> 4) & 1;
  if ((PEEK(0xD68B) & 3) != 3) {
    printf("no d81 mounted on drive 0: mount one first\n");
    return;
  }
  img_start = PEEK(0xD68C) | ((uint32_t)PEEK(0xD68D) << 8) | ((uint32_t)PEEK(0xD68E) << 16)
              | ((uint32_t)PEEK(0xD68F) << 24);
  printf("d81 on drive 0 at sector %lu of the %s card\n", (unsigned long)img_start,
         slot ? "external" : "internal");
  sd_select(slot);
  printf("comparing (any key stops)\n");
  drain_keys();
  for (round = 0; !max_rounds || round < max_rounds; round++) {
    r = rnd8() & 7;
    if (r < 3) {
      /* a whole track, both sides, as a loader would */
      t = rnd8() % 80;
      for (sd = 0; sd < 2; sd++)
        for (sc = 1; sc <= 10; sc++) f011_check(t, sd, sc);
    } else if (r < 6) {
      f011_check(rnd8() % 80, rnd8() & 1, 1 + rnd8() % 10);
    } else if (r == 6) {
      /* something else in between: raw reads (a stream) or a cache change */
      if (rnd8() & 1) {
        sd_set_sector(img_start + rnd() % 1500);
        for (t = 0; t < 20; t++) {
          sd_cmd(0x02);
          POKE(0xD681, PEEK(0xD681) + 1);
          if (!PEEK(0xD681)) { POKE(0xD682, PEEK(0xD682) + 1); }
        }
      } else {
        sd_cmd(rnd8() & 1 ? 0x27 : 0x25);
      }
    } else {
      /* an open multi-sector read left open, then the f011 */
      sd_set_sector(img_start + rnd() % 1500);
      sd_cmd(0x07);
      sd_cmd(0x08);
      f011_check(rnd8() % 80, rnd8() & 1, 1 + rnd8() % 10);
    }
    if (round % 20 == 0) {
      printf("\rf011 reads %lu bad %lu rnf %lu  ", (unsigned long)f_reads,
             (unsigned long)f_bad, (unsigned long)f_rnf);
      progress_end();
    }
    if (key_pressed()) break;
  }
  sd_cmd(0x25);
  printf("\n\ndone: %lu f011 reads, %lu mismatches, %lu rnf/stuck\n", (unsigned long)f_reads,
         (unsigned long)f_bad, (unsigned long)f_rnf);
}

/* ------------------------------------------------------------------------ */
/* setting up                                                                */
/* ------------------------------------------------------------------------ */

static uint8_t mbr_valid(void)
{
  uint8_t i, any = 0;
  uint8_t *e;
  if (buf[510] != 0x55 || buf[511] != 0xAA) return 0;
  for (i = 0; i < 4; i++) {
    e = buf + 446 + i * 16;
    if (e[4] == 0) continue;
    if ((e[0] & 0x7f) != 0) return 0;
    if ((e[8] | e[9] | e[10] | e[11]) == 0) return 0;
    if ((e[12] | e[13] | e[14] | e[15]) == 0) return 0;
    any = 1;
  }
  return any;
}

/* ------------------------------------------------------------------------ */
/* 4. sampling point scan                                                    */
/* ------------------------------------------------------------------------ */

/* a little-endian word of the controller's diagnostics (latched first) */
static uint16_t diag_word(uint8_t i)
{
  return diag_byte(i) | ((uint16_t)diag_byte(i + 1) << 8);
}

/* For each sample delay D (half cycles of 3.086 ns after the SD clock's
   rising edge) at clock period P: make (P, D) the clock setting ($21, no
   checks), read 64 sectors with the cache off, and count what went wrong.
   A failing read is retried, and the retries fall back to the normal
   setting: so the counts, and whether the setting is still (P, D) at the
   end, show where the data eye is.  The sectors should hold varied data
   (mode 3's region does): sector 0 of a wiped card is all zeros. */
static void sample_scan(uint8_t p)
{
  uint8_t d, i, fails;
  uint16_t crc0, ret0, term0, set;
  printf("\nsample delay scan at p=%u, 64 reads each, cache off\n"
         " d  crc retry term fail setting\n", p);
  sd_cmd(0x26);
  for (d = 0; d < 16; d++) {
    POKE(0xD6CE, 0x80);
    crc0 = diag_word(4); ret0 = diag_word(0); term0 = diag_word(10);
    POKE(0xD681, p);
    POKE(0xD682, d);
    sd_error = 0;
    sd_cmd(0x21);
    if (sd_error) { printf("%2u  (setting refused)\n", d); sd_error = 0; sd_cmd(0x2A); continue; }
    fails = 0;
    for (i = 0; i < 64; i++) {
      sd_set_sector(base + i);
      sd_error = 0;
      sd_cmd(0x02);
      if (sd_error) { fails++; sd_error = 0; sd_cmd(0x2A); }
    }
    POKE(0xD6CE, 0x80);
    set = diag_word(14);
    printf("%2u %4u %5u %4u %4u $%04x%s\n", d, diag_word(4) - crc0, diag_word(0) - ret0,
           diag_word(10) - term0, fails, set,
           set == ((uint16_t)d << 8 | p) ? "" : " (fell back)");
    sd_error = 0;
    sd_cmd(0x22);
  }
  sd_cmd(0x25);
}

int main(int argc, char **argv)
{
  static char line[64];
  uint8_t slot;
  uint32_t max = 0;

  hw_init();
#ifdef HOST
  if (argc > 1) sim_fault = atoi(argv[1]);
  if (argc > 2) sim_fault_at = strtoul(argv[2], 0, 0);
  if (argc > 3) max = strtoul(argv[3], 0, 0);
  if (sim_fault == 9) {
    uint8_t *m = sim_card;
    m[446 + 4] = 0x0C; m[446 + 9] = 0x08; m[446 + 14] = 0x40;
    m[510] = 0x55; m[511] = 0xAA;
    sim_fault = 0;
  }
#else
  (void)argc; (void)argv;
#endif

  printf("sdstress: sd controller stress test\n\n"
         "1 init report (reads only)\n"
         "2 f011 compare with a mounted d81 (reads only)\n"
         "3 stress a scratch card (DESTRUCTIVE)\n"
         "4 sampling point scan (reads only)\n> ");
  read_line(line, sizeof(line));
  run_seed = 1;
  rnd_state = 2891336453UL;

  if (line[0] == '1') {
    init_report();
    return 0;
  }
  if (line[0] == '2') {
    printf("seed (default 1)? ");
    read_line(line, sizeof(line));
    if (strtoul(line, 0, 0)) rnd_state = strtoul(line, 0, 0) * 2891336453UL + 1;
    f011_compare(max);
    return f_bad || f_rnf;
  }
  if (line[0] == '4') {
    printf("card (0 = full-size, 1 = micro-sd)? ");
    read_line(line, sizeof(line));
    slot = line[0] == '1';
    if (!sd_select(slot)) {
      printf("no card there\n");
      return 1;
    }
    printf("first sector to read (default 4096)? ");
    read_line(line, sizeof(line));
    base = strtoul(line, 0, 0);
    if (!base) base = 4096;
    printf("clock period p (324 mhz / p; default 8 = 40.5 mhz)? ");
    read_line(line, sizeof(line));
    sample_scan((uint8_t)(strtoul(line, 0, 0) ? strtoul(line, 0, 0) : 8));
    return 0;
  }
  if (line[0] != '3') return 0;

  printf("card to stress (0 = full-size, 1 = micro-sd)? ");
  read_line(line, sizeof(line));
  slot = line[0] == '1';
  if (!sd_select(slot)) {
    printf("no card there\n");
    return 1;
  }
  sd_buffer_sd();
  sd_set_sector(0);
  sd_cmd(0x02);
  if (!(buf[0] == 'S' && buf[1] == 'D' && buf[2] == 'T' && buf[3] == '1') && mbr_valid()) {
    printf("\nthat card has a valid mbr: refusing.\n"
           "(clear sector 0 first if you really want to use it)\n");
    return 1;
  }
  printf("first sector of the region (default 4096)? ");
  read_line(line, sizeof(line));
  base = strtoul(line, 0, 0);
  if (!base) base = 4096;
  printf("seed (default 1)? ");
  read_line(line, sizeof(line));
  run_seed = strtoul(line, 0, 0);
  if (!run_seed) run_seed = 1;
  rnd_state = run_seed * 2891336453UL + 1;
  printf("resets in the middle of open reads (y/n, default y)? ");
  read_line(line, sizeof(line));
  mid_resets = line[0] != 'n' && line[0] != 'N';
  printf("stop at the first error (y/n, default n)? ");
  read_line(line, sizeof(line));
  stop_first = line[0] == 'y' || line[0] == 'Y';
  printf("check the card after every operation (y/n, default n)? ");
  read_line(line, sizeof(line));
  check_each = line[0] == 'y' || line[0] == 'Y';
  printf("\nthis overwrites sectors %lu-%lu of the card in slot %u.\n"
         "type: this will destroy card contents\n> ", (unsigned long)base,
         (unsigned long)(base + REGION - 1), slot);
  read_line(line, sizeof(line));
  if (strcmp(line, "this will destroy card contents")) {
    printf("not confirmed: stopping.\n");
    return 1;
  }
  sd_select(slot);
  sd_cmd(0x25);
  stress(max);
  return (e_ctrl || e_cache || e_card) ? 1 : 0;
}
