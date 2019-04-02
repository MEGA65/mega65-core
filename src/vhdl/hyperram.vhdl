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
         hr_rsto : in std_logic; -- Unknown PIN
         hr_reset : out std_logic := '1'; -- Active low RESET line to HyperRAM
         hr_int : in std_logic; -- Interrupt?
         hr_clk_n : out std_logic := '0';
         hr_clk_p : out std_logic := '1';
         hr_cs : out std_logic := '0'
         );
end hyperram;

architecture gothic of hyperram is

  type state_t is (
    Idle,
    ReadSetup,
    WriteSetup
    );
  
  signal state : state_t := Idle;
  signal busy_internal : std_logic := '0';
  signal hr_command : std_logic_vector(47 downto 0);
  signal ram_address : unsigned(22 downto 0);
  signal ram_wdata : unsigned(7 downto 0);
  
begin
  process (cpuclock,clock240) is
  begin
    if rising_edge(cpuclock) then
      if read_request='1' and busy_internal='0' then
        -- Begin read request
        state <= ReadSetup;
        -- Latch address
        ram_address <= address;
        null;
      elsif write_request='1' and busy_internal='0' then
        -- Begin write request
        state <= WriteSetup;
        -- Latch address and data 
        ram_address <= address;
        ram_wdata <= wdata;
        null;
      else
        -- Nothing new to do
        null;
      end if;
    end if;

    if rising_edge(clock240) then
      -- HyperRAM state machine
      case state is
        when Idle =>
          null;
        when others =>
          state <= Idle;
      end case;      
    end if;
        
    end if;
  end process;
end gothic;

         
