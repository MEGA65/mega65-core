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
use work.victypes.all;

entity vicii_sprites is
  Port (
    ----------------------------------------------------------------------
    -- dot clock & io clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;
    cpuclock : in std_logic;

    signal sprite_h640 : in std_logic;
    signal sprite_v400s : in std_logic_vector(7 downto 0);
    signal bitplane_h640 : in std_logic;
    signal bitplane_h1280 : in std_logic;
    signal bitplanes_x_start : in unsigned(7 downto 0);
    signal bitplanes_y_start : in unsigned(7 downto 0);
    signal bitplane_mode_in : in std_logic;
    signal bitplane_enables_in : in std_logic_vector(7 downto 0);
    signal bitplane_complements_in : in std_logic_vector(7 downto 0);
    signal bitplane_sixteen_colour_mode_flags_in : in std_logic_vector(7 downto 0);

    -- Pull sprite data in along the chain from the previous sprite (or VIC-IV)
    signal sprite_datavalid_in : in std_logic;
    signal sprite_bytenumber_in : in spritebytenumber;
    signal sprite_spritenumber_in : in spritenumber;
    signal sprite_data_in : in unsigned(7 downto 0);

    -- Extended sprite size control registers
    signal sprite_horizontal_tile_enables : in std_logic_vector(7 downto 0);
    signal sprite_bitplane_enables : in std_logic_vector(7 downto 0);
    signal sprite_extended_height_enables : in std_logic_vector(7 downto 0);
    signal sprite_extended_height_size : in unsigned(7 downto 0);
    signal sprite_extended_width_enables : in std_logic_vector(7 downto 0);
    signal sprite_sixteen_colour_enables : in std_logic_vector(7 downto 0);
    
    -- which base offset for the VIC-II sprite data are we showing this raster line?
    -- VIC-IV clocks sprite_number_for_data and each sprite replaces
    -- sprite_data_offset with the appropriate value if the sprite number is itself
    signal sprite_number_for_data_in : in spritenumber;
    signal sprite_data_offset_out : out spritedatabytenumber;    
    signal sprite_number_for_data_out : out spritenumber;
    
    -- Is the pixel just passed in a foreground pixel?
    signal is_foreground_in : in std_logic;
    signal is_background_in : in std_logic;
    -- and what is the colour of the bitmap pixel?
    signal x320_in : in xposition;
    signal x640_in : in xposition;
    signal x1280_in : in xposition;
    signal pipeline_delay : in integer range 0 to 31;

    signal y_in : in yposition;
    signal yfine_in : in yposition;
    signal border_in : in std_logic;
    signal alt_palette_in : in std_logic;
    signal pixel_in : in unsigned(7 downto 0);
    signal alpha_in : in unsigned(7 downto 0);

    -- Pass pixel information back out, as well as the sprite colour information
    signal is_foreground_out : out std_logic := '0';
    signal is_background_out : out std_logic := '0';
    signal x_out : out xposition := 0;
    signal y_out : out yposition := 0;
    signal border_out : out std_logic;
    signal alt_palette_out : out std_logic;
    signal pixel_out : out unsigned(7 downto 0) := (others => '0');
    signal alpha_out : out unsigned(7 downto 0) := (others => '0');
    signal sprite_colour_out : out unsigned(7 downto 0) := (others => '0');
    signal sprite_number_out : out integer range 0 to 7 := 0; 
    signal is_sprite_out : out std_logic := '0';
    signal sprite_fg_map_final : out std_logic_vector(7 downto 0) := (others => '0');
    signal sprite_map_final : out std_logic_vector(7 downto 0) := (others => '0');

    -- We need the registers that describe the various sprites.
    -- We could pull these in from the VIC-IV, but that would mean that they
    -- would have to propogate within one pixelclock, which will be very
    -- difficult to achieve.  A better way is to snoop the fastio bus, and read
    -- them directly on the much slower cpuclock, and provide them to each sprite.
    fastio_addr : in std_logic_vector(19 downto 0);
    fastio_write : in std_logic;
    fastio_wdata : in std_logic_vector(7 downto 0)

    );
end vicii_sprites;

