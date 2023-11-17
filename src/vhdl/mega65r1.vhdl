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
         restore_key : in std_logic;
         column : inout  std_logic_vector(8 downto 0) := (others => 'Z');
         row : in  std_logic_vector(8 downto 0);
         keyleft : inout std_logic := 'Z';
         keyup : inout std_logic := 'Z';
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
         -- CBM floppy serial port
         ----------------------------------------------------------------------
         iec_clk_en : out std_logic;
         iec_data_en : out std_logic;
         iec_data_o : out std_logic;
         iec_reset : out std_logic;
         iec_clk_o : out std_logic;
         iec_data_i : in std_logic;
         iec_clk_i : in std_logic;
         iec_atn : out std_logic;
         
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

         hdmi_vsync : out  STD_LOGIC;
         hdmi_hsync : out  STD_LOGIC;
         hdmired : out  UNSIGNED (7 downto 0);
         hdmigreen : out  UNSIGNED (7 downto 0);
         hdmiblue : out  UNSIGNED (7 downto 0);
         hdmi_spdif : in std_logic;
         hdmi_spdif_out : out std_logic;
         hdmi_scl : inout std_logic;
         hdmi_sda : inout std_logic;
         hdmi_de : out std_logic; -- high when valid pixels being output
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

         sd2MOSI : out std_logic;
         sd2MISO : in std_logic;

         -- Left and right audio
         pwm_l : out std_logic;
         pwm_r : out std_logic;
         
         ----------------------------------------------------------------------
         -- Floppy drive interface
         ----------------------------------------------------------------------
         f_density : out std_logic := '1';
         f_motor : out std_logic := '1';
         f_select : out std_logic := '1';
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

         led : out std_logic;
         
         ----------------------------------------------------------------------
         -- Debug interfaces on Nexys4 board
         ----------------------------------------------------------------------
         UART_TXD : out std_logic;
         RsRx : in std_logic
         
         );
end container;

