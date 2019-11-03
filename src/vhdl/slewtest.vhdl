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

library unisim;
use unisim.vcomponents.all;


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity container is
  Port ( CLK_IN : STD_LOGIC;         
         
         ----------------------------------------------------------------------
         -- PMODs for LCD screen and associated things during testing
         ----------------------------------------------------------------------

         power_down : out std_logic := '0';

         ----------------------------------------------------------------------
         -- LCD output
         ----------------------------------------------------------------------
         lcd_vsync : out STD_LOGIC;
         lcd_hsync : out  STD_LOGIC;
         lcd_display_enable : out std_logic;
         lcd_pwm : out std_logic;
         lcd_dclk : out std_logic;
         lcd_red : out  UNSIGNED (5 downto 0);
         lcd_green : out  UNSIGNED (5 downto 0);
         lcd_blue : out  UNSIGNED (5 downto 0)
      
         );
end container;

architecture Behavioral of container is

  signal dummy_red : unsigned(1 downto 0);
  signal dummy_green : unsigned(1 downto 0);
  signal dummy_blue : unsigned(1 downto 0);
  
  signal pixelclock : std_logic;
  signal cpuclock : std_logic;
  signal clock240 : std_logic;
  signal clock120 : std_logic;
  signal ethclock : std_logic;
  signal clock200 : std_logic;
  signal clock30 : std_logic;
  signal clock30in : std_logic := '0';
  signal clock30count : integer range 0 to 3 := 0;

  signal pal50_select : std_logic := '0';

  signal pixel_strobe : std_logic := '0';
  signal lcd_in_frame : std_logic := '0';
  
begin
  
  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock80 => pixelclock, -- 80MHz
               clock40 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock200 => clock200,
               clock120 => clock120,
               clock240 => clock240
               );


  -- Create BUFG'd 30MHz clock for LCD panel
  --------------------------------------
  clkin30_buf : IBUFG
  port map
   (O => clock30,
    I => clock30in);

  pixel0: entity work.pixel_driver
    port map (
      clock80 => pixelclock,
      clock120 => clock120,
      clock240 => clock240,

      pixel_strobe80_out => pixel_strobe,
      
      -- Configuration information from the VIC-IV
      hsync_invert => '0',
      vsync_invert => '0',
      pal50_select =>  pal50_select,
      test_pattern_enable => '1',
      
      -- Framing information for VIC-IV
--      x_zero => external_frame_x_zero,     
--      y_zero => external_frame_y_zero,     

      -- Pixel data from the video pipeline
      -- (clocked at 100MHz pixel clock)
      pixel_strobe_in => pixel_strobe,
      red_i => x"FF",
      green_i => x"FF",
      blue_i => x"FF",

      -- The pixel for direct output to VGA pins
      -- It is clocked at the correct pixel
      red_o(7 downto 2) => lcd_red,
      red_o(1 downto 0) => dummy_red,
      green_o(7 downto 2) => lcd_green,
      green_o(1 downto 0) => dummy_green,
      blue_o(7 downto 2) => lcd_blue,      
      blue_o(1 downto 0) => dummy_blue,
--      hsync => hsync,
--      vsync => vsync,

      -- And the variations on those signals for the LCD display
      lcd_hsync => lcd_hsync,
      lcd_vsync => lcd_vsync,
      lcd_display_enable => lcd_display_enable,
--      lcd_inletterbox => lcd_in_letterbox,
--      inframe => vga_in_frame,
      lcd_inframe => lcd_in_frame

      );

  
  lcd_dclk <= (clock30 ) when pal50_select='1' else (cpuclock);
  
  process (clock240,pal50_select,clock30,clock30in)
  begin

    if rising_edge(clock240) then

      if (clock30count /= 3 ) then
        clock30count <= clock30count + 1;
      else
        clock30in <= not clock30in;
        clock30count <= 0;
      end if;
    end if;
  end process;
  
end Behavioral;
