--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 3 of the
-- *  License, or (at your option) any later version.
-- *
-- *  This program is distributed in the hope that it will be useful,
-- *  but WITHOUT ANY WARRANTY; without even the implied warranty of
-- *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- *  GNU General Public License for more details.
-- *
-- *  You should have received a copy of the GNU Lesser General Public License
-- *  along with this program; if not, write to the Free Software
-- *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
-- *  02111-1307  USA.

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
use work.victypes.all;
use work.cputypes.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity machine is
  generic (cpufrequency : integer := 50;
           target : mega65_target_t );
  Port ( pixelclock : in STD_LOGIC;
         cpuclock : in std_logic;
         clock50mhz : in std_logic;  -- normal ethernet clock
         clock100 : in std_logic;    -- Must be 2x ethernet clock
         clock27 : in std_logic;
         clock162 : in std_logic;
         ioclock : std_logic;
         uartclock : std_logic;
         btnCpuReset : in  STD_LOGIC;
         reset_out : out std_logic;
         irq : in  STD_LOGIC;
         nmi : in  STD_LOGIC;
         restore_key : in std_logic;
         osk_toggle_key : in std_logic := '1';
         joyswap_key : in std_logic := '1';
         cpu_exrom : in std_logic;
         cpu_game : in std_logic;

         fast_key : in std_logic := '1';
         
         power_down : out std_logic := '1';
         
         no_hyppo : in std_logic;

         flopled : out std_logic;
         flopmotor : out std_logic;

         buffereduart_rx : inout std_logic;
         buffereduart_tx : out std_logic := '1';
         buffereduart_ringindicate : in std_logic;
         buffereduart2_rx : inout std_logic;
         buffereduart2_tx : out std_logic := '1';
         
         slow_access_request_toggle : out std_logic;
         slow_access_ready_toggle : in std_logic := '0';
         slow_access_write : out std_logic := '0';
         slow_access_address : out unsigned(27 downto 0);
         slow_access_wdata : out unsigned(7 downto 0);
         slow_access_rdata : in unsigned(7 downto 0);
         cart_access_count : in unsigned(7 downto 0) := x"00";

         sector_buffer_mapped : inout std_logic;

         joy3 : in std_logic_vector(4 downto 0) := "11011";
         joy4 : in std_logic_vector(4 downto 0) := "10111";
         
         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vsync : out  STD_LOGIC;
         vga_hsync : out  STD_LOGIC;
         lcd_hsync : out std_logic;
         lcd_vsync : out std_logic;
         pal50_select_out : out std_logic;
         
         vgared : out  UNSIGNED (7 downto 0);
         vgagreen : out  UNSIGNED (7 downto 0);
         vgablue : out  UNSIGNED (7 downto 0);

         panelred : out  UNSIGNED (7 downto 0);
         panelgreen : out  UNSIGNED (7 downto 0);
         panelblue : out  UNSIGNED (7 downto 0);
         lcd_dataenable : out std_logic;

         hdmi_hsync : out  STD_LOGIC;
         hdmi_scl : inout std_logic;
         hdmi_sda : inout std_logic;
         hpd_a : inout std_logic;

        porto_out : out unsigned(7 downto 0);
        portp_out : out unsigned(7 downto 0);

        -------------------------------------------------------------------------
         -- CIA1 ports for keyboard and joysticks
         -------------------------------------------------------------------------
         porta_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
         portb_pins : in  std_logic_vector(7 downto 0);
         keyleft : in std_logic;
         keyup : in std_logic;
         keyboard_column8 : out std_logic;
         caps_lock_key : in std_logic;
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
         fa_potx : in std_logic;
         fa_poty : in std_logic;
         fb_potx : in std_logic;
         fb_poty : in std_logic;
         pot_drain : buffer std_logic;
         pot_via_iec : buffer std_logic;

        i2c_joya_fire : out std_logic;
        i2c_joya_up : out std_logic;
        i2c_joya_down : out std_logic;
        i2c_joya_left : out std_logic;
        i2c_joya_right : out std_logic;
        i2c_joyb_fire : out std_logic;
        i2c_joyb_up : out std_logic;
        i2c_joyb_down : out std_logic;
        i2c_joyb_left : out std_logic;
        i2c_joyb_right : out std_logic;
        i2c_button2 : out std_logic;
        i2c_button3 : out std_logic;
        i2c_button4 : out std_logic;
        i2c_black2 : out std_logic;
        i2c_black3 : out std_logic;
        i2c_black4 : out std_logic;
         
         ----------------------------------------------------------------------
         -- CBM floppy serial port
         ----------------------------------------------------------------------
         iec_clk_en : out std_logic;
         iec_data_en : out std_logic;
         iec_data_o : out std_logic;
         iec_reset : out std_logic;
         iec_clk_o : out std_logic;
         iec_atn_o : out std_logic;
         iec_data_external : in std_logic;
         iec_clk_external : in std_logic;
         
         -------------------------------------------------------------------------
         -- Lines for the SDcard interface itself
         -------------------------------------------------------------------------
         cs_bo : out std_logic;
         sclk_o : out std_logic;
         mosi_o : out std_logic;
         miso_i : in  std_logic;
         mosi2_o : out std_logic;
         miso2_i : in  std_logic;

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

         
         ---------------------------------------------------------------------------
         -- Lines for other devices that we handle here
         ---------------------------------------------------------------------------
         aclMISO : in std_logic;
         aclMOSI : out std_logic;
         aclSS : out std_logic;
         aclSCK : out std_logic;
         aclInt1 : in std_logic;
         aclInt2 : in std_logic;

         ampPWM_l : out std_logic;
         ampPWM_r : out std_logic;
         ampSD : out std_logic;
         audio_left : out std_logic_vector(19 downto 0);
         audio_right : out std_logic_vector(19 downto 0);

         micData0 : in std_logic;
         micData1 : in std_logic;
         micClk : out std_logic;
         micLRSel : out std_logic;

         -- I2S audio channels
         i2s_master_clk : out std_logic := '0';
         i2s_master_sync : out std_logic := '0';
         i2s_slave_clk : in std_logic := '0';
         i2s_slave_sync : in std_logic := '0';
         pcm_modem_clk : out std_logic := '0';
         pcm_modem_sync : out std_logic := '0';
         pcm_modem_clk_in : in std_logic := '0';
         pcm_modem_sync_in : in std_logic := '0';
         i2s_speaker_data_out : out std_logic := '0';
         pcm_modem1_data_in : in std_logic := '0';
         pcm_modem2_data_in : in std_logic := '0';
         pcm_modem1_data_out : out std_logic := '0';
         pcm_modem2_data_out : out std_logic := '0';
         i2s_bt_data_in : in std_logic := '0';
         i2s_bt_data_out : out std_logic := '0';    
         
         tmpSDA : inout std_logic;
         tmpSCL : inout std_logic;
         tmpInt : in std_logic;
         tmpCT : in std_logic;

         i2c1SDA : inout std_logic;
         i2c1SCL : inout std_logic;

         lcdpwm : out std_logic := '1';
         touchSDA : inout std_logic := '1';
         touchSCL : inout std_logic := '1';
         
         ---------------------------------------------------------------------------
         -- IO lines to the ethernet controller
         ---------------------------------------------------------------------------
         eth_mdio : inout std_logic;
         eth_mdc : out std_logic;
         eth_reset : out std_logic;
         eth_rxd : in unsigned(1 downto 0);
         eth_txd : out unsigned(1 downto 0);
         eth_txen : out std_logic;
         eth_rxdv : in std_logic;
         eth_rxer : in std_logic;
         eth_interrupt : in std_logic;
         
         fpga_temperature : in std_logic_vector(11 downto 0);
         
         ----------------------------------------------------------------------
         -- PS/2 adapted USB keyboard & joystick connector.
         -- (For using a keyrah adapter to connect to the keyboard.)
         ----------------------------------------------------------------------
         ps2data : in std_logic;
         ps2clock : in std_logic;

         ----------------------------------------------------------------------
         -- PMOD and related interfaces for keyboard, joystick, expansion port etc board.
         ----------------------------------------------------------------------

        -- Widget board / MEGA65R2 keyboard
        widget_matrix_col_idx : out integer range 0 to 8 := 0;
        widget_matrix_col : in std_logic_vector(7 downto 0);
        widget_restore : in std_logic;
        widget_capslock : in std_logic;
        widget_joya : in std_logic_vector(4 downto 0);
        widget_joyb : in std_logic_vector(4 downto 0);

         uart_rx : inout std_logic;
         uart_tx : out std_logic;
         
         -- CPU block ram debug
         -- Debugging
         debug_address_w_dbg_out : out std_logic_vector(16 downto 0);
         debug_address_r_dbg_out : out std_logic_vector(16 downto 0);
         debug_rdata_dbg_out : out std_logic_vector(7 downto 0);
         debug_wdata_dbg_out : out std_logic_vector(7 downto 0);
         debug_write_dbg_out : out std_logic;
         debug_read_dbg_out : out std_logic;
         rom_address_i_dbg_out : out std_logic_vector(16 downto 0);
         rom_address_o_dbg_out : out std_logic_vector(16 downto 0);
         rom_address_rdata_dbg_out : out std_logic_vector(7 downto 0);
         rom_address_wdata_dbg_out : out std_logic_vector(7 downto 0);
         rom_address_write_dbg_out : out std_logic;
         rom_address_read_dbg_out : out std_logic;
         debug8_state_out : out std_logic_vector(7 downto 0);
         debug4_state_out : out std_logic_vector(3 downto 0);
         proceed_dbg_out : out std_logic;
         
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
end machine;

architecture Behavioral of machine is

  component uart_monitor is
    port (
      reset : in std_logic;
      reset_out : out std_logic := '1';
      monitor_hyper_trap : out std_logic := '1';
      clock : in std_logic;
      tx : out std_logic;
      rx : in  std_logic;
      bit_rate_divisor : out unsigned(15 downto 0);
      activity : out std_logic;

      request_monitor_halt : in std_logic;
      protected_hardware_in : in unsigned(7 downto 0);
      uart_char : in unsigned(7 downto 0);
      uart_char_valid : in std_logic;
      secure_mode_from_cpu : in std_logic;
      secure_mode_from_monitor : out std_logic := '0';
      clear_matrix_mode_toggle : out std_logic := '0';

      monitor_char_out : out unsigned(7 downto 0);
      monitor_char_valid : out std_logic;
      terminal_emulator_ready : in std_logic;
      terminal_emulator_ack : in std_logic;
  
      key_scancode : out unsigned(15 downto 0);
      key_scancode_toggle : out std_logic;

      force_single_step : in std_logic;
  
      fastio_read : in std_logic;
      fastio_write : in std_logic;
      
      monitor_proceed : in std_logic;
      monitor_waitstates : in unsigned(7 downto 0);
      monitor_request_reflected : in std_logic;
      monitor_pc : in unsigned(15 downto 0);
      monitor_cpu_state : in unsigned(15 downto 0);
      monitor_hypervisor_mode : in std_logic;
      monitor_instruction : in unsigned(7 downto 0);
      monitor_watch : out unsigned(27 downto 0) := x"7FFFFFF";
      monitor_watch_match : in std_logic;
      monitor_opcode : in unsigned(7 downto 0);
      monitor_ibytes : in unsigned(3 downto 0);
      monitor_arg1 : in unsigned(7 downto 0);
      monitor_arg2 : in unsigned(7 downto 0);
      monitor_memory_access_address : in unsigned(31 downto 0);
      monitor_roms : in unsigned(7 downto 0);
      
      monitor_a : in unsigned(7 downto 0);
      monitor_x : in unsigned(7 downto 0);
      monitor_y : in unsigned(7 downto 0);
      monitor_z : in unsigned(7 downto 0);
      monitor_b : in unsigned(7 downto 0);
      monitor_sp : in unsigned(15 downto 0);
      monitor_p : in unsigned(7 downto 0);
      monitor_map_offset_low : in unsigned(11 downto 0);
      monitor_map_offset_high : in unsigned(11 downto 0);
      monitor_map_enables_low : in unsigned(3 downto 0);
      monitor_map_enables_high : in unsigned(3 downto 0);
      monitor_interrupt_inhibit : in std_logic;

      monitor_char : in unsigned(7 downto 0);
      monitor_char_toggle : in std_logic;
      monitor_char_busy : out std_logic;
      
      monitor_mem_address : out unsigned(27 downto 0);
      monitor_mem_rdata : in unsigned(7 downto 0);
      monitor_mem_wdata : out unsigned(7 downto 0);
      monitor_mem_attention_request : out std_logic := '0';
      monitor_mem_attention_granted : in std_logic;
      monitor_mem_read : out std_logic := '0';
      monitor_mem_write : out std_logic := '0';
      monitor_mem_setpc : out std_logic := '0';
      monitor_irq_inhibit : out std_logic := '0';
      monitor_mem_stage_trace_mode : out std_logic := '0';
      monitor_mem_trace_mode : out std_logic := '0';
      monitor_mem_trace_toggle : out std_logic := '0'
      );
  end component;

  signal clock2mhz : std_logic := '0';
  signal clock2mhz_i : std_logic := '0';
  signal clock2mhz_counter : integer := 0;
  
  signal pmodb_in_buffer : std_logic_vector(5 downto 0);
  signal pmodb_out_buffer : std_logic_vector(1 downto 0);

  signal fa_up_out : std_logic;
  signal fa_down_out : std_logic;
  signal fa_left_out : std_logic;
  signal fa_right_out : std_logic;
  signal fb_up_out : std_logic;
  signal fb_down_out : std_logic;
  signal fb_left_out : std_logic;
  signal fb_right_out : std_logic;
  
  signal key_scancode : unsigned(15 downto 0);
  signal key_scancode_toggle : std_logic;

  signal xray_mode : std_logic;
  
  signal cpu_hypervisor_mode : std_logic;

  signal reg_isr_out : unsigned(7 downto 0);
  signal imask_ta_out : std_logic;
  
  signal cpu_leds : std_logic_vector(3 downto 0);
  
  signal viciii_iomode : std_logic_vector(1 downto 0);

  signal iomode_set : std_logic_vector(1 downto 0);
  signal iomode_set_toggle : std_logic;

  signal vicii_2mhz : std_logic;
  signal viciii_fast : std_logic;
  signal viciv_fast : std_logic;
  signal speed_gate : std_logic;
  signal speed_gate_enable : std_logic;
  signal badline_toggle : std_logic;
  
  signal drive_led : std_logic;
  signal motor : std_logic;
  
  signal seg_led_data : unsigned(31 downto 0);

  signal reset_io : std_logic;
  signal reset_monitor : std_logic;
  -- Holds reset on for 8 cycles so that reset line entry is used on start up,
  -- instead of implicit startup state.
  -- (Note that uart_monitor actually holds reset low for ~5 usec on power on,
  --  i.e., for much longer than this here provides).
  signal power_on_reset : std_logic_vector(7 downto 0) := (others => '0');
  signal reset_combined : std_logic := '1';
  
  signal io_irq : std_logic;
  signal io_nmi : std_logic;
  signal vic_irq : std_logic;
  signal combinedirq : std_logic;
  signal combinednmi : std_logic;
  signal restore_nmi : std_logic;
  signal hyper_trap : std_logic := '1';
  signal hyper_trap_combined : std_logic := '1';
  signal monitor_hyper_trap : std_logic := '1';
  signal hyper_trap_f011_read : std_logic := '0';
  signal hyper_trap_f011_write : std_logic := '0';
  signal hyper_trap_count : unsigned(7 downto 0) := x"00";

  signal fastio_addr : std_logic_vector(19 downto 0);
  signal fastio_addr_fast : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);
  signal hyppo_rdata : std_logic_vector(7 downto 0);
  signal hyppo_address : std_logic_vector(13 downto 0);
  
  signal fastio_vic_rdata : std_logic_vector(7 downto 0);
  signal colour_ram_fastio_rdata : std_logic_vector(7 downto 0);

  --signal chipram_we : STD_LOGIC;
  signal chipram_address : unsigned(19 DOWNTO 0);
  signal chipram_data : unsigned(7 DOWNTO 0);
  
  signal rom_at_e000 : std_logic := '0';
  signal rom_at_c000 : std_logic := '0';
  signal rom_at_a000 : std_logic := '0';
  signal rom_at_8000 : std_logic := '0';

  signal colourram_at_dc00 : std_logic := '0';
  signal colour_ram_cs : std_logic := '0';
  signal charrom_write_cs : std_logic := '0';

  signal monitor_instruction_strobe : std_logic;
  signal monitor_pc : unsigned(15 downto 0);
  signal monitor_hypervisor_mode : std_logic;
  signal monitor_state : unsigned(15 downto 0);
  signal monitor_instruction : unsigned(7 downto 0);
  signal monitor_instructionpc : unsigned(15 downto 0);
  signal monitor_watch : unsigned(27 downto 0);
