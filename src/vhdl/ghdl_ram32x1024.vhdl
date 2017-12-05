use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

-- XXX This is only for rough simulation. Per-byte write-enables have no effect,
-- but VICIV expects them to.

ENTITY ram32x1024 IS
  PORT (
    clka : IN STD_LOGIC;
    ena : in std_logic;
    wea : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(31 DOWNTO 0) := (others => '1');
    clkb : IN STD_LOGIC;
    web : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    addrb : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    dinb : IN STD_LOGIC_VECTOR(31 DOWNTO 0); -- XXX ignored
    doutb : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END ram32x1024;

architecture behavioural of ram32x1024 is

  type ram_t is array (0 to 1023) of std_logic_vector(31 downto 0);

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
