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

    -- Signals from VIC-IV
    pixel_stream_in : in unsigned (7 downto 0);
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
  
  -- signals go here
  signal pixel_count : unsigned(7 downto 0) := x"00";
  signal last_pixel_value : unsigned(7 downto 0) := x"00";
  signal dispatch_frame : std_logic := '0';

  signal output_address_internal : unsigned(11 downto 0) := (others => '0');
  signal output_address : unsigned(11 downto 0);
  signal output_data : unsigned(7 downto 0);
  signal output_write : std_logic := '0';
  
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
  
  -- Look after CPU side of mapping of compressed data
  process (ioclock,fastio_addr,fastio_wdata,fastio_read,fastio_write
           ) is
    variable temp_cmd : unsigned(7 downto 0);
  begin

    if fastio_read='1' and (fastio_addr(19 downto 12) = x"01") then
      -- XXX Map buffer here in 4KB pieces
    elsif fastio_read='1' and (fastio_addr(19 downto 4) = x"D500") then
      case fastio_addr(3 downto 0) is
        when x"0" => -- status flags
          -- bit 7 = DONE
          -- bit 6 = buffer overrun (only partial frame captured)
        when x"1" =>  -- low byte of buffer pointer
        when x"2" => -- high byte of buffer pointer
          
        when others =>
          fastio_rdata <= (others => 'Z');
      end case;
    else
      fastio_rdata <= (others => 'Z');
    end if;
   
    if rising_edge(ioclock) then
      -- Tell ethernet controller which half of the buffer we are writing to.
      -- Ethernet controller autonomously sends the contents of the other half
      -- whenever we switch halves.
      buffer_moby_toggle <= output_address_internal(11);
    end if;
  end process;

  -- Receive pixels and compress

  -- We use a very simple RLE scheme for now, which supports only 128 colours.
  -- When we see a pixel of a new colour we write the bottom 7 bits of the
  -- colour with 0 in the MSB.  During each subsequent instance, we write the
  -- updated count with MSB set to 1, unless a different colour (or RLE overflow)
  -- occurs, in which case we advance the address pointer, and write the new colour
  -- and continue the process.  In this way we never need to write >1 byte per
  -- cycle, and rasters without repetition take 1 byte per pixel.  It also
  -- means that we never have any data to flush at the end of frame.
  process (pixel_newraster,pixel_stream_in,pixel_valid,pixel_newframe,pixelclock) is
  begin
    if rising_edge(pixelclock) then
      if pixel_valid='1' then
        -- report "PACKER: pixel=$"&to_hstring(pixel_stream_in) severity note;      
        
        if (pixel_stream_in /= last_pixel_value) or pixel_count = x"7F" then
          -- end of last RLE

          report "PACKER: Recording $"&to_hstring(pixel_count)&" x $"
            & to_hstring(last_pixel_value) & " coloured pixels." severity note;

          output_address_internal <= output_address_internal + 1;
          output_address <= output_address_internal + 1;
          output_data <= '0'&pixel_stream_in(6 downto 0);
          output_write <= '1';
          
          last_pixel_value <= pixel_stream_in;
          pixel_count <= x"01";
        else
          -- add to existing RLE
          pixel_count <= pixel_count + 1;

          if pixel_count = x"01" then
            output_address_internal <= output_address_internal + 1;
            output_address <= output_address_internal + 1;
          end if;
          output_data <= '1'&(pixel_count(6 downto 0) + 1);
          output_write <= '1';          
        end if;
      else
        output_write <= '0';
      end if;
      if pixel_newframe='1' then        
        report "PACKER: ------ NEW FRAME" severity note;

        -- Write end of frame marker.
        output_address_internal <= output_address_internal + 1;
        output_address <= output_address_internal + 1;
        output_data <= x"80";  -- length byte with value 0 means end of frame
        output_write <= '1';

        -- Reset pixel value state
        last_pixel_value <= x"00";
        pixel_count <= x"00";
      end if;
    end if;
  end process;
  
end behavioural;
