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
  
entity shifter32 is
  port (
    clock : in std_logic;
    unit : in integer range 0 to 15;
    do_add : in std_logic;
    input_a : in integer range 0 to 15;
    input_b : in integer range 0 to 15;
    input_value_number : in integer range 0 to 15;
    input_value : unsigned(31 downto 0);
    output_select : in integer range 0 to 15;
    output_value : out unsigned(63 downto 0)
    );
end entity;

architecture neo_gregorian of shifter32 is

  signal a : unsigned(31 downto 0) := to_unsigned(0,32);
  signal b : unsigned(31 downto 0) := to_unsigned(0,32);
  signal p : unsigned(63 downto 0) := to_unsigned(0,64);
  signal s : unsigned(32 downto 0) := to_unsigned(0,33);
  
begin

  process(clock) is
    variable shift : integer;
  begin
    if rising_edge(clock) then
      -- Latch input values as required
      if input_value_number = input_a then
        a <= input_value;
      end if;
      if input_value_number = input_b then
        b <= input_value;
      end if;

      -- Calculate the result
      -- Even units do addition, odd ones do subtraction
      if (unit mod 2) = 0 then
        s <= to_unsigned(to_integer(a)+to_integer(b),33);
      else
        s <= to_unsigned(to_integer(a)-to_integer(b),33);
      end if;

      if b(7 downto 0) = x"00" then
        p(63 downto 32) <= (others => '0');
        p(31 downto 0) <= a;
      else     
        if b(7)='0' then
          -- Shift right        
          shift := to_integer(b(6 downto 0));
          p(63 downto 32) <= (others => '0');
          p(31 downto 0) <= shift_right(a,shift);
        else
          -- Shift left
          shift := 127 - to_integer(b(6 downto 0));
          p <= shift_left(x"00000000"&a,shift);
        end if;
      end if;

      -- Display output value when requested, and tri-state outputs otherwise
      if output_select = unit then
        if do_add='1' then
          -- Output sign-extended 33 bit addition result
          output_value(63 downto 33) <= (others => s(32));
          output_value(32 downto 0) <= s;
        else
          output_value <= p;
        end if;
      else
        output_value <= (others => 'Z');
      end if;
    end if;
  end process;
end neo_gregorian;
