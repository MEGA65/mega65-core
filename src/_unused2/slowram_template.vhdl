library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

--
entity THEROM is
  port (
        address : in integer range 0 to 65535;
        -- output enable, active high       
        oe : in std_logic;
        data_o : out unsigned(15 downto 0)
        );
end THEROM;

architecture Behavioral of THEROM is

  type ram_t is array (0 to 65535) of unsigned(15 downto 0);
  signal ram : ram_t := (ROMDATA);

begin

--process for read and write operation.
  PROCESS(oe,ram,address)
  BEGIN
    if oe='0' then
      data_o <= ram(address)(7 downto 0)&ram(address)(15 downto 8);
    else
      data_o <= "ZZZZZZZZZZZZZZZZ";
    end if;
  END PROCESS;

end Behavioral;
