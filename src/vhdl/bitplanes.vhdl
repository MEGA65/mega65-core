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
    ioclock : in std_logic;

    signal fastio_address :in unsigned(19 downto 0);
    signal fastio_write : in std_logic;
    signal fastio_wdata : in unsigned(7 downto 0);
    
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
    signal x_in : in integer range 0 to 4095;
    signal x640_in : in integer range 0 to 4095;
    signal x1280_in : in integer range 0 to 4095;
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
  signal x_left : std_logic := '0';
  signal y_top : std_logic := '0';
  signal x_in_bitplanes : std_logic := '0';
  signal bitplane_drawing : std_logic := '0';
  signal bitplane_x_start : integer range 0 to 4095 := 30;
  signal bitplane_y_start : integer range 0 to 4095 := 30;
  signal bitplanes_answer_data_request_timeout : integer range 0 to 255 := 0;

  signal bitplane_mode : std_logic;
  signal bitplane_enables : std_logic_vector(7 downto 0);
  signal bitplane_complements : std_logic_vector(7 downto 0);

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

  signal bitplanedata_fetching : std_logic := '0';
  signal bitplanedata_fetch_bitplane : integer range 0 to 7;
  
begin  -- behavioural

  -- 4K buffer for holding buffered bitplane data for rendering.
  -- 8 bitplanes x 512 bytes = 4KB.
  -- This is plenty, since we actually only read 80 bytes max per bitplane per
  -- line (actually upto 320 bytes per line when using bitplanes in 16-colour mode)
  bitplanedatabuffer: component ram9x4k
    port map (clka => pixelclock,
              wea(0) => bitplanedatabuffer_write,
              dina => std_logic_vector(bitplanedatabuffer_wdata),
              addraa => std_logic_vector(bitplanedatabuffer_waddress),

              clkb => pixelclock,
              addrb => std_logic_vector(bitplanedatabuffer_address),
              unsigned(doutb) => bitplanedatabuffer_rdata
              );

  generate_bitplanes:  
  for index in 0 to 7 generate  
    begin  
      bitplane_inst : bitplane
      port map (  
        pixelclock => pixelclock,
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
  main: process (pixelclock)
  begin  -- process main
    if ioclock'event and ioclock = '1' then
      -- Allow writing to bitplane buffer memory directly for debugging
      -- (will be overridden if VIC-IV data pipeline is feeding us data)
      -- @IO:GS $FFBF000 - $FFBFFFF - DEBUG allow writing directly to the bitplane data buffer.  Will be removed in production.
      if fastio_write='1' and fastio_address(19 downto 12) = x"BF" then
        bitplanedatabuffer_waddress(11 downto 0)
          <= fastio_address(11 downto 0);
        bitplanedatabuffer_wdata(8) <= '0';
        bitplanedatabuffer_wdata(7 downto 0) <= fastio_wdata;
        bitplanedatabuffer_write <= '1';
      end if;
    end if;
    if pixelclock'event and pixelclock = '1' then  -- rising clock edge

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
      
      if sprite_datavalid_in = '1' and (sprite_spritenumber_in > 7) then
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
        bitplanedatabuffer_waddress(11 downto 9)
          <= to_unsigned(sprite_spritenumber_in mod 8, 3);
        bitplanedatabuffer_waddress(8 downto 0)
          <= to_unsigned(sprite_bytenumber_in, 9);
        bitplanedatabuffer_wdata(8) <= '0';
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
      is_foreground_out <= is_foreground_in;
      is_background_out <= is_background_in;

      -- Work out if we need to fetch a byte
      bitplanedata_fetching <= '0';
      if bitplanes_answer_data_request_timeout = 0 then        
        for i in 7 downto 0 loop
          if bitplanes_data_request(i) = '1' then
            bitplanedatabuffer_address(11 downto 9) <= to_unsigned(i,3);
            bitplanedatabuffer_address(8 downto 0)
              <= to_unsigned(bitplanes_byte_numbers(i),9);
            bitplanedata_fetch_bitplane <= i;
            if bitplanes_byte_numbers(i) < 511 then
              bitplanes_byte_numbers(i) <= bitplanes_byte_numbers(i) + 1;
            else
              bitplanes_byte_numbers(i) <= 0;
            end if;
            -- Only fetch the byte if we have not reached the end of the bitplane
            if bitplanes_byte_numbers(i) < 320 then
              bitplanedata_fetching <= '1';
            end if;
          end if;
        end loop;
      else
        -- Reduce timeout before we honour bitplane fetch requests
        bitplanes_answer_data_request_timeout
          <= bitplanes_answer_data_request_timeout - 1;
      end if;
      
      -- Pass fetched data to bitplanes if data is available
      bitplanes_data_in_valid <= "00000000";
      if bitplanedata_fetching = '1' then
        bitplanes_data_in <= bitplanedatabuffer_rdata(7 downto 0);
        bitplanes_data_in_valid(bitplanedata_fetch_bitplane) <= '1';
      end if;
      
      -- Work out when we start drawing the bitplane
      y_last <= y_in;
      if y_last = bitplane_y_start then
        y_top <= '1';
        report "asserting y_top";
        -- Start requesting pixels from bitplanes to empty their buffers.
        bitplanes_advance_pixel <= "11111111";
        -- Allow enough cycles to flush the buffers in single-colour (C65) bitplane mode
        bitplanes_answer_data_request_timeout <= 64;
      else
        y_top <= '0';
      end if;

      bitplanes_advance_pixel <= "00000000";
      -- XXX: Bitplane output is delayed by one physical pixel here.
      -- This means that the bitplanes needs to be fed the x value one pixel clock
      -- early, or bitplanes will be offset by one physical pixel.
      -- Also, we need to have a 640 and 1280 pixel clock to do
      -- higher-resolution bitplanes for full C65 compatibility.
      -- None of the above has yet been done.
      if x_in = bitplane_x_start
        and (y_top='1' or bitplane_drawing='1') then
        x_left <= '1';
        x_in_bitplanes <= '1';
        report "asserting x_left and x_in_bitplanes";
      else
        x_left <= '0';
      end if;
      -- Clear bitplane byte numbers at the start of each raster.
      if x_in = 0 then
        for i in 7 downto 0 loop
          bitplanes_byte_numbers(i) <= 0; 
        end loop;
      end if;

      -- Start drawing once we hit the top of the bitplanes.
      -- Note: the logic here means that bitplanes must be enabled at this
      -- point, or they will not be shown at all on the frame!
      if (y_top = '1') and (bitplane_mode_in = '1') then
        bitplane_drawing <= '1';
        report "bitplane_drawing asserted.";
      end if;
      -- Always stop drawing bitplanes at raster 255 (just a little into the
      -- lower border).
      if y_in = 255 then
        bitplane_drawing <= '0';
        report "bitplane_drawing cleared.";
      end if;
        
      if (x_in /= x_last) and (bitplane_drawing='1') then
        -- Request first or next pixel from each bitplane.
        -- We now fetch enough bytes for 16-colour bitplanes to be at full resolution.
        bitplanes_advance_pixel <= "11111111";
      end if;              

      pixel_out <= pixel_in;
      if (bitplane_mode='1') and (border_in='0') and (bitplane_drawing='1') then
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
    end if;
  end process main;

end behavioural;
