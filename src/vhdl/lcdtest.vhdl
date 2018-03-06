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
         -- CIA1 ports for keyboard/joystick 
         ----------------------------------------------------------------------
--         porta_pins : inout  std_logic_vector(7 downto 0);
--         portb_pins : inout  std_logic_vector(7 downto 0);
         
         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vsync : out STD_LOGIC;
         hsync : out  STD_LOGIC;
         vgared : buffer  UNSIGNED (3 downto 0);
         vgagreen : buffer  UNSIGNED (3 downto 0);
         vgablue : buffer  UNSIGNED (3 downto 0);

         ----------------------------------------------------------------------
         -- PS/2 keyboard interface
         ----------------------------------------------------------------------
         ps2clk : in std_logic;
         ps2data : in std_logic;

         jblo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jbhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jalo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jahi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jdlo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jdhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jclo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jchi : inout std_logic_vector(10 downto 7) := (others => 'Z');
                  
         ----------------------------------------------------------------------
         -- Debug interfaces on Nexys4 board
         ----------------------------------------------------------------------
         led : out std_logic_vector(15 downto 0) := (others => '1');
         sw : in std_logic_vector(15 downto 0);
         btn : in std_logic_vector(4 downto 0);

         UART_TXD : out std_logic := '1';
         RsRx : in std_logic;
         
         sseg_ca : out std_logic_vector(7 downto 0) := x"00";
         sseg_an : out std_logic_vector(7 downto 0) := x"00"
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
  signal clock200 : std_logic;
  signal clock40 : std_logic;
  signal clock33 : std_logic;
  signal clock30 : std_logic;

  signal hsync_i : std_logic := '0';
  signal vsync_i : std_logic := '0';
  signal hsync_o : std_logic := '0';
  signal vsync_o : std_logic := '0';
  signal oof_i : std_logic := '0';
  signal oof_o : std_logic := '0';
  
  signal segled_counter : unsigned(31 downto 0) := (others => '0');

  signal lcd_clk_i : std_logic;
  signal lcd_clk_o : std_logic;
  signal lcd_hsync_i : std_logic;
  signal lcd_hsync : std_logic;
  signal lcd_vsync_i : std_logic;
  signal lcd_vsync : std_logic;
  signal lcd_de_i : std_logic;
  signal lcd_de_o : std_logic;

  signal hsync_pal50 : std_logic;
  signal vsync_pal50 : std_logic;
  signal inframe_pal50 : std_logic;
  
  
  signal red_i : unsigned(7 downto 0);
  signal green_i : unsigned(7 downto 0);
  signal blue_i : unsigned(7 downto 0);

  signal red_o : unsigned(7 downto 0);
  signal green_o : unsigned(7 downto 0);
  signal blue_o : unsigned(7 downto 0);
  
begin
  
  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock100 => pixelclock, -- 100MHz
               clock50 => cpuclock, -- 50MHz
               clock40 => clock40,
               clock33 => clock33,
               clock30 => clock30,
               clock200 => clock200
               );

  frame50: entity work.frame_generator
    generic map ( frame_width => 1065,
                  display_width => 800,
                  frame_height => 625,
                  display_height => 600,
                  vsync_start => 618,
                  hsync_start => 921,
                  hsync_end => 1033
                  )                  
    port map ( clock => clock33,
               hsync => hsync_pal50,
               vsync => vsync_pal50,
               inframe => inframe_pal50,

               -- Get test pattern
               red_o => red_i,
               green_o => green_i,
               blue_o => blue_i
               );
               
               
  
  pixel0: entity work.pixel_driver
    port map (
      pixelclock_select => sw(7 downto 0),
      
      clock200 => clock200,
      clock100 => pixelclock,
      clock50 => cpuclock,
      clock40 => clock40,
      clock33 => clock33,
      clock30 => clock30,

      red_i => red_i,
      green_i => green_i,
      blue_i => blue_i,

      red_o => red_o,
      green_o => green_o,
      blue_o => blue_o,

      hsync_i => hsync_i,
      hsync_o => hsync_o,
      vsync_i => vsync_i,
      vsync_o => vsync_o,

      lcd_hsync_i => lcd_hsync_i,
      lcd_hsync_o => lcd_hsync,
      lcd_vsync_i => lcd_vsync_i,
      lcd_vsync_o => lcd_vsync,

      viciv_outofframe_i => oof_i,
      viciv_outofframe_o => oof_o,
      
      lcd_display_enable_i => lcd_de_i,
      lcd_display_enable_o => lcd_de_o,

      lcd_pixel_strobe_i => lcd_clk_i,
      lcd_pixel_strobe_o => lcd_clk_o

      );

  vgared <= red_o(7 downto 4);
  vgagreen <= green_o(7 downto 4);
  vgablue <= blue_o(7 downto 4);
    
  jalo <= std_logic_vector(blue_o);
  jahi <= std_logic_vector(red_o);
  jblo <= std_logic_vector(green_o);
  jbhi(7) <= lcd_clk_o;
  jbhi(8) <= lcd_hsync;
  jbhi(9) <= lcd_vsync;
  jbhi(10) <= lcd_de_o;
  
  process (cpuclock)
  begin
    if rising_edge(cpuclock) then
    end if;
  end process;
  
end Behavioral;
