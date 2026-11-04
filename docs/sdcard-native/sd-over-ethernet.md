# SD card over Ethernet (#965): design notes

Status: **design, not built.**  Only the PC side exists so far
(`src/tools/netsd.py`, `src/tools/netsd_vfat.py`, tests in
`src/tools/test_netsd.py`).  It speaks the wire format below, minus the
crypto, and refuses frames with the authenticate or encrypt flag set.  Branch `965-sd-over-ethernet`, on top of
`890-sdcard-native`.

The idea: a third SD "slot" whose sectors come from a PC on the LAN.  The PC
builds a virtual card (MBR, a FAT32 partition generated from a host directory
tree, and a MEGA65 system partition) and answers sector reads and writes over
UDP.  The MEGA65 sees a card on slot 2 and treats it like any other card.

## 1. What is there today

### 1.1 `ethernet.vhdl`

- **RX** runs on the 50 MHz clock, a dibit at a time.  Each byte goes, by
  toggle CDC, into one of `num_buffers` = 4 2 KB CPU RX buffers, chosen
  round-robin.  The CPU frees a buffer with `$D6E1` bit 1.
  - The frame length and the CRC/for-me/broadcast/multicast flags go into
    bytes 0-1 of the buffer at the end of the frame.
  - Frames that fail the CRC or the MAC filter are never handed over.
- **Magic keyboard frames.** While a frame arrives, its bytes 100-109 are
  compared on the fly with `"eGSKEYCODE"` (`keyinput_magic`).
  - With remote control on, bytes 110-111 become `eth_keycode` with a toggle.
  - This happens **before the CRC is known**, and it ignores protocol
    headers and the destination MAC.  It works for its job but isn't a model
    for anything that must not act on corrupt frames.
- **TX** has one 2 KB buffer (`txbuffer0`) that the CPU writes, plus
  hardware sources picked in the TX `Idle` state:
  - the beacon (`eth_beacon_ram`: an IPv6 link-local UDP multicast to ff02::1
    port 4510, its UDP checksum worked out in hardware from the MAC);
  - the video/CPU-trace streams (disabled with `if false`).
  - `eth_tx_viciv` / `eth_tx_dump` choose which RAM feeds the shared
    preamble/CRC/FCS logic.
  - Adding another hardware TX source here is a well-trodden path.
- **Registers** `$D6E0-$D6EF` are all taken.  `$D6E4` is a write-only
  command register with spare codes.

So the magic frame isn't worth overloading.  It is checked before the CRC,
it has no headers, and it is too small for a sector.  The useful things to
reuse are:
- the RX byte stream with its end-of-frame CRC verdict;
- the TX source arbitration with its CRC/FCS generator;
- the MAC register (`eth_mac`).

### 1.2 Native SD stack (`890-sdcard-native`)

```
$D680 ─▶ sdcardio_native ─▶ sd_cache ─▶ sdcard_native_dual ─▶ slot 0 / slot 1
```

Every interface in this chain is `sdcard_native`'s host interface:
- a command mailbox (`cmd_code/addr/count/arg`);
- status;
- a read stream (`rd_valid/rd_data/rd_offset/rd_block` with a per-block
  `rd_good`/`rd_bad` verdict; on `rd_bad` the block is sent again);
- a write fetch (`wr_fetch/wr_offset` → `wr_data` a fixed `G_WR_LAT` later).

**This is the seam.**  A new entity `sd_eth` implements the same host
interface and sits beside `sdcard_native_dual` as slot 2.  Everything above
works unchanged:
- the cache with its 8-sector read-ahead lines;
- the F011 path;
- the later FAT32 engine.

The per-block good/bad verdict is also exactly what an authenticated stream
needs (§4.4).

### 1.3 Spare register space

Per the controller's convention, new commands take their parameters in
`$D681-$D684`.  That needs **no new register addresses** (§3).  The
hardware RNG exists (neoTRNG, `$D7EF`, not-ready flag `$D7FE.7`), so Hyppo can
take session entropy from it at no FPGA cost.

## 2. Wire format: UDP/IPv4

