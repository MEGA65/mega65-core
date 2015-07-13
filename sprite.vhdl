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

entity sprite is
  Port (
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;

    signal sprite_number : in integer range 0 to 15;

    signal sprite_horizontal_tile_enable : in std_logic;
    signal sprite_bitplane_enable : in std_logic;
    signal sprite_extended_height_enable : in std_logic;
    signal sprite_extended_width_enable : in std_logic;
    signal sprite_extended_height_size : in unsigned(7 downto 0);  

    -- Pull sprite data in along the chain from the previous sprite (or VIC-IV)
    signal sprite_datavalid_in : in std_logic;
    signal sprite_bytenumber_in : in integer range 0 to 79;
    signal sprite_spritenumber_in : in integer range 0 to 15;
    signal sprite_data_in : in unsigned(7 downto 0);

    -- Pass sprite data out along the chain to the next sprite
    signal sprite_datavalid_out : out std_logic;
    signal sprite_bytenumber_out : out integer range 0 to 79;
    signal sprite_spritenumber_out : out integer range 0 to 15;
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
    signal sprite_fg_map_out : out std_logic_vector(7 downto 0);
    
    signal sprite_enable : in std_logic;
    signal sprite_x : in unsigned(8 downto 0);
    signal sprite_y : in unsigned(7 downto 0);
    signal sprite_colour : in unsigned(7 downto 0);
    signal sprite_multi0_colour : in unsigned(7 downto 0);
    signal sprite_multi1_colour : in unsigned(7 downto 0);
    signal sprite_is_multicolour : in std_logic;
    signal sprite_stretch_x : in std_logic;
    signal sprite_stretch_y : in std_logic;
    signal sprite_priority : in std_logic

);

end sprite;

architecture behavioural of sprite is

  signal sprite_data_offset : integer range 0 to 1023;    
  signal y_last : integer range 0 to 4095;
  signal x_last : integer range 0 to 4095;
  signal x_left : std_logic := '0';
  signal y_top : std_logic := '0';
  signal y_offset : integer range 0 to 255;
  signal x_offset : integer range 0 to 64;
  signal x_is_odd : std_logic := '0';
  signal x_in_sprite : std_logic := '0';
  signal sprite_drawing : std_logic := '0';
  signal x_expand_toggle : std_logic := '0';
  signal y_expand_toggle : std_logic := '0';
  signal sprite_pixel_bits_mono : std_logic_vector(127 downto 0) := (others => '1');
  signal sprite_pixel_bits_mc : std_logic_vector(127 downto 0) := (others => '1');
  signal sprite_pixel_bits : std_logic_vector(127 downto 0) := (others => '1');
  signal sprite_data_64bits : unsigned(63 downto 0);
  signal check_colissions : std_logic := '0';
  
begin  -- behavioural
  
  -- purpose: sprite drawing
  -- type   : sequential
  -- inputs : pixelclock, <reset>
  -- outputs: colour, is_sprite_out
  main: process (pixelclock)
    variable sprite_number_mod_4 : integer range 0 to 7 := (sprite_number mod 4) * 2;
  begin  -- process main
    if pixelclock'event and pixelclock = '1' then  -- rising clock edge
