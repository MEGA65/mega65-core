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
use work.victypes.all;

entity sprite is
  Port (
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;

    signal sprite_number : in spritenumber;

    signal sprite_h640 : in std_logic;
    signal sprite_v400 : in std_logic;

    signal sprite_sixteen_colour_mode : in std_logic;
    
    signal sprite_horizontal_tile_enable : in std_logic;
    signal sprite_bitplane_enable : in std_logic;
    signal sprite_extended_height_enable : in std_logic;
    signal sprite_extended_width_enable : in std_logic;
    signal sprite_extended_height_size : in unsigned(7 downto 0);  

    -- Pull sprite data in along the chain from the previous sprite (or VIC-IV)
    signal sprite_datavalid_in : in std_logic;
    signal sprite_bytenumber_in : in spritebytenumber;
    signal sprite_spritenumber_in : in spritenumber;
    signal sprite_data_in : in unsigned(7 downto 0);

    -- Pass sprite data out along the chain to the next sprite
    signal sprite_datavalid_out : out std_logic;
    signal sprite_bytenumber_out : out spritebytenumber;
    signal sprite_spritenumber_out : out spritenumber;
    signal sprite_data_out : out unsigned(7 downto 0);

    -- which base offset for the VIC-II sprite data are we showing this raster line?
    -- VIC-IV clocks sprite_number_for_data and each sprite replaces
    -- sprite_data_offset with the appropriate value if the sprite number is itself
    signal sprite_number_for_data_in : in spritenumber;
    signal sprite_data_offset_in : in spritedatabytenumber;    
    signal sprite_data_offset_out : out spritedatabytenumber;    
    signal sprite_number_for_data_out : out spritenumber;
    
    -- Is the pixel just passed in a foreground pixel?
    signal is_foreground_in : in std_logic;
    signal is_background_in : in std_logic;
    -- and what is the colour of the bitmap pixel?
    signal x320_in : in xposition;
    signal x640_in : in xposition;
    signal pipeline_delay : integer range 0 to 31;
    signal y_in : in yposition;
    signal yfine_in : in yposition;
    signal border_in : in std_logic;
    signal alt_palette_in : in std_logic;
    signal pixel_in : in unsigned(7 downto 0);
    signal alpha_in : in unsigned(7 downto 0);
    -- and information from the previous sprite
    signal is_sprite_in : in std_logic;
    signal sprite_colour_in : in unsigned(7 downto 0);
    signal sprite_number_in : in integer range 0 to 7;
    signal sprite_map_in : in std_logic_vector(7 downto 0);
    signal sprite_fg_map_in : in std_logic_vector(7 downto 0);

    -- Pass pixel information back out, as well as the sprite colour information
    signal is_foreground_out : out std_logic;
    signal is_background_out : out std_logic;
    signal x320_out : out xposition;
    signal x640_out : out xposition;
    signal y_out : out yposition;
    signal yfine_out : out yposition;
    signal border_out : out std_logic;
    signal alt_palette_out : out std_logic;
    signal pixel_out : out unsigned(7 downto 0) := x"00";
    signal alpha_out : out unsigned(7 downto 0) := x"00";
    signal sprite_colour_out : out unsigned(7 downto 0);
    signal sprite_number_out : out integer range 0 to 7;
    signal is_sprite_out : out std_logic;
    signal sprite_map_out : out std_logic_vector(7 downto 0);
    signal sprite_fg_map_out : out std_logic_vector(7 downto 0);
    
    signal sprite_enable : in std_logic;
    signal sprite_x : in unsigned(9 downto 0);
    signal sprite_y : in unsigned(9 downto 0);
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

  signal sprite_data_offset : integer range 0 to 1023 := 0;    
  signal y_last : integer range 0 to 4095 := 0; 
  signal x_last : integer range 0 to 4095 := 0;
  signal y_top : std_logic := '0';
  signal y_offset : integer range 0 to 255 := 0;
  signal x_offset : integer range 0 to 64 := 0;
  signal x_in_sprite : std_logic := '0';
  signal x_in_sprite_soon : std_logic := '0';
  signal sprite_drawing : std_logic := '0';
  signal x_expand_toggle : std_logic := '0';
  signal y_expand_toggle : std_logic := '0';
  signal sprite_pixel_bits : std_logic_vector(63 downto 0) := (others => '1');
  signal sprite_pixel_bits_last : std_logic_vector(63 downto 0) := (others => '1'); -- is this maybe just redundant wrt. sprite_data_64bits?
  signal sprite_data_64bits : unsigned(63 downto 0) := (others => '0');
  signal check_collisions : std_logic := '0';

  signal x_in : xposition := 0;

  signal pixel_strobe : std_logic := '0';
  signal pixel_strobe_history : std_logic_vector(31 downto 0) := (others => '0');
  
begin  -- behavioural
  
  -- purpose: sprite drawing
  -- type   : sequential
  -- inputs : pixelclock, <reset>
  -- outputs: colour, is_sprite_out
  main: process (pixelclock,sprite_number,sprite_h640,x640_in,x320_in,x_offset)
    variable sprite_number_mod_4 : integer range 0 to 7 := (sprite_number mod 4) * 2;
    variable pixel_16 : std_logic_vector(3 downto 0);
    variable sprite_color2_bits  : std_logic_vector(1 downto 0);
    variable sprite_color16_bits : std_logic_vector(3 downto 0);
    variable x_offset_bit_0 : std_logic;
    variable x_offset_bits : std_logic_vector(5 downto 0);
    
  begin  -- process main
    if sprite_h640='1' then
      x_in <= x640_in;
--      report "x_in <= x640_in";
    else
      x_in <= x320_in;
--      report "x_in <= x320_in";
    end if;
    
    x_offset_bits := std_logic_vector(to_unsigned(x_offset,6));
    x_offset_bit_0 := x_offset_bits(0);
    
    if pixelclock'event and pixelclock = '1' then  -- rising clock edge
--      report "SPRITE: entering VIC-II sprite #" & integer'image(sprite_number);
      -- copy sprite data chain from input side to output side      
      sprite_spritenumber_out <= sprite_spritenumber_in;
      sprite_datavalid_out <= sprite_datavalid_in;
      sprite_bytenumber_out <= sprite_bytenumber_in;
      sprite_data_out <= sprite_data_in;
      sprite_number_for_data_out <= sprite_number_for_data_in;

      sprite_color2_bits(1) := sprite_pixel_bits(63);
      if sprite_is_multicolour = '1' then
        sprite_color2_bits(0) := sprite_pixel_bits(62);
      else
        sprite_color2_bits(0) := '0';
      end if;
      
      sprite_color16_bits := sprite_pixel_bits(63 downto 60);

      if sprite_v400 = '1' then
        y_last <= yfine_in;
      else
        y_last <= y_in;
      end if;
      x_last <= x_in;

      if (x_last /= x_in) then
        pixel_strobe_history(0) <= '1';
      else
        pixel_strobe_history(0) <= '0';
      end if;
      pixel_strobe_history(31 downto 1) <= pixel_strobe_history(30 downto 0);
      pixel_strobe <= pixel_strobe_history(pipeline_delay);

      
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

      if sprite_number_for_data_in = sprite_number then
        -- Tell VIC-IV our current sprite data offset
        sprite_data_offset_out <= sprite_data_offset;
      else
        sprite_data_offset_out <= sprite_data_offset_in;
      end if;

      -- copy pixel data chain from input side to output side
      alpha_out <= alpha_in;
      x320_out <= x320_in;
      x640_out <= x640_in;
      y_out <= y_in;
      yfine_out <= yfine_in;
      border_out <= border_in;
      alt_palette_out <= alt_palette_in;
      is_foreground_out <= is_foreground_in;
      is_background_out <= is_background_in;

      -- Work out when we start drawing the sprite
      -- sprite data offset = y_offset * 3
      if sprite_drawing='0' then
        sprite_data_offset <= 0;
        if (sprite_data_offset /= 0) then
          report "drawing row fetch from row 0 (hard wire)";
        end if;
      else
        -- When drawing, we ask for the next row of data, so that we can
        -- latch it.
        if (sprite_data_offset = 0) then
          report "drawing row fetch from row 1 + " & integer'image(y_offset);
        end if;
        if (sprite_extended_width_enable='0') and (sprite_sixteen_colour_mode='0') then
          sprite_data_offset <= 3 + (y_offset * 2) + y_offset;
        else
          sprite_data_offset <= 8 + (y_offset * 8);
        end if;
      end if;
      if ((y_in = sprite_y) and (sprite_v400='0'))
         or ((yfine_in = sprite_y) and (sprite_v400='1')) then
        if y_top='0' then
          report "SPRITE: y_top set";
        end if;
        y_top <= '1';
        check_collisions <= '1';
        if ((sprite_v400='0') and (y_last /= y_in))
          or ((sprite_v400='1') and (y_last /= yfine_in))
        then
          sprite_pixel_bits <= std_logic_vector(sprite_data_64bits);
          sprite_pixel_bits_last <= std_logic_vector(sprite_data_64bits);
          report "sprite_pixel_bits (from _mc/_mono)";
        end if;
        if y_top='0' then
          y_offset <= 0;
          y_expand_toggle <= '0';
        end if;
      else
        if y_top='1' then
          report "SPRITE: y_top cleared";
        end if;
        y_top <= '0';
      end if;
--      report "SPRITE: #" & integer'image(sprite_number) & ": "
--        & "x_in=" & integer'image(x_in)
--        & ", y_in=" & integer'image(y_in)
----        & ", y_top=" & std_logic'image(y_top)
--        & ", enable=" & std_logic'image(sprite_enable)
--        & ", drawing=" & std_logic'image(sprite_drawing)
--        & ", in_sprite=" & std_logic'image(x_in_sprite)
--        & ", sprite_x,y=" & to_hstring("000"&sprite_x) & "," &
--        to_hstring(sprite_y);
--      if (x_in = to_integer(sprite_x)) then
--        report "x_in = sprite_x";
--      else
--        report "x_in = " & integer'image(x_in) & ", != sprite_x = " & integer'image(to_integer(sprite_x));
--      end if;

      -- Make sure we don't start a sprite edge except on an output pixel edge,
      -- to stop the left pixel column being trimmed by one clock tick
      if (x_in_sprite_soon= '1') and (pixel_strobe = '1')  then
        x_in_sprite_soon <= '0';
        x_in_sprite <= '1';
      end if;

      if (x_in = to_integer(sprite_x))
        and (x_in /= x_last)
        and (sprite_enable='1')
        and ((y_top='1') or (sprite_drawing = '1')) then
        x_in_sprite_soon <= '1';
        x_expand_toggle <= '0';
        report "SPRITE: drawing row " & integer'image(y_offset)
          & " of sprite " & integer'image(sprite_number)
          & " using data bits %" & to_string(std_logic_vector(sprite_pixel_bits));
        x_offset <= 0;
      else
--        report "SPRITE: not drawing a row: xcompare=" & boolean'image(x_in=sprite_x)
--          & ", sprite_x=" & integer'image(to_integer(sprite_x));
        null;
      end if;
      if y_top = '1' and sprite_enable = '1' then
        if sprite_drawing='0' then
          report "SPRITE: sprite start hit and enabled: drawing xoffset="
            & integer'image(x_offset);
          sprite_drawing <= '1';
        end if;
      end if;
      -- Advance Y position of sprite
      if ((sprite_v400='0') and (y_last /= y_in))
        or ((sprite_v400='1') and (y_last /= yfine_in)) then
        report "stop drawing to to y_in advance to " & integer'image(y_in);
        if sprite_v400='0' then
          y_last <= y_in;
        else
          y_last <= yfine_in;
        end if;
        x_in_sprite <= '0';
        if (sprite_drawing = '1') or (y_top='1') then
          -- Check collisions whenever we start a new logical sprite pixel row, even
          -- if it is just a VIC-II stretch of the above one, since it could collide
          -- with a non-expanded sprite that starts here.
          check_collisions <= '1';
        else
          check_collisions <= '0';
        end if;

        -- Y position has advanced while drawing a sprite
        if (sprite_drawing = '1') or (y_top='1') then
          if ((y_expand_toggle = '1') or (sprite_stretch_y='0')) then
            y_offset <= y_offset + 1;
            report "drawing row increasing"
              & ": y_last=" & integer'image(y_last)
              & ", y_in=" & integer'image(y_in)
              & ", y_expand_toggle=" & std_logic'image(y_expand_toggle)
              & ", sprite_stretch_y=" & std_logic'image(sprite_stretch_y)
              & ", y_top=" & std_logic'image(y_top)
              & ", old y_offset=" & integer'image(y_offset);

            report "sprite_pixel_bits (from _mc/_mono)";
            sprite_pixel_bits <= std_logic_vector(sprite_data_64bits);
            sprite_pixel_bits_last <= std_logic_vector(sprite_data_64bits);
          else
            report "sprite_pixel_bits (from _last)";
            sprite_pixel_bits <= sprite_pixel_bits_last;
          end if;
          y_expand_toggle <= not y_expand_toggle;
        else
          y_offset <= 0;
        end if;
      elsif x_in < x_last then
        -- Start of new VGA raster
        report "sprite_pixel_bits (from _last)";
        sprite_pixel_bits <= sprite_pixel_bits_last;
        x_in_sprite <= '0';
      end if;
      if ((sprite_extended_height_enable = '0')
          and (y_offset = 21))
        or
        ((sprite_extended_height_enable = '1')
         and (y_offset = sprite_extended_height_size)) then
        report "SPRITE: end of sprite y reached. no longer drawing";        
        sprite_drawing <= '0';      
        y_offset <= 0;
      end if;
      
      -- Advance X position of sprite
      if (pixel_strobe='1') and (x_in_sprite = '1') then
        -- X position has advanced while drawing a sprite
        report "SPRITE: drawing next pixel";
        if (x_expand_toggle = '1') or (sprite_stretch_x/='1') then
          if
            (
              
            ((sprite_stretch_x='1') and
            (
              ((x_offset = (23)) and (sprite_extended_width_enable='0'))
              or ((x_offset = (63)) and (sprite_extended_width_enable='1'))
              -- 16 colour sprites are always 16 pixels wide
              or ((x_offset = (15)) and (sprite_sixteen_colour_mode='1'))))

            or
            
            ((sprite_stretch_x='0') and
            (
              ((x_offset = (23)) and (sprite_extended_width_enable='0'))
              or ((x_offset = (63)) and (sprite_extended_width_enable='1'))
              -- 16 colour sprites are always 16 pixels wide
              or ((x_offset = (15)) and (sprite_sixteen_colour_mode='1'))))
            )
            
            and (sprite_horizontal_tile_enable='0')
          then
            report "SPRITE: right edge of sprite encountered. stopping drawing.";
            x_in_sprite <= '0';
            -- Only check collisions on first raster of each sprite pixel
            -- so that we don't trigger collision interrupts on each physical raster
            -- of a single pixel row of a sprite, which might cause some games
            -- to get confused and trigger the collision routine 5x for each collision
            -- instead of just once -- especially since there are ~640 CPU
            -- cycles per physical raster = ~ 3,000 CPU cycles per sprite pixel
            -- row.
            check_collisions <= '0';
          else
            report "x_offset <= " & integer'image(x_offset) & " + 1";
            x_offset <= x_offset + 1;
          end if;
          -- shift along to next pixel
          report "SPRITE: shifting pixel vector along (was "&
            to_string(sprite_pixel_bits)
            &")";
--          report "sprite_pixel_bits (rotate)";
          if sprite_sixteen_colour_mode = '1' then
            sprite_pixel_bits <= sprite_pixel_bits(59 downto 0)&sprite_pixel_bits(63 downto 60);
          elsif sprite_is_multicolour = '0' then
            sprite_pixel_bits <= sprite_pixel_bits(62 downto 0)&sprite_pixel_bits(63);            
          elsif x_offset_bit_0 = '1' then 
            sprite_pixel_bits <= sprite_pixel_bits(61 downto 0)&sprite_pixel_bits(63 downto 62);            
          end if;
        end if;
        report "SPRITE: toggling x_expand_toggle";
        x_expand_toggle <= not x_expand_toggle;
      end if;
      
      -- decide whether we are visible or not, and update sprite colour
      -- accordingly.
      -- check for sprite/foreground collision
      sprite_fg_map_out <= sprite_fg_map_in;
      if (x_in_sprite='1') and (border_in='0') and (is_foreground_in='1') then
        if (sprite_sixteen_colour_mode='0') and (sprite_color2_bits /= "00") then
          -- Sprite and foreground collision
          sprite_fg_map_out(sprite_number) <= check_collisions;
        end if;
        if (sprite_sixteen_colour_mode='1')
          and (unsigned(sprite_color16_bits) /= sprite_colour(3 downto 0)) then
          -- Sprite and foreground collision
          sprite_fg_map_out(sprite_number) <= check_collisions;
        end if;
      end if;
      -- check for sprite/sprite collision
      sprite_map_out <= sprite_map_in;
      if (x_in_sprite='1') and (border_in='0') then
        if (sprite_sixteen_colour_mode='0') and (sprite_color2_bits /= "00") then
          -- Sprite and foreground collision
          sprite_map_out(sprite_number) <= check_collisions;
        end if;
        if (sprite_sixteen_colour_mode='1')
          and (unsigned(sprite_color16_bits) /= sprite_colour(3 downto 0)) then
          -- Sprite and foreground collision
          sprite_map_out(sprite_number) <= check_collisions;
        end if;
      end if;      
      
      -- Stop drawing sprites in right fly-back, to prevent glitches with
      -- horizontally tiled sprites.
      -- (but allow non-tiled sprites to wrap around into left border, as on the
      -- C64.)
      if (sprite_h640='0') and (x_in > 416) and (sprite_horizontal_tile_enable='1') then
        x_in_sprite <= '0';
      end if;
      if (sprite_h640='1') and (x_in > 832) and (sprite_horizontal_tile_enable='1') then
        x_in_sprite <= '0';
      end if;
      
      if (sprite_bitplane_enable='1') and (sprite_sixteen_colour_mode='0') and (x_in_sprite='1') then
        -- Bitmap mode of sprites modifies the palette entry of the
        -- sprite/graphics instead of drawing a sprite. Thus multiple
        -- sprites can be combined to get more colours, like on the Amiga,
        -- but also with the background, e.g., to modify colour of background
        -- when a "shadow" or "highlight" or sprite of other purpose is drawn
        sprite_number_out <= sprite_number_in;
        is_sprite_out <= is_sprite_in;
        if sprite_is_multicolour = '0' then
          for bit in 0 to 7 loop
            if bit /= sprite_number then
              sprite_colour_out(bit) <= sprite_colour_in(bit);
              pixel_out(bit) <= pixel_in(bit);
            end if;
          end loop;
          pixel_out(sprite_number) <= sprite_color2_bits(1) xor pixel_in(sprite_number);
          sprite_colour_out(sprite_number) <= sprite_color2_bits(1) xor sprite_colour_in(sprite_number);
        else
          for bit in 0 to 7 loop
            if (bit /= sprite_number_mod_4)
              and (bit /= (sprite_number_mod_4 +1)) then
              sprite_colour_out(bit) <= sprite_colour_in(bit);
              pixel_out(bit) <= pixel_in(bit);
            end if;
          end loop;
          pixel_out(sprite_number_mod_4 + 1) <= sprite_color2_bits(1) xor pixel_in(sprite_number_mod_4 + 1);
          pixel_out(sprite_number_mod_4) <= sprite_color2_bits(0) xor pixel_in(sprite_number_mod_4);
          sprite_colour_out(sprite_number_mod_4 + 1) <= sprite_color2_bits(1) xor sprite_colour_in(sprite_number_mod_4 + 1);
          sprite_colour_out(sprite_number_mod_4) <= sprite_color2_bits(0) xor sprite_colour_in(sprite_number_mod_4);
        end if;
      else
        -- Non-bitplane sprites
        pixel_out <= pixel_in;
        if ((is_foreground_in='0') or (sprite_priority='0')) and (x_in_sprite='1') then
          if sprite_sixteen_colour_mode='1' then
            pixel_16 := sprite_color16_bits;
            report "SPRITE: Painting 16-colour pixel using bits "
              & to_string(pixel_16);
            if unsigned(pixel_16) /= sprite_colour(3 downto 0) then
              sprite_number_out <= sprite_number;
              is_sprite_out <= not border_in;
              sprite_colour_out(3 downto 0) <= unsigned(pixel_16);
              -- Setting bitplane mode and 16-colour mode allows setting the
              -- upper bits of the sprite colour
              sprite_colour_out(6 downto 4) <= to_unsigned(sprite_number,3);
              sprite_colour_out(7) <= sprite_bitplane_enable;
            else
              -- Transparent pixel, don't draw.
              sprite_number_out <= sprite_number_in;
              sprite_colour_out <= sprite_colour_in;
              sprite_map_out <= sprite_map_in;
              sprite_fg_map_out <= sprite_fg_map_in;
              is_sprite_out <= is_sprite_in;
              null;
            end if;
          else
            report "SPRITE: Painting pixel using bits " & to_string(sprite_color2_bits);        
            case sprite_color2_bits is
              when "01" =>
                is_sprite_out <= not border_in;
                sprite_number_out <= sprite_number;
                sprite_colour_out <= sprite_multi0_colour;
              when "10" =>
                is_sprite_out <= not border_in;
                sprite_number_out <= sprite_number;
                sprite_colour_out <= sprite_colour;
              when "11" =>
                is_sprite_out <= not border_in;
                sprite_number_out <= sprite_number;
                sprite_colour_out <= sprite_multi1_colour;
              when others =>
                -- background shows through
                is_sprite_out <= is_sprite_in;
                sprite_number_out <= sprite_number_in;
                sprite_colour_out <= sprite_colour_in;
            end case;
          end if;
        else
          is_sprite_out <= is_sprite_in;
          sprite_colour_out <= sprite_colour_in;
          sprite_number_out <= sprite_number_in;
        end if;
      end if;
--      report "SPRITE: leaving VIC-II sprite #" & integer'image(sprite_number);
    end if;
  end process main;

end behavioural;