--  signal monitor_debug_memory_access : std_logic_vector(31 downto 0);
  signal monitor_proceed : std_logic;
  signal monitor_waitstates : unsigned(7 downto 0);
  signal monitor_request_reflected : std_logic;
  signal monitor_watch_match : std_logic;
  signal monitor_mem_address : unsigned(27 downto 0);
  signal monitor_mem_rdata : unsigned(7 downto 0);
  signal monitor_mem_wdata : unsigned(7 downto 0);
  signal monitor_map_offset_low : unsigned(11 downto 0);
  signal monitor_map_offset_high : unsigned(11 downto 0);
  signal monitor_map_enables_low : unsigned(3 downto 0);
  signal monitor_map_enables_high : unsigned(3 downto 0);   
  signal monitor_mem_read : std_logic;
  signal monitor_mem_write : std_logic;
  signal monitor_mem_setpc : std_logic;
  signal monitor_mem_attention_request : std_logic;
  signal monitor_mem_attention_granted : std_logic;
  signal monitor_mem_stage_trace_mode : std_logic;
  signal monitor_irq_inhibit : std_logic;
  signal monitor_mem_trace_mode : std_logic;
  signal monitor_mem_trace_toggle : std_logic;
  signal monitor_memory_access_address : unsigned(31 downto 0);
  signal monitor_char : unsigned(7 downto 0);
  signal monitor_char_toggle : std_logic;
  signal monitor_char_busy : std_logic;
  signal monitor_cpuport : unsigned(2 downto 0);
  signal monitor_roms : unsigned(7 downto 0);
  
  signal monitor_a : unsigned(7 downto 0);
  signal monitor_b : unsigned(7 downto 0);
  signal monitor_interrupt_inhibit : std_logic;
  signal monitor_x : unsigned(7 downto 0);
  signal monitor_y : unsigned(7 downto 0);
  signal monitor_z : unsigned(7 downto 0);
  signal monitor_sp : unsigned(15 downto 0);
  signal monitor_p : unsigned(7 downto 0);
  signal monitor_opcode : unsigned(7 downto 0);
  signal monitor_ibytes : unsigned(3 downto 0);
  signal monitor_arg1 : unsigned(7 downto 0);
  signal monitor_arg2 : unsigned(7 downto 0);

  signal cpuis6502 : std_logic;
  signal cpuspeed : unsigned(7 downto 0);

  signal segled_counter : unsigned(19 downto 0) := (others => '0');

  signal phi : std_logic := '0';

  -- Video pipeline plumbing
  signal pixel_x_viciv : integer;
  signal pixel_strobe_viciv : std_logic := '0';
  signal vgared_viciv : unsigned(7 downto 0);
  signal vgagreen_viciv : unsigned(7 downto 0);
  signal vgablue_viciv : unsigned(7 downto 0);

  signal vgared_rain : unsigned(7 downto 0);
  signal vgagreen_rain : unsigned(7 downto 0);
  signal vgablue_rain : unsigned(7 downto 0);

  signal pixel_strobe_osk : std_logic := '0';
  signal vgared_osk : unsigned(7 downto 0);
  signal vgagreen_osk : unsigned(7 downto 0);
  signal vgablue_osk : unsigned(7 downto 0);
  
  signal pixel_stream : unsigned (7 downto 0);
  signal pixel_red : unsigned (7 downto 0);
  signal pixel_green : unsigned (7 downto 0);
  signal pixel_blue : unsigned (7 downto 0);
  signal pixel_y : unsigned (11 downto 0);
  signal vicii_raster : unsigned (11 downto 0);
  signal pixel_newframe : std_logic;
  signal pixel_newraster : std_logic;

  signal uart_tx_buffer : std_logic; 
  signal uart_rx_buffer : std_logic;
  signal protected_hardware_sig : unsigned(7 downto 0);
  signal virtualised_hardware_sig : unsigned(7 downto 0);
  signal chipselect_enables : std_logic_vector(7 downto 0);

  -- Matrix Mode signals
  signal scancode_out : std_logic_vector(12 downto 0); 
  signal mm_displayMode : unsigned(1 downto 0):=b"10"; 
  signal bit_rate_divisor : unsigned(15 downto 0);

  signal matrix_fetch_address : unsigned(11 downto 0) := to_unsigned(0,12);
  signal matrix_rdata : unsigned(7 downto 0);

  signal lcd_inletterbox : std_logic := '0';
  signal vga_inletterbox : std_logic := '0';
  signal lcd_dataenable_internal : std_logic := '0';

  signal pal50_select : std_logic := '0';
  signal vga60_select : std_logic := '0';
  signal hsync_polarity : std_logic := '0';
  signal vsync_polarity : std_logic := '0';

  signal external_pixel_strobe : std_logic := '0';
  signal external_frame_x_zero : std_logic := '0';
  signal external_frame_y_zero : std_logic := '0';
  
  signal xcounter_viciv : integer;
  signal ycounter_viciv : integer;
  signal xcounter_viciv_u : unsigned(11 downto 0);
  signal ycounter_viciv_u : unsigned(11 downto 0);
  
  signal uart_txd_sig : std_logic;
  signal display_shift : std_logic_vector(2 downto 0) := "000";
  signal shift_ready : std_logic := '0';
  signal shift_ack : std_logic := '0'; 
  signal matrix_trap : std_logic;  
  signal uart_char : unsigned(7 downto 0);
  signal uart_char_valid : std_logic := '0';
  signal uart_monitor_char : unsigned(7 downto 0);
  signal uart_monitor_char_valid : std_logic := '0';
  signal monitor_char_out : unsigned(7 downto 0);
  signal monitor_char_out_valid : std_logic := '0';
  signal terminal_emulator_ready : std_logic := '0';
  signal terminal_emulator_ack : std_logic := '0';

  signal osk_debug_display : std_logic;
  signal visual_keyboard_enable : std_logic;
  signal zoom_en_osk : std_logic;
  signal zoom_en_always : std_logic;
  signal keyboard_at_top : std_logic;
  signal alternate_keyboard : std_logic;
  signal osk_ystart : unsigned(11 downto 0); 
  
  signal osk_x : unsigned(11 downto 0);
  signal osk_y : unsigned(11 downto 0);
  signal osk_key1 : unsigned(7 downto 0);
  signal osk_key2 : unsigned(7 downto 0);
  signal osk_key3 : unsigned(7 downto 0);
  signal osk_key4 : unsigned(7 downto 0);
  
  signal osk_touch1_valid : std_logic := '0';
  signal osk_touch1_x : unsigned(13 downto 0) := to_unsigned(0,14);
  signal osk_touch1_y : unsigned(11 downto 0) := to_unsigned(0,12);
  signal osk_touch1_key : unsigned(7 downto 0) := x"FF";
  signal osk_touch1_key_driver : unsigned(7 downto 0) := x"FF";
  signal osk_touch2_valid : std_logic := '0';
  signal osk_touch2_x : unsigned(13 downto 0) := to_unsigned(0,14);
  signal osk_touch2_y : unsigned(11 downto 0) := to_unsigned(0,12);
  signal osk_touch2_key : unsigned(7 downto 0) := x"FF";
  signal osk_touch2_key_driver : unsigned(7 downto 0) := x"FF";

  signal secure_mode_flag : std_logic := '0';
  signal secure_mode_from_monitor : std_logic := '0';
  signal secure_mode_triage_required : std_logic := '0';
  signal clear_matrix_mode_toggle : std_logic := '0';
  signal matrix_rain_seed : unsigned(15 downto 0);
  
  signal all_pause : std_logic := '0';

  signal dat_even : std_logic;
  signal dat_offset : unsigned(15 downto 0);
  signal dat_bitplane_addresses : sprite_vector_eight;  

  signal pota_x : unsigned(7 downto 0);
  signal pota_y : unsigned(7 downto 0);
  signal potb_x : unsigned(7 downto 0);
  signal potb_y : unsigned(7 downto 0);
  
  signal mouse_debug : unsigned(7 downto 0);
  signal amiga_mouse_enable_a : std_logic;
  signal amiga_mouse_enable_b : std_logic;
  signal amiga_mouse_assume_a : std_logic;
  signal amiga_mouse_assume_b : std_logic;

  -- local debug signals from CPU
  signal shadow_address_state_dbg_out : std_logic_vector(3 downto 0);

  signal test_pattern_enable : std_logic := '0';

  signal ethernet_cpu_arrest : std_logic := '0';

  signal d031_write_toggle : std_logic;

  signal request_monitor_halt : std_logic;

  signal viciv_frame_indicate : std_logic;
  
