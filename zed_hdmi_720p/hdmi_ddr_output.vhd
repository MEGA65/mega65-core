----------------------------------------------------------------------------------
-- Engineer:    Mike Field <hamster@snap.net.nz>
-- 
-- Module Name:    hdmi_ddr_output - Behavioral 
--
-- Description: DDR inferface to the ADV7511 HDMI transmitter
--
-- Feel free to use this how you see fit, and fix any errors you find :-)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity hdmi_ddr_output is
    Port ( clk      : in  STD_LOGIC;
           clk90    : in  STD_LOGIC;
           y        : in  STD_LOGIC_VECTOR (7 downto 0);
           c        : in  STD_LOGIC_VECTOR (7 downto 0);
           hsync_in : in  STD_LOGIC;
           vsync_in : in  STD_LOGIC;
           de_in    : in  STD_LOGIC;
           
           hdmi_clk      : out   STD_LOGIC;
           hdmi_hsync    : out   STD_LOGIC;
           hdmi_vsync    : out   STD_LOGIC;
           hdmi_d        : out   STD_LOGIC_VECTOR (15 downto 0);
           hdmi_de       : out   STD_LOGIC;
           hdmi_scl      : out   STD_LOGIC;
           hdmi_sda      : inout STD_LOGIC);
end hdmi_ddr_output;

architecture Behavioral of hdmi_ddr_output is
   COMPONENT i2c_sender
   PORT(
      clk    : IN std_logic;
      resend : IN std_logic;    
      siod   : INOUT std_logic;      
      sioc   : OUT std_logic
   );
   END COMPONENT;

       signal counter : integer := 0;
       signal resend : std_logic := '1';
      
begin
clk_proc: process(clk)
   begin
      if rising_edge(clk) then
         hdmi_vsync <= vsync_in;
         hdmi_hsync <= hsync_in;

         if counter < 100000000 then
           counter <= counter + 1;
           resend <= '0';
         else
           counter <= 0;
           resend <= '1';
         end if;
                                  
      end if;
   end process;

ODDR_hdmi_clk : ODDR 
   generic map(DDR_CLK_EDGE => "SAME_EDGE", INIT => '0',SRTYPE => "SYNC") 
   port map (C => clk90, Q => hdmi_clk,  D1 => '1', D2 => '0', CE => '1', R => '0', S => '0');

ODDR_hdmi_de : ODDR 
   generic map(DDR_CLK_EDGE => "SAME_EDGE", INIT => '0',SRTYPE => "SYNC") 
   port map (C => clk, Q => hdmi_de,  D1 => de_in, D2 => de_in, CE => '1', R => '0', S => '0');

ddr_gen: for i in 0 to 7 generate
   begin
   ODDR_hdmi_d : ODDR 
     generic map(DDR_CLK_EDGE => "SAME_EDGE", INIT => '0',SRTYPE => "SYNC") 
     port map (C => clk, Q => hdmi_d(i+8),  D1 => y(i), D2 => c(i), CE => '1', R => '0', S => '0');
   end generate;
   hdmi_d(7 downto 0) <= "00000000";

-----------------------------------------------------------------------   
-- This sends the configuration register values to the HDMI transmitter
-----------------------------------------------------------------------   
i_i2c_sender: i2c_sender PORT MAP(
      clk => clk,
      resend => resend,
      sioc => hdmi_scl,
      siod => hdmi_sda
   );
end Behavioral;

