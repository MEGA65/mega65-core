
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
  type state_t is (idle, normalise, step, output);
  signal state : state_t := idle;
  signal steps_remaining : integer range 0 to 5 := 0;

  signal dd : unsigned(31 downto 0);
  signal nn : unsigned(63 downto 0);
    
begin

  process (clock) is
    variable temp64 : unsigned(65 downto 0);
    variable temp96 : unsigned(97 downto 0);
    variable f : unsigned(33 downto 0);
  begin
    if rising_edge(clock) then
      report "state is " & state_t'image(state);
      case state is
        when idle =>
          -- Deal with divide by zero
          if dd = to_unsigned(0,32) then
            q <= (others => '1');
            busy <= '0';
          end if;
        when normalise =>
          if dd(31)='1' then
            report "Normalised to $" & to_hstring(nn) & " / $" & to_hstring(dd);
            state <= step;
          else
            -- Normalise in not more than 5 cycles
            if dd(31 downto 16)= to_unsigned(0,16) then
              dd(31 downto 16) <= dd(15 downto 0);
              dd(15 downto 0) <= (others => '0');
              nn(63 downto 16) <= nn(47 downto 0);
              nn(15 downto 0) <= (others => '0');
            elsif dd(31 downto 24)= to_unsigned(0,8) then
              dd(31 downto 8) <= dd(23 downto 0);
              dd(7 downto 0) <= (others => '0');
              nn(63 downto 8) <= nn(55 downto 0);
              nn(7 downto 0) <= (others => '0');
            elsif dd(31 downto 28) = to_unsigned(0,4) then
              dd(31 downto 4) <= dd(27 downto 0);
              dd(3 downto 0) <= (others => '0');
              nn(63 downto 4) <= nn(59 downto 0);
              nn(3 downto 0) <= (others => '0');
            elsif dd(31 downto 30) = to_unsigned(0,2) then
              dd(31 downto 2) <= dd(29 downto 0);
              dd(1 downto 0) <= (others => '0');
              nn(63 downto 2) <= nn(61 downto 0);
              nn(1 downto 0) <= (others => '0');
            elsif dd(31)='0' then
              dd(31 downto 1) <= dd(30 downto 0);
              dd(0) <= '0';
              nn(63 downto 1) <= nn(62 downto 0);
              nn(0) <= '0';
            end if;
          end if;
        when step =>
          report "nn=$" & to_hstring(nn(63 downto 32)) & "." & to_hstring(nn(31 downto 0))
            & ", dd=$" & to_hstring(dd);

          -- f = 2 - dd
          f := to_unsigned(0,34);
          f(33) := '1';
          f := f - dd;
          report "f = $" & to_hstring(f);

          -- Now multiply both nn and dd by f
          temp96 := nn * f;
          nn <= temp96(95 downto 32);
          temp64 := dd * f;
          dd <= temp64(63 downto 32);      

          -- Perform number of required steps, or abort early if we can
          if steps_remaining /= 0 and dd /= x"FFFFFFFF" then
            steps_remaining <= steps_remaining - 1;
          else
            state <= output;
          end if;
        when output =>
          busy <= '0';
          -- No idea why we need to add one, but we do to stop things like 4/2
          -- giving a result of 1.999999999
          q <= nn(63 downto 0) + 1;
          state <= idle;
      end case;

      if start_over='1' and d /= to_unsigned(0,32) then
        report "Calculating $" & to_hstring(n) & " / $" & to_hstring(d);
        dd(31 downto 0) <= d;
        nn(31 downto 0) <= n;
        nn(63 downto 32) <= (others => '0');
        state <= normalise;
        steps_remaining <= 5;
        busy <= '1';
      end if;

      
    end if;
  end process;
end wattle_and_daub;



