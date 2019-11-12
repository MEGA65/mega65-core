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
    frame_width : integer;
    frame_height : integer;

    x_zero_position : integer := 0;
    
    fullwidth_start : integer;
    fullwidth_width : integer;

    narrow_start : integer;
    narrow_width : integer;

    pipeline_delay : integer;
    viciv_pipeline_depth : integer := 4;
    cycles_per_raster : integer := 63;

    vsync_start : integer;
    vsync_end : integer;
    hsync_start : integer;
    hsync_end : integer;

    vga_hsync_start : integer;
    vga_hsync_end : integer;
    
    first_raster : integer;
    last_raster : integer;

    lcd_first_raster : integer;
    lcd_last_raster : integer
    
    );
  port (
    -- Single 81MHz clock : divide by 2 for ~41MHz CPU and 27MHz
    -- video pixel clock
    clock81 : in std_logic;
    -- 41MHHz CPU clock is used for exporting the PHI2 clock
    clock41 : in std_logic;

    -- ~40MHz oriented signal that strobes for each CPU tick
    phi2_out : out std_logic;  
    
    hsync_polarity : in std_logic;
    vsync_polarity : in std_logic;

    -- Video output oriented signals
    hsync : out std_logic := '0';
    hsync_uninverted : out std_logic := '0';
    vsync : out std_logic := '0';
    vsync_uninverted : out std_logic := '0';

    lcd_hsync : out std_logic := '0';
    lcd_vsync : out std_logic := '0';

    lcd_inletterbox : out std_logic := '0';
    vga_inletterbox : out std_logic := '0';
    vga_hsync : out std_logic := '0';
    
    -- For video outputs that are wider
    -- (Typically the 800x480 LCD panel on the MEGAphone)
    fullwidth_dataenable : out std_logic := '0';
    
    -- For video outputs that are narrower.
    -- Typically anything other than the LCD panel of the MEGAphone 
    narrow_dataenable : out std_logic := '0';
    
    red_o : out unsigned(7 downto 0) := x"00";
    green_o : out unsigned(7 downto 0) := x"00";
    blue_o : out unsigned(7 downto 0) := x"00";

    nred_o : out unsigned(7 downto 0) := x"00";
    ngreen_o : out unsigned(7 downto 0) := x"00";
    nblue_o : out unsigned(7 downto 0) := x"00";
    
    -- ~80MHz oriented signals for VIC-IV
    pixel_strobe : out std_logic := '0';
    x_zero : out std_logic := '0';
    y_zero : out std_logic := '0'    
    
    );

end frame_generator;

architecture brutalist of frame_generator is

  constant cycles_per_pixel : integer := 3;

  -- Work out what we need to add so that 16th bit (bit 15) will flip every time
  -- a phi2 cycle has occurred
  signal ticks_per_128_phi2 : integer := 32768*cycles_per_raster/(frame_width*cycles_per_pixel);
  signal ticks_per_phi2 : unsigned(15 downto 0) := to_unsigned(ticks_per_128_phi2,16);

  signal phi2_accumulator : unsigned(15 downto 0) := to_unsigned(0,16);
  signal last_phi2 : std_logic := '0';
  signal phi2_toggle : std_logic := '0';
  signal last_phi2_toggle : std_logic := '0';
  
  signal x : integer := 0;
  signal y : integer := frame_height - 3;

  signal vsync_driver : std_logic := '0';
  signal hsync_driver : std_logic := '0';
  signal hsync_uninverted_driver : std_logic := '0';
  signal vsync_uninverted_driver : std_logic := '0';

  signal narrow_dataenable_driver : std_logic := '0';
  signal fullwidth_dataenable_driver : std_logic := '0';
  
  signal pixel_toggle : std_logic := '0';
  signal last_pixel_toggle : std_logic := '0';

  signal pixel_strobe_counter : integer := 0;

  signal x_zero_driver : std_logic := '0';
  signal y_zero_driver : std_logic := '0';

  signal normal_y_active : std_logic := '0';
  signal lcd_y_active : std_logic := '0';
  
  
