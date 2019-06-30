library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity hyperram is
  Port ( cpuclock : in STD_LOGIC; -- For slow devices bus interface
         clock240 : in std_logic; -- Used for fast clock for HyperRAM

         read_request : in std_logic;
         write_request : in std_logic;
         address : in unsigned(26 downto 0);
         wdata : in unsigned(7 downto 0);
         
         rdata : out unsigned(7 downto 0);
         data_ready_strobe : out std_logic := '0';
         busy : out std_logic := '0';

         hr_d : inout unsigned(7 downto 0) := (others => 'Z'); -- Data/Address
         hr_rwds : inout std_logic := 'Z'; -- RW Data strobe
--         hr_rsto : in std_logic; -- Unknown PIN
         hr_reset : out std_logic := '1'; -- Active low RESET line to HyperRAM
--         hr_int : in std_logic; -- Interrupt?
         hr_clk_n : out std_logic := '0';
         hr_clk_p : out std_logic := '1';
         hr_cs0 : out std_logic := '1';
         hr_cs1 : out std_logic := '1'
         );
end hyperram;

architecture gothic of hyperram is

  component hyper_xface is
    port (
      reset : in std_logic;
      clk : in std_logic;
      rd_req : in std_logic;
      wr_req : in std_logic;
      mem_or_reg : in std_logic;
      wr_byte_en : in std_logic_vector(3 downto 0);
      rd_num_dwords : in unsigned(5 downto 0);
      addr : in unsigned(31 downto 0);
      wr_d : in unsigned(31 downto 0);
      rd_d : out unsigned(31 downto 0);
      rd_rdy : out std_logic;
      busy : out std_logic;
      burst_wr_rdy : out std_logic;
      latency_x1 : in unsigned(7 downto 0);
      latency_x2 : in unsigned(7 downto 0);

      dram_dq_in : in unsigned(7 downto 0);
      dram_dq_out : out unsigned(7 downto 0);
      dram_dq_oe_l : out std_logic;

      dram_rwds_in : in std_logic;
      dram_rwds_out : out std_logic;
      dram_rwds_oe_l : out std_logic;

      dram_ck : out std_logic;
      dram_rst_l : out std_logic;
      dram_cs_l : out std_logic;
      sump_dbg : out unsigned(7 downto 0)
      );
  end component;
  
  type state_t is (
    Idle,
    ReadSetup,
    WriteSetup,
    HyperRAMCSStrobe,
    HyperRAMOutputCommand,
    HyperRAMLatencyWait,
    HyperRAMFinishWriting,
    HyperRAMReadWait
    );
  
  signal state : state_t := Idle;
  signal busy_internal : std_logic := '0';
  signal hr_command : unsigned(47 downto 0);
  signal ram_address : unsigned(26 downto 0);
  signal ram_wdata : unsigned(7 downto 0);
  signal ram_reading : std_logic := '1';
  
  signal countdown : integer := 0;
  signal extra_latency : std_logic := '0';

  signal next_is_data : std_logic := '1';
  signal hr_clock : std_logic := '0';

  signal data_ready_toggle : std_logic := '0';
  signal last_data_ready_toggle : std_logic := '0';

  signal request_toggle : std_logic := '0';
  signal last_request_toggle : std_logic := '0';

  signal dram_dq_in : unsigned(7 downto 0);
  signal dram_dq_out : unsigned(7 downto 0);
  signal dram_dq_oe_l : std_logic := '1';
  signal dram_rwds_in : std_logic := '1';
  signal dram_rwds_out : std_logic := '1';
  signal dram_rwds_oe_l : std_logic := '1';
  
  
begin

  hyper0: hyper_xface(

    -- Access interface
    reset => reset,
    clk => cpuclock,
    rd_req => rd_req,
    wr_req => wr_req,
    mem_or_reg => mem_or_reg,
    wr_byte_en => wr_byte_en,
    rd_num_dwords => rd_num_dwords,
    addr(26 downto 0) => address,
    addr(31 downto 27) => address_dummy,
    wr_d(31 downto 24) => wdata,
    wr_d(23 downto 16) => wdata,
    wr_d(15 downto 8) => wdata,
    wr_d(7 downto 0) => wdata,
    rd_d => rd_d,
    rd_rdy => rd_rdy,
    busy => busy_int,
    burst_wr_rdy => burst_wr_rdy,
    latency_x1 => to_unsigned(7,8),
    latency_x2 => to_unsigned(14,8),

    -- Hyperram pins
    dram_dq_in => dram_dq_in,
    dram_dq_out => dram_dq_out,
    dram_dq_oe_l => dram_dq_oe_l,
    dram_rwds_in => dram_rwds_in,
    dram_rwds_out => dram_rwds_out,
    dram_rwda_oe_l => dram_rwds_oe_l,

    dram_ck => hr_clk_p,
    dram_rst_l => hr_reset,
    dram_cs_l => hr_cs0
    );

  process is (dram_dq_in,dram_dq_out,dram_dq_oe_l,
              dram_rwds_in,dram_rwds_out,dram_rwds_oe_l)
  begin
    if dram_dq_oe_l = '0' then
      hr_d <= (others => 'Z');
      dram_dq_in <= hr_d;
    else
      hr_d <= dram_dq_out;
    end if;
    if dram_rwds_oe_l='0' then
      hr_rwds <= 'Z';
      dram_rwds_in <= hr_rwds;
    else
      hr_rwds <= dram_rwds_out;
    end if;
  end process;
  
    
  process (cpuclock,clock240) is
  begin
    if rising_edge(cpuclock) then
      report "read_request=" & std_logic'image(read_request) & ", busy_internal=" & std_logic'image(busy_internal);

      busy <= busy_internal;
      
      data_ready_strobe <= '0';
      if read_request='1' and busy_internal='0' then
        -- Begin read request
        request_toggle <= not request_toggle;
        -- Latch address
        ram_address <= address;
        ram_reading <= '1';
        null;
      elsif write_request='1' and busy_internal='0' then
        -- Begin write request
        request_toggle <= not request_toggle;
        -- Latch address and data 
        ram_address <= address;
        ram_wdata <= wdata;
        ram_reading <= '0';
        null;
      else
        -- Nothing new to do
        if data_ready_toggle /= last_data_ready_toggle then
          last_data_ready_toggle <= data_ready_toggle;
          data_ready_strobe <= '1';
        end if;
      end if;
    end if;


  end process;
end gothic;


