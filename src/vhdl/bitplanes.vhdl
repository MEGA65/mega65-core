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
use work.victypes.all;

entity bitplanes is
  Port (
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;
    cpuclock : in std_logic;

    signal fastio_address :in unsigned(19 downto 0);
    signal fastio_write : in std_logic;
    signal fastio_wdata : in unsigned(7 downto 0);

    -- Pull sprite data in along the chain from the previous sprite (or VIC-IV)
    signal sprite_datavalid_in : in std_logic;
    signal sprite_bytenumber_in : in spritebytenumber;
    signal sprite_spritenumber_in : in spritenumber;
    signal sprite_data_in : in unsigned(7 downto 0);

    -- Pass sprite data out along the chain to the next sprite
    signal sprite_datavalid_out : out std_logic := '0';
    signal sprite_bytenumber_out : out spritebytenumber := 0;
    signal sprite_spritenumber_out : out spritenumber := 0;
    signal sprite_data_out : out unsigned(7 downto 0) := (others => '0');

    -- which base offset for the VIC-II sprite data are we showing this raster line?
    -- VIC-IV clocks sprite_number_for_data and each sprite replaces
    -- sprite_data_offset with the appropriate value if the sprite number is itself
    signal sprite_number_for_data_in : in spritenumber;
    signal sprite_data_offset_in : in spritedatabytenumber;
    signal sprite_data_offset_out : out spritedatabytenumber := 0;
    signal sprite_number_for_data_out : out spritenumber := 0;

    signal bitplane_h640 : in std_logic;
    signal bitplane_h1280 : in std_logic;
    signal bitplane_mode_in : in std_logic;
    signal bitplane_enables_in : in std_logic_vector(7 downto 0);
    signal bitplane_complements_in : in std_logic_vector(7 downto 0);
    signal bitplanes_x_start : in unsigned(7 downto 0);
    signal bitplanes_y_start : in unsigned(7 downto 0);
    signal bitplane_sixteen_colour_mode_flags : in std_logic_vector(7 downto 0);

    -- Is the pixel just passed in a foreground pixel?
    signal is_foreground_in : in std_logic;
    signal is_background_in : in std_logic;
    -- and what is the colour of the bitmap pixel?
    signal x_in : in xposition;
    signal x640_in : in xposition;
    signal x1280_in : in xposition;
    signal y_in : in yposition;
    signal yfine_in : in yposition;
    signal border_in : in std_logic;
    signal alt_palette_in : in std_logic;
    signal pixel_in : in unsigned(7 downto 0);
    signal alpha_in : in unsigned(7 downto 0);
    -- and information from the previous sprite
    signal is_sprite_in : in std_logic;
    signal sprite_number_in : integer range 0 to 7;
    signal sprite_colour_in : in unsigned(7 downto 0);
    signal sprite_map_in : in std_logic_vector(7 downto 0);
    signal sprite_fg_map_in : in std_logic_vector(7 downto 0);

    -- Pass pixel information back out, as well as the sprite colour information
    signal is_foreground_out : out std_logic := '0';
    signal is_background_out : out std_logic := '0';
    signal x_out : out xposition := 0;
    signal y_out : out yposition := 0;
    signal border_out : out std_logic := '0';
    signal alt_palette_out : out std_logic;
    signal pixel_out : out unsigned(7 downto 0) := (others => '0');
    signal alpha_out : out unsigned(7 downto 0) := (others => '0');
    signal sprite_colour_out : out unsigned(7 downto 0) := (others => '0');
    signal is_sprite_out : out std_logic := '0';
    signal sprite_number_out : out integer range 0 to 7 := 0;
    signal sprite_map_out : out std_logic_vector(7 downto 0) := (others => '0');
    signal sprite_fg_map_out : out std_logic_vector(7 downto 0) := (others => '0')


);

end bitplanes;

