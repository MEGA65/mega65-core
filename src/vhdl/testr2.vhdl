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
         -- XXX Replace with new 8-pin keyboard interface
--         restore_key : in std_logic;
--         column : inout  std_logic_vector(8 downto 0) := (others => 'Z');
--         row : in  std_logic_vector(8 downto 0);
--         keyleft : inout std_logic := 'Z';
--         keyup : inout std_logic := 'Z';

         kb_io0 : out std_logic;
         kb_io1 : out std_logic;
         kb_io2 : in std_logic;
         
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
         iec_clk_en : out std_logic := '0';
         iec_data_en : out std_logic := '0';
         iec_data_o : out std_logic;
         iec_reset : out std_logic;
         iec_clk_o : out std_logic;
         iec_data_i : in std_logic;
         iec_clk_i : in std_logic;
         iec_srq_o : out std_logic;
         iec_srq_en : out std_logic := '0';
         iec_src_i : in std_logic;
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
         -- Lines for the SDcard interfaces
         -------------------------------------------------------------------------
         sdReset : out std_logic;
         sdClock : out std_logic;
         sdMOSI : out std_logic;      
         sdMISO : in  std_logic;

         sd2Reset : out std_logic;
         sd2Clock : out std_logic;
         sd2MOSI : out std_logic;
         sd2MISO : out std_logic;
         sd2_dat : out std_logic_vector(3 downto 3);

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
         RsRx : out std_logic
         
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
  signal clock120 : std_logic;
  signal clock100 : std_logic := '0';
  signal clock200 : std_logic;
  signal clock240 : std_logic;

  -- XXX Actually connect to new keyboard
  signal restore_key : std_logic := '1';
  signal column : std_logic_vector(8 downto 0) := (others => '1');
  signal row : std_logic_vector(8 downto 0) := (others => '1');
  signal keyleft : std_logic := '1';
  signal keyup : std_logic := '1';
  
  
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
  signal v_green : unsigned(7 downto 0) := x"00";
  signal v_blue : unsigned(7 downto 0);
  signal v_de : std_logic;

  signal phi2_out : std_logic;
  
  -- XXX We should read the real temperature and feed this to the DDR controller
  -- so that it can update timing whenever the temperature changes too much.
  signal fpga_temperature : std_logic_vector(11 downto 0) := (others => '0');

  -- XXX Connect to real QSPI flash interface at some point
  signal QspiDB : std_logic_vector(3 downto 0) := (others => '0');
  signal QspiCSn : std_logic := '1';

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

  signal powerled : std_logic := '1';
  signal flopled_drive : std_logic := '1';
  signal flopmotor_drive : std_logic := '0';

  signal joy3 : std_logic_vector(4 downto 0);
  signal joy4 : std_logic_vector(4 downto 0);

  signal cart_access_count : unsigned(7 downto 0);

  signal counter : integer := 0;
  signal ktoggle : std_logic := '0';

  signal restore : std_logic := '0';
  signal capslock : std_logic := '0';
  signal leftkey : std_logic := '0';
  signal upkey : std_logic := '0';

  signal delete_out : std_logic := '0';
  signal return_out : std_logic := '0';
  
  signal matrix_col : std_logic_vector(7 downto 0);

  signal x_zero : std_logic;
  signal y_zero : std_logic;

  signal x_pos : unsigned(11 downto 0) := to_unsigned(0,12);
  signal y_pos : unsigned(11 downto 0) := to_unsigned(0,12);
  
--  signal dummy : std_logic := '0';
  
begin

  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock80 => pixelclock, -- 80MHz
               clock40 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock100 => clock100,
               clock120 => clock120,
               clock240 => clock240
               );

  frame50: entity work.frame_generator
    generic map ( frame_width => 968*4-1,    -- 63 cycles x 16 pixels per clock
                  clock_divider => 4,
                  display_width => 800*4,
                  frame_height => 624,        -- 312 lines x 2 fields
                  pipeline_delay => 128,
                  display_height => 600,
                  vsync_start => 624-18-5,
                  vsync_end => 624-18,
                  hsync_start => (968-46-1)*4,
                  hsync_end => (968-1)*4
                  )                  
