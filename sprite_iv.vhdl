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

entity sprite_iv is
  Port (
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;

    signal sprite_number : in integer range 0 to 7;
    
    -- Is the pixel just passed in a foreground pixel?
    signal is_foreground_in : in std_logic;
    -- and what is the colour of the bitmap pixel?
    signal x_in : in integer range 0 to 4095;
    signal y_in : in integer range 0 to 4095;
    signal border_in : in std_logic;
    signal pixel_in : in unsigned(7 downto 0);
    -- and information from the previous sprite
    signal is_sprite_in : in std_logic;
    signal sprite_colour_in : in unsigned(7 downto 0);

    -- Pass pixel information back out, as well as the sprite colour information
    signal is_foreground_out : out std_logic;
    signal x_out : out integer range 0 to 4095;
    signal y_out : out integer range 0 to 4095;
    signal border_out : out std_logic;
    signal pixel_out : out unsigned(7 downto 0);
    signal sprite_colour_out : out unsigned(7 downto 0);
    signal is_sprite_out : out std_logic;

    ioclock : in std_logic;
    fastio_address : in unsigned(19 downto 0);
    fastio_read : in std_logic;
    fastio_write : out std_logic;
    fastio_rdata : out unsigned(7 downto 0);
    fastio_wdata : in unsigned(7 downto 0)
    
    );

end sprite_iv;

architecture behavioural of sprite_iv is

  signal sprite_x : unsigned(11 downto 0);
  signal sprite_y : unsigned(11 downto 0);
  
  -- Transform matrix for rotations, flips etc.
  signal transform_0_0 : unsigned(15 downto 0);
  signal transform_0_1 : unsigned(15 downto 0);
  signal transform_1_0 : unsigned(15 downto 0);
  signal transform_1_1 : unsigned(15 downto 0);

  -- coordinate transformation pipeline uses a simple 2D linear
  -- transformation matrix, which boils down to:
  -- x' = 0_0*x + 0_1*y
  -- y' = 1_0*x + 1_1*y
  -- This can support rotation, horizontal and vertical flips, shears,
  -- scaling and probably other effects.  The matrix coefficients are 16 bit
  -- precision to allow for a wide range of zoom values.  Enhanced sprites are
  -- drawn at 1920x1200 native resolution, so lower resolutions are obtained
  -- exclusively through zooming.
  -- Implementing this requires four DSP blocks.  We calculate 0_1*y and 1_1*y
  -- first, and then use that (shifted down several bits) as the add coefficient
  -- into the second DSP block that performs the *x operation and then adds the *y
  -- result to that.  The reason for this construction is that we don't need to
  -- worry about the extra latency from the *y calculation, since it will
  -- remain constant for a whole raster line.  We could reduce the DSP block
  -- count by calculating the *y values once per raster, provided it doesn't
  -- mess up timing.  Will look at this later. 
  
  signal x : unsigned(11 downto 0);
  signal y : unsigned(11 downto 0);
  signal y_times_1_0 : unsigned(47 downto 0);
  signal y_times_1_1 : unsigned(47 downto 0);

  COMPONENT mult_and_add
    PORT (
      clk : IN STD_LOGIC;
      a : IN STD_LOGIC_VECTOR(17 DOWNTO 0);
      b : IN STD_LOGIC_VECTOR(17 DOWNTO 0);
      c : IN STD_LOGIC_VECTOR(47 DOWNTO 0);
      p : OUT STD_LOGIC_VECTOR(47 DOWNTO 0)
      );
  END COMPONENT;
  
