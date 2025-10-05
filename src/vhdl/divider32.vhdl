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
  
entity divider32 is
  generic (
    unit : integer range 0 to 15
    );
  port (
    clock : in std_logic;
    do_add : in std_logic;
    invert_b : in std_logic;
    do_mult : in std_logic;
    input_a : in integer range 0 to 15;
    input_b : in integer range 0 to 15;
    input_value_number : in integer range 0 to 15;
    input_value : unsigned(31 downto 0);
    -- output_select : in integer range 0 to 15;
    mult_shift : in unsigned(2 downto 0);
    output_value : out unsigned(63 downto 0) := (others => '0')
    );
end entity;

architecture neo_gregorian of divider32 is

  signal a : unsigned(31 downto 0) := to_unsigned(0,32);
  signal b : unsigned(31 downto 0) := to_unsigned(0,32);
  signal p : unsigned(63 downto 0) := to_unsigned(0,64);
  signal q : unsigned(63 downto 0) := to_unsigned(0,64);
  signal s : unsigned(32 downto 0) := to_unsigned(0,33);

  signal busy : std_logic := '0';
  signal start_over : std_logic := '0';

  type state_t is (idle, start_1, start_2, start_3, step_1, step_2, output);
  signal state : state_t := idle;
  signal steps_remaining : integer range 0 to 5 := 0;

  signal mult_a : unsigned(67 downto 0) := (others => '0');
  signal mult_b : unsigned(69 downto 0) := (others => '0');
  signal mult_signed : std_logic := '0';
  signal mult_out : unsigned(137 downto 0) := (others => '0');

  signal dd : unsigned(67 downto 0) := to_unsigned(0,68);
  signal nn : unsigned(67 downto 0) := to_unsigned(0,68);

  pure function count_leading_zeros(arg : unsigned(31 downto 0)) return natural is
  begin
    for i in 0 to 31 loop
      if arg(31-i) = '1' then
        return i;
      end if;
    end loop;
    return 0;
  end function count_leading_zeros;
