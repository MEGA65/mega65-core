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
use work.cputypes.all;
use work.types_pkg.all;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity container is
  Port ( CLK_IN : in STD_LOGIC;
--         btnCpuReset : in  STD_LOGIC;
--         irq : in  STD_LOGIC;
--         nmi : in  STD_LOGIC;

         irled : out std_logic := '1';

         i2c1sda : inout std_logic;
         i2c1scl : inout std_logic;

         -- Direct lines to OrangeCrab FPGA board.
         -- NOTE: fpga_mux3 is also tied to EN_MIC/EN_5V by OrangeCrab. Thus we
         -- should not drive it from here.  Later it will be freed up again for
         -- us to use as a direct link between the FPGAs.
         fpga_mux1 : out std_logic;
         fpga_mux2 : in std_logic;
         fpga_mux3 : in std_logic; -- MUST BE INPUT: See note above!
         fpga_mux4 : in std_logic;
         
         modem1_pcm_clk_in : in std_logic;
         modem1_pcm_sync_in : in std_logic;
         modem1_pcm_data_in : in std_logic;
         modem1_pcm_data_out : out std_logic;

         modem2_pcm_clk_in : in std_logic;
         modem2_pcm_sync_in : in std_logic;
         modem2_pcm_data_in : in std_logic;
         modem2_pcm_data_out : out std_logic;

         ----------------------------------------------------------------------
         -- MEMS microphones
         ----------------------------------------------------------------------
         micData0 : in std_logic;
         micData1 : in std_logic;

         ----------------------------------------------------------------------
         -- Touch screen interface
         ----------------------------------------------------------------------
         touch_sda : inout std_logic := '1';
         touch_scl : inout std_logic := '1';

         ----------------------------------------------------------------------
         -- LCD output
         ----------------------------------------------------------------------
         lcd_vsync : out STD_LOGIC;
         lcd_hsync : out  STD_LOGIC;
         lcd_display_enable : out STD_LOGIC;
         lcd_dclk : out STD_LOGIC;
         lcd_red : out  UNSIGNED (5 downto 0);
         lcd_green : out  UNSIGNED (5 downto 0);
         lcd_blue : out  UNSIGNED (5 downto 0);

         TMDS_data_p : out STD_LOGIC_VECTOR(2 downto 0);
         TMDS_data_n : out STD_LOGIC_VECTOR(2 downto 0);
         TMDS_clk_p : out STD_LOGIC;
         TMDS_clk_n : out STD_LOGIC;

         ----------------------------------------------------------------------
         -- HyperRAM as expansion RAM
         ----------------------------------------------------------------------
         hr_d : inout unsigned(7 downto 0) := (others => 'Z');
         hr_rwds : inout std_logic := '1';
         hr_reset : out std_logic := '1';
         hr_rsto : out std_logic := '1';
         hr_clk_n : out std_logic := '0';
         hr_clk_p : out std_logic := '1';
         hr_cs0 : out std_logic := '1';
         hr_cs1 : out std_logic := '1';

         -------------------------------------------------------------------------
         -- Lines for the SDcard interface itself
         -------------------------------------------------------------------------
         sdReset : out std_logic := '0';  -- must be 0 to power SD controller (cs_bo)
         sdClock : out std_logic := 'Z';       -- (sclk_o)
         sdMOSI : out std_logic := 'Z';
         sdMISO : in  std_logic;

         ----------------------------------------------------------------------
         -- Flash RAM for holding config
         ----------------------------------------------------------------------
--         QspiSCK : out std_logic;
         QspiDB : inout unsigned(3 downto 0) := (others => 'Z');
         QspiCSn : out std_logic;

         ----------------------------------------------------------------------
         -- Analog headphone jack output
         -- (amplifier enable is on an IO expander)
         ----------------------------------------------------------------------
         headphone_right : out std_logic;
         headphone_mic : in std_logic;

         ----------------------------------------------------------------------
         -- I2S speaker audio output
         ----------------------------------------------------------------------
         i2s_speaker : out std_logic;
         i2s_bclk : out std_logic := '1'; -- Force 16 cycles per sample,
                                          -- instead of 32

         ----------------------------------------------------------------------
         -- Debug interfaces on TE0725
         ----------------------------------------------------------------------
         led : out std_logic;

         ----------------------------------------------------------------------
         -- UART monitor interface
         ----------------------------------------------------------------------
         monitor_tx : out std_logic;
         monitor_rx : in std_logic

         );
