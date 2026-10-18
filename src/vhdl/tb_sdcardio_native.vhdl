--------------------------------------------------------------------------------
-- tb_sdcardio_native: the sdcardio fork (sdcardio_native) driven through its
-- registers, as the CPU would, with sdcard_native_model in slot 0.
-- (VHDL-93, like sdcardio.)
--
-- GHDL needs the rest of the sources in the work library, a UNISIM library
-- with an ICAPE2 component (reconfig.vhdl; icape2sim.vhdl's entity of the
-- same name must then be left out), and -frelaxed:
--   for f in src/vhdl/*.vhdl; do ghdl -i --std=93c -fsynopsys -frelaxed $f; done
--   ghdl -m --std=93c -fsynopsys -frelaxed tb_sdcardio_native
--   ghdl -r --std=93c -fsynopsys -frelaxed tb_sdcardio_native --stop-time=200ms
-- (skipping files that need UNISIM / XPM, other than reconfig.vhdl).
--
-- G_BOOT_TEST=true runs the legacy busy/ready regressions, without writes.
-- Also run it with G_CACHE_LINES=0 and with G_SPI_CARD=true.  These cover
-- empty-slot fallback and immediate reset polling with and without the cache
-- and with a card left in SPI mode by a previous core.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cputypes.all;

entity tb_sdcardio_native is
  generic (
    G_BOOT_TEST   : boolean := false;
    G_ERROR_TEST  : boolean := false;
    G_CACHE_LINES : natural := 16;
    G_SPI_CARD    : boolean := false
    );
end entity;

architecture tb of tb_sdcardio_native is

  constant T162  : time := 6172 ps;
  constant TCPU  : time := 4 * T162;
  constant BOARD : time := 1500 ps;

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

  signal fastio_addr  : unsigned(19 downto 0) := (others => '0');
  signal fastio_write : std_logic := '0';
  signal fastio_read  : std_logic := '0';
  signal fastio_wdata : unsigned(7 downto 0) := (others => '0');
  signal fastio_rdata : unsigned(7 downto 0);
  signal sdcardio_cs  : std_logic := '0';
  signal f011_cs      : std_logic := '0';
  signal sb_cs        : std_logic := '0';

  signal hw_errata : unsigned(7 downto 0) := (others => 'Z');
  signal tmpSDA, tmpSCL, i2c1SDA, i2c1SCL, touchSDA, touchSCL : std_logic := 'H';

  signal sd_clk    : std_logic_vector(1 downto 0);
  signal sd_cmd_o  : std_logic_vector(1 downto 0);
  signal sd_cmd_oe : std_logic_vector(1 downto 0);
  signal sd_cmd_i  : std_logic_vector(1 downto 0) := "11";
  signal sd_dat_o  : std_logic_vector(7 downto 0);
  signal sd_dat_oe : std_logic_vector(7 downto 0);
  signal sd_dat_i  : std_logic_vector(7 downto 0) := (others => '1');

  signal card_clk : std_logic := '1';
  signal card_cmd : std_logic;
  signal card_dat : std_logic_vector(3 downto 0);
  signal host_cmd : std_logic;
  signal host_dat : std_logic_vector(3 downto 0);

  signal fails : natural := 0;

begin

  clock162 <= not clock162 after T162 / 2 when not done;
  cpuclock <= not cpuclock after TCPU / 2 when not done;

  dut : entity work.sdcardio_native
    generic map (target => mega65r6, cpu_frequency => 40500000,
                 sd_xilinx_io => false, sd_cache_lines => G_CACHE_LINES)
    port map (
      clock => cpuclock, pixelclk => cpuclock, reset => '1',
      sdcardio_cs => sdcardio_cs, f011_cs => f011_cs,
      hw_errata_level => hw_errata,
      hw_errata_disable_toggle => '0', hw_errata_enable_toggle => '0',
      hypervisor_mode => '1',
      fpga_temperature => (others => '0'), pwm_knob => (others => '0'),
      fastio_addr => fastio_addr, fastio_addr_fast => fastio_addr,
      fastio_write => fastio_write, fastio_read => fastio_read,
      fastio_wdata => fastio_wdata, fastio_rdata_sel => fastio_rdata,
      virtualise_f011_drive0 => '0', virtualise_f011_drive1 => '0',
      colourram_at_dc00 => '0', viciii_iomode => "11",
      sectorbuffercs => sb_cs, sectorbuffercs_fast => sb_cs,
      last_scan_code => (others => '0'),
      dipsw_hi => (others => '0'), dipsw => (others => '0'),
      j21in => (others => '0'), sw => (others => '0'), btn => (others => '0'),
      clock162 => clock162,
      sd_clk => sd_clk, sd_cmd_o => sd_cmd_o, sd_cmd_oe => sd_cmd_oe,
      sd_cmd_i => sd_cmd_i, sd_dat_o => sd_dat_o, sd_dat_oe => sd_dat_oe,
      sd_dat_i => sd_dat_i,
      f_index => '1', f_track0 => '1', f_writeprotect => '1', f_rdata => '1',
      f_diskchanged => '1',
      sd1541_request_toggle => '0', sd1541_enable => '0', sd1541_track => (others => '0'),
      aclMISO => '1', aclInt1 => '0', aclInt2 => '0',
      tmpSDA => tmpSDA, tmpSCL => tmpSCL, tmpInt => '0', tmpCT => '0',
      i2c1SDA => i2c1SDA, i2c1SCL => i2c1SCL,
      touchSDA => touchSDA, touchSCL => touchSCL,
      QspiDB_in => (others => '1'));

  -- the board: pull-ups, and a delay each way (slot 0)
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
    generic map (G_CRC_ERR_BLK => 21, G_START_SPI => G_SPI_CARD)
    port map (clk => card_clk, cmd => card_cmd, dat => card_dat);

  stim : process

    procedure poke(a : natural; v : natural) is
    begin
      wait until rising_edge(cpuclock);
      fastio_addr  <= to_unsigned(a, 20);
      fastio_wdata <= to_unsigned(v, 8);
      fastio_write <= '1';
      if a >= 16#D3680# and a <= 16#D36FF# then sdcardio_cs <= '1'; end if;
      if a >= 16#D3080# and a <= 16#D309F# then f011_cs <= '1'; end if;
      if a >= 16#FFE00# then sb_cs <= '1'; end if;
      wait until rising_edge(cpuclock);
      fastio_write <= '0';
      sdcardio_cs  <= '0';
      f011_cs      <= '0';
      sb_cs        <= '0';
    end procedure;

    procedure peek(a : natural; v : out unsigned(7 downto 0)) is
    begin
      wait until rising_edge(cpuclock);
      fastio_addr <= to_unsigned(a, 20);
      fastio_read <= '1';
      if a >= 16#D3680# and a <= 16#D36FF# then sdcardio_cs <= '1'; end if;
      if a >= 16#D3080# and a <= 16#D309F# then f011_cs <= '1'; end if;
      if a >= 16#FFE00# then sb_cs <= '1'; end if;
      wait until rising_edge(cpuclock);      -- (the buffer has one cycle latency)
      wait until falling_edge(cpuclock);
      v := fastio_rdata;
      wait until rising_edge(cpuclock);
      fastio_read <= '0';
      sdcardio_cs <= '0';
      f011_cs     <= '0';
      sb_cs       <= '0';
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

    -- wait until $D680 bits 1..0 (busy) are clear
    procedure wait_ready(tmo : time) is
      variable v : unsigned(7 downto 0);
      variable t : time;
    begin
      t := now;
      loop
        peek(16#D3680#, v);
        exit when v(1 downto 0) = "00";
        assert now - t < tmo report "timeout waiting for ready" severity failure;
        wait for 1 us;
      end loop;
    end procedure;

    procedure set_sector(n : natural) is
    begin
      poke(16#D3681#, n mod 256);
      poke(16#D3682#, (n / 256) mod 256);
      poke(16#D3683#, (n / 65536) mod 256);
      poke(16#D3684#, 0);
    end procedure;

    procedure check_buffer(n : natural; written : boolean; msg : string) is
      variable v, want : unsigned(7 downto 0);
      variable bad : natural := 0;
    begin
      for i in 0 to 511 loop
        peek(16#FFE00# + i, v);
        if written then want := wpattern(n, i); else want := pattern(n, i); end if;
        if v /= want then
          if bad < 3 then
            report "  sector " & integer'image(n) & " byte " & integer'image(i) & " = "
              & integer'image(to_integer(v)) & ", want " & integer'image(to_integer(want));
          end if;
          bad := bad + 1;
        end if;
      end loop;
      check(bad = 0, msg);
    end procedure;

    procedure fill_buffer(n : natural) is
    begin
      for i in 0 to 511 loop
        poke(16#FFE00# + i, to_integer(wpattern(n, i)));
      end loop;
    end procedure;

    variable v : unsigned(7 downto 0);
    variable t0 : time;
    variable h0, h1 : natural;

  begin
    wait for 1 us;
    if G_BOOT_TEST then
      -- Hyppo tries slot 1 first and only tests $D680 bits 1..0.  An empty
      -- slot must never look ready merely because initialisation has ended.
      poke(16#D3680#, 16#C1#);
      poke(16#D3680#, 16#00#);
      poke(16#D3680#, 16#01#);
      t0 := now;
      loop
        peek(16#D3686#, v);
        exit when v(7) = '1' and v(0) = '0';
        assert now - t0 < 40 ms report "empty slot did not finish initialising" severity failure;
        wait for 100 us;
      end loop;
      peek(16#D3687#, v);
      check(v = 1, "empty external slot reports ERR_NOCARD");
      peek(16#D3680#, v);
      check(v(1 downto 0) /= "00", "empty slot stays unavailable to Hyppo's busy-bit test");

      -- Fall back to the populated internal slot, polling immediately as
      -- firmware does.  A queued INIT must hide the previous idle status.
      poke(16#D3680#, 16#C0#);
      poke(16#D3680#, 16#00#);
      poke(16#D3680#, 16#01#);
      wait_ready(40 ms);
      peek(16#D3686#, v);
      check(v(0) = '1' and v(7) = '0', "Hyppo fallback waits for the internal card to be ready");
      set_sector(5);
      poke(16#D3680#, 16#02#);
      wait_ready(5 ms);
      check_buffer(5, false, "read after empty-slot fallback");

      -- Also reset an already working card: its old ready/idle status must
      -- not leak through the mailbox before INIT reaches the SD engine.
      poke(16#D3680#, 16#00#);
      poke(16#D3680#, 16#01#);
      peek(16#D3680#, v);
      check(v(1 downto 0) /= "00", "reset is busy immediately, before the mailbox completes");
      wait_ready(40 ms);
      peek(16#D3686#, v);
      check(v(0) = '1' and v(7) = '0', "reset completes with a usable card");
      set_sector(6);
      poke(16#D3680#, 16#02#);
      wait_ready(5 ms);
      check_buffer(6, false, "read after immediate reset polling");
      if fails = 0 then
        report "ALL BOOT TESTS PASSED";
      else
        report integer'image(fails) & " BOOT TESTS FAILED" severity error;
      end if;
      done <= true;
      wait;
    end if;
    -- reset and initialise
    poke(16#D3680#, 16#00#);
    poke(16#D3680#, 16#01#);
    wait for 1 us;
    wait_ready(40 ms);
    peek(16#D3686#, v);
    report "  $D686 = " & integer'image(to_integer(v));
    if G_SPI_CARD then
      check(v(0) = '1' and v(1) = '0' and v(2) = '0', "init: ready, SPI fallback");
    else
      check(v(0) = '1' and v(1) = '1' and v(2) = '1', "init: ready, native, high speed");
    end if;
    peek(16#D3687#, v);
    check(v = 0, "init: low-level error code 0");
    peek(16#D3680#, v);
    check(v(6) = '0', "init: no error");

    if G_ERROR_TEST then
      set_sector(5);
      poke(16#D3680#, 16#02#);
      wait_ready(5 ms);
      check_buffer(5, false, "read before terminal error");
      -- An error on an initialised card must stay busy for legacy software.
      poke(16#D3681#, 3);                 -- invalid P: minimum is 4
      poke(16#D3682#, 0);
      poke(16#D3680#, 16#21#);
      t0 := now;
      loop
        peek(16#D3687#, v);
        exit when v = 16#43#;
        assert now - t0 < 1 ms report "missing invalid-setting error" severity failure;
        wait for 1 us;
      end loop;
      wait for 2 us;
      peek(16#D3686#, v);
      check(v(7) = '1' and v(0) = '1', "terminal error with card still initialised");
      peek(16#D3680#, v);
      check(v(1) = '1' and v(6) = '1', "legacy BUSY stays set on terminal error");
      wait for 10 us;
      peek(16#D3680#, v);
      check(v(1) = '1', "error BUSY remains asserted after cleanup");
      t0 := now;
      poke(16#D3680#, 16#2A#);
      wait_ready(5 ms);
      check(now - t0 < 100 us, "clear/recover does not run card initialisation");
      peek(16#D3686#, v);
      if G_SPI_CARD then
        check(v = 9, "clear preserves SPI session without reset");
      else
        check(v = 15, "clear/recover preserves native high-speed session");
      end if;
      peek(16#D3680#, v);
      check(v(6) = '0', "clear/recover clears error BUSY without reset");
      set_sector(5);
      poke(16#D3680#, 16#02#);
      wait_ready(5 ms);
      check_buffer(5, false, "read after error recovery without reset");
      if G_CACHE_LINES > 0 then
        poke(16#D3680#, 16#28#);
        peek(16#D3683#, v);
        check(v = 2, "clear/recover invalidated the previous cached sector");
      end if;
      report "ALL ERROR TESTS PASSED";
      done <= true;
      wait;
    end if;

    -- single sector read
    set_sector(5);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    peek(16#D3680#, v);
    check(v(6) = '0', "read sector 5: no error");
    check_buffer(5, false, "read sector 5");

    -- multi-sector read 20, 21 (CRC retry inside), 22
    set_sector(20);
    t0 := now;
    poke(16#D3680#, 16#07#);
    wait_ready(5 ms);
    report "  first sector of the multi-sector read after " & time'image(now - t0);
    peek(16#D3686#, v);
    check(v(4) = '1' and v(5) = '1', "multi read: open and waiting");
    check_buffer(20, false, "multi read sector 20");
    poke(16#D3680#, 16#08#);
    wait_ready(5 ms);
    check_buffer(21, false, "multi read sector 21 (after a CRC retry)");
    poke(16#D3680#, 16#09#);
    wait_ready(5 ms);
    check_buffer(22, false, "multi read sector 22");
    peek(16#D3686#, v);
    check(v(5) = '0' and v(4) = '0', "multi read: closed");

    -- single sector write, read back
    fill_buffer(300);
    set_sector(300);
    poke(16#D3680#, 16#57#);
    poke(16#D3680#, 16#03#);
    wait_ready(5 ms);
    peek(16#D3680#, v);
    check(v(6) = '0', "write sector 300: no error");
    poke(16#FFE00#, 0);                    -- spoil the buffer
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    check_buffer(300, true, "write sector 300, read back");

    -- multi-sector write 400, 401, 402 ($04 / $05 / $06), read back
    for k in 0 to 2 loop
      fill_buffer(400 + k);
      if k = 0 then
        set_sector(400);
      end if;
      poke(16#D3680#, 16#57#);
      if k = 0 then
        poke(16#D3680#, 16#04#);
      elsif k = 1 then
        poke(16#D3680#, 16#05#);
      else
        poke(16#D3680#, 16#06#);
      end if;
      wait_ready(5 ms);
      peek(16#D3680#, v);
      check(v(6) = '0', "multi write sector " & integer'image(400 + k));
    end loop;
    for k in 0 to 2 loop
      set_sector(400 + k);
      poke(16#D3680#, 16#02#);
      wait_ready(5 ms);
      check_buffer(400 + k, true, "multi write sector " & integer'image(400 + k) & " read back");
    end loop;

    -- an open multi-sector read ended with $0A, then a plain read
    set_sector(30);
    poke(16#D3680#, 16#07#);
    wait_ready(5 ms);
    poke(16#D3680#, 16#0A#);
    wait_ready(5 ms);
    peek(16#D3686#, v);
    check(v(5) = '0' and v(4) = '0', "$0A ended the multi read");
    set_sector(31);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    check_buffer(31, false, "read after $0A");

    -- bus speed: probe and use 81 MHz (P = 4, D = 4)
    poke(16#D3681#, 4);
    poke(16#D3682#, 4);
    poke(16#D3680#, 16#20#);
    wait_ready(10 ms);
    peek(16#D309B#, v);
    report "  probe P=4 D=4: pass " & integer'image(to_integer(v));
    check(v = 8, "probe 81 MHz: 8 of 8");
    poke(16#D3681#, 4);
    poke(16#D3682#, 2);
    poke(16#D3680#, 16#20#);
    wait_ready(10 ms);
    peek(16#D309C#, v);
    check(v = 8, "probe 81 MHz with D=2: 8 failures");
    poke(16#D3681#, 4);
    poke(16#D3682#, 4);
    poke(16#D3680#, 16#21#);
    wait_ready(1 ms);
    set_sector(50);
    t0 := now;
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    report "  one sector at 81 MHz (command to ready): " & time'image(now - t0);
    check_buffer(50, false, "read at 81 MHz");
    poke(16#D3680#, 16#22#);
    wait_ready(1 ms);
    set_sector(51);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    check_buffer(51, false, "read back at normal speed");

    -- sector cache: sector 51 was just read, so a metadata read of it ($0B)
    -- is a hit; the counters come back in $D681-$D684 ($28)
    poke(16#D3680#, 16#28#);
    peek(16#D3681#, v);
    h0 := to_integer(v);
    peek(16#D3682#, v);
    h0 := h0 + 256 * to_integer(v);
    set_sector(51);
    t0 := now;
    poke(16#D3680#, 16#0B#);
    wait_ready(5 ms);
    report "  metadata read of a cached sector: " & time'image(now - t0);
    check_buffer(51, false, "metadata read ($0B) of sector 51");
    poke(16#D3680#, 16#28#);
    peek(16#D3681#, v);
    h1 := to_integer(v);
    peek(16#D3682#, v);
    h1 := h1 + 256 * to_integer(v);
    report "  cache hits " & integer'image(h0) & " -> " & integer'image(h1);
    check(h1 = h0 + 1, "  ... it was a cache hit ($28)");
    -- cache off: still right (from the card)
    poke(16#D3680#, 16#26#);
    wait_ready(1 ms);
    set_sector(51);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    check_buffer(51, false, "read with the cache off ($26)");
    poke(16#D3680#, 16#25#);
    wait_ready(1 ms);

    if fails = 0 then
      report "ALL TESTS PASSED";
    else
      report integer'image(fails) & " TESTS FAILED" severity error;
    end if;
    done <= true;
    wait;
  end process;

end architecture;
