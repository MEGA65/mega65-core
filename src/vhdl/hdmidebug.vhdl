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
use work.cputypes.all;
use work.debugtools.all;

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

         p1lo : out std_logic_vector(3 downto 0);
         p1hi : out std_logic_vector(3 downto 0);
         p2lo : out std_logic_vector(3 downto 0);
         p2hi : out std_logic_vector(3 downto 0);

         sd2Clock : out std_logic;
         sd2Reset : out std_logic;
         sd2MISO : out std_logic;
         sd2MOSI : out std_logic;
         sd2d1 : out std_logic;
         sd2d2 : out std_logic;
         
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
         iec_clk_en : out std_logic;
         iec_data_en : out std_logic;
         iec_data_o : out std_logic;
         iec_reset : out std_logic;
         iec_clk_o : out std_logic;
         iec_data_i : in std_logic;
         iec_clk_i : in std_logic;
         iec_srq_o : out std_logic;
         iec_srq_en : out std_logic;
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
         hdmi_spdif : out std_logic := '0';
         hdmi_spdif_out : in std_logic;
         hdmi_int : in std_logic;
         hdmi_scl : inout std_logic;
         hdmi_sda : inout std_logic;
         hdmi_de : out std_logic; -- high when valid pixels being output
         hdmi_clk : out std_logic; 

         hpd_a : inout std_logic;
         ct_hpd : out std_logic := '1';
         ls_oe : out std_logic := '1';
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
         -- Lines for the SDcard interface itself
         -------------------------------------------------------------------------
         sdReset : out std_logic := '0';  -- must be 0 to power SD controller (cs_bo)
         sdClock : out std_logic;       -- (sclk_o)
         sdMOSI : out std_logic;      
         sdMISO : in  std_logic;

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
         -- I2C on-board peripherals
         ----------------------------------------------------------------------
         fpga_sda : out std_logic := '0';
         fpga_scl : out std_logic := '0';         
         
         ----------------------------------------------------------------------
         -- Serial monitor interface
         ----------------------------------------------------------------------
         UART_TXD : out std_logic;
         RsRx : in std_logic
         
         );
end container;

architecture Behavioral of container is

  signal ethclock : std_logic;
  signal cpuclock : std_logic;
  signal clock41 : std_logic;
  signal clock27 : std_logic;
  signal pixelclock : std_logic; -- i.e., clock81p
  signal clock81n : std_logic;
  signal clock120 : std_logic;
  signal clock100 : std_logic;
  signal clock135p : std_logic;
  signal clock135n : std_logic;
  signal clock162 : std_logic;
  signal clock325 : std_logic;
  
  signal red : std_logic_vector(7 downto 0);
  signal green : std_logic_vector(7 downto 0);
  signal blue : std_logic_vector(7 downto 0);

  signal pattern_r : unsigned(7 downto 0);
  signal pattern_g : unsigned(7 downto 0);
  signal pattern_b: unsigned(7 downto 0);
  signal pattern_de : std_logic;
  signal pattern_hsync : std_logic;
  signal pattern_vsync : std_logic;

  signal zero : std_logic := '0';
  signal one : std_logic := '1';

  signal h_audio_left : unsigned(19 downto 0) := to_unsigned(0,20);
  signal h_audio_right : unsigned(19 downto 0) := to_unsigned(0,20);

  signal counter : unsigned(31 downto 0) := to_unsigned(0,32);
  signal trigger_reconfigure : std_logic := '0';

  signal pmod_counter : unsigned(15 downto 0) := to_unsigned(0,16);

  signal reconfigure_address : unsigned(31 downto 0) := to_unsigned(0,32);
  signal boot_address : unsigned(31 downto 0) := (others => '1');

  signal x_zero : std_logic;
  signal y_zero : std_logic;
  signal pixel_strobe : std_logic;
  signal xcounter : unsigned(11 downto 0) := to_unsigned(0,12);
  signal ycounter : integer := 0;

  signal reg_num : unsigned(31 downto 0) := to_unsigned(0,32);

  signal ram_cache : unsigned(511 downto 0) := (others => '0');
  signal ram_written : unsigned(511 downto 0) := (others => '0');

  signal ram_cell : integer range 0 to 511 := 0;

  signal frame_counter : unsigned(7 downto 0) := x"00";

  signal joya_idle : std_logic := '1';
  signal joyb_idle : std_logic := '1';

  signal expansionram_read : std_logic;
  signal expansionram_write : std_logic;
  signal expansionram_rdata : unsigned(7 downto 0);
  signal expansionram_wdata : unsigned(7 downto 0);
  signal expansionram_address : unsigned(26 downto 0);
  signal expansionram_data_ready_toggle : std_logic;
  signal last_expansionram_data_ready_toggle : std_logic := '0';
  signal expansionram_busy : std_logic;

  signal read_address : unsigned(7 downto 0) := to_unsigned(0,8);
  
  signal queue_ram_write : std_logic := '0';
  signal read_countdown : integer range 0 to 10 := 0;

  signal ascii_key : unsigned(7 downto 0);
  signal ascii_key_valid : std_logic := '0';
  signal bucky_key : std_logic_vector(6 downto 0);
  signal capslock_combined : std_logic;
  signal widget_matrix_col_idx : integer range 0 to 8 := 5;  
  signal widget_matrix_col : std_logic_vector(7 downto 0);
  signal key_caps : std_logic := '0';
  signal key_restore : std_logic := '0';
  signal key_up : std_logic := '0';
  signal key_left : std_logic := '0';

  signal matrix_segment_num : std_logic_vector(7 downto 0);
  signal porta_pins : std_logic_vector(7 downto 0) := (others => '1');

  signal key_count : unsigned(15 downto 0) := to_unsigned(0,16);
  
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
      USRCCLKO=>cpuclock,--1-bit input: User CCLK input
      USRCCLKTS=>'0',--1-bit input: User CCLK 3-state enable input

      -- Assert DONE pin
      USRDONEO=>'1',--1-bit input: User DONE pin output control
      USRDONETS=>'1' --1-bit input: User DONE 3-state enable output
      );
