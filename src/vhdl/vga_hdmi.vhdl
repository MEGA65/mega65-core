----------------------------------------------------------------------------------
-- Engineer:    Mike Field <hamster@snap.net.nz> 
-- Module Name: vga_hdmi - Behavioral 
-- 
-- Description: A test of the Zedboard's VGA & HDMI interface
--
-- Feel free to use this how you see fit, and fix any errors you find :-)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity vga_hdmi is
    Port ( clock27 : in std_logic;

           -- Signals from the VGA generator
           pattern_r      : in std_logic_vector(7 downto 0);
           pattern_g      : in std_logic_vector(7 downto 0);
           pattern_b      : in std_logic_vector(7 downto 0);
           pattern_hsync  : in std_logic;
           pattern_vsync  : in std_logic;
           pattern_de     : in std_logic;
           
           vga_r         : out  STD_LOGIC_VECTOR (7 downto 0);
           vga_g         : out  STD_LOGIC_VECTOR (7 downto 0);
           vga_b         : out  STD_LOGIC_VECTOR (7 downto 0);
           vga_hs        : out  STD_LOGIC;
           vga_vs        : out  STD_LOGIC;

           hdmi_int      : in   std_logic;
           hdmi_clk      : out  STD_LOGIC;
           hdmi_hsync    : out  STD_LOGIC;
           hdmi_vsync    : out  STD_LOGIC;
           hdmi_d        : out  STD_LOGIC_VECTOR (23 downto 0);
           hdmi_de       : out  STD_LOGIC;
           hdmi_scl      : out  STD_LOGIC;
           hdmi_sda      : inout  STD_LOGIC);
end vga_hdmi;

architecture Behavioral of vga_hdmi is
   COMPONENT i2c_sender
   PORT(
      clk    : IN std_logic;
      resend : IN std_logic;    
      siod   : INOUT std_logic;      
      sioc   : OUT std_logic
   );
   END COMPONENT;

   COMPONENT vga_generator
	PORT(
		clk : IN std_logic;          
		r : OUT std_logic_vector(7 downto 0);
		g : OUT std_logic_vector(7 downto 0);
		b : OUT std_logic_vector(7 downto 0);
		de : OUT std_logic;
		vsync : OUT std_logic;
		hsync : OUT std_logic
		);
	END COMPONENT;

   signal counter : integer := 0;
   signal resend : std_logic := '1';      

   signal last_hdmi_int : std_logic;                                     
                                      
begin


-----------------------------------------------------------------------   
-- This sends the configuration register values to the HDMI transmitter
-----------------------------------------------------------------------   
i_i2c_sender: i2c_sender PORT MAP(
      clk => clock27,
      resend => resend,
      sioc => hdmi_scl,
      siod => hdmi_sda
   );

   hdmi_clk <= clock27;
       
clk_proc: process(clock27)
   begin
      if rising_edge(clock27) then

         -- Try to re-activate HDMI display every 0.5 seconds
        resend <= '0';
         if counter < 13500000 then
           counter <= counter + 1;
         else
           counter <= 0;
           resend <= '1';
         end if;

         -- Trigger I2C config on HDMI interrupt
         last_hdmi_int <= hdmi_int;
         if hdmi_int = '0' and last_hdmi_int='1' then
           resend <= '1';
         end if;                                  
                                  
         vga_r  <= pattern_r(7 downto 0);
         vga_g  <= pattern_g(7 downto 0);
         vga_b  <= pattern_b(7 downto 0);

         hdmi_d(7 downto 0)  <= pattern_r;
         hdmi_d(15 downto 8)  <= pattern_g;
         hdmi_d(23 downto 16)  <= pattern_b;

         hdmi_de    <= pattern_de;
         hdmi_hsync <= pattern_hsync;
         hdmi_vsync <= pattern_vsync;
                              
         vga_hs <= pattern_hsync;
         vga_vs <= pattern_vsync;
      end if;
   end process;
end Behavioral;

