/*
  sdtest: DESTRUCTIVE SD card write test for the MEGA65.
  MEGA65/mega65-core#890 (native SD controller) and #953 (sector cache).

  Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project.
  LGPL v3 (see LICENSE.txt).

  It overwrites the start of the chosen card, so it only runs on a card
  whose sector 0 does not hold a valid MBR (or that holds this program's own
  test data), and only after the words "this will destroy card contents" are
  typed in.  Load it with m65 over JTAG, so no card holds the program.

  Every test sector is self-describing:
     0..3    "SDT1"
     4..7    the sector it was written to (32 bits, little-endian)
     8..9    the stage that wrote it
    10..13   the seed of the run
    14..15   a checksum of bytes 0..13
    16..511  a pseudo-random stream keyed by (seed, sector, stage)
  so a wrong sector usually says where its data was meant to go.

  The test works on slabs at the start of the card: 16 MB first, then twice
  as large each pass, up to a limit (256 MB by default).  For each slab:
    1. wipe: one long run of multi-sector writes (stage 0), then verify;
    2. rounds: groups of sectors chosen at random are written with a new
       stage, alternating single and multi-sector writes; after each round
       the groups and the sectors on either side of them are verified;
    3. the whole slab is verified, with the sector cache on and then off
       (off: everything comes from the card).
  The expected stage of a sector comes from the list of groups written so
  far, newest first: no per-sector table is needed.

  Build for the MEGA65:  cl65 -t c64 -O -Or -Oi -Os -o sdtest.prg sdtest.c
  Build for a PC (simulated card, fault injection):
                         cc -DHOST -O2 -o sdtest_host sdtest.c
*/

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

/* ------------------------------------------------------------------------ */
/* the card: MEGA65 registers, or a simulation                               */
/* ------------------------------------------------------------------------ */

#define SECTORS_PER_MB 2048UL

static uint8_t *buf;            /* the SD sector buffer */

#ifdef HOST

/* A simulated card.  sim_fault selects a fault to check that the test sees
   it: 1 = a write goes to the sector before instead, 2 = a write is lost,
   3 = a byte of a write is flipped.  The fault is at sector sim_fault_at,
   or (sim_fault_at = 0) at the first sector written by a round.
   sim_fault 9: no fault, but sector 0 holds a valid MBR. */
#define SIM_SECTORS (520UL * SECTORS_PER_MB)
static uint8_t *sim_card;
static uint8_t sim_buf[512];
static int sim_fault = 0;
static uint32_t sim_fault_at = 0xFFFFFFFFUL;
static int sim_on_round = 0;
static uint32_t sim_sector, sim_open = 0xFFFFFFFFUL;
static uint8_t sim_status = 0x0F;      /* $D686: ready, native, high speed, SDHC */
static int sim_cache = 1;

static void sim_write(uint32_t s)
{
  /* at 0: the first write of a round (stage 1) */
  if (sim_fault && sim_on_round && (sim_buf[8] | (sim_buf[9] << 8)) == 1) {
    sim_fault_at = s;
    sim_on_round = 0;
  }
  if (s == sim_fault_at && sim_fault) {
    if (sim_fault == 1) s--;
    else if (sim_fault == 2) return;
    else if (sim_fault == 3) { memcpy(sim_card + s * 512, sim_buf, 512); sim_card[s * 512 + 300] ^= 0x40; return; }
  }
  if (s < SIM_SECTORS) memcpy(sim_card + s * 512, sim_buf, 512);
}

static void sim_read(uint32_t s)
{
  if (s < SIM_SECTORS) memcpy(sim_buf, sim_card + s * 512, 512);
  else memset(sim_buf, 0, 512);
}

static uint8_t regs[256];
static void POKE(uint16_t a, uint8_t v)
{
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
  case 0x25: sim_cache = 1; break;
  case 0x26: sim_cache = 0; break;
  default: break;
  }
}
static uint8_t PEEK(uint16_t a)
{
  if (a == 0xD680) return 0x00;          /* never busy, no error */
  if (a == 0xD686) return sim_status;
  if (a == 0xD687) return 0;
  return 0;
}
static void hw_init(void)
{
  sim_card = calloc(SIM_SECTORS, 512);
  if (!sim_card) { printf("no memory for the simulated card\n"); exit(1); }
  buf = sim_buf;
}
static uint32_t ticks(void) { return 0; }   /* (tenths of seconds) */
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
}

/* CIA 1 time of day, in tenths of a second (it runs from power-on) */
static uint32_t ticks(void)
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

static char *read_line(char *s, int n)
{
  fgets(s, n, stdin);
  s[strcspn(s, "\r\n")] = 0;
  return s;
}

#endif

