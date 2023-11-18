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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity container is
  Port ( CLK_IN : STD_LOGIC;         
         reset_from_max10 : inout  STD_LOGIC;
--         irq : in  STD_LOGIC;
--         nmi : in  STD_LOGIC;
         
         ----------------------------------------------------------------------
         -- keyboard/joystick 
         ----------------------------------------------------------------------

         -- Interface for physical keyboard
         kb_io0 : inout std_logic;
         kb_io1 : out std_logic;
         kb_io2 : in std_logic;

         -- Direct joystick lines         
         fa_left : in std_logic;
         fa_right : in std_logic;
         fa_up : in std_logic;
         fa_down : in std_logic;
         fa_fire : in std_logic;
         fb_left : in std_logic;
         fb_right : in std_logic;
         fb_up : in std_logic;
         fb_down : in std_logic;
         fb_fire : in std_logic;
         paddle : in std_logic_vector(3 downto 0);
         paddle_drain : out std_logic := '0';

         -- 8 test points on the motherboard
         testpoint : inout unsigned(8 downto 1) := to_unsigned(0,8);
         
         ----------------------------------------------------------------------
         -- Expansion/cartridge port
         ----------------------------------------------------------------------
         cart_ctrl_dir : out std_logic;
         cart_haddr_dir : out std_logic;
         cart_laddr_dir : out std_logic;
         cart_data_en : out std_logic;
         cart_addr_en : out std_logic;
         cart_data_dir : out std_logic;
         cart_phi2 : out std_logic;
         cart_dotclock : out std_logic;
         cart_reset : out std_logic;

         cart_nmi : in std_logic;
         cart_irq : in std_logic;
         cart_dma : in std_logic;

         cart_exrom : inout std_logic := 'Z';
         cart_ba : inout std_logic := 'Z';
         cart_rw : inout std_logic := 'Z';
         cart_roml : inout std_logic := 'Z';
         cart_romh : inout std_logic := 'Z';
         cart_io1 : inout std_logic := 'Z';
         cart_game : inout std_logic := 'Z';
         cart_io2 : inout std_logic := 'Z';

         cart_d : inout unsigned(7 downto 0) := (others => 'Z');
         cart_a : inout unsigned(15 downto 0) := (others => 'Z');

         ----------------------------------------------------------------------
         -- HyperRAM as expansion RAM
         ----------------------------------------------------------------------
         hr_d : inout unsigned(7 downto 0);
         hr_rwds : inout std_logic;
         hr_reset : out std_logic;
         hr_clk_p : out std_logic;
         hr_cs0 : out std_logic;

         ----------------------------------------------------------------------
         -- CBM floppy serial port
         ----------------------------------------------------------------------
         iec_reset : out std_logic;
         iec_atn : out std_logic;
         iec_clk_en : out std_logic;
         iec_data_en : out std_logic;
         iec_srq_en : out std_logic;
         iec_clk_o : out std_logic;
         iec_data_o : out std_logic;
         iec_srq_o : out std_logic;
         iec_clk_i : in std_logic;
         iec_data_i : in std_logic;
         iec_srq_i : in std_logic;
         
         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vdac_clk : out std_logic;
         vdac_sync_n : out std_logic; -- tie low
         vdac_blank_n : out std_logic; -- tie high
         vsync : out  STD_LOGIC;
         hsync : out  STD_LOGIC;
         vgared : out  UNSIGNED (7 downto 0);
         vgagreen : out  UNSIGNED (7 downto 0);
         vgablue : out  UNSIGNED (7 downto 0);

         TMDS_data_p : out STD_LOGIC_VECTOR(2 downto 0);
         TMDS_data_n : out STD_LOGIC_VECTOR(2 downto 0);
         TMDS_clk_p : out STD_LOGIC;
         TMDS_clk_n : out STD_LOGIC;
         
         hdmi_scl : inout std_logic;
         hdmi_sda : inout std_logic;

         hpd_a : inout std_logic;
         ct_hpd : out std_logic := '1';
         ls_oe : out std_logic := '1';
         -- (i.e., when hsync, vsync both low?)

         ---------------------------------------------------------------------------
         -- IO lines to QSPI config flash (used so that we can update bitstreams)
         ---------------------------------------------------------------------------
         QspiDB : inout unsigned(3 downto 0) := (others => '0');
         QspiCSn : out std_logic;
                
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
--         eth_interrupt : in std_logic;
         eth_clock : out std_logic;
         
         -------------------------------------------------------------------------
         -- Lines for the SDcard interface itself
         -------------------------------------------------------------------------
--         sdReset : out std_logic := '0';  -- must be 0 to power SD controller (cs_bo)
--         sdClock : out std_logic;       -- (sclk_o)
--         sdMOSI : out std_logic;      
--         sdMISO : in  std_logic;

--         sd2reset : out std_logic;
--         sd2Clock : out std_logic;       -- (sclk_o)
--         sd2MOSI : out std_logic;
--         sd2MISO : in std_logic;

         -- Left and right headphone port audio
         pwm_l : out std_logic;
         pwm_r : out std_logic;
         
         -- PMOD connectors on the MEGA65 R2 main board
         p1lo : inout std_logic_vector(3 downto 0);
         p1hi : inout std_logic_vector(3 downto 0);
         p2lo : inout std_logic_vector(3 downto 0);
         p2hi : inout std_logic_vector(3 downto 0);
         
         ----------------------------------------------------------------------
         -- Floppy drive interface
         ----------------------------------------------------------------------
         f_density : out std_logic := '1';
         f_motora : out std_logic := '1';
         f_motorb : out std_logic := '1';
         f_selecta : out std_logic := '1';
         f_selectb : out std_logic := '1';
         f_stepdir : out std_logic := '1';
         f_step : out std_logic := '1';
         f_wdata : out std_logic := '1';
         f_wgate : out std_logic := '1';
         f_side1 : out std_logic := '1';
         f_index : in std_logic;
         f_track0 : in std_logic;
         f_writeprotect : in std_logic;
         f_rdata : in std_logic;
         f_diskchanged : in std_logic;

         led : inout std_logic;

         ----------------------------------------------------------------------
         -- I2S speaker audio output
         ----------------------------------------------------------------------
         i2s_mclk : out std_logic;
         i2s_sync : out std_logic;
         i2s_speaker : out std_logic;
         i2s_bclk : out std_logic := '1'; -- Force 16 cycles per sample,
         i2s_sd : out std_logic;
         
         ----------------------------------------------------------------------
         -- I2C on-board peripherals
         ----------------------------------------------------------------------
         fpga_sda : inout std_logic;
         fpga_scl : inout std_logic;         

         ----------------------------------------------------------------------
         -- Comms link to MAX10 FPGA
         ----------------------------------------------------------------------
         max10_tx : in std_logic;
         max10_rx : out std_logic := '1';
         
         ----------------------------------------------------------------------
         -- Serial monitor interface
         ----------------------------------------------------------------------
         UART_TXD : out std_logic;
         RsRx : in std_logic
         
         );
