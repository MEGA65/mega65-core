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

entity touch_test is
  Port ( CLK_IN : STD_LOGIC;         
         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vsync : out  STD_LOGIC;
         hsync : out  STD_LOGIC;
         vgared : out  UNSIGNED (3 downto 0);
         vgagreen : out  UNSIGNED (3 downto 0);
         vgablue : out  UNSIGNED (3 downto 0)


         );
end touch_test;

architecture Behavioral of touch_test is

  signal dummy_vgared : unsigned(3 downto 0);
  signal dummy_vgagreen : unsigned(3 downto 0);
  signal dummy_vgablue : unsigned(3 downto 0);

  signal pixelclock : std_logic;
  signal pixelclock2x : std_logic;
  signal cpuclock : std_logic;
--  signal ioclock : std_logic;
  
  signal clock100mhz : std_logic := '0';
  signal clock50mhz : std_logic := '0';

begin
  
  dotclock1: entity work.dotclock150
    port map ( clk_in1 => CLK_IN,
               clock100 => clock100mhz,
               -- CLK_OUT2 is good for 1920x1200@60Hz, CLK_OUT3___160
               -- for 1600x1200@60Hz
               -- 60Hz works fine, but 50Hz is not well supported by monitors. 
               -- so I guess we will go with an NTSC-style 60Hz display.       
               -- For C64 mode it would be nice to have PAL or NTSC selectable.                    -- Perhaps consider a different video mode for that, or buffering
               -- the generated frames somewhere?
               pixclock => pixelclock,
               cpuclock => cpuclock, -- 48MHz
               pix2xclock => pixelclock2x
--               clk_out3 => ioclock -- also 48MHz
               );

  -- Generate 50MHz clock for ethernet
  process (clock100mhz) is
  begin
    if rising_edge(clock100mhz) then
      report "50MHz tick";
      clock50mhz <= not clock50mhz;
      hsync <= '1';
      vsync <= '1';
      vgared <= (others => '1');
      vgagreen <= (others => '1');
      vgablue <= (others => '1');
    end if;
  end process;
  
end Behavioral;
