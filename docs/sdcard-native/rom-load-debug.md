The 2026-10-18 ROM-load investigation used the populated internal slot
(controller slot 0), with no SD writes. The physical build identified itself
as `043638c`; the subsequent `a96fe3585` build changed only the simulation
card model. Neither contained the fixes described below.

The card's root directory identifies `MEGA65.ROM` as a 131072-byte file
starting at cluster 109665. Its 32 contiguous clusters occupy SD sectors
922520 through 922775. Uncached reads, with errored commands explicitly
retried, produced SHA256:

```text
6f186dc6e32e381f9d7dd930304544559d16c4b7c1fbdb21f3a63926ebc88000
```

The initial `$20000-$3FFFF` RAM capture had SHA256:

```text
72eb0163be43ff9523d7bb9cb35215aa531fb24ff44ac8f6f085687a2aaa97e8
```

Some mismatches are entire cache lines from later in the file:

| RAM address | Expected SD sector | Sector actually present |
|---|---:|---:|
| `$2A000` | 922600 | 922608 (+8) |
| `$2F000` | 922640 | 922672 (+32) |
| `$35000` | 922688 | 922704 (+16) |
| `$36000` | 922696 | 922704 (+8) |

Direct cached reads also returned wrong lines: sector 922552 returned data
from 922576 (+24), and 922568 returned 922576 (+8). Zero/FF-filled blocks
cannot be mapped uniquely and are excluded from these conclusions.

A later capture on physical build `e6a7c` (the cache dispatch guard, but
before the checked close and Hyppo error checks) still contained 69 incorrect
512-byte sectors. Its SHA256 was
`0d92029d74010b21b1338321a978552c4a54d59469aeb5743b2f6c0265f68c53`.
Examples of whole 4 KiB replacements were `$2A000`: 922600 -> 922608,
`$2F000`: 922640 -> 922672, and `$33000`: 922672 -> 922704. Other errors
were partial lines or sectors without an exact match elsewhere in the ROM.
The CPU was executing BRK at `$D420`. The cache dispatch guard alone is
therefore insufficient to fix the physical ROM load.

Disabling cache alone did not make the physical build reliable. A completed
warm boot with cache disabled differed from the file in 35 sectors; direct
uncached commands reported exhausted read CRC retries (`$21`) and data
timeouts (`$20`). These observations do not by themselves distinguish lost
stream framing from electrical errors.

The default high-speed clock was 325 MHz / 8 = 40.625 MHz, below 50 MHz.
The source's 324/40.5 MHz comments are rounded. Slower clocks were diagnostic
probes; accepted settings can automatically fall back to the normal setting
on repeated errors, so a long run cannot be labelled by its initial setting
alone. No diagnostic used an overclock.

Three software/RTL defects were found and tested independently:

- Cache dispatch checked mailbox availability without always checking that
  card cleanup had finished. A default-speed regression with consecutive
  last-sector misses failed before the idle guard was added.
- Native read close continued after CMD12 without checking its success or
  positively checking card state. Cleanup now requires CMD12 plus a CMD13
  Transfer/ready response, with bounded retries. A model that acknowledges
  CMD12 while continuing to stream now produces a terminal error, rather
  than a false successful close.
- Hyppo accepted idle as success without checking the error flag. It now
  detects errors during polling and after ready, taking its reset/retry
  path before copying the buffer. The controller also retains legacy
  stuck-BUSY semantics, with explicit `$2A` recovery for new callers.

The corrected bitstream still needs physical validation. Capture its loaded
ROM with:

```sh
python3 src/tools/monitor_memfetch.py 20000 40000 /tmp/mega65-rom-new.bin \
  --halt --log /tmp/mega65-rom-new-monitor.txt
```

Compare the complete image with a fresh, error-checked read of the card file;
capture it after Hyppo has finished, since a timed pause during boot can
otherwise capture an incomplete load. The RAM capture utility is documented
in [monitor-memfetch.md](monitor-memfetch.md). Raw ROM data and full serial
transcripts remain under `/tmp`, outside the repository.
