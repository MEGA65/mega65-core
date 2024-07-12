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

library unisim;
use unisim.vcomponents.all;


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

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
         vgared : out  UNSIGNED (4 downto 0);
         vgagreen : out  UNSIGNED (5 downto 0);
         vgablue : out  UNSIGNED (4 downto 0);

         ---------------------------------------------------------------------------
         -- IO lines to the ethernet controller
         ---------------------------------------------------------------------------
        --  eth_mdio : inout std_logic;
        --  eth_mdc : out std_logic;
        --  eth_reset : out std_logic;
        --  eth_rxd : in unsigned(1 downto 0);
        --  eth_txd : out unsigned(1 downto 0);
        --  eth_rxer : in std_logic;
        --  eth_txen : out std_logic;
        --  eth_rxdv : in std_logic;
        --  eth_interrupt : in std_logic;
        --  eth_clock : out std_logic;
         
         -------------------------------------------------------------------------
         -- Lines for the SDcard interface itself
         -----------------------------------------------------------------------
         sdReset : out std_logic := '0';  -- must be 0 to power SD controller (cs_bo)
         sdClock : out std_logic;       -- (sclk_o)
         sdMOSI : out std_logic;      
         sdMISO : in  std_logic;

         ---------------------------------------------------------------------------
         -- Lines for other devices that we handle here
         ---------------------------------------------------------------------------
        --  aclMISO : in std_logic;
        --  aclMOSI : out std_logic;
        --  aclSS : out std_logic;
        --  aclSCK : out std_logic;
        --  aclInt1 : in std_logic;
        --  aclInt2 : in std_logic;
         
        --  micData : in std_logic;
        --  micClk : out std_logic;
        --  micLRSel : out std_logic;

        --  ampPWM : out std_logic;
        --  ampSD : out std_logic;

        --  tmpSDA : inout std_logic;
        --  tmpSCL : inout std_logic;
        --  tmpInt : in std_logic;
        --  tmpCT : in std_logic;

         ----------------------------------------------------------------------
         -- PS/2 keyboard interface
         ----------------------------------------------------------------------
        --  ps2clk : in std_logic;
        --  ps2data : in std_logic;

         ----------------------------------------------------------------------
         -- PMODs for LCD screen and associated things during testing
         ----------------------------------------------------------------------
         jalo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jahi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jblo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jbhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jclo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jchi : inout std_logic_vector(10 downto 7) := (others => 'Z');
        --  jdlo : inout std_logic_vector(4 downto 1) := (others => 'Z');
        --  jdhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
        --  jxadc : inout std_logic_vector(7 downto 0) := (others => 'Z');
         gpio : inout std_logic_vector(7 downto 0) := (others => 'Z');
         
         ----------------------------------------------------------------------
         -- Flash ROM for holding config
         ----------------------------------------------------------------------
         QspiDB : inout unsigned(3 downto 0);
         QspiCSn : out std_logic;
--         QspiSCK : out std_logic;
         
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
        --  ddr2_addr      : out   std_logic_vector(12 downto 0);
        --  ddr2_ba        : out   std_logic_vector(2 downto 0);
        --  ddr2_ras_n     : out   std_logic;
        --  ddr2_cas_n     : out   std_logic;
        --  ddr2_we_n      : out   std_logic;
        --  ddr2_ck_p      : out   std_logic_vector(0 downto 0);
        --  ddr2_ck_n      : out   std_logic_vector(0 downto 0);
        --  ddr2_cke       : out   std_logic_vector(0 downto 0);
        --  ddr2_cs_n      : out   std_logic_vector(0 downto 0);
        --  ddr2_dm        : out   std_logic_vector(1 downto 0);
        --  ddr2_odt       : out   std_logic_vector(0 downto 0);
        --  ddr2_dq        : inout std_logic_vector(15 downto 0);
        --  ddr2_dqs_p     : inout std_logic_vector(1 downto 0);
        --  ddr2_dqs_n     : inout std_logic_vector(1 downto 0);
         
         ----------------------------------------------------------------------
         -- Debug interfaces on QMTech A200T board
         ----------------------------------------------------------------------
         led : out std_logic_vector(4 downto 0);
         sw : in std_logic_vector(7 downto 0);
         btn : in std_logic_vector(3 downto 0)

        --  UART_TXD : out std_logic;
        --  RsRx : in std_logic;
         
        --  sseg_ca : out std_logic_vector(7 downto 0);
        --  sseg_an : out std_logic_vector(7 downto 0)
         );
end container;

