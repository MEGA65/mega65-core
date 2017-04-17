use work.all;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity pal_simulation is
  port(
    clock : in std_logic;
    red_in : in unsigned(7 downto 0);
    green_in : in unsigned(7 downto 0);
    blue_in : in unsigned(7 downto 0);
    red_out : out unsigned(7 downto 0);
    green_out : out unsigned(7 downto 0);
    blue_out : out unsigned(7 downto 0);
    x_position : in unsigned(11 downto 0);
    y_position : in unsigned(11 downto 0)
    );
end pal_simulation;
      
architecture behavioural of pal_simulation is

  signal x_mod5 : integer := 0;
  signal y_mod5 : integer := 0;

begin
  process (clock)
    variable luma : integer;
    variable scaled : unsigned(15 downto 0);
  begin
    if rising_edge(clock) then

      if x_position = "000000000000" then
        x_mod5 <= 0;

        if y_position = "000000000000" then
        y_mod5 <= 0;
      else
        if y_mod5 = 4 then
          y_mod5 <= 0;
        else
          y_mod5 <= y_mod5 + 1;
        end if;
      end if;
      
      else
        if x_mod5 = 4 then
          x_mod5 <= 0;
        else
          x_mod5 <= x_mod5 + 1;
        end if;
      end if;
      
      -- 200 line mode is 5 physical pixels high
      case  y_mod5 is
        when 0 => luma := 256;
        when 1 => luma := 240;
        when 2 => luma := 220;
        when 3 => luma := 240;
        when 4 => luma := 256;
        when others => luma := 256;
      end case;

      scaled := to_unsigned(to_integer(red_in) * luma,16);
      red_out <= scaled(15 downto 8);
      scaled := to_unsigned(to_integer(green_in) * luma,16);
      green_out <= scaled(15 downto 8);
      scaled := to_unsigned(to_integer(blue_in) * luma,16);
      blue_out <= scaled(15 downto 8);
      
    end if;
  end process;
  
end behavioural;      
