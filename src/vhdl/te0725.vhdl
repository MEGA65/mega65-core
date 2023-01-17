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
         led : inout std_logic := '0';

         ----------------------------------------------------------------------
         -- UART monitor interface
         ----------------------------------------------------------------------
         monitor_tx : out std_logic := '1';
         monitor_rx : in std_logic
         
         );
end container;

architecture Behavioral of container is
  
  signal pixelclock : std_logic;
  signal cpuclock : std_logic;
  signal counter : integer := 0;
  
begin
  
  gen_pin1:
  for i in 1 to 100 generate
      pin1: entity work.pin_id
        port map (
          clock => cpuclock,
          pin_number => to_unsigned(i,8),
          pin => fpga_pins(i)
          );
  end generate gen_pin1;
  
  dotclock1: entity work.clocking
    port map ( clk_in => CLK_IN,
               clock81p => pixelclock, -- 80MHz
               clock41 => cpuclock -- 40MHz
               );

  process (cpuclock) is
  begin
    if rising_edge(cpuclock) then
      if counter /= 40_500_000 then
        counter <= counter + 1;
      else
        counter <= 0;
        led <= '1';
      end if;
      if counter = 20_250_000 then
        led <= '0';
      end if;
      
    end if;
  end process;
  
  
end Behavioral;