architecture Behavioral of container is
  
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal reset_out : std_logic := '1';
  signal cpu_game : std_logic := '1';
  signal cpu_exrom : std_logic := '1';

  signal pixelclock : std_logic;
  signal ethclock : std_logic;
  signal cpuclock : std_logic;
  signal clock27 : std_logic;
  signal clock100 : std_logic;
  signal clock162 : std_logic;
  
  
  signal segled_counter : unsigned(31 downto 0) := (others => '0');

  signal slow_access_request_toggle : std_logic;
  signal slow_access_ready_toggle : std_logic;
  signal slow_access_write : std_logic;
  signal slow_access_address : unsigned(27 downto 0);
  signal slow_access_wdata : unsigned(7 downto 0);
  signal slow_access_rdata : unsigned(7 downto 0);
  signal sector_buffer_mapped : std_logic;  

  signal pmoda_dummy :  std_logic_vector(7 downto 0) := (others => '1');

  signal v_hsync : std_logic;
  signal v_vsync : std_logic;
  signal v_red : unsigned(7 downto 0);
  signal v_green : unsigned(7 downto 0);
  signal v_blue : unsigned(7 downto 0);
  signal v_de : std_logic;
  
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
  signal iec_data_o_drive : std_logic;
  signal iec_reset_drive : std_logic;
  signal iec_clk_o_drive : std_logic;
  signal iec_data_i_drive : std_logic;
  signal iec_clk_i_drive : std_logic;
  signal iec_atn_drive : std_logic;

  signal pwm_l_drive : std_logic;
  signal pwm_r_drive : std_logic;

  signal flopled_drive : std_logic;
  signal flopmotor_drive : std_logic;

  signal joy3 : std_logic_vector(4 downto 0);
  signal joy4 : std_logic_vector(4 downto 0);

  signal cart_access_count : unsigned(7 downto 0);

  signal qspi_clock : std_logic;
  
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

  
  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock100 => clock100,
               clock81 => pixelclock, -- 80MHz
               clock41 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock162 => clock162,
               clock27 => clock27
               );

  fpgatemp0: entity work.fpgatemp
    generic map (DELAY_CYCLES => 480)
    port map (
      rst => '0',
      clk => cpuclock,
      temp => fpga_temperature);

  slow_devices0: entity work.slow_devices
    port map (
      cpuclock => cpuclock,
      pixelclock => pixelclock,
      reset => iec_reset_drive,
      cpu_exrom => cpu_exrom,
      cpu_game => cpu_game,
      sector_buffer_mapped => sector_buffer_mapped,
      
      qspidb => qspiDB,
      qspicsn => qspiCSn,      
      qspisck => qspi_clock,

      joya => joy3,
      joyb => joy4,
      
      cart_busy => led,
      cart_access_count => cart_access_count,
      
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
      cart_data_en => cart_data_en,
      cart_addr_en => cart_addr_en,
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
      
      cart_d_in => cart_d,
      cart_d => cart_d,
      cart_a => cart_a
      );
  
  machine0: entity work.machine
    generic map (cpufrequency => 40,
                 target => mega65r1)
    port map (
      pixelclock      => pixelclock,
      cpuclock        => cpuclock,
      uartclock       => cpuclock, -- Match CPU clock
      ioclock         => cpuclock, -- Match CPU clock
      clock162 => clock162,
      clock100 => clock100,
      clock27 => clock27,
      clock50mhz      => ethclock,

      btncpureset => btncpureset,
      reset_out => reset_out,
      irq => irq,
      nmi => nmi,
      restore_key => restore_key,
      sector_buffer_mapped => sector_buffer_mapped,

      joy3 => joy3,
      joy4 => joy4,
      
      no_hyppo => '0',
      
      vsync           => v_vsync,
      vga_hsync           => v_hsync,
      vgared          => v_red,
      vgagreen        => v_green,
      vgablue         => v_blue,
      hdmi_sda        => hdmi_sda,
      hdmi_scl        => hdmi_scl,      
      
      ----------------------------------------------------------------------
      -- CBM floppy  std_logic_vectorerial port
      ----------------------------------------------------------------------
      iec_clk_en => iec_clk_en_drive,
      iec_data_en => iec_data_en_drive,
      iec_data_o => iec_data_o_drive,
      iec_reset => iec_reset_drive,
      iec_clk_o => iec_clk_o_drive,
      iec_data_external => iec_data_i_drive,
      iec_clk_external => iec_clk_i_drive,
      iec_atn_o => iec_atn_drive,

--      buffereduart_rx => '1',
      buffereduart_ringindicate => '1',

      porta_pins => column(7 downto 0),
      portb_pins => row(7 downto 0),
      keyboard_column8 => column(8),
      caps_lock_key => row(8),
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
    f_motor => f_motor,
    f_select => f_select,
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
      -- Lines for the SDcard interface itself
      -------------------------------------------------------------------------
      cs_bo => sdReset,
      sclk_o => sdClock,
      mosi_o => sdMOSI,
      miso_i => sdMISO,
      mosi2_o => sd2MOSI,
      miso2_i => sd2MISO,

      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_address => slow_access_address,
      slow_access_write => slow_access_write,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,
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

      flopled => flopled_drive,
      flopmotor => flopmotor_drive,
      ampPWM_l => pwm_l_drive,
      ampPWM_r => pwm_r_drive,

      -- No PS/2 keyboard for now
      ps2data =>      '1',
      ps2clock =>     '1',

      fpga_temperature => fpga_temperature,
      
      UART_TXD => UART_TXD,
      RsRx => RsRx,

      -- Ignore widget board interface and other things
      tmpint => '1',
      tmpct => '1',

     widget_matrix_col => (others => '1'),
      widget_restore => '1',
      widget_capslock => '1',
      widget_joya => (others => '1'),
      widget_joyb => (others => '1'),      

      sw => (others => '0'),
--      uart_rx => '1',
      btn => (others => '1')
         
      );

  process (pixelclock) is
  begin
    vdac_sync_n <= '0';  -- no sync on green
    vdac_blank_n <= '1'; -- was: not (v_hsync or v_vsync); 

    -- VGA output at full pixel clock
    vdac_clk <= pixelclock;

    -- Ethernet clock at 50MHz
    eth_clock <= ethclock;

    -- Drive most ports, to relax timing
    if rising_edge(cpuclock) then
      
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

      -- The CIAs drive these lines naively, so we need to apply the inverters
      -- on the outputs here, and also deal with the particulars of how the
      -- MEGA65 PCB drives these lines.
      -- Note that the MEGA65 PCB lacks pull-ups on these lines, and relies on
      -- the connected disk drive(s) having pull-ups of their own.
      -- Here is the truth table for behaviour with a pull-up on the pin:
      -- +----+-----++----+
      -- | _o | _en || _i |
      -- +----+-----++----+
      -- |  0 |   X || 0  |
      -- |  1 |   0 || 1* |
      -- |  1 |   1 || 1  |
      -- +----+-----++----+
      -- * Value provided by pin up, or equivalently device on the bus
      --
      -- End result is simple: Invert output bit, and copy output enable
      -- Except, that the CIA always thinks it is driving the line, so
      -- we need to ignore the _en lines, and instead use the _o lines
      -- (before inversion) to indicate when we should be driving the pin
      -- to ground.

      iec_reset <= iec_reset_drive;
      iec_atn <= not iec_atn_drive;

      if pot_via_iec = '0' then
        -- Normal IEC port operation
        iec_clk_en <= iec_clk_o_drive;
        iec_clk_o <= not iec_clk_o_drive;
        iec_clk_i_drive <= iec_clk_i;
        iec_data_en <= iec_data_o_drive;
        iec_data_o <= not iec_data_o_drive;
        iec_data_i_drive <= iec_data_i;
        -- So pots act like infinite resistance
        fa_potx <= '0';
        fa_poty <= '0';
        fb_potx <= '0';
        fb_poty <= '0';
      else
        -- IEC lines being used as POT inputs
        iec_clk_i_drive <= '1';
        iec_data_i_drive <= '1';
        if pot_drain = '1' then
          -- IEC lines being used to drain pots
          iec_clk_en <= '1';
          iec_clk_o <= '0';
          iec_data_en <= '1';
          iec_data_o <= '0';
        else
          -- Stop draining
          iec_clk_en <= '0';
          iec_clk_o <= '0';
          iec_data_en <= '0';
          iec_data_o <= '0';
        end if;
        -- Copy IEC input values to POT inputs
        fa_potx <= iec_data_i;
        fa_poty <= iec_clk_i;
        fb_potx <= iec_data_i;
        fb_poty <= iec_clk_i;
      end if;

      pwm_l <= pwm_l_drive;
      pwm_r <= pwm_r_drive;

    end if;
    
    if rising_edge(pixelclock) then
      hsync <= v_hsync;
      vsync <= v_vsync;
      vgared <= v_red;
      vgagreen <= v_green;
      vgablue <= v_blue;
    end if;
    
    if rising_edge(pixelclock) then

      hdmi_hsync <= v_hsync;
      hdmi_vsync <= v_vsync;
      hdmired <= v_red;
      hdmigreen <= v_green;
      hdmiblue <= v_blue;
      -- pixels valid only when neither sync signal is asserted
      hdmi_de <= not (v_hsync or v_vsync);
      -- no hdmi audio yet
      hdmi_spdif_out <= 'Z';
      -- HDMI control interface
      -- XXX We need to send some commands via I2C to configure the HDMI
      -- interface, which we don't yet do, so HDMI output will not yet work.
--      hdmi_scl <= hdmi_scl;
--      hdmi_sda <= hdmi_sda;
    end if;
  end process;    
  
end Behavioral;
