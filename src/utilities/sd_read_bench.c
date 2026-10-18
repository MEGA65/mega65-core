/* Read-only MEGA65 SD benchmark for legacy and native controllers.
 * Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project. LGPL v3.
 */
#include <stdint.h>
#include <stdio.h>

#ifndef SD_BENCH_CPU_HZ
/* clocking.vhdl: 100 MHz * 8.125 / 20. */
#define SD_BENCH_CPU_HZ 40625000UL
#endif
#ifndef SD_BENCH_SECONDS
#define SD_BENCH_SECONDS 2
#endif
#if SD_BENCH_SECONDS < 1 || SD_BENCH_SECONDS > 60
#error SD_BENCH_SECONDS must be between 1 and 60
#endif

#ifdef SD_BENCH_HOST_TEST
extern uint8_t bench_peek(uint16_t address);
extern void bench_poke(uint16_t address, uint8_t value);
#define PEEK(a) bench_peek(a)
#define POKE(a, v) bench_poke(a, v)
#define FASTCALL
#else
#define PEEK(a) (*(volatile uint8_t *)(a))
#define POKE(a, v) (*(volatile uint8_t *)(a) = (uint8_t)(v))
#define FASTCALL __fastcall__
#endif

extern uint8_t FASTCALL sd_bench_command(uint8_t command);
extern void FASTCALL sd_bench_sector(uint32_t sector);
extern void sd_bench_copy(void);
extern void sd_bench_irq_save(void);
extern void sd_bench_irq_restore(void);
extern void sd_bench_irq_mask(void);
extern void sd_bench_clear(void);
extern void sd_bench_key(void);

enum { REPEAT, SEQUENTIAL, SCATTER, MULTI };
static uint8_t mbr[512];
static uint8_t native_controller, cache_control, stream_open, last_frame;
static uint16_t frames, target_frames, window_mask;
static uint32_t first_sector, frame_us;

static void print_cpu_clock(void)
{
  printf("%lu.%03lu MHZ", (unsigned long)(SD_BENCH_CPU_HZ / 1000000UL),
         (unsigned long)((SD_BENCH_CPU_HZ % 1000000UL) / 1000UL));
}

static uint32_t le32(const uint8_t *p)
{
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8)
    | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void tick(void)
{
  uint8_t now = PEEK(0xd7fa);
  frames += (uint8_t)(now - last_frame);
  last_frame = now;
}

static uint8_t frame_edge(void)
{
  uint16_t limit = 65535U;
  uint8_t old = PEEK(0xd7fa);
  while (PEEK(0xd7fa) == old)
    if (!--limit)
      return 0;
  return 1;
}

static void error(uint8_t result)
{
  printf("ERROR %u: D680=%02X D686=%02X D687=%02X\n",
         result, PEEK(0xd680), PEEK(0xd686), PEEK(0xd687));
}

static uint8_t command(uint8_t code)
{
  uint8_t result = sd_bench_command(code);
  if (result)
    error(result);
  return result;
}