UDP/IPv4 was chosen so that the PC tool runs unprivileged:
- it is plain `socket(AF_INET, SOCK_DGRAM)`;
- no raw sockets, no `CAP_NET_RAW`, no libpcap.

The cost in the FPGA:
- **IPv4 header checksum:** a 17-bit ones'-complement accumulator while the
  header is written.
- **UDP checksum: 0.** That is legal on IPv4.  The Ethernet FCS plus the
  Ascon tag cover integrity.
- **A tiny ARP responder** (§2.3).

### 2.1 Frame layout

```
Ethernet (14) | IPv4 (20, no options) | UDP (8, port 6565 both ends)
| netsd header (16) | payload (0, 16 or 512) | tag (16, if authenticated)
```

A read response is 14+20+8+16+512+16 = 586 bytes plus FCS.  With the
preamble and inter-frame gap that is about 49 µs at 100 Mb/s, so about
10.4 MB/s at best.

### 2.2 netsd header (16 bytes; also the Ascon associated data)

All multi-byte fields are little-endian.

| Offset | Field |
|---|---|
| 0-1 | Magic `'M','S'` |
| 2 | bits 7-4 version (1); bit 0 response (PC → MEGA65); bit 1 authenticated (16-byte tag follows); bit 2 payload encrypted |
| 3 | Opcode |
| 4-7 | Session ID: random, chosen by the MEGA65 at each HELLO |
| 8-11 | Request sequence number.  A response echoes it |
| 12-15 | LBA |

| Op | Request (MEGA65 → PC) | Response (PC → MEGA65) |
|---|---|---|
| `$01` HELLO | Payload 16: MAC (6), requested host octet (1), capabilities (1), MEGA65 nonce (8).  Sent from 0.0.0.0 to 255.255.255.255 | Payload 32: MEGA65's IPv4 (4), server's IPv4 (4), capacity in sectors (4), flags (1: bit 0 writable), max sectors per READ (1), 2 reserved, server nonce (8), MAC echo (6), 2 reserved.  Sent to the subnet's broadcast address (e.g. 192.168.1.255; Ethernet ff:ff:ff:ff:ff:ff), because the MEGA65 has no address yet; the PC kernel picks the right interface for a directed broadcast, which it would not for 255.255.255.255.  While discovering, the MEGA65 takes any broadcast destination IP, and checks the MAC echo and the session |
| `$02` READ | Payload 16: count (1-8), 15 reserved | `count` frames, one per sector, LBA = request LBA + i, payload 512 |
| `$03` WRITE | Payload 512 | Payload 16: status (1), 15 reserved |
| `$7F` NAK | none | Payload 16: status (1), refused op (1), 14 reserved |

Statuses:

| Status | Meaning | What the MEGA65 does |
|---|---|---|
| 0 | OK | |
| 1 | Out of range | |
| 2 | Read-only | |
| 3 | Host I/O error | |
| 4 | Unknown session | HELLO again: the server was restarted |
| 5 | Authentication failed | |
| 6 | Bad request | |

Request/response rules:

- **Repeats are allowed.**  The MEGA65 sends a request again, with the
  **same** sequence number and the **same** bytes, if nothing comes back in
  about 20 ms.  After a few tries it reports an error up through `rd_bad` or
  `error`.
- **Duplicate writes.**  The server remembers each client's last write, by
  sequence number, and answers a duplicate without applying it again.
- **Requests are not pipelined.**  The MEGA65 has one request outstanding.
  READ's count, up to 8 (one cache line, from the cache's read-ahead),
  supplies the pipelining.
- **Response checks.**  A response counts only when all of these hold:
  - its session and sequence number match the outstanding request;
  - its LBA lies within the request;
  - its UDP source is the server learned at HELLO.

### 2.3 Addressing, several MEGA65s, ARP

- **Discovery.**  The MEGA65 learns its IPv4 address from the HELLO reply,
  much as DHCP does.  It sends HELLO from 0.0.0.0 with its MAC and a
  *requested host octet* (from the config).  The PC tool is told which subnet
  it serves (`--subnet 192.168.1.0/24`).  It answers with
  `subnet prefix + octet`, or with an address from its client table (keyed by
  MAC or octet).
- **The server's address.**  The MEGA65 takes the server's MAC from that
  reply's Ethernet source, and its IP from the payload.
