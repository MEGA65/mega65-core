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
         kb_io0 : out std_logic;
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

         -- Optional 2nd hyperram in trap-door slot
         hr2_d : inout unsigned(7 downto 0);
         hr2_rwds : inout std_logic;
         hr2_reset : out std_logic;
         hr2_clk_p : out std_logic;
         hr2_cs0 : out std_logic;
         
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
         sdReset : out std_logic := '0';  -- must be 0 to power SD controller (cs_bo)
         sdClock : out std_logic;       -- (sclk_o)
         sdMOSI : out std_logic;      
         sdMISO : in  std_logic;

         sd2reset : out std_logic;
         sd2Clock : out std_logic;       -- (sclk_o)
         sd2MOSI : out std_logic;
         sd2MISO : in std_logic;

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
  signal clock41 : std_logic;
  signal clock27 : std_logic;
  signal pixelclock : std_logic; -- i.e., clock81p
  signal clock81n : std_logic;
  signal clock100 : std_logic;
  signal clock135p : std_logic;
  signal clock135n : std_logic;
  signal clock162 : std_logic;
  signal clock200 : std_logic;
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

  signal v_vga_hsync : std_logic;
  signal v_hdmi_hsync : std_logic;
  signal v_vsync : std_logic;
  signal v_red : unsigned(7 downto 0);
  signal v_green : unsigned(7 downto 0);
  signal v_blue : unsigned(7 downto 0);
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

  signal widget_matrix_col_idx : integer range 0 to 8 := 0;
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
  signal expansionram_data_ready_strobe : std_logic;
  signal expansionram_busy : std_logic;

  signal current_cache_line : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic := '0';
  signal expansionram_current_cache_line_next_toggle : std_logic := '0';

  
  signal audio_left : std_logic_vector(19 downto 0);
  signal audio_right : std_logic_vector(19 downto 0);
  signal audio_left_slow : std_logic_vector(19 downto 0);
  signal audio_right_slow : std_logic_vector(19 downto 0);
  signal h_audio_left : std_logic_vector(19 downto 0);
  signal h_audio_right : std_logic_vector(19 downto 0);
  signal spdif_44100 : std_logic;
  
  signal porto : unsigned(7 downto 0);
  signal portp : unsigned(7 downto 0);

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

  signal reset_high : std_logic := '1';

  signal kbd_datestamp : unsigned(13 downto 0);
  signal kbd_commit : unsigned(31 downto 0);

  signal dvi_select : std_logic := '0';
  
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
               clock81n  => clock81n,   --   81     MHz
               clock100  => clock100,   --  100     MHz
               clock135p => clock135p,  --  135     MHz
               clock135n => clock135n,  --  135     MHz
               clock163  => clock162,   --  162.5   MHz
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
        vga_vs => v_vsync, -- active high vsync
        vga_hs => v_hdmi_hsync, -- active high hsync
        vga_de => hdmi_dataenable,   -- pixel enable
        vga_r => std_logic_vector(v_red),
        vga_g => std_logic_vector(v_green),
        vga_b => std_logic_vector(v_blue),

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
                clk_x5  => clock135p,
                d       => tmds(i),
                out_p   => TMDS_data_p(i),
                out_n   => TMDS_data_n(i)
            );
    end generate GEN_HDMI_DATA;
    HDMI_CLK: entity work.serialiser_10to1_selectio
        port map (
            rst     => reset_high,
            clk     => clock27,
            clk_x5  => clock135p,
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
      flopled => flopled_drive,
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

      led => led,
      
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

  m0:
    if true generate
      machine0: entity work.machine_container
        generic map (cpu_frequency => 40500000,
                     target => mega65r3
                     )                 
        port map (
          pixelclock      => pixelclock,
          cpuclock        => cpuclock,
          uartclock       => cpuclock, -- Match CPU clock
          clock162 => clock162,
          clock100 => clock100,
          clock200 => clock200,
          clock27 => clock27,
          clock50mhz      => ethclock,
          
          hyper_addr => hyper_addr,
          hyper_request_toggle => hyper_request_toggle,
          hyper_data => hyper_data,
          hyper_data_strobe => hyper_data_strobe,
          
          fast_key => fastkey,
          
          j21in => j21in,
          j21out => j21out,
          
          j21ddr => j21ddr,
          
          max10_fpga_commit => max10_fpga_commit,
          max10_fpga_date => max10_fpga_date,
          
          kbd_datestamp => kbd_datestamp,
          kbd_commit => kbd_commit,
          
          btncpureset => btncpureset,
          reset_out => reset_out,
          irq => irq_combined,
          nmi => nmi_combined,
          restore_key => restore_key,
          sector_buffer_mapped => sector_buffer_mapped,
          
          qspi_clock => qspi_clock,
          qspicsn => qspicsn,
          qspidb => qspidb,
          
          joy3 => joy3,
          joy4 => joy4,
          
          fm_left => fm_left,
          fm_right => fm_right,
          
          no_hyppo => '0',
          
          vsync           => v_vsync,
          vga_hsync       => v_vga_hsync,
          hdmi_hsync       => v_hdmi_hsync,
          vgared          => v_red,
          vgagreen        => v_green,
          vgablue         => v_blue,
          hdmi_sda        => hdmi_sda,
          hdmi_scl        => hdmi_scl,
          hpd_a           => hpd_a,
          lcd_dataenable => lcd_dataenable,
          hdmi_dataenable =>  hdmi_dataenable,
          
          ----------------------------------------------------------------------
          -- CBM floppy  serial port
          ----------------------------------------------------------------------
          iec_clk_en => iec_clk_en_drive,
          iec_data_en => iec_data_en_drive,
          iec_srq_en => iec_srq_en_drive,
          iec_data_o => iec_data_o_drive,
          iec_reset => iec_reset_drive,
          iec_clk_o => iec_clk_o_drive,
          iec_srq_o => iec_srq_o_drive,
          iec_data_external => iec_data_i_drive,
          iec_clk_external => iec_clk_i_drive,
          iec_srq_external => iec_srq_i_drive,
          iec_atn_o => iec_atn_drive,
          iec_bus_active => iec_bus_active,     
          
--      buffereduart_rx => '1',
          buffereduart_ringindicate => (others => '0'),
          
          porta_pins => column(7 downto 0),
          portb_pins => row(7 downto 0),
          keyboard_column8 => column(8),
          caps_lock_key => '1',
          keyleft => keyleft,
          keyup => keyup,
          
          fa_fire => fa_fire_drive,
          fa_up => fa_up_drive,
          fa_left => fa_left_drive,
          fa_down => fa_down_drive,
          fa_right => fa_right_drive,
          
          fb_fire => fb_fire_drive,
          fb_up => fb_up_drive,
          fb_left => fb_left_drive,
          fb_down => fb_down_drive,
          fb_right => fb_right_drive,
          
          fa_potx => fa_potx,
          fa_poty => fa_poty,
          fb_potx => fb_potx,
          fb_poty => fb_poty,
          pot_drain => pot_drain,
          pot_via_iec => pot_via_iec,
          
          f_density => f_density,
          f_motorb => f_motorb,
          f_motora => f_motora,
          f_selecta => f_selecta,
          f_selectb => f_selectb,
          f_stepdir => f_stepdir,
          f_step => f_step,
          f_wdata => f_wdata,
          f_wgate => f_wgate,
          f_side1 => f_side1,
          f_index => f_index,
          f_track0 => f_track0,
          f_writeprotect => f_writeprotect,
          f_rdata => f_rdata,
          f_diskchanged => f_diskchanged,
          
          ---------------------------------------------------------------------------
          -- IO lines to the ethernet controller
          ---------------------------------------------------------------------------
          eth_mdio => eth_mdio,
          eth_mdc => eth_mdc,
          eth_reset => eth_reset,
          eth_rxd => eth_rxd,
          eth_txd => eth_txd,
          eth_txen => eth_txen,
          eth_rxer => eth_rxer,
          eth_rxdv => eth_rxdv,
          eth_interrupt => '0',
          
          -------------------------------------------------------------------------
          -- Lines for the SDcard interfaces
          -------------------------------------------------------------------------
          -- External one is bus 0, so that it has priority.
          -- Internal SD card:
          cs_bo => sdReset,
          sclk_o => sdClock,
          mosi_o => sdMOSI,
          miso_i => sdMISO,
          -- External microSD
          cs2_bo => sd2reset,
          sclk2_o => sd2Clock,
          mosi2_o => sd2MOSI,
          miso2_i => sd2MISO,
          
          slow_access_request_toggle => slow_access_request_toggle,
          slow_access_ready_toggle => slow_access_ready_toggle,
          slow_access_address => slow_access_address,
          slow_access_write => slow_access_write,
          slow_access_wdata => slow_access_wdata,
          slow_access_rdata => slow_access_rdata,
          
          slow_prefetched_address => slow_prefetched_address,
          slow_prefetched_data => slow_prefetched_data,
          slow_prefetched_request_toggle => slow_prefetched_request_toggle,
          
          cpu_exrom => cpu_exrom,      
          cpu_game => cpu_game,
          cart_access_count => cart_access_count,
          
--      aclMISO => aclMISO,
          aclMISO => '1',
--      aclMOSI => aclMOSI,
--      aclSS => aclSS,
--      aclSCK => aclSCK,
--      aclInt1 => aclInt1,
--      aclInt2 => aclInt2,
          aclInt1 => '1',
          aclInt2 => '1',
          
          micData0 => '1',
          micData1 => '1',
--      micClk => micClk,
--      micLRSel => micLRSel,
          
          disco_led_en => disco_led_en,
          disco_led_id => disco_led_id,
          disco_led_val => disco_led_val,      
          
          flopled => flopled_drive,
          flopmotor => flopmotor_drive,
          ampPWM_l => pwm_l_drive,
          ampPWM_r => pwm_r_drive,
          audio_left => audio_left,
          audio_right => audio_right,
          
          -- PC speakers left/right on main board
          ampSD => i2s_sd,
          i2s_master_clk => i2s_mclk,
          i2s_master_sync => i2s_sync,
          i2s_speaker_data_out => i2s_speaker,
          
          -- Normal connection of I2C peripherals to dedicated address space
          i2c1sda => fpga_sda,
          i2c1scl => fpga_scl,
          
--      tmpsda => fpga_sda,
--      tmpscl => fpga_scl,
          
          portp_out => portp,
          
          -- No PS/2 keyboard for now
          ps2data =>      '1',
          ps2clock =>     '1',
          
          fpga_temperature => fpga_temperature,
          
          UART_TXD => UART_TXD,
          RsRx => RsRx,
          
          -- Ignore widget board interface and other things
          tmpint => '1',
          tmpct => '1',
          
          -- Connect MEGA65 smart keyboard via JTAG-like remote GPIO interface
          widget_matrix_col_idx => widget_matrix_col_idx,
          widget_matrix_col => widget_matrix_col,
          widget_restore => widget_restore,
          widget_capslock => widget_capslock,
          widget_joya => (others => '1'),
          widget_joyb => (others => '1'),      
          
          sw => sw,
          dipsw => dipsw,
--      uart_rx => '1',
          btn => (others => '1')
          
          );
    end generate;  
      
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

      dvi_select <= portp(1) xor dipsw(1);
      
      reset_high <= not btncpureset;

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

      reset_high <= not btncpureset;
      
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

      last_iec_atn_drive <= iec_atn_drive;
      if (iec_srq_i_drive /= iec_srq_i)
        or (iec_clk_i_drive /= iec_clk_i)
        or (iec_data_i_drive /= iec_data_i)
        or (iec_atn_drive /= last_iec_atn_drive) then
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

    if rising_edge(pixelclock) then
      hsync <= v_vga_hsync;
      vsync <= v_vsync;
      vgared <= v_red;
      vgagreen <= v_green;
      vgablue <= v_blue;
      hdmired <= v_red;
      hdmigreen <= v_green;
      hdmiblue <= v_blue;
    end if;

    -- XXX DEBUG: Allow showing audio samples on video to make sure they are
    -- getting through
    if portp(2)='1' then
      vgagreen <= unsigned(audio_left(15 downto 8));
      vgared <= unsigned(audio_right(15 downto 8));
      hdmigreen <= unsigned(audio_left(15 downto 8));
      hdmired <= unsigned(audio_right(15 downto 8));
    end if;
    
  end process;    
  
end Behavioral;