--      report "SPRITE: entering VIC-II sprite #" & integer'image(sprite_number);
      -- copy sprite data chain from input side to output side      
      sprite_spritenumber_out <= sprite_spritenumber_in;
      sprite_datavalid_out <= sprite_datavalid_in;
      sprite_bytenumber_out <= sprite_bytenumber_in;
      sprite_data_out <= sprite_data_in;
      sprite_number_for_data_out <= sprite_number_for_data_in;

      if sprite_datavalid_in='1' then
        report "SPRITE: fetching sprite #"
          & integer'image(sprite_spritenumber_in)
          & "."
          & integer'image(sprite_bytenumber_in)
          & " of $" & to_hstring(sprite_data_in) & " seen in sprite #"
          & integer'image(sprite_number);
      end if;
      
      if sprite_datavalid_in = '1' and sprite_spritenumber_in = sprite_number then
        -- Record sprite data
        report "SPRITE: sprite #" & integer'image(sprite_number)
          & " accepting data byte $" & to_hstring(sprite_data_in)
          & " from VIC-IV for byte #" & integer'image(sprite_bytenumber_in)
          & " vector was " & to_string(std_logic_vector(sprite_data_64bits));
        case sprite_bytenumber_in is
          when 0 => sprite_data_64bits(63 downto 56) <= sprite_data_in;
          when 1 => sprite_data_64bits(55 downto 48) <= sprite_data_in;
          when 2 => sprite_data_64bits(47 downto 40) <= sprite_data_in;
          when 3 => sprite_data_64bits(39 downto 32) <= sprite_data_in;
          when 4 => sprite_data_64bits(31 downto 24) <= sprite_data_in;
          when 5 => sprite_data_64bits(23 downto 16) <= sprite_data_in;
          when 6 => sprite_data_64bits(15 downto 8) <= sprite_data_in;
          when 7 => sprite_data_64bits(7 downto 0) <= sprite_data_in;
          when others => null;
        end case;
      end if;

      -- Every cycle update mono and multi-colour bit expansion of sprite
      for i in 0 to 63 loop
        -- mono version just copies the bits stretching each bit to two to
        -- select the foreground colour.
        sprite_pixel_bits_mono(i*2) <= '0';
        sprite_pixel_bits_mono(i*2+1) <= sprite_data_64bits(i);
      end loop;
      for i in 0 to 31 loop
        -- multi-colour version copies the bit pair twice to stretch the colour
        -- over two pixels.
        sprite_pixel_bits_mc(i*4) <= sprite_data_64bits(i*2);
        sprite_pixel_bits_mc(i*4+1) <= sprite_data_64bits(i*2+1);
        sprite_pixel_bits_mc(i*4+2) <= sprite_data_64bits(i*2);
        sprite_pixel_bits_mc(i*4+3) <= sprite_data_64bits(i*2+1);
      end loop;
      
      if sprite_number_for_data_in = sprite_number then
        -- Tell VIC-IV our current sprite data offset
        sprite_data_offset_out <= sprite_data_offset;
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
      x_left <= '0';
      y_top <= '0';
      -- sprite data offset = y_offset * 3
      if sprite_extended_width_enable='0' then
        sprite_data_offset <= (y_offset * 2) + y_offset;
      else
        sprite_data_offset <= (y_offset * 8);
      end if;
      if y_in = sprite_y then
        --report "SPRITE: y_top set";
        y_top <= '1';
        y_offset <= 0;
        y_expand_toggle <= '0';
      end if;
      --report "SPRITE: #" & integer'image(sprite_number) & ": "
      --  & "x_in=" & integer'image(x_in)
      --  & ", y_in=" & integer'image(y_in)
      --  & ", enable=" & std_logic'image(sprite_enable)
      --  & ", drawing=" & std_logic'image(sprite_drawing)
      --  & ", in_sprite=" & std_logic'image(x_in_sprite)
      --  & ", sprite_x,y=" & to_hstring("000"&sprite_x) & "," &
      --  to_hstring(sprite_y);
      if x_in = to_integer(sprite_x) and sprite_enable='1' and (y_top='1' or sprite_drawing = '1') then
        x_left <= '1';
        x_in_sprite <= '1';
        report "SPRITE: drawing row " & integer'image(y_offset)
          & " of sprite " & integer'image(sprite_number)
          & " using data bits %" & to_string(std_logic_vector(sprite_data_64bits));
        x_offset <= 0;
        x_is_odd <= '0';
        if sprite_is_multicolour = '1' then
          report "SPRITE: using multi-colour pixel vector";
          sprite_pixel_bits <= sprite_pixel_bits_mc;
        else
          report "SPRITE: using mono pixel vector";
          sprite_pixel_bits <= sprite_pixel_bits_mono;
        end if;
      else
