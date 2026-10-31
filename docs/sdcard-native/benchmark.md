# Read-only SD controller benchmark

Build the C64-mode PRG with cc65, then transfer it over USB:

```sh
make USE_LOCAL_CC65=1 src/utilities/sd_read_bench.prg
m65 -4 -r src/utilities/sd_read_bench.prg
```

Use the same PRG, SD card and slot for the legacy and native bitstreams.
The program opens a keyboard menu:

| Key | Action |
| --- | --- |
| `0` / `1` | Select card bus 0 / 1 |
| `B` | Run the two benchmark pages on the selected card |
| `C` / `I` / `R` / `S` | Read CSD / CID / SCR / SD Status |
| `A` | Show all four card-info pages, SPACE between pages |
| `N` | Reset/initialise the selected card |
| `P` | Probe/reset both cards concurrently, when supported |
| `X` | Native clear/recover without reset |
| `L` | Toggle the selected card's reported-capacity limit, when supported |
| `Q` | Exit, restoring the original selected bus |

The menu shows the selected bus, raw status/error registers, native versus
SPI mode and high/default speed. On cores with capacity protection it also
shows the limit state and inclusive last LBA. The retry signature identifies
recent native controllers without needing a successful sector read; older
native controllers are recognised from `$D686/$D687` after a common `$02`
read. Legacy cards return the `$FE` data token instead of native mode flags.

Bus selection preserves both sessions on the dual-card controller. Older
controllers are reinitialised when switching buses, including restoring the
original bus on exit. `N` explicitly initialises a card; `P` probes both
including absent sockets. Ordinary benchmark runs keep the existing card
mode/clock. Neither reset operation forces SPI or an overclock.

Card-info commands require `$D6CC=$53`, `$D6CD=1`, `$D6D8=$49`; unsupported
controllers never receive them. They work without an MBR/FAT32 partition.
Each page shows the raw 16/16/8/64-byte result, and CSD/CID pages also decode
capacity, manufacturer/product, serial and date. CSD capacity decoding covers
SDSC/SDHC/SDXC, including the 4294967296-sector (2 TiB) case. Press SPACE to
return to the menu. Info failures show status and leave recovery/reset to
the explicit menu actions.

Limit control requires `$D6D9`'s `$A0` signature. `L` issues `$30` (on) or
`$31` (off); the selected card's setting survives program exit and software
reset, so it can also be used with the freezer. Power-up defaults to on.
An unknown capacity no longer fails initialisation or bounds anything, so
`L` only matters for a card whose capacity is known. The benchmark itself remains
read-only and its timing reads still stay inside the discovered FAT32 window.

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

Select `B`. After the first page, capture it with `m65 -S0`, then press SPACE on the
MEGA65 (or use `m65 -t ' '`) to start the second page. Capture that page when
`BENCHMARK COMPLETE` appears; SPACE returns to the menu. Keep serial screenshots and other monitor activity outside
the timed runs; monitor memory access can stall the CPU while video time
continues.

Both controllers run exactly the same `$02` workloads: repeated reads of one
sector, sequential sectors, `RANDOM 512B` (one sector per scattered location),
and `RANDOM 4K` (eight consecutive sectors at each scattered location).
The deterministic walk uses a 509-sector stride for 512-byte requests and a
509-block stride for 4 KiB requests. The 4 KiB case uses eight ordinary `$02`
commands on both controllers, and completes each group before stopping.
Tiny partition windows use their full two- or four-sector size instead.
The native controller additionally runs those workloads
with the cache off and on (the repeated-sector cache test is warmed first),
scattered metadata reads with `$0B`, and explicit multi-sector reads with
`$07/$08/$09` in runs of up to 128 sectors. `$0A` closes the final partial
run. Cache controls are skipped if a native build has no cache handler.
New-controller commands are never sent to the legacy controller.

Each result shows completed 512-byte sector reads, KiB/s and `RETRY`.
The elapsed-time column is omitted because each workload has the same target
duration. `RETRY` is the sum of read-retry and stop/recovery-retry events
during the workload. It requires retry-statistics v1 in the FPGA; legacy and
older native builds display `--`, not zero. Initialisation/probe errors are
excluded. The last background fill/close is drained before timing and retry
counting end. Counts use wrapping 16-bit deltas per event type.
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
flags, buffer mapping/selection, original card bus and IRQ state on exit. Native cache tests
finish with the cache enabled. Read errors stop the benchmark and report
`$D680`, `$D686` and `$D687`; the latter two are diagnostic bytes on the
legacy controller, not native error flags. Sticky error/BUSY returns an error
promptly once the foreground command has ended; an old error while a new
command is starting is allowed to clear. The polling timeout is 120 video
frames per command. Extended/logical partitions and unpartitioned volumes
are outside this first benchmark's discovery support.

Host-side scheduler and error-path checks:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_sd_read_bench.py -v
```

These run the actual C benchmark logic against a register/card model. They
check legacy command gating, native multi-sector sequencing, cache bypass,
small and overflowing partition bounds, bad MBRs, stream/read errors and a
stopped clock. They also check random request addresses/group completion and
optional retry-counter deltas across wrapping counters. Menu cases exercise
all info pages, bus switching/restoration, capability gating, no-MBR info,
recovery, capacity decoding and limit selection. When cc65 and hyppotest
are available, they also assemble the real PRG and run its polling routine
against successful/sticky/stale errors and wrapping timeouts. DMA and actual
SD timings still need the on-machine run with the next bitstream.
