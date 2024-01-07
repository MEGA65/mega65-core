use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity sim74LS125 is
  port (
    a : in std_logic_vector(3 downto 0);
    y : out std_logic_vector(3 downto 0);
    oe : in std_logic_vector(3 downto 0)
    );
end sim74LS125;

architecture simulated of sim74LS125 is

begin

  process (a,oe) is
    for i in 0 to 3 loop
      if oe(i)='1' then
        y(i) <= a(i);
      else
        y(i) <= 'Z';
      end if;
    end loop;
  end process;
end simulated;
    
