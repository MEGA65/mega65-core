# Read-only SD controller benchmark

Build the C64-mode PRG with cc65, then transfer it over USB:

```sh
make USE_LOCAL_CC65=1 src/utilities/sd_read_bench.prg
m65 -4 -r src/utilities/sd_read_bench.prg
```

Use the same PRG, SD card and slot for the legacy and native bitstreams.
The card must already be initialised. The program keeps its current bus
mode: it does not reset the card, force SPI or change the SD clock. On the
native controller it reports native 4-bit versus SPI and high versus default
speed. It identifies the controller from `$D686/$D687` after a successful
common `$02` read; legacy cards return the `$FE` data token instead of native
mode flags.

The program reads the MBR and uses a power-of-two window of up to 16384
sectors (8 MiB) inside the first FAT32 partition. All benchmark reads stay
inside that partition. It stops if the MBR, partition bounds or read status
are invalid. There are **no card-write commands or write-gate commands**.
The `FAT32 LBA` value is the partition's starting 512-byte sector number;
2048 means a 1 MiB offset from the start of the card. The header's CPU clock
is the configured timing-calibration frequency, displayed in MHz.

There are two result pages:

1. Card to controller sector buffer: includes command setup and polling.
2. The same reads, followed by a 512-byte DMA copy to application RAM. This
   includes DMA setup and transfer time.

After the first page, capture it with `m65 -S0`, then press SPACE on the
MEGA65 (or use `m65 -t ' '`) to start the second page. Capture that page when
`DONE` appears. Keep serial screenshots and other monitor activity outside
the timed runs; monitor memory access can stall the CPU while video time
continues.

Both controllers run exactly the same `$02` workloads: repeated reads of one
sector, sequential sectors, and a deterministic scattered walk with a
509-sector stride. The native controller additionally runs those workloads
with the cache off and on (the repeated-sector cache test is warmed first),
scattered metadata reads with `$0B`, and explicit multi-sector reads with
`$07/$08/$09` in runs of up to 128 sectors. `$0A` closes the final partial
run. Cache controls are skipped if a native build has no cache handler.
New-controller commands are never sent to the legacy controller.

Each result shows completed sector reads, elapsed milliseconds and KiB/s.
Printing, cache setup, warm-up and keyboard waits are outside the timed
regions. Reads include controller error checking; this is a throughput
benchmark, not a full data-integrity test or a filesystem benchmark.

Timing uses the hardware frame counter, with its period calibrated from
`$D7F2-$D7F5` at full CPU speed. IRQs are disabled during the program; CIA
timers are left alone. Default runs last about two seconds per workload,
with about one video frame of timing uncertainty. PAL, NTSC and VGA frame
rates are calibrated rather than assumed. The clock-frequency conversion
defaults to **40.625 MHz**, as generated for r6 by `clocking.vhdl`. Override
it when comparing a bitstream with another CPU clock:

```sh
make -B USE_LOCAL_CC65=1 \
  SD_BENCH_CFLAGS='-DSD_BENCH_CPU_HZ=40500000UL -DSD_BENCH_SECONDS=5' \
  src/utilities/sd_read_bench.prg
```

Use equal settings for both controllers. The program restores the CPU speed
flags, buffer mapping/selection and IRQ state on exit. Native cache tests
finish with the cache enabled. Read errors stop the benchmark and report
`$D680`, `$D686` and `$D687`; the latter two are diagnostic bytes on the
legacy controller, not native error flags. The polling timeout is 120 video
frames per command. Extended/logical partitions and unpartitioned volumes
are outside this first benchmark's discovery support.

Host-side scheduler and error-path checks:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_sd_read_bench.py -v
```

These run the actual C benchmark logic against a register/card model. They
check legacy command gating, native multi-sector sequencing, cache bypass,
small and overflowing partition bounds, bad MBRs, stream/read errors and a
stopped clock. They do not emulate the 6502 polling or DMA hardware; those
paths still need the on-machine run with the next bitstream.
