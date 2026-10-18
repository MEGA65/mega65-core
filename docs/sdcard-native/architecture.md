# Native SD card controller, sector cache and FAT32 engine: architecture

Issues: SD controller MEGA65/mega65-core#890, cache #953, hardware FAT32 #766.

Status: the low-level controller, upper-controller fork and data cache pass
simulation and are plumbed into mega65r6.  The first Vivado build missed
timing; commit `81ca519af` registers the critical controller paths.  Hardware
testing of that commit has begun (2026-10-18): internal-card reads work in
SPI fallback and, after a power cycle, native 4-bit high-speed mode. Checks
include identical uncached and cached MBR reads, the FAT32 boot sector and
the MEGA65 system-partition header. Boot exposed a legacy
busy-status compatibility bug, described below.  Read-ahead, the metadata
cache and the FAT32 engine are still plans.

## 1. Where things stand

| File | Role | State |
|---|---|---|
| `src/vhdl/sdcard_native.vhdl` | Low-level controller: native 4-bit SD bus, SPI fallback | Done, simulated |
| `src/vhdl/sdcardio_native.vhdl` | Fork of `sdcardio` that uses it | Done, simulated; **generated**, do not edit |
| `src/tools/make_sdcardio_native.py` | Generates the fork from `sdcardio.vhdl` | Done |
| `src/vhdl/sdcard_native_model.vhdl` | Behavioural SD card for simulation (native, SPI, CRC error injection) | Done |
| `src/vhdl/tb_sdcard_native.vhdl`, `tb_sdcardio_native.vhdl` | Testbenches | Pass |

### 1.0 Plumbing (mega65r6)

- `iomapper` and `machine` have a generic `sd_native` (default false) and
  native SD ports with defaults, so the other targets are unchanged.  With
  `sd_native`, `iomapper` instantiates `sdcardio_native` instead of
  `sdcardio`; the old SPI lines and the slot multiplexer stay idle, and the
  CIA bit-bashing of the SD lines does not work.
- `mega65r6.vhdl` sets `sd_native => true`.  Its SD pins keep their old
  names (`sdReset` = DAT3, `sdMOSI` = CMD, `sdMISO` = DAT0, and the same for
  `sd2*`), now bidirectional, plus new `sdDAT1/2` and `sd2DAT1/2`.  The
  tristate buffers are in the top level; the ODDR (clock), the IOB output
  registers and the IDDRs are inside `sdcard_native`.
