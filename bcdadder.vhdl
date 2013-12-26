library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;

entity bcdadder is
  
  port (
    cin  : in  std_logic;
    i1   : in  unsigned(3 downto 0);
    i2   : in  unsigned(3 downto 0);
    o   : out  unsigned(3 downto 0);
    cout : out std_logic);

end bcdadder;

architecture rtl of bcdadder is

begin  -- rtl
  
  process(cin, i1,i2)
      variable c : std_logic_vector(0 downto 0);
    begin
      c(0) := cin;
      if (i1+i2+unsigned(c))<9 then
        o <= i1+i2+unsigned(c);
        cout <= '0';
      else
        o <= i1+i2+unsigned(c)+5;
        cout <= '1';
      end if;
    end process;

end rtl;
