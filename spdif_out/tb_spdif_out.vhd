--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:   22:35:20 07/07/2011
-- Design Name:   
-- Module Name:   C:/Users/Hamster/Projects/FPGA/spdif_out/tb_spdif_out.vhd
-- Project Name:  spdif_out
-- Target Device:  
-- Tool versions:  
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: spdf_out
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
 
ENTITY tb_spdif_out IS
END tb_spdif_out;
 
ARCHITECTURE behavior OF tb_spdif_out IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT spdf_out
    PORT(
         clk : IN  std_logic;
         spdif_out : OUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal clk : std_logic := '0';

 	--Outputs
   signal spdif_out : std_logic;

   -- Clock period definitions
   constant clk_period : time := 20 ns;
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: spdf_out PORT MAP (
          clk => clk,
          spdif_out => spdif_out
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

      wait for clk_period*10;

      -- insert stimulus here 

      wait;
   end process;

END;