architecture Behavioral of container is

  component fpgatemp is
    Generic ( DELAY_CYCLES : natural := 480 ); -- 10us @ 48 Mhz
    Port ( clk : in  STD_LOGIC;
           rst : in  STD_LOGIC;
           temp : out  STD_LOGIC_VECTOR (11 downto 0));
  end component;
  
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal restore_key : std_logic := '1';
  signal reset_out : std_logic := '1';
  signal cpu_game : std_logic := '1';
  signal cpu_exrom : std_logic := '1';
  
  signal buffer_vgared : unsigned(7 downto 0);
  signal buffer_vgagreen : unsigned(7 downto 0);
  signal buffer_vgablue : unsigned(7 downto 0);
  
  signal pixelclock : std_logic;
  signal cpuclock : std_logic;
  signal clock200 : std_logic;
  signal clock27 : std_logic;
  signal clock163 : std_logic;
  signal ethclock : std_logic;
  
  -- signal segled_counter : unsigned(31 downto 0) := (others => '0');

  signal slow_access_request_toggle : std_logic;
  signal slow_access_ready_toggle : std_logic;
  signal slow_access_write : std_logic;
  signal slow_access_address : unsigned(27 downto 0);
  signal slow_access_wdata : unsigned(7 downto 0);
  signal slow_access_rdata : unsigned(7 downto 0);

  signal sector_buffer_mapped : std_logic;

  
  signal vgaredignore : unsigned(3 downto 0);
  signal vgagreenignore : unsigned(3 downto 0);
  signal vgablueignore : unsigned(3 downto 0);

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

  
  -- XXX We should read the real temperature and feed this to the DDR controller
  -- so that it can update timing whenever the temperature changes too much.
  signal fpga_temperature : std_logic_vector(11 downto 0) := (others => '0');

  signal ampPWM_internal : std_logic;
  signal dummy : std_logic_vector(10 downto 0);
  signal sawtooth_phase : integer := 0;
  signal sawtooth_counter : integer := 0;
  signal sawtooth_level : integer := 0;

  signal lcd_hsync : std_logic;
  signal lcd_vsync : std_logic;
  signal lcd_display_enable : std_logic;
  signal pal50_select : std_logic;

  signal joy3 : std_logic_vector(4 downto 0);
  signal joy4 : std_logic_vector(4 downto 0);

  -- Assume MK-II keyboard on power on, for the reasons explained further down
  -- in the file
  signal mk1_connected : std_logic := '0';
  signal mkii_counter : integer range 0 to 5000 := 5000;
  signal xil_io1 : std_logic;
  signal xil_io2 : std_logic;
  signal xil_io3 : std_logic;
  signal mk2_xil_io1 : std_logic;
  signal mk2_xil_io2 : std_logic;
  signal mk2_xil_io3 : std_logic;
  signal mk2_io1 : std_logic;
  signal mk2_io2 : std_logic;
  signal mk2_io1_in : std_logic;
  signal mk2_io2_in : std_logic;
  signal mk2_io1_en : std_logic;
  signal mk2_io2_en : std_logic;
  
  signal widget_matrix_col_idx : integer range 0 to 15 := 0;
  signal widget_matrix_col : std_logic_vector(7 downto 0);
  signal widget_restore : std_logic := '1';
  signal widget_capslock : std_logic := '0';
  signal widget_joya : std_logic_vector(4 downto 0);
  signal widget_joyb : std_logic_vector(4 downto 0);
  
  signal qspi_clock : std_logic;
  signal qspidb_oe : std_logic;
  signal qspidb_out : unsigned(3 downto 0);
  signal qspidb_in : unsigned(3 downto 0);

  signal disco_led_en : std_logic := '0';
  signal disco_led_val : unsigned(7 downto 0);
  signal disco_led_id : unsigned(7 downto 0);

  signal flopled0_drive : std_logic;
  signal flopled2_drive : std_logic;
  signal flopledsd_drive : std_logic;
  signal flopmotor_drive : std_logic;
  
  signal keyleft : std_logic := '0';
  signal keyup : std_logic := '0';
  -- On the R2 onwards, we don't use the "real" keyboard interface, but instead the
  -- widget board interface, so just have these as dummy all-high place holders
  signal column : std_logic_vector(8 downto 0) := (others => '1');
  signal row : std_logic_vector(7 downto 0) := (others => '1');

  signal kbd_datestamp : unsigned(13 downto 0);
  signal kbd_commit : unsigned(31 downto 0);

  signal fastkey : std_logic;
  
