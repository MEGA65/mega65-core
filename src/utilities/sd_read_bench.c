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
extern uint8_t sd_bench_getkey(void);

enum { REPEAT, SEQUENTIAL, RANDOM_512, RANDOM_4K, MULTI };
static uint8_t mbr[512];
static uint8_t native_controller, cache_control, stream_open, last_frame;
static uint16_t frames, target_frames, window_mask;
static uint32_t first_sector, frame_us;
static uint8_t retry_stats, persistent_slots, card_info, capacity_limits;

static void detect_features(void)
{
  retry_stats = PEEK(0xd6cc) == 0x53 && PEEK(0xd6cd) == 1;
  if (retry_stats)
    native_controller = 1;
  persistent_slots = retry_stats && PEEK(0xd6d7) == 0xd2;
  card_info = retry_stats && PEEK(0xd6d8) == 0x49;
  capacity_limits = card_info && (PEEK(0xd6d9) & 0xf0) == 0xa0;
}

static void copy_sector_buffer(void)
{
  uint16_t i;
  sd_bench_irq_mask();
  sd_bench_command(0x81);
  for (i = 0; i != 512; ++i)
    mbr[i] = PEEK(0xde00 + i);
  sd_bench_command(0x82);
}

/* Native retry-statistics v1: latch and read two wrapping 16-bit counters.
 * Older native/legacy builds return no signature; display -- on those. */
static uint32_t read_retry_counts(void)
{
  uint8_t i;
  uint32_t value = 0;
  POKE(0xd6ce, 0x80);
  for (i = 0; i != 4; ++i) {
    POKE(0xd6ce, i);
    value |= (uint32_t)PEEK(0xd6cf) << (8 * i);
  }
  return value;
}

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
  uint16_t window;
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
  copy_sector_buffer();
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
  uint8_t result, op, in_random = 0, random_sectors = 8;
  uint16_t offset = 0, in_stream = 0, chunk;
  uint32_t count = 0, elapsed_ms, kib_tenths, retries_before = 0, retries_after;
  if (cache_control && command(0x27))
    return 0;
  if (cached && pattern == REPEAT) {
    sd_bench_sector(first_sector);
    if (command(code))
      return 0;
    /* Retain warmed data, but retire its background fill before timing. */
    if (cache_control && command(0x25))
      return 0;
  }
  printf("%-13s ", name);
  if (retry_stats)
    retries_before = read_retry_counts();
  sd_bench_irq_mask();
  if (!frame_edge()) {
    puts("FRAME CLOCK STOPPED");
    return 0;
  }
  last_frame = PEEK(0xd7fa);
  frames = 0;
  chunk = window_mask + 1;
  if (chunk < random_sectors)
    random_sectors = (uint8_t)chunk;
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
    if (pattern == RANDOM_512)
      offset = (offset + 509) & window_mask;
    else if (pattern == RANDOM_4K) {
      if (++in_random == random_sectors) {
        in_random = 0;
        offset = (offset + 509U * random_sectors - (random_sectors - 1)) & window_mask;
      } else
        offset = (offset + 1) & window_mask;
    }
    else if (pattern != REPEAT)
      offset = (offset + 1) & window_mask;
    tick();
  } while (frames < target_frames || (pattern == RANDOM_4K && in_random));
  if (stream_open) {
    result = sd_bench_command(0x0a);
    tick();
    if (result) {
      error(result);
      return 0;
    }
    stream_open = 0;
  }
  /* Include the last fill/close in the time and retry count. Each workload
   * starts empty, so draining and invalidating here costs no useful hits. */
  if (cache_control && command(0x27))
    return 0;
  tick();
  elapsed_ms = ((uint32_t)frames * frame_us) / 1000;
  if (!elapsed_ms)
    return 0;
  kib_tenths = (count / elapsed_ms) * 5000UL
    + (count % elapsed_ms) * 5000UL / elapsed_ms;
  printf("%6lu%8lu.%lu", (unsigned long)count,
         (unsigned long)(kib_tenths / 10),
         (unsigned long)(kib_tenths % 10));
  if (retry_stats) {
    retries_after = read_retry_counts();
    printf("%6lu\n", (unsigned long)((uint16_t)(retries_after - retries_before)
      + (uint32_t)(uint16_t)((retries_after >> 16) - (retries_before >> 16))));
  } else
    puts("    --");
  return 1;
}

static uint8_t plain_reads(uint8_t copy, uint8_t cached)
{
  return benchmark("REPEAT $02", REPEAT, 0x02, copy, cached)
    && benchmark("SEQUENTIAL", SEQUENTIAL, 0x02, copy, cached)
    && benchmark("RANDOM 512B", RANDOM_512, 0x02, copy, cached)
    && benchmark("RANDOM 4K", RANDOM_4K, 0x02, copy, cached);
}

