

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity pal_simulation is
  port(
    clock : in std_logic;
    shadow_mask_enable : in std_logic;
    vertical_phase : in unsigned(7 downto 0) := "00000000";
    red_in : in unsigned(7 downto 0);
    green_in : in unsigned(7 downto 0);
    blue_in : in unsigned(7 downto 0);
    red_out : out unsigned(7 downto 0);
    green_out : out unsigned(7 downto 0);
    blue_out : out unsigned(7 downto 0);
    x_position : in unsigned(13 downto 0);
    y_position : in unsigned(11 downto 0)
    );
end pal_simulation;
      
architecture behavioural of pal_simulation is

begin
  process (clock)
    variable luma : integer;
    variable scaled : unsigned(15 downto 0);
  begin
    if rising_edge(clock) then

      -- every 2nd raster line is much darker to simulate scan-lines
      -- more subtle dimming of alternate pixel columns to simulate CRT mask
      -- (horizontal smoothing occurs in VIC-IV itself, with a 3 pixel running
      -- average independently selectable from this filter)
      if x_position(0) = '0' then
        if y_position(0) = '0' then
          luma := 255;
        else
          luma := 128;
        end if;
      else
        if shadow_mask_enable='0' then
          if y_position(0) = '0' then
            luma := 240;
          else
            luma := 112;
          end if;
        else
          if y_position(0) = '0' then
            luma := 224;
          else
            luma := 96;
          end if;
        end if;
      end if;
      
      scaled := to_unsigned(to_integer(red_in) * luma,16);
      red_out <= scaled(15 downto 8);
      scaled := to_unsigned(to_integer(green_in) * luma,16);
      green_out <= scaled(15 downto 8);
      scaled := to_unsigned(to_integer(blue_in) * luma,16);
      blue_out <= scaled(15 downto 8);
      
    end if;
  end process;
  
end behavioural;      
