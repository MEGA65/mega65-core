
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;


entity fast_divide is
  port (
    clock : in std_logic;
    n : in unsigned(31 downto 0);
    d : in unsigned(31 downto 0);
    q : out unsigned(63 downto 0);
    start_over : in std_logic;
    busy : out std_logic := '0'
    );
end entity;

architecture wattle_and_daub of fast_divide is
  type state_t is (idle, step, output);
  signal state : state_t := idle;
  signal steps_remaining : integer range 0 to 5 := 0;

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

  process (clock) is
    variable temp64 : unsigned(73 downto 0) := to_unsigned(0,74);
    variable temp96 : unsigned(105 downto 0) := to_unsigned(0,106);
    variable temp138 : unsigned(137 downto 0) := to_unsigned(0,138);
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
      case state is
        when idle =>
          null;
        when step =>
          report "nn=$" & to_hstring(nn(67 downto 36)) & "." & to_hstring(nn(35 downto 4)) & "." & to_hstring(nn(3 downto 0))
            & " / dd=$" & to_hstring(dd(67 downto 36)) & "." & to_hstring(dd(35 downto 4)) & "." & to_hstring(dd(3 downto 0));

        -- f = 2 - dd
          f := to_unsigned(0,70);
          f(69) := '1';
          f := f - dd;
          report "f = $" & to_hstring(f);

          -- Now multiply both nn and dd by f
          temp138 := nn * f;
          -- Check whether to round up
          if temp138(67) = '1' then
             nn <= temp138(135 downto 68) + 1;
          else
             nn <= temp138(135 downto 68);
          end if;
          report "temp138=$" & to_hstring(temp138);

          temp138 := dd * f;
          -- Check whether to round up, but avoid overflow
          if temp138(67) = '1' and temp138(135 downto 68) /= X"FFFFFFFFFFFFFFFFF" then
             dd <= temp138(135 downto 68) + 1;
          else
             dd <= temp138(135 downto 68);
          end if;
          report "temp138=$" & to_hstring(temp138);

          -- Perform number of required steps, or abort early if we can
          if steps_remaining /= 0 and dd /= x"FFFFFFFFFFFFFFFFF" then
            steps_remaining <= steps_remaining - 1;
          else
            state <= output;
          end if;
        when output =>
          -- No idea why we need to add one, but we do to stop things like 4/2
          -- giving a result of 1.999999999
          temp64(67 downto 0) := nn;
          temp64(73 downto 68) := (others => '0');
          temp64 := temp64 + 8;
          report "temp64=$" & to_hstring(temp64);
          busy <= '0';
          q <= temp64(67 downto 4);
          state <= idle;
      end case;

      if start_over='1' and d /= to_unsigned(0,32) then
        report "Calculating $" & to_hstring(n) & " / $" & to_hstring(d);
        leading_zeros := count_leading_zeros(d);
        padded_d := d & X"00000000";
        new_dd := (others => '0');
        new_dd(35 downto 4) := padded_d(63-leading_zeros downto 32-leading_zeros);
        new_nn := (others => '0');
        new_nn(35+leading_zeros downto 4+leading_zeros) := n;
        report "Normalised to $" & to_hstring(new_nn(67 downto 36)) & "." &
          to_hstring(new_nn(35 downto 4)) & "." & to_hstring(new_nn(3 downto 0))
          & " / $" & to_hstring(new_dd(35 downto 4)) & "." & to_hstring(new_dd(3 downto 0));
        dd <= new_dd & X"00000000";
        nn <= new_nn;
        state <= step;
        steps_remaining <= 5;
        busy <= '1';
      elsif start_over='1' then
        report "Ignoring divide by zero";
      end if;

    end if;
  end process;
end wattle_and_daub;