static void finish_benchmark(void)
{
  if (native_controller && stream_open)
    sd_bench_command(0x0a);
  stream_open = 0;
  if (cache_control)
    sd_bench_command(0x25);
  cache_control = 0;
}

static uint8_t run_benchmark(void)
{
  uint8_t copy;
  if (!get_partition())
    return 0;
  detect_features();
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
    puts("TEST          READS     KIB/S RETRY");
    cache_control = 0;
    if (native_controller && !sd_bench_command(0x26))
      cache_control = 1;
    puts(cache_control ? "\nCACHE OFF:" : "\nCOMMON $02 READS:");
    if (!plain_reads(copy, 0))
      return 0;
    if (cache_control) {
      if (command(0x25))
        return 0;
      puts("\nCACHE ON (REPEAT IS WARM):");
      if (!plain_reads(copy, 1))
        return 0;
    }
    if (native_controller) {
      if (!benchmark("META $0B", RANDOM_512, 0x0b, copy, 0)
          || !benchmark("MULTI 07--09", MULTI, 0x02, copy, 0))
        return 0;
    }
    if (!copy) {
      puts("\nSPACE FOR RAM COPY BENCHMARK");
      sd_bench_key();
    }
  }
  return 1;
}

static uint8_t initialise_card(void)
{
  POKE(0xd680, 0x00); /* Reset assertion is intentionally not polled. */
  return command(0x01) == 0;
}

static void print_status(void)
{
  uint8_t i, flags;
  uint32_t last = 0;
  printf("BUS %u: %s\n", PEEK(0xd680) >> 7,
         native_controller ? "NATIVE CONTROLLER" : "LEGACY/OLDER CONTROLLER");
  printf("D680=%02X D686=%02X D687=%02X\n",
         PEEK(0xd680), PEEK(0xd686), PEEK(0xd687));
  if (native_controller)
    printf("%s; %s SPEED\n", PEEK(0xd686) & 2 ? "4-BIT" : "SPI",
           PEEK(0xd686) & 4 ? "HIGH" : "DEFAULT");
  if (capacity_limits) {
    flags = PEEK(0xd6d9);
    printf("SIZE LIMIT %s; CAPACITY %s\n", flags & 1 ? "ON" : "OFF", flags & 2 ? "KNOWN" : "UNKNOWN");
    if (flags & 2) {
      for (i = 0; i != 4; ++i) {
        POKE(0xd6dc, i);
        last |= (uint32_t)PEEK(0xd6dd) << (8*i);
      }
      printf("LAST LBA %lu\n", (unsigned long)last);
    }
  }
}

static void print_capacity(void)
{
  uint8_t version = mbr[0] >> 6, shift;
  uint32_t units, sectors;
  printf("CSD STRUCTURE %u\n", version);
  if (version == 1) {
    units = (((uint32_t)mbr[7] & 63) << 16)
      | ((uint32_t)mbr[8] << 8) | mbr[9];
    ++units;
    printf("CAPACITY: %lu.%u MIB\n", (unsigned long)(units / 2), (units & 1) ? 5 : 0);
    if (units == 0x400000UL) {
      puts("512B SECTORS: 4294967296");
      return;
    }
    sectors = units << 10;
  } else if (version == 0) {
    units = ((uint32_t)(mbr[6] & 3) << 10) | ((uint16_t)mbr[7] << 2) | (mbr[8] >> 6);
    shift = ((mbr[9] & 3) << 1) | (mbr[10] >> 7);
    sectors = (units + 1) << (shift + 2);
    shift = mbr[5] & 15;
    if (shift >= 9) sectors <<= shift - 9;
    else sectors >>= 9 - shift;
    printf("CAPACITY: %lu KIB\n", (unsigned long)(sectors / 2));
  } else {
    puts("CAPACITY DECODE NOT SUPPORTED");
    return;
  }
  printf("512B SECTORS: %lu\n", (unsigned long)sectors);
}

static uint8_t text_byte(uint8_t c)
{
  return c >= 32 && c <= 126 ? c : '.';
}

