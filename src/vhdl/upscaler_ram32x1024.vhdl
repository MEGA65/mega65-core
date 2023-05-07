use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

-- XXX This is only for rough simulation. Per-byte write-enables have no effect,
-- but VICIV expects them to.

ENTITY upscaler_ram32x1024 IS
  PORT (
    clka : IN STD_LOGIC;
    ena : in std_logic;
    wea : IN STD_LOGIC;
    addra : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    clkb : IN STD_LOGIC;
    enb : in std_logic;
    addrb : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END upscaler_ram32x1024;

architecture behavioural of upscaler_ram32x1024 is

  type ram_t is array (0 to 1023) of std_logic_vector(31 downto 0);

  signal ram : ram_t := ( others => (others => '0'));

begin  -- behavioural

  process(clka,clkb)
  begin
    if(rising_edge(Clka)) then
      if ena='1' then
        if wea='1' then
          ram(to_integer(unsigned(addra))) <= dina;
        end if;
      end if;
    end if;
    if (rising_edge(clkb)) then
      if enb='1' then
        report "reading from address $" & to_hstring(addrb) & " : data=$" & to_hstring(ram(to_integer(unsigned(addrb))));
        doutb <= ram(to_integer(unsigned(addrb)));
      end if;
    end if;
  end process;

end behavioural;
