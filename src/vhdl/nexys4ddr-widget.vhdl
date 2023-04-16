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

        --  ----------------------------------------------------------------------
        --  -- PMODs for HyperRAM module
        --  ----------------------------------------------------------------------
        --  jalo : inout std_logic_vector(4 downto 1) := (others => 'Z');
        --  jahi : inout std_logic_vector(10 downto 7) := (others => 'Z');
        -- --  jblo : inout std_logic_vector(4 downto 1) := (others => 'Z');
        -- --  jbhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
        --  jb : inout unsigned(7 downto 0) := (others => 'Z');
         ----------------------------------------------------------------------
         -- HyperRAM as expansion RAM
         ----------------------------------------------------------------------
         hr_d : inout unsigned(7 downto 0) := (others => 'Z');
         hr_rwds : inout std_logic := 'Z';
         hr_reset : out std_logic := 'Z';
         hr_clk_p : out std_logic := 'Z';
         hr_clk_n : out std_logic := 'Z';
         hr_cs0 : out std_logic := 'Z';
         hr_cs1 : out std_logic := 'Z';
         hr_cs2 : out std_logic := 'Z';
         hr_cs3 : out std_logic := 'Z';

         ----------------------------------------------------------------------
         -- PMODs for UART interfaces
         ----------------------------------------------------------------------
         jblo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         ----------------------------------------------------------------------
         -- PMOD for MKII keyboard interface
         ----------------------------------------------------------------------
         jbhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         ----------------------------------------------------------------------
         -- PMOD for widget interface
         ----------------------------------------------------------------------
         jclo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jchi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jdlo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jdhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
        --  ----------------------------------------------------------------------
        --  -- PMOD for joystick interface
        --  ----------------------------------------------------------------------
        --  jxadc : inout std_logic_vector(7 downto 0) := (others => 'Z');

         ----------------------------------------------------------------------
         -- Flash RAM for holding config
         ----------------------------------------------------------------------