end container;

architecture Behavioral of container is

  signal buffer_vgared : unsigned(7 downto 0);
  signal buffer_vgagreen : unsigned(7 downto 0);
  signal buffer_vgablue : unsigned(7 downto 0);

  signal ethclock : std_logic;
  signal cpuclock : std_logic;
  signal clock41 : std_logic;
  signal clock27 : std_logic;
  signal pixelclock : std_logic; -- i.e., clock81p
  signal clock162 : std_logic;
  signal clock200 : std_logic;
  signal clock270 : std_logic;
  signal clock325 : std_logic;

  signal dummy : std_logic_vector(2 downto 0);
  signal sawtooth_phase : integer := 0;
  signal sawtooth_counter : integer := 0;
  signal sawtooth_level : integer := 0;

  -- Dummy signals for stub / not yet implemented interfaces
  signal eth_mdio : std_logic := '0';
  signal c65uart_rx : std_logic := '1';

  signal pin_number : integer;

  signal dummypins : std_logic_vector(1 to 100) := (others => '0');

  signal qspi_clock : std_logic;

  signal pcm_clk : std_logic := '0';
  signal pcm_rst : std_logic := '1';
  signal pcm_clken : std_logic := '0';
  signal pcm_l : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(0,16));
  signal pcm_r : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(0,16));
  signal pcm_acr : std_logic := '0';
  signal pcm_n   : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(0,20));
  signal pcm_cts : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(0,20));

  signal vsync : std_logic;
  signal hdmi_hsync : std_logic;
  signal vgared : unsigned(7 downto 0);
  signal vgagreen : unsigned(7 downto 0);
  signal vgablue : unsigned(7 downto 0);
  signal hdmi_dataenable : std_logic;
  signal lcd_dataenable : std_logic;

  signal tmds : slv_9_0_t(0 to 2);
  
  signal reset_high : std_logic := '1';
  signal dvi_reset : std_logic := '1';

  signal dvi_select : std_logic := '1';

  signal TMDS_clk_q : std_logic := '0';
  
