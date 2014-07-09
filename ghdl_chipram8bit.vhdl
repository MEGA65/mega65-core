library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

ENTITY chipram8bit IS
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(16 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    clkb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(16 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
  );
END chipram8bit;

architecture behavioural of chipram8bit is

  type ram_t is array (0 to 131071) of std_logic_vector(7 downto 0);
  signal ram : ram_t := (
    4096 => x"03",
    4097 => x"08",
    4098 => x"09",
    4099 => x"10",
    4100 => x"12",
    4101 => x"01",
    4102 => x"0d",
    others => x"BD" );

begin
  PROCESS(Clka,addrb)
BEGIN
  --report "viciv reading charrom address $"
  --  & to_hstring(address)
  --  & " = " & integer'image(to_integer(address))
  --  & " -> $" & to_hstring(ram(to_integer(address)))
  --  severity note;
  doutb <= ram(to_integer(unsigned(addrb)));

  if(rising_edge(Clka)) then 
    if(wea(0)='1') then
      ram(to_integer(unsigned(addra))) <= dina;
    end if;
  end if;
END PROCESS;

end Behavioural;
