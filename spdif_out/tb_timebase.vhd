--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:   20:25:57 07/07/2011
-- Design Name:   
-- Module Name:   C:/Users/Hamster/Projects/FPGA/spdif_out/tb_timebase.vhd
-- Project Name:  spdif_out
-- Target Device:  
-- Tool versions:  
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: Timebase
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
 
ENTITY tb_timebase IS
END tb_timebase;
 
ARCHITECTURE behavior OF tb_timebase IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT Timebase
    PORT(
         clk : IN  std_logic;
         bitclock : OUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal clk : std_logic := '0';

 	--Outputs
   signal bitclock : std_logic;

   -- Clock period definitions
   constant clk_period : time := 10 ns;
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: Timebase PORT MAP (
          clk => clk,
          bitclock => bitclock
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
