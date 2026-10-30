# Native SD card controller, sector cache and FAT32 engine: architecture

Issues: SD controller MEGA65/mega65-core#890, cache #953, hardware FAT32 #766.

Status: native 4-bit and SPI reads, the data cache/read-ahead and Hyppo boot
work on hardware with `30f3f7e15`. The two persistent card sessions and
parallel initialisation described below are tested in simulation; FPGA
resource/timing results and hardware confirmation are pending. Sequential
read-ahead across lines, the separate metadata cache (§2.3, §2.4) and card
detect are built and simulated (2026-10-21), not yet tried on hardware.
The hardware FAT32 engine ([fat32-engine.md](fat32-engine.md)) is built,
reading and writing, and tested against the simulator and in RTL; Hyppo
does not use it yet. [hardware-tests.md](hardware-tests.md) is the plan
for trying all of it on a board.

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
  - 24.9 MHz default speed;
  - 12.5 MHz SPI (`$031A`): in SPI the card launches a bit at the falling
    edge, up to 14 ns late, and the sample point is not probed, so 24.9 MHz
    left about 6 ns less the board's delay; on hardware a card's SPI reads
    and CMD12 responses failed now and then (84 of each in a stress run);
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
| `$00` then `$01` | Reset, then initialise (as legacy).  A `$01` with the slot not in reset (since `$00`/`$10`, or power-up) only clears the errors: the legacy init starts as its reset is released, and FDISK writes `$01` before every sector write |
| `$07` / `$08` / `$09` | Multi-sector read: first / next / last |
| `$0A` | End an open multi-sector read or write |
| `$20` | Probe a clock setting.  P is in `$D681`, D in `$D682`; pass/fail counts appear in `$D09B` / `$D09C` |
| `$21` | Use that setting from now on |
| `$22` | Back to the normal setting |
| `$23` | Re-initialise in SPI mode only |
| `$24` | Re-initialise, staying at default speed |
| `$2A` | Clear errors/recover without card reset; invalidate cached data |
| `$2B` | Initialise both slots concurrently; each slot reports its own result |
| `$2C` | Read CSD (capacity/card parameters), 16 bytes |
| `$2D` | Read CID (manufacturer/product/serial/date), 16 bytes |
| `$2E` | Read SCR (SD version/bus capabilities), 8 bytes |
| `$2F` | Read SD Status (speed classes/allocation/erase information), 64 bytes |
| `$30` | Enable the selected card's reported-capacity limit (power-up default) |
| `$31` | Disable that limit for explicit raw-card diagnostics |
| `$70-$7F` | The hardware FAT32 engine ([fat32-engine.md](fat32-engine.md)); arguments and results in `$D681-$D684`, its status in `$D687` (generic `sd_fat32`) |

- `$D686` (read) returns status flags and `$D687` (read) the low-level error
  code.
- Commands may borrow the sector-number registers `$D681-$D684` as
  parameters.  This is the agreed convention for every new command below.

With the engine (`sd_fat32`), its read-only policy for programs also
refuses their raw writes `$03-$06`: an error, with `$D687` = `$0F`.  Each
F011 disk image is bound to the card selected when the hypervisor wrote its
start sector (`$D68C-$D68F`, `$D690-$D693`); `$D68A` bits 4 and 5 show
which (1 = external).

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

**Retry diagnostics v1.** Native-only registers `$D6CC=$53` and `$D6CD=1`
identify support; these previously unused addresses read zero on older
builds. Write `$D6CE=$80` to latch all 16 diagnostic bytes, then write a byte
index (0..15) to `$D6CE` and read `$D6CF`. The snapshot does not issue a card
command or change the sector address/buffer/cache. Its little-endian words
are read retries, stop retries, read CRC errors, read timeouts, read command
errors, terminal read failures, terminal stop failures, and current clock
setting. Event counts wrap at 65536, include both slots/native/SPI, survive
card reinitialisation and clear with FPGA configuration. Init/probe read
errors are excluded. Counters cross to the CPU with the existing coherent
status mailbox and use registers, with no extra BRAM.
`tb_sdcardio_native` has a `G_BOOT_TEST` mode covering empty-slot failure,
fallback, and immediate reset polling; `G_CACHE_LINES=0` exercises the same
contract without the cache, and `G_SPI_CARD=true` covers SPI fallback.

**Init record.** Bytes 17-23 (latched by the same `$80` write) say why the
selected card's (`$C0`/`$C1`, not the slot of the last command) last initialisation gave up the native bus and fell back to
SPI, or, in an SPI-only init (`$23`), why its SPI init failed; they are zero
when neither happened, and cleared by every init.

