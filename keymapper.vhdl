library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity keymapper is
  
  port (
    clk : in std_logic;

    -- PS2 keyboard interface
    ps2clock  : in  std_logic;
    ps2data   : in  std_logic;
    -- CIA ports
    porta_in  : in  std_logic_vector(7 downto 0);
    porta_out : out std_logic_vector(7 downto 0);
    portb_in  : in  std_logic_vector(7 downto 0);
    portb_out : out std_logic_vector(7 downto 0);

    last_scan_code : out unsigned(7 downto 0)
    );

end keymapper;

architecture behavioural of keymapper is

begin  -- behavioural

  

end behavioural;
