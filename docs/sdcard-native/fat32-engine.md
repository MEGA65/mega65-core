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

Instructions are 24 bits.  The program budget is 2K instructions (48 Kbit
of LUT ROM, about 750 LUT6s); the goal is to need about half of that.

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
result against `fat32img`'s own reading of the image (49 checks).  The
phase 1 firmware is about 1070 instructions, under half the 2K budget.

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
| `$76-$7F` | Reserved | | |

- **`$74/$75` are the disk-image path.** For FDs 0 and 1 they use the run
  table: a lookup, not a walk along the cluster chain.  An exact read that
  crosses the end of the file is rejected.  The file position is left
  unchanged.
- **The `$70` request block** is at the start of the SD half: magic `"F3"`,
  version, op, fd, flags, two 32-bit arguments, then a path or name (ASCII,
  0-terminated, at most 255 characters).  The response replaces it: magic,
  version, status, fd, two 32-bit results, then data (a directory entry, a
  partition list, ...).
- **Completion:** busy (`$D680.0`) as for any command.  The status and
  error code are in the response block, and in `$D687` for `$71-$75`.

**As built (phase 1 firmware):** the request block is `"F3"`, version 1,
op (+3), fd (+4), flags (+5), arg0 (+6), arg1 (+10), path or data (+16).  In
the response, byte 3 is the status (0, or an error code below).

| Op | Operation | In | Out |
|---|---|---|---|
| `$01` | `rescan` | | arg0 = drives found |
| `$02` | `getpartitionlist` | | arg0 = n; 16 bytes each from +16: drive, slot, type, log2 sectors per cluster, partition LBA, size, clusters |
| `$03` | `setdrive` | arg0 = drive | |
| `$10` | `opendir` | path | fd |
| `$11` | `readdir` | fd | entry (below), or error 8 at the end |
| `$12` | `chdir` | path | |
| `$13` | `getcwd` | arg0 = drive (0 the current) | the path from +16 (found by walking up `..`) |
| `$20` | `open` | path; flags bit 0 write, bit 1 append, bit 7 use fd | fd |
| `$22` | `close` | fd | |
| `$23` | `seek` | fd, arg0 offset, flags 0 start / 1 position / 2 end | arg0 = new position |
| `$24` | `stat` | path | entry |

An entry (from +16): attributes, 3 bytes 0, size (4), first cluster (4),
time and date (4), the 8.3 name as text (13, 0-terminated), and from +48
the long name (or the 8.3 name), 0-terminated.

Errors: 1 not found, 2 not a directory, 3 is a directory, 4 bad fd, 5 no
free fd, 6 no such drive, 7 I/O, 8 end, 9 denied, 10 bad request, 11 name
too long, 12 exists, 13 not empty, 14 no space, 15 read-only.

`$70` operations:

| Group | Operations |
|---|---|
| Drives | `rescan` (read both cards' MBRs: external first, up to 4 FAT32 partitions per card, as 1: to 8:), `getpartitionlist`, `setdrive`, `volinfo` (later) |
| Directories | `opendir(path)`, `readdir(fd)` (one entry per call, long filename included), `chdir`, `getcwd`, `mkdir`, `rmdir`, `findfirst/findnext` (wildcards: later) |
| Files | `open(path, flags, [fd])`, `openentry(dirfd, entry, flags, [fd])`, `close`, `create`, `delete`, `rename`, `stat`, `setattr`, `seek(fd, offset, whence)`, `truncate(fd, length)` (shorter or longer; longer allocates contiguously when it can), `flush` (placeholder: writes are synchronous) |
| Hypervisor only | `mountimage(fd 0/1, path)`, `systemaccess(on/off)`, `policy(read-only/read-write)`, `settime`, `getfdstate/setfdstate` (freezer: later), `defrag/copycontig` (later) |

## 6. Rules

- **Descriptors:** 0 and 1 are only for disk images (hypervisor only).
  `open` gives the lowest free one of 2-7, or the one requested if it is
  free.  Directories use descriptors too.
- **Open flags:** read-only or read-write, appendable or not.  Overwriting
  existing bytes and growing the file are separate permissions.
- **SYSTEM attribute:** files and directories with it are invisible and
  inaccessible from user mode until the hypervisor issues `systemaccess on`.
  This covers paths, directory listings and entry-based opens alike.
- **Policy:** in read-only mode, every modifying operation fails, raw sector
  writes (`$03-$06`) included.  That check goes in the write-gate logic of
  `sdcardio_native`, so there is no way around it.
- **Archive bit:** set whenever a file is modified.
- **Writes are synchronous:** the data, both FATs and the directory entry
  (size, time, archive) are written before the command completes.
- **Card removal or a new partition scan** marks the affected descriptors
  stale; they then fail until closed.  Drive numbers are not silently
  re-pointed to another volume.
- **Names:** ASCII only, compared case-insensitively.  A long filename with
  characters outside ASCII is listed with `?` in their place and can be
  opened by its 8.3 name.
- **Paths:** `/` separated, optional drive prefix `n:`, with `.` and `..`.
- **Sectors:** 512 bytes per sector only; FAT32 only (no FAT12/16, no exFAT).

## 7. Testing

1. **Simulator:** firmware against images made by `mkfs.fat`/mtools.  These
   include fragmented files, long filenames, deep and large directories,
   full disks, and two partitions.  The results are checked against mtools
   (`mdir`, `mcopy`, `fsck.fat` after writes).
2. **GHDL:** the card model is given a backing image file.  The engine RTL
   runs the same tests, through the real cache and controller.
3. **HYPPO / hardware:** `hyppotest` cases, then real cards.

## 8. Phases

1. **Toolchain:** assembler, simulator, image fixtures (done).  Firmware for
   `rescan`, `getpartitionlist`, `setdrive`, `opendir`, `readdir`, `open`,
   `read`, `seek`, `close`, `stat`, `chdir`, `getcwd`, `$74`.
2. **Engine RTL** running phase 1's firmware.  The sector slot in the sector
   buffer, mailbox sharing, GHDL tests against images.
3. **Writes:** `create`, `write`, `append`, `truncate`, `delete`, `mkdir`,
   `rmdir`, `rename`, `setattr`, `$75`.  Policies and the SYSTEM attribute.
4. **Disk images on FDs 0/1** (run tables), and HYPPO integration.
5. **Later:** freezer state, `findfirst/findnext`, `volinfo`, `defrag`.

## 9. Questions

1. ~~No new BRAM, or the one RAMB36?~~ **Decided (2026-10-21): no new
   BRAM.**  The engine's sector slot and tables use the spare `$000-$9FF`
   of the existing sector buffer.  (That space had been earmarked for
   FD2000/FD4000 sectors from real floppy drives, a much less compelling
   use than hardware FAT32.)
2. **One `$70` with a request block** for everything but the data paths, as
   proposed?  Or a code per operation, with arguments in registers?
3. **Long filenames with non-ASCII characters:** list them with `?` as
   proposed, or hide them?
