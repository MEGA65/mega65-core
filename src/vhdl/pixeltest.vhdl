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
         vgared : out  UNSIGNED (3 downto 0);
         vgagreen : out  UNSIGNED (3 downto 0);
         vgablue : out  UNSIGNED (3 downto 0);

         ---------------------------------------------------------------------------
         -- IO lines to the ethernet controller
         ---------------------------------------------------------------------------
         eth_mdio : inout std_logic;
         eth_mdc : out std_logic;
         eth_reset : out std_logic;
         eth_rxd : in unsigned(1 downto 0);
         eth_txd : out unsigned(1 downto 0);
         eth_rxer : in std_logic;
         eth_txen : out std_logic;
         eth_rxdv : in std_logic;
         eth_interrupt : in std_logic;
         eth_clock : out std_logic;
         
         -------------------------------------------------------------------------
         -- Lines for the SDcard interface itself
         -------------------------------------------------------------------------
         sdReset : out std_logic := '0';  -- must be 0 to power SD controller (cs_bo)
         sdClock : out std_logic;       -- (sclk_o)
         sdMOSI : out std_logic;      
         sdMISO : in  std_logic;

         ---------------------------------------------------------------------------
         -- Lines for other devices that we handle here
         ---------------------------------------------------------------------------
         aclMISO : in std_logic;
         aclMOSI : out std_logic;
         aclSS : out std_logic;
         aclSCK : out std_logic;
         aclInt1 : in std_logic;
         aclInt2 : in std_logic;
         
         micData : in std_logic;
         micClk : out std_logic;
         micLRSel : out std_logic;

         ampPWM : out std_logic;
         ampSD : out std_logic;

         tmpSDA : inout std_logic;
         tmpSCL : inout std_logic;
         tmpInt : in std_logic;
         tmpCT : in std_logic;

         ----------------------------------------------------------------------
         -- PS/2 keyboard interface
         ----------------------------------------------------------------------
         ps2clk : in std_logic;
         ps2data : in std_logic;

         ----------------------------------------------------------------------
         -- PMODs for LCD screen and associated things during testing
         ----------------------------------------------------------------------
         jalo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jahi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jblo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jbhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jclo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jchi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jdlo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jdhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jxadc : inout std_logic_vector(7 downto 0) := (others => 'Z');
         
         ----------------------------------------------------------------------
         -- Flash RAM for holding config
         ----------------------------------------------------------------------
--         QspiSCK : out std_logic;
         QspiDB : inout std_logic_vector(3 downto 0);
         QspiCSn : out std_logic;
         
         ----------------------------------------------------------------------
         -- Cellular RAM interface for Slow RAM
         ----------------------------------------------------------------------
         --RamCLK : out std_logic;
         --RamADVn : out std_logic;
         --RamCEn : out std_logic;
         --RamCRE : out std_logic;
         --RamOEn : out std_logic;
         --RamWEn : out std_logic;
         --RamUBn : out std_logic;
         --RamLBn : out std_logic;
         --RamWait : in std_logic;
         --MemDB : inout std_logic_vector(15 downto 0);
         --MemAdr : inout std_logic_vector(22 downto 0);
--         ddr2_addr      : out   std_logic_vector(12 downto 0);
--         ddr2_ba        : out   std_logic_vector(2 downto 0);
--         ddr2_ras_n     : out   std_logic;
--         ddr2_cas_n     : out   std_logic;
--         ddr2_we_n      : out   std_logic;
--         ddr2_ck_p      : out   std_logic_vector(0 downto 0);
--         ddr2_ck_n      : out   std_logic_vector(0 downto 0);
--         ddr2_cke       : out   std_logic_vector(0 downto 0);
--         ddr2_cs_n      : out   std_logic_vector(0 downto 0);
--         ddr2_dm        : out   std_logic_vector(1 downto 0);
--         ddr2_odt       : out   std_logic_vector(0 downto 0);
--         ddr2_dq        : inout std_logic_vector(15 downto 0);
--         ddr2_dqs_p     : inout std_logic_vector(1 downto 0);
--         ddr2_dqs_n     : inout std_logic_vector(1 downto 0);
         
         ----------------------------------------------------------------------
         -- Debug interfaces on Nexys4 board
         ----------------------------------------------------------------------
         led : out std_logic_vector(15 downto 0);
         sw : in std_logic_vector(15 downto 0);
         btn : in std_logic_vector(4 downto 0);

         UART_TXD : out std_logic;
         RsRx : in std_logic;
         
         sseg_ca : out std_logic_vector(7 downto 0);
         sseg_an : out std_logic_vector(7 downto 0)
         );
