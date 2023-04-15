library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_sdram_controller is
  generic (runner_cfg : string);
end entity;

architecture test_arch of tb_sdram_controller is

signal pixelclock : std_logic := '0';
  signal clock163 : std_logic := '0';
  signal request_counter : std_logic;
  signal read_request : std_logic;
  signal write_request : std_logic;
  signal address : unsigned(26 downto 0);
  signal wdata : unsigned(7 downto 0);
  signal wdata_hi : unsigned(7 downto 0) := x"00";
  signal wen_hi : std_logic := '0';
  signal wen_lo : std_logic := '1';
  signal rdata_hi : unsigned(7 downto 0);
  signal rdata_16en : std_logic := '0';
  signal rdata : unsigned(7 downto 0);
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
  signal sdram_address : unsigned(23 downto 0);
  signal sdram_wdata : std_logic_vector(15 downto 0);
  signal sdram_we : std_logic;
  signal sdram_req : std_logic;
  signal sdram_ack : std_logic;
  signal sdram_valid : std_logic;
  signal sdram_rdata : std_logic_vector(15 downto 0);

signal sdram_a : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
signal sdram_ba : unsigned(SDRAM_BANK_WIDTH-1 downto 0);
signal sdram_dq : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
signal sdram_cke : std_logic;
signal sdram_cs_n : std_logic;
signal sdram_ras_n : std_logic;
signal sdram_cas_n : std_logic;
signal sdram_we_n : std_logic;
signal sdram_dqml : std_logic;
signal sdram_dqmh : std_logic;
signal ack : std_logic;
signal valid : std_logic;

begin

  sdram_model0: entity is42s16320f_model
  generic map (
    CLK_FREQ => 50_000_000.0,
    SDRAM_COL_WIDTH => 9,
    SDRAM_ROW_WIDTH => 13,
    SDRAM_BANK_WIDTH => 2,
    SDRAM_DATA_WIDTH => 16
  )
  port map (
    clk => clk,
    reset => reset,
    addr_in => addr,
    data => data,
    we_in => we,
    req_in => req,
    ack_out => ack,
    valid_out => valid,
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

  
  sdram_interface0 : entity work.sdram
  generic map (
    CLK_FREQ => 162_000_000.0,
    ADDR_WIDTH => 24,
    DATA_WIDTH => 16,
    SDRAM_ADDR_WIDTH => 13,
    SDRAM_DATA_WIDTH => 16,
    SDRAM_COL_WIDTH => 9,
    SDRAM_ROW_WIDTH => 13,
    SDRAM_BANK_WIDTH => 2,
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
    clk => clk,
    addr => sdram_address,
    data => sdram_wdata,
    we => we,
    req => req,
    ack => ack,
    valid => valid,
    q => sdram_rdata,
    
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
        clock163 => clock163,
        request_counter => open,
        read_request => read_request,
        write_request => write_request,
        address => address,
        wdata => wdata,
        wdata_hi => wdata_hi,
        wen_hi => wen_hi,
        wen_lo => wen_lo,
        rdata_hi => rdata_hi,
        rdata_16en => rdata_16en,
        rdata => rdata,
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
        sdram_address => sdram_address,
        sdram_wdata => sdram_wdata,
        sdram_we => sdram_we,
        sdram_req => sdram_req,
        sdram_ack => sdram_ack,
        sdram_valid => sdram_valid,
        sdram_rdata => sdram_rdata
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
