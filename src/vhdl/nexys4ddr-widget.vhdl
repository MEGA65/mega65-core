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

         ----------------------------------------------------------------------
         -- PMOD for joystick interface
         ----------------------------------------------------------------------
         jalo : in std_logic_vector(4 downto 1) := (others => 'Z');
         jahi : in std_logic_vector(9 downto 7) := (others => '0');

         ----------------------------------------------------------------------
         -- PMODs for LCD screen and associated things during testing
         ----------------------------------------------------------------------
         jblo : in std_logic_vector(4 downto 1) := (others => 'Z');
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

  signal widget_matrix_col_idx : integer range 0 to 15 := 0;
  signal widget_matrix_col : std_logic_vector(7 downto 0);
  signal widget_restore : std_logic;
  signal widget_capslock : std_logic;
  signal widget_joya : std_logic_vector(4 downto 0);
  signal widget_joyb : std_logic_vector(4 downto 0);

  signal qspi_clock : std_logic := '0';
  signal qspidb_oe : std_logic;
  signal qspidb_out : unsigned(3 downto 0);
  signal qspidb_in : unsigned(3 downto 0);

  signal kbd_datestamp : unsigned(13 downto 0) := to_unsigned(0,14);
  signal kbd_commit : unsigned(31 downto 0) := to_unsigned(0,32);

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
               clock163  => clock162,   -- 162.5    MHz
               clock200  => clock200,   -- 200      MHz
               clock325  => clock325    -- 325      MHz
               );

  fpgatemp0: fpgatemp
    generic map (DELAY_CYCLES => 480)
    port map (
      rst => '0',
      clk => cpuclock,
      temp => fpga_temperature);

  widget0: entity work.widget_to_matrix port map(
    cpuclock => pixelclock,

    pmod_clock => jblo(1),
    pmod_start_of_sequence => jblo(2),
    pmod_data_in(1 downto 0) => jblo(4 downto 3),
    pmod_data_in(3 downto 2) => jbhi(8 downto 7),
    pmod_data_out => jbhi(10 downto 9),

    matrix_col => widget_matrix_col,
    matrix_col_idx => widget_matrix_col_idx,
    restore => widget_restore,
    capslock_out => widget_capslock,
    joya => widget_joya,
    joyb => widget_joyb
    );  
  
  slow_devices0: entity work.slow_devices
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
     
      pal50_select_out => pal50_select,
      
      -- Wire up a dummy caps_lock key on switch 8
      caps_lock_key => sw(8),

      -- fa_fire => '1',
      -- fa_up =>  '1',
	  -- fa_left => '1',
      -- fa_down => '1',
      -- fa_right => '1',

	  -- Joystick port via PMOD
      fa_fire => jahi(9),
      fa_up => jalo(1),     
      fa_left => jalo(2),
      fa_down => jahi(7),
      fa_right => jahi(8),

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

      porta_pins => porta_pins,
      portb_pins => portb_pins,
      keyleft => '0',
      keyup => '0',
      
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

      touchSDA => jdlo(2),
      touchSCL => jdlo(1),
      lcdpwm => jdlo(3),

      -- Add second I2C bus we can connect to external things for testing.
      i2c1sda => jdlo(4),
      i2c1scl => jchi(7),

      kbd_datestamp => kbd_datestamp,
      kbd_commit => kbd_commit,
      
      -- This is for modem as PCM master:
      pcm_modem_clk_in => jdhi(7),
      pcm_modem_sync_in => jdhi(8),
      -- This is for modem as PCM slave:
      -- (note that the EC25AU firmware we have doesn't work properly as a PCM
      -- slave).
      -- pcm_modem_clk => jdhi(7),
      -- pcm_modem_sync => jdhi(8),
      
      pcm_modem1_data_out => jdhi(9),
      pcm_modem1_data_in => jdhi(10),
      
      ps2data =>      ps2data,
      ps2clock =>     ps2clk,

      widget_matrix_col_idx => widget_matrix_col_idx,
      widget_matrix_col => widget_matrix_col,
      widget_restore => widget_restore,
      widget_capslock => widget_capslock,
      widget_joya => widget_joya,
      widget_joyb => widget_joyb,      
      
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
  end generate core0;
  
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
      portb_pins <= (others => '1');
      
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
    end if;
  end process;

end Behavioral;