begin

  -- instance "fast_divide_1"
  -- fast_divide_1: entity work.fast_divide
  --   port map (
  --     clock      => clock,
  --     n          => a,
  --     d          => b,
  --     q          => q,
  --     start_over => start_over,
  --     busy       => busy);

  process (clock) is
    variable temp64 : unsigned(73 downto 0) := to_unsigned(0,74);
    variable temp96 : unsigned(105 downto 0) := to_unsigned(0,106);
    -- variable temp138 : unsigned(137 downto 0) := to_unsigned(0,138);
    variable f : unsigned(69 downto 0) := to_unsigned(0,70);
    variable leading_zeros : natural range 0 to 31;
    variable new_dd : unsigned( 35 downto 0);
    variable new_nn : unsigned( 67 downto 0);
    variable padded_d : unsigned(63 downto 0);
  begin
    if rising_edge(clock) then
      report "state is " & state_t'image(state);
      -- only for vunit test
      -- report "q$" & to_hstring(q) & " = n$" & to_hstring(n) & " / d$" & to_hstring(d);
      if mult_signed = '0' then
        mult_out <= mult_a * mult_b;
      else
        mult_out <= unsigned(signed(mult_a) * signed(mult_b));
      end if;
      if start_over = '0' then
        case state is
          when idle =>
            null;
            -- special startup case to allow for multiplier outputs to settle
          when start_1 =>
            -- f = 2 - dd
            f := to_unsigned(0,70);
            f(69) := '1';
            f := f - dd;
            -- Now multiply both nn and dd by f
            -- temp138 := nn * f;
            report "mult_a=$" & to_hstring(mult_a) & ", mult_b=$" & to_hstring(mult_b) & ", mult_out=$" & to_hstring(mult_out);
            mult_a <= nn;
            mult_b <= f;
            mult_signed <= '0';
            state <= start_2;
          when start_2 =>
            report "mult_a=$" & to_hstring(mult_a) & ", mult_b=$" & to_hstring(mult_b) & ", mult_out=$" & to_hstring(mult_out);
            mult_a <= dd; 
            mult_b <= f;
            -- multiplier gets set to a * b when start_over is asserted, so store the product.
            p <= mult_out(137 downto 74);
            state <= start_3;
          when start_3 =>
            report "mult_a=$" & to_hstring(mult_a) & ", mult_b=$" & to_hstring(mult_b) & ", mult_out=$" & to_hstring(mult_out);
            mult_a <= nn;
            mult_b <= f;
            state <= step_2;
          when step_1 =>
            report "nn=$" & to_hstring(nn(67 downto 36)) & "." & to_hstring(nn(35 downto 4)) & "." & to_hstring(nn(3 downto 0))
              & " / dd=$" & to_hstring(dd(67 downto 36)) & "." & to_hstring(dd(35 downto 4)) & "." & to_hstring(dd(3 downto 0));
            report "mult_a=$" & to_hstring(mult_a) & ", mult_b=$" & to_hstring(mult_b) & ", mult_out=$" & to_hstring(mult_out);
            -- f = 2 - dd
            -- f := to_unsigned(0,70);
            -- f(69) := '1';
            -- f := f - dd;
            report "f = $" & to_hstring(f);

            -- Check whether to round up
            if mult_out(67) = '1' then
              nn <= mult_out(135 downto 68) + 1;
              mult_a <= mult_out(135 downto 68) + 1;
            else
              nn <= mult_out(135 downto 68);
              mult_a <= mult_out(135 downto 68);
            end if;
            -- Now multiply both nn and dd by f
            -- temp138 := nn * f;
            mult_b <= f;
            state <= step_2;
            -- report "temp138=$" & to_hstring(temp138);
          when step_2 =>
            report "nn=$" & to_hstring(nn(67 downto 36)) & "." & to_hstring(nn(35 downto 4)) & "." & to_hstring(nn(3 downto 0))
              & " / dd=$" & to_hstring(dd(67 downto 36)) & "." & to_hstring(dd(35 downto 4)) & "." & to_hstring(dd(3 downto 0));
            report "mult_a=$" & to_hstring(mult_a) & ", mult_b=$" & to_hstring(mult_b) & ", mult_out=$" & to_hstring(mult_out);
            -- temp138 := dd * f;
            -- Check whether to round up, but avoid overflow
            f := to_unsigned(0,70);
            f(69) := '1';
            -- f := f - dd;
            if mult_out(67) = '1' and mult_out(135 downto 68) /= X"FFFFFFFFFFFFFFFFF" then
              dd <= mult_out(135 downto 68) + 1;
              mult_a <= mult_out(135 downto 68) + 1;
              f := f - (mult_out(135 downto 68) + 1);
            else
              dd <= mult_out(135 downto 68);
              mult_a <= mult_out(135 downto 68);
              f := f - mult_out(135 downto 68);
            end if;
            -- report "temp138=$" & to_hstring(temp138);          
            mult_b <= f;
            -- Perform number of required steps, or abort early if we can
            if steps_remaining /= 0 and dd /= x"FFFFFFFFFFFFFFFFF" then
              steps_remaining <= steps_remaining - 1;
              state <= step_1;
            else
              state <= output;
            end if;
          when output =>
            report "mult_a=$" & to_hstring(mult_a) & ", mult_b=$" & to_hstring(mult_b) & ", mult_out=$" & to_hstring(mult_out);
            -- No idea why we need to add one, but we do to stop things like 4/2
            -- giving a result of 1.999999999
            if mult_out(67) = '1' then
              temp64(67 downto 0) := mult_out(135 downto 68) + 1;
            else
              temp64(67 downto 0) := mult_out(135 downto 68);
            end if;
            -- temp64(67 downto 0) := nn;
            temp64(73 downto 68) := (others => '0');
            temp64 := temp64 + 8;
            report "temp64=$" & to_hstring(temp64);
            busy <= '0';
            q <= temp64(67 downto 4);
            state <= idle;
        end case;
      end if;

      if start_over='1' and b /= to_unsigned(0,32) then
        report "Calculating $" & to_hstring(a) & " / $" & to_hstring(b);
        leading_zeros := count_leading_zeros(b);
        padded_d := b & X"00000000";
        new_dd := (others => '0');
        new_dd(35 downto 4) := padded_d(63-leading_zeros downto 32-leading_zeros);
        new_nn := (others => '0');
        new_nn(35+leading_zeros downto 4+leading_zeros) := a;
        report "Normalised to $" & to_hstring(new_nn(67 downto 36)) & "." &
          to_hstring(new_nn(35 downto 4)) & "." & to_hstring(new_nn(3 downto 0))
          & " / $" & to_hstring(new_dd(35 downto 4)) & "." & to_hstring(new_dd(3 downto 0));
        dd <= new_dd & X"00000000";
        nn <= new_nn;
        state <= start_1;
        steps_remaining <= 5;
        busy <= '1';
        -- calculate multiplication
        mult_a(35 downto 0) <= (others => '0');
        mult_a(67 downto 36) <= a;
        mult_b(37 downto 0) <= (others => '0');
        mult_b(69 downto 38) <= b;
        mult_signed <= '1';
      elsif start_over='1' then
        -- define divide by zero as zero
        report "Ignoring divide by zero";
        state <= idle;
        busy <= '0';
        q <= (others => '0');
        -- zero product of a * b, since we know b = 0
        p <= (others => '0');
      end if;
    end if;
  end process;
  
  process(clock) is
  begin
    if rising_edge(clock) then
      -- Latch input values as required
      if false then
        report "MATH: Unit #" & integer'image(unit)
          & ": I see input_value_number = " & integer'image(input_value_number)
          & ", while I am waiting for " &
          integer'image(input_a) & " or " & integer'image(input_b);
      end if;
      if input_value_number = input_a then
