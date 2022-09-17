----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    22:30:37 12/10/2013 
-- Design Name: 
-- Module Name:    container - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
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

entity container is
  Port ( CLK_IN : STD_LOGIC;         
--         btnCpuReset : in  STD_LOGIC;
--         irq : in  STD_LOGIC;
--         nmi : in  STD_LOGIC;

         fpga_pins : out std_logic_vector(1 to 100) := (others => '1');
         
         ----------------------------------------------------------------------
         -- HyperRAM as expansion RAM
         ----------------------------------------------------------------------
         hr_d : inout unsigned(7 downto 0) := (others => '1');
         hr_rwds : inout std_logic := '1';
         hr_reset : out std_logic := '1';
         hr_clk_n : out std_logic := '1';
         hr_clk_p : out std_logic := '1';
         hr_cs0 : out std_logic := '1';
         hr_cs1 : out std_logic := '1';
         
         ----------------------------------------------------------------------
         -- Flash RAM for holding config
         ----------------------------------------------------------------------
--         QspiSCK : out std_logic := '1';
         QspiDB : inout std_logic_vector(3 downto 0) := (others => 'Z');
         QspiCSn : out std_logic := '1';
         
         ----------------------------------------------------------------------
         -- Debug interfaces on TE0725
         ----------------------------------------------------------------------
         led : inout std_logic := '1';

         ----------------------------------------------------------------------
         -- UART monitor interface
         ----------------------------------------------------------------------
         monitor_tx : out std_logic := '1';
         monitor_rx : in std_logic
         
         );
end container;

architecture Behavioral of container is
  
  component fpgatemp is
    Generic ( DELAY_CYCLES : natural := 480 ); -- 10us @ 48 Mhz
    Port ( clk : in  STD_LOGIC;
           rst : in  STD_LOGIC;
           temp : out  STD_LOGIC_VECTOR (11 downto 0));
  end component;

  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal restore_key : std_logic := '1';
  signal reset_out : std_logic := '1';
  signal cpu_game : std_logic := '1';
  signal cpu_exrom : std_logic := '1';
  
  
  signal pixelclock : std_logic;
  signal cpuclock : std_logic;
  signal clock240 : std_logic;
  signal clock120 : std_logic;
  signal clock100 : std_logic;
  signal ethclock : std_logic;
  signal clock200 : std_logic;

  signal i2s_master_clk_int : std_logic := '0';
  signal i2s_master_clk : std_logic := '0';
  signal i2s_sync : std_logic := '0';
  signal i2s_sync_int : std_logic := '0';
  signal sample : unsigned(15 downto 0) := x"0001";
  signal table_offset : integer range 0 to 255 := 0;
  signal table_dir : std_logic := '1';
  signal table_neg : std_logic := '0';
  signal divisor : integer := 0;
  constant divisor_max : integer := 40000000/(256*4)/1;  -- proceed it really slowly

  constant max_table_value: integer := 255;
  subtype table_value_type is integer range 0 to 255;

  constant max_table_index: integer := 255;
  subtype table_index_type is integer range 0 to 255;

  subtype sine_vector_type is std_logic_vector( 8 downto 0 );

begin
  
  gen_pin1:
  for i in 1 to 100 generate
      pin1: entity work.pin_id
        port map (
          clock => pixelclock,
          pin_number => to_unsigned(i,8),
          pin => fpga_pins(i)
          );
  end generate gen_pin1;
  
  dotclock1: entity work.clocking
    port map ( clk_in => CLK_IN,
               clock81p => pixelclock, -- 80MHz
               clock41 => cpuclock -- 40MHz
               );
      
  
end Behavioral;
