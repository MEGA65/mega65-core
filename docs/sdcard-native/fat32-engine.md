# Hardware FAT32 engine: design (for review)

MEGA65/mega65-core#766.  It builds on the native SD controller (#890) and
the sector cache (#953).  The requirements are in
[architecture.md](architecture.md) §3.1 (file system commands) and §3.2 (the
storage budget).  This document proposes how to meet them.  None of it is
implemented yet.

## 1. Summary

- **A small, file-system-specific MCU** inside `sdcardio_native`, as its own
  entity (`fat32_engine.vhdl`).  It has an 8-bit datapath, a few 32-bit
  registers for clusters, sectors and file positions, and dedicated
  instructions for the work FAT32 does all the time: reading a sector
  through the cache, following a FAT chain, comparing names, assembling long
  filenames.  Its program is in **LUT ROM**.
- **Memory: no new BRAM** (decided).  The existing sector buffer is two
  4 KB BRAMs, of which only `$A00-$FFF` is used: `$000-$9FF` (2.5 KB) is
  free in both copies.  The engine's working sector (512 bytes) and all its
  tables (about 1.7 KB, §4) go there.
- **The CPU interface** uses `$D680` command codes `$70-$7F` (free), with
  parameters in `$D681-$D684` and the sector buffer.  The data operations
  keep the whole sector buffer for data.
- **Firmware** is written in the MCU's assembly language.  A Python
  assembler and instruction-set simulator let it be developed and tested
  against real FAT32 images made with `mkfs.fat`/mtools before any RTL runs
  it.  The RTL is then checked against the same images in GHDL.

## 2. Where it sits

```
 $D680 commands ─▶ sdcardio_native ─┬─ sector reads/writes (as today) ─────────┐
                                    │                                          ▼
                                    └─ $70-$7F ─▶ fat32_engine ─ requests ─▶ sd_cache ─▶ sdcard_native
                                                    │    ▲
                                    sector buffer ◀─┘    └─ its sector slot ($800-$9FF) and state
```

- **One client at a time.** The engine runs only while the CPU waits for a
  `$70-$7F` command, so it borrows the same mailbox (`nat_cmd_*`) that the
  sector commands use.  `sdcardio_native` multiplexes the mailbox:
  `sd_state = FsBusy` hands it to the engine.  There is no arbitration
  inside the cache.
- **The engine's own sector**, for FAT and directory sectors, is read into
  `$800-$9FF` of the sector buffer.  The CPU's request block and data in the
  SD half (`$E00-$FFF`) are therefore never clobbered.  The write path is
  the existing `f011_buffer_write_*` port, with a third prefix (`"100"`) next
  to the SD and F011 ones.  The engine reads through the device read port,
  which it owns while it runs.
- **FAT and directory reads** go through the cache as metadata reads (bit 15
  of the read's arg), so the meta cache keeps them.  File data uses normal
  reads.
- **Bytes in the CPU-visible SD half** are reached through the same ports:
  request fields, path names, and the data of read/write calls.

## 3. The MCU

### 3.1 Datapath

| Resource | Use |
|---|---|
| `R0-R15` (8 bits) | Byte registers (counters, characters, flags) |
| `L0-L7` (32 bits) | Clusters, LBAs, file positions and sizes |
| `X`, `Y` (12 bits) | Byte pointers into the sector buffer address space (`$000-$FFF`) |
| `S` (8-deep) | Return stack (in registers, not memory) |
| Flags | `Z`, `C`, plus `E` (an error from the last sector operation) |

The state tables (§4) are in the same 12-bit address space, so one pair of
pointers reaches everything.

### 3.2 Instructions (sketch)

Instructions are 24 bits.  The program budget was 2K instructions; with
the write side the firmware is about 2465, so jump addresses became 12
bits and the ROM is 4K deep (about 59 Kbit of LUT ROM as used).  A BRAM is
the fallback if the LUTs are too dear.

| Group | Instructions |
|---|---|
| Control | `JMP`, `JZ/JNZ/JC/JNC/JE`, `CALL`, `RET`, `FAIL code` (end the command with an error) |
| Bytes | `LDI`, `LD/ST (X+k)`, `LD/ST (Y+k)`, `MOV`, `ADD`, `SUB`, `AND`, `OR`, `XOR`, `CMP`, `INC`, `DEC`, `SHL`, `SHR` |
| 32-bit | `LLD/LST` (4 bytes at X, little-endian), `LADD`, `LSUB`, `LCMP`, `LSHL n`, `LSHR n`, `LMOV`, `LLDI`, `LADDB` (add a byte register) |
| Pointers | `XLD/YLD`, `XADD/YADD`, `XLD Lk` (low 12 bits of a long) |
| Sector I/O | `SREAD Lk` (meta read of LBA Lk into the engine slot), `DREAD Lk` / `DWRITE Lk` (data reads/writes to or from the CPU's SD half), `SWRITE Lk` (write the engine slot back) |
| FAT | `FATNX Lk` (Lk = next cluster: works out the FAT sector and offset, `SREAD`s it if it is not the last FAT sector read, masks 28 bits, sets `Z` at end of chain); `FATSET Lk, Lm` (FAT entry Lk = Lm, in both FATs) |
| Names | `UPC` (ASCII upper case); `NCMP` (compare the 11-byte 8.3 name at X with the one at Y); `LFNPUT` (copy a long-filename entry's 13 UCS-2 characters, as ASCII, into the name buffer at the position its sequence number gives); `LFNSUM` (the 8.3 checksum of the entry at X) |
| Copy | `COPY n` (n bytes from X to Y), `FILL n` |

The FAT, name and copy instructions are microsequenced in hardware.  They
are what keep the program small: following a cluster chain is one
instruction, not a few dozen.  Cluster-to-LBA conversion is a shift and an
add (`LSHL` by log2 of the sectors per cluster, which is stored at mount).

### 3.3 Toolchain

- `src/tools/fat32asm.py`: assembler, output a VHDL ROM package.
- `src/tools/fat32sim.py`: instruction-set simulator, running the firmware
  against a disk image file and a model of the `$D680` interface.  Most
  firmware development and testing happens here.
- `src/fat32/*.fs`: the firmware sources.

**As built (phase 1):** the assembler is part of `fat32sim.py` for now (the
VHDL ROM output comes with the engine RTL), and its docstring is the
instruction reference.  `src/tools/test_fat32_engine.py` runs
`src/fat32/engine.fs` against the `fat32img.py` fixture and checks every
result against `fat32img`'s own reading of the image (60 read checks, 98
write checks).

## 4. Memory layout

Each address below is in the 12-bit sector buffer space; the engine's tables
take whatever area is decided on.

| Area | Bytes | Contents |
|---|---:|---|
| Engine sector slot | 512 | FAT and directory sectors (`$800-$9FF`) |
| Drives (8 × 32) | 256 | Card/slot, partition LBA, sectors per cluster (log2), FAT LBA and size, data LBA, root cluster, free-cluster hint, state |
| Descriptors (8 × 48) | 384 | First, current and index cluster; position; size; directory entry (LBA + index); flags (dir, read-only, read-write, append, system, dirty); drive |
| Current directories (8 × 4) | 32 | Cluster per drive |
| Disk image runs (2 × 8 × 8) | 128 | Up to 8 (file sector, LBA, length) runs for FDs 0 and 1 |
| Name buffer | 256 | One long filename (ASCII), path component |
| Scratch | 128 | Path parsing, allocation |
| **Total** | **~1.7 KB + 512** | |

That leaves about 300 bytes spare in `$000-$9FF`, and **the engine needs no
new BRAM**.  Any later features have to fit in that, or make room.

The CPU can address `$000-$9FF` in hypervisor mode (direct 12-bit
addresses), but not in user mode.  The engine's state is therefore visible
to the hypervisor, which also makes saving it for the freezer easy.  The
hypervisor must not write there while descriptors are open.

## 5. CPU interface

| Command | Operation | Parameters | Data |
|---|---|---|---|
| `$70` | File system request (most operations) | sector buffer request block | sector buffer response block |
| `$71` | `read(fd, n)` | `$D681-$D682` = n (≤ 512), `$D684` = fd | bytes out to the SD half; count back in `$D681-$D682` |
| `$72` | `write(fd, n)` | as `$71` | bytes in from the SD half |
| `$73` | `append(fd, n)` | as `$71` | bytes in from the SD half |
| `$74` | Read exactly 512 bytes at file sector k | `$D681-$D683` = k, `$D684` = fd | out to the SD half |
| `$75` | Write exactly 512 bytes at file sector k | as `$74` | in from the SD half |
| `$76/$77` | Read the next 512 bytes of fd 0/1 | | as `$71` |
| `$78/$79` | Write the next 512 bytes of fd 0/1 | | as `$72` |
| `$7A-$7F` | Reserved | | |

- **`$74/$75` are a software path to disk images** (or any file): sector
  k of the file, through its cluster chain from the cached position.  A
  sector that crosses the end of the file is rejected, and the file
  position is left unchanged.  The F011 does not use them: its emulation
  reads and writes the card directly at `$D68C`/`$D690` + the track/sector
  offset, so a mounted image must be contiguous (phase 4).
- **The `$70` request block** is at the start of the SD half: magic `"F3"`,
  version, op, fd, flags, two 32-bit arguments, then a path or name (ASCII,
  0-terminated, at most 255 characters).  The response replaces it: magic,
  version, status, fd, two 32-bit results, then data (a directory entry, a
  partition list, ...).
- **Completion:** busy (`$D680.0`) as for any command.  The status and
  error code are in the response block, and in `$D687` for `$71-$75`.

**As built (phases 1 and 3):** the request block is `"F3"`, version 1,
op (+3), fd (+4), flags (+5), arg0 (+6), arg1 (+10), path or data (+16).  In
the response, byte 3 is the status (0, or an error code below).

| Op | Operation | In | Out |
|---|---|---|---|
| `$01` | `rescan` | | arg0 = drives found |
| `$02` | `getpartitionlist` | | arg0 = n; 16 bytes each from +16: drive, slot, type, log2 sectors per cluster, partition LBA, size, clusters |
| `$03` | `setdrive` | arg0 = drive | |
| `$04` | `policy` (hypervisor) | arg0 bit 0: programs may not modify the file system | |
| `$05` | `systemaccess` (hypervisor) | arg0 bit 0: programs see SYSTEM entries | |
| `$06` | `settime` (hypervisor) | arg0 = FAT time \| date << 16 (0: 2026-01-01) | |
| `$07` | `thaw` (hypervisor; below) | | arg0 = descriptors made stale (bits 0-1 H0/H1, 2-9 the programs' 0-7), arg1 = drives found |
| `$08` | `mountimage` (hypervisor) | fd (open; one run of clusters, else error 18) | arg0 = start sector (for `$D68C`/`$D690`), arg1 = size in sectors, flags (+5) = the card (1 external) |
| `$10` | `opendir` | path | fd |
| `$11` | `readdir` | fd | entry (below), or error 8 at the end |
| `$12` | `chdir` | path | |
| `$13` | `getcwd` | arg0 = drive (0 the current) | the path from +16 (found by walking up `..`); arg0 = the drive |
| `$14` | `mkdir` | path | |
| `$15` | `rmdir` | path (empty, nobody's current directory, not open) | |
| `$20` | `open` | path; flags bit 0 write, bit 1 append, bit 7 use fd | fd |
| `$21` | `create` | path; arg0 attributes (read-only, hidden, system; archive is set); flags bit 7 use fd | fd, open for writing |
| `$22` | `close` | fd (writes the entry if `$75` left it out of date; closing a closed one is not an error) | |
| `$23` | `seek` | fd, arg0 offset, flags 0 start / 1 position / 2 end | arg0 = new position |
| `$24` | `stat` | path | entry (long name included) |
| `$25` | `delete` | path (a file, not open, not read-only) | |
| `$26` | `rename` | the old path, then the new one after its terminator (one drive; directories move too, `..` follows) | |
| `$27` | `setattr` | path, arg0 (read-only, hidden, system, archive) | |
| `$28` | `truncate` | fd, arg0 length (shorter frees; longer allocates from the file's end on, so contiguously where it can, and fills with zeros) | |
| `$29` | `flush` | fd | |

`$72` write and `$73` append take `$D681-$D682` = n (at most 512) and `$D684`
= fd, the bytes at `$E00`; `$75` writes exactly 512 bytes at file sector
`$D681-$D683`, inside the file (disk images: the entry is updated at flush
or close).  Writes are synchronous: data, both FATs, the directory entry
(size, first cluster, archive bit, time stamp) and FSInfo (free count,
hint) are written before the command completes.  If a write or truncate
runs out of space part way, the entry still gets what was allocated, so no
cluster leaks.

**Quick commands `$76-$79`** take no parameters: the caller's fd 0 or 1
(H0/H1 in hypervisor mode, the program's own otherwise), 512 bytes at its
position, which advances; the count comes back in `$D681-$D682` as for
`$71/$72`.  A whole sector inside the file at a 512-byte-aligned position
goes straight between the card and `$E00` (a write then updates the entry
at flush or close, as `$75` does); anything else is `$71/$72` with n = 512,
so a write at the end extends the file.

**One writer per file:** opening a file for writing (or appending) fails
with 17 (busy) while another descriptor, in either name space, has it open
for writing.  Otherwise one could truncate clusters the other still uses.
Readers are not limited.

**Thaw (`$07`):** the freezer saves `$000-$7FF` and puts it back, then
the hypervisor issues `thaw`.  The cards are scanned again, and each frozen
drive is found again by its volume (serial number, partition start and
size), so a card that moved to the other slot, or partitions found in a
different order, are followed.  Then every open descriptor is checked
against the card.  A file's directory entry must still be in use, at the
same place, with the same first cluster: its size is taken from the entry
and its place in the chain restarts from the first cluster.  A directory's
first sector must still hold its own `.` entry.  A descriptor that fails is
marked stale (error 16 until closed; closing it writes nothing).  Current
directories that fail fall back to the root.  This also works after a power
cycle: nothing in a descriptor depends on the session.  The full names of
open files are not stored, and none are needed.  The thaw returns which
descriptors went stale.  A hypervisor that opened H0/H1 before the restore
loses them: they come back as the frozen program's.

An entry (from +16): attributes, 3 bytes 0, size (4), first cluster (4),
time and date (4), the 8.3 name as text (13, 0-terminated), and from +48
the long name (UTF-8; or the 8.3 name), 0-terminated.

New names: an 8.3 alias (the name itself if it fits; else up to 6
characters and `~1`..`~9`, then 5 and `~10`..`~99`), plus long-name entries
(UCS-2 from UTF-8) unless the name is exactly its alias.  Names may not be
`.`/`..`, contain `" * / : < > ? \ |` or control characters, or end in a
space or `.`.

Errors: 1 not found, 2 not a directory, 3 is a directory, 4 bad fd, 5 no
free fd, 6 no such drive, 7 I/O, 8 end, 9 denied, 10 bad request, 11 name
too long, 12 exists, 13 not empty, 14 no space, 15 read-only, 16 stale
descriptor, 17 busy (open, or a current directory), 18 fragmented (an
image must be one run of clusters).

**Descriptors:** two name spaces.  In hypervisor mode `fd` 0 and 1 are H0
and H1 (disk images); programs have their own 0-7.  The hypervisor reaches
the programs' descriptors with bit 7 of the number (`$80`-`$87`), for the
freezer and for cleaning up.

**Memory** (`$000-$7FF`, what the freezer saves): drive records (8 x 48:
geometry, volume serial, FSInfo sector, free count, hint) at `$000`,
descriptors (10 x 32) at `$180`, current directories at `$2C0`, globals,
the entry copy, the name buffers (path component and long name, UTF-8),
the UCS-2 buffer at `$580`, the write side's working state at `$788`, and
"F3" at `$7FE`.  Without "F3" (power on) the engine clears the area first.

**Firmware size:** about 2820 instructions, so the ROM is 4K x 24 (12-bit
jump addresses) in LUTs.

`$70` operations:

| Group | Operations |
|---|---|
| Drives | `rescan` (read both cards' MBRs: external first, up to 4 FAT32 partitions per card, as 1: to 8:), `getpartitionlist`, `setdrive`, `volinfo` (later) |
| Directories | `opendir(path)`, `readdir(fd)` (one entry per call, long filename included), `chdir`, `getcwd`, `mkdir`, `rmdir`, `findfirst/findnext` (wildcards: later) |
| Files | `open(path, flags, [fd])`, `openentry(dirfd, entry, flags, [fd])`, `close`, `create`, `delete`, `rename`, `stat`, `setattr`, `seek(fd, offset, whence)`, `truncate(fd, length)` (shorter or longer; longer allocates contiguously when it can), `flush` (placeholder: writes are synchronous) |
| Hypervisor only | `mountimage(fd)`, `systemaccess(on/off)`, `policy(read-only/read-write)`, `settime`, `thaw`, `defrag/copycontig` (later) |

## 6. Rules

- **Descriptors:** the hypervisor's H0/H1 (disk images) and the
  programs' 0-7 are separate name spaces.  `open` gives the lowest free
  one of the caller's, or the one requested if it is free.  Directories use
  descriptors too.
- **Open flags:** read-only or read-write, appendable or not.  Overwriting
  existing bytes and growing the file are separate permissions.
- **SYSTEM attribute:** files and directories with it are invisible and
  inaccessible from user mode until the hypervisor issues `systemaccess on`.
  This covers paths, directory listings and entry-based opens alike.
- **Policy:** in read-only mode, every modifying operation fails for
  programs, raw sector writes (`$03-$06`) included.  The raw-write check is
  in `sdcardio_native`'s command decode: a refused write is an error with
  `$D687` = `$0F` (15, read-only).  Its register follows every write of the
  policy byte (`$2E3`) into the sector buffer, by the engine, a cold start or
  the freezer's restore, so the firmware and the hardware cannot disagree.
  The hypervisor is never refused.
- **Archive bit:** set whenever a file is modified.
- **Writes are synchronous:** the data, both FATs and the directory entry
  (size, time, archive) are written before the command completes.
- **Stale descriptors:** a thaw marks a descriptor stale when its file or
  directory is no longer where it was; it then fails until closed.  Drive
  numbers follow the volume, never silently another one.  (Card removal
  does not yet mark descriptors stale.)
- **One writer per file** (busy otherwise); readers are not limited.
- **Names:** UTF-8, at most 255 bytes per component (longer long names are
  listed cut short with an ellipsis, and open by that form).  Matching
  ignores case for ASCII letters only.
- **Paths:** `/` separated, optional drive prefix `n:`, with `.` and `..`.
- **Sectors:** 512 bytes per sector only; FAT32 only (no FAT12/16, no exFAT).

## 7. Testing

1. **Simulator:** firmware against images made by `mkfs.fat`/mtools.  These
   include fragmented files, long filenames, deep and large directories,
   full disks, and two partitions.  The results are checked against mtools
   (`mdir`, `mcopy`, `fsck.fat` after writes).
2. **GHDL:** the card model is given a backing image file.  The engine RTL
   runs the same tests, through the real cache and controller.
3. **Programs:** [f3dos and f3test](f3dos.md), a shell and a self-checking
   test in C.  On a PC they run against the simulator
   (`src/tools/test_f3dos.py`).  On the MEGA65 they check the engine
   against raw sector reads and the FAT walked independently, and against
   a tree of files written by a PC.
4. **HYPPO / hardware:** `hyppotest` cases, then real cards.

## 8. Phases

1. **Toolchain:** assembler, simulator, image fixtures (done).  Firmware for
   `rescan`, `getpartitionlist`, `setdrive`, `opendir`, `readdir`, `open`,
   `read`, `seek`, `close`, `stat`, `chdir`, `getcwd`, `$74`.
2. **Engine RTL** running phase 1's firmware.  The sector slot in the sector
   buffer, mailbox sharing, GHDL tests against images.

   **As built:** `src/vhdl/fat32_engine.vhdl`, with the firmware as a LUT
   ROM package (`fat32_rom.vhdl`, generated: `python3 src/tools/fat32sim.py
   src/fat32/engine.fs src/vhdl/fat32_rom.vhdl`).  In `sdcardio_native`
   (generic `sd_fat32`, default on) commands `$70-$7F` start it in the
   `Fat32Engine` state, where it has the sector buffer's device read port
   and write port; the CPU's buffer writes wait.  Its sector reads are
   ordinary controller reads: to its slot (`$800`) as metadata (through the
   metadata cache), to `$E00` as data.  An open multi-sector transfer is
   ended first.  Engine writes are refused until phase 3 brings the write
   policy.  Engine slot 1 is controller slot 1 (`$C1`); check on hardware
   that this is the external card.
   - `test_fat32_engine.py --rtl` replays the simulator's transcript through
     the RTL in GHDL, comparing the whole buffer after every command (also
     the 1815-command full run).
   - `tb_sdcardio_native` writes an MBR and boot sector to the card model
     and runs rescan and the partition list through the real cache and
     controller, plus a bad request (`$D687` = 10).
3. **Writes:** `create`, `write`, `append`, `truncate`, `delete`, `mkdir`,
   `rmdir`, `rename`, `setattr`, `$75`.  Policies and the SYSTEM attribute.  **Done** (see the
   table above): `test_fat32_engine.py` runs 61 write checks on a copy of
   the image, `fsck.fat` and the FSInfo free count checked after each part
   (FSInfo is not fixed first), and the RTL matches the simulator on all
   480 commands and 3179 sector writes.  `tb_sdcardio_native` creates,
   writes and reads back a file through the real controller.
4. **Disk images and the freezer.**  Done so far:
   - the quick commands `$76-$79`;
   - `thaw`;
   - one writer per file;
   - the hardware read-only gate on programs' raw writes;
   - each F011 image bound to its card: the card selected when the
     hypervisor writes `$D68C-$D68F` (drive 0) or `$D690-$D693` (drive 1),
     readable as `$D68A` bits 4 and 5.  Before, the F011 used whichever
     card was selected when it asked, which breaks once the engine or Hyppo
     moves between the cards.

   `test_fat32_engine.py`: 98 write checks, among them the quick commands, mountimage,
   thaw within a session (a file deleted meanwhile goes stale, the rest
   carry on), and thaw with the card moved to the internal slot and another
   card in the external one.  `tb_sdcardio_native`: a quick read, the
   policy gate (refused for a program, `$D687` = `$0F`; the hypervisor's
   write and, with the policy off, a program's go ahead) and the image
   slots.

   - `mountimage` (`$08`): checks that an open file is one run of
     clusters and gives its start sector, size and card.  Open for writing,
     its entry gets the archive bit and the time now, because the F011's
     writes go around the engine.  To mount, the hypervisor opens the image
     on H0/H1 and issues `mountimage`.  It then selects that card (`$C0`/`$C1`),
     writes the start to `$D68C` (or `$D690`), and sets `$D68B` as today.
     The size check (819200 bytes for a D81, and so on) is left to the
     hypervisor, which knows the image types.  Keeping the descriptor open
     while mounted makes delete, rename and a second writer fail with busy.

   To do: HYPPO integration (the hypervisor's own FAT32 code replaced by
   the engine), then hardware tests.
5. **Later:** `findfirst/findnext`, `volinfo`, `defrag`, `copy`.

## 9. Questions

1. ~~No new BRAM, or the one RAMB36?~~ **Decided (2026-10-21): no new
   BRAM.**  The engine's sector slot and tables use the spare `$000-$9FF`
   of the existing sector buffer.  (That space had been earmarked for
   FD2000/FD4000 sectors from real floppy drives, a much less compelling
   use than hardware FAT32.)
2. ~~One `$70` with a request block?~~ **Decided (2026-10-21):** `$70` for
   most operations, plus quick commands for the disk-image descriptors:
   `$76`/`$77` read the next sector of FD 0/1, `$78`/`$79` write it (no
   request block; data at `$E00`).  Phase 4, with the run tables; they can
   walk the chain before that.
3. ~~Long filenames with non-ASCII characters?~~ **Decided (2026-10-21):**
   rendered as UTF-8, so odd names survive.  The name buffer is 256 bytes,
   so names are capped at 255 UTF-8 bytes (longer ones are reached by their
   8.3 name); case-blind matching stays ASCII-only.  `LFNPUT` changes from
   `?` replacement to UTF-8 encoding (phase 3).
