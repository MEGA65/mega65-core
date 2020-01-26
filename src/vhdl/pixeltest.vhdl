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

library UNISIM;
use UNISIM.vcomponents.all;



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
         jbhi : out std_logic_vector(10 downto 7) := (others => 'Z');
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
  signal ethclock : std_logic;
  signal clock162 : std_logic;
  signal clock27 : std_logic;
  signal clock54 : std_logic;
  
  signal segled_counter : unsigned(31 downto 0) := (others => '0');

  signal pixel_strobe : std_logic := '0';
  signal pixel_valid : std_logic := '0';
  signal pixel_x : integer := 0;
  
  signal lcd_pixel_strobe : std_logic;
  signal lcd_hsync : std_logic;
  signal lcd_vsync : std_logic;
  signal lcd_display_enable : std_logic := '0';

  signal red_in : unsigned(7 downto 0) := x"00";
  signal green_in : unsigned(7 downto 0) := x"00";
  signal blue_in : unsigned(7 downto 0) := x"00";
  
  signal buffer_vgared : unsigned(7 downto 0);
  signal buffer_vgagreen : unsigned(7 downto 0);
  signal buffer_vgablue : unsigned(7 downto 0);

  signal pixel_counter : integer := 0;
  signal x_zero : std_logic := '0';
  signal y_zero : std_logic := '0';

  signal xz50 : std_logic;
  signal xz60 : std_logic;
  signal p : std_logic;
  signal ifi : std_logic;
  signal ra60 : integer := 0;
  
  signal spot : std_logic := '0';
  signal bitnum : integer range 0 to 16 := 0;
  signal raster_counter : integer range 0 to 65535 := 0;
  signal x_zero_last : std_logic := '0';

  signal pixel_due : std_logic := '0';

  signal seg_led_data : unsigned(31 downto 0);

  signal x0count : integer := 0;
  signal y0count : integer := 0;

  signal qspi_clock : std_logic := '0';

  signal trigger_reconfigure : std_logic := '0';
  signal reconfigure_address : unsigned(31 downto 0) := to_unsigned(0,32);
  signal counter : unsigned(31 downto 0) := to_unsigned(0,32);
  
begin

  -- Used to allow MEGA65 to instruct FPGA to start a different bitstream #153
  reconfig1: entity work.reconfig
    port map ( clock => cpuclock,
               trigger_reconfigure => trigger_reconfigure,
               reconfigure_address => reconfigure_address);

--XilinxHDLLibrariesGuide,version2012.4
  STARTUPE2_inst: STARTUPE2
    generic map(PROG_USR=>"FALSE", --Activate program event security feature.
                                   --Requires encrypted bitstreams.
  SIM_CCLK_FREQ=>10.0 --Set the Configuration Clock Frequency(ns) for simulation.
    )
    port map(
--      CFGCLK=>CFGCLK,--1-bit output: Configuration main clock output
--      CFGMCLK=>CFGMCLK,--1-bit output: Configuration internal oscillator
                              --clock output
--             EOS=>EOS,--1-bit output: Active high output signal indicating the
                      --End Of Startup.
--             PREQ=>PREQ,--1-bit output: PROGRAM request to fabric output
             CLK=>'0',--1-bit input: User start-up clock input
             GSR=>'0',--1-bit input: Global Set/Reset input (GSR cannot be used
                      --for the port name)
             GTS=>'0',--1-bit input: Global 3-state input (GTS cannot be used
                      --for the port name)
             KEYCLEARB=>'0',--1-bit input: Clear AES Decrypter Key input
                                  --from Battery-Backed RAM (BBRAM)
             PACK=>'0',--1-bit input: PROGRAM acknowledge input

             -- Put CPU clock out on the QSPI CLOCK pin
             USRCCLKO=>qspi_clock,--1-bit input: User CCLK input
             USRCCLKTS=>'0',--1-bit input: User CCLK 3-state enable input

             -- Assert DONE pin
             USRDONEO=>'1',--1-bit input: User DONE pin output control
             USRDONETS=>'1' --1-bit input: User DONE 3-state enable output
             );
-- End of STARTUPE2_inst instantiation

  
  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock81 => pixelclock, -- 80MHz
               clock41 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock162 => clock162,
               clock27 => clock27,
               clock54 => clock54
               );

  pixel0: entity work.pixel_driver
    port map (
               clock81 => pixelclock, -- 80MHz
               clock162 => clock162,
               clock27 => clock27,

               cpuclock => cpuclock,

--               xz50 => xz50,
--               xz60 => xz60,
--               p => p,
--               ifi => ifi,
--               ra60 => ra60,
               
               -- Select 50/60Hz video mode
               pal50_select => sw(0),
               vga60_select => sw(4),
               -- Show test pattern
               test_pattern_enable => sw(1),
               -- Control HSYNC/VSYNC polarities
               hsync_invert => sw(2),
               vsync_invert => sw(3),
               x_zero => x_zero,
               y_zero => y_zero,

               pixel_strobe_out => pixel_due,
               
               -- Pixels
               red_i => red_in,
               green_i => green_in,
               blue_i => blue_in,

               red_no => buffer_vgared,
               green_no => buffer_vgagreen,
               blue_no => buffer_vgablue,

               -- VGA signals
               hsync => hsync,
               vsync => vsync,

               -- LCD panel signals
               lcd_pixel_strobe => lcd_pixel_strobe,
               lcd_hsync => lcd_hsync,
               lcd_vsync => lcd_vsync
--               lcd_display_enable => lcd_display_enable
               );                              

  red_in <= x"00" when (pixel_counter > (39+raster_counter) and pixel_counter < (760-raster_counter) ) else x"FF";
  blue_in <= x"00" when (pixel_counter /=1 and pixel_counter /= 39 and pixel_counter/= 759 and pixel_counter/=799 ) else x"FF";
  
  -- VGA out on LCD panel
  jalo <= std_logic_vector(buffer_vgablue(7 downto 4));
  jahi <= std_logic_vector(buffer_vgared(7 downto 4));
  jblo <= std_logic_vector(buffer_vgagreen(7 downto 4));    
  jbhi(8) <= lcd_hsync;
  jbhi(9) <= lcd_vsync;
  jbhi(10) <= lcd_display_enable xor sw(15);

  -- Push correct clock to LCD panel
