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
    frame_height : integer := 625;
    display_height : integer := 600;
    vsync_start : integer := 601;
    vsync_end : integer := 606;
    hsync_start : integer := 814;
    hsync_end : integer := 880
    );
  port (
    clock : in std_logic;
    hsync : out std_logic := '0';
    vsync : out std_logic := '0';
    inframe : out std_logic := '0';

    red_o : out unsigned(7 downto 0) := x"00";
    green_o : out unsigned(7 downto 0) := x"00";
    blue_o : out unsigned(7 downto 0) := x"00"
    
    );

end frame_generator;

architecture brutalist of frame_generator is

  signal x : integer := 0;
  signal y : integer := 0;
  signal inframe_internal : std_logic := '0';
  
begin

  process (clock) is
  begin

    if rising_edge(clock) then
      if x < frame_width then
        x <= x + 1;
      else
        x <= 0;
        if y < frame_height then
          y <= y + 1;
        else
          y <= 0;
        end if;
      end if;

      if x = hsync_start then
        hsync <= '1';
      end if;
      if x = hsync_end then
        hsync <= '0';
      end if;
      if y = vsync_start then
        vsync <= '1';
      end if;
      if y = 0 or y = vsync_end then
        vsync <= '0';
      end if;

      -- Colourful pattern inside frame
      if inframe_internal = '1' then
        -- Inside frame, draw a test pattern
        red_o <= to_unsigned(x,8);
        green_o <= to_unsigned(y,8);
        blue_o <= to_unsigned(x+y,8);
      end if;
      
      -- Draw white edge on frame
      if x = 0 and y < display_height then
        inframe <= '1';
        inframe_internal <= '1';
        red_o <= x"FF";
        green_o <= x"FF";
        blue_o <= x"FF";
      end if;
      if ((x = ( display_width - 1 ))
          or (y = 0) or (y = (display_height - 1)))
        and (inframe_internal='1') then
        red_o <= x"FF";
        green_o <= x"FF";
        blue_o <= x"FF";
      end if;
      -- Black outside of frame
      if x = display_width then
        inframe <= '0';
        inframe_internal <= '0';
        red_o <= x"00";
        green_o <= x"00";
        blue_o <= x"00";        
      end if;
    end if;

  end process;
  
end brutalist;