architecture behavioural of bitplanes is

  signal y_last : yposition;
  signal x_last : xposition;
  signal x_left : std_logic := '0';
  signal y_top : std_logic := '0';
  signal x_in_bitplanes : std_logic := '0';
  signal x_in_bitplanes_drive : std_logic := '0';
  signal last_x_in_bitplanes : std_logic := '0';
  signal bitplane_drawing : std_logic := '0';
  signal bitplane_drawing_next : std_logic := '0';
  signal bitplane_x_start : xposition := 23;
  signal bitplane_x_start_h640 : xposition := 54;
  signal bitplane_x_start_h1280 : xposition := 54;
  signal bitplane_y_start : yposition := 51;
  signal bitplane_y_start_h640 : yposition := 51;
  signal bitplane_y_start_h1820 : xposition := 51;
  signal bitplanes_answer_data_request_timeout : integer range 0 to 255 := 0;

  signal bitplane_mode : std_logic;
  signal bitplane_enables : std_logic_vector(7 downto 0);
  signal bitplane_complements : std_logic_vector(7 downto 0);

  type bdo is array(0 to 7) of spritedatabytenumber;
  signal bitplane_data_offsets : bdo;
  signal bitplane_data_offsets_next : bdo;
  signal bitplane_y_card_position : spritedatabytenumber := 0;
  signal bitplane_y_card_number : spritedatabytenumber := 0;
  signal bitplane_y_card_number_drive : spritedatabytenumber := 0;

  signal bitplanedatabuffer_cs : std_logic := '1';
  signal bitplanedatabuffer_write : std_logic := '0';
  signal bitplanedatabuffer_wdata : unsigned(7 downto 0);
  signal bitplanedatabuffer_waddress : integer range 0 to 4095 := 0;
  signal bitplanedatabuffer_rdata : unsigned(7 downto 0);
  signal bitplanedatabuffer_address : integer range 0 to 4095 := 0;

  -- Signals into and out of bitplane pixel engines
  signal bitplanes_reset : std_logic_vector(7 downto 0) := "00000000";
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
  signal bitplanes_byte_number : integer range 0 to 511;
  signal bitplanedata_fetch_column : integer range 0 to 511;

  signal bitplanedata_fetching : std_logic := '0';
  signal bitplanedata_fetch_bitplane : integer range 0 to 7;
  signal current_data_fetch : integer range 0 to 8;

  signal fetch_ongoing : std_logic := '0';
  signal bitplanes_column_done : std_logic := '0';

  signal pixel_out_count : integer range 0 to 255 := 0;

  signal bitplanes_y_start_drive : unsigned(7 downto 0) := to_unsigned(0,8);

begin  -- behavioural

  -- 4K buffer for holding buffered bitplane data for rendering.
  -- 8 bitplanes x 512 bytes = 4KB.
  -- This is plenty, since we actually only read 100 bytes max per bitplane
  -- (800 pixel wide mode) per
  -- line (actually upto 400 bytes per line when using bitplanes in 16-colour mode)
  bitplanedatabuffer: entity work.ram8x4096
    port map (clkr => pixelclock,
              clkw => pixelclock,
              w => bitplanedatabuffer_write,
              wdata => bitplanedatabuffer_wdata,
              write_address => bitplanedatabuffer_waddress,

              cs => bitplanedatabuffer_cs,
              address => bitplanedatabuffer_address,
              rdata => bitplanedatabuffer_rdata
              );

  generate_bitplanes:
  for index in 0 to 7 generate
    begin
      bitplane_inst : entity work.bitplane
      port map (
        pixelclock => pixelclock,
        reset => bitplanes_reset(index),
        advance_pixel => bitplanes_advance_pixel(index),
        sixteen_colour_mode => bitplanes_sixteen_colour_mode(index),
        data_in_valid => bitplanes_data_in_valid(index),
        data_in => bitplanes_data_in,
        data_request => bitplanes_data_request(index),
        pixel_out => bitplanes_pixel_out(index),
        pixel16_out => bitplanes_pixel16_out(index)
      );
  end generate;

  -- purpose: bitplane drawing
  -- type   : sequential
  -- inputs : pixelclock, <reset>
  -- outputs: colour, is_sprite_out
  main: process (pixelclock) is
    variable v_x_in : integer;
    variable v_y_in : integer;
    variable v_bitplane_y_start : integer := 0;
    variable v_bitplane_x_start : integer := 0;
  begin  -- process main
    if pixelclock'event and pixelclock = '1' then  -- rising clock edge

      -- Process delayed signals for improving timing closure
      bitplanes_y_start_drive <= bitplanes_y_start;
      bitplane_data_offsets <= bitplane_data_offsets_next;

      if bitplane_h640='1' then
        v_x_in := x640_in;
        v_bitplane_y_start := bitplane_y_start_h640;
        v_bitplane_x_start := bitplane_x_start_h640;
      elsif bitplane_h1280='1' then
        v_x_in := x1280_in;
        v_bitplane_y_start := bitplane_y_start_h1820;
        v_bitplane_x_start := bitplane_x_start_h1280;
      else
        v_x_in := x_in;
        v_bitplane_y_start := bitplane_y_start;
        v_bitplane_x_start := bitplane_x_start;
      end if;

      if (yfine_in mod 2) = 0 then
        v_y_in := y_in;
      else
        v_y_in := y_in + 1;
      end if;

      -- Pre-calculate some things to improve timing
      if v_y_in >= (v_bitplane_y_start + to_integer(signed(std_logic_vector(bitplanes_y_start_drive)))) then