/* ------------------------------------------------------------------------ */
/* SD controller commands                                                    */
/* ------------------------------------------------------------------------ */

static uint8_t sd_error;

static void sd_wait(void)
{
  while (PEEK(0xD680) & 0x03)
    continue;
  if (PEEK(0xD680) & 0x40) sd_error = 1;
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
static void sd_wcmd(uint8_t c, uint32_t s)
{
  POKE(0xD680, s ? 0x57 : 0x4D);
  POKE(0xD680, c);
  sd_wait();
}

static uint8_t sd_select(uint8_t slot)
{
  POKE(0xD680, slot ? 0xC1 : 0xC0);
  POKE(0xD680, 0x00);
  POKE(0xD680, 0x01);
  sd_error = 0;
  sd_wait();
  return !sd_error && (PEEK(0xD686) & 1);
}

/* ------------------------------------------------------------------------ */
/* test data                                                                 */
/* ------------------------------------------------------------------------ */

static uint32_t run_seed;

/* XABC: a small 8-bit generator, cheap on a 6502 (a macro in the loops) */
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
  /* let it settle */
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

/* errors found */
static uint32_t errors, sectors_checked;
#define MAX_REPORT 20

/* check the buffer against what sector should hold; report a mismatch */
static uint8_t check_sector(uint32_t sector, uint16_t stage)
{
  uint16_t i, bad = 0, first = 0;
  uint32_t hs;
  uint16_t hst;
  sectors_checked++;
  if (buf[0] == 'S' && buf[1] == 'D' && buf[2] == 'T' && buf[3] == '1'
      && buf[4] == (uint8_t)sector && buf[5] == (uint8_t)(sector >> 8)
      && buf[6] == (uint8_t)(sector >> 16) && buf[7] == (uint8_t)(sector >> 24)
      && buf[8] == (uint8_t)stage && buf[9] == (uint8_t)(stage >> 8)) {
    gen_key(sector, stage);
    for (i = 16; i < 512; i++) {
      if (buf[i] != GEN()) {
        if (!bad) first = i;
        bad++;
      }
    }
    if (!bad) return 1;
  }
  errors++;
  if (errors <= MAX_REPORT) {
    printf("\nERROR sector %lu (want stage %u): ", (unsigned long)sector, stage);
    if (buf[0] == 'S' && buf[1] == 'D' && buf[2] == 'T' && buf[3] == '1'
        && (buf[14] | (buf[15] << 8)) == hdr_sum(buf)) {
      hs = buf[4] | ((uint32_t)buf[5] << 8) | ((uint32_t)buf[6] << 16) | ((uint32_t)buf[7] << 24);
      hst = buf[8] | (buf[9] << 8);
      if (hs != sector) printf("holds the data of sector %lu stage %u", (unsigned long)hs, hst);
      else if (hst != stage) printf("holds stage %u (stale or lost write)", hst);
      else printf("%u bytes differ, first at %u", bad, first);
    } else {
      printf("not test data (%02x %02x %02x %02x)", buf[0], buf[1], buf[2], buf[3]);
    }
  }
  return 0;
}

/* ------------------------------------------------------------------------ */
/* the groups written so far (newest last)                                   */
/* ------------------------------------------------------------------------ */

#define ROUNDS 8
#define GROUPS 16
#define MAX_GROUP 64
static uint32_t g_start[ROUNDS * GROUPS];
static uint8_t g_len[ROUNDS * GROUPS];
static uint16_t g_stage[ROUNDS * GROUPS];
static uint16_t n_groups;
static uint16_t stage_base;

static uint16_t expected_stage(uint32_t s)
{
  uint16_t i = n_groups;
  while (i--) {
    if (s >= g_start[i] && s < g_start[i] + g_len[i]) return g_stage[i];
  }
  return stage_base;
}

/* run PRNG (for choosing groups) */
static uint32_t rnd_state;
static uint32_t rnd(void)
{
  rnd_state ^= rnd_state << 13;
  rnd_state ^= rnd_state >> 17;
  rnd_state ^= rnd_state << 5;
  return rnd_state;
}

/* ------------------------------------------------------------------------ */
/* writing and reading runs of sectors                                       */
/* ------------------------------------------------------------------------ */

/* write sectors first..first+n-1 with stage; multi = use $04/$05/$06 */
static void write_run(uint32_t first, uint32_t n, uint16_t stage, uint8_t multi)
{
  uint32_t i;
  for (i = 0; i < n; i++) {
    make_sector(buf, first + i, stage);
    if (!multi || n == 1) {
      sd_set_sector(first + i);
      sd_wcmd(0x03, first + i);
    } else if (i == 0) {
      sd_set_sector(first);
      sd_wcmd(0x04, first);
    } else if (i == n - 1) {
      sd_wcmd(0x06, first + i);
    } else {
      sd_wcmd(0x05, first + i);
    }
    if (sd_error) {
      printf("\nwrite error at sector %lu (code $%02x)", (unsigned long)(first + i), PEEK(0xD687));
      errors++;
      sd_error = 0;
    }
  }
}

/* read and check sectors first..first+n-1; multi = use $07/$08/$09 */
static void verify_run(uint32_t first, uint32_t n, uint8_t multi)
{
  uint32_t i;
  for (i = 0; i < n; i++) {
    if (!multi || n == 1) {
      sd_set_sector(first + i);
      sd_cmd(0x02);
    } else if (i == 0) {
      sd_set_sector(first);
      sd_cmd(0x07);
    } else if (i == n - 1) {
      sd_cmd(0x09);
    } else {
      sd_cmd(0x08);
    }
    if (sd_error) {
      printf("\nread error at sector %lu (code $%02x)", (unsigned long)(first + i), PEEK(0xD687));
      errors++;
      sd_error = 0;
      continue;
    }
    check_sector(first + i, expected_stage(first + i));
  }
}

static void progress(const char *what, uint32_t done, uint32_t total)
{
  printf("\r%s %lu/%lu MB   ", what, (unsigned long)(done / SECTORS_PER_MB),
         (unsigned long)(total / SECTORS_PER_MB));
#ifdef HOST
  fflush(stdout);
#endif
}

static void rate(uint32_t sectors, uint32_t t0)
{
  uint32_t t = ticks() - t0;
  if (t) printf(" %lu KB/s", (unsigned long)(sectors * 5 / t));   /* sectors/2 KB per t/10 s */
}

/* ------------------------------------------------------------------------ */
/* one slab                                                                  */
/* ------------------------------------------------------------------------ */

#define CHUNK 256UL        /* sectors per multi-sector run during the wipe */

static void run_slab(uint32_t n, uint16_t slab_no)
{
  uint32_t s, k, t0;
  uint16_t r, g;
  uint32_t start;
  uint8_t len;

  stage_base = slab_no * 16;
  n_groups = 0;
  printf("\n\n== slab %u: %lu MB, seed %08lx ==", slab_no, (unsigned long)(n / SECTORS_PER_MB),
         (unsigned long)run_seed);

  /* 1. wipe */
  t0 = ticks();
  for (s = 0; s < n; s += CHUNK) {
    k = n - s < CHUNK ? n - s : CHUNK;
    write_run(s, k, stage_base, 1);
    if ((s & 0x3fff) == 0) progress("\nwipe  ", s, n);
  }
  progress("\rwipe  ", n, n);
  rate(n, t0);
  t0 = ticks();
  for (s = 0; s < n; s += CHUNK) {
    k = n - s < CHUNK ? n - s : CHUNK;
    verify_run(s, k, (s / CHUNK) & 1);       /* alternate plain and multi reads */
    if ((s & 0x3fff) == 0) progress("\rverify", s, n);
  }
  progress("\rverify", n, n);
  rate(n, t0);
  printf("  errors %lu", (unsigned long)errors);

  /* 2. rounds of random groups */
  for (r = 1; r <= ROUNDS; r++) {
    printf("\nround %u: ", r);
    for (g = 0; g < GROUPS; g++) {
      len = 1 + rnd() % MAX_GROUP;
      start = rnd() % n;
      if (start + len > n) len = n - start;
      g_start[n_groups] = start;
      g_len[n_groups] = len;
      g_stage[n_groups] = stage_base + r;
      n_groups++;
      write_run(start, len, stage_base + r, g & 1);
    }
    /* each group and its neighbours */
    for (g = n_groups - GROUPS; g < n_groups; g++) {
      start = g_start[g];
      if (start) verify_run(start - 1, 1, 0);
      verify_run(start, g_len[g], g & 1);
      if (start + g_len[g] < n) verify_run(start + g_len[g], 1, 0);
    }
    printf("errors %lu", (unsigned long)errors);
  }

  /* 3. everything, cache on then off */
  for (k = 0; k < 2; k++) {
    sd_cmd(k ? 0x26 : 0x25);
    t0 = ticks();
    for (s = 0; s < n; s += CHUNK) {
      verify_run(s, n - s < CHUNK ? n - s : CHUNK, 1);
      if ((s & 0x3fff) == 0) progress(k ? "\nfinal, cache off" : "\nfinal, cache on ", s, n);
    }
    progress(k ? "\rfinal, cache off" : "\rfinal, cache on ", n, n);
    rate(n, t0);
    printf("  errors %lu", (unsigned long)errors);
  }
  sd_cmd(0x25);
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
    if ((e[0] & 0x7f) != 0) return 0;                      /* boot flag 0 or $80 */
    if ((e[8] | e[9] | e[10] | e[11]) == 0) return 0;      /* start 0 */
    if ((e[12] | e[13] | e[14] | e[15]) == 0) return 0;    /* size 0 */
    any = 1;
  }
  return any;
}

