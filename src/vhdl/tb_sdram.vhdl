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
  signal busy : std_logic := '0';
  signal current_cache_line : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic := '0';
  signal expansionram_current_cache_line_next_toggle : std_logic := '0';
  signal viciv_addr : unsigned(18 downto 3) := (others => '0');
  signal viciv_request_toggle : std_logic := '0';
  signal viciv_data_out : unsigned(7 downto 0) := x"00";
  signal viciv_data_strobe : std_logic := '0';

  -- Interface between M65 SDRAM controller and SDRAM chip
  signal if_address : unsigned(23 downto 0);
  signal if_wdata : std_logic_vector(15 downto 0);
  signal if_we : std_logic;
  signal if_req : std_logic;
  signal if_ack : std_logic;
  signal if_valid : std_logic;
  signal if_rdata : std_logic_vector(15 downto 0);

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
    enforce_100usec_init => enforce_100usec_init
  );

  
  sdram_interface0 : entity work.sdram
  generic map (
    CLK_FREQ => 162_000_000.0,
    ADDR_WIDTH => sdram_addr_width,
    DATA_WIDTH => sdram_data_width,
    SDRAM_ADDR_WIDTH => sdram_addr_width,
    SDRAM_DATA_WIDTH => sdram_data_width,
    SDRAM_COL_WIDTH => sdram_col_width,
    SDRAM_ROW_WIDTH => sdram_row_width,
    SDRAM_BANK_WIDTH => sdram_bank_width,
    CAS_LATENCY => 2,
    BURST_LENGTH => 1,
    T_DESL => 200000.0,
    T_MRD => 12.0,
    T_RC => 60.0,
    T_RCD => 18.0,
    T_RP => 18.0,
    T_WR => 12.0,
    T_REFI => 7800.0
  )
  port map (
    reset => reset,
    clk => clock162,
    addr => if_address,
    data => if_wdata,
    we => if_we,
    req => if_req,
    ack => if_ack,
    valid => if_valid,
    q => if_rdata,
    
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

  sdram_controller0 : entity work.sdram_controller
    generic map (
        in_simulation => false
    )
    port map (
        pixelclock => pixelclock,
        clock162 => clock162,
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

        sdram_address => if_address,
        sdram_wdata => if_wdata,
        sdram_we => if_we,
        sdram_req => if_req,
        sdram_ack => if_ack,
        sdram_valid => if_valid,
        sdram_rdata => if_rdata
    );
  
  main : process
  begin
    test_runner_setup(runner, runner_cfg);    
    
    while test_suite loop

      if run("Dummy test") then
      end if;
    end loop;    
  end process;
    
end architecture;