--         QspiSCK : out std_logic;
         QspiDB : inout unsigned(3 downto 0);
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

  signal ethclock : std_logic;
  signal ethclock_rotate : std_logic;
  signal cpuclock : std_logic;
  signal clock41 : std_logic;
  signal clock27 : std_logic;
  signal pixelclock : std_logic; -- i.e., clock81p
  signal clock162 : std_logic;
  signal clock200 : std_logic;
  signal clock325 : std_logic;

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
  signal iec_srq_en : std_logic := 'Z';
  signal iec_data_o : std_logic := 'Z';
  signal iec_srq_o : std_logic := 'Z';
  signal iec_reset : std_logic := 'Z';
  signal iec_clk_o : std_logic := 'Z';
  signal iec_data_i : std_logic := '1';
  signal iec_clk_i : std_logic := '1';
  signal iec_srq_i : std_logic := '1';
  signal iec_atn : std_logic := 'Z';


  -- XXX We should read the real temperature and feed this to the DDR controller
  -- so that it can update timing whenever the temperature changes too much.
  signal fpga_temperature : std_logic_vector(11 downto 0) := (others => '0');

  signal ampPWM_internal : std_logic;
  signal dummy : std_logic_vector(2 downto 0);
  signal sawtooth_phase : integer := 0;
  signal sawtooth_counter : integer := 0;
  signal sawtooth_level : integer := 0;

  signal lcd_hsync : std_logic;
  signal lcd_vsync : std_logic;
  signal pal50_select : std_logic;

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

  signal kbd_matrix_col_idx : integer range 0 to 8 := 0;
  signal kbd_matrix_col : std_logic_vector(7 downto 0) := (others => '1');
  signal kbd_restore : std_logic;
  signal kbd_capslock : std_logic;
  signal kbd_disable : std_logic := '0';

  signal widget_matrix_col_idx : integer range 0 to 8 := 0;
  signal widget_matrix_col : std_logic_vector(7 downto 0) := (others => '1');
  signal widget_restore : std_logic;
  signal widget_capslock : std_logic;
  signal widget_joya : std_logic_vector(4 downto 0);
  signal widget_joyb : std_logic_vector(4 downto 0);
  signal widget_disable : std_logic := '0';

  signal com_matrix_col_idx : integer range 0 to 8 := 0;
  signal com_matrix_col : std_logic_vector(7 downto 0);
  signal com_restore : std_logic;
  signal com_capslock : std_logic;

  signal qspi_clock : std_logic := '0';
  signal qspidb_oe : std_logic;
  signal qspidb_out : unsigned(3 downto 0);
  signal qspidb_in : unsigned(3 downto 0);

  signal hyper_addr : unsigned(18 downto 3) := (others => '0');
  signal hyper_request_toggle : std_logic := '0';
  signal hyper_data : unsigned(7 downto 0) := x"00";
  signal hyper_data_strobe : std_logic := '0';

  -- signal hr_d : unsigned(7 downto 0) := (others => 'Z');

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

  signal kbd_datestamp : unsigned(13 downto 0) := to_unsigned(0,14);
  signal kbd_commit : unsigned(31 downto 0) := to_unsigned(0,32);

  signal fastkey : std_logic;

  signal eth_load_enable : std_logic;

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

      eth_load_enable => eth_load_enable,

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

      matrix_col => kbd_matrix_col,
      matrix_col_idx => kbd_matrix_col_idx,
      restore => kbd_restore,
      capslock_out => kbd_capslock,
      upkey => keyup,
      leftkey => keyleft

      );


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

             -- Assert DONE pin
             USRDONEO=>'1',--1-bit input: User DONE pin output control
             USRDONETS=>'1' --1-bit input: User DONE 3-state enable output
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
               clock27   => clock27,    --   27.083 MHz
               clock41   => cpuclock,   --   40.625 MHz
               clock50   => ethclock,   --   50     MHz
               clock81p  => pixelclock, --   81.25  MHz
               clock163  => clock162,   --  162.5   MHz
               clock200  => clock200,   --  200     MHz
               clock325  => clock325    --  325     MHz
               );

  fpgatemp0: fpgatemp
    generic map (DELAY_CYCLES => 480)
    port map (
      rst => '0',
      clk => cpuclock,
      temp => fpga_temperature);

  widget0: entity work.widget_to_matrix port map(
    cpuclock => pixelclock,

    pmod_clock => jdlo(1),
    pmod_start_of_sequence => jdlo(2),
    pmod_data_in(1 downto 0) => jdlo(4 downto 3),
    pmod_data_in(3 downto 2) => jdhi(8 downto 7),
    pmod_data_out => jdhi(10 downto 9),

    matrix_col => widget_matrix_col,
    matrix_col_idx => widget_matrix_col_idx,
    restore => widget_restore,
    capslock_out => widget_capslock,
    -- reset_out => reset_combined,
    joya => widget_joya,
    joyb => widget_joyb
    );

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
      data_ready_strobe => expansionram_data_ready_strobe,
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
      -- hr_cs2 => hr_cs2,
      -- hr_cs3 => hr_cs3,

      hr2_d => hr_d,
      hr2_rwds => hr_rwds
