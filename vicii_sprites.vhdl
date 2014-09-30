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
-- Company: 
-- Engineer: 
-- 
-- Create Date:    19:11:30 01/02/2014 
-- Design Name: 
-- Module Name:    vga - Behavioral 
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
use work.debugtools.all;
use work.cputypes.all;

entity vicii_sprites is
  Port (
    ----------------------------------------------------------------------
    -- dot clock & io clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;
    ioclock : in std_logic;

    -- Pull sprite data in along the chain from the previous sprite (or VIC-IV)
    signal sprite_datavalid_in : in std_logic;
    signal sprite_bytenumber_in : in integer range 0 to 2;
    signal sprite_spritenumber_in : in integer range 0 to 7;
    signal sprite_data_in : in unsigned(7 downto 0);

    -- which base offset for the VIC-II sprite data are we showing this raster line?
    -- VIC-IV clocks sprite_number_for_data and each sprite replaces
    -- sprite_data_offset with the appropriate value if the sprite number is itself
    signal sprite_number_for_data_in : in integer range 0 to 7;
    signal sprite_data_offset_out : out integer range 0 to 1023;    
    signal sprite_number_for_data_out : out integer range 0 to 7;
    
    -- Is the pixel just passed in a foreground pixel?
    signal is_foreground_in : in std_logic;
    -- and what is the colour of the bitmap pixel?
    signal x_in : in integer range 0 to 2047;
    signal y_in : in integer range 0 to 2047;
    signal border_in : in std_logic;
    signal pixel_in : in unsigned(7 downto 0);

    -- Pass pixel information back out, as well as the sprite colour information
    signal x_out : out integer range 0 to 2047;
    signal y_out : out integer range 0 to 2047;
    signal border_out : out std_logic;
    signal pixel_out : out unsigned(7 downto 0);
    signal sprite_colour_out : out unsigned(7 downto 0);
    signal is_sprite_out : out std_logic;

    -- We need the registers that describe the various sprites.
    -- We could pull these in from the VIC-IV, but that would mean that they
    -- would have to propogate within one pixelclock, which will be very
    -- difficult to achieve.  A better way is to snoop the fastio bus, and read
    -- them directly on the much slower ioclock, and provide them to each sprite.
    fastio_addr : in std_logic_vector(19 downto 0);
    fastio_write : in std_logic;
    fastio_wdata : in std_logic_vector(7 downto 0)

    );
end vicii_sprites;

