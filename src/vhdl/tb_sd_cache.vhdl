--------------------------------------------------------------------------------
-- tb_sd_cache: sd_cache + sdcard_native + sdcard_native_model, driven through
-- the cache's upstream interface (as sdcardio_native does).
--
--   ghdl -a --std=08 sdcard_native.vhdl sdcard_native_model.vhdl sd_cache.vhdl tb_sd_cache.vhdl
--   ghdl -r --std=08 tb_sd_cache --stop-time=200ms
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sd_cache is
  generic (
    G_LINES : positive := 4;
    G_ROM_TEST : boolean := false;
    G_ROM_COUNT : positive := 256;
    G_CLOSE_TEST : boolean := false;
    G_NAC : natural := 2000;
    G_HS_OK : boolean := true;
    G_NAC_MULTI : natural := 2
    );
end entity;

architecture tb of tb_sd_cache is

  constant T162  : time := 6172 ps;
  constant TCPU  : time := 4 * T162;
  constant BOARD : time := 1500 ps;
  constant LINES : natural := G_LINES;

  function pattern(b : natural; i : natural) return unsigned is
  begin
    return to_unsigned((b * 37 + i * 7 + (i / 256) * 101 + 13) mod 256, 8);
  end function;

  function wpattern(b : natural; i : natural) return unsigned is
  begin
    return to_unsigned((b * 11 + i * 3 + 200) mod 256, 8);
  end function;

  signal clock162 : std_logic := '0';
  signal cpuclock : std_logic := '0';
  signal done     : boolean := false;

  -- upstream (the test) <-> cache
  signal u_cmd_valid : std_logic := '0';
  signal u_cmd_ready : std_logic;
  signal u_cmd_code  : unsigned(3 downto 0) := (others => '0');
  signal u_cmd_addr  : unsigned(31 downto 0) := (others => '0');
  signal u_cmd_count : unsigned(15 downto 0) := (others => '0');
  signal u_cmd_arg   : unsigned(15 downto 0) := (others => '0');
  signal u_card_ready, u_busy, u_waiting, u_error : std_logic;
  signal u_native, u_hs, u_sdhc : std_logic;
  signal u_err_code  : unsigned(7 downto 0);
  signal u_setting   : unsigned(15 downto 0);
  signal u_pp, u_pf  : unsigned(7 downto 0);
  signal u_bdone     : unsigned(15 downto 0);
  signal u_rd_valid, u_rd_good, u_rd_bad : std_logic;
  signal u_rd_data   : unsigned(7 downto 0);
  signal u_rd_offset : unsigned(8 downto 0);
  signal u_rd_block  : unsigned(15 downto 0);
  signal u_wr_fetch  : std_logic;
  signal u_wr_offset : unsigned(8 downto 0);
  signal u_wr_block  : unsigned(15 downto 0);
  signal u_wr_data   : unsigned(7 downto 0) := (others => '0');
  signal cache_on    : std_logic;
  signal hits, misses : unsigned(15 downto 0);

  -- cache <-> controller
  signal d_cmd_valid : std_logic;
  signal d_cmd_ready : std_logic;
  signal d_cmd_code  : unsigned(3 downto 0);
  signal d_cmd_addr  : unsigned(31 downto 0);
  signal d_cmd_count : unsigned(15 downto 0);
  signal d_cmd_arg   : unsigned(15 downto 0);
  signal d_card_ready, d_busy, d_waiting, d_error : std_logic;
  signal d_native, d_hs, d_sdhc : std_logic;
  signal d_err_code  : unsigned(7 downto 0);
  signal d_setting   : unsigned(15 downto 0);
  signal d_pp, d_pf  : unsigned(7 downto 0);
  signal d_bdone     : unsigned(15 downto 0);
  signal d_rd_valid, d_rd_good, d_rd_bad : std_logic;
  signal d_rd_data   : unsigned(7 downto 0);
  signal d_rd_offset : unsigned(8 downto 0);
  signal d_rd_block  : unsigned(15 downto 0);
  signal d_wr_fetch  : std_logic;
  signal d_wr_offset : unsigned(8 downto 0);
  signal d_wr_block  : unsigned(15 downto 0);
  signal d_wr_data   : unsigned(7 downto 0);

  -- card wires
  signal sd_clk    : std_logic_vector(1 downto 0);
  signal sd_cmd_o  : std_logic_vector(1 downto 0);
  signal sd_cmd_oe : std_logic_vector(1 downto 0);
  signal sd_cmd_i  : std_logic_vector(1 downto 0) := "11";
  signal sd_dat_o  : std_logic_vector(7 downto 0);
  signal sd_dat_oe : std_logic_vector(7 downto 0);
  signal sd_dat_i  : std_logic_vector(7 downto 0) := (others => '1');
  signal card_clk  : std_logic := '1';
  signal card_cmd  : std_logic;
  signal card_dat  : std_logic_vector(3 downto 0);
  signal host_cmd  : std_logic;
  signal host_dat  : std_logic_vector(3 downto 0);

  -- what came up the read stream
  type t_rx is array (0 to 15, 0 to 511) of unsigned(7 downto 0);
  signal rx      : t_rx;
  signal n_good  : natural := 0;
  signal n_bad   : natural := 0;
  signal clr     : boolean := false;
  signal wr_base : natural := 0;
  signal pipe1   : unsigned(7 downto 0) := (others => '0');
  signal fails   : natural := 0;

