use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY ram8x2048 IS
  generic (
    id : in integer
    );
  PORT (
    clkr : IN STD_LOGIC;
    clkw : IN STD_LOGIC;
    cs : IN STD_LOGIC;
    w : IN std_logic;
    write_address : IN integer range 0 to 2047;
    wdata : IN unsigned(7 DOWNTO 0);
    address : IN integer range 0 to 2047;
    rdata : OUT unsigned(7 DOWNTO 0)
    );
END ram8x2048;

architecture behavioural of ram8x2048 is

  type ram_t is array (0 to 2047) of unsigned(7 downto 0);
  signal ram : ram_t := (
    others => x"00");

begin  -- behavioural

  process(clkr,clkw,cs,address,ram)
  begin
    if cs='1' then
      rdata <= ram(address);
      if (id < 1000) then
        report integer'image(id) & ": reading $" & to_hstring(ram(address)) & " from address $" & to_hstring(to_unsigned(address,12));
      end if;
    else
      rdata <= (others => 'Z');
    end if;

    if(rising_edge(Clkw)) then
      if w='1' then
        ram(write_address) <= wdata;
        report integer'image(id) & ": writing $" & to_hstring(wdata) & " to sector buffer offset $"
          & to_hstring(to_unsigned(write_address,12)) severity note;
      end if;
    end if;    
  end process;

end behavioural;

-- The same RAM with a registered read, so that it is block RAM: Vivado
-- cannot map the asynchronous read above to block RAM (ISE could), and the
-- Ethernet RX buffers built from it took 12288 LUTs as LUT RAM, with the
-- tri-state outputs of all of them multiplexed onto the FastIO bus.  The
-- read address must come one clock early (FastIO's fastio_addr_fast), so
-- rdata matches fastio_addr when the CPU reads it.
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

ENTITY ram8x2048_sync IS
  PORT (
    clkr : IN STD_LOGIC;
    clkw : IN STD_LOGIC;
    w : IN std_logic;
    write_address : IN integer range 0 to 2047;
    wdata : IN unsigned(7 DOWNTO 0);
    address : IN integer range 0 to 2047;
    rdata : OUT unsigned(7 DOWNTO 0) := x"00"
    );
END ram8x2048_sync;

architecture behavioural of ram8x2048_sync is

  type ram_t is array (0 to 2047) of unsigned(7 downto 0);
  signal ram : ram_t := (
    others => x"00");
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

begin  -- behavioural

  process(clkr)
  begin
    if rising_edge(clkr) then
      rdata <= ram(address);
    end if;
  end process;

  process(clkw)
  begin
    if rising_edge(clkw) then
      if w='1' then
        ram(write_address) <= wdata;
      end if;
    end if;
  end process;

end behavioural;
