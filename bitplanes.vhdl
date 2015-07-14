--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2014-2015
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

  component bitplane is
  Port (
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;

    advance_pixel : in std_logic;
    sixteen_colour_mode : in std_logic;

    data_in_valid : in std_logic;
    data_in : in unsigned(7 downto 0);
    data_request : out std_logic := '0';
    
    pixel_out : out std_logic := '0';
    pixel16_out : out unsigned(3 downto 0) := x"0"
    );

  end component;

  
  component ram9x4k IS
    PORT (
      clka : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      addraa : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
      clkb : IN STD_LOGIC;
      addrb : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
      );
  END component;

  signal y_last : integer range 0 to 4095;
  signal x_last : integer range 0 to 4095;

  type bdo is array(0 to 7) of integer range 0 to 65535;
  signal bitplane_data_offsets : bdo;

  signal bitplanedatabuffer_write : std_logic := '0';
  signal bitplanedatabuffer_wdata : unsigned(8 downto 0);
  signal bitplanedatabuffer_waddress : unsigned(11 downto 0);
  signal bitplanedatabuffer_rdata : unsigned(8 downto 0);
  signal bitplanedatabuffer_address : unsigned(11 downto 0);

  -- Signals into and out of bitplane pixel engines
  signal bitplanes_advance_pixel : std_logic_vector(7 downto 0) := "00000000";
  signal bitplanes_sixteen_colour_mode : std_logic_vector(7 downto 0) := "00000000";
  signal bitplanes_data_in_valid : std_logic_vector(7 downto 0) := "00000000";
  signal bitplanes_data_in : unsigned(7 downto 0) := x"00";
  signal bitplanes_data_request : std_logic_vector(7 downto 0);
  signal bitplanes_pixel_out : std_logic_vector(7 downto 0);
  type nybl_array_8 is array(0 to 7) of unsigned(3 downto 0);
  signal bitplanes_pixel16_out : nybl_array_8;
  type bitplane_offsets_8 is array(0 to 7) of integer range 0 to 511;
  signal bitplanes_byte_numbers : bitplane_offsets_8;
  
begin  -- behavioural

  -- 4K buffer for holding buffered bitplane data for rendering.
  -- 8 bitplanes x 512 bytes = 4KB.
  -- This is plenty, since we actually only read 80 bytes max per bitplane per
  -- line
  bitplanedatabuffer: component ram9x4k
    port map (clka => pixelclock,
              wea(0) => bitplanedatabuffer_write,
              dina => std_logic_vector(bitplanedatabuffer_wdata),
              addraa => std_logic_vector(bitplanedatabuffer_waddress),

              clkb => pixelclock,
              addrb => std_logic_vector(bitplanedatabuffer_address),
              unsigned(doutb) => bitplanedatabuffer_rdata
              );

  
  
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
      
      if sprite_datavalid_in = '1' and (sprite_spritenumber_in > 7) then
        -- Record sprite data
        report "BITPLANES:"
          & " accepting data byte $" & to_hstring(sprite_data_in)
          & " from VIC-IV for byte #" & integer'image(sprite_bytenumber_in);
        bitplanedatabuffer_waddress(11 downto 9)
          <= to_unsigned(sprite_spritenumber_in mod 8, 3);
        bitplanedatabuffer_waddress(8 downto 0)
          <= to_unsigned(sprite_bytenumber_in, 9);
        bitplanedatabuffer_wdata(8) <= '0';
        bitplanedatabuffer_wdata(7 downto 0) <= sprite_data_in;
        bitplanedatabuffer_write <= '1';
      else
        bitplanedatabuffer_write <= '0';
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
