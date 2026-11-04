# SD card over Ethernet (#965)

A virtual SD card served by a PC on the LAN.

## What it does

`src/tools/netsd.py` turns a host directory tree into a whole SD card:
- an MBR;
- a FAT32 partition generated from the tree;
- a MEGA65 system partition.

It serves the card's sectors over UDP.  On the MEGA65, `sd_eth` takes the
internal card's place as slot 0 of the native SD controller.  It builds,
sends, receives, checks and decrypts frames itself, so there is no CPU work
per sector, and everything above slot 0 works unchanged:
- the sector cache with its read-ahead;
- the F011 disk images;
- the FAT32 engine;
- Hyppo.

Branch `965-sd-over-ethernet`, on top of `890-sdcard-native`.

**Status:** built and simulated end to end against the real `netsd.py`
server code.  **Not yet on hardware, not yet through Vivado** (timing and
area to be confirmed).

| Part | Files |
|---|---|
| PC server | `src/tools/netsd.py`, `netsd_vfat.py` (the virtual card), `netsd_crypto.py` + `netsd_ascon.c` (Ascon) |
| FPGA | `src/vhdl/sd_eth.vhdl`, `ascon_aead128.vhdl`, `eth_netsd_buf.vhdl`; changes to `ethernet.vhdl`, `sdcard_native.vhdl` (`sdcard_native_dual`), `sdcardio_native.vhdl`, `iomapper.vhdl` |
| Hyppo | `src/hyppo/netsd.asm`; calls from `main.asm` and `syspart.asm` |
| CONFIGURE | `src/utilities/mega65_config.inc` (Network tab, page 2) |
| Tests | `src/tools/test_netsd.py`, `tb_ascon_aead128` + `gen_ascon_vectors.py`, `tb_sd_eth` + `sim_netsd.py`, `src/hyppo/netsd.test` |

## Using it

### PC

```
netsd.py --subnet 192.168.1.0/24 --client 65=~/m65,key=00112233445566778899aabbccddeeff
netsd.py --subnet 192.168.1.0/24 --default ~/m65 -w          # no key: open
```

| Option | Meaning |
|---|---|
| `--client OCTET\|MAC=DIR[,key=HEX]` | A tree for one MEGA65, matched by its host number or MAC.  Repeatable |
| `--default DIR` | A tree for any other MEGA65 |
| `--key HEX` | The key for clients without their own |
| `-w` | Write the MEGA65's changes back to the tree |
| `--delete` | Also apply deletions (needs `-w`) |
| `--size` / `--spc` | The card size in MB, and sectors per cluster |
| `netsd.py dump DIR card.img` | Write the virtual card as an image |

The server runs unprivileged.  It is a plain UDP socket on port 6565.

### MEGA65

In CONFIGURE, Network tab, page 2:
- **"sd over ethernet host"**: 1-127.
- **"key"**: 32 hex digits; leave it empty for no signing.
- **"with a key"**: "signed" or "signed+encrypted".

Then turn on **DIP switch 8** (R6), or hold **right shift** at power-on.

| What happens | Result |
|---|---|
| Hyppo connects | It says so and boots from the network card's partitions |
| No answer (DIP switch 8) | It boots from the SD card as usual |
| No answer (right shift) | It says so and waits for right shift to be released, then boots from the SD card |

## Protocol (UDP/IPv4, port 6565)

```
Ethernet | IPv4 (no options, DF, UDP checksum 0 from the MEGA65) | UDP
| netsd header (16) | payload (16, 32 or 512) | Ascon tag (16, when signed)
```

### Header (16 bytes, little-endian)

