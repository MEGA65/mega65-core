library ieee;
use ieee.std_logic_1164.all;

entity bufg is
  port (I : std_logic;
        O : out std_logic);
end bufg;

architecture behav of bufg is
begin
  O <= I;
end behav;