begin

  lcd_dataenable <= lcd_dataenable_internal;
  
  xcounter_viciv_u <= to_unsigned(xcounter_viciv,12);
  ycounter_viciv_u <= to_unsigned(ycounter_viciv,12);
  
  monitor_roms(7) <= colourram_at_dc00;
  monitor_roms(6) <= rom_at_e000;
  monitor_roms(5) <= rom_at_c000;
  monitor_roms(4) <= rom_at_a000;
  monitor_roms(3) <= rom_at_8000;
  monitor_roms(2 downto 0) <= monitor_cpuport;
  
  ----------------------------------------------------------------------------
  -- IRQ & NMI: If either the hardware buttons on the FPGA board or an IO
  -- device via the IOmapper pull an interrupt line down, then trigger an
  -- interrupt.
  -----------------------------------------------------------------------------
  process(irq,nmi,restore_nmi,io_irq,vic_irq,io_nmi,sw,reset_io,btnCpuReset,
          power_on_reset,reset_monitor,hyper_trap)
  begin
    -- XXX Allow switch 0 to mask IRQs
    combinedirq <= ((irq and io_irq and vic_irq) or sw(0));
    combinednmi <= (nmi and io_nmi and restore_nmi) or sw(14);
    if btnCpuReset='0' then
      report "reset asserted via btnCpuReset";
      reset_combined <= '0';
    elsif reset_io='0' then
      report "reset asserted via reset_io";
      reset_combined <= '0';
    elsif power_on_reset(0)='0' then
      report "reset asserted via power_on_reset(0)";
      reset_combined <= '0';
    elsif reset_monitor='0' then
      report "reset asserted via reset_monitor = " & std_logic'image(reset_monitor);
      reset_combined <= '0';
    else
      report "reset_combined not asserted";
      reset_combined <= '1';
    end if;

    hyper_trap_combined <= hyper_trap and monitor_hyper_trap;
    
  -- report "btnCpuReset = " & std_logic'image(btnCpuReset) & ", reset_io = " & std_logic'image(reset_io) & ", sw(15) = " & std_logic'image(sw(15)) severity note;
    report "reset_combined = " & std_logic'image(reset_combined) severity note;
  end process;
  
  process(pixelclock,ioclock)
    variable digit : std_logic_vector(3 downto 0);
  begin
    if rising_edge(pixelclock) then
      report "external_pixel_strobe = " & std_logic'image(external_pixel_strobe);
    end if;
    if rising_edge(ioclock) then
      -- Hold reset low for a while when we first turn on
