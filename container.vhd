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
           monitor_pc : out STD_LOGIC_VECTOR(15 downto 0)
           );
end container;

architecture Behavioral of container is
  component cpu6502
  port (   clock : in STD_LOGIC;
           reset : in  STD_LOGIC;
           irq : in  STD_LOGIC;
           nmi : in  STD_LOGIC;
           monitor_pc : out STD_LOGIC_VECTOR(15 downto 0);
           monitor_opcode : out std_logic_vector(7 downto 0);
           monitor_a : out std_logic_vector(7 downto 0);
           monitor_x : out std_logic_vector(7 downto 0);
           monitor_y : out std_logic_vector(7 downto 0);
           monitor_sp : out std_logic_vector(7 downto 0);
           monitor_p : out std_logic_vector(7 downto 0);

           -- fast IO port (clocked at core clock)
           fastio_addr : out std_logic_vector(19 downto 0);
           fastio_read : out std_logic;
           fastio_write : out std_logic;
           fastio_wdata : out std_logic_vector(7 downto 0);
           fastio_rdata : in std_logic_vector(7 downto 0)
           );      
  end component;
  
  component iomapper is
    port (Clk : in std_logic;
        address : in std_logic_vector(19 downto 0);
        r : in std_logic;
        w : in std_logic;
        data_i : in std_logic_vector(7 downto 0);
        data_o : out std_logic_vector(7 downto 0)
     );
  end component;
    
  component fpga_clock is
  port
   (-- Clock in ports
    CLK_IN1           : in     std_logic;
    -- Clock out ports
    CLK_OUT1          : out    std_logic;  -- 100MHz
    CLK_OUT2          : out    std_logic;  -- 90MHz
    CLK_OUT3          : out    std_logic;  -- 85MHz
    CLK_OUT4          : out    std_logic;  -- 80MHz
    CLK_OUT5          : out    std_logic;  -- 70MHz
    CLK_OUT6          : out    std_logic;  -- 60MHz
    CLK_OUT7          : out    std_logic;  -- 50MHz
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

  signal fastio_addr : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);

   signal halved_clock : std_logic := '1';
begin
  fast_clock: fpga_clock port map(CLK_IN1 => CLK_IN,
                                  CLK_OUT7 => clock,reset => reset);
  pixel_clock: vga_clock port map(CLK_IN1 => CLK_IN,
                                  CLK_OUT2 => vga_pixel_clock,reset => reset);
  
  cpu0: cpu6502 port map(clock => clock,reset =>reset,irq => irq,
                         nmi => nmi,monitor_pc => monitor_pc,
                         fastio_addr => fastio_addr,
                         fastio_read => fastio_read,
                         fastio_write => fastio_write,
                         fastio_wdata => fastio_wdata,
                         fastio_rdata => fastio_rdata);
  iomapper0: iomapper port map (
    clk => clock, address => fastio_addr, r => fastio_read, w => fastio_write,
    data_i => fastio_wdata, data_o => fastio_rdata);

end Behavioral;

