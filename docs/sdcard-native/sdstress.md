# sdstress: shaking out the SD controller

MEGA65/mega65-core#890, #953.  `src/tests/sdstress.c` drives the SD
controller through `$D680` in the orders real software uses.  `sdtest`
checks that sectors are written and read back; sdstress looks for what goes
wrong between commands: an open transfer ended by the next command, a write
straight after a read-ahead stream, a stale cache, the F011 path.

```
make src/tests/sdstress.prg
# or: cl65 -t c64 -O -Or -Oi -Os -o sdstress.prg src/tests/sdstress.c
m65 -r src/tests/sdstress.prg
```

It asks for one of three modes.

## 1. Init report (reads only)

For each slot: first the state the boot left (the hypervisor's init,
untouched: the bus it ended up on and its init record), then initialise
normally, at default speed (`$24`), then normally again, showing `$D686`/`$D687`, the bus the card ended up on, and the card's
CID (maker, name, serial, date).  If the native bus was given up and the
card fell back to SPI, it says at which init step, whether the card did not
answer or answered badly, the last response, and the test read's error.
This comes from the controller's init record (`$D6CE`/`$D6CF` bytes 17-23,
see [architecture.md](architecture.md)), which bitstreams before it was
added do not have: they show `$D686`/`$D687` and the CID only.

This is the mode for a card that boots with `SD STUCK IN SPI MODE`: send the
screen.

## 2. F011 compare (reads only, any card)

Mount a D81 on drive 0 the usual way first.  sdstress reads its sectors
through the F011 and compares each with a raw read of the same card sector
(`$D68C-$D68F` + track × 20 + side × 10 + sector - 1): whole tracks of both
sides (as a loader reads), single sectors at random, with raw read-ahead
streams, cache changes and open multi-sector reads in between.  A mismatch
names the image sector the F011 data really is.  RNF or a stuck BUSY is
counted too.

## 3. Stress (DESTRUCTIVE, a scratch card)

Only on a card whose sector 0 is not a valid MBR, after typing `this will
destroy card contents`.  It uses 4096 sectors from a chosen start (default
4096), first writes them all, then runs random operations, each after a
random pause (none, a few microseconds, a few milliseconds):

| Operation | |
|---|---|
| read1, readseq | Single reads (`$02`); a run of them starts the cache's read-ahead stream |
| readmulti | `$07`/`$08`/`$09`, sometimes left open or ended with `$0A` |
| write1, writemulti | `$03`; `$04`/`$05`/`$06`, sometimes left open or ended early with `$0A` |
| freeze | A run of reads (stream open), then at once a long multi-sector write, then read back: Hyppo's freeze and resume |
| write-in-read | A write into the middle of an open multi-sector read |
| cache, clear, reset | `$25`/`$26`/`$27`; `$2A`; now and then a reset in the middle of an open read |
| verify | 16 sectors, cache emptied first |

It asks whether to include the resets in the middle of open reads (default
yes): on hardware such a reset has left a card that needed a power cycle
(re-inserting it), so they can be left out to run the rest for longer.  It
also asks whether to stop at the first error (default no): it then leaves
out its recovery after a controller error (`$2A`, else a reset), so that
the controller and card stay as the error left them, and the report and
the operations before it stay on the screen.  With the same seed the run
is the same, so an error comes back at the same operation.  And whether to
check the card after every operation (default no): the cache is emptied
and one sector read from the card, so that a card hung by an operation
(still busy, DAT0 held low) is found straight after it, with that
operation last in the list.

Every 500 operations it checks the whole region, cache on then off.  Any
key stops it.

Each sector says what it is: as in sdtest, `SDT1`, its sector number, the
stage (write pass) that wrote it, the seed and a checksum, then a stream
keyed by all of them.  A table holds the stage each sector should have.  On
a mismatch, sdstress empties the cache and reads the sector again:

- **STALE CACHE**: the card has the right data, the cache did not.
- **WRONG ON THE CARD**: also wrong from the card.  It says what the
  sector holds: another sector's data (a write went to the wrong place),
  an older stage (a lost write), some bytes wrong, or not test data.
- **CONTROLLER ERROR**: a command failed (`$D680` bit 6, or BUSY for
  seconds), with `$D680`/`$D686`/`$D687`.

Each report lists the last twelve operations, so the sequence that led to
it can be replayed.  The sector is rewritten and the run goes on.  The
first 10 to 20 reports of each kind are printed; the totals are at the end.

## On a PC

`cc -DHOST` builds it against a simulated card and controller.
`python3 src/tools/test_sdstress.py` checks that a clean run finds nothing,
that each simulated fault is found and put in the right class (a write to
the wrong sector, a lost write, a flipped byte, a cache that kept old data,
an F011 read of the wrong sector), and that a card with a valid MBR is
refused.
