use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY ram18x2k IS
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addrl : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(17 DOWNTO 0);
    clkb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(17 DOWNTO 0)
    );
END ram18x2k;

architecture behavioural of ram18x2k is

  type ram_t is array (0 to 2047) of std_logic_vector(17 downto 0);

  signal ram : ram_t;
begin  -- behavioural

  process(clka)
    variable theram : ram_t;
  begin
    if(rising_edge(Clka)) then 
      if wea(0)='1' then
        ram(to_integer(unsigned(addrl))) <= dina;
      end if;        

      doutb <= ram(to_integer(unsigned(addrb)));
    end if;
  end process;

end behavioural;
