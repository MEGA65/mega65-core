--------------------------------------------------------------------------------
-- sd_cache: sector cache between the upper SD controller (sdcardio_native)
-- and the native SD controller (sdcard_native).  MEGA65/mega65-core#953.
--
-- Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project.
-- Released under the GNU Lesser General Public License v3 (as LICENSE.txt).
--
-- Both sides of this entity have the host interface of sdcard_native (command
-- mailbox, status, read stream, write fetch), so it sits transparently in
-- between: "u_" is the side towards sdcardio_native, "d_" the side towards
-- sdcard_native.  All of it runs on cpuclock.
--
-- With G_LINES = 0 it is only wires.
--
-- DATA CACHE (this version)
--
--   * Lines of 4 KB (8 sectors), G_LINES of them, one RAMB36 each.  Tags are
--     fully associative (compared in parallel); each sector of a line has
--     its own valid bit.
--   * A single-sector C_READ is looked up:
--       hit:  the sector streams out of the cache BRAM (512 cycles);
--       miss: a line is chosen (an unused one, else by the replacement
--             policy) and the controller reads from the requested sector to
--             the end of the line.  The first sector goes up as it arrives;
--             the rest arrive in the background (blocks are granted one ahead
--             of the data, so the card is not paused between them).  The
--             read is complete for the upper controller as soon as its sector
--             is there.
--     A read of a sector that the background fill is about to bring waits
--     for it; any other command first ends the fill (C_STOP after the
--     blocks granted so far).  Sectors that did not arrive stay invalid.
--   * Everything else goes straight through: multi-sector reads (explicit
--     $07/$08/$09), writes, probe, accept, init.  Writes are write-through:
--     the bytes the controller fetches for a write are also written into the
--     cache if that sector is valid there.  A write that fails empties the
--     cache, and so does an init (which also covers a slot change).
--   * C_CACHE (code 8): arg bits 1..0 = 0 cache off, 1 cache on, 2 empty the
--     cache, 3 set the replacement policy (arg bit 4: 0 random, 1 LRU).
--   * C_READ with arg bit 15 set is a file system metadata read.  The META
--     CACHE (G_META one-sector slots, LRU by default) holds those: a miss
--     there reads just that sector and does not take a 4 KB data line.
--     Every single-sector read looks in both caches; writes update both.
--   * SEQUENTIAL READ-AHEAD: when single-sector reads are sequential, the
--     fill becomes a stream.  Its open multi-block read is not closed at
--     the end of the line: as the reader gets within G_AHEAD lines of the
--     stream's end, the next line is allocated and 8 more blocks granted.
--     If the reader stops, the grants run out and the card waits (clock
--     stopped); anything else ends the stream with C_STOP.  Lines filled by
--     a stream are replaced before others once the stream has passed them.
--   * C_CACHE arg 3 (policy): arg bit 5 = 0 data cache, 1 meta cache; arg
--     bit 4 = 0 random, 1 LRU.
--   * media_change(slot) (a card detect change): that slot's sectors are
--     forgotten.
--   * hits / misses count single-sector reads served from the cache / from
--     the card.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sd_cache is
  generic (
    G_LINES  : natural := 16;       -- 4 KB lines (RAMB36 each); 0 = no cache
    G_META   : natural := 16;       -- metadata sector slots (8 per RAMB36); 0 = none
    G_AHEAD  : natural := 2;        -- read-ahead: lines ahead of a sequential reader
    G_WR_LAT : natural := 2         -- write fetch latency (only 2 supported)
    -- (G_LINES <= 255)
    );
  port (
    clock : in std_logic;           -- cpuclock

    -- towards sdcardio_native ------------------------------------------------
    u_cmd_valid   : in  std_logic;
    u_cmd_ready   : out std_logic;
    u_cmd_code    : in  unsigned(3 downto 0);
    u_cmd_addr    : in  unsigned(31 downto 0);
    u_cmd_count   : in  unsigned(15 downto 0);
    u_cmd_arg     : in  unsigned(15 downto 0);
    u_cmd_slot    : in  std_logic := '0';
    u_limit_enable : in std_logic := '0';
    u_capacity_valid : in std_logic := '0';
    u_last_sector : in unsigned(31 downto 0) := (others => '0');
    u_card_ready  : out std_logic;
    u_busy        : out std_logic;
    u_waiting     : out std_logic;
    u_error       : out std_logic;
    u_err_code    : out unsigned(7 downto 0);
    u_native_mode : out std_logic;
    u_high_speed  : out std_logic;
    u_sdhc        : out std_logic;
    u_clk_setting : out unsigned(15 downto 0);
    u_probe_pass  : out unsigned(7 downto 0);
    u_probe_fail  : out unsigned(7 downto 0);
    u_blocks_done : out unsigned(15 downto 0);
    u_rd_valid    : out std_logic;
    u_rd_data     : out unsigned(7 downto 0);
    u_rd_offset   : out unsigned(8 downto 0);
    u_rd_block    : out unsigned(15 downto 0);
    u_rd_good     : out std_logic;
    u_rd_bad      : out std_logic;
    u_wr_fetch    : out std_logic;
    u_wr_offset   : out unsigned(8 downto 0);
    u_wr_block    : out unsigned(15 downto 0);
    u_wr_data     : in  unsigned(7 downto 0);

    -- towards sdcard_native -----------------------------------------------------
    d_cmd_valid   : out std_logic;
    d_cmd_ready   : in  std_logic;
    d_cmd_code    : out unsigned(3 downto 0);
    d_cmd_addr    : out unsigned(31 downto 0);
    d_cmd_count   : out unsigned(15 downto 0);
    d_cmd_arg     : out unsigned(15 downto 0);
    d_cmd_slot    : out std_logic;
    d_cards_status : in unsigned(63 downto 0) := (others => '0');
    d_card_ready  : in  std_logic;
    d_busy        : in  std_logic;
    d_waiting     : in  std_logic;
    d_error       : in  std_logic;
    d_err_code    : in  unsigned(7 downto 0);
    d_native_mode : in  std_logic;
    d_high_speed  : in  std_logic;
    d_sdhc        : in  std_logic;
    d_clk_setting : in  unsigned(15 downto 0);
    d_probe_pass  : in  unsigned(7 downto 0);
    d_probe_fail  : in  unsigned(7 downto 0);
    d_blocks_done : in  unsigned(15 downto 0);
    d_rd_valid    : in  std_logic;
    d_rd_data     : in  unsigned(7 downto 0);
    d_rd_offset   : in  unsigned(8 downto 0);
    d_rd_block    : in  unsigned(15 downto 0);
    d_rd_good     : in  std_logic;
    d_rd_bad      : in  std_logic;
    d_wr_fetch    : in  std_logic;
    d_wr_offset   : in  unsigned(8 downto 0);
    d_wr_block    : in  unsigned(15 downto 0);
    d_wr_data     : out unsigned(7 downto 0);

    -- a slot's card was removed or inserted: forget its sectors
    media_change  : in  std_logic_vector(1 downto 0) := "00";

    -- statistics -------------------------------------------------------------
    cache_on      : out std_logic;
    cache_hits    : out unsigned(15 downto 0);
    cache_misses  : out unsigned(15 downto 0)
    );