| Byte | |
|---|---|
| 17 | The init step that failed: 4 CMD55 (no SD-mode answer), 5 ACMD41 (power-up), 7 CMD2, 8 CMD3, 21 CMD9 (with the capacity limit on), 10 CMD7, 11 CMD55, 12 ACMD6 (4-bit bus), 15 CMD16, 13 the test read of block 0.  16 and up: an SPI-only init's step (16 + its step: 0/1 CMD0, 2 CMD8, 4/5 ACMD41, 7 CMD58, 9 CMD59, 10 CMD16, 15 the test read) |
| 18 | Flags: bit 0 fell back to SPI; 1 no response; 2 a response came (with 1 and 2 clear: its CRC, index or header was bad); 3 the test read failed at high speed and was retried at default speed; 4 the test read failed at default speed; 5 the card did not grant high speed; 6 native init failed once and was tried again before SPI (bytes 17 and 20-23 are then from the second try), or an SPI-only init failed once and was tried again (bytes 17 and 20-23 from the last failure: when the retry passed, from the first try); 7 the failed command's busy (DAT0 low after an R1b) did not end within 1.5 s |
| 19 | The failed test read's error code |
| 20-23 | Bits 39..8 of the last response (R1 card status, OCR, ...), little-endian; for an SPI step, byte 23 is its R1 and 20-22 the low 24 bits of the R3/R7 after it |

**Present but not answering.**  `$D687` reads `$03` in place of `$01` (no
card answered) when the selected slot's card-detect switch said a card was in
as the init failed, and still does (diagnostic byte 16: bit 0 slot 0, bit 2 slot 1, low when
a card is in).  A slot that was empty at boot reads `$01` after a card is
put in, until an init fails with the card in, and a card pulled after its
init failed reads `$01` again, and still does once a card is put back, until
an init of it fails (the change shows in byte 16 bits 4-5, so software can init it).  An
empty slot and a card that answers nothing fail the init alike (native step
4, then the SPI fallback); only card detect tells them apart.  On hardware a
card that had a native init and then an SPI-only one (`$23`) answered no
init of either kind until it was re-inserted, which powers it off and on (the
sockets have no power switch).  Only the code differs: `$D680` and `$D686`
are as for `$01`, and a board without card detect (the input defaults to
"no card") still reads `$01`.
Hyppo, when neither slot gave it a card at boot, reads `$D687` for the
external slot and then the internal one (only with the native signature at
`$D6CC`/`$D6CD`), and on a `$03` from either prints "SD CARD IS IN BUT NOT
RESPONDING." and "REINSERT IT OR POWER-CYCLE, THEN RESET." and waits for a
key (as the SPI-mode warning does) before the built-in ROM, in place of "NO
SDCARD, TRYING BUILT-IN ROM".

An SPI init that fails is tried once more before it gives up (with or
without a native fallback before it).  On hardware a card's first SPI-only
init after it was inserted failed with `$02` and the next passed; a card
that has had a native CMD0 since power-up may not take SPI mode at all
(`$01`: CMD0 in SPI never answered), until it is re-inserted.

**SPI writes.**  A write block's data response (`xxx0sss1`) is looked for
bit by bit after the last CRC byte, not byte by byte: some cards send it a
few bits late (Linux's `mmc_spi` does the same; its first 3 bits are
undefined).  On hardware a card's late response was missed, and the write
failed with `$33` (no data response).  `G_SPI_LATE=3`
(`run_sdcard_tests.py io-spi-late`) sends every other response 3 bits late.
The busy after it, or after a multi-block write's stop token, ends only after
four `$FF` bytes in a row, and before every SPI command but CMD0 and CMD12 the
controller clocks `$FF` until the card has sent four `$FF` bytes in a row (up
to 1.5 s, then the command fails as unanswered), as native mode waits for
DAT0 high before a read or write.  A card may start its busy a byte or more
late, and a busy card holds DO low: a command sent then reads its `$00` as R1
"no error".  On hardware an SPI card lost the 26 sectors before a
multi-block write's first in its 16 KB unit, with no error seen.
`G_SPI_BUSY_LATE=3` (`io-spi-busy-late`, `io-spi-replay-busy`) starts the
model's busy 3 bytes late; the model reports a command or data token sent
while it is busy.  SPI byte positions are 13-bit
numbers that wrap every 8192 bytes; "after" a command or a write's CRC is up
to 4095 bytes on (a plain compare missed a response just after a wrap, and
the operation timed out: `$32` after a write block).