begin

  mk2: entity work.mk2_to_mk1 
  port map (
    cpuclock => cpuclock,

    mk2_xil_io1 => mk2_xil_io1,
    mk2_xil_io2 => mk2_xil_io2,
    mk2_xil_io3 => mk2_xil_io3,
    
    mk2_io1_in => mk2_io1_in,
    mk2_io1 => mk2_io1,
    mk2_io1_en => mk2_io1_en,

    mk2_io2_in => mk2_io2_in,
    mk2_io2 => mk2_io2,
    mk2_io2_en => mk2_io2_en

    );
  
  kbd0: entity work.mega65kbd_to_matrix
    port map (
      cpuclock => cpuclock,

      disco_led_en => disco_led_en,
      disco_led_id => disco_led_id,
      disco_led_val => disco_led_val,
      
      powerled => '1',
      flopled0 => flopled0_drive,
      flopled2 => flopled2_drive,
      flopledsd => flopledsd_drive,
      flopmotor => flopmotor_drive,
            
      kio8 => xil_io1,
      kio9 => xil_io2,
      kio10 => xil_io3,

      kbd_datestamp => kbd_datestamp,
      kbd_commit => kbd_commit,

      fastkey_out => fastkey,
      
      matrix_col => widget_matrix_col,
      matrix_col_idx => widget_matrix_col_idx,
      restore => widget_restore,
      capslock_out => widget_capslock,
      upkey => keyup,
      leftkey => keyleft
      
      );

  
--STARTUPE2:STARTUPBlock--7Series

