library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity fpgatemp is
	 Generic ( DELAY_CYCLES : natural := 480 ); -- 10us @ 48 Mhz
    Port ( clk : in  STD_LOGIC;
           rst : in  STD_LOGIC;
           temp : out  STD_LOGIC_VECTOR (11 downto 0));
end fpgatemp;

architecture Behavioral of fpgatemp is

begin

process (clk)
begin
	if Rising_Edge(clk) then
		-- Give a dummy temperature to GHDL simulation
		temp <= (others => '0');
	end if;
end process;

end Behavioral;
