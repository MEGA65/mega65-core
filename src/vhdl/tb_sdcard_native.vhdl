--------------------------------------------------------------------------------
-- tb_sdcard_native: sdcard_native against sdcard_native_model.
--
--   ghdl -a --std=08 sdcard_native.vhdl sdcard_native_model.vhdl tb_sdcard_native.vhdl
--   ghdl -r --std=08 tb_sdcard_native -gG_SPI_CARD=false
--   ghdl -r --std=08 tb_sdcard_native -gG_SPI_CARD=true
--
-- G_SPI_CARD: the card is already in SPI mode (as after a core that used it),
-- so the controller must fall back to SPI.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sdcard_native is
  generic (
    G_SPI_CARD : boolean := false;
    G_TRACE    : boolean := false;
    G_STOP_TEST : boolean := false;
    G_SINGLE_CRC_TEST : boolean := false;
    G_LONG_READ_NAC : natural := 0;
    G_LONG_MULTI_NAC : natural := 2;
    G_STOP_FAILS : natural := 0;
    G_STOP_ACK_FAILS : natural := 0;
    G_INFO_TEST : boolean := false;
    G_INFO_BAD_CRC : boolean := false;
    G_INFO_TIMEOUT : boolean := false;
    G_INFO_BAD_HEADER : boolean := false;
    G_BOUND_TEST : boolean := false;
    G_SDHC_CARD : boolean := true;
    G_MAXCARD_TEST : boolean := false;
    G_CAPFAIL_TEST : boolean := false
    );
end entity;

architecture tb of tb_sdcard_native is

  constant T162 : time := 6172 ps;
  constant TCPU : time := 4 * T162;
  constant BOARD : time := 1500 ps;     -- each way
  function size_units return positive is
  begin
    if G_MAXCARD_TEST then return 4194304;
    elsif G_BOUND_TEST then return 1; else return 244140; end if;
  end function;
  signal limit_enable : std_logic := '1';
  signal capacity_valid : std_logic;
  signal last_sector : unsigned(31 downto 0);

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

  signal cmd_valid   : std_logic := '0';
  signal cmd_ready   : std_logic;
  signal cmd_code    : unsigned(3 downto 0) := (others => '0');
  signal cmd_addr    : unsigned(31 downto 0) := (others => '0');
  signal cmd_count   : unsigned(15 downto 0) := (others => '0');
  signal cmd_arg     : unsigned(15 downto 0) := (others => '0');
  signal card_ready  : std_logic;
  signal busy        : std_logic;
  signal waiting     : std_logic;
  signal error       : std_logic;
  signal err_code    : unsigned(7 downto 0);
  signal native_mode : std_logic;
  signal high_speed  : std_logic;
  signal sdhc        : std_logic;
  signal clk_setting : unsigned(15 downto 0);
  signal probe_pass  : unsigned(7 downto 0);
  signal probe_fail  : unsigned(7 downto 0);
  signal blocks_done : unsigned(15 downto 0);
  signal rd_valid    : std_logic;
  signal rd_data     : unsigned(7 downto 0);
  signal rd_offset   : unsigned(8 downto 0);
  signal rd_block    : unsigned(15 downto 0);
  signal rd_good     : std_logic;
  signal rd_bad      : std_logic;
  signal diag_stats : unsigned(127 downto 0);
  signal wr_fetch    : std_logic;
  signal wr_offset   : unsigned(8 downto 0);
  signal wr_block    : unsigned(15 downto 0);
  signal wr_data     : unsigned(7 downto 0) := (others => '0');

  signal sd_clk    : std_logic_vector(1 downto 0);
  signal sd_cmd_o  : std_logic_vector(1 downto 0);
  signal sd_cmd_oe : std_logic_vector(1 downto 0);
  signal sd_cmd_i  : std_logic_vector(1 downto 0) := "11";
  signal sd_dat_o  : std_logic_vector(7 downto 0);
  signal sd_dat_oe : std_logic_vector(7 downto 0);
  signal sd_dat_i  : std_logic_vector(7 downto 0) := (others => '1');

  -- the card side of the slot 0 wires
  signal card_clk : std_logic := '1';
  signal card_cmd : std_logic;
  signal card_dat : std_logic_vector(3 downto 0);
  signal host_cmd : std_logic;
  signal host_dat : std_logic_vector(3 downto 0);

  -- what the read stream delivered
  type t_rx is array (0 to 15, 0 to 511) of unsigned(7 downto 0);
  signal rx       : t_rx;
  signal n_good   : natural := 0;
  signal n_bad    : natural := 0;
  signal n_bytes  : natural := 0;
  signal wr_base  : natural := 0;       -- block number of write block 0
  signal pipe1    : unsigned(7 downto 0) := (others => '0');
  signal max_gap  : natural := 0;

  signal fails    : natural := 0;
  signal clr      : boolean := false;