begin

  -- New clocking setup, using more optimised selection of multipliers
  -- and dividers, as well as the ability of some clock outputs to provide an
  -- inverted clock for free.
  -- Also, the 50 and 100MHz ethernet clocks are now independent of the other
  -- clocks, so that Vivado shouldn't try to meet timing closure in the (already
  -- protected) domain crossings used for those.
  clocks1: entity work.clocking
    port map ( clk_in    => CLK_IN,
               clock27   => clock27,    --   27     MHz
               clock41   => cpuclock,   --   40.5   MHz
               clock50   => ethclock,   --   50     MHz
               clock81p  => pixelclock, --   81     MHz
               clock163  => clock162,   --  162.5   MHz
               clock200  => clock200,   --  200     MHz
               clock270 => clock270,
               clock325  => clock325    --  325     MHz
               );

  pixel0: entity work.pixel_driver
    port map (
      clock81 => pixelclock, -- 80MHz
      clock27 => clock27,

      cpuclock => cpuclock,
      
      -- Define the video signal we want
      hsync_invert => '0',
      vsync_invert => '0',
      pal50_select => '1',
      vga60_select => '0',
      test_pattern_enable => '1',
      
      -- Pixel data from the video pipeline
      -- (clocked at 81MHz pixel clock)
      -- For now, just provide a blank blue screen.
      -- Should never be displayed, anyway, as we are using test pattern mode
      red_i => (others => '0'),
      green_i => (others => '0'),
      blue_i => (others => '1'),

      -- The pixel for direct output to VGA pins
      -- It is clocked at the correct pixel
      red_no => vgared,
      green_no => vgagreen,
      blue_no => vgablue,      

      hsync => hdmi_hsync,
      vsync => vsync,  -- for HDMI & LCD
      lcd_hsync => lcd_hsync,      -- for LCD
--      vga_blank => vga_blank,

      narrow_dataenable => hdmi_dataenable,
      fullwidth_dataenable => lcd_dataenable
      
      );     
  
  hdmi0: entity work.vga_to_hdmi
    port map (
      select_44100 => '1',
      -- Disable HDMI-style audio if one
      -- BUT allow dipswitch 2 of S3 on the MEGA65 R3 main board to INVERT
      -- this behaviour
      dvi => dvi_select,
      vic => std_logic_vector(to_unsigned(2,8)), -- CEA/CTA VIC 17=576p50 PAL, 2 = 480p60 NTSC
      aspect => "01", -- 01=4:3, 10=16:9
      pix_rep => '0', -- no pixel repetition
      vs_pol => '1',  -- 1=active high
      hs_pol => '1',

      vga_rst => reset_high, -- active high reset
      vga_clk => clock27, -- VGA pixel clock
      vga_vs => vsync, -- active high vsync
      vga_hs => hdmi_hsync, -- active high hsync
      vga_de => hdmi_dataenable,   -- pixel enable

      vga_r => std_logic_vector(vgared),
      vga_g => std_logic_vector(vgagreen),
      vga_b => std_logic_vector(vgablue),

      -- Feed in audio
      pcm_rst => pcm_rst, -- active high audio reset
      pcm_clk => pcm_clk, -- audio clock at fs
      pcm_clken => pcm_clken, -- audio clock enable
      pcm_l => pcm_l,
      pcm_r => pcm_r,
      pcm_acr => pcm_acr, -- 1KHz
      pcm_n => pcm_n, -- ACR N value
      pcm_cts => pcm_cts, -- ACR CTS value

      tmds => tmds
      );

     -- serialiser: in this design we use TMDS SelectIO outputs
    GEN_HDMI_DATA: for i in 0 to 2 generate
    begin
        HDMI_DATA: entity work.serialiser_10to1_selectio
            port map (
                rst     => dvi_reset,
                clk     => clock27,
                clk_x10  => clock270,
                d       => tmds(i),
                out_p   => TMDS_data_p(i),
                out_n   => TMDS_data_n(i)
            );
    end generate GEN_HDMI_DATA;
    HDMI_CLK: entity work.serialiser_10to1_selectio
        port map (
            rst     => dvi_reset,
            clk     => clock27,
            clk_x10  => clock270,
            d       => "0000011111",
            out_p   => TMDS_clk_p,
            out_n   => TMDS_clk_n
        );    

  lcd_display_enable <= lcd_dataenable;
  
  process (clock27,cpuclock)
  begin
    
    if rising_edge(cpuclock) then

      fpga_mux1 <= monitor_rx;
      monitor_tx <= fpga_mux2;
      
      -- Set active-high reset based on some method of input
      -- MEGAphone R4 PCB doesn't have a reset button, though.
      reset_high <= '0';
      
      -- Provide and clear single reset impulse to digital video output modules
      if reset_high='0' then
        dvi_reset <= '0';
      end if;
    end if;
    
    -- LCD direct output
    lcd_dclk <= clock27;
    lcd_vsync <= vsync;
    lcd_red <= vgared(7 downto 2);
    lcd_green <= vgagreen(7 downto 2);
    lcd_blue <= vgablue(7 downto 2);
    
  end process;

end Behavioral;
