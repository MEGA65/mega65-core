
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
  type state_t is (idle, normalise, step, preoutput, output);
  signal state : state_t := idle;
  signal steps_remaining : integer range 0 to 5 := 0;

  signal dd : unsigned(35 downto 0) := to_unsigned(0,36);
  signal nn : unsigned(67 downto 0) := to_unsigned(0,68);
    
begin

  process (clock) is
    variable temp64 : unsigned(73 downto 0) := to_unsigned(0,74);
    variable temp96 : unsigned(105 downto 0) := to_unsigned(0,106);
    variable f : unsigned(37 downto 0) := to_unsigned(0,38);
  begin
    if rising_edge(clock) then
      report "state is " & state_t'image(state);
      -- only for vunit test
      -- report "q$" & to_hstring(q) & " = n$" & to_hstring(n) & " / d$" & to_hstring(d);
      case state is
        when idle =>
          -- Deal with divide by zero
          if dd = to_unsigned(0,36) then
            q <= (others => '1');
            busy <= '0';
          end if;
        when normalise =>
          if dd(35)='1' then
            report "Normalised to $" & to_hstring(nn(67 downto 36)) & "." & to_hstring(nn(35 downto 4)) & "." & to_hstring(nn(3 downto 0))
              & " / $" & to_hstring(dd(35 downto 4)) & "." & to_hstring(dd(3 downto 0));
            state <= step;
          else
              -- Normalise in not more than 5 cycles
            if dd(35 downto 20)= to_unsigned(0,16) then
              dd(35 downto 20) <= dd(19 downto 4);
              dd(19 downto 0) <= (others => '0');
              nn(67 downto 20) <= nn(51 downto 4);
              nn(19 downto 0) <= (others => '0');
            elsif dd(35 downto 28)= to_unsigned(0,8) then
              dd(35 downto 12) <= dd(27 downto 4);
              dd(11 downto 0) <= (others => '0');
              nn(67 downto 12) <= nn(59 downto 4);
              nn(11 downto 0) <= (others => '0');
            elsif dd(35 downto 32) = to_unsigned(0,4) then
              dd(35 downto 8) <= dd(31 downto 4);
              dd(7 downto 0) <= (others => '0');
              nn(67 downto 8) <= nn(63 downto 4);
              nn(7 downto 0) <= (others => '0');
            elsif dd(35 downto 34) = to_unsigned(0,2) then
              dd(35 downto 6) <= dd(33 downto 4);
              dd(5 downto 0) <= (others => '0');
              nn(67 downto 6) <= nn(65 downto 4);
              nn(5 downto 0) <= (others => '0');
            elsif dd(35)='0' then
              dd(35 downto 5) <= dd(34 downto 4);
              dd(4 downto 0) <= (others => '0');
              nn(67 downto 5) <= nn(66 downto 4);
              nn(4 downto 0) <= (others => '0');
            end if;
          end if;
        when step =>
          report "nn=$" & to_hstring(nn(67 downto 36)) & "." & to_hstring(nn(35 downto 4)) & "." & to_hstring(nn(3 downto 0))
            & " / $" & to_hstring(dd(35 downto 4)) & "." & to_hstring(dd(3 downto 0));

        -- f = 2 - dd
          f := to_unsigned(0,38);
          f(37) := '1';
          f := f - dd;
          report "f = $" & to_hstring(f);

          -- Now multiply both nn and dd by f
          temp96 := nn * f;
          nn <= temp96(103 downto 36);
          report "temp96=$" & to_hstring(temp96);

          temp64 := dd * f;
          dd <= temp64(71 downto 36);
          report "temp64=$" & to_hstring(temp64);

          -- Perform number of required steps, or abort early if we can
          if steps_remaining /= 0 and dd /= x"FFFFFFFFF" then
            steps_remaining <= steps_remaining - 1;
          else
            state <= preoutput;
          end if;
        when preoutput =>
          -- No idea why we need to add one, but we do to stop things like 4/2
          -- giving a result of 1.999999999
          temp64(67 downto 0) := nn;
          temp64(73 downto 68) := (others => '0');
          temp64 := temp64 + 1;
          report "temp64=$" & to_hstring(temp64);
          state <= output;
        when output =>
          busy <= '0';
          q <= temp64(67 downto 4);
          state <= idle;
      end case;

      if start_over='1' and d /= to_unsigned(0,32) then
        report "Calculating $" & to_hstring(n) & " / $" & to_hstring(d);
        dd(35 downto 4) <= d;
        dd(3 downto 0) <= (others => '0');
        nn(35 downto 4) <= n;
        nn(3 downto 0) <= (others => '0');
        nn(67 downto 36) <= (others => '0');
        state <= normalise;
        steps_remaining <= 5;
        busy <= '1';
      elsif start_over='1' then
        report "Ignoring divide by zero";
      end if;

    end if;
  end process;
end wattle_and_daub;