static uint8_t show_info(uint8_t kind)
{
  static const char * const names[] = { "CSD", "CID", "SCR", "SD STATUS" };
  uint8_t i, length = kind == 3 ? 64 : (kind == 2 ? 8 : 16);
  if (!card_info) {
    puts("CARD INFO COMMANDS NOT SUPPORTED");
    return 0;
  }
  sd_bench_clear();
  printf("BUS %u %s $%02X (%u BYTES)\n", PEEK(0xd680) >> 7, names[kind], 0x2c + kind, length);
  if (command(0x2c + kind))
    return 0;
  copy_sector_buffer();
  for (i = 0; i != length; ++i) {
    if (!(i & 7)) printf("%04X:", i);
    printf(" %02X", mbr[i]);
    if ((i & 7) == 7) puts("");
  }
  if (!kind)
    print_capacity();
  else if (kind == 1) {
    printf("MFG %02X OEM %c%c PRODUCT ", mbr[0], text_byte(mbr[1]), text_byte(mbr[2]));
    for (i = 3; i != 8; ++i) putchar(text_byte(mbr[i]));
    printf("\nREV %u.%u SERIAL %08lX\n", mbr[8] >> 4, mbr[8] & 15,
           (unsigned long)(((uint32_t)mbr[9] << 24) | ((uint32_t)mbr[10] << 16)
             | ((uint16_t)mbr[11] << 8) | mbr[12]));
    printf("DATE %u-%02u\n", 2000U + ((uint16_t)(mbr[13] & 15) << 4) + (mbr[14] >> 4), mbr[14] & 15);
  } else if (kind == 2) {
    printf("SD_SPEC %u; BUS WIDTH MASK %X\n", mbr[0] & 15, mbr[1] & 15);
  } else
    printf("BUS WIDTH CODE %u; SPEED CLASS CODE %u\n", mbr[0] >> 6, mbr[8]);
  return 1;
}

static void pause_menu(void)
{
  puts("\nSPACE FOR MENU");
  sd_bench_key();
}

int main(void)
{
  uint8_t saved_30, saved_31, saved_54, saved_89, saved_mapped, saved_bus, key;
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
  saved_bus = PEEK(0xd680) >> 7;
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
  ok = 1;
  for (;;) {
    detect_features();
    sd_bench_clear();
    puts("MEGA65 SD READ BENCH - NO CARD WRITES");
    print_status();
    puts("\n0/1 SELECT BUS   B BENCHMARK");
    puts("C CSD   I CID   R SCR   S SD STATUS");
    puts("A ALL CARD INFO  N INIT SELECTED CARD");
    puts("P PROBE BOTH     X CLEAR/RECOVER");
    puts("L TOGGLE SIZE LIMIT");
    puts("Q QUIT");
    key = sd_bench_getkey();
    if (key >= 0xc1 && key <= 0xda) key &= 0x7f;
    if (key >= 'a' && key <= 'z') key -= 'a' - 'A';
    if (key == 'Q') break;
    if (key == '0' || key == '1') {
      key -= '0';
      if ((PEEK(0xd680) >> 7) != key) {
        POKE(0xd680, 0xc0 | key);
        if (!persistent_slots) {
          ok = initialise_card();
          if (!ok) pause_menu();
        }
      }
      continue;
    }
    if (key == 'B') {
      ok = run_benchmark();
      finish_benchmark();
      puts(ok ? "\nBENCHMARK COMPLETE" : "\nBENCHMARK STOPPED");
    } else if (key == 'C' || key == 'I' || key == 'R' || key == 'S') {
      ok = show_info(key == 'C' ? 0 : (key == 'I' ? 1 : (key == 'R' ? 2 : 3)));
    } else if (key == 'A') {
      for (key = 0; key != 4; ++key) {
        ok = show_info(key);
        if (!ok || key == 3) break;
        puts("\nSPACE FOR NEXT INFO PAGE");
        sd_bench_key();
      }
    } else if (key == 'N') {
      ok = initialise_card();
      print_status();
    } else if (key == 'P') {
      if (persistent_slots) ok = command(0x2b) == 0;
      else { puts("PARALLEL PROBE NOT SUPPORTED"); ok = 0; }
      print_status();
    } else if (key == 'X') {
      if (native_controller) ok = command(0x2a) == 0;
      else { puts("RECOVERY NOT SUPPORTED; USE N"); ok = 0; }
      print_status();
    } else if (key == 'L') {
      if (capacity_limits) {
        POKE(0xd680, 0x30 | (PEEK(0xd6d9) & 1));
        ok = 1;
      } else { puts("SIZE LIMIT CONTROL NOT SUPPORTED"); ok = 0; }
      print_status();
    } else continue;
    pause_menu();
  }
out:
  finish_benchmark();
  if ((PEEK(0xd680) >> 7) != saved_bus) {
    POKE(0xd680, 0xc0 | saved_bus);
    if (!persistent_slots)
      initialise_card();
  }
  POKE(0xd689, saved_89 & 0xa4);
  sd_bench_command(saved_mapped ? 0x81 : 0x82);
  POKE(0xd054, saved_54);
  POKE(0xd031, saved_31);
  POKE(0xd030, saved_30);
  sd_bench_irq_restore();
  puts(ok ? "\nDONE. SD CARD WAS ONLY READ." : "\nBENCHMARK STOPPED.");
  return !ok;
}