- **Afterwards everything is unicast.**
- **Several MEGA65s.**  Each is told apart by MAC (and octet).  The PC tool
  maps each to its own directory tree (`--client`).
- **ARP is needed.**  For the PC kernel to send unicast UDP to the MEGA65, it
  has to resolve the MEGA65's IP, so `sd_eth` answers ARP requests for its
  own IP:
  - match: EtherType `0806`, oper 1, target IP = mine;
  - reply: a fixed 42-byte template with SHA/SPA/THA/TPA filled in.
  - Answering every frame by broadcast instead is not an option: about
    10 MB/s of broadcast would flatten any Wi-Fi access point bridged onto
    the segment, because APs send broadcasts at their basic rate.
- **Why a whole byte for the octet.**  The 7-bit octet in the original idea
  would limit MEGA65s to .0-.127.  With the enable bit elsewhere (§3) the
  whole byte is free.  An octet of 0 means "server chooses, by MAC".

## 3. MEGA65 side

### 3.1 Hardware

**`ethernet.vhdl`: small, local changes.**
- **RX tap.**  Export the received byte stream (byte, strobe, frame start) and
  an end-of-frame strobe with the CRC verdict, on the 50 MHz clock.  This is
  independent of the CPU RX buffers: SD traffic must not fill them, and must
  not be blocked when they are full.
- **TX source.**  `sd_tx_req` (toggle), `sd_tx_len`, a read address out and a
  data byte in.  It gets a branch in the TX `Idle` state next to the beacon,
  at lower priority than a CPU-triggered frame.  `sd_tx_done` toggles back.
- **`eth_mac`** out.

**New `sd_eth.vhdl`: the bulk.**
- **Cost:** 2 RAMB18, plus an FSM and, later, the Ascon core.
- **RX BRAM:** 2 KB as two 1 KB frame slots (ping-pong).
  - The write side is on 50 MHz.  It filters on the fly: Ethernet
    destination = my MAC, EtherType `0800`, IPv4 `45`, protocol 17,
    destination IP, UDP port 6565, magic.  For ARP it matches
    `0806`/oper 1/target IP.
  - A slot is committed only on a good CRC.
  - The read side is on cpuclock.  It is drained into the host read stream at
    up to a byte a cycle (40.5 MB/s), more than three times the 12.5 MB/s
    the wire delivers, so two slots are enough.
    - If upstream pauses (an open-ended read waiting for MORE), frames are
      dropped, and the request for the first missing LBA is sent again.
- **TX BRAM:** 1 KB.  It is written on cpuclock: the template header with
  addresses, lengths, IP ID and checksum, then the payload.
  - A write request's payload is pulled with `wr_fetch` at whatever pace
    suits (the fetch is by offset, so there is no need to keep up).
- **Host-side FSM:**
  - C_INIT = HELLO, retried for about 2 s;
  - C_READ/MORE/STOP = READ requests of up to 8 sectors;
  - C_WRITE = WRITE then wait for the status;
  - plus timeouts, repeats, and the ARP reply.
- **Status:** `card_ready`, `sdhc` (always '1': block addressing),
  `capacity_valid`/`last_sector` from HELLO.

**`sdcardio_native` (through `make_sdcardio_native.py`):**
- `sd_interface_select` becomes 2 bits, and that ripples into:
  - the `$D680` status mux;
  - `busy_unseen` (one per slot);
  - `diag_slot`;
  - the F011 disk-image binding (`$D68A` bits 4-5 can't say "slot 2";
    another bit is needed).
- **Control registers live in the SD controller.**  They are piped to
  `sd_eth`/`ethernet`, not the other way round.  `$D6E0-$D6EF` is full.  A
  sweep of every `@IO` annotation over `$D680-$D6FF` leaves only `$D6F1` and
  `$D6FF` unclaimed:
  - `$D697-$D69A` are AUTOIEC's;
  - `$D6CC-$D6CE`, `$D6D5-$D6D9` and `$D6DC-$D6DD` are decoded without
    annotations.

  So:

  | Register | Meaning |
  |---|---|
  | `$D6F1` | NETSD control.  bit 7 enable, bit 1 authenticate, bit 0 encrypt (r/w); bit 6 session up, bit 5 link up (read only) |
  | `$D6FF` | Requested host octet (0 = server chooses) |

  Both need confirming against the real read mux before use.  Clearing bit 7
  wipes the key.  These settings are quasi-static, so they reach
  `sd_eth`/`ethernet` through two or three plain register stages, which lets
  them cross the die without timing pressure; the 50 MHz side takes them
  through a two-flop synchroniser.  The 128-bit key crosses the same way: it
  is written once, before the HELLO, and is stable long before it is used.

