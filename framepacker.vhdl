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

    pixel_stream_in : in unsigned (7 downto 0);
    pixel_valid : in std_logic;
    pixel_newframe : in std_logic;
    pixel_newraster : in std_logic;
    
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
  
  -- signals go here
 
begin  -- behavioural

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
      -- do synchronous stuff
    end if;
  end process;

  -- Receive pixels and compress 
  
end behavioural;