| Offset | Field |
|---|---|
| 0-1 | `'M','S'` |
| 2 | bits 7-4 version (1); bit 0 response; bit 1 signed (tag follows); bit 2 encrypted |
| 3 | op |
| 4-7 | Session ID |
| 8-11 | Sequence number (a response echoes its request's) |
| 12-15 | LBA |

### Ops

| Op | Request | Response |
|---|---|---|
| `$01` HELLO | 16 bytes: MAC, host number, capabilities, 8 bytes of entropy.  Broadcast from 0.0.0.0 | 32 bytes: our IPv4 address, the server's, the card size in sectors, flags (bit 0 writable), the most sectors per READ (8), 2 reserved, the server nonce (8), the MAC echoed, 2 reserved.  Sent to the subnet's broadcast address (we have no address yet).  The server's MAC is its Ethernet source |
| `$02` READ | 16 bytes: count (1-8) | `count` frames of 512, LBA = request LBA + i |
| `$03` WRITE | 512 bytes | 16 bytes: status |
| `$7F` NAK | — | 16 bytes: status, the op refused |

Statuses: 0 OK, 1 out of range, 2 read-only, 3 host I/O error, 4 unknown
session, 5 authentication, 6 bad request.

### Rules

- **Addresses.**  The MEGA65's full IPv4 address comes from the HELLO reply
  (subnet prefix + host number), and so does the server's.
- **ARP.**  `sd_eth` answers ARP requests for its own address, so the PC's
  kernel can send to it unicast.  Nothing goes to broadcast after HELLO.
- **One request at a time.**  A request is sent again after 20 ms without
  progress, 10 times, then the command fails.
- **Reads ahead.**  An open-ended read (the cache's line fills, `$07`-`$09`)
  asks for 8 sectors ahead of the data, whatever the grants.  So the PC's
  latency hides behind the stream.
- **Writes** go one block at a time.
- **The server** answers a repeated write without applying it again, and
  drops a write older than one it has already taken (a replay).
- **A new HELLO** (the MEGA65 reset, or `$01`) is a new session.  It
  rebuilds the virtual card from the tree, unless writes are still waiting to
  be written back.

### Crypto: Ascon-AEAD128 (NIST SP 800-232)

- **Key:** 128 bits, pre-shared.
- **Nonce:**

  | Bytes | Field |
  |---|---|
  | 4 | session |
  | 4 | sequence |
  | 4 | LBA |
  | 3 | the server nonce's first 3 bytes (zeros for HELLO and its reply) |
  | 1 | op, bit 7 for a response |

- **AD** = the header.  The payload is encrypted, or with "signed" alone it
  goes into the AD.
- **HELLO and its reply** are signed, never encrypted: the server finds the
  key by the MAC in the HELLO.
- **Replays.**  The session is fresh at each HELLO.  It is TRNG entropy XOR a
  free-running cycle count, plus one per init.  The server nonce makes each
  session's nonces fresh even if a session ID repeats.  Repeats of a request
  are byte-identical.
- **Bad tags.**  A read with a bad tag gives `rd_bad`, and the block is asked
  for again, so nothing unverified is ever marked good.
- **The key at rest** is in the clear in the real card's config sector.

## MEGA65 side

### Hardware

```
ethernet.vhdl --(eth_netsd_buf: 4x1 KB RX ring, 2 KB TX)-- iomapper --
  sdcardio_native ($D6F1) -- sdcard_native_dual: slot 0 = sd_eth while on
```

- **`ethernet.vhdl`** (generic `netsd`, set from iomapper's `sd_native`):
  - an RX tap: every byte, frame start and end, with the CRC verdict;
  - a TX source next to the beacon, below the CPU's own frames;
  - the MAC.

  The SD frames don't touch the CPU's receive buffers.

- **`eth_netsd_buf`** holds the clock-crossing buffers:
  - RX: one RAMB36, written at 50 MHz, committed only on a good CRC, read on
    cpuclock;
  - TX: one RAMB18.

- **`sd_eth`** (cpuclock) does the rest:
  - `sdcard_native`'s host interface;
  - HELLO, READ, WRITE, timeouts and retries;
  - the IPv4 header checksum;
  - ARP replies;
  - frame parsing;
  - `ascon_aead128`, byte-serial, one round per cycle.

- **`sdcard_native_dual`** (generic `G_NET`): while `sd_eth` is on, slot 0's
  status, data stream and write fetch are `sd_eth`'s, and the internal
  socket's core gets no commands.  Slot 1 is untouched.  The F011 image
  binding stays one bit: internal means slot 0.

- **`$D6F1`** (decoded in `sdcardio_native`, passed down):

  | Access | Meaning |
  |---|---|
  | Write, bit 7 clear | Shift 7 bits into a 168-bit register (24 writes).  Its layout: flags (8: bit 0 sign, bit 1 encrypt), key (16 bytes, first byte first), entropy (32).  Ignored while on, so the key in use can't be disturbed |
  | Write, bit 7 set | Bits 6-0 = host number: on.  0: off, and the register (the key with it) is cleared |
  | Read | bit 7 on, bit 6 connected, bit 5 signing, bit 4 encrypting, bits 3-0 the last NAK's status |

  A write held for more than a cycle counts once.

**Size (Yosys `synth_xilinx`, xc7; Vivado's figures still to be had):**

| Block | LUTs | FFs | BRAM |
|---|---|---|---|
| `sd_eth` with Ascon | ~3040 | ~1660 | |
| of which Ascon | ~1200 | ~340 | |
| `eth_netsd_buf` | 31 | 47 | RAMB36 + RAMB18 |

Ascon's round with its state register is ~650 of its 1200.  The rest is byte
and key multiplexing.

Further cuts, if wanted:
- a template ROM and a field multiplexer, in place of the per-byte header and
  ARP multiplexers;
- sharing the parse and build byte paths;
- Ascon's 64-bit lane-serial round (about 1/5 of the round's LUTs, at 5
  cycles a round, which still keeps up with the wire).

### Hyppo (`src/hyppo/netsd.asm`)

**`syspart_configsector_apply`** keeps the config text:
- the host number (`$031-$033`, decimal);
- the key (`$040-$05F`, hex);
- encrypt (`$030` bit 0).

**After the boot-time partition scan, `netsd_boot`:**

1. Runs only with DIP switch 8 or right shift, and a host number set.
2. Shifts flags, key and TRNG entropy into `$D6F1`, wipes its own copy, and
   switches on.
3. Checks that it's there (bit 7 reads back).
4. `$C0`, `$00`, `$01`, then waits up to 5 boot-card windows.
5. **Connected:** `syspart_present` = 0, then `dos_clearall` and
   `dos_read_partitiontable` again.  The network card's system partition is
   opened without applying its config sector (`netsd_skip_config`).
6. **Otherwise:** off, back to the bus Hyppo booted from (the internal card
   initialised again), and the right-shift release wait.

It adds about 600 bytes.  Hyppo's code now ends at about `$BA0E`, against
`$BB00`.

### CONFIGURE

Network tab, page 2: two string fields and an on/off option, all existing
input types, so no new code.  The screen is 40 columns, and a 32-character
field starts at column 7, hence the short "key:" label and the line above it.

## Tests

| Command | What it checks |
|---|---|
| `python3 src/tools/test_netsd.py` (14 tests; also with `NETSD_PURE_PYTHON=1`) | The card is fsck-clean and holds the host files (checked with `fat32img`'s reader).  Changes made with `fat32img`'s FAT32 writer come back to the tree (new directories and files, in-place writes, a rename).  Deletes only with `--delete`.  Hostile entries: a symlink trap, a slash in a name, `../` in a long name, a FAT loop.  The server: plain, signed and encrypted sessions, a wrong key, tampering, a replayed write.  The C and Python Ascon against KAT 1 |
| `gen_ascon_vectors.py`, then `tb_ascon_aead128` | 138 messages, 15254 bytes, encrypted and decrypted byte by byte, every byte and tag checked.  The vectors come from the C version, which is checked against pyascon (current master, SP 800-232) |
| `sim_netsd.py WORKDIR --flags 0\|1\|3 [--drop N] [--corrupt N]` with `tb_sd_eth` | `sd_eth` + `eth_netsd_buf` against `netsd.py`'s own `Server`, over named pipes.  Init; reads of 1, 3 and 8 sectors; an open-ended read of 12 granted block by block; writes read back; an open-ended write; a refused write; a range error; ARP; a second connect.  Every block checked against what was served, and every frame's IPv4 framing and checksum.  Lost and corrupted frames recover |
| `sim_netsd.py WORKDIR --tb tb_sd_eth_cache --flags 3` | The stack as in the core: `sd_cache` in front of `sdcard_native_dual` with `G_NET`.  Init through the cache; misses filling 8-sector lines from the network card (open-ended reads, grants, the last grant), read-ahead, hits, scattered reads, an explicit 3-sector read, a write through the cache read back, a refused write, and back to the internal socket.  36 blocks checked; 20 hits, 3 misses |
| `src/tools/hyppotest src/hyppo/netsd.test` (9 tests) | Config parsing.  The boot paths: not asked for; connects; DIP switch with no answer; right shift with no answer and the release wait; not in this core.  The 24 `$D6F1` writes checked against an independent computation |
| `run_sdcard_tests.py dual` / `io` | The existing controller tests, with `sdcard_native_dual` restructured and `sd_eth` built in.  `dual`: 7/7 pass.  `io`: 23/23 pass |

## Known gaps

1. **Hardware and Vivado:** neither yet.  Check timing, especially:
   - the `sd_eth` header and ARP byte multiplexers;
   - the parse comparisons;
   - the new `ethernet.vhdl` TX branch.
2. **`make_sdcardio_native.py` is stale.**  The #890 work has been editing
   `sdcardio_native.vhdl` directly (since `busy_unseen`), so regenerating
   would lose it.  The netsd edits were made the same way.
3. **The internal card is unavailable while the network card is on.**  It
   should become a third bus for the FAT32 engine later.
4. **Throughput** is unmeasured.  Expected limits:
   - one request outstanding;
   - reads in runs of 8;
   - writes one block per round trip;
   - the Python server's per-packet cost.
5. **Changes made on the PC while mounted** are seen only at the next HELLO.
6. **`hyppotest`'s CMP** sets C from N instead of from the unsigned compare.
   `netsd.test` avoids bytes of `$80` and up because of it.
7. **The `DEBUG_HYPPO=1` build** already overflowed `$BB00` before this work
   (`debug.asm` lands after the code).
