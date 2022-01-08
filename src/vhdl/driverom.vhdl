library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

--
entity driverom is
  port (ClkA : in std_logic;
        addressa : in integer; -- range 0 to 16383;
        wea : in std_logic;
        csa : in std_logic;
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
  shared variable ram : ram_t := (
    16383 => x"FE",
    16382 => x"FD",
    16381 => x"FC",
    16380 => x"FB",
    16379 => x"FA",
    16378 => x"F9",
    16377 => x"F8",
    16376 => x"F7",
    others => x"42"
    )
    ;
begin

  writes <= write_count;
  no_writes <= no_write_count;
--process for read and write operation.
  PROCESS(ClkA,csa,addressa)
  BEGIN
    if(rising_edge(ClkA)) then 
      if wea /= '0' and csa='1' then
        write_count <= write_count + 1;        
          ram(addressa) := dia;
      else
        no_write_count <= no_write_count + 1;        
      end if;
    end if;
    if csa='1' then
      doa <= ram(addressa);
    else
      doa <= (others => 'Z');
    end if;
  END PROCESS;
PROCESS(ClkB)
BEGIN
  if(rising_edge(ClkB)) then
      dob <= ram(addressb);
  end if;
END PROCESS;

end Behavioral;
