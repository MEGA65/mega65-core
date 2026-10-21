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
    G_DUAL_TEST : boolean := false;
    G_DUAL_SPI0 : boolean := false;
    G_DUAL_SPI1 : boolean := false;
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
  signal u_slot : std_logic := '0';
  signal d_slot : std_logic;
  signal cards_status : unsigned(63 downto 0);
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
  signal card1_clk : std_logic;
  signal card1_cmd, host1_cmd : std_logic;
  signal card1_dat, host1_dat : std_logic_vector(3 downto 0);
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
  signal media   : std_logic_vector(1 downto 0) := "00";

begin

  clock162 <= not clock162 after T162 / 2 when not done;
  cpuclock <= not cpuclock after TCPU / 2 when not done;

  cache : entity work.sd_cache
    generic map (G_LINES => LINES, G_META => 4)
    port map (
      clock => cpuclock,
      u_cmd_valid => u_cmd_valid, u_cmd_ready => u_cmd_ready, u_cmd_code => u_cmd_code,
      u_cmd_slot => u_slot,
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
      d_cmd_slot => d_slot, d_cards_status => cards_status,
      d_cmd_addr => d_cmd_addr, d_cmd_count => d_cmd_count, d_cmd_arg => d_cmd_arg,
      d_card_ready => d_card_ready, d_busy => d_busy, d_waiting => d_waiting,
      d_error => d_error, d_err_code => d_err_code, d_native_mode => d_native,
      d_high_speed => d_hs, d_sdhc => d_sdhc, d_clk_setting => d_setting,
      d_probe_pass => d_pp, d_probe_fail => d_pf, d_blocks_done => d_bdone,
      d_rd_valid => d_rd_valid, d_rd_data => d_rd_data, d_rd_offset => d_rd_offset,
      d_rd_block => d_rd_block, d_rd_good => d_rd_good, d_rd_bad => d_rd_bad,
      d_wr_fetch => d_wr_fetch, d_wr_offset => d_wr_offset, d_wr_block => d_wr_block,
      d_wr_data => d_wr_data,
      media_change => media,
      cache_on => cache_on, cache_hits => hits, cache_misses => misses);

  single : if not G_DUAL_TEST generate
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

    cards_status <= (others => '0');
  end generate;
  dual : if G_DUAL_TEST generate
  sdn : entity work.sdcard_native_dual
    generic map (G_XILINX => false, G_MS => 1620, G_TRACE => true)
    port map (
      clock162 => clock162, cpuclock => cpuclock,
      cmd_valid => d_cmd_valid, cmd_ready => d_cmd_ready, cmd_code => d_cmd_code,
      cmd_slot => d_slot, status_slot => d_slot, cards_status => cards_status,
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

  end generate;

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
    generic map (G_NAC => G_NAC, G_NAC_MULTI => G_NAC_MULTI, G_START_SPI => G_DUAL_SPI0,
                 G_HS_OK => G_HS_OK, G_CRC_ERR_BLK => 99,
                 G_LONG_READ_NAC => 40000 * boolean'pos(G_DUAL_TEST))
    port map (clk => card_clk, cmd => card_cmd, dat => card_dat);

  other_card : if G_DUAL_TEST generate
    card1_clk <= transport sd_clk(1) after BOARD;
    card1_cmd <= 'H'; card1_dat <= "HHHH";
    host1_cmd <= sd_cmd_o(1) when sd_cmd_oe(1) = '1' else 'Z';
    card1_cmd <= transport host1_cmd after BOARD;
    drv1 : for l in 0 to 3 generate
      host1_dat(l) <= sd_dat_o(l+4) when sd_dat_oe(l+4) = '1' else 'Z';
    end generate;
    card1_dat <= transport host1_dat after BOARD;
    sd_cmd_i(1) <= transport to_X01(card1_cmd) after BOARD;
    sd_dat_i(7 downto 4) <= transport to_X01(card1_dat) after BOARD;
    card1 : entity work.sdcard_native_model
      generic map (G_PATTERN_SEED => 89, G_NAC => G_NAC, G_START_SPI => G_DUAL_SPI1)
      port map (clk => card1_clk, cmd => card1_cmd, dat => card1_dat);
  end generate;

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

    -- the same, with an arg (bit 15: metadata read)
    procedure read1a(n : natural; written : boolean; arg : natural; msg : string; t : out time) is
      variable t0 : time;
    begin
      clear_rx;
      t0 := now;
      command(2, n, 1, arg);
      wait_idle(10 ms);
      t := now - t0;
      check(u_error = '0' and n_good = 1 and same(n, written, 0, rx), msg);
    end procedure;

    procedure readslot(slot, n : natural; written_base : integer := -1) is
      variable want : unsigned(7 downto 0);
    begin
      if slot = 0 then u_slot <= '0'; else u_slot <= '1'; end if;
      clear_rx;
      command(2, n, 1, 0);
      wait_idle(10 ms);
      check(u_error = '0' and n_good = 1, "dual read completes");
      for i in 0 to 511 loop
        if written_base < 0 then want := pattern(n, i) + to_unsigned(slot*89, 8);
        else want := wpattern(written_base, i); end if;
        assert rx(0, i) = want report "wrong card/sector in dual read" severity failure;
      end loop;
      report "dual slot " & integer'image(slot) & " sector " & integer'image(n) & " correct";
    end procedure;

    variable t, t_miss, t_hit : time;
    variable h0, m0 : natural;
    variable t_ahead : time;

  begin
    wait for 100 ns;
    if G_DUAL_TEST then
      if G_DUAL_SPI0 /= G_DUAL_SPI1 then
        wait until cards_status(0) = '1' or cards_status(32) = '1' for 40 ms;
        if G_DUAL_SPI0 then
          readslot(1, 7);
          check(cards_status(0) = '0' and cards_status(1) = '1', "external read completes while internal still initialises");
        else
          readslot(0, 7);
          check(cards_status(32) = '0' and cards_status(33) = '1', "internal read completes while external still initialises");
        end if;
      end if;
      wait until cards_status(0) = '1' and cards_status(32) = '1' for 40 ms;
      assert cards_status(0) = '1' and cards_status(32) = '1' report "dual init failed" severity failure;
      readslot(0, 96);
      readslot(1, 96);
      readslot(0, 96);
      readslot(1, 96);
      readslot(0, 300);
      -- An info request on the other card retires this active read-ahead
      -- stream, uses the other card's response, and bypasses cache storage.
      u_slot <= '1'; clear_rx;
      command(11, 0, 1, 0); wait_idle(10 ms);
      check(u_error = '0' and n_good = 1
        and rx(0,0) = x"40" and rx(0,8) = x"BA" and rx(0,9) = x"04"
        and rx(0,15) = x"59" and rx(0,16) = 0 and rx(0,511) = 0,
        "cross-card CSD read retires fill and zero-pads the response");
      readslot(0, 96);
      readslot(1, 96);
      -- Write-through snooping and the shared write-fetch stream must be
      -- card-qualified too. Give identical LBAs different written contents.
      u_slot <= '1'; wr_base <= 96;
      command(3, 96, 1, 0); wait_idle(10 ms);
      check(u_error = '0', "external write completes");
      readslot(1, 96, 96);
      readslot(0, 96);
      u_slot <= '0'; wr_base <= 97;
      command(3, 96, 1, 0); wait_idle(10 ms);
      check(u_error = '0', "internal write completes");
      readslot(0, 96, 97);
      readslot(1, 96, 96);
      -- Drop both cached copies and verify the two simulated cards really
      -- received different bytes, independently of write-through snooping.
      command(8, 0, 0, 2); wait_idle(10 ms);
      readslot(0, 96, 97);
      readslot(1, 96, 96);
      assert fails = 0 severity failure;
      report "ALL DUAL CACHE TESTS PASSED";
      done <= true;
      wait;
    end if;
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

    ----------------------------------------------------------------------------
    -- sequential read-ahead: five lines read in order come from one card
    -- read (a stream that grows ahead of the reader)
    command(8, 0, 0, 2);                 -- empty the cache
    wait_idle(1 ms);
    command(8, 0, 0, 3 + 16);            -- LRU
    wait_idle(1 ms);
    m0 := to_integer(misses);
    h0 := to_integer(hits);
    for n in 4000 to 4039 loop
      read1(n, false, "stream: sector " & integer'image(n), t);
    end loop;
    check(to_integer(misses) = m0 + 1 and to_integer(hits) = h0 + 39,
          "stream: 40 sectors over five lines from one card read");
    -- after a pause the stream is ahead of the reader: the next sector is
    -- already there
    wait for 300 us;
    read1(4040, false, "stream: sector 4040 after a pause", t_ahead);
    report "  read-ahead hit " & time'image(t_ahead) & " (a miss took " & time'image(t_miss) & ")";
    check(t_ahead < t_miss / 2 and to_integer(misses) = m0 + 1, "  ... it was read ahead");
    -- something else ends the stream; the data stays right
    read1(4100, false, "stream: a non-sequential read ends it", t);
    read1(4041, false, "stream: sector 4041 afterwards", t);

    ----------------------------------------------------------------------------
    -- the meta cache (4 slots in this testbench)
    m0 := to_integer(misses);
    read1a(5000, false, 16#8000#, "meta: sector 5000 (miss)", t);
    read1a(5000, false, 16#8000#, "meta: sector 5000 again", t);
    check(to_integer(misses) = m0 + 1, "  ... a hit");
    h0 := to_integer(hits);
    read1(5000, false, "meta: a data read of 5000 finds it there", t);
    check(to_integer(hits) = h0 + 1 and to_integer(misses) = m0 + 1, "  ... a hit, no line taken");
    -- a metadata hit during a stream leaves the stream running
    read1(6000, false, "meta: stream sector 6000", t);
    read1(6001, false, "meta: stream sector 6001", t);
    m0 := to_integer(misses);
    read1a(5000, false, 16#8000#, "meta: sector 5000 during the stream", t);
    for n in 6002 to 6012 loop
      read1(n, false, "meta: stream sector " & integer'image(n), t);
    end loop;
    check(to_integer(misses) = m0, "  ... the stream went on (no misses)");
    -- LRU in the meta cache: 5000 is used again, so 5100 is replaced
    read1a(5100, false, 16#8000#, "meta LRU: 5100", t);
    read1a(5200, false, 16#8000#, "meta LRU: 5200", t);
    read1a(5300, false, 16#8000#, "meta LRU: 5300", t);
    read1a(5000, false, 16#8000#, "meta LRU: 5000 again", t);
    read1a(5400, false, 16#8000#, "meta LRU: 5400 replaces the oldest", t);
    m0 := to_integer(misses);
    read1a(5000, false, 16#8000#, "meta LRU: 5000 still there", t);
    check(to_integer(misses) = m0, "  ... a hit");
    read1a(5100, false, 16#8000#, "meta LRU: 5100 was replaced", t);
    check(to_integer(misses) = m0 + 1, "  ... a miss");
    -- a write updates the metadata copy
    wr_base <= 5000;
    command(3, 5000, 1, 0);
    wait_idle(10 ms);
    h0 := to_integer(hits);
    read1a(5000, true, 16#8000#, "meta: sector 5000 after a write", t);
    check(to_integer(hits) = h0 + 1, "  ... from the meta cache");

    -- a card change empties that card's part of the cache
    read1(7000, false, "card change: sector 7000", t);
    read1(7000, false, "card change: sector 7000 again", t);
    m0 := to_integer(misses);
    wait until rising_edge(cpuclock);
    media <= "01";
    wait until rising_edge(cpuclock);
    media <= "00";
    read1(7000, false, "card change: sector 7000 after it", t);
    check(to_integer(misses) = m0 + 1, "  ... a miss");

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
