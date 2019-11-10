----------------------------------------------------------------------------------
-- Engineer:    Mike Field <hamster@snap.net.nz>
-- 
-- Module Name: clamp_channel - Behavioral 
--
-- Description: data_out is data_in, clamped between 16 and 235
--
-- Feel free to use this how you see fit, and fix any errors you find :-)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity clamp_channel is
    Port ( clk : in  STD_LOGIC;
           data_in : in  STD_LOGIC_VECTOR (7 downto 0);
           data_out : out  STD_LOGIC_VECTOR (7 downto 0));
end clamp_channel;

architecture Behavioral of clamp_channel is

begin

clamp_proc: process(clk) 
   begin
      if rising_edge(clk) then
         data_out <= data_in;
         if data_in( 7 downto 4) = "0000" then  -- if less then 16
            data_out <= "00010000";  -- clap it to 16
         elsif data_in( 7 downto 4) = "1111" or data_in( 7 downto 2) = "111011" then  -- if greater/equal to 236 
            data_out <= "11101011";  -- clap it to 235
         end if;
      end if;
   end process;

end Behavioral;