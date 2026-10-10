-- Testbench for the SDRAM read capture training in sdram_controller.
--
-- As on the board, clock162r comes from a separate MMCM whose phase relative
-- to clock162 is arbitrary (generic phi0_ps); the bench models its dynamic
-- fine phase shift (PSEN -> PSDONE after 12 PSCLK cycles, T/280 per step).
-- The SDRAM model is clocked dm_ps after clock162 (clock out + tAC + trace),
-- and read data is invalid ('X') for xw_ps after each change, so only part of
-- each cycle can be sampled.  After training, LUMP and CPU reads must be
-- clean, and the training registers ($C000008+) must report a window.
--
--   ghdl -r --std=93c -fexplicit -fsynopsys tb_sdram_train -gphi0_ps=1234

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;
use work.cputypes.all;
use work.lumptypes.all;

entity tb_sdram_train is
  generic (phi0_ps : integer := 0;      -- initial clock162r phase
           dm_ps   : integer := 4000;   -- SDRAM data delay after clock162
           xw_ps   : integer := 2500;   -- invalid data time per word
           identical : integer := 0;    -- $D7FE bit 5 (flips the cycle)
           no_ps   : integer := 0;      -- 1: no phase shifter connected
           boot    : integer := 0;
           force_h1c0 : integer := 0;
           lock_us : integer := 0);     -- capture clock MMCM locks this late  -- 1: after training, move to a
                                        -- phase where the falling-edge
                                        -- path reads at cycle 0, and force
                                        -- that ($C000014), then test     -- 1: no init write: training must
                                        -- start by itself after power-on
end entity;

architecture test of tb_sdram_train is

  constant T : time := 6 ns;
  constant PS_STEP : time := T / 280;
  signal clk_m : std_logic := '0';
  signal ps_en, ps_incdec, ps_done : std_logic := '0';
  signal ps_locked : std_logic := '0';
  signal ps_offset : integer := 0;

  signal clock162   : std_logic := '0';
  signal clock162r  : std_logic := '0';
  signal pixelclock : std_logic := '0';
  signal identical_clocks : std_logic;

  signal slow_read    : std_logic := '0';
  signal slow_write   : std_logic := '0';
  signal slow_address : unsigned(26 downto 0) := (others => '0');
  signal slow_wdata   : unsigned(7 downto 0) := x"00";
  signal slow_rdata, slow_rdata_hi : unsigned(7 downto 0);
  signal data_ready_toggle : std_logic;
  signal busy : std_logic;
  signal current_cache_line : cache_row_t;
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic;

  signal sdram_a : unsigned(12 downto 0);
  signal sdram_ba : unsigned(1 downto 0);
  signal sdram_dq : unsigned(15 downto 0);
  signal sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n : std_logic;
  signal sdram_dqml, sdram_dqmh : std_logic;
  signal init_sequence_done : std_logic;

  -- LUMP
  signal lump_cmd_valid : std_logic := '0';
  signal lump_cmd_ready : std_logic;
  signal lump_cmd_op    : unsigned(1 downto 0) := "00";
  signal lump_cmd_addr  : unsigned(26 downto 0) := (others => '0');
  signal lump_cmd_len   : unsigned(8 downto 0) := (others => '0');
  signal lump_rdata     : unsigned(15 downto 0);
  signal lump_rdata_valid : std_logic;
  signal lump_wdata_req : std_logic;
  signal lump_wdata     : unsigned(15 downto 0) := x"0000";
  signal lump_wdata_be  : std_logic_vector(1 downto 0) := "11";
  signal lump_cmd_done  : std_logic;
  signal lump_error     : std_logic;
  signal lump_idle      : std_logic;

  type words_t is array (0 to 255) of unsigned(15 downto 0);
  type bes_t is array (0 to 255) of std_logic_vector(1 downto 0);
  signal wmem : words_t := (others => x"0000");
  signal wbe  : bes_t := (others => "11");
  signal wptr : integer := 0;          -- next write word to supply
  signal wrst : std_logic := '0';
  signal rmem : words_t := (others => x"0000");
  signal rcount : integer := 0;        -- read words received (never reset)
  signal done_count : integer := 0;

  signal finished : boolean := false;
  signal errors : integer := 0;