end entity sd_cache;

architecture rtl of sd_cache is

  constant C_INIT   : unsigned(3 downto 0) := x"1";
  constant C_READ   : unsigned(3 downto 0) := x"2";
  constant C_WRITE  : unsigned(3 downto 0) := x"3";
  constant C_MORE   : unsigned(3 downto 0) := x"4";
  constant C_STOP   : unsigned(3 downto 0) := x"5";
  constant C_CACHE  : unsigned(3 downto 0) := x"8";
  constant C_CLEAR  : unsigned(3 downto 0) := x"9";
  constant C_INIT_BOTH : unsigned(3 downto 0) := x"A";

  function slot_index(s : std_logic) return natural is
  begin
    if s = '1' then return 1; else return 0; end if;
  end function;

  function boolean_to_sl(b : boolean) return std_logic is
  begin
    if b then return '1'; else return '0'; end if;
  end function;

  function log2c(n : natural) return natural is
    variable r : natural := 0;
  begin
    while 2 ** r < n loop
      r := r + 1;
    end loop;
    return r;
  end function;

begin

  ------------------------------------------------------------------------------
  -- no cache: wires
  ------------------------------------------------------------------------------
  no_cache : if G_LINES = 0 generate
    d_cmd_valid   <= u_cmd_valid;
    u_cmd_ready   <= d_cmd_ready;
    d_cmd_code    <= u_cmd_code;
    d_cmd_addr    <= u_cmd_addr;
    d_cmd_count   <= u_cmd_count;
    d_cmd_arg     <= u_cmd_arg;
    d_cmd_slot    <= u_cmd_slot;
    u_card_ready  <= d_card_ready;
    u_busy        <= d_busy;
    u_waiting     <= d_waiting;
    u_error       <= d_error;
    u_err_code    <= d_err_code;
    u_native_mode <= d_native_mode;
    u_high_speed  <= d_high_speed;
    u_sdhc        <= d_sdhc;
    u_clk_setting <= d_clk_setting;
    u_probe_pass  <= d_probe_pass;
    u_probe_fail  <= d_probe_fail;
    u_blocks_done <= d_blocks_done;
    u_rd_valid    <= d_rd_valid;
    u_rd_data     <= d_rd_data;
    u_rd_offset   <= d_rd_offset;
    u_rd_block    <= d_rd_block;
    u_rd_good     <= d_rd_good;
    u_rd_bad      <= d_rd_bad;
    u_wr_fetch    <= d_wr_fetch;
    u_wr_offset   <= d_wr_offset;
    u_wr_block    <= d_wr_block;
    d_wr_data     <= u_wr_data;
    cache_on      <= '0';
    cache_hits    <= (others => '0');
    cache_misses  <= (others => '0');
  end generate;

  ------------------------------------------------------------------------------
  -- the cache
  ------------------------------------------------------------------------------
  with_cache : if G_LINES /= 0 generate

    constant LW : natural := log2c(G_LINES);      -- line index bits
    constant AW : natural := LW + 12;              -- data address bits

    -- the data: G_LINES x 4 KB
    type t_mem is array (0 to G_LINES * 4096 - 1) of unsigned(7 downto 0);
    signal mem : t_mem := (others => (others => '0'));
    attribute ram_style : string;
    attribute ram_style of mem : signal is "block";
    signal wa_en   : std_logic := '0';
    signal wa_addr : unsigned(AW-1 downto 0) := (others => '0');
    signal wa_data : unsigned(7 downto 0) := (others => '0');
    signal rb_addr : unsigned(AW-1 downto 0) := (others => '0');
    signal rb_q    : unsigned(7 downto 0) := (others => '0');

    -- the tags
    type t_tags  is array (0 to G_LINES-1) of unsigned(28 downto 0);   -- sector / 8
    type t_vld   is array (0 to G_LINES-1) of std_logic_vector(7 downto 0);
    type t_stamp is array (0 to G_LINES-1) of unsigned(15 downto 0);
    signal tag    : t_tags := (others => (others => '0'));
    signal tag_slot : std_logic_vector(G_LINES-1 downto 0) := (others => '0');
    signal used   : std_logic_vector(G_LINES-1 downto 0) := (others => '0');
    signal vld    : t_vld := (others => (others => '0'));
    signal stamp  : t_stamp := (others => (others => '0'));
    signal now_ts : unsigned(15 downto 0) := (others => '0');

    signal enabled : std_logic := '1';
    signal lru     : std_logic := '0';     -- 0 random, 1 LRU
    signal lfsr    : unsigned(15 downto 0) := x"ACE1";
    signal hits    : unsigned(15 downto 0) := (others => '0');
    signal misses  : unsigned(15 downto 0) := (others => '0');

    -- upstream command, as taken
    signal u_ready : std_logic := '1';
    signal c_code  : unsigned(3 downto 0) := (others => '0');
    signal c_addr  : unsigned(31 downto 0) := (others => '0');
    signal c_count : unsigned(15 downto 0) := (others => '0');
    signal c_arg   : unsigned(15 downto 0) := (others => '0');
    signal c_slot  : std_logic := '0';
    signal c_limited, c_capacity : std_logic := '0';
    signal c_last : unsigned(31 downto 0) := (others => '0');

    -- pass-through: upstream sees the controller's status and streams
    signal pt      : std_logic := '1';
    signal pt_wr   : std_logic := '0';     -- (a write: snoop it)
    signal pt_addr : unsigned(31 downto 0) := (others => '0');
    signal pt_slot : std_logic := '0';

    -- own status (when not pass-through)
    signal o_busy  : std_logic := '0';
    signal o_error : std_logic := '0';
    signal o_err   : unsigned(7 downto 0) := (others => '0');
    signal o_done  : unsigned(15 downto 0) := (others => '0');
    signal o_rv    : std_logic := '0';
    signal o_rgood : std_logic := '0';
    signal o_roff  : unsigned(8 downto 0) := (others => '0');
    signal fwd0    : std_logic := '0';     -- pass up block 0 of the controller's read

    -- the controller's mailbox
    signal dv      : std_logic := '0';
    signal dcode   : unsigned(3 downto 0) := (others => '0');
    signal daddr   : unsigned(31 downto 0) := (others => '0');
    signal dcount  : unsigned(15 downto 0) := (others => '0');
    signal darg    : unsigned(15 downto 0) := (others => '0');
    signal dslot   : std_logic := '0';
    signal dquiet_cnt : integer range 0 to 3 := 0;
    signal dfree   : std_logic;            -- may issue now

    -- the fill: one open read from f_start on, into the lines of a window
    -- (win(j) holds line number win_first + j); a plain fill has one line, a
    -- stream several
    -- at least one line outside the window, and the reader's line never
    -- drops out of it: W <= G_LINES - 1, AH <= W - 1 (W < 2: no streaming)
    function minn(a, b : integer) return integer is
    begin
      if a < b then return a; else return b; end if;
    end function;
    constant W  : natural := minn(G_AHEAD + 2, minn(G_LINES - 1, 8)) + boolean'pos(G_LINES <= 1);
    constant AH : natural := minn(G_AHEAD, W - 1);
    type t_win is array (0 to W-1) of integer range 0 to G_LINES-1;
    signal fill     : std_logic := '0';
    signal stream   : std_logic := '0';     -- no "last" grant: may grow
    signal f_slot   : std_logic := '0';
    signal f_line   : integer range 0 to G_LINES-1 := 0;
    signal f_first  : unsigned(2 downto 0) := (others => '0');   -- first sector
    signal f_start  : unsigned(31 downto 0) := (others => '0');  -- sector of block 0
    signal f_total  : unsigned(15 downto 0) := (others => '0');  -- blocks wanted
    signal f_grant  : unsigned(15 downto 0) := (others => '0');  -- blocks granted
    signal f_recv   : unsigned(15 downto 0) := (others => '0');  -- blocks received
    signal f_limited, f_capacity : std_logic := '0';
    signal f_last   : unsigned(31 downto 0) := (others => '0');
    signal win      : t_win := (others => 0);
    signal win_first : unsigned(28 downto 0) := (others => '0');
    signal win_n    : integer range 0 to W := 0;
    signal ext_req  : std_logic := '0';     -- the stream should grow
    signal line_strm : std_logic_vector(G_LINES-1 downto 0) := (others => '0');

    -- sequential reads
    signal seq_next : unsigned(31 downto 0) := (others => '1');
    signal seq_slot : std_logic := '0';
    signal seq_run  : std_logic := '0';     -- the last read followed the one before

    -- the meta cache: G_META one-sector slots
    constant MS : natural := G_META + boolean'pos(G_META = 0);   -- (>= 1)
    constant MW : natural := log2c(MS) + 9;
    type t_mmem is array (0 to MS * 512 - 1) of unsigned(7 downto 0);
    type t_mtag is array (0 to MS-1) of unsigned(31 downto 0);
    type t_mstamp is array (0 to MS-1) of unsigned(15 downto 0);
    signal mmem    : t_mmem := (others => (others => '0'));
    attribute ram_style of mmem : signal is "block";
    signal mwa_en  : std_logic := '0';
    signal mwa_addr : unsigned(MW-1 downto 0) := (others => '0');
    signal mwa_data : unsigned(7 downto 0) := (others => '0');
    signal mrb_addr : unsigned(MW-1 downto 0) := (others => '0');
    signal mrb_q   : unsigned(7 downto 0) := (others => '0');
    signal mtag    : t_mtag := (others => (others => '0'));
    signal mslot   : std_logic_vector(MS-1 downto 0) := (others => '0');
    signal mvld    : std_logic_vector(MS-1 downto 0) := (others => '0');
    signal mstamp  : t_mstamp := (others => (others => '0'));
    signal mlru    : std_logic := '1';     -- 0 random, 1 LRU
    signal m_fill  : std_logic := '0';     -- a meta miss is being read
    signal m_line  : integer range 0 to MS-1 := 0;
    signal o_msrc  : std_logic := '0';     -- the hit comes from the meta cache

    -- serving a request
    type t_st is (T_IDLE, T_PT_WAIT, T_STOPFILL, T_STOPFILL_WAIT, T_DISPATCH,
                  T_VICTIM, T_MISS_CMD, T_MISS_WAIT, T_WAITSEC, T_HIT, T_HIT_END,
                  T_EXTEND, T_MVICTIM, T_MMISS_CMD);
    signal st       : t_st := T_IDLE;
    signal r_line   : integer range 0 to G_LINES-1 := 0;
    signal r_sec    : unsigned(2 downto 0) := (others => '0');
    signal r_cnt    : unsigned(9 downto 0) := (others => '0');
    signal v_i      : integer range 0 to G_LINES := 0;   -- victim scan
    signal v_best   : integer range 0 to G_LINES-1 := 0;
    signal v_age    : unsigned(15 downto 0) := (others => '0');
    signal v_free   : std_logic := '0';
    signal v_ext    : std_logic := '0';     -- the scan is for a stream extension
    signal v_strm   : std_logic := '0';     -- found a passed streaming line
    signal v_strm_i : integer range 0 to G_LINES-1 := 0;

    -- write snooping
    signal s1_v     : std_logic := '0';
    signal s1_sec   : unsigned(31 downto 0) := (others => '0');
    signal s1_off   : unsigned(8 downto 0) := (others => '0');
    signal s2_v     : std_logic := '0';
    signal s2_addr  : unsigned(AW-1 downto 0) := (others => '0');
    signal s2_mv    : std_logic := '0';
    signal s2_maddr : unsigned(MW-1 downto 0) := (others => '0');

    -- look a sector up: hit (a line holds it, valid or not) and the line
    procedure lookup(signal tg : in t_tags; signal ts, us : in std_logic_vector;
                     sector : in unsigned(31 downto 0); slot : in std_logic;
                     variable hit : out boolean; variable idx : out integer) is
    begin
      hit := false;
      idx := 0;
      for i in 0 to G_LINES-1 loop
        if us(i) = '1' and ts(i) = slot and tg(i) = sector(31 downto 3) then
          hit := true;
          idx := i;
        end if;
      end loop;
    end procedure;

    -- look a sector up in the meta cache
    procedure mlookup(signal tg : in t_mtag; signal ts, vs : in std_logic_vector;
                      sector : in unsigned(31 downto 0); slot : in std_logic;
                      variable hit : out boolean; variable idx : out integer) is
    begin
      hit := false;
      idx := 0;
      if G_META /= 0 then
        for i in 0 to MS-1 loop
          if vs(i) = '1' and ts(i) = slot and tg(i) = sector then
            hit := true;
            idx := i;
          end if;
        end loop;
      end if;
    end procedure;

    function mmaddr(line : integer; off : unsigned(8 downto 0)) return unsigned is
      variable a : unsigned(MW-1 downto 0);
    begin
      a := to_unsigned(line, MW - 9) & off;
      return a;
    end function;

    function maddr(line : integer; sec : unsigned(2 downto 0);
                   off : unsigned(8 downto 0)) return unsigned is
      variable a : unsigned(AW-1 downto 0);
    begin
      a := to_unsigned(line, LW) & sec & off;
      return a;
    end function;

  begin

    assert G_WR_LAT = 2 report "sd_cache: only G_WR_LAT = 2 is supported" severity failure;

    cache_on     <= enabled;
    cache_hits   <= hits;
    cache_misses <= misses;

    -- the card side status always passes through
    u_card_ready  <= d_card_ready when u_cmd_slot = dslot else d_cards_status(slot_index(u_cmd_slot)*32);
    u_native_mode <= d_native_mode when u_cmd_slot = dslot else d_cards_status(slot_index(u_cmd_slot)*32+12);
    u_high_speed  <= d_high_speed when u_cmd_slot = dslot else d_cards_status(slot_index(u_cmd_slot)*32+13);
    u_sdhc        <= d_sdhc when u_cmd_slot = dslot else d_cards_status(slot_index(u_cmd_slot)*32+14);
    u_clk_setting <= d_clk_setting when u_cmd_slot = dslot else
      d_cards_status(slot_index(u_cmd_slot)*32+31 downto slot_index(u_cmd_slot)*32+16);
    u_probe_pass  <= d_probe_pass;
    u_probe_fail  <= d_probe_fail;

    u_cmd_ready   <= u_ready;
    u_busy <= o_busy when pt = '0' and u_cmd_slot = c_slot else
              d_busy when u_cmd_slot = dslot else d_cards_status(slot_index(u_cmd_slot)*32+1);
    u_waiting <= '0' when pt = '0' and u_cmd_slot = c_slot else
              d_waiting when u_cmd_slot = dslot else d_cards_status(slot_index(u_cmd_slot)*32+2);
    u_error <= o_error when pt = '0' and u_cmd_slot = c_slot else
              d_error when u_cmd_slot = dslot else d_cards_status(slot_index(u_cmd_slot)*32+3);
    u_err_code <= o_err when pt = '0' and u_cmd_slot = c_slot else
              d_err_code when u_cmd_slot = dslot else
              d_cards_status(slot_index(u_cmd_slot)*32+11 downto slot_index(u_cmd_slot)*32+4);
    u_blocks_done <= d_blocks_done when pt = '1' else o_done;

    -- read stream: the controller's (pass-through, or block 0 of a miss), or
    -- the cache's own
    u_rd_valid  <= d_rd_valid when pt = '1' else
                   o_rv or (fwd0 and d_rd_valid and boolean_to_sl(d_rd_block = 0));
    u_rd_data   <= mrb_q when pt = '0' and o_rv = '1' and o_msrc = '1' else
                   rb_q when pt = '0' and o_rv = '1' else d_rd_data;
    u_rd_offset <= o_roff when pt = '0' and o_rv = '1' else d_rd_offset;
    u_rd_block  <= d_rd_block when pt = '1' else (others => '0');
    u_rd_good   <= d_rd_good when pt = '1' else
                   o_rgood or (fwd0 and d_rd_good and boolean_to_sl(d_rd_block = 0));
    u_rd_bad    <= d_rd_bad when pt = '1' else
                   fwd0 and d_rd_bad and boolean_to_sl(d_rd_block = 0);

    -- writes only happen in pass-through: the fetches go straight through
    u_wr_fetch  <= d_wr_fetch;
    u_wr_offset <= d_wr_offset;
    u_wr_block  <= d_wr_block;
    d_wr_data   <= u_wr_data;

    d_cmd_valid <= dv;
    d_cmd_code  <= dcode;
    d_cmd_addr  <= daddr;
    d_cmd_count <= dcount;
    d_cmd_arg   <= darg;
    d_cmd_slot  <= dslot;
    dfree       <= '1' when dquiet_cnt = 0 and dv = '0' and d_cmd_ready = '1' else '0';

    -- the data RAM: port A writes (fill, write snoop), port B reads (hits)
    ram : process (clock)
    begin
      if rising_edge(clock) then
        if wa_en = '1' then
          mem(to_integer(wa_addr)) <= wa_data;
        end if;
        rb_q <= mem(to_integer(rb_addr));
      end if;
    end process ram;

    mram : process (clock)
    begin
      if rising_edge(clock) then
        if mwa_en = '1' then
          mmem(to_integer(mwa_addr)) <= mwa_data;
        end if;
        mrb_q <= mmem(to_integer(mrb_addr));
      end if;
    end process mram;

    ctrl : process (clock)

      procedure dcmd(code : unsigned(3 downto 0); addr : unsigned(31 downto 0);
                     count : unsigned(15 downto 0); arg : unsigned(15 downto 0); slot : std_logic) is
      begin
        dv         <= '1';
        dcode      <= code;
        daddr      <= addr;
        dcount     <= count;
        darg       <= arg;
        dslot      <= slot;
        dquiet_cnt <= 3;
      end procedure;

      procedure flush_slot(slot : std_logic) is
      begin
        for i in 0 to G_LINES-1 loop
          if tag_slot(i) = slot then
            used(i) <= '0';
            vld(i) <= (others => '0');
          end if;
        end loop;
        for i in 0 to MS-1 loop
          if mslot(i) = slot then
            mvld(i) <= '0';
          end if;
        end loop;
      end procedure;

      procedure flush_all is
      begin
        used <= (others => '0');
        for i in 0 to G_LINES-1 loop
          vld(i) <= (others => '0');
        end loop;
        mvld <= (others => '0');
      end procedure;

      -- line i is one of the stream window's lines
      function in_window(i : integer; signal wn : integer; signal wl : t_win) return boolean is
      begin
        for j in 0 to W-1 loop
          if j < wn and wl(j) = i then
            return true;
          end if;
        end loop;
        return false;
      end function;

      variable hit  : boolean;
      variable idx  : integer range 0 to G_LINES-1;
      variable sec  : unsigned(31 downto 0);
      variable k    : unsigned(2 downto 0);
      variable age  : unsigned(15 downto 0);
      variable rnd  : integer range 0 to G_LINES-1;
      variable fill_writes : boolean;
      variable target_busy : std_logic;
      variable fill_count : unsigned(3 downto 0);
      variable mhit : boolean;
      variable midx : integer range 0 to MS-1;
      variable fs   : unsigned(31 downto 0);
      variable fj   : integer range 0 to W-1;
      variable seq  : boolean;
      variable more_blocks : unsigned(15 downto 0);

    begin
      if rising_edge(clock) then
        target_busy := d_busy;
        if c_slot /= dslot then target_busy := d_cards_status(slot_index(c_slot)*32+1); end if;
        dv      <= '0';
        wa_en   <= '0';
        mwa_en  <= '0';
        o_rv    <= '0';
        o_rgood <= '0';
        if dquiet_cnt /= 0 then
          dquiet_cnt <= dquiet_cnt - 1;
        end if;
        lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
        fill_writes := false;

        ------------------------------------------------------------------------
        -- the controller's read stream: into the line being filled
        ------------------------------------------------------------------------
        -- the block's sector, and its line in the window
        fs := f_start + resize(d_rd_block, 32);
        fj := 0;
        for j in 0 to W-1 loop
          if fs(31 downto 3) - win_first = to_unsigned(j, 29) then
            fj := j;
          end if;
        end loop;
        k := fs(2 downto 0);
        if fill = '1' and pt = '0' and d_rd_valid = '1' then
          wa_en   <= '1';
          wa_addr <= maddr(win(fj), k, d_rd_offset);
          wa_data <= d_rd_data;
          fill_writes := true;
        end if;
        if fill = '1' and pt = '0' and d_rd_good = '1' then
          vld(win(fj))(to_integer(k)) <= '1';
          f_recv <= f_recv + 1;
          if d_rd_block = 0 then
            fwd0   <= '0';
            o_busy <= '0';
            o_done <= to_unsigned(1, 16);
          end if;
          if f_recv + 1 = f_total and stream = '0' then
            fill <= '0';              -- (the controller ends the transfer itself)
          end if;
        end if;
        -- a meta miss: its one sector into its slot
        if m_fill = '1' and pt = '0' and d_rd_valid = '1' then
          mwa_en   <= '1';
          mwa_addr <= mmaddr(m_line, d_rd_offset);
          mwa_data <= d_rd_data;
        end if;
        if m_fill = '1' and pt = '0' and d_rd_good = '1' then
          mvld(m_line) <= '1';
          m_fill <= '0';
          fwd0   <= '0';
          o_busy <= '0';
          o_done <= to_unsigned(1, 16);
        end if;

        -- more blocks for the fill, one ahead of the data
        if fill = '1' and f_grant /= f_total and f_grant < f_recv + 2 and dfree = '1'
          and (st = T_IDLE or st = T_WAITSEC or st = T_HIT or st = T_HIT_END
               or st = T_MISS_WAIT or (v_ext = '1' and (st = T_VICTIM or st = T_EXTEND))) then
          if f_grant + 1 = f_total and stream = '0' then
            dcmd(C_MORE, (others => '0'), (others => '0'), x"0001", f_slot);
          else
            dcmd(C_MORE, (others => '0'), (others => '0'), x"0000", f_slot);
          end if;
          f_grant <= f_grant + 1;
        end if;

        ------------------------------------------------------------------------
        -- write snooping (pass-through writes): the byte fetched now comes two
        -- cycles later; it goes into the cache if the sector is valid there
        ------------------------------------------------------------------------
        s1_v   <= d_wr_fetch and pt_wr;
        s1_sec <= pt_addr + resize(d_wr_block, 32);
        s1_off <= d_wr_offset;
        lookup(tag, tag_slot, used, s1_sec, pt_slot, hit, idx);
        if s1_v = '1' and hit and vld(idx)(to_integer(s1_sec(2 downto 0))) = '1' then
          s2_v <= '1';
        else
          s2_v <= '0';
        end if;
        s2_addr <= maddr(idx, s1_sec(2 downto 0), s1_off);
        mlookup(mtag, mslot, mvld, s1_sec, pt_slot, mhit, midx);
        if s1_v = '1' and mhit then
          s2_mv <= '1';
        else
          s2_mv <= '0';
        end if;
        s2_maddr <= mmaddr(midx, s1_off);
        if s2_v = '1' and not fill_writes then
          wa_en   <= '1';
          wa_addr <= s2_addr;
          wa_data <= u_wr_data;
        end if;
        if s2_mv = '1' then
          mwa_en   <= '1';
          mwa_addr <= s2_maddr;
          mwa_data <= u_wr_data;
        end if;

        ------------------------------------------------------------------------
        -- requests
        ------------------------------------------------------------------------
        case st is

          when T_IDLE =>
            if u_cmd_valid = '1' and u_ready = '1' then
              u_ready <= '0';
              c_code  <= u_cmd_code;
              c_addr  <= u_cmd_addr;
              c_count <= u_cmd_count;
              c_arg   <= u_cmd_arg;
              c_slot  <= u_cmd_slot;
              c_limited <= u_limit_enable; c_capacity <= u_capacity_valid; c_last <= u_last_sector;
              if u_cmd_code = C_INIT_BOTH then
                -- the controller drops everything at once: no need to stop
                -- the fill first
                flush_all;
                fill    <= '0';
                stream  <= '0';
                ext_req <= '0';
                m_fill  <= '0';
                fwd0    <= '0';
                st      <= T_DISPATCH;
              elsif u_cmd_code = C_INIT then
                flush_slot(u_cmd_slot);
                if fill = '1' and u_cmd_slot /= f_slot then
                  st <= T_STOPFILL;
                else
                  fill <= '0';
                  stream  <= '0';
                  ext_req <= '0';
                  m_fill  <= '0';
                  fwd0 <= '0';
                  st <= T_DISPATCH;
                end if;
              elsif fill = '1' and not (u_cmd_code = C_READ and u_cmd_count = 1
                                        and enabled = '1' and u_cmd_slot = f_slot) then
                st <= T_STOPFILL;
              else
                st <= T_DISPATCH;
              end if;
            end if;

          -- end the background fill: no more grants, then the controller idle
          when T_STOPFILL =>
            -- no more grants (this state does not give any); C_STOP ends an
            -- open transfer after the blocks granted so far
            if fill = '0' then
              if dfree = '1' and d_busy = '0' then
                st <= T_DISPATCH;
              end if;
            elsif dfree = '1' then
              if f_grant /= f_total or stream = '1' then
                dcmd(C_STOP, (others => '0'), (others => '0'), (others => '0'), f_slot);
                f_total <= f_grant;
              end if;
              stream  <= '0';
              ext_req <= '0';
              st <= T_STOPFILL_WAIT;
            end if;

          when T_STOPFILL_WAIT =>
            if dfree = '1' and d_busy = '0' then
              fill <= '0';
              st   <= T_DISPATCH;
            end if;

          -- what to do with the request
          when T_DISPATCH =>
            sec := c_addr;
            lookup(tag, tag_slot, used, sec, c_slot, hit, idx);
            if (c_code = C_READ or c_code = C_WRITE) and c_limited = '1'
              and (c_capacity = '0' or resize(c_addr, 33) > resize(c_last, 33)
                or (c_count /= 0 and resize(c_addr, 33) + resize(c_count-1, 33) > resize(c_last, 33))) then
              -- Check before lookup too: an override may have cached data
              -- beyond the card's size before protection was re-enabled.
              pt <= '0'; o_busy <= '0'; o_error <= '1'; o_done <= (others => '0');
              if c_capacity = '0' then o_err <= x"45"; else o_err <= x"44"; end if;
              u_ready <= '1'; st <= T_IDLE;
            elsif c_code = C_CACHE then
              -- A completed fill may still be closing CMD12 / tail clocks.
              -- Do not hide that busy period when changing to own status.
              if dfree = '1' and target_busy = '0' then
                case c_arg(1 downto 0) is
                  when "00" => enabled <= '0';
                               flush_all;
                  when "01" => enabled <= '1';
                  when "10" => flush_all;
                  when others =>
                    if c_arg(5) = '1' then
                      mlru <= c_arg(4);
                    else
                      lru <= c_arg(4);
                    end if;
                end case;
                pt      <= '0';
                o_busy  <= '0';
                o_error <= '0';
                o_err   <= (others => '0');
                u_ready <= '1';
                st      <= T_IDLE;
              end if;
            elsif c_code = C_READ and c_count = 1 and enabled = '1' then
              pt      <= '0';
              o_busy  <= '1';
              o_error <= '0';
              o_err   <= (others => '0');
              o_done  <= (others => '0');
              o_msrc  <= '0';
              u_ready <= '0';
              r_sec   <= sec(2 downto 0);
              mlookup(mtag, mslot, mvld, sec, c_slot, mhit, midx);
              -- data reads that follow each other make the fill a stream
              seq := c_arg(15) = '0' and c_slot = seq_slot and sec = seq_next;
              if c_arg(15) = '0' then
                seq_next <= sec + 1;
                seq_slot <= c_slot;
                seq_run  <= boolean_to_sl(seq);
              end if;
              if seq and fill = '1' and c_slot = f_slot and stream = '0'
                and f_grant /= f_total then
                -- (the last grant has not gone yet: it can still grow)
                stream <= '1';
              end if;
              if seq and fill = '1' and c_slot = f_slot
                and (stream = '1' or f_grant /= f_total) and win_n > 0
                and AH > 0 and W >= 2
                and sec(31 downto 3) - win_first + AH >= to_unsigned(win_n, 29) then
                ext_req <= '1';
              end if;
              if hit and vld(idx)(to_integer(sec(2 downto 0))) = '1' then
                r_line <= idx;
                r_cnt  <= (others => '0');
                hits   <= hits + 1;
                stamp(idx) <= now_ts;
                now_ts <= now_ts + 1;
                if not seq then
                  line_strm(idx) <= '0';   -- used again: keep it like any other
                end if;
                st     <= T_HIT;
              elsif hit and fill = '1' and c_slot = f_slot
                and sec - f_start < resize(f_total, 32) then
                -- on its way in
                r_line <= idx;
                st     <= T_WAITSEC;
              elsif mhit then
                -- in the meta cache
                m_line <= midx;
                r_cnt  <= (others => '0');
                o_msrc <= '1';
                hits   <= hits + 1;
                mstamp(midx) <= now_ts;
                now_ts <= now_ts + 1;
                st     <= T_HIT;
              elsif c_arg(15) = '1' and G_META /= 0 then
                -- a metadata miss: one sector into the meta cache
                if fill = '1' then
                  st <= T_STOPFILL;
                else
                  misses <= misses + 1;
                  v_i    <= 0;
                  v_free <= '0';
                  v_age  <= (others => '0');
                  st     <= T_MVICTIM;
                end if;
              elsif hit and fill = '0' then
                -- the line is here but not this sector: fill it from here
                r_line <= idx;
                misses <= misses + 1;
                st     <= T_MISS_CMD;
              elsif fill = '1' then
                st <= T_STOPFILL;
              else
                -- choose a line
                misses <= misses + 1;
                v_i    <= 0;
                v_free <= '0';
                v_strm <= '0';
                v_ext  <= '0';
                v_age  <= (others => '0');
                st     <= T_VICTIM;
              end if;
            else
              -- straight through
              if dfree = '1' and (target_busy = '0' or c_code = C_INIT or c_code = C_INIT_BOTH
                                   or c_code = C_MORE or c_code = C_STOP) then
                if c_code = C_CLEAR then
                  flush_slot(c_slot);
                end if;
                pt <= '1';
                if c_code = C_WRITE then
                  pt_wr   <= '1';
                  pt_addr <= c_addr;
                  pt_slot <= c_slot;
                elsif c_code /= C_MORE and c_code /= C_STOP then
                  pt_wr <= '0';
                end if;
                dcmd(c_code, c_addr, c_count, c_arg, c_slot);
                st <= T_PT_WAIT;
              end if;
            end if;

          when T_PT_WAIT =>
            -- the controller's status reflects the command: so does ours
            if dfree = '1' then
              u_ready <= '1';
              st      <= T_IDLE;
            end if;

          -- choose a line to replace: an unused one, else the oldest (LRU)
          -- or a random one
          -- (an unused line first, then a line a stream has passed, then by the
          -- policy; never a line of the stream's window)
          when T_VICTIM =>
            if v_i = G_LINES then
              rnd := to_integer(shift_right(resize(lfsr(7 downto 0), 16)
                                            * to_unsigned(G_LINES, 8), 8));
              if v_free = '1' or (lru = '1' and v_ext = '0') then
                r_line <= v_best;
              elsif v_strm = '1' then
                r_line <= v_strm_i;
              elsif lru = '1' or (v_ext = '1' and in_window(rnd, win_n, win)) then
                r_line <= v_best;
              else
                r_line <= rnd;
              end if;
              if v_ext = '1' then
                st <= T_EXTEND;
              else
                st <= T_MISS_CMD;
              end if;
            else
              age := now_ts - stamp(v_i);
              if v_ext = '1' and in_window(v_i, win_n, win) then
                null;
              elsif used(v_i) = '0' and v_free = '0' then
                v_free <= '1';
                v_best <= v_i;
              elsif v_free = '0' and (v_age = 0 or age > v_age) then
                v_best <= v_i;
                v_age  <= age;
              end if;
              if line_strm(v_i) = '1' and used(v_i) = '1' and v_strm = '0'
                and not (v_ext = '1' and in_window(v_i, win_n, win)) then
                v_strm   <= '1';
                v_strm_i <= v_i;
              end if;
              v_i <= v_i + 1;
            end if;

          -- the stream grows by the next line
          when T_EXTEND =>
            more_blocks := to_unsigned(8, 16);
            if f_limited = '1' and f_capacity = '1'
              and resize(f_last, 33) < resize(win_first + to_unsigned(win_n, 29), 33) * 8 + 7 then
              if resize(f_last, 33) < resize(win_first + to_unsigned(win_n, 29), 33) * 8 then
                more_blocks := (others => '0');       -- the card ends before it
              else
                more_blocks := resize(f_last(2 downto 0), 16) + 1;
              end if;
            end if;
            if more_blocks /= 0 and f_total < 60000 and fill = '1' and stream = '1' then
              tag(r_line)      <= win_first + to_unsigned(win_n, 29);
              tag_slot(r_line) <= f_slot;
              used(r_line)     <= '1';
              vld(r_line)      <= (others => '0');
              line_strm(r_line) <= '1';
              stamp(r_line)    <= now_ts;
              now_ts <= now_ts + 1;
              if win_n = W then
                -- the oldest line drops out of the window (the reader has
                -- passed it)
                for j in 0 to W-2 loop
                  win(j) <= win(j+1);
                end loop;
                win(W-1)  <= r_line;
                win_first <= win_first + 1;
              else
                win(win_n) <= r_line;
                win_n <= win_n + 1;
              end if;
              f_total <= f_total + more_blocks;
            end if;
            ext_req <= '0';
            v_ext   <= '0';
            u_ready <= '1';
            st      <= T_IDLE;

          -- choose a meta slot: an empty one, else the oldest (LRU) or random
          when T_MVICTIM =>
            if v_i = MS then
              if v_free = '1' or mlru = '1' then
                m_line <= v_best;
              else
                m_line <= to_integer(shift_right(resize(lfsr(7 downto 0), 16)
                                                 * to_unsigned(MS, 8), 8));
              end if;
              st <= T_MMISS_CMD;
            else
              age := now_ts - mstamp(v_i);
              if mvld(v_i) = '0' and v_free = '0' then
                v_free <= '1';
                v_best <= v_i;
              elsif v_free = '0' and (v_age = 0 or age > v_age) then
                v_best <= v_i;
                v_age  <= age;
              end if;
              v_i <= v_i + 1;
            end if;

          -- read the one sector
          when T_MMISS_CMD =>
            if dfree = '1' and target_busy = '0' then
              mtag(m_line)   <= c_addr;
              mslot(m_line)  <= c_slot;
              mvld(m_line)   <= '0';
              mstamp(m_line) <= now_ts;
              now_ts <= now_ts + 1;
              m_fill <= '1';
              fwd0   <= '1';
              dcmd(C_READ, c_addr, to_unsigned(1, 16), (others => '0'), c_slot);
              st <= T_MISS_WAIT;
            end if;

          -- read from the requested sector to the end of the line
          when T_MISS_CMD =>
            -- cmd_ready only means the mailbox is free. A first-sector
            -- completion is published upstream before the card finishes its
            -- stop/tail sequence. Wait for this card; the dual wrapper also
            -- retires another card's data stream, without waiting on init.
            if dfree = '1' and target_busy = '0' then
              if used(r_line) = '0' or tag_slot(r_line) /= c_slot or tag(r_line) /= c_addr(31 downto 3) then
                tag(r_line)  <= c_addr(31 downto 3);
                tag_slot(r_line) <= c_slot;
                used(r_line) <= '1';
                vld(r_line)  <= (others => '0');
              end if;
              stamp(r_line) <= now_ts;
              now_ts  <= now_ts + 1;
              f_line  <= r_line;
              f_slot  <= c_slot;
              f_first <= c_addr(2 downto 0);
              f_start <= c_addr;
              f_limited <= c_limited; f_capacity <= c_capacity; f_last <= c_last;
              win(0)    <= r_line;
              win_n     <= 1;
              win_first <= c_addr(31 downto 3);
              line_strm(r_line) <= seq_run;
              if W >= 2 and AH > 0 then
                stream  <= seq_run;
                ext_req <= seq_run;
              else
                stream  <= '0';
                ext_req <= '0';
              end if;
              fill_count := 8 - resize(c_addr(2 downto 0), 4);
              if c_limited = '1' and c_capacity = '1'
                and c_last-c_addr < resize(fill_count-1, 32) then
                fill_count := resize(c_last-c_addr, 4) + 1;
              end if;
              f_total <= resize(fill_count, 16);
              f_recv  <= (others => '0');
              f_grant <= to_unsigned(1, 16);
              fill    <= '1';
              fwd0    <= '1';
              if fill_count = 1 and (seq_run = '0' or W < 2 or AH = 0) then
                dcmd(C_READ, c_addr, to_unsigned(1, 16), (others => '0'), c_slot);
              else
                dcmd(C_READ, c_addr, to_unsigned(0, 16), (others => '0'), c_slot);
              end if;
              st <= T_MISS_WAIT;
            end if;

          -- the first sector streams up; done with it (or with an error)
          when T_MISS_WAIT =>
            if fwd0 = '0' and ext_req = '1' and fill = '1' and stream = '1' then
              v_ext  <= '1';
              v_i    <= 0;
              v_free <= '0';
              v_strm <= '0';
              v_age  <= (others => '0');
              st     <= T_VICTIM;
            elsif fwd0 = '0' then
              ext_req <= '0';
              u_ready <= '1';
              st      <= T_IDLE;
            elsif dfree = '1' and d_busy = '0' and d_error = '1' then
              -- the read failed: the line is no good
              if m_fill = '1' then
                mvld(m_line) <= '0';
              else
                used(f_line) <= '0';
                vld(f_line)  <= (others => '0');
              end if;
              fill    <= '0';
              stream  <= '0';
              ext_req <= '0';
              m_fill  <= '0';
              fwd0    <= '0';
              o_busy  <= '0';
              o_error <= '1';
              o_err   <= d_err_code;
              u_ready <= '1';
              st      <= T_IDLE;
            end if;

          -- the sector is on its way in
          when T_WAITSEC =>
            if vld(r_line)(to_integer(r_sec)) = '1' then
              r_cnt <= (others => '0');
              hits  <= hits + 1;
              stamp(r_line) <= now_ts;
              now_ts <= now_ts + 1;
              st     <= T_HIT;
            elsif fill = '0' then
              -- the fill ended without it: read it after all
              st <= T_STOPFILL;
            end if;

          -- stream the sector out of the cache (RAM read latency 1)
          when T_HIT =>
            rb_addr  <= maddr(r_line, r_sec, r_cnt(8 downto 0));
            mrb_addr <= mmaddr(m_line, r_cnt(8 downto 0));
            if r_cnt /= 0 then
              o_rv   <= '1';
              o_roff <= r_cnt(8 downto 0) - 1;
            end if;
            r_cnt <= r_cnt + 1;
            if r_cnt = 512 then
              st <= T_HIT_END;
            end if;

          when T_HIT_END =>
            o_rgood <= '1';
            o_busy  <= '0';
            o_done  <= to_unsigned(1, 16);
            if ext_req = '1' and fill = '1' and stream = '1' then
              -- grow the stream before taking the next command
              v_ext  <= '1';
              v_i    <= 0;
              v_free <= '0';
              v_strm <= '0';
              v_age  <= (others => '0');
              st     <= T_VICTIM;
            else
              ext_req <= '0';
              u_ready <= '1';
              st      <= T_IDLE;
            end if;

        end case;

        -- the controller failed while filling in the background: stop
        if fill = '1' and fwd0 = '0' and dfree = '1' and d_busy = '0' then
          fill    <= '0';
          stream  <= '0';
          ext_req <= '0';
        end if;

        -- a card was changed: forget its sectors (a fill from it may still be
        -- running; what it brings goes into lines that are no longer used)
        for i in 0 to 1 loop
          if media_change(i) = '1' then
            for j in 0 to G_LINES-1 loop
              if tag_slot(j) = boolean_to_sl(i = 1) then
                used(j) <= '0';
                vld(j)  <= (others => '0');
              end if;
            end loop;
            for j in 0 to MS-1 loop
              if mslot(j) = boolean_to_sl(i = 1) then
                mvld(j) <= '0';
              end if;
            end loop;
            if f_slot = boolean_to_sl(i = 1) then
              ext_req <= '0';
            end if;
          end if;
        end loop;

        -- a pass-through write that failed: the cache may be stale
        if pt = '1' and pt_wr = '1' and st = T_IDLE and dfree = '1'
          and d_busy = '0' and d_error = '1' then
          flush_slot(pt_slot);
          pt_wr <= '0';
        end if;

      end if;
    end process ctrl;

  end generate;

end architecture rtl;
