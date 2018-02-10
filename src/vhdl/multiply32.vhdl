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
  
entity multiply32 is
  port (
    clock : in std_logic;
    a : in unsigned(31 downto 0);
    b : in unsigned(31 downto 0);
    p : out unsigned(63 downto 0)
    );
end entity;

architecture neo_gregorian of multiply32 is

  signal p1 : unsigned(63 downto 0);
  signal p2 : unsigned(63 downto 0);
  signal p3 : unsigned(63 downto 0);
  signal p4 : unsigned(63 downto 0);

begin

  process(clock) is
  begin
    if rising_edge(clock) then
      p1 <= to_unsigned(to_integer(a)*to_integer(b),64);
      p2 <= p1;
      p3 <= p2;
      p4 <= p1;
      p <= p4;
    end if;
  end process;
end neo_gregorian;
