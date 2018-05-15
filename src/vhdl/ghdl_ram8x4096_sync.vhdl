use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY ram8x4096_sync IS
  PORT (
    clk : IN STD_LOGIC;
    cs : IN STD_LOGIC;
    w : IN std_logic;
    write_address : IN integer;
    wdata : IN unsigned(7 DOWNTO 0);
    address : IN integer;
    rdata : OUT unsigned(7 DOWNTO 0)
    );
END ram8x4096_sync;

architecture behavioural of ram8x4096_sync is

  type ram_t is array (0 to 4095) of unsigned(7 downto 0);
  signal ram : ram_t := (
    others => x"00");

begin  -- behavioural

  process(clk)
  begin
    if(rising_edge(Clk)) then

      if cs='1' then
        rdata <= ram(address);
      end if;

        if w='1' then
          ram(write_address) <= wdata;
          report "writing $" & to_hstring(wdata) & " to sector buffer offset $"
            & to_hstring(to_unsigned(write_address,12)) severity note;
        end if;
      
    end if;    
  end process;

end behavioural;