begin

  clock162 <= not clock162 after T162 / 2 when not done;
  cpuclock <= not cpuclock after TCPU / 2 when not done;

  cache : entity work.sd_cache
    generic map (G_LINES => LINES)
    port map (
      clock => cpuclock,
      u_cmd_valid => u_cmd_valid, u_cmd_ready => u_cmd_ready, u_cmd_code => u_cmd_code,
      u_cmd_addr => u_cmd_addr, u_cmd_count => u_cmd_count, u_cmd_arg => u_cmd_arg,
      u_card_ready => u_card_ready, u_busy => u_busy, u_waiting => u_waiting,
      u_error => u_error, u_err_code => u_err_code, u_native_mode => u_native,
      u_high_speed => u_hs, u_sdhc => u_sdhc, u_clk_setting => u_setting,
      u_probe_pass => u_pp, u_probe_fail => u_pf, u_blocks_done => u_bdone,
      u_rd_valid => u_rd_valid, u_rd_data => u_rd_data, u_rd_offset => u_rd_offset,
      u_rd_block => u_rd_block, u_rd_good => u_rd_good, u_rd_bad => u_rd_bad,
      u_wr_fetch => u_wr_fetch, u_wr_offset => u_wr_offset, u_wr_block => u_wr_block,
      u_wr_data => u_wr_data,
      d_cmd_valid => d_cmd_valid, d_cmd_ready => d_cmd_ready, d_cmd_code => d_cmd_code,
      d_cmd_addr => d_cmd_addr, d_cmd_count => d_cmd_count, d_cmd_arg => d_cmd_arg,
      d_card_ready => d_card_ready, d_busy => d_busy, d_waiting => d_waiting,
      d_error => d_error, d_err_code => d_err_code, d_native_mode => d_native,
      d_high_speed => d_hs, d_sdhc => d_sdhc, d_clk_setting => d_setting,
      d_probe_pass => d_pp, d_probe_fail => d_pf, d_blocks_done => d_bdone,
      d_rd_valid => d_rd_valid, d_rd_data => d_rd_data, d_rd_offset => d_rd_offset,
      d_rd_block => d_rd_block, d_rd_good => d_rd_good, d_rd_bad => d_rd_bad,
      d_wr_fetch => d_wr_fetch, d_wr_offset => d_wr_offset, d_wr_block => d_wr_block,
      d_wr_data => d_wr_data,
      cache_on => cache_on, cache_hits => hits, cache_misses => misses);

  sdn : entity work.sdcard_native
    generic map (G_XILINX => false, G_MS => 1620)
    port map (
      clock162 => clock162, cpuclock => cpuclock,
      cmd_valid => d_cmd_valid, cmd_ready => d_cmd_ready, cmd_code => d_cmd_code,
      cmd_addr => d_cmd_addr, cmd_count => d_cmd_count, cmd_arg => d_cmd_arg,
      card_ready => d_card_ready, busy => d_busy, waiting => d_waiting, error => d_error,
      err_code => d_err_code, native_mode => d_native, high_speed => d_hs,
      sdhc => d_sdhc, clk_setting => d_setting, probe_pass => d_pp,
      probe_fail => d_pf, blocks_done => d_bdone, diag_stats => open,
      rd_valid => d_rd_valid, rd_data => d_rd_data, rd_offset => d_rd_offset,
      rd_block => d_rd_block, rd_good => d_rd_good, rd_bad => d_rd_bad,
      wr_fetch => d_wr_fetch, wr_offset => d_wr_offset, wr_block => d_wr_block,
      wr_data => d_wr_data,
      sd_clk => sd_clk, sd_cmd_o => sd_cmd_o, sd_cmd_oe => sd_cmd_oe,
      sd_cmd_i => sd_cmd_i, sd_dat_o => sd_dat_o, sd_dat_oe => sd_dat_oe,
      sd_dat_i => sd_dat_i);

  card_clk <= transport sd_clk(0) after BOARD;
  card_cmd <= 'H';
  card_dat <= "HHHH";
  host_cmd <= sd_cmd_o(0) when sd_cmd_oe(0) = '1' else 'Z';
  card_cmd <= transport host_cmd after BOARD;
  drv : for l in 0 to 3 generate
    host_dat(l) <= sd_dat_o(l) when sd_dat_oe(l) = '1' else 'Z';
  end generate;
  card_dat <= transport host_dat after BOARD;
  sd_cmd_i(0)          <= transport to_X01(card_cmd) after BOARD;
  sd_dat_i(3 downto 0) <= transport to_X01(card_dat) after BOARD;

  -- a slow card (access latency ~50 us at 40.5 MHz), with one CRC error in
  -- the background fill of the first line
  card : entity work.sdcard_native_model
    generic map (G_NAC => G_NAC, G_NAC_MULTI => G_NAC_MULTI,
                 G_HS_OK => G_HS_OK, G_CRC_ERR_BLK => 99)
    port map (clk => card_clk, cmd => card_cmd, dat => card_dat);

  host : process (cpuclock)
  begin
    if rising_edge(cpuclock) then
      if clr then
        for k in 0 to 15 loop
          for i in 0 to 511 loop
            rx(k, i) <= x"EE";
          end loop;
        end loop;
        n_good <= 0;
        n_bad  <= 0;
      else
        if u_rd_valid = '1' then
          rx(to_integer(u_rd_block) mod 16, to_integer(u_rd_offset)) <= u_rd_data;
        end if;
        if u_rd_good = '1' then n_good <= n_good + 1; end if;
        if u_rd_bad = '1' then n_bad <= n_bad + 1; end if;
      end if;
      if u_wr_fetch = '1' then
        pipe1 <= wpattern(wr_base + to_integer(u_wr_block), to_integer(u_wr_offset));
      end if;
      u_wr_data <= pipe1;
    end if;
  end process;

  stim : process

    procedure command(code : natural; addr : natural; count : natural; arg : natural) is
    begin
      wait until rising_edge(cpuclock) and u_cmd_ready = '1';
      u_cmd_code  <= to_unsigned(code, 4);
      u_cmd_addr  <= to_unsigned(addr, 32);
      u_cmd_count <= to_unsigned(count, 16);
      u_cmd_arg   <= to_unsigned(arg, 16);
      u_cmd_valid <= '1';
      wait until rising_edge(cpuclock);
      u_cmd_valid <= '0';
      wait until rising_edge(cpuclock) and u_cmd_ready = '1';
    end procedure;

    procedure wait_idle(tmo : time) is
    begin
      if u_busy = '1' or u_cmd_ready = '0' then
        wait until u_busy = '0' and u_cmd_ready = '1' for tmo;
      end if;
      assert u_busy = '0' report "timeout waiting for idle" severity failure;
      wait until rising_edge(cpuclock);
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
      if cond then
        report "PASS: " & msg;
      else
        report "FAIL: " & msg severity error;
        fails <= fails + 1;
        wait for 0 ns;
      end if;
    end procedure;

    procedure clear_rx is
    begin
      clr <= true;
      wait until rising_edge(cpuclock);
      clr <= false;
      wait until rising_edge(cpuclock);
    end procedure;

    function same(b : natural; written : boolean; k : natural; signal r : t_rx) return boolean is
      variable v : unsigned(7 downto 0);
    begin
      for i in 0 to 511 loop
        if written then v := wpattern(b, i); else v := pattern(b, i); end if;
        if r(k, i) /= v then
          report "  sector " & integer'image(b) & " byte " & integer'image(i) & " = "
            & to_hstring(r(k, i)) & ", want " & to_hstring(v);
          return false;
        end if;
      end loop;
      return true;
    end function;

    -- read one sector through the cache; returns the time it took
    procedure read1(n : natural; written : boolean; msg : string; t : out time) is
      variable t0 : time;
    begin
      clear_rx;
      t0 := now;
      command(2, n, 1, 0);
      wait_idle(10 ms);
      t := now - t0;
      check(u_error = '0' and n_good = 1 and same(n, written, 0, rx), msg);
    end procedure;

    variable t, t_miss, t_hit : time;
    variable h0, m0 : natural;

  begin
    wait for 100 ns;
    wait until u_card_ready = '1' and u_busy = '0' for 40 ms;
    check(u_card_ready = '1' and cache_on = '1', "init, cache on");

    if G_CLOSE_TEST then
      read1(7, false, "last sector of first line", t);
      read1(15, false, "last sector of next line before card cleanup finishes", t);
      command(8, 0, 0, 0);
      check(d_busy = '0', "cache control waits for card cleanup");
      read1(23, false, "uncached read after cache control", t);
      command(8, 0, 0, 1);
      read1(31, false, "cached read after cache control", t);
      report "ALL CLOSE TESTS PASSED";
      done <= true;
      wait;
    end if;

    if G_ROM_TEST then
      -- A full 128 KiB ROM crosses more lines than the hardware cache holds.
      -- Let the card finish its fill while software copies each sector, and
      -- interleave FAT lookups at cluster boundaries as Hyppo does.
      for n in 0 to G_ROM_COUNT - 1 loop
        if n mod 8 = 0 then
          read1(2616 + 109665 / 128 + n / 1024, false, "ROM FAT lookup", t);
        end if;
        read1(922520 + n, false, "ROM sector " & integer'image(n), t);
        wait for 150 us;
      end loop;
      report "ALL ROM TESTS PASSED";
      done <= true;
      wait;
    end if;

    -- a miss, then the same sector again
    read1(96, false, "sector 96 (miss)", t_miss);
    read1(96, false, "sector 96 again (hit)", t_hit);
    report "  miss " & time'image(t_miss) & ", hit " & time'image(t_hit);
    check(t_hit < t_miss / 2, "a hit is much faster than a miss");
    check(misses = 1 and hits = 1, "1 miss, 1 hit");

    -- the rest of the line (96..103) comes in the background (99 needs a CRC
    -- retry); reading straight behind the fill waits for each sector
    for n in 97 to 103 loop
      read1(n, false, "sector " & integer'image(n) & " from the background fill", t);
    end loop;
    check(misses = 1 and hits = 8, "the whole line from one card read");

    -- a miss in the middle of a line; the next sector while it is still on
    -- its way in; then an earlier sector of the same line
    read1(203, false, "sector 203 (miss)", t);
    read1(204, false, "sector 204 (on its way in)", t);
    read1(202, false, "sector 202 (same line, before the fill)", t);
    read1(207, false, "sector 207", t);
    report "  hits " & integer'image(to_integer(hits)) & ", misses " & integer'image(to_integer(misses));

    -- a multi-sector read (straight through) while a fill is running
    read1(300, false, "sector 300 (miss, starts a fill)", t);
    clear_rx;
    command(2, 500, 3, 0);
    wait_idle(10 ms);
    check(n_good = 3 and same(500, false, 0, rx) and same(501, false, 1, rx)
          and same(502, false, 2, rx), "multi-sector read during a fill");
    read1(301, false, "sector 301 after that", t);

    -- write-through: sector 101 is cached; write it, read it back from the
    -- cache, then (cache off) from the card
    wr_base <= 101;
    command(3, 101, 1, 0);
    wait_idle(10 ms);
    check(u_error = '0', "write sector 101");
    h0 := to_integer(hits);
    read1(101, true, "sector 101 after the write (from the cache)", t);
    check(to_integer(hits) = h0 + 1, "  ... it was a hit");
    command(8, 0, 0, 0);                 -- cache off
    wait_idle(1 ms);
    check(cache_on = '0', "cache off");
    read1(101, true, "sector 101 from the card", t);
    command(8, 0, 0, 1);                 -- cache on (it starts empty)
    wait_idle(1 ms);

    -- LRU: fill all four lines, use the first again, then a fifth line must
    -- replace the second
    command(8, 0, 0, 3 + 16);
    wait_idle(1 ms);
    read1(1000, false, "LRU: line A", t);
    read1(1008, false, "LRU: line B", t);
    read1(1016, false, "LRU: line C", t);
    read1(1024, false, "LRU: line D", t);
    read1(1001, false, "LRU: line A again", t);
    read1(1032, false, "LRU: line E", t);
    h0 := to_integer(hits);
    m0 := to_integer(misses);
    read1(1002, false, "LRU: line A still there", t);
    read1(1016, false, "LRU: line C still there", t);
    check(to_integer(hits) = h0 + 2 and to_integer(misses) = m0, "LRU kept A and C");
    read1(1008, false, "LRU: line B was replaced", t);
    check(to_integer(misses) = m0 + 1, "  ... B was a miss");

    -- random replacement: many lines, the data must stay right
    command(8, 0, 0, 3);
    wait_idle(1 ms);
    for n in 0 to 11 loop
      read1(2000 + (n mod 6) * 8 + n mod 3, false, "random: sector " & integer'image(2000 + (n mod 6) * 8 + n mod 3), t);
    end loop;

    -- init empties the cache
    read1(3000, false, "sector 3000", t);
    command(1, 0, 0, 0);
    wait until u_card_ready = '1' and u_busy = '0' and u_cmd_ready = '1' for 40 ms;
    m0 := to_integer(misses);
    read1(3000, false, "sector 3000 after init", t);
    check(to_integer(misses) = m0 + 1, "  ... was a miss");

    if fails = 0 then
      report "ALL TESTS PASSED";
    else
      report integer'image(fails) & " TESTS FAILED" severity error;
    end if;
    done <= true;
    wait;
  end process;

end architecture;
