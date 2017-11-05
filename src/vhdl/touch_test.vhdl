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

  signal x_counter : integer range 0 to 1023 := 0;
  signal y_counter : integer range 0 to 1023 := 0;
  
  signal pixelclock : std_logic;
  signal pixelclock2x : std_logic;
  signal cpuclock : std_logic;
--  signal ioclock : std_logic;
  
  signal clock100mhz : std_logic := '0';
  signal clock50mhz : std_logic := '0';
  signal clock25mhz : std_logic := '0';

  signal touch1_x : integer := 0;
  signal touch2_x : integer := 0;
  signal touch1_y : integer := 0;
  signal touch2_y : integer := 0;
  signal touch1_downevent : std_logic := '0';
  signal touch2_downevent : std_logic := '0';
  
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
      if clock50mhz = '1' then
        clock25mhz <= not clock25mhz;
      end if;
    end if;
  end process;

  -- Implement a simple frame generator, and show
  -- the location of the touch points from the touch interface
  -- {"800x480@50","Modeline \"800x480\" 24.13 800 832 920 952 480 490 494 505 +hsync"},
  process (clock25mhz) is
  begin
    if rising_edge(clock25mhz) then
      if x_counter /= 952 then
        x_counter <= x_counter + 1;
      else
        y_counter <= y_counter + 1;
        x_counter <= 0;
      end if;
      if x_counter = 832 then
        hsync <= '1';
      end if;
      if x_counter = 920 then
        hsync <= '0';
      end if;
      if y_counter = 490 then
        vsync <= '1';
      end if;
      if y_counter = 495 then
        vsync <= '0';
      end if;
      if x_counter = touch1_x or y_counter = touch1_y then
        -- touch1 cross-hairs in yellow
        vgared <= (others => '1');
        vgagreen <= (others => '1');
        vgablue <= (others => '0');
      elsif x_counter = touch2_x or y_counter = touch2_y then
        -- touch2 cross-hairs in aqua
        vgared <= (others => '0');
        vgagreen <= (others => '1');
        vgablue <= (others => '1');
      else
        if touch1_downevent = '1' then
          -- touch1 press and release events flash the screen red for a frame
          vgared <= (others => '1');
        else        
          vgared <= (others => '0');
        end if;
        if touch2_downevent = '1' then
          -- touch2 press events flash the screen green for a frame
          vgagreen <= (others => '1');
        else
          vgagreen <= (others => '0');
        end if;
        vgablue <= (others => '0');
      end if;
    end if;
  end process;
    
end Behavioral;
 