architecture behavioural of vicii_sprites is

  component sprite is
    Port (
      ----------------------------------------------------------------------
      -- dot clock
      ----------------------------------------------------------------------
      pixelclock : in  STD_LOGIC;

      -- Pull sprite data in along the chain from the previous sprite (or VIC-IV)
      signal sprite_datavalid_in : in std_logic;
      signal sprite_bytenumber_in : in integer range 0 to 2;
      signal sprite_spritenumber_in : in integer range 0 to 7;
      signal sprite_data_in : in unsigned(7 downto 0);

      -- Pass sprite data out along the chain to the next sprite
      signal sprite_datavalid_out : out std_logic;
      signal sprite_bytenumber_out : out integer range 0 to 2;
      signal sprite_spritenumber_out : out integer range 0 to 7;
      signal sprite_data_out : out unsigned(7 downto 0);

      -- which base offset for the VIC-II sprite data are we showing this raster line?
      -- VIC-IV clocks sprite_number_for_data and each sprite replaces
      -- sprite_data_offset with the appropriate value if the sprite number is itself
      signal sprite_number_for_data_in : in integer range 0 to 7;
      signal sprite_data_offset_out : out integer range 0 to 1023;    
      signal sprite_number_for_data_out : out integer range 0 to 7;
      
      -- Is the pixel just passed in a foreground pixel?
      signal is_foreground_in : in std_logic;
      -- and what is the colour of the bitmap pixel?
      signal x_in : in integer range 0 to 2047;
      signal y_in : in integer range 0 to 2047;
      signal border_in : in std_logic;
      signal pixel_in : in unsigned(7 downto 0);

      -- Pass pixel information back out, as well as the sprite colour information
      signal x_out : out integer range 0 to 2047;
      signal y_out : out integer range 0 to 2047;
      signal border_out : out std_logic;
      signal pixel_out : out unsigned(7 downto 0);
      signal sprite_colour_out : out unsigned(7 downto 0);
      signal is_sprite_out : out std_logic;

      signal sprite_x : in unsigned(8 downto 0);
      signal sprite_y : in unsigned(7 downto 0);
      signal sprite_colour : in unsigned(7 downto 0);
      signal sprite_multi0_colour : in unsigned(7 downto 0);
      signal sprite_multi1_colour : in unsigned(7 downto 0);
      signal sprite_is_multicolour : in std_logic;
      signal sprite_stretch_x : in std_logic;
      signal sprite_stretch_y : in std_logic;

      -- Pass 
      signal pixel_out : out unsigned(7 downto 0);
      signal sprite_colour_out : out unsigned(7 downto 0);
      signal is_sprite_out : out std_logic;
      );
  end component;
  
  signal viciii_iomode : std_logic_vector(1 downto 0) := "11";
  signal reg_key : unsigned(7 downto 0) := x"00";
  
  -- Description of VIC-II sprites
  signal sprite_x : sprite_vector_8;
  signal vicii_sprite_enables : std_logic_vector(7 downto 0);
  signal vicii_sprite_xmsbs : std_logic_vector(7 downto 0);
  signal sprite_y : sprite_vector_8;
  signal sprite_colours : sprite_vector_8;
  signal vicii_sprite_priority_bits : std_logic_vector(7 downto 0);
  signal sprite_multi0_colour : unsigned(7 downto 0) := x"04";
  signal sprite_multi1_colour : unsigned(7 downto 0) := x"05";
  signal vicii_sprite_multicolour_bits : std_logic_vector(7 downto 0);
  signal vicii_sprite_x_expand : std_logic_vector(7 downto 0);
  signal vicii_sprite_y_expand : std_logic_vector(7 downto 0);

  -- if set, then upper nybl of colours are used, else only lower nybls, ala VIC-II
  signal viciii_extended_attributes : std_logic := '1';

  -- Pass sprite data out along the chain to the next sprite
  signal sprite_datavalid_out : std_logic;
  signal sprite_bytenumber_out : integer range 0 to 2;
  signal sprite_spritenumber_out : integer range 0 to 7;
  signal sprite_data_out : unsigned(7 downto 0);
  
