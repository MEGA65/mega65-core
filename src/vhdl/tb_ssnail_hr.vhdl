-- SSNAIL with the real HyperRAM controller (and the Cypress S27KL0641 model)
-- and the real SDRAM controller, doing what 02.LUMP FETCH does on the
-- board: the CPU writes through the HyperRAM controller's CPU port, then a
-- job runs straight away.
--   1. a lone HALT fetched from HyperRAM (16-byte slots, HALT at byte K of
--      slot K, so a misaligned fetch shows as a different end PC)
--   2. COPY HyperRAM -> SDRAM of a CPU-written pattern, then SDRAM ->
--      HyperRAM to another place; the CPU reads that back
-- Generic mode: the $BFFFFF2 value to set first (-1: leave the boot value).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;
use work.cputypes.all;
use work.lumptypes.all;

entity tb_ssnail_hr is
  generic (mode : integer := -1;
           cpu_gap : integer := 4;      -- pixel clocks between CPU writes
           trace : integer := 0;
           -- 1: the HyperRAM model checks CS and DQ setup/hold (1 ns) at CK
           tchk : integer := 0);
end entity;

architecture test of tb_ssnail_hr is
  signal pixelclock, clock163, clock325, cpuclock : std_logic := '0';
  signal finished : boolean := false;
  -- command/address bytes that changed within 1 ns of a HyperRAM clock edge
  signal ca_bad : integer := 0;

  -- HyperRAM CPU port
  signal address : unsigned(26 downto 0) := (others => '0');
  signal wdata, rdata : unsigned(7 downto 0) := x"00";
  signal read_request, write_request : std_logic := '0';
  signal busy, ready_toggle : std_logic;
  signal rdata_hi : unsigned(7 downto 0);
  signal hr_d, hr2_d : unsigned(7 downto 0) := (others => 'Z');
  signal hr_rwds, hr2_rwds : std_logic := 'Z';
  signal hr_reset, hr2_reset, hr_clk_p, hr_clk_n, hr2_clk_p, hr2_clk_n : std_logic;
  signal hr_cs0, hr_cs1 : std_logic;

  -- FastIO
  signal cs, rd, wr : std_logic := '0';
  signal faddr : unsigned(19 downto 0) := (others => '0');
  signal fwdata : unsigned(7 downto 0) := x"00";
  signal frdata : unsigned(7 downto 0);
  signal irq : std_logic;

  -- LUMP, HyperRAM side
  signal hr_cmd_valid, hr_cmd_ready : std_logic;
  signal hr_cmd_op : unsigned(1 downto 0);
  signal hr_cmd_addr : unsigned(26 downto 0);
  signal hr_cmd_len : unsigned(8 downto 0);
  signal hr_rdata : unsigned(15 downto 0);
  signal hr_rdata_valid, hr_wdata_req, hr_cmd_done, hr_error : std_logic;
  signal hr_wdata : unsigned(15 downto 0);
  signal hr_wdata_be : std_logic_vector(1 downto 0);
  -- LUMP, SDRAM side
  signal sd_cmd_valid, sd_cmd_ready : std_logic;
  signal sd_cmd_op : unsigned(1 downto 0);
  signal sd_cmd_addr : unsigned(26 downto 0);
  signal sd_cmd_len : unsigned(8 downto 0);
  signal sd_rdata : unsigned(15 downto 0);
  signal sd_rdata_valid, sd_wdata_req, sd_cmd_done, sd_error : std_logic;
  signal sd_wdata : unsigned(15 downto 0);
  signal sd_wdata_be : std_logic_vector(1 downto 0);

  signal sd_busy : std_logic;
  -- as in tb_ssnail: the capture clock is a (delta-delayed) copy
  signal clock162r : std_logic := '0';
  signal sdram_a : unsigned(12 downto 0);
  signal sdram_ba : unsigned(1 downto 0);
  signal sdram_dq : unsigned(15 downto 0);
  signal sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n : std_logic;
  signal sdram_dqml, sdram_dqmh, init_done : std_logic;
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
  process
  begin
    while not finished loop
      cpuclock <= '1'; wait for 12 ns; cpuclock <= '0'; wait for 12 ns;
    end loop;
    wait;
  end process;

  clock162r <= clock163;

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
      lump_cmd_valid => hr_cmd_valid, lump_cmd_ready => hr_cmd_ready,
      lump_cmd_op => hr_cmd_op, lump_cmd_addr => hr_cmd_addr, lump_cmd_len => hr_cmd_len,
      lump_rdata => hr_rdata, lump_rdata_valid => hr_rdata_valid,
      lump_wdata_req => hr_wdata_req, lump_wdata => hr_wdata, lump_wdata_be => hr_wdata_be,
      lump_cmd_done => hr_cmd_done, lump_error => hr_error, lump_idle => open);

  ram0 : entity work.s27kl0641
    generic map (id => "$8000000", tdevice_vcs => 5 ns, timingmodel => "S27KL0641DABHI000",
                 TimingChecksOn => (tchk /= 0),
                 tsetup_DQ0_CK => 1 ns, thold_DQ0_CK => 1 ns,
                 tsetup_CSNeg_CK => 1 ns, thold_CSNeg_CK => 1 ns)
    port map (DQ7 => hr_d(7), DQ6 => hr_d(6), DQ5 => hr_d(5), DQ4 => hr_d(4),
              DQ3 => hr_d(3), DQ2 => hr_d(2), DQ1 => hr_d(1), DQ0 => hr_d(0),
              CSNeg => hr_cs0, CK => hr_clk_p, RESETneg => hr_reset, RWDS => hr_rwds);

  dut : entity work.ssnail
    port map (
      cpuclock => cpuclock, reset => '1', irq => irq, ssnail_cs => cs,
      fastio_addr => faddr, fastio_write => wr, fastio_read => rd,
      fastio_wdata => fwdata, fastio_rdata => frdata,
      clock162 => clock163,
      hr_cmd_valid => hr_cmd_valid, hr_cmd_ready => hr_cmd_ready,
      hr_cmd_op => hr_cmd_op, hr_cmd_addr => hr_cmd_addr, hr_cmd_len => hr_cmd_len,
      hr_rdata => hr_rdata, hr_rdata_valid => hr_rdata_valid,
      hr_wdata_req => hr_wdata_req, hr_wdata => hr_wdata, hr_wdata_be => hr_wdata_be,
      hr_cmd_done => hr_cmd_done, hr_error => hr_error,
      sd_cmd_valid => sd_cmd_valid, sd_cmd_ready => sd_cmd_ready,
      sd_cmd_op => sd_cmd_op, sd_cmd_addr => sd_cmd_addr, sd_cmd_len => sd_cmd_len,
      sd_rdata => sd_rdata, sd_rdata_valid => sd_rdata_valid,
      sd_wdata_req => sd_wdata_req, sd_wdata => sd_wdata, sd_wdata_be => sd_wdata_be,
      sd_cmd_done => sd_cmd_done, sd_error => sd_error);

  sdram_model0 : entity work.is42s16320f_model
    generic map (clock_frequency => 162_000_000)
    port map (clk => clock163, reset => '0', addr => sdram_a, ba => sdram_ba,
              dq => sdram_dq, clk_en => sdram_cke, cs => sdram_cs_n,
              ras => sdram_ras_n, cas => sdram_cas_n, we => sdram_we_n,
              ldqm => sdram_dqml, udqm => sdram_dqmh,
              enforce_100usec_init => false, init_sequence_done => init_done);

  sdc : entity work.sdram_controller
    port map (
      pixelclock => pixelclock, clock162 => clock163, clock162r => clock162r,
      identical_clocks => '1', enforce_100us_delay => false,
      read_request => '0', write_request => '0',
      address => (others => '0'), wdata => x"00", busy => sd_busy,
      lump_cmd_valid => sd_cmd_valid, lump_cmd_ready => sd_cmd_ready,
      lump_cmd_op => sd_cmd_op, lump_cmd_addr => sd_cmd_addr, lump_cmd_len => sd_cmd_len,
      lump_rdata => sd_rdata, lump_rdata_valid => sd_rdata_valid,
      lump_wdata_req => sd_wdata_req, lump_wdata => sd_wdata, lump_wdata_be => sd_wdata_be,
      lump_cmd_done => sd_cmd_done, lump_error => sd_error,
      sdram_a => sdram_a, sdram_ba => sdram_ba, sdram_dq => sdram_dq,
      sdram_cke => sdram_cke, sdram_cs_n => sdram_cs_n, sdram_ras_n => sdram_ras_n,
      sdram_cas_n => sdram_cas_n, sdram_we_n => sdram_we_n,
      sdram_dqml => sdram_dqml, sdram_dqmh => sdram_dqmh);

  process (clock163)
  begin
    if rising_edge(clock163) then
      if trace = 1 then
        if hr_cmd_valid = '1' and hr_cmd_ready = '1' then
          report "TRACE HR cmd op " & integer'image(to_integer(hr_cmd_op)) & " addr $"
            & to_hstring(hr_cmd_addr) & " len " & integer'image(to_integer(hr_cmd_len));
        end if;
        if hr_rdata_valid = '1' then report "TRACE HR rdata $" & to_hstring(hr_rdata); end if;
        if hr_wdata_req = '1' then report "TRACE HR wreq"; end if;
        if hr_cmd_done = '1' then report "TRACE HR done"; end if;
        report "TRACE HR wdata $" & to_hstring(hr_wdata) & " be " & std_logic'image(hr_wdata_be(1)) & std_logic'image(hr_wdata_be(0));
        if sd_cmd_valid = '1' and sd_cmd_ready = '1' then
          report "TRACE SD cmd op " & integer'image(to_integer(sd_cmd_op)) & " addr $"
            & to_hstring(sd_cmd_addr) & " len " & integer'image(to_integer(sd_cmd_len));
        end if;
        if sd_rdata_valid = '1' then report "TRACE SD rdata $" & to_hstring(sd_rdata); end if;
        if sd_wdata_req = '1' then report "TRACE SD wreq"; end if;
      end if;
      if hr_error = '1' then report "HyperRAM LUMP error strobe" severity error; end if;
    end if;
  end process;

  main : process
    variable errors : integer := 0;
    variable v : unsigned(7 downto 0);

    procedure cpu_write(a : integer; d : unsigned(7 downto 0)) is
    begin
      wait until rising_edge(pixelclock) and busy = '0';
      address <= to_unsigned(a, 27); wdata <= d; write_request <= '1';
      wait until rising_edge(pixelclock);
      write_request <= '0';
      for i in 1 to cpu_gap loop wait until rising_edge(pixelclock); end loop;
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
    procedure ctick(n : integer := 1) is
    begin
      for i in 1 to n loop wait until rising_edge(cpuclock); end loop;
    end procedure;
    procedure poke(r : integer; x : unsigned(7 downto 0)) is
    begin
      faddr <= to_unsigned(r, 20); fwdata <= x; cs <= '1'; wr <= '1';
      ctick; cs <= '0'; wr <= '0'; ctick;
    end procedure;
    procedure peek(r : integer; x : out unsigned(7 downto 0)) is
    begin
      faddr <= to_unsigned(r, 20); cs <= '1'; rd <= '1';
      wait for 1 ns; x := frdata;
      ctick; cs <= '0'; rd <= '0';
    end procedure;
    -- a 16-byte instruction, written by the CPU through the HyperRAM port
    procedure instr(a : integer; op : integer; s : integer; d : integer; l : integer) is
      variable su, du, lu : unsigned(31 downto 0);
    begin
      su := to_unsigned(s, 32); du := to_unsigned(d, 32); lu := to_unsigned(l, 32);
      cpu_write(a, to_unsigned(op, 8));
      cpu_write(a + 1, x"00"); cpu_write(a + 2, x"00"); cpu_write(a + 3, x"00");
      for k in 0 to 3 loop
        cpu_write(a + 4 + k, su(8 * k + 7 downto 8 * k));
        cpu_write(a + 8 + k, du(8 * k + 7 downto 8 * k));
        cpu_write(a + 12 + k, lu(8 * k + 7 downto 8 * k));
      end loop;
    end procedure;
    procedure run_job(name : string; jp : integer; expect_pc : integer) is
      variable ju : unsigned(31 downto 0) := to_unsigned(jp, 32);
      variable e, p0, p1, p2, p3, st : unsigned(7 downto 0);
    begin
      for k in 0 to 3 loop poke(8 + k, ju(8 * k + 7 downto 8 * k)); end loop;
      poke(3, x"01");
      for i in 1 to 20000 loop
        peek(4, st);
        if st(0) = '0' then
          peek(5, e); peek(12, p0); peek(13, p1); peek(14, p2); peek(15, p3);
          if to_integer(e) /= 0 or (p3 & p2 & p1 & p0) /= to_unsigned(expect_pc, 32) then
            report name & ": FAIL, error " & integer'image(to_integer(e)) & ", PC $"
              & to_hexstring(p3 & p2 & p1 & p0) severity error;
            errors := errors + 1;
          else
            report name & ": PASS";
          end if;
          peek(3, st); poke(3, st);
          return;
        end if;
      end loop;
      report name & ": job timed out" severity error;
      errors := errors + 1;
    end procedure;
  begin
    -- HyperRAM start-up (CR0 write), SDRAM init (training: no phase shifter)
    for i in 1 to 20000 loop
      wait until rising_edge(pixelclock);
      exit when busy = '0' and i > 2000;
    end loop;
    for i in 1 to 300000 loop
      wait until rising_edge(clock163);
      exit when sd_busy = '0' and init_done = '1';
    end loop;
    if mode >= 0 then
      cpu_write(16#3FFFFF2#, to_unsigned(mode, 8));
    end if;
    cpu_read(16#3FFFFF2#, v);
    report "HyperRAM $BFFFFF2 = $" & to_hstring(v);

    -- SSNAIL map as 02 sets it: SDRAM $8000000 (64 MB), HyperRAM $C000000
    poke(16#11#, x"80"); poke(16#12#, x"40"); poke(16#10#, x"08"); poke(16#13#, x"C0");

    -- 1. The slots: zeros, HALT at byte K of slot K, then a slot of $FF
    for i in 0 to 127 loop cpu_write(16#300000# + i, x"00"); end loop;
    for i in 128 to 143 loop cpu_write(16#300000# + i, x"FF"); end loop;
    for k in 0 to 7 loop cpu_write(16#300000# + 17 * k, x"01"); end loop;
    run_job("lone HALT fetched from HyperRAM", 16#C300000#, 16#C300000#);

    -- 2. A pattern in HyperRAM, copied to SDRAM and back to HyperRAM
    for i in 0 to 63 loop cpu_write(16#304000# + i, to_unsigned((i * 3 + 1) mod 256, 8)); end loop;
    instr(16#300200#, 3, 16#C304000#, 16#8305000#, 64);   -- COPY HR -> SDRAM
    instr(16#300210#, 3, 16#8305000#, 16#C306000#, 64);   -- COPY SDRAM -> HR
    instr(16#300220#, 2, 0, 0, 0);                        -- SYNC
    instr(16#300230#, 1, 0, 0, 0);                        -- HALT
    run_job("copy HyperRAM -> SDRAM -> HyperRAM", 16#C300200#, 16#C300230#);
    v := x"00";
    for i in 0 to 63 loop
      cpu_read(16#306000# + i, v);
      if v /= to_unsigned((i * 3 + 1) mod 256, 8) then
        if errors < 8 then
          report "copied byte " & integer'image(i) & " = $" & to_hstring(v) & ", expected $"
            & to_hstring(to_unsigned((i * 3 + 1) mod 256, 8)) severity error;
        end if;
        errors := errors + 1;
      end if;
    end loop;

    if ca_bad /= 0 then
      report integer'image(ca_bad) & " HyperRAM command bytes changed on a clock edge"
        severity error;
      errors := errors + ca_bad;
    end if;
    if errors = 0 then
      report "TB_SSNAIL_HR: ALL PASSED";
    else
      report "TB_SSNAIL_HR: " & integer'image(errors) & " FAILURES" severity error;
    end if;
    finished <= true;
    wait;
  end process;
end test;
