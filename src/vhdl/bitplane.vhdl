--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2015
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

entity bitplane is
  Port (
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;

    reset : in std_logic;

    advance_pixel : in std_logic;
    sixteen_colour_mode : in std_logic;

    data_in_valid : in std_logic;
    data_in : in unsigned(7 downto 0);
    data_request : out std_logic := '0';
    
    pixel_out : out std_logic := '0';
    pixel16_out : out unsigned(3 downto 0) := x"0"
    );

end bitplane;

architecture behavioural of bitplane is

  signal byte_bits_available : integer range 0 to 8 := 0;
  signal byte_buffer_head : std_logic_vector(7 downto 0);
  signal byte_buffer_2 : std_logic_vector(7 downto 0);
  signal byte_buffer_3 : std_logic_vector(7 downto 0);

  signal bb_valid_h : std_logic := '0';
  signal bb_valid_2 : std_logic := '0';
  signal bb_valid_3 : std_logic := '0';

begin

  process (pixelclock)
    variable v_bb_valid_h : std_logic := '0';
    variable v_bb_valid_2 : std_logic := '0';
    variable v_bb_valid_3 : std_logic := '0';
    variable v_byte_bits_available : integer range 0 to 8 := 0;
    variable v_byte_buffer_head : std_logic_vector(7 downto 0);
    variable v_byte_buffer_2 : std_logic_vector(7 downto 0);
    variable v_byte_buffer_3 : std_logic_vector(7 downto 0);

  begin
    if pixelclock'event and pixelclock = '1' then

      -- XXX Note that the buffer handling, both on input and output, assumes
      -- that new bytes are not supplied on successive clocks, nor that new
      -- pixels are required on successive clocks.  This keeps the logic
      -- somewhat simpler.
      
      if reset='1' then
--          report "Flushing buffered bytes from bitstream.";
          bb_valid_h <= '0';
          bb_valid_2 <= '0';
          bb_valid_3 <= '0';
      else

      -- Request more data if our buffer is not full.
      if (bb_valid_h='0' or bb_valid_2='0' or bb_valid_3='0') then
        data_request <= '1';
      else
        data_request <= '0';
      end if;

      v_bb_valid_h := bb_valid_h;
      v_bb_valid_2 := bb_valid_2;
      v_bb_valid_3 := bb_valid_3;
      v_byte_bits_available := byte_bits_available;
      v_byte_buffer_head := byte_buffer_head;
      v_byte_buffer_2 := byte_buffer_2;
      v_byte_buffer_3 := byte_buffer_3;

      -- Accept new data if available
      if data_in_valid='1' then
          if bb_valid_h='0' then
              v_byte_buffer_head := std_logic_vector(data_in);
              v_bb_valid_h := '1';
              v_byte_bits_available := 8;
          elsif bb_valid_2='0' then
              v_byte_buffer_2 := std_logic_vector(data_in);
              v_bb_valid_2 := '1';
          elsif bb_valid_3='0' then
              v_byte_buffer_3 := std_logic_vector(data_in);
              v_bb_valid_3 := '1';
          end if;        
      end if;

      if advance_pixel='1' then
        if sixteen_colour_mode='0' then
            if v_byte_bits_available > 0 then   
	      v_byte_bits_available := v_byte_bits_available - 1;
	      pixel_out <= v_byte_buffer_head(7);
	      v_byte_buffer_head(7 downto 1) := v_byte_buffer_head(6 downto 0);
	      v_byte_buffer_head(0) := '0';
	      --pixel_out <= '1';
	      if v_byte_bits_available = 0 then
	        -- We are using the last bit, so mark byte as empty.
	        v_bb_valid_h := '0';
	        if v_bb_valid_2='1' then
	          -- Shuffle buffer down as required
		  v_byte_buffer_head := byte_buffer_2;
	  	  v_byte_bits_available := 8;
		  v_bb_valid_h := '1';
		  if v_bb_valid_3='1' then
		    v_byte_buffer_2 := byte_buffer_3;
		    v_bb_valid_2 := '1';
		    v_bb_valid_3 := '0';
		  else
		    v_bb_valid_2 := '0';
		  end if;
	      end if;
            end if;
          end if;
        else
          v_byte_bits_available := v_byte_bits_available - 4;
          v_byte_buffer_head(7 downto 4) := v_byte_buffer_head(3 downto 0);
          v_byte_buffer_head(3 downto 0) := x"0";
          if v_byte_bits_available < 4 then
            -- We are using the last bit, so mark byte as empty.
            v_bb_valid_h := '0';
          end if;
          pixel16_out <= unsigned(v_byte_buffer_head(7 downto 4));
        end if;

      end if;
      bb_valid_h <= v_bb_valid_h;
      bb_valid_2 <= v_bb_valid_2;
      bb_valid_3 <= v_bb_valid_3;
      byte_bits_available <= v_byte_bits_available;
      byte_buffer_head <= v_byte_buffer_head;
      byte_buffer_2 <= v_byte_buffer_2;
      byte_buffer_3 <= v_byte_buffer_3;
      end if;
      
    end if;

  end process;

end behavioural;
