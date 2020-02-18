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

         led : out std_logic := '1';
         
         ----------------------------------------------------------------------
         -- HyperRAM as expansion RAM
         ----------------------------------------------------------------------
         hr_d : inout unsigned(7 downto 0);
         hr_rwds : inout std_logic;
         hr_reset : out std_logic;
         hr_clk_p : out std_logic;
         hr_cs0 : out std_logic
         
         );
end container;

architecture Behavioral of container is

  signal pixelclock : std_logic;
  signal ethclock : std_logic;
  signal cpuclock : std_logic;
  signal clock27 : std_logic;
  signal clock100 : std_logic;
  signal clock162 : std_logic;

  signal counter : unsigned(31 downto 0) := to_unsigned(0,32);

begin

<<<<<<< HEAD
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

=======
>>>>>>> e7d2a8ab... prune everything out except hyperram interface. #165
  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock100 => clock100,
               clock81 => pixelclock, -- 80MHz
               clock41 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock162 => clock162,
               clock27 => clock27
               );

--   hyperram0: entity work.hyperram
--     port map (
--       cpuclock => cpuclock,
--       clock240 => cpuclock,
--       -- reset => reset_out,
--       address => expansionram_address,
--       wdata => expansionram_wdata,
--       read_request => expansionram_read,
--       write_request => expansionram_write,
--       rdata => expansionram_rdata,
--       data_ready_strobe => expansionram_data_ready_strobe,
--       busy => expansionram_busy,
-- --      latency_1x => to_unsigned(4,8),
-- --      latency_2x => to_unsigned(8,8),
      
--       hr_d => hr_d,
--       hr_rwds => hr_rwds,
--       hr_reset => hr_reset,
--       hr_clk_p => hr_clk_p,
--       hr_cs0 => hr_cs0
--       );
  
<<<<<<< HEAD

  
  kbd0: entity work.mega65kbd_to_matrix
    port map (
      ioclock => cpuclock,

      powerled => key_up,
      flopled => '0',
      flopmotor => fb_fire,
            
      kio8 => kb_io0,
      kio9 => kb_io1,
      kio10 => kb_io2,

--      matrix_col => widget_matrix_col,
      matrix_col_idx => 0 -- widget_matrix_col_idx,
--      restore => widget_restore,
--      fastkey_out => fastkey,
--      capslock_out => widget_capslock,
--      upkey => keyup,
--      leftkey => keyleft
      
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
      
    ioclock       => cpuclock,
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
      BIT_TMR_MAX => to_unsigned((40000000/2000000) - 1,16),
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
      clk => clock100,
      spdif_out => hdmi_spdif,
      left_in => std_logic_vector(h_audio_left),
      right_in => std_logic_vector(h_audio_right)
      );

  PROCESS (PIXELCLOCK) IS
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
      if expansionram_data_ready_strobe='1' then
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
    if xcounter(3 downto 0) = "0000" then
      red <= x"00";      
    elsif to_integer(xcounter(11 downto 4)) < 37 and to_integer(xcounter(11 downto 4)) > 4 then
      blue <= x"00";
      if ycounter = 0 or ycounter = 64 or ycounter = 128 or ycounter = 192 or ycounter = 256 or ycounter = 320 or ycounter = 384 then
        red <= x"00";
        blue <= x"FF";
      elsif ycounter < 64 then
        red <= (others => boot_address(to_integer(xcounter(11 downto 4))-5));
      elsif ycounter < 128 then
        red <= (others => boot_address(to_integer(xcounter(11 downto 4))-5));
      elsif ycounter < 192 then
        red <= (others => boot_address(to_integer(xcounter(11 downto 4))-5));
      elsif ycounter < 256 then
        red <= (others => boot_address(to_integer(xcounter(11 downto 4))-5));
      elsif ycounter < 320 then
        red <= (others => boot_address(to_integer(xcounter(11 downto 4))-5));
      elsif ycounter < 384 then
        red <= (others => reg_num(to_integer(xcounter(11 downto 4))-5));
      else
        red <= (others => xcounter(4));
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

    if expansionram_busy='1' then
      hdmiblue <= (others => '1');
    else
      hdmiblue <= (others => '0');
    end if;
    led <= expansionram_busy;
  
    vdac_sync_n <= '0';  -- no sync on green
    vdac_blank_n <= '1'; -- was: not (v_hsync or v_vsync); 

    -- VGA output at full pixel clock
    vdac_clk <= pixelclock;

    -- Ethernet clock at 50MHz
    eth_clock <= ethclock;

    -- Make a horrible triangle wave test audio pattern
    h_audio_left <= h_audio_left + 32;
    h_audio_right <= h_audio_right + 32;

=======
  PROCESS (PIXELCLOCK) IS
  BEGIN

>>>>>>> e7d2a8ab... prune everything out except hyperram interface. #165
    if rising_edge(ethclock) then
      counter <= counter + 1; 

      -- Try waggling Hyperram pins
      hr_d <= counter(7 downto 0);
      hr_cs0 <= counter(24);
      hr_reset <= counter(25);
      hr_rwds <= counter(26);
      hr_clk_p <= counter(23);
      led <= counter(23);
      
    end if;
    
  end process;    
  
end Behavioral;
