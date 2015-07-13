--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2014
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
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity bitplanes is
  Port (
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;

    -- Pull sprite data in along the chain from the previous sprite (or VIC-IV)
    signal sprite_datavalid_in : in std_logic;
    signal sprite_bytenumber_in : in integer range 0 to 15;
    signal sprite_spritenumber_in : in integer range 0 to 15;
    signal sprite_data_in : in unsigned(7 downto 0);

    -- Pass sprite data out along the chain to the next sprite
    signal sprite_datavalid_out : out std_logic;
    signal sprite_bytenumber_out : out integer range 0 to 79;
    signal sprite_spritenumber_out : out integer range 0 to 79;
    signal sprite_data_out : out unsigned(7 downto 0);

    -- which base offset for the VIC-II sprite data are we showing this raster line?
    -- VIC-IV clocks sprite_number_for_data and each sprite replaces
    -- sprite_data_offset with the appropriate value if the sprite number is itself
    signal sprite_number_for_data_in : in integer range 0 to 15;
    signal sprite_data_offset_in : in integer range 0 to 65535;    
    signal sprite_data_offset_out : out integer range 0 to 65535;    
    signal sprite_number_for_data_out : out integer range 0 to 15;
    
    -- Is the pixel just passed in a foreground pixel?
    signal is_foreground_in : in std_logic;
    signal is_background_in : in std_logic;
    -- and what is the colour of the bitmap pixel?
    signal x_in : in integer range 0 to 4095;
    signal y_in : in integer range 0 to 4095;
    signal border_in : in std_logic;
    signal pixel_in : in unsigned(7 downto 0);
    signal alpha_in : in unsigned(7 downto 0);
    -- and information from the previous sprite
    signal is_sprite_in : in std_logic;
    signal sprite_colour_in : in unsigned(7 downto 0);
    signal sprite_map_in : in std_logic_vector(7 downto 0);
    signal sprite_fg_map_in : in std_logic_vector(7 downto 0);

    -- Pass pixel information back out, as well as the sprite colour information
    signal is_foreground_out : out std_logic;
    signal is_background_out : out std_logic;
    signal x_out : out integer range 0 to 4095;
    signal y_out : out integer range 0 to 4095;
    signal border_out : out std_logic;
    signal pixel_out : out unsigned(7 downto 0);
    signal alpha_out : out unsigned(7 downto 0);
    signal sprite_colour_out : out unsigned(7 downto 0);
    signal is_sprite_out : out std_logic;
    signal sprite_map_out : out std_logic_vector(7 downto 0);
    signal sprite_fg_map_out : out std_logic_vector(7 downto 0)
    
);

end bitplanes;

architecture behavioural of bitplanes is

  signal y_last : integer range 0 to 4095;
  signal x_last : integer range 0 to 4095;

  type bdo is array(0 to 7) of integer range 0 to 65535;
  signal bitplane_data_offsets : bdo;
  
begin  -- behavioural
  
  -- purpose: sprite drawing
  -- type   : sequential
  -- inputs : pixelclock, <reset>
  -- outputs: colour, is_sprite_out
  main: process (pixelclock)
  begin  -- process main
    if pixelclock'event and pixelclock = '1' then  -- rising clock edge
--      report "SPRITE: entering VIC-II sprite #" & integer'image(sprite_number);
      -- copy sprite data chain from input side to output side      
      sprite_spritenumber_out <= sprite_spritenumber_in;
      sprite_datavalid_out <= sprite_datavalid_in;
      sprite_bytenumber_out <= sprite_bytenumber_in;
      sprite_data_out <= sprite_data_in;
      sprite_number_for_data_out <= sprite_number_for_data_in;
      
      if sprite_datavalid_in = '1' and sprite_spritenumber_in > 7 then
        -- Record sprite data
        report "BITPLANES:"
          & " accepting data byte $" & to_hstring(sprite_data_in)
          & " from VIC-IV for byte #" & integer'image(sprite_bytenumber_in);
      end if;
      
      if sprite_number_for_data_in > 7 then
        -- Tell VIC-IV our current bitplane data offsets
        sprite_data_offset_out <= bitplane_data_offsets(sprite_number_for_data_in mod 8);
      else
        sprite_data_offset_out <= sprite_data_offset_in;
      end if;

      -- copy pixel data chain from input side to output side
      alpha_out <= alpha_in;
      x_out <= x_in;
      y_out <= y_in;
      border_out <= border_in;
      is_foreground_out <= is_foreground_in;
      is_background_out <= is_background_in;

      -- Work out when we start drawing the sprite
      y_last <= y_in;

      is_sprite_out <= is_sprite_in;
      sprite_colour_out <= sprite_colour_in;
      pixel_out <= pixel_in;
    end if;
  end process main;

end behavioural;
