# f3dos and f3test: trying the FAT32 engine on real cards

MEGA65/mega65-core#766.  Two C programs drive the hardware FAT32 engine
([fat32-engine.md](fat32-engine.md)) directly through `$D680`:

- **f3dos**: a small DOS-like shell for poking at cards by hand.
- **f3test**: a self-checking test that asks nothing and reports
  pass/fail counts.

Both run as ordinary programs (user mode), so they get the programs'
descriptors 0-7, never see SYSTEM entries, and are bound by the read-only
policy.  Neither needs anything from HYPPO beyond a bitstream with the
engine in it.

## Building

```
make src/tests/f3dos.prg src/tests/f3test.prg
# or by hand:
cl65 -t c64 -O -Os -o f3dos.prg src/tests/f3dos.c src/tests/f3lib.c
cl65 -t c64 -O -Os -o f3test.prg src/tests/f3test.c src/tests/f3lib.c
```

Load them with `m65 -r f3dos.prg` (or from a D81).  They run in C64 mode,
in 40 columns, switching to upper and lower case.

## f3dos

Drives `C:` to `J:` are the engine's drives 1 to 8: the FAT32 partitions,
external card first.  Paths use `/` (or `\`), may start with a drive
letter, and may be quoted to hold spaces: `cd "Arcade Classics"`.

| Command | |
|---|---|
| `DRIVES`, `RESCAN` | List the partitions; initialise both cards (`$2B`) and scan them again (needed after putting a card in; open files on a card that was pulled are stale) |
| `C:` .. `J:` | Change the current drive |
| `CD [dir]` | Change directory; on its own, show where you are |
| `DIR [spec]` | List a directory (`*` and `?` in the last part) |
| `MD dir`, `RD dir` | Make and remove directories |
| `TYPE f`, `DUMP f [off [len]]` | Show a text file; hex dump |
| `STAT f`, `ATTRIB [+r -r +h -h +s -s +a -a] f` | Show an entry; show or change its attributes |
| `COPY spec dst`, `MOVE spec dst` | Copy, or move (a rename on one drive, else copy and delete).  `dst` may be a directory or a drive (`D:`) |
| `REN old new`, `DEL spec` | Rename (`new` stays in `old`'s directory unless it has a path); delete |
| `WRITE f text`, `APPEND f text` | Write or append a line |
| `MKFILE f size [seed]`, `CHECK f [seed]` | Write test data; check it (and time both) |
| `CRC f` | CRC-32 and size, to compare with a PC (`crc32 file`) |
| `TRUNC f len` | Truncate, or extend with zeros |
| `BENCH f` | Read a file three ways: `$71` reads, `$74` file sectors, `$76` quick reads |
| `VERIFY [manifest]` | Check every file a manifest lists (below) |
| `CACHE on\|off` | The sector cache |
| `EXEC f` | Run the commands in a text file |
| `ECHO text`, `HELP`, `EXIT` | |

Wildcards match the name `DIR` shows, never the 8.3 alias (so `*7.TXT`
does not catch `FILENU~7.TXT`).  Listings pause each screen; RUN/STOP (or
`q` at the pause) stops a listing, copy or check.  Names with characters
other than ASCII are listed with `?` for each such character; use their 8.3
names to reach them.

## A known tree: VERIFY

`src/tools/make_f3_testtree.py` writes a deterministic tree of test files:
sizes around sector and cluster boundaries, long, mixed-case and UTF-8
names, deep directories, a directory with many entries, and some larger
files.  It also writes `manifest.txt`, with `crc32 size path` for each file.
On a PC, with the card mounted:

```
python3 src/tools/make_f3_testtree.py /media/$USER/CARD/F3TREE
```

then in f3dos on the MEGA65:

```
verify c:/f3tree/manifest.txt
```

Every file is opened by its path (UTF-8 included) and read to the end,
and its size and CRC are compared with the manifest.  Since a PC wrote the
card, this checks the engine's reading against an independent writer.
In the other direction, `MKFILE` or `COPY` on the MEGA65, then `crc32` or
`fsck.fat -n` on the PC, checks the engine's writing.

## f3test

```
f3test.prg            (part 2 on C:)
RUN:REM D             (part 2 on D:)
```

**Part 1** only reads.  For every drive it parses the boot sector itself,
with raw `$02` sector reads, and walks each file's cluster chain through
the raw FAT.  It then reads every file it finds through the engine, `$71`
512 bytes at a time plus every 8th sector through `$74`, and compares each
sector with the raw one.  So it checks the engine against something that
never uses the engine.  It also checks that `stat` agrees with `readdir`,
that chains have the right length and end, that both FATs agree, and that
`$74` refuses a sector across the end of a file.  A budget (4 MB and 3000
entries per drive, 512 sectors per file) keeps a full card from taking
hours.

**Part 2** writes, only inside `/F3TEST.TMP` on one drive, and removes it
afterwards (a left-over one from a stopped run is removed first):

- **Sizes:** 0, 1, 511, 512, 513, 1025, a cluster -1, 0 and +1, 2 clusters
  +7, 5 clusters +300, and 300000 bytes.  Each is written in odd pieces (1
  to 512 bytes), then read back four ways: `$71` in odd pieces, seeks from
  the start, position and end, `$74` sectors, and the raw sectors through
  f3test's own chain walk.
- **Changes:** append, overwrite in the middle, growth by writing at the
  end, truncate shorter and longer (the new part reads as zeros).
- **Sector and quick commands:** `$75` inside and past the end, `$76` reads
  on descriptor 0, `$79` writes on descriptor 1.
- **Names:** long, mixed-case and dotted names; lookups ignoring case; twelve
  names sharing an alias stem (distinct aliases); a UTF-8 name round trip;
  bad names and a 260-byte name refused.
- **Directories:**
  - a directory grown past one cluster: every entry listed exactly once,
    then again after deleting half, then the freed slots reused;
  - nested directories, `..`, `getcwd`;
  - renames of files and directories (`..` follows);
  - `rmdir` refused for a full directory or a current one.
- **Attributes:** a read-only file can't be opened for writing or deleted.
- **Errors:** not found, is a directory, not a directory, exists, no such
  drive, busy (delete of an open file, a second writer), bad descriptors,
  the ninth open file.
- **Again after a rescan:** with the sector cache off, then on.

It ends with `f3test: N passed, M failed`.  The first 40 failures are
listed with their section.

## On a PC

`src/tests/f3lib.c` built with `-DHOST` sends each controller command
through a pipe to `src/tools/f3bridge.py`, which runs the engine's firmware
on the instruction-set simulator against image files:

```
cc -DHOST -O2 -o f3dos_host src/tests/f3dos.c src/tests/f3lib.c
python3 src/tools/f3bridge.py --card1 card.img -- ./f3dos_host
```

`src/tools/test_f3dos.py` does all of it: it builds both programs, makes
the standard test image with the tree in it (larger files fragmented), and
runs f3test on both partitions (4 KB and 512-byte clusters).  It then runs
an f3dos session whose output it checks, with `fsck.fat` and the FSInfo
free count checked after each step.  It builds the `.prg`s too when `cl65`
is there.

Running it found three engine bugs, now fixed:

- **Lost first cluster.** The busy check (used by delete, rmdir and open
  for writing) overwrote the first cluster of the file being worked on
  whenever another descriptor was open:
  - a delete then freed the wrong chain;
  - rmdir checked and freed the wrong cluster;
  - a file opened for writing beside another writer got a wrong first
    cluster.

  HYPPO, with a disk image always open, would have hit this on every
  delete.
- **Deleting a read-only file** was allowed.
- **`stat`** gave only the 8.3 name, not the long one.