static uint8_t get_partition(void)
{
  uint16_t i, window;
  uint8_t n, *entry;
  uint32_t length;
  sd_bench_sector(0);
  if (command(0x02))
    return 0;
  /* After a successful read the legacy data token is $FE; the new fork
   * returns ready/mode flags. Never send new commands before identifying
   * this register format via the common read operation. */
  native_controller = (PEEK(0xd686) & 0xf1) == 1 && PEEK(0xd687) == 0;
  printf("%s SLOT %u: D686=%02X D687=%02X\n",
         native_controller ? "NATIVE CTRL" : "LEGACY CTRL",
         PEEK(0xd680) >> 7, PEEK(0xd686), PEEK(0xd687));
  if (native_controller)
    printf("BUS: %s, %s SPEED\n", PEEK(0xd686) & 2 ? "4-BIT" : "SPI",
           PEEK(0xd686) & 4 ? "HIGH" : "DEFAULT");

  /* The mapping overlays colour RAM/CIAs: only use it for the MBR copy. */
  sd_bench_irq_mask();
  sd_bench_command(0x81);
  for (i = 0; i != 512; ++i)
    mbr[i] = PEEK(0xde00 + i);
  sd_bench_command(0x82);
  if (mbr[510] != 0x55 || mbr[511] != 0xaa) {
    puts("NO VALID MBR; NO BENCHMARK READS STARTED.");
    return 0;
  }
  for (n = 0; n != 4; ++n) {
    entry = mbr + 446 + 16 * n;
    if (entry[4] != 0x0b && entry[4] != 0x0c)
      continue;
    first_sector = le32(entry + 8);
    length = le32(entry + 12);
    if (!first_sector || length < 2 || length > UINT32_MAX - first_sector)
      continue;
    window = 2;
    while (window < 16384 && (uint32_t)window * 2 <= length)
      window *= 2;
    window_mask = window - 1;
    printf("FAT32 LBA %lu, WINDOW %u SECTORS\n", (unsigned long)first_sector, window);
    return 1;
  }
  puts("NO USABLE MBR FAT32 PARTITION.");
  return 0;
}

static uint8_t benchmark(const char *name, uint8_t pattern, uint8_t code,
                         uint8_t copy, uint8_t cached)
{
  uint8_t result, op;
  uint16_t offset = 0, in_stream = 0, chunk;
  uint32_t count = 0, elapsed_ms, kib_tenths;
  if (cache_control && command(0x27))
    return 0;
  if (cached && pattern == REPEAT) {
    sd_bench_sector(first_sector);
    if (command(code))
      return 0;
  }
  printf("%-13s ", name);
  sd_bench_irq_mask();
  if (!frame_edge()) {
    puts("FRAME CLOCK STOPPED");
    return 0;
  }
  last_frame = PEEK(0xd7fa);
  frames = 0;
  chunk = window_mask + 1;
  if (chunk > 128)
    chunk = 128;
  stream_open = 0;
  do {
    if (pattern == MULTI) {
      if (!in_stream) {
        sd_bench_sector(first_sector + offset);
        op = 0x07;
        stream_open = 1;
      } else
        op = in_stream == chunk - 1 ? 0x09 : 0x08;
    } else {
      sd_bench_sector(first_sector + offset);
      op = code;
    }
    result = sd_bench_command(op);
    tick();
    if (result) {
      error(result);
      return 0;
    }
    if (pattern == MULTI) {
      stream_open = op != 0x09;
      if (++in_stream == chunk)
        in_stream = 0;
    }
    if (copy)
      sd_bench_copy();
    ++count;
    if (pattern == SCATTER)
      offset = (offset + 509) & window_mask;
    else if (pattern != REPEAT)
      offset = (offset + 1) & window_mask;
    tick();
  } while (frames < target_frames);
  if (stream_open) {
    result = sd_bench_command(0x0a);
    tick();
    if (result) {
      error(result);
      return 0;
    }
    stream_open = 0;
  }
  elapsed_ms = ((uint32_t)frames * frame_us) / 1000;
  if (!elapsed_ms)
    return 0;
  kib_tenths = (count / elapsed_ms) * 5000UL
    + (count % elapsed_ms) * 5000UL / elapsed_ms;
  printf("%6lu%5lu%7lu.%lu\n", (unsigned long)count,
         (unsigned long)elapsed_ms, (unsigned long)(kib_tenths / 10),
         (unsigned long)(kib_tenths % 10));
  return 1;
}

static uint8_t plain_reads(uint8_t copy, uint8_t cached)
{
  return benchmark("REPEAT $02", REPEAT, 0x02, copy, cached)
    && benchmark("SEQUENTIAL", SEQUENTIAL, 0x02, copy, cached)
    && benchmark("SCATTER 509", SCATTER, 0x02, copy, cached);
}

