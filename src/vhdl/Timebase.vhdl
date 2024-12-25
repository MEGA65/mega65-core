----------------------------------------------------------------------------------
-- Engineer: Mike Field (hamster@snap.net.nz)
-- 
-- Module Name:    Timebase - Behavioral 
-- Description: Generates bit clock signals for a SPDIF output
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity Timebase is
    Port ( clk : in  STD_LOGIC;
           bitclock : out  STD_LOGIC;
			  loadSerialiser : OUT std_logic);
end Timebase;

architecture Behavioral of Timebase is
   type reg is record
      state      : std_logic_vector(4 downto 0);
      errorTotal : std_logic_vector(9 downto 0);
		bitCount   : std_logic_vector(5 downto 0);
      bitClock   : std_logic;
		loadSerialiser : std_logic;
   end record;

   signal r : reg := ((others => '0'), (others => '0'), (others => '0'), '0', '0');
   signal n : reg;
   
   constant terminalCount : natural := 1133;
   constant errorStep      : natural := 631;
begin
	loadSerialiser <= r.loadSerialiser;
   bitClock 		<= r.bitClock;
	
   process(clk,r)
   begin
      n <= r;
      n.bitclock			<= '0';
		n.loadSerialiser	<= '0';
      n.state 				<= r.state+1;
      case r.state is
         when "00000" =>
            n.bitclock <= '1';
         when "00001" =>
				n.bitcount <= r.bitcount + 1;
         when "00010" =>
				if n.bitcount = "000000" then
					n.loadSerialiser	<= '1';
				end if;				
         when "10000" =>
            if r.errorTotal < terminalCount - errorStep then
               n.state <= "00000";
               n.errorTotal <= r.errorTotal + errorStep;
            else
               n.errorTotal <= r.errorTotal + errorStep - terminalCount;
            end if;
         when "10001" =>            
            n.state <= "00000";
         when others =>
            n.state <= r.state+1;
      end case;
   end process;
   
   process(clk, n)
   begin
      if clk'event and clk = '1' then
         r <= n;
      end if;
   end process;
end Behavioral;
