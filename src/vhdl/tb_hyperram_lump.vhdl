-- The real HyperRAM controller (hyperram.vhdl) against the Cypress S27KL0641
-- device model, exercising the CPU path and the LUMP port with the
-- controller in a given mode (generic mode = the $BFFFFF2 value; the R6
-- runs $60, slow; $62 is fast reads, which also passes):
--   1. CPU writes a 64-byte pattern, CPU reads it back (model + CPU path)
--   2. LUMP reads it (64 bytes = 32 words)
--   3. LUMP writes a second pattern; CPU reads it back; LUMP reads it back
--   4. LUMP write with byte enables (odd bytes masked) over a known fill

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;
use work.cputypes.all;
use work.lumptypes.all;

entity tb_hyperram_lump is
  generic (fast : integer := 0;        -- 0: slow mode ($60), 1: fast ($63)
           mode : integer := -1;       -- or the exact $BFFFFF2 value
           cr0 : integer := -1;        -- HyperRAM CR0 to set via $BFFFFF8/9
           wl : integer := -1;         -- write_latency override ($BFFFFF3)
           ewl : integer := -1;        -- extra_write_latency override ($BFFFFF4)
           noreadback : integer := 0;
           cr0late : integer := 0;
           cr0wait : integer := 200;
           wcm : integer := -1;
           n1 : integer := 64;
           wgap : integer := 4;        -- idle pixel clocks after each CPU write         -- bytes in test 1 (CPU write -> CPU read)        -- write_continues_max ($BFFFFF0)   -- pixel clocks to wait after the CR0 write     -- 1: CR0 write between test 1's writes and reads
           trace : integer := 0);      -- 1: trace the bus for one CPU write,
                                       -- 2: for one LUMP write, then stop
end entity;

architecture test of tb_hyperram_lump is
  signal pixelclock, clock163, clock325 : std_logic := '0';
  signal finished : boolean := false;
  -- command/address bytes that changed within 1 ns of a HyperRAM clock edge
  signal ca_bad : integer := 0;

  signal address : unsigned(26 downto 0) := (others => '0');
  signal wdata, rdata : unsigned(7 downto 0) := x"00";
  signal read_request, write_request : std_logic := '0';
  signal busy, ready_toggle : std_logic;
  signal rdata_hi : unsigned(7 downto 0);

  signal hr_d, hr2_d : unsigned(7 downto 0) := (others => 'Z');
  signal hr_rwds, hr2_rwds : std_logic := 'Z';
  signal hr_reset, hr2_reset, hr_clk_p, hr_clk_n, hr2_clk_p, hr2_clk_n : std_logic;
  signal hr_cs0, hr_cs1 : std_logic;

  signal l_valid : std_logic := '0';
  signal l_ready, l_rvalid, l_wreq, l_done, l_error, l_idle : std_logic;
  signal l_op : unsigned(1 downto 0) := "00";
  signal l_addr : unsigned(26 downto 0) := (others => '0');
  signal l_len : unsigned(8 downto 0) := (others => '0');
  signal l_rdata : unsigned(15 downto 0);
  signal l_wdata : unsigned(15 downto 0) := x"0000";
  signal l_be : std_logic_vector(1 downto 0) := "11";

  type words_t is array (0 to 127) of unsigned(15 downto 0);
  signal rwords : words_t := (others => x"0000");
  signal rcount : integer := 0;
  signal wwords : words_t := (others => x"0000");
  signal wbes : std_logic_vector(0 to 255) := (others => '1');
  signal wcount : integer := 0;
  signal lclear : std_logic := '0';
  signal tracing : std_logic := '0';