end container;

architecture Behavioral of container is

  signal pixelclock : std_logic;
  signal cpuclock : std_logic;
  signal clock200 : std_logic;
  signal clock40 : std_logic;
  signal clock33 : std_logic;
  signal clock30 : std_logic;
  
  signal segled_counter : unsigned(31 downto 0) := (others => '0');

  signal pixel_strobe : std_logic := '0';
  signal pixel_valid : std_logic := '0';
  
  signal lcd_pixel_strobe : std_logic;
  signal lcd_hsync : std_logic;
  signal lcd_vsync : std_logic;
  signal lcd_display_enable : std_logic;

  signal red_in : unsigned(7 downto 0) := x"00";
  signal green_in : unsigned(7 downto 0) := x"00";
  signal blue_in : unsigned(7 downto 0) := x"00";
  
  signal buffer_vgared : unsigned(7 downto 0);
  signal buffer_vgagreen : unsigned(7 downto 0);
  signal buffer_vgablue : unsigned(7 downto 0);

  signal pixel_counter : integer := 0;
  signal x_zero : std_logic := '0';
  signal y_zero : std_logic := '0';

  signal spot : std_logic := '0';
  signal bitnum : integer range 0 to 16 := 0;
  signal raster_counter : integer range 0 to 65535 := 0;
  signal x_zero_last : std_logic := '0';
  
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

  pixeldriver: entity work.pixel_driver
    port map (
               clock100 => pixelclock, -- 100MHz
               clock50 => cpuclock, -- 50MHz
               clock40 => clock40,
               clock33 => clock33,
               clock30 => clock30,

               -- Select 50/60Hz video mode
               pal50_select => sw(0),
               -- Show test pattern
               test_pattern_enable => sw(1),
               -- Control HSYNC/VSYNC polarities
               hsync_invert => sw(2),
               vsync_invert => sw(3),
               rd_data_count => led(15 downto 6),
               x_zero_out => x_zero,
               y_zero_out => y_zero,
               wr_ack => led(2),
               fifo_full => led(4),
               
               -- Pixels
               pixel_valid => pixel_valid,
               red_i => red_in,
               green_i => green_in,
               blue_i => blue_in,

               red_o => buffer_vgared,
               green_o => buffer_vgagreen,
               blue_o => buffer_vgablue,
               pixel_strobe => pixel_strobe,

               -- VGA signals
               hsync => hsync,
               vsync => vsync,

               -- LCD panel signals
               lcd_pixel_strobe => jbhi(7),
               lcd_hsync => jbhi(8),
               lcd_vsync => jbhi(9),
               lcd_display_enable => jbhi(10)
               );                              

  led(0) <= pixel_strobe;

  vgablue <= buffer_vgablue(7 downto 4);
  vgared <= buffer_vgared(7 downto 4);
  vgagreen <= buffer_vgagreen(7 downto 4);

  red_in <= x"00" when (pixel_counter < 800 ) else x"FF";
  blue_in <= x"00" when (pixel_counter /= 1 ) else x"FF";
  green_in <= (others => spot);
  
  jalo <= std_logic_vector(buffer_vgablue(7 downto 4));
  jahi <= std_logic_vector(buffer_vgared(7 downto 4));
  jblo <= std_logic_vector(buffer_vgagreen(7 downto 4));    

  process (pixelclock) is
  begin
    if rising_edge(pixelclock) then
      bitnum <= raster_counter mod 16;
      spot <= to_unsigned(pixel_counter,16)(bitnum);
      x_zero_last <= x_zero;
      if y_zero='1' then
        raster_counter <= 0;
        pixel_valid <= '0';
      elsif x_zero='1' then
        if (x_zero_last = '0') then
          raster_counter <= raster_counter + 1;
        end if;
        pixel_counter <= 0;
      else
        if pixel_counter /= 800 then
          if x_zero_last = '0' then
            pixel_counter <= pixel_counter + 1;
          end if;
          pixel_valid <= '1';
        else
          pixel_valid <= '0';
        end if;
      end if;
    end if;
  end process;
  
  
end Behavioral;
