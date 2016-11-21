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
    hypervisor_mode : in std_logic;
    
    -- Signals from VIC-IV
    pixel_stream_in : in unsigned (7 downto 0);
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

  component CRC is
    Port 
      (  
        CLOCK               :   in  std_logic;
        RESET               :   in  std_logic;
        DATA                :   in  std_logic_vector(7 downto 0);
        LOAD_INIT           :   in  std_logic;
        CALC                :   in  std_logic;
        D_VALID             :   in  std_logic;
        CRC                 :   out std_logic_vector(7 downto 0);
        CRC_REG             :   out std_logic_vector(31 downto 0);
        CRC_VALID           :   out std_logic
        );
  end component CRC;
  
  -- signals go here
  signal pixel_count : unsigned(7 downto 0) := x"00";
  signal last_pixel_value : unsigned(7 downto 0) := x"FF";
  signal dispatch_frame : std_logic := '0';

  signal new_raster_pending : std_logic := '0';
  signal new_raster_phase : integer range 0 to 8;
  signal next_draw_raster : unsigned(11 downto 0) := to_unsigned(1,12);
  
  signal output_address_internal : unsigned(11 downto 0) := (others => '0');
  signal output_address : unsigned(11 downto 0);
  signal output_data : unsigned(7 downto 0);
  signal output_write : std_logic := '0';
  signal draw_this_raster : std_logic := '0';
  signal just_drew_a_raster : std_logic := '0';

  signal crc_data_in : unsigned(7 downto 0);
  signal crc_reg : unsigned(31 downto 0);
  signal crc_load_init : std_logic := '0';
  signal crc_calc_en : std_logic := '0';
  signal crc_d_valid : std_logic := '0';

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

  raster_crc : CRC
    port map(
      CLOCK           => pixelclock,
      RESET           => '0',
      DATA            => std_logic_vector(crc_data_in),
      LOAD_INIT       => crc_load_init,
      CALC            => crc_calc_en,
      D_VALID         => crc_d_valid,
      CRC             => open,
      unsigned(CRC_REG)         => crc_reg,
      CRC_VALID       => open
      );

  
  -- Look after CPU side of mapping of compressed data
  process (ioclock,fastio_addr,fastio_wdata,fastio_read,fastio_write
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
    if fastio_read='1' then
      if fastio_addr = x"D3632" then
        -- @IO:GS $D632 - Lower 8 bits of thumbnail buffer read address (TEMPORARY DEBUG REGISTER)
        fastio_rdata <= thumbnail_read_address(7 downto 0);
      elsif fastio_addr = x"D3631" then
        -- @IO:GS $D631 - Read port for thumbnail generator
        fastio_rdata <= thumbnail_rdata;
      elsif fastio_addr = x"D3630" then
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
      if fastio_read='1' then
        if fastio_addr = x"D3631" then
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

  process (pixel_newraster,pixel_stream_in,pixel_valid,
           pixel_y,pixel_newframe,pixelclock) is
  begin
    if rising_edge(pixelclock) then

      -- update CRC of raster line
      crc_calc_en <= pixel_valid;
      crc_d_valid <= pixel_valid;
      crc_data_in <= pixel_stream_in;
      crc_load_init <= '0';

      -- Work out address to write pixel to in thumbnail buffer.
      -- 80x50 pixels = 4,000 bytes.
      -- 1200 / 50 = every 24th row 
      -- 1920 / 80 = every 24th column
      last_pixel_y <= pixel_y;
      if to_integer(last_pixel_y) /= to_integer(pixel_y) then
        if to_integer(pixel_y) = 0 then
          thumbnail_write_address <= (others => '0');
          report "THUMB: Reset write address";
          thumbnail_y_counter <= 0;
          thumbnail_x_counter <= 0;
          thumbnail_active_row <= '0';
        end if;
        if thumbnail_y_counter < 23 then
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
      if pixel_valid = '1' then
        if thumbnail_x_counter < 23 then
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

      
      
      if pixel_valid='1' then
--        report "PACKER: considering raw pixel $" & to_hstring(pixel_stream_in) & " in raster $" & to_hstring(pixel_y);        
        if draw_this_raster = '1' then
          -- Write raw pixel
          report "PACKER: writing raw pixel $" & to_hstring(pixel_stream_in)&" @ $" & to_hstring(output_address_internal);
          output_address_internal <= output_address_internal + 1;
          output_address <= output_address_internal + 1;
          output_data <= pixel_stream_in;
          output_write <= '1';
        end if;  
      else
        output_write <= '0';
        if new_raster_pending = '1' then

          report "PACKER: ------ NEW RASTER $" & to_hstring(pixel_y) & " (next draw is $" & to_hstring(next_draw_raster) & ")" severity note;

          -- Write end of frame marker.
          report "PACKER: advancing address on end of raster";
          output_address_internal <= output_address_internal + 1;
          output_address <= output_address_internal + 1;
          output_write <= '1';
          case new_raster_phase is
            -- Raster number of most recent raster
            when 0 =>
              -- We set MSB in the raster record that immediately preceeds the
              -- raster we have included in full.
              if pixel_y = next_draw_raster then
                output_data(7) <= '1';
                draw_this_raster <= '1';
              else
                output_data(7) <= '0';
                draw_this_raster <= '0';
              end if;
              output_data(6 downto 4) <= "000";
              output_data(3 downto 0) <= pixel_y(11 downto 8);
            when 1 => output_data <= pixel_y(7 downto 0);
            -- Audio
            when 2 => output_data <= x"01"; -- XXX left audio
            when 3 => output_data <= x"02"; -- XXX right audio
            -- CRC of most recent raster
            when 4 => output_data <= crc_reg(31 downto 24);
            when 5 => output_data <= crc_reg(23 downto 16);
            when 6 => output_data <= crc_reg(15 downto 8);
            when 7 => output_data <= crc_reg(7 downto 0);
                      -- reset CRC
                      crc_load_init <= '1';
                      crc_calc_en <= '0';
            when 8 => output_data <= x"00";
                      if pixel_y = (next_draw_raster+1) then
                        -- only draw one raster per packet, so flip buffer halves after
                        -- drawing a raster.
                        output_address(11) <= not output_address(11);
                        output_address(10 downto 0) <= (others => '0');
                        -- then work out the next raster to draw.
                        -- 1200 rasters, stepping 13 at a time cycles through them all,
                        -- and 13 x 9 byte raster records fits in less than 2048 bytes.
                        if to_integer(next_draw_raster)<(1200-13) then
                          next_draw_raster <= to_unsigned(to_integer(next_draw_raster) + 13,12);
                        else
                          next_draw_raster <= to_unsigned(to_integer(next_draw_raster) + 13 - 1200,12);
                        end if;
                      end if;
          end case;
          if new_raster_phase /= 8 then
            -- get ready to write the next byte in the sequence
            new_raster_phase <= new_raster_phase + 1;
          else
            -- all done
            new_raster_pending <= '0';
            new_raster_phase <= 0;
          end if;
          report "PACKER writing end of raster tags"
            & " @ $" & to_hstring(output_address_internal + 1);

          -- Reset pixel value state
          last_pixel_value <= x"ff";
          pixel_count <= x"00";
        end if;
      end if;
      if pixel_newraster='1' then
        -- This occurs at the end of the previous raster.  There are thus
        -- several cycles with pixel_y stable at this point
        new_raster_pending <= '1';
        new_raster_phase <= 0;
        just_drew_a_raster <= draw_this_raster;
        if just_drew_a_raster = '1' then
          -- make next write happen at start of other half of buffer
          output_address_internal(10 downto 0) <= (others => '1');
        end if;       
      end if;
    end if;
  end process;
  
end behavioural;
