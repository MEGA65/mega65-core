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
use ieee.numeric_std.all;
use Std.TextIO.all;


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity container is
  Port ( CLK_IN : STD_LOGIC;         
--         btnCpuReset : in  STD_LOGIC;
--         irq : in  STD_LOGIC;
--         nmi : in  STD_LOGIC;

         wifirx : out std_logic;
         wifitx : out std_logic;
         
         ----------------------------------------------------------------------
         -- CIA1 ports for keyboard/joystick 
         ----------------------------------------------------------------------
--         porta_pins : inout  std_logic_vector(7 downto 0);
--         portb_pins : inout  std_logic_vector(7 downto 0);
         
         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vga_vsync : out STD_LOGIC;
         vga_hsync : out  STD_LOGIC;
         vga_red : out  UNSIGNED (3 downto 0);
         vga_green : out  UNSIGNED (3 downto 0);
         vga_blue : out  UNSIGNED (3 downto 0);

         -------------------------------------------------------------------------
         -- Lines for the SDcard interface itself
         -------------------------------------------------------------------------
--         sdReset : out std_logic := '0';  -- must be 0 to power SD controller (cs_bo)
--         sdClock : out std_logic;       -- (sclk_o)
--         sdMOSI : out std_logic;      
--         sdMISO : in  std_logic;

         ----------------------------------------------------------------------
         -- Flash RAM for holding config
         ----------------------------------------------------------------------
--         QspiSCK : out std_logic;
         QspiDB : inout std_logic_vector(3 downto 0) := (others => 'Z');
         QspiCSn : out std_logic;
         
         ----------------------------------------------------------------------
         -- Hyper RAM interface for Slow RAM
         ----------------------------------------------------------------------
         
         ----------------------------------------------------------------------
         -- Debug interfaces on TE0725
         ----------------------------------------------------------------------
         led : out std_logic

--         UART_TXD : out std_logic;
--         RsRx : in std_logic;
         
         );
end container;

architecture Behavioral of container is

  component fpgatemp is
    Generic ( DELAY_CYCLES : natural := 480 ); -- 10us @ 48 Mhz
    Port ( clk : in  STD_LOGIC;
           rst : in  STD_LOGIC;
           temp : out  STD_LOGIC_VECTOR (11 downto 0));
  end component;

  signal pixelclock : std_logic;
  signal cpuclock : std_logic;
  signal clock240 : std_logic;
  signal clock120 : std_logic;
  signal clock100 : std_logic;
  signal ethclock : std_logic;
  signal clock200 : std_logic;

  signal fpga_temperature : std_logic_vector(11 downto 0) := (others => '0');
  
  signal counter : integer range 0 to 100000000 := 0;
  signal led_internal : std_logic := '0';

  signal counter2 : integer range 0 to 10000000 := 0;
  signal wifirx_internal : std_logic := '0';

  signal counter3 : integer range 0 to 50000000 := 0;
  signal wifitx_internal : std_logic := '0';

  signal video_red : unsigned(7 downto 0);
  signal video_green : unsigned(7 downto 0);
  signal video_blue : unsigned(7 downto 0);
  
begin

  -- 60Hz VGA frame
  frame0:       entity work.frame_generator
    generic map ( frame_width => 1057*3-1,
                  display_width => 800 *3,
                  clock_divider => 3,
                  frame_height => 628,
                  display_height => 600,
                  pipeline_delay => 96,
                  vsync_start => 628-22-4,
                  vsync_end => 628-22,
                  hsync_start => 840*3,
                  hsync_end => 900*3
                  )                  
    port map ( clock240 => clock240,
               clock120 => clock120,
               clock80 => pixelclock,
               hsync_polarity => '0',
               vsync_polarity => '0',

               hsync => vga_hsync,
               vsync => vga_vsync,
               red_o => video_red,
               green_o => video_green,
               blue_o => video_blue
               );
               
  
  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock80 => pixelclock, -- 80MHz
               clock40 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock200 => clock200,
               clock100 => clock100,
               clock120 => clock120,
               clock240 => clock240
               );

  fpgatemp0: fpgatemp
    generic map (DELAY_CYCLES => 480)
    port map (
      rst => '0',
      clk => cpuclock,
      temp => fpga_temperature);
  
  process (cpuclock)
  begin
    if rising_edge(cpuclock) then

      vga_red <= video_red(7 downto 4);
      vga_green <= video_red(7 downto 4);
      vga_blue <= video_red(7 downto 4);
      
      if counter /= 0 then
        counter <= counter - 1;
      else
        counter <= 25000000;
        led_internal <= not led_internal;
        led <= led_internal;
      end if;
      if counter2 /= 0 then
        counter2 <= counter2 - 1;
      else
        counter2 <= 5000;
        wifirx_internal <= not wifirx_internal;
        wifirx <= wifirx_internal;
      end if;
      if counter3 /= 0 then
        counter3 <= counter3 - 1;
      else
        counter3 <= 1000;
        wifitx_internal <= not wifitx_internal;
        wifitx <= wifitx_internal;
      end if;
    end if;
  end process;

  -- XXX Ethernet should be 250Mbit fibre port on this board  
  -- eth_clock <= cpuclock;
  
end Behavioral;
