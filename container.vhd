----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    22:30:37 12/10/2013 
-- Design Name: 
-- Module Name:    container - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity container is
    Port ( CLK_IN : STD_LOGIC;
	        reset : in  STD_LOGIC;
           irq : in  STD_LOGIC;
           nmi : in  STD_LOGIC;
			  monitor_pc : out STD_LOGIC_VECTOR(15 downto 0));
end container;

architecture Behavioral of container is
  component cpu6502
  port (   clock : in STD_LOGIC;
           reset : in  STD_LOGIC;
           irq : in  STD_LOGIC;
           nmi : in  STD_LOGIC;
			  monitor_pc : out STD_LOGIC_VECTOR(15 downto 0));
  end component;
  component fpga_clock is
  port
   (-- Clock in ports
    CLK_IN1           : in     std_logic;
    -- Clock out ports
    CLK_OUT1          : out    std_logic;
    CLK_OUT2          : out    std_logic;
    -- Status and control signals
    RESET             : in     std_logic;
    LOCKED            : out    std_logic
   );
   end component;
	component vga_clock is
   port
     (-- Clock in ports
      CLK_IN1           : in     std_logic;
      -- Clock out ports
      CLK_OUT1          : out    std_logic;
      CLK_OUT2          : out    std_logic;
      -- Status and control signals
      RESET             : in     std_logic;
      LOCKED            : out    std_logic
     );
   end component;

   signal clock : STD_LOGIC;
	signal VGA_PIXEL_CLOCK : STD_LOGIC;
   
begin
  cpu0: cpu6502 port map(clock => clock,reset =>reset,irq => irq,
                         nmi => nmi,monitor_pc => monitor_pc);
  fast_clock: fpga_clock port map(CLK_IN1 => CLK_IN,
                                  CLK_OUT2 => clock,reset => reset);
  pixel_clock: vga_clock port map(CLK_IN1 => CLK_IN,
                                  CLK_OUT2 => vga_pixel_clock,reset => reset);
end Behavioral;

