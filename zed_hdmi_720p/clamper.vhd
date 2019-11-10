----------------------------------------------------------------------------------
-- Engineer: Mike Field <hamster@snap.net.nz>
-- 
-- Module Name: clamper - Behavioral 
--
-- Description: ensure that Y and Cb/Cr are within range, between 16 and 235
--
-- Feel free to use this how you see fit, and fix any errors you find :-)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity clamper is
    Port ( clk      : in  STD_LOGIC;
           y_in     : in  STD_LOGIC_VECTOR (7 downto 0);
           c_in     : in  STD_LOGIC_VECTOR (7 downto 0);
           de_in    : IN std_logic;
           hsync_in : IN std_logic;
           vsync_in : IN std_logic;
           
           y_out     : out  STD_LOGIC_VECTOR (7 downto 0);
           c_out     : out  STD_LOGIC_VECTOR (7 downto 0);
           de_out    : OUT std_logic;
           hsync_out : OUT std_logic;
           vsync_out : OUT std_logic);
end clamper;

architecture Behavioral of clamper is
	COMPONENT clamp_channel
	PORT(
		clk      : IN std_logic;
		data_in  : IN std_logic_vector(7 downto 0);         
		data_out  : OUT std_logic_vector(7 downto 0)
		);
	END COMPONENT;


begin

	Inst_clamp_channel_y: clamp_channel PORT MAP(
		clk => clk,
		data_in => y_in,
		data_out => y_out
	);

	Inst_clamp_channel_c: clamp_channel PORT MAP(
		clk => clk,
		data_in => c_in,
		data_out => c_out
	);
   
delay_proc: process(clk)
   begin
      if rising_edge(clk) then
         vsync_out <= vsync_in;
         hsync_out <= hsync_in;
         de_out    <= de_in;         
      end if;
   end process;
end behavioral;