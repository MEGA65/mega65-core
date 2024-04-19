use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY ram36_variable IS
  generic ( size : integer );
  PORT (
    clkr : IN STD_LOGIC;
    clkw : IN STD_LOGIC;
    cs : IN STD_LOGIC;
    w : IN std_logic;
    write_address : IN integer range 0 to (size - 1);
    wdata : IN unsigned(35 DOWNTO 0);
    address : IN integer range 0 to (size - 1);
    rdata : OUT unsigned(35 DOWNTO 0)
    );
END ram36_variable;

architecture behavioural of ram36_variable is

  type ram_t is array (0 to (size-1)) of unsigned(35 downto 0);
  signal ram : ram_t := (
    others => (others => '0'));

begin  -- behavioural

  process(clkr,clkw,cs,address,ram)
  begin
    if cs='1' then
      rdata <= ram(address);
    else
      rdata <= (others => 'Z');
    end if;

    if(rising_edge(Clkw)) then
      if w='1' then
        ram(write_address) <= wdata;
        report "writing $" & to_hexstring(wdata) & " to sector buffer offset $"
          & to_hexstring(to_unsigned(write_address,20)) severity note;
      end if;
    end if;    
  end process;

end behavioural;
