-- Hardware thumbnail generator and frame packer, used for preparing frames
-- for sending via 100mbit ethernet for digital screen capture.
-- 100mbit = ~12MB/sec.  800x600 60Hz = ~30Mpixels per second, so we need
-- to use < 12/30 = 0.4 bytes per pixel on average.
-- A bit-oriented packer is probably best here.
-- 0 = previous pixel colour (since this happens a lot)
-- 10 = pen-ultimate pixel colour
-- 1100-1110 = colour of three other most recent pixel colours
-- 11110yyyyyyyyyyyy = explicit 12-bit pixel colour
-- 111110yy yyyyyyyy - New raster, with raster number encoded
-- 11111100 - New frame
-- 11111101 - RESERVED (maybe will use for 24 bit colour values?)
-- 11111110 nnnnnnnn - Run of 1 to 256 pixels of the same colour as the last.
-- 11111111 - end of packet marker.
--
-- This should hopefully reduce the bandwidth requirement enough, 
-- requiring likely less than 1 bit per pixel for a typical text display.
-- For the situation where there is insufficient bandwidth, we should have a
-- mechanism to make sure we don't repeatedly miss the same rasters.  This is
-- however less likely, now that we are packing multiple rasters in a packet.
-- Worse case scenario is 17 bits per pixel, plus raster and frame markers,
-- which would mean that we would need ~60MB/sec = 5x too much. To deal with
-- packet loss gracefully, we should always begin a new packet on a new symbol,
-- and also forget the most recent colour list (or better, pre-initialise it with
-- some likely culprits) on any given packet so that we can always synchronise.
-- By having the raster numbers labeled, we can do this quite effectively.
--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2014,2018
--
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

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity framepacker is
  port (
    pixelclock : in std_logic;
    ioclock : in std_logic;
    hypervisor_mode : in std_logic;
    thumbnail_cs : in std_logic;
    
    -- Signals from VIC-IV
    pixel_stream_in : in unsigned (7 downto 0);
    pixel_red_in : in unsigned(7 downto 0);
    pixel_green_in : in unsigned(7 downto 0);
    pixel_blue_in : in unsigned(7 downto 0);
    pixel_y : in unsigned (11 downto 0);
    pixel_valid : in std_logic;
    pixel_newframe : in std_logic;
    pixel_newraster : in std_logic;

    -- Signals for ethernet controller
    buffer_moby_toggle : out std_logic := '0';
    buffer_address : in unsigned(11 downto 0);
    buffer_rdata : out unsigned(7 downto 0);    
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at CPU clock).
    ---------------------------------------------------------------------------
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0)
    );
end framepacker;

architecture behavioural of framepacker is
  
  -- components go here
  component videobuffer IS
    PORT (
      clka : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      addra : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      clkb : IN STD_LOGIC;
      addrb : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
      );
  END component;

  signal output_address_internal : unsigned(11 downto 0) := (others => '0');
  signal output_address : unsigned(11 downto 0);
  signal output_data : unsigned(7 downto 0);
  signal output_write : std_logic := '0';

  signal thumbnail_write_address : unsigned(11 downto 0);
  signal thumbnail_read_address : unsigned(11 downto 0);
  signal thumbnail_wdata : unsigned(7 downto 0);
  signal thumbnail_rdata : unsigned(7 downto 0);
  signal thumbnail_valid : std_logic := '0';
  signal thumbnail_started : std_logic := '0';  
  signal thumbnail_active_pixel : std_logic := '0';
  signal thumbnail_active_row : std_logic := '0';

  signal last_pixel_y : unsigned(11 downto 0);
  signal pixel_drive : unsigned(7 downto 0);
  signal last_hypervisor_mode : std_logic := '0'; 
  signal last_access_is_thumbnail : std_logic := '0';
  signal thumbnail_x_counter : integer range 0 to 24 := 0;
  signal thumbnail_y_counter : integer range 0 to 24 := 0;


  signal x_counter : integer range 0 to 4095 := 0;
  signal bit_queue_len : integer range 0 to 32 := 0;
  signal bit_queue : std_logic_vector(31 downto 0) := (others => '0');
  signal bits_appended : integer range 0 to 32 := 0;
  signal new_bits : std_logic_vector(31 downto 0) := (others => '0');
  signal rle_count : integer range 0 to 255 := 0;
  signal colour0 : std_logic_vector(11 downto 0) := (others => '0');
  signal colour1 : std_logic_vector(11 downto 0) := (others => '0');
  signal colour2 : std_logic_vector(11 downto 0) := (others => '0');
  signal colour3 : std_logic_vector(11 downto 0) := (others => '0');
  signal colour4 : std_logic_vector(11 downto 0) := (others => '0');
  