int main(void)
{
  uint8_t saved_30, saved_31, saved_54, saved_89, saved_mapped, copy;
  uint8_t ok = 0;
  uint32_t per_frame;
  sd_bench_irq_save();
  POKE(0xd02f, 0x47);
  POKE(0xd02f, 0x53);
  saved_30 = PEEK(0xd030);
  saved_31 = PEEK(0xd031);
  saved_54 = PEEK(0xd054);
  saved_89 = PEEK(0xd689);
  saved_mapped = PEEK(0xd680) & 8;
  POKE(0xd030, saved_30 & 0xfe);
  POKE(0xd031, saved_31 | 0x40);
  POKE(0xd054, saved_54 | 0x40);
  POKE(0xd689, (saved_89 & 0x24) | 0x80);
  sd_bench_command(0x82);
  puts("\nMEGA65 SD READ BENCH - NO CARD WRITES");
  sd_bench_irq_mask();
  /* PHIPERFRAME calibrates video timing at full speed, in PAL/NTSC/VGA.
   * IRQs stay disabled; no CIA timer or KERNAL clock is borrowed. */
  if (!frame_edge() || !frame_edge()) {
    puts("FRAME CLOCK STOPPED");
    goto out;
  }
  per_frame = (uint32_t)PEEK(0xd7f2) | ((uint32_t)PEEK(0xd7f3) << 8)
    | ((uint32_t)PEEK(0xd7f4) << 16) | ((uint32_t)PEEK(0xd7f5) << 24);
  if (per_frame < 100000 || per_frame > 2000000UL) {
    puts("UNEXPECTED FRAME TIMING; CHECK CPU SPEED.");
    goto out;
  }
  frame_us = per_frame * 1000UL / (SD_BENCH_CPU_HZ / 1000UL);
  target_frames = (SD_BENCH_SECONDS * 1000000UL + frame_us - 1) / frame_us;
  printf("CPU ");
  print_cpu_clock();
  printf("; %lu US/FRAME\n", (unsigned long)frame_us);
  if (!get_partition())
    goto out;
  for (copy = 0; copy != 2; ++copy) {
    sd_bench_clear();
    printf("%s SLOT %u: %s%s\n", native_controller ? "NATIVE" : "LEGACY",
           PEEK(0xd680) >> 7,
           native_controller ? (PEEK(0xd686) & 2 ? "4-BIT" : "SPI") : "SPI",
           native_controller ? (PEEK(0xd686) & 4 ? " HS" : " DS") : "");
    printf("FAT32 LBA %lu; CPU ", (unsigned long)first_sector);
    print_cpu_clock();
    puts("");
    puts(copy ? "SD BUFFER + 512-BYTE DMA TO RAM" : "SD CARD TO SECTOR BUFFER");
    puts("TEST          READS   MS    KIB/S");
    cache_control = 0;
    if (native_controller && !sd_bench_command(0x26))
      cache_control = 1;
    puts(cache_control ? "CACHE OFF:" : "COMMON $02 READS:");
    if (!plain_reads(copy, 0))
      goto out;
    if (cache_control) {
      if (command(0x25))
        goto out;
      puts("CACHE ON (REPEAT IS WARM):");
      if (!plain_reads(copy, 1))
        goto out;
    }
    if (native_controller) {
      if (!benchmark("META $0B", SCATTER, 0x0b, copy, 0)
          || !benchmark("MULTI 07--09", MULTI, 0x02, copy, 0))
        goto out;
    }
    if (!copy) {
      puts("\nSPACE FOR RAM COPY BENCHMARK");
      sd_bench_key();
    }
  }
  ok = 1;
out:
  if (native_controller && stream_open)
    sd_bench_command(0x0a);
  if (cache_control)
    sd_bench_command(0x25);
  POKE(0xd689, saved_89 & 0xa4);
  sd_bench_command(saved_mapped ? 0x81 : 0x82);
  POKE(0xd054, saved_54);
  POKE(0xd031, saved_31);
  POKE(0xd030, saved_30);
  sd_bench_irq_restore();
  puts(ok ? "\nDONE. SD CARD WAS ONLY READ." : "\nBENCHMARK STOPPED.");
  return !ok;
}
