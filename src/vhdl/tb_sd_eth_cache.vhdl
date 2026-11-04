-- Testbench (#965): the sector cache in front of sdcard_native_dual with the
-- network card in slot 0 (G_NET), as sdcardio_native has them, against
-- netsd.py's own server.  Run by src/tools/sim_netsd.py --tb tb_sd_eth_cache,
-- which plays the PC over tb_tx.fifo / tb_rx.fifo, as for tb_sd_eth.
--
-- The host side issues what sdcardio_native issues: single-sector reads
-- (the cache fills its 8-sector lines with open-ended reads, grants and
-- stops, and reads ahead into the next line), a run of sequential reads
-- across lines, scattered reads, an explicit 3-sector read, writes through
-- the cache read back, and the switch back to the internal socket.  Every
-- block it gets is logged to tb_reads.txt for the harness to check.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_sd_eth_cache is
  generic (
    G_FLAGS   : natural := 0;
    G_SYS_LBA : natural := 100000
    );
end entity;

architecture sim of tb_sd_eth_cache is

  function test_key return unsigned is
    variable k : unsigned(127 downto 0);
  begin
    for i in 0 to 15 loop
      k(127 - 8 * i downto 120 - 8 * i) := to_unsigned(16#40# + i, 8);
    end loop;
    return k;
  end function;

  function pattern(blk : natural; off : natural) return unsigned is
  begin
    return to_unsigned((blk * 7 + off * 13 + 16#5a#) mod 256, 8);
  end function;

  signal cpuclock, clock162, clock50 : std_logic := '0';
  signal finished : boolean := false;

  -- host <-> cache
  signal u_cmd_valid : std_logic := '0';
  signal u_cmd_ready : std_logic;
  signal u_cmd_code : unsigned(3 downto 0) := x"0";
  signal u_cmd_addr : unsigned(31 downto 0) := (others => '0');
  signal u_cmd_count, u_cmd_arg : unsigned(15 downto 0) := (others => '0');
  signal u_card_ready, u_busy, u_waiting, u_error : std_logic;
  signal u_err_code : unsigned(7 downto 0);
  signal u_rd_valid, u_rd_good, u_rd_bad, u_wr_fetch : std_logic;
  signal u_rd_data : unsigned(7 downto 0);
  signal u_rd_offset, u_wr_offset : unsigned(8 downto 0);
  signal u_rd_block, u_wr_block, u_blocks_done : unsigned(15 downto 0);
  signal u_wr_data, wr_d1 : unsigned(7 downto 0) := x"00";
  signal wr_base : natural := 0;
  signal cache_hits, cache_misses : unsigned(15 downto 0);

  -- cache <-> dual
  signal d_cmd_valid, d_cmd_ready, d_cmd_slot : std_logic;
  signal d_cmd_code : unsigned(3 downto 0);
  signal d_cmd_addr : unsigned(31 downto 0);
  signal d_cmd_count, d_cmd_arg : unsigned(15 downto 0);
  signal d_cards : unsigned(63 downto 0);
  signal d_card_ready, d_busy, d_waiting, d_error, d_native, d_hs, d_hc : std_logic;
  signal d_err_code, d_pass, d_fail : unsigned(7 downto 0);
  signal d_setting, d_done, d_rblock, d_wblock : unsigned(15 downto 0);
  signal d_rv, d_good, d_bad, d_wfetch : std_logic;
  signal d_data, d_wdata : unsigned(7 downto 0);
  signal d_roff, d_woff : unsigned(8 downto 0);
  signal d_last : unsigned(63 downto 0);
  signal d_capacity : std_logic_vector(1 downto 0);

  -- the network card
  signal ctl_write : std_logic := '0';
  signal ctl_wdata, ctl_status : unsigned(7 downto 0) := x"00";
  signal net_active : std_logic;
  signal mac : unsigned(47 downto 0) := x"024753656599";
  signal rx_ready, rx_release, tx_we, tx_go, tx_base, tx_busy : std_logic;
  signal rx_len, tx_waddr, tx_len : unsigned(10 downto 0);
  signal rx_raddr : unsigned(9 downto 0);
  signal rx_rdata, tx_wdata : unsigned(7 downto 0);
  signal rx50_start, rx50_we, rx50_end, rx50_ok : std_logic := '0';
  signal rx50_addr, rx50_len : unsigned(10 downto 0) := (others => '0');
  signal rx50_data : unsigned(7 downto 0) := x"00";
  signal tx50_pending, tx50_done : std_logic := '0';
  signal tx50_len, tx50_raddr : unsigned(10 downto 0) := (others => '0');
  signal tx50_rdata : unsigned(7 downto 0);

  -- the sockets: no cards (pulled up)
  signal sd_clk, sd_cmd_o, sd_cmd_oe : std_logic_vector(1 downto 0);
  signal sd_dat_o, sd_dat_oe : std_logic_vector(7 downto 0);
begin

  cpuclock <= not cpuclock after 12.345 ns when not finished;
  -- (the sockets' cores are idle here: a slow clock162 keeps the simulation fast)
  clock162 <= not clock162 after 50 ns when not finished;
  clock50 <= not clock50 after 10 ns when not finished;

  cache : entity work.sd_cache
    generic map (G_LINES => 4, G_WR_LAT => 2)
    port map (
      clock => cpuclock,
      u_cmd_valid => u_cmd_valid, u_cmd_ready => u_cmd_ready, u_cmd_code => u_cmd_code,
      u_cmd_addr => u_cmd_addr, u_cmd_count => u_cmd_count, u_cmd_arg => u_cmd_arg,
      u_cmd_slot => '0', u_limit_enable => '1', u_capacity_valid => d_capacity(0),
      u_last_sector => d_last(31 downto 0),
      u_card_ready => u_card_ready, u_busy => u_busy, u_waiting => u_waiting,
      u_error => u_error, u_err_code => u_err_code,
      u_native_mode => open, u_high_speed => open, u_sdhc => open, u_clk_setting => open,
      u_probe_pass => open, u_probe_fail => open, u_blocks_done => u_blocks_done,
      u_rd_valid => u_rd_valid, u_rd_data => u_rd_data, u_rd_offset => u_rd_offset,
      u_rd_block => u_rd_block, u_rd_good => u_rd_good, u_rd_bad => u_rd_bad,
      u_wr_fetch => u_wr_fetch, u_wr_offset => u_wr_offset, u_wr_block => u_wr_block,
      u_wr_data => u_wr_data,
      d_cmd_valid => d_cmd_valid, d_cmd_ready => d_cmd_ready, d_cmd_code => d_cmd_code,
      d_cmd_addr => d_cmd_addr, d_cmd_count => d_cmd_count, d_cmd_arg => d_cmd_arg,
      d_cmd_slot => d_cmd_slot, d_cards_status => d_cards,
      d_card_ready => d_card_ready, d_busy => d_busy, d_waiting => d_waiting,
      d_error => d_error, d_err_code => d_err_code, d_native_mode => d_native,
      d_high_speed => d_hs, d_sdhc => d_hc, d_clk_setting => d_setting,
      d_probe_pass => d_pass, d_probe_fail => d_fail, d_blocks_done => d_done,
      d_rd_valid => d_rv, d_rd_data => d_data, d_rd_offset => d_roff,
      d_rd_block => d_rblock, d_rd_good => d_good, d_rd_bad => d_bad,
      d_wr_fetch => d_wfetch, d_wr_offset => d_woff, d_wr_block => d_wblock,
      d_wr_data => d_wdata,
      media_change => "00", cache_on => open, cache_hits => cache_hits,
      cache_misses => cache_misses);

  dual : entity work.sdcard_native_dual
    generic map (G_XILINX => false, G_AUTO_INIT => false, G_WR_LAT => 2, G_NET => true)
    port map (
      clock162 => clock162, cpuclock => cpuclock,
      cmd_valid => d_cmd_valid, cmd_ready => d_cmd_ready, cmd_code => d_cmd_code,
      cmd_addr => d_cmd_addr, cmd_count => d_cmd_count, cmd_arg => d_cmd_arg,
      cmd_slot => d_cmd_slot, status_slot => d_cmd_slot, diag_slot => '0',
      cards_status => d_cards,
      card_ready => d_card_ready, busy => d_busy, waiting => d_waiting, error => d_error,
      err_code => d_err_code, native_mode => d_native, high_speed => d_hs, sdhc => d_hc,
      clk_setting => d_setting, probe_pass => d_pass, probe_fail => d_fail,
      blocks_done => d_done, diag_stats => open, init_diag => open, blk_diag => open,
      rd_valid => d_rv, rd_data => d_data, rd_offset => d_roff, rd_block => d_rblock,
      rd_good => d_good, rd_bad => d_bad,
      wr_fetch => d_wfetch, wr_offset => d_woff, wr_block => d_wblock, wr_data => d_wdata,
      sd_clk => sd_clk, sd_cmd_o => sd_cmd_o, sd_cmd_oe => sd_cmd_oe, sd_cmd_i => "11",
      sd_dat_o => sd_dat_o, sd_dat_oe => sd_dat_oe, sd_dat_i => x"FF",
      limit_enable => "11", cards_last_sector => d_last, cards_capacity_valid => d_capacity,
      net_ctl_write => ctl_write, net_ctl_wdata => ctl_wdata, net_ctl_status => ctl_status,
      net_active => net_active, net_mac => mac,
      net_rx_ready => rx_ready, net_rx_len => rx_len, net_rx_raddr => rx_raddr,
      net_rx_rdata => rx_rdata, net_rx_release => rx_release,
      net_tx_we => tx_we, net_tx_waddr => tx_waddr, net_tx_wdata => tx_wdata,
      net_tx_go => tx_go, net_tx_base => tx_base, net_tx_len => tx_len,
      net_tx_busy => tx_busy);

  frames : entity work.eth_netsd_buf
    port map (
      clock50 => clock50, cpuclock => cpuclock,
      rx50_start => rx50_start, rx50_we => rx50_we, rx50_addr => rx50_addr,
      rx50_data => rx50_data, rx50_end => rx50_end, rx50_ok => rx50_ok, rx50_len => rx50_len,
      tx50_pending => tx50_pending, tx50_len => tx50_len, tx50_raddr => tx50_raddr,
      tx50_rdata => tx50_rdata, tx50_done => tx50_done,
      rx_ready => rx_ready, rx_len => rx_len, rx_raddr => rx_raddr, rx_rdata => rx_rdata,
      rx_release => rx_release, tx_we => tx_we, tx_waddr => tx_waddr, tx_wdata => tx_wdata,
      tx_go => tx_go, tx_base => tx_base, tx_len => tx_len, tx_busy => tx_busy);

  -- the host's sector buffer (the byte for a fetch two cycles after it)
  process(cpuclock)
  begin
    if rising_edge(cpuclock) then
      wr_d1 <= pattern(wr_base + to_integer(u_wr_block), to_integer(u_wr_offset));
      u_wr_data <= wr_d1;
    end if;
  end process;

  -- the wire (as tb_sd_eth's) ----------------------------------------------------------
  wire : process
    file txf : text;
    file rxf : text;
    variable l : line;
    variable c, c2 : character;
    variable n : integer;
    function hexval(ch : character) return integer is
    begin
      case ch is
        when '0' to '9' => return character'pos(ch) - character'pos('0');
        when 'a' to 'f' => return character'pos(ch) - character'pos('a') + 10;
        when others => return 0;
      end case;
    end function;
    constant HEX : string(1 to 16) := "0123456789abcdef";
  begin
    file_open(txf, "tb_tx.fifo", write_mode);
    file_open(rxf, "tb_rx.fifo", read_mode);
    loop
      wait until rising_edge(clock50) and (tx50_pending = '1' or finished);
      exit when finished;
      l := new string'("");
      for a in 0 to to_integer(tx50_len) - 1 loop
        tx50_raddr <= to_unsigned(a, 11);
        wait until rising_edge(clock50);
        wait until rising_edge(clock50);
        wait for 1 ns;
        write(l, HEX(to_integer(tx50_rdata(7 downto 4)) + 1));
        write(l, HEX(to_integer(tx50_rdata(3 downto 0)) + 1));
      end loop;
      for w in 0 to to_integer(tx50_len) * 4 loop
        wait until rising_edge(clock50);
      end loop;
      writeline(txf, l);
      flush(txf);
      tx50_done <= '1';
      wait until rising_edge(clock50);
      tx50_done <= '0';
      wait until rising_edge(clock50) and tx50_pending = '0';
      loop
        readline(rxf, l);
        exit when l'length = 0 or l(l'left) = '.';
        for w in 0 to 50 loop
          wait until rising_edge(clock50);
        end loop;
        n := l'length / 2;
        rx50_start <= '1';
        wait until rising_edge(clock50);
        rx50_start <= '0';
        for k in 0 to n - 1 loop
          read(l, c);
          read(l, c2);
          rx50_we <= '1';
          rx50_addr <= to_unsigned(k, 11);
          rx50_data <= to_unsigned(hexval(c) * 16 + hexval(c2), 8);
          wait until rising_edge(clock50);
          rx50_we <= '0';
          for w in 1 to 3 loop
            wait until rising_edge(clock50);
          end loop;
        end loop;
        rx50_end <= '1';
        rx50_ok <= '1';
        rx50_len <= to_unsigned(n + 4, 11);
        wait until rising_edge(clock50);
        rx50_end <= '0';
      end loop;
    end loop;
    file_close(txf);
    file_close(rxf);
    wait;
  end process;

  -- the host (sdcardio_native's part) -------------------------------------------------------
  host : process
    file logf : text open write_mode is "tb_reads.txt";
    variable l : line;
    variable buf : unsigned(4095 downto 0);
    variable errors, good : integer := 0;
    variable sr : unsigned(167 downto 0);
    variable lba : natural;
    constant HEX : string(1 to 16) := "0123456789abcdef";

    procedure check(cond : boolean; msg : string) is
    begin
      if not cond then
        report "FAIL: " & msg severity error;
        errors := errors + 1;
      end if;
    end procedure;

    procedure cmd(code : unsigned(3 downto 0); addr : natural; count : natural; arg : natural) is
    begin
      wait until rising_edge(cpuclock) and u_cmd_ready = '1';
      u_cmd_code <= code;
      u_cmd_addr <= to_unsigned(addr, 32);
      u_cmd_count <= to_unsigned(count, 16);
      u_cmd_arg <= to_unsigned(arg, 16);
      u_cmd_valid <= '1';
      wait until rising_edge(cpuclock);
      u_cmd_valid <= '0';
      wait until rising_edge(cpuclock) and u_cmd_ready = '1';
    end procedure;

    procedure ctl(v : unsigned(7 downto 0)) is
    begin
      wait until rising_edge(cpuclock);
      ctl_wdata <= v;
      ctl_write <= '1';
      wait until rising_edge(cpuclock);
      ctl_write <= '0';
    end procedure;

    procedure log_block(b : natural) is
    begin
      write(l, string'("R "));
      write(l, b);
      write(l, string'(" "));
      for k in 0 to 511 loop
        write(l, HEX(to_integer(buf(8 * k + 7 downto 8 * k + 4)) + 1));
        write(l, HEX(to_integer(buf(8 * k + 3 downto 8 * k)) + 1));
      end loop;
      writeline(logf, l);
    end procedure;

    -- read count sectors from addr (as sdcardio_native: $02 is count 1)
    procedure read_sectors(addr : natural; count : natural) is
      variable got : natural := 0;
    begin
      -- issue it and collect at once: the cache streams a miss's first
      -- sector up before it is ready for the next command
      wait until rising_edge(cpuclock) and u_cmd_ready = '1';
      u_cmd_code <= x"2";
      u_cmd_addr <= to_unsigned(addr, 32);
      u_cmd_count <= to_unsigned(count, 16);
      u_cmd_arg <= (others => '0');
      u_cmd_valid <= '1';
      wait until rising_edge(cpuclock);
      u_cmd_valid <= '0';
      loop
        wait until rising_edge(cpuclock);
        if u_rd_valid = '1' then
          buf(8 * to_integer(u_rd_offset) + 7 downto 8 * to_integer(u_rd_offset)) := u_rd_data;
        end if;
        if u_rd_good = '1' then
          log_block(addr + to_integer(u_rd_block));
          good := good + 1;
          got := got + 1;
        end if;
        exit when u_busy = '0' and u_cmd_ready = '1' and got >= count;
        exit when u_error = '1' and u_cmd_ready = '1';
      end loop;
      report "read " & integer'image(addr) & " done";
      check(u_error = '0' and got = count, "read " & integer'image(count) & " at "
            & integer'image(addr) & ": got " & integer'image(got) & ", error $" & to_hstring(u_err_code));
    end procedure;

    procedure wait_idle is
    begin
      wait until rising_edge(cpuclock) and u_busy = '0' and u_cmd_ready = '1';
    end procedure;
  begin
    wait for 500 ns;
    sr := to_unsigned(G_FLAGS, 8) & test_key & x"0badcafe";
    for w in 23 downto 0 loop
      ctl('0' & sr(7 * w + 6 downto 7 * w));
    end loop;
    ctl(x"80" or to_unsigned(65, 8));      -- (the harness has a card for 65)
    wait until rising_edge(cpuclock);
    check(net_active = '1', "on");
    -- init slot 0 (arg bit 4 = slot): the network card
    cmd(x"1", 0, 0, 0);
    report "init issued";
    wait_idle;
    report "init done: ready " & std_logic'image(u_card_ready) & " error $" & to_hstring(u_err_code);
    check(u_card_ready = '1' and u_error = '0', "connected (error $" & to_hstring(u_err_code) & ")");
    check(d_capacity(0) = '1', "capacity known");

    -- the boot's reads: MBR, then the FAT32 boot sector and FSInfo (misses
    -- that fill lines), then a run of 20 sequential sectors across lines
    read_sectors(0, 1);
    read_sectors(2048, 1);
    read_sectors(2049, 1);
    for s in 0 to 19 loop
      read_sectors(2048 + 568 + s, 1);
    end loop;
    report "cache: " & integer'image(to_integer(cache_hits)) & " hits, "
      & integer'image(to_integer(cache_misses)) & " misses";
    check(cache_hits > 10, "the cache's lines were filled from the network card");
    -- scattered sectors, and the same ones again (hits)
    lba := 3000;
    for s in 0 to 5 loop
      read_sectors(lba, 1);
      lba := lba + 977;
    end loop;
    read_sectors(3000, 1);
    read_sectors(3977, 1);
    -- an explicit multi-sector read
    read_sectors(5000, 3);
    -- writes, through the cache
    wr_base <= 0;
    cmd(x"3", G_SYS_LBA, 1, 0);
    wait_idle;
    check(u_error = '0', "write (error $" & to_hstring(u_err_code) & ")");
    read_sectors(G_SYS_LBA, 1);
    check(buf(7 downto 0) = pattern(0, 0) and buf(4095 downto 4088) = pattern(0, 511),
          "written sector read back");
    -- a write to the read-only FAT32 partition is refused
    cmd(x"3", 2048 + 600, 1, 0);
    wait_idle;
    check(u_error = '1', "read-only write refused");
    read_sectors(2048 + 600, 1);

    -- off: slot 0 is the internal socket again (no card there)
    ctl(x"80");
    wait until rising_edge(cpuclock);
    check(net_active = '0', "off");
    check(d_cards(0) = '0', "the internal socket's card is not ready (none)");

    report "tb_sd_eth_cache: " & integer'image(good) & " blocks read, "
      & integer'image(errors) & " errors";
    write(l, string'("DONE "));
    write(l, errors);
    writeline(logf, l);
    file_close(logf);
    finished <= true;
    if errors = 0 then
      report "PASS";
    else
      report "FAILED" severity failure;
    end if;
    wait;
  end process;

  -- what the cache asks of the dual controller, and what comes back
  trace : process(cpuclock)
  begin
    if rising_edge(cpuclock) then
      if d_cmd_valid = '1' then
        report "cache -> card: cmd " & to_hstring(d_cmd_code) & " addr " & integer'image(to_integer(d_cmd_addr))
          & " count " & integer'image(to_integer(d_cmd_count)) & " arg " & to_hstring(d_cmd_arg);
      end if;
      if d_good = '1' or d_bad = '1' then
        report "card -> cache: block " & integer'image(to_integer(d_rblock)) & " good "
          & std_logic'image(d_good) & " busy " & std_logic'image(d_busy) & " waiting " & std_logic'image(d_waiting);
      end if;
      if u_rd_good = '1' then
        report "cache -> host: block " & integer'image(to_integer(u_rd_block));
      end if;
    end if;
  end process;

  -- the handshake signals whenever they change
  status : process(cpuclock)
    variable last : std_logic_vector(6 downto 0) := (others => 'X');
    variable now : std_logic_vector(6 downto 0);
  begin
    if rising_edge(cpuclock) then
      now := u_busy & u_cmd_ready & u_error & d_busy & d_waiting & d_cmd_ready & d_error;
      if now /= last then
        report "status: u_busy " & std_logic'image(u_busy) & " u_ready " & std_logic'image(u_cmd_ready)
          & " u_err " & std_logic'image(u_error) & " | d_busy " & std_logic'image(d_busy)
          & " d_wait " & std_logic'image(d_waiting) & " d_ready " & std_logic'image(d_cmd_ready)
          & " d_err " & std_logic'image(d_error);
        last := now;
      end if;
    end if;
  end process;

  watchdog : process
  begin
    wait for 40 ms;
    if not finished then
      report "watchdog: stuck" severity failure;
    end if;
    wait;
  end process;
end architecture;
