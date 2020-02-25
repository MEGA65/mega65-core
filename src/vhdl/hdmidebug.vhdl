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
library UNISIM;
use UNISIM.vcomponents.all;
use work.cputypes.all;
                
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity container is
  Port ( CLK_IN : STD_LOGIC;         
         btnCpuReset : in  STD_LOGIC;

         led : out std_logic := '1';

         -- internal speaker
         pcspeaker_left : out std_logic;
         pcspeaker_muten : out std_logic;         
         
         ----------------------------------------------------------------------
         -- HyperRAM as expansion RAM
         ----------------------------------------------------------------------
         hr_d : inout unsigned(7 downto 0);
         hr_rwds : inout std_logic;
         hr_reset : inout std_logic;
         hr_clk_p : out std_logic;
         hr_cs0 : inout std_logic
         
         );
end container;

architecture Behavioral of container is

  signal pixelclock : std_logic;
  signal ethclock : std_logic;
  signal cpuclock : std_logic;
  signal clock41 : std_logic;
  signal clock27 : std_logic;
  signal clock81 : std_logic;
  signal clock120 : std_logic;
  signal clock100 : std_logic;
  signal clock162 : std_logic;
  signal clock163 : std_logic;

  signal counter : unsigned(31 downto 0) := to_unsigned(0,32);

  signal expansionram_address : unsigned(26 downto 0) := to_unsigned(0,27);
  signal expansionram_wdata : unsigned(7 downto 0) := to_unsigned(42,8);
  signal expansionram_rdata : unsigned(7 downto 0);
  signal expansionram_read : std_logic := '1';
  signal expansionram_write : std_logic := '0';
  signal expansionram_data_ready_strobe : std_logic;
  signal expansionram_busy : std_logic;
  
begin

  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock100 => clock100,
               clock81 => pixelclock, -- 80MHz
               clock41 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock162 => clock162,
               clock27 => clock27
               );

   hyperram0: entity work.hyperram
     port map (
       cpuclock => cpuclock,
       clock240 => cpuclock,
       address => expansionram_address,
       wdata => expansionram_wdata,
       read_request => expansionram_read,
       write_request => expansionram_write,
       rdata => expansionram_rdata,
       data_ready_strobe => expansionram_data_ready_strobe,
       busy => expansionram_busy,
      
       hr_d => hr_d,
       hr_rwds => hr_rwds,
       hr_reset => hr_reset,
       hr_clk_p => hr_clk_p,
       hr_cs0 => hr_cs0
       );
  
  PROCESS (PIXELCLOCK) IS
  BEGIN

    if rising_edge(ethclock) then
      counter <= counter + 1; 

      -- Try waggling Hyperram pins
--      hr_d <= counter(7 downto 0);
--      hr_cs0 <= counter(24);
--      hr_reset <= counter(25);
--      hr_rwds <= counter(26);
--      hr_clk_p <= counter(23);
--      led <= counter(23);
      led <= hr_cs0;

      pcspeaker_left <= counter(20);
      pcspeaker_muten <= counter(26);
      
    end if;
    
  end process;    
  
end Behavioral;