--        report "MATH: Unit #" & integer'image(unit)
--          & ": Setting a=$" & to_hstring(input_value);
        a <= input_value;
        if a /= input_value or busy = '0' then
          start_over <= '1';
        end if;
      end if;
      if input_value_number = input_b then
--        report "MATH: Unit #" & integer'image(unit)
 --         & ": Setting b=$" & to_hstring(input_value);
        if invert_b = '1' then
          b <= unsigned(-signed(input_value));
          if b /= unsigned(-signed(input_value)) or busy = '0' then
            start_over <= '1';
          end if;
        else
          b <= input_value;
          if b /= input_value or busy = '0' then
            start_over <= '1';
          end if;
        end if;
      end if;

      if start_over = '1' then
        start_over <= '0';
      end if;

      -- Even units do addition, odd ones do subtraction
      -- if (unit mod 2) = 0 then
        s <= unsigned((a(31) & a) + (b(31) & b));
      -- else
      --   s <= unsigned((a(31) & a)-(b(31) & b));
      -- end if;

      -- Display output value when requested, and tri-state outputs otherwise
      -- if output_select = unit then
        if do_add='1' then
          -- Output sign-extended 33 bit addition result
          output_value(63 downto 33) <= (others => s(32));
          output_value(32 downto 0) <= s;
          report "MATH: Unit #" & integer'image(unit)
            & " outputting addition sum $" & to_hstring(s);
        elsif do_mult = '1' then
          output_value <= shift_right(p, to_integer(mult_shift & "000"));
          report "MATH: Unit #" & integer'image(unit)
            & " outputting multiplication product $" & to_hstring(p);
        else
          output_value <= q;
          report "MATH: Unit #" & integer'image(unit)
            & " outputting division quotient $" & to_hstring(q);
        end if;
      -- else
      --   output_value <= (others => 'Z');
      -- end if;
    end if;
  end process;
end neo_gregorian;