--      hr2_reset => hr2_reset,
--      hr2_clk_p => hr2_clk_p
--      hr_clk_n => hr_clk_n,
--      hr_cs1 => hr2_cs0
      );

  slow_devices0: entity work.slow_devices
    generic map (
      target => nexys4ddr_widget
      )
    port map (
      cpuclock => cpuclock,
      pixelclock => pixelclock,
      reset => reset_out,
      cpu_exrom => cpu_exrom,
      cpu_game => cpu_game,
      sector_buffer_mapped => sector_buffer_mapped,

--      qspidb => qspidb,
--      qspicsn => qspicsn,
--      qspisck => '1',

      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_write => slow_access_write,
      slow_access_address => slow_access_address,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,

      slow_prefetched_address => slow_prefetched_address,
      slow_prefetched_data => slow_prefetched_data,
      slow_prefetched_request_toggle => slow_prefetched_request_toggle,

      ----------------------------------------------------------------------
      -- Expansion RAM interface (upto 127MB)
      ----------------------------------------------------------------------
      expansionram_data_ready_strobe => expansionram_data_ready_strobe,
      expansionram_busy => expansionram_busy,
      expansionram_read => expansionram_read,
      expansionram_write => expansionram_write,
      expansionram_address => expansionram_address,
      expansionram_rdata => expansionram_rdata,
      expansionram_wdata => expansionram_wdata,

      expansionram_current_cache_line => current_cache_line,
      expansionram_current_cache_line_address => current_cache_line_address,
      expansionram_current_cache_line_valid => current_cache_line_valid,
      expansionram_current_cache_line_next_toggle  => expansionram_current_cache_line_next_toggle,

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

  core0:
    if true generate
      machine0: entity work.machine
        generic map (cpu_frequency => 40500000,
                    target => nexys4ddr_widget)
        port map (
          pixelclock      => pixelclock,
          cpuclock        => cpuclock,
          uartclock       => cpuclock, -- Match CPU clock
          clock162 => clock162,
          clock27 => clock27,
          clock50mhz      => ethclock,
          clock200  => clock200,

          btncpureset => btncpureset,
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

          hyper_addr => hyper_addr,
          hyper_request_toggle => hyper_request_toggle,
          hyper_data => hyper_data,
          hyper_data_strobe => hyper_data_strobe,

          kbd_datestamp => kbd_datestamp,
          kbd_commit => kbd_commit,

          pal50_select_out => pal50_select,

          -- Wire up a dummy caps_lock key on switch 8
          caps_lock_key => sw(8),

        --   fa_fire => '1',
        --   fa_up =>   '1',
        --   fa_left => '1',
        --   fa_down => '1',
        --   fa_right =>'1',

          fa_fire => widget_joya(4),
          fa_up =>   widget_joya(0),
          fa_left => widget_joya(1),
          fa_down => widget_joya(2),
          fa_right =>widget_joya(3),

        -- Joystick port via PMOD
        --   fa_fire => jchi(9),
        --   fa_up => jclo(1),
        --   fa_left => jclo(2),
        --   fa_down => jchi(7),
        --   fa_right => jchi(8),

          fb_fire => '1',
          fb_up =>   '1',
          fb_left => '1',
          fb_down => '1',
          fb_right =>'1',

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
          iec_srq_en => iec_srq_en,
          iec_data_o => iec_data_o,
          iec_reset => iec_reset,
          iec_clk_o => iec_clk_o,
          iec_atn_o => iec_atn,
          iec_data_external => iec_data_i,
          iec_clk_external => iec_clk_i,
          iec_srq_external => iec_srq_i,
          iec_bus_active => '0', -- No IEC port on this target

          no_hyppo => '0',

          vsync           => vsync,
          vga_hsync           => hsync,
          lcd_vsync => lcd_vsync,
          lcd_hsync => lcd_hsync,

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
          eth_mdio => eth_mdio,
          eth_mdc => eth_mdc,
          eth_reset => eth_reset,
          eth_rxd => eth_rxd,
          eth_txd => eth_txd,
          eth_txen => eth_txen,
          eth_rxer => eth_rxer,
          eth_rxdv => eth_rxdv,
          eth_interrupt => eth_interrupt,

          -------------------------------------------------------------------------
          -- Lines for the SDcard interface itself
          -------------------------------------------------------------------------
          cs_bo => sdReset,
          sclk_o => sdClock,
          mosi_o => sdMOSI,
          miso_i => sdMISO,
          miso2_i => '1',

          aclMISO => aclMISO,
          aclMOSI => aclMOSI,
          aclSS => aclSS,
          aclSCK => aclSCK,
          aclInt1 => aclInt1,
          aclInt2 => aclInt2,

          micData0 => micData,
          micData1 => '0', -- This board has only one microphone
          micClk => micClk,
          micLRSel => micLRSel,

          ampPWM_l => ampPWM_internal,
          ampPWM_r => led(14),
          ampSD => ampSD,

          tmpSDA => tmpSDA,
          tmpSCL => tmpSCL,
          tmpInt => tmpInt,
          tmpCT => tmpCT,

          touchSDA => jblo(4),
          touchSCL => jblo(3),
          lcdpwm => jbhi(10),

          -- Add second I2C bus we can connect to external things for testing.
          -- i2c1sda => jdlo(4),
          -- i2c1scl => jchi(7),

          -- This is for modem as PCM master:
          pcm_modem_clk_in => jchi(7),
          pcm_modem_sync_in => jchi(8),
          -- This is for modem as PCM slave:
          -- (note that the EC25AU firmware we have doesn't work properly as a PCM
          -- slave).
          -- pcm_modem_clk => jchi(7),
          -- pcm_modem_sync => jchi(8),

          pcm_modem1_data_out => jchi(9),
          pcm_modem1_data_in => jchi(10),

          ps2data =>      ps2data,
          ps2clock =>     ps2clk,

          widget_matrix_col_idx => com_matrix_col_idx,
          widget_matrix_col => com_matrix_col,
          widget_restore => com_restore,
          widget_capslock => com_capslock,
          widget_joya => widget_joya,
          widget_joyb => widget_joyb,

          uart_rx => jblo(1),
          uart_tx => jblo(2),

    --      buffereduart_rx => jblo(3),
    --      buffereduart_tx => jblo(4),
    --      buffereduart2_rx => jbhi(9),
    --      buffereduart2_tx => jbhi(10),
          buffereduart_ringindicate => (others => '0'),

          slow_access_request_toggle => slow_access_request_toggle,
          slow_access_ready_toggle => slow_access_ready_toggle,
          slow_access_address => slow_access_address,
          slow_access_write => slow_access_write,
          slow_access_wdata => slow_access_wdata,
          slow_access_rdata => slow_access_rdata,

          slow_prefetched_address => slow_prefetched_address,
          slow_prefetched_data => slow_prefetched_data,
          slow_prefetched_request_toggle => slow_prefetched_request_toggle,

    --      cpu_exrom => cpu_exrom,
    --      cpu_game => cpu_game,
          -- enable/disable cartridge with sw(8)
          cpu_exrom => '1',
          cpu_game => '1',
          cart_access_count => x"00",

          fpga_temperature => fpga_temperature,

          led(12 downto 0) => led(12 downto 0),
          led(15 downto 13) => dummy,
          dipsw(0) => '0',
          dipsw(1) => sw(11), -- switch 11 turns on ethernet remote control
          dipsw(2) => '0',
          dipsw(3) => '0',
          dipsw(4) => '0',
          sw => sw,
          btn => btn,

          UART_TXD => UART_TXD,
          RsRx => RsRx,

          sseg_ca => sseg_ca,
          sseg_an => sseg_an
          );
    end generate;

  -- Hardware buttons for triggering IRQ & NMI
  irq <= not btn(0);
  nmi <= not btn(4);
  restore_key <= not btn(1);

  -- BUFG on ethernet clock to keep the clock nice and strong
  ethbufg0:
  bufg port map ( I => ethclock,
                  O => eth_clock);

  qspidb <= qspidb_out when qspidb_oe='1' else "ZZZZ";
  qspidb_in <= qspidb;

  -- jalo(1) <= '1';
  -- jahi(7) <= '1';
  -- hr_cs0 <= '1';
  -- hr_cs1 <= '1';
  -- hr_cs2 <= '1';
  -- hr_cs3 <= '1';

  widget_matrix_col_idx <= com_matrix_col_idx;
  kbd_matrix_col_idx <= com_matrix_col_idx;
  com_matrix_col <=
                    "11111111"
                    and (widget_matrix_col or (7 downto 0 => widget_disable))
                    and (kbd_matrix_col or (7 downto 0 => kbd_disable));
  com_restore <= '1' and (kbd_restore or kbd_disable) and (widget_restore or widget_disable);
  com_capslock <= '1'and (kbd_capslock or kbd_disable) and (widget_capslock or widget_disable);

  process (cpuclock,pixelclock,cpuclock,pal50_select)
  begin
    if rising_edge(pixelclock) then

      if sw(7)='0' then
        -- VGA direct output
        vgared <= buffer_vgared(7 downto 4);
        vgagreen <= buffer_vgagreen(7 downto 4);
        vgablue <= buffer_vgablue(7 downto 4);
      else
        vgared <= (others => not (lcd_hsync or lcd_vsync));
        vgagreen <= to_unsigned(sawtooth_counter,4);
        vgablue <= to_unsigned(sawtooth_counter,4);
      end if;

    end if;

    if rising_edge(cpuclock) then

      -- No physical keyboard
      -- portb_pins <= (others => '1');

      -- Debug audio output
      if sw(7) = '0' then
        ampPWM <= ampPWM_internal;
        led(15) <= ampPWM_internal;
      else
        -- 1KHz sawtooth
        if sawtooth_phase < 50000000 then
          sawtooth_phase <= sawtooth_phase + 1;
          if sawtooth_counter < 256 then
            sawtooth_counter <= sawtooth_counter + sawtooth_level;
            ampPWM <= '0';
            led(15) <= '0';
          else
            sawtooth_counter <= sawtooth_counter + sawtooth_level - 256;
            ampPWM <= '1';
            led(15) <= '1';
          end if;
        else
          sawtooth_phase <= 0;
          if sawtooth_level < 255 then
            sawtooth_level <= sawtooth_level + 1;
          else
            sawtooth_level <= 0;
          end if;
--          qspi_clock <= not qspi_clock_int;
--          qspi_clock_int <= not qspi_clock_int;

        end if;
      end if;

      if widget_matrix_col = x"FF" then
        widget_disable <= '1';
      elsif kbd_matrix_col = x"FF" then
        kbd_disable <= '1';
      end if;

      -- Detect MK-I keyboard by looking for KIO10 going high, as MK-II keyboard
      -- holds this line forever low.  As MK-I will start with KIO10 high, we can
      -- assume MK-II keyboard, and correct our decision in 1 clock tick if it was
      -- wrong.  Doing it the other way around would cause fake key presses during
      -- the 5000 cycles while we wait to decide it really is a MK-II keyboard.
      led(13) <= mk1_connected;
      if to_X01(jbhi(9)) = '1' then
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
      jbhi(7) <= xil_io1;
      jbhi(8) <= xil_io2;
      xil_io3 <= jbhi(9);
    else
      -- MK-II keyboard connected
      -- Make tri-state link from keyboard connector to MK-II controller
      mk2_io1_in <= jbhi(7);
      if mk2_io1_en='1' then
        jbhi(7) <= mk2_io1;
      else
        jbhi(7) <= 'Z';
      end if;
      mk2_io2_in <= jbhi(8);
      if mk2_io2_en='1' then
--        report "io2 drive : k_io2 <= " & std_logic'image(mk2_io2);
        jbhi(8) <= mk2_io2;
      else
--        report "io2 Z";
        jbhi(8) <= 'Z';
      end if;

      -- Connect Xilinx MK-I interface to MK-II controller
      mk2_xil_io1 <= xil_io1;
      mk2_xil_io2 <= xil_io2;
      xil_io3 <= mk2_xil_io3;
    end if;
  end process;

end Behavioral;
