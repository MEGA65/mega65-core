library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_sdram_controller is
  generic (runner_cfg : string);
end entity;

architecture test_arch of tb_sdram_controller is

  constant SDRAM_BANK_WIDTH : integer := 2;
  constant SDRAM_ROW_WIDTH : integer := 13;
  constant SDRAM_COL_WIDTH : integer := 10;
  constant SDRAM_DATA_WIDTH : integer := 16;
  constant SDRAM_ADDR_WIDTH : integer := sdram_row_width + sdram_col_width + sdram_bank_width;

  signal pixelclock : std_logic := '0';
  signal clock41 : std_logic := '0';
  signal clock162 : std_logic := '0';
  signal slow_read : std_logic;
  signal slow_write : std_logic;
  signal slow_address : unsigned(26 downto 0);
  signal slow_wdata : unsigned(7 downto 0);
  signal slow_wdata_hi : unsigned(7 downto 0) := x"00";
  signal slow_wen_hi : std_logic := '0';
  signal slow_wen_lo : std_logic := '1';
  signal slow_rdata_hi : unsigned(7 downto 0);
  signal slow_rdata_16en : std_logic := '0';
  signal slow_rdata : unsigned(7 downto 0);
  signal data_ready_toggle : std_logic := '0';
  signal last_data_ready_toggle : std_logic := '0';
  signal busy : std_logic;
  signal current_cache_line : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic := '0';
  signal expansionram_current_cache_line_next_toggle : std_logic := '0';
  signal expansionram_current_cache_line_prev_toggle : std_logic := '0';
  signal viciv_addr : unsigned(18 downto 3) := (others => '0');
  signal viciv_request_toggle : std_logic := '0';
  signal viciv_data_out : unsigned(7 downto 0) := x"00";
  signal viciv_data_strobe : std_logic := '0';

  -- SDRAM chip pins
  signal sdram_a : unsigned(SDRAM_ROW_WIDTH-1 downto 0);
  signal sdram_ba : unsigned(SDRAM_BANK_WIDTH-1 downto 0);
  signal sdram_dq : unsigned(SDRAM_DATA_WIDTH-1 downto 0);
  signal sdram_cke : std_logic;
  signal sdram_cs_n : std_logic;
  signal sdram_ras_n : std_logic;
  signal sdram_cas_n : std_logic;
  signal sdram_we_n : std_logic;
  signal sdram_dqml : std_logic;
  signal sdram_dqmh : std_logic;
  signal ack : std_logic;
  signal valid : std_logic;

  signal req : std_logic;
  signal reset : std_logic;

  signal enforce_100usec_init : boolean := false;
  signal init_sequence_done : std_logic;

  signal data_seen : std_logic := '0';
  signal data_val : unsigned(15 downto 0);

