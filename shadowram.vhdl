library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

--
entity shadowram is
  port (Clk : in std_logic;
        address : in integer range 0 to 131071;
        we : in std_logic;
        data_i : in unsigned(7 downto 0);
        data_o : out unsigned(7 downto 0);
        writes : out unsigned(7 downto 0);
        no_writes : out unsigned(7 downto 0)
        );
end shadowram;

architecture Behavioral of shadowram is

  signal write_count : unsigned(7 downto 0) := x"00";
  signal no_write_count : unsigned(7 downto 0) := x"00";
  
--  type ram_t is array (0 to 262143) of std_logic_vector(7 downto 0);
  type ram_t is array (0 to 131071) of unsigned(7 downto 0);
  signal ram : ram_t := (
    4096 => x"03",
    4097 => x"08",
    4098 => x"01",
    4099 => x"04",
    4100 => x"0f",
    4101 => x"17",
    4102 => x"18",
    8192 => x"a9",
    8193 => x"01",
    8194 => x"a9",
    8195 => x"02",
    8196 => x"a9",
    8197 => x"03",
    8198 => x"a9",
    8199 => x"04",
    others => x"53"); 
begin

--process for read and write operation.
  PROCESS(Clk,ram,address)
  BEGIN
    data_o <= ram(address);
    writes <= write_count;
    no_writes <= no_write_count;
    if(rising_edge(Clk)) then 
      if we /= '0' then
        write_count <= write_count + 1;        
        ram(address) <= data_i;
        report "wrote to shadow ram" severity note;
      else
        no_write_count <= no_write_count + 1;        
      end if;
    end if;
  END PROCESS;

end Behavioral;
