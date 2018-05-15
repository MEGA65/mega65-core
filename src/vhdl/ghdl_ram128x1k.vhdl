use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY ram128x1k IS
  PORT (
    clk : IN STD_LOGIC;
    w : IN STD_LOGIC;
    addr : IN integer range 0 to 1023;
    din : IN unsigned(176 downto 0);
    dout : OUT unsigned(176 downto 0)
    );
END ram128x1k;

architecture behavioural of ram128x1k is

  type ram_t is array (0 to 1024) of unsigned(176 downto 0);
  signal ram : ram_t;

begin  -- behavioural

  process(clk)
  begin
    if(rising_edge(Clk)) then
      dout <= ram(addr);
      if w='1' then
        ram(addr) <= din;
      end if;
    end if;
  end process;

end behavioural;
