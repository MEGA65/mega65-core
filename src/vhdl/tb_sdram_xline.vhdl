-- The SDRAM controller's exported cache line under next/prev (the CPU's
-- expansion RAM line, x_* in sdram_controller.vhdl), which tb_tbdr never
-- drives: CPU writes a pattern, reads one byte, then walks the exported line
-- forward and back - over lines the controller has cached (look-up hits) and
-- lines it must fetch (misses) - and rewrites a cached line in between, which
-- the next export must show.  Every exported line is checked byte for byte.
-- Run (nvc, from an empty directory; src = src/vhdl):
--   nvc --std=2008 -a --relaxed $src/debugtools.vhdl $src/cputypes.vhdl \
--       $src/lump_queue.vhdl $src/sdram_banks_model.vhdl \
--       $src/sdram_controller.vhdl $src/tb_sdram_xline.vhdl
--   nvc --std=2008 -H 2g -e tb_sdram_xline
--   nvc --std=2008 -H 2g -r tb_sdram_xline --ieee-warnings=off
-- Expected: TB_SDRAM_XLINE: ALL PASSED (91 lines)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cputypes.all;

entity tb_sdram_xline is
end entity;

architecture test of tb_sdram_xline is
  signal pixelclock, clock162 : std_logic := '0';
  signal finished : boolean := false;

  signal s_read, s_write, s_busy, s_toggle, s_line_valid : std_logic := '0';
  signal s_address : unsigned(26 downto 0) := (others => '0');
  signal s_wdata, s_rdata, s_rdata_hi : unsigned(7 downto 0) := (others => '0');
  signal s_line : cache_row_t := (others => (others => '0'));
  signal s_line_addr : unsigned(26 downto 3) := (others => '0');
  signal t_next, t_prev : std_logic := '0';

  signal sdram_a : unsigned(12 downto 0);
  signal sdram_ba : unsigned(1 downto 0);
  signal sdram_dq : unsigned(15 downto 0);
  signal sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n,
         sdram_dqml, sdram_dqmh, sd_init_done : std_logic;

  constant BASE : integer := 16#0100000#;       -- byte address of line 0
  constant NLINES : integer := 40;              -- more lines than the cache holds

  -- the byte at a byte offset from BASE; "gen" = which rewrite
  function pat(i, gen : integer) return unsigned is
  begin
    return to_unsigned((i * 7 + i / 256 + gen * 101) mod 256, 8);
  end function;
