use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity pinprober is
  port (Clk : in std_logic;
        pins : out std_logic_vector(1 to 82);
        pin_number : in integer 
        );

end pinprober;

architecture moorish of pinprober is
  signal counter : integer range 0 to 5000 := 0;
  signal toggle : std_logic := '0';

begin
  process (clk) is
  begin
    if rising_edge(clk) then
      if counter = 5000 then
        counter <= 0;
        toggle <= not toggle;
      else
        counter <= counter + 1;
      end if;
      if pin_number >= 1 and pin_number <= 82 then
        pins(pin_number) <= toggle;
      end if;
    end if;
  end process;
end moorish;

  