begin

  identical_clocks <= '1' when identical = 1 else '0';

  clock162 <= not clock162 after T/2 when not finished;
  clk_m <= transport clock162 after dm_ps * 1 ps;
  ps_locked <= '1' after lock_us * 1 us;

  -- clock162r: arbitrary start phase, moved by ps_offset fine steps
  rclk : process
    variable k : integer := 1;
    variable t_next : time;
  begin
    loop
      t_next := k * T + phi0_ps * 1 ps + ps_offset * PS_STEP;
      if t_next > now then
        wait for t_next - now;
      end if;
      clock162r <= '1';
      wait for T / 2;
      clock162r <= '0';
      k := k + 1;
      exit when finished;
    end loop;
    wait;
  end process;

  -- MMCM dynamic phase shift: PSDONE 12 PSCLK cycles after PSEN
  psm : process
  begin
    wait until rising_edge(clock162);
    if ps_en = '1' and no_ps = 0 and ps_locked = '1' then
      for i in 1 to 11 loop
        wait until rising_edge(clock162);
      end loop;
      if ps_incdec = '1' then ps_offset <= ps_offset + 1; else ps_offset <= ps_offset - 1; end if;
      ps_done <= '1';
      wait until rising_edge(clock162);
      ps_done <= '0';
    end if;
  end process;

  -- Read data is invalid for xw_ps after each word (except write cycles,
  -- where the model samples the controller's data at clk_m)
  xwin : process
  begin
    sdram_dq <= (others => 'Z');
    loop
      wait until rising_edge(clk_m);
      exit when finished;
      if not (sdram_cs_n = '0' and sdram_ras_n = '1' and sdram_cas_n = '0' and sdram_we_n = '0') then
        sdram_dq <= (others => 'X');
        wait for xw_ps * 1 ps;
        sdram_dq <= (others => 'Z');
      end if;
    end loop;
    wait;
  end process;
  process (clock162) begin
    if rising_edge(clock162) then pixelclock <= not pixelclock; end if;
  end process;

  sdram_model0 : entity work.is42s16320f_model
    generic map (clock_frequency => 162_000_000)
    port map (clk => clk_m, reset => '0', addr => sdram_a, ba => sdram_ba,
              dq => sdram_dq, clk_en => sdram_cke, cs => sdram_cs_n,
              ras => sdram_ras_n, cas => sdram_cas_n, we => sdram_we_n,
              ldqm => sdram_dqml, udqm => sdram_dqmh,
              enforce_100usec_init => false,
              init_sequence_done => init_sequence_done);

  dut : entity work.sdram_controller
    port map (
      pixelclock => pixelclock, clock162 => clock162, clock162r => clock162r,
      identical_clocks => identical_clocks,
      ps_en => ps_en, ps_incdec => ps_incdec, ps_done => ps_done,
      ps_locked => ps_locked,
      enforce_100us_delay => boot = 1,
      request_counter => open,
      read_request => slow_read, write_request => slow_write,
      address => slow_address, wdata => slow_wdata,
      rdata_hi => slow_rdata_hi, rdata => slow_rdata,
      data_ready_toggle => data_ready_toggle, busy => busy,
      current_cache_line => current_cache_line,
      current_cache_line_address => current_cache_line_address,
      current_cache_line_valid => current_cache_line_valid,
      lump_cmd_valid => lump_cmd_valid, lump_cmd_ready => lump_cmd_ready,
      lump_cmd_op => lump_cmd_op, lump_cmd_addr => lump_cmd_addr,
      lump_cmd_len => lump_cmd_len,
      lump_rdata => lump_rdata, lump_rdata_valid => lump_rdata_valid,
      lump_wdata_req => lump_wdata_req, lump_wdata => lump_wdata,
      lump_wdata_be => lump_wdata_be,
      lump_cmd_done => lump_cmd_done, lump_error => lump_error,
      lump_idle => lump_idle,
      sdram_a => sdram_a, sdram_ba => sdram_ba, sdram_dq => sdram_dq,
      sdram_cke => sdram_cke, sdram_cs_n => sdram_cs_n,
      sdram_ras_n => sdram_ras_n, sdram_cas_n => sdram_cas_n,
      sdram_we_n => sdram_we_n, sdram_dqml => sdram_dqml, sdram_dqmh => sdram_dqmh);

  -- Write data source, per the LUMP contract: register the next word on
  -- the first edge that sees wdata_req.
  wsrc : process (clock162) begin
    if rising_edge(clock162) then
      if wrst = '1' then
        wptr <= 0;
      elsif lump_wdata_req = '1' then
        lump_wdata    <= wmem(wptr);
        lump_wdata_be <= wbe(wptr);
        wptr <= wptr + 1;
      end if;
    end if;
  end process;

  rsink : process (clock162) begin
    if rising_edge(clock162) then
      if lump_rdata_valid = '1' then
        rmem(rcount mod 256) <= lump_rdata;
        rcount <= rcount + 1;
      end if;
      if lump_cmd_done = '1' then
        done_count <= done_count + 1;
      end if;
      if lump_error = '1' then
        report "LUMP error strobe seen" severity error;
      end if;
    end if;
  end process;

  main : process
    variable expect_r : integer := 0;
    variable expect_d : integer := 0;
    variable v : unsigned(15 downto 0);

    procedure tick(n : integer := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clock162);
      end loop;
    end procedure;

    procedure push(op : unsigned(1 downto 0); addr : integer; len : integer) is
    begin
      lump_cmd_op   <= op;
      lump_cmd_addr <= to_unsigned(addr, 27);
      lump_cmd_len  <= to_unsigned(len, 9);
      lump_cmd_valid <= '1';
      loop
        tick;
        exit when lump_cmd_ready = '1';
      end loop;
      lump_cmd_valid <= '0';
      expect_d := expect_d + 1;
      if op = LUMP_OP_READ then
        expect_r := expect_r + len / 2;
      end if;
    end procedure;

    procedure wait_all is
    begin
      for i in 1 to 5000 loop
        tick;
        if done_count = expect_d and rcount = expect_r and lump_idle = '1' then
          return;
        end if;
      end loop;
      report "Timeout waiting for LUMP: done=" & integer'image(done_count)
        & "/" & integer'image(expect_d) & ", rwords=" & integer'image(rcount)
        & "/" & integer'image(expect_r) severity failure;
    end procedure;

    procedure fill(base_word : integer; n : integer; seed : integer) is
    begin
      for i in 0 to n - 1 loop
        wmem(base_word + i) <= to_unsigned((seed * 7919 + i * 2654) mod 65536, 16);
        wbe(base_word + i)  <= "11";
      end loop;
      tick;
    end procedure;

    function pat(seed : integer; i : integer) return unsigned is
    begin
      return to_unsigned((seed * 7919 + i * 2654) mod 65536, 16);
    end function;

    procedure check_read(first_word : integer; n : integer; seed : integer;
                         name : string) is
      variable bad : integer := 0;
    begin
      for i in 0 to n - 1 loop
        if rmem((first_word + i) mod 256) /= pat(seed, i) then
          if bad < 4 then
            report name & ": word " & integer'image(i) & " = $"
              & to_hexstring(rmem((first_word + i) mod 256)) & ", expected $"
              & to_hexstring(pat(seed, i)) severity error;
          end if;
          bad := bad + 1;
        end if;
      end loop;
      if bad = 0 then
        report name & ": PASS (" & integer'image(n) & " words)";
      else
        errors <= errors + 1;
        report name & ": FAIL (" & integer'image(bad) & " bad words)" severity error;
      end if;
    end procedure;

    procedure cpu_access(addr : integer; wr : boolean; val : unsigned(7 downto 0)) is
      -- (Reads wait for data_ready_toggle, as slow_devices does: busy can
      -- drop at the end of a refresh with a read still latched.)
      variable t0 : std_logic;
    begin
      t0 := data_ready_toggle;
      slow_address <= to_unsigned(addr, 27);
      slow_wdata <= val;
      if wr then slow_write <= '1'; else slow_read <= '1'; end if;
      for i in 1 to 100 loop
        tick;
        exit when busy = '1';
      end loop;
      slow_write <= '0'; slow_read <= '0';
      for i in 1 to 100000 loop
        tick;
        if wr then
          exit when busy = '0';
        else
          exit when data_ready_toggle /= t0;
        end if;
      end loop;
      tick(4);
    end procedure;

    variable r0 : integer;
    variable expect_r2 : integer;
    variable fp, fpos : integer;
    type treg_t is array (0 to 31) of unsigned(7 downto 0);
    variable treg : treg_t;
    variable mapline : string(1 to 280);
  begin
    tick(20);
    -- The uploaded controller starts with sdram_prepped='1' (debug), so
    -- trigger the init sequence by writing to the non-RAM area.
    if boot = 0 then
      cpu_access(64 * 1024 * 1024, true, x"00");
    else
      -- as on the board at power-on: nothing writes the non-RAM area; the
      -- init sequence runs after ~100 us by itself, then training
      wait for 110 us;
    end if;
    for i in 1 to 200000 loop
      tick;
      exit when (boot = 1 or init_sequence_done = '1') and busy = '0';
    end loop;
    assert (boot = 1 or init_sequence_done = '1') and busy = '0'
      report "SDRAM init/training not done" severity failure;
    tick(10);
    -- Wait for a training run to complete (it waits for the MMCM lock)
    for i in 1 to 50000 loop
      cpu_access(64 * 1024 * 1024 + 15, false, x"00");
      exit when slow_rdata /= x"00";
    end loop;
    -- Training registers
    for i in 8 to 31 loop
      cpu_access(64 * 1024 * 1024 + i, false, x"00");
      treg(i) := slow_rdata;
    end loop;
    mapline := (others => ' ');
    for p in 0 to 7 loop
      -- coarse phase p: path 0 then path 1, '.' = not clean, else its cycle
      if treg(24 + p)(2) = '1' then
        mapline(p * 3 + 1) := character'val(48 + to_integer(treg(24 + p)(1 downto 0)));
      else
        mapline(p * 3 + 1) := '.';
      end if;
      if treg(24 + p)(6) = '1' then
        mapline(p * 3 + 2) := character'val(48 + to_integer(treg(24 + p)(5 downto 4)));
      else
        mapline(p * 3 + 2) := '.';
      end if;
    end loop;
    report "TRAINING: status $" & to_hexstring(treg(8))
      & ", window " & integer'image(to_integer(treg(9)) + 256 * to_integer(treg(10)))
      & " steps (" & integer'image(to_integer(treg(16)) + 256 * to_integer(treg(17)))
      & "-" & integer'image(to_integer(treg(18)) + 256 * to_integer(treg(19)))
      & "), centre " & integer'image(to_integer(treg(11)) + 256 * to_integer(treg(12)))
      & ", pos " & integer'image(to_integer(treg(13)) + 256 * to_integer(treg(14)))
      & ", runs " & integer'image(to_integer(treg(15)))
      & ", h " & integer'image(to_integer(treg(20)))
      & ", coarse run $" & to_hexstring(treg(21))
      & ", coarse map [" & mapline(1 to 24) & "]"
      & ", phase offset " & integer'image(ps_offset);
    if no_ps = 1 then
      if treg(8)(5) /= '1' or treg(8)(7) /= '0' then
        report "TRAINING: expected 'no phase shifter' status" severity error;
        errors <= errors + 1;
      end if;
    elsif treg(8)(7) /= '1' or treg(8)(4) = '1' then
      report "TRAINING: no (or a weak) window found" severity error;
      errors <= errors + 1;
    end if;
    if no_ps = 1 then
      if errors = 0 then
        report "ALL SDRAM TRAINING TESTS PASSED (no phase shifter: training skipped)";
      end if;
      finished <= true;
      wait;
    end if;

    if force_h1c0 = 1 then
      fp := -1;
      for p in 0 to 6 loop
        if fp < 0 and treg(24 + p)(6 downto 4) = "100" and treg(25 + p)(6 downto 4) = "100" then
          fp := p;
        end if;
      end loop;
      assert fp >= 0 report "no phase with path 1 at cycle 0 to force" severity failure;
      fpos := to_integer(treg(13)) + 256 * to_integer(treg(14));
      for i in 1 to (fp * 35 + 17 - fpos + 280) mod 280 loop
        cpu_access(64 * 1024 * 1024 + 16#11#, true, x"00");
      end loop;
      cpu_access(64 * 1024 * 1024 + 16#14#, true, x"04");
      cpu_access(64 * 1024 * 1024 + 8, false, x"00");
      report "FORCED: path 1, read cycle 0 at coarse phase " & integer'image(fp)
        & "+17, status $" & to_hexstring(slow_rdata);
    end if;

    -- 1. Simple 64-byte write then read back (row closed -> ACTIVATE path)
    fill(0, 32, 1); wrst <= '1'; tick; wrst <= '0'; tick;
    push(LUMP_OP_WRITE, 16#100#, 64);
    wait_all;
    r0 := rcount;
    push(LUMP_OP_READ, 16#100#, 64);
    wait_all;
    check_read(r0, 32, 1, "64B write/read, same row");

    -- 2. 256-byte burst in a different row (PRECHARGE + ACTIVATE path)
    fill(0, 128, 2); wrst <= '1'; tick; wrst <= '0'; tick;
    push(LUMP_OP_WRITE, 16#1800#, 256);
    wait_all;
    r0 := rcount;
    push(LUMP_OP_READ, 16#100#, 64);    -- back to first row
    push(LUMP_OP_READ, 16#1800#, 256);  -- queued behind it
    wait_all;
    check_read(r0, 32, 1, "re-read first block after row switch");
    check_read(r0 + 32, 128, 2, "256B burst in second row");

    -- 2b. CPU reads of LUMP-written data (the CPU line-fill path)
    push(LUMP_OP_INVALIDATE, 0, 0);
    wait_all;
    for i in 0 to 15 loop
      cpu_access(16#1800# + i, false, x"00");
      v := pat(2, i / 2);
      if (i mod 2 = 0 and slow_rdata /= v(7 downto 0))
        or (i mod 2 = 1 and slow_rdata /= v(15 downto 8)) then
        report "CPU read of $" & to_hexstring(to_unsigned(16#1800# + i, 16)) & " = $"
          & to_hexstring(slow_rdata) severity error;
        errors <= errors + 1;
      end if;
    end loop;
    report "CPU reads after training complete";

    -- 3. Byte enables: alternate low/high byte writes over first block
    for i in 0 to 3 loop
      wmem(i) <= x"AA55";
      if i mod 2 = 0 then wbe(i) <= "01"; else wbe(i) <= "10"; end if;
    end loop;
    tick; wrst <= '1'; tick; wrst <= '0'; tick;
    push(LUMP_OP_WRITE, 16#100#, 8);
    wait_all;
    r0 := rcount;
    push(LUMP_OP_READ, 16#100#, 8);
    wait_all;
    for i in 0 to 3 loop
      v := pat(1, i);
      if i mod 2 = 0 then v(7 downto 0) := x"55"; else v(15 downto 8) := x"AA"; end if;
      if rmem(r0 + i) /= v then
        report "byte enable word " & integer'image(i) & " = $" & to_hexstring(rmem(r0 + i))
          & ", expected $" & to_hexstring(v) severity error;
        errors <= errors + 1;
      end if;
    end loop;
    report "byte enable test complete";

    -- 4. Byte order / coherency with CPU path: CPU read of a byte LUMP wrote,
    -- after an INVALIDATE.
    push(LUMP_OP_INVALIDATE, 0, 0);
    wait_all;
    cpu_access(16#1800# + 3, false, x"00");
    v := pat(2, 1);
    if slow_rdata /= v(15 downto 8) then
      report "CPU read of $1803 = $" & to_hexstring(slow_rdata) & ", expected $"
        & to_hexstring(v(15 downto 8)) severity error;
      errors <= errors + 1;
    else
      report "CPU read of LUMP-written byte: PASS";
    end if;

    -- 5. CPU write interleaved with LUMP traffic, then LUMP read sees it
    cpu_access(16#1800# + 4, true, x"C3");
    r0 := rcount;
    push(LUMP_OP_READ, 16#1800#, 8);
    wait_all;
    v := pat(2, 2); v(7 downto 0) := x"C3";
    if rmem(r0 + 2) /= v then
      report "LUMP read after CPU write = $" & to_hexstring(rmem(r0 + 2))
        & ", expected $" & to_hexstring(v) severity error;
      errors <= errors + 1;
    else
      report "LUMP read of CPU-written byte: PASS";
    end if;

    -- 6. Soak: many bursts, spanning several refresh intervals
    for k in 0 to 11 loop
      fill(0, 128, 10 + k); wrst <= '1'; tick; wrst <= '0'; tick;
      push(LUMP_OP_WRITE, 16#4000# + k * 256, 256);
      wait_all;
    end loop;
    for k in 0 to 11 loop
      r0 := rcount;
      push(LUMP_OP_READ, 16#4000# + k * 256, 256);
      wait_all;
      check_read(r0, 128, 10 + k, "soak block " & integer'image(k));
    end loop;

    -- 7. Retrain from the MEGA65 side ($C000010): the 8 test bytes at the
    -- top of the SDRAM must come back, and reads must still be clean.
    fill(0, 4, 77); wrst <= '1'; tick; wrst <= '0'; tick;
    push(LUMP_OP_WRITE, 16#3FFFFF8#, 8);
    wait_all;
    cpu_access(64 * 1024 * 1024 + 16#0F#, false, x"00");
    r0 := to_integer(slow_rdata);
    cpu_access(64 * 1024 * 1024 + 16#10#, true, x"00");
    for i in 1 to 400000 loop
      tick;
      exit when busy = '0';
    end loop;
    cpu_access(64 * 1024 * 1024 + 16#0F#, false, x"00");
    if to_integer(slow_rdata) /= r0 + 1 then
      report "retrain: run count did not advance" severity error;
      errors <= errors + 1;
    end if;
    cpu_access(64 * 1024 * 1024 + 8, false, x"00");
    if slow_rdata(7) /= '1' then
      report "retrain: no window" severity error;
      errors <= errors + 1;
    end if;
    r0 := rcount;
    push(LUMP_OP_READ, 16#3FFFFF8#, 8);
    push(LUMP_OP_READ, 16#4000#, 256);
    wait_all;
    check_read(r0, 4, 77, "test bytes restored after retraining");
    check_read(r0 + 4, 128, 10, "reads after retraining");
    -- 8. Manual phase steps ($C000011 later, $C000012 earlier)
    cpu_access(64 * 1024 * 1024 + 16#0D#, false, x"00");
    r0 := to_integer(slow_rdata);
    cpu_access(64 * 1024 * 1024 + 16#0E#, false, x"00");
    r0 := r0 + 256 * to_integer(slow_rdata);
    cpu_access(64 * 1024 * 1024 + 16#11#, true, x"00");
    cpu_access(64 * 1024 * 1024 + 16#11#, true, x"00");
    cpu_access(64 * 1024 * 1024 + 16#12#, true, x"00");
    tick(100);
    cpu_access(64 * 1024 * 1024 + 16#0D#, false, x"00");
    expect_r2 := to_integer(slow_rdata);
    cpu_access(64 * 1024 * 1024 + 16#0E#, false, x"00");
    expect_r2 := expect_r2 + 256 * to_integer(slow_rdata);
    if (expect_r2 - r0 + 280) mod 280 /= 1 then
      report "manual steps: position " & integer'image(r0) & " -> "
        & integer'image(expect_r2) severity error;
      errors <= errors + 1;
    else
      report "manual phase steps: PASS";
    end if;

    tick;
    if errors = 0 then
      report "ALL SDRAM TRAINING TESTS PASSED (phi0=" & integer'image(phi0_ps) & " ps)";
    else
      report integer'image(errors) & " SDRAM TRAINING TEST FAILURES" severity error;
    end if;
    finished <= true;
    wait;
  end process;

end test;
