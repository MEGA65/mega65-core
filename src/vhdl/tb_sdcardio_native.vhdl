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
    G_SPI_CARD    : boolean := false;
    G_DUAL_TEST : boolean := false;
    G_CARD0_PRESENT : boolean := true;
    G_CARD1_PRESENT : boolean := false;
    G_CARD1_SPI : boolean := false;
    G_INFO_TEST : boolean := false;
    G_INFO_BAD_CRC : boolean := false;
    G_BOUND_TEST : boolean := false;
    G_TAIL_TEST : boolean := false;
    G_REINIT_TEST : boolean := false;
    G_STREAM_TEST : boolean := false;
    G_F011_TEST : boolean := false;
    G_F011_ROUNDS : natural := 60
    );
end entity;

architecture tb of tb_sdcardio_native is

  constant T162  : time := 6172 ps;
  constant TCPU  : time := 4 * T162;
  constant BOARD : time := 1500 ps;
  function size_units return positive is
  begin
    if G_BOUND_TEST then return 1; else return 244140; end if;
  end function;
  function sdsc_csize return natural is
  begin if G_TAIL_TEST then return 2; else return 4095; end if; end function;
  function sdsc_mult return natural is
  begin if G_TAIL_TEST then return 0; else return 7; end if; end function;

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
  signal sd_cd_t   : std_logic_vector(1 downto 0) := "11";   -- card detect levels

  signal card_clk : std_logic := '1';
  signal card_cmd : std_logic;
  signal card_dat : std_logic_vector(3 downto 0);
  signal host_cmd : std_logic;
  signal host_dat : std_logic_vector(3 downto 0);
  signal card1_clk : std_logic := '1';
  signal card1_cmd, host1_cmd : std_logic;
  signal card1_dat, host1_dat : std_logic_vector(3 downto 0);
  type t_times is array (0 to 1) of time;
  signal first_clock : t_times := (others => 0 ns);

  signal fails : natural := 0;
  signal hyp : std_logic := '1';             -- the CPU in hypervisor mode

