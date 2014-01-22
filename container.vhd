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
         btnCpuReset : in  STD_LOGIC;
--         irq : in  STD_LOGIC;
--         nmi : in  STD_LOGIC;

         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vsync : out  STD_LOGIC;
         hsync : out  STD_LOGIC;
         vgared : out  UNSIGNED (3 downto 0);
         vgagreen : out  UNSIGNED (3 downto 0);
         vgablue : out  UNSIGNED (3 downto 0);

         ----------------------------------------------------------------------
         -- PS/2 keyboard interface
         ----------------------------------------------------------------------
         ps2clk : in std_logic;
         ps2data : in std_logic;
         
         ----------------------------------------------------------------------
         -- Debug interfaces on Nexys4 board
         ----------------------------------------------------------------------
         led0 : out std_logic;
         led1 : out std_logic;
         led2 : out std_logic;
         led3 : out std_logic;
         led4 : out std_logic;
         led5 : out std_logic;
         sw : in std_logic_vector(15 downto 0);
         btn : in std_logic_vector(4 downto 0);

         UART_TXD : out std_logic;
         RsRx : in std_logic;
         
         sseg_ca : out std_logic_vector(7 downto 0);
         sseg_an : out std_logic_vector(7 downto 0)
         );
end container;

architecture Behavioral of container is

  component dotclock is
    port
      (-- Clock in ports
        CLK_IN1           : in     std_logic;
        -- Clock out ports
        CLK_OUT1          : out    std_logic;
        CLK_OUT2          : out    std_logic;
        CLK_OUT3          : out    std_logic;
        CLK_OUT4          : out    std_logic;
        CLK_OUT5          : out    std_logic
        );
  end component;

  component machine is
  Port ( pixelclock : STD_LOGIC;
         btnCpuReset : in  STD_LOGIC;
         irq : in  STD_LOGIC;
         nmi : in  STD_LOGIC;

         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vsync : out  STD_LOGIC;
         hsync : out  STD_LOGIC;
         vgared : out  UNSIGNED (3 downto 0);
         vgagreen : out  UNSIGNED (3 downto 0);
         vgablue : out  UNSIGNED (3 downto 0);

         ----------------------------------------------------------------------
         -- PS/2 adapted USB keyboard & joystick connector.
         -- For now we will use a keyrah adapter to connect to the keyboard.
         ----------------------------------------------------------------------
         ps2data : in std_logic;
         ps2clock : in std_logic;         

         ----------------------------------------------------------------------
         -- Debug interfaces on Nexys4 board
         ----------------------------------------------------------------------
         led0 : out std_logic;
         led1 : out std_logic;
         led2 : out std_logic;
         led3 : out std_logic;
         sw : in std_logic_vector(15 downto 0);
         btn : in std_logic_vector(4 downto 0);

         UART_TXD : out std_logic;
         RsRx : in std_logic;
         
         sseg_ca : out std_logic_vector(7 downto 0);
         sseg_an : out std_logic_vector(7 downto 0)
         );
  end component;

  
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  
  signal pixelclock : std_logic;
  
  signal segled_counter : unsigned(31 downto 0) := (others => '0');

begin
  
  dotclock1: component dotclock
    port map ( clk_in1 => CLK_IN,
               -- CLK_OUT2 is good for 1920x1200@60Hz, CLK_OUT3___160
               -- for 1600x1200@60Hz
               -- 60Hz works fine, but 50Hz is not well supported by monitors. 
               -- so I guess we will go with an NTSC-style 60Hz display.       
               -- For C64 mode it would be nice to have PAL or NTSC selectable.                    -- Perhaps consider a different video mode for that, or buffering
               -- the generated frames somewhere?
               clk_out2 => pixelclock);

  machine0: machine
    port map (
      pixelclock      => pixelclock,
      btncpureset => btncpureset,
      irq => irq,
      nmi => nmi,
      
      vsync           => vsync,
      hsync           => hsync,
      vgared          => vgared,
      vgagreen        => vgagreen,
      vgablue         => vgablue,

      ps2data =>      ps2data,
      ps2clock =>     ps2clk,
      
      led0 => led0,
      led1 => led1,
      led2 => led2,
      led3 => led3,
      sw => sw,
      btn => btn,

      UART_TXD => UART_TXD,
      RsRx => RsRx,
         
      sseg_ca => sseg_ca,
      sseg_an => sseg_an
      );

  
  -- Hardware buttons for triggering IRQ & NMI
  irq <= not btn(0);
  nmi <= not btn(4);

  
end Behavioral;