architecture behavioural of vicii_sprites is

  type sprite_vector_8 is array(0 to 7) of unsigned(7 downto 0);

  signal pipeline_delay_latched : integer range 0 to 31 := 0;
  
  -- Description of VIC-II sprites
  signal sprite_x : sprite_vector_8  := (others => x"02");
  signal vicii_sprite_enables : std_logic_vector(7 downto 0) := (others => '1');
  signal vicii_sprite_xmsbs : std_logic_vector(7 downto 0) := (others => '0');
  signal sprite_h640_msbs : std_logic_vector(7 downto 0) := (others => '0');
  signal sprite_v400_msbs : std_logic_vector(7 downto 0) := (others => '0');
  signal sprite_v400_super_msbs : std_logic_vector(7 downto 0) := (others => '0');
  signal sprite_y : sprite_vector_8 := (others => to_unsigned(2,8));
  signal sprite_colours : sprite_vector_8 := (others => x"00");
  signal vicii_sprite_priority_bits : std_logic_vector(7 downto 0) := (others => '0');
  signal sprite_multi0_colour : unsigned(7 downto 0) := x"04";
  signal sprite_multi1_colour : unsigned(7 downto 0) := x"05";
  signal vicii_sprite_multicolour_bits : std_logic_vector(7 downto 0) := (others => '0');
  signal vicii_sprite_x_expand : std_logic_vector(7 downto 0) := (others => '0');
  signal vicii_sprite_y_expand : std_logic_vector(7 downto 0) := (others => '0');

  -- if set, then upper nybl of colours are used, else only lower nybls, ala VIC-II
  signal viciii_extended_attributes : std_logic := '1';

  -- Pass sprite data out along the chain and out the end 
  signal sprite_datavalid_out : std_logic := '0';
  signal sprite_bytenumber_out : spritebytenumber := 0;
  signal sprite_spritenumber_out : spritenumber := 0;
  signal sprite_data_out : unsigned(7 downto 0) := x"00";

  -- And between the sprites
  signal sprite_datavalid_7_6 : std_logic;
  signal sprite_bytenumber_7_6 : spritebytenumber;
  signal sprite_spritenumber_7_6 : spritenumber;
  signal sprite_data_7_6 : unsigned(7 downto 0);
  signal sprite_datavalid_6_5 : std_logic;
  signal sprite_bytenumber_6_5 : spritebytenumber;
  signal sprite_spritenumber_6_5 : spritenumber;
  signal sprite_data_6_5 : unsigned(7 downto 0);
  signal sprite_datavalid_5_4 : std_logic;
  signal sprite_bytenumber_5_4 : spritebytenumber;
  signal sprite_spritenumber_5_4 : spritenumber;
  signal sprite_data_5_4 : unsigned(7 downto 0);
  signal sprite_datavalid_4_3 : std_logic;
  signal sprite_bytenumber_4_3 : spritebytenumber;
  signal sprite_spritenumber_4_3 : spritenumber;
  signal sprite_data_4_3 : unsigned(7 downto 0);
  signal sprite_datavalid_3_2 : std_logic;
  signal sprite_bytenumber_3_2 : spritebytenumber;
  signal sprite_spritenumber_3_2 : spritenumber;
  signal sprite_data_3_2 : unsigned(7 downto 0);
  signal sprite_datavalid_2_1 : std_logic;
  signal sprite_bytenumber_2_1 : spritebytenumber;
  signal sprite_spritenumber_2_1 : spritenumber;
  signal sprite_data_2_1 : unsigned(7 downto 0);
  signal sprite_datavalid_1_0 : std_logic;
  signal sprite_bytenumber_1_0 : spritebytenumber;
  signal sprite_spritenumber_1_0 : spritenumber;
  signal sprite_data_1_0 : unsigned(7 downto 0);
  signal sprite_datavalid_0_bp : std_logic;
  signal sprite_bytenumber_0_bp : spritebytenumber;
  signal sprite_spritenumber_0_bp : spritenumber;
  signal sprite_data_0_bp : unsigned(7 downto 0);

  signal sprite_number_for_data_7_6 : spritenumber;
  signal sprite_number_for_data_6_5 : spritenumber;
  signal sprite_number_for_data_5_4 : spritenumber;
  signal sprite_number_for_data_4_3 : spritenumber;
  signal sprite_number_for_data_3_2 : spritenumber;
  signal sprite_number_for_data_2_1 : spritenumber;
  signal sprite_number_for_data_1_0 : spritenumber;
  signal sprite_number_for_data_0_bp : spritenumber;
  signal sprite_data_offset_7_6 : spritedatabytenumber;
  signal sprite_data_offset_6_5 : spritedatabytenumber;
  signal sprite_data_offset_5_4 : spritedatabytenumber;
  signal sprite_data_offset_4_3 : spritedatabytenumber;
  signal sprite_data_offset_3_2 : spritedatabytenumber;
  signal sprite_data_offset_2_1 : spritedatabytenumber;
  signal sprite_data_offset_1_0 : spritedatabytenumber;
  signal sprite_data_offset_0_bp : spritedatabytenumber;

  signal sprite_fg_map_7_6 : std_logic_vector(7 downto 0);
  signal sprite_fg_map_6_5 : std_logic_vector(7 downto 0);
  signal sprite_fg_map_5_4 : std_logic_vector(7 downto 0);
  signal sprite_fg_map_4_3 : std_logic_vector(7 downto 0);
  signal sprite_fg_map_3_2 : std_logic_vector(7 downto 0);
  signal sprite_fg_map_2_1 : std_logic_vector(7 downto 0);
  signal sprite_fg_map_1_0 : std_logic_vector(7 downto 0);
  signal sprite_fg_map_0_bp : std_logic_vector(7 downto 0);

  signal sprite_map_7_6 : std_logic_vector(7 downto 0);
  signal sprite_map_6_5 : std_logic_vector(7 downto 0);
  signal sprite_map_5_4 : std_logic_vector(7 downto 0);
  signal sprite_map_4_3 : std_logic_vector(7 downto 0);
  signal sprite_map_3_2 : std_logic_vector(7 downto 0);
  signal sprite_map_2_1 : std_logic_vector(7 downto 0);
  signal sprite_map_1_0 : std_logic_vector(7 downto 0);
  signal sprite_map_0_bp : std_logic_vector(7 downto 0);
  
  signal is_foreground_7_6 : std_logic;
  signal is_foreground_6_5 : std_logic;
  signal is_foreground_5_4 : std_logic;
  signal is_foreground_4_3 : std_logic;
  signal is_foreground_3_2 : std_logic;
  signal is_foreground_2_1 : std_logic;
  signal is_foreground_1_0 : std_logic;
  signal is_foreground_0_bp : std_logic;
  signal is_background_7_6 : std_logic;
  signal is_background_6_5 : std_logic;
  signal is_background_5_4 : std_logic;
  signal is_background_4_3 : std_logic;
  signal is_background_3_2 : std_logic;
  signal is_background_2_1 : std_logic;
  signal is_background_1_0 : std_logic;
  signal is_background_0_bp : std_logic;
  signal x320_7_6 : xposition;
  signal x320_6_5 : xposition;
  signal x320_5_4 : xposition;
  signal x320_4_3 : xposition;
  signal x320_3_2 : xposition;
  signal x320_2_1 : xposition;
  signal x320_1_0 : xposition;
  signal x320_0_bp : xposition;
  signal x640_7_6 : xposition;
  signal x640_6_5 : xposition;
  signal x640_5_4 : xposition;
  signal x640_4_3 : xposition;
  signal x640_3_2 : xposition;
  signal x640_2_1 : xposition;
  signal x640_1_0 : xposition;
  signal x640_0_bp : xposition;
  signal y_7_6 : yposition;
  signal y_6_5 : yposition;
  signal y_5_4 : yposition;
  signal y_4_3 : yposition;
  signal y_3_2 : yposition;
  signal y_2_1 : yposition;
  signal y_1_0 : yposition;
  signal y_0_bp : yposition;
  signal yfine_7_6 : yposition;
  signal yfine_6_5 : yposition;
  signal yfine_5_4 : yposition;
  signal yfine_4_3 : yposition;
  signal yfine_3_2 : yposition;
  signal yfine_2_1 : yposition;
  signal yfine_1_0 : yposition;
  signal yfine_0_bp : yposition;
  signal border_7_6 : std_logic;
  signal border_6_5 : std_logic;
  signal border_5_4 : std_logic;
  signal border_4_3 : std_logic;
  signal border_3_2 : std_logic;
  signal border_2_1 : std_logic;
  signal border_1_0 : std_logic;
  signal border_0_bp : std_logic;
  signal is_sprite_7_6 : std_logic;
  signal is_sprite_6_5 : std_logic;
  signal is_sprite_5_4 : std_logic;
  signal is_sprite_4_3 : std_logic;
  signal is_sprite_3_2 : std_logic;
  signal is_sprite_2_1 : std_logic;
  signal is_sprite_1_0 : std_logic;
  signal is_sprite_0_bp : std_logic;
  signal is_sprite_final : std_logic;
  signal alt_palette_7_6 : std_logic;
  signal alt_palette_6_5 : std_logic;
  signal alt_palette_5_4 : std_logic;
  signal alt_palette_4_3 : std_logic;
  signal alt_palette_3_2 : std_logic;
  signal alt_palette_2_1 : std_logic;
  signal alt_palette_1_0 : std_logic;
  signal alt_palette_0_bp : std_logic;
  signal alt_palette_final : std_logic;
  signal sprite_number_7_6 : integer range 0 to 7;
  signal sprite_number_6_5 : integer range 0 to 7;
  signal sprite_number_5_4 : integer range 0 to 7;
  signal sprite_number_4_3 : integer range 0 to 7;
  signal sprite_number_3_2 : integer range 0 to 7;
  signal sprite_number_2_1 : integer range 0 to 7;
  signal sprite_number_1_0 : integer range 0 to 7;
  signal sprite_number_0_bp : integer range 0 to 7;
  signal sprite_number_final : integer range 0 to 7;  
  signal sprite_colour_7_6 : unsigned(7 downto 0);
  signal sprite_colour_6_5 : unsigned(7 downto 0);
  signal sprite_colour_5_4 : unsigned(7 downto 0);
  signal sprite_colour_4_3 : unsigned(7 downto 0);
  signal sprite_colour_3_2 : unsigned(7 downto 0);
  signal sprite_colour_2_1 : unsigned(7 downto 0);
  signal sprite_colour_1_0 : unsigned(7 downto 0);  
  signal sprite_colour_0_bp : unsigned(7 downto 0);  
  signal sprite_colour_final : unsigned(7 downto 0) := x"00";  
  signal pixel_7_6 : unsigned(7 downto 0);
  signal pixel_6_5 : unsigned(7 downto 0);
  signal pixel_5_4 : unsigned(7 downto 0);
  signal pixel_4_3 : unsigned(7 downto 0);
  signal pixel_3_2 : unsigned(7 downto 0);
  signal pixel_2_1 : unsigned(7 downto 0);
  signal pixel_1_0 : unsigned(7 downto 0);  
  signal pixel_0_bp : unsigned(7 downto 0);  
  signal pixel_final : unsigned(7 downto 0);  
  signal alpha_7_6 : unsigned(7 downto 0);
  signal alpha_6_5 : unsigned(7 downto 0);
  signal alpha_5_4 : unsigned(7 downto 0);
  signal alpha_4_3 : unsigned(7 downto 0);
  signal alpha_3_2 : unsigned(7 downto 0);
  signal alpha_2_1 : unsigned(7 downto 0);
  signal alpha_1_0 : unsigned(7 downto 0);  
  signal alpha_0_bp : unsigned(7 downto 0);  
  signal alpha_final : unsigned(7 downto 0);  

