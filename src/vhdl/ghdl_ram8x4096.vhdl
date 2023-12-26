use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY ram8x4096 IS
  PORT (
    clkr : IN STD_LOGIC;
    clkw : IN STD_LOGIC;
    cs : IN STD_LOGIC;
    w : IN std_logic;
    write_address : IN integer range 0 to 4095;
    wdata : IN unsigned(7 DOWNTO 0);
    address : IN integer range 0 to 4095;
    rdata : OUT unsigned(7 DOWNTO 0)
    );
END ram8x4096;

architecture behavioural of ram8x4096 is

  type ram_t is array (0 to 4095) of unsigned(7 downto 0);
  signal ram : ram_t := (
    others => x"00");

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
        report "writing $" & to_hstring(wdata) & " to sector buffer offset $"
          & to_hstring(to_unsigned(write_address,12)) severity note;
      end if;
    end if;    
  end process;

end behavioural;
