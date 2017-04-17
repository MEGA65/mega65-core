

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
    x_position : in unsigned(11 downto 0);
    y_position : in unsigned(11 downto 0)
    );
end pal_simulation;
      
architecture behavioural of pal_simulation is

  signal x_mod5 : integer := 0;
  signal y_mod40 : integer := 0;

begin
  process (clock)
    variable luma : integer;
    variable scaled : unsigned(15 downto 0);
  begin
    if rising_edge(clock) then

      if x_position = "000000000000" then
        x_mod5 <= 0;

        if y_position = "000000000000" then
        y_mod40 <= to_integer(vertical_phase);
      else
        if y_mod40 = 39 then
          y_mod40 <= 0;
        else
          y_mod40 <= y_mod40 + 1;
        end if;
      end if;
      
      else
        if x_mod5 = 4 then
          x_mod5 <= 0;
        else
          x_mod5 <= x_mod5 + 1;
        end if;
      end if;

      -- VICE with 3 physical pixels per pixel uses the following over the full
      -- height of a character:
      -- pixel 0: 186 / $BA
      -- pixel 0: 249 / $F9
      -- pixel 0: 199 / $C7
      -- pixel 1: 203
      -- pixel 1: 246
      -- pixel 1: 184
      -- pixel 2: 217
      -- pixel 2: 231
      -- pixel 2: 170
      -- pixel 3: 232
      -- pixel 3: 216
      -- pixel 3: 170
      -- pixel 4: 185
      -- pixel 4: 247
      -- pixel 4: 202
      -- pixel 5: 200
      -- pixel 5: 249
      -- pixel 5: 187
      -- pixel 6: 214
      -- pixel 6: 234
      -- pixel 6: 172
      -- pixel 7: 229
      -- pixel 7: 219
      -- pixel 7: 172
      -- We need to then translate these to 5 physical pixels per logical pixel
      -- Let's start by thinking about the centre pixel brightnesses:
      -- 249, 246, 231, *232, 247, 249, 234, *229
      -- Pixels 3 and 7 are brightest at the top, not bottom
            
      case  y_mod40 is
        -- Pixel 0
        when 0 => luma := 186;
        when 1 => luma := 220;
        when 2 => luma := 249;
        when 3 => luma := 225;
        when 4 => luma := 199;
        -- Pixel 1
        when 5 => luma := 203;
        when 6 => luma := 225;
        when 7 => luma := 246;
        when 8 => luma := 215;
        when 9 => luma := 184;
        -- Pixel 2
        when 10 => luma := 217;
        when 11 => luma := 207;
        when 12 => luma := 231;
        when 13 => luma := 200;
        when 14 => luma := 170;
        -- Pixel 3
        when 15 => luma := 232;
        when 16 => luma := 224;
        when 17 => luma := 216;
        when 18 => luma := 195;
        when 19 => luma := 170;
        -- Pixel 4
        when 20 => luma := 185;
        when 21 => luma := 216;
        when 22 => luma := 247;
        when 23 => luma := 224;
        when 24 => luma := 202;
        -- Pixel 5
        when 25 => luma := 200;
        when 26 => luma := 225;
        when 27 => luma := 249;
        when 28 => luma := 218;
        when 29 => luma := 187;
        -- Pixel 6
        when 30 => luma := 214;
        when 31 => luma := 224;
        when 32 => luma := 234;
        when 33 => luma := 202;
        when 34 => luma := 172;
        -- Pixel 7
        when 35 => luma := 229;
        when 36 => luma := 224;
        when 37 => luma := 219;
        when 38 => luma := 196;
        when 39 => luma := 172;
        -- else...
        when others => luma := 256;
      end case;

      -- Put a narrow dim region between each horizontal H320 pixel to simulate
      -- CRT phosphor resolution
      if shadow_mask_enable='1' then
        case x_mod5 is
          when 3 => luma := luma - 15;
          when 4 => luma := luma - 30;
          when 0 => luma := luma - 15;
          when others => null;    
        end case;       
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
