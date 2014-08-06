library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

--
entity THEROM is
  port (Clk : in std_logic;
        address : in integer range 0 to 131071;
        -- Yes, we do have a write enable, because we allow modification of ROMs
        -- in the running machine, unless purposely disabled.  This gives us
        -- something like the WOM that the Amiga had.
        we : in std_logic;
        -- chip select, active low       
        cs : in std_logic;
        data_i : in unsigned(15 downto 0);
        data_o : out unsigned(15 downto 0)
        );
end THEROM;

architecture Behavioral of THEROM is

-- 8K x 8bit pre-initialised RAM
  type ram_t is array (0 to 131071) of unsigned(15 downto 0);
  signal ram : ram_t := (ROMDATA);

begin

--process for read and write operation.
  PROCESS(Clk,cs,ram,address)
  BEGIN
    if cs='1' then
      data_o <= ram(address)(7 downto 0)&ram(address(15 downto 8);
    else
      data_o <= "ZZZZZZZZZZZZZZZZ";
    end if;
  END PROCESS;

end Behavioral;
