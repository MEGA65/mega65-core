use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY ram8x32k IS
  PORT (
    clka : IN STD_LOGIC;
    ena : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(14 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    clkb : IN STD_LOGIC;
    web : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addrb : IN STD_LOGIC_VECTOR(14 DOWNTO 0);
    dinb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
END ram8x32k;

architecture behavioural of ram8x32k is

  type ram_t is array (0 to 32767) of std_logic_vector(7 downto 0);
  signal ram : ram_t := (
    0 => x"02", 1 => x"03", 2 => x"04", 3 => x"06", 4 => x"06", 5 => x"06", 6 => x"06", 7 => x"06", 8 => x"06", 39 => x"06",
    others => x"07");

  signal douta_drive : std_logic_vector(7 downto 0);
  signal doutb_drive : std_logic_vector(7 downto 0);
  
begin  -- behavioural

  process(clka)
  begin
    douta_drive <= ram(to_integer(unsigned(addra(14 downto 0))));
    douta <= douta_drive;

    --report "COLOURRAM: A Reading from $" & to_hstring(unsigned(addra))
    --  & " = $" & to_hstring(ram(to_integer(unsigned(addra))));
    if(rising_edge(Clka)) then 
      if ena='1' then
        if(wea="1") then
          ram(to_integer(unsigned(addra(14 downto 0)))) <= dina;
          report "COLOURRAM: A writing to $" & to_hstring(unsigned(addra))
            & " = $" & to_hstring(dina);
        end if;
      end if;
    end if;
  end process;

  process (clkb,addrb,ram)
  begin
    doutb_drive <= ram(to_integer(unsigned(addrb(14 downto 0))));
    doutb <= doutb_drive;
    if(rising_edge(Clkb)) then 
      if(web="1") then
--        ram(to_integer(unsigned(addrb))) <= dinb;
      end if;
    end if;
  end process;

end behavioural;
