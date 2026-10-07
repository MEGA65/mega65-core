-- Testbench for the SSNAIL shell.
-- HyperRAM side: behavioural LUMP slave (memory array, preloaded with a
-- script and test data).  SDRAM side: the real sdram_controller + model.
-- Driven through the FastIO registers like the 45GS02 would.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;
use work.cputypes.all;
use work.lumptypes.all;
use work.step2_pkg.all;

entity tb_ssnail_step2 is
end entity;

architecture test of tb_ssnail_step2 is
  signal clock162, cpuclock, pixelclock : std_logic := '0';
  -- Same as tb_sdram_lump: clock162r is a (delta-delayed) copy of clock162
  signal clock162r : std_logic := '0';
  signal finished : boolean := false;

  -- FastIO
  signal cs, rd, wr : std_logic := '0';
  signal addr : unsigned(19 downto 0) := (others => '0');
  signal wdata : unsigned(7 downto 0) := x"00";
  signal rdata : unsigned(7 downto 0);
  signal irq : std_logic;

  -- HyperRAM-side LUMP (behavioural)
  signal hr_cmd_valid, hr_cmd_ready : std_logic := '0';
  signal hr_cmd_op : unsigned(1 downto 0);
  signal hr_cmd_addr : unsigned(26 downto 0);
  signal hr_cmd_len : unsigned(8 downto 0);
  signal hr_rdata : unsigned(15 downto 0) := x"0000";
  signal hr_rdata_valid, hr_wdata_req, hr_cmd_done : std_logic := '0';
  signal hr_wdata : unsigned(15 downto 0);
  signal hr_wdata_be : std_logic_vector(1 downto 0);

  -- SDRAM-side LUMP
  signal sd_cmd_valid, sd_cmd_ready : std_logic;
  signal sd_cmd_op : unsigned(1 downto 0);
  signal sd_cmd_addr : unsigned(26 downto 0);
  signal sd_cmd_len : unsigned(8 downto 0);
  signal sd_rdata : unsigned(15 downto 0);
  signal sd_rdata_valid, sd_wdata_req, sd_cmd_done, sd_error : std_logic;
  signal sd_wdata : unsigned(15 downto 0);
  signal sd_wdata_be : std_logic_vector(1 downto 0);

  -- SDRAM pins etc.
  signal slow_read, slow_write : std_logic := '0';
  signal slow_address : unsigned(26 downto 0) := (others => '0');
  signal busy : std_logic;
  signal sdram_a : unsigned(12 downto 0);
  signal sdram_ba : unsigned(1 downto 0);
  signal sdram_dq : unsigned(15 downto 0);
  signal sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n : std_logic;
  signal sdram_dqml, sdram_dqmh, init_done : std_logic;

  -- Behavioural HyperRAM memory: 4K words
  type mem_t is array (0 to 4095) of unsigned(15 downto 0);
  signal hmem : mem_t := (others => x"0000");
  signal tb_hmem_we : std_logic := '0';
  signal tb_hmem_addr : integer := 0;
  signal tb_hmem_data : unsigned(15 downto 0) := x"0000";