--      report "power_on_reset(0) = " & std_logic'image(power_on_reset(0)) severity note;
      power_on_reset(7) <= '1';
      power_on_reset(6 downto 0) <= power_on_reset(7 downto 1);

      pal50_select_out <= pal50_select;
      
      led(0) <= irq;
      led(1) <= nmi;
      led(2) <= combinedirq;
      led(3) <= combinednmi;
      led(4) <= io_irq;
      led(5) <= io_nmi;
      led(6) <= external_pixel_strobe;
      led(7) <= external_frame_x_zero;      
      led(8) <= external_frame_y_zero;      
      led(9) <= drive_led;
      led(10) <= cpu_hypervisor_mode;
      led(11) <= hyper_trap;
      led(12) <= hyper_trap_combined;
      led(13) <= speed_gate;
      led(14) <= speed_gate_enable;
      led(15) <= motor;

      xray_mode <= sw(1);
      
      segled_counter <= segled_counter + 1;

      sseg_an <= (others => '1');
      sseg_an(to_integer(segled_counter(17 downto 15))) <= '0';

      --if segled_counter(17 downto 15)=0 then
      --  digit := std_logic_vector(monitor_pc(3 downto 0));
      --elsif segled_counter(17 downto 15)=1 then
      --  digit := std_logic_vector(monitor_pc(7 downto 4));
      --elsif segled_counter(17 downto 15)=2 then
      --  digit := std_logic_vector(monitor_pc(11 downto 8));
      --elsif segled_counter(17 downto 15)=3 then
      --  digit := std_logic_vector(monitor_pc(15 downto 12));
      --elsif segled_counter(17 downto 15)=4 then
      --  digit := std_logic_vector(monitor_state(3 downto 0));
      --elsif segled_counter(17 downto 15)=5 then
      --  digit := std_logic_vector(monitor_state(7 downto 4));
      --elsif segled_counter(17 downto 15)=6 then
      --  digit := std_logic_vector(monitor_state(11 downto 8));
      --elsif segled_counter(17 downto 15)=7 then
      --  digit := std_logic_vector(monitor_state(15 downto 12));
      --end if;
      --if segled_counter(17 downto 15)=0 then
      --  digit := std_logic_vector(slowram_addr_reflect(3 downto 0));
      --elsif segled_counter(17 downto 15)=1 then
      --  digit := std_logic_vector(slowram_addr_reflect(7 downto 4));
      --elsif segled_counter(17 downto 15)=2 then
      --  digit := std_logic_vector(slowram_addr_reflect(11 downto 8));
      --elsif segled_counter(17 downto 15)=3 then
      --  digit := std_logic_vector(slowram_addr_reflect(15 downto 12));
      --elsif segled_counter(17 downto 15)=4 then
      --  digit := std_logic_vector(slowram_addr_reflect(19 downto 16));
      --elsif segled_counter(17 downto 15)=5 then
      --  digit := std_logic_vector(slowram_addr_reflect(23 downto 20));
      --elsif segled_counter(17 downto 15)=6 then
      --  digit := '1'&std_logic_vector(slowram_addr_reflect(26 downto 24));
      --elsif segled_counter(17 downto 15)=7 then
      --  digit := std_logic_vector(slowram_datain_reflect(3 downto 0));
      --end if;
      if segled_counter(17 downto 15)=0 then
        digit := std_logic_vector(seg_led_data(3 downto 0));
      elsif segled_counter(17 downto 15)=1 then
        digit := std_logic_vector(seg_led_data(7 downto 4));
      elsif segled_counter(17 downto 15)=2 then
        digit := std_logic_vector(seg_led_data(11 downto 8));
      elsif segled_counter(17 downto 15)=3 then
        digit := std_logic_vector(seg_led_data(15 downto 12));
      elsif segled_counter(17 downto 15)=4 then
        digit := std_logic_vector(seg_led_data(19 downto 16));
      elsif segled_counter(17 downto 15)=5 then
        digit := std_logic_vector(seg_led_data(23 downto 20));
      elsif segled_counter(17 downto 15)=6 then
        digit := std_logic_vector(seg_led_data(27 downto 24));
      elsif segled_counter(17 downto 15)=7 then
        digit := std_logic_vector(seg_led_data(31 downto 28));
      end if;
      
      seg_led_data(31 downto 24) <= cpuspeed;
      if cpuis6502 = '1' then
        seg_led_data(23 downto 16) <= x"65";
      else
        seg_led_data(23 downto 16) <= x"45";
      end if;
      -- XXX temporary debug
      seg_led_data(23 downto 16) <= protected_hardware_sig;
      seg_led_data(15 downto 8) <= uart_char;
      seg_led_data(7 downto 0) <= uart_monitor_char;      
      
      -- segments are:
      -- 7 - decimal point
      -- 6 - middle
      -- 5 - upper left
      -- 4 - lower left
      -- 3 - bottom
      -- 2 - lower right
      -- 1 - upper right
      -- 0 - top
      case digit is
        when x"0" => sseg_ca <= "11000000";
        when x"1" => sseg_ca <= "11111001";
        when x"2" => sseg_ca <= "10100100";
        when x"3" => sseg_ca <= "10110000";
        when x"4" => sseg_ca <= "10011001";
        when x"5" => sseg_ca <= "10010010";
        when x"6" => sseg_ca <= "10000010";
        when x"7" => sseg_ca <= "11111000";
        when x"8" => sseg_ca <= "10000000";
        when x"9" => sseg_ca <= "10010000";
        when x"A" => sseg_ca <= "10001000";
        when x"B" => sseg_ca <= "10000011";
        when x"C" => sseg_ca <= "11000110";
        when x"D" => sseg_ca <= "10100001";
        when x"E" => sseg_ca <= "10000110";
        when x"F" => sseg_ca <= "10001110";
        when others => sseg_ca <= "10100001";
      end case; 
      

    end if;
    if rising_edge(pixelclock) then
      
      null;
      
    end if;
  end process;

  cpu0: entity work.gs4510
    generic map(
      cpufrequency => cpufrequency,
      target => target)
    port map(
      phi_in => phi,
      all_pause => all_pause,
      matrix_trap_in=>matrix_trap,
      request_monitor_halt => request_monitor_halt,
      protected_hardware => protected_hardware_sig,
      virtualised_hardware => virtualised_hardware_sig,
      chipselect_enables => chipselect_enables,
      mathclock => cpuclock,
      clock => cpuclock,
      ioclock => ioclock,
      reset =>reset_combined,
      reset_out => reset_out,
      irq => combinedirq,
      nmi => combinednmi,
      exrom => cpu_exrom,
      power_down => power_down,
      game => cpu_game,
      hyper_trap => hyper_trap_combined,
      hyper_trap_f011_read => hyper_trap_f011_read,
      hyper_trap_f011_write => hyper_trap_f011_write,
      speed_gate => speed_gate,
      speed_gate_enable => speed_gate_enable,
      cpuis6502 => cpuis6502,
      cpuspeed => cpuspeed,
      ethernet_cpu_arrest => ethernet_cpu_arrest,
      secure_mode_out => secure_mode_flag,
      secure_mode_from_monitor => secure_mode_from_monitor,
      clear_matrix_mode_toggle => clear_matrix_mode_toggle,
      matrix_rain_seed => matrix_rain_seed,
      dat_offset => dat_offset,
      dat_even => dat_even,
      dat_bitplane_addresses => dat_bitplane_addresses,

      fast_key => fast_key,
      
      debug_address_w_dbg_out => debug_address_w_dbg_out,
      debug_address_r_dbg_out => debug_address_r_dbg_out,
      debug_rdata_dbg_out => debug_rdata_dbg_out,
      debug_wdata_dbg_out => debug_wdata_dbg_out,
      debug_write_dbg_out => debug_write_dbg_out,
      debug_read_dbg_out => debug_read_dbg_out,
      debug4_state_out => debug4_state_out,
      
      proceed_dbg_out => proceed_dbg_out,
      
      irq_hypervisor => sw(4 downto 2),    -- JBM
      
      -- Hypervisor signals: we need to tell hyppo memory whether
      -- to map or not, and we also need to be able to set the VIC-III
      -- IO mode.
      cpu_hypervisor_mode => cpu_hypervisor_mode,
      iomode_set => iomode_set,
      iomode_set_toggle => iomode_set_toggle,
      
      no_hyppo => no_hyppo,
      
      reg_isr_out => reg_isr_out,
      imask_ta_out => imask_ta_out,
      
      vicii_2mhz => vicii_2mhz,
      viciii_fast => viciii_fast,
      viciv_fast => viciv_fast,
      badline_toggle => badline_toggle,

      monitor_char => monitor_char,
      monitor_char_toggle => monitor_char_toggle,
      monitor_char_busy => monitor_char_busy,

      monitor_instruction_strobe => monitor_instruction_strobe,
      monitor_proceed => monitor_proceed,
--    monitor_debug_memory_access => monitor_debug_memory_access,
      monitor_waitstates => monitor_waitstates,
      monitor_request_reflected => monitor_request_reflected,
      monitor_hypervisor_mode => monitor_hypervisor_mode,
      monitor_pc => monitor_pc,
      monitor_watch => monitor_watch,
      monitor_watch_match => monitor_watch_match,
      monitor_opcode => monitor_opcode,
      monitor_ibytes => monitor_ibytes,
      monitor_arg1 => monitor_arg1,
      monitor_arg2 => monitor_arg2,
      monitor_a => monitor_a,
      monitor_b => monitor_b,
      monitor_x => monitor_x,
      monitor_y => monitor_y,
      monitor_z => monitor_z,
      monitor_sp => monitor_sp,
      monitor_p => monitor_p,
      monitor_state => monitor_state,
      monitor_map_offset_low => monitor_map_offset_low,
      monitor_map_offset_high => monitor_map_offset_high,
      monitor_map_enables_low => monitor_map_enables_low,
      monitor_map_enables_high => monitor_map_enables_high,
      monitor_memory_access_address => monitor_memory_access_address,

      monitor_mem_address => monitor_mem_address,
      monitor_mem_rdata => monitor_mem_rdata,
      monitor_mem_wdata => monitor_mem_wdata,
      monitor_mem_read => monitor_mem_read,
      monitor_mem_write => monitor_mem_write,
      monitor_mem_setpc => monitor_mem_setpc,
      monitor_mem_attention_request => monitor_mem_attention_request,
      monitor_mem_attention_granted => monitor_mem_attention_granted,
      monitor_irq_inhibit => monitor_irq_inhibit,
      monitor_mem_trace_mode => monitor_mem_trace_mode,
      monitor_mem_stage_trace_mode => monitor_mem_stage_trace_mode,
      monitor_mem_trace_toggle => monitor_mem_trace_toggle,
      monitor_cpuport => monitor_cpuport,
      
      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,    
      slow_access_address => slow_access_address,
      slow_access_write => slow_access_write,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,
      
      chipram_clk => pixelclock,
      chipram_address => chipram_address,
      chipram_dataout => chipram_data,

      cpu_leds => cpu_leds,
      
      fastio_addr => fastio_addr,
      fastio_addr_fast => fastio_addr_fast,
      fastio_read => fastio_read,
      fastio_write => fastio_write,
      fastio_wdata => fastio_wdata,
      fastio_rdata => fastio_rdata,
      sector_buffer_mapped => sector_buffer_mapped,
      fastio_vic_rdata => fastio_vic_rdata,
      fastio_colour_ram_rdata => colour_ram_fastio_rdata,
      hyppo_rdata => hyppo_rdata,
      hyppo_address_out => hyppo_address,
      colour_ram_cs => colour_ram_cs,
      charrom_write_cs => charrom_write_cs,

      viciii_iomode => viciii_iomode,
      
      colourram_at_dc00 => colourram_at_dc00,
      rom_at_e000 => rom_at_e000,
      rom_at_c000 => rom_at_c000,
      rom_at_a000 => rom_at_a000,
      rom_at_8000 => rom_at_8000

      );

  pixel0: entity work.pixel_driver
    port map (
               clock81 => pixelclock, -- 80MHz
               clock162 => clock162,
               clock27 => clock27,

               cpuclock => cpuclock,

               phi_out => phi,

      pixel_strobe_out => external_pixel_strobe,
      
      -- Configuration information from the VIC-IV
      hsync_invert => hsync_polarity,
      vsync_invert => vsync_polarity,
               pal50_select => pal50_select,
               vga60_select => vga60_select,
      test_pattern_enable => test_pattern_enable,      
      
      -- Framing information for VIC-IV
      x_zero => external_frame_x_zero,     
      y_zero => external_frame_y_zero,     

      -- Pixel data from the video pipeline
      -- (clocked at 100MHz pixel clock)
      red_i => vgared_osk,
      green_i => vgagreen_osk,
      blue_i => vgablue_osk,

      -- The pixel for direct output to VGA pins
      -- It is clocked at the correct pixel
      red_no => vgared,
      green_no => vgagreen,
      blue_no => vgablue,      

      red_o => panelred,
      green_o => panelgreen,
      blue_o => panelblue,
               
      hsync => hdmi_hsync,
      vsync => vsync,  -- for HDMI
      vga_hsync => vga_hsync,      -- for VGA          

      -- And the variations on those signals for the LCD display
      lcd_hsync => lcd_hsync,               
      lcd_vsync => lcd_vsync,
      fullwidth_dataenable => lcd_dataenable_internal,
      lcd_inletterbox => lcd_inletterbox,
      vga_inletterbox => vga_inletterbox

      );
      
      
  viciv0: entity work.viciv
    port map (
      pixelclock      => pixelclock,
      cpuclock        => cpuclock,
      ioclock        => ioclock,
      all_pause => all_pause,

      viciv_frame_indicate => viciv_frame_indicate,
      
      hypervisor_mode => cpu_hypervisor_mode,
      
      irq             => vic_irq,
      reset           => reset_combined,

      touch_active => osk_touch1_valid,
      touch_x => osk_touch1_x,    
      touch_y => osk_touch1_y,
      
      -- Configuration information for pixel_driver
      pal50_select => pal50_select,
      vga60_select => vga60_select,
      vsync_polarity => vsync_polarity,
      hsync_polarity => hsync_polarity,

      -- Framing information from pixel_driver
      external_pixel_strobe_in => external_pixel_strobe,
      external_frame_x_zero => external_frame_x_zero,
      external_frame_y_zero => external_frame_y_zero,
      vga_in_frame => vga_inletterbox,

      -- Pixels output for the video pipeline
      pixel_strobe_out => pixel_strobe_viciv,
      pixel_x_out => pixel_x_viciv,
      vgared          => vgared_viciv,
      vgagreen        => vgagreen_viciv,
      vgablue         => vgablue_viciv,

      -- Framing information for the video pipeline
      xcounter_out => xcounter_viciv,
      ycounter_out => ycounter_viciv,

      test_pattern_enable => test_pattern_enable,
      
      led => '0',
      motor => '0',

      xray_mode => xray_mode,
      d031_written => d031_write_toggle,

      dat_even => dat_even,
      dat_offset => dat_offset,
      dat_bitplane_addresses => dat_bitplane_addresses,
     
      -- Pixel stream to ethernet video packer
      pixel_stream_out => pixel_stream,
      pixel_red_out => pixel_red,
      pixel_green_out => pixel_green,
      pixel_blue_out => pixel_blue,
      pixel_y => pixel_y,
      pixel_newframe => pixel_newframe,
      pixel_newraster => pixel_newraster,
      vicii_raster_out => vicii_raster,

      --chipram_we => chipram_we,
      chipram_address => chipram_address,
      chipram_datain => chipram_data,
      colour_ram_fastio_rdata => colour_ram_fastio_rdata,
      colour_ram_cs => colour_ram_cs,
      charrom_write_cs => charrom_write_cs,

      fastio_addr     => fastio_addr,
      fastio_read     => fastio_read,
      fastio_write    => fastio_write,
      fastio_wdata    => fastio_wdata,
      fastio_rdata    => fastio_vic_rdata,
      
      viciii_iomode => viciii_iomode,
      iomode_set_toggle => iomode_set_toggle,
      iomode_set => iomode_set,
      vicii_2mhz => vicii_2mhz,
      viciii_fast => viciii_fast,
      viciv_fast => viciv_fast,
      badline_toggle => badline_toggle,
      
      colourram_at_dc00 => colourram_at_dc00,
      rom_at_e000 => rom_at_e000,
      rom_at_c000 => rom_at_c000,
      rom_at_a000 => rom_at_a000,
      rom_at_8000 => rom_at_8000      
      );


  matrix_compositor0 : entity work.matrix_rain_compositor port map(
    clk => uartclock,
    pixelclock => pixelclock,
    pal_mode => pal50_select,
    
    monitor_char_in => monitor_char_out,
    monitor_char_valid => monitor_char_out_valid,
    terminal_emulator_ready => terminal_emulator_ready,
    terminal_emulator_ack => terminal_emulator_ack,

    matrix_rdata => matrix_rdata,
    matrix_fetch_address => matrix_fetch_address,
    seed => matrix_rain_seed,

    external_frame_x_zero => external_frame_x_zero,
    external_frame_y_zero => external_frame_y_zero,
    ycounter_in => ycounter_viciv_u,
    xcounter_in => xcounter_viciv,
    
    lcd_in_letterbox => lcd_inletterbox,
    pixel_y_scale_200 => to_unsigned(2,4),
    pixel_y_scale_400 => to_unsigned(1,4),
    osk_ystart => osk_ystart,
    visual_keyboard_enable => visual_keyboard_enable,
    keyboard_at_top => keyboard_at_top,

    matrix_mode_enable => protected_hardware_sig(6),--sw(5),
    secure_mode_flag =>  secure_mode_triage_required,

    vgared_in => vgared_viciv,
    vgagreen_in => vgagreen_viciv,
    vgablue_in => vgablue_viciv,

    vgared_out => vgared_rain,
    vgagreen_out => vgagreen_rain,
    vgablue_out => vgablue_rain
    );

  visual_keyboard0 : entity work.visual_keyboard
    port map(
      pixelclock => pixelclock,

      ycounter_in => ycounter_viciv,
      xcounter_in => xcounter_viciv,
      
      -- Used as proxy for whether there we are in frame vs in border
      -- (visual keyboard is only for LCD display, so this makes sense
      -- here).
      lcd_display_enable => lcd_dataenable_internal,
      
      -- Pixels from video pipeline
      pixel_strobe_in => pixel_strobe_viciv,
      vgared_in => vgared_rain,
      vgagreen_in => vgagreen_rain,
      vgablue_in => vgablue_rain,

      -- Pixels output
      pixel_strobe_out => pixel_strobe_osk,
      vgared_out => vgared_osk,
      vgagreen_out => vgagreen_osk,
      vgablue_out => vgablue_osk,

      -- Configuration for the visual keyboard
      visual_keyboard_enable => visual_keyboard_enable,
      osk_debug_display => osk_debug_display,
      zoom_en_osk => zoom_en_osk,
      zoom_en_always => zoom_en_always,
      keyboard_at_top => keyboard_at_top,
      alternate_keyboard => alternate_keyboard,
      instant_at_top => '0',

      -- Current position of the visual keyboard
      osk_ystart => osk_ystart,

      -- Touch screen input status
      key1 => osk_key1,
      key2 => osk_key2,
      key3 => osk_key3,
      key4 => osk_key4,
      touch1_valid => osk_touch1_valid,
      touch1_x => osk_touch1_x,    
      touch1_y => osk_touch1_y,
      touch1_key => osk_touch1_key_driver,
      touch2_valid => osk_touch2_valid,
      touch2_x => osk_touch2_x,    
      touch2_y => osk_touch2_y,
      touch2_key => osk_touch2_key_driver,

      -- Access to the BRAM with the matrix characters etc for drawing
      matrix_fetch_address => matrix_fetch_address,
      matrix_rdata => matrix_rdata
    
    );
  

  
  mouse0: entity work.mouse_input
    port map (
      clk => ioclock,

      mouse_debug => mouse_debug,
      amiga_mouse_enable_a => amiga_mouse_enable_a,
      amiga_mouse_enable_b => amiga_mouse_enable_b,
      amiga_mouse_assume_a => amiga_mouse_assume_a,
      amiga_mouse_assume_b => amiga_mouse_assume_b,
      
      -- These are the 1351 mouse / C64 paddle inputs and drain control
      pot_drain => pot_drain,
      fa_potx => fa_potx,
      fa_poty => fa_poty,
      fb_potx => fb_potx,
      fb_poty => fb_poty,

      -- To allow auto-detection of Amiga mouses, we need to know what the
      -- rest of the joystick pins are doing
      fa_fire => fa_fire,
      fa_left => fa_left,
      fa_right => fa_right,
      fa_up => fa_up,
      fa_down => fa_down,
      fb_fire => fb_fire,
      fb_left => fb_left,
      fb_right => fb_right,
      fb_up => fb_up,
      fb_down => fb_down,

      fa_up_out => fa_up_out,
      fa_down_out => fa_down_out,
      fa_left_out => fa_left_out,
      fa_right_out => fa_right_out,

      fb_up_out => fb_up_out,
      fb_down_out => fb_down_out,
      fb_left_out => fb_left_out,
      fb_right_out => fb_right_out,
      
      -- We output the four sampled pot values
      pota_x => pota_x,
      pota_y => pota_y,
      potb_x => potb_x,
      potb_y => potb_y
      );
  
  iomapper0: entity work.iomapper
    generic map ( target => target )
    port map (
      clk => ioclock,
      clock100mhz => clock100,
      clock2mhz => clock2mhz,
      cpuspeed => cpuspeed,      
      protected_hardware_in => protected_hardware_sig,
      virtualised_hardware_in => virtualised_hardware_sig,
      chipselect_enables => chipselect_enables,
      matrix_mode_trap => matrix_trap,
      hyper_trap => hyper_trap,
      hyper_trap_f011_read => hyper_trap_f011_read,
      hyper_trap_f011_write => hyper_trap_f011_write,
      hyper_trap_count => hyper_trap_count,
      viciv_frame_indicate => viciv_frame_indicate,      
      cpuclock => cpuclock,
      pixelclk => pixelclock,
      clock50mhz => clock50mhz,
      cpu_hypervisor_mode => cpu_hypervisor_mode,
      speed_gate => speed_gate,
      speed_gate_enable => speed_gate_enable,
      ethernet_cpu_arrest => ethernet_cpu_arrest,

      joy3 => joy3,
      joy4 => joy4,

      porto_out => porto_out,
      portp_out => portp_out,
      
      buffereduart_rx => buffereduart_rx,
      buffereduart_tx => buffereduart_tx,
      buffereduart_ringindicate => buffereduart_ringindicate,
      buffereduart2_rx => buffereduart2_rx,
      buffereduart2_tx => buffereduart2_tx,
      
      visual_keyboard_enable => visual_keyboard_enable,
      osk_debug_display => osk_debug_display,
      zoom_en_osk => zoom_en_osk,
      zoom_en_always => zoom_en_always,
      keyboard_at_top => keyboard_at_top,
      alternate_keyboard => alternate_keyboard,
      osk_key1 => osk_key1,
      osk_key2 => osk_key2,
      osk_key3 => osk_key3,
      osk_key4 => osk_key4,
      touch_key1 => osk_touch1_key,
      touch_key2 => osk_touch2_key,
            
      uart_char => uart_char,
      uart_char_valid => uart_char_valid,
      
      -- ASCII key from keyboard_complex for feeding UART monitor interface
      -- when using local keyboard
      uart_monitor_char => uart_monitor_char,
      uart_monitor_char_valid => uart_monitor_char_valid,
      
      fpga_temperature => fpga_temperature,

      restore_key => restore_key,
      osk_toggle_key => osk_toggle_key,
      joyswap_key => joyswap_key,
      
      reg_isr_out => reg_isr_out,
      imask_ta_out => imask_ta_out,    

      key_scancode => key_scancode,
      key_scancode_toggle => key_scancode_toggle,

      cart_access_count => cart_access_count,
      
      uartclock => uartclock,
      phi0 => phi,
      reset => reset_combined,
      reset_out => reset_io,
      irq => io_irq, -- (but we might like to AND this with the hardware IRQ button)
      nmi => io_nmi, -- (but we might like to AND this with the hardware IRQ button)
      restore_nmi => restore_nmi,
      address => fastio_addr,
      addr_fast => fastio_addr_fast,
      r => fastio_read, w => fastio_write,
      data_i => fastio_wdata, data_o => fastio_rdata,
      hyppo_rdata => hyppo_rdata,
      hyppo_address => hyppo_address,
      colourram_at_dc00 => colourram_at_dc00,
      drive_led => drive_led,
      motor => motor,
      sw => sw,
      btn => btn,
--    seg_led => seg_led_data,
      viciii_iomode => viciii_iomode,
      sector_buffer_mapped => sector_buffer_mapped,

      -- CPU status for sending to ethernet frame packer

      d031_write_toggle => d031_write_toggle,
    monitor_instruction_strobe => monitor_instruction_strobe,
    monitor_pc => monitor_pc,
    monitor_opcode => monitor_opcode,
    monitor_arg1 => monitor_arg1,
    monitor_arg2 => monitor_arg2,
    monitor_a => monitor_a,
    monitor_b => monitor_b,
    monitor_x => monitor_x,
    monitor_y => monitor_y,
    monitor_z => monitor_z,
    monitor_sp => monitor_sp,
    monitor_p => monitor_p,
      
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
      
      ----------------------------------------------------------------------
      -- CBM floppy  std_logic_vectorerial port
      ----------------------------------------------------------------------
      iec_clk_en => iec_clk_en,
      iec_data_en => iec_data_en,
      iec_data_o => iec_data_o,
      iec_reset => iec_reset,
      iec_clk_o => iec_clk_o,
      iec_atn_o => iec_atn_o,
      iec_data_external => iec_data_external,
      iec_clk_external => iec_clk_external,
      
      porta_pins => porta_pins,
      portb_pins => portb_pins,
      capslock_key => caps_lock_key,
      keyboard_column8_out => keyboard_column8,
      key_left => keyleft,
      key_up => keyup,

      fa_fire => fa_fire,
      fa_up => fa_up_out,
      fa_left => fa_left_out,
      fa_down => fa_down_out,
      fa_right => fa_right_out,
      fa_potx => fa_potx,
      fa_poty => fa_poty,
      
      fb_fire => fb_fire,
      fb_up => fb_up_out,
      fb_left => fb_left_out,
      fb_down => fb_down_out,
      fb_right => fb_right_out,
      fb_potx => fb_potx,
      fb_poty => fb_poty,

      pota_x => pota_x,
      pota_y => pota_y,
      potb_x => potb_x,
      potb_y => potb_y,      
      
      pot_drain => pot_drain,
      pot_via_iec => pot_via_iec,

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
      i2c_button2 => i2c_button2,
      i2c_button3 => i2c_button3,
      i2c_button4 => i2c_button4,
      i2c_black2 => i2c_black2,
      i2c_black3 => i2c_black3,
      i2c_black4 => i2c_black4,
      
      mouse_debug => mouse_debug,
      amiga_mouse_enable_a => amiga_mouse_enable_a,
      amiga_mouse_enable_b => amiga_mouse_enable_b,
      amiga_mouse_assume_a => amiga_mouse_assume_a,
      amiga_mouse_assume_b => amiga_mouse_assume_b,

      badline_toggle => badline_toggle,
      raster_number => pixel_y,
      vicii_raster => vicii_raster,
      pixel_stream_in => pixel_stream,
      pixel_red_in => pixel_red,
      pixel_green_in => pixel_green,
      pixel_blue_in => pixel_blue,
      pixel_y => pixel_y,
      pixel_valid => pixel_strobe_viciv,
      pixel_newframe => pixel_newframe,
      pixel_newraster => pixel_newraster,

      widget_matrix_col_idx => widget_matrix_col_idx,
      widget_matrix_col => widget_matrix_col,
      widget_restore => widget_restore,
      widget_capslock => widget_capslock,
      widget_joya => widget_joya,
      widget_joyb => widget_joyb,     
      
      hdmi_sda => hdmi_sda,
      hdmi_scl => hdmi_scl,
      hpd_a => hpd_a,

      uart_rx => uart_rx,
      uart_tx => uart_tx,
      
      cs_bo => cs_bo,
      sclk_o => sclk_o,
      mosi_o => mosi_o,
      miso_i => miso_i,
      mosi2_o => mosi2_o,
      miso2_i => miso2_i,
      
      aclMISO => aclMISO,
      aclMOSI => aclMOSI,
      aclSS => aclSS,
      aclSCK => aclSCK,
      aclInt1 => aclInt1,
      aclInt2 => aclInt2,

      -- PDM digital audio output
      ampPWM_l => ampPWM_l,
      ampPWM_r => ampPWM_r,
      audio_left => audio_left,
      audio_right => audio_right,
      ampSD => ampSD,

      -- MEMS microphones
      micData0 => micData0,
      micData1 => micData1,
      micClk => micClk,
      micLRSel => micLRSel,

      -- I2S interfaces for various boards
      i2s_master_clk => i2s_master_clk,
      i2s_master_sync => i2s_master_sync,
      i2s_slave_clk => i2s_slave_clk,
      i2s_slave_sync => i2s_slave_sync,
      pcm_modem_clk => pcm_modem_clk,
      pcm_modem_sync => pcm_modem_sync,
      pcm_modem_clk_in => pcm_modem_clk_in,
      pcm_modem_sync_in => pcm_modem_sync_in,      
      i2s_speaker_data_out => i2s_speaker_data_out,
      pcm_modem1_data_in => pcm_modem1_data_in,
      pcm_modem2_data_in => pcm_modem2_data_in,
      pcm_modem1_data_out => pcm_modem1_data_out,
      pcm_modem2_data_out => pcm_modem2_data_out,
      i2s_bt_data_in => i2s_bt_data_in,
      i2s_bt_data_out => i2s_bt_data_out,
      
      tmpSDA => tmpSDA,
      tmpSCL => tmpSCL,
      tmpInt => tmpInt,
      tmpCT => tmpCT,

      i2c1SDA => i2c1SDA,
      i2c1SCL => i2c1SCL,

      lcdpwm => lcdpwm,
      touchSDA => touchSDA,
      touchSCL => touchSCL,
      touch1_valid => osk_touch1_valid,
      touch1_x => osk_touch1_x,
      touch1_y => osk_touch1_y,
      touch2_valid => osk_touch2_valid,
      touch2_x => osk_touch2_x,
      touch2_y => osk_touch2_y,
      
      ---------------------------------------------------------------------------
      -- IO lines to the ethernet controller
      ---------------------------------------------------------------------------
      eth_mdio => eth_mdio,
      eth_mdc => eth_mdc,
      eth_reset => eth_reset,
      eth_rxd => eth_rxd,
      eth_txd => eth_txd,
      eth_txen => eth_txen,
      eth_rxdv => eth_rxdv,
      eth_rxer => eth_rxer,
      eth_interrupt => eth_interrupt,
      
      ps2data => ps2data,
      ps2clock => ps2clock,
      
      scancode_out => scancode_out
      );

  -----------------------------------------------------------------------------
  -- UART interface for monitor debugging and loading data
  -----------------------------------------------------------------------------
  monitor0 : uart_monitor port map (
    reset => reset_combined,
    reset_out => reset_monitor,

    request_monitor_halt => request_monitor_halt,
    
    monitor_hyper_trap => monitor_hyper_trap,
    clock => uartclock,
    tx       => uart_txd_sig,--uart_txd_sig,
    rx       => RsRx,
    bit_rate_divisor => bit_rate_divisor,

    protected_hardware_in => protected_hardware_sig,
    -- ASCII key from keyboard_complex for feeding UART monitor interface
    -- when using local keyboard
    uart_char => uart_monitor_char,
    uart_char_valid => uart_monitor_char_valid,

    -- output for matrix mode
    monitor_char_out => monitor_char_out,
    monitor_char_valid => monitor_char_out_valid,
    terminal_emulator_ready => terminal_emulator_ready,
    terminal_emulator_ack => terminal_emulator_ack,

    force_single_step => sw(11),

    secure_mode_from_cpu => secure_mode_flag,
    secure_mode_from_monitor => secure_mode_from_monitor,
    clear_matrix_mode_toggle => clear_matrix_mode_toggle,
    
    fastio_read => fastio_read,
    fastio_write => fastio_write,

    key_scancode => key_scancode,
    key_scancode_toggle => key_scancode_toggle,

    monitor_char => monitor_char,
    monitor_char_toggle => monitor_char_toggle,
    monitor_char_busy => monitor_char_busy,
--    monitor_debug_memory_access => monitor_debug_memory_access,
--    monitor_debug_memory_access => (others => '1'),
    monitor_proceed => monitor_proceed,
    monitor_waitstates => monitor_waitstates,
    monitor_request_reflected => monitor_request_reflected,
    monitor_hypervisor_mode => monitor_hypervisor_mode,
    monitor_pc => monitor_pc,
    monitor_cpu_state => monitor_state,
    monitor_instruction => monitor_instruction,
    monitor_watch => monitor_watch,
    monitor_watch_match => monitor_watch_match,
    monitor_opcode => monitor_opcode,
    monitor_ibytes => monitor_ibytes,
    monitor_arg1 => monitor_arg1,
    monitor_arg2 => monitor_arg2,
    monitor_a => monitor_a,
    monitor_b => monitor_b,
    monitor_x => monitor_x,
    monitor_y => monitor_y,
    monitor_z => monitor_z,
    monitor_sp => monitor_sp,
    monitor_p => monitor_p,
    monitor_roms => monitor_roms,
    monitor_interrupt_inhibit => monitor_interrupt_inhibit,
    monitor_map_offset_low => monitor_map_offset_low,
    monitor_map_offset_high => monitor_map_offset_high,
    monitor_map_enables_low => monitor_map_enables_low,
    monitor_map_enables_high => monitor_map_enables_high,
    monitor_memory_access_address => monitor_memory_access_address,
    monitor_mem_address => monitor_mem_address,
    monitor_mem_rdata => monitor_mem_rdata,
    monitor_mem_wdata => monitor_mem_wdata,
    monitor_mem_read => monitor_mem_read,
    monitor_mem_write => monitor_mem_write,
    monitor_mem_setpc => monitor_mem_setpc,
    monitor_mem_attention_request => monitor_mem_attention_request,
    monitor_mem_attention_granted => monitor_mem_attention_granted,
    monitor_irq_inhibit => monitor_irq_inhibit,
    monitor_mem_trace_mode => monitor_mem_trace_mode,
    monitor_mem_stage_trace_mode => monitor_mem_stage_trace_mode,
    monitor_mem_trace_toggle => monitor_mem_trace_toggle
    );

  process (cpuclock) is
  begin
    if rising_edge(cpuclock) then

      secure_mode_triage_required <= protected_hardware_sig(7) or secure_mode_from_monitor;
      
      osk_touch1_key <= osk_touch1_key_driver;
      osk_touch2_key <= osk_touch2_key_driver;
      
      flopled <= drive_led;
      flopmotor <= motor;

      -- Generate 2MHz for SIDs from CPUCLOCK / 20
      if clock2mhz_counter = 19 then
        clock2mhz_counter <= 0;
        clock2mhz_i <= not clock2mhz_i;
      else
        clock2mhz_counter <= clock2mhz_counter + 1;
      end if;
      clock2mhz <= clock2mhz_i;
      
    end if;
  end process;

  
  debug8_state_out <= std_logic_vector(monitor_state(15 downto 8));
--  debug4_state_out <= (others => '0');

  UART_TXD<=uart_txd_sig; 
  
end Behavioral;