- **Commands:**

  | Command | Meaning |
  |---|---|
  | `$C2` | Select slot 2 (network) |
  | `$35` | Load the session secret from the sector buffer: bytes 0-15 the PSK, bytes 16-23 the MEGA65 nonce.  It goes into write-only flops and is never readable.  16 bytes is too much for registers |

  The command codes need checking against the command decode.
- **Not building it:** an `sd_net` generic, false by default, so A100T
  targets don't pay.

### 3.2 Config sector (absolute LBA 1 of the real card) and the config program

The offsets in use are `$000-$022` and `$1F0-$1F5`.  Proposed (check these
against the upstream config layout first):

| Offset | Meaning |
|---|---|
| `$030` | bit 7 network SD enable, bit 0 encrypt, bit 1 authenticate |
| `$031` | Requested host octet (0 = server chooses) |
| `$032-$03F` | Reserved, zero |
| `$040-$04F` | 128-bit pre-shared key |

`src/utilities/mega65_config.s` / `.inc`, Network tab (`networkOptions0`,
which today has only the MAC):
- a type `$20` on/off option, "sd over ethernet", for `$030` bit `$80`;
- a type `$20` option, "encrypt sd traffic", for `$030` bit `$01`;
- **"host octet":** a new input type, a single hex/decimal byte.  The MAC
  editor (type `$50`) is the model.  Generalising `$50` to "N hex bytes" with
  a length byte would also cover the key;
- **"shared key":** 16 hex bytes (type `$50` generalised), plus a "press 'k'
  for random key" button like the random MAC one.  The tool then needs the
  same key: `--key HEX`, or a key file per client.

The key is stored in the clear on the real card's config sector.  Anyone
with the card has it.  That fits "better than nothing".

### 3.3 Hyppo

After the normal boot scan of the physical card, `syspart_configsector_apply`
sees `$030` bit 7, and Hyppo then:

1. Collects entropy: 8 bytes from `$D7EF` (waiting on `$D7FE.7`), XORed with
   the cycle/raster counters.  The time from power-on to here varies with the
   card's init time.
2. Writes the octet to `$D6FF` and the flags to `$D6F1` (bit 7 last), puts
   PSK + nonce in the sector buffer and issues `$35`, then `$C2` and
   `$00`/`$01` (HELLO), and polls with a timeout of about 2 s.
3. **On success:**
   - `dos_clearall`;
   - **clear `syspart_present`**, or the network card's system partition is
     refused as a second one (`partitionisinteresting_mega65sys` →
     `partitionerror`);
   - set a "config already applied" flag that `syspart_open` checks before
     `syspart_configsector_read`/`apply`/onboarding;
   - `dos_read_partitiontable` again.
4. **On failure:** select the physical slot again, print
   `NETWORK SD NOT FOUND`, and carry on as before.

So the network card **replaces** the physical one for DOS until reset.  Hyppo's
disk table has no per-disk slot, so mixing partitions from two slots isn't
possible yet.  That waits for the hardware FAT32 engine, which can scan all
three slots, as planned.

## 4. Crypto: options and recommendation

**Threat model:** someone on the LAN.  They can watch, inject and replay
frames.  They don't have the card or the PSK.

- **Integrity matters more than confidentiality.**  An attacker who can
  change sector data can change code the MEGA65 runs.
