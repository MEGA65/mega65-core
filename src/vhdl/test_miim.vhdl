library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_miim is
end entity;

architecture foo of test_miim is

  signal clock50mhz : std_logic := '1';

  signal eth_mdio : std_logic := '0';
  signal eth_mdc : std_logic := '0';

  signal miim_request : std_logic := '0';
  signal miim_write : std_logic := '0';
  signal miim_phyid : unsigned(4 downto 0) := to_unsigned(0,5);
  signal miim_register : unsigned(4 downto 0) := to_unsigned(0,5);
  signal miim_read_value : unsigned(15 downto 0) := to_unsigned(0,16);
  signal miim_write_value : unsigned(15 downto 0) := to_unsigned(0,16);
  signal miim_ready : std_logic := '0';
  
  
begin

    miim0:        entity work.ethernet_miim port map (
    clock => clock50mhz,
    eth_mdio => eth_mdio,
    eth_mdc => eth_mdc,

    miim_request => miim_request,
    miim_write => miim_write,
    miim_phyid => miim_phyid,
    miim_register => miim_register,
    miim_read_value => miim_read_value,
    miim_write_value => miim_write_value,
    miim_ready => miim_ready
    );
  
  process is
  begin
    while true loop
      clock50mhz <= '0';
      wait for 10 ns;
      clock50mhz <= '1';
      wait for 10 ns;
    end loop;
  end process;

  process is
  begin
    while true loop
      wait for 100 ns;
      report "asserting miim_request";
      miim_request <= '1';
      wait for 100 ns;
      report "releasing miim_request";
      miim_request <= '0';
      wait for 10 ms;
    end loop;
  end process;       
  
  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
      report "eth_mdio = " & std_logic'image(eth_mdio)
        & ", eth_mdc = " & std_logic'image(eth_mdc);
    end if;
  end process;
  
end foo;
