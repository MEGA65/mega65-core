library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

ENTITY videobuffer IS
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    clkb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
  );
END videobuffer;

architecture behavioural of videobuffer is

  type ram_t is array (0 to 4095) of std_logic_vector(7 downto 0);
  signal ram : ram_t := (
    others => x"42" );

begin
  PROCESS(Clka,clkb,addrb,ram)
BEGIN
  report "VIDEOBUFFER: Reading address $"
    & to_hexstring(unsigned(addrb))
    & " = " & integer'image(to_integer(unsigned(addrb)))
    & " -> $" & to_hexstring(ram(to_integer(unsigned(addrb))))
    severity note;
  if rising_edge(clkb) then
    doutb <= ram(to_integer(unsigned(addrb)));    
  end if;

  if(rising_edge(Clka)) then 
    if(wea(0)='1') then
      ram(to_integer(unsigned(addra))) <= dina;
    end if;
  end if;
END PROCESS;

end Behavioural;
