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
use work.victypes.all;

entity pixel_driver is

  port (
    pixelclock_select : in std_logic_vector(7 downto 0);

    clock200 : in std_logic;
    clock100 : in std_logic;
    clock50 : in std_logic;
    clock40 : in std_logic;
    clock33 : in std_logic;
    clock30 : in std_logic;

    red_i : in unsigned(7 downto 0);
    green_i : in unsigned(7 downto 0);
    blue_i : in unsigned(7 downto 0);

    red_o : out unsigned(7 downto 0);
    green_o : out unsigned(7 downto 0);
    blue_o : out unsigned(7 downto 0);

    hsync_i : in std_logic;
    hsync_o : out std_logic;
    vsync_i : in std_logic;
    vsync_o : out std_logic;

    lcd_hsync_i : in std_logic;
    lcd_hsync_o : out std_logic;
    lcd_vsync_i : in std_logic;
    lcd_vsync_o : out std_logic;

    lcd_display_enable_i : in std_logic;
    lcd_display_enable_o : out std_logic;
    lcd_pixel_strobe_i : in std_logic;
    lcd_pixel_strobe_o : out std_logic;
    
    viciv_outofframe_i : in std_logic;
    viciv_outofframe_o : out std_logic

    );

end pixel_driver;

architecture greco_roman of pixel_driver is

  signal red_l : unsigned(7 downto 0) := x"00";
  signal green_l : unsigned(7 downto 0) := x"00";
  signal blue_l : unsigned(7 downto 0) := x"00";

  signal clock_select : std_logic_vector(7 downto 0) := x"00";
  
begin

  -- The only real job here is to select the output clock based
  -- on the input clock.  Thus the bulk of the logic is actually
  -- timing-domain crossing logic.
  -- If we are lucky, it can in fact be implemented just as a
  -- bunch of latches and muxes.

  process (lcd_pixel_strobe_i,red_i,green_i,blue_i,clock50) is
  begin

    if rising_edge(clock50) then
      clock_select <= pixelclock_select;
    end if;
    
    hsync_o <= hsync_i;
    vsync_o <= vsync_i;
    lcd_hsync_o <= lcd_hsync_i;
    lcd_vsync_o <= lcd_vsync_i;
    lcd_display_enable_o <= lcd_display_enable_i;
    viciv_outofframe_o <= viciv_outofframe_i;
    
    if clock_select(6) = '0' then
      red_o <= red_i;
      green_o <= green_i;
      blue_o <= blue_i;
    else
      red_o <= red_l;
      green_o <= green_l;
      blue_o <= blue_l;
    end if;

    if clock_select(5)='0' then
      if rising_edge(lcd_pixel_strobe_i) then
        red_l <= red_i;
        green_l <= green_i;
        blue_l <= blue_i;
      end if;
    else
      if clock_select(1 downto 0) = "00" then
        if rising_edge(clock30) then
          red_l <= red_i;
          green_l <= green_i;
          blue_l <= blue_i;
        end if;
      end if;
      if clock_select(1 downto 0) = "01" then
        if rising_edge(clock33) then
          red_l <= red_i;
          green_l <= green_i;
          blue_l <= blue_i;
        end if;
      end if;
      if clock_select(1 downto 0) = "10" then
        if rising_edge(clock40) then
          red_l <= red_i;
          green_l <= green_i;
          blue_l <= blue_i;
        end if;
      end if;
      if clock_select(1 downto 0) = "11" then
        if rising_edge(clock50) then
          red_l <= red_i;
          green_l <= green_i;
          blue_l <= blue_i;
        end if;
      end if;
    end if;

    if clock_select(7) = '1' then
      -- Replace pixel clock with a fixed one
      case clock_select(1 downto 0) is
        when "00" => lcd_pixel_strobe_o <= clock30;
        when "01" => lcd_pixel_strobe_o <= clock33;
        when "10" => lcd_pixel_strobe_o <= clock40;
        when "11" => lcd_pixel_strobe_o <= clock50;
        when others =>
          lcd_pixel_strobe_o <= clock50;
      end case;
    else
      -- Pass pixel clock unmodified
      lcd_pixel_strobe_o <= lcd_pixel_strobe_i;
    end if;

  end process;
  
end greco_roman;
