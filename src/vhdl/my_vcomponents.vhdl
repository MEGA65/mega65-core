library ieee;
use ieee.std_logic_1164.all;

package vcomponents is
  component bufg is
    port (I : std_logic;
          O : out std_logic);
  end component;
end;
