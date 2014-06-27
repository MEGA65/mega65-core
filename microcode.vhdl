--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 2 of the
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
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.cputypes.all;

--
entity microcode is
  port (Clk : in std_logic;
        address : in instruction;
        data_o : out std_logic_vector(63 downto 0)
        );
end microcode;

architecture Behavioral of microcode is
  
  type ram_t is array (instruction)
    of std_logic_vector(63 downto 0);
  signal ram : ram_t := (
    
    others => ( mcInstructionFetch => '1', others => '0'));

begin

--process for read and write operation.
  PROCESS(Clk,address)
  BEGIN
    if(rising_edge(Clk)) then 
      data_o <= ram(address);
    end if;
  END PROCESS;

end Behavioral;