end container;

architecture Behavioral of container is

  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal irq_combined : std_logic := '1';
  signal nmi_combined : std_logic := '1';
  signal irq_out : std_logic := '1';
  signal nmi_out : std_logic := '1';
  signal reset_out : std_logic := '1';
  signal cpu_game : std_logic := '1';
  signal cpu_exrom : std_logic := '1';

  -- Communications with the MAX10 FPGA
  signal btncpureset : std_logic := '1';
  signal j21ddr : std_logic_vector(11 downto 0) := (others => '0');
  signal j21out : std_logic_vector(11 downto 0) := (others => '0');
  signal j21in : std_logic_vector(11 downto 0) := (others => '0');
  signal max10_fpga_commit : unsigned(31 downto 0) := (others => '0');
  signal max10_fpga_date : unsigned(15 downto 0) := (others => '0');
  signal max10_reset_out : std_logic := '1';
  signal fpga_done : std_logic := '1';
  signal sw : std_logic_vector(15 downto 0) := (others => '0');
  signal dipsw : std_logic_vector(4 downto 0) := (others => '0');
  
  signal ethclock : std_logic;
  signal cpuclock : std_logic;
  signal clock27 : std_logic;
  signal pixelclock : std_logic; -- i.e., clock81p
  signal clock100 : std_logic;
  signal clock163 : std_logic;
  signal clock200 : std_logic;
  signal clock270 : std_logic;
  signal clock325 : std_logic;

  -- XXX Actually connect to new keyboard
  signal restore_key : std_logic := '1';
  -- XXX Note that left and up are active HIGH!
  -- XXX Plumb these into the MEGA65R2 keyboard protocol receiver
  signal keyleft : std_logic := '0';
  signal keyup : std_logic := '0';
  -- On the R2, we don't use the "real" keyboard interface, but instead the
  -- widget board interface, so just have these as dummy all-high place holders
  signal column : std_logic_vector(8 downto 0) := (others => '1');
  signal row : std_logic_vector(7 downto 0) := (others => '1');
  
  
  signal segled_counter : unsigned(31 downto 0) := (others => '0');

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

  signal pmoda_dummy :  std_logic_vector(7 downto 0) := (others => '1');

  signal lcd_dataenable : std_logic;
  signal hdmi_dataenable : std_logic;

  signal hdmired : UNSIGNED (7 downto 0);
  signal hdmigreen : UNSIGNED (7 downto 0);
  signal hdmiblue : UNSIGNED (7 downto 0);
  signal hdmi_int : std_logic;
  
  -- XXX We should read the real temperature and feed this to the DDR controller
  -- so that it can update timing whenever the temperature changes too much.
  signal fpga_temperature : std_logic_vector(11 downto 0) := (others => '0');

  signal fa_left_drive : std_logic;
  signal fa_right_drive : std_logic;
  signal fa_up_drive : std_logic;
  signal fa_down_drive : std_logic;
  signal fa_fire_drive : std_logic;
  
  signal fb_left_drive : std_logic;
  signal fb_right_drive : std_logic;
  signal fb_up_drive : std_logic;
  signal fb_down_drive : std_logic;
  signal fb_fire_drive : std_logic;

  signal fa_potx : std_logic;
  signal fa_poty : std_logic;
  signal fb_potx : std_logic;
  signal fb_poty : std_logic;
  signal pot_drain : std_logic;

  signal pot_via_iec : std_logic;
  
  signal iec_clk_en_drive : std_logic;
  signal iec_data_en_drive : std_logic;
  signal iec_srq_en_drive : std_logic;
  signal iec_data_o_drive : std_logic;
  signal iec_reset_drive : std_logic;
  signal iec_clk_o_drive : std_logic;
  signal iec_srq_o_drive : std_logic;
  signal iec_data_i_drive : std_logic;
  signal iec_clk_i_drive : std_logic;
  signal iec_srq_i_drive : std_logic;
  signal iec_atn_drive : std_logic;
  signal last_iec_atn_drive : std_logic;
  signal iec_bus_active : std_logic := '0';

  signal pwm_l_drive : std_logic;
  signal pwm_r_drive : std_logic;

  signal flopled_drive : std_logic;
  signal flopmotor_drive : std_logic;

  signal joy3 : std_logic_vector(4 downto 0);
  signal joy4 : std_logic_vector(4 downto 0);

  signal cart_access_count : unsigned(7 downto 0);

  signal widget_matrix_col_idx : integer range 0 to 8 := 5;
  signal widget_matrix_col : std_logic_vector(7 downto 0);
  signal widget_restore : std_logic := '1';
  signal widget_capslock : std_logic := '0';
  signal widget_joya : std_logic_vector(4 downto 0);
  signal widget_joyb : std_logic_vector(4 downto 0);

  signal fastkey : std_logic;
  
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

  signal test_pattern_enable : std_logic := '1';
  signal pal50 : std_logic := '1';
  signal vga60 : std_logic := '0';

  signal interlace : std_logic := '1';
  signal mono : std_logic := '1';
    
  signal pattern_r : unsigned(7 downto 0);
  signal pattern_g : unsigned(7 downto 0);
  signal pattern_b: unsigned(7 downto 0);
  signal pattern_de : std_logic;
  signal pattern_de_n : std_logic;
  signal pattern_hsync : std_logic;
  signal pattern_vsync : std_logic;

  signal luma : unsigned(7 downto 0);
  signal chroma : unsigned(7 downto 0);
  signal composite : unsigned(7 downto 0);
  
  signal zero : std_logic := '0';
  signal one : std_logic := '1';  

  signal pixel_strobe : std_logic := '0';
  signal x_zero : std_logic := '0';
  signal y_zero : std_logic := '0';
  
  signal audio_left : std_logic_vector(19 downto 0);
  signal audio_right : std_logic_vector(19 downto 0);
  signal audio_left_slow : std_logic_vector(19 downto 0);
  signal audio_right_slow : std_logic_vector(19 downto 0);
  signal h_audio_left : std_logic_vector(19 downto 0);
  signal h_audio_right : std_logic_vector(19 downto 0);
  signal spdif_44100 : std_logic;
  
  signal porto : unsigned(7 downto 0);
  signal portp : unsigned(7 downto 0) := x"00";

  signal qspi_clock : std_logic;

  signal disco_led_en : std_logic := '0';
  signal disco_led_val : unsigned(7 downto 0);
  signal disco_led_id : unsigned(7 downto 0);

  signal hyper_addr : unsigned(18 downto 3) := (others => '0');
  signal hyper_request_toggle : std_logic := '0';
  signal hyper_data : unsigned(7 downto 0) := x"00";
  signal hyper_data_strobe : std_logic := '0';

  signal fm_left : signed(15 downto 0);
  signal fm_right : signed(15 downto 0);

  constant clock_frequency : integer := 40500000;
  constant target_sample_rate : integer := 48000;
  signal audio_counter : integer := 0;
  signal sample_ready_toggle : std_logic := '0';
  signal audio_counter_interval : unsigned(25 downto 0) := to_unsigned(4*clock_frequency/target_sample_rate,26);
  signal acr_counter : integer range 0 to 12288 := 0;
  
  signal pcm_clk : std_logic := '0';
  signal pcm_rst : std_logic := '1';
  signal pcm_clken : std_logic := '0';
  signal pcm_l : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(0,16));
  signal pcm_r : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(0,16));
  signal pcm_acr : std_logic := '0';
  signal pcm_n   : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(0,20));
  signal pcm_cts : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(0,20));
  
  
  signal hdmi_is_progressive : boolean := true;
  signal hdmi_is_pal : boolean := true;
  signal hdmi_is_30khz : boolean := true;
  signal hdmi_is_limited : boolean := true;
  signal hdmi_is_widescreen : boolean := true;

  signal vga_blank : std_logic := '0';

  signal tmds : slv_9_0_t(0 to 2);

  signal reset_high : std_logic := '0';

  signal kbd_datestamp : unsigned(13 downto 0);
  signal kbd_commit : unsigned(31 downto 0);

  signal dvi_select : std_logic := '0';

  signal ascii_key : unsigned(7 downto 0);
  signal ascii_key_valid : std_logic := '0';
  signal bucky_key : std_logic_vector(6 downto 0);
  signal capslock_combined : std_logic;
  signal key_caps : std_logic := '0';
  signal key_restore : std_logic := '0';
  signal key_up : std_logic := '0';
  signal key_left : std_logic := '0';

  signal matrix_segment_num : std_logic_vector(7 downto 0);
  signal porta_pins : std_logic_vector(7 downto 0) := (others => '1');

  signal key_count : unsigned(15 downto 0) := to_unsigned(0,16);

  signal debug_backward : std_logic := '0';
  signal debug_backward_int : std_logic := '0';
  signal debug_forward : std_logic := '0';
  signal debug_forward_int : std_logic := '0';
  
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
               clock270  => clock270,
               clock163  => clock163,   --  162.5   MHz
               clock200  => clock200,   --  200     MHz
               clock325  => clock325    --  325     MHz
               );

    -- Feed audio into digital video feed
    AUDIO_TONE: entity work.audio_out_test_tone
      generic map (
        -- You have to update audio_clock if you change this
        fref        => 100.0
        )
      port map (
            select_44100 => portp(3),
            ref_rst   => reset_high,
            ref_clk   => CLK_IN,
            pcm_rst   => pcm_rst,
            pcm_clk   => pcm_clk,
            pcm_clken => pcm_clken,

            audio_left_slow => audio_left_slow,
            audio_right_slow => audio_right_slow,
            sample_ready_toggle => sample_ready_toggle,
            
            pcm_l     => pcm_l,
            pcm_r     => pcm_r
        );
  
    pcm_n <= std_logic_vector(to_unsigned(6144,pcm_n'length));
    pcm_cts <= std_logic_vector(to_unsigned(27000,pcm_cts'length));
    
    hdmi0: entity work.vga_to_hdmi
      port map (
        select_44100 => portp(3),
        -- Disable HDMI-style audio if one
        -- BUT allow dipswitch 2 of S3 on the MEGA65 R3 main board to INVERT
        -- this behaviour
        dvi => dvi_select, 
        vic => std_logic_vector(to_unsigned(17,8)), -- CEA/CTA VIC 17=576p50 PAL, 2 = 480p60 NTSC
        aspect => "01", -- 01=4:3, 10=16:9
        pix_rep => '0', -- no pixel repetition
        vs_pol => '1',  -- 1=active high
        hs_pol => '1',

        vga_rst => reset_high, -- active high reset
        vga_clk => clock27, -- VGA pixel clock
        vga_vs => pattern_vsync, -- active high vsync
        vga_hs => pattern_hsync, -- active high hsync
        vga_de => pattern_de,   -- pixel enable
        vga_r => std_logic_vector(pattern_r),
        vga_g => std_logic_vector(pattern_g),
        vga_b => std_logic_vector(pattern_b),

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
                rst     => reset_high,
                clk     => clock27,
                clk_x10  => clock270,
                d       => tmds(i),
                out_p   => TMDS_data_p(i),
                out_n   => TMDS_data_n(i)
            );
    end generate GEN_HDMI_DATA;
    HDMI_CLK: entity work.serialiser_10to1_selectio
        port map (
            rst     => reset_high,
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
  
  kbd0: entity work.mega65kbd_to_matrix
    port map (
      cpuclock => cpuclock,

      disco_led_en => disco_led_en,
      disco_led_id => disco_led_id,
      disco_led_val => disco_led_val,
      
      powerled => '1',
      flopled0 => flopled_drive,
      flopled2 => flopled_drive,
      flopledsd => flopled_drive,
      flopmotor => flopmotor_drive,
            
      kio8 => kb_io0,
      kio9 => kb_io1,
      kio10 => kb_io2,

      kbd_datestamp => kbd_datestamp,
      kbd_commit => kbd_commit,
      
      matrix_col => widget_matrix_col,
      matrix_col_idx => widget_matrix_col_idx,
      restore => widget_restore,
      fastkey_out => fastkey,
      capslock_out => widget_capslock,
      upkey => keyup,
      leftkey => keyleft
      
      );    
  
  max10: entity work.max10
    port map (
      pixelclock      => pixelclock,
      cpuclock        => cpuclock,

--      led => led,
      
      max10_clkandsync => reset_from_max10,
      max10_rx => max10_rx,
      max10_tx => max10_tx,

      max10_fpga_commit => max10_fpga_commit,
      max10_fpga_date => max10_fpga_date,

      reset_button => max10_reset_out,
      dipsw => dipsw,
      j21in => j21in,
      j21out => j21out,
      j21ddr => j21ddr
      );

  block5: block
  begin
    kc0 : entity work.keyboard_complex
      port map (
      reset_in => '1',
      matrix_mode_in => '0',
      viciv_frame_indicate => '0',

      matrix_disable_modifiers => '0',
      matrix_segment_num => matrix_segment_num,
--      matrix_segment_out => matrix_segment_out,
      suppress_key_glitches => '0',
      suppress_key_retrigger => '0',
    
      scan_mode => "11",
      scan_rate => x"FF",

      -- MEGA65 keyboard acts as though it were a widget board
    widget_disable => '0',
    ps2_disable => '0',
    joyreal_disable => '0',
    joykey_disable => '0',
    physkey_disable => '0',
    virtual_disable => '0',

      joyswap => '0',
      
      joya_rotate => '0',
      joyb_rotate => '0',
      
    cpuclock       => cpuclock,
--    restore_out => restore_nmi,
    keyboard_restore => key_restore,
    keyboard_capslock => key_caps,
    key_left => key_left,
    key_up => key_up,

    key1 => (others => '1'),
    key2 => (others => '1'),
    key3 => (others => '1'),

    touch_key1 => (others => '1'),
    touch_key2 => (others => '1'),

--    keydown1 => osk_key1,
--    keydown2 => osk_key2,
--    keydown3 => osk_key3,
--    keydown4 => osk_key4,
      
--    hyper_trap_out => hyper_trap,
--    hyper_trap_count => hyper_trap_count,
--    restore_up_count => restore_up_count,
--    restore_down_count => restore_down_count,
--    reset_out => reset_out,
    ps2clock       => '1',
    ps2data        => '1',
--    last_scan_code => last_scan_code,
--    key_status     => seg_led(1 downto 0),
    porta_in       => (others => '1'),
    portb_in       => (others => '1'),
--    porta_out      => cia1porta_in,
--    portb_out      => cia1portb_in,
    porta_ddr      => (others => '1'),
    portb_ddr      => (others => '1'),

    joya(4) => '1',
    joya(0) => '1',
    joya(2) => '1',
    joya(1) => '1',
    joya(3) => '1',
    
    joyb(4) => '1',
    joyb(0) => '1',
    joyb(2) => '1',
    joyb(1) => '1',
    joyb(3) => '1',
    
--    key_debug_out => key_debug,
  
    porta_pins => porta_pins, 
    portb_pins => (others => '1'),

--    speed_gate => speed_gate,
--    speed_gate_enable => speed_gate_enable,

    capslock_out => capslock_combined,
--    keyboard_column8_out => keyboard_column8_out,
    keyboard_column8_select_in => '0',

    widget_matrix_col_idx => widget_matrix_col_idx,
    widget_matrix_col => widget_matrix_col,
      widget_restore => '1',
      widget_capslock => '1',
    widget_joya => (others => '1'),
    widget_joyb => (others => '1'),
      
      
    -- remote keyboard input via ethernet
      eth_keycode_toggle => '0',
      eth_keycode => (others => '0'),

    -- remote 
--    eth_keycode_toggle => key_scancode_toggle,
--    eth_keycode => key_scancode,

    -- ASCII feed via hardware keyboard scanner
    ascii_key => ascii_key,
    ascii_key_valid => ascii_key_valid,
    bucky_key => bucky_key(6 downto 0)
    
    );
  end block;

  uart_tx0: entity work.UART_TX_CTRL
    port map (
      send    => ascii_key_valid,
      BIT_TMR_MAX => to_unsigned((40500000/2000000) - 1,24),
      clk     => cpuclock,
      data    => ascii_key,
--      ready   => tx0_ready,
      uart_tx => UART_TXD);

  
  pixel0: entity work.pixel_driver
    port map (
      clock81 => pixelclock, -- 80MHz
      clock27 => clock27,

      cpuclock => cpuclock,

      debug_forward => debug_forward,
      debug_backward => debug_backward,
      
      pixel_strobe_out => pixel_strobe,
      
      -- Configuration information from the VIC-IV
      hsync_invert => one,
      vsync_invert => one,
      pal50_select => pal50,
      vga60_select => vga60,
      test_pattern_enable => test_pattern_enable,

      interlace_mode => interlace,
      mono_mode => mono,
      
      -- Framing information for VIC-IV
      x_zero => x_zero,     
      y_zero => y_zero,     

      -- Show simple purple screen when test pattern is off
      red_i => to_unsigned(255,8),
      green_i => to_unsigned(0,8),
      blue_i => to_unsigned(255,8),

      -- The pixel for direct output to VGA pins
      -- It is clocked at the correct pixel
      red_no => pattern_r,
      green_no => pattern_g,
      blue_no => pattern_b,      

--      red_o => panelred,
--      green_o => panelgreen,
--      blue_o => panelblue,

      luma => luma,
      chroma => chroma,
      composite => composite,
      
      hsync => pattern_hsync,
      vsync => pattern_vsync,  -- for HDMI
--      vga_hsync => vga_hsync,      -- for VGA          

      -- And the variations on those signals for the LCD display
--      lcd_hsync => lcd_hsync,               
--      lcd_vsync => lcd_vsync,
      narrow_dataenable => pattern_de
--      lcd_inletterbox => lcd_inletterbox,
--      vga_inletterbox => vga_inletterbox

      );

  expansionboard0: entity work.r3_expansion
    port map (
      cpuclock => cpuclock,
      clock27 => clock27,
      clock81 => pixelclock,
      clock270 => clock270,

      p1lo => p1lo,
      p1hi => p1hi,
      p2lo => p2lo,
      p2hi => p2hi,

      -- XXX The first revision of the R3 expansion board has the video
      -- connector mis-wired.  So we put luma out everywhere, so that
      -- we can still pick it up on a normally wired video cable
      luma => luma,
      chroma => luma,
      composite => luma,
      audio => luma
      
      );
  
  -- BUFG on ethernet clock to keep the clock nice and strong
  ethbufg0:
  bufg port map ( I => ethclock,
                  O => eth_clock);

  -- XXX debug: export exactly 1KHz rate out to the LED for monitoring 
--  led <= pcm_acr;  
  
  process (pixelclock,cpuclock,pcm_clk) is
  begin
    vdac_sync_n <= '0';  -- no sync on green
    vdac_blank_n <= '1'; -- was: not (v_hsync or v_vsync); 

    -- VGA output at full pixel clock
    vdac_clk <= pixelclock;

    pattern_de_n <= not pattern_de;
    
    -- Use both real and cartridge IRQ and NMI signals
    irq_combined <= irq and irq_out;
    nmi_combined <= nmi and nmi_out;

    if rising_edge(pcm_clk) then
      -- Generate 1KHz ACR pulse train from 12.288MHz
      if acr_counter /= (12288 - 1) then
        acr_counter <= acr_counter + 1;
        pcm_acr <= '0';
      else
        pcm_acr <= '1';
        acr_counter <= 0;
      end if;
    end if;
    
    -- Drive most ports, to relax timing
    if rising_edge(cpuclock) then      

      if ascii_key_valid='1' then
        case ascii_key is
          when x"31" => pal50 <= '1';
          when x"32" => pal50 <= '0';
          when x"33" => test_pattern_enable <= '1';
          when x"34" => test_pattern_enable <= '0';
          when x"35" => interlace <= '1';
          when x"36" => interlace <= '0';
          when x"37" => mono <= '1';
          when x"38" => mono <= '0';
          when x"39" =>
            debug_backward <= not debug_backward_int;
            debug_backward_int <= not debug_backward_int;
          when x"30" =>
            debug_forward <= not debug_forward_int;
            debug_forward_int <= not debug_forward_int;
          when others => null;
        end case;        
      end if;                        
      
      dvi_select <= portp(1) xor dipsw(1);
      
--      reset_high <= not btncpureset;

      btncpureset <= max10_reset_out;
      
      -- We need to pass audio to 12.288 MHz clock domain.
      -- Easiest way is to hold samples constant for 16 ticks, and
      -- have a slow toggle
      -- At 40.5MHz and 48KHz sample rate, we have a ratio of 843.75
      -- Thus we need to calculate the remainder, so that we can get the
      -- sample rate EXACTLY 48KHz.
      -- Otherwise we end up using 844, which gives a sample rate of
      -- 40.5MHz / 844 = 47.986KHz, which might just be enough to throw
      -- some monitors out, since it means that the CTS / N rates will
      -- be wrong.
      -- (Or am I just chasing my tail, because this is only used to set the
      -- rate at which we LATCH the samples?)
      if audio_counter < to_integer(audio_counter_interval) then
        audio_counter <= audio_counter + 4;
      else
        audio_counter <= audio_counter - to_integer(audio_counter_interval);
        sample_ready_toggle <= not sample_ready_toggle;
        audio_left_slow <= h_audio_left;
        audio_right_slow <= h_audio_right;
--        led <= not led;
      end if;

--      reset_high <= not btncpureset;
      
--      led <= cart_exrom;
--      led <= flopled_drive;
      
      fa_left_drive <= fa_left;
      fa_right_drive <= fa_right;
      fa_up_drive <= fa_up;
      fa_down_drive <= fa_down;
      fa_fire_drive <= fa_fire;  
      fb_left_drive <= fb_left;
      fb_right_drive <= fb_right;
      fb_up_drive <= fb_up;
      fb_down_drive <= fb_down;
      fb_fire_drive <= fb_fire;  

      -- The simple output-only IEC lines we just drive
      iec_reset <= iec_reset_drive;
      iec_atn <= not iec_atn_drive;
      
      -- The active-high EN lines enable the IEC output drivers.
      -- We need to invert the signal, so that if a signal from CIA
      -- is high, we drive the IEC pin low. Else we let the line
      -- float high.  We have external pull-ups, so shouldn't use them
      -- in the FPGA.  This also means we can leave the input line to
      -- the output drivers set a 0, as we never "send" a 1 -- only relax
      -- and let it float to 1.
      iec_srq_o <= '0';
      iec_clk_o <= '0';
      iec_data_o <= '0';

      -- Reading pins is simple
      iec_srq_i_drive <= iec_srq_i;
      iec_clk_i_drive <= iec_clk_i;
      iec_data_i_drive <= iec_data_i;

--      last_iec_atn_drive <= iec_atn_drive;
--      if (iec_srq_i_drive /= iec_srq_i)
--        or (iec_clk_i_drive /= iec_clk_i)
--        or (iec_data_i_drive /= iec_data_i)
--        or (iec_atn_drive /= last_iec_atn_drive) then
      if ((iec_srq_o_drive and iec_srq_en_drive) = '1')
        or ((iec_clk_o_drive and iec_clk_en_drive) = '1')
        or ((iec_data_o_drive and iec_data_en_drive) = '1') then
        iec_bus_active <= '1';
      else
        iec_bus_active <= '0';
      end if;
      
      
      -- Finally, because we have the output value of 0 hard-wired
      -- on the output drivers, we need only gate the EN line.
      -- But we only do this if the DDR is set to output
      iec_srq_en <= iec_srq_o_drive and iec_srq_en_drive;
      iec_clk_en <= iec_clk_o_drive and iec_clk_en_drive;
      iec_data_en <= iec_data_o_drive and iec_data_en_drive;

      -- Connect up real C64-compatible paddle ports
      paddle_drain <= pot_drain;
      fa_potx <= paddle(0);
      fa_poty <= paddle(1);
      fb_potx <= paddle(2);
      fb_poty <= paddle(3);

      pwm_l <= pwm_l_drive;
      pwm_r <= pwm_r_drive;
      
    end if;

    -- @IO:GS $D61A.7 SYSCTL:AUDINV Invert digital video audio sample values
    -- @IO:GS $D61A.4 SYSCTL:LED Control LED next to U1 on mother board
    -- @IO:GS $D61A.3 SYSCTL:AUD48K Select 48KHz or 44.1KHz digital video audio sample rate
    -- @IO:GS $D61A.2 SYSCTL:AUDDBG Visualise audio samples (DEBUG)
    -- @IO:GS $D61A.1 SYSCTL:DVI Control digital video as DVI (disables audio)
    -- @IO:GS $D61A.0 SYSCTL:AUDMUTE Mute digital video audio (MEGA65 R2 only)


    
    h_audio_right <= audio_right;
    h_audio_left <= audio_left;
    -- toggle signed/unsigned audio flipping
    if portp(7)='1' then
      h_audio_right(19) <= not audio_right(19);
      h_audio_left(19) <= not audio_left(19);
    end if;
    -- LED on main board 
--    led <= portp(4);
    led <= dipsw(3);

    if rising_edge(pixelclock) then
      hsync <= pattern_hsync;
      vsync <= pattern_vsync;
      vgared <= pattern_r;
      vgagreen <= pattern_g;
      vgablue <= pattern_b;
    end if;

  end process;    
  
end Behavioral;