--        report "SPRITE: not drawing a row: xcompare=" & boolean'image(x_in=sprite_x)
--          & ", sprite_x=" & integer'image(to_integer(sprite_x));
      end if;
      if x_left = '1' and y_top = '1' and sprite_enable = '1' then
        report "SPRITE: sprite start hit and enabled: drawing xoffset="
          & integer'image(x_offset);
        sprite_drawing <= '1';
      end if;
      -- Advance Y position of sprite
      if y_last /= y_in then
        y_last <= y_in;
        x_in_sprite <= '0';
        if sprite_drawing = '1' then
          -- Y position has advanced while drawing a sprite
          if y_expand_toggle = '1' or sprite_stretch_y/='1' then
            if ((sprite_extended_height_enable = '0')
                and (y_offset /= 20))
              or
              ((sprite_extended_height_enable = '1')
               and (y_offset /= sprite_extended_height_size)) then
              y_offset <= y_offset + 1;
            else
              report "SPRITE: end of sprite y reached. no longer drawing";
              sprite_drawing <= '0';
              y_offset <= 0;
            end if;
          end if;
          y_expand_toggle <= not y_expand_toggle;
          -- Check colissions whenever we start a new logical sprite pixel row, even
          -- if it is just a VIC-II stretch of the above one, since it could collide
          -- with a non-expanded sprite that starts here.
          check_colissions <= '1';
        end if;
      end if;
      -- Advance X position of sprite
      if (x_last /= x_in) and (x_in_sprite = '1') then
        -- X position has advanced while drawing a sprite
        x_last <= x_in;
        report "SPRITE: drawing next pixel";
        if (x_expand_toggle = '1') or (sprite_stretch_x/='1') then
          if ((x_offset /= 23) and (sprite_extended_width_enable='0'))
            or ((x_offset /= 63) and (sprite_extended_width_enable='1'))
            or (sprite_horizontal_tile_enable='1')
              then
            x_offset <= x_offset + 1;
            x_is_odd <= not x_is_odd;
          else
            report "SPRITE: right edge of sprite encountered. stopping drawing.";
            x_in_sprite <= '0';
            -- Only check colissions on first raster of each sprite pixel
            -- so that we don't trigger colission interrupts on each physical raster
            -- of a single pixel row of a sprite, which might cause some games
            -- to get confused and trigger the colission routine 5x for each colission
            -- instead of just once -- especially since there are ~640 CPU
            -- cycles per physical raster = ~ 3,000 CPU cycles per sprite pixel
            -- row.
            check_colissions <= '0';
          end if;
          -- shift along to next pixel
          report "SPRITE: shifting pixel vector along (was "&
            to_string(sprite_pixel_bits)
            &")";
          sprite_pixel_bits <= sprite_pixel_bits(125 downto 0)&sprite_pixel_bits(127 downto 126);
        end if;
        report "SPRITE: toggling x_expand_toggle";
        x_expand_toggle <= not x_expand_toggle;
      end if;      
      
      
      -- decide whether we are visible or not, and update sprite colour
      -- accordingly.
      -- XXX - foreground priority is not implemented.
      -- XXX - sprite colission map generation is not implemented
      -- XXX - sprites draw on top of the border?
      -- check for sprite/foreground colission
      sprite_fg_map_out <= sprite_fg_map_in;
      if (x_in_sprite='1') and (border_in='0') and (is_foreground_in='1') and
        (sprite_pixel_bits(127 downto 126) /= "00") then
        -- Sprite and foreground colission
        if check_colissions='1' then
          sprite_fg_map_out(sprite_number) <= '1';
        end if;
      end if;
      
      -- Stop drawing sprites in right fly-back, to prevent glitches with
      -- horizontally tiled sprites.
      if x_in > 416 then
        x_in_sprite <= '0';
      end if;
      
      if (sprite_bitplane_enable='1') and (x_in_sprite='1') then
        -- Bitmap mode of sprites modifies the palette entry of the
        -- sprite/graphics instead of drawing a sprite. Thus multiple
        -- sprites can be combined to get more colours, like on the Amiga,
        -- but also with the background, e.g., to modify colour of background
        -- when a "shadow" or "highlight" or sprite of other purpose is drawn
        is_sprite_out <= is_sprite_in;
        if sprite_is_multicolour = '0' then
          for bit in 0 to 7 loop
            if bit /= sprite_number then
              sprite_colour_out(bit) <= sprite_colour_in(bit);
              pixel_out(bit) <= pixel_in(bit);
            end if;
          end loop;
          pixel_out(sprite_number) <= sprite_pixel_bits(127) xor pixel_in(sprite_number);
          sprite_colour_out(sprite_number) <= sprite_pixel_bits(127) xor sprite_colour_in(sprite_number);
        else
          for bit in 0 to 7 loop
            if (bit /= sprite_number_mod_4)
               and (bit /= (sprite_number_mod_4 +1)) then
              sprite_colour_out(bit) <= sprite_colour_in(bit);
              pixel_out(bit) <= pixel_in(bit);
            end if;
          end loop;
          pixel_out(sprite_number_mod_4 + 1) <= sprite_pixel_bits(127) xor pixel_in(sprite_number_mod_4 + 1);
          pixel_out(sprite_number_mod_4) <= sprite_pixel_bits(126) xor pixel_in(sprite_number_mod_4);
          sprite_colour_out(sprite_number_mod_4 + 1) <= sprite_pixel_bits(127) xor sprite_colour_in(sprite_number_mod_4 + 1);
          sprite_colour_out(sprite_number_mod_4) <= sprite_pixel_bits(126) xor sprite_colour_in(sprite_number_mod_4);
        end if;
      else
        pixel_out <= pixel_in;
        if ((is_foreground_in='0') or (sprite_priority='0')) and (x_in_sprite='1') then
          report "SPRITE: Painting pixel using bits " & to_string(sprite_pixel_bits(127 downto 126));
          case sprite_pixel_bits(127 downto 126) is
            when "01" =>
              -- Set this sprite in the colission map        
              sprite_map_out <= sprite_map_in;
              if check_colissions='1' then
                sprite_map_out(sprite_number) <= '1';
              end if;
              is_sprite_out <= not border_in;
              sprite_colour_out <= sprite_multi0_colour;
            when "10" =>
              -- Set this sprite in the colission map        
              sprite_map_out <= sprite_map_in;
              if check_colissions='1' then
                sprite_map_out(sprite_number) <= '1';
              end if;
              is_sprite_out <= not border_in;
              sprite_colour_out <= sprite_colour;
            when "11" =>
              is_sprite_out <= not border_in;
              sprite_colour_out <= sprite_multi1_colour;
              -- Set this sprite in the colission map        
              sprite_map_out <= sprite_map_in;
              if check_colissions='1' then
                sprite_map_out(sprite_number) <= '1';
              end if;
            when others =>
              -- background shows through
              is_sprite_out <= is_sprite_in;
              sprite_colour_out <= sprite_colour_in;
          end case;
        else
          is_sprite_out <= is_sprite_in;
          sprite_colour_out <= sprite_colour_in;
          sprite_map_out <= sprite_map_in;
        end if;
      end if;
--      report "SPRITE: leaving VIC-II sprite #" & integer'image(sprite_number);
    end if;
  end process main;

end behavioural;
