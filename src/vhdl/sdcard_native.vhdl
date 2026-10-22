--------------------------------------------------------------------------------
-- sdcard_native: SD card controller with the native 4-bit SD bus (and SPI as
-- a fallback), for the MEGA65.
--
-- Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project.
-- Released under the GNU Lesser General Public License v3 (as LICENSE.txt).
--
-- Written from scratch.  The protocol sequencing borrows ideas from the
-- Megamiga sdhost (native init with a test read, SPI fallback for cards that
-- are still in SPI mode, flow control by stopping the clock between blocks),
-- but none of its code.
--
-- Used on the mega65r6 target (iomapper generic sd_native) in place of
-- sdcard.vhdl (SdCardCtrl); see MEGA65/mega65-core#890.  sdcardio_native.vhdl
-- (generated from sdcardio by src/tools/make_sdcardio_native.py) is the upper
-- controller that uses it.
-- Simulation: tb_sdcard_native.vhdl (with sdcard_native_model.vhdl), and
-- tb_sdcardio_native.vhdl for the pair.
--
-- OVERVIEW
--
--   * The protocol engine runs on clock162.  SD_CLK comes from an ODDR, so its
--     edges fall on clock162 half cycles: the clock period is P half cycles of
--     3.086 ns (P >= 4), i.e. 324 MHz / P:
--         P = 810 : 400 kHz   (identification)
--         P =  13 : 24.9 MHz  (default speed; SPI)
--         P =   8 : 40.5 MHz  (high speed: the default once CMD6 succeeded)
--         P =   7 : 46.3 MHz  (high speed, still in spec)
--         P =   6 : 54 MHz, 5 : 64.8 MHz, 4 : 81 MHz   (overclocking)
--     Odd P gives a duty cycle of (P+1)/2 : (P-1)/2, the low phase the longer
--     one (it is the card's set-up time).  At 81 MHz the 4-bit bus moves 40.5
--     MB/s: one byte per cpuclock, which is what the host side can take.
--
--   * No block RAM.  Read data streams out through a small LUTRAM FIFO, one
--     byte strobe per byte, and the block's CRC verdict follows as a separate
--     strobe.  Write data is fetched from the host's sector buffer: the
--     controller drives a byte offset and a strobe, and takes the byte
--     G_WR_LAT cpuclocks later.
--
-- BIT TIMING
--
--   Every SD clock cycle has a TAG: cycles are numbered from 1 since the tags
--   were last reset (only ever with the clock stopped).  The host changes
--   CMD/DAT at the falling edge that starts a cycle (on the first clock162
--   edge at or after it) and the card samples at the rising edge.
--
--   Inputs go through an IDDR: one sample per clock162 half cycle.  The sample
--   for cycle n is taken D half cycles after the (internal) rising edge of
--   cycle n, and is handed to the engine tagged n.  Since everything the engine
--   receives carries its tag, D may be more than one SD clock: the engine finds
--   every response, data block, CRC status and busy period by scanning tagged
--   samples for start bits, and ignores samples of cycles in which it drove
--   the line itself.
--
--   Default speed and SPI: the card changes its outputs after a falling edge,
--   so a D of a few half cycles (well before the next falling edge) is safe.
--   High speed: the card changes after a rising edge, with up to 14 ns output
--   delay, so D sits near one whole SD clock.  C_PROBE lets software search for
--   (P, D) pairs that work with the card at hand.
--
--   (A finer sample point would need IDELAYE2 taps, which need a 200/300 MHz
--   IDELAYCTRL reference that the MEGA65 clocking does not have yet.)
--
-- FLOW CONTROL
--
--   Reads: the host takes bytes as they come.  When the start bit of block k
--   arrives, the engine knows the tag of its end bit; if block k+1 is not
--   granted yet (open-ended transfers) the clock is set to stop exactly after
--   that end bit, before the card can start the next block, and runs on once
--   the grant arrives.  Writes: the clock simply stops while the engine waits.
--   SPI: the clock only ever stops at byte boundaries.
--
-- HOST INTERFACE (cpuclock)
--
--   Commands: put code/addr/count/arg on the inputs and pulse cmd_valid while
--   cmd_ready = '1'.  cmd_ready stays low until the engine has taken the
--   command AND the status outputs reflect it, so "issue, wait for cmd_ready,
--   then look at busy/waiting/error" has no races.
--
--     C_INIT   (1) (re)initialise the card.  Aborts whatever is going on.
--                  arg bit 0 = SPI only (do not try the native bus)
--                  arg bit 1 = stay at default speed (do not try high speed)
--                  arg bit 4 = slot (0 or 1)
--     C_READ   (2) read count blocks from block address addr.  count = 0 opens
--                  an open-ended transfer with ONE block granted.
--     C_WRITE  (3) as C_READ, writing.
--     C_MORE   (4) grant one more block of an open-ended transfer.  arg bit 0 =
--                  it is the last one.
--     C_STOP   (5) end the open-ended transfer after the blocks granted so far.
--     C_PROBE  (6) try clock setting arg: read block addr count times (0 =
--                  once), count clean reads in probe_pass and failed ones in
--                  probe_fail, then go back to the current setting.  The data
--                  is thrown away.
--     C_ACCEPT (7) make clock setting arg the current one (no checks: probe it
--                  first).  arg = 0 goes back to the normal setting.
--     C_CLEAR  (9) clear errors without CMD0/reinitialisation. Native SD
--                  confirms CMD12 + CMD13 Transfer/ready before reuse; SPI
--                  clears the retired transfer's error with CS inactive.
--     C_INFO   (B) read card information: arg = 0 CSD, 1 CID, 2 SCR,
--                  3 SD Status. Raw wire-order bytes (16/16/8/64), padded
--                  with zeros to 512 bytes through the normal read FIFO.
--   Init reads CSD and publishes capacity_valid/last_sector in the CPU
--   domain. limit_enable (default 1) bounds sector reads/writes/probes and
--   open-transfer grants; out-of-range requests return ERR_RANGE ($44),
--   unknown capacity ERR_CAPACITY ($45). No extra block RAM is used.
--
--   Clock setting (arg of C_PROBE / C_ACCEPT, and clk_setting): bits 6..0 = P
--   (4..127), bits 12..8 = D (0..31).  P < 13 needs a card that switched to
--   high speed (ERR_NOHS otherwise).  If an accepted setting fails a transfer
--   twice, the controller goes back to the normal setting and retries.
--
--   Status (look at it while cmd_ready = '1'):
--     card_ready   the card is initialised
--     busy         a command or transfer is active (read data included)
--     waiting      an open-ended transfer finished all granted blocks (and all
--                  their data came out): issue C_MORE or C_STOP
--     error/err_code  the last command failed (cleared by the next command)
--     native_mode, high_speed, sdhc, clk_setting, probe_pass/fail, blocks_done
--
--   Read stream: rd_valid strobes rd_data at rd_offset (0..511) of block
--   rd_block (relative to addr).  rd_valid can be high every cycle.  After the
--   512th byte comes rd_good (CRC fine) or rd_bad (CRC wrong: the block is
--   sent again, from offset 0, unless the retries ran out).
--
--   Write fetch: wr_fetch strobes for byte wr_offset of block wr_block; the
--   host presents that byte on wr_data exactly G_WR_LAT cpuclocks later.
--   A block can be fetched more than once (after a CRC error).
--
-- CARD PINS: two slots (0 = internal, 1 = external), each with CLK, CMD and
-- DAT3..0; every line has an output, an output enable and an input.  In SPI
-- mode CMD is MOSI, DAT0 is MISO and DAT3 is the chip select.  The ODDR
-- (clock), the output registers (IOB) and the IDDRs (inputs) are inside this
-- entity: the top level should only place the IOBUFs.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdcard_native is
  generic (
    G_XILINX    : boolean := true;      -- false: behavioural ODDR/IDDR (GHDL)
    G_MS        : natural := 162_000;   -- clock162 cycles per millisecond
    G_AUTO_INIT : boolean := true;      -- initialise slot 0 after power-up
    G_WR_LAT    : natural := 2;         -- wr_fetch -> wr_data latency (cpuclocks)
    G_TRACE     : boolean := false;     -- simulation: report state changes
    G_INIT_P    : natural := 810;       -- 400 kHz during identification
    G_INIT_D    : natural := 3;
    G_DS_P      : natural := 13;        -- default speed: 24.9 MHz
    G_DS_D      : natural := 3;
    G_HS_P      : natural := 8;         -- high speed: 40.5 MHz
    G_HS_D      : natural := 8;
    -- -1: original multiplexed engine; 0/1: own just that socket's I/O.
    G_FIXED_SLOT : integer range -1 to 1 := -1
    );
  port (
    clock162    : in  std_logic;
    cpuclock    : in  std_logic;

    -- host side (cpuclock) ----------------------------------------------------
    cmd_valid   : in  std_logic;
    cmd_ready   : out std_logic;
    cmd_code    : in  unsigned(3 downto 0);
    cmd_addr    : in  unsigned(31 downto 0);
    cmd_count   : in  unsigned(15 downto 0);
    cmd_arg     : in  unsigned(15 downto 0);

    card_ready  : out std_logic;
    busy        : out std_logic;
    waiting     : out std_logic;
    error       : out std_logic;
    err_code    : out unsigned(7 downto 0);
    native_mode : out std_logic;
    high_speed  : out std_logic;
    sdhc        : out std_logic;
    clk_setting : out unsigned(15 downto 0);
    probe_pass  : out unsigned(7 downto 0);
    probe_fail  : out unsigned(7 downto 0);
    blocks_done : out unsigned(15 downto 0);
    -- CPU-domain diagnostic snapshot: seven wrapping 16-bit event counters
    -- (read retries, stop retries, read CRC/timeouts/commands, terminal read
    -- failures, terminal stop failures), then the current clock setting.
    diag_stats  : out unsigned(127 downto 0);

    rd_valid    : out std_logic;
    rd_data     : out unsigned(7 downto 0);
    rd_offset   : out unsigned(8 downto 0);
    rd_block    : out unsigned(15 downto 0);
    rd_good     : out std_logic;
    rd_bad      : out std_logic;

    wr_fetch    : out std_logic;
    wr_offset   : out unsigned(8 downto 0);
    wr_block    : out unsigned(15 downto 0);
    wr_data     : in  unsigned(7 downto 0);

    -- card slots ---------------------------------------------------------------
    sd_clk      : out std_logic_vector(1 downto 0);
    sd_cmd_o    : out std_logic_vector(1 downto 0);
    sd_cmd_oe   : out std_logic_vector(1 downto 0);
    sd_cmd_i    : in  std_logic_vector(1 downto 0);
    sd_dat_o    : out std_logic_vector(7 downto 0);   -- slot*4 + line
    sd_dat_oe   : out std_logic_vector(7 downto 0);
    sd_dat_i    : in  std_logic_vector(7 downto 0);
    limit_enable : in std_logic := '1'; -- CPU-domain policy, default bounded
    capacity_valid : out std_logic;
    last_sector : out unsigned(31 downto 0) -- inclusive, CPU-domain
    );
end entity sdcard_native;

architecture rtl of sdcard_native is

  -- Xilinx primitives (bound to UNISIM by Vivado; only elaborated if G_XILINX)
  component ODDR is
    generic (DDR_CLK_EDGE : string := "OPPOSITE_EDGE"; INIT : bit := '0';
             SRTYPE : string := "SYNC");
    port (Q : out std_ulogic; C : in std_ulogic; CE : in std_ulogic;
          D1 : in std_ulogic; D2 : in std_ulogic; R : in std_ulogic; S : in std_ulogic);
  end component;
  component IDDR is
    generic (DDR_CLK_EDGE : string := "OPPOSITE_EDGE"; INIT_Q1 : bit := '0';
             INIT_Q2 : bit := '0'; SRTYPE : string := "SYNC");
    port (Q1 : out std_ulogic; Q2 : out std_ulogic; C : in std_ulogic; CE : in std_ulogic;
          D : in std_ulogic; R : in std_ulogic; S : in std_ulogic);
  end component;

  ------------------------------------------------------------------------------
  -- constants
  ------------------------------------------------------------------------------

  constant C_NOP    : unsigned(3 downto 0) := x"0";
  constant C_INIT   : unsigned(3 downto 0) := x"1";
  constant C_READ   : unsigned(3 downto 0) := x"2";
  constant C_WRITE  : unsigned(3 downto 0) := x"3";
  constant C_MORE   : unsigned(3 downto 0) := x"4";
  constant C_STOP   : unsigned(3 downto 0) := x"5";
  constant C_PROBE  : unsigned(3 downto 0) := x"6";
  constant C_ACCEPT : unsigned(3 downto 0) := x"7";
  constant C_CLEAR  : unsigned(3 downto 0) := x"9";
  constant C_INFO   : unsigned(3 downto 0) := x"B";

  constant ERR_NONE     : unsigned(7 downto 0) := x"00";
  constant ERR_NOCARD   : unsigned(7 downto 0) := x"01";  -- no card answered
  constant ERR_INIT     : unsigned(7 downto 0) := x"02";  -- init failed
  constant ERR_CMD      : unsigned(7 downto 0) := x"10";  -- command not answered / refused
  constant ERR_RD_TMO   : unsigned(7 downto 0) := x"20";  -- no read data
  constant ERR_RD_CRC   : unsigned(7 downto 0) := x"21";  -- read data bad (after retries)
  constant ERR_WR_CRC   : unsigned(7 downto 0) := x"30";  -- write: card saw a CRC error
  constant ERR_WR_ERR   : unsigned(7 downto 0) := x"31";  -- write: card reported an error
  constant ERR_WR_TMO   : unsigned(7 downto 0) := x"32";  -- write: status / busy timeout
  constant ERR_BUSY     : unsigned(7 downto 0) := x"40";  -- command while busy
  constant ERR_NOTREADY : unsigned(7 downto 0) := x"41";  -- transfer without a card
  constant ERR_NOHS     : unsigned(7 downto 0) := x"42";  -- setting needs high speed
  constant ERR_BADCMD   : unsigned(7 downto 0) := x"43";  -- unknown command / bad setting
  constant ERR_RANGE    : unsigned(7 downto 0) := x"44";  -- outside reported card capacity
  constant ERR_CAPACITY : unsigned(7 downto 0) := x"45";  -- unavailable/unsupported CSD capacity

  -- R1 card status bits that fail a command.  COM_CRC_ERROR and
  -- ILLEGAL_COMMAND are left out: they are about the PREVIOUS command.
  constant R1_ERRMASK : std_logic_vector(31 downto 0) := x"FD380000";

  constant TMO_INIT   : natural := 1000 * G_MS;   -- ACMD41 loop
  constant TMO_READ   : natural := 250 * G_MS;    -- read data start
  constant TMO_PROBE  : natural := 20 * G_MS;     -- read data start while probing
  constant TMO_BUSY   : natural := 750 * G_MS;    -- programming busy
  constant TMO_SETTLE : natural := 2 * G_MS;      -- power-up settling

  constant MH_LEN : natural := 36;              -- sample markers: D <= 31

  constant WPF    : natural := 16;              -- write FIFO fill before a block

  function setting(p : natural; d : natural) return unsigned is
    variable s : unsigned(15 downto 0) := (others => '0');
  begin
    s(6 downto 0)  := to_unsigned(p mod 128, 7);
    s(12 downto 8) := to_unsigned(d, 5);
    return s;
  end function;

  constant SET_DS : unsigned(15 downto 0) := setting(G_DS_P, G_DS_D);
  constant SET_HS : unsigned(15 downto 0) := setting(G_HS_P, G_HS_D);

  ------------------------------------------------------------------------------
  -- CRCs (MSB first), command frames, tags
  ------------------------------------------------------------------------------

  function crc7_bit(c : std_logic_vector(6 downto 0); b : std_logic) return std_logic_vector is
    variable r : std_logic_vector(6 downto 0);
  begin
    r := c(5 downto 0) & '0';
    if (b xor c(6)) = '1' then
      r := r xor "0001001";
    end if;
    return r;
  end function;

  function crc16_bit(c : std_logic_vector(15 downto 0); b : std_logic) return std_logic_vector is
    variable r : std_logic_vector(15 downto 0);
  begin
    r := c(14 downto 0) & '0';
    if (b xor c(15)) = '1' then
      r := r xor x"1021";
    end if;
    return r;
  end function;

  function crc16_byte(c : std_logic_vector(15 downto 0); b : std_logic_vector(7 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(15 downto 0) := c;
  begin
    for i in 7 downto 0 loop
      r := crc16_bit(r, b(i));
    end loop;
    return r;
  end function;

  function cmd_frame(idx : natural; arg : std_logic_vector(31 downto 0)) return std_logic_vector is
    variable f : std_logic_vector(47 downto 0);
    variable c : std_logic_vector(6 downto 0) := (others => '0');
  begin
    f(47 downto 46) := "01";
    f(45 downto 40) := std_logic_vector(to_unsigned(idx, 6));
    f(39 downto 8)  := arg;
    for i in 47 downto 8 loop
      c := crc7_bit(c, f(i));
    end loop;
    f(7 downto 1) := c;
    f(0)          := '1';
    return f;
  end function;

  function boolean_to_sl(b : boolean) return std_logic is
  begin
    if b then return '1'; else return '0'; end if;
  end function;

  -- tag a is later than tag b (16-bit wrapping)
  function later(a : unsigned(15 downto 0); b : unsigned(15 downto 0)) return boolean is
    variable d : unsigned(15 downto 0);
  begin
    d := a - b;
    return d /= 0 and d(15) = '0';
  end function;

  function bin2gray(b : unsigned) return unsigned is
  begin
    return b xor shift_right(b, 1);
  end function;

  function gray2bin(g : unsigned) return unsigned is
    variable b : unsigned(g'range);
  begin
    b(g'high) := g(g'high);
    for i in g'high - 1 downto g'low loop
      b(i) := b(i + 1) xor g(i);
    end loop;
    return b;
  end function;

  ------------------------------------------------------------------------------
  -- FIFOs (LUTRAM, 32 entries, pointers with a wrap bit)
  --   read FIFO  (engine -> host): bits 9..8 = 00 data, 10 block good, 11 bad
  --   write FIFO (host -> engine): bit 8 = fetch sequence bit, 7..0 data
  ------------------------------------------------------------------------------

  type t_rfifo is array (0 to 31) of std_logic_vector(9 downto 0);
  type t_wfifo is array (0 to 31) of std_logic_vector(8 downto 0);
  signal rfifo : t_rfifo := (others => (others => '0'));
  signal wfifo : t_wfifo := (others => (others => '0'));
  attribute ram_style : string;
  attribute ram_style of rfifo : signal is "distributed";
  attribute ram_style of wfifo : signal is "distributed";

  attribute ASYNC_REG : string;

  -- read FIFO
  signal rf_we      : std_logic := '0';
  signal rf_din     : std_logic_vector(9 downto 0) := (others => '0');
  signal rf_wp      : unsigned(5 downto 0) := (others => '0');   -- engine
  signal rf_wpg     : unsigned(5 downto 0) := (others => '0');
  signal rf_wpg_s0  : unsigned(5 downto 0) := (others => '0');   -- host
  signal rf_wpg_s1  : unsigned(5 downto 0) := (others => '0');
  signal rf_rp      : unsigned(5 downto 0) := (others => '0');   -- host
  signal rf_rpg     : unsigned(5 downto 0) := (others => '0');
  signal rf_rpg_s0  : unsigned(5 downto 0) := (others => '0');   -- engine
  signal rf_rpg_s1  : unsigned(5 downto 0) := (others => '0');
  signal rf_empty_e : std_logic := '1';                          -- engine view
  -- room for one more push (at most 24 in the FIFO; registered, and pushes
  -- are at least two cycles apart, hence 23)
  signal rf_room    : std_logic := '1';
  attribute ASYNC_REG of rf_wpg_s0 : signal is "TRUE";
  attribute ASYNC_REG of rf_wpg_s1 : signal is "TRUE";
  attribute ASYNC_REG of rf_rpg_s0 : signal is "TRUE";
  attribute ASYNC_REG of rf_rpg_s1 : signal is "TRUE";

  -- write FIFO
  signal wf_wp      : unsigned(5 downto 0) := (others => '0');   -- host
  signal wf_wpg     : unsigned(5 downto 0) := (others => '0');
  signal wf_wpg_s0  : unsigned(5 downto 0) := (others => '0');   -- engine
  signal wf_wpg_s1  : unsigned(5 downto 0) := (others => '0');
  signal wf_wp_e    : unsigned(5 downto 0) := (others => '0');
  signal wf_rp      : unsigned(5 downto 0) := (others => '0');   -- engine
  signal wf_rpg     : unsigned(5 downto 0) := (others => '0');
  signal wf_rpg_s0  : unsigned(5 downto 0) := (others => '0');   -- host
  signal wf_rpg_s1  : unsigned(5 downto 0) := (others => '0');
  signal wf_head    : std_logic_vector(8 downto 0);
  attribute ASYNC_REG of wf_wpg_s0 : signal is "TRUE";
  attribute ASYNC_REG of wf_wpg_s1 : signal is "TRUE";
  attribute ASYNC_REG of wf_rpg_s0 : signal is "TRUE";
  attribute ASYNC_REG of wf_rpg_s1 : signal is "TRUE";

  ------------------------------------------------------------------------------
  -- host side (cpuclock)
  ------------------------------------------------------------------------------

  signal h_req      : std_logic := '0';
  signal h_code     : unsigned(3 downto 0) := (others => '0');
  signal h_addr     : unsigned(31 downto 0) := (others => '0');
  signal h_count    : unsigned(15 downto 0) := (others => '0');
  signal h_arg      : unsigned(15 downto 0) := (others => '0');

  signal pub_req_s  : std_logic_vector(2 downto 0) := "000";
  signal pub_ack    : std_logic := '0';
  attribute ASYNC_REG of pub_req_s : signal is "TRUE";

  signal hs_ack     : std_logic;
  signal hs_busy    : std_logic;
  signal hs_wait    : std_logic;
  signal hs_wseq    : std_logic;
  signal hs_wblk    : unsigned(15 downto 0);

  -- read stream
  signal h_rv       : std_logic := '0';
  signal h_rgood    : std_logic := '0';
  signal h_rbad     : std_logic := '0';
  signal h_rdata    : unsigned(7 downto 0) := (others => '0');
  signal h_roff     : unsigned(8 downto 0) := (others => '0');
  signal h_rnext    : unsigned(8 downto 0) := (others => '0');
  signal h_rblk     : unsigned(15 downto 0) := (others => '0');
  signal h_rpending : std_logic;

  -- write fetch
  signal h_wseq     : std_logic := '0';
  signal h_wact     : std_logic := '0';
  signal h_wfetch   : std_logic := '0';
  signal h_woff     : unsigned(8 downto 0) := (others => '0');
  signal h_wnext    : unsigned(8 downto 0) := (others => '0');
  signal h_wblk     : unsigned(15 downto 0) := (others => '0');
  signal h_wip      : unsigned(5 downto 0) := (others => '0');   -- issued fetches
  signal h_wdly     : std_logic_vector(G_WR_LAT downto 0) := (others => '0');
  signal h_wsdly    : std_logic_vector(G_WR_LAT downto 0) := (others => '0');

  ------------------------------------------------------------------------------
  -- status bundle (engine -> host)
  ------------------------------------------------------------------------------

  constant ST_W : natural := 249;
  signal st_live   : std_logic_vector(ST_W-1 downto 0);
  signal st_pub    : std_logic_vector(ST_W-1 downto 0) := (others => '0');
  signal st_host   : std_logic_vector(ST_W-1 downto 0) := (2 => '1', others => '0');
  signal pub_req   : std_logic := '0';
  signal pub_ack_s : std_logic_vector(1 downto 0) := "00";
  attribute ASYNC_REG of pub_ack_s : signal is "TRUE";

  ------------------------------------------------------------------------------
  -- clock generator (clock162)
  ------------------------------------------------------------------------------

  signal cg_p      : unsigned(9 downto 0) := to_unsigned(G_INIT_P, 10);
  signal cg_low    : unsigned(9 downto 0) := to_unsigned((G_INIT_P + 1) / 2, 10);
  signal cg_d      : unsigned(4 downto 0) := to_unsigned(G_INIT_D, 5);
  signal cg_ph     : unsigned(9 downto 0) := (others => '0');
  signal cg_ph1    : unsigned(9 downto 0) := to_unsigned(1, 10);
  signal cg_frz    : std_logic := '1';
  signal cg_d1     : std_logic := '1';
  signal cg_d2     : std_logic := '1';
  signal fall0_r   : std_logic := '0';
  signal fall1_r   : std_logic := '0';
  signal fall1_rr  : std_logic := '0';
  signal rise0_r   : std_logic := '0';
  signal rise1_r   : std_logic := '0';
  signal rcnt      : unsigned(15 downto 0) := (others => '0');  -- rising edges so far
  signal at_stop   : std_logic := '0';     -- rcnt = stop_at
  signal byte_end  : std_logic := '1';     -- rcnt is a multiple of 8
  signal stop_m1   : unsigned(15 downto 0) := (others => '1');
  signal cg_allow  : std_logic;
  signal cg_clr    : std_logic := '0';     -- engine: reset the tags (clock stopped)

  signal run       : std_logic := '0';     -- let the clock run
  signal stop_en   : std_logic := '0';     -- ... but stop after the cycle stop_at
  signal stop_at   : unsigned(15 downto 0) := (others => '0');

  -- output stage
  signal load_en   : std_logic;
  signal tick      : std_logic := '0';     -- a cycle just started (tag ttag)
  signal ttag      : unsigned(15 downto 0) := (others => '0');
  signal cmd_nx    : std_logic := '1';
  signal cmd_oe_nx : std_logic := '0';
  signal dat_nx    : std_logic_vector(3 downto 0) := "1111";
  signal dat_oe_nx : std_logic_vector(3 downto 0) := "0000";
  signal cmd_q     : std_logic_vector(1 downto 0) := "11";
  signal cmd_t_q   : std_logic_vector(1 downto 0) := "11";    -- '1' = released
  signal dat_q     : std_logic_vector(7 downto 0) := (others => '1');
  signal dat_t_q   : std_logic_vector(7 downto 0) := (others => '1');
  function initial_slot return std_logic is
  begin
    if G_FIXED_SLOT = 1 then return '1'; else return '0'; end if;
  end function;
  signal slot      : std_logic := initial_slot;
  signal clk_d1    : std_logic_vector(1 downto 0);
  signal clk_d2    : std_logic_vector(1 downto 0);

  attribute IOB : string;
  attribute IOB of cmd_q    : signal is "TRUE";
  attribute IOB of cmd_t_q  : signal is "TRUE";
  attribute IOB of dat_q    : signal is "TRUE";
  attribute IOB of dat_t_q  : signal is "TRUE";

  -- input stage: IDDR outputs per slot and line (bit 5*slot+4 = CMD)
  signal in_q1     : std_logic_vector(9 downto 0);
  signal in_q2     : std_logic_vector(9 downto 0);
  signal in_pins   : std_logic_vector(9 downto 0);
  signal s_q1      : std_logic_vector(4 downto 0) := (others => '1');
  signal s_q2      : std_logic_vector(4 downto 0) := (others => '1');
  signal mh        : std_logic_vector(0 to MH_LEN-1) := (others => '0');
  signal sel1      : std_logic := '0';
  signal sel2      : std_logic := '0';

  -- the sample stream: one tagged sample per SD cycle
  signal rx_v      : std_logic := '0';
  signal rx_cmd    : std_logic := '1';
  signal rx_dat    : std_logic_vector(3 downto 0) := "1111";
  signal rx_tag    : unsigned(15 downto 0) := (others => '0');

  -- the same, one cycle later in the engine, with tag comparisons
  signal rxd_v     : std_logic := '0';
  signal rxd_cmd   : std_logic := '1';
  signal rxd_dat   : std_logic_vector(3 downto 0) := "1111";
  signal rxd_tag   : unsigned(15 downto 0) := (others => '0');
  signal rf_cend, rf_c80, rf_dafter, rf_bafter, rf_tend, rf_t16 : std_logic := '0';
  signal cmd_gap_ok : std_logic := '1';
  signal wr_gap_ok  : std_logic := '0';

  ------------------------------------------------------------------------------
  -- engine (clock162)
  ------------------------------------------------------------------------------

  type t_resp is (R_NONE, R_R1, R_R1B, R_R2, R_R3, R_R7);

  type t_state is (
    S_POWERUP, S_INIT, S_IDLE, S_DISPATCH, S_FINISH, S_FAIL, S_TAIL, S_DRAIN,
    S_RESYNC, S_RESYNC2, S_CMD_WAIT, S_CMD, S_BUSY0, S_BUSY1, S_ABORT,
    S_CLOSE, S_CLOSE_RESP, S_CLOSE_STATUS, S_RECOVER,
    I_START, I_APP, I_APP_RESP, I_DATA_CMD, I_DATA_RESP, I_DATA,
    I_EMIT, I_GOOD, I_ABORT, I_ERROR,
    N_I_REG, N_I_REG_RESP, N_I_SELECT,
    S_CAP_DECODE, S_CAP_SHIFT, S_RANGE_ADD, S_RANGE_CHECK,
    -- native
    N_PRE, N_INIT,
    N_RD_CMD, N_RD_RESP, N_RD_BLOCK, N_RD_STOP,
    N_WR_CMD, N_WR_RESP, N_WR_WAIT, N_WR_DATA, N_WR_STATUS, N_WR_NEXT,
    -- SPI
    P_PRE, P_INIT, P_DESEL, P_FIN,
    P_RD_CMD, P_RD_RESP, P_RD_BLOCK, P_RD_END, P_RD_END2,
    P_WR_CMD, P_WR_RESP, P_WR_WAIT, P_WR_DATA, P_WR_DRESP, P_WR_STOPTOK
    );
  signal st, ret_st, resync_ret, drain_ret : t_state := S_POWERUP;
  signal close_ret : t_state := S_DISPATCH;
  signal close_tries : natural range 0 to 2 := 0;

  -- mode / card
  signal mode_native : std_logic := '0';
  signal spi_only    : std_logic := '0';
  signal spi_fb      : std_logic := '0';     -- native failed in this init: SPI
  signal no_hs       : std_logic := '0';
  signal hs          : std_logic := '0';
  signal hc          : std_logic := '0';
  signal v2          : std_logic := '0';
  signal ready       : std_logic := '0';
  signal rca         : std_logic_vector(15 downto 0) := (others => '0');
  signal cur_set     : unsigned(15 downto 0) := SET_DS;
  signal new_set     : unsigned(15 downto 0) := SET_DS;
  signal istep       : natural range 0 to 31 := 0;
  signal tries       : natural range 0 to 15 := 0;
  signal tmo         : unsigned(27 downto 0) := (others => '0');
  signal tmo_z       : std_logic := '1';     -- tmo is 0
  signal cnt         : unsigned(10 downto 0) := (others => '0');

  -- command mailbox
  signal e_req_s     : std_logic_vector(1 downto 0) := "00";
  signal e_ack       : std_logic := '0';
  signal e_seen      : std_logic := '0';     -- the request toggle as last copied
  signal cmd_pend    : std_logic := '0';     -- a copied command waits
  signal e_code      : unsigned(3 downto 0) := (others => '0');
  signal e_addr      : unsigned(31 downto 0) := (others => '0');
  signal e_count     : unsigned(15 downto 0) := (others => '0');
  signal e_arg       : unsigned(15 downto 0) := (others => '0');
  signal e_cnt0      : std_logic := '0';     -- count = 0
  signal e_argz      : std_logic := '0';     -- arg = 0
  signal e_lt4       : std_logic := '0';     -- arg P < 4
  signal e_lt13      : std_logic := '0';     -- arg P < 13
  attribute ASYNC_REG of e_req_s : signal is "TRUE";

  -- status
  signal e_busy      : std_logic := '1';
  signal e_error     : std_logic := '0';
  signal e_err       : unsigned(7 downto 0) := (others => '0');
  signal e_pass      : unsigned(7 downto 0) := (others => '0');
  signal e_fail      : unsigned(7 downto 0) := (others => '0');
  signal e_wait      : std_logic := '0';

  -- the operation
  type t_op is (OP_NONE, OP_READ, OP_WRITE, OP_PROBE, OP_INFO);
  signal op          : t_op := OP_NONE;
  signal info_kind   : unsigned(1 downto 0) := (others => '0');
  signal info_len    : unsigned(6 downto 0) := to_unsigned(16, 7);
  signal info_pos    : unsigned(9 downto 0) := (others => '0');
  signal info_ok     : std_logic := '0';
  signal info_data_done, info_data_ok : std_logic := '0';
  signal info_init : std_logic := '0';
  signal cap_known : std_logic := '0';
  signal cap_last : unsigned(31 downto 0) := (others => '0');
  signal cap_work : unsigned(32 downto 0) := (others => '0');
  signal cap_shift : integer range -7 to 15 := 0;
  signal cap_ret : t_state := N_INIT;
  signal limit_s : std_logic_vector(1 downto 0) := "11";
  signal range_failed : std_logic := '0';
  signal range_end, grant_next : unsigned(32 downto 0) := (others => '0');
  attribute ASYNC_REG of limit_s : signal is "TRUE";
  signal op_addr     : unsigned(31 downto 0) := (others => '0');
  signal op_granted  : unsigned(15 downto 0) := (others => '0');  -- blocks allowed
  signal op_closed   : std_logic := '1';     -- no more grants will come
  signal op_done     : unsigned(15 downto 0) := (others => '0');  -- blocks finished
  signal op_multi    : std_logic := '0';     -- CMD18/CMD25 in progress
  signal op_try      : natural range 0 to 3 := 0;
  signal stat_read_retries, stat_stop_retries : unsigned(15 downto 0) := (others => '0');
  signal stat_read_crc, stat_read_timeout, stat_read_cmd : unsigned(15 downto 0) := (others => '0');
  signal stat_read_fail, stat_stop_fail : unsigned(15 downto 0) := (others => '0');
  signal op_verify   : std_logic := '0';     -- the test read at the end of init
  signal op_reps     : unsigned(7 downto 0) := (others => '0');   -- probe reads left
  signal op_stop12   : std_logic := '0';     -- CMD12 after the last write block

  -- command machine (native)
  signal c_go        : std_logic := '0';
  signal c_frame     : std_logic_vector(47 downto 0) := (others => '1');
  signal c_arg       : std_logic_vector(31 downto 0) := (others => '0');
  signal c_resp      : t_resp := R_NONE;
  signal c_idx       : natural range 0 to 63 := 0;
  signal c_act       : std_logic := '0';
  signal c_done      : std_logic := '0';
  signal c_ok        : std_logic := '0';
  signal c_n         : unsigned(7 downto 0) := (others => '0');
  signal c_phase     : natural range 0 to 3 := 0;
  signal c_end       : unsigned(15 downto 0) := (others => '0');   -- tag of the end bit
  signal c_earliest  : unsigned(15 downto 0) := (others => '0');   -- first tag for a command
  signal r_sr        : std_logic_vector(47 downto 0) := (others => '0');
  signal r_long      : std_logic_vector(127 downto 0) := (others => '0');
  signal r2_header_ok : std_logic := '0';
  signal r_crc       : std_logic_vector(6 downto 0) := (others => '0');

  -- data receiver (native)
  signal d_arm       : std_logic := '0';     -- scan for a start bit after d_after
  signal d_after     : unsigned(15 downto 0) := (others => '0');
  signal d_act       : std_logic := '0';     -- inside a block
  signal d_phase     : natural range 0 to 2 := 0;
  signal d_small     : std_logic := '0';     -- 64-byte block (CMD6 status)
  signal d_discard   : std_logic := '0';     -- do not hand the data out
  signal d_idx       : unsigned(9 downto 0) := (others => '0');   -- nibble / byte
  signal d_hi        : std_logic_vector(3 downto 0) := (others => '0');
  signal d_crc       : std_logic_vector(63 downto 0) := (others => '0');
  signal d_crcrx     : std_logic_vector(63 downto 0) := (others => '0');
  signal d_crcn      : natural range 0 to 15 := 0;
  signal d_start     : std_logic := '0';     -- pulse: a start bit (d_start_tag)
  signal d_start_tag : unsigned(15 downto 0) := (others => '0');
  signal d_done      : std_logic := '0';     -- pulse: a block ended
  signal d_ok        : std_logic := '0';
  signal d_end_tag   : unsigned(15 downto 0) := (others => '0');
  signal hs_byte     : std_logic_vector(7 downto 0) := (others => '0');  -- CMD6 status byte 16
  signal rd_next_ok  : std_logic := '0';     -- block op_done+1 may follow op_done
  -- block op_done is the last of a closed read (registered: the 16-bit
  -- compare is not in front of the state logic; op_done changes once a block,
  -- and a close seen a cycle late is caught between blocks)
  signal rd_last     : std_logic := '0';
  -- the sample tagged n carries the card's bit of cycle n + lag: the sample
  -- point is lag whole SD clocks late (worked out at every clock change)
  signal lag         : unsigned(4 downto 0) := (others => '0');
  signal lag_acc     : unsigned(9 downto 0) := (others => '0');

  -- data transmitter (both modes)
  signal w_seq       : std_logic := '0';     -- fetch request (toggle)
  signal w_blk       : unsigned(15 downto 0) := (others => '0');
  signal w_reqd      : std_logic := '0';     -- this block's data was requested
  signal w_under     : std_logic := '0';     -- FIFO ran dry: send a bad CRC
  signal w_avail     : unsigned(5 downto 0);
  signal w_ready     : std_logic;            -- head is of this fetch, enough queued
  signal t_idx       : unsigned(10 downto 0) := (others => '0');
  signal t_byte      : std_logic_vector(7 downto 0) := (others => '0');
  signal t_crc       : std_logic_vector(63 downto 0) := (others => '0');
  signal t_end       : unsigned(15 downto 0) := (others => '0');
  signal w_stat      : std_logic_vector(3 downto 0) := (others => '0');
  signal w_n         : natural range 0 to 7 := 0;

  -- busy (DAT0) detection
  signal b_after     : unsigned(15 downto 0) := (others => '0');
  signal b_n         : natural range 0 to 31 := 0;

  -- SPI byte machinery
  signal sp_tx_next  : std_logic_vector(7 downto 0) := x"FF";
  signal sp_cs_next  : std_logic := '1';
  signal sp_txsr     : std_logic_vector(7 downto 0) := x"FF";
  signal sp_ld       : std_logic := '0';     -- pulse: byte sp_ld_n went out
  signal sp_ld_n     : unsigned(12 downto 0) := (others => '0');
  signal sp_rxsr     : std_logic_vector(7 downto 0) := x"FF";
  signal sp_new      : std_logic := '0';     -- pulse: byte sp_byte (number sp_bn) in
  signal sp_byte     : std_logic_vector(7 downto 0) := x"FF";
  signal sp_bn       : unsigned(12 downto 0) := (others => '0');
  signal sp_cmd_end  : unsigned(12 downto 0) := (others => '0');
  signal sp_r1       : std_logic_vector(7 downto 0) := x"FF";
  signal sp_ext      : std_logic_vector(31 downto 0) := (others => '0');
  signal sp_n        : natural range 0 to 15 := 0;
  signal sp_cnt      : natural range 0 to 7 := 0;
  signal sp_tok_bn   : unsigned(12 downto 0) := (others => '0');
  signal sp_ok       : std_logic := '0';

begin

  ------------------------------------------------------------------------------
  -- host side
  ------------------------------------------------------------------------------

  hs_ack      <= st_host(0);
  card_ready  <= st_host(1);
  hs_busy     <= st_host(2);
  error       <= st_host(3);
  err_code    <= unsigned(st_host(11 downto 4));
  native_mode <= st_host(12);
  high_speed  <= st_host(13);
  sdhc        <= st_host(14);
  clk_setting <= unsigned(st_host(31 downto 16));
  probe_pass  <= unsigned(st_host(39 downto 32));
  probe_fail  <= unsigned(st_host(47 downto 40));
  blocks_done <= unsigned(st_host(63 downto 48));
  diag_stats  <= unsigned(st_host(215 downto 88));
  last_sector <= unsigned(st_host(247 downto 216));
  capacity_valid <= st_host(248);
  hs_wait     <= st_host(64);
  hs_wseq     <= st_host(65);
  hs_wblk     <= unsigned(st_host(81 downto 66));

  h_rpending <= '1' when gray2bin(rf_wpg_s1) /= rf_rp else '0';
  cmd_ready  <= '1' when h_req = hs_ack else '0';
  busy       <= hs_busy or h_rpending or (h_req xor hs_ack);
  waiting    <= hs_wait and not h_rpending;

  rd_valid  <= h_rv;
  rd_data   <= h_rdata;
  rd_offset <= h_roff;
  rd_block  <= h_rblk;
  rd_good   <= h_rgood;
  rd_bad    <= h_rbad;

  wr_fetch  <= h_wfetch;
  wr_offset <= h_woff;
  wr_block  <= h_wblk;

  host : process (cpuclock)
    variable e : std_logic_vector(9 downto 0);
  begin
    if rising_edge(cpuclock) then
      -- commands
      if cmd_valid = '1' and h_req = hs_ack then
        h_code  <= cmd_code;
        h_addr  <= cmd_addr;
        h_count <= cmd_count;
        h_arg   <= cmd_arg;
        h_req   <= not h_req;
        if cmd_code = C_READ or cmd_code = C_INFO then
          h_rblk <= (others => '0');
        end if;
      end if;

      -- status capture: the engine holds st_pub stable until we acknowledge
      pub_req_s <= pub_req_s(1 downto 0) & pub_req;
      if pub_req_s(2) /= pub_ack then
        st_host <= st_pub;
        pub_ack <= pub_req_s(2);
      end if;

      -- read stream: one FIFO entry per cycle
      rf_wpg_s0 <= rf_wpg;
      rf_wpg_s1 <= rf_wpg_s0;
      h_rv    <= '0';
      h_rgood <= '0';
      h_rbad  <= '0';
      if h_rgood = '1' then
        h_rblk <= h_rblk + 1;
      end if;
      if h_rpending = '1' then
        e := rfifo(to_integer(rf_rp(4 downto 0)));
        rf_rp <= rf_rp + 1;
        if e(9) = '0' then
          h_rv    <= '1';
          h_rdata <= unsigned(e(7 downto 0));
          h_roff  <= h_rnext;
          h_rnext <= h_rnext + 1;
        else
          h_rgood <= not e(8);
          h_rbad  <= e(8);
          h_rnext <= (others => '0');
        end if;
      end if;
      rf_rpg <= bin2gray(rf_rp);

      -- write fetch: a new request (sequence bit) starts again at offset 0;
      -- at most 28 bytes are fetched ahead of the engine
      wf_rpg_s0 <= wf_rpg;
      wf_rpg_s1 <= wf_rpg_s0;
      h_wfetch  <= '0';
      if hs_wseq /= h_wseq then
        h_wseq  <= hs_wseq;
        h_wact  <= '1';
        h_wblk  <= hs_wblk;
        h_wnext <= (others => '0');
      elsif h_wact = '1' and h_wip - gray2bin(wf_rpg_s1) < 28 then
        h_wfetch <= '1';
        h_woff   <= h_wnext;
        h_wnext  <= h_wnext + 1;
        h_wip    <= h_wip + 1;
        if h_wnext = 511 then
          h_wact <= '0';
        end if;
      end if;
      -- the byte comes G_WR_LAT cycles after the fetch strobe
      h_wdly  <= h_wdly(G_WR_LAT - 1 downto 0) & h_wfetch;
      h_wsdly <= h_wsdly(G_WR_LAT - 1 downto 0) & h_wseq;
      if h_wdly(G_WR_LAT - 1) = '1' then
        wfifo(to_integer(wf_wp(4 downto 0))) <= h_wsdly(G_WR_LAT - 1) & std_logic_vector(wr_data);
        wf_wp <= wf_wp + 1;
      end if;
      wf_wpg <= bin2gray(wf_wp);
    end if;
  end process host;

  ------------------------------------------------------------------------------
  -- status publishing (clock162): copy the live status whenever the host has
  -- taken the previous copy
  ------------------------------------------------------------------------------

  st_live(0)            <= e_ack;
  st_live(1)            <= ready;
  st_live(2)            <= e_busy;
  st_live(3)            <= e_error;
  st_live(11 downto 4)  <= std_logic_vector(e_err);
  st_live(12)           <= mode_native;
  st_live(13)           <= hs;
  st_live(14)           <= hc;
  st_live(15)           <= '0';
  st_live(31 downto 16) <= std_logic_vector(cur_set);
  st_live(39 downto 32) <= std_logic_vector(e_pass);
  st_live(47 downto 40) <= std_logic_vector(e_fail);
  st_live(63 downto 48) <= std_logic_vector(op_done);
  st_live(64)           <= e_wait;
  st_live(65)           <= w_seq;
  st_live(81 downto 66) <= std_logic_vector(w_blk);
  st_live(87 downto 82) <= (others => '0');
  st_live(215 downto 88) <= std_logic_vector(cur_set & stat_stop_fail & stat_read_fail
    & stat_read_cmd & stat_read_timeout & stat_read_crc & stat_stop_retries & stat_read_retries);
  st_live(247 downto 216) <= std_logic_vector(cap_last);
  st_live(248) <= cap_known;

  publish : process (clock162)
  begin
    if rising_edge(clock162) then
      limit_s <= limit_s(0) & limit_enable;
      pub_ack_s <= pub_ack_s(0) & pub_ack;
      if pub_ack_s(1) = pub_req then
        st_pub  <= st_live;
        pub_req <= not pub_req;
      end if;
    end if;
  end process publish;

  ------------------------------------------------------------------------------
  -- engine side of the FIFOs
  ------------------------------------------------------------------------------

  wf_head <= wfifo(to_integer(wf_rp(4 downto 0)));
  w_avail <= wf_wp_e - wf_rp;
  w_ready <= '1' when wf_head(8) = w_seq and w_avail >= WPF else '0';

  fifos : process (clock162)
  begin
    if rising_edge(clock162) then
      if rf_we = '1' then
        rfifo(to_integer(rf_wp(4 downto 0))) <= rf_din;
        rf_wp <= rf_wp + 1;
      end if;
      rf_wpg    <= bin2gray(rf_wp);
      rf_rpg_s0 <= rf_rpg;
      rf_rpg_s1 <= rf_rpg_s0;
      if gray2bin(rf_rpg_s1) = rf_wp and rf_we = '0' then
        rf_empty_e <= '1';
      else
        rf_empty_e <= '0';
      end if;
      if rf_wp - gray2bin(rf_rpg_s1) < 23 then
        rf_room <= '1';
      else
        rf_room <= '0';
      end if;
      wf_wpg_s0 <= wf_wpg;
      wf_wpg_s1 <= wf_wpg_s0;
      wf_wp_e   <= gray2bin(wf_wpg_s1);
      wf_rpg    <= bin2gray(wf_rp);
    end if;
  end process fifos;

  ------------------------------------------------------------------------------
  -- SD clock generator
  --
  -- Every clock162 cycle it works out the two half cycles of the NEXT cycle
  -- (cg_d1, cg_d2: the ODDR takes them at the next edge).  Half h of a period
  -- (0 .. P-1) is low for h < cg_low; the falling edge (a new SD cycle) is at
  -- h = 0, the rising edge at h = cg_low.  At h = 0 the clock only goes on
  -- when cg_allow is set, otherwise it freezes high, ready to start again with
  -- a falling edge.
  ------------------------------------------------------------------------------

  cg_allow <= ((run and not (stop_en and at_stop)) or (not mode_native and not byte_end))
              and not cg_clr;

  clkgen : process (clock162)
    variable f0, f1, r0, r1 : std_logic;
    variable o1, o2 : std_logic;
    variable x, y   : unsigned(9 downto 0);
    variable h2, h3 : unsigned(9 downto 0);
  begin
    if rising_edge(clock162) then
      -- cg_ph is the next half (h0), cg_ph1 = h0 + 1 mod P (h1)
      f0 := '0'; f1 := '0'; r0 := '0'; r1 := '0';
      o1 := '1'; o2 := '1';
      x := cg_ph1 + 1;
      y := cg_ph1 + 2;
      if x = cg_p then h2 := (others => '0'); else h2 := x; end if;
      if y = cg_p then h3 := (others => '0');
      elsif y = cg_p + 1 then h3 := to_unsigned(1, 10);
      else h3 := y; end if;
      if (cg_frz = '1' or cg_ph = 0) and cg_allow = '0' then
        cg_frz <= '1';
        cg_ph  <= (others => '0');
        cg_ph1 <= to_unsigned(1, 10);
      else
        if cg_ph < cg_low then o1 := '0'; end if;
        if cg_ph = 0 then f0 := '1'; end if;
        if cg_ph = cg_low then r0 := '1'; end if;
        if cg_ph1 = 0 and cg_allow = '0' then
          cg_frz <= '1';
          cg_ph  <= (others => '0');
          cg_ph1 <= to_unsigned(1, 10);
        else
          if cg_ph1 < cg_low then o2 := '0'; end if;
          if cg_ph1 = 0 then f1 := '1'; end if;
          if cg_ph1 = cg_low then r1 := '1'; end if;
          cg_ph  <= h2;
          cg_ph1 <= h3;
          cg_frz <= '0';
        end if;
      end if;
      cg_d1    <= o1;
      cg_d2    <= o2;
      fall0_r  <= f0;
      fall1_r  <= f1;
      fall1_rr <= fall1_r;
      rise0_r  <= r0;
      rise1_r  <= r1;

      -- the rising edge count, and the stop / byte-boundary flags for it (a
      -- falling edge can follow a rising one in the very next cycle, so the
      -- flags are worked out for the count as it will be)
      stop_m1 <= stop_at - 1;
      if cg_clr = '1' then
        rcnt     <= (others => '0');
        at_stop  <= '0';
        byte_end <= '1';
      elsif r0 = '1' or r1 = '1' then
        rcnt <= rcnt + 1;
        if rcnt = stop_m1 then at_stop <= '1'; else at_stop <= '0'; end if;
        if rcnt(2 downto 0) = "111" then byte_end <= '1'; else byte_end <= '0'; end if;
      else
        if rcnt = stop_at then at_stop <= '1'; else at_stop <= '0'; end if;
      end if;
    end if;
  end process clkgen;

  ------------------------------------------------------------------------------
  -- output stage: CMD/DAT change with the falling edge (the first clock162
  -- edge at or after it).  tick marks the cycle after such an edge: ttag is
  -- then the tag of the SD cycle that just started, and the engine decides the
  -- bits of cycle ttag+1 (cmd_nx, dat_nx).
  ------------------------------------------------------------------------------

  load_en <= fall0_r or fall1_rr;

  outstage : process (clock162)
  begin
    if rising_edge(clock162) then
      tick <= load_en;
      if cg_clr = '1' then
        ttag <= (others => '0');
      elsif load_en = '1' then
        ttag <= ttag + 1;
      end if;
      if load_en = '1' then
        if slot = '0' then
          cmd_q(0) <= cmd_nx;  cmd_t_q(0) <= not cmd_oe_nx;
          dat_q(3 downto 0) <= dat_nx;  dat_t_q(3 downto 0) <= not dat_oe_nx;
          cmd_q(1) <= '1';     cmd_t_q(1) <= '1';
          dat_q(7 downto 4) <= "1111";  dat_t_q(7 downto 4) <= "1111";
        else
          cmd_q(1) <= cmd_nx;  cmd_t_q(1) <= not cmd_oe_nx;
          dat_q(7 downto 4) <= dat_nx;  dat_t_q(7 downto 4) <= not dat_oe_nx;
          cmd_q(0) <= '1';     cmd_t_q(0) <= '1';
          dat_q(3 downto 0) <= "1111";  dat_t_q(3 downto 0) <= "1111";
        end if;
      end if;
    end if;
  end process outstage;

  sd_cmd_o  <= cmd_q;
  -- (the enables are kept inverted, as the IOBUF's T, so that the registers
  -- go into the IOBs: pin <= o when oe = '1' else 'Z' folds the inversion)
  sd_cmd_oe <= not cmd_t_q;
  sd_dat_o  <= dat_q;
  sd_dat_oe <= not dat_t_q;

  clk_d1(0) <= cg_d1 when slot = '0' else '1';
  clk_d2(0) <= cg_d2 when slot = '0' else '1';
  clk_d1(1) <= cg_d1 when slot = '1' else '1';
  clk_d2(1) <= cg_d2 when slot = '1' else '1';

  in_pins <= sd_cmd_i(1) & sd_dat_i(7 downto 4) & sd_cmd_i(0) & sd_dat_i(3 downto 0);

  xilinx_io : if G_XILINX generate
    clkout : for s in 0 to 1 generate
      owned : if G_FIXED_SLOT = -1 or G_FIXED_SLOT = s generate
      oddr_clk : ODDR
        generic map (DDR_CLK_EDGE => "SAME_EDGE", INIT => '1', SRTYPE => "SYNC")
        port map (Q => sd_clk(s), C => clock162, CE => '1',
                  D1 => clk_d1(s), D2 => clk_d2(s), R => '0', S => '0');
      end generate;
      unused_slot : if G_FIXED_SLOT /= -1 and G_FIXED_SLOT /= s generate
        sd_clk(s) <= '1';
      end generate;
    end generate;
    inputs : for i in 0 to 9 generate
      owned : if G_FIXED_SLOT = -1 or G_FIXED_SLOT = i / 5 generate
      iddr_in : IDDR
        generic map (DDR_CLK_EDGE => "SAME_EDGE_PIPELINED", INIT_Q1 => '1',
                     INIT_Q2 => '1', SRTYPE => "SYNC")
        port map (Q1 => in_q1(i), Q2 => in_q2(i), C => clock162, CE => '1',
                  D => in_pins(i), R => '0', S => '0');
      end generate;
      unused_slot : if G_FIXED_SLOT /= -1 and G_FIXED_SLOT /= i / 5 generate
        in_q1(i) <= '1';
        in_q2(i) <= '1';
      end generate;
    end generate;
  end generate;

  behavioural_io : if not G_XILINX generate
    signal ck_d2_held : std_logic_vector(1 downto 0) := "11";
    signal ck_q       : std_logic_vector(1 downto 0) := "11";
    signal pre1, pre2 : std_logic_vector(9 downto 0) := (others => '1');
    signal q1r, q2r   : std_logic_vector(9 downto 0) := (others => '1');
  begin
    oddr_model : process (clock162)
    begin
      if rising_edge(clock162) then
        ck_q       <= clk_d1;
        ck_d2_held <= clk_d2;
      elsif falling_edge(clock162) then
        ck_q <= ck_d2_held;
      end if;
    end process;
    sd_clk <= ck_q;

    iddr_model : process (clock162)
    begin
      if rising_edge(clock162) then
        pre1 <= in_pins;
        q1r  <= pre1;
        q2r  <= pre2;
      elsif falling_edge(clock162) then
        pre2 <= in_pins;
      end if;
    end process;
    in_q1 <= q1r;
    in_q2 <= q2r;
  end generate;

  ------------------------------------------------------------------------------
  -- sampler.  In cycle c, mh(k) says whether half cycle 2c+1-k starts with a
  -- rising edge on the pin, and the IDDR holds half cycles 2c-2 (q1) and 2c-1
  -- (q2).  The sample D half cycles after a rising edge is q2 if mh(D+2) and
  -- q1 if mh(D+3).
  ------------------------------------------------------------------------------

  sampler : process (clock162)
    variable d : natural range 0 to 31;
  begin
    if rising_edge(clock162) then
      mh <= rise1_r & rise0_r & mh(0 to MH_LEN-3);
      d  := to_integer(cg_d);
      sel1 <= mh(d + 3);
      sel2 <= mh(d + 2);
      if slot = '0' then
        s_q1 <= in_q1(4 downto 0);
        s_q2 <= in_q2(4 downto 0);
      else
        s_q1 <= in_q1(9 downto 5);
        s_q2 <= in_q2(9 downto 5);
      end if;

      rx_v <= '0';
      if sel1 = '1' then
        rx_v   <= '1';
        rx_cmd <= s_q1(4);
        rx_dat <= s_q1(3 downto 0);
      elsif sel2 = '1' then
        rx_v   <= '1';
        rx_cmd <= s_q2(4);
        rx_dat <= s_q2(3 downto 0);
      end if;
      if cg_clr = '1' then
        rx_tag <= (others => '0');
      elsif sel1 = '1' or sel2 = '1' then
        rx_tag <= rx_tag + 1;
      end if;
    end if;
  end process sampler;

  ------------------------------------------------------------------------------
  -- the engine
  ------------------------------------------------------------------------------

  engine : process (clock162)

    -- start a command (native: the command machine, SPI: S_CMD); go on at ret
    procedure do_cmd(idx : natural; arg : std_logic_vector(31 downto 0);
                     resp : t_resp; ret : t_state) is
    begin
      c_arg   <= arg;
      c_idx   <= idx;
      c_resp  <= resp;
      c_go    <= '1';
      ret_st  <= ret;
      st      <= S_CMD_WAIT;
    end procedure;

    -- change the clock: stop it, let the samples drain, apply new_set, reset
    -- the tags, go on at ret
    procedure resync(ret : t_state) is
    begin
      resync_ret <= ret;
      cnt        <= (others => '0');
      st         <= S_RESYNC;
    end procedure;

    procedure count_read_error(code : unsigned(7 downto 0)) is
    begin
      if op = OP_READ and op_verify = '0' then
        case code is
          when ERR_RD_CRC => stat_read_crc <= stat_read_crc + 1;
          when ERR_RD_TMO => stat_read_timeout <= stat_read_timeout + 1;
          when ERR_CMD => stat_read_cmd <= stat_read_cmd + 1;
          when others => null;
        end case;
      end if;
    end procedure;

    -- a transfer went wrong: end a multi-block one with CMD12 first
    procedure failed(code : unsigned(7 downto 0)) is
    begin
      e_err <= code;
      count_read_error(code);
      d_arm <= '0';
      if mode_native = '1' and (op_multi = '1' or
          (op = OP_READ and op_verify = '0')) then
        st <= S_ABORT;
      else
        st <= S_FAIL;
      end if;
    end procedure;

    -- A failed stop must not be followed by another read into the old data
    -- stream. Retry CMD12/status a bounded number of times, then require
    -- explicit recovery or init before accepting another read.
    procedure close_failed is
    begin
      if close_tries < 2 then
        stat_stop_retries <= stat_stop_retries + 1;
        close_tries <= close_tries + 1;
        if close_tries = 1 and cur_set /= SET_DS and cur_set /= SET_HS then
          if hs = '1' then
            cur_set <= SET_HS; new_set <= SET_HS;
          else
            cur_set <= SET_DS; new_set <= SET_DS;
          end if;
          resync(S_CLOSE);
        else
          st <= S_CLOSE;
        end if;
      else
        stat_stop_fail <= stat_stop_fail + 1;
        if op = OP_READ then stat_read_fail <= stat_read_fail + 1; end if;
        ready   <= '0';
        e_error <= '1';
        e_err   <= ERR_CMD;
        e_wait  <= '0';
        op      <= OP_NONE;
        cnt     <= (others => '0');
        st      <= S_TAIL;
      end if;
    end procedure;

    -- push a read FIFO entry
    procedure rpush(kind : std_logic_vector(1 downto 0); v : std_logic_vector(7 downto 0)) is
    begin
      rf_we  <= '1';
      rf_din <= kind & v;
    end procedure;

    -- the data receiver is stopped: if a block was half way through, tell the
    -- host side (its byte offsets start again with the next block)
    procedure cut_block is
    begin
      if d_act = '1' and d_discard = '0' and d_small = '0' then
        rpush("11", x"00");
      end if;
      d_act <= '0';
    end procedure;

    function card_addr(a : unsigned(31 downto 0); k : unsigned(15 downto 0);
                       h : std_logic) return std_logic_vector is
      variable b : unsigned(31 downto 0);
    begin
      b := a + resize(k, 32);
      if h = '1' then
        return std_logic_vector(b);
      else
        return std_logic_vector(b(22 downto 0) & "000000000");
      end if;
    end function;

    function r1_bad(r : std_logic_vector(47 downto 0)) return boolean is
    begin
      return (r(39 downto 8) and R1_ERRMASK) /= x"00000000";
    end function;

    variable nib     : std_logic_vector(3 downto 0);
    variable crc     : std_logic_vector(63 downto 0);
    variable b       : std_logic_vector(7 downto 0);
    variable next_ok : boolean;
    variable take    : boolean;
    variable granting : boolean;
    variable last_nib : unsigned(9 downto 0);

  begin
    if rising_edge(clock162) then

      -- the sample stream, one cycle later, with the comparisons of its tag
      -- already worked out (registers in front of the state logic)
      rxd_v   <= rx_v;
      rxd_cmd <= rx_cmd;
      rxd_dat <= rx_dat;
      rxd_tag <= rx_tag;
      rf_cend   <= boolean_to_sl(later(rx_tag, c_end));
      rf_c80    <= boolean_to_sl(rx_tag - c_end > 80);
      -- A card may take much longer than half the 16-bit tag range to
      -- produce data (32768 clocks is only 0.81 ms at normal high speed).
      -- Once the samples have crossed this boundary, keep accepting them
      -- until the next d_after assignment explicitly rearms the guard.
      rf_dafter <= rf_dafter or boolean_to_sl(rx_v = '1' and later(rx_tag, d_after));
      rf_bafter <= boolean_to_sl(later(rx_tag, b_after));
      rf_tend   <= boolean_to_sl(later(rx_tag, t_end));
      rf_t16    <= boolean_to_sl(rx_tag - t_end > 16);
      -- and the start of a command / of a write block: far enough after the
      -- last one (one SD clock more than needed: it is a cycle late)
      cmd_gap_ok <= cmd_gap_ok or boolean_to_sl(not later(c_earliest, ttag + 1));
      wr_gap_ok  <= boolean_to_sl(later(ttag + 1, c_end + 1));

      -- (A comparison flag above was worked out with the threshold of this
      -- cycle; where the state logic changes a threshold it also clears its
      -- flags for one cycle.  The samples in flight then are all of earlier
      -- cycles, so "not later / no timeout" is right for them.)

      -- one-cycle pulses
      c_go    <= '0';
      c_done  <= '0';
      d_start <= '0';
      d_done  <= '0';
      rf_we   <= '0';
      sp_ld   <= '0';
      sp_new  <= '0';
      cg_clr  <= '0';
      -- An eight-byte SCR can finish before its R1 response. Retain the
      -- data verdict independently of the command machine's progress.
      if d_done = '1' and op = OP_INFO then
        info_data_done <= '1'; info_data_ok <= d_ok;
      end if;

      e_req_s <= e_req_s(0) & h_req;

      -- a new command: take a copy into this clock domain first (and work out
      -- the comparisons on it here), handle it from the next cycle on
      if e_req_s(1) /= e_seen and cmd_pend = '0' then
        e_seen   <= e_req_s(1);
        cmd_pend <= '1';
        e_code   <= h_code;
        e_addr   <= h_addr;
        e_count  <= h_count;
        e_arg    <= h_arg;
        if h_count = 0 then e_cnt0 <= '1'; else e_cnt0 <= '0'; end if;
        if h_arg = 0 then e_argz <= '1'; else e_argz <= '0'; end if;
        if h_arg(6 downto 0) < 4 then e_lt4 <= '1'; else e_lt4 <= '0'; end if;
        if h_arg(6 downto 0) < 13 then e_lt13 <= '1'; else e_lt13 <= '0'; end if;
      end if;

      -- the command frame, from registers (c_go is the cycle after do_cmd)
      if c_go = '1' then
        c_frame <= cmd_frame(c_idx, c_arg);
      end if;

      if op_done + 1 < op_granted and op_multi = '1' and op = OP_READ and op_verify = '0' then
        rd_next_ok <= '1';
      else
        rd_next_ok <= '0';
      end if;
      if op_done + 1 = op_granted and op_closed = '1' then
        rd_last <= '1';
      else
        rd_last <= '0';
      end if;

      -- timeout: tmo_z says tmo has reached 0 (a register, so that the 28-bit
      -- compare is not in front of the state logic)
      if tmo /= 0 then
        tmo <= tmo - 1;
        if tmo = 1 then
          tmo_z <= '1';
        end if;
      end if;

      -- write FIFO: drop entries of an earlier fetch
      if wf_head(8) /= w_seq and wf_rp /= wf_wp_e then
        wf_rp <= wf_rp + 1;
      end if;

      --------------------------------------------------------------------------
      -- command machine (native)
      --------------------------------------------------------------------------
      if mode_native = '1' then
        if c_go = '1' then
          c_act   <= '1';
          c_phase <= 0;
          c_n     <= (others => '0');
          c_ok    <= '0';
        end if;
        if c_act = '1' then
          case c_phase is
            when 0 =>
              -- send the frame, not before c_earliest (Nrc, Ncc)
              if tick = '1' and (c_n /= 0 or cmd_gap_ok = '1') then
                cmd_oe_nx <= '1';
                cmd_nx    <= c_frame(47);
                c_frame   <= c_frame(46 downto 0) & '1';
                if c_n = 47 then
                  c_end <= ttag + 1;  rf_cend <= '0'; rf_c80 <= '0'; wr_gap_ok <= '0';
                  c_n   <= (others => '0');
                  if c_resp = R_NONE then
                    c_phase <= 2;
                  else
                    c_phase <= 1;
                  end if;
                else
                  c_n <= c_n + 1;
                end if;
              end if;
            when 1 =>
              -- release CMD after the end bit, look for the response
              if tick = '1' then
                cmd_oe_nx <= '0';
                cmd_nx    <= '1';
              end if;
              if rxd_v = '1' and rf_cend = '1' then
                if c_n = 0 then
                  if rxd_cmd = '0' then
                    c_n   <= to_unsigned(1, 8);
                    r_sr  <= (others => '0');
                    r2_header_ok <= '1';
                    if c_resp = R_R2 then r_crc <= (others => '0');
                    else r_crc <= crc7_bit("0000000", '0'); end if;
                  elsif rf_c80 = '1' then
                    -- no response (Ncr is at most 64)
                    c_ok    <= '0';
                    c_end   <= rxd_tag;  rf_cend <= '0'; rf_c80 <= '0'; wr_gap_ok <= '0';
                    c_phase <= 3;
                  end if;
                else
                  r_sr <= r_sr(46 downto 0) & rxd_cmd;
                  if c_resp = R_R2 then
                    r_long <= r_long(126 downto 0) & rxd_cmd;
                    if (c_n = 1 and rxd_cmd /= '0') or
                      (c_n >= 2 and c_n < 8 and rxd_cmd /= '1') then r2_header_ok <= '0'; end if;
                    -- R2 CRC covers the register, excluding its CRC/end and
                    -- the response header. Keep the legacy init CID path.
                    if c_n >= 8 and c_n < 128 then
                      r_crc <= crc7_bit(r_crc, rxd_cmd);
                    end if;
                  elsif c_n < 40 then
                    r_crc <= crc7_bit(r_crc, rxd_cmd);
                  end if;
                  if (c_resp = R_R2 and c_n = 135) or (c_resp /= R_R2 and c_n = 47) then
                    -- the end bit (r_sr still holds frame bits 46..1)
                    c_ok <= '1';
                    if c_resp = R_R2 and (op = OP_INFO or c_idx = 9) then
                      if r2_header_ok = '0' or r_long(6 downto 0) /= r_crc
                        or rxd_cmd /= '1' then c_ok <= '0'; end if;
                    elsif c_resp = R_R1 or c_resp = R_R1B or c_resp = R_R7 then
                      if r_sr(6 downto 0) /= r_crc or
                        r_sr(44 downto 39) /= std_logic_vector(to_unsigned(c_idx, 6)) then
                        c_ok <= '0';
                      end if;
                    end if;
                    c_end   <= rxd_tag;  rf_cend <= '0'; rf_c80 <= '0'; wr_gap_ok <= '0';
                    c_phase <= 3;
                  else
                    c_n <= c_n + 1;
                  end if;
                end if;
              end if;
            when 2 =>
              -- no response: release the line
              if tick = '1' then
                cmd_oe_nx <= '0';
                cmd_nx    <= '1';
                c_ok      <= '1';
                c_phase   <= 3;
              end if;
            when others =>
              c_act      <= '0';
              c_done     <= '1';
              c_earliest <= c_end + 8;  cmd_gap_ok <= '0';
          end case;
        end if;
      end if;

      --------------------------------------------------------------------------
      -- data receiver (native, 4 bits). Sector blocks, 64-byte status or
      -- 8-byte SCR. Data goes to the read FIFO as it comes; the verdict
      -- follows the block.
      --------------------------------------------------------------------------
      if d_small = '1' then
        if op = OP_INFO and info_kind = 2 then last_nib := to_unsigned(15, 10);
        else last_nib := to_unsigned(127, 10); end if;
      else
        last_nib := to_unsigned(1023, 10);
      end if;
      if mode_native = '1' and rxd_v = '1' then
        if d_act = '0' then
          if d_arm = '1' and rf_dafter = '1' and rxd_dat(0) = '0' then
            d_act       <= '1';
            d_arm       <= '0';
            d_phase     <= 0;
            d_idx       <= (others => '0');
            d_crc       <= (others => '0');
            d_crcn      <= 0;
            d_start     <= '1';
            d_start_tag <= rxd_tag;
            -- stop the clock after the end bit unless the next block may
            -- follow (this can be before the command's response is over)
            if d_small = '0' then
              stop_at <= rxd_tag + 1041 + lag;
              if rd_next_ok = '0' then
                stop_en <= '1';
              end if;
            end if;
          end if;
        else
          case d_phase is
            when 0 =>
              nib := rxd_dat;
              crc := d_crc;
              for l in 0 to 3 loop
                crc(16*l+15 downto 16*l) := crc16_bit(d_crc(16*l+15 downto 16*l), nib(l));
              end loop;
              d_crc <= crc;
              if d_idx(0) = '0' then
                d_hi <= nib;
              else
                b := d_hi & nib;
                if d_small = '1' then
                  if op = OP_INFO then
                    rpush("00", b);
                  elsif d_idx(9 downto 1) = 16 then
                    hs_byte <= b;
                  end if;
                elsif d_discard = '0' then
                  rpush("00", b);
                end if;
              end if;
              d_idx <= d_idx + 1;
              if d_idx = last_nib then
                d_phase <= 1;
              end if;
            when 1 =>
              for l in 0 to 3 loop
                d_crcrx(16*l+15 downto 16*l) <= d_crcrx(16*l+14 downto 16*l) & rxd_dat(l);
              end loop;
              if d_crcn = 15 then
                d_phase <= 2;
              else
                d_crcn <= d_crcn + 1;
              end if;
            when others =>
              -- the end bit
              d_act     <= '0';
              d_done    <= '1';
              d_end_tag <= rxd_tag;
              if d_crcrx = d_crc and rxd_dat = "1111" then
                d_ok <= '1';
                if d_small = '0' and d_discard = '0' then
                  rpush("10", x"00");
                end if;
              else
                d_ok <= '0';
                if d_small = '0' and d_discard = '0' then
                  rpush("11", x"00");
                end if;
              end if;
          end case;
        end if;
      end if;

      --------------------------------------------------------------------------
      -- SPI byte machinery.  Byte k is sent in the cycles tagged 8k+1 .. 8k+8;
      -- the clock only stops after a tag that is a multiple of 8.
      --------------------------------------------------------------------------
      if mode_native = '0' then
        if tick = '1' then
          -- deciding the bit of cycle ttag+1
          if ttag(2 downto 0) = "000" then
            cmd_nx    <= sp_tx_next(7);
            sp_txsr   <= sp_tx_next(6 downto 0) & '1';
            dat_nx(3) <= sp_cs_next;
            sp_ld     <= '1';
            sp_ld_n   <= ttag(15 downto 3);
          else
            cmd_nx  <= sp_txsr(7);
            sp_txsr <= sp_txsr(6 downto 0) & '1';
          end if;
          cmd_oe_nx          <= '1';
          dat_nx(2 downto 0) <= "111";
          dat_oe_nx          <= "1000";
        end if;
        if rxd_v = '1' then
          -- the sample tagged n is bit n + lag of the stream
          sp_rxsr <= sp_rxsr(6 downto 0) & rxd_dat(0);
          if (rxd_tag(2 downto 0) + lag(2 downto 0)) = "000" then
            sp_byte <= sp_rxsr(6 downto 0) & rxd_dat(0);
            sp_bn   <= resize(shift_right(rxd_tag + lag - 1, 3), 13);
            sp_new  <= '1';
          end if;
        end if;
      end if;

      --------------------------------------------------------------------------
      -- the mailbox.  C_MORE / C_STOP are taken in any state, C_INIT aborts
      -- anything, the rest only in S_IDLE.
      --------------------------------------------------------------------------
      take     := false;
      granting := false;
      if cmd_pend = '1' then
        if e_code = C_MORE then
          if op /= OP_NONE and op_closed = '0' then
            if limit_s(1) = '1' and (cap_known = '0' or
              grant_next > resize(cap_last, 33)) then
              op_closed <= '1'; range_failed <= '1';
            else
              op_granted <= op_granted + 1;
              op_closed  <= e_arg(0);
              grant_next <= grant_next + 1;
              granting   := true;
            end if;
          end if;
          e_ack <= e_seen;
          cmd_pend <= '0';
        elsif e_code = C_STOP then
          op_closed <= '1';
          e_ack     <= e_seen;
          cmd_pend <= '0';
        elsif e_code = C_NOP then
          e_ack <= e_seen;
          cmd_pend <= '0';
        elsif e_code = C_INIT then
          take := true;
        elsif st /= S_IDLE then
          e_error <= '1';
          e_err   <= ERR_BUSY;
          e_ack   <= e_seen;
          cmd_pend <= '0';
        else
          take := true;
        end if;
      end if;

      --------------------------------------------------------------------------
      -- main state machine
      --------------------------------------------------------------------------
      case st is

        when S_POWERUP =>
          run <= '0';
          if G_AUTO_INIT then
            tmo    <= to_unsigned(TMO_SETTLE, 28);
            tmo_z    <= '0';
            e_busy <= '1';
            st     <= S_INIT;
          else
            e_busy <= '0';
            st     <= S_IDLE;
          end if;

        ------------------------------------------------------------------------
        -- (re)initialisation: identification clock, then native or SPI
        ------------------------------------------------------------------------
        when S_INIT =>
          run     <= '0';
          stop_en <= '0';
          if tmo_z = '1' and cg_frz = '1' then
            -- reset the tags now: in SPI mode the clock would otherwise run
            -- on to a byte boundary of the old count
            cg_clr  <= '1';
            ready   <= '0';
            hs      <= '0';
            hc      <= '0';
            op      <= OP_NONE;
            cap_known <= '0'; info_init <= '0'; range_failed <= '0';
            cur_set <= SET_DS;
            cg_p    <= to_unsigned(G_INIT_P, 10);
            cg_low  <= to_unsigned((G_INIT_P + 1) / 2, 10);
            cg_d    <= to_unsigned(G_INIT_D, 5);
            cnt     <= (others => '0');
            istep   <= 0;
            tries   <= 0;
            if spi_only = '0' and spi_fb = '0' then
              -- DAT3 high (driven) so that CMD0 leaves the card in SD mode
              mode_native <= '1';
              cmd_nx <= '1'; cmd_oe_nx <= '0';
              dat_nx <= "1111"; dat_oe_nx <= "1000";
              resync_ret <= N_PRE;
            else
              mode_native <= '0';
              sp_tx_next  <= x"FF";
              sp_cs_next  <= '1';
              resync_ret  <= P_PRE;
            end if;
            st <= S_RESYNC2;
          end if;

        -- stop the clock, let the samples drain, apply new_set, reset the tags
        when S_RESYNC =>
          run     <= '0';
          stop_en <= '0';
          if cg_frz = '1' then
            cnt <= cnt + 1;
            if cnt = 15 then
              cnt    <= (others => '0');
              cg_p   <= resize(new_set(6 downto 0), 10);
              cg_low <= resize(shift_right(new_set(6 downto 0) + 1, 1), 10);
              cg_d   <= new_set(12 downto 8);
              st     <= S_RESYNC2;
            end if;
          else
            cnt <= (others => '0');
          end if;

        when S_RESYNC2 =>
          -- lag = floor((D + launch) / P), where the card launches its bits at
          -- the falling edge (default speed, SPI: launch = the low phase) or
          -- at the rising edge (high speed: launch = 0)
          run <= '0';
          cnt <= cnt + 1;
          if cnt = 2 then
            lag <= (others => '0');
            if hs = '1' and mode_native = '1' then
              lag_acc <= resize(cg_d, 10);
            else
              lag_acc <= resize(cg_d, 10) + cg_low;
            end if;
          elsif cnt > 2 and lag_acc >= cg_p then
            lag_acc <= lag_acc - cg_p;
            lag     <= lag + 1;
          end if;
          if cnt = 63 then
            cg_clr     <= '1';
            c_earliest <= (others => '0');  cmd_gap_ok <= '0';
            cnt        <= (others => '0');
            st         <= resync_ret;
          end if;

        ------------------------------------------------------------------------
        -- idle: take commands
        ------------------------------------------------------------------------
        when S_IDLE =>
          run <= '0';
          if rf_empty_e = '1' then
            e_busy <= '0';
          end if;
          if take and e_code /= C_INIT then
            e_ack     <= e_seen;
            cmd_pend <= '0';
            e_error   <= '0';
            e_err     <= ERR_NONE;
            e_pass    <= (others => '0');
            e_fail    <= (others => '0');
            op_done   <= (others => '0');
            op_try    <= 0;
            op_verify <= '0';
            range_failed <= '0';
            op_addr   <= e_addr;
            w_reqd    <= '0';
            if e_cnt0 = '1' then
              op_granted <= to_unsigned(1, 16);
              op_closed  <= '0';
            else
              op_granted <= e_count;
              op_closed  <= '1';
            end if;
            if e_code = C_READ or e_code = C_WRITE or e_code = C_PROBE then
              if ready = '0' then
                e_error <= '1';
                e_err   <= ERR_NOTREADY;
              elsif e_code = C_PROBE and e_lt4 = '1' then
                e_error <= '1';
                e_err   <= ERR_BADCMD;
              elsif e_code = C_PROBE and e_lt13 = '1' and hs = '0' then
                e_error <= '1';
                e_err   <= ERR_NOHS;
              else
                e_busy <= '1';
                if e_code = C_READ then
                  op <= OP_READ;
                  st <= S_RANGE_ADD;
                elsif e_code = C_WRITE then
                  op <= OP_WRITE;
                  st <= S_RANGE_ADD;
                else
                  op         <= OP_PROBE;
                  op_granted <= to_unsigned(1, 16);
                  op_closed  <= '1';
                  if e_cnt0 = '1' then
                    op_reps <= to_unsigned(1, 8);
                  else
                    op_reps <= e_count(7 downto 0);
                  end if;
                  new_set <= e_arg;
                  st <= S_RANGE_ADD;
                end if;
              end if;
            elsif e_code = C_INFO then
              if ready = '0' then
                e_error <= '1'; e_err <= ERR_NOTREADY;
              elsif e_arg > 3 then
                e_error <= '1'; e_err <= ERR_BADCMD;
              else
                op <= OP_INFO;
                op_multi <= '0';
                e_busy <= '1';
                info_kind <= e_arg(1 downto 0);
                if e_arg = 2 then info_len <= to_unsigned(8, 7);
                elsif e_arg = 3 then info_len <= to_unsigned(64, 7);
                else info_len <= to_unsigned(16, 7); end if;
                info_pos <= (others => '0');
                info_init <= '0';
                d_small <= '0'; d_discard <= '0';
                st <= I_START;
              end if;
            elsif e_code = C_CLEAR then
              op <= OP_NONE;
              if mode_native = '1' and rca /= x"0000" then
                e_busy <= '1';
                close_ret <= S_RECOVER;
                close_tries <= 0;
                st <= S_CLOSE;
              elsif ready = '1' then
                -- SPI transfers finish deselected with trailing clocks.
                e_busy <= '1';
                st <= S_FINISH;
              else
                e_error <= '1';
                e_err <= ERR_NOTREADY;
              end if;
            elsif e_code = C_ACCEPT then
              if e_argz = '1' then
                if hs = '1' then
                  new_set <= SET_HS; cur_set <= SET_HS;
                else
                  new_set <= SET_DS; cur_set <= SET_DS;
                end if;
                e_busy <= '1';
                resync(S_FINISH);
              elsif e_lt4 = '1' then
                e_error <= '1';
                e_err   <= ERR_BADCMD;
              elsif e_lt13 = '1' and hs = '0' then
                e_error <= '1';
                e_err   <= ERR_NOHS;
              else
                new_set <= e_arg;
                cur_set <= e_arg;
                e_busy  <= '1';
                resync(S_FINISH);
              end if;
            else
              e_error <= '1';
              e_err   <= ERR_BADCMD;
            end if;
          end if;

        -- issue (or re-issue after an error) the rest of the transfer
        when S_RANGE_ADD =>
          -- Separate the wide add and compare at 162 MHz. C_MORE compares
          -- the registered next grant address instead of adding it inline.
          range_end <= resize(op_addr, 33) + resize(op_granted - 1, 33);
          st <= S_RANGE_CHECK;

        when S_RANGE_CHECK =>
          grant_next <= range_end + 1;
          if limit_s(1) = '1' and (cap_known = '0' or range_end > resize(cap_last, 33)) then
            e_error <= '1';
            if cap_known = '0' then e_err <= ERR_CAPACITY; else e_err <= ERR_RANGE; end if;
            op <= OP_NONE; cnt <= (others => '0'); st <= S_TAIL;
          elsif op = OP_PROBE then resync(S_DISPATCH);
          else st <= S_DISPATCH; end if;

        when S_DISPATCH =>
          run     <= '0';
          stop_en <= '0';
          if op = OP_PROBE then
            if op_reps = 0 then
              op      <= OP_NONE;
              new_set <= cur_set;
              resync(S_FINISH);
            else
              op_done   <= (others => '0');
              op_multi  <= '0';
              d_discard <= '1';
              if mode_native = '1' then st <= N_RD_CMD; else st <= P_RD_CMD; end if;
            end if;
          elsif op_done = op_granted and op_closed = '1' then
            st <= S_FINISH;
          elsif op_done = op_granted then
            -- open-ended: wait for the next grant
            if rf_empty_e = '1' then
              e_wait <= '1';
            end if;
          else
            d_discard <= '0';
            if op_closed = '0' or op_granted - op_done > 1 then
              op_multi <= '1';
            else
              op_multi <= '0';
            end if;
            if op = OP_READ then
              if mode_native = '1' then st <= N_RD_CMD; else st <= P_RD_CMD; end if;
            else
              w_reqd <= '0';
              if mode_native = '1' then st <= N_WR_CMD; else st <= P_WR_CMD; end if;
            end if;
          end if;

        when S_FINISH =>
          if range_failed = '1' then
            e_error <= '1';
            if cap_known = '0' then e_err <= ERR_CAPACITY; else e_err <= ERR_RANGE; end if;
          end if;
          range_failed <= '0';
          op     <= OP_NONE;
          e_wait <= '0';
          cnt    <= (others => '0');
          st     <= S_TAIL;

        -- End a failed native read before resynchronising/retrying it, even
        -- for CMD17: a framing error may have left the card mid-sector.
        when S_ABORT =>
          close_ret   <= S_FAIL;
          close_tries <= 0;
          st          <= S_CLOSE;

        when S_CLOSE =>
          d_arm   <= '0';
          cut_block;
          d_discard <= '1';
          stop_en <= '0';
          run     <= '1';
          do_cmd(12, x"00000000", R_R1B, S_CLOSE_RESP);

        when S_CLOSE_RESP =>
          -- CMD12 is illegal in Transfer state: a failed CMD17 may already
          -- have completed at the card, so no stop response is then normal.
          -- Conversely, an acknowledged stop may leave the card streaming.
          -- In both cases CMD13 must positively prove Transfer/ready.
          do_cmd(13, rca & x"0000", R_R1, S_CLOSE_STATUS);

        when S_CLOSE_STATUS =>
          if c_ok = '1' and not r1_bad(r_sr)
            and r_sr(20 downto 17) = "0100" and r_sr(16) = '1' then
            st <= close_ret;
          else
            close_failed;
          end if;

        when S_RECOVER =>
          -- CMD12/CMD13 proved the existing card session usable; no CMD0,
          -- bus-width change, high-speed switch or reinitialisation needed.
          ready <= '1';
          e_error <= '0';
          e_err <= ERR_NONE;
          st <= S_FINISH;

        -- a transfer failed: retry, slow down, or give up
        when S_FAIL =>
          run     <= '0';
          stop_en <= '0';
          d_arm   <= '0';
          cut_block;
          d_small <= '0';
          if op_verify = '1' then
            -- the test read at the end of the init
            op_verify <= '0';
            if hs = '1' and mode_native = '1' then
              -- once more, at default speed
              hs      <= '0';
              cur_set <= SET_DS;
              new_set <= SET_DS;
              istep   <= 13;
              resync(N_INIT);
            elsif mode_native = '1' then
              spi_fb <= '1';             -- give up on the native bus
              tmo    <= (others => '0');
              tmo_z    <= '1';
              st     <= S_INIT;
            else
              ready   <= '0';
              e_error <= '1';
              e_err   <= ERR_INIT;
              op      <= OP_NONE;
              cnt     <= (others => '0');
              st      <= S_TAIL;
            end if;
          elsif op = OP_PROBE then
            -- the card may still be sending: let it finish first
            e_fail    <= e_fail + 1;
            op_reps   <= op_reps - 1;
            drain_ret <= S_DISPATCH;
            cnt       <= (others => '0');
            st        <= S_DRAIN;
          elsif op_try < 2 then
            if op = OP_READ then stat_read_retries <= stat_read_retries + 1; end if;
            op_try <= op_try + 1;
            if op_try = 1 and cur_set /= SET_DS and cur_set /= SET_HS then
              -- an accepted fast setting failed twice: back to normal
              if hs = '1' then
                cur_set <= SET_HS; new_set <= SET_HS;
              else
                cur_set <= SET_DS; new_set <= SET_DS;
              end if;
            else
              new_set <= cur_set;
            end if;
            e_err  <= ERR_NONE;
            w_reqd <= '0';
            resync(S_DISPATCH);
          else
            if op = OP_READ then stat_read_fail <= stat_read_fail + 1; end if;
            e_error <= '1';
            if e_err = ERR_NONE then
              e_err <= ERR_CMD;
            end if;
            op     <= OP_NONE;
            e_wait <= '0';
            cnt    <= (others => '0');
            st     <= S_TAIL;
          end if;

        -- let the clock run for 2048 cycles (a block the card is still sending)
        when S_DRAIN =>
          run <= '1';
          if tick = '1' then
            cnt <= cnt + 1;
            if cnt = 2047 then
              cnt <= (others => '0');
              st  <= drain_ret;
            end if;
          end if;

        -- some idle clocks after the last command or data, then stop
        when S_TAIL =>
          run     <= '1';
          stop_en <= '0';
          d_arm   <= '0';
          if mode_native = '1' then
            cmd_oe_nx <= '0'; cmd_nx <= '1';
            dat_oe_nx <= "0000"; dat_nx <= "1111";
          else
            sp_tx_next <= x"FF";
            sp_cs_next <= '1';
          end if;
          if tick = '1' then
            cnt <= cnt + 1;
            if cnt = 16 then
              run <= '0';
              st  <= S_IDLE;
            end if;
          end if;

        ------------------------------------------------------------------------
        -- commands
        ------------------------------------------------------------------------
        when S_CMD_WAIT =>
          run <= '1';
          if mode_native = '0' then
            sp_n <= 0;
            st   <= S_CMD;
          elsif c_done = '1' then
            st <= ret_st;
            if c_resp = R_R1B and c_ok = '1' then
              b_after <= c_end;  rf_bafter <= '0';
              b_n     <= 0;
              tmo     <= to_unsigned(TMO_BUSY, 28);
              tmo_z     <= '0';
              st      <= S_BUSY0;
            end if;
          end if;

        -- busy on DAT0: up to 16 cycles for it to go low, then until high
        when S_BUSY0 =>
          run <= '1';
          if rxd_v = '1' and rf_bafter = '1' then
            if rxd_dat(0) = '0' then
              st <= S_BUSY1;
            elsif b_n = 16 then
              c_earliest <= rxd_tag + 2;  cmd_gap_ok <= '0';
              st         <= ret_st;
            else
              b_n <= b_n + 1;
            end if;
          end if;

        when S_BUSY1 =>
          run <= '1';
          if rxd_v = '1' and rxd_dat(0) = '1' then
            c_earliest <= rxd_tag + 2;  cmd_gap_ok <= '0';
            st         <= ret_st;
          elsif tmo_z = '1' then
            c_ok <= '0';
            st   <= ret_st;
          end if;

        -- SPI: 6 command bytes, then R1 in one of the following bytes (CMD12:
        -- not in the stuff byte right after it); R3/R7 add 4 bytes, R1b a busy
        when S_CMD =>
          run <= '1';
          if sp_ld = '1' then
            -- byte sp_ld_n is going out: prepare byte sp_ld_n+1
            if sp_n < 6 then
              sp_tx_next <= c_frame(47 downto 40);
              c_frame    <= c_frame(39 downto 0) & x"FF";
              sp_n       <= sp_n + 1;
              if sp_n = 5 then
                sp_cmd_end <= sp_ld_n + 1;
              end if;
            else
              sp_tx_next <= x"FF";
            end if;
          end if;
          if sp_n = 6 and sp_new = '1' and sp_bn > sp_cmd_end then
            if sp_byte(7) = '0' and not (c_idx = 12 and sp_bn = sp_cmd_end + 1) then
              sp_r1  <= sp_byte;
              c_ok   <= '1';
              sp_cnt <= 0;
              sp_ext <= (others => '0');
              if c_resp = R_R3 or c_resp = R_R7 or c_resp = R_R2 then
                sp_n <= 7;
              elsif c_resp = R_R1B then
                tmo  <= to_unsigned(TMO_BUSY, 28);
                tmo_z  <= '0';
                sp_n <= 8;
              else
                st <= ret_st;
              end if;
            elsif sp_bn - sp_cmd_end > 10 then
              c_ok  <= '0';
              sp_r1 <= x"FF";
              st    <= ret_st;
            end if;
          elsif sp_n = 7 and sp_new = '1' then
            sp_ext <= sp_ext(23 downto 0) & sp_byte;
            if sp_cnt = 3 or c_resp = R_R2 then
              st <= ret_st;
            else
              sp_cnt <= sp_cnt + 1;
            end if;
          elsif sp_n = 8 then
            if sp_new = '1' and sp_byte /= x"00" then
              st <= ret_st;
            elsif tmo_z = '1' then
              c_ok <= '0';
              st   <= ret_st;
            end if;
          end if;

        ------------------------------------------------------------------------
        -- Read-only card information. Native CID/CSD are long CMD responses
        -- in Stand-by; SCR/SD Status use short DAT blocks in Transfer. SPI
        -- uses a data token and CRC16 for all four, plus R2 for ACMD13.
        ------------------------------------------------------------------------
        when I_START =>
          run <= '1'; stop_en <= '0';
          if info_kind < 2 then
            if mode_native = '1' then
              do_cmd(7, x"00000000", R_NONE, N_I_REG);
            else
              sp_cs_next <= '0';
              if info_kind = 0 then do_cmd(9, x"00000000", R_R1, I_DATA_RESP);
              else do_cmd(10, x"00000000", R_R1, I_DATA_RESP); end if;
              tmo <= to_unsigned(TMO_READ, 28); tmo_z <= '0';
            end if;
          else
            st <= I_APP;
          end if;

        when N_I_REG =>
          if info_kind = 0 then do_cmd(9, rca & x"0000", R_R2, N_I_REG_RESP);
          else do_cmd(10, rca & x"0000", R_R2, N_I_REG_RESP); end if;

        when N_I_REG_RESP =>
          info_ok <= c_ok;
          if c_ok = '0' then
            if c_n = 135 and r2_header_ok = '1' then e_err <= ERR_RD_CRC; else e_err <= ERR_CMD; end if;
          end if;
          -- Reselect even after a corrupt/missing register response.
          do_cmd(7, rca & x"0000", R_R1B, N_I_SELECT);

        when N_I_SELECT =>
          if c_ok = '0' or r1_bad(r_sr) then
            e_err <= ERR_CMD; st <= I_ABORT;
          elsif info_ok = '0' then st <= I_ABORT;
          else st <= I_EMIT; end if;

        when I_APP =>
          sp_cs_next <= '0';
          if mode_native = '1' then do_cmd(55, rca & x"0000", R_R1, I_APP_RESP);
          else do_cmd(55, x"00000000", R_R1, I_APP_RESP); end if;

        when I_APP_RESP =>
          if c_ok = '0' or (mode_native = '1' and r1_bad(r_sr))
            or (mode_native = '0' and sp_r1 /= x"00") then
            e_err <= ERR_CMD; st <= I_ABORT;
          else st <= I_DATA_CMD; end if;

        when I_DATA_CMD =>
          tmo <= to_unsigned(TMO_READ, 28); tmo_z <= '0';
          info_data_done <= '0'; info_data_ok <= '0';
          if mode_native = '1' then
            d_small <= '1'; d_arm <= '1'; d_after <= ttag; rf_dafter <= '0';
          end if;
          if info_kind = 2 then do_cmd(51, x"00000000", R_R1, I_DATA_RESP);
          elsif mode_native = '1' then do_cmd(13, x"00000000", R_R1, I_DATA_RESP);
          else do_cmd(13, x"00000000", R_R2, I_DATA_RESP); end if;

        when I_DATA_RESP =>
          if c_ok = '0' or (mode_native = '1' and r1_bad(r_sr))
            or (mode_native = '0' and (sp_r1 /= x"00"
              or (info_kind = 3 and sp_ext(7 downto 0) /= x"00"))) then
            e_err <= ERR_CMD; st <= I_ABORT;
          else
            if mode_native = '0' then d_act <= '0'; end if;
            st <= I_DATA;
          end if;

        when I_DATA =>
          run <= '1';
          if mode_native = '1' then
            if info_data_done = '1' then
              d_small <= '0';
              if info_data_ok = '1' then
                info_pos <= resize(info_len, 10); st <= I_EMIT;
              else e_err <= ERR_RD_CRC; st <= I_ABORT; end if;
            elsif tmo_z = '1' then e_err <= ERR_RD_TMO; st <= I_ABORT; end if;
          elsif sp_new = '1' then
            if d_act = '0' then
              if sp_byte = x"FE" then
                d_act <= '1'; d_idx <= (others => '0'); d_crc <= (others => '0');
              elsif sp_byte(7 downto 4) = "0000" then
                e_err <= ERR_RD_CRC; st <= I_ABORT;
              elsif tmo_z = '1' then e_err <= ERR_RD_TMO; st <= I_ABORT; end if;
            else
              if d_idx < resize(info_len, 10) then
                if info_init = '1' then r_long <= r_long(119 downto 0) & sp_byte;
                else rpush("00", sp_byte); end if;
                d_crc(15 downto 0) <= crc16_byte(d_crc(15 downto 0), sp_byte);
              else d_crcrx(15 downto 0) <= d_crcrx(7 downto 0) & sp_byte; end if;
              d_idx <= d_idx + 1;
              if d_idx = resize(info_len, 10) + 1 then
                d_act <= '0';
                if (d_crcrx(7 downto 0) & sp_byte) /= d_crc(15 downto 0) then
                  e_err <= ERR_RD_CRC; st <= I_ABORT;
                else
                  info_pos <= resize(info_len, 10);
                  cnt <= (others => '0');
                  if info_init = '1' then ret_st <= S_CAP_DECODE;
                  else ret_st <= I_EMIT; end if;
                  st <= P_DESEL;
                end if;
              end if;
            end if;
          elsif tmo_z = '1' then e_err <= ERR_RD_TMO; st <= I_ABORT; end if;

        when I_EMIT =>
          run <= '0';
          -- Serialise native R2 and pad short payloads. Bound the FIFO's
          -- occupancy; the engine clock is faster than the consumer.
          if rf_we = '0' and rf_room = '1' then
            if mode_native = '1' and info_kind < 2 and info_pos < 16 then
              rpush("00", r_long(127 downto 120));
              r_long <= r_long(119 downto 0) & x"00";
            else rpush("00", x"00"); end if;
            info_pos <= info_pos + 1;
            if info_pos = 511 then st <= I_GOOD; end if;
          end if;

        when I_GOOD =>
          if rf_we = '0' and rf_room = '1' then
            rpush("10", x"00"); op_done <= to_unsigned(1, 16); st <= S_FINISH;
          end if;

        when I_ABORT =>
          d_arm <= '0'; d_act <= '0'; d_small <= '0';
          if info_init = '1' then
            info_init <= '0'; op <= OP_NONE;
            if limit_s(1) = '1' then istep <= 30; else istep <= 15; end if;
            cnt <= (others => '0'); ret_st <= P_INIT; st <= P_DESEL;
          elsif mode_native = '1' then
            rpush("11", x"00");
            close_ret <= I_ERROR; close_tries <= 0; st <= S_CLOSE;
          else
            rpush("11", x"00");
            cnt <= (others => '0'); ret_st <= I_ERROR; st <= P_DESEL;
          end if;

        when I_ERROR =>
          e_error <= '1'; op <= OP_NONE; e_wait <= '0';
          cnt <= (others => '0'); st <= S_TAIL;

        -- Decode the inclusive last LBA. SDHC/SDXC has 1024 sectors per
        -- C_SIZE unit; SDSC shifts a registered count to avoid a large
        -- variable barrel shifter on the 162 MHz control path.
        when S_CAP_DECODE =>
          info_init <= '0'; op <= OP_NONE;
          if r_long(127 downto 126) = "01" then
            cap_last <= unsigned(r_long(69 downto 48)) & "1111111111";
            cap_known <= '1'; st <= cap_ret;
          elsif r_long(127 downto 126) = "00" then
            cap_work <= resize(unsigned(r_long(73 downto 62)), 33) + 1;
            cap_shift <= to_integer(unsigned(r_long(83 downto 80)))
              + to_integer(unsigned(r_long(49 downto 47))) - 7;
            st <= S_CAP_SHIFT;
          elsif limit_s(1) = '0' then st <= cap_ret;
          else
            e_error <= '1'; e_err <= ERR_CAPACITY; ready <= '0';
            cnt <= (others => '0'); st <= S_TAIL;
          end if;

        when S_CAP_SHIFT =>
          if cap_shift > 0 then cap_work <= shift_left(cap_work, 1); cap_shift <= cap_shift-1;
          elsif cap_shift < 0 then cap_work <= shift_right(cap_work, 1); cap_shift <= cap_shift+1;
          elsif cap_work /= 0 then
            cap_last <= resize(cap_work-1, 32); cap_known <= '1'; st <= cap_ret;
          elsif limit_s(1) = '0' then st <= cap_ret;
          else
            e_error <= '1'; e_err <= ERR_CAPACITY; ready <= '0';
            cnt <= (others => '0'); st <= S_TAIL;
          end if;

        ------------------------------------------------------------------------
        -- native init
        ------------------------------------------------------------------------
        when N_PRE =>
          -- 80 clocks with CMD and DAT3 high
          run <= '1';
          if tick = '1' then
            cnt <= cnt + 1;
            if cnt = 80 then
              cnt   <= (others => '0');
              istep <= 0;
              st    <= N_INIT;
            end if;
          end if;

        when N_INIT =>
          run <= '1';
          case istep is
            when 0 =>                   -- CMD0, no response
              istep <= 1;
              do_cmd(0, x"00000000", R_NONE, N_INIT);
            when 1 =>                   -- release DAT3
              dat_oe_nx <= "0000";
              istep     <= 2;
              do_cmd(8, x"000001AA", R_R7, N_INIT);
            when 2 =>
              if c_ok = '1' and r_sr(19 downto 8) = x"1AA" then
                v2 <= '1';
              else
                v2 <= '0';
              end if;
              tmo   <= to_unsigned(TMO_INIT, 28);
              tmo_z   <= '0';
              istep <= 3;
            when 3 =>
              istep <= 4;
              do_cmd(55, x"00000000", R_R1, N_INIT);
            when 4 =>
              if c_ok = '0' then
                istep <= 30;            -- no SD-mode card: SPI
              else
                istep <= 5;
                if v2 = '1' then
                  do_cmd(41, x"40FF8000", R_R3, N_INIT);
                else
                  do_cmd(41, x"00FF8000", R_R3, N_INIT);
                end if;
              end if;
            when 5 =>
              if c_ok = '0' then
                istep <= 30;
              elsif r_sr(39) = '1' then
                hc    <= r_sr(38) and v2;
                istep <= 6;
              elsif tmo_z = '1' then
                istep <= 30;
              else
                istep <= 3;
              end if;
            when 6 =>
              istep <= 7;
              do_cmd(2, x"00000000", R_R2, N_INIT);
            when 7 =>
              if c_ok = '0' then
                istep <= 30;
              else
                istep <= 8;
                do_cmd(3, x"00000000", R_R1, N_INIT);   -- R6
              end if;
            when 8 =>
              if c_ok = '0' then
                istep <= 30;
              else
                rca     <= r_sr(39 downto 24);
                new_set <= SET_DS;      -- data transfer mode: default speed
                cur_set <= SET_DS;
                istep   <= 20;
                resync(N_INIT);
              end if;
            when 20 =>
              istep <= 21; do_cmd(9, rca & x"0000", R_R2, N_INIT);
            when 21 =>
              if c_ok = '1' then
                cap_ret <= N_INIT; istep <= 9; st <= S_CAP_DECODE;
              elsif limit_s(1) = '0' then istep <= 9;
              else istep <= 30; end if;
            when 9 =>
              istep <= 10;
              do_cmd(7, rca & x"0000", R_R1B, N_INIT);
            when 10 =>
              if c_ok = '0' or r1_bad(r_sr) then
                istep <= 30;
              else
                istep <= 11;
                do_cmd(55, rca & x"0000", R_R1, N_INIT);
              end if;
            when 11 =>
              if c_ok = '0' then
                istep <= 30;
              else
                istep <= 12;
                do_cmd(6, x"00000002", R_R1, N_INIT);   -- ACMD6: 4-bit bus
              end if;
            when 12 =>
              if c_ok = '0' or r1_bad(r_sr) then
                istep <= 30;
              elsif hc = '0' then
                istep <= 15;
                do_cmd(16, x"00000200", R_R1, N_INIT);
              else
                istep <= 16;
              end if;
            when 15 =>
              if c_ok = '0' then
                istep <= 30;
              else
                istep <= 16;
              end if;
            when 16 =>
              -- CMD6: function group 1 to high speed.  The 64-byte switch
              -- status comes on DAT, possibly before the response is over.
              if no_hs = '1' then
                istep <= 13;
              else
                d_small   <= '1';
                d_arm     <= '1';
                d_after   <= ttag;  rf_dafter <= '0';
                hs_byte   <= (others => '0');
                istep     <= 17;
                do_cmd(6, x"80FFFFF1", R_R1, N_INIT);
              end if;
            when 17 =>
              tmo <= to_unsigned(TMO_PROBE, 28);
              tmo_z <= '0';
              if c_ok = '0' or r1_bad(r_sr) then
                d_arm   <= '0';
                d_small <= '0';
                istep   <= 13;          -- no high speed
              else
                istep <= 18;
              end if;
            when 18 =>
              if d_done = '1' then
                d_small <= '0';
                if d_ok = '1' and hs_byte(3 downto 0) = x"1" then
                  hs      <= '1';
                  new_set <= SET_HS;
                  cur_set <= SET_HS;
                  cnt     <= (others => '0');
                  istep   <= 19;
                else
                  istep <= 13;
                end if;
              elsif tmo_z = '1' then
                d_arm   <= '0';
                d_act   <= '0';
                d_small <= '0';
                istep   <= 13;
              end if;
            when 19 =>
              -- 8 clocks, then the faster clock
              if tick = '1' then
                cnt <= cnt + 1;
                if cnt = 8 then
                  istep <= 13;
                  resync(N_INIT);
                end if;
              end if;
            when 13 =>
              -- test read of block 0 on all four lines
              ready      <= '1';
              op_verify  <= '1';
              op         <= OP_READ;
              op_addr    <= (others => '0');
              op_granted <= to_unsigned(1, 16);
              op_closed  <= '1';
              op_done    <= (others => '0');
              op_multi   <= '0';
              op_try     <= 0;
              d_discard  <= '1';
              istep      <= 14;
              st         <= N_RD_CMD;
            when 14 =>
              -- passed
              op_verify <= '0';
              op        <= OP_NONE;
              op_done   <= (others => '0');
              cnt       <= (others => '0');
              st        <= S_TAIL;
            when others =>
              -- 30: the native bus failed: try SPI
              ready  <= '0';
              spi_fb <= '1';
              tmo    <= (others => '0');
              tmo_z    <= '1';
              st     <= S_INIT;
          end case;

        ------------------------------------------------------------------------
        -- native read
        ------------------------------------------------------------------------
        when N_RD_CMD =>
          run <= '1';
          if op = OP_PROBE then
            tmo <= to_unsigned(TMO_PROBE, 28);
            tmo_z <= '0';
          else
            tmo <= to_unsigned(TMO_READ, 28);
            tmo_z <= '0';
          end if;
          -- the data may start before the response is over: scan from now
          d_arm   <= '1';
          d_after <= ttag;  rf_dafter <= '0';
          d_small <= '0';
          if op_multi = '1' then
            do_cmd(18, card_addr(op_addr, op_done, hc), R_R1, N_RD_RESP);
          else
            do_cmd(17, card_addr(op_addr, op_done, hc), R_R1, N_RD_RESP);
          end if;

        when N_RD_RESP =>
          run <= '1';
          if c_ok = '0' or r1_bad(r_sr) then
            cut_block;
            failed(ERR_CMD);
          else
            st <= N_RD_BLOCK;
          end if;

        when N_RD_BLOCK =>
          -- block op_done is coming in
          -- (registered: rd_next_ok, worked out every cycle above)
          next_ok := rd_next_ok = '1';
          run <= '1';
          if next_ok and d_start = '0' then
            stop_en <= '0';
          end if;
          if d_act = '1' or d_start = '1' then
            tmo <= to_unsigned(TMO_READ, 28);
            tmo_z <= '0';
          end if;
          if d_done = '1' then
            if d_ok = '0' then
              failed(ERR_RD_CRC);
            else
              op_try <= 0;
              if op = OP_PROBE then
                e_pass  <= e_pass + 1;
                op_reps <= op_reps - 1;
                st      <= S_DISPATCH;
              elsif op_verify = '1' then
                st <= N_INIT;            -- istep 14
              else
                op_done <= op_done + 1;
                if op_multi = '0' then
                  st <= S_DISPATCH;
                elsif rd_last = '1' then
                  st <= N_RD_STOP;
                else
                  -- scan on from the end bit (if the clock stops after it, it
                  -- runs again once the next block is granted)
                  d_arm   <= '1';
                  d_after <= d_end_tag;  rf_dafter <= '0';
                end if;
              end if;
            end if;
          elsif d_act = '0' and d_arm = '1' and stop_en = '1' and cg_frz = '1'
            and rcnt = stop_at then
            -- paused between blocks: go on once the next block is granted
            if op_done /= op_granted then
              stop_en <= '0';
            elsif op_closed = '1' then
              d_arm <= '0';
              st    <= N_RD_STOP;
            elsif rf_empty_e = '1' then
              e_wait <= '1';
            end if;
            tmo <= to_unsigned(TMO_READ, 28);
            tmo_z <= '0';
          elsif tmo_z = '1' then
            failed(ERR_RD_TMO);
          end if;

        -- CMD12 ends a multi-block read
        when N_RD_STOP =>
          d_arm   <= '0';
          stop_en <= '0';
          e_wait  <= '0';
          close_ret   <= S_DISPATCH;
          close_tries <= 0;
          st          <= S_CLOSE;

        ------------------------------------------------------------------------
        -- native write
        ------------------------------------------------------------------------
        when N_WR_CMD =>
          run <= '1';
          if op_multi = '1' then
            do_cmd(25, card_addr(op_addr, op_done, hc), R_R1, N_WR_RESP);
          else
            do_cmd(24, card_addr(op_addr, op_done, hc), R_R1, N_WR_RESP);
          end if;

        when N_WR_RESP =>
          if c_ok = '0' or r1_bad(r_sr) then
            failed(ERR_CMD);
          else
            op_stop12 <= '0';
            st        <= N_WR_WAIT;
          end if;

        -- fetch the block's data, then the start bit (Nwr: 2 cycles after the
        -- response at least)
        when N_WR_WAIT =>
          if op_done = op_granted and op_closed = '1' then
            -- all written: CMD12 ends the multi-block write
            run       <= '1';
            e_wait    <= '0';
            op_stop12 <= '1';
            do_cmd(12, x"00000000", R_R1B, N_WR_NEXT);
          elsif op_done = op_granted then
            run <= '0';
            if rf_empty_e = '1' then
              e_wait <= '1';
            end if;
          elsif w_reqd = '0' then
            w_seq  <= not w_seq;
            w_blk  <= op_done;
            w_reqd <= '1';
            e_wait <= '0';
          elsif w_ready = '1' then
            run <= '1';
            if tick = '1' and wr_gap_ok = '1' then
              dat_oe_nx <= "1111";
              dat_nx    <= "0000";
              t_idx     <= (others => '0');
              t_crc     <= (others => '0');
              w_under   <= '0';
              st        <= N_WR_DATA;
            end if;
          else
            run <= '0';
          end if;

        when N_WR_DATA =>
          run <= '1';
          if tick = '1' then
            if t_idx < 1024 then
              if t_idx(0) = '0' then
                if wf_rp /= wf_wp_e and wf_head(8) = w_seq then
                  b := wf_head(7 downto 0);
                  wf_rp <= wf_rp + 1;
                else
                  b := x"00";
                  w_under <= '1';       -- ran dry: the CRC will be bad
                end if;
                nib    := b(7 downto 4);
                t_byte <= b;
              else
                nib := t_byte(3 downto 0);
              end if;
              dat_nx <= nib;
              crc := t_crc;
              for l in 0 to 3 loop
                crc(16*l+15 downto 16*l) := crc16_bit(t_crc(16*l+15 downto 16*l), nib(l));
              end loop;
              t_crc <= crc;
            elsif t_idx < 1040 then
              for l in 0 to 3 loop
                dat_nx(l) <= t_crc(16*l+15) xor w_under;
                t_crc(16*l+15 downto 16*l) <= t_crc(16*l+14 downto 16*l) & '0';
              end loop;
            elsif t_idx = 1040 then
              dat_nx <= "1111";            -- end bit
              t_end  <= ttag + 1;  rf_tend <= '0'; rf_t16 <= '0';
            else
              dat_oe_nx <= "0000";
              w_n       <= 0;
              w_stat    <= (others => '1');
              tmo       <= to_unsigned(TMO_BUSY, 28);
              tmo_z       <= '0';
              st        <= N_WR_STATUS;
            end if;
            t_idx <= t_idx + 1;
          end if;

        -- CRC status (0 sss 1 on DAT0), then busy
        when N_WR_STATUS =>
          run <= '1';
          if rxd_v = '1' and rf_tend = '1' then
            if w_n = 0 then
              if rxd_dat(0) = '0' then
                w_n <= 1;
              elsif rf_t16 = '1' then
                failed(ERR_WR_TMO);
              end if;
            else
              w_stat <= w_stat(2 downto 0) & rxd_dat(0);
              w_n    <= w_n + 1;
              if w_n = 4 then
                if w_stat(2 downto 0) = "010" and rxd_dat(0) = '1' then
                  b_after <= rxd_tag;  rf_bafter <= '0';
                  b_n     <= 0;
                  c_ok    <= '1';
                  ret_st  <= N_WR_NEXT;
                  st      <= S_BUSY0;
                elsif w_stat(2 downto 0) = "101" then
                  failed(ERR_WR_CRC);
                else
                  failed(ERR_WR_ERR);
                end if;
              end if;
            end if;
          elsif tmo_z = '1' then
            failed(ERR_WR_TMO);
          end if;

        when N_WR_NEXT =>
          run <= '1';
          if c_ok = '0' then
            failed(ERR_WR_TMO);
          elsif op_stop12 = '1' then
            op_stop12 <= '0';
            st        <= S_DISPATCH;
          else
            op_done <= op_done + 1;
            op_try  <= 0;
            w_reqd  <= '0';
            c_end   <= c_earliest;  rf_cend <= '0'; rf_c80 <= '0'; wr_gap_ok <= '0';
            if op_multi = '0' then
              st <= S_DISPATCH;
            else
              st <= N_WR_WAIT;
            end if;
          end if;

        ------------------------------------------------------------------------
        -- SPI init
        ------------------------------------------------------------------------
        when P_PRE =>
          -- 80 clocks with CS high
          run        <= '1';
          sp_tx_next <= x"FF";
          sp_cs_next <= '1';
          if sp_ld = '1' then
            cnt <= cnt + 1;
            if cnt = 10 then
              cnt   <= (others => '0');
              istep <= 0;
              tries <= 0;
              st    <= P_INIT;
            end if;
          end if;

        when P_INIT =>
          run        <= '1';
          sp_cs_next <= '0';
          case istep is
            when 0 =>
              istep <= 1;
              do_cmd(0, x"00000000", R_R1, P_INIT);
            when 1 =>
              if c_ok = '1' and sp_r1 = x"01" then
                istep <= 2;
                do_cmd(8, x"000001AA", R_R7, P_INIT);
              elsif tries = 9 then
                istep <= 31;
              else
                tries <= tries + 1;
                do_cmd(0, x"00000000", R_R1, P_INIT);
              end if;
            when 2 =>
              tmo <= to_unsigned(TMO_INIT, 28);
              tmo_z <= '0';
              if c_ok = '1' and sp_r1 = x"01" and sp_ext(11 downto 0) = x"1AA" then
                v2    <= '1';
                istep <= 3;
              elsif c_ok = '1' and sp_r1(2) = '1' then
                v2    <= '0';             -- illegal command: version 1
                istep <= 3;
              else
                istep <= 30;
              end if;
            when 3 =>
              istep <= 4;
              do_cmd(55, x"00000000", R_R1, P_INIT);
            when 4 =>
              istep <= 5;
              if v2 = '1' then
                do_cmd(41, x"40000000", R_R1, P_INIT);
              else
                do_cmd(41, x"00000000", R_R1, P_INIT);
              end if;
            when 5 =>
              if c_ok = '1' and sp_r1 = x"00" then
                istep <= 6;
              elsif c_ok = '1' and sp_r1 = x"01" and tmo_z = '0' then
                istep <= 3;
              else
                istep <= 30;
              end if;
            when 6 =>
              if v2 = '1' then
                istep <= 7;
                do_cmd(58, x"00000000", R_R3, P_INIT);
              else
                hc    <= '0';
                istep <= 8;
              end if;
            when 7 =>
              if c_ok = '1' and sp_r1 = x"00" then
                hc    <= sp_ext(30);
                istep <= 8;
              else
                istep <= 30;
              end if;
            when 8 =>
              istep <= 9;
              do_cmd(59, x"00000001", R_R1, P_INIT);    -- CRC on
            when 9 =>
              if c_ok = '1' and sp_r1 = x"00" then
                if hc = '0' then
                  istep <= 10;
                  do_cmd(16, x"00000200", R_R1, P_INIT);
                else
                  istep <= 11;
                end if;
              else
                istep <= 30;
              end if;
            when 10 =>
              if c_ok = '1' and sp_r1 = x"00" then
                istep <= 11;
              else
                istep <= 30;
              end if;
            when 11 =>
              -- deselect, then the data clock
              cnt    <= (others => '0');
              ret_st <= P_INIT;
              istep  <= 12;
              st     <= P_DESEL;
            when 12 =>
              new_set <= SET_DS;
              cur_set <= SET_DS;
              istep   <= 13;
              resync(P_INIT);
            when 13 =>
              -- Read capacity internally, without publishing data to the
              -- shared sector buffer while both sockets initialise.
              info_init <= '1'; info_kind <= "00"; info_len <= to_unsigned(16, 7);
              info_pos <= (others => '0'); op <= OP_INFO;
              cap_ret <= P_INIT; istep <= 15; st <= I_START;
            when 15 =>
              -- test read of block 0
              ready      <= '1';
              op_verify  <= '1';
              op         <= OP_READ;
              op_addr    <= (others => '0');
              op_granted <= to_unsigned(1, 16);
              op_closed  <= '1';
              op_done    <= (others => '0');
              op_multi   <= '0';
              op_try     <= 0;
              d_discard  <= '1';
              istep      <= 14;
              st         <= P_RD_CMD;
            when 14 =>
              op_verify <= '0';
              op        <= OP_NONE;
              op_done   <= (others => '0');
              cnt       <= (others => '0');
              st        <= S_TAIL;
            when others =>
              -- 30: init failed, 31: no card
              ready      <= '0';
              sp_cs_next <= '1';
              e_error    <= '1';
              if istep = 31 then
                e_err <= ERR_NOCARD;
              else
                e_err <= ERR_INIT;
              end if;
              cnt <= (others => '0');
              st  <= S_TAIL;
          end case;

        -- CS high for two bytes
        when P_DESEL =>
          run        <= '1';
          sp_cs_next <= '1';
          sp_tx_next <= x"FF";
          if sp_ld = '1' then
            cnt <= cnt + 1;
            if cnt = 2 then
              cnt <= (others => '0');
              st  <= ret_st;
            end if;
          end if;

        -- end of an SPI transfer: deselect, then go on or fail
        when P_FIN =>
          cnt <= (others => '0');
          if sp_ok = '1' then
            ret_st <= S_DISPATCH;
          else
            ret_st <= S_FAIL;
          end if;
          st <= P_DESEL;

        ------------------------------------------------------------------------
        -- SPI read
        ------------------------------------------------------------------------
        when P_RD_CMD =>
          run        <= '1';
          sp_cs_next <= '0';
          if op = OP_PROBE then
            tmo <= to_unsigned(TMO_PROBE, 28);
            tmo_z <= '0';
          else
            tmo <= to_unsigned(TMO_READ, 28);
            tmo_z <= '0';
          end if;
          if op_multi = '1' then
            do_cmd(18, card_addr(op_addr, op_done, hc), R_R1, P_RD_RESP);
          else
            do_cmd(17, card_addr(op_addr, op_done, hc), R_R1, P_RD_RESP);
          end if;

        when P_RD_RESP =>
          d_act <= '0';
          if c_ok = '0' or sp_r1 /= x"00" then
            e_err <= ERR_CMD;
            sp_ok <= '0';
            st    <= P_RD_END;
          else
            st <= P_RD_BLOCK;
          end if;

        -- token, 512 bytes, 2 CRC bytes
        when P_RD_BLOCK =>
          -- (registered: rd_next_ok, worked out every cycle above)
          next_ok := rd_next_ok = '1';
          run <= '1';
          if d_act = '1' and next_ok then
            stop_en <= '0';
          end if;
          if sp_new = '1' then
            if d_act = '0' then
              if sp_byte = x"FE" then
                d_act <= '1';
                d_idx <= (others => '0');
                d_crc <= (others => '0');
                tmo   <= to_unsigned(TMO_READ, 28);
                tmo_z   <= '0';
                -- the block's last byte is sp_bn + 514: stop the clock after
                -- it unless the next block can follow
                stop_at <= shift_left(resize(sp_bn, 16) + 515, 3);
                if not next_ok then
                  stop_en <= '1';
                end if;
              elsif sp_byte(7 downto 4) = "0000" then
                e_err <= ERR_RD_CRC;      -- data error token
                sp_ok <= '0';
                st    <= P_RD_END;
              end if;
            else
              if d_idx < 512 then
                d_crc(15 downto 0) <= crc16_byte(d_crc(15 downto 0), sp_byte);
                if d_discard = '0' then
                  rpush("00", sp_byte);
                end if;
              else
                d_crcrx(15 downto 0) <= d_crcrx(7 downto 0) & sp_byte;
              end if;
              d_idx <= d_idx + 1;
              if d_idx = 513 then
                d_act <= '0';
                if (d_crcrx(7 downto 0) & sp_byte) /= d_crc(15 downto 0) then
                  if d_discard = '0' then
                    rpush("11", x"00");
                  end if;
                  e_err <= ERR_RD_CRC;
                  sp_ok <= '0';
                  st    <= P_RD_END;
                else
                  op_try <= 0;
                  sp_ok  <= '1';
                  if op = OP_PROBE then
                    e_pass  <= e_pass + 1;
                    op_reps <= op_reps - 1;
                    st      <= P_RD_END;
                  elsif op_verify = '1' then
                    st <= P_RD_END;
                  else
                    rpush("10", x"00");
                    op_done <= op_done + 1;
                    if op_multi = '0' or rd_last = '1' then
                      st <= P_RD_END;
                    end if;
                  end if;
                end if;
              end if;
            end if;
          elsif d_act = '0' and stop_en = '1' and cg_frz = '1' and rcnt = stop_at then
            -- paused between blocks: go on once the next block is granted
            if op_done /= op_granted then
              stop_en <= '0';
            elsif op_closed = '1' then
              sp_ok <= '1';
              st    <= P_RD_END;
            elsif rf_empty_e = '1' then
              e_wait <= '1';
            end if;
            tmo <= to_unsigned(TMO_READ, 28);
            tmo_z <= '0';
          elsif tmo_z = '1' then
            e_err <= ERR_RD_TMO;
            sp_ok <= '0';
            st    <= P_RD_END;
          end if;

        -- CMD12 for a multi-block read, then deselect
        when P_RD_END =>
          if sp_ok = '0' then count_read_error(e_err); end if;
          run     <= '1';
          stop_en <= '0';
          e_wait  <= '0';
          cut_block;
          if op_multi = '1' then
            do_cmd(12, x"00000000", R_R1B, P_RD_END2);
          elsif op_verify = '1' and sp_ok = '1' then
            cnt    <= (others => '0');
            ret_st <= P_INIT;              -- istep 14
            st     <= P_DESEL;
          else
            st <= P_FIN;
          end if;

        when P_RD_END2 =>
          if c_ok = '0' then
            count_read_error(ERR_CMD);
            sp_ok <= '0';
          end if;
          st <= P_FIN;

        ------------------------------------------------------------------------
        -- SPI write
        ------------------------------------------------------------------------
        when P_WR_CMD =>
          run        <= '1';
          sp_cs_next <= '0';
          if op_multi = '1' then
            do_cmd(25, card_addr(op_addr, op_done, hc), R_R1, P_WR_RESP);
          else
            do_cmd(24, card_addr(op_addr, op_done, hc), R_R1, P_WR_RESP);
          end if;

        when P_WR_RESP =>
          if c_ok = '0' or sp_r1 /= x"00" then
            e_err <= ERR_CMD;
            sp_ok <= '0';
            st    <= P_FIN;
          else
            st <= P_WR_WAIT;
          end if;

        -- fetch the data, then the token (at least one FF before it)
        when P_WR_WAIT =>
          sp_tx_next <= x"FF";
          if op_done = op_granted and op_closed = '1' then
            run    <= '1';
            e_wait <= '0';
            sp_cnt <= 0;
            if op_multi = '1' then
              st <= P_WR_STOPTOK;
            else
              sp_ok <= '1';
              st    <= P_FIN;
            end if;
          elsif op_done = op_granted then
            run <= '0';
            if rf_empty_e = '1' then
              e_wait <= '1';
            end if;
          elsif w_reqd = '0' then
            w_seq  <= not w_seq;
            w_blk  <= op_done;
            w_reqd <= '1';
            e_wait <= '0';
          elsif w_ready = '1' then
            run <= '1';
            if sp_ld = '1' then
              if op_multi = '1' then
                sp_tx_next <= x"FC";
              else
                sp_tx_next <= x"FE";
              end if;
              t_idx   <= (others => '0');
              t_crc   <= (others => '0');
              w_under <= '0';
              st      <= P_WR_DATA;
            end if;
          else
            run <= '0';
          end if;

        when P_WR_DATA =>
          run <= '1';
          if sp_ld = '1' then
            if t_idx < 512 then
              if wf_rp /= wf_wp_e and wf_head(8) = w_seq then
                b := wf_head(7 downto 0);
                wf_rp <= wf_rp + 1;
              else
                b := x"00";
                w_under <= '1';
              end if;
              sp_tx_next <= b;
              t_crc(15 downto 0) <= crc16_byte(t_crc(15 downto 0), b);
            elsif t_idx = 512 then
              sp_tx_next <= t_crc(15 downto 8) xor (7 downto 0 => w_under);
            elsif t_idx = 513 then
              sp_tx_next <= t_crc(7 downto 0);
              sp_tok_bn  <= sp_ld_n + 1;   -- the last CRC byte
            else
              sp_tx_next <= x"FF";
              tmo        <= to_unsigned(TMO_BUSY, 28);
              tmo_z        <= '0';
              sp_cnt     <= 0;
              st         <= P_WR_DRESP;
            end if;
            t_idx <= t_idx + 1;
          end if;

        -- data response xxx0sss1 right after the CRC, then busy (00)
        when P_WR_DRESP =>
          run        <= '1';
          sp_tx_next <= x"FF";
          if sp_new = '1' and sp_bn > sp_tok_bn then
            if sp_cnt = 0 then
              if sp_byte(4) = '0' and sp_byte(0) = '1' then
                if sp_byte(3 downto 1) = "010" then
                  sp_cnt <= 1;
                elsif sp_byte(3 downto 1) = "101" then
                  e_err <= ERR_WR_CRC;
                  sp_ok <= '0';
                  st    <= P_FIN;
                else
                  e_err <= ERR_WR_ERR;
                  sp_ok <= '0';
                  st    <= P_FIN;
                end if;
              elsif sp_bn - sp_tok_bn > 8 then
                e_err <= ERR_WR_TMO;
                sp_ok <= '0';
                st    <= P_FIN;
              end if;
            elsif sp_byte /= x"00" then
              -- programmed
              op_done <= op_done + 1;
              op_try  <= 0;
              w_reqd  <= '0';
              if op_multi = '1' then
                st <= P_WR_WAIT;
              else
                sp_ok <= '1';
                st    <= P_FIN;
              end if;
            end if;
          elsif tmo_z = '1' then
            e_err <= ERR_WR_TMO;
            sp_ok <= '0';
            st    <= P_FIN;
          end if;

        -- multi-block write: stop token FD, then busy
        when P_WR_STOPTOK =>
          run <= '1';
          if sp_ld = '1' then
            if sp_cnt = 0 then
              sp_tx_next <= x"FD";
              sp_tok_bn  <= sp_ld_n + 2;  -- skip the byte after the token
              sp_cnt     <= 1;
              tmo        <= to_unsigned(TMO_BUSY, 28);
              tmo_z        <= '0';
            else
              sp_tx_next <= x"FF";
            end if;
          end if;
          if sp_cnt = 1 and sp_new = '1' and sp_bn > sp_tok_bn and sp_byte /= x"00" then
            sp_ok <= '1';
            st    <= P_FIN;
          elsif sp_cnt = 1 and tmo_z = '1' then
            e_err <= ERR_WR_TMO;
            sp_ok <= '0';
            st    <= P_FIN;
          end if;

      end case;

      -- a grant ends the wait (the states above still saw the old count)
      if granting then
        e_wait <= '0';
      end if;

      --------------------------------------------------------------------------
      -- C_INIT at any time: drop everything (last, so it wins)
      --------------------------------------------------------------------------
      if take and e_code = C_INIT then
        e_ack     <= e_seen;
        cmd_pend <= '0';
        spi_only  <= e_arg(0);
        spi_fb    <= '0';
        no_hs     <= e_arg(1);
        if G_FIXED_SLOT = -1 then
          slot <= e_arg(4);
        else
          slot <= initial_slot;
        end if;
        e_error   <= '0';
        e_err     <= ERR_NONE;
        e_busy    <= '1';
        e_wait    <= '0';
        op        <= OP_NONE;
        cap_known <= '0'; info_init <= '0'; range_failed <= '0';
        op_closed <= '1';
        ready     <= '0';
        c_act     <= '0';
        cut_block;
        d_arm     <= '0';
        d_small   <= '0';
        stop_en   <= '0';
        run       <= '0';
        w_seq     <= not w_seq;          -- orphan any write data in flight
        tmo       <= to_unsigned(TMO_SETTLE, 28);
        tmo_z       <= '0';
        st        <= S_INIT;
      end if;

    end if;
  end process engine;

  -- pragma translate_off
  trace : process (clock162)
    variable last : t_state := S_POWERUP;
    variable lstep : natural := 0;
  begin
    if rising_edge(clock162) then
      if G_TRACE and (st /= last or istep /= lstep) then
        report "SDN: " & t_state'image(st) & " istep=" & integer'image(istep)
          & " c_ok=" & std_logic'image(c_ok) & " r1=" & integer'image(to_integer(unsigned(sp_r1)))
          & " err=" & integer'image(to_integer(e_err));
      end if;
      last := st;
      lstep := istep;
    end if;
  end process;
  -- pragma translate_on

end architecture rtl;

-------------------------------------------------------------------------------
-- Two persistent card sessions. Only the socket engines are duplicated; the
-- upper controller, sector buffer and cache remain shared. No block RAM.
-- C_INIT (1) still resets only arg(4)'s card. C_INIT_BOTH (A) starts both
-- engines on the same cpuclock edge. cmd_slot targets other commands;
-- status_slot independently selects the visible status.
-- cards_status contains two 32-bit CPU-domain words:
-- 0 ready, 1 busy, 2 waiting, 3 error, 11:4 error code, 12 native,
-- 13 high speed, 14 SDHC, 15 mailbox free, 31:16 clock setting.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdcard_native_dual is
  generic (
    G_XILINX : boolean := true;
    G_MS : natural := 162_000;
    G_AUTO_INIT : boolean := true;
    G_WR_LAT : natural := 2;
    G_TRACE : boolean := false;
    G_INIT_P : natural := 810;
    G_INIT_D : natural := 3;
    G_DS_P : natural := 13;
    G_DS_D : natural := 3;
    G_HS_P : natural := 8;
    G_HS_D : natural := 8
  );
  port (
    clock162, cpuclock : in std_logic;
    cmd_valid : in std_logic;
    cmd_ready : out std_logic;
    cmd_code : in unsigned(3 downto 0);
    cmd_addr : in unsigned(31 downto 0);
    cmd_count, cmd_arg : in unsigned(15 downto 0);
    cmd_slot, status_slot : in std_logic;
    cards_status : out unsigned(63 downto 0);
    card_ready, busy, waiting, error : out std_logic;
    err_code : out unsigned(7 downto 0);
    native_mode, high_speed, sdhc : out std_logic;
    clk_setting : out unsigned(15 downto 0);
    probe_pass, probe_fail : out unsigned(7 downto 0);
    blocks_done : out unsigned(15 downto 0);
    diag_stats : out unsigned(127 downto 0);
    rd_valid : out std_logic;
    rd_data : out unsigned(7 downto 0);
    rd_offset : out unsigned(8 downto 0);
    rd_block : out unsigned(15 downto 0);
    rd_good, rd_bad : out std_logic;
    wr_fetch : out std_logic;
    wr_offset : out unsigned(8 downto 0);
    wr_block : out unsigned(15 downto 0);
    wr_data : in unsigned(7 downto 0);
    sd_clk, sd_cmd_o, sd_cmd_oe : out std_logic_vector(1 downto 0);
    sd_cmd_i : in std_logic_vector(1 downto 0);
    sd_dat_o, sd_dat_oe : out std_logic_vector(7 downto 0);
    sd_dat_i : in std_logic_vector(7 downto 0);
    limit_enable : in std_logic_vector(1 downto 0) := "11";
    cards_last_sector : out unsigned(63 downto 0);
    cards_capacity_valid : out std_logic_vector(1 downto 0)
  );
end entity;

architecture rtl of sdcard_native_dual is
  type t_u8 is array (0 to 1) of unsigned(7 downto 0);
  type t_u9 is array (0 to 1) of unsigned(8 downto 0);
  type t_u16 is array (0 to 1) of unsigned(15 downto 0);
  type t_u32 is array (0 to 1) of unsigned(31 downto 0);
  type t_u128 is array (0 to 1) of unsigned(127 downto 0);
  type t_p2 is array (0 to 1) of std_logic_vector(1 downto 0);
  type t_p8 is array (0 to 1) of std_logic_vector(7 downto 0);
  type t_state is (Q_IDLE, Q_DISPATCH, Q_STOP_ACK, Q_ACK);
  signal st : t_state := Q_IDLE;
  signal p_code : unsigned(3 downto 0) := (others => '0');
  signal p_addr : unsigned(31 downto 0) := (others => '0');
  signal p_count, p_arg : unsigned(15 downto 0) := (others => '0');
  signal p_slot : natural range 0 to 1 := 0;
  signal p_mask, ack_low : std_logic_vector(1 downto 0) := "00";
  signal data_owner, stop_slot : natural range 0 to 1 := 0;
  signal data_active, stop_low : std_logic := '0';
  signal c_valid : std_logic_vector(1 downto 0) := "00";
  signal c_code : unsigned(3 downto 0) := x"1";
  signal c_addr : unsigned(31 downto 0) := (others => '0');
  signal c_count, c_arg : unsigned(15 downto 0) := (others => '0');
  signal c_ready, c_card, c_busy, c_wait, c_error : std_logic_vector(1 downto 0);
  signal c_native, c_hs, c_hc, c_rv, c_good, c_bad, c_wfetch : std_logic_vector(1 downto 0);
  signal c_err, c_pass, c_fail, c_data : t_u8;
  signal c_setting, c_done, c_rblock, c_wblock : t_u16;
  signal c_roff, c_woff : t_u9;
  signal c_diag : t_u128;
  signal c_last : t_u32;
  signal c_capacity : std_logic_vector(1 downto 0);
  signal c_clk, c_cmd_o, c_cmd_oe : t_p2;
  signal c_dat_o, c_dat_oe : t_p8;
  signal info : unsigned(63 downto 0);

  function slot_index(s : std_logic) return natural is
  begin
    if s = '1' then return 1; else return 0; end if;
  end function;
begin
  sockets : for s in 0 to 1 generate
    core : entity work.sdcard_native
      generic map (
        G_XILINX => G_XILINX, G_FIXED_SLOT => s, G_MS => G_MS,
        G_AUTO_INIT => G_AUTO_INIT, G_WR_LAT => G_WR_LAT, G_TRACE => G_TRACE,
        G_INIT_P => G_INIT_P, G_INIT_D => G_INIT_D,
        G_DS_P => G_DS_P, G_DS_D => G_DS_D, G_HS_P => G_HS_P, G_HS_D => G_HS_D)
      port map (
        clock162 => clock162, cpuclock => cpuclock,
        cmd_valid => c_valid(s), cmd_ready => c_ready(s), cmd_code => c_code,
        cmd_addr => c_addr, cmd_count => c_count, cmd_arg => c_arg,
        card_ready => c_card(s), busy => c_busy(s), waiting => c_wait(s),
        error => c_error(s), err_code => c_err(s), native_mode => c_native(s),
        high_speed => c_hs(s), sdhc => c_hc(s), clk_setting => c_setting(s),
        probe_pass => c_pass(s), probe_fail => c_fail(s), blocks_done => c_done(s),
        diag_stats => c_diag(s), rd_valid => c_rv(s), rd_data => c_data(s),
        rd_offset => c_roff(s), rd_block => c_rblock(s), rd_good => c_good(s), rd_bad => c_bad(s),
        wr_fetch => c_wfetch(s), wr_offset => c_woff(s), wr_block => c_wblock(s), wr_data => wr_data,
        sd_clk => c_clk(s), sd_cmd_o => c_cmd_o(s), sd_cmd_oe => c_cmd_oe(s), sd_cmd_i => sd_cmd_i,
        sd_dat_o => c_dat_o(s), sd_dat_oe => c_dat_oe(s), sd_dat_i => sd_dat_i,
        limit_enable => limit_enable(s), last_sector => c_last(s), capacity_valid => c_capacity(s));
    cards_last_sector(s*32+31 downto s*32) <= c_last(s);
    cards_capacity_valid(s) <= c_capacity(s);
    sd_clk(s) <= c_clk(s)(s);
    sd_cmd_o(s) <= c_cmd_o(s)(s);
    sd_cmd_oe(s) <= c_cmd_oe(s)(s);
    sd_dat_o(s*4+3 downto s*4) <= c_dat_o(s)(s*4+3 downto s*4);
    sd_dat_oe(s*4+3 downto s*4) <= c_dat_oe(s)(s*4+3 downto s*4);
  end generate;

  status : process(c_card, c_busy, c_wait, c_error, c_err, c_native, c_hs, c_hc,
                   c_ready, c_setting, st, p_mask, p_code)
    variable v : unsigned(63 downto 0);
  begin
    v := (others => '0');
    for s in 0 to 1 loop
      v(s*32) := c_card(s);
      v(s*32+1) := c_busy(s);
      v(s*32+2) := c_wait(s);
      v(s*32+3) := c_error(s);
      v(s*32+11 downto s*32+4) := c_err(s);
      v(s*32+12) := c_native(s);
      v(s*32+13) := c_hs(s);
      v(s*32+14) := c_hc(s);
      v(s*32+15) := c_ready(s);
      v(s*32+31 downto s*32+16) := c_setting(s);
      -- Cover queued dispatch and CDC latency without hiding the other card.
      if st /= Q_IDLE and p_mask(s) = '1' then
        v(s*32+1) := '1';
        if p_code = x"1" or p_code = x"A" then
          v(s*32) := '0';
          v(s*32+3) := '0';
          v(s*32+11 downto s*32+4) := (others => '0');
        end if;
      end if;
    end loop;
    info <= v;
  end process;
  cards_status <= info;
  card_ready <= info(slot_index(status_slot)*32);
  busy <= info(slot_index(status_slot)*32+1);
  waiting <= info(slot_index(status_slot)*32+2);
  error <= info(slot_index(status_slot)*32+3);
  err_code <= info(slot_index(status_slot)*32+11 downto slot_index(status_slot)*32+4);
  native_mode <= info(slot_index(status_slot)*32+12);
  high_speed <= info(slot_index(status_slot)*32+13);
  sdhc <= info(slot_index(status_slot)*32+14);
  clk_setting <= c_setting(slot_index(status_slot));
  probe_pass <= c_pass(slot_index(status_slot));
  probe_fail <= c_fail(slot_index(status_slot));
  blocks_done <= c_done(slot_index(status_slot));
  counters : process(c_diag, c_setting, status_slot)
    variable v : unsigned(127 downto 0);
  begin
    for w in 0 to 6 loop
      v(w*16+15 downto w*16) := c_diag(0)(w*16+15 downto w*16) + c_diag(1)(w*16+15 downto w*16);
    end loop;
    v(127 downto 112) := c_setting(slot_index(status_slot));
    diag_stats <= v;
  end process;
  -- Selection never redirects the shared data stream or write fetches.
  rd_valid <= c_rv(data_owner);
  rd_data <= c_data(data_owner);
  rd_offset <= c_roff(data_owner);
  rd_block <= c_rblock(data_owner);
  rd_good <= c_good(data_owner);
  rd_bad <= c_bad(data_owner);
  wr_fetch <= c_wfetch(data_owner);
  wr_offset <= c_woff(data_owner);
  wr_block <= c_wblock(data_owner);
  cmd_ready <= '1' when st = Q_IDLE else '0';

  commands : process(cpuclock)
    variable target : natural range 0 to 1;
    variable lows : std_logic_vector(1 downto 0);
  begin
    if rising_edge(cpuclock) then
      c_valid <= "00";
      case st is
        when Q_IDLE =>
          if cmd_valid = '1' then
            target := slot_index(cmd_slot);
            if cmd_code = x"1" then target := slot_index(cmd_arg(4)); end if;
            p_slot <= target;
            p_code <= cmd_code;
            p_addr <= cmd_addr;
            p_count <= cmd_count;
            p_arg <= cmd_arg;
            if cmd_code = x"A" then p_mask <= "11";
            elsif target = 0 then p_mask <= "01";
            else p_mask <= "10"; end if;
            st <= Q_DISPATCH;
          end if;
        when Q_DISPATCH =>
          if (p_code = x"2" or p_code = x"3" or p_code = x"B") and data_active = '1'
            and p_slot /= data_owner and c_busy(data_owner) = '1' then
            -- Retire an old card's granted blocks/checked close before
            -- assigning its shared stream to a request for the other card.
            if c_wait(data_owner) = '1' and c_ready(data_owner) = '1' then
              c_code <= x"5";
              c_arg <= (others => '0');
              c_valid(data_owner) <= '1';
              stop_slot <= data_owner;
              stop_low <= '0';
              st <= Q_STOP_ACK;
            end if;
          elsif (c_ready and p_mask) = p_mask then
            c_code <= p_code;
            if p_code = x"A" then c_code <= x"1"; end if;
            c_addr <= p_addr;
            c_count <= p_count;
            c_arg <= p_arg;
            c_valid <= p_mask;
            ack_low <= "00";
            if p_code = x"2" or p_code = x"3" or p_code = x"B" then
              data_owner <= p_slot;
              data_active <= '1';
            elsif (p_code = x"1" and p_slot = data_owner) or p_code = x"A" then
              data_active <= '0';
            end if;
            st <= Q_ACK;
          end if;
        when Q_STOP_ACK =>
          if c_ready(stop_slot) = '0' then stop_low <= '1'; end if;
          if stop_low = '1' and c_ready(stop_slot) = '1' then st <= Q_DISPATCH; end if;
        when Q_ACK =>
          lows := ack_low or (not c_ready and p_mask);
          ack_low <= lows;
          if lows = p_mask and (c_ready and p_mask) = p_mask then st <= Q_IDLE; end if;
      end case;
    end if;
  end process;
end architecture;