begin

  -- The eight VIC-II sprites.
  -- Sprite 0 is "above" sprite 7, so sprite 7 must be the first in the chain.
  sprite7: entity work.sprite
    port map(pixelclock => pixelclock,
             -- Receive sprite data chain to receive data from the VIC-IV
             sprite_datavalid_in => sprite_datavalid_in,
             sprite_bytenumber_in => sprite_bytenumber_in,
             sprite_spritenumber_in => sprite_spritenumber_in,
             sprite_data_in => sprite_data_in,
             
             -- and to pass it out to the next sprite
             sprite_datavalid_out => sprite_datavalid_7_6,
             sprite_bytenumber_out => sprite_bytenumber_7_6,
             sprite_spritenumber_out => sprite_spritenumber_7_6,
             sprite_data_out => sprite_data_7_6,
             
             -- Sprite offset data chain for VIC-IV
             sprite_number_for_data_in => sprite_number_for_data_in,
             sprite_data_offset_in
	      => 0,
             sprite_data_offset_out => sprite_data_offset_7_6,
             sprite_number_for_data_out => sprite_number_for_data_7_6,

             sprite_extended_height_size => sprite_extended_height_size,
             sprite_extended_height_enable => sprite_extended_height_enables(7),
             sprite_extended_width_enable => sprite_extended_width_enables(7),
             sprite_horizontal_tile_enable => sprite_horizontal_tile_enables(7),
             sprite_bitplane_enable => sprite_bitplane_enables(7),
             sprite_sixteen_colour_mode => sprite_sixteen_colour_enables(7),

             -- pixel data
             is_foreground_in => is_foreground_in,
             is_background_in => is_background_in,
             sprite_h640 => sprite_h640,
             sprite_v400 => sprite_v400s(7),
             pipeline_delay => pipeline_delay_latched,
             x320_in => x320_in,
             x640_in => x640_in,
             y_in => y_in,
             yfine_in => yfine_in,
             border_in => border_in,
             alt_palette_in => alt_palette_in,
             pixel_in => pixel_in,
             alpha_in => alpha_in,
             is_sprite_in => '0',
             sprite_number_in => 0,
             sprite_colour_in => x"00",
             is_foreground_out => is_foreground_7_6,
             is_background_out => is_background_7_6,
             x320_out => x320_7_6,
             x640_out => x640_7_6,
             y_out => y_7_6,
             yfine_out => yfine_7_6,
             border_out => border_7_6,
             alt_palette_out => alt_palette_7_6,
             pixel_out => pixel_7_6,
             alpha_out => alpha_7_6,
             is_sprite_out => is_sprite_7_6,
             sprite_number_out => sprite_number_7_6,
             sprite_colour_out => sprite_colour_7_6,
             
             -- Also pass in sprite data
             sprite_number => 7,
             sprite_x(9) => sprite_h640_msbs(7),
             sprite_x(8) => vicii_sprite_xmsbs(7),
             sprite_x(7 downto 0) => sprite_x(7),
             sprite_y(7 downto 0) => sprite_y(7),
             sprite_y(8) => sprite_v400_msbs(7),
             sprite_y(9) => sprite_v400_super_msbs(7),
             sprite_colour => sprite_colours(7),
             sprite_enable => vicii_sprite_enables(7),
             sprite_priority => vicii_sprite_priority_bits(7),
             sprite_multi0_colour => sprite_multi0_colour,
             sprite_multi1_colour => sprite_multi1_colour,
             sprite_is_multicolour => vicii_sprite_multicolour_bits(7),
             sprite_stretch_x => vicii_sprite_x_expand(7),
             sprite_stretch_y => vicii_sprite_y_expand(7),
             sprite_map_in => x"00",
             sprite_fg_map_in => "00000000",
             sprite_map_out => sprite_map_7_6,
             sprite_fg_map_out => sprite_fg_map_7_6
             );
  sprite6: entity work.sprite
    port map(pixelclock => pixelclock,
             -- Receive sprite data chain to receive data from VIC-IV
             sprite_datavalid_in => sprite_datavalid_7_6,
             sprite_bytenumber_in => sprite_bytenumber_7_6,
             sprite_spritenumber_in => sprite_spritenumber_7_6,
             sprite_data_in => sprite_data_7_6,
             -- and to pass it out to the next sprite
             sprite_datavalid_out => sprite_datavalid_6_5,
             sprite_bytenumber_out => sprite_bytenumber_6_5,
             sprite_spritenumber_out => sprite_spritenumber_6_5,
             sprite_data_out => sprite_data_6_5,

             -- Sprite offset data chain for VIC-IV
             sprite_number_for_data_in => sprite_number_for_data_7_6,
             sprite_data_offset_in
	      => sprite_data_offset_7_6,
             sprite_data_offset_out => sprite_data_offset_6_5,
             sprite_number_for_data_out => sprite_number_for_data_6_5,

             sprite_extended_height_size => sprite_extended_height_size,
             sprite_extended_height_enable => sprite_extended_height_enables(6),
             sprite_extended_width_enable => sprite_extended_width_enables(6),
             sprite_horizontal_tile_enable => sprite_horizontal_tile_enables(6),
             sprite_bitplane_enable => sprite_bitplane_enables(6),
             sprite_sixteen_colour_mode => sprite_sixteen_colour_enables(6),

             -- pixel data
             is_foreground_in => is_foreground_7_6,
             is_background_in => is_background_7_6,
             sprite_h640 => sprite_h640,
             sprite_v400 => sprite_v400s(6),
             pipeline_delay => pipeline_delay,
             x320_in => x320_7_6,
             x640_in => x640_7_6,
             y_in => y_7_6,
             yfine_in => yfine_7_6,
             border_in => border_7_6,
             alt_palette_in => alt_palette_7_6,
             pixel_in => pixel_7_6,
             alpha_in => alpha_7_6,
             is_sprite_in => is_sprite_7_6,
             sprite_number_in => sprite_number_7_6,
             sprite_colour_in => sprite_colour_7_6,
             is_foreground_out => is_foreground_6_5,
             is_background_out => is_background_6_5,
             x320_out => x320_6_5,
             x640_out => x640_6_5,
             y_out => y_6_5,
             yfine_out => yfine_6_5,
             border_out => border_6_5,
             alt_palette_out => alt_palette_6_5,
             pixel_out => pixel_6_5,
             alpha_out => alpha_6_5,
             is_sprite_out => is_sprite_6_5,
             sprite_number_out => sprite_number_6_5,
             sprite_colour_out => sprite_colour_6_5,
             
             -- Also pass in sprite data
             sprite_number => 6,
             sprite_x(9) => sprite_h640_msbs(6),
             sprite_x(8) => vicii_sprite_xmsbs(6),
             sprite_x(7 downto 0) => sprite_x(6),
             sprite_y(7 downto 0) => sprite_y(6),
             sprite_y(8) => sprite_v400_msbs(6),
             sprite_y(9) => sprite_v400_super_msbs(6),
             sprite_colour => sprite_colours(6),
             sprite_enable => vicii_sprite_enables(6),
             sprite_priority => vicii_sprite_priority_bits(6),
             sprite_multi0_colour => sprite_multi0_colour,
             sprite_multi1_colour => sprite_multi1_colour,
             sprite_is_multicolour => vicii_sprite_multicolour_bits(6),
             sprite_stretch_x => vicii_sprite_x_expand(6),
             sprite_stretch_y => vicii_sprite_y_expand(6),

             sprite_fg_map_in => sprite_fg_map_7_6,
             sprite_map_in => sprite_map_7_6,
             sprite_map_out => sprite_map_6_5,
             sprite_fg_map_out => sprite_fg_map_6_5
             );
    sprite5: entity work.sprite
    port map(pixelclock => pixelclock,
             -- Receive sprite data chain to receive data from VIC-IV
             sprite_datavalid_in => sprite_datavalid_6_5,
             sprite_bytenumber_in => sprite_bytenumber_6_5,
             sprite_spritenumber_in => sprite_spritenumber_6_5,
             sprite_data_in => sprite_data_6_5,
             -- and to pass it out to the next sprite
             sprite_datavalid_out => sprite_datavalid_5_4,
             sprite_bytenumber_out => sprite_bytenumber_5_4,
             sprite_spritenumber_out => sprite_spritenumber_5_4,
             sprite_data_out => sprite_data_5_4,

             -- Sprite offset data chain for VIC-IV
             sprite_number_for_data_in => sprite_number_for_data_6_5,
             sprite_data_offset_in
	      => sprite_data_offset_6_5,
             sprite_data_offset_out => sprite_data_offset_5_4,
             sprite_number_for_data_out => sprite_number_for_data_5_4,

             sprite_extended_height_size => sprite_extended_height_size,
             sprite_extended_height_enable => sprite_extended_height_enables(5),
             sprite_extended_width_enable => sprite_extended_width_enables(5),
             sprite_horizontal_tile_enable => sprite_horizontal_tile_enables(5),
             sprite_bitplane_enable => sprite_bitplane_enables(5),
             sprite_sixteen_colour_mode => sprite_sixteen_colour_enables(5),

             -- pixel data
             is_foreground_in => is_foreground_6_5,
             is_background_in => is_background_6_5,
             sprite_h640 => sprite_h640,
             sprite_v400 => sprite_v400s(5),
             pipeline_delay => pipeline_delay,
             x320_in => x320_6_5,
             x640_in => x640_6_5,
             y_in => y_6_5,
             yfine_in => yfine_6_5,
             border_in => border_6_5,
             alt_palette_in => alt_palette_6_5,
             pixel_in => pixel_6_5,
             alpha_in => alpha_6_5,
             is_sprite_in => is_sprite_6_5,
             sprite_number_in => sprite_number_6_5,
             sprite_colour_in => sprite_colour_6_5,
             is_foreground_out => is_foreground_5_4,
             is_background_out => is_background_5_4,
             x320_out => x320_5_4,
             x640_out => x640_5_4,
             y_out => y_5_4,
             yfine_out => yfine_5_4,
             border_out => border_5_4,
             alt_palette_out => alt_palette_5_4,
             pixel_out => pixel_5_4,
             alpha_out => alpha_5_4,
             is_sprite_out => is_sprite_5_4,
             sprite_number_out => sprite_number_5_4,
             sprite_colour_out => sprite_colour_5_4,
             
             -- Also pass in sprite data
             sprite_number => 5,
             sprite_x(9) => sprite_h640_msbs(5),
             sprite_x(8) => vicii_sprite_xmsbs(5),
             sprite_x(7 downto 0) => sprite_x(5),
             sprite_y(7 downto 0) => sprite_y(5),
             sprite_y(8) => sprite_v400_msbs(5),
             sprite_y(9) => sprite_v400_super_msbs(5),
             sprite_colour => sprite_colours(5),
             sprite_enable => vicii_sprite_enables(5),
             sprite_priority => vicii_sprite_priority_bits(5),
             sprite_multi0_colour => sprite_multi0_colour,
             sprite_multi1_colour => sprite_multi1_colour,
             sprite_is_multicolour => vicii_sprite_multicolour_bits(5),
             sprite_stretch_x => vicii_sprite_x_expand(5),
             sprite_stretch_y => vicii_sprite_y_expand(5),

             sprite_fg_map_in => sprite_fg_map_6_5,
             sprite_map_in => sprite_map_6_5,
             sprite_map_out => sprite_map_5_4,
             sprite_fg_map_out => sprite_fg_map_5_4
             );
    sprite4: entity work.sprite
    port map(pixelclock => pixelclock,
             -- Receive sprite data chain to receive data from VIC-IV
             sprite_datavalid_in => sprite_datavalid_5_4,
             sprite_bytenumber_in => sprite_bytenumber_5_4,
             sprite_spritenumber_in => sprite_spritenumber_5_4,
             sprite_data_in => sprite_data_5_4,
             -- and to pass it out to the next sprite
             sprite_datavalid_out => sprite_datavalid_4_3,
             sprite_bytenumber_out => sprite_bytenumber_4_3,
             sprite_spritenumber_out => sprite_spritenumber_4_3,
             sprite_data_out => sprite_data_4_3,

             sprite_extended_height_size => sprite_extended_height_size,
             sprite_extended_height_enable => sprite_extended_height_enables(4),
             sprite_extended_width_enable => sprite_extended_width_enables(4),
             sprite_horizontal_tile_enable => sprite_horizontal_tile_enables(4),
             sprite_bitplane_enable => sprite_bitplane_enables(4),
             sprite_sixteen_colour_mode => sprite_sixteen_colour_enables(4),

             -- Sprite offset data chain for VIC-IV
             sprite_number_for_data_in => sprite_number_for_data_5_4,
             sprite_data_offset_in
	      => sprite_data_offset_5_4,
             sprite_data_offset_out => sprite_data_offset_4_3,
             sprite_number_for_data_out => sprite_number_for_data_4_3,

             -- pixel data
             is_foreground_in => is_foreground_5_4,
             is_background_in => is_background_5_4,
             sprite_h640 => sprite_h640,
             sprite_v400 => sprite_v400s(4),
             pipeline_delay => pipeline_delay,
             x320_in => x320_5_4,
             x640_in => x640_5_4,
             y_in => y_5_4,
             yfine_in => yfine_5_4,
             border_in => border_5_4,
             alt_palette_in => alt_palette_5_4,
             pixel_in => pixel_5_4,
             alpha_in => alpha_5_4,
             is_sprite_in => is_sprite_5_4,
             sprite_number_in => sprite_number_5_4,
             sprite_colour_in => sprite_colour_5_4,
             is_foreground_out => is_foreground_4_3,
             is_background_out => is_background_4_3,
             x320_out => x320_4_3,
             x640_out => x640_4_3,
             y_out => y_4_3,
             yfine_out => yfine_4_3,
             border_out => border_4_3,
             alt_palette_out => alt_palette_4_3,
             pixel_out => pixel_4_3,
             alpha_out => alpha_4_3,
             is_sprite_out => is_sprite_4_3,
             sprite_number_out => sprite_number_4_3,
             sprite_colour_out => sprite_colour_4_3,
             
             -- Also pass in sprite data
             sprite_number => 4,
             sprite_x(9) => sprite_h640_msbs(4),
             sprite_x(8) => vicii_sprite_xmsbs(4),
             sprite_x(7 downto 0) => sprite_x(4),
             sprite_y(7 downto 0) => sprite_y(4),
             sprite_y(8) => sprite_v400_msbs(4),
             sprite_y(9) => sprite_v400_super_msbs(4),
             sprite_colour => sprite_colours(4),
             sprite_enable => vicii_sprite_enables(4),
             sprite_priority => vicii_sprite_priority_bits(4),
             sprite_multi0_colour => sprite_multi0_colour,
             sprite_multi1_colour => sprite_multi1_colour,
             sprite_is_multicolour => vicii_sprite_multicolour_bits(4),
             sprite_stretch_x => vicii_sprite_x_expand(4),
             sprite_stretch_y => vicii_sprite_y_expand(4),

             sprite_fg_map_in => sprite_fg_map_5_4,
             sprite_map_in => sprite_map_5_4,
             sprite_map_out => sprite_map_4_3,
             sprite_fg_map_out => sprite_fg_map_4_3
             );
    sprite3: entity work.sprite
    port map(pixelclock => pixelclock,
             -- Receive sprite data chain to receive data from VIC-IV
             sprite_datavalid_in => sprite_datavalid_4_3,
             sprite_bytenumber_in => sprite_bytenumber_4_3,
             sprite_spritenumber_in => sprite_spritenumber_4_3,
             sprite_data_in => sprite_data_4_3,
             -- and to pass it out to the next sprite
             sprite_datavalid_out => sprite_datavalid_3_2,
             sprite_bytenumber_out => sprite_bytenumber_3_2,
             sprite_spritenumber_out => sprite_spritenumber_3_2,
             sprite_data_out => sprite_data_3_2,

             sprite_extended_height_size => sprite_extended_height_size,
             sprite_extended_height_enable => sprite_extended_height_enables(3),
             sprite_extended_width_enable => sprite_extended_width_enables(3),
             sprite_horizontal_tile_enable => sprite_horizontal_tile_enables(3),
             sprite_bitplane_enable => sprite_bitplane_enables(3),
             sprite_sixteen_colour_mode => sprite_sixteen_colour_enables(3),

             -- Sprite offset data chain for VIC-IV
             sprite_number_for_data_in => sprite_number_for_data_4_3,
             sprite_data_offset_in
	      => sprite_data_offset_4_3,
             sprite_data_offset_out => sprite_data_offset_3_2,
             sprite_number_for_data_out => sprite_number_for_data_3_2,

             -- pixel data
             is_foreground_in => is_foreground_4_3,
             is_background_in => is_background_4_3,
             sprite_h640 => sprite_h640,
             sprite_v400 => sprite_v400s(3),
             pipeline_delay => pipeline_delay,
             x320_in => x320_4_3,
             x640_in => x640_4_3,
             y_in => y_4_3,
             yfine_in => yfine_4_3,
             border_in => border_4_3,
             alt_palette_in => alt_palette_4_3,
             pixel_in => pixel_4_3,
             alpha_in => alpha_4_3,
             is_sprite_in => is_sprite_4_3,
             sprite_number_in => sprite_number_4_3,
             sprite_colour_in => sprite_colour_4_3,
             is_foreground_out => is_foreground_3_2,
             is_background_out => is_background_3_2,
             x320_out => x320_3_2,
             x640_out => x640_3_2,
             y_out => y_3_2,
             yfine_out => yfine_3_2,
             border_out => border_3_2,
             alt_palette_out => alt_palette_3_2,
             pixel_out => pixel_3_2,
             alpha_out => alpha_3_2,
             is_sprite_out => is_sprite_3_2,
             sprite_number_out => sprite_number_3_2,
             sprite_colour_out => sprite_colour_3_2,
             
             -- Also pass in sprite data
             sprite_number => 3,
             sprite_x(9) => sprite_h640_msbs(3),
             sprite_x(8) => vicii_sprite_xmsbs(3),
             sprite_x(7 downto 0) => sprite_x(3),
             sprite_y(7 downto 0) => sprite_y(3),
             sprite_y(8) => sprite_v400_msbs(3),
             sprite_y(9) => sprite_v400_super_msbs(3),
             sprite_colour => sprite_colours(3),
             sprite_enable => vicii_sprite_enables(3),
             sprite_priority => vicii_sprite_priority_bits(3),
             sprite_multi0_colour => sprite_multi0_colour,
             sprite_multi1_colour => sprite_multi1_colour,
             sprite_is_multicolour => vicii_sprite_multicolour_bits(3),
             sprite_stretch_x => vicii_sprite_x_expand(3),
             sprite_stretch_y => vicii_sprite_y_expand(3),

             sprite_fg_map_in => sprite_fg_map_4_3,
             sprite_map_in => sprite_map_4_3,
             sprite_map_out => sprite_map_3_2,
             sprite_fg_map_out => sprite_fg_map_3_2
             );
    sprite2: entity work.sprite
    port map(pixelclock => pixelclock,
             -- Receive sprite data chain to receive data from VIC-IV
             sprite_datavalid_in => sprite_datavalid_3_2,
             sprite_bytenumber_in => sprite_bytenumber_3_2,
             sprite_spritenumber_in => sprite_spritenumber_3_2,
             sprite_data_in => sprite_data_3_2,
             -- and to pass it out to the next sprite
             sprite_datavalid_out => sprite_datavalid_2_1,
             sprite_bytenumber_out => sprite_bytenumber_2_1,
             sprite_spritenumber_out => sprite_spritenumber_2_1,
             sprite_data_out => sprite_data_2_1,

             sprite_extended_height_size => sprite_extended_height_size,
             sprite_extended_height_enable => sprite_extended_height_enables(2),
             sprite_extended_width_enable => sprite_extended_width_enables(2),
             sprite_horizontal_tile_enable => sprite_horizontal_tile_enables(2),
             sprite_bitplane_enable => sprite_bitplane_enables(2),
             sprite_sixteen_colour_mode => sprite_sixteen_colour_enables(2),
             
             -- Sprite offset data chain for VIC-IV
             sprite_number_for_data_in => sprite_number_for_data_3_2,
             sprite_data_offset_in
	      => sprite_data_offset_3_2,
             sprite_data_offset_out => sprite_data_offset_2_1,
             sprite_number_for_data_out => sprite_number_for_data_2_1,

             -- pixel data
             is_foreground_in => is_foreground_3_2,
             is_background_in => is_background_3_2,
             sprite_h640 => sprite_h640,
             sprite_v400 => sprite_v400s(2),
             pipeline_delay => pipeline_delay,
             x320_in => x320_3_2,
             x640_in => x640_3_2,
             y_in => y_3_2,
             yfine_in => yfine_3_2,
             border_in => border_3_2,
             alt_palette_in => alt_palette_3_2,
             pixel_in => pixel_3_2,
             alpha_in => alpha_3_2,
             is_sprite_in => is_sprite_3_2,
             sprite_number_in => sprite_number_3_2,
             sprite_colour_in => sprite_colour_3_2,
             is_foreground_out => is_foreground_2_1,
             is_background_out => is_background_2_1,
             x320_out => x320_2_1,
             x640_out => x640_2_1,
             y_out => y_2_1,
             yfine_out => yfine_2_1,
             border_out => border_2_1,
             alt_palette_out => alt_palette_2_1,
             pixel_out => pixel_2_1,
             alpha_out => alpha_2_1,
             is_sprite_out => is_sprite_2_1,
             sprite_number_out => sprite_number_2_1,
             sprite_colour_out => sprite_colour_2_1,
             
             -- Also pass in sprite data
             sprite_number => 2,
             sprite_x(9) => sprite_h640_msbs(2),
             sprite_x(8) => vicii_sprite_xmsbs(2),
             sprite_x(7 downto 0) => sprite_x(2),
             sprite_y(7 downto 0) => sprite_y(2),
             sprite_y(8) => sprite_v400_msbs(2),
             sprite_y(9) => sprite_v400_super_msbs(2),
             sprite_colour => sprite_colours(2),
             sprite_enable => vicii_sprite_enables(2),
             sprite_priority => vicii_sprite_priority_bits(2),
             sprite_multi0_colour => sprite_multi0_colour,
             sprite_multi1_colour => sprite_multi1_colour,
             sprite_is_multicolour => vicii_sprite_multicolour_bits(2),
             sprite_stretch_x => vicii_sprite_x_expand(2),
             sprite_stretch_y => vicii_sprite_y_expand(2),

             sprite_fg_map_in => sprite_fg_map_3_2,
             sprite_map_in => sprite_map_3_2,
             sprite_map_out => sprite_map_2_1,
             sprite_fg_map_out => sprite_fg_map_2_1
             );
    sprite1: entity work.sprite
    port map(pixelclock => pixelclock,
             -- Receive sprite data chain to receive data from VIC-IV
             sprite_datavalid_in => sprite_datavalid_2_1,
             sprite_bytenumber_in => sprite_bytenumber_2_1,
             sprite_spritenumber_in => sprite_spritenumber_2_1,
             sprite_data_in => sprite_data_2_1,
             -- and to pass it out to the next sprite
             sprite_datavalid_out => sprite_datavalid_1_0,
             sprite_bytenumber_out => sprite_bytenumber_1_0,
             sprite_spritenumber_out => sprite_spritenumber_1_0,
             sprite_data_out => sprite_data_1_0,

             sprite_extended_height_size => sprite_extended_height_size,
             sprite_extended_height_enable => sprite_extended_height_enables(1),
             sprite_extended_width_enable => sprite_extended_width_enables(1),
             sprite_horizontal_tile_enable => sprite_horizontal_tile_enables(1),
             sprite_bitplane_enable => sprite_bitplane_enables(1),
             sprite_sixteen_colour_mode => sprite_sixteen_colour_enables(1),
             
             -- Sprite offset data chain for VIC-IV
             sprite_number_for_data_in => sprite_number_for_data_2_1,
             sprite_data_offset_in
	      => sprite_data_offset_2_1,
             sprite_data_offset_out => sprite_data_offset_1_0,
             sprite_number_for_data_out => sprite_number_for_data_1_0,

             -- pixel data
             is_foreground_in => is_foreground_2_1,
             is_background_in => is_background_2_1,
             sprite_h640 => sprite_h640,
             sprite_v400 => sprite_v400s(1),
             pipeline_delay => pipeline_delay,
             x320_in => x320_2_1,
             x640_in => x640_2_1,
             y_in => y_2_1,
             yfine_in => yfine_2_1,
             border_in => border_2_1,
             alt_palette_in => alt_palette_2_1,
             pixel_in => pixel_2_1,
             alpha_in => alpha_2_1,
             is_sprite_in => is_sprite_2_1,
             sprite_number_in => sprite_number_2_1,
             sprite_colour_in => sprite_colour_2_1,
             is_foreground_out => is_foreground_1_0,
             is_background_out => is_background_1_0,
             x320_out => x320_1_0,
             x640_out => x640_1_0,
             y_out => y_1_0,
             yfine_out => yfine_1_0,
             border_out => border_1_0,
             alt_palette_out => alt_palette_1_0,
             pixel_out => pixel_1_0,
             alpha_out => alpha_1_0,
             is_sprite_out => is_sprite_1_0,
             sprite_number_out => sprite_number_1_0,
             sprite_colour_out => sprite_colour_1_0,
             
             -- Also pass in sprite data
             sprite_number => 1,
             sprite_x(9) => sprite_h640_msbs(1),
             sprite_x(8) => vicii_sprite_xmsbs(1),
             sprite_x(7 downto 0) => sprite_x(1),
             sprite_y(7 downto 0) => sprite_y(1),
             sprite_y(8) => sprite_v400_msbs(1),
             sprite_y(9) => sprite_v400_super_msbs(1),
             sprite_colour => sprite_colours(1),
             sprite_enable => vicii_sprite_enables(1),
             sprite_priority => vicii_sprite_priority_bits(1),
             sprite_multi0_colour => sprite_multi0_colour,
             sprite_multi1_colour => sprite_multi1_colour,
             sprite_is_multicolour => vicii_sprite_multicolour_bits(1),
             sprite_stretch_x => vicii_sprite_x_expand(1),
             sprite_stretch_y => vicii_sprite_y_expand(1),

             sprite_fg_map_in => sprite_fg_map_2_1,
             sprite_map_in => sprite_map_2_1,
             sprite_map_out => sprite_map_1_0,
             sprite_fg_map_out => sprite_fg_map_1_0
             );
    sprite0: entity work.sprite
    port map(pixelclock => pixelclock,
             -- Receive sprite data chain to receive data from VIC-IV
             sprite_datavalid_in => sprite_datavalid_1_0,
             sprite_bytenumber_in => sprite_bytenumber_1_0,
             sprite_spritenumber_in => sprite_spritenumber_1_0,
             sprite_data_in => sprite_data_1_0,
             -- and to pass it out to the next sprite
             sprite_datavalid_out => sprite_datavalid_0_bp,
             sprite_bytenumber_out => sprite_bytenumber_0_bp,
             sprite_spritenumber_out => sprite_spritenumber_0_bp,
             sprite_data_out => sprite_data_0_bp,

             sprite_extended_height_size => sprite_extended_height_size,
             sprite_extended_height_enable => sprite_extended_height_enables(0),
             sprite_extended_width_enable => sprite_extended_width_enables(0),
             sprite_horizontal_tile_enable => sprite_horizontal_tile_enables(0),
             sprite_bitplane_enable => sprite_bitplane_enables(0),
             sprite_sixteen_colour_mode => sprite_sixteen_colour_enables(0),

             -- Sprite offset data chain for VIC-IV
             sprite_number_for_data_in => sprite_number_for_data_1_0,
             sprite_data_offset_in
	      => sprite_data_offset_1_0,
             sprite_data_offset_out => sprite_data_offset_0_bp,
             sprite_number_for_data_out => sprite_number_for_data_0_bp,

             -- pixel data
             is_foreground_in => is_foreground_1_0,
             is_background_in => is_background_1_0,
             sprite_h640 => sprite_h640,
             sprite_v400 => sprite_v400s(0),
             pipeline_delay => pipeline_delay,
             x320_in => x320_1_0,
             x640_in => x640_1_0,
             y_in => y_1_0,
             yfine_in => yfine_1_0,
             border_in => border_1_0,
             alt_palette_in => alt_palette_1_0,
             pixel_in => pixel_1_0,
             alpha_in => alpha_1_0,
             is_sprite_in => is_sprite_1_0,
             sprite_number_in => sprite_number_1_0,
             sprite_colour_in => sprite_colour_1_0,
             is_foreground_out => is_foreground_0_bp,
             is_background_out => is_background_0_bp,
             x320_out => x320_0_bp,
             x640_out => x640_0_bp,
	     yfine_out => yfine_0_bp,
             y_out => y_0_bp,
             border_out => border_0_bp,
             alt_palette_out => alt_palette_0_bp,
             pixel_out => pixel_0_bp,
             alpha_out => alpha_0_bp,
             is_sprite_out => is_sprite_0_bp,
             sprite_number_out => sprite_number_0_bp,
             sprite_colour_out => sprite_colour_0_bp,
             
             -- Also pass in sprite data
             sprite_number => 0,
             sprite_x(9) => sprite_h640_msbs(0),
             sprite_x(8) => vicii_sprite_xmsbs(0),
             sprite_x(7 downto 0) => sprite_x(0),
             sprite_y(7 downto 0) => sprite_y(0),
             sprite_y(8) => sprite_v400_msbs(0),
             sprite_y(9) => sprite_v400_super_msbs(0),
             sprite_colour => sprite_colours(0),
             sprite_enable => vicii_sprite_enables(0),
             sprite_priority => vicii_sprite_priority_bits(0),
             sprite_multi0_colour => sprite_multi0_colour,
             sprite_multi1_colour => sprite_multi1_colour,
             sprite_is_multicolour => vicii_sprite_multicolour_bits(0),
             sprite_stretch_x => vicii_sprite_x_expand(0),
             sprite_stretch_y => vicii_sprite_y_expand(0),

             sprite_fg_map_in => sprite_fg_map_1_0,
             sprite_map_in => sprite_map_1_0,
             sprite_map_out => sprite_map_0_bp,
             sprite_fg_map_out => sprite_fg_map_0_bp
             );

  bitplanes0: entity work.bitplanes
    port map(pixelclock => pixelclock,
             cpuclock => cpuclock,

             fastio_address => unsigned(fastio_addr),
             fastio_wdata => unsigned(fastio_wdata),
             fastio_write => fastio_write,

             -- Bitplane mode information
             bitplane_h640 => bitplane_h640,
             bitplane_h1280 => bitplane_h1280,
             bitplane_mode_in => bitplane_mode_in,
             bitplane_enables_in => bitplane_enables_in,
             bitplane_complements_in => bitplane_complements_in,
             bitplanes_y_start => bitplanes_y_start,
             bitplanes_x_start => bitplanes_x_start,
             bitplane_sixteen_colour_mode_flags =>
               bitplane_sixteen_colour_mode_flags_in,
             
             -- Receive sprite data chain to receive data from VIC-IV
             sprite_datavalid_in => sprite_datavalid_0_bp,
             sprite_bytenumber_in => sprite_bytenumber_0_bp,
             sprite_spritenumber_in => sprite_spritenumber_0_bp,
             sprite_data_in => sprite_data_0_bp,

             -- and to pass it out to the next sprite
             sprite_datavalid_out => sprite_datavalid_out,
             sprite_bytenumber_out => sprite_bytenumber_out,
             sprite_spritenumber_out => sprite_spritenumber_out,
             sprite_data_out => sprite_data_out,

             -- XXX Bitplane registers here
             
             -- Sprite offset data chain for VIC-IV
             sprite_number_for_data_in => sprite_number_for_data_0_bp,
             sprite_data_offset_in
	      => sprite_data_offset_0_bp,
             sprite_data_offset_out => sprite_data_offset_out,
             sprite_number_for_data_out => sprite_number_for_data_out,

             -- pixel data
             is_foreground_in => is_foreground_0_bp,
             is_background_in => is_background_0_bp,
             x_in => x320_0_bp,
             x640_in => x640_0_bp,
             x1280_in => x640_0_bp,
             y_in => y_0_bp,
	     yfine_in => yfine_0_bp,
             border_in => border_0_bp,
             alt_palette_in => alt_palette_0_bp,
             pixel_in => pixel_0_bp,
             alpha_in => alpha_0_bp,
             is_sprite_in => is_sprite_0_bp,
             sprite_number_in => sprite_number_0_bp,
             sprite_colour_in => sprite_colour_0_bp,
             is_foreground_out => is_foreground_out,
             is_background_out => is_background_out,
             x_out => x_out,
             y_out => y_out,
             border_out => border_out,
             alt_palette_out => alt_palette_final,
             pixel_out => pixel_final,
             alpha_out => alpha_final,
             is_sprite_out => is_sprite_final,
             sprite_number_out => sprite_number_final,
             sprite_colour_out => sprite_colour_final,
             
             sprite_fg_map_in => sprite_fg_map_0_bp,
             sprite_map_in => sprite_map_0_bp,
             sprite_map_out => sprite_map_final,
             sprite_fg_map_out => sprite_fg_map_final
             );

  
  process(cpuclock,pixelclock,fastio_addr,is_sprite_final,sprite_colour_final,alt_palette_final,pixel_final,alpha_final) is
    variable register_bank : unsigned(7 downto 0) := x"00";
    variable register_page : unsigned(3 downto 0) := "0000";
    variable register_num : unsigned(7 downto 0) := x"00";
    variable register_number : unsigned(11 downto 0) := x"000";
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

    if rising_edge(pixelclock) then
      pipeline_delay_latched <= pipeline_delay;
    end if;   
    
    -- Snoop fastio bus to obtain sprite register values.
    -- (We also have to snoop $D02F and $D031 so that we know if VIC-III
    -- extended attributes are enabled.  If so, sprite colour registers are
    -- 8-bit (256 colour) instead of 4-bit (16 colour).
    if rising_edge(cpuclock) then
      if fastio_write='1'
        and (fastio_addr(19) = '0' or fastio_addr(19) = '1') then        
        if register_number>=0 and register_number<16 then
                                        -- compatibility sprite coordinates
          if register_num(0)='0' then
            sprite_x(to_integer(register_num(3 downto 1))) <= unsigned(fastio_wdata);
          else
            sprite_y(to_integer(register_num(3 downto 1))) <= unsigned(fastio_wdata);
          end if;
        elsif register_number=16 then
          vicii_sprite_xmsbs <= fastio_wdata;
        elsif register_number=21 then          -- $D015 compatibility sprite enable
          vicii_sprite_enables <= fastio_wdata;
        elsif register_number=23 then          -- $D017 compatibility sprite enable
          vicii_sprite_y_expand <= fastio_wdata;
        elsif register_number=27 then          -- $D01B sprite background priority
          vicii_sprite_priority_bits <= fastio_wdata;
        elsif register_number=28 then          -- $D01C sprite multicolour
          vicii_sprite_multicolour_bits <= fastio_wdata;
        elsif register_number=29 then          -- $D01D compatibility sprite enable
          vicii_sprite_x_expand <= fastio_wdata;
        elsif register_number=37 then
          if (fastio_addr(19 downto 12)=x"D0" or fastio_addr(19 downto 12)=x"D2") then
            sprite_multi0_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            sprite_multi0_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=38 then
          if (fastio_addr(19 downto 12)=x"D0" or fastio_addr(19 downto 12)=x"D2") then
            sprite_multi1_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            sprite_multi1_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number>=39 and register_number<=46 then
          if (fastio_addr(19 downto 12)=x"D0" or fastio_addr(19 downto 12)=x"D2") then
            sprite_colours(to_integer(register_number)-39) <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            sprite_colours(to_integer(register_number)-39) <= unsigned(fastio_wdata);
          end if;
        elsif register_number=49 then
          viciii_extended_attributes <= fastio_wdata(5);
        elsif register_number=95 then
          sprite_h640_msbs <= fastio_wdata;
        elsif register_number=119 then  -- $D3077
          -- $D077 Sprite V400 Y position MSBs
          sprite_v400_msbs <= fastio_wdata;          
        elsif register_number=120 then  -- $D3078
          -- $D078 Sprite V400 Y position superMSBs
          sprite_v400_super_msbs <= fastio_wdata;          
        end if;
      end if;
    end if;
  end process;

  process(pixelclock,sprite_number_final,is_sprite_final,sprite_colour_final,alt_palette_final,
          pixel_final,alpha_final) is
  begin
    -- Merge chargen and sprite pixels
    sprite_number_out <= sprite_number_final;
    is_sprite_out <= is_sprite_final;
    if is_sprite_final = '1' then
      report "VIC-II: SPRITE: Compositing sprite pixel colour $" & to_hstring(sprite_colour_final);
      pixel_out <= sprite_colour_final;
      -- XXX Do we need to make sure we have the foreground and background
      -- values set correctly here for the alpha blending?
      alpha_out <= x"ff";
      alt_palette_out <= '0';
    else
      alt_palette_out <= alt_palette_final;
      pixel_out <= pixel_final;
      alpha_out <= alpha_final;
    end if;

  end process;
  
end behavioural;
