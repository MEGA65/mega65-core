library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

--
entity driverom is
  port (ClkA : in std_logic;
        addressa : in integer; -- range 0 to 16383;
        wea : in std_logic;
        dia : in unsigned(7 downto 0);
        writes : out unsigned(7 downto 0);
        no_writes : out unsigned(7 downto 0);
        doa : out unsigned(7 downto 0);
        ClkB : in std_logic;
        addressb : in integer;
        dob : out unsigned(7 downto 0)
        );
end driverom;

architecture Behavioral of driverom is

  signal write_count : unsigned(7 downto 0) := x"00";
  signal no_write_count : unsigned(7 downto 0) := x"00";
  
  type ram_t is array (0 to 16383) of unsigned(7 downto 0);
  shared variable ram : ram_t;
begin

  writes <= write_count;
  no_writes <= no_write_count;
--process for read and write operation.
  PROCESS(ClkA)
  BEGIN
    if(rising_edge(ClkA)) then 
      if wea /= '0' then
        write_count <= write_count + 1;        
          ram(addressa) := dia;
      else
        no_write_count <= no_write_count + 1;        
      end if;
        doa <= ram(addressa);
    end if;
  END PROCESS;
PROCESS(ClkB)
BEGIN
  if(rising_edge(ClkB)) then
      dob <= ram(addressb);
  end if;
END PROCESS;

end Behavioral;
