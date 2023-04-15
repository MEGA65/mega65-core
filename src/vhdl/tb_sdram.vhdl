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
  signal data_ready_strobe : std_logic := '0';
  signal busy : std_logic;
  signal current_cache_line : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic := '0';
  signal expansionram_current_cache_line_next_toggle : std_logic := '0';
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
        data_ready_strobe => data_ready_strobe,
        busy => busy,
        current_cache_line => current_cache_line,
        current_cache_line_address => current_cache_line_address,
        current_cache_line_valid => current_cache_line_valid,
        expansionram_current_cache_line_next_toggle => expansionram_current_cache_line_next_toggle,
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
    procedure clock_tick is
    begin
      clock41 <= '0';
      pixelclock <= '0';
      clock162 <= '0'; wait for 6.173 ns;
      clock162 <= '1'; wait for 6.173 ns;

      pixelclock <= '1';
      clock162 <= '0'; wait for 6.173 ns;
      clock162 <= '1'; wait for 6.173 ns;

      clock41 <= '1';
      pixelclock <= '0';
      clock162 <= '0'; wait for 6.173 ns;
      clock162 <= '1'; wait for 6.173 ns;

      pixelclock <= '1';
      clock162 <= '0'; wait for 6.173 ns;
      clock162 <= '1'; wait for 6.173 ns;      
    end procedure;
    
  begin
    test_runner_setup(runner, runner_cfg);    
    
    while test_suite loop

      if run("SDRAM starts busy, and becomes ready") then
        report "Make sure busy stays asserted for ~16,200 cycles";
        enforce_100usec_init <= true;
        for i in 1 to (16_200/4) loop
          clock_tick;
          if busy='0' then
            assert false report "SDRAM controller busy flag should start set, but was clear after " & integer'image(i) & " cycles.";
          end if;
        end loop;
        report "Make sure busy clears soon after 16,200 cycles";
        for i in 1 to (100*2)/4 loop
          clock_tick;
        end loop;
        if busy='1' then
          assert false report "SDRAM controller does not come ready.";
        end if;
        if init_sequence_done='0' then
          assert false report "SDRAM model did not see complete init sequence";
        end if;
      elsif run("Write and read back single bytes") then
        assert false report "not implemented";

      end if;
    end loop;    
    test_runner_cleanup(runner);
  end process;
    
end architecture;