--  jbhi(7) <= clock30 when sw(0)='1' else cpuclock;
  
  process (pixelclock,sw,buffer_vgablue,buffer_vgared,buffer_vgagreen) is
    variable digit : std_logic_vector(3 downto 0);
  begin    

    if sw(0)='0' and sw(4)='0' then
      -- NTSC
      vgablue <= buffer_vgablue(7 downto 4);
      vgared <= buffer_vgared(7 downto 4);
      vgagreen <= buffer_vgagreen(7 downto 4);
    elsif sw(0)='0' and sw(4)='1' then
      -- VGA64Hz
      vgared <= buffer_vgablue(7 downto 4);
      vgagreen <= buffer_vgared(7 downto 4);
      vgablue <= buffer_vgagreen(7 downto 4);
    else
      -- PAL
      vgagreen <= buffer_vgablue(7 downto 4);
      vgablue <= buffer_vgared(7 downto 4);
      vgared <= buffer_vgagreen(7 downto 4);
    end if;
    
    if rising_edge(pixelclock) then

      counter <= counter + 1;
      led(14) <= counter(25);
      led(15) <= counter(28);
      trigger_reconfigure <= counter(28);
      
      led(0) <= x_zero;
      led(1) <= y_zero;
      led(2) <= pixel_due;
      led(3) <= p;
      led(4) <= ifi;
--      led(15 downto 6) <= std_logic_vector(to_unsigned(ra60,10));
      jclo(1) <= x_zero;
      jclo(2) <= xz60;
      jclo(3) <= p;
      jclo(4) <= ifi;

      if x_zero='1' then
        x0count <= x0count + 1;
      end if;
      if y_zero='1' then
        y0count <= y0count + 1;
      end if;
      
      segled_counter <= segled_counter + 1;

      sseg_an <= (others => '1');
      sseg_an(to_integer(segled_counter(17 downto 15))) <= '0';

      qspi_clock <= segled_counter(26);
      
      if segled_counter(17 downto 15)=0 then
        digit := std_logic_vector(seg_led_data(3 downto 0));
      elsif segled_counter(17 downto 15)=1 then
        digit := std_logic_vector(seg_led_data(7 downto 4));
      elsif segled_counter(17 downto 15)=2 then
        digit := std_logic_vector(seg_led_data(11 downto 8));
      elsif segled_counter(17 downto 15)=3 then
        digit := std_logic_vector(seg_led_data(15 downto 12));
      elsif segled_counter(17 downto 15)=4 then
        digit := std_logic_vector(seg_led_data(19 downto 16));
      elsif segled_counter(17 downto 15)=5 then
        digit := std_logic_vector(seg_led_data(23 downto 20));
      elsif segled_counter(17 downto 15)=6 then
        digit := std_logic_vector(seg_led_data(27 downto 24));
      elsif segled_counter(17 downto 15)=7 then
        digit := std_logic_vector(seg_led_data(31 downto 28));
      end if;

      seg_led_data(31 downto 16) <= to_unsigned(x0count,16);
      seg_led_data(15 downto 0) <= to_unsigned(y0count,16);

      -- segments are:
      -- 7 - decimal point
      -- 6 - middle
      -- 5 - upper left
      -- 4 - lower left
      -- 3 - bottom
      -- 2 - lower right
      -- 1 - upper right
      -- 0 - top
      case digit is
        when x"0" => sseg_ca <= "11000000";
        when x"1" => sseg_ca <= "11111001";
        when x"2" => sseg_ca <= "10100100";
        when x"3" => sseg_ca <= "10110000";
        when x"4" => sseg_ca <= "10011001";
        when x"5" => sseg_ca <= "10010010";
        when x"6" => sseg_ca <= "10000010";
        when x"7" => sseg_ca <= "11111000";
        when x"8" => sseg_ca <= "10000000";
        when x"9" => sseg_ca <= "10010000";
        when x"A" => sseg_ca <= "10001000";
        when x"B" => sseg_ca <= "10000011";
        when x"C" => sseg_ca <= "11000110";
        when x"D" => sseg_ca <= "10100001";
        when x"E" => sseg_ca <= "10000110";
        when x"F" => sseg_ca <= "10001110";
        when others => sseg_ca <= "10100001";
      end case; 
      



      
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
        if pixel_due='1' then          
          if pixel_counter /= 800 then
            if x_zero_last = '0' then
              pixel_counter <= pixel_counter + 1;
            end if;

            pixel_valid <= '1';
            pixel_x <= pixel_counter;
            green_in <= (others => spot);
          end if;
        end if;        
      end if;
    end if;
  end process;
  
  
end Behavioral;
