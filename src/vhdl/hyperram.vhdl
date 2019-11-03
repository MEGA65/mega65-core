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
         reset : in std_logic;

         latency_1x : in Unsigned(7 downto 0);
         latency_2x : in Unsigned(7 downto 0);
         
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
         hr_clk_p : out std_logic := '1';
         hr_cs0 : out std_logic := '1'
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
      latency_1x : in unsigned(7 downto 0);
      latency_2x : in unsigned(7 downto 0);

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

  signal reset_hi : std_logic;
  
  signal address_latched : unsigned(26 downto 0);
  signal wdata_latched : unsigned(7 downto 0);
  
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

  signal rd_req : std_logic := '0';
  signal wr_req : std_logic := '0';
  signal mem_or_reg : std_logic := '1';
  signal wr_byte_en : std_logic_vector(3 downto 0);
  signal rd_num_dwords : unsigned(5 downto 0) := to_unsigned(1,6);
  signal address_dummy : unsigned(4 downto 0) := (others => '0');
  signal rd_d : unsigned(31 downto 0);
  signal rd_rdy : std_logic;
  signal burst_wr_rdy : std_logic;
  signal byte_pick : unsigned(1 downto 0);
  
  type state_t is (
    Idle,
    Reading,
    Writing);
  signal state : state_t := Idle;

  signal mem_busy : std_logic;

  
begin

  hyper0: component hyper_xface
    port map(
    -- Access interface
    reset => reset_hi,  -- active high
    clk => cpuclock,
    rd_req => rd_req,
    wr_req => wr_req,
    mem_or_reg => mem_or_reg,
    wr_byte_en => wr_byte_en,
    rd_num_dwords => rd_num_dwords,
    addr(26 downto 0) => address_latched,
    addr(31 downto 27) => address_dummy,
    wr_d(31 downto 24) => wdata_latched,
    wr_d(23 downto 16) => wdata_latched,
    wr_d(15 downto 8) => wdata_latched,
    wr_d(7 downto 0) => wdata_latched,
    rd_d => rd_d,
    rd_rdy => rd_rdy,
    busy => mem_busy,
    burst_wr_rdy => burst_wr_rdy,
    latency_1x => latency_1x,
    latency_2x => latency_2x,

    -- Hyperram pins
    dram_dq_in => dram_dq_in,
    dram_dq_out => dram_dq_out,
    dram_dq_oe_l => dram_dq_oe_l,
    dram_rwds_in => dram_rwds_in,
    dram_rwds_out => dram_rwds_out,
    dram_rwds_oe_l => dram_rwds_oe_l,

    dram_ck => hr_clk_p,
    dram_rst_l => hr_reset,
    dram_cs_l => hr_cs0
    );

  reset_hi <= not reset;
  
  process (dram_dq_in,dram_dq_out,dram_dq_oe_l,
           dram_rwds_in,dram_rwds_out,dram_rwds_oe_l) is
  begin
    -- Control direction of bi-directional signals
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
      data_ready_strobe <= '0';

      case state is
        when Idle =>
          case address(1 downto 0) is
            when "00" => wr_byte_en <= "0001";
            when "01" => wr_byte_en <= "0010";
            when "10" => wr_byte_en <= "0100";
            when "11" => wr_byte_en <= "1000";
            when others => null;
          end case;
          byte_pick <= address(1 downto 0);
          rd_req <= '0';
          wr_req <= '0';
          if mem_busy='1' then
            null;
          elsif read_request='1' then
            address_latched <= address;
            byte_pick <= address(1 downto 0);
            state <= Reading;
            rd_req <= '1';
            busy <= '1';
          elsif write_request='1' then
            address_latched <= address;
            wdata_latched <= wdata;
            busy <= '1';
            wr_req <= '1';
          else
            busy <= '0';
          end if;
        when Writing =>
          -- We just allow one cycle for busy to go high, then writing
          -- happens in the background
          state <= Idle;
        when Reading =>
          if rd_rdy='1' then
            -- We have the read data
            data_ready_strobe <= '1';
            case byte_pick is
              when "00" => rdata <= rd_d(7 downto 0);
              when "01" => rdata <= rd_d(15 downto 8);
              when "10" => rdata <= rd_d(23 downto 16);
              when "11" => rdata <= rd_d(31 downto 24);
              when others => null;
            end case;
            state <= Idle;
          end if;
        when others =>
          state <= Idle;
      end case;
      
    end if;


  end process;
end gothic;