--    generic map ( frame_width => 1265*3-1,   -- 65 cycles x 16 pixels = 1040,
--                                             -- but with 526 lines, we need it
--                                             -- wider.
--                  display_width => 800 *3,
--                  clock_divider => 3,
--                  frame_height => 526,       -- NTSC frame is 263 lines x 2 frames
--                  display_height => 526-4,
--                  pipeline_delay => 96,
--                  vsync_start => 526-4,
--                  vsync_end => 526,
--                  hsync_start => 1204*3,
--                  hsync_end => 1264*3
--                  )                  
    port map ( clock240 => clock240,
               clock120 => clock120,
               clock80 => pixelclock,
               clock40 => cpuclock,
               hsync => v_hsync,
               vsync => v_vsync,
               hsync_polarity => '1',
               vsync_polarity => '1',

               phi2_out => phi2_out,
               
               x_zero_80 => x_zero,
               y_zero_80 => y_zero
--               inframe => inframe_pal50,
--               x_zero => x_zero50,

     -- Get test pattern
--               red_o => v_red,
--               green_o => v_green,
--               blue_o => v_blue
               );

  
  kbd0: entity work.mega65kbd_to_matrix
    port map (
      ioclock => cpuclock,

--      powerled => powerled,
--      flopled => flopled_drive,
--      flopmotor => flopmotor_drive,

      powerled => matrix_col(0),
      flopled => matrix_col(1),

--      powerled => delete_out,
--      flopled => return_out,
      flopmotor => matrix_col(2),

      kio8 => kb_io0,
      kio9 => kb_io1,
      kio10 => kb_io2,

      matrix_col_idx => 0,
      matrix_col => matrix_col,
      restore => restore,
      capslock_out => capslock,
      leftkey => leftkey,
      upkey => upkey,
      delete_out => delete_out,
      return_out => return_out

      );

  slow_devices0: entity work.slow_devices
    generic map (
      target => mega65r2
      )
    port map (
      cpuclock => cpuclock,
      pixelclock => pixelclock,
      reset => iec_reset_drive,
      cpu_exrom => cpu_exrom,
      cpu_game => cpu_game,
      sector_buffer_mapped => sector_buffer_mapped,
      
      qspidb => qspidb,
      qspicsn => qspicsn,      
--      qspisck => '1',

      joya => joy3,
      joyb => joy4,
      
--      cart_busy => led,
      cart_access_count => cart_access_count,
      
      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_write => slow_access_write,
      slow_access_address => slow_access_address,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,

      expansionram_data_ready_strobe => '1',
      
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
--      cart_exrom => dummy,
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
  
  process (pixelclock) is
  begin
    vdac_sync_n <= '0';  -- no sync on green
    vdac_blank_n <= '1'; -- was: not (v_hsync or v_vsync); 

    -- VGA output at full pixel clock
    vdac_clk <= pixelclock;

    -- Ethernet clock at 50MHz
    eth_clock <= ethclock;

    if rising_edge(pixelclock) then
      hsync <= v_hsync;
      vsync <= v_vsync;
      vgared <= v_red;
      vgagreen <= v_green;
      vgablue <= v_blue;

      if x_zero = '1' then
        x_pos <= to_unsigned(0,12);
        y_pos <= y_pos + 1;
      else
        x_pos <= x_pos + 1;
      end if;
      if y_zero = '1' then
        y_pos <= to_unsigned(0,12);
        x_pos <= to_unsigned(0,12);
      end if;


      if x_pos(6)='1' then
        v_red <= x"FF";
      else
        v_red <= x"00";
      end if;
      if y_pos(5)='1' then
        v_blue <= x"FF";
      else
        v_blue <= x"00";
      end if;
      
    end if;

    if rising_edge(cpuclock) then
      if phi2_out = '1' then
        v_green <= not v_green;
      end if;
    end if;
    
    -- Drive most ports, to relax timing
    if rising_edge(cpuclock) then

      led <= cpu_exrom;
      
      -- Try to debug keyboard interface
      if counter /= 10000000 then
        counter <= counter + 1;
      else
        counter <= 0;
        ktoggle <= not ktoggle;
--        flop <= ktoggle;
      end if;
      
      -- Connect UART RX and TX
--      uart_txd <= rsrx;

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