begin

  clock162 <= not clock162 after T162 / 2 when not done;
  cpuclock <= not cpuclock after TCPU / 2 when not done;

  dut : entity work.sdcardio_native
    -- Scale protocol millisecond counters by 100 for simulation; retain
    -- the real CPU/SD clocks, line timing and all command/data framing.
    generic map (target => mega65r6, cpu_frequency => 40500000,
                 sd_xilinx_io => false, sd_cache_lines => G_CACHE_LINES, sd_ms_cycles => 1620,
                 sd_auto_init => not (G_DUAL_TEST or G_INFO_TEST or G_BOUND_TEST))
    port map (
      clock => cpuclock, pixelclk => cpuclock, reset => '1',
      sdcardio_cs => sdcardio_cs, f011_cs => f011_cs,
      hw_errata_level => hw_errata,
      hw_errata_disable_toggle => '0', hw_errata_enable_toggle => '0',
      hypervisor_mode => hyp,
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
      sd_cd => sd_cd_t,
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

  present0 : if G_CARD0_PRESENT generate
    card : entity work.sdcard_native_model
      generic map (G_CRC_ERR_BLK => 21, G_START_SPI => G_SPI_CARD, G_LONG_READ_NAC => 40000,
                   G_INFO_BAD_CRC => G_INFO_BAD_CRC, G_SIZE_UNITS => size_units,
                   G_SDHC => not G_TAIL_TEST, G_SDSC_CSIZE => sdsc_csize, G_SDSC_MULT => sdsc_mult)
      port map (clk => card_clk, cmd => card_cmd, dat => card_dat);
  end generate;
  card1_clk <= transport sd_clk(1) after BOARD;
  card1_cmd <= 'H';
  card1_dat <= "HHHH";
  host1_cmd <= sd_cmd_o(1) when sd_cmd_oe(1) = '1' else 'Z';
  card1_cmd <= transport host1_cmd after BOARD;
  drv1 : for l in 0 to 3 generate
    host1_dat(l) <= sd_dat_o(l+4) when sd_dat_oe(l+4) = '1' else 'Z';
  end generate;
  card1_dat <= transport host1_dat after BOARD;
  sd_cmd_i(1) <= transport to_X01(card1_cmd) after BOARD;
  sd_dat_i(7 downto 4) <= transport to_X01(card1_dat) after BOARD;
  present1 : if G_CARD1_PRESENT generate
    card : entity work.sdcard_native_model
      generic map (G_START_SPI => G_CARD1_SPI, G_PATTERN_SEED => 89,
                   G_INFO_BAD_CRC => G_INFO_BAD_CRC, G_SIZE_UNITS => size_units)
      port map (clk => card1_clk, cmd => card1_cmd, dat => card1_dat);
  end generate;
  clock_start : for s in 0 to 1 generate
    process(sd_clk(s))
    begin
      if falling_edge(sd_clk(s)) and first_clock(s) = 0 ns then first_clock(s) <= now; end if;
    end process;
  end generate;

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

    procedure wait_range_error is
      variable v : unsigned(7 downto 0);
      variable t : time := now;
    begin
      loop
        peek(16#D3680#, v);
        exit when v(6) = '1' and v(0) = '0';
        assert now-t < 5 ms report "range error timeout" severity failure;
        wait for 1 us;
      end loop;
      check(v(1) = '1', "range error retains legacy BUSY");
      peek(16#D3687#, v); check(v = x"44", "range error code is visible");
    end procedure;

    procedure set_sector(n : natural) is
    begin
      poke(16#D3681#, n mod 256);
      poke(16#D3682#, (n / 256) mod 256);
      poke(16#D3683#, (n / 65536) mod 256);
      poke(16#D3684#, 0);
    end procedure;

    procedure check_buffer(n : natural; written : boolean; msg : string; slot : natural := 0) is
      variable v, want : unsigned(7 downto 0);
      variable bad : natural := 0;
    begin
      for i in 0 to 511 loop
        peek(16#FFE00# + i, v);
        if written then want := wpattern(n, i);
        else want := pattern(n, i) + to_unsigned(slot * 89, 8); end if;
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

    -- what the buffer half at $DE00 holds against sector n: that sector,
    -- the one before, or that sector rotated (k bytes)
    procedure f011_diag(n : natural) is
      variable b : unsigned(7 downto 0);
      type t_b is array (0 to 511) of unsigned(7 downto 0);
      variable d : t_b;
      variable ok_n, ok_p : boolean := true;
      variable rot : integer := -1;
      variable good : boolean;
    begin
      for i in 0 to 511 loop
        peek(16#FFE00# + i, b); d(i) := b;
        if b /= pattern(n, i) then ok_n := false; end if;
        if n = 0 or b /= pattern(n - 1, i) then ok_p := false; end if;
      end loop;
      for k in 1 to 511 loop
        good := true;
        for i in 0 to 511 loop
          if d((i + k) mod 512) /= pattern(n, i) then good := false; exit; end if;
        end loop;
        if good then rot := k; exit; end if;
      end loop;
      report "    holds sector " & integer'image(n) & ": " & boolean'image(ok_n)
        & ", the one before: " & boolean'image(ok_p) & ", it rotated by: " & integer'image(rot)
        & "; bytes 0/255/256/511 = " & integer'image(to_integer(d(0))) & " "
        & integer'image(to_integer(d(255))) & " " & integer'image(to_integer(d(256))) & " "
        & integer'image(to_integer(d(511)));
    end procedure;

    -- an F011 read of drive 0's image (as sdstress), checked against the
    -- card; then a raw read of the same card sector
    procedure f011_check(t, sd, sc : natural) is
      variable st : unsigned(7 downto 0);
      variable n : natural;
    begin
      n := 55854 + t * 20 + sd * 10 + sc - 1;
      if sd = 1 then poke(16#D3080#, 16#28#); else poke(16#D3080#, 16#20#); end if;
      poke(16#D3084#, t); poke(16#D3085#, sc); poke(16#D3086#, sd);
      -- (the image offset follows these registers two cycles later; a CPU's
      -- next STA comes later than that, this testbench's next write not)
      wait for 100 ns;
      poke(16#D3081#, 16#40#);
      for i in 0 to 5000 loop
        peek(16#D3082#, st);
        exit when st(7) = '0';
        wait for 1 us;
      end loop;
      check(st(7) = '0' and st(4) = '0', "f011 read t" & integer'image(t) & " s" & integer'image(sd)
            & " n" & integer'image(sc) & " done, found");
      -- (as a program: in hypervisor mode $DE00 is always the SD half)
      hyp <= '0';
      poke(16#D3689#, 16#00#);
      check_buffer(n, false, "f011 data t" & integer'image(t) & " s" & integer'image(sd)
                   & " n" & integer'image(sc) & " (card sector " & integer'image(n) & ")");
      if fails /= 0 then f011_diag(n); end if;
      poke(16#D3689#, 16#80#);
      hyp <= '1';
      set_sector(n); poke(16#D3680#, 2); wait_ready(5 ms);
      check_buffer(n, false, "raw read after f011");
    end procedure;

    variable v : unsigned(7 downto 0);
    variable t0 : time;
    variable lfsr : unsigned(31 downto 0) := x"1234ABCD";
    variable r, ft, fs, fn : natural;
    variable h0, h1 : natural;
    variable s0, s1 : unsigned(7 downto 0);
    variable ready0, ready1 : boolean;
    variable want : unsigned(7 downto 0);
    variable bad : natural;
    type t_regs is array (0 to 1) of std_logic_vector(127 downto 0);
    constant csd : t_regs := (x"400E00325B590003B9AB7F800A400067", x"400E00325B590003BA047F800A400059");
    constant cid : t_regs := (x"03534453453136308012345678017AEB", x"035344534531363080123456D1017A8D");
    constant scr : std_logic_vector(63 downto 0) := x"0235800100000000";

  begin
    wait for 1 us;
    if G_TAIL_TEST then
      -- A synthetic 12-sector SDSC volume ends halfway through a cache
      -- line. Read-ahead must stop there without poisoning a valid read.
      poke(16#D3680#, 0); poke(16#D3680#, 1); wait_ready(40 ms);
      set_sector(11); poke(16#D3680#, 2); wait_ready(5 ms);
      check_buffer(11, false, "last sector in a partial cache line");
      wait for 100 us; peek(16#D3680#, v); check(v(6) = '0', "no out-of-range tail prefetch");
      set_sector(8); poke(16#D3680#, 2); wait_ready(5 ms);
      check_buffer(8, false, "partial final cache-line fill");
      wait for 100 us; peek(16#D3680#, v); check(v(6) = '0', "partial fill closes cleanly at capacity");
      set_sector(12); poke(16#D3680#, 2); wait_range_error;
      report "ALL TAIL TESTS PASSED"; done <= true; wait;
    end if;
    if G_F011_TEST then
      -- sdstress mode 2: a D81 image on the card read through the F011,
      -- each sector against the card, with raw read-ahead runs, cache
      -- changes and open multi-sector reads in between; then a long run of
      -- sequential raw reads (sdstress's search after a mismatch).  On
      -- hardware an F011 read returned another sector, and the search then
      -- left the controller busy for good.
      poke(16#D3680#, 16#2B#); wait_ready(40 ms);
      poke(16#D368C#, 55854 mod 256); poke(16#D368D#, (55854 / 256) mod 256);
      poke(16#D368E#, 0); poke(16#D368F#, 0);
      poke(16#D368B#, 16#07#);
      for round in 0 to G_F011_ROUNDS - 1 loop
        lfsr := lfsr(30 downto 0) & (lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
        r := to_integer(lfsr(2 downto 0));
        ft := to_integer(lfsr(15 downto 8)) mod 80;
        fs := to_integer(lfsr(16 downto 16));
        fn := 1 + to_integer(lfsr(23 downto 20)) mod 10;
        if r < 3 then
          for sd in 0 to 1 loop
            for sc in 1 to 10 loop
              f011_check(ft, sd, sc);
            end loop;
          end loop;
        elsif r < 6 then
          f011_check(ft, fs, fn);
        elsif r = 6 then
          if lfsr(24) = '1' then
            for n in 0 to 19 loop
              set_sector(55854 + to_integer(lfsr(30 downto 20)) + n);
              poke(16#D3680#, 2); wait_ready(5 ms);
            end loop;
          elsif lfsr(25) = '1' then
            poke(16#D3680#, 16#27#); wait_ready(5 ms);
          else
            poke(16#D3680#, 16#25#); wait_ready(5 ms);
          end if;
        else
          set_sector(55854 + to_integer(lfsr(30 downto 20)));
          poke(16#D3680#, 16#07#); wait_ready(5 ms);
          poke(16#D3680#, 16#08#); wait_ready(5 ms);
          f011_check(ft, fs, fn);
        end if;
      end loop;
      for n in 55854 to 55854 + 299 loop
        set_sector(n); poke(16#D3680#, 2); wait_ready(5 ms);
        check_buffer(n, false, "search read " & integer'image(n));
      end loop;
      poke(16#D3680#, 16#25#); wait_ready(5 ms);
      assert fails = 0 report "F011 TESTS FAILED" severity failure;
      report "ALL F011 TESTS PASSED"; done <= true; wait;
    end if;
    if G_STREAM_TEST then
      -- A long run of sequential single-sector reads (sdstress's search of a
      -- D81 image): the read-ahead stream is extended line after line.  On
      -- hardware one such run stopped with the reader at the first sector
      -- of a line, the controller busy for good.
      poke(16#D3680#, 16#2B#); wait_ready(40 ms);
      for n in 55854 to 55854 + 299 loop
        set_sector(n); poke(16#D3680#, 2); wait_ready(5 ms);
        check_buffer(n, false, "sequential read " & integer'image(n));
      end loop;
      assert fails = 0 report "STREAM TESTS FAILED" severity failure;
      report "ALL STREAM TESTS PASSED"; done <= true; wait;
    end if;
    if G_REINIT_TEST then
      -- As after booting: both slots initialised, sequential reads (the
      -- cache's read-ahead stream left open and paused), the CPU elsewhere
      -- for a while; then a program selects the card and resets it.
      poke(16#D3680#, 16#2B#); wait_ready(40 ms);
      for n in 0 to 11 loop
        set_sector(n); poke(16#D3680#, 2); wait_ready(5 ms);
        check_buffer(n, false, "boot read");
      end loop;
      wait for 2 ms;
      for r in 0 to 2 loop
        poke(16#D3680#, 16#C0#);
        if r = 2 then poke(16#D3680#, 16#24#);
        else poke(16#D3680#, 0); poke(16#D3680#, 1); end if;
        wait_ready(40 ms);
        peek(16#D3680#, v); check(v(6) = '0', "re-init: no error");
        peek(16#D3686#, v); check(v(1 downto 0) = "11", "re-init: ready, native bus");
        poke(16#D36CE#, 16#80#);
        for i in 17 to 23 loop
          poke(16#D36CE#, i); peek(16#D36CF#, v);
          report "  init record byte " & integer'image(i) & " = " & integer'image(to_integer(v));
        end loop;
        poke(16#D36CE#, 17); peek(16#D36CF#, v);
        check(v = 0, "re-init: no failed init step");
        set_sector(40 + r); poke(16#D3680#, 2); wait_ready(5 ms);
        check_buffer(40 + r, false, "read after re-init");
        for n in 41 + r to 50 + r loop
          set_sector(n); poke(16#D3680#, 2); wait_ready(5 ms);
        end loop;
        wait for 1 ms;
      end loop;
      assert fails = 0 report "REINIT TESTS FAILED" severity failure;
      report "ALL REINIT TESTS PASSED"; done <= true; wait;
    end if;
    if G_BOUND_TEST then
      poke(16#D3680#, 16#2B#); wait_ready(40 ms);
      peek(16#D36D9#, v); check(v = x"A3", "capacity protection defaults on before ready");
      for i in 0 to 3 loop
        poke(16#D36DC#, i); peek(16#D36DD#, v);
        if i = 0 then check(v = x"FF", "last LBA byte 0");
        elsif i = 1 then check(v = x"03", "last LBA byte 1");
        else check(v = 0, "last LBA high bytes"); end if;
      end loop;
      set_sector(1023); poke(16#D3680#, 2); wait_ready(5 ms);
      check_buffer(1023, false, "normal read at reported last sector");
      set_sector(1024); poke(16#D3680#, 2); wait_range_error;
      if G_CARD1_PRESENT then
        poke(16#D3680#, 16#C1#); wait_ready(40 ms);
        set_sector(1024); poke(16#D3680#, 2); wait_ready(5 ms);
        check_buffer(1024, false, "other card can read while first has a cached range error", 1);
        poke(16#D3680#, 16#C0#);
        peek(16#D3687#, v); check(v = x"44", "cached range error code survives other-card operation");
      end if;
      fill_buffer(1024); poke(16#D3680#, 16#57#); poke(16#D3680#, 3); wait_range_error;
      poke(16#D3680#, 16#31#);
      peek(16#D36D9#, v); check(v = x"A2", "override disables selected card limit");
      poke(16#D3680#, 2); wait_ready(5 ms);
      check_buffer(1024, false, "override read also proves rejected write changed nothing");
      -- This data is now cached beyond capacity. Re-enabling the limit
      -- must reject it before a cache hit can publish any stale buffer.
      poke(16#D3680#, 16#30#); poke(16#D3680#, 2); wait_range_error;
      poke(16#D3680#, 16#31#);
      poke(16#D3680#, 16#00#); poke(16#D3680#, 16#01#); wait_ready(40 ms);
      peek(16#D36D9#, v); check(v = x"A2", "selected-card override survives reset");
      set_sector(1024); poke(16#D3680#, 2); wait_ready(5 ms);
      check_buffer(1024, false, "ordinary read remains unbounded after reset");
      if G_CARD1_PRESENT then
        poke(16#D3680#, 16#C1#); wait_ready(40 ms);
        peek(16#D36D9#, v); check(v = x"A3", "other card keeps its default limit");
        set_sector(1024); poke(16#D3680#, 2); wait_ready(5 ms);
        check_buffer(1024, false, "same LBA is valid on the larger other card", 1);
      end if;
      assert fails = 0 report "BOUND TESTS FAILED" severity failure;
      report "ALL BOUND TESTS PASSED"; done <= true; wait;
    end if;
    if G_INFO_TEST then
      peek(16#D36D8#, v); check(v = x"49", "card info capability signature");
      poke(16#D3680#, 16#2B#);
      for s in 0 to 1 loop
        if (s = 0 and G_CARD0_PRESENT) or (s = 1 and G_CARD1_PRESENT) then
          poke(16#D3680#, 16#C0# + s); wait_ready(40 ms);
          set_sector(7); poke(16#D3680#, 2); wait_ready(5 ms);
          check_buffer(7, false, "warm normal sector before info", s);
          poke(16#D3680#, 16#28#); peek(16#D3683#, v); h0 := to_integer(v);
          for kind in 0 to 3 loop
            set_sector(7); fill_buffer(700+kind);
            poke(16#D3680#, 16#2C# + kind);
            t0 := now;
            loop
              peek(16#D3680#, v);
              exit when v(0) = '0' and (v(1) = '0' or v(6) = '1');
              assert now-t0 < 5 ms report "info command timeout" severity failure;
              wait for 1 us;
            end loop;
            if G_INFO_BAD_CRC then
              check(v(6) = '1' and v(1) = '1', "bad info CRC retains legacy error/BUSY");
              peek(16#D3687#, v); check(v = x"21", "info CRC error code visible");
              poke(16#D3680#, 16#2A#); wait_ready(5 ms);
            else
              check(v(6) = '0', "info request succeeds");
              bad := 0;
              for i in 0 to 511 loop
                peek(16#FFE00#+i, v); want := x"00";
                if kind = 0 and i < 16 then want := unsigned(csd(s)(127-i*8 downto 120-i*8));
                elsif kind = 1 and i < 16 then want := unsigned(cid(s)(127-i*8 downto 120-i*8));
                elsif kind = 2 and i < 8 then want := unsigned(scr(63-i*8 downto 56-i*8));
                elsif kind = 3 and i < 64 then
                  if i = 0 then want := x"80"; elsif i = 8 then want := x"04";
                  else want := to_unsigned((i*13+7+s*89) mod 256, 8); end if;
                end if;
                if v /= want then
                  if bad < 3 then report "info mismatch slot " & integer'image(s) & " kind "
                    & integer'image(kind) & " offset " & integer'image(i); end if;
                  bad := bad + 1;
                end if;
              end loop;
              check(bad = 0, "selected card info bytes and zero padding");
            end if;
            peek(16#D3681#, v); check(v = 7, "info preserves sector address");
            poke(16#D3680#, 2); wait_ready(5 ms);
            check_buffer(7, false, "normal read after info", s);
          end loop;
          if not G_INFO_BAD_CRC and G_CACHE_LINES /= 0 then
            poke(16#D3680#, 16#28#); peek(16#D3683#, v);
            check(to_integer(v) = h0, "info bypasses cache and preserves sector cache lines");
          end if;
        end if;
      end loop;
      assert fails = 0 report "INFO TESTS FAILED" severity failure;
      report "ALL INFO TESTS PASSED"; done <= true; wait;
    end if;
    if G_DUAL_TEST then
      -- Disable automatic power-up init in this mode so only the explicit
      -- extension can start either card. This catches an ignored $2B.
      peek(16#D36D7#, v); check(v = x"D2", "parallel extension has an exact capability signature");
      poke(16#D3680#, 16#C1#);
      poke(16#D3680#, 16#2B#);
      t0 := now;
      ready0 := false; ready1 := false;
      loop
        poke(16#D3680#, 16#C0#); peek(16#D3686#, s0);
        poke(16#D3680#, 16#C1#); peek(16#D3686#, s1);
        ready0 := s0(0) = '1' or s0(7) = '1';
        ready1 := s1(0) = '1' or s1(7) = '1';
        exit when ready0 and ready1;
        assert now - t0 < 40 ms report "parallel init timeout" severity failure;
        wait for 25 us;
      end loop;
      check(first_clock(0) /= 0 ns and first_clock(1) /= 0 ns
        and abs(first_clock(0) - first_clock(1)) <= TCPU,
        "both sockets start reset clocks together, including absent cards");
      check((s0(0) = '1') = G_CARD0_PRESENT, "internal ready state belongs to internal card");
      check((s1(0) = '1') = G_CARD1_PRESENT, "external ready state belongs to external card");
      check((s0(7) = '1') /= G_CARD0_PRESENT, "internal error state is independent");
      check((s1(7) = '1') /= G_CARD1_PRESENT, "external error state is independent");
      if G_CARD0_PRESENT then
        check((s0(1) = '0') = G_SPI_CARD, "internal retains its own native/SPI mode");
      end if;
      if G_CARD1_PRESENT then
        check((s1(1) = '0') = G_CARD1_SPI, "external retains its own native/SPI mode");
      end if;
      report "parallel probe elapsed " & time'image(now - t0);
      for s in 0 to 1 loop
        if (s = 0 and G_CARD0_PRESENT) or (s = 1 and G_CARD1_PRESENT) then
          poke(16#D3680#, 16#C0# + s);
          wait_ready(1 ms);
          set_sector(96); poke(16#D3680#, 2); wait_ready(5 ms);
          check_buffer(96, false, "same LBA returns selected card data", s);
        else
          poke(16#D3680#, 16#C0# + s);
          peek(16#D3680#, v);
          check(v(1) = '1' and v(6) = '1', "absent card retains legacy error/BUSY");
        end if;
      end loop;
      if G_CARD0_PRESENT and G_CARD1_PRESENT then
        -- Both lines survive selection changes. First visits were misses.
        poke(16#D3680#, 16#28#); peek(16#D3681#, v); h0 := to_integer(v);
        for s in 0 to 1 loop
          poke(16#D3680#, 16#C0# + s);
          set_sector(96); poke(16#D3680#, 2); wait_ready(5 ms);
          check_buffer(96, false, "slot-tagged cached hit", s);
        end loop;
        poke(16#D3680#, 16#28#); peek(16#D3681#, v);
        if G_CACHE_LINES /= 0 then check(to_integer(v) = h0 + 2, "both card lines remain cached"); end if;

        -- Card selection changes the status view, never the running read.
        poke(16#D3680#, 16#C0#);
        set_sector(300); poke(16#D3680#, 2);
        peek(16#D3680#, v); check(v(1 downto 0) /= "00", "internal read is busy");
        poke(16#D3680#, 16#C1#); peek(16#D3680#, v);
        check(v(1 downto 0) = "00" and v(6) = '0', "selecting idle external card exposes its own status");
        poke(16#D3680#, 16#C0#); wait_ready(5 ms);
        check_buffer(300, false, "selection during a read preserves transfer owner");

        -- Legacy selected-card reset does not reset/invalidate the other.
        poke(16#D3680#, 16#00#);
        peek(16#D3680#, v); check(v(2) = '1', "selected card asserts legacy RESET");
        poke(16#D3680#, 16#C1#); peek(16#D3680#, v);
        check(v(2 downto 0) = "000", "other card remains ready while internal reset is held");
        poke(16#D3680#, 16#C0#); poke(16#D3680#, 16#01#);
        peek(16#D3680#, v); check(v(1) = '1', "selected reset queues BUSY immediately");
        wait_ready(40 ms);
        poke(16#D3680#, 16#28#); peek(16#D3681#, v); h0 := to_integer(v);
        poke(16#D3680#, 16#C1#);
        set_sector(96); poke(16#D3680#, 2); wait_ready(5 ms);
        check_buffer(96, false, "external cache survives internal reset", 1);
        poke(16#D3680#, 16#28#); peek(16#D3681#, v);
        if G_CACHE_LINES /= 0 then check(to_integer(v) = h0 + 1, "single-card reset preserves other card's cache hit"); end if;

        -- Upper-controller errors are sticky per card as well as low-level
        -- errors. Resetting/mapping the other card must not erase them.
        poke(16#D3680#, 16#FF#); peek(16#D3680#, v);
        check(v(6) = '1' and v(1) = '1', "external upper error retains legacy BUSY");
        poke(16#D3680#, 16#C0#); peek(16#D3680#, v);
        check(v(6) = '0', "external upper error does not leak into internal status");
        poke(16#D3680#, 16#00#);
        poke(16#D3680#, 16#C1#); peek(16#D3680#, v);
        check(v(6) = '1', "resetting internal card preserves external upper error");
        poke(16#D3680#, 16#81#); peek(16#D3680#, v);
        check(v(6) = '0' and v(1 downto 0) = "00", "legacy map command clears selected upper error");
        poke(16#D3680#, 16#C0#); peek(16#D3680#, v);
        check(v(2) = '1' and v(6) = '0', "selection restores internal RESET without external error");
      end if;
      assert fails = 0 report "DUAL TESTS FAILED" severity failure;
      report "ALL DUAL TESTS PASSED";
      done <= true;
      wait;
    end if;
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

    peek(16#D36CC#, v);
    check(v = 16#53#, "retry diagnostics signature");
    peek(16#D36CD#, v);
    check(v = 1, "retry diagnostics version");
    poke(16#D36CE#, 16#80#);
    for i in 0 to 13 loop
      poke(16#D36CE#, i);
      peek(16#D36CF#, v);
      check(v = 0, "initial diagnostic events exclude initialisation");
    end loop;
    poke(16#D36CE#, 14);
    peek(16#D36CF#, v);
    if G_SPI_CARD then
      check(v = 13, "diagnostic SPI clock divisor");
    else
      check(v = 8, "diagnostic high-speed clock divisor");
    end if;
    -- bytes 17-23: why the native bus was given up.  A card already in SPI
    -- mode does not answer CMD55 on the native bus (step 4): fell back to
    -- SPI, no response.  A native card: nothing.
    poke(16#D36CE#, 17);
    peek(16#D36CF#, v);
    if G_SPI_CARD then
      check(v = 4, "init diagnostic: the step that failed (CMD55)");
    else
      check(v = 0, "init diagnostic: no step failed");
    end if;
    poke(16#D36CE#, 18);
    peek(16#D36CF#, v);
    if G_SPI_CARD then
      check(v = 16#43#, "init diagnostic: native tried twice, fell back to SPI, no response");
    else
      check(v = 0, "init diagnostic: no flags");
    end if;
    poke(16#D36CE#, 19);
    peek(16#D36CF#, v);
    check(v = 0, "init diagnostic: no test read error");

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

    -- Native high-speed only: SPI fallback correctly rejects an 81 MHz
    -- probe with ERR_NOHS, retaining legacy error/BUSY until recovery.
    if not G_SPI_CARD then
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
    end if;
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
    if G_CACHE_LINES /= 0 then check(h1 = h0 + 1, "  ... it was a cache hit ($28)"); end if;
    -- cache off: still right (from the card)
    poke(16#D3680#, 16#26#);
    wait_ready(1 ms);
    set_sector(51);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    check_buffer(51, false, "read with the cache off ($26)");
    poke(16#D3680#, 16#25#);
    wait_ready(1 ms);

    -- card detect: diagnostic byte 16 shows the levels; a change of slot 0's
    -- card detect is sticky and makes its cached sectors misses
    poke(16#D36CE#, 16#10#);
    peek(16#D36CF#, v);
    report "  card detect byte: " & integer'image(to_integer(v));
    check(v = x"05", "card detect: both cards present, no changes");
    set_sector(60);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    set_sector(60);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    poke(16#D3680#, 16#28#);
    peek(16#D3683#, v);
    h0 := to_integer(v);                 -- misses (low byte)
    sd_cd_t(0) <= '0';
    wait for 2500 us;
    poke(16#D36CE#, 16#10#);
    peek(16#D36CF#, v);
    check(v = x"14", "card detect: slot 0 changed (sticky)");
    set_sector(60);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    check_buffer(60, false, "card detect: sector 60 read again");
    poke(16#D3680#, 16#28#);
    peek(16#D3683#, v);
    if G_CACHE_LINES /= 0 then
      check(to_integer(v) = h0 + 1, "  ... a miss: the card change emptied its cache");
    end if;
    poke(16#D36CE#, 16#50#);             -- clear the changes
    peek(16#D36CF#, v);
    check(v = x"04", "card detect: change cleared");
    sd_cd_t(0) <= '1';

    -- the FAT32 engine ($70): an MBR with one FAT32 partition at LBA 8 and
    -- its boot sector, written to the card; rescan and the partition list
    -- then go through the engine, the cache and the controller
    for i in 0 to 511 loop
      poke(16#FFE00# + i, 0);
    end loop;
    poke(16#FFE00# + 446 + 4, 16#0C#);           -- FAT32 (LBA)
    poke(16#FFE00# + 446 + 8, 8);                -- at LBA 8
    poke(16#FFE00# + 446 + 14, 1);               -- 65536 sectors
    poke(16#FFE00# + 510, 16#55#);
    poke(16#FFE00# + 511, 16#AA#);
    set_sector(0);
    poke(16#D3680#, 16#4D#);
    poke(16#D3680#, 16#03#);
    wait_ready(5 ms);
    for i in 0 to 511 loop
      poke(16#FFE00# + i, 0);
    end loop;
    poke(16#FFE00# + 12, 2);                     -- 512 bytes per sector
    poke(16#FFE00# + 13, 1);                     -- 1 sector per cluster
    poke(16#FFE00# + 14, 2);                     -- 2 reserved sectors
    poke(16#FFE00# + 16, 2);                     -- 2 FATs
    poke(16#FFE00# + 34, 1);                     -- 65536 sectors
    poke(16#FFE00# + 36, 4);                     -- 4 sectors per FAT
    poke(16#FFE00# + 44, 2);                     -- root directory: cluster 2
    poke(16#FFE00# + 510, 16#55#);
    poke(16#FFE00# + 511, 16#AA#);
    set_sector(8);
    poke(16#D3680#, 16#57#);
    poke(16#D3680#, 16#03#);
    wait_ready(5 ms);
    -- rescan
    poke(16#FFE00#, character'pos('F'));
    poke(16#FFE01#, character'pos('3'));
    poke(16#FFE02#, 1);
    poke(16#FFE03#, 1);
    poke(16#D3680#, 16#70#);
    wait_ready(20 ms);
    peek(16#D3680#, v);
    check(v(6) = '0', "FAT32 engine: rescan, no error");
    peek(16#FFE03#, v);
    check(v = 0, "FAT32 engine: rescan status 0");
    peek(16#FFE06#, v);
    check(v = 1, "FAT32 engine: one drive found (" & integer'image(to_integer(v)) & ")");
    -- the partition list
    poke(16#FFE00#, character'pos('F'));
    poke(16#FFE01#, character'pos('3'));
    poke(16#FFE02#, 1);
    poke(16#FFE03#, 2);
    poke(16#D3680#, 16#70#);
    wait_ready(5 ms);
    peek(16#FFE10#, v);
    check(v = 1, "FAT32 engine: partition list: drive 1");
    peek(16#FFE11#, v);
    check(v = 0, "FAT32 engine: partition list: slot 0");
    peek(16#FFE12#, v);
    check(v = 16#0C#, "FAT32 engine: partition list: type $0C");
    peek(16#FFE14#, v);
    check(v = 8, "FAT32 engine: partition list: LBA 8");
    peek(16#FFE1C#, v);
    h0 := to_integer(v);
    peek(16#FFE1D#, v);
    h0 := h0 + 256 * to_integer(v);
    check(h0 = 65528, "FAT32 engine: partition list: 65528 clusters ("
          & integer'image(h0) & ")");
    -- a bad request: the error in $D680 and $D687
    poke(16#FFE00#, 0);
    poke(16#D3680#, 16#70#);
    t0 := now;
    loop                                     -- (an error keeps the legacy BUSY bit)
      peek(16#D3680#, v);
      exit when v(0) = '0';
      assert now - t0 < 5 ms report "FAT32 engine: no end" severity failure;
      wait for 1 us;
    end loop;
    check(v(6) = '1', "FAT32 engine: a bad request is an error");
    peek(16#D3687#, v);
    check(v = 10, "FAT32 engine: $D687 = 10 (bad request)");
    -- an ordinary read afterwards
    set_sector(51);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    check_buffer(51, false, "read after the FAT32 engine");

    -- writing through the engine: a FAT (both copies) and an empty root
    -- directory first; then create /T.TXT, write 10 bytes, close, read back
    for k in 0 to 2 loop
      for i in 0 to 511 loop
        poke(16#FFE00# + i, 0);
      end loop;
      if k < 2 then
        for i in 0 to 11 loop                    -- clusters 0, 1, 2 (the root): used
          poke(16#FFE00# + i, 16#FF#);
        end loop;
        poke(16#FFE03#, 16#0F#);
        poke(16#FFE07#, 16#0F#);
        poke(16#FFE0B#, 16#0F#);
        poke(16#FFE00#, 16#F8#);
        set_sector(10 + 4 * k);
      else
        set_sector(18);
      end if;
      poke(16#D3680#, 16#57#);
      poke(16#D3680#, 16#03#);
      wait_ready(5 ms);
    end loop;
    poke(16#FFE00#, character'pos('F'));
    poke(16#FFE01#, character'pos('3'));
    poke(16#FFE02#, 1);
    poke(16#FFE03#, 16#21#);                     -- create
    poke(16#FFE05#, 0);
    poke(16#FFE06#, 0);
    poke(16#FFE10#, character'pos('/'));
    poke(16#FFE11#, character'pos('T'));
    poke(16#FFE12#, character'pos('.'));
    poke(16#FFE13#, character'pos('T'));
    poke(16#FFE14#, character'pos('X'));
    poke(16#FFE15#, character'pos('T'));
    poke(16#FFE16#, 0);
    poke(16#D3680#, 16#70#);
    wait_ready(20 ms);
    peek(16#FFE03#, v);
    check(v = 0, "FAT32 engine: create /T.TXT (" & integer'image(to_integer(v)) & ")");
    peek(16#FFE04#, v);
    h1 := to_integer(v);                         -- the descriptor
    for i in 0 to 9 loop
      poke(16#FFE00# + i, 48 + i);
    end loop;
    poke(16#D3681#, 10);
    poke(16#D3682#, 0);
    poke(16#D3683#, 0);
    poke(16#D3684#, h1);
    poke(16#D3680#, 16#72#);
    wait_ready(20 ms);
    peek(16#D3680#, v);
    check(v(6) = '0', "FAT32 engine: write 10 bytes");
    poke(16#FFE00#, character'pos('F'));
    poke(16#FFE01#, character'pos('3'));
    poke(16#FFE02#, 1);
    poke(16#FFE03#, 16#22#);                     -- close
    poke(16#FFE04#, h1);
    poke(16#D3680#, 16#70#);
    wait_ready(20 ms);
    poke(16#FFE03#, 16#20#);                     -- open (the path is still there)
    poke(16#FFE05#, 0);
    poke(16#FFE00#, character'pos('F'));
    poke(16#FFE01#, character'pos('3'));
    poke(16#FFE02#, 1);
    poke(16#D3680#, 16#70#);
    wait_ready(20 ms);
    peek(16#FFE03#, v);
    check(v = 0, "FAT32 engine: open /T.TXT");
    peek(16#FFE04#, v);
    h1 := to_integer(v);
    poke(16#D3681#, 0);
    poke(16#D3682#, 2);                          -- 512
    poke(16#D3683#, 0);
    poke(16#D3684#, h1);
    poke(16#D3680#, 16#71#);
    wait_ready(20 ms);
    peek(16#D3681#, v);
    check(v = 10, "FAT32 engine: read: 10 bytes (" & integer'image(to_integer(v)) & ")");
    h0 := 0;
    for i in 0 to 9 loop
      peek(16#FFE00# + i, v);
      if v /= 48 + i then h0 := h0 + 1; end if;
    end loop;
    check(h0 = 0, "FAT32 engine: read back what was written");
    -- on the card: the root directory's entry, the FAT's chain
    set_sector(18);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    peek(16#FFE00#, v);
    check(v = character'pos('T'), "FAT32 engine: the entry on the card");
    peek(16#FFE1C#, v);
    check(v = 10, "FAT32 engine: its size on the card");
    set_sector(14);                              -- the second FAT
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    peek(16#FFE0F#, v);
    check(v = 16#0F#, "FAT32 engine: cluster 3 ends its chain, in the second FAT too");

    -- $76/$77: the next 512 bytes of descriptor 0/1 (here the hypervisor's)
    poke(16#FFE00#, character'pos('F'));
    poke(16#FFE01#, character'pos('3'));
    poke(16#FFE02#, 1);
    poke(16#FFE03#, 16#23#);                     -- seek to 0
    poke(16#FFE04#, h1);
    poke(16#FFE05#, 0);
    for i in 6 to 9 loop
      poke(16#FFE00# + i, 0);
    end loop;
    poke(16#D3680#, 16#70#);
    wait_ready(20 ms);
    for i in 0 to 9 loop
      poke(16#FFE00# + i, 0);
    end loop;
    poke(16#D3680#, 16#76# + h1);
    wait_ready(20 ms);
    peek(16#D3681#, v);
    check(v = 10, "FAT32 engine: quick read: 10 bytes (" & integer'image(to_integer(v)) & ")");
    h0 := 0;
    for i in 0 to 9 loop
      peek(16#FFE00# + i, v);
      if v /= 48 + i then h0 := h0 + 1; end if;
    end loop;
    check(h0 = 0, "FAT32 engine: quick read: the bytes");

    -- the read-only policy for programs gates their raw sector writes too
    poke(16#FFE00#, character'pos('F'));
    poke(16#FFE01#, character'pos('3'));
    poke(16#FFE02#, 1);
    poke(16#FFE03#, 4);                          -- policy: read-only
    poke(16#FFE06#, 1);
    poke(16#D3680#, 16#70#);
    wait_ready(20 ms);
    set_sector(40);
    hyp <= '0';
    poke(16#D3680#, 16#57#);
    poke(16#D3680#, 16#03#);
    t0 := now;
    loop
      peek(16#D3680#, v);
      exit when v(0) = '0';
      assert now - t0 < 5 ms report "read-only policy: no end" severity failure;
      wait for 1 us;
    end loop;
    check(v(6) = '1', "read-only policy: a program's sector write is refused");
    peek(16#D3687#, v);
    check(v = 16#0F#, "read-only policy: $D687 = $0F");
    hyp <= '1';
    fill_buffer(40);
    poke(16#D3680#, 16#57#);
    poke(16#D3680#, 16#03#);
    wait_ready(5 ms);
    peek(16#D3680#, v);
    check(v(6) = '0', "read-only policy: the hypervisor's write goes ahead");
    poke(16#FFE00#, character'pos('F'));
    poke(16#FFE01#, character'pos('3'));
    poke(16#FFE02#, 1);
    poke(16#FFE03#, 4);                          -- policy: read-write
    poke(16#FFE06#, 0);
    poke(16#D3680#, 16#70#);
    wait_ready(20 ms);
    set_sector(41);
    hyp <= '0';
    poke(16#D3680#, 16#57#);
    poke(16#D3680#, 16#03#);
    wait_ready(5 ms);
    peek(16#D3680#, v);
    check(v(6) = '0', "read-only policy off: a program's write goes ahead");
    hyp <= '1';
    set_sector(40);
    poke(16#D3680#, 16#02#);
    wait_ready(5 ms);
    check_buffer(40, true, "read-only policy: the hypervisor's sector written");

    -- a card change (card detect) reaches the engine: its next command
    -- thaws first.  The volume's serial number is changed on the card, so
    -- the descriptor is stale after the change, and only then.  (First the
    -- earlier card-detect test's last change, still pending after its
    -- debounce: the k = 0 round below consumes it before the serial
    -- number changes.)
    wait for 2500 us;
    for k in 0 to 2 loop
      if k = 1 then
        set_sector(8);
        poke(16#D3680#, 16#02#);
        wait_ready(5 ms);
        poke(16#FFE00# + 67, 16#5A#);
        set_sector(8);
        poke(16#D3680#, 16#57#);
        poke(16#D3680#, 16#03#);
        wait_ready(5 ms);
      elsif k = 2 then
        sd_cd_t(0) <= '0';
        wait for 2500 us;
      end if;
      poke(16#FFE00#, character'pos('F'));
      poke(16#FFE01#, character'pos('3'));
      poke(16#FFE02#, 1);
      poke(16#FFE03#, 16#23#);                   -- seek to 0
      poke(16#FFE04#, h1);
      poke(16#FFE05#, 0);
      for i in 6 to 9 loop
        poke(16#FFE00# + i, 0);
      end loop;
      poke(16#D3680#, 16#70#);
      t0 := now;
      loop
        peek(16#D3680#, v);
        exit when v(0) = '0';
        assert now - t0 < 20 ms report "card change: no end" severity failure;
        wait for 1 us;
      end loop;
      peek(16#D3687#, v);
      if k < 2 then
        check(v = 0, "card change: before it, the descriptor works ("
              & integer'image(to_integer(v)) & ")");
      else
        check(v = 16, "card change: then the descriptor is stale ("
              & integer'image(to_integer(v)) & ")");
      end if;
    end loop;
    sd_cd_t(0) <= '1';
    poke(16#FFE00#, character'pos('F'));
    poke(16#FFE01#, character'pos('3'));
    poke(16#FFE02#, 1);
    poke(16#FFE03#, 16#22#);                     -- close it
    poke(16#FFE04#, h1);
    poke(16#D3680#, 16#70#);
    wait_ready(20 ms);
    peek(16#D3687#, v);
    check(v = 0, "card change: the stale descriptor closes");

    -- each disk image is on the card selected when its start was set
    poke(16#D3680#, 16#C1#);
    poke(16#D368C#, 0);
    poke(16#D3680#, 16#C0#);
    poke(16#D3690#, 0);
    peek(16#D368A#, v);
    check(v(5 downto 4) = "01", "disk images: drive 0 on the external card, drive 1 internal");
    poke(16#D368F#, 0);
    peek(16#D368A#, v);
    check(v(5 downto 4) = "00", "disk images: drive 0 moved to the internal card");

    if fails = 0 then
      report "ALL TESTS PASSED";
    else
      report integer'image(fails) & " TESTS FAILED" severity error;
    end if;
    done <= true;
    wait;
  end process;

end architecture;
