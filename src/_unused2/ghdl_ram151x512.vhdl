use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY ram151x512 IS
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(150 DOWNTO 0);
    clkb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(150 DOWNTO 0)
    );
END ram151x512;

architecture behavioural of ram151x512 is

  type ram_t is array (0 to 511) of std_logic_vector(150 downto 0);

  signal ram : ram_t;
begin  -- behavioural

  process(clka)
    variable theram : ram_t;
  begin
    if(rising_edge(Clka)) then 
      if wea(0)='1' then
        ram(to_integer(unsigned(addra))) <= dina;
      end if;        

      doutb <= ram(to_integer(unsigned(addrb)));
    end if;
  end process;

end behavioural;
