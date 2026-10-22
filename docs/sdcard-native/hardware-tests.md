# Trying the SD controller, cache and FAT32 engine on a board

MEGA65/mega65-core#890, #953, #766.  The order below goes from what Hyppo
needs to boot, through the controller and the cache, to the engine, so a
failure early on explains later ones.  Each step says what should happen;
note what does not (a photo of the screen is fine).

## What you need

- A bitstream from `890-sdcard-native` (mega65r6), with its timing and
  utilisation reports.  Card change (step 7) needs `f3dos`/engine changes
  from after `821401d48`; everything else works with `821401d48`.
- **Card A:** an ordinary MEGA65 card (FAT32, the usual system files), with
  the test tree written on a PC:
  `python3 src/tools/make_f3_testtree.py /media/$USER/CARD/F3TREE`.
  Ideally a second FAT32 partition too (for `D:`).
- **Card B:** a scratch card for `sdtest`, which **destroys** its contents.
- The programs, all loaded with `m65 -r` (so no card holds them):
  `src/utilities/sd_read_bench.prg`, `src/tests/sdtest.prg`,
  `src/tests/f3dos.prg`, `src/tests/f3test.prg`
  (`make src/utilities/sd_read_bench.prg src/tests/f3dos.prg
  src/tests/f3test.prg`; `sdtest`: `cl65 -t c64 -O -Or -Oi -Os -o
  sdtest.prg src/tests/sdtest.c`).

## 1. Booting

1. Card A in the internal slot, nothing external: Hyppo boots, loads the
   ROM, BASIC starts.  Then in the external slot instead, and then with a
   card in each (the external one wins).
2. Mount a D81 (the usual way, Hyppo's own FAT32 code), `DIR` it and load
   something from it.  The F011 reads go to the card the image is on
   (`$D68A` bits 4/5 show which: bit 4 drive 0, 1 = external).
3. Freeze and unfreeze once.

## 2. Controller (`sd_read_bench`, see [benchmark.md](benchmark.md))

1. `0` then `B`, `1` then `B`: both cards read, native 4-bit, high speed.
2. `P`: both cards initialised together, each with its own result.
3. `A`: the four card information pages.
4. `X` on a healthy card: recovers without a reset (the CMD12/CMD13 fix,
   [rom-load-debug.md](rom-load-debug.md), still waits for this).
5. Card detect: in the monitor, `S D36CE 10` then `M D36CF`: bit 0 slot 0
   present, bit 2 slot 1 present.  Pull the external card: bit 2 clears and
   bit 5 (changed) sets; `S D36CE 50` clears bit 5.

## 3. Cache

1. `B` with the cache on (`$25`, the default) and off (`$26`): on should be
   much faster on repeated and sequential reads.
2. `$28` latches the hit/miss counters into `$D681-$D684`.

## 4. Raw writes (`sdtest`, card B)

Card B in one slot, run `sdtest`, type the confirmation.  Every slab should
pass, with the cache on and then off.  Then the other slot.

## 5. Engine, reading (card A)

1. `f3dos`: `DRIVES` lists the partitions.  **Check that the card in the
   external slot is labelled `ext`** (the engine assumes slot 1 is
   external; only a board can confirm it).
2. `DIR`, `CD`, `TYPE readme.txt` (or any text file), `DIR *.d81`:
   names, upper and lower case and wildcards look right.  Anything garbled
   is probably a PETSCII/ASCII mix-up the PC build can't show.
3. `VERIFY c:/f3tree/manifest.txt`: every file `ok`, `0 bad`.  This checks
   the engine against files a PC wrote, UTF-8 names included.
4. `BENCH c:/f3tree/big/big819200.bin`: three speeds; note them.
5. `f3test` (`RUN`): part 1 should list no failures on any drive.  Stop it
   with RUN/STOP before part 2 if you only want the reading half.

## 6. Engine, writing

1. `f3test` on `C:` (`RUN`), then on `D:` (`RUN:REM D`):
   `f3test: N passed, 0 failed`.  It only writes inside `/F3TEST.TMP`, and
   removes it.
2. In `f3dos`: `MKFILE c:/t1.bin 300000 7`, `CHECK c:/t1.bin 7`,
   `COPY c:/t1.bin d:`, `MD c:/newdir`, `WRITE c:/newdir/hello.txt hi`,
   `REN c:/t1.bin "a long name.bin"`.
3. On a PC: `fsck.fat -n` on each partition (no errors), and
   `crc32 "a long name.bin"` matches `CRC c:/"a long name.bin"` in f3dos.
   Then delete the files, in f3dos or on the PC.

If writes fail with `error 15: read-only`, the engine's policy is
read-only after a cold start, which it should not be: tell me.  An error
254 (`timeout`) means the engine never finished: note the command.

## 7. Card change (the build after `821401d48`)

1. In `f3dos`, `CRC c:/f3tree/big/big2097275.bin` (or `MKFILE` a large
   file) and pull the card part way.  It should stop with an error (stale
   descriptor 16, or I/O 7) within a second or so, not hang.
2. `DIR c:` with the card out: `error 6: no such drive` (or the internal
   card's drive, if that one became `C:`).
3. Put it back, `RESCAN`: the drives are back, `VERIFY` passes again.
4. Swap the two cards between the slots and `RESCAN`: drive letters follow
   (external first), `DRIVES` shows the new labels.

## 8. What to send back

- Timing (WNS, the failing paths if any) and LUT use of the build.
- Steps that did not do what they say, with the screen.
- The `sd_read_bench` and `BENCH` speeds, cache on and off.