**Conservative timing for poor cards.**  A data block starts only on all
four DAT lines low (DAT0 alone low is a busy).  Before a read or write
command the controller waits for the card to be idle (DAT0 high for 8 clocks,
or 1.5 s, the busy timeout; it was 750 ms, which a slow card can exceed).  After an R1b command the card has 31 clocks to start its busy.
An init that arrives while a write block is on its way (its data, CRC
status, or the busy after it or after the CMD12 ending the write) waits for
the block to finish, so that a write is cut only between sectors.

**Failed block.**  Bytes 32-55 (latched by the same `$80` write) keep the
first native data block since the selected card's last init whose CRC or
end bit was wrong; byte 32 bit 0 says whether there is one.  Each block's
CRCs and end bits are captured as it ends, and the capture freezes a cycle
after one fails, so the 162 MHz paths gain no compare.

| Byte | |
|---|---|
| 32 | Bit 0 a block failed; bits 4-1 its end-bit nibble (DAT3..0, all ones when right); bit 5 DAT0 went low with the other lines high while a block was awaited (a card's busy, which is not taken for a start bit) |
| 33 | Its block number in the transfer (low 8 bits) |
| 34-35 | The clock setting it was read with (bits 6-0 P, 12-8 D) |
| 36-37 | Its start bit's tag minus the command's end tag (SD clocks; the first block's Nac) |
| 38-45 | The CRC16s received, DAT0 first, each little-endian |
| 46-53 | The CRC16s worked out from the data |
| 54-55 | Its first two bytes (55 the first) |

One line's CRC wrong and the other three right is that line's signal or
sampling point; all four wrong with a wrong end bit is the block found in
the wrong place (framing); a CRC off by a bit or two is isolated bit errors.

Step 5 with a response (bit 2) means the card never finished powering up
within a second.  Native init starts with CMD12 (a card left in a
multi-block read by a reset or by configuring the FPGA stops it; an idle
card ignores it), and a failed native init is tried once more before
falling back to SPI: a card leaves SPI mode only by a power cycle, so a
fallback after one transient failure would last until the card is
re-inserted.  `sdstress` (mode 1, [sdstress.md](sdstress.md)) prints
this.  `tb_sdcardio_native` checks it with `G_SPI_CARD=true` (step 4, no
response) and without (all zero).

Terminal native or upper-controller errors also keep `$D680.1` asserted.
This preserves software that detects failure by a busy timeout. New callers
can issue `$2A` after `$D680.0` clears instead of resetting the card. Native
SD uses a checked CMD12/CMD13 recovery; SPI clears the error after the
retired transfer has deselected the card. Success clears the error and busy
flags without changing the selected slot or reinitialising bus mode. If
recovery fails, error/BUSY stay asserted. The sector address is preserved.
`G_ERROR_TEST=true` covers this with 16 cache lines, with `G_CACHE_LINES=0`,
and with `G_SPI_CARD=true`.

Hyppo also checks the selected card's native status after initialisation.
If it is ready in SPI mode, it displays
`SD STUCK IN SPI MODE. POWER-CYCLE TO FIX` and waits for a fresh keypress
before continuing at SPI speed. Native 4-bit mode, unavailable/error states,
and the legacy controller's `$FE` data token bypass this warning.
`src/hyppo/sd_spi_mode.test` exercises mode detection and key acknowledgement
using `src/tools/hyppotest` after assembling Hyppo.

Hyppo checks `$D680.6` both while polling and after ready. An error takes
the existing reset/retry path immediately, including when legacy BUSY is
deliberately stuck. A failed sector buffer is never accepted as a successful
read. `src/hyppo/sd_read_errors.test` covers idle success, idle error, and
error with BUSY still asserted.

**Freezing checks its writes.** The freeze (RESTORE) used to take every
write of the freeze slot for a good one: `sd_wait_for_ready` only waits for
BUSY to clear, and never gives up.  Each write now waits in
`freeze_wait_write`, which fails on `$D680.6` or after three timeout
windows of BUSY; after a failure nothing more is written.  Freezing then
undoes itself: a card reset (bounded: the card may be gone), then the SD
sector buffer, `$D681-$D684`, `$D070`, `$D030` and the DMA list address as
they were (memory itself is only read while freezing).  It blinks the
border red and black at about 3 Hz for 2 seconds and goes back to the
program, instead of loading the freezer over a program that could not be
resumed.  No freeze slot (no system partition) is a failure too.
`src/hyppo/freeze_errors.test`.

**Boot polling and session reuse.** With retry diagnostics v1 present,
Hyppo polls each slot's BUSY/error status immediately after reset instead of
always sleeping before checking it. An empty external slot can therefore
fall back to the internal slot as soon as initialisation reports failure;
external cards retain priority. Slow cards still get three complete polling
timeout windows, and the controller's protocol timeouts are unchanged.
Legacy controllers, older native builds and unknown diagnostic versions keep
the original settling waits. The initial general boot settling delay remains.

On an internal-only boot the former slot search incurred three fixed waits
for the absent external card and at least one for the internal card. Each
fixed wait runs a 24-bit counter from `$F30000` to zero (851968 increments),
irrespective of when the card becomes ready or reports an error. Hyppo also
avoids resetting the selected card again in `readmbr` if the new controller
reports no busy/reset/error condition, native READY and a zero error code;
otherwise it takes the existing reset path. The normal SDHC/MBR reads remain.

`src/hyppo/sd_boot_wait.test` and `sd_boot_slots.test` cover readiness, errors,
timeout windows, legacy fallback, slot priority, healthy-session reuse and
the `$03` message (either slot; never on a legacy controller).
These are assembled-code tests with mocked register state, not physical
boot-time measurements. Hardware timing of the reduced waits is pending.

**Two persistent card sessions.** `sdcard_native_dual` (in the same source
file as `sdcard_native`) instantiates one engine per socket. Each owns its
RCA, native/SPI mode, high-speed state, clock/sample setting, errors and
protocol state. The engines instantiate only their own socket's I/O
primitives. The upper controller, sector buffer and data-cache BRAM remain
shared. Engine FIFOs use LUTRAM, so the second session requires no extra
BRAM; its LUT/FF cost and timing still require synthesis confirmation.

`$D6CC=$53`, `$D6CD=1`, **`$D6D7=$D2`** identifies this extension. The retry
diagnostic layout/version remains unchanged. The exact new signature avoids
mistaking an older controller's unmapped register for support.

- `$C0/$C1` selects the card for subsequent requests and immediately changes
  the `$D680`, `$D686` and `$D687` status view. Selection issues no reset and
  preserves cache lines from both cards. Pending mailbox/reset latency,
  ready, native/SPI mode, RESET and sticky error/BUSY are scoped to the card.
- `$00/$01` and `$10/$11` retain selected-card reset semantics. `$23/$24`
  also reinitialise only the selected card. Reset assertion/host errors for
  one card do not become the other card's status.
- New `$2B` starts both card initialisations together, including probing
  empty sockets. Failures are independent. Software selects either slot to
  poll its result; an absent card retains legacy error/stuck-BUSY semantics.
- New Hyppo recognises the extension, selects external and issues `$2B`.
  If external probing fails, it selects internal and uses the result already
  in progress/completed, with no second reset. Both probes overlap: the
  relevant wait is governed by their completion times rather than their sum.
  Older controllers use the existing sequential reset path.
- Requests capture their card at acceptance. Selection during a foreground
  transfer changes the status view without redirecting data or write fetches.
  The shared buffer still supports one foreground operation at a time;
  software completes/copies that result before starting another operation.
- A cross-card data request drains an earlier transfer and uses the existing
  checked stop/close before reassigning the shared stream. An idle/failed
  card does not prevent using the other card after its own transfer retires.

Cache identity is `(slot, sector / 8)`, adding one register bit per line.
Requests, fills and write snoops retain their slot, including when the
selection changes. A selected-card init/recovery or failed write invalidates
that card's lines; `$2B` and explicit cache flush invalidate both. Metadata
cache tags will need the same card identity. Retry counters remain aggregate
across the two sockets, and the snapshot's clock setting follows selection.

The upper testbench's `G_DUAL_TEST` covers all four populated/empty socket
combinations, concurrent clock starts, cache separation for identical LBAs,
selection during a long read, independent legacy reset/error state, mixed
SPI/native operation and `G_CACHE_LINES=0`. `tb_sd_cache` has a lower-level
`G_DUAL_TEST` for cross-card fill/stream handover. Simulation shortens only
protocol millisecond counters; pin/CPU clocks and frame/data timing remain.
The upper dual tests disable automatic power-up init so the explicit `$2B`
must start both sockets. Lower dual tests with `G_DUAL_SPI0` / `G_DUAL_SPI1`
also check reads on the ready socket while the other is still initialising.
Their same-LBA writes check that write fetches and cache snoops affect only
the owning card, with native/SPI roles tested in both directions.
These are simulation checks, not measured hardware boot times.

**Read-only card information.** `$D6CC=$53`, `$D6CD=1`, `$D6D8=$49`
identifies the `$2C`--`$2F` commands. Select the card with `$C0/$C1`, issue
the command and poll the usual `$D680` busy/error bits before reading the
normal 512-byte SD sector buffer. Each result starts at offset zero, with
the most significant register byte first; the rest of the buffer is zero.
CID/CSD include their register CRC7/end byte. Data tokens, response headers
and the transfer CRC16 of SCR/SD Status are not included. All four fit in
one sector buffer; no extra BRAM or information cache is needed.

These commands leave `$D681`--`$D684` unchanged, bypass the sector cache and
retain its data. They close any open multi-sector transfer first, and latch
the selected slot like ordinary reads. Native CID/CSD temporarily deselect
the card with CMD7, read CMD9/CMD10 in Stand-by, then reselect it without
resetting or changing its speed/bus width. SCR/SD Status use ACMD51/ACMD13
short data transfers; an SCR may finish before its command response, so
the data verdict is retained separately. SPI reads use short data blocks
for all four, including the second response byte of ACMD13's SPI R2.

Native R2 header/CRC7 and short-data CRC16 are verified; SPI transfer CRC16 is
verified. Only a successful, padded 512-byte result publishes completion.
Failure retains the legacy error/stuck-BUSY indication; the buffer must
then be treated as invalid. Native failures use the checked CMD12/CMD13
close; SPI deselects with trailing clocks. `$2A` can recover without a card
reset. Information failures do not increment sector-read error counters.

`G_INFO_TEST` in the core testbench checks all payloads/padding, CRC errors,
malformed R2 headers, timeouts, recovery and subsequent ordinary reads in
native and SPI modes.
The upper testbench checks both slots, cache bypass/preservation, unchanged
sector addresses, mixed native/SPI cards, CRC error/BUSY and no-cache mode.

**Default capacity bounds.** Each card's initialisation reads CSD before
publishing READY. Native SD uses CMD9 in Stand-by before CMD7; SPI consumes
the short CSD block privately, without publishing bytes into the shared
sector buffer. CSD v1 (SDSC) and v2 (SDHC/SDXC) are decoded to an inclusive
32-bit last LBA; a 2 TiB card therefore has last LBA `$FFFFFFFF`, not zero.
This adds registers, not BRAM. The existing retry diagnostics remain v1.

Reads, writes and speed-probe reads are bounded by default. A fixed-length
request crossing the end is rejected in full, including 32-bit address
overflow. An open multi-sector read/write accepts only in-range grants;
an out-of-range next grant closes the existing stream and returns an error
without transferring that sector. Error `$44` means out of range; `$45`
means the capacity is unavailable/unsupported. Legacy sticky error/BUSY
semantics are retained, allowing existing sector-reading tools, including
the freezer, to encounter an error at the reported end without changing
their read commands. The limit uses the card's advertised capacity.

`$D680 <- $31` disables protection for the selected card; `$30` enables it.
Issue these between foreground operations. The settings are independent
per slot and survive software resets; power-up enables both. They can be
set even after init failed, so explicit override followed by reset can
initialise a card whose CSD cannot be decoded. With protection enabled,
unknown capacity prevents init/access. Re-enabling protection also blocks
cached sectors fetched beyond capacity while override was enabled. Cache
read-ahead stops at the reported end, including a partially filled final
line. The engine registers the range sum and next-grant address so wide
addition and comparison do not share the 162 MHz control path.

`$D6D9 = $A0 | (capacity_known << 1) | limit_enabled` reports the selected
slot's policy/result and identifies this extension. To read its inclusive
last LBA, write byte index 0--3 to `$D6DC`, then read `$D6DD` (little endian).
This window changes neither the sector address nor the sector buffer;
ignore its LBA when `capacity_known` is zero. Cached range errors also
appear in `$D687`, and their code survives operations on the other card.

`G_BOUND_TEST`, `G_MAXCARD_TEST` and `G_CAPFAIL_TEST` cover the boundaries,
overflow, bulk/open read/write rejection, override/reset behaviour, SDSC,
SPI, unknown capacity and 2 TiB decoding. The upper tests include cache
override/re-enable and per-card limits/error codes; `G_TAIL_TEST` exercises
a synthetic capacity that ends halfway through a cache line in native/SPI.

**Checked native close.** A read's final CMD12 waits for its response and
busy phase, then sends CMD13 and requires Transfer state plus READY_FOR_DATA.
CMD13 is also sent after an unanswered CMD12: a completed single-block read
has already returned the card to Transfer, where CMD12 is illegal and may
receive no reply. A positively confirmed Transfer/ready status is sufficient
for recovery in that case.
An accepted-looking stop is insufficient if the card still reports Data
state. Three failed attempts invalidate the card session and block further
reads; `$2A` can recover that session once a checked close succeeds. Failed
single-sector reads also use the stop/status sequence before retrying,
because a framing error can leave part of their sector on the bus. Receiver
data is discarded during cleanup. Clock defaults and BRAM use are unchanged.

`tb_sdcard_native -gG_STOP_TEST=true` exercises missing CMD12 responses
(`G_STOP_FAILS=1`), a stop acknowledged without actually stopping
(`G_STOP_ACK_FAILS=1`), permanent failure (`99`), and recovery without init
after three failed stops (`G_STOP_FAILS=3`). The permanent acknowledged-stop
case failed before the checked-close change. See the
[ROM-load investigation](rom-load-debug.md) for the physical captures.
`G_SINGLE_CRC_TEST=true` makes the model ignore CMD12 in Transfer and verifies
both a failed single-read CRC retry and an explicit clear on an idle card.

Read-start eligibility and command-gap completion stay latched once their
tag boundaries have passed. Recomputing a wrapping 16-bit ordering test
would revoke eligibility after 32768 SD clocks (about 0.807 ms at 40.625 MHz),
even though the read timeout permits much longer card access times. Each
new boundary assignment explicitly clears its latch. The native testbench's
`G_LONG_READ_NAC=40000` and `G_LONG_MULTI_NAC=40000` options exercise delayed
first blocks and inter-block gaps without lowering the SD clock.

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

**As built (`sd_cache`, generic `G_AHEAD`, default 2):** a single-sector data
read of the sector after the previous one makes the fill a *stream*: its
open-ended read gets no "last" grant.  When the reader is within `G_AHEAD`
lines of the stream's end, the next line is allocated (never one of the
stream's own lines) and 8 more blocks are granted.  Up to `G_AHEAD + 2`
lines form the stream's window; the oldest drops out as the reader passes
it.  A reader that stops leaves the card paused with its clock stopped; any
other command ends the stream with C_STOP.  The extension happens at the end
of the read that asked for it, before the next command is taken.  Streams
stop at the card's reported end and after 60000 blocks (the next read then
starts a new one).  Lines filled by a stream are chosen for replacement
first once the stream has passed them (random policy), unless they are read
again.  `tb_sd_cache`: 40 sequential sectors over five lines come from one
card read, and after a pause the next sector is already there (13 µs, against
77 µs for a miss).

The design notes from before it was built:

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

**As built (`sd_cache`, generic `G_META`, default 16 sectors = 2 RAMB36):**
metadata reads (`$0B`, arg bit 15) are looked up in both caches; a miss reads
just that sector into a meta slot (an empty one, else LRU by default, or
random: `$32`).  A metadata hit during a stream leaves the stream running; a
metadata miss ends it.  Data reads also find sectors in the meta cache.
Writes update both caches; flushes, init and card selection behave as for
the data cache.  With the default sizes the r6 build uses 18 RAMB36 for
caching (16 data lines, 2 for metadata): the 72 KB agreed.

The design notes from before it was built:

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
- Tags carry the slot. Reset/init (`$00` / `$01`, `$23`, `$24`) invalidates
  that card's lines; `$2B` invalidates both. Selection preserves both cards'
  lines. Future card-detect support must invalidate the removed/replaced
  card's lines and filesystem mount/descriptor state.

### 2.6 Control, statistics, safety

Proposed codes, all taking parameters or returning values via `$D681-$D684`:

| Command | Meaning |
|---|---|
| `$25` | Cache on |
| `$26` | Cache off (behaves as the pass-through) |
| `$27` | Invalidate all |
| `$28` | Latch hit/miss counters into `$D681-$D684` for reading |
| `$29` | Data cache replacement: `$D681` bit 0 = 0 random, 1 LRU (built) |
| `$32` | Meta cache replacement: `$D681` bit 0 = 0 random, 1 LRU (built; `$2A` went to error recovery) |

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

The design proposal (MCU, memory layout, `$70-$7F` commands, rules, testing)
is in [fat32-engine.md](fat32-engine.md).

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