- **What is not covered:** denial of service (it's a LAN), and the key at
  rest on the card.

### 4.1 Candidates

| | Gives | FPGA cost (estimate) | Latency per 512 B sector | PC side |
|---|---|---|---|---|
| ChaCha20 alone | Confidentiality only.  **Malleable**: flip ciphertext bits and the same plaintext bits flip, and a forged response is accepted | ~600 LUT + 512 FF (one quarter-round per cycle), ~2000 LUT unrolled | ~1300 cycles qr-serial (8 blocks × 160) | `cryptography` (C) |
| ChaCha20-Poly1305 | AEAD | the above + a 130-bit multiply-accumulate (several DSP48 + ~500 LUT) | similar | `cryptography` (C) |
| SipHash-2-4 | MAC only, 64-bit tag | ~400 LUT + 256 FF | ~300 cycles | a few lines (`ctypes`/pure, slow) |
| **Ascon-AEAD128** (NIST SP 800-232, 2025) | AEAD, 128-bit tag; MAC-only by putting the payload in the AD | ~700 LUT + 320 FF at one round per cycle; ~250 LUT 64-bit lane-serial (5 cycles/round) | ~12 + 32×8 + 12 ≈ 280 cycles ≈ 7 µs at 40.5 MHz (lane-serial ≈ 35 µs) | `pyascon` (pure, slow) or a small C helper |
| AES-128-GCM | AEAD | ~2-3k LUT + a GHASH multiplier | | `cryptography` |

### 4.2 Recommendation: Ascon-AEAD128

- **One primitive** gives both authentication and optional encryption.
- **Its permutation is bit-sliced 64-bit lanes:** a 5-bit S-box and
  XOR/rotate diffusion, with no adders or multipliers, so it suits LUT6 well.
- **It costs less than any ChaCha20 variant that is actually secure**,
  because ChaCha20 needs Poly1305 for integrity.
- **It keeps up easily.**  At one round per cycle, a 16-byte block takes 8
  cycles (0.2 µs).  The wire delivers 16 bytes every 1.28 µs.  So it runs on
  the fly as frames stream in and out, and adds only the ~12-round
  finalisation (0.3 µs) to latency.
- **Authenticate-only mode costs the same as encrypting:** AD and plaintext
  absorb at the same rate.  So the encrypt flag is just a mode bit.

**On "ChaCha20 alone with a shared secret and session salting":** that keeps
the data secret, but anyone on the LAN could still answer a READ with
anything.  The MEGA65 can't tell a forgery from the real thing.  It could
also flip bits in a write's data without knowing the key.  Some MAC is
required whatever cipher is chosen.

### 4.3 Keys and nonces

- **K:** the 128-bit PSK from the config sector, or `--key` / per-client keys
  on the PC.
- **Nonce (128 bits):**

  | Bytes | Field |
  |---|---|
  | 4 | session |
  | 4 | sequence |
  | 4 | LBA |
  | 3 | server nonce, low 3 bytes |
  | 1 | op \| response bit \| frame index |

  Every message under K gets a unique nonce, provided that:
  - the session is fresh at each HELLO (64 bits of entropy go into the
    HELLO; the session ID is 32 of them);
  - the MEGA65 never reuses a sequence number with different contents.
    Repeats are byte-identical, which is safe.
- **No separate session-key derivation.**  The session and nonces already
  separate sessions, so K is used directly: no key schedule hardware and no
  Ascon-Hash.
- **AD** = the 16-byte header.  **Plaintext** = the payload, or empty with
  the payload moved into the AD for authenticate-only.  The tag goes after
  the payload.
- **HELLO and its reply are authenticated too**, which stops a rogue server.
- **Replay:**
  - The MEGA65 accepts only responses that match its single outstanding
    (session, sequence).
  - The server drops requests whose sequence is not newer than the last it
    accepted in that session (except an exact repeat of the last).
  - A replayed old HELLO only starts a session nobody can finish without K.

### 4.4 Fitting the stream

- **Reads:** decrypt and verify on the fly while passing bytes up `rd_data`.
  A bad tag gives `rd_bad`, and the existing per-block retry machinery asks
  again.  So unverified data is never marked good.  The cache only marks a
  sector valid on `rd_good`; this needs checking for the F011 path.
- **Writes:** encrypt while copying the fetched data into the TX BRAM, then
  append the tag.  The status response is authenticated.

### 4.5 PC-side cost

- **Pure-Python Ascon is too slow:** about 280 rounds per sector at ~15 µs a
  round is about 4 ms, or ~120 KB/s.
- **Instead:** a ~150-line C file built into a shared object and loaded with
  `ctypes`, with the pure-Python version as a reference and fallback.
- **Phase 1** of the tool sends and accepts flag bits 1-2 clear only.

## 5. PC tool (`src/tools/netsd.py`, `netsd_vfat.py`)

- **Virtual card:**
  - MBR: partition 1 FAT32 (`0C`) at LBA 2048; partition 2 MEGA65 system
    partition (`41`) at the end.  This is FDISK's layout.
  - **Generated lazily, sector by sector**, so a 4 GB virtual card costs no
    memory: the boot sector, FSInfo, backup, FAT sectors (from a sorted
    extent table), directory clusters (LFN + 8.3 entries) and file data (read
    from the host file on demand).
  - Each host file is contiguous on the virtual card.
- **System partition.**  A valid `MEGA65SYS00` header with freeze slots, so
  the freezer works.  **Its writes always go to a per-client scratch
  overlay**, even in read-only mode: freezing writes the slot.  They never
  touch the host tree.  LBA 1 (the config sector) reads as zeros.
- **Writes (`-w`):**
  - every write goes to a per-client overlay, so the MEGA65 always reads
    back what it wrote;
  - after a short quiet time, the overlay's FAT and directories are parsed
    and differences from the host tree are applied:
    - new directories: mkdir;
    - new and changed files: written to a temporary file, then renamed;
    - renames: detected by an unchanged first cluster;
    - deletes: only with `--delete`, so a parser bug can't destroy user
      files.
- **Sandbox:**
  - the MEGA65 sends only LBAs, never names, for reads;
  - host files are opened only from the tool's own scan, with
    `O_NOFOLLOW`;
  - symlinks, devices, FIFOs and sockets are skipped at scan time;
  - names from the MEGA65's directory entries are checked: no `/`, `\`, NUL,
    control characters, `.` or `..`;
  - all creation goes through directory fds (`dir_fd=`, `O_NOFOLLOW`,
    `O_EXCL`), so a symlink race can't escape the root;
  - cluster chains are bounded by the cluster count, and directory walks
    keep a visited set, so a malicious FAT can't loop the parser;
  - requests are accepted only from `--subnet`.
- **Several MEGA65s:** `--client OCTET|MAC=DIR` (repeatable), plus
  `--default DIR`.  Each client gets its own virtual card, overlay and
  session.
- **Host changes while mounted:** these are not seen, because the cluster
  layout must stay stable.  A new HELLO (the MEGA65 restarted) rebuilds the
  card from the host tree, if the overlay has nothing waiting to be written.

## 6. Gaps, risks, questions

1. **Hyppo has no per-disk slot**, so it's replace, not merge, until the
   FAT32 engine (§3.3).
2. **Freezing over the network** writes the whole slot each time (hundreds
   of KB): about 0.1 s at wire speed, more with the Python server.  That's
   acceptable.
3. **F011 image binding to slot 2** needs a new bit next to `$D68A` bits 4-5.
4. **CPU Ethernet users at the same time** (etherload, a TCP stack, the
   monitor): TX is shared by arbitration.  RX is a separate tap, so SD frames
   don't eat CPU RX buffers.  But the CPU's own promiscuous/broadcast
   settings still deliver HELLO replies (broadcast) to it.  That's harmless.
5. **Python server latency.**  Expect a few hundred µs per request.  With
   8-sector READs that is roughly 3-6 MB/s, not 10.  `sendmmsg` isn't
   available from Python; the asyncio overhead is what it is.
6. **Config sector offsets `$030-$04F`** must be checked against the current
   upstream config utility, the ROM, and the freezer.
7. **Ethernet not up at that point of boot** (PHY reset, link
   autonegotiation can take 2-3 s): Hyppo has to wait for link before HELLO.
8. **The hardware cost** of `sd_eth` without crypto: an estimated
   400-700 LUT plus 2 RAMB18.  With full-width Ascon, about +700 LUT, which
   is large next to the area budget.  The lane-serial core (~250 LUT) is
   still fast enough to keep up with the wire, so it's the likely choice.
