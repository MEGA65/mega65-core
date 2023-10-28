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
         micClk : out std_logic;

         ----------------------------------------------------------------------
         -- Analog headphone jack output
         -- (amplifier enable is on an IO expander)
         ----------------------------------------------------------------------
         headphone_left : out std_logic;
         headphone_right : out std_logic;
         headphone_mic : in std_logic;

         ----------------------------------------------------------------------
         -- I2S speaker audio output
         ----------------------------------------------------------------------
         i2s_mclk : out std_logic;
         i2s_sync : out std_logic;
         i2s_speaker : out std_logic;
         i2s_bclk : out std_logic := '1'; -- Force 16 cycles per sample,
         
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

         sd2reset : out std_logic;
         sd2Clock : out std_logic;       -- (sclk_o)
         sd2MOSI : out std_logic;
         sd2MISO : in std_logic;
         
         ----------------------------------------------------------------------
         -- Flash RAM for holding config
         ----------------------------------------------------------------------
         QspiDB : inout unsigned(3 downto 0) := (others => 'Z');
         QspiCSn : out std_logic;

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

  -- XXX Plumb to VCC_FPGA shutdown
  signal power_down : std_logic;
  
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal restore_key : std_logic := '1';
  signal osk_toggle_key : std_logic := '1';
  signal joyswap_key : std_logic := '1';
  signal reset_out : std_logic := '1';
  signal cpu_game : std_logic := '1';
  signal cpu_exrom : std_logic := '1';
  
  signal ethclock : std_logic;
  signal cpuclock : std_logic;
  signal clock41 : std_logic;
  signal clock27 : std_logic;
  signal pixelclock : std_logic; -- i.e., clock81p
  signal clock162 : std_logic;
  signal clock200 : std_logic;
  signal clock270 : std_logic;
  signal clock325 : std_logic;

  signal modem1_uart_rx : std_logic;
  signal modem1_uart_tx : std_logic;
  signal modem1_debug_uart_rx : std_logic;
  signal modem1_debug_uart_tx : std_logic;
  signal modem2_uart_rx : std_logic;
  signal modem2_uart_tx : std_logic;
  signal modem2_debug_uart_rx : std_logic;
  signal modem2_debug_uart_tx : std_logic;
  signal wifi_uart_rx : std_logic;
  signal wifi_uart_tx : std_logic;
  signal bluetooth_uart_rx : std_logic;
  signal bluetooth_uart_tx : std_logic;
  signal lora1_uart_rx : std_logic;
  signal lora1_uart_tx : std_logic;
  signal lora2_uart_rx : std_logic;
  signal lora2_uart_tx : std_logic;
  
  signal slow_access_request_toggle : std_logic;
  signal slow_access_ready_toggle : std_logic;
  signal slow_access_write : std_logic;
  signal slow_access_address : unsigned(27 downto 0);
  signal slow_access_wdata : unsigned(7 downto 0);
  signal slow_access_rdata : unsigned(7 downto 0);

  signal slow_prefetched_address : unsigned(26 downto 0);
  signal slow_prefetched_data : unsigned(7 downto 0);
  signal slow_prefetched_request_toggle : std_logic;

  signal sector_buffer_mapped : std_logic;

  signal kbd_datestamp : unsigned(13 downto 0)  := to_unsigned(0,14);
  signal kbd_commit : unsigned(31 downto 0) := to_unsigned(0,32);

  signal porta_pins : std_logic_vector(7 downto 0) := (others => '1');
  signal portb_pins : std_logic_vector(7 downto 0) := (others => '1');

  signal cart_ctrl_dir : std_logic := 'Z';
  signal cart_haddr_dir : std_logic := 'Z';
  signal cart_laddr_dir : std_logic := 'Z';
  signal cart_data_dir : std_logic := 'Z';
  signal cart_phi2 : std_logic := 'Z';
  signal cart_dotclock : std_logic := 'Z';
  signal cart_reset : std_logic := 'Z';

  signal cart_nmi : std_logic := 'Z';
  signal cart_irq : std_logic := 'Z';
  signal cart_dma : std_logic := 'Z';

  signal cart_exrom : std_logic := 'Z';
  signal cart_ba : std_logic := 'Z';
  signal cart_rw : std_logic := 'Z';
  signal cart_roml : std_logic := 'Z';
  signal cart_romh : std_logic := 'Z';
  signal cart_io1 : std_logic := 'Z';
  signal cart_game : std_logic := 'Z';
  signal cart_io2 : std_logic := 'Z';

  signal cart_d : unsigned(7 downto 0) := (others => 'Z');
  signal cart_d_read : unsigned(7 downto 0) := (others => 'Z');
  signal cart_a : unsigned(15 downto 0) := (others => 'Z');

  ----------------------------------------------------------------------
  -- CBM floppy serial port
  ----------------------------------------------------------------------
  signal iec_clk_en : std_logic := 'Z';
  signal iec_data_en : std_logic := 'Z';
  signal iec_data_o : std_logic := 'Z';
  signal iec_reset : std_logic := 'Z';
  signal iec_clk_o : std_logic := 'Z';
  signal iec_data_i : std_logic := '1';
  signal iec_clk_i : std_logic := '1';
  signal iec_atn : std_logic := 'Z';
  signal smartcard_io_read : std_logic := '1';
  signal smartcard_clk_read : std_logic := '1';

  signal pal50_select : std_logic;
  
  -- Dummy signals for stub / not yet implemented interfaces
  signal eth_mdio : std_logic := '0';
  signal c65uart_rx : std_logic := '1';

  signal qspi_clock : std_logic;
  signal qspidb_oe : std_logic;
  signal qspidb_out : unsigned(3 downto 0);
  signal qspidb_in : unsigned(3 downto 0);

  signal fpga_done : std_logic := '1';
  
  signal expansionram_read : std_logic;
  signal expansionram_write : std_logic;
  signal expansionram_rdata : unsigned(7 downto 0);
  signal expansionram_wdata : unsigned(7 downto 0);
  signal expansionram_address : unsigned(26 downto 0);
  signal expansionram_data_ready_toggle : std_logic;
  signal expansionram_busy : std_logic;

  signal current_cache_line : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic := '0';
  signal expansionram_current_cache_line_next_toggle : std_logic := '0';

  signal i2c_joya_fire : std_logic;
  signal i2c_joya_left : std_logic;
  signal i2c_joya_right : std_logic;
  signal i2c_joya_up : std_logic;
  signal i2c_joya_down : std_logic;
  signal i2c_joyb_fire : std_logic;
  signal i2c_joyb_left : std_logic;
  signal i2c_joyb_right : std_logic;
  signal i2c_joyb_up : std_logic;
  signal i2c_joyb_down : std_logic;

  signal i2c_button2 : std_logic;
  signal i2c_button3 : std_logic;
  signal i2c_button4 : std_logic;
  signal i2c_black2 : std_logic;
  signal i2c_black3 : std_logic;
  signal i2c_black4 : std_logic;

  signal widget_matrix_col : std_logic_vector(7 downto 0) := (others => '1');

  signal hyper_addr : unsigned(18 downto 3) := (others => '0');
  signal hyper_request_toggle : std_logic := '0';
  signal hyper_data : unsigned(7 downto 0) := x"00";
  signal hyper_data_strobe : std_logic := '0';
  signal portp : unsigned(7 downto 0);
  signal portp_drive : unsigned(7 downto 0);
  
  signal pcm_clk : std_logic := '0';
  signal pcm_rst : std_logic := '1';
  signal pcm_clken : std_logic := '0';
  signal pcm_l : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(0,16));
  signal pcm_r : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(0,16));
  signal pcm_acr : std_logic := '0';
  signal pcm_n   : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(0,20));
  signal pcm_cts : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(0,20));

  signal v_vsync : std_logic;
  signal v_hdmi_hsync : std_logic;
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

  signal fpga_temperature : std_logic_vector(11 downto 0) := (others => '0');  
  