begin
  clock162 <= not clock162 after 3 ns when not finished;
  cpuclock <= not cpuclock after 12 ns when not finished;
  clock162r <= clock162;
  process (clock162) begin
    if rising_edge(clock162) then pixelclock <= not pixelclock; end if;
  end process;

  dut : entity work.ssnail
    port map (
      cpuclock => cpuclock, reset => '1', irq => irq, ssnail_cs => cs,
      fastio_addr => addr, fastio_write => wr, fastio_read => rd,
      fastio_wdata => wdata, fastio_rdata => rdata,
      clock162 => clock162,
      hr_cmd_valid => hr_cmd_valid, hr_cmd_ready => hr_cmd_ready,
      hr_cmd_op => hr_cmd_op, hr_cmd_addr => hr_cmd_addr, hr_cmd_len => hr_cmd_len,
      hr_rdata => hr_rdata, hr_rdata_valid => hr_rdata_valid,
      hr_wdata_req => hr_wdata_req, hr_wdata => hr_wdata, hr_wdata_be => hr_wdata_be,
      hr_cmd_done => hr_cmd_done, hr_error => '0',
      sd_cmd_valid => sd_cmd_valid, sd_cmd_ready => sd_cmd_ready,
      sd_cmd_op => sd_cmd_op, sd_cmd_addr => sd_cmd_addr, sd_cmd_len => sd_cmd_len,
      sd_rdata => sd_rdata, sd_rdata_valid => sd_rdata_valid,
      sd_wdata_req => sd_wdata_req, sd_wdata => sd_wdata, sd_wdata_be => sd_wdata_be,
      sd_cmd_done => sd_cmd_done, sd_error => sd_error);

  sdram_model0 : entity work.is42s16320f_model
    generic map (clock_frequency => 162_000_000)
    port map (clk => clock162, reset => '0', addr => sdram_a, ba => sdram_ba,
              dq => sdram_dq, clk_en => sdram_cke, cs => sdram_cs_n,
              ras => sdram_ras_n, cas => sdram_cas_n, we => sdram_we_n,
              ldqm => sdram_dqml, udqm => sdram_dqmh,
              enforce_100usec_init => false, init_sequence_done => init_done);

  sdc : entity work.sdram_controller
    port map (
      pixelclock => pixelclock, clock162 => clock162, clock162r => clock162r,
      identical_clocks => '1', enforce_100us_delay => false,
      read_request => slow_read, write_request => slow_write,
      address => slow_address, wdata => x"00", busy => busy,
      lump_cmd_valid => sd_cmd_valid, lump_cmd_ready => sd_cmd_ready,
      lump_cmd_op => sd_cmd_op, lump_cmd_addr => sd_cmd_addr, lump_cmd_len => sd_cmd_len,
      lump_rdata => sd_rdata, lump_rdata_valid => sd_rdata_valid,
      lump_wdata_req => sd_wdata_req, lump_wdata => sd_wdata, lump_wdata_be => sd_wdata_be,
      lump_cmd_done => sd_cmd_done, lump_error => sd_error,
      sdram_a => sdram_a, sdram_ba => sdram_ba, sdram_dq => sdram_dq,
      sdram_cke => sdram_cke, sdram_cs_n => sdram_cs_n, sdram_ras_n => sdram_ras_n,
      sdram_cas_n => sdram_cas_n, sdram_we_n => sdram_we_n,
      sdram_dqml => sdram_dqml, sdram_dqmh => sdram_dqmh);

  -- Behavioural LUMP slave.  Deliberately irregular read timing (a gap
  -- every 3rd word) to make sure SSNAIL does not assume a steady stream.
  hslave : process (clock162)
    type st_t is (IDLE, RD, WR, WRTAIL);
    variable st : st_t := IDLE;
    variable a, n, k, lat : integer := 0;
    variable g : integer := 0;
  begin
    if rising_edge(clock162) then
      hr_rdata_valid <= '0';
      hr_wdata_req <= '0';
      hr_cmd_done <= '0';
      if tb_hmem_we = '1' then
        hmem(tb_hmem_addr) <= tb_hmem_data;
      end if;
      case st is
        when IDLE =>
          hr_cmd_ready <= '1';
          if hr_cmd_valid = '1' and hr_cmd_ready = '1' then
            hr_cmd_ready <= '0';
            a := to_integer(hr_cmd_addr) / 2;
            n := to_integer(hr_cmd_len) / 2;
            k := 0; lat := 6;
            if hr_cmd_op = LUMP_OP_READ then st := RD;
            elsif hr_cmd_op = LUMP_OP_WRITE then st := WR;
            else hr_cmd_done <= '1'; hr_cmd_ready <= '1';
            end if;
          end if;
        when RD =>
          if lat /= 0 then lat := lat - 1;
          elsif (k mod 3) = 2 and g = 0 then
            g := 1;                     -- insert a gap
          else
            g := 0;
            hr_rdata <= hmem((a + k) mod 4096);
            hr_rdata_valid <= '1';
            k := k + 1;
            if k = n then hr_cmd_done <= '1'; st := IDLE; end if;
          end if;
        when WR =>
          -- request one word per cycle; sample 2 edges after each request
          if k < n then hr_wdata_req <= '1'; end if;
          k := k + 1;
          if k >= 3 and k - 3 < n then
            if hr_wdata_be(0) = '1' then
              hmem((a + k - 3) mod 4096)(7 downto 0) <= hr_wdata(7 downto 0);
            end if;
            if hr_wdata_be(1) = '1' then
              hmem((a + k - 3) mod 4096)(15 downto 8) <= hr_wdata(15 downto 8);
            end if;
          end if;
          if k - 3 = n - 1 then hr_cmd_done <= '1'; st := IDLE; end if;
        when others => st := IDLE;
      end case;
    end if;
  end process;

  main : process
    procedure ctick(n : integer := 1) is
    begin
      for i in 1 to n loop wait until rising_edge(cpuclock); end loop;
    end procedure;
    procedure poke(r : integer; v : unsigned(7 downto 0)) is
    begin
      addr <= to_unsigned(r, 20); wdata <= v; cs <= '1'; wr <= '1';
      ctick; cs <= '0'; wr <= '0'; ctick;
    end procedure;
    procedure peek(r : integer; v : out unsigned(7 downto 0)) is
    begin
      addr <= to_unsigned(r, 20); cs <= '1'; rd <= '1';
      wait for 1 ns; v := rdata;
      ctick; cs <= '0'; rd <= '0';
    end procedure;
    procedure hpoke(waddr : integer; v : unsigned(15 downto 0)) is
    begin
      tb_hmem_addr <= waddr; tb_hmem_data <= v; tb_hmem_we <= '1';
      wait until rising_edge(clock162);
      tb_hmem_we <= '0';
      wait until rising_edge(clock162);
    end procedure;
    -- Write a 16-byte instruction at a HyperRAM-local byte address
    procedure instr(byteaddr : integer; op : integer; src : integer;
                    dst : integer; len : integer) is
      variable w : integer := byteaddr / 2;
      variable s, d : unsigned(31 downto 0);
    begin
      s := to_unsigned(src, 32); d := to_unsigned(dst, 32);
      hpoke(w + 0, to_unsigned(op, 16));
      hpoke(w + 1, x"0000");
      hpoke(w + 2, s(15 downto 0)); hpoke(w + 3, s(31 downto 16));
      hpoke(w + 4, d(15 downto 0)); hpoke(w + 5, d(31 downto 16));
      hpoke(w + 6, to_unsigned(len, 16)); hpoke(w + 7, x"0000");
    end procedure;
    procedure wait_done(name : string; expect_err : integer; expect_pc : integer) is
      variable v, e, p0, p1 : unsigned(7 downto 0);
    begin
      for i in 1 to 20000 loop
        peek(4, v);
        if v(0) = '0' then
          peek(5, e); peek(12, p0); peek(13, p1);
          if to_integer(e) /= expect_err then
            report name & ": error code " & integer'image(to_integer(e))
              & ", expected " & integer'image(expect_err) severity error;
          elsif to_integer(p1 & p0) /= expect_pc mod 65536 then
            report name & ": PC low = $" & to_hexstring(p1 & p0)
              & ", expected $" & to_hexstring(to_unsigned(expect_pc mod 65536, 16)) severity error;
          else
            report name & ": PASS";
          end if;
          return;
        end if;
      end loop;
      report name & ": timed out" severity failure;
    end procedure;
    variable v : unsigned(7 downto 0);
    variable bad : integer;
    variable errors : integer := 0;
    procedure check(c : boolean; name : string) is
    begin
      if c then
        report "PASS  " & name;
      else
        report "FAIL  " & name severity error;
        errors := errors + 1;
      end if;
    end procedure;
    procedure wait_ready(name : string) is
      variable r : unsigned(7 downto 0);
    begin
      for i in 1 to 5000 loop
        peek(16#17#, r);
        if r(7) = '1' then
          return;
        end if;
      end loop;
      report "FAIL  READY never came: " & name severity failure;
    end procedure;
  begin
    -- Bring the SDRAM up (debug build needs an explicit init trigger)
    wait until rising_edge(clock162);
    slow_address <= to_unsigned(64 * 1024 * 1024, 27); slow_write <= '1';
    for i in 1 to 100 loop wait until rising_edge(clock162); exit when busy = '1'; end loop;
    slow_write <= '0';
    for i in 1 to 3000 loop
      wait until rising_edge(clock162);
      exit when init_done = '1' and busy = '0';
    end loop;

    -- Load the program and data (attic RAM, local $0000-$05FF)
    for i in INIT'range loop
      hpoke(i, INIT(i));
    end loop;
    poke(16#10#, x"08"); poke(16#11#, x"88"); poke(16#12#, x"40");
    poke(8, x"00"); poke(9, x"00"); poke(10, x"00"); poke(11, x"08");
    poke(3, x"01");
    wait_done("step 2 program", 0, HALT_PC);
    bad := 0;
    for i in EXPECT'range loop
      if hmem(16#800# + i) /= EXPECT(i) then
        if bad < 6 then
          report "  word $" & to_hexstring(to_unsigned(16#1000# + 2 * i, 16)) & " = $"
            & to_hexstring(hmem(16#800# + i)) & ", emulator says $" & to_hexstring(EXPECT(i))
            severity error;
        end if;
        bad := bad + 1;
      end if;
    end loop;
    check(bad = 0, "outputs match the emulator in hardware-numerics mode (" 
          & integer'image(EXPECT'length * 2) & " bytes)");
    if errors = 0 then
      report "TB_SSNAIL_STEP2: ALL PASSED";
    else
      report "TB_SSNAIL_STEP2: " & integer'image(errors) & " FAILURES" severity error;
    end if;

    finished <= true;
    wait;
  end process;
end test;
