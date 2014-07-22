--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
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

entity ethernet is
  port (
    clock : in std_logic;
    pixelclk : in std_logic;
    reset : in std_logic;

    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0)
    );
end ethernet;

architecture behavioural of ethernet is

begin  -- behavioural
  
  -- XXX also implement F1011 floppy controller emulation.
  process (clock,fastio_addr,fastio_wdata,fastio_read,fastio_write
           ) is
    variable temp_cmd : unsigned(7 downto 0);
  begin

    if fastio_read='1' then
      if (fastio_addr(19 downto 8)&'0' = x"DE0") then
        case fastio_addr(7 downto 0) is
          when x"00" =>
            -- First IO register
            fastio_rdata <= x"23";
          when x"01" =>
            -- Second IO register
            fastio_rdata <= x"99";
          when others =>
            -- Otherwise tristate output
            fastio_rdata <= (others => 'Z');
        end case;
      else
        -- Otherwise tristate output
        fastio_rdata <= (others => 'Z');
      end if;
    end if;

    
    if rising_edge(clock) then

      -- Update module status based on register reads
      if fastio_read='1' then
        if fastio_addr(19 downto 0) = x"DE000" then
          -- If the CPU is reading from this register, then in addition to
          -- reading the register contents asynchronously, do something,
          -- for example, clear an interrupt status, or tell the ethernet
          -- controller that the packet buffer is okay to overwrite.
        end if;
      end if;

      -- Write to registers
      if fastio_write='1' then
        if fastio_addr(19 downto 8) = x"DE0" then
          case fastio_addr(7 downto 0) is
            when x"00" =>
              -- wrote to register $DE000
              null;
            when others =>
              -- Other registers do nothing
              null;
          end case;
        end if;
      end if;

      -- Do synchronous actions
      
    end if;
  end process;

end behavioural;