begin

--STARTUPE2:STARTUPBlock--7Series

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

             -- Place DONE pin under programmatic control
             USRDONEO=>fpga_done,--1-bit input: User DONE pin output control
             USRDONETS=>'1' --1-bit input: User DONE 3-state enable output DISABLE
             );
-- End of STARTUPE2_inst instantiation
  
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

      vga_rst => dvi_reset, -- active high reset
      vga_clk => clock27, -- VGA pixel clock
      vga_vs => v_vsync, -- active high vsync
      vga_hs => v_hdmi_hsync, -- active high hsync
      vga_de => hdmi_dataenable,   -- pixel enable

      vga_r => std_logic_vector(buffer_vgared),
      vga_g => std_logic_vector(buffer_vgagreen),
      vga_b => std_logic_vector(buffer_vgablue),

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

  fpgatemp0: entity work.fpgatemp
    generic map (DELAY_CYCLES => 480)
    port map (
      rst => '0',
      clk => cpuclock,
      temp => fpga_temperature);

  
  hyperram0: entity work.hyperram
    port map (
      pixelclock => pixelclock,
      clock163 => clock162,
      clock325 => clock325,

      -- XXX Debug by showing if expansion RAM unit is receiving requests or not
--      request_counter => led,

      viciv_addr => hyper_addr,
      viciv_request_toggle => hyper_request_toggle,
      viciv_data_out => hyper_data,
      viciv_data_strobe => hyper_data_strobe,

      -- reset => reset_out,
      address => expansionram_address,
      wdata => expansionram_wdata,
      read_request => expansionram_read,
      write_request => expansionram_write,
      rdata => expansionram_rdata,
      data_ready_toggle_out => expansionram_data_ready_toggle,
      busy => expansionram_busy,

      current_cache_line => current_cache_line,
      current_cache_line_address => current_cache_line_address,
      current_cache_line_valid => current_cache_line_valid,
      expansionram_current_cache_line_next_toggle  => expansionram_current_cache_line_next_toggle,

      hr_d => hr_d,
      hr_rwds => hr_rwds,
      hr_reset => hr_reset,
      hr_clk_p => hr_clk_p,
      hr_clk_n => hr_clk_n,

      hr_cs0 => hr_cs0,
      hr_cs1 => hr_cs1,

      hr2_d => open,
      hr2_rwds => open,
      hr2_reset => open,
      hr2_clk_p => open,
      hr2_clk_n => open
      );

  slow_devices0: entity work.slow_devices
    generic map (
      target => megaphoner4
      )
    port map (
      cpuclock => cpuclock,
      pixelclock => pixelclock,
      reset => reset_out,
      cpu_exrom => cpu_exrom,
      cpu_game => cpu_game,
      sector_buffer_mapped => sector_buffer_mapped,

      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_write => slow_access_write,
      slow_access_address => slow_access_address,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,

      ----------------------------------------------------------------------
      -- Expansion RAM interface (upto 127MB)
      ----------------------------------------------------------------------
      expansionram_read => expansionram_read,
      expansionram_write => expansionram_write,
      expansionram_rdata => expansionram_rdata,
      expansionram_wdata => expansionram_wdata,
      expansionram_address => expansionram_address,
      expansionram_data_ready_toggle => expansionram_data_ready_toggle,
      expansionram_busy => expansionram_busy,

      slow_prefetched_address => slow_prefetched_address,
      slow_prefetched_data => slow_prefetched_data,
      slow_prefetched_request_toggle => slow_prefetched_request_toggle,

      ----------------------------------------------------------------------
      -- Expansion/cartridge port
      ----------------------------------------------------------------------
      cart_ctrl_dir => cart_ctrl_dir,
      cart_haddr_dir => cart_haddr_dir,
      cart_laddr_dir => cart_laddr_dir,
      cart_data_dir => cart_data_dir,
      cart_phi2 => cart_phi2,
      cart_dotclock => cart_dotclock,
      cart_reset => cart_reset,

      cart_nmi => cart_nmi,
      cart_irq => cart_irq,
      cart_dma => cart_dma,

      cart_exrom => cart_exrom,
      cart_ba => cart_ba,
      cart_rw => cart_rw,
      cart_roml => cart_roml,
      cart_romh => cart_romh,
      cart_io1 => cart_io1,
      cart_game => cart_game,
      cart_io2 => cart_io2,

      cart_d_in => cart_d_read,
      cart_d => cart_d,
      cart_a => cart_a
      );

  machine0: entity work.machine
    generic map (cpu_frequency => 40500000,
                 target => megaphoner1,
                 hyper_installed => true -- For VIC-IV to know it can use
                                         -- hyperram for full-colour glyphs
                 )
    port map (
      pixelclock      => pixelclock,
      cpuclock        => cpuclock,
      uartclock       => cpuclock, -- Match CPU clock
      clock162 => clock162,
      clock200 => clock200,
      clock27 => clock27,
      clock50mhz      => ethclock,

      portp_out => portp,

      -- No IEC bus on this hardware, so no need to slow CPU down for it.
      iec_bus_active => '0',
      iec_srq_external => '1',

      kbd_datestamp => kbd_datestamp,
      kbd_commit => kbd_commit,

      btncpureset => '1',
      reset_out => reset_out,
      irq => irq,
      nmi => nmi,
      restore_key => restore_key,
      joyswap_key => joyswap_key,
      osk_toggle_key => osk_toggle_key,
      sector_buffer_mapped => sector_buffer_mapped,

      hyper_addr => hyper_addr,
      hyper_request_toggle => hyper_request_toggle,
      hyper_data => hyper_data,
      hyper_data_strobe => hyper_data_strobe,

      -- enable/disable cartridge with sw(8)
      cpu_exrom => '1',
      cpu_game => '1',

      power_down => power_down,

      pal50_select_out => pal50_select,

      -- Wire up a dummy caps_lock key on switch 8
      caps_lock_key => '1',

      fa_fire => i2c_joya_fire,
      fa_up => i2c_joya_up,
      fa_left => i2c_joya_left,
      fa_down => i2c_joya_down,
      fa_right => i2c_joya_right,

      fb_fire => i2c_joyb_fire,
      fb_up => i2c_joyb_up,
      fb_left => i2c_joyb_left,
      fb_down => i2c_joyb_down,
      fb_right => i2c_joyb_right,

      fa_potx => '0',
      fa_poty => '0',
      fb_potx => '0',
      fb_poty => '0',

      i2c_joya_fire => i2c_joya_fire,
      i2c_joya_up => i2c_joya_up,
      i2c_joya_down => i2c_joya_down,
      i2c_joya_left => i2c_joya_left,
      i2c_joya_right => i2c_joya_right,
      i2c_joyb_fire => i2c_joyb_fire,
      i2c_joyb_up => i2c_joyb_up,
      i2c_joyb_down => i2c_joyb_down,
      i2c_joyb_left => i2c_joyb_left,
      i2c_joyb_right => i2c_joyb_right,
      -- XXX Come up with better button assignments
      i2c_button2 => i2c_button2,
      i2c_button3 => i2c_button3,
      i2c_button4 => joyswap_key,
      i2c_black3 => osk_toggle_key,
      i2c_black4 => restore_key,

      f_index => '1',
      f_track0 => '1',
      f_writeprotect => '1',
      f_rdata => '1',
      f_diskchanged => '1',

      ----------------------------------------------------------------------
      -- CBM floppy serial port stub
      ----------------------------------------------------------------------
      iec_clk_en => iec_clk_en,
      iec_data_en => iec_data_en,
      iec_data_o => iec_data_o,
      iec_reset => iec_reset,
      iec_clk_o => iec_clk_o,
      iec_atn_o => iec_atn,
      iec_data_external => smartcard_io_read,
      iec_clk_external => smartcard_clk_read,

      no_hyppo => '0',

      vsync           => v_vsync,
      hdmi_hsync           => v_hdmi_hsync,      
      lcd_vsync => lcd_vsync,
      lcd_hsync => lcd_hsync,
      lcd_dataenable => lcd_display_enable,
      hdmi_dataenable => hdmi_dataenable,
      vgared(7 downto 0)          => buffer_vgared,
      vgagreen(7 downto 0)        => buffer_vgagreen,
      vgablue(7 downto 0)         => buffer_vgablue,

      porta_pins => porta_pins,
      portb_pins => portb_pins,
      keyleft => '0',
      keyup => '0',


      ---------------------------------------------------------------------------
      -- IO lines to the mems and headphone microphone
      ---------------------------------------------------------------------------
      micData0 => micData0,
      micData1 => micData1,
      micClk => micClk,
      headphone_mic => headphone_mic,

      ---------------------------------------------------------------------------
      -- IO lines to the ethernet controller (stub)
      ---------------------------------------------------------------------------
      eth_mdio => eth_mdio,
      eth_rxd => "11",
      eth_rxer => '1',
      eth_rxdv => '0',
      eth_interrupt => '1',

      -------------------------------------------------------------------------
      -- Lines for the SDcard interface itself
      -- sd is attached to both microSD slots of the SIM slots in parallel
      -- sd2 is Bodged up microSD on PMOD on spare FPGA pins during development
      -------------------------------------------------------------------------
      cs_bo => sd2Reset,
      sclk_o => sd2Clock,
      mosi_o => sd2MOSI,
      miso_i => sd2MISO,

      cs2_bo => sdreset,
      sclk2_o => sdClock,
      mosi2_o => sdMOSI,
      miso2_i => sdMISO,
      
      -- Accelerometer is connected via shared I2C bus, not a dedicated one
      -- so just dummy plumb this for now
      aclMISO => '1',
      aclInt1 => '0',
      aclInt2 => '0',

      -- Audio output
      ampPWM_l => headphone_left,
      ampPWM_r => headphone_right,

      i2s_master_clk => i2s_mclk,
      i2s_master_sync => i2s_sync,
      i2s_speaker_data_out => i2s_speaker,

      -- No nexys4 temperature sensor
      tmpInt => '0',
      tmpCT => '0',

      -- Touch screen
      touchSDA => touch_SDA,
      touchSCL => touch_scl,
      -- XXX LCD PWM needs to be relayed to the OrangeCrab to set the backlight
      -- brightness.
--      lcdpwm =>  lcd_pwm,

      -- XXX I2C bus is currently joined to that of the OrangeCrab. So don't
      -- drive it from ourside. 
--      i2c1sda => i2c1sda,
--      i2c1scl => i2c1scl,

      -- Bluetooth source, I2S slave
      -- XXX Connect when module has been designed
      pcm_bluetooth_clk_in => '1',
      pcm_bluetooth_sync_in => '1',
      pcm_bluetooth_data_in => '1',
      pcm_bluetooth_data_out => open,

      -- This is for modem as PCM master:
      pcm_modem_clk_in => modem1_pcm_clk_in,
      pcm_modem_sync_in => modem1_pcm_sync_in,

      pcm_modem1_data_out => modem1_pcm_data_out,
      pcm_modem1_data_in => modem1_pcm_data_in,

      ps2data =>      '1',
      ps2clock =>     '1',

      widget_matrix_col => (others => '1'),
      widget_restore => '1',
      widget_capslock => '1',
      widget_joya => (others => '1'),
      widget_joyb => (others => '1'),

      -- C65 UART
      uart_rx => c65uart_rx,
--      uart_tx => jclo(2),

      -- Buffered UARTs for cellular modems etc
      buffereduart_rx(0) => modem1_uart_rx,
      buffereduart_rx(1) => modem1_debug_uart_rx,
      buffereduart_rx(2) => modem2_uart_rx,
      buffereduart_rx(3) => modem2_debug_uart_rx,
      buffereduart_rx(4) => wifi_uart_rx,
      buffereduart_rx(5) => bluetooth_uart_rx,
      buffereduart_rx(6) => lora1_uart_rx,
      buffereduart_rx(7) => lora2_uart_rx,

      buffereduart_tx(0) => modem1_uart_tx,
      buffereduart_tx(1) => modem1_debug_uart_tx,
      buffereduart_tx(2) => modem2_uart_tx,
      buffereduart_tx(3) => modem2_debug_uart_tx,
      buffereduart_tx(4) => wifi_uart_tx,
      buffereduart_tx(5) => bluetooth_uart_tx,
      buffereduart_tx(6) => lora1_uart_tx,
      buffereduart_tx(7) => lora2_uart_tx,

      -- XXX Plumb to input from the orange crab FPGA
      buffereduart_ringindicate => (others => '0'),

      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_address => slow_access_address,
      slow_access_write => slow_access_write,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,

      cart_access_count => x"00",

      fpga_temperature => fpga_temperature,

      qspi_clock => qspi_clock,
      qspicsn => qspicsn,
      qspidb => qspidb_out,
      qspidb_in => qspidb_in,
      qspidb_oe => qspidb_oe,          
      
      sw => (others => '0'),
      btn => (others => '0'),

      UART_TXD => monitor_tx,
      RsRx => monitor_rx

      );


  
  lcd_display_enable <= lcd_dataenable;

  qspidb <= qspidb_out when qspidb_oe='1' else "ZZZZ";
  qspidb_in <= qspidb;
  
  process (clock27,cpuclock)
  begin
    
    if rising_edge(cpuclock) then

      fpga_mux1 <= monitor_rx;
--      monitor_tx <= fpga_mux2;
      
      -- Set active-high reset based on some method of input
      -- MEGAphone R4 PCB doesn't have a reset button, though.
      reset_high <= '0';
      
      -- Provide and clear single reset impulse to digital video output modules
      if reset_high='0' then
        dvi_reset <= '0';
      end if;

      portp_drive <= portp;
      
      dvi_select <= portp_drive(1);
      
    end if;
    
    -- LCD direct output
    lcd_dclk <= clock27;
    lcd_red <= buffer_vgared(7 downto 2);
    lcd_green <= buffer_vgagreen(7 downto 2);
    lcd_blue <= buffer_vgablue(7 downto 2);
    
  end process;

end Behavioral;
