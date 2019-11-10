--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:   21:08:15 09/12/2013
-- Design Name:   
-- Module Name:   C:/Users/hamster/Projects/FPGA/zedboard/zed_hdmi/tb_colour_conversion.vhd
-- Project Name:  zed_hdmi
-- Target Device:  
-- Tool versions:  
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: colour_space_conversion
-- 
-- Dependencies:
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
-- Notes: 
-- This testbench has been automatically generated using types std_logic and
-- std_logic_vector for the ports of the unit under test.  Xilinx recommends
-- that these types always be used for the top-level I/O of a design in order
-- to guarantee that the testbench will bind correctly to the post-implementation 
-- simulation model.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY tb_colour_conversion IS
END tb_colour_conversion;
 
ARCHITECTURE behavior OF tb_colour_conversion IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT colour_space_conversion
    PORT(
         clk : IN  std_logic;
         r1_in : IN  std_logic_vector(8 downto 0);
         g1_in : IN  std_logic_vector(8 downto 0);
         b1_in : IN  std_logic_vector(8 downto 0);
         r2_in : IN  std_logic_vector(8 downto 0);
         g2_in : IN  std_logic_vector(8 downto 0);
         b2_in : IN  std_logic_vector(8 downto 0);
         pair_start_in : IN  std_logic;
         de_in : IN  std_logic;
         vsync_in : IN  std_logic;
         hsync_in : IN  std_logic;
         y_out : OUT  std_logic_vector(7 downto 0);
         c_out : OUT  std_logic_vector(7 downto 0);
         de_out : OUT  std_logic;
         hsync_out : OUT  std_logic;
         vsync_out : OUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal clk : std_logic := '0';
   signal r1_in : std_logic_vector(8 downto 0) := (others => '0');
   signal g1_in : std_logic_vector(8 downto 0) := (others => '0');
   signal b1_in : std_logic_vector(8 downto 0) := (others => '0');
   signal r2_in : std_logic_vector(8 downto 0) := (others => '0');
   signal g2_in : std_logic_vector(8 downto 0) := (others => '0');
   signal b2_in : std_logic_vector(8 downto 0) := (others => '0');
   signal pair_start_in : std_logic := '0';
   signal de_in : std_logic := '0';
   signal vsync_in : std_logic := '0';
   signal hsync_in : std_logic := '0';

 	--Outputs
   signal y_out : std_logic_vector(7 downto 0);
   signal c_out : std_logic_vector(7 downto 0);
   signal de_out : std_logic;
   signal hsync_out : std_logic;
   signal vsync_out : std_logic;

   -- Clock period definitions
   constant clk_period : time := 10 ns;
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: colour_space_conversion PORT MAP (
          clk => clk,
          r1_in => r1_in,
          g1_in => g1_in,
          b1_in => b1_in,
          r2_in => r2_in,
          g2_in => g2_in,
          b2_in => b2_in,
          pair_start_in => pair_start_in,
          de_in => de_in,
          vsync_in => vsync_in,
          hsync_in => hsync_in,
          y_out => y_out,
          c_out => c_out,
          de_out => de_out,
          hsync_out => hsync_out,
          vsync_out => vsync_out
        );

   -- Clock process definitions
   clk_process :process
   begin
		clk <= '0';
		wait for clk_period/2;
		clk <= '1';
		wait for clk_period/2;
   end process;
 

   -- Stimulus process
   stim_proc: process
   begin		
      -- hold reset state for 100 ns.
      wait for 100 ns;	

      de_in    <= '1';
      hsync_in <= '1';
      vsync_in <= '1';
--      r1_in <= "010000000";
--      r2_in <= "010000000";
      g1_in <= "010000000";
      g2_in <= "010000000";
--      b1_in <= "010000000";
--      b2_in <= "010000000";
      pair_start_in <= '1';   
      wait for clk_period;
      de_in    <= '0';
      hsync_in <= '0';
      vsync_in <= '0';
      pair_start_in <= '0';   
      wait for clk_period;
      
--      r1_in <= "100000000";
--      r2_in <= "100000000";
      g1_in <= "100000000";
      g2_in <= "100000000";
--      b1_in <= "100000000";
--      b2_in <= "100000000";
      pair_start_in <= '1';   
      wait for clk_period;
      pair_start_in <= '0';   
      wait for clk_period;

--      r1_in <= "110000000";
--      r2_in <= "110000000";
      g1_in <= "110000000";
      g2_in <= "110000000";
--      b1_in <= "110000000";
--      b2_in <= "110000000";
      pair_start_in <= '1';   
      wait for clk_period;
      pair_start_in <= '0';   
      wait for clk_period;

--      r1_in <= "111111111";
--      r2_in <= "111111111";
      g1_in <= "111111111";
      g2_in <= "111111111";
--      b1_in <= "111111111";
--      b2_in <= "111111111";
      pair_start_in <= '1';   
      wait for clk_period;
      pair_start_in <= '0';   
      wait for clk_period;

      
      -- insert stimulus here 

      wait;
   end process;

END;