-- End of STARTUPE2_inst instantiation

  reconfig1: entity work.reconfig
    port map ( clock => cpuclock,
               reg_num => reg_num(4 downto 0),
               reconfigure_address => reconfigure_address,
               boot_address => boot_address,
               trigger_reconfigure => trigger_reconfigure);

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
               clock81n  => clock81n,   --   81.25  MHz
               clock100  => clock100,   --  100     MHz
               clock135p => clock135p,  --  135.417 MHz
               clock135n => clock135n,  --  135.417 MHz
               clock163  => clock162,   -- 162.5    MHz
               clock325  => clock325    -- 325      MHz
               );

  kbd0: entity work.mega65kbd_to_matrix
    port map (
      cpuclock => cpuclock,

      powerled => key_up,
      flopled => '0',
      flopmotor => fb_fire,
      
      kio8 => kb_io0,
      kio9 => kb_io1,
      kio10 => kb_io2,

      matrix_col => widget_matrix_col,
      matrix_col_idx => widget_matrix_col_idx,
      restore => key_restore,
      capslock_out => key_caps,
      upkey => key_up,
      leftkey => key_left
      
      );

--  i_vga_generator: entity work.vga_generator PORT MAP(
--               clk   => clock27,
--               r     => pattern_r,
--               g     => pattern_g,
--               b     => pattern_b,
--               de    => pattern_de,
--               vsync => pattern_vsync,
--               hsync => pattern_hsync
--       );

  block5: block
  begin
    kc0 : entity work.keyboard_complex
      port map (
      reset_in => '1',
      matrix_mode_in => '0',
      viciv_frame_indicate => '0',

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
      BIT_TMR_MAX => to_unsigned((40500000/2000000) - 1,16),
      clk     => cpuclock,
      data    => ascii_key,
--      ready   => tx0_ready,
      uart_tx => UART_TXD);

  
  pixel0: entity work.pixel_driver
    port map (
      clock81 => pixelclock, -- 80MHz
      clock162 => clock162,
      clock27 => clock27,

      cpuclock => cpuclock,

      pixel_strobe_out => pixel_strobe,
      
      -- Configuration information from the VIC-IV
      hsync_invert => zero,
      vsync_invert => zero,
      pal50_select => zero,
      vga60_select => zero,
      test_pattern_enable => one,      
      
      -- Framing information for VIC-IV
      x_zero => x_zero,     
      y_zero => y_zero,     

      -- Pixel data from the video pipeline
      -- (clocked at 100MHz pixel clock)
      red_i => to_unsigned(0,8),
      green_i => to_unsigned(255,8),
      blue_i => to_unsigned(0,8),

      -- The pixel for direct output to VGA pins
      -- It is clocked at the correct pixel
      red_no => pattern_r,
      green_no => pattern_g,
      blue_no => pattern_b,      

--      red_o => panelred,
--      green_o => panelgreen,
--      blue_o => panelblue,
      
      hsync => pattern_hsync,
      vsync => pattern_vsync,  -- for HDMI
--      vga_hsync => vga_hsync,      -- for VGA          

      -- And the variations on those signals for the LCD display
--      lcd_hsync => lcd_hsync,               
--      lcd_vsync => lcd_vsync,
      fullwidth_dataenable => pattern_de
--      lcd_inletterbox => lcd_inletterbox,
--      vga_inletterbox => vga_inletterbox

      );
  

  
  hdmi0: entity work.vga_hdmi
    port map (
      clock27 => clock27,
      
      pattern_r => std_logic_vector(pattern_r),
      pattern_g => std_logic_vector(pattern_g),
      pattern_b => std_logic_vector(pattern_b),
      pattern_hsync => pattern_hsync,
      pattern_vsync => pattern_vsync,
      pattern_de => pattern_de,
      
--      vga_r => red,
--      vga_g => green,
--      vga_b => blue,
      vga_hs => hsync,
      vga_vs => vsync,

      hdmi_int => hdmi_int,
      hdmi_clk => hdmi_clk,
      hdmi_hsync => hdmi_hsync,
      hdmi_vsync => hdmi_vsync,
      hdmi_de => hdmi_de,
      hdmi_scl => hdmi_scl,
      hdmi_sda => hdmi_sda
      );

  hdmiaudio: entity work.hdmi_spdif
    generic map ( samplerate => 44100 )
    port map (
      clock27 => clock27,
      spdif_out => hdmi_spdif,
      left_in => std_logic_vector(h_audio_left),
      right_in => std_logic_vector(h_audio_right)
      );

  hyperram0: entity work.hyperram
    port map (
      pixelclock => pixelclock,
      clock163 => clock162,
      clock325 => clock325,

      -- XXX Debug by showing if expansion RAM unit is receiving requests or not
      request_counter => led,
      
      -- reset => reset_out,
      address => expansionram_address,
      wdata => expansionram_wdata,
      read_request => expansionram_read,
      write_request => expansionram_write,
      rdata => expansionram_rdata,
      data_ready_toggle_out => expansionram_data_ready_toggle,
      busy => expansionram_busy,
      hr_d => hr_d,
      hr_rwds => hr_rwds,
      hr_reset => hr_reset,
      hr_clk_p => hr_clk_p,
--      hr_clk_n => hr_clk_n,
      hr_cs0 => hr_cs0
      );

  
  PROCESS (PIXELCLOCK) IS
    variable row : unsigned(31 downto 0);
    variable thebit : unsigned(31 downto 0);
  BEGIN

    if rising_edge(pixelclock) then
      
      -- XXX Show keyboard status on screen
      if ascii_key_valid='1' then
        key_count <= key_count + 1;
      end if;
      ram_cache(15 downto 0) <= key_count;
      ram_cache(31 downto 24) <= ascii_key;
      ram_cache(23) <= ascii_key_valid;
      ram_cache(22 downto 16) <= unsigned(bucky_key);
      ram_cache(32) <= key_up;
      ram_cache(33) <= key_left;
      ram_cache(34) <= key_restore;
      ram_cache(63 downto 56) <= unsigned(widget_matrix_col);
      ram_cache(55 downto 48) <= to_unsigned(widget_matrix_col_idx,8);
      ram_cache(47) <= key_caps;
      
      -- Control hyperram
      last_expansionram_data_ready_toggle <= expansionram_data_ready_toggle;
      if expansionram_data_ready_toggle /= last_expansionram_data_ready_toggle then
        if (read_address /= ((512/8)-1)) then
          read_address <= read_address + 1;
        else
          read_address <= to_unsigned(0,8);
        end if;
              
        ram_cache(to_integer(read_address)*8+7 downto to_integer(read_address)*8+0) <= expansionram_rdata;
        expansionram_read <= '0';
        expansionram_write <= '0';
      elsif expansionram_busy = '1' then
        expansionram_read <= '0';
        expansionram_write <= '0';
      elsif (queue_ram_write = '1') and (expansionram_busy='0') then
        queue_ram_write <= '0';
        thebit := to_unsigned(ram_cell,32);
        expansionram_address <= thebit(29 downto 3);
        thebit(31 downto 3) := to_unsigned(ram_cell,29);
        thebit(2 downto 0) := "000";
        expansionram_wdata <= ram_written((to_integer(thebit)+7) downto to_integer(thebit));
        expansionram_read <= '0';
        expansionram_write <= '1';
        read_countdown <= 10;
      elsif (queue_ram_write = '0') and (expansionram_busy='0') and (read_countdown=0) then
        expansionram_address <= (others => '0');
        -- XXX DEBUG limit reading to only 4 bytes repeatedly
        expansionram_address(1 downto 0) <= read_address(1 downto 0);
        expansionram_read <= '1';
        expansionram_write <= '0';
      elsif read_countdown /= 0 then
        read_countdown <= read_countdown - 1;
      end if;
      
      
      if y_zero = '1' then
        if ycounter /= 0 then
          frame_counter <= frame_counter + 1;
          joya_idle <= fa_left and fa_right and fa_up and fa_down and fa_fire;
          if joya_idle='1' then
            if fa_left='0' then
              ram_cell <= ram_cell - 1;
            elsif fa_right='0' then
              ram_cell <= ram_cell + 1;
            elsif fa_up='0' then
              ram_cell <= ram_cell - 32;
            elsif fa_down='0' then
              ram_cell <= ram_cell + 32;
            end if;
            if fa_fire='0' then
              -- Trigger toggle of the RAM cell in question
              ram_written(ram_cell) <= not ram_written(ram_cell);
              queue_ram_write <= '1';
            end if;
          end if;
        end if;
        ycounter <= 0;
      elsif x_zero = '1' then
        xcounter <= to_unsigned(0,12);
        if xcounter /= to_unsigned(0,12) then
          ycounter <= ycounter + 1;
        end if;
      elsif pixel_strobe = '1' then
        xcounter <= xcounter + 1;
      end if;

      -- Show values read back
      if y_zero = '1' or x_zero = '1' then
        green <= x"ff";
      else
        green <= x"00";
      end if;
      blue <= x"00";
      if xcounter(3 downto 0) = "0000" and (xcounter(11 downto 4)>4) and (xcounter(11 downto 4)<=37)
        and (ycounter >=64) and (ycounter < (64+16*16)) then
        red <= x"00";
        blue <= x"ff";
      elsif to_integer(xcounter(11 downto 4)) < 37 and to_integer(xcounter(11 downto 4)) > 4 then
        row := to_unsigned(ycounter-64,32);
        blue <= x"00";
        if row(3 downto 0) = "0000" and ycounter>=64 and ycounter<=320 then
          red <= x"00";
          blue <= x"FF";
        elsif ycounter >=64 and ycounter < (64+16*16) then
          red <= (others => ram_cache(to_integer(row(31 downto 4))*32+to_integer(xcounter(11 downto 4))-5));
          blue <= (others => ram_written(to_integer(row(31 downto 4))*32+to_integer(xcounter(11 downto 4))-5));
          if ram_cell = (to_integer(row(31 downto 4))*32+to_integer(xcounter(11 downto 4))-5) then
            green <= (others => frame_counter(5));
          end if;
        end if;
      else
        red <= x"00";
      end if;
    end if;
    
    VGARED <= UNSIGNED(RED);
    VGAGREEN <= UNSIGNED(GREEN);
    VGABLUE <= UNSIGNED(BLUE);

    HDMIRED <= UNSIGNED(RED);
    hdmigreen <= unsigned(green);
    hdmiblue <= unsigned(blue);
    
    vdac_sync_n <= '0';  -- no sync on green
    vdac_blank_n <= '1'; -- was: not (v_hsync or v_vsync); 

    -- VGA output at full pixel clock
    vdac_clk <= pixelclock;

    -- Ethernet clock at 50MHz
    eth_clock <= ethclock;

    -- Make a horrible triangle wave test audio pattern
    h_audio_left <= h_audio_left + 32;
    h_audio_right <= h_audio_right + 32;

    if rising_edge(ethclock) then
      counter <= counter + 1; 

      if counter(24 downto 0) = to_unsigned(0,25) then
        reg_num(4 downto 0) <= reg_num(4 downto 0) + 1;
      end if;
      
      if counter(12 downto 0) = x"000" then
        pmod_counter <= pmod_counter + 1;
        p1lo <= std_logic_vector(pmod_counter(3 downto 0));
        p1hi <= std_logic_vector(pmod_counter(7 downto 4));

        p2lo <= std_logic_vector(pmod_counter(11 downto 8));
        p2hi <= std_logic_vector(pmod_counter(15 downto 12));

      end if;
      sd2Clock <= counter(4);
      sd2Reset <= counter(5);
      sd2MISO <= counter(6);
      sd2MOSI <= counter(7);
      sd2d1 <= counter(8);
      sd2d2 <= counter(9);
    end if;
    
  end process;    
  
end Behavioral;
