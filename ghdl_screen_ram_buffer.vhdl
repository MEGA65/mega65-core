library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

ENTITY screen_ram_buffer IS
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    clkb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
  );
END screen_ram_buffer;

architecture behavioural of screen_ram_buffer is

  type ram_t is array (0 to 511) of std_logic_vector(7 downto 0);
  signal ram : ram_t := (
    0 => x"00",
    39 => x"39",
    40 => x"30",
    41 => x"31",
    42 => x"32",
    43 => x"33",
    44 => x"34",
    45 => x"35",
    46 => x"36",
    47 => x"37",
    48 => x"38",
    511 => x"1A",
    others => x"10" );

begin
  PROCESS(Clka,addrb,ram)
BEGIN
  doutb <= ram(to_integer(unsigned(addrb)));

  if(rising_edge(Clka)) then 
    if(wea(0)='1') then
      ram(to_integer(unsigned(addra))) <= dina;
      report "Wrote $" & to_hstring(dina)
        & " to " & integer'image(to_integer(unsigned(addra)))
        severity note;
    end if;
  end if;
END PROCESS;

end Behavioural;