begin

  sdram_model0: entity work.is42s16320f_model
  generic map (
    clock_frequency => 162_000_000
  )
  port map (
    clk => clock162,
    reset => reset,
    addr => sdram_a,
    ba => sdram_ba,
    dq => sdram_dq,
    clk_en => sdram_cke,
    cs => sdram_cs_n,
    ras => sdram_ras_n,
    cas => sdram_cas_n,
    we => sdram_we_n,
    ldqm => sdram_dqml,
    udqm => sdram_dqmh,
    enforce_100usec_init => enforce_100usec_init,
    init_sequence_done => init_sequence_done
  );

  sdram_controller0 : entity work.sdram_controller
    generic map (
        in_simulation => false
    )
    port map (
        pixelclock => pixelclock,
        clock162 => clock162,

        enforce_100us_delay => enforce_100usec_init,

        request_counter => open,
        read_request => slow_read,
        write_request => slow_write,
        address => slow_address,
        wdata => slow_wdata,
        wdata_hi => slow_wdata_hi,
        wen_hi => slow_wen_hi,
        wen_lo => slow_wen_lo,
        rdata_hi => slow_rdata_hi,
        rdata_16en => slow_rdata_16en,
        rdata => slow_rdata,
        data_ready_toggle => data_ready_toggle,
        busy => busy,
        current_cache_line => current_cache_line,
        current_cache_line_address => current_cache_line_address,
        current_cache_line_valid => current_cache_line_valid,
        expansionram_current_cache_line_next_toggle => expansionram_current_cache_line_next_toggle,
        expansionram_current_cache_line_prev_toggle => expansionram_current_cache_line_prev_toggle,
        viciv_addr => viciv_addr,
        viciv_request_toggle => viciv_request_toggle,
        viciv_data_out => viciv_data_out,
        viciv_data_strobe => viciv_data_strobe,

        sdram_a => sdram_a,
        sdram_ba => sdram_ba,
        sdram_dq => sdram_dq,
        sdram_cke => sdram_cke,
        sdram_cs_n => sdram_cs_n,
        sdram_ras_n => sdram_ras_n,
        sdram_cas_n => sdram_cas_n,
        sdram_we_n => sdram_we_n,
        sdram_dqml => sdram_dqml,
        sdram_dqmh => sdram_dqmh

    );


  main : process

    variable v : unsigned(15 downto 0);

    procedure check_sdram_read_strobe is
    begin
      if data_ready_toggle /= last_data_ready_toggle then
        last_data_ready_toggle <= data_ready_toggle;
        report "SDRAM data ready strobe seen: read value $" & to_hexstring(slow_rdata_hi) & to_hexstring(slow_rdata);
        data_seen <= '1';
        data_val(7 downto 0) <= slow_rdata;
        data_val(15 downto 8) <= slow_rdata_hi;
      end if;
    end procedure;

    procedure clock_tick is
    begin
      clock162 <= not clock162;
      if clock162 = '1' then
        pixelclock <= not pixelclock;
        if pixelclock='1' then
          check_sdram_read_strobe;
          clock41 <= not clock41;
        end if;
      end if;
      wait for 6.173 ns;

    end procedure;

    procedure sdram_write( addr : integer; val : unsigned(7 downto 0)) is
    begin
      if busy='1' then
        assert false report "SDRAM controller is busy";
      end if;
      report "SDRAMWRITE: $" & to_hexstring(to_unsigned(addr,28)) & " <- $" & to_hexstring(val);
      slow_read <= '0'; slow_write <= '1';
      slow_address <= to_unsigned(addr,27);
      slow_wdata <= val;
      slow_wdata_hi <= val;
      slow_wen_lo <= '0'; slow_wen_hi <= '0';
      if to_integer(to_unsigned(addr,1)) = 1 then
        slow_wen_hi <= '1';
      else
        slow_wen_lo <= '1';
      end if;
      clock_tick;
      for i in 1 to 100 loop
        if busy ='1' then
          -- Clear any read or write request so that it doesn't get
          -- double scheduled
          slow_read <= '0'; slow_write <= '0';
          exit;
        end if;
        clock_tick;
      end loop;

      for i in 1 to 100 loop
        if busy='0' then
          report "SDRAMWRITE: BUSY released after " & integer'image(i) & " cycles.";
          return;
        end if;
        clock_tick;
      end loop;
      assert false report "SDRAMWRITE: SDRAM BUSY flag did not clear after writing";

    end procedure;

    procedure sdram_read( addr : integer; expected_val : unsigned(15 downto 0)) is
    begin

      report "SDRAM_READ: Starting test to read from $" & to_hexstring(to_unsigned(addr,28)) & ", expecting value $" & to_hexstring(expected_val);

      if busy='1' then
        assert false report "Attempted to read from SDRAM while BUSY";
      end if;

      report "SDRAMREAD: $" & to_hexstring(to_unsigned(addr,28)) & " (looking for $" & to_hexstring(expected_val) & ").";
      slow_address <= to_unsigned(addr,27);
      slow_read <= '1'; slow_write <= '0';
      slow_rdata_16en <= '1';

      for i in 1 to 100 loop
        if busy ='1' then
          -- Clear any read or write request so that it doesn't get
          -- double scheduled
          slow_read <= '0'; slow_write <= '0';
          exit;
        end if;
        clock_tick;
      end loop;
      for i in 1 to 1600 loop
        if data_seen='1' then
          if data_val /= expected_val then
            assert false report "SDRAM: Read $" & to_hexstring(data_val) & ", but expected $" & to_hexstring(expected_val);
          else
            report "SDRAM: Read correct value. Now waiting for data strobe to release";
          end if;

          for j in 1 to 32 loop
            data_seen <= '0';
            clock_tick;
            if data_seen='0' then
              report "SDRAM: data strobe cleared after " & integer'image(j) & " cycles.";
              report "SDRAM_READ: Read complete.";
              return;
            end if;
          end loop;
          assert false report "SDRAM: data strobe did not clear after 4 CPU cycles";

        end if;
        clock_tick;
      end loop;
      assert false report "SDRAM: Failed to read value after 100 cycles.";
    end procedure;

    procedure wait_for_sdram_ready is
    begin
      clock_tick;
      for i in 1 to 1000 loop
        clock_tick;
        if busy='0' then
          report "SDRAM ready after " & integer'image(i) & " cycles.";
          return;
        end if;
      end loop;
      assert false report "SDRAM did not become ready";
    end procedure;

    procedure cache_line_check(addr : unsigned(27 downto 0); d : unsigned(63 downto 0)) is
    begin
      if current_cache_line_valid = '0' then
        assert false report "Cache line is not marked valid.";
      end if;
      if addr(2 downto 0) /= "000" then
        assert false report "TEST DEFINITION ERROR: Cache check addresses must be cache-line aligned";
      end if;
      if current_cache_line_address /= addr(26 downto 3) then
        assert false report "Cache line address was $" & to_hexstring(current_cache_line_address) & ", but expected $" & to_hexstring(addr);
      end if;
      for i in 0 to 7 loop
        if d((7-i)*8+7 downto (7-i)*8) /= current_cache_line(i) then
          report "Current cache line is $" & to_hexstring(current_cache_line_address) & " : "
            & to_hexstring(current_cache_line(0)) & " "
            & to_hexstring(current_cache_line(1)) & " "
            & to_hexstring(current_cache_line(2)) & " "
            & to_hexstring(current_cache_line(3)) & " "
            & to_hexstring(current_cache_line(4)) & " "
            & to_hexstring(current_cache_line(5)) & " "
            & to_hexstring(current_cache_line(6)) & " "
            & to_hexstring(current_cache_line(7));
          assert false report "Cache line byte " & integer'image(i) & " = $" & to_hexstring(current_cache_line(i))
            &", but expected $" & to_hexstring(d((7-i)*8+7 downto (7-i)*8));
        end if;
      end loop;
    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      if run("SDRAM starts busy, and becomes ready") then
        report "Make sure busy stays asserted for ~16,200 cycles";
        enforce_100usec_init <= true;
        for i in 1 to 16200*2 loop
          clock_tick;
          if busy='0' then
            assert false report "SDRAM controller busy flag should start set, but was clear after " & integer'image(i) & " cycles.";
          end if;
        end loop;
        report "Make sure busy clears soon after 16,200 cycles";
        for i in 1 to 16200*2 loop
          clock_tick;
        end loop;
        if busy='1' then
          assert false report "SDRAM controller does not come ready.";
        end if;
        if init_sequence_done='0' then
          assert false report "SDRAM model did not see complete init sequence";
        end if;
      elsif run("Can read config registers") then
        wait_for_sdram_ready;
        -- Read "SDRAM" signature
        sdram_read(64*1024*1024+0,x"5353");
        sdram_read(64*1024*1024+1,x"4444");
        sdram_read(64*1024*1024+2,x"5252");
        sdram_read(64*1024*1024+3,x"4141");
        sdram_read(64*1024*1024+4,x"4d4d");
        -- Read jumber of read and write jobs
        sdram_read(64*1024*1024+5,x"0000");
        sdram_read(64*1024*1024+6,x"0000");
        -- Read unmapped register
        sdram_read(64*1024*1024+255,x"4242");
      elsif run("Write and read back single bytes") then
        wait_for_sdram_ready;
        sdram_write(0,x"12");
        sdram_write(1,x"34");
        sdram_write(2,x"56");
        sdram_write(3,x"78");
        sdram_write(4,x"9a");
        sdram_write(5,x"bc");
        sdram_write(6,x"de");
        sdram_write(7,x"f0");
        sdram_read(0,x"3412");
        sdram_read(2,x"7856");
        sdram_read(4,x"bc9a");
        sdram_read(6,x"f0de");
      elsif run("Write and read back single bytes from different rows") then
        wait_for_sdram_ready;
        sdram_write(0,x"12");
        sdram_write(1,x"34");
        sdram_write(2,x"56");
        sdram_write(3,x"78");
        sdram_write(4,x"9a");
        sdram_write(5,x"bc");
        sdram_write(6,x"de");
        sdram_write(7,x"f0");

        sdram_write(65536+0,x"80");
        sdram_write(65536+1,x"81");
        sdram_write(65536+2,x"82");
        sdram_write(65536+3,x"83");
        sdram_write(65536+4,x"84");
        sdram_write(65536+5,x"85");
        sdram_write(65536+6,x"86");
        sdram_write(65536+7,x"87");

        sdram_read(0,x"3412");
        sdram_read(2,x"7856");
        sdram_read(4,x"bc9a");
        sdram_read(6,x"f0de");

        sdram_read(65536+0,x"8180");
        sdram_read(65536+2,x"8382");
        sdram_read(65536+4,x"8584");
        sdram_read(65536+6,x"8786");

      elsif run("Cache line correctly populated") then
        wait_for_sdram_ready;

        sdram_write(0,x"00");
        sdram_write(1,x"01");
        sdram_write(2,x"02");
        sdram_write(3,x"03");
        sdram_write(4,x"04");
        sdram_write(5,x"05");
        sdram_write(6,x"06");
        sdram_write(7,x"07");

        sdram_write(8,x"88");
        sdram_write(9,x"89");
        sdram_write(10,x"8a");
        sdram_write(11,x"8b");
        sdram_write(12,x"8c");
        sdram_write(13,x"8d");
        sdram_write(14,x"8e");
        sdram_write(15,x"8f");

        sdram_read(0,x"0100");
        cache_line_check(x"8000000",x"0001020304050607");
        sdram_read(8,x"8988");
        cache_line_check(x"8000008",x"88898a8b8c8d8e8f");

      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;

end architecture;