begin  -- behavioural

  videobuffer0: videobuffer port map (
    clka => pixelclock,
    wea(0) => output_write,
    addra => std_logic_vector(output_address),
    dina => std_logic_vector(output_data),
    clkb => ioclock,
    addrb => std_logic_vector(buffer_address),
    unsigned(doutb) => buffer_rdata
    );

  thumnailbuffer0: videobuffer port map (
    clka => pixelclock,
    wea(0) => '1',
    addra => std_logic_vector(thumbnail_write_address),
    dina => std_logic_vector(thumbnail_wdata),
    clkb => ioclock,
    addrb => std_logic_vector(thumbnail_read_address),
    unsigned(doutb) => thumbnail_rdata
    );

  -- Look after CPU side of mapping of compressed data
  process (ioclock,fastio_addr,fastio_wdata,fastio_read,fastio_write,
           thumbnail_cs,thumbnail_read_address,thumbnail_rdata,
           thumbnail_valid,thumbnail_started
           ) is
    variable temp_cmd : unsigned(7 downto 0);
  begin

    -- Provide read access to thumbnail buffer.  To simplify things, we won't
    -- memory map the whole thing, but just provide a 2-byte interface to reset
    -- the read address, and to read a byte of data.  We will also provide a
    -- flag that indicates if a complete frame has been processed since the
    -- last read of the reset register.  This will allow the hypervisor to
    -- detect if the thumbnail is valid, or if it is still showing data from
    -- another process.
    if fastio_read='1' and (thumbnail_cs='1') then
      if fastio_addr(3 downto 0) = x"2" then
        -- @IO:GS $D632 - Lower 8 bits of thumbnail buffer read address (TEMPORARY DEBUG REGISTER)
        fastio_rdata <= thumbnail_read_address(7 downto 0);
      elsif fastio_addr(3 downto 0) = x"1" then
        -- @IO:GS $D631 - Read port for thumbnail generator
        fastio_rdata <= thumbnail_rdata;
      elsif fastio_addr(3 downto 0) = x"0" then
        -- @IO:GS $D630-$D631 - Read-only hardware-generated thumbnail of display (accessible only in hypervisor mode)
        -- @IO:GS $D630 - Write to reset port address for thumbnail generator
        -- @IO:GS $D630 - Read to obtain status of thumbnail generator.
        -- @IO:GS $D630.7 - Thumbnail is valid if 1.  Else there has not been a complete frame since elapsed without a trap to hypervisor mode, in which case the thumbnail may not reflect the current process.
        -- @IO:GS $D630.6 - Thumbnail drawing was in progress.
        thumbnail_read_address <= (others => '0');
        fastio_rdata(7) <= thumbnail_valid;
        fastio_rdata(6) <= thumbnail_started;
        fastio_rdata(5 downto 0) <= (others => '0');
      else
        fastio_rdata <= (others => 'Z');
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;
    
    if rising_edge(ioclock) then

      -- Tell ethernet controller which half of the buffer we are writing to.
      -- Ethernet controller autonomously sends the contents of the other half
      -- whenever we switch halves.
      buffer_moby_toggle <= output_address_internal(11);

      -- Logic to control port address for thumbnail buffer
      if (fastio_read='1') and (thumbnail_cs='1') then
        if fastio_addr(3 downto 0) = x"1" then
          last_access_is_thumbnail <= '1';
          if last_access_is_thumbnail = '0' then
            thumbnail_read_address <= thumbnail_read_address + 1;
          end if;
        else
          last_access_is_thumbnail <= '0';
        end if;       
      else
        last_access_is_thumbnail <= '0';
      end if;             
    end if;
  end process;

  -- Receive pixels and compress
  -- Also write pixels to thumbnail buffer

  process (pixelclock) is
    variable next_byte_valid : std_logic := '0';
    variable next_byte : std_logic_vector(7 downto 0) := "00000000";
  begin
    if rising_edge(pixelclock) then

      -- Work out address to write pixel to in thumbnail buffer.
      -- 80x50 pixels = 4,000 bytes.
      -- 600 / 50 = every 12th row 
      -- 800 / 80 = every 10th column
      last_pixel_y <= pixel_y;
      if to_integer(last_pixel_y) /= to_integer(pixel_y) then
        if to_integer(pixel_y) = 0 then
          thumbnail_write_address <= (others => '0');
          report "THUMB: Reset write address";
          thumbnail_y_counter <= 0;
          thumbnail_x_counter <= 0;
          thumbnail_active_row <= '0';
        end if;
        if thumbnail_y_counter < 11 then
          thumbnail_y_counter <= thumbnail_y_counter + 1;
          thumbnail_active_row <= '0';
          report "THUMB: active_row cleared on row "
            & to_string(std_logic_vector(pixel_y));
        else
          thumbnail_valid <= thumbnail_started;
          thumbnail_started <= '1';
          thumbnail_y_counter <= 0;
          thumbnail_active_row <= '1';
          report "THUMB: active_row asserted on row "
            & to_string(std_logic_vector(pixel_y));
        end if;
      end if;
      if pixel_newraster='1' then
        x_counter <= 0;
      end if;
      if pixel_valid = '1' then
        if pixel_newraster='1' then
          x_counter <= 0;
        else
          x_counter <= x_counter + 1;
        end if;
        if thumbnail_x_counter < 9 then
          -- Make sure it doesn't wrap around within a frame if things go wrong.
          if thumbnail_x_counter< 4000 then
            thumbnail_x_counter <= thumbnail_x_counter + 1;
          end if;
          thumbnail_active_pixel <= '0';
        else
          thumbnail_x_counter <= 0;
          thumbnail_active_pixel <= thumbnail_active_row;
        end if;
      end if;
      if thumbnail_active_pixel='1' then
        thumbnail_write_address
          <= to_unsigned(to_integer(thumbnail_write_address) + 1,12);
        thumbnail_wdata <= pixel_drive;
        report "THUMB: Writing pixel $" & to_hstring(pixel_drive)
          & " @ $" & to_hstring(thumbnail_write_address);
      end if;
      pixel_drive <= pixel_stream_in;

      if hypervisor_mode = '0' and last_hypervisor_mode = '1' then
        thumbnail_started <= '0';
        thumbnail_valid <= '0';
      end if;

      bits_appended <= 0;
      if pixel_newframe='1' then
        -- Encode new frame.
        -- (no need to output RLE remainder, as it is implied that missing
        -- pixels will be the same colour)
        bits_appended <= 8;
        new_bits <= "11111100"&"00000000"&"00000000"&"00000000";
      elsif pixel_newraster='1' then
        -- Encode new raster
        -- (no need to output RLE remainder, as it is implied that missing
        -- pixels will be the same colour)
        bits_appended <= 16;
        new_bits <= "111110" & std_logic_vector(pixel_y(9 downto 0)) & "00000000" & "00000000";
      elsif pixel_valid='1' then
        -- Work out how to encode this pixel
        -- If the same as the last, then accumulate RLE, and output RLE
        -- token if RLE run is full.
        -- If not the same as the last, then output RLE if run warrants it,
        -- else output the bit vector for the pixels.  After outputing
        -- RLE/pixel vector, output token for encoding this pixel.
        report "PACKER: considering raw pixel (" & integer'image(x_counter) & "," & integer'image(to_integer(pixel_y)) & ")"
          & " #" & to_hstring(pixel_red_in)
          & to_hstring(pixel_green_in) & to_hstring(pixel_blue_in) & " in raster $" & to_hstring(pixel_y);
        if std_logic_vector(pixel_red_in(7 downto 4) & pixel_green_in(7 downto 4) & pixel_blue_in(7 downto 4)) = colour0 then
          bits_appended <= 1;
          new_bits <= "00000000"&"00000000"&"00000000"&"00000000";          
        elsif std_logic_vector(pixel_red_in(7 downto 4) & pixel_green_in(7 downto 4) & pixel_blue_in(7 downto 4)) = colour1 then
          bits_appended <= 2;
          new_bits <= "10"&"000000"&"00000000"&"00000000"&"00000000";
          colour0 <= colour1;
          colour1 <= colour0;
        elsif std_logic_vector(pixel_red_in(7 downto 4) & pixel_green_in(7 downto 4) & pixel_blue_in(7 downto 4)) = colour2 then
          bits_appended <= 4;
          new_bits <= "1100"&"0000"&"00000000"&"00000000"&"00000000";
          colour0 <= colour2;
          colour1 <= colour0;
          colour2 <= colour1;
        elsif std_logic_vector(pixel_red_in(7 downto 4) & pixel_green_in(7 downto 4) & pixel_blue_in(7 downto 4)) = colour3 then
          bits_appended <= 4;
          new_bits <= "1101"&"0000"&"00000000"&"00000000"&"00000000";
          colour0 <= colour3;
          colour1 <= colour0;
          colour2 <= colour1;
          colour3 <= colour2;
        elsif std_logic_vector(pixel_red_in(7 downto 4) & pixel_green_in(7 downto 4) & pixel_blue_in(7 downto 4)) = colour4 then
          bits_appended <= 4;
          new_bits <= "1110"&"0000"&"00000000"&"00000000"&"00000000";
          colour0 <= colour4;
          colour1 <= colour0;
          colour2 <= colour1;
          colour3 <= colour2;
          colour4 <= colour3;
        else
          bits_appended <= 17;
          new_bits <= "11110" & std_logic_vector(pixel_red_in(7 downto 4) & pixel_green_in(7 downto 4) & pixel_blue_in(7 downto 4)) & "0000000"&"00000000";
          colour0 <= std_logic_vector(pixel_red_in(7 downto 4) & pixel_green_in(7 downto 4) & pixel_blue_in(7 downto 4));
          colour1 <= colour0;
          colour2 <= colour1;
          colour3 <= colour2;
          colour4 <= colour3;
        end if;
      end if;

      -- Pack accumulated bits
      -- Here we have a bit of a problem: The longest token is 17 bit, i.e., 2
      -- and a bit bytes.  This means it can take upto three cycles for us to
      -- commit this to the packet buffer a byte at a time.  But the 60Hz video
      -- mode can produce some pixels only 2 cycles apart.  The average is 2.5
      -- cycles per pixel, however.  Further complication is if we have an RLE
      -- token that we need to flush, which means we can need to flush five
      -- bytes in the worst case.
      -- Of course, if we have a fully random display, then we can need 17 bits
      -- for EVERY pixel.  This is however less than the 2.5 average cycles per
      -- pixel, so that's okay.  The RLE tokens can only happen at most every
      -- 16 pixels (since less than 16 pixels are more efficiently coded using
      -- the 1-bit-per-pixel token).
      -- So really the problem is just one of dealing with the burst of two long
      -- code words that have to be flushed in only two cycles.  Thus, we need
      -- some sort of buffering arrangement.
      -- So, the most we need to flush is 5 bytes. We know that we have at
      -- least 2 cycles immediately.  It can take 3 cycles to flush the RLE
      -- token, based on where the byte boundary falls, which is a bit annoying.
      -- But what we can see is that the buffer doesn't need to be very big.
      -- Also, we can make the buffer to double duty, by encodin the RLE tokens
      -- as it goes.
      if bit_queue_len /= 0 then
        report "Existing bit queue = %" & to_string(bit_queue(31 downto (32 - bit_queue_len)));
      else
        report "Bit queue empty.";
      end if;
      next_byte_valid := '0';
      if bits_appended /= 0 then
        report "Appending " & integer'image(bits_appended) & " bits = %" & to_string(new_bits(31 downto (32-bits_appended)));
        if bits_appended=1 then
          -- It's the same colour as the last pixel, so collect RLE token
          if rle_count < 255 then
            rle_count <= rle_count + 1;
            -- Nothing to emit from this token, so just keep flushing out
            -- any pending bits.
            if bit_queue_len > 7 then
              bit_queue_len <= bit_queue_len - 8;
              next_byte_valid := '1';
              next_byte := bit_queue(31 downto 24);
              bit_queue(31 downto 8) <= bit_queue(23 downto 0);
            end if;
          else
            -- RLE token full, so emit
            -- We can safely assume that there is nothing else queued, because
            -- otherwise we wouldn't have a full RLE token :)
            next_byte_valid := '1';
            next_byte := "11111110";
            bit_queue_len <= 8;
            bit_queue(31 downto 24) <= "11111111";
            rle_count <= 0;
          end if;
        else
          -- Some other token.
          -- The pain is that we have to glue all the bits together.
          -- So what we can do is to defer the new token to the next cycle,
          -- and just append the RLE token/bits for now

          -- Now work out what to do about the RLE bits...
          if rle_count = 0 then
            -- The easy case: No RLE to flush, so just write the token
            if bit_queue_len > 7 then
              report "Appending " & integer'image(bits_appended) & " to " & integer'image(bit_queue_len)
                & " existing bits in queue (flushing old byte first)";
              next_byte := bit_queue(31 downto 24);
              next_byte_valid := '1';
              bit_queue(31 downto 8) <= bit_queue(23 downto 0);
              bit_queue(31 - (bit_queue_len - 8) downto 0)
                <= new_bits(31 downto (bit_queue_len - 8));
              bit_queue_len <= bit_queue_len - 8 + bits_appended;
            elsif (bit_queue_len + bits_appended) > 7 then
              -- New token plus existing queue is >= 1 byte, so output mashed byte
              report "Appending " & integer'image(bits_appended) & " to " & integer'image(bit_queue_len)
                & " existing bits in queue (hybrid byte)";
              if bit_queue_len > 0 then
                next_byte := bit_queue(31 downto (31 - bit_queue_len)) & new_bits(31 downto (24 + bit_queue_len));
              else
                next_byte := new_bits(31 downto 24);
              end if;
              next_byte_valid := '1';
              bit_queue(31 downto (8 - bit_queue_len)) <= new_bits((23 + bit_queue_len) downto 0);
              bit_queue_len <= bit_queue_len - 8 + bits_appended;
            else
              -- Append token to end of partial byte 
              report "Appending " & integer'image(bits_appended) & " to " & integer'image(bit_queue_len)
                & " existing bits in queue (accumulating partial byte)";
              bit_queue(31 - (bit_queue_len - 8) downto 0)
                <= new_bits(31 downto (bit_queue_len - 8));
              bit_queue_len <= bit_queue_len + bits_appended;
            end if;
          elsif rle_count /= 0 and rle_count < 17 then
            -- RLE run is more efficiently output as the single bit vector.
            -- If RLE count is more than some very small amount (possibly even
            -- just zero), then we can be sure that there are no backed up bits,
            -- as they would have had time to flush out.
            
            -- Mark the new token as still needing processing
            bits_appended <= bits_appended;
            
            -- Append the RLE vector to the bit queue
            if (bit_queue_len + rle_count) > 39 then
              -- We have a problem houston! The data is coming too fast
              -- for our available bandwidth.
              -- Things will now go pearshaped for the remainder of this raster.
              -- (We stuff as many pixels as we can in, but we will have missed
              -- some).
              if bit_queue_len > 7 then
                bit_queue_len <= 32;
                next_byte_valid := '1';
                next_byte := bit_queue(31 downto 24);
                bit_queue(31 downto 8) <= bit_queue(23 downto 0);
                bit_queue(7 downto 0) <= "00000000";
                if rle_count > 7 then
                  rle_count <= rle_count - 8;
                else
                  rle_count <= 0;
                end if;
              end if;
            else
              -- Whew! We can fit the data in
              if bit_queue_len > 7 then
                bit_queue_len <= (bit_queue_len + rle_count) - 8;
                next_byte_valid := '1';
                next_byte := bit_queue(31 downto 24);
                bit_queue(31 downto 8) <= bit_queue(23 downto 0);
                bit_queue(7 downto 0) <= "00000000";
                if rle_count > 7 then
                  rle_count <= rle_count - 8;
                else
                  rle_count <= 0;
                end if;
              else
                -- So we don't have a whole byte to stuff just yet.
                -- But we can send off the current set of bits and
                -- the RLE bits, but only if that all adds up to at least
                -- 8 bits. Else we just need to stuff it in the bit queue
                if (bit_queue_len + rle_count) > 7 then
                  bit_queue_len <= (bit_queue_len + rle_count) - 8;
                  next_byte := bit_queue(31 downto 24);
                  next_byte((7 - bit_queue_len) downto 0) := (others => '0');
                  bit_queue(31 downto 0) <= (others => '0');
                else
                  bit_queue_len <= (bit_queue_len + rle_count);
                  bit_queue(31 - bit_queue_len downto 0) <= (others => '0');
                end if;
              end if;              
            end if;                        
          else
            -- RLE run is long, so output proper RLE token
            -- Here we can be sure there are no backed up bits, and can output
            -- the RLE token immediately.

            -- Mark the new token as still needing processing
            bits_appended <= bits_appended;
            
            next_byte_valid := '1';
            next_byte := "11111110";
            bit_queue_len <= 8;
            bit_queue(31 downto 24) <= std_logic_vector(to_unsigned(rle_count,8));
            rle_count <= 0;
          end if;
        end if;
      else
        -- No new token, just keep pushing byte at a time out
        if bit_queue_len > 7 then
          bit_queue_len <= bit_queue_len - 8;
          next_byte := bit_queue(31 downto 24);
          next_byte_valid := '1';
          bit_queue(31 downto 8) <= bit_queue(23 downto 0);                 
        end if;                                       
      end if;

      if next_byte_valid = '1' then
        -- XXX Need to detect when we get close to full, so that we can
        -- consciously flip buffer halves, and reset the move to front coder.
        if output_address_internal(10 downto 0) /= "1111111111" then
          output_address <= output_address_internal + 1;
          output_address_internal <= output_address_internal + 1;
        else
          -- Flip half of packet buffer if required
          output_address(11) <= not output_address(11);
          output_address(10 downto 0) <= (others => '0');
          output_address_internal(10 downto 0) <= (others => '0');
        end if;
        report "Commiting byte $" & to_hstring(next_byte) & " to packet buffer @ offset " & integer'image(output_address_internal);
        output_data <= unsigned(next_byte);
        output_write <= '1';
      else
        output_write <= '0';
      end if;

    end if;
  end process;
  
end behavioural;