begin

  -- The eight VIC-II sprites.
  -- Sprite 0 is "above" sprite 7, so sprite 7 must be the first in the chain.
  sprite7: component sprite
    port map(pixelclock => pixelclock,
             -- Receive sprite data chain to receive data from VIC-IV
             sprite_datavalid_in <= sprite_datavalid_in,
             sprite_bytenumber_in <= sprite_bytenumber_in,
             sprite_spritenumber_in <= sprite_spritenumber_in,
             sprite_data_in <= sprite_data_in,
             -- and to pass it out to the next sprite
             sprite_datavalid_out <= sprite_datavalid_7_6,
             sprite_bytenumber_out <= sprite_bytenumber_7_6,
             sprite_spritenumber_out <= sprite_spritenumber_7_6,
             sprite_data_out <= sprite_data_7_6,

             
             );
  
  process(ioclock) is
    variable register_bank : unsigned(7 downto 0);
    variable register_page : unsigned(3 downto 0);
    variable register_num : unsigned(7 downto 0);
    variable register_number : unsigned(11 downto 0);
  begin
    -- Duplicate of the same logic from VIC-IV
    if true then
      -- Calculate register number asynchronously
      register_number := x"FFF";
      if fastio_addr(19) = '0' or fastio_addr(19) = '1' then
        register_bank := unsigned(fastio_addr(19 downto 12));
        register_page := unsigned(fastio_addr(11 downto 8));
        register_num := unsigned(fastio_addr(7 downto 0));
      else
        -- Give values when inputs are bad to supress warnings cluttering output
        -- when simulating
        register_bank := x"FF";
        register_page := x"F";
        register_num := x"FF";
      end if;    
      
      if (register_bank=x"D0" or register_bank=x"D2") and register_page<4 then
        -- First 1KB of normal C64 IO space maps to r$0 - r$3F
        register_number(5 downto 0) := unsigned(fastio_addr(5 downto 0));        
        register_number(11 downto 6) := (others => '0');
        if fastio_addr(11 downto 0) = x"030" then
          -- C128 $D030
          register_number := x"0FF"; -- = 255
        end if;
        report "IO access resolves to video register number "
          & integer'image(to_integer(register_number)) severity note;        
      elsif (register_bank = x"D1" or register_bank = x"D3") and register_page<4 then
        register_number(11 downto 10) := "00";
        register_number(9 downto 8) := register_page(1 downto 0);
        register_number(7 downto 0) := register_num;
        report "IO access resolves to video register number "
          & integer'image(to_integer(register_number)) severity note;
      end if;
    end if;

    -- Snoop fastio bus to obtain sprite register values.
    -- (We also have to snoop $D02F and $D031 so that we know if VIC-III
    -- extended attributes are enabled.  If so, sprite colour registers are
    -- 8-bit (256 colour) instead of 4-bit (16 colour).
    if rising_edge(ioclock) then
      if fastio_write='1'
        and (fastio_addr(19) = '0' or fastio_addr(19) = '1') then        
        if register_number>=0 and register_number<8 then
                                        -- compatibility sprite coordinates
          sprite_x(to_integer(register_num(2 downto 0))) <= unsigned(fastio_wdata);
        elsif register_number<16 then
          sprite_y(to_integer(register_num(2 downto 0))) <= unsigned(fastio_wdata);
        elsif register_number=16 then
          vicii_sprite_xmsbs <= fastio_wdata;
        elsif register_number=23 then          -- $D017 compatibility sprite enable
          vicii_sprite_y_expand <= fastio_wdata;
        elsif register_number=27 then          -- $D01B sprite background priority
          vicii_sprite_priority_bits <= fastio_wdata;
        elsif register_number=28 then          -- $D01C sprite multicolour
          vicii_sprite_multicolour_bits <= fastio_wdata;
        elsif register_number=29 then          -- $D01D compatibility sprite enable
          vicii_sprite_x_expand <= fastio_wdata;
        elsif register_number=37 then
          sprite_multi0_colour <= unsigned(fastio_wdata);
        elsif register_number=38 then
          sprite_multi1_colour <= unsigned(fastio_wdata);
        elsif register_number>=39 and register_number<=46 then
          sprite_colours(to_integer(register_number)-39) <= unsigned(fastio_wdata);
        elsif register_number=47 then
          -- C65 VIC-III KEY register for unlocking extended registers.
          viciii_iomode <= "00"; -- by default go back to VIC-II mode
          if reg_key=x"a5" then
            if fastio_wdata=x"96" then
              -- C65 VIC-III mode
              viciii_iomode <= "01";
            end if;
          elsif reg_key=x"47" then
            if fastio_wdata=x"53" then
              -- C65GS VIC-IV mode
              viciii_iomode <= "11";
            end if;
          end if;
          reg_key <= unsigned(fastio_wdata);
        elsif register_number=49 then
          viciii_extended_attributes <= fastio_wdata(5);
        end if;
      end if;
    end if;
  end process;

  process(pixelclock) is
  begin
    -- XXX For now just pipe pixels through
    border_out <= border_in;
    pixel_out <= pixel_in;
    is_sprite_out <= '0';
  end process;
  
end behavioural;
