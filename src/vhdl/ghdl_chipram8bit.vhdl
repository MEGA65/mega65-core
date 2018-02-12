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
  shared variable RAM : ram_t := (
    -- Some data for testing full-colour mode
    -- Screen starts @ $1000, so put a couple of glyph numbers that point
    -- somewhere convenient there. Each full-colour glyph is 64 bytes long,
    -- so char code $80 will be at $80 * 64 = $2000 = 8192
    4096 => x"80",
    4097 => x"81",
    4098 => x"02",
    4099 => x"03",
    4100 => x"04",
    4101 => x"05",
    4102 => x"06",
    4103 => x"07",
    4104 => x"08",

    -- Colour values for first row of char $80
    8192 => x"01",
    8193 => x"02",
    8194 => x"03",
    8195 => x"04",
    8196 => x"05",
    8197 => x"06",
    8198 => x"07",
    8199 => x"08",

    -- Colour values for first row of char $80
    8256 => x"0a",
    8257 => x"03",
    8258 => x"0a",
    8259 => x"03",
    8260 => x"0a",
    8261 => x"03",
    8262 => x"0a",
    8263 => x"03",

    others => x"BD" );

begin

PROCESS(Clka)
BEGIN
  --report "viciv reading charrom address $"
  --  & to_hstring(address)
  --  & " = " & integer'image(to_integer(address))
  --  & " -> $" & to_hstring(ram(to_integer(address)))
  --  severity note;

  if(rising_edge(Clka)) then 
    if(wea(0)='1') then
      ram(to_integer(unsigned(addra))) := dina;
    end if;
  end if;

END PROCESS;

PROCESS(Clkb)
BEGIN
  if(rising_edge(Clkb)) then
    doutb <= ram(to_integer(unsigned(addrb)));
end if;

END PROCESS;

end Behavioural;
