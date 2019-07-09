--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2018
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 3 of the
-- *  License, or (at your option) any later version.
-- *
-- *  This program is distributed in the hope that it will be useful,
-- *  but WITHOUT ANY WARRANTY; without even the implied warranty of
-- *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- *  GNU General Public License for more details.
-- *
-- *  You should have received a copy of the GNU Lesser General Public License
-- *  along with this program; if not, write to the Free Software
-- *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
-- *  02111-1307  USA.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity frame_generator is
  generic (
    frame_width : integer := 960;
    display_width : integer := 800;
    clock_divider : integer := 4;
    pipeline_delay : integer := 0;
    frame_height : integer := 625;
    lcd_height : integer := 480;
    display_height : integer := 600;
    vsync_start : integer := 601;
    vsync_end : integer := 606;
    hsync_start : integer := 814;
    hsync_end : integer := 880;
    cycles_per_raster : integer := 63
    );
  port (
    clock240 : in std_logic;
    clock120 : in std_logic;
    clock80 : in std_logic;
    clock40 : in std_logic;

    -- 80MHz oriented configuration flags
    hsync_polarity : in std_logic;
    vsync_polarity : in std_logic;

    -- 120MHz video output oriented signals
    hsync : out std_logic := '0';
    hsync_uninverted : out std_logic := '0';
    vsync : out std_logic := '0';
    inframe : out std_logic := '0';
    pixel_strobe_120 : out std_logic := '0';   -- used to clock read-side of
                                               -- raster buffer fifo


    -- 40MHz oriented signal that strobes for each CPU tick
    phi2_out : out std_logic;  
    
    lcd_hsync : out std_logic := '0';
    lcd_vsync : out std_logic := '0';
    lcd_inframe : out std_logic := '0';
    lcd_inletterbox : out std_logic := '0';

    red_o : out unsigned(7 downto 0) := x"00";
    green_o : out unsigned(7 downto 0) := x"00";
    blue_o : out unsigned(7 downto 0) := x"00";

    -- 80MHz oriented signals for VIC-IV
    pixel_strobe_80 : out std_logic := '0';
    x_zero_80 : out std_logic := '0';
    x_zero_120 : out std_logic := '0';
    y_zero_120 : out std_logic := '0';
    y_zero_80 : out std_logic := '0'
    
    
    );

end frame_generator;

architecture brutalist of frame_generator is

  -- Work out what we need to add so that 16th bit (bit 15) will flip every time
  -- a phi2 cycle has occurred
  signal ticks_per_128_phi2 : integer := 32768*cycles_per_raster/frame_width;
  signal ticks_per_phi2 : unsigned(15 downto 0) := to_unsigned(ticks_per_128_phi2,16);

  signal phi2_accumulator : unsigned(15 downto 0) := to_unsigned(0,16);
  signal last_phi2 : std_logic := '0';
  signal phi2_toggle : std_logic := '0';
  signal last_phi2_toggle : std_logic := '0';
  
  signal x : integer := 0;
  signal x_zero_driver : std_logic := '0';
  signal x_zero_driver2 : std_logic := '0';
  signal x_zero_driver80 : std_logic := '0';
  signal x_zero_driver80b : std_logic := '0';
  signal y_zero_driver : std_logic := '0';
  signal y_zero_driver2 : std_logic := '0';
  signal y_zero_driver80 : std_logic := '0';
  signal y_zero_driver80b : std_logic := '0';
  signal y : integer := frame_height - 3;
  signal inframe_internal : std_logic := '0';

  signal lcd_inletterbox_internal : std_logic := '0';

  signal vsync_driver : std_logic := '0';
  signal hsync_driver : std_logic := '0';
  signal hsync_uninverted_driver : std_logic := '0';

  signal pixel_toggle120 : std_logic := '0';
  signal pixel_toggle80 : std_logic := '0';
  signal last_pixel_toggle80 : std_logic := '0';
  signal pixel_strobe_counter : integer range 0 to clock_divider := 0;

  signal pixel_strobe120_drive : std_logic := '0';
  