static void show_card(uint8_t slot)
{
  uint8_t i, st;
  uint8_t *e;
  printf("\nslot %u (%s): ", slot, slot ? "micro-sd" : "full-size sd");
  if (!sd_select(slot)) {
    printf("no card");
    return;
  }
  st = PEEK(0xD686);
  printf("%s%s%s", st & 2 ? "4-bit" : "spi", st & 4 ? ", high speed" : "", st & 8 ? ", sdhc" : "");
  sd_set_sector(0);
  sd_cmd(0x02);
  if (buf[0] == 'S' && buf[1] == 'D' && buf[2] == 'T' && buf[3] == '1') {
    printf("\n  sector 0: sdtest data");
    return;
  }
  if (!mbr_valid()) {
    printf("\n  sector 0: no valid mbr");
    return;
  }
  for (i = 0; i < 4; i++) {
    e = buf + 446 + i * 16;
    if (!e[4]) continue;
    printf("\n  partition %u: type $%02x, start %lu, %lu MB", i + 1, e[4],
           (unsigned long)(e[8] | ((uint32_t)e[9] << 8) | ((uint32_t)e[10] << 16) | ((uint32_t)e[11] << 24)),
           (unsigned long)((e[12] | ((uint32_t)e[13] << 8) | ((uint32_t)e[14] << 16) | ((uint32_t)e[15] << 24))
                           / SECTORS_PER_MB));
  }
}