begin  -- behavioural

  
  -- Construct the 2D linear transformation pipeline
  mult_and_add_0_y: component mult_and_add
    port map(
      clk => pixelclk,
      a(17 downto 5) => sprite_y,
      a(4 downto 0) => "00000",
      b(17 downto 2) => transform_1_0,
      b(1 downto 0) => "00",
      c => (others => '0'),
      p => y_times_1_0);
  mult_and_add_1_y: component mult_and_add port map(
    clk => pixelclk,
    a(17 downto 5) => sprite_y,
    a(4 downto 0) => "00000",
    b(17 downto 2) => transform_1_1,
    b(1 downto 0) => "00",
    c => (others => '0'),
    p => y_1_1);
  mult_and_add_x: component mult_and_add port map(
    clk => pixelclk,
    a(17 downto 0) => sprite_x,
    a(4 downto 0) => "00000",
    b(17 downto 2) => transform_0_0,
    b(1 downto 0) => "00",
    c => y_times_1_0,
    p(33 downto 16) => x);
  mult_and_add_y: component mult_and_add port map(
    clk => pixelclk,
    a(17 downto 0) => sprite_x,
    a(4 downto 0) => "00000",
    b(17 downto 2) => transform_1_0,
    b(1 downto 0) => "00",
    c => y_times_1_1,
    p(33 downto 16) => y);    

  main: process (pixelclock,ioclock)
  begin  -- process main
    
    if ioclock'event and ioclock='1' then -- rising clock edge
      -- IO registers:
      -- - 4KB for sprite data
      -- - sprite control registers
      fastio_rdata <= (others => 'Z');      
      if fastio_write='1' then
        if fastio_address(19 downto 16) = x"9" and
          to_integer(fastio_address(15 downto 12)) = sprite_number then
          -- @IO:GS $FF9x000-$FF9xFFF - Enhanced sprite data buffers (4KB each)
          sprite_buffer_write <= '1';
          sprite_buffer_wdata <= fastio_wdata;
          sprite_buffer_write_addr <= to_integer(fastio_address(11 downto 0));
        end if;
        if fastio_address(19 downto 8) = x"D37" and
          to_integer(fastio_address(7 downto 4)) = sprite_number then
          -- @IO:GS $D710-$D7FF - Enhanced sprite control registers (16 per enhanced sprite)
          case fastio_address(3 downto 0) is
            -- @IO:GS $D7x0-$D7x1 - Enhanced sprite X position in physical pixels (lower 12 bits)
            -- @IO:GS $D7x1.4-7   - Enhanced sprite width (4 -- 64 pixels)
            when x"0" => sprite_x(7 downto 0) <= fastio_wdata;
            when x"1" => sprite_x(11 downto 8) <= fastio_wdata(3 downto 0);
                         sprite_width(5 downto 2) <= fastio_wdata(7 downto 4) + 1;
                         sprite_width(1 downto 0) <= "00";
            -- @IO:GS $D7x2-$D7x3 - Enhanced sprite Y position in physical pixels (16 bits)
            -- @IO:GS $D7x3.4-7   - Enhanced sprite height (4 -- 64 pixels)
            when x"2" => sprite_y(7 downto 0) <= fastio_wdata;
            when x"3" => sprite_y(11 downto 8) <= fastio_wdata(3 downto 0);
                         sprite_height(5 downto 2) <= fastio_wdata(7 downto 4) + 1;
                         sprite_height(1 downto 0) <= "00";
            -- @IO:GS $D7x4 - Enhanced sprite data offset in its 4KB SpriteRAM (x16 bytes)
            when x"4" => sprite_base_addr(11 downto 4) <= fastio_wdata;
            -- @IO:GS $D7x5 - Enhanced sprite foreground mask
            -- chargen/bitmap pixels which = $00 when anded with this mask will
            -- appear behind this sprite.
            when x"5" => sprite_background_mask <= fastio_wdata;
            -- @IO:GS $D7x6       - Enhanced sprite colour AND mask (sprite not visible if result = $00)
            when x"6" => sprite_and_mask <= fastio_wdata;
            -- @IO:GS $D7x7       - Enhanced sprite colour OR mask
            when x"7" => sprite_or_mask <= fastio_wdata;
            -- @IO:GS $D718-$D7FF - Enhanced sprite linear transform matricies. These allow for hardware rotation, flipping etc.
            -- @IO:GS $D7x8-$D7x9 - Enhanced sprite 2x2 linear transform matrix 0,0 (5.11 bits)
            when x"8" => transform_0_0(7 downto 0) <= fastio_wdata;
            when x"9" => transform_0_0(15 downto 8) <= fastio_wdata;
            -- @IO:GS $D7xA-$D7xB - Enhanced sprite 2x2 linear transform matrix 0,1 (5.11 bits)
            when x"a" => transform_0_1(7 downto 0) <= fastio_wdata;
            when x"b" => transform_0_1(15 downto 8) <= fastio_wdata;
            -- @IO:GS $D7xC-$D7xD - Enhanced sprite 2x2 linear transform matrix 1,0 (5.11 bits)
            when x"c" => transform_1_0(7 downto 0) <= fastio_wdata;
            when x"d" => transform_1_0(15 downto 8) <= fastio_wdata;
            -- @IO:GS $D7xE-$D7xF - Enhanced sprite 2x2 linear transform matrix 1,1 (5.11 bits)
            when x"e" => transform_1_1(7 downto 0) <= fastio_wdata;
            when x"f" => transform_1_1(15 downto 8) <= fastio_wdata;
            when others => null;
          end case;
        end if;
        if pixelclock'event and pixelclock = '1' then  -- rising clock edge
          
          -- decide whether we are visible or not, and update sprite colour
          -- accordingly.
          if sprite_visible='1' then
            report "SPRITE: Painting pixel using bits " & to_string(sprite_pixel_bits(47 downto 46));
            is_sprite_out <= '1';
            sprite_colour_out <= sprite_pixel;
          else
            is_sprite_out <= is_sprite_in;
            sprite_colour_out <= sprite_colour_in;
          end if;
          is_border_out <= is_border_in;
          is_foreground_out <= is_foreground_in;
          x_out <= x_in;
          y_out <= y_in;
          pixel_out <= pixel_in;
          
--      report "SPRITE: leaving VIC-II sprite #" & integer'image(sprite_number);
        end if;
      end if;
    end if;
  end process main;
  
end behavioural;