begin
  process begin
    while not finished loop
      clock162 <= '1'; wait for 3.077 ns; clock162 <= '0'; wait for 3.077 ns;
    end loop;
    wait;
  end process;
  process begin
    while not finished loop
      pixelclock <= '1'; wait for 6.154 ns; pixelclock <= '0'; wait for 6.154 ns;
    end loop;
    wait;
  end process;

  chip : entity work.sdram_banks_model
    port map (clk => clock162, cke => sdram_cke, cs_n => sdram_cs_n,
              ras_n => sdram_ras_n, cas_n => sdram_cas_n, we_n => sdram_we_n,
              ba => sdram_ba, a => sdram_a, dqml => sdram_dqml, dqmh => sdram_dqmh,
              dq => sdram_dq, init_done => sd_init_done);

  ctrl : entity work.sdram_controller
    generic map (in_simulation => true)
    port map (
      pixelclock => pixelclock, clock162 => clock162, clock162r => clock162,
      identical_clocks => '1',
      enforce_100us_delay => false,
      request_counter => open,
      read_request => s_read, write_request => s_write,
      address => s_address, wdata => s_wdata,
      rdata_hi => s_rdata_hi, rdata => s_rdata,
      data_ready_toggle => s_toggle, busy => s_busy,
      current_cache_line => s_line,
      current_cache_line_address => s_line_addr,
      current_cache_line_valid => s_line_valid,
      expansionram_current_cache_line_next_toggle => t_next,
      expansionram_current_cache_line_prev_toggle => t_prev,
      sdram_a => sdram_a, sdram_ba => sdram_ba, sdram_dq => sdram_dq,
      sdram_cke => sdram_cke, sdram_cs_n => sdram_cs_n,
      sdram_ras_n => sdram_ras_n, sdram_cas_n => sdram_cas_n,
      sdram_we_n => sdram_we_n, sdram_dqml => sdram_dqml, sdram_dqmh => sdram_dqmh);

  process
    variable errors, checks : integer := 0;
    variable gen : integer_vector(0 to NLINES - 1) := (others => 0);
    variable cur : integer;
    variable v : unsigned(7 downto 0);

    procedure cpu_write(a : integer; d : unsigned(7 downto 0)) is
    begin
      wait until rising_edge(pixelclock) and s_busy = '0';
      s_address <= to_unsigned(a, 27); s_wdata <= d; s_write <= '1';
      wait until rising_edge(pixelclock);
      s_write <= '0';
      for i in 1 to 4 loop wait until rising_edge(pixelclock); end loop;
    end procedure;

    procedure cpu_read(a : integer; d : out unsigned(7 downto 0)) is
      variable t : std_logic;
    begin
      wait until rising_edge(pixelclock) and s_busy = '0';
      t := s_toggle;
      s_address <= to_unsigned(a, 27); s_read <= '1';
      wait until rising_edge(pixelclock);
      s_read <= '0';
      for i in 1 to 2000 loop
        wait until rising_edge(pixelclock);
        exit when s_toggle /= t;
      end loop;
      wait until rising_edge(pixelclock);
      d := s_rdata;
    end procedure;

    -- wait for the exported line to be line l, then check its 8 bytes
    procedure check_line(l : integer; what : string) is
      variable want : unsigned(26 downto 3);
      variable ok : boolean := false;
    begin
      want := to_unsigned((BASE + 8 * l) / 8, 24);
      for i in 1 to 3000 loop
        wait until rising_edge(pixelclock);
        if s_line_valid = '1' and s_line_addr = want then ok := true; exit; end if;
      end loop;
      checks := checks + 1;
      if not ok then
        errors := errors + 1;
        report "FAIL " & what & ": line " & integer'image(l) & " never exported" severity error;
        return;
      end if;
      for b in 0 to 7 loop
        if s_line(b) /= pat(8 * l + b, gen(l)) then
          errors := errors + 1;
          report "FAIL " & what & ": line " & integer'image(l) & " byte " & integer'image(b)
            & " = " & integer'image(to_integer(s_line(b))) & ", wanted "
            & integer'image(to_integer(pat(8 * l + b, gen(l)))) severity error;
          exit;
        end if;
      end loop;
    end procedure;

    procedure step(up : boolean; what : string) is
    begin
      wait until rising_edge(pixelclock);
      if up then t_next <= not t_next; cur := cur + 1;
      else t_prev <= not t_prev; cur := cur - 1; end if;
      check_line(cur, what);
    end procedure;
  begin
    wait until sd_init_done = '1';
    wait until rising_edge(pixelclock) and s_busy = '0';
    for i in 1 to 200 loop wait until rising_edge(pixelclock); end loop;

    for i in 0 to 8 * NLINES - 1 loop cpu_write(BASE + i, pat(i, 0)); end loop;
    for i in 1 to 200 loop wait until rising_edge(pixelclock); end loop;

    -- 1. a read exports its line; walk forward over fresh lines (misses)
    cpu_read(BASE + 8 * 4 + 3, v);
    if v /= pat(8 * 4 + 3, 0) then
      errors := errors + 1; report "FAIL read byte" severity error;
    end if;
    cur := 4;
    check_line(4, "read");
    for k in 1 to 12 loop step(true, "next (miss)"); end loop;        -- -> 16
    -- 2. back over the lines just fetched (look-up hits)
    for k in 1 to 10 loop step(false, "prev (hit)"); end loop;        -- -> 6
    -- 3. rewrite cached lines 7 and 8, then walk over them
    for i in 0 to 15 loop cpu_write(BASE + 8 * 7 + i, pat(8 * 7 + i, 1)); end loop;
    gen(7) := 1; gen(8) := 1;
    for i in 1 to 100 loop wait until rising_edge(pixelclock); end loop;
    for k in 1 to 4 loop step(true, "next after write"); end loop;    -- -> 10
    for k in 1 to 4 loop step(false, "prev after write"); end loop;   -- -> 6
    -- 4. fast steps, back to back
    for k in 1 to 30 loop
      wait until rising_edge(pixelclock);
      t_next <= not t_next; cur := cur + 1;
      check_line(cur, "fast next");
    end loop;                                                          -- -> 36
    for k in 1 to 30 loop
      wait until rising_edge(pixelclock);
      t_prev <= not t_prev; cur := cur - 1;
      check_line(cur, "fast prev");
    end loop;                                                          -- -> 6

    if errors = 0 then
      report "TB_SDRAM_XLINE: ALL PASSED (" & integer'image(checks) & " lines)";
    else
      report "TB_SDRAM_XLINE: " & integer'image(errors) & " FAILURES" severity error;
    end if;
    finished <= true;
    wait;
  end process;
end test;
