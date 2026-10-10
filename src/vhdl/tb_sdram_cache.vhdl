-- Testbench for the SDRAM controller's CPU path (caching, write buffering,
-- open rows) as the CPU and slow_devices drive it, plus LUMP alongside.
--
-- The CPU side models gs4510 + slow_devices as wired on the R4-R6 tops:
--   * $D7FE bit 2 (cpu_line=1): the CPU reads straight from the exported
--     current cache line when it matches; bit 3 (cpu_adv=1): reading byte 7
--     after byte 6 there flips current_cache_line_next_toggle.
--   * $D7FE bit 0 (cpu_pf=1): slow_devices' "next byte" prefetch register.
--   * otherwise a slow access: slow_devices waits for busy = '0', pulses
--     read/write for one pixelclock, and for reads waits for
--     data_ready_toggle (128 pixelclocks timeout, then returns junk).
-- (slow_devices' own cache line shortcut is not connected on those tops.)
--
-- Every CPU read and every LUMP read is checked against a reference
-- memory.  Throughput of the CPU patterns is reported in KB/s.
-- The SDRAM is sdram4_model (4 banks, timing checks); read capture is
-- trained as on the board.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;
use work.cputypes.all;
use work.lumptypes.all;

entity tb_sdram_cache is
  generic (cpu_line : integer := 0;     -- $D7FE bit 2
           cpu_adv  : integer := 0;     -- $D7FE bit 3
           cpu_pf   : integer := 0;     -- $D7FE bit 0
           phi0_ps  : integer := 1500;
           dm_ps    : integer := 4000;
           xw_ps    : integer := 1500;
           nrand    : integer := 3000;
           cflags   : integer := -1;     -- >= 0: write $C000015 (CPU path flags)
           seed0    : integer := 1);
end entity;

architecture test of tb_sdram_cache is

  constant T : time := 6173 ps;
  constant PS_STEP : time := T / 280;
  signal clk_m : std_logic := '0';
  signal ps_en, ps_incdec, ps_done : std_logic := '0';
  signal ps_offset : integer := 0;

  signal clock162   : std_logic := '0';
  signal clock162r  : std_logic := '0';
  signal pixelclock : std_logic := '0';

  -- controller CPU-side port
  signal exr_read, exr_write : std_logic := '0';
  signal exr_addr  : unsigned(26 downto 0) := (others => '0');
  signal exr_wdata : unsigned(7 downto 0) := x"00";
  signal exr_rdata, exr_rdata_hi : unsigned(7 downto 0);
  signal exr_toggle : std_logic;
  signal exr_busy : std_logic;
  signal line_data : cache_row_t;
  signal line_addr : unsigned(26 downto 3) := (others => '0');
  signal line_valid : std_logic;
  signal line_next_toggle, line_prev_toggle : std_logic := '0';

  -- CPU <-> slow_devices
  signal sa_req_toggle : std_logic := '0';
  signal sa_ready_toggle : std_logic := '0';
  signal sa_addr  : unsigned(27 downto 0) := (others => '1');
  signal sa_write : std_logic := '0';
  signal sa_wdata : unsigned(7 downto 0) := x"00";
  signal sa_rdata : unsigned(7 downto 0) := x"00";
  signal pf_req_toggle : std_logic := '0';
  signal pf_addr : unsigned(26 downto 0) := (others => '1');
  signal pf_data : unsigned(7 downto 0) := x"00";
  signal sd_timeouts : integer := 0;

  signal sdram_a : unsigned(12 downto 0);
  signal sdram_ba : unsigned(1 downto 0);
  signal sdram_dq : unsigned(15 downto 0);
  signal sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n : std_logic;
  signal sdram_dqml, sdram_dqmh : std_logic;
  signal model_errors, n_act, n_rd, n_wr, n_pre : integer;

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
  signal wmem : words_t := (others => x"0000");
  signal wptr : integer := 0;
  signal wrst : std_logic := '0';
  signal rmem : words_t := (others => x"0000");
  signal rcount : integer := 0;
  signal done_count : integer := 0;

  signal finished : boolean := false;

begin

  clock162 <= not clock162 after T/2 when not finished;
  clk_m <= transport clock162 after dm_ps * 1 ps;
  process (clock162) begin
    if rising_edge(clock162) then pixelclock <= not pixelclock; end if;
  end process;

  rclk : process
    variable k : integer := 1;
    variable t_next : time;
  begin
    loop
      t_next := k * T + phi0_ps * 1 ps + ps_offset * PS_STEP;
      if t_next > now then wait for t_next - now; end if;
      clock162r <= '1';
      wait for T / 2;
      clock162r <= '0';
      k := k + 1;
      exit when finished;
    end loop;
    wait;
  end process;

  psm : process
  begin
    wait until rising_edge(clock162);
    if ps_en = '1' then
      for i in 1 to 11 loop wait until rising_edge(clock162); end loop;
      if ps_incdec = '1' then ps_offset <= ps_offset + 1; else ps_offset <= ps_offset - 1; end if;
      ps_done <= '1';
      wait until rising_edge(clock162);
      ps_done <= '0';
    end if;
  end process;

  -- read data invalid for xw_ps after each edge (not on write cycles)
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

  model : entity work.sdram4_model
    port map (clk => clk_m, cke => sdram_cke, cs_n => sdram_cs_n,
              ras_n => sdram_ras_n, cas_n => sdram_cas_n, we_n => sdram_we_n,
              ba => sdram_ba, addr => sdram_a, dq => sdram_dq,
              ldqm => sdram_dqml, udqm => sdram_dqmh, errors => model_errors,
              n_act => n_act, n_rd => n_rd, n_wr => n_wr, n_pre => n_pre);

  dut : entity work.sdram_controller
    port map (
      pixelclock => pixelclock, clock162 => clock162, clock162r => clock162r,
      identical_clocks => '0',
      ps_en => ps_en, ps_incdec => ps_incdec, ps_done => ps_done, ps_locked => '1',
      enforce_100us_delay => false,
      request_counter => open,
      read_request => exr_read, write_request => exr_write,
      address => exr_addr, wdata => exr_wdata,
      rdata_hi => exr_rdata_hi, rdata => exr_rdata,
      data_ready_toggle => exr_toggle, busy => exr_busy,
      current_cache_line => line_data,
      current_cache_line_address => line_addr,
      current_cache_line_valid => line_valid,
      expansionram_current_cache_line_next_toggle => line_next_toggle,
      expansionram_current_cache_line_prev_toggle => line_prev_toggle,
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

  wsrc : process (clock162) begin
    if rising_edge(clock162) then
      if wrst = '1' then
        wptr <= 0;
      elsif lump_wdata_req = '1' then
        lump_wdata <= wmem(wptr mod 256);
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
      if lump_cmd_done = '1' then done_count <= done_count + 1; end if;
      if lump_error = '1' then report "LUMP error strobe seen" severity error; end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- slow_devices: the expansion RAM part, as in slow_devices.vhdl
  ---------------------------------------------------------------------------
  slowdev : process (pixelclock)
    type st_t is (Idle, ExpansionRAMRequest, ExpansionRAMReadWait);
    variable st : st_t := Idle;
    variable last_req : std_logic := '0';
    variable last_toggle : std_logic := '0';
    variable tmo : integer := 0;
    variable last_pf_req : std_logic := '0';
    variable eternally_busy : std_logic := '1';
  begin
    if rising_edge(pixelclock) then
      if st /= Idle then
        if tmo /= 0 then
          tmo := tmo - 1;
        else
          st := Idle;
          sa_rdata <= exr_toggle & exr_busy & exr_rdata(5 downto 0);
          sa_ready_toggle <= sa_req_toggle;
          sd_timeouts <= sd_timeouts + 1;
        end if;
      end if;
      if pf_req_toggle /= last_pf_req then
        last_pf_req := pf_req_toggle;
        if pf_addr(2 downto 0) /= "111" then
          pf_addr <= pf_addr + 1;
          pf_data <= line_data(to_integer(pf_addr(2 downto 0)) + 1);
        end if;
      end if;
      if exr_busy = '0' then eternally_busy := '0'; end if;
      case st is
        when Idle =>
          exr_read <= '0'; exr_write <= '0';
          if last_req /= sa_req_toggle then
            last_req := sa_req_toggle;
            tmo := 128;
            st := ExpansionRAMRequest;
          end if;
        when ExpansionRAMRequest =>
          if eternally_busy = '0' and exr_busy = '0' then
            exr_wdata <= sa_wdata;
            exr_addr  <= sa_addr(26 downto 0);
            exr_read  <= not sa_write;
            exr_write <= sa_write;
            if sa_write = '1' then
              st := Idle;
              sa_ready_toggle <= sa_req_toggle;
              if sa_addr(26 downto 0) = pf_addr then pf_data <= sa_wdata; end if;
            else
              st := ExpansionRAMReadWait;
            end if;
          end if;
        when ExpansionRAMReadWait =>
          exr_read <= '0'; exr_write <= '0';
          if exr_toggle /= last_toggle then
            st := Idle;
            sa_rdata <= exr_rdata;
            sa_ready_toggle <= sa_req_toggle;
            if sa_addr(2 downto 0) /= "111" then
              pf_addr(26 downto 3) <= line_addr;
              pf_addr(2 downto 0) <= sa_addr(2 downto 0) + 1;
              pf_data <= line_data(to_integer(sa_addr(2 downto 0)) + 1);
            end if;
          end if;
      end case;
      last_toggle := exr_toggle;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- The CPU (and DMA) side, and the tests
  ---------------------------------------------------------------------------
  main : process
    constant REF_BYTES : integer := 1024 * 1024;
    type ref_t is array (0 to REF_BYTES - 1) of unsigned(7 downto 0);
    variable ref : ref_t := (others => x"00");
    variable errs : integer := 0;
    variable prev_idx : integer := 0;
    variable inc_t : std_logic := '0';
    variable r : unsigned(7 downto 0);
    variable seed : integer := seed0;
    variable c0, c1 : integer;
    variable cyc : integer := 0;
    variable expect_d, expect_r : integer := 0;
    variable a, n : integer;
    variable shown : integer := 0;
    variable to_base : integer := 0;

    procedure ptick(k : integer := 1) is
    begin
      for i in 1 to k loop
        wait until rising_edge(pixelclock);
        cyc := cyc + 1;
      end loop;
    end procedure;

    impure function rnd(m : integer) return integer is
      variable hi : integer;
    begin
      -- (two 16-bit LCG steps: GHDL integers are 32-bit)
      seed := (seed * 25173 + 13849) mod 65536;
      hi := seed mod 64;
      seed := (seed * 25173 + 13849) mod 65536;
      return (hi * 65536 + seed) mod m;
    end function;

    function pat(addr : integer; k : integer) return unsigned is
    begin
      return to_unsigned((addr * 7 + addr / 256 * 13 + k * 101 + 5) mod 256, 8);
    end function;

    procedure slow_access(addr : integer; wr : boolean; v : unsigned(7 downto 0)) is
    begin
      sa_addr  <= to_unsigned(addr, 28);
      sa_wdata <= v;
      if wr then sa_write <= '1'; else sa_write <= '0'; end if;
      sa_req_toggle <= not sa_req_toggle;
      ptick;
      for i in 1 to 100000 loop
        exit when sa_ready_toggle = sa_req_toggle;
        ptick;
      end loop;
      assert sa_ready_toggle = sa_req_toggle report "slow access never completed" severity failure;
    end procedure;

    procedure cpu_write(addr : integer; v : unsigned(7 downto 0)) is
    begin
      slow_access(addr, true, v);
      if addr < REF_BYTES then ref(addr) := v; end if;
      ptick(2);                         -- next CPU cycle
    end procedure;

    procedure cpu_read(addr : integer; check : boolean := true) is
      variable idx : integer := addr mod 8;
      variable au : unsigned(26 downto 0) := to_unsigned(addr, 27);
    begin
      if cpu_line = 1 and line_valid = '1' and au(26 downto 3) = line_addr then
        r := line_data(idx);
        if cpu_adv = 1 and prev_idx = 6 and idx = 7 then
          inc_t := not inc_t;
          line_next_toggle <= inc_t;
        end if;
        prev_idx := idx;
        ptick(1);
      elsif cpu_pf = 1 and au = pf_addr then
        r := pf_data;
        pf_req_toggle <= not pf_req_toggle;
        ptick(1);
      else
        slow_access(addr, false, x"00");
        r := sa_rdata;
      end if;
      if check and addr < REF_BYTES and r /= ref(addr) then
        errs := errs + 1;
        if shown < 12 then
          shown := shown + 1;
          report "CPU READ $" & to_hstring(au) & " = $" & to_hstring(r)
            & ", expected $" & to_hstring(ref(addr)) severity error;
        end if;
      end if;
      ptick(1);
    end procedure;

    procedure rate(name : string; bytes : integer; cycles : integer) is
    begin
      report "SPEED " & name & ": " & integer'image(bytes) & " bytes in "
        & integer'image(cycles) & " pixelclocks = "
        & integer'image(integer(real(bytes) / (real(cycles) * 12.346e-9) / 1024.0))
        & " KB/s";
    end procedure;

    procedure ltick(k : integer := 1) is
    begin
      for i in 1 to k loop wait until rising_edge(clock162); end loop;
    end procedure;

    procedure push(op : unsigned(1 downto 0); addr : integer; len : integer) is
    begin
      lump_cmd_op <= op;
      lump_cmd_addr <= to_unsigned(addr, 27);
      lump_cmd_len <= to_unsigned(len, 9);
      lump_cmd_valid <= '1';
      loop
        ltick;
        exit when lump_cmd_ready = '1';
      end loop;
      lump_cmd_valid <= '0';
      expect_d := expect_d + 1;
      if op = LUMP_OP_READ then expect_r := expect_r + len / 2; end if;
    end procedure;

    procedure lump_wait is
    begin
      for i in 1 to 20000 loop
        ltick;
        if done_count = expect_d and rcount = expect_r and lump_idle = '1' then return; end if;
      end loop;
      report "LUMP timeout" severity failure;
    end procedure;

    procedure lump_read_check(addr : integer; words : integer; name : string) is
      variable r0 : integer;
      variable bad : integer := 0;
      variable w : unsigned(15 downto 0);
    begin
      r0 := rcount;
      push(LUMP_OP_READ, addr, words * 2);
      lump_wait;
      for i in 0 to words - 1 loop
        w := ref(addr + 2 * i + 1) & ref(addr + 2 * i);
        if rmem((r0 + i) mod 256) /= w then
          if bad < 4 then
            report name & ": word " & integer'image(i) & " = $" & to_hstring(rmem((r0 + i) mod 256))
              & ", expected $" & to_hstring(w) severity error;
          end if;
          bad := bad + 1;
        end if;
      end loop;
      errs := errs + bad;
      report name & ": " & integer'image(bad) & " bad of " & integer'image(words) & " words";
    end procedure;

  begin
    -- init and training: poll the run count ($C00000F) until it moves
    -- (while it is busy, slow_devices times out and returns junk)
    ptick(50);
    for i in 1 to 100000 loop
      a := sd_timeouts;
      slow_access(64 * 1024 * 1024 + 15, false, x"00");
      exit when sd_timeouts = a and sa_rdata /= x"00";
      ptick(20);
    end loop;
    slow_access(64 * 1024 * 1024 + 8, false, x"00");
    report "TRAINING status $" & to_hstring(sa_rdata);
    assert sa_rdata(7) = '1' report "training failed" severity failure;
    to_base := sd_timeouts;
    if cflags >= 0 then
      slow_access(64 * 1024 * 1024 + 16#15#, true, to_unsigned(cflags, 8));
      slow_access(64 * 1024 * 1024 + 16#17#, false, x"00");
      report "CPU path flags $" & to_hstring(sa_rdata);
      assert to_integer(sa_rdata) = cflags report "flags did not stick" severity failure;
    end if;

    -- 1. sequential writes (fill), 4 KB
    c0 := cyc;
    for i in 0 to 4095 loop cpu_write(16#10000# + i, pat(16#10000# + i, 1)); end loop;
    rate("fill (CPU writes)", 4096, cyc - c0);

    -- 2. sequential reads of it
    c0 := cyc;
    for i in 0 to 4095 loop cpu_read(16#10000# + i); end loop;
    rate("sequential reads", 4096, cyc - c0);

    -- 3. copy byte by byte to 64 KB higher
    c0 := cyc;
    for i in 0 to 4095 loop
      cpu_read(16#10000# + i);
      cpu_write(16#20000# + i, r);
    end loop;
    rate("copy (read+write)", 4096, cyc - c0);
    for i in 0 to 4095 loop cpu_read(16#20000# + i); end loop;

    -- 4. reverse reads
    c0 := cyc;
    for i in 4095 downto 0 loop cpu_read(16#10000# + i); end loop;
    rate("reverse reads", 4096, cyc - c0);

    -- 5. read-modify-write in place, and immediate read-back of each write
    for i in 0 to 1023 loop
      cpu_read(16#30000# + i);
      cpu_write(16#30000# + i, pat(16#30000# + i, 2));
      cpu_read(16#30000# + i);
    end loop;

    -- 6. random mix over 256 KB (rows in all banks)
    for k in 1 to nrand loop
      a := rnd(256 * 1024);
      case rnd(8) is
        when 0 | 1 | 2 =>
          cpu_write(a, to_unsigned(rnd(256), 8));
        when 3 =>
          -- a short sequential run
          n := rnd(24);
          for j in 0 to n loop cpu_read((a + j) mod (256 * 1024)); end loop;
        when 4 =>
          n := rnd(24);
          for j in 0 to n loop cpu_write((a + j) mod (256 * 1024), to_unsigned(rnd(256), 8)); end loop;
        when others =>
          cpu_read(a);
      end case;
    end loop;
    report "random mix done";

    -- 7. LUMP after CPU writes (SSNAIL's SYNC: INVALIDATE, then use)
    for i in 0 to 511 loop cpu_write(16#40000# + i, pat(16#40000# + i, 3)); end loop;
    push(LUMP_OP_INVALIDATE, 0, 0);
    lump_wait;
    lump_read_check(16#40000#, 128, "LUMP read of CPU-written data");
    lump_read_check(16#40100#, 128, "LUMP read of CPU-written data (2)");

    -- 8. CPU reads after a LUMP write (lines cached before it)
    for i in 0 to 255 loop cpu_read(16#50000# + i); end loop;
    for i in 0 to 127 loop
      wmem(i) <= pat(16#50000# + 2 * i + 1, 4) & pat(16#50000# + 2 * i, 4);
      ref(16#50000# + 2 * i)     := pat(16#50000# + 2 * i, 4);
      ref(16#50000# + 2 * i + 1) := pat(16#50000# + 2 * i + 1, 4);
    end loop;
    wrst <= '1'; ltick; wrst <= '0'; ltick;
    push(LUMP_OP_WRITE, 16#50000#, 256);
    lump_wait;
    push(LUMP_OP_INVALIDATE, 0, 0);
    lump_wait;
    for i in 0 to 255 loop cpu_read(16#50000# + i); end loop;

    -- 9. CPU writes while a LUMP read of another area runs
    push(LUMP_OP_READ, 16#10000#, 256);
    for i in 0 to 63 loop cpu_write(16#60000# + i, pat(16#60000# + i, 5)); end loop;
    lump_wait;
    for i in 0 to 63 loop cpu_read(16#60000# + i); end loop;

    -- 10. the whole of areas 1 and 2 again, after everything
    for i in 0 to 4095 loop cpu_read(16#10000# + i); end loop;
    for i in 0 to 4095 loop cpu_read(16#20000# + i); end loop;

    report "SDRAM commands: " & integer'image(n_act) & " ACT, " & integer'image(n_rd)
      & " READ, " & integer'image(n_wr) & " WRITE, " & integer'image(n_pre) & " PRE; "
      & integer'image(sd_timeouts - to_base) & " slow_devices timeouts";
    if errs = 0 and model_errors = 0 and sd_timeouts = to_base then
      report "TB_SDRAM_CACHE: ALL PASSED";
    else
      report "TB_SDRAM_CACHE: " & integer'image(errs) & " data errors, "
        & integer'image(model_errors) & " SDRAM rule violations, "
        & integer'image(sd_timeouts - to_base) & " timeouts" severity error;
    end if;
    finished <= true;
    wait;
  end process;

end architecture;