- `mega65r5.xdc` (used by the r5 and r6 projects) enables DAT1/DAT2 of both
  slots and turns on pull-ups on CMD and DAT0-3.  (The r5 project's top level
  doesn't have the new ports, so building r5 now warns about them.)
- Every Vivado project with `iomapper` lists the two new sources, as does the
  Makefile's simulation list.
- Checked by GHDL elaboration of the whole r6 top level (with the CPU,
  VIC-IV, sound and the like stubbed out). Vivado timing closure still needs
  confirmation. Native 4-bit high-speed reads were checked on hardware after
  a power cycle: `$D686=$0F`, `$D687=$00`, with correct MBR and FAT32 boot
  sector data on slot 0.
- Pins checked against the TE0765 rev 06 schematic (pages 9, 10 and 20):

  | Slot | Socket | CLK | CMD | DAT0 | DAT1 | DAT2 | DAT3 | CD | WP |
  |---|---|---|---|---|---|---|---|---|---|
  | 0 (`sd*`)  | full-size SD (J15, "SD2") | B17 | B16 | B18 | C18 | C19 | B15 | D17 | C17 |
  | 1 (`sd2*`) | micro-SD (J2, "SD1")      | G2  | J2  | H2  | H3  | J1  | K2  | K1  | -   |

  Both sockets get VDD straight from 3.3 V (no power switch: `sdReset` really
  is DAT3).  CMD, DAT0-3, CD and WP have 12.1 kOhm pull-ups to 3.3 V, with no
  series resistors or level shifters, so the internal pull-ups in the XDC are
  only a belt-and-braces measure.  The card-detect lines (D17, K1; not
  constrained yet) are what the cache will use to invalidate on a card change.
- To try at higher clocks: SLEW FAST on the SD pins.

### 1.1 Low-level controller (`sdcard_native`)

- **Clocks.** The engine runs on clock162; SD_CLK comes from an ODDR.  The
  period is P half cycles of 3.086 ns, so the SD clock is 324 MHz / P:
  - 400 kHz for identification;
  - 24.9 MHz default speed (and SPI);
  - 40.5 MHz high speed, the default once CMD6 succeeds;
  - 46.3 / 54 / 64.8 / 81 MHz by probe and accept.
- **Inputs** go through an IDDR.  The sample point is D half cycles after the
  rising edge (D = 0..31).
- **Tags.** Every SD cycle has a number, and every input sample carries the
  number of its cycle.  Responses, data blocks, CRC status and busy are all
  found by scanning tagged samples for start bits.  So the sample point may lag
  by whole SD clocks, which is what makes the overclocked settings usable.
- **Flow control.** The clock stops exactly after a block's end bit when the
  next block isn't granted yet.  An open-ended CMD18 can therefore sit paused
  indefinitely, with no CMD12.
- **Host side (cpuclock, no BRAM).**
  - A command mailbox: INIT, READ, WRITE, MORE, STOP, PROBE, ACCEPT.
  - A read stream: one byte strobe per byte, which can be on every cycle,
    followed by a good/bad verdict per block.  After a bad CRC the controller
    resends the block.
  - Write data is fetched by offset from the host's buffer, with a fixed
    latency.
  - Both directions go through 32-entry LUTRAM FIFOs.
- **Throughput.** 81 MHz × 4 bits = 40.5 MB/s, which is one byte per cpuclock.
  That is the practical limit anyway, because a DMA copy out of the sector
  buffer costs time too.

### 1.2 Upper controller fork (`sdcardio_native`)

The fork keeps the existing `$D680` interface and adds:

| Command | Meaning |
|---|---|
| `$07` / `$08` / `$09` | Multi-sector read: first / next / last |
| `$0A` | End an open multi-sector read or write |
| `$20` | Probe a clock setting.  P is in `$D681`, D in `$D682`; pass/fail counts appear in `$D09B` / `$D09C` |
| `$21` | Use that setting from now on |
| `$22` | Back to the normal setting |
| `$23` | Re-initialise in SPI mode only |
| `$24` | Re-initialise, staying at default speed |

- `$D686` (read) returns status flags and `$D687` (read) the low-level error
  code.
- Commands may borrow the sector-number registers `$D681-$D684` as
  parameters.  This is the agreed convention for every new command below.

**Legacy ready semantics (hardware finding, 2026-10-18).** Hyppo probes slot
1 first and treats `$D680 & $03 == 0` as a usable card.  It does not inspect
the native ready/error flags.  The initial fork exposed the SD engine's idle
state after a failed init, so an empty slot was accepted: the screen said
`USING SDCARD BUS 1` and `FOUND AND RESET SDHC CARD`, but reads failed with
`ERR_NOTREADY` and left an empty buffer.  A successful init and MBR read on
slot 0 returned valid partition entries, independently of the cache.

The compatibility adapter now keeps `$D680.1` set while reset or init is
pending, while mailbox status is unsettled, or while the card is unusable.
An empty slot therefore times out in the existing firmware and falls back
to the other slot.  `$D686` and `$D687` still expose the native failure.
Open multi-sector transfers continue to clear busy between granted blocks.
`tb_sdcardio_native` has a `G_BOOT_TEST` mode covering empty-slot failure,
fallback, and immediate reset polling; `G_CACHE_LINES=0` exercises the same
contract without the cache, and `G_SPI_CARD=true` covers SPI fallback.

Hyppo also checks the selected card's native status after initialisation.
If it is ready in SPI mode, it displays
`SD STUCK IN SPI MODE. POWER-CYCLE TO FIX` and waits for a fresh keypress
before continuing at SPI speed. Native 4-bit mode, unavailable/error states,
and the legacy controller's `$FE` data token bypass this warning.
`src/hyppo/sd_spi_mode.test` exercises mode detection and key acknowledgement
using `src/tools/hyppotest` after assembling Hyppo.

A [read-only benchmark](benchmark.md) builds as
`src/utilities/sd_read_bench.prg`. It compares legacy `$02` reads with native
cache, metadata and multi-sector commands, with and without a RAM copy.

## 2. Sector cache

### 2.0 As built (steps 1 and 2)

`src/vhdl/sd_cache.vhdl`.  It turned out simplest to give the cache **the
host interface of `sdcard_native` on both sides** (command mailbox, status,
read stream, write fetch), so it sits transparently between them:
`sdcardio_native` talks to it exactly as it talked to the controller, and
with `G_LINES = 0` it is only wires.  `sdcardio_native` has a generic
`sd_cache_lines` (default 16 = 64 KB).

- A single-sector `C_READ` is looked up (parallel tag compare).
  - **Hit:** the sector streams out of the cache BRAM.
  - **Miss:** the cache reads from the requested sector to the end of the
    line as an open-ended transfer.  It passes the first sector up as it
    arrives, then grants the remaining blocks one ahead of the data, so the
    card isn't paused between blocks.
  - **A sector still on its way in:** the read waits for it.
  - **Any other command** first ends the fill with C_STOP after the blocks
    already granted.
- Everything else passes straight through: explicit multi-sector reads,
  writes, probe, accept, init.
  - Writes update cached sectors as the bytes are fetched.
  - A failed write empties the cache, and so does init (which also covers a
    slot change).
- New controller command `C_CACHE` (8): on, off (which also empties the
  cache), empty, and replacement policy (random by LFSR, or LRU by age
  stamps).
- Hit and miss counters.
- Unused lines are always chosen first.

`sdcardio_native` commands for it:

| Command | Meaning |
|---|---|
| `$0B` | Metadata read (sets bit 15 of the read's arg, for the future meta cache) |
| `$25` / `$26` / `$27` | Cache on / off / empty |
| `$28` | Hits and misses (16 bits each) into `$D681-$D684` |
| `$29` | Replacement policy: `$D681` bit 0 = 0 random, 1 LRU |

**Tests:** `tb_sd_cache` uses 4 lines and a slow card, about 50 µs access
latency.
- A hit takes 12.8 µs against 77 µs for a miss.
- It also covers: a whole line from one card read, with a CRC retry inside
  the background fill; a sector still on its way in; re-filling the earlier
  sectors of a line; a multi-sector read during a fill; write-through; cache
  off; LRU eviction order; random replacement; init emptying the cache.
- `tb_sdcardio_native` passes with the cache in.

**Card cleanup boundary (2026-10-18).** The upstream read completes when
its sector arrives; the card can still be closing CMD12 or sending tail
clocks. A free command mailbox is not an idle card. Cache misses and normal
pass-through commands now wait for downstream `busy=0`, and cache control
waits before switching away from downstream status. INIT can still abort,
and MORE/STOP can still control an active transfer.

`tb_sd_cache -gG_CLOSE_TEST=true -gG_HS_OK=false` reproduces the old race:
back-to-back misses for sectors 7 and 15 failed at default speed while the
first read was finishing. The regression also covers cache off/on followed
by another read. `G_ROM_TEST=true -gG_LINES=16` reads a 128 KiB ROM with FAT
lookups and software copy delays. `G_NAC=6 -gG_NAC_MULTI=0` tests early data
and blocks with no idle clocks between them.

**What it showed:** a program reading sequentially right behind a miss waits
about 26 µs per sector at 40.5 MHz, because the fill only runs at card speed.
Read-ahead into the next line (§2.3) is what removes that.

### 2.1 Placement: one entity, one client

```
           ┌──────────────────────────── sdcardio_native ───────────────────────────┐
 $D680 ──▶ │ command decode, F011 path ──┐                                          │
           │                             ├─▶ request port ──▶ sd_cache ──▶ sdcard_native
 (later)   │ FAT32 engine (8-bit) ───────┘        ▲                │               │
           └──────────────────────────────────────┼────────────────┼───────────────┘
                                                  └ stream back ◀──┘
```

- **`sd_cache.vhdl` is a separate, hand-written entity** between
  `sdcardio_native` and `sdcard_native`.  This keeps the generator script's
  edits small.
- **It has a single request port.** Regular operations and FAT32 operations
  never run at the same time, so the upper controller hosts the FAT32 engine
  and passes its requests over the same port.  There is no multi-client
  arbitration.  (Background prefetch is internal to the cache, not a client.)
- **The request port:**
  - op: data-read, meta-read, write, invalidate;
  - sector number;
  - destination: SD half or F011 half of the sector buffer.
  - It returns the byte stream into the sector buffer, plus done or error.
- **The cache is optional:**
  - `G_CACHE = false` builds a thin pass-through adapter, which behaves
    exactly like today's fork (for A100T targets etc.);
  - `G_DATA_BRAMS` sets the number of data lines (one RAMB36 = one 4 KB line);
  - `G_META_BRAMS` sets the meta-cache size (one RAMB36 = 8 sectors).
- **Default for the R6:** 16 data BRAMs (64 KB) + 2 meta BRAMs (16 sectors,
  8 KB) = **72 KB**.  The sector buffer already uses 2 RAMB36.

### 2.2 Data cache

- **Lines** are 4 KB (8 sectors), one RAMB36 each.  Tags live in registers,
  fully associative; with 16-64 lines, parallel compares at 40.5 MHz are cheap.
- **Valid bits are per sector, not per line.** A miss on sector k of a line
  fetches from k to the end of the line, so the requested sector comes first.
  Partly filled lines are fine.
- **Background fill.** The program's busy bit clears as soon as its sector is
  delivered; the rest of the line keeps streaming in.
  - A request for a sector that is still on its way in the current fill waits
    for it.
  - A miss elsewhere waits if only a few blocks remain.  Otherwise it ends the
    fill with C_STOP at a block boundary; sectors not yet fetched stay invalid.
  - Errors in prefetched sectors are never reported to the program.  Those
    sectors just stay invalid.
- **Hits** copy the sector into the sector buffer at 1 byte per cycle
  (12.6 µs).  A random card read costs hundreds of µs before data even starts,
  so this is a large win as it is.  (The 32-bit interface is for later; see
  §5.)
- **BRAM ports** (both cpuclock):
  - port A: fills from the low-level read stream, and write-through updates;
  - port B: copying out to the sector buffer.
- **Replacement, switchable at run time** (so it can be benchmarked on real
  hardware, and programs can choose):
  - random (an LFSR), the default for the data cache.  It degrades gracefully
    on cyclic access patterns slightly larger than the cache, where LRU fails
    badly.
  - LRU, the default for the meta cache, whose job is to hold on to hot FAT
    and directory sectors.

  Lines filled by read-ahead carry a "streaming" bit.  Victims are chosen in
  this order: an invalid line, then a streaming line that has been read, then
  a random (or the LRU) line.  A streaming line stops being streaming when it
  is read a second time.  This keeps streaming through a big file from
  flushing everything else.  The policy is global state, so reset
  (`$00`/`$01`) restores the defaults.  If one policy clearly wins, the other
  can become a generic so it costs nothing.

### 2.3 Sequential read-ahead

Software doesn't need to know about the multi-sector commands; plain `$02`
reads get the benefit.

- **Trigger:** a read of the last sector plus one, while the fill for that line
  is still running or has just finished.  Then keep the open-ended CMD18 going
  with C_MORE grants into the next line, and allocate that line.
- **Depth:** at most K lines ahead of the program (a generic, default 2).
  - While the program falls behind, grants run out and the low-level
    controller pauses the card with the clock stopped.
  - A non-sequential request ends the read-ahead.
- **Simple, sensible rules** (to tune on hardware): two consecutive sequential
  requests, or a request for the last two sectors of a line, start read-ahead.
  Getting the LRU insertion right (§2.2) matters more than the exact trigger.
- **F011 disk-image reads** use the same path, so D81 loads get read-ahead
  for free.

### 2.4 Meta cache

- **New command byte `$0B`:** a metadata read, otherwise the same as `$02`.
  Hyppo's FAT and directory code, and the libc, use it; plain programs keep
  using `$02`.
- **Lines are 512 bytes (one sector).** FAT and directory accesses are
  scattered, so 4 KB lines would waste most of a small cache.
- **No read-ahead**, or one extra sector at most.  It has its own LRU, so file
  data never evicts directory and FAT sectors.
- **Every read looks in both caches**, and writes update both.  A sector can
  legitimately be in both.

### 2.5 Writes and coherency

- **Write-through, always.** The card stays the authoritative copy: a cache
  bug can serve stale reads but can never lose data.
- **Updating the cache:** while a write streams out of the sector buffer (the
  low-level fetch path), the same bytes are copied into the cached sector's
  slot if the sector is cached.  Write misses don't allocate a line.  If the
  card reports a write error, the sector is invalidated.
- **A write during a background fill** first stops the CMD18 (the card has to
  leave it anyway).  Sectors not yet fetched stay invalid.
- **Multi-sector writes** (`$04` / `$05` / `$06`) follow the same rules, one
  sector at a time.
- **Invalidate everything** on reset/init (`$00` / `$01`, `$23`, `$24`), on a
  slot switch (`$C0` / `$C1`), and on a card-detect change.  Alternatively the
  tags could carry the slot.

### 2.6 Control, statistics, safety

Proposed codes, all taking parameters or returning values via `$D681-$D684`:

| Command | Meaning |
|---|---|
| `$25` | Cache on |
| `$26` | Cache off (behaves as the pass-through) |
| `$27` | Invalidate all |
| `$28` | Latch hit/miss counters into `$D681-$D684` for reading |
| `$29` | Data cache replacement: `$D681` bit 0 = 0 random, 1 LRU (built) |
| `$2A` | Meta cache replacement: `$D681` bit 0 = 0 random, 1 LRU (planned) |

- **Verify mode, for testing on hardware:** re-read every hit from the card
  and compare, counting mismatches.
- **Busy-bit compatibility:** some code (fdisk after `$06`) waits for busy to
  go high and then low.  Every command must keep busy visible for at least a
  few register polls; a hit's 12.6 µs copy already does.

### 2.7 Simulation

- Give `sdcard_native_model` a realistic access latency (hundreds of µs per
  command), so the cache's gain shows up.
- Random mixes of reads and writes, run with the cache on and off; the results
  must be the same.
- Coherency cases: a write to a sector of a line still being filled; a slot
  switch during read-ahead; an error in a prefetched sector.

## 3. FAT32 engine (later)

- **An 8-bit microcoded sequencer, per the MEGA65 architecture rule** (nothing
  like an ARM core).  It lives inside the upper controller and issues sector
  requests through the cache's request port.
- **Interface: command bytes plus registers, not magic sector numbers.**
  - The command byte selects the operation.  Assign its range after the
    protocol is defined; the expanded operation list may need subcommands
    or more than sixteen command bytes.
  - `$D681-$D684` carry the arguments: handle, offset, seek position, and so
    on.  (A magic sector range would cost the last 128 KB of a 2 TB card,
    which would be bearable, but command bytes are cleaner.)
  - The 512-byte sector buffer holds the request and the response blocks:
    path names, directory entries, results.  When reading or writing whole
    data sectors by handle, all 512 bytes are data.
- **Request blocks start with a magic number and a version byte**, so software
  can tell whether the core has the engine and which protocol it speaks.
- **Read-only first:**
  - path lookup with long filenames;
  - following cluster chains;
  - open, read and seek by handle.

  Writes (cluster allocation, both FAT copies, FSInfo, directory-entry
  updates, consistency if power drops) come later.
- **Handle writes need the `$57` write gate,** like raw sector writes.
- **Read-ahead by handle:** the engine knows each file's cluster chain, so it
  asks for exactly the right read-ahead, even across fragments.  The heuristic
  of §2.3 then only matters for raw-sector users.
- **Possible optimisation:** a byte/word read port into the cache for the
  engine.  It could read a FAT entry or a directory field without waiting for
  a 512-byte copy.  Cache port B is free while the engine runs, because
  copy-outs and engine work never overlap.
- **Disk images on handles:** later, D81/D65 images move onto two reserved
  handles, so images can at last be fragmented and still work.  The freezer
  then has to save and restore those handles' state.  This is not part of the
  first version.

### 3.1 Follow-on requirements (recorded 2026-10-18; implementation deferred)

- Probe both cards and their partition tables, with the external card taking
  priority over the internal card.  Interpret the requested limit as up to
  **four FAT32 partitions per card, eight total**, mounted as `1:` through
  `8:`; `0:` aliases the current drive.  Provide `getpartitionlist()` and
  `setdrive()`.  The list must identify the backing card, partition start
  and extent, and access status.  Drive assignment on rescan must not
  silently redirect existing descriptors to another volume.
- Eight descriptors total, shared by files and directories.  Reserve FDs
  **0 and 1 for disk images**; normal allocation uses **2 through 7**.
  `open()` may request an explicit descriptor, subject to those restrictions.
  Directory descriptors retain independent iteration state.
- `opendir(path)` returns an FD.  `readdir(fd)` returns one entry per call,
  including its long filename.  Support opening a file either by a returned
  directory entry or by a supplied path, closing descriptors, changing the
  current directory, and creating files.  Entry-based opens need a stable
  entry identity and validation against directory changes and media changes.
- Seek relative to the start, end or current file position.  Read, write,
  or append **up to 512 bytes** per call; return the actual byte count.
  Support truncation.  Define growth permission separately from permission
  to overwrite existing bytes: read-only/read-write and
  appendable/non-appendable are distinct open capabilities.
- Read or write **exactly 512 bytes at a specified file-sector offset**.
  These will serve disk images, including fragmented files.  Define bounds
  and EOF handling explicitly; proposed behaviour is to leave the normal
  file position unchanged and reject an exact read that crosses EOF.
- Include `mkdir()`, `rmdir()`, `delete()`, and `setattr()`.
- A protected system path is accessible only in hypervisor mode.  The
  hypervisor controls application read-only/read-write access, and disk-image
  mounting commands are hypervisor-only.  Effective access combines those
  policies, descriptor permissions, media write protection and the existing
  write gate.  Path normalisation, entry-based opens, reserved descriptors
  and raw-sector access must all respect the policy; restricting pathname
  commands alone would leave a bypass.

Recommended additions to settle before freezing the protocol: rename/move,
stat and free-space queries, explicit sync, EOF versus error results,
partial-transfer and seek/truncation rules, filename encoding and path
limits, and stale-descriptor handling after removal or reprobe.  Keep
ordinary close/flush, directory EOF and per-drive current directories
unambiguous.  Multiple opens of the same file also need a defined write and
truncate policy.  None of these commands or opcode allocations is
implemented yet.

### 3.2 FAT32 storage budget

The FAT32 engine may add **exactly one RAMB36** for filesystem state and
descriptors.  Budget against its 4096 byte-wide data bytes, without relying
on parity bits.  An initial sizing exercise is:

| State | Provisional bytes |
|---|---:|
| Eight partition records, 64 bytes each | 512 |
| Eight file/directory descriptors, 128 bytes each | 1024 |
| Eight current-directory records, 16 bytes each | 128 |
| Shared traversal, LFN and allocation scratch | 1024 |
| Remaining layout headroom | 1408 |

This is a feasibility budget, not a fixed record format.  Reuse the existing
sector buffer for requests, directory results and sector I/O; do not reserve
a sector buffer or full pathname per FD.  Names plus result metadata may
need separate transfers rather than a single fixed response block.  The
microcode store must use LUT ROM or another existing resource, rather than
silently adding another BRAM.  A100T builds must be able to disable both
optional caches while retaining FAT32 support within this additional-BRAM
limit.

## 4. Order of work

1. **`sd_cache` as a pass-through** with the request port, and the fork
   re-pointed at it via the generator script.  The existing testbenches must
   still pass.
2. **Data cache:** hits, requested-sector-first fills with per-sector valid
   bits, write-through updates, invalidation, `$25`-`$28`.
3. **Background fill and sequential read-ahead.**
4. **Meta cache and `$0B`.**  Change hyppo and libc to use it for FAT and
   directory reads.
5. **FAT32 engine, read-only:** microcode sequencer, request-block protocol,
   handles.
6. **Disk images on reserved handles, and freezer support.**
7. **FAT32 writes.**

## 5. Deferred (not now)

- A 32-bit path between the cache and the sector buffer (RAMB36 supports mixed
  port widths; the fork can use its own `sector_buffer` variant).
- A DMAgic job type that reads SD sectors straight into a chosen memory
  location, skipping the sector-buffer copy.
- Finer sample-point tuning with IDELAYE2 taps (needs a 200/300 MHz
  IDELAYCTRL reference clock).
- High speed in SPI mode.
- Probing a sector other than 0.
