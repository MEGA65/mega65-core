--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2018
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

--------------------------------------------------------------------------------

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity buffereduart is
  port (
    clock : in std_logic;
    clock50mhz : in std_logic;
    clock200 : in std_logic;
    reset : in std_logic;
    irq : out std_logic := 'Z';
    buffereduart_cs : in std_logic;

    ---------------------------------------------------------------------------
    -- IO lines to the UART
    ---------------------------------------------------------------------------
    uart_rx : in std_logic;
    uart_tx : out std_logic := '1';
    uart_ringindicate : in std_logic;
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0)
    );
end buffereduart;

architecture behavioural of buffereduart is

  signal buffer_write : std_logic := '0';
  signal buffer_writeaddress : integer := 0;
  signal buffer_readaddress : integer := 0;
  signal buffer_wdata : unsigned(7 downto 0) := x"00"; 
  signal buffer_rdata : unsigned(7 downto 0) := x"00"; 
  
begin  -- behavioural

  buffer0: entity work.ram8x4096 port map (
    clk => clock50mhz,
    cs => '1',
    w => buffer_write,
    write_address => buffer_writeaddress,
    wdata => buffer_wdata,
    address => buffer_readaddress,
    rdata => buffer_rdata);
  
  process (clock,fastio_addr,fastio_wdata,fastio_read,fastio_write
           ) is
    variable temp_cmd : unsigned(7 downto 0);

  begin

    -- Register reading is asynchronous to avoid wait states
    if fastio_read='1' then
      if buffereduart_cs='1' then
        report "MEMORY: Reading from buffered UART register block";
        case fastio_addr(3 downto 0) is
          -- Use this notation to create entries for auto-populating iomap.txt
          -- @IO:GS $D0E0 An example regisgter
          when x"0" =>
            fastio_rdata <= x"12";
          when others =>
            fastio_rdata <= (others => 'Z');
        end case;
      else
        fastio_rdata <= (others => 'Z');
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;

    if rising_edge(clock) then

      -- Update module status based on register reads
      if fastio_read='1' and buffereduart_cs='1' then
        case fastio_addr(3 downto 0) is
          when x"0" =>
            -- Cause a side effect when $D0E0 is read
            null;
          when others =>
            null;
        end case;
      end if;

      if fastio_write='1' and buffereduart_cs='1' then
        case fastio_addr(3 downto 0) is
          when x"0" =>
            -- Do action for $D0E0 being written to
            -- something <= fastio_wdata;
          when others =>
            null;
        end case;
      end if;

      -- Do synchronous actions
      
    end if;
  end process;

end behavioural;
