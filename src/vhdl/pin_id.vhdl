library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity pin_id is
  port (clock : in std_logic;
        pin_number : in unsigned(7 downto 0);
        pin : out std_logic := '0');

end pin_id;

architecture homestead  of pin_id is

  signal counter : integer range 0 to 255 := 0;
  signal tick : integer range 0 to 255 := 0;
  
begin

  process(clock) is
  begin
    if rising_edge(clock) then
      if tick = 15 then
        tick <= tick + 1;
        -- Mark each bit with a pulse
        pin <= '1';
      elsif tick /= 16 then
        tick <= tick + 1;
      else
        tick <= 0;
        if counter < 8 then
          pin <= '1';
        elsif counter < 16 then
          pin <= '0';
        elsif counter > 15 and counter < 24 then
          pin <= std_logic(pin_number(counter - 16));
        else
          pin <= '0';
        end if;
        if counter /= 255 then
          counter <= counter + 1;
        else
          counter <= 0;
        end if;
      end if;
    end if;
    end process;
      
    end homestead;