begin

  clock162 <= not clock162 after T162 / 2 when not done;
  cpuclock <= not cpuclock after TCPU / 2 when not done;

  dut : entity work.sdcard_native
    generic map (G_XILINX => false, G_MS => 1620, G_TRACE => G_TRACE)   -- 1 "ms" = 10 us
    port map (
      clock162 => clock162, cpuclock => cpuclock,
      cmd_valid => cmd_valid, cmd_ready => cmd_ready, cmd_code => cmd_code,
      cmd_addr => cmd_addr, cmd_count => cmd_count, cmd_arg => cmd_arg,
      card_ready => card_ready, busy => busy, waiting => waiting, error => error,
      err_code => err_code, native_mode => native_mode, high_speed => high_speed,
      sdhc => sdhc, clk_setting => clk_setting, probe_pass => probe_pass,
      probe_fail => probe_fail, blocks_done => blocks_done, diag_stats => diag_stats,
      rd_valid => rd_valid, rd_data => rd_data, rd_offset => rd_offset,
      rd_block => rd_block, rd_good => rd_good, rd_bad => rd_bad,
      wr_fetch => wr_fetch, wr_offset => wr_offset, wr_block => wr_block,
      wr_data => wr_data,
      sd_clk => sd_clk, sd_cmd_o => sd_cmd_o, sd_cmd_oe => sd_cmd_oe,
      sd_cmd_i => sd_cmd_i, sd_dat_o => sd_dat_o, sd_dat_oe => sd_dat_oe,
      sd_dat_i => sd_dat_i, limit_enable => limit_enable,
      capacity_valid => capacity_valid, last_sector => last_sector);

  -- the board: pull-ups, and a delay each way
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

  card : entity work.sdcard_native_model
    generic map (G_START_SPI => G_SPI_CARD, G_CRC_ERR_BLK => 101,
                 G_STOP_FAILS => G_STOP_FAILS, G_STOP_ACK_FAILS => G_STOP_ACK_FAILS,
                 G_STRICT_STOP => G_SINGLE_CRC_TEST,
                 G_LONG_READ_NAC => G_LONG_READ_NAC,
                 G_LONG_MULTI_NAC => G_LONG_MULTI_NAC,
                 G_INFO_BAD_CRC => G_INFO_BAD_CRC, G_INFO_TIMEOUT => G_INFO_TIMEOUT,
                 G_INFO_BAD_HEADER => G_INFO_BAD_HEADER,
                 G_SIZE_UNITS => size_units, G_SDHC => G_SDHC_CARD,
                 G_UNSUPPORTED_CSD => G_CAPFAIL_TEST)
    port map (clk => card_clk, cmd => card_cmd, dat => card_dat);

  -- host: keep the read stream, answer write fetches (latency 2)
  host : process (cpuclock)
    variable gap : natural := 0;
  begin
    if rising_edge(cpuclock) then
      if clr then
        for k in 0 to 15 loop
          for i in 0 to 511 loop
            rx(k, i) <= x"EE";
          end loop;
        end loop;
        n_good  <= 0;
        n_bad   <= 0;
        n_bytes <= 0;
        max_gap <= 0;
      elsif rd_valid = '1' then
        rx(to_integer(rd_block) mod 16, to_integer(rd_offset)) <= rd_data;
        n_bytes <= n_bytes + 1;
        if gap > max_gap and to_integer(rd_offset) /= 0 then
          max_gap <= gap;
        end if;
        gap := 0;
      else
        gap := gap + 1;
      end if;
      if rd_good = '1' and not clr then n_good <= n_good + 1; end if;
      if rd_bad = '1' and not clr then n_bad <= n_bad + 1; end if;
      if wr_fetch = '1' then
        pipe1 <= wpattern(wr_base + to_integer(wr_block), to_integer(wr_offset));
      end if;
      wr_data <= pipe1;
    end if;
  end process;

  stim : process

    procedure command(code : natural; addr : natural; count : natural; arg : natural) is
    begin
      wait until rising_edge(cpuclock) and cmd_ready = '1';
      cmd_code  <= to_unsigned(code, 4);
      cmd_addr  <= to_unsigned(addr, 32);
      cmd_count <= to_unsigned(count, 16);
      cmd_arg   <= to_unsigned(arg, 16);
      cmd_valid <= '1';
      wait until rising_edge(cpuclock);
      cmd_valid <= '0';
      wait until rising_edge(cpuclock) and cmd_ready = '1';
    end procedure;

    procedure wait_idle(tmo : time) is
    begin
      if busy = '1' then
        wait until busy = '0' for tmo;
      end if;
      assert busy = '0' report "timeout waiting for idle" severity failure;
      wait until rising_edge(cpuclock);
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
      if cond then
        report "PASS: " & msg;
      else
        report "FAIL: " & msg severity std.standard.error;
        fails <= fails + 1;
        wait for 0 ns;
      end if;
    end procedure;

    procedure check_blocks(first : natural; n : natural; written : boolean; msg : string) is
      variable bad : natural := 0;
      variable v   : unsigned(7 downto 0);
    begin
      for k in 0 to n - 1 loop
        for i in 0 to 511 loop
          if written then v := wpattern(first + k, i); else v := pattern(first + k, i); end if;
          if rx(k mod 16, i) /= v then
            if bad < 4 then
              report "  block " & integer'image(first + k) & " byte " & integer'image(i)
                & " got " & to_hstring(rx(k mod 16, i)) & " want " & to_hstring(v);
            end if;
            bad := bad + 1;
          end if;
        end loop;
      end loop;
      check(bad = 0, msg);
    end procedure;

    procedure clear_rx is
    begin
      clr <= true;
      wait until rising_edge(cpuclock);
      clr <= false;
      wait until rising_edge(cpuclock);
    end procedure;

    variable t0 : time;
    variable g  : natural;
    variable last : natural;
    variable want : unsigned(7 downto 0);
    constant csd : std_logic_vector(127 downto 0) := x"400E00325B590003B9AB7F800A400067";
    constant cid : std_logic_vector(127 downto 0) := x"03534453453136308012345678017AEB";
    constant scr : std_logic_vector(63 downto 0) := x"0235800100000000";

  begin
    -- power-up init
    wait for 100 ns;
    if G_CAPFAIL_TEST then
      wait_idle(40 ms);
      check(error = '1' and err_code = x"45" and card_ready = '0' and capacity_valid = '0',
            "unknown capacity cannot initialise with protection enabled");
      limit_enable <= '0'; wait for 4*TCPU;
      command(1, 0, 0, 0); wait_idle(10 ms);
      check(error = '0' and card_ready = '1' and capacity_valid = '0',
            "explicit override permits init with unknown capacity");
      clear_rx; command(2, 5, 1, 0); wait_idle(5 ms);
      check_blocks(5, 1, false, "unknown-capacity override permits ordinary reads");
      limit_enable <= '1'; wait for 4*TCPU;
      clear_rx; command(2, 5, 1, 0); wait_idle(5 ms);
      check(error = '1' and err_code = x"45" and n_bytes = 0, "re-enabling unknown capacity blocks reads");
      report "ALL CAPFAIL TESTS PASSED"; done <= true; wait;
    end if;
    wait until card_ready = '1' and busy = '0' for 40 ms;
    check(card_ready = '1' and error = '0', "auto init");
    report "  native=" & std_logic'image(native_mode) & " hs=" & std_logic'image(high_speed)
      & " sdhc=" & std_logic'image(sdhc) & " setting=" & to_hstring(clk_setting);
    if G_SPI_CARD then
      check(native_mode = '0', "fell back to SPI");
    else
      check(native_mode = '1' and high_speed = '1', "native, high speed");
      check(clk_setting = x"0808", "40.5 MHz setting");
    end if;

    if G_MAXCARD_TEST then
      check(capacity_valid = '1' and last_sector = x"FFFFFFFF", "2 TiB capacity keeps inclusive last LBA");
      clear_rx;
      wait until rising_edge(cpuclock) and cmd_ready = '1';
      cmd_code <= x"2"; cmd_addr <= x"FFFFFFFF"; cmd_count <= x"0002"; cmd_arg <= x"0000";
      cmd_valid <= '1'; wait until rising_edge(cpuclock); cmd_valid <= '0';
      wait until rising_edge(cpuclock) and cmd_ready = '1'; wait_idle(5 ms);
      check(error = '1' and err_code = x"44" and n_bytes = 0, "range end cannot wrap at 2 TiB");
      report "ALL MAXCAP TESTS PASSED"; done <= true; wait;
    end if;
    if G_BOUND_TEST then
      if G_SDHC_CARD then last := 1023; else last := 2097151; end if;
      check(capacity_valid = '1' and last_sector = last, "capacity decoded before ready");
      clear_rx; command(2, last, 1, 0); wait_idle(5 ms);
      check_blocks(last, 1, false, "last reported sector is readable");
      clear_rx; command(2, last+1, 1, 0); wait_idle(5 ms);
      check(error = '1' and err_code = x"44" and n_bytes = 0, "reject first out-of-range read");
      clear_rx; command(3, last+1, 1, 0); wait_idle(5 ms);
      check(error = '1' and err_code = x"44", "reject out-of-range write");
      clear_rx; command(2, last, 2, 0); wait_idle(5 ms);
      check(error = '1' and err_code = x"44" and n_bytes = 0, "reject whole read crossing capacity");
      wr_base <= last;
      command(3, last, 2, 0); wait_idle(5 ms);
      check(error = '1' and err_code = x"44", "reject whole write crossing capacity");
      clear_rx; command(2, last, 1, 0); wait_idle(5 ms);
      check_blocks(last, 1, false, "rejected multi-write changed no valid sector");
      clear_rx; command(2, last, 0, 0);
      wait until waiting = '1' for 5 ms;
      check(waiting = '1' and n_good = 1, "open read pauses at last valid sector");
      command(4, 0, 0, 0); wait_idle(5 ms);
      check(error = '1' and err_code = x"44" and n_good = 1 and n_bytes = 512,
            "out-of-range grant closes stream without another sector");
      command(3, last, 0, 0);
      wait until waiting = '1' for 5 ms;
      check(waiting = '1' and blocks_done = 1, "open write pauses at last valid sector");
      command(4, 0, 0, 0); wait_idle(5 ms);
      check(error = '1' and err_code = x"44" and blocks_done = 1,
            "out-of-range write grant closes without another sector");
      limit_enable <= '0'; wait for 4*TCPU;
      clear_rx; command(2, last+1, 1, 0); wait_idle(5 ms);
      check_blocks(last+1, 1, false, "override permits read and rejected write changed nothing");
      wr_base <= last+1; command(3, last+1, 1, 0); wait_idle(5 ms);
      check(error = '0', "override permits write");
      clear_rx; command(2, last+1, 1, 0); wait_idle(5 ms);
      check_blocks(last+1, 1, true, "override write reached the simulated card");
      limit_enable <= '1'; wait for 4*TCPU;
      clear_rx; command(2, last+1, 1, 0); wait_idle(5 ms);
      check(error = '1' and err_code = x"44" and n_bytes = 0, "re-enabling protection restores range checks");
      limit_enable <= '0'; wait for 4*TCPU;
      command(1, 0, 0, 0); wait_idle(10 ms);
      clear_rx; command(2, last+1, 1, 0); wait_idle(5 ms);
      check_blocks(last+1, 1, true, "override survives card reset");
      report "ALL BOUND TESTS PASSED"; done <= true; wait;
    end if;
    if G_INFO_TEST then
      for kind in 0 to 3 loop
        clear_rx;
        command(11, 0, 1, kind); wait_idle(5 ms);
        if G_INFO_BAD_CRC or G_INFO_TIMEOUT or (G_INFO_BAD_HEADER and kind < 2) then
          check(error = '1' and n_good = 0 and n_bad = 1,
                "bad info never publishes a successful buffer");
          if G_INFO_BAD_CRC then check(err_code = x"21", "info CRC error is reported"); end if;
          if G_INFO_BAD_HEADER and kind < 2 then check(err_code = x"10", "malformed R2 header is rejected"); end if;
          command(9, 0, 0, 0); wait_idle(5 ms);
          check(error = '0' and card_ready = '1', "recover info failure without reset");
        else
          check(error = '0' and n_good = 1 and n_bad = 0 and n_bytes = 512,
                "info completes one 512-byte buffer");
          for i in 0 to 511 loop
            want := x"00";
            if kind = 0 and i < 16 then want := unsigned(csd(127-i*8 downto 120-i*8));
            elsif kind = 1 and i < 16 then want := unsigned(cid(127-i*8 downto 120-i*8));
            elsif kind = 2 and i < 8 then want := unsigned(scr(63-i*8 downto 56-i*8));
            elsif kind = 3 and i < 64 then
              if i = 0 then want := x"80"; elsif i = 8 then want := x"04";
              else want := to_unsigned((i*13+7) mod 256, 8); end if;
            end if;
            assert rx(0,i) = want report "info payload/padding mismatch kind "
              & integer'image(kind) & " offset " & integer'image(i)
              & " got " & to_hstring(rx(0,i)) & " want " & to_hstring(want) severity failure;
          end loop;
        end if;
        clear_rx; command(2, 5, 1, 0); wait_idle(5 ms);
        check(error = '0', "sector read works after info command");
        check_blocks(5, 1, false, "info preserves card selection and data mode");
      end loop;
      clear_rx; command(11, 0, 1, 4); wait_idle(5 ms);
      check(error = '1' and err_code = x"43" and n_bytes = 0, "reject invalid info selector");
      check(diag_stats(79 downto 32) = 0, "info failures are not sector-read errors");
      report "ALL INFO TESTS PASSED";
      done <= true; wait;
    end if;

    if G_STOP_TEST then
      clear_rx;
      command(2, 200, 0, 0);
      wait until waiting = '1' for 5 ms;
      check(waiting = '1' and n_good = 1, "close test: open read paused");
      command(5, 0, 0, 0);
      wait_idle(10 ms);
      if G_STOP_FAILS >= 3 or G_STOP_ACK_FAILS >= 3 then
        check(error = '1' and card_ready = '0', "failed close invalidates card");
        check(diag_stats(31 downto 16) = 2 and diag_stats(111 downto 96) = 1,
              "two stop retries and one terminal stop failure counted");
        clear_rx;
        command(2, 300, 1, 0);
        wait_idle(5 ms);
        check(error = '1' and err_code = x"41" and n_bytes = 0,
              "read after failed close is rejected without stale data");
        t0 := now;
        command(9, 0, 0, 0);
        wait_idle(5 ms);
        if G_STOP_FAILS = 3 or G_STOP_ACK_FAILS = 3 then
          check(error = '0' and card_ready = '1' and high_speed = '1'
                and clk_setting = x"0808", "clear recovers existing card session");
          check(now - t0 < 100 us, "recovery does not reinitialise the card");
          clear_rx;
          command(2, 300, 1, 0);
          wait_idle(5 ms);
          check_blocks(300, 1, false, "requested sector after clear/recover");
        else
          check(error = '1' and card_ready = '0', "clear cannot falsely acknowledge an unclosed card");
        end if;
      else
        check(error = '0' and card_ready = '1', "close recovered and card ready");
        if G_STOP_FAILS = 1 or G_STOP_ACK_FAILS = 1 then
          check(diag_stats(31 downto 16) = 1 and diag_stats(111 downto 96) = 0,
                "recovered stop counted without a terminal stop failure");
        end if;
        clear_rx;
        command(2, 300, 1, 0);
        wait_idle(5 ms);
        check(error = '0' and n_good = 1, "read after checked close");
        check_blocks(300, 1, false, "read after close is requested sector");
      end if;
      report "ALL STOP TESTS PASSED";
      done <= true;
      wait;
    end if;

    if G_LONG_READ_NAC /= 0 then
      clear_rx;
      command(2, 300, 1, 0);
      wait_idle(15 ms);
      check(error = '0' and n_good = 1 and n_bad = 0,
            "single read after long card access delay");
      check_blocks(300, 1, false, "long-latency single read data");
      clear_rx;
      command(2, 300, 4, 0);
      wait_idle(20 ms);
      check(error = '0' and n_good = 4 and n_bad = 0,
            "multi read with long first/inter-block card delays");
      check_blocks(300, 4, false, "long-latency multi read data");
      report "ALL LONG READ TESTS PASSED";
      done <= true;
      wait;
    end if;

    if G_SINGLE_CRC_TEST then
      -- The card has completed CMD17 and returned to Transfer when the host
      -- detects the injected CRC error. CMD12 is then illegal/no-response.
      clear_rx;
      command(2, 101, 1, 0);
      wait_idle(10 ms);
      check(error = '0' and card_ready = '1' and n_good = 1 and n_bad = 1,
            "single CRC retry accepts confirmed Transfer without CMD12 reply");
      check_blocks(101, 1, false, "single CRC retry data");
      check(diag_stats(15 downto 0) = 1 and diag_stats(47 downto 32) = 1,
            "recovered single CRC counted as one retry and one CRC event");
      t0 := now;
      command(9, 0, 0, 0);
      wait_idle(5 ms);
      check(error = '0' and card_ready = '1', "clear on idle Transfer card");
      check(now - t0 < 100 us, "idle clear does not reinitialise card");
      report "ALL SINGLE CRC TESTS PASSED";
      done <= true;
      wait;
    end if;

    -- single block read
    clear_rx;
    command(2, 5, 1, 0);
    wait_idle(5 ms);
    check(error = '0' and n_good = 1 and n_bad = 0 and n_bytes = 512, "single read status");
    check_blocks(5, 1, false, "single read data");

    -- multi-block read, block 101 has a CRC error the first time
    clear_rx;
    t0 := now;
    command(2, 99, 4, 0);
    wait_idle(10 ms);
    report "  4 blocks in " & time'image(now - t0) & ", max gap inside a block "
      & integer'image(max_gap) & " cycles";
    check(error = '0' and n_good = 4 and n_bad = 1, "multi read with one CRC retry");
    check_blocks(99, 4, false, "multi read data");
    check(diag_stats(15 downto 0) = 1 and diag_stats(47 downto 32) = 1,
          "recovered multi CRC counted without a terminal failure");
    check(diag_stats(95 downto 80) = 0, "CRC recovery is not a terminal read failure");

    -- open-ended read: first / next / last
    clear_rx;
    command(2, 200, 0, 0);
    wait until waiting = '1' for 5 ms;
    check(waiting = '1' and n_good = 1, "open read: first block, waiting");
    wait for 20 us;                       -- the clock is stopped meanwhile
    command(4, 0, 0, 0);
    wait until waiting = '0' for 1 us;
    wait until waiting = '1' for 5 ms;
    check(waiting = '1' and n_good = 2, "open read: second block, waiting");
    command(4, 0, 0, 1);
    wait_idle(5 ms);
    check(error = '0' and n_good = 3 and n_bad = 0, "open read: last block");
    check_blocks(200, 3, false, "open read data");

    -- single block write, read back
    wr_base <= 300;
    command(3, 300, 1, 0);
    wait_idle(5 ms);
    check(error = '0' and blocks_done = 1, "single write");
    clear_rx;
    command(2, 300, 1, 0);
    wait_idle(5 ms);
    check_blocks(300, 1, true, "single write read back");

    -- multi-block write (3), read back
    wr_base <= 400;
    command(3, 400, 3, 0);
    wait_idle(10 ms);
    check(error = '0' and blocks_done = 3, "multi write");
    clear_rx;
    command(2, 400, 3, 0);
    wait_idle(10 ms);
    check_blocks(400, 3, true, "multi write read back");

    -- open-ended write: first / last
    wr_base <= 500;
    command(3, 500, 0, 0);
    wait until waiting = '1' for 5 ms;
    check(waiting = '1' and blocks_done = 1, "open write: first block");
    command(4, 0, 0, 1);
    wait_idle(5 ms);
    check(error = '0' and blocks_done = 2, "open write: last block");
    clear_rx;
    command(2, 500, 2, 0);
    wait_idle(10 ms);
    check_blocks(500, 2, true, "open write read back");

    if not G_SPI_CARD then
      -- probe 81 MHz at a few sample points
      for d in 0 to 8 loop
        command(6, 7, 3, 4 + d * 256);
        wait_idle(10 ms);
        report "  probe P=4 D=" & integer'image(d) & ": pass " & integer'image(to_integer(probe_pass))
          & " fail " & integer'image(to_integer(probe_fail)) & " err " & to_hstring(err_code);
      end loop;
      command(6, 7, 3, 4 + 4 * 256);
      wait_idle(10 ms);
      check(probe_pass = 3 and probe_fail = 0 and clk_setting = x"0808", "probe P=4 D=4 passes, setting kept");
      command(6, 7, 3, 4 + 2 * 256);
      wait_idle(10 ms);
      check(probe_pass = 0 and probe_fail = 3, "probe P=4 D=2 (in the card's X window) fails");
      command(6, 7, 3, 4 + 8 * 256);
      wait_idle(10 ms);
      check(probe_pass = 3 and probe_fail = 0, "probe P=4 D=8 (two SD clocks late) passes");

      -- accept 81 MHz and read
      command(7, 0, 0, 4 + 4 * 256);
      wait_idle(1 ms);
      check(clk_setting = x"0404", "accepted 81 MHz");
      clear_rx;
      t0 := now;
      command(2, 600, 8, 0);
      wait_idle(10 ms);
      report "  8 blocks at 81 MHz in " & time'image(now - t0) & ", max gap inside a block "
        & integer'image(max_gap) & " cycles";
      check(error = '0' and n_good = 8 and n_bad = 0, "81 MHz multi read");
      check_blocks(600, 8, false, "81 MHz multi read data");

      -- write at 81 MHz
      wr_base <= 700;
      command(3, 700, 4, 0);
      wait_idle(10 ms);
      check(error = '0' and blocks_done = 4, "81 MHz multi write");
      clear_rx;
      command(2, 700, 4, 0);
      wait_idle(10 ms);
      check_blocks(700, 4, true, "81 MHz write read back");

      -- odd divider: 64.8 MHz
      command(6, 7, 2, 5 + 5 * 256);
      wait_idle(10 ms);
      report "  probe P=5 D=5: pass " & integer'image(to_integer(probe_pass));
      command(7, 0, 0, 5 + 5 * 256);
      wait_idle(1 ms);
      clear_rx;
      command(2, 800, 2, 0);
      wait_idle(10 ms);
      check(error = '0' and n_good = 2, "64.8 MHz read");
      check_blocks(800, 2, false, "64.8 MHz read data");

      -- back to normal; a bad command
      command(7, 0, 0, 0);
      wait_idle(1 ms);
      check(clk_setting = x"0808", "back to 40.5 MHz");
    end if;

    command(15, 0, 0, 0);
    wait_idle(1 ms);
    check(error = '1' and err_code = x"43", "unknown command refused");

    -- re-init
    command(1, 0, 0, 0);
    wait until card_ready = '1' and busy = '0' for 40 ms;
    check(card_ready = '1' and error = '0', "re-init");
    check(diag_stats(15 downto 0) = 1 and diag_stats(47 downto 32) = 1,
          "diagnostic counters survive re-init and exclude probe errors");
    clear_rx;
    command(2, 42, 1, 0);
    wait_idle(5 ms);
    check_blocks(42, 1, false, "read after re-init");

    if fails = 0 then
      report "ALL TESTS PASSED";
    else
      report integer'image(fails) & " TESTS FAILED" severity std.standard.error;
    end if;
    done <= true;
    wait;
  end process;

end architecture;