--XilinxHDLLibrariesGuide,version2012.4
  STARTUPE2_inst: STARTUPE2
    generic map(PROG_USR=>"FALSE", --Activate program event security feature.
                                   --Requires encrypted bitstreams.
  SIM_CCLK_FREQ=>20.0 --Set the Configuration Clock Frequency(ns) for simulation.
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

  
  dotclock1: entity work.clocking50mhz
    port map ( clk_in => CLK_IN,
               clock81p => pixelclock, -- 80MHz
               clock41 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock162 => clock163,
               clock27 => clock27,
               clock200 => clock200
               );

  fpgatemp0: fpgatemp
    generic map (DELAY_CYCLES => 480)
    port map (
      rst => '0',
      clk => cpuclock,
      temp => fpga_temperature);

  slow_devices0: entity work.slow_devices
    port map (
      cpuclock => cpuclock,
      pixelclock => pixelclock,
      reset => reset_out,
      cpu_exrom => cpu_exrom,
      cpu_game => cpu_game,
      sector_buffer_mapped => sector_buffer_mapped,

      joya => joy3,
      joyb => joy4,
      
      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_write => slow_access_write,
      slow_access_address => slow_access_address,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,

      expansionram_data_ready_toggle => '1',
      expansionram_busy => '1',
      
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
                 target => qmtechk325t,
                 num_eth_rx_buffers => 0,
                 hyper_installed => false
                 )
    port map (
      pixelclock      => pixelclock,
      cpuclock        => cpuclock,
      clock50mhz      => ethclock,
      uartclock       => cpuclock, -- Match CPU clock
      clock200 => clock200,
      clock27 => clock27,
      clock162 => clock163,
      btncpureset => btnCpuReset,
      reset_out => reset_out,
      irq => irq,
      nmi => nmi,
      restore_key => restore_key,
      sector_buffer_mapped => sector_buffer_mapped,

      qspi_clock => qspi_clock,
      qspicsn => qspicsn,
      qspidb => qspidb_out,
      qspidb_in => qspidb_in,
      qspidb_oe => qspidb_oe,
      
      max10_fpga_commit => (others => '1'),
      max10_fpga_date => (others => '1'),
      
      kbd_datestamp => kbd_datestamp,
      kbd_commit => kbd_commit,
      
      joy3 => joy3,
      joy4 => joy4,
      
      pal50_select_out => pal50_select,
      
      caps_lock_key => '1',

      fa_fire => '1',
      fa_up =>  '1',
      fa_left => '1',
      fa_down => '1',
      fa_right => '1',

      fb_fire => '1',
      fb_up => '1',
      fb_left => '1',
      fb_down => '1',
      fb_right => '1',

      fa_potx => '0',
      fa_poty => '0',
      fb_potx => '0',
      fb_poty => '0',

      f_index => '1',
      f_track0 => '1',
      f_writeprotect => '1',
      f_rdata => '1',
      f_diskchanged => '1',
      
      ----------------------------------------------------------------------
      -- CBM floppy  std_logic_vectorerial port
      ----------------------------------------------------------------------
      iec_clk_en => iec_clk_en,
      iec_data_en => iec_data_en,
      iec_data_o => iec_data_o,
      iec_reset => iec_reset,
      iec_clk_o => iec_clk_o,
      iec_atn_o => iec_atn,
      iec_data_external => iec_data_i,
      iec_clk_external => iec_clk_i,
      iec_bus_active => '0', -- No IEC port on this target
      iec_srq_external => '1',
      
      no_hyppo => '0',
      
      vsync           => vsync,
      vga_hsync           => hsync,
      lcd_vsync => lcd_vsync,
      lcd_hsync => lcd_hsync,
      lcd_dataenable => lcd_display_enable,
      vgared(7 downto 0)          => buffer_vgared,
      vgagreen(7 downto 0)        => buffer_vgagreen,
      vgablue(7 downto 0)         => buffer_vgablue,

      porta_pins => column(7 downto 0),
      portb_pins => row(7 downto 0),
      keyboard_column8 => column(8),
      keyleft => keyleft,
      keyup => keyup,

      disco_led_en => disco_led_en,
      disco_led_id => disco_led_id,
      disco_led_val => disco_led_val,      

      flopled0 => flopled0_drive,
      flopled2 => flopled2_drive,
      flopledsd => flopledsd_drive,
      flopmotor => flopmotor_drive,
      
      ---------------------------------------------------------------------------
      -- IO lines to the ethernet controller
      ---------------------------------------------------------------------------
      -- eth_mdio => eth_mdio,
      -- eth_mdc => eth_mdc,
      -- eth_reset => eth_reset,
      -- eth_rxd => eth_rxd,
      eth_rxd => "00",
      -- eth_txd => eth_txd,
      -- eth_txen => eth_txen,
      -- eth_rxer => eth_rxer,
      -- eth_rxdv => eth_rxdv,
      -- eth_interrupt => eth_interrupt,
      eth_rxer => '0',
      eth_rxdv => '0',
      eth_interrupt => '0',
      
      -------------------------------------------------------------------------
      -- Lines for the SDcard interface itself
      -------------------------------------------------------------------------
      cs_bo => sdReset,
      sclk_o => sdClock,
      mosi_o => sdMOSI,
      miso_i => sdMISO,
      miso2_i => '1',

      -- aclMISO => aclMISO,
      -- aclMOSI => aclMOSI,
      -- aclSS => aclSS,
      -- aclSCK => aclSCK,
      -- aclInt1 => aclInt1,
      -- aclInt2 => aclInt2,
      ----------------------
      aclMISO => gpio(1),
      aclMOSI => gpio(2),
      aclSS => gpio(3),
      aclSCK => gpio(4),
      aclInt1 => gpio(5),
      aclInt2 => gpio(6),
      
      micData0 => '0',
      micData1 => '0', -- This board has only one microphone
      -- micClk => micClk,
      -- micLRSel => micLRSel,

      -- ampPWM_l => ampPWM_internal,
      -- ampPWM_r => led(14),
      -- ampSD => ampSD,
      
      -- tmpSDA => tmpSDA,
      -- tmpSCL => tmpSCL,
      tmpInt => '0',
      tmpCT => '0',

      -- touchSDA => jdlo(2),
      -- touchSCL => jdlo(1),
      -- lcdpwm => jdlo(3),
      -- -- This is for modem as PCM master:
      -- pcm_modem_clk_in => jdhi(7),
      -- pcm_modem_sync_in => jdhi(8),
      -- -- This is for modem as PCM slave:
      -- -- (note that the EC25AU firmware we have doesn't work properly as a PCM
      -- -- slave).
      -- -- pcm_modem_clk => jdhi(7),
      -- -- pcm_modem_sync => jdhi(8),
      
      -- pcm_modem1_data_out => jdhi(9),
      -- pcm_modem1_data_in => jdhi(10),
      
      ps2data =>      '0',
      ps2clock =>     '0',
      -- ps2data =>      ps2data,
      -- ps2clock =>     ps2clk,

      -- Connect MEGA65 smart keyboard via JTAG-like remote GPIO interface
      widget_matrix_col_idx => widget_matrix_col_idx,
      widget_matrix_col => widget_matrix_col,
      widget_restore => widget_restore,
      widget_capslock => widget_capslock,
      widget_joya => (others => '1'),
      widget_joyb => (others => '1'),      
      
      uart_rx => jclo(1),
      uart_tx => jclo(2),

--      buffereduart_rx => jclo(3),
--      buffereduart_tx => jclo(4),
--      buffereduart2_rx => jchi(9),
--      buffereduart2_tx => jchi(10),
      buffereduart_ringindicate => (others => '0'),
      
      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_address => slow_access_address,
      slow_access_write => slow_access_write,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,
      cpu_exrom => '1',
      cpu_game => '1',
      cart_access_count => x"00",

      fpga_temperature => fpga_temperature,

      led(4 downto 0) => led(4 downto 0),
      led(15 downto 5) => dummy,
      sw(7 downto 0) => sw(7 downto 0),
      sw(15 downto 8) => dummy(7 downto 0),
      btn(2 downto 0) => btn(2 downto 0),
      btn(4 downto 3) => dummy(1 downto 0),

      UART_TXD => jclo(3),
      RsRx => jclo(4)
      
      -- sseg_ca => sseg_ca,
      -- sseg_an => sseg_an
      );
    
  -- Hardware buttons for triggering IRQ & NMI
  irq <= not btn(0);
  nmi <= not btn(2);
  restore_key <= not btn(1);

  qspidb <= qspidb_out when qspidb_oe='1' else "ZZZZ";
  qspidb_in <= qspidb;
  
  process (cpuclock,clock27,pixelclock, pal50_select)
  begin
    if rising_edge(clock27) then
      if sw(7)='0' then
        -- VGA direct output
        vgared <= buffer_vgared(7 downto 3);
        vgagreen <= buffer_vgagreen(7 downto 2);
        vgablue <= buffer_vgablue(7 downto 3);
      else
        vgared <= (others => not (lcd_hsync or lcd_vsync));
        vgagreen <= to_unsigned(sawtooth_counter,6);
        vgablue <= to_unsigned(sawtooth_counter,5);
      end if;

      -- VGA out on LCD panel
      jalo <= std_logic_vector(buffer_vgablue(7 downto 4));
      jahi <= std_logic_vector(buffer_vgared(7 downto 4));
      jblo <= std_logic_vector(buffer_vgagreen(7 downto 4));
      jbhi(8) <= lcd_hsync;
      jbhi(9) <= lcd_vsync;
      jbhi(10) <= lcd_display_enable;
    end if;

    if rising_edge(cpuclock) then

      -- Detect MK-I keyboard by looking for KIO10 going high, as MK-II keyboard
      -- holds this line forever low.  As MK-I will start with KIO10 high, we can
      -- assume MK-II keyboard, and correct our decision in 1 clock tick if it was
      -- wrong.  Doing it the other way around would cause fake key presses during
      -- the 5000 cycles while we wait to decide it really is a MK-II keyboard.
      led(4) <= mk1_connected;
      if to_X01(jchi(9)) = '1' then
        mkii_counter <= 0;
        mk1_connected <= '1';
        if mk1_connected='0' then
          report "Switching to MK-I keyboard protocol";
        end if;
      else
        if mkii_counter < 5000 then
          mkii_counter <= mkii_counter + 1;
        else
          mk1_connected <= '0';
          if mk1_connected='1' then
            report "Switching to MK-II keyboard protocol";
          end if;
        end if;
      end if;
    end if;
    
    if mk1_connected='1' then
      -- Connect MK-I keyboard to keyboard decoder
      jchi(7) <= xil_io1;
      jchi(8) <= xil_io2;
      xil_io3 <= jchi(9);
    else
      -- MK-II keyboard connected

      -- Make tri-state link from keyboard connector to MK-II controller
      mk2_io1_in <= jchi(7);
      if mk2_io1_en='1' then
        jchi(7) <= mk2_io1; 
      else
        jchi(7) <= 'Z'; 
      end if;
      mk2_io2_in <= jchi(8);
      if mk2_io2_en='1' then
--        report "io2 drive : k_io2 <= " & std_logic'image(mk2_io2);
        jchi(8) <= mk2_io2;
      else
--        report "io2 Z";
        jchi(8) <= 'Z';
      end if;
      
      -- Connect Xilinx MK-I interface to MK-II controller
      mk2_xil_io1 <= xil_io1;
      mk2_xil_io2 <= xil_io2;
      xil_io3 <= mk2_xil_io3;
    end if;
      
    -- ampPWM <= ampPWM_internal;
    -- led(3) <= ampPWM_internal;

  end process;

  -- 50MHz clock to ethernet controller
  -- eth_clock <= ethclock;
  
end Behavioral;
