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
--   * C_READ with arg bit 15 set is a file system metadata read.  (For the
--     meta cache, still to come; for now it is treated like any read.)
--   * hits / misses count single-sector reads served from the cache / from
--     the card.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sd_cache is
  generic (
    G_LINES  : natural := 16;       -- 4 KB lines (RAMB36 each); 0 = no cache
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

    -- pass-through: upstream sees the controller's status and streams
    signal pt      : std_logic := '1';
    signal pt_wr   : std_logic := '0';     -- (a write: snoop it)
    signal pt_addr : unsigned(31 downto 0) := (others => '0');

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
    signal dquiet_cnt : integer range 0 to 3 := 0;
    signal dfree   : std_logic;            -- may issue now

    -- the line being filled
    signal fill     : std_logic := '0';
    signal f_line   : integer range 0 to G_LINES-1 := 0;
    signal f_first  : unsigned(2 downto 0) := (others => '0');   -- first sector
    signal f_total  : unsigned(3 downto 0) := (others => '0');   -- blocks wanted
    signal f_grant  : unsigned(3 downto 0) := (others => '0');   -- blocks granted
    signal f_recv   : unsigned(3 downto 0) := (others => '0');   -- blocks received

    -- serving a request
    type t_st is (T_IDLE, T_PT_WAIT, T_STOPFILL, T_STOPFILL_WAIT, T_DISPATCH,
                  T_VICTIM, T_MISS_CMD, T_MISS_WAIT, T_WAITSEC, T_HIT, T_HIT_END);
    signal st       : t_st := T_IDLE;
    signal r_line   : integer range 0 to G_LINES-1 := 0;
    signal r_sec    : unsigned(2 downto 0) := (others => '0');
    signal r_cnt    : unsigned(9 downto 0) := (others => '0');
    signal v_i      : integer range 0 to G_LINES := 0;   -- victim scan
    signal v_best   : integer range 0 to G_LINES-1 := 0;
    signal v_age    : unsigned(15 downto 0) := (others => '0');
    signal v_free   : std_logic := '0';

    -- write snooping
    signal s1_v     : std_logic := '0';
    signal s1_sec   : unsigned(31 downto 0) := (others => '0');
    signal s1_off   : unsigned(8 downto 0) := (others => '0');
    signal s2_v     : std_logic := '0';
    signal s2_addr  : unsigned(AW-1 downto 0) := (others => '0');

    -- look a sector up: hit (a line holds it, valid or not) and the line
    procedure lookup(signal tg : in t_tags; signal us : in std_logic_vector;
                     sector : in unsigned(31 downto 0);
                     variable hit : out boolean; variable idx : out integer) is
    begin
      hit := false;
      idx := 0;
      for i in 0 to G_LINES-1 loop
        if us(i) = '1' and tg(i) = sector(31 downto 3) then
          hit := true;
          idx := i;
        end if;
      end loop;
    end procedure;

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
    u_card_ready  <= d_card_ready;
    u_native_mode <= d_native_mode;
    u_high_speed  <= d_high_speed;
    u_sdhc        <= d_sdhc;
    u_clk_setting <= d_clk_setting;
    u_probe_pass  <= d_probe_pass;
    u_probe_fail  <= d_probe_fail;

    u_cmd_ready   <= u_ready;
    u_busy        <= d_busy        when pt = '1' else o_busy;
    u_waiting     <= d_waiting     when pt = '1' else '0';
    u_error       <= d_error       when pt = '1' else o_error;
    u_err_code    <= d_err_code    when pt = '1' else o_err;
    u_blocks_done <= d_blocks_done when pt = '1' else o_done;

    -- read stream: the controller's (pass-through, or block 0 of a miss), or
    -- the cache's own
    u_rd_valid  <= d_rd_valid when pt = '1' else
                   o_rv or (fwd0 and d_rd_valid and boolean_to_sl(d_rd_block = 0));
    u_rd_data   <= rb_q when pt = '0' and o_rv = '1' else d_rd_data;
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

    ctrl : process (clock)

      procedure dcmd(code : unsigned(3 downto 0); addr : unsigned(31 downto 0);
                     count : unsigned(15 downto 0); arg : unsigned(15 downto 0)) is
      begin
        dv         <= '1';
        dcode      <= code;
        daddr      <= addr;
        dcount     <= count;
        darg       <= arg;
        dquiet_cnt <= 3;
      end procedure;

      procedure flush_all is
      begin
        used <= (others => '0');
        for i in 0 to G_LINES-1 loop
          vld(i) <= (others => '0');
        end loop;
      end procedure;

      variable hit  : boolean;
      variable idx  : integer range 0 to G_LINES-1;
      variable sec  : unsigned(31 downto 0);
      variable k    : unsigned(2 downto 0);
      variable age  : unsigned(15 downto 0);
      variable rnd  : integer range 0 to G_LINES-1;
      variable fill_writes : boolean;

    begin
      if rising_edge(clock) then
        dv      <= '0';
        wa_en   <= '0';
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
        if fill = '1' and pt = '0' and d_rd_valid = '1' then
          k := f_first + d_rd_block(2 downto 0);
          wa_en   <= '1';
          wa_addr <= maddr(f_line, k, d_rd_offset);
          wa_data <= d_rd_data;
          fill_writes := true;
        end if;
        if fill = '1' and pt = '0' and d_rd_good = '1' then
          k := f_first + d_rd_block(2 downto 0);
          vld(f_line)(to_integer(k)) <= '1';
          f_recv <= f_recv + 1;
          if d_rd_block = 0 then
            fwd0   <= '0';
            o_busy <= '0';
            o_done <= to_unsigned(1, 16);
          end if;
          if f_recv + 1 = f_total then
            fill <= '0';              -- (the controller ends the transfer itself)
          end if;
        end if;

        -- more blocks for the fill, one ahead of the data
        if fill = '1' and f_grant /= f_total and f_grant < f_recv + 2 and dfree = '1'
          and (st = T_IDLE or st = T_WAITSEC or st = T_HIT or st = T_HIT_END
               or st = T_MISS_WAIT) then
          if f_grant + 1 = f_total then
            dcmd(C_MORE, (others => '0'), (others => '0'), x"0001");
          else
            dcmd(C_MORE, (others => '0'), (others => '0'), x"0000");
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
        lookup(tag, used, s1_sec, hit, idx);
        if s1_v = '1' and hit and vld(idx)(to_integer(s1_sec(2 downto 0))) = '1' then
          s2_v <= '1';
        else
          s2_v <= '0';
        end if;
        s2_addr <= maddr(idx, s1_sec(2 downto 0), s1_off);
        if s2_v = '1' and not fill_writes then
          wa_en   <= '1';
          wa_addr <= s2_addr;
          wa_data <= u_wr_data;
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
              if u_cmd_code = C_INIT then
                -- the controller drops everything at once: no need to stop
                -- the fill first
                flush_all;
                fill    <= '0';
                fwd0    <= '0';
                st      <= T_DISPATCH;
              elsif fill = '1' and not (u_cmd_code = C_READ and u_cmd_count = 1
                                        and enabled = '1') then
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
              if f_grant /= f_total then
                dcmd(C_STOP, (others => '0'), (others => '0'), (others => '0'));
                f_total <= f_grant;
              end if;
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
            lookup(tag, used, sec, hit, idx);
            if c_code = C_CACHE then
              -- A completed fill may still be closing CMD12 / tail clocks.
              -- Do not hide that busy period when changing to own status.
              if dfree = '1' and d_busy = '0' then
                case c_arg(1 downto 0) is
                  when "00" => enabled <= '0';
                               flush_all;
                  when "01" => enabled <= '1';
                  when "10" => flush_all;
                  when others => lru <= c_arg(4);
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
              u_ready <= '0';
              r_sec   <= sec(2 downto 0);
              if hit and vld(idx)(to_integer(sec(2 downto 0))) = '1' then
                r_line <= idx;
                r_cnt  <= (others => '0');
                hits   <= hits + 1;
                stamp(idx) <= now_ts;
                now_ts <= now_ts + 1;
                st     <= T_HIT;
              elsif hit and fill = '1' and idx = f_line
                and sec(2 downto 0) >= f_first
                and resize(sec(2 downto 0) - f_first, 4) < f_total then
                -- on its way in
                r_line <= idx;
                st     <= T_WAITSEC;
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
                v_age  <= (others => '0');
                st     <= T_VICTIM;
              end if;
            else
              -- straight through
              if dfree = '1' and (d_busy = '0' or c_code = C_INIT
                                   or c_code = C_MORE or c_code = C_STOP) then
                if c_code = C_CLEAR then
                  flush_all;
                end if;
                pt <= '1';
                if c_code = C_WRITE then
                  pt_wr   <= '1';
                  pt_addr <= c_addr;
                elsif c_code /= C_MORE and c_code /= C_STOP then
                  pt_wr <= '0';
                end if;
                dcmd(c_code, c_addr, c_count, c_arg);
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
          when T_VICTIM =>
            if v_i = G_LINES then
              if v_free = '1' or lru = '1' then
                r_line <= v_best;
              else
                rnd := to_integer(shift_right(resize(lfsr(7 downto 0), 16)
                                              * to_unsigned(G_LINES, 8), 8));
                r_line <= rnd;
              end if;
              st <= T_MISS_CMD;
            else
              age := now_ts - stamp(v_i);
              if used(v_i) = '0' and v_free = '0' then
                v_free <= '1';
                v_best <= v_i;
              elsif v_free = '0' and (v_i = 0 or age > v_age) then
                v_best <= v_i;
                v_age  <= age;
              end if;
              v_i <= v_i + 1;
            end if;

          -- read from the requested sector to the end of the line
          when T_MISS_CMD =>
            -- cmd_ready only means the mailbox is free. A first-sector
            -- completion is published upstream before the card finishes its
            -- stop/tail sequence; wait for that sequence before a new read.
            if dfree = '1' and d_busy = '0' then
              if used(r_line) = '0' or tag(r_line) /= c_addr(31 downto 3) then
                tag(r_line)  <= c_addr(31 downto 3);
                used(r_line) <= '1';
                vld(r_line)  <= (others => '0');
              end if;
              stamp(r_line) <= now_ts;
              now_ts  <= now_ts + 1;
              f_line  <= r_line;
              f_first <= c_addr(2 downto 0);
              f_total <= resize(8 - resize(c_addr(2 downto 0), 4), 4);
              f_recv  <= (others => '0');
              f_grant <= to_unsigned(1, 4);
              fill    <= '1';
              fwd0    <= '1';
              if c_addr(2 downto 0) = "111" then
                dcmd(C_READ, c_addr, to_unsigned(1, 16), (others => '0'));
              else
                dcmd(C_READ, c_addr, to_unsigned(0, 16), (others => '0'));
              end if;
              st <= T_MISS_WAIT;
            end if;

          -- the first sector streams up; done with it (or with an error)
          when T_MISS_WAIT =>
            if fwd0 = '0' then
              u_ready <= '1';
              st      <= T_IDLE;
            elsif dfree = '1' and d_busy = '0' and d_error = '1' then
              -- the read failed: the line is no good
              fill    <= '0';
              fwd0    <= '0';
              used(f_line) <= '0';
              vld(f_line)  <= (others => '0');
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
            rb_addr <= maddr(r_line, r_sec, r_cnt(8 downto 0));
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
            u_ready <= '1';
            st      <= T_IDLE;

        end case;

        -- the controller failed while filling in the background: stop
        if fill = '1' and fwd0 = '0' and dfree = '1' and d_busy = '0' then
          fill <= '0';
        end if;

        -- a pass-through write that failed: the cache may be stale
        if pt = '1' and pt_wr = '1' and st = T_IDLE and dfree = '1'
          and d_busy = '0' and d_error = '1' then
          flush_all;
          pt_wr <= '0';
        end if;

      end if;
    end process ctrl;

  end generate;

end architecture rtl;
