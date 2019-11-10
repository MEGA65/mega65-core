--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:   13:13:40 01/23/2013
-- Design Name:   
-- Module Name:   C:/Users/Hamster/Projects/FPGA/Zedboard/zed_hdmi/tb_zedboard_hdmi.vhd
-- Project Name:  zed_hdmi
-- Target Device:  
-- Tool versions:  
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: zedboard_hdmi
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
 
ENTITY tb_vga_hdmi IS
END tb_vga_hdmi;
 
ARCHITECTURE behavior OF tb_vga_hdmi IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT vga_hdmi
    PORT(
         clk_100     : IN  std_logic;
         hdmi_clk   : OUT  std_logic;
         hdmi_hsync : OUT  std_logic;
         hdmi_vsync : OUT  std_logic;
         hdmi_d : OUT  std_logic_vector(15 downto 0);
         hdmi_de : OUT  std_logic;
         hdmi_scl : OUT  std_logic;
         hdmi_sda : INOUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal clk_100 : std_logic := '0';
   signal hdmi_spdifo : std_logic := '0';

 	--Outputs
   signal hdmi_clk : std_logic;
   signal hdmi_hsync : std_logic;
   signal hdmi_vsync : std_logic;
   signal hdmi_d : std_logic_vector(15 downto 0);
   signal hdmi_de : std_logic;
   signal hdmi_spdif : std_logic;
   signal hdmi_scl : std_logic;
   signal hdmi_sda : std_logic;

   -- Clock period definitions
   constant clk100_period : time := 10 ns; 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: vga_hdmi PORT MAP (
          clk_100    => clk_100,
          hdmi_clk   => hdmi_clk,
          hdmi_hsync => hdmi_hsync,
          hdmi_vsync => hdmi_vsync,
          hdmi_d     => hdmi_d,
          hdmi_de    => hdmi_de,
          hdmi_scl   => hdmi_scl,
          hdmi_sda   => hdmi_sda
        );

   -- Clock process definitions
   clk100_process :process
   begin
		clk_100 <= '0';
		wait for clk100_period/2;
		clk_100 <= '1';
		wait for clk100_period/2;
   end process;
END;