begin

  process (clock240,clock120,clock80) is
  begin

    if rising_edge(clock80) then
      -- Cross from 120MHz to 80MHz clock domains for VIC-IV signals
      x_zero_80 <= x_zero_driver80b;
      y_zero_80 <= y_zero_driver80b;
      if y_zero_driver80b='1' then
        report "y_zero asserted";
      end if;
      if x_zero_driver80b='1' then
        report "x_zero asserted";
      end if;
      x_zero_driver80b <= x_zero_driver80;
      y_zero_driver80b <= y_zero_driver80;      
      x_zero_driver80 <= x_zero_driver2;
      y_zero_driver80 <= y_zero_driver2;      

      -- Pixel strobe to VIC-IV can just be a 50MHz pulse
      -- train, since it all goes into a buffer.
      -- But better is to still try to follow the 120MHz driven
      -- chain.
      pixel_toggle80 <= pixel_toggle120;
      last_pixel_toggle80 <= pixel_toggle80;
      if pixel_toggle80 /= last_pixel_toggle80 then
        pixel_strobe_80 <= '1';
      else
        pixel_strobe_80 <= '0';
      end if;
    end if;

    if rising_edge(clock40) then
      last_phi2_toggle <= phi2_toggle;
      if phi2_toggle /= last_phi2_toggle then
        phi2_out <= '1';
      else
        phi2_out <= '0';
      end if;
    end if;
    
    if rising_edge(clock120) then

      phi2_accumulator <= phi2_accumulator + ticks_per_128_phi2;
      if phi2_accumulator(15) /= last_phi2 then
        phi2_toggle <= not phi2_toggle;
      end if;
      
      x_zero_driver2 <= x_zero_driver;
      y_zero_driver2 <= y_zero_driver;
      x_zero_120 <= x_zero_driver;
      y_zero_120 <= y_zero_driver;
      
      vsync <= vsync_driver;
      hsync <= hsync_driver;
      hsync_uninverted <= hsync_uninverted_driver;
      pixel_strobe_120 <= pixel_strobe120_drive;

      -- Generate pixel strobe train
      if pixel_strobe_counter = 0 then
        pixel_strobe_counter <= (clock_divider - 1);
        pixel_strobe120_drive <= '1';
        pixel_toggle120 <= not pixel_toggle120;
      else
        pixel_strobe120_drive <= '0';
        pixel_strobe_counter <= pixel_strobe_counter - 1;
      end if;
      
      if x < frame_width then
        x <= x + 1;
        -- make the x_zero signal last a bit longer, to make sure it gets captured.
        if x = 3 then
          x_zero_driver <= '0';
        end if;
      else
        x <= 0;
        x_zero_driver <= '1';
        if y < frame_height then
          y <= y + 1;
          y_zero_driver <= '0';
        else
          y <= 0;
          y_zero_driver <= '1';
          phi2_accumulator <= to_unsigned(0,16);
        end if;
      end if;

      -- LCD HSYNC is expected to be just before start of pixels
      if x = (frame_width - 200) then
        lcd_hsync <= '0';
      end if;
      if x = (frame_width - 400) then
        lcd_hsync <= '1';
      end if;
      -- HSYNC for VGA follows the settings passed via the generics
      if x = hsync_start then
        hsync_driver <= not hsync_polarity; 
        hsync_uninverted_driver <= '1'; 
      end if;
      if x = hsync_end then
        hsync_driver <= hsync_polarity;
        hsync_uninverted_driver <= '0';
      end if;

      if y = ( display_height - lcd_height ) / 2 then
        if lcd_inletterbox_internal='0' then
          report "entering letter box";
        end if;
        lcd_inletterbox_internal <= '1';
        lcd_inletterbox <= '1';
      end if;
      if y = display_height - (display_height - lcd_height ) / 2 then
        if lcd_inletterbox_internal='1' then
          report "leaving letter box";
        end if;
        lcd_inletterbox_internal <= '0';
        lcd_inletterbox <= '0';
      end if;
      report "preparing for lcd_inframe check at (" & integer'image(x) & "," & integer'image(y) & ").";
      if x = (1 + pipeline_delay) and lcd_inletterbox_internal = '1' then
        lcd_inframe <= '1';
        report "lcd_inframe=1 at x = " & integer'image(x);
      end if;
      if x = (1 + pipeline_delay + display_width) then
        report "lcd_inframe=0 at x = " & integer'image(x);
        lcd_vsync <= lcd_inletterbox_internal;
        lcd_inframe <= '0';
      end if;
      if x = pipeline_delay and y < display_height then
        inframe <= '1';
        inframe_internal <= '1';
      end if;
      if y = vsync_start then
        vsync_driver <= vsync_polarity;
      end if;
      if y = 0 or y = vsync_end then
        vsync_driver <= not vsync_polarity;
      end if;

      -- Colourful pattern inside frame
      if inframe_internal = '1' then
        -- Inside frame, draw a test pattern
        red_o <= to_unsigned(x,8);
        green_o <= to_unsigned(y,8);
        blue_o <= to_unsigned(x+y,8);
      end if;
      
      -- Draw white edge on frame
      if x = pipeline_delay and y < display_height then
        inframe <= '1';
        inframe_internal <= '1';
        red_o <= x"FF";
        green_o <= x"FF";
        blue_o <= x"FF";
      end if;
      if ((x = ( display_width + pipeline_delay - 1 ))
          or (y = 0) or (y = (display_height - 1)))
        and (inframe_internal='1') then
        red_o <= x"FF";
        green_o <= x"FF";
        blue_o <= x"FF";
      end if;
      -- Black outside of frame
      if x = display_width + pipeline_delay then
        inframe <= '0';
        inframe_internal <= '0';
        red_o <= x"00";
        green_o <= x"00";
        blue_o <= x"00";        
      end if;
    end if;

  end process;
  
end brutalist;
