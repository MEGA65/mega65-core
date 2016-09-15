use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY ram9x4k IS
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addraa : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    clkb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
    );
END ram9x4k;

architecture behavioural of ram9x4k is

  type ram_t is array (0 to 4095) of std_logic_vector(8 downto 0);

  -- Put some values in to help debug bitplanes
  signal ram : ram_t;
begin  -- behavioural

  process(clka)
    variable theram : ram_t;
  begin
    if(rising_edge(Clka)) then 
      if wea(0)='1' then
        ram(to_integer(unsigned(addraa))) <= dina;
      end if;        

      doutb <= ram(to_integer(unsigned(addrb)));
    end if;
  end process;

end behavioural;