begin

  process (clock41,clock81) is
  begin

    if rising_edge(clock81) then

      x_zero <= x_zero_driver;
      y_zero <= y_zero_driver;
      
      vsync <= vsync_driver;
      vsync_uninverted <= vsync_uninverted_driver;
      hsync <= hsync_driver;
      hsync_uninverted <= hsync_uninverted_driver;

      fullwidth_dataenable <= fullwidth_dataenable_driver;
      narrow_dataenable <= narrow_dataenable_driver;
      
      phi2_accumulator <= phi2_accumulator + ticks_per_128_phi2;
      if phi2_accumulator(15) /= last_phi2 then
        phi2_toggle <= not phi2_toggle;
      end if;
      
      -- Pixel strobe to VIC-IV can just be a 50MHz pulse
      -- train, since it all goes into a buffer.
      -- But better is to still try to follow the 27MHz driven
      -- chain.
      if pixel_strobe_counter /= (cycles_per_pixel-1) then
        pixel_strobe <= '0';
        pixel_strobe_counter <= pixel_strobe_counter + 1;
      else
        
        pixel_strobe <= '1';     -- stays high for 1 cycle
        pixel_strobe_counter <= 0;

        if x = x_zero_position then
          x_zero_driver <= '1';          
        elsif x = x_zero_position + 3 then
          x_zero_driver <= '0';
        end if;
        if x < frame_width then
          x <= x + 1;
        else
          x <= 0;
          if y < frame_height then
            y <= y + 1;
            y_zero_driver <= '0';
          else
            y <= 0;
            y_zero_driver <= '1';
            phi2_accumulator <= to_unsigned(0,16);
          end if;
        end if;

        -- LCD HSYNC is expected to be just before start of pixels, and is
        -- always negative
        if x = hsync_start then
          lcd_hsync <= '0';
        end if;
        if x = hsync_end then
          lcd_hsync <= '1';
        end if;
        -- HSYNC is negative by default
        -- HDMI hsync
        if x = hsync_start then
          hsync_driver <= not hsync_polarity; 
          hsync_uninverted_driver <= '1'; 
        end if;
        if x = hsync_end then
          hsync_driver <= hsync_polarity;
          hsync_uninverted_driver <= '0';
        end if;
        -- Analog VGA HSYNC needs to be somewhat earlier, to allow
        -- pseudo-flyback time
        if x = vga_hsync_start then
          vga_hsync <= '0';
        end if;
        if x = vga_hsync_end then
          vga_hsync <= '1';
        end if;

        
        -- VSYNC is negative by default
        if y = vsync_start then
          lcd_vsync <= '0';
          vsync_driver <= '0';
          vsync_uninverted_driver <= '1'; 
        end if;
        if y = vsync_end+1 then
          lcd_vsync <= '1';
          vsync_driver <= '1';
          vsync_uninverted_driver <= '0'; 
        end if;

        if x = (1 + pipeline_delay + narrow_start + viciv_pipeline_depth) and normal_y_active='1'  then
          narrow_dataenable_driver <= '1';
        end if;
        if x = (1 + pipeline_delay + narrow_start + narrow_width + viciv_pipeline_depth) then
          narrow_dataenable_driver <= '0';
        end if;

        if x = (1 + pipeline_delay + fullwidth_start + viciv_pipeline_depth) and normal_y_active='1'  then
          fullwidth_dataenable_driver <= '1';
        end if;
        if x = (1 + pipeline_delay + fullwidth_start + fullwidth_width + viciv_pipeline_depth) then
          fullwidth_dataenable_driver <= '0';
        end if;
        
        if y = first_raster then
          normal_y_active <= '1';
          vga_inletterbox <= '1';
        end if;
        if y = (last_raster+1) then
          normal_y_active <= '0';
          vga_inletterbox <= '0';
        end if;

        if y = lcd_first_raster then
          lcd_y_active <= '1';
          lcd_inletterbox <= '1';
        end if;
        if y = (lcd_last_raster+1) then
          lcd_y_active <= '0';
          lcd_inletterbox <= '0';
        end if;

        -- Colourful pattern inside frame
        if fullwidth_dataenable_driver = '1' then
          -- Inside frame, draw a test pattern
          red_o <= to_unsigned(x,8);
          green_o <= to_unsigned(y,8);
          blue_o <= to_unsigned(x+y,8);
          nred_o <= to_unsigned(x,8);
          ngreen_o <= to_unsigned(y,8);
          nblue_o <= to_unsigned(x+y,8);
        end if;
        
        -- Draw white edge on frame
        if x = narrow_start or x = (narrow_start + narrow_width - 1) then
          red_o <= x"FF";
          green_o <= x"FF";
          blue_o <= x"FF";
          nred_o <= x"FF";
          ngreen_o <= x"FF";
          nblue_o <= x"FF";
        end if;
        if y = first_raster or y = last_raster then
          red_o <= x"FF";
          green_o <= x"FF";
          blue_o <= x"FF";
          nred_o <= x"FF";
          ngreen_o <= x"FF";
          nblue_o <= x"FF";
        end if;
      end if;

      -- Make sure we have nothing visible during H/VSYNC pulses, so we don't
      -- mess up the VGA colours
      if fullwidth_dataenable_driver = '0' then
        red_o <= x"00";
        green_o <= x"00";
        blue_o <= x"00";        
      end if;
      if narrow_dataenable_driver = '0' then
        nred_o <= x"00";
        ngreen_o <= x"00";
        nblue_o <= x"00";
      end if;

      
    end if;

    if rising_edge(clock41) then
      last_phi2_toggle <= phi2_toggle;
      if phi2_toggle /= last_phi2_toggle then
        phi2_out <= '1';
      else
        phi2_out <= '0';
      end if;
    end if;
    
  end process;

end brutalist;
