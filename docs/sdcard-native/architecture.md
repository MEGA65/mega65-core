# Native SD card controller, sector cache and FAT32 engine: architecture

Issues: SD controller MEGA65/mega65-core#890, cache #953, hardware FAT32 #766.

Status: the low-level controller and the upper-controller fork pass
simulation, and are plumbed into the mega65r6 target (not yet built in
Vivado or tried on hardware).  The cache and the FAT32 engine are plans.

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
  VIC-IV, sound and the like stubbed out).  Still to do: a Vivado build.
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

## 2. Sector cache

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
| `$29` | Data cache replacement: `$D681` = 0 random, 1 LRU |
| `$2A` | Meta cache replacement: `$D681` = 0 random, 1 LRU |

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
  - The command byte selects the operation, in a block such as `$30-$3F`.
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
