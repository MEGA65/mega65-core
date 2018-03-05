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

  -- signals here

begin

  process (clock200) is
  begin
  end process;

end greco_roman;