begin
  -- The command and address bytes (the first 6 clock edges after CS falls)
  -- must not change within 1 ns of a clock edge.  In a zero-delay simulation
  -- the model still reads the old value, so a command a whole cycle out of
  -- phase works here and fails on the real chip (#949: LUMP reads).
  ca_check : process (hr_clk_p, hr_d, hr_cs0)
    variable edges : integer := 0;
  begin
    if hr_cs0 /= '0' then
      edges := 0;
    else
      if hr_clk_p'event then
        if edges < 6 and hr_d'last_event < 1 ns then
          if ca_bad < 4 then
            report "HyperRAM command byte " & integer'image(edges)
              & " changed on a clock edge" severity error;
          end if;
          ca_bad <= ca_bad + 1;
        end if;
        edges := edges + 1;
      elsif hr_d'event and edges >= 1 and edges <= 6 and hr_clk_p'last_event < 1 ns then
        if ca_bad < 4 then
          report "HyperRAM command byte " & integer'image(edges - 1)
            & " changed just after its clock edge" severity error;
        end if;
        ca_bad <= ca_bad + 1;
      end if;
    end if;
  end process;
  -- 325, 163 and 81 MHz, in phase
  process
  begin
    while not finished loop
      clock325 <= '1'; wait for 1.5 ns; clock325 <= '0'; wait for 1.5 ns;
    end loop;
    wait;
  end process;
  process
  begin
    while not finished loop
      clock163 <= '1'; wait for 3 ns; clock163 <= '0'; wait for 3 ns;
    end loop;
    wait;
  end process;
  process
  begin
    while not finished loop
      pixelclock <= '1'; wait for 6 ns; pixelclock <= '0'; wait for 6 ns;
    end loop;
    wait;
  end process;

  hram0 : entity work.hyperram
    generic map (in_simulation => true)
    port map (
      pixelclock => pixelclock, clock163 => clock163, clock325 => clock325,
      read_request => read_request, write_request => write_request,
      address => address, wdata => wdata, rdata => rdata, rdata_hi => rdata_hi,
      data_ready_toggle_out => ready_toggle, busy => busy,
      hr_d => hr_d, hr_rwds => hr_rwds, hr_reset => hr_reset,
      hr_clk_n => hr_clk_n, hr_clk_p => hr_clk_p,
      hr2_d => hr2_d, hr2_rwds => hr2_rwds, hr2_reset => hr2_reset,
      hr2_clk_n => hr2_clk_n, hr2_clk_p => hr2_clk_p,
      hr_cs0 => hr_cs0, hr_cs1 => hr_cs1,
      lump_cmd_valid => l_valid, lump_cmd_ready => l_ready, lump_cmd_op => l_op,
      lump_cmd_addr => l_addr, lump_cmd_len => l_len,
      lump_rdata => l_rdata, lump_rdata_valid => l_rvalid,
      lump_wdata_req => l_wreq, lump_wdata => l_wdata, lump_wdata_be => l_be,
      lump_cmd_done => l_done, lump_error => l_error, lump_idle => l_idle);

  ram0 : entity work.s27kl0641
    generic map (id => "$8000000", tdevice_vcs => 5 ns, timingmodel => "S27KL0641DABHI000")
    port map (DQ7 => hr_d(7), DQ6 => hr_d(6), DQ5 => hr_d(5), DQ4 => hr_d(4),
              DQ3 => hr_d(3), DQ2 => hr_d(2), DQ1 => hr_d(1), DQ0 => hr_d(0),
              CSNeg => hr_cs0, CK => hr_clk_p, RESETneg => hr_reset, RWDS => hr_rwds);
  ram1 : entity work.s27kl0641
    generic map (id => "$8800000", tdevice_vcs => 5 ns, timingmodel => "S27KL0641DABHI000")
    port map (DQ7 => hr2_d(7), DQ6 => hr2_d(6), DQ5 => hr2_d(5), DQ4 => hr2_d(4),
              DQ3 => hr2_d(3), DQ2 => hr2_d(2), DQ1 => hr2_d(1), DQ0 => hr2_d(0),
              CSNeg => hr_cs1, CK => hr2_clk_p, RESETneg => hr2_reset, RWDS => hr2_rwds);

  -- Bus tracer: every HyperRAM clock edge while CS0 is low
  process (hr_clk_p)
  begin
    if tracing = '1' and hr_cs0 = '0' then
      report "BUS CK=" & std_logic'image(hr_clk_p) & " DQ=$" & to_hstring(hr_d)
        & " RWDS=" & std_logic'image(hr_rwds);
    end if;
  end process;
  process (hr_cs0)
  begin
    if tracing = '1' then
      report "BUS CS0=" & std_logic'image(hr_cs0);
    end if;
  end process;

  -- LUMP read data collector, and write data supply (SSNAIL's contract:
  -- register the next word on the edge that sees a request)
  process (clock163)
  begin
    if rising_edge(clock163) then
      if lclear = '1' then
        rcount <= 0; wcount <= 0;
      end if;
      if l_rvalid = '1' then
        rwords(rcount) <= l_rdata;
        rcount <= rcount + 1;
      end if;
      if l_wreq = '1' then
        l_wdata <= wwords(wcount);
        l_be <= wbes(2 * wcount + 1) & wbes(2 * wcount);
        wcount <= wcount + 1;
      end if;
    end if;
  end process;

  main : process
    variable errors : integer := 0;
    variable v : unsigned(7 downto 0);
    variable t0 : time;

    procedure check(ok : boolean; what : string) is
    begin
      if ok then
        report "PASS  " & what;
      else
        report "FAIL  " & what severity error;
        errors := errors + 1;
      end if;
    end procedure;

    procedure cpu_write(a : integer; d : unsigned(7 downto 0)) is
    begin
      wait until rising_edge(pixelclock) and busy = '0';
      address <= to_unsigned(a, 27); wdata <= d; write_request <= '1';
      wait until rising_edge(pixelclock);
      write_request <= '0';
      for i in 1 to wgap loop wait until rising_edge(pixelclock); end loop;
    end procedure;

    procedure cpu_read(a : integer; d : out unsigned(7 downto 0)) is
      variable t : std_logic;
    begin
      wait until rising_edge(pixelclock) and busy = '0';
      t := ready_toggle;
      address <= to_unsigned(a, 27); read_request <= '1';
      wait until rising_edge(pixelclock);
      read_request <= '0';
      for i in 1 to 2000 loop
        wait until rising_edge(pixelclock);
        exit when ready_toggle /= t;
      end loop;
      wait until rising_edge(pixelclock);
      d := rdata;
    end procedure;

    procedure lump(op : unsigned(1 downto 0); a : integer; nbytes : integer) is
    begin
      lclear <= '1';
      wait until rising_edge(clock163);
      lclear <= '0';
      wait until rising_edge(clock163) and l_ready = '1';
      l_valid <= '1'; l_op <= op; l_addr <= to_unsigned(a, 27);
      l_len <= to_unsigned(nbytes, 9);
      wait until rising_edge(clock163);
      l_valid <= '0';
      t0 := now;
      for i in 1 to 20000 loop
        wait until rising_edge(clock163);
        exit when l_done = '1';
      end loop;
      report "  LUMP " & integer'image(to_integer(op)) & " of " & integer'image(nbytes)
        & " bytes took " & integer'image((now - t0) / 1 ns) & " ns, error " & std_logic'image(l_error);
      for i in 1 to 10 loop wait until rising_edge(clock163); end loop;
    end procedure;

    function pat(i, k : integer) return unsigned is
    begin
      return to_unsigned((i * 3 + k) mod 256, 8);
    end function;

    variable bad : integer;
    variable w : unsigned(15 downto 0);
    variable hrmode : unsigned(7 downto 0);
  begin
    if mode >= 0 then hrmode := to_unsigned(mode, 8);
    elsif fast = 1 then hrmode := x"63"; else hrmode := x"60"; end if;
    report "HyperRAM mode $BFFFFF2 = $" & to_hstring(hrmode);
    wait for 200 us;                        -- device power-up
    cpu_write(16#3FFFFF2#, hrmode);
    for i in 1 to 50 loop wait until rising_edge(pixelclock); end loop;
    if cr0 >= 0 and cr0late = 0 then
      -- High byte, then low byte: writing $BFFFFF9 sends CR0 to the HyperRAM
      if trace = 3 then tracing <= '1'; report "BUS TRACE: CR0 write"; end if;
      cpu_write(16#3FFFFF8#, to_unsigned(cr0 / 256, 8));
      cpu_write(16#3FFFFF9#, to_unsigned(cr0 mod 256, 8));
      for i in 1 to cr0wait loop wait until rising_edge(pixelclock); end loop;
      tracing <= '0';
    end if;
    if wcm >= 0 then cpu_write(16#3FFFFF0#, to_unsigned(wcm, 8)); end if;
    if wl >= 0 then cpu_write(16#3FFFFF3#, to_unsigned(wl, 8)); end if;
    if ewl >= 0 then cpu_write(16#3FFFFF4#, to_unsigned(ewl, 8)); end if;
    cpu_read(16#3FFFFF3#, v);
    report "write_latency " & integer'image(to_integer(v));
    cpu_read(16#3FFFFF4#, v);
    report "extra_write_latency " & integer'image(to_integer(v));
    if cr0 >= 0 and noreadback = 0 then
      -- the device's CR0, read back from register space ($A001000)
      cpu_read(16#2001000#, v);
      w(15 downto 8) := v;
      cpu_read(16#2001001#, v);
      w(7 downto 0) := v;
      check(to_integer(w) = cr0, "HyperRAM CR0 reads back $" & to_hstring(w)
            & " (set $" & to_hstring(to_unsigned(cr0, 16)) & ")");
    end if;

    if trace /= 0 and trace /= 4 then
      for i in 1 to 400 loop wait until rising_edge(pixelclock); end loop;
      tracing <= '1';
      if trace = 1 then
        report "BUS TRACE: CPU write of $A5 to $305001";
        cpu_write(16#305001#, x"A5");
        for i in 1 to 400 loop wait until rising_edge(pixelclock); end loop;
      else
        report "BUS TRACE: LUMP write of 8 bytes $11..$88 to $305008";
        wwords(0) <= x"2211"; wwords(1) <= x"4433"; wwords(2) <= x"6655"; wwords(3) <= x"8877";
        wbes <= (others => '1');
        lump(LUMP_OP_WRITE, 16#305008#, 8);
      end if;
      tracing <= '0';
      -- read back in slow mode, which works
      cpu_write(16#3FFFFF2#, x"60");
      for i in 1 to 50 loop wait until rising_edge(pixelclock); end loop;
      for i in 0 to 15 loop
        cpu_read(16#305000# + i, v);
        report "BUS READBACK +" & integer'image(i) & " = $" & to_hstring(v);
      end loop;
      finished <= true;
      wait;
    end if;

    -- 1. CPU write, CPU read
    for i in 0 to n1 - 1 loop
      if trace = 4 and i = 14 then tracing <= '1'; end if;
      if trace = 4 and i = 30 then tracing <= '0'; end if;
      cpu_write(16#304000# + i, pat(i, 1));
    end loop;
    for i in 1 to 200 loop wait until rising_edge(pixelclock); end loop;
    if cr0 >= 0 and cr0late = 1 then
      cpu_write(16#3FFFFF8#, to_unsigned(cr0 / 256, 8));
      cpu_write(16#3FFFFF9#, to_unsigned(cr0 mod 256, 8));
      for i in 1 to 200 loop wait until rising_edge(pixelclock); end loop;
    end if;
    bad := 0;
    for i in 0 to n1 - 1 loop
      cpu_read(16#304000# + i, v);
      if v /= pat(i, 1) then
        bad := bad + 1;
        if bad < 40 then report "  CPU +" & integer'image(i) & " = $" & to_hstring(v)
          & ", wanted $" & to_hstring(pat(i, 1)); end if;
      end if;
    end loop;
    check(bad = 0, "CPU write -> CPU read, " & integer'image(n1) & " bytes (" & integer'image(bad) & " bad)");

    -- 2. LUMP read of the same 64 bytes
    lump(LUMP_OP_READ, 16#304000#, 64);
    bad := 0;
    for i in 0 to 31 loop
      w := rwords(i);
      if w(7 downto 0) /= pat(2 * i, 1) or w(15 downto 8) /= pat(2 * i + 1, 1) then
        bad := bad + 1;
        if bad < 5 then report "  LUMP word " & integer'image(i) & " = $" & to_hstring(w)
          & ", wanted $" & to_hstring(pat(2 * i + 1, 1) & pat(2 * i, 1)); end if;
      end if;
    end loop;
    check(rcount = 32 and bad = 0, "LUMP read of CPU-written data: " & integer'image(rcount)
          & " words, " & integer'image(bad) & " bad");

    -- 3. LUMP write, CPU read back, LUMP read back
    for i in 0 to 31 loop wwords(i) <= pat(2 * i + 1, 7) & pat(2 * i, 7); end loop;
    wbes <= (others => '1');
    lump(LUMP_OP_WRITE, 16#307000#, 64);
    lump(LUMP_OP_INVALIDATE, 16#307000#, 64);
    bad := 0;
    for i in 0 to 63 loop
      cpu_read(16#307000# + i, v);
      if v /= pat(i, 7) then
        bad := bad + 1;
        if bad < 4 then report "  CPU +" & integer'image(i) & " = $" & to_hstring(v)
          & ", wanted $" & to_hstring(pat(i, 7)); end if;
      end if;
    end loop;
    check(bad = 0, "LUMP write -> CPU read (" & integer'image(bad) & " bad)");
    lump(LUMP_OP_READ, 16#307000#, 64);
    bad := 0;
    for i in 0 to 31 loop
      if rwords(i) /= (pat(2 * i + 1, 7) & pat(2 * i, 7)) then bad := bad + 1; end if;
    end loop;
    check(rcount = 32 and bad = 0, "LUMP write -> LUMP read (" & integer'image(bad) & " bad)");

    -- 4. byte enables: write $EE everywhere, then a LUMP write with the odd
    -- bytes masked: even bytes take the pattern, odd bytes keep $EE
    for i in 0 to 15 loop cpu_write(16#308000# + i, x"EE"); end loop;
    for i in 1 to 200 loop wait until rising_edge(pixelclock); end loop;
    for i in 0 to 7 loop wwords(i) <= x"55" & pat(2 * i, 9); end loop;
    for i in 0 to 15 loop
      if i mod 2 = 0 then wbes(i) <= '1'; else wbes(i) <= '0'; end if;
    end loop;
    lump(LUMP_OP_WRITE, 16#308000#, 16);
    lump(LUMP_OP_INVALIDATE, 16#308000#, 16);
    bad := 0;
    for i in 0 to 15 loop
      cpu_read(16#308000# + i, v);
      if (i mod 2 = 0 and v /= pat(i, 9)) or (i mod 2 = 1 and v /= x"EE") then
        bad := bad + 1;
        if bad < 4 then report "  BE +" & integer'image(i) & " = $" & to_hstring(v); end if;
      end if;
    end loop;
    check(bad = 0, "LUMP write with byte enables (" & integer'image(bad) & " bad)");
    check(ca_bad = 0, "command bytes stable at the clock edges ("
          & integer'image(ca_bad) & " changed on an edge)");

    if errors = 0 then
      report "TB_HYPERRAM_LUMP: ALL PASSED";
    else
      report "TB_HYPERRAM_LUMP: " & integer'image(errors) & " FAILURES" severity error;
    end if;
    finished <= true;
    -- The device model and controller never run out of events: the runner
    -- ends the simulation with --stop-time
    wait;
  end process;
end test;