--        report "y_in = " & integer'image(y_in);
--        report "v_bitplane_y_start = " & integer'image(v_bitplane_y_start);
--        report "bitplane_y_start_drive = " & integer'image(to_integer(signed(std_logic_vector(bitplanes_y_start_drive))));
        bitplane_y_card_position
          <= integer((v_y_in - (v_bitplane_y_start + to_integer(signed(std_logic_vector(bitplanes_y_start_drive))))) mod 8);
        bitplane_y_card_number_drive
          <= integer(((v_y_in - (v_bitplane_y_start + to_integer(signed(std_logic_vector(bitplanes_y_start_drive))))) / 8));
      else
        bitplane_y_card_position <= 0;
        bitplane_y_card_number_drive <= 0;
      end if;
      bitplane_y_card_number <= bitplane_y_card_number_drive;

      -- Copy sprite colission status out
      sprite_map_out <= sprite_map_in;
      sprite_fg_map_out <= sprite_fg_map_in;

      -- Have a drive stage on bitplane mode bits to ease timing.
      bitplane_mode <= bitplane_mode_in;
      bitplane_enables <= bitplane_enables_in;
      bitplane_complements <= bitplane_complements_in;

      -- copy sprite data chain from input side to output side
      sprite_spritenumber_out <= sprite_spritenumber_in;
      sprite_datavalid_out <= sprite_datavalid_in;
      sprite_bytenumber_out <= sprite_bytenumber_in;
      sprite_data_out <= sprite_data_in;
      sprite_number_for_data_out <= sprite_number_for_data_in;

      bitplanes_column_done <= '0';
      if bitplanes_column_done = '1' then

        fetch_ongoing <= '0';
      end if;

      if (sprite_datavalid_in = '1') and (sprite_spritenumber_in > 7) then
        -- Record sprite data
        report "BITPLANES:"
          & "  byte $" & to_hstring(sprite_data_in)
          & " from VIC-IV for bp#"
          & integer'image(sprite_spritenumber_in)
          & " byte #" & integer'image(sprite_bytenumber_in)
          & " x=" & integer'image(x_in)
          & " x_start=" & integer'image(bitplane_x_start)
          & " y=" & integer'image(y_in)
          & " y_start=" & integer'image(bitplane_y_start)
          & " border_in=" & std_logic'image(border_in)
          & " bitplane_mode_in=" & std_logic'image(bitplane_mode_in)
          & " bitplane_drawing=" & std_logic'image(bitplane_drawing);
        bitplanedatabuffer_waddress
          <= (sprite_spritenumber_in mod 8)*512 + sprite_bytenumber_in;
        bitplanedatabuffer_wdata(7 downto 0) <= sprite_data_in;
        bitplanedatabuffer_write <= '1';
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
      alt_palette_out <= alt_palette_in;
      is_foreground_out <= is_foreground_in;
      is_background_out <= is_background_in;

      -- Work out if we need to fetch a byte
      bitplanes_advance_pixel <= "00000000";
      bitplanedata_fetching <= '0';

      if current_data_fetch > 0 then

        bitplanedata_fetching <= '1';
        bitplanedata_fetch_bitplane <= current_data_fetch - 1;
        bitplanedatabuffer_address <= (current_data_fetch - 1)*512 + bitplanes_byte_number;
        bitplanedata_fetch_column <= bitplanes_byte_number;
	current_data_fetch <= current_data_fetch - 1;

      elsif (bitplanes_data_request(7) = '1') and (fetch_ongoing = '0') then

        fetch_ongoing <= '1';

        -- start new fetch of column
        bitplanes_byte_number <= bitplanes_byte_numbers(0);
        bitplanes_byte_numbers(0) <= bitplanes_byte_numbers(0) + 1;
        -- ent_data_fetch <= 8;   -- triggers fetching data in the next cycle

        bitplanedata_fetching <= '1';
        bitplanedata_fetch_bitplane <= 7;
        bitplanedatabuffer_address <= (7)*512 + bitplanes_byte_numbers(0);
        bitplanedata_fetch_column <= bitplanes_byte_number;
	current_data_fetch <= 7;

      end if;

      -- Pass fetched data to bitplanes if data is available
      bitplanes_data_in_valid <= "00000000";
      if bitplanedata_fetching = '1' then
        bitplanes_data_in <= bitplanedatabuffer_rdata(7 downto 0);
        bitplanes_data_in_valid(bitplanedata_fetch_bitplane) <= '1';

        if(bitplanedata_fetch_bitplane = 0) then
          fetch_ongoing <= '0';
        end if;
      end if;

      -- Work out when we start drawing the bitplane
      y_last <= y_in;
      if y_in = (v_bitplane_y_start + bitplanes_y_start) then
        y_top <= '1';
        report "asserting y_top";
      else
        y_top <= '0';
      end if;

      -- XXX: Bitplane output is delayed by one physical pixel here.
      -- This means that the bitplanes needs to be fed the x value one pixel clock
      -- early, or bitplanes will be offset by one physical pixel.
      -- Also, we need to have a 640 and 1280 pixel clock to do
      -- higher-resolution bitplanes for full C65 compatibility.
      -- None of the above has yet been done.
      if v_x_in = (v_bitplane_x_start + to_integer(signed(std_logic_vector(bitplanes_x_start))))
        and (y_top='1' or bitplane_drawing='1') then
        x_left <= '1';
        x_in_bitplanes_drive <= '1';
        if (v_x_in /= x_last) then
          bitplanes_advance_pixel <= "11111111";
        end if;
        report "asserting x_left and x_in_bitplanes";
      else
        x_left <= '0';
      end if;

      if bitplane_h640 = '1' and bitplane_h1280 = '1' then
        if v_x_in >= (v_bitplane_x_start + to_integer(signed(std_logic_vector(bitplanes_x_start))) + 800) then
          x_in_bitplanes_drive <= '0';
        end if;
      elsif bitplane_h640 = '1' then
        if v_x_in >= (v_bitplane_x_start + to_integer(signed(std_logic_vector(bitplanes_x_start))) + 640) then
          x_in_bitplanes_drive <= '0';
        end if;
      elsif bitplane_h1280 = '1' then
        if v_x_in >= (v_bitplane_x_start + to_integer(signed(std_logic_vector(bitplanes_x_start))) + 1280) then
          x_in_bitplanes_drive <= '0';
        end if;
      else
        if v_x_in >= (v_bitplane_x_start + to_integer(signed(std_logic_vector(bitplanes_x_start))) + 320) then
          x_in_bitplanes_drive <= '0';
        end if;
      end if;
      -- Clear bitplane byte numbers at the end of each raster
      x_in_bitplanes <= x_in_bitplanes_drive;
      last_x_in_bitplanes <= x_in_bitplanes;
      if x_in_bitplanes = '0' and last_x_in_bitplanes = '1' then
        report "Hit right border. Flushing buffered bytes in all bitplanes";
        for i in 7 downto 0 loop
          bitplanes_byte_numbers(i) <= 0;
          if y_in < (v_bitplane_y_start + to_integer(signed(std_logic_vector(bitplanes_y_start)))) then
            bitplane_data_offsets_next(i) <= 0;
          else

            if bitplane_h640 = '1' then
                bitplane_data_offsets_next(i) <= bitplane_y_card_position + (bitplane_y_card_number * 512) + (bitplane_y_card_number * 128);
            elsif bitplane_h1280 = '1' then
                bitplane_data_offsets_next(i) <= bitplane_y_card_position + (bitplane_y_card_number * 1024) + (bitplane_y_card_number * 256);
            else
                bitplane_data_offsets_next(i) <= bitplane_y_card_position + (bitplane_y_card_number * 256) + (bitplane_y_card_number * 64);
            end if;
          end if;
        end loop;

        x_in_bitplanes <= '0';
        bitplanes_reset <= "11111111";           -- flushes bitplane byte buffers
        bitplanes_data_in_valid <= "00000000";
	bitplanes_advance_pixel <= "11111111";
	fetch_ongoing <= '0';
      else
        bitplanes_reset <= "00000000";
      end if;
      if v_x_in = 0 then
        for i in 7 downto 0 loop
          bitplanes_byte_numbers(i) <= 0;
        end loop;
        x_in_bitplanes <= '0';
        bitplanes_reset <= "11111111";           -- flushes bitplane byte buffers
        bitplanes_data_in_valid <= "00000000";
        bitplanes_advance_pixel <= "11111111";
        fetch_ongoing <= '0';
      end if;

      -- Start drawing once we hit the top of the bitplanes.
      -- Note: the logic here means that bitplanes must be enabled at this
      -- point, or they will not be shown at all on the frame!
      if (y_top = '1') and (bitplane_mode_in = '1') then
        bitplane_drawing_next <= '1';
        report "bitplane_drawing asserted.";
      else
        bitplane_drawing_next <= '0';
      end if;

      if bitplane_drawing_next = '1' then
        bitplane_drawing <= '1';
      end if;

      -- Always stop drawing bitplanes at raster 255 (just a little into the
      -- lower border).
      if y_in = (v_bitplane_y_start + to_integer(signed(std_logic_vector(bitplanes_y_start))) + 200) then
        bitplane_drawing <= '0';
        for i in 7 downto 0 loop
          bitplane_data_offsets_next(i) <= 0;
        end loop;
        report "bitplane_drawing cleared.";
      end if;

      if (v_x_in /= x_last) and (bitplane_drawing='1') and (x_in_bitplanes='1') then
        -- Request first or next pixel from each bitplane.
        -- We now fetch enough bytes for 16-colour bitplanes to be at full resolution.
        bitplanes_advance_pixel <= "11111111";
      end if;
      x_last <= v_x_in;

      pixel_out <= pixel_in;
      if (bitplane_mode='1') and (x_in_bitplanes='1') and (bitplane_drawing='1') then
        -- Display bitplanes, and set foreground based on bitplane 2
        -- (but not for 16-colour bitplanes)
        report "bitplane pixel";
        for i in 0 to 7 loop
          if bitplane_enables(i)='1' then
            if bitplanes_sixteen_colour_mode(i)='0' then
              report "bitplanes_pixel_out(" & integer'image(i) & ") = " &
                std_logic'image(bitplanes_pixel_out(i));
              pixel_out(i) <= bitplanes_pixel_out(i) xor bitplane_complements(i);
              if i = 2 then
                is_foreground_out <= bitplanes_pixel_out(i) xor bitplane_complements(i);
              end if;
            else
              -- 16 colour bitplane mode modifies four bits of the colour,
              -- depending on which bitplane it is.
              if bitplanes_pixel16_out(i) /= x"0" then
                pixel_out((3+(i mod 4)) downto (i mod 4)) <= bitplanes_pixel16_out(i);
              end if;
            end if;
          else
            pixel_out(i) <= bitplane_complements(i);
            if i = 2 then
              is_foreground_out <= bitplane_complements(i);
            end if;
          end if;
        end loop;
      end if;
      is_sprite_out <= is_sprite_in;
      sprite_colour_out <= sprite_colour_in;
      sprite_number_out <= sprite_number_in;
    end if;
  end process main;

end behavioural;