int main(int argc, char **argv)
{
  static char line[64];
  uint8_t slot;
  uint32_t max_mb, n;
  uint16_t slab;

  hw_init();
#ifdef HOST
  if (argc > 1) sim_fault = atoi(argv[1]);
  if (argc > 2) sim_fault_at = strtoul(argv[2], 0, 0);
  if (sim_fault == 9) {
    /* a card with a valid MBR: one FAT32 partition */
    uint8_t *m = sim_card;
    m[446 + 4] = 0x0C; m[446 + 8] = 0x00; m[446 + 9] = 0x08;   /* start 2048 */
    m[446 + 12] = 0x00; m[446 + 13] = 0x00; m[446 + 14] = 0x40; /* 4M sectors */
    m[510] = 0x55; m[511] = 0xAA;
    sim_fault = 0;
  }
  if (sim_fault && sim_fault_at == 0) {
    sim_on_round = 1;
    sim_fault_at = 0xFFFFFFFFUL;
  }
#else
  (void)argc; (void)argv;
#endif

  printf("sdtest: DESTRUCTIVE sd card write test\n");
  show_card(1);
  show_card(0);

  printf("\n\ncard to test (0 = full-size, 1 = micro-sd)? ");
  read_line(line, sizeof(line));
  slot = line[0] == '1';
  if (!sd_select(slot)) {
    printf("no card there\n");
    return 1;
  }
  sd_set_sector(0);
  sd_cmd(0x02);
  if (!(buf[0] == 'S' && buf[1] == 'D' && buf[2] == 'T' && buf[3] == '1') && mbr_valid()) {
    printf("\nthat card has a valid mbr: refusing.\n"
           "(clear sector 0 first if you really want to test it)\n");
    return 1;
  }

  printf("largest slab in mb (16..; default 256)? ");
  read_line(line, sizeof(line));
  max_mb = atol(line);
  if (max_mb < 16) max_mb = 256;
  printf("seed (default 1)? ");
  read_line(line, sizeof(line));
  run_seed = strtoul(line, 0, 0);
  if (!run_seed) run_seed = 1;

  printf("\nthis overwrites the first %lu mb of the card in slot %u.\n"
         "type: this will destroy card contents\n> ", (unsigned long)max_mb, slot);
  read_line(line, sizeof(line));
  if (strcmp(line, "this will destroy card contents")) {
    printf("not confirmed: stopping.\n");
    return 1;
  }

  sd_select(slot);
  rnd_state = run_seed * 2891336453UL + 1;
  errors = 0;
  sectors_checked = 0;
  slab = 0;
  for (n = 16 * SECTORS_PER_MB; n <= max_mb * SECTORS_PER_MB; n *= 2) {
    run_slab(n, slab++);
    if (errors >= 1000) break;
  }
  printf("\n\ndone: %lu sectors checked, %lu errors\n", (unsigned long)sectors_checked,
         (unsigned long)errors);
  return errors ? 1 : 0;
}
