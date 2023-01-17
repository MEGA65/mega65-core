library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

--
entity kb_matrix_ram is
  port (ClkA : in std_logic;
        addressa : in integer range 0 to 15;
        dia : in std_logic_vector(7 downto 0);
        wea : in std_logic_vector(7 downto 0);
        addressb : in integer range 0 to 15;
        dob : out std_logic_vector(7 downto 0)
        );
end kb_matrix_ram;

architecture Behavioral of kb_matrix_ram is
  
  type ram_t is array (0 to 15) of std_logic_vector(7 downto 0);
  shared variable ram : ram_t := (others => x"FF");

begin

--process for read and write operation.
  PROCESS(ClkA)
  BEGIN
    if(rising_edge(ClkA)) then
      for i in 0 to 7 loop
        if wea(i) = '1' then
          ram(addressa)(i) := dia(i);
          report "Writing bit " & integer'image(i) & " of byte " & integer'image(addressa) & " with " & std_logic'image(dia(i));
        end if;
      end loop;
    end if;
  END PROCESS;
PROCESS(addressb)
BEGIN
  dob <= ram(addressb);
--  report "Reading byte " & integer'image(addressb) & " with value $" & to_hstring(ram(addressb));
END PROCESS;

end Behavioral;
