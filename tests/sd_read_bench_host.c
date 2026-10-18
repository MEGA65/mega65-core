/* Run the actual benchmark controller selection, request scheduling, bounds
 * and error cleanup against a deterministic register/card model. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int sd_read_bench_run(void);
static uint8_t regs[65536], sector_buffer[512];
static unsigned commands[256], frame_polls, data_reads, copies;
static uint32_t sector, stream_sector, partition_length = 16384;
static int native, cache, open_stream, fault, irq_depth, stopped_clock;
static unsigned fault_at;
static FILE *trace;
static uint8_t stats_snapshot[16];
static uint16_t retry_reads = 65530, retry_stops = 65533;

uint8_t bench_peek(uint16_t address)
{
  if (address == 0xd7fa && !stopped_clock)
    return (uint8_t)(++frame_polls / 16);
  if (address >= 0xde00 && address <= 0xdfff)
    return sector_buffer[address - 0xde00];
  if (address == 0xd6cf && regs[0xd6cc] == 0x53)
    return stats_snapshot[regs[0xd6ce] & 15];
  return regs[address];
}

void bench_poke(uint16_t address, uint8_t value)
{
  if (address == 0xd6ce && regs[0xd6cc] == 0x53) {
    if (value & 0x80) {
      stats_snapshot[0] = retry_reads; stats_snapshot[1] = retry_reads >> 8;
      stats_snapshot[2] = retry_stops; stats_snapshot[3] = retry_stops >> 8;
    }
    value &= 15;
  }
  regs[address] = value;
}
void sd_bench_irq_save(void) { assert(irq_depth++ == 0); }
void sd_bench_irq_restore(void) { assert(--irq_depth == 0); }
void sd_bench_irq_mask(void) { assert(irq_depth == 1); }
void sd_bench_sector(uint32_t value) { sector = value; }
void sd_bench_copy(void) { ++copies; }
void sd_bench_clear(void) { }
void sd_bench_key(void) { }

uint8_t sd_bench_command(uint8_t op)
{
  assert(irq_depth == 1);
  ++commands[op];
  switch (op) {
  case 0x81: regs[0xd680] |= 8; return 0;
  case 0x82: regs[0xd680] &= ~8; return 0;
  case 0x25: case 0x26: case 0x27:
    assert(native); /* No new commands may reach the legacy controller. */
    if (!cache) {
      regs[0xd680] |= 0x40;
      return 1;
    }
    return 0;
  case 0x0a:
    assert(native);
    open_stream = 0;
    return 0;
  case 0x07:
    assert(native && !open_stream);
    open_stream = 1;
    stream_sector = sector;
    break;
  case 0x08: case 0x09:
    assert(native && open_stream);
    sector = ++stream_sector;
    if (op == 0x09) open_stream = 0;
    break;
  case 0x0b: assert(native); break;
  case 0x02: break;
  default: assert(!"Unexpected command, including SD writes/write gates");
  }
  assert(!sector || (sector >= 2048 && sector - 2048 < partition_length));
  ++data_reads;
  if (trace) fprintf(trace, "%02x %lu\n", op, (unsigned long)sector);
  ++retry_reads; retry_stops += 2; /* Synthetic events, including counter wrap. */
  if ((fault == 1 && op == 0x08) || (fault == 2 && data_reads == fault_at)) {
    regs[0xd680] |= 0x40;
    return 1;
  }
  regs[0xd680] &= ~0x60;
  if (sector) memset(sector_buffer, 0xa5, sizeof sector_buffer);
  return 0;
}

static void le32(uint8_t *p, uint32_t value)
{
  unsigned i;
  for (i = 0; i < 4; ++i) { p[i] = value; value >>= 8; }
}

int main(int argc, char **argv)
{
  int result, expected_ok = 1;
  unsigned i;
  assert(argc == 2);
  if (getenv("SD_BENCH_TRACE")) {
    trace = fopen(getenv("SD_BENCH_TRACE"), "w");
    assert(trace);
  }
  native = strcmp(argv[1], "legacy") != 0;
  cache = strcmp(argv[1], "uncached") != 0;
  regs[0xd680] = 0x10;
  regs[0xd686] = native ? 0x0f : 0xfe;
  regs[0xd687] = native ? 0 : 0xa5;
  regs[0xd030] = 0xa0;
  regs[0xd031] = 0x20;
  regs[0xd054] = 0x20;
  regs[0xd689] = 0x20;
  if (!strcmp(argv[1], "stats")) { regs[0xd6cc] = 0x53; regs[0xd6cd] = 1; }
  le32(regs + 0xd7f2, 812500); /* 50 Hz at 40.625 MHz. */
  sector_buffer[510] = 0x55;
  sector_buffer[511] = 0xaa;
  sector_buffer[450] = 0x0c;
  le32(sector_buffer + 454, 2048);
  if (!strcmp(argv[1], "small")) partition_length = 3;
  le32(sector_buffer + 458, partition_length);
  if (!strcmp(argv[1], "bad-mbr")) {
    sector_buffer[510] = 0;
    expected_ok = 0;
  }
  if (!strcmp(argv[1], "overflow")) {
    le32(sector_buffer + 454, 0xfffffff0);
    expected_ok = 0;
  }
  if (!strcmp(argv[1], "stream-error")) { fault = 1; expected_ok = 0; }
  if (!strcmp(argv[1], "read-error")) {
    fault = 2; fault_at = 40; expected_ok = 0;
  }
  if (!strcmp(argv[1], "stopped-clock")) {
    stopped_clock = 1; expected_ok = 0;
  }
  result = sd_read_bench_run();
  if (trace) fclose(trace);
  assert(result == !expected_ok);
  assert(!open_stream && !irq_depth);
  assert(regs[0xd030] == 0xa0 && regs[0xd031] == 0x20);
  assert(regs[0xd054] == 0x20 && regs[0xd689] == 0x20);
  assert(!(regs[0xd680] & 8));
  if (!expected_ok) {
    if (!strcmp(argv[1], "bad-mbr") || !strcmp(argv[1], "overflow"))
      assert(data_reads == 1);
    if (stopped_clock) assert(!data_reads);
    if (fault == 1) assert(commands[0x0a]);
    if (fault == 2) assert(data_reads == fault_at);
  } else {
    assert(copies && commands[0x02]);
    if (native) {
      assert(commands[0x07] && commands[0x09] && commands[0x0b]);
      if (partition_length > 128) assert(commands[0x08]);
    } else {
      for (i = 0; i != 256; ++i)
        if (i != 0x02 && i != 0x81 && i != 0x82) assert(!commands[i]);
    }
  }
  fprintf(stderr, "PASS: %s (%u reads, %u copies)\n", argv[1], data_reads, copies);
  return 0;
}
