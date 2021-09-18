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

entity machine_container is
  generic (cpu_frequency : integer;
           hyper_installed : boolean := false;
           target : mega65_target_t );
  Port ( pixelclock : in STD_LOGIC;
         cpuclock : in std_logic;
         clock50mhz : in std_logic;  -- normal ethernet clock
         clock100 : in std_logic;    -- Must be 2x ethernet clock
         clock200 : in std_logic;    -- Must be 4x ethernet clock
         clock27 : in std_logic;
         clock162 : in std_logic;
         uartclock : std_logic;
         btnCpuReset : in  STD_LOGIC;
         reset_out : out std_logic := '1';
         irq : in  STD_LOGIC;
         nmi : in  STD_LOGIC;
         restore_key : in std_logic;
         osk_toggle_key : in std_logic := '1';
         joyswap_key : in std_logic := '1';
         cpu_exrom : in std_logic;
         cpu_game : in std_logic;

         fast_key : in std_logic := '1';
         iec_bus_active : in std_logic;      
         
         power_down : out std_logic := '1';
         
         no_hyppo : in std_logic;

         disco_led_id : out unsigned(7 downto 0) := x"00";
         disco_led_val : out unsigned(7 downto 0) := x"00";
         disco_led_en : out std_logic := '0';

         flopled : out std_logic := '0';
         flopmotor : out std_logic := '0';

         j21in : in std_logic_vector(11 downto 0) := (others => '1');
         j21out : inout std_logic_vector(11 downto 0) := (others => '1');
         j21ddr : inout std_logic_vector(11 downto 0) := (others => '0');
         
         buffereduart_rx : inout std_logic_vector(7 downto 0);
         buffereduart_tx : out std_logic_vector(7 downto 0);
         buffereduart_ringindicate : in std_logic_vector(7 downto 0);
         
         slow_access_request_toggle : out std_logic := '0';
         slow_access_ready_toggle : in std_logic := '0';
         slow_access_write : out std_logic := '0';
         slow_access_address : out unsigned(27 downto 0) := to_unsigned(0,28);
         slow_access_wdata : out unsigned(7 downto 0) := to_unsigned(0,8);
         slow_access_rdata : in unsigned(7 downto 0);
         cart_access_count : in unsigned(7 downto 0) := x"00";

         -- Fast read interface for slow devices linear reading
         -- (only hyperram)
         slow_prefetched_request_toggle : inout std_logic := '0';
         slow_prefetched_data : in unsigned(7 downto 0) := x"00";
         slow_prefetched_address : in unsigned(26 downto 0) := (others => '1');
         
         sector_buffer_mapped : inout std_logic;

         joy3 : in std_logic_vector(4 downto 0) := "11011";
         joy4 : in std_logic_vector(4 downto 0) := "10111";

         fm_left : in signed(15 downto 0) := to_signed(0,16);
         fm_right : in signed(15 downto 0) := to_signed(0,16);
         
         ----------------------------------------------------------------------
         -- Flash RAM for holding FPGA config
         ----------------------------------------------------------------------
         QspiDB : inout unsigned(3 downto 0) := (others => 'Z');
         QspiCSn : out std_logic := '0';
         qspi_clock : out std_logic := '0';
         
         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vsync : out  STD_LOGIC := '0';
         vga_hsync : out STD_LOGIC := '0';
         lcd_hsync : out std_logic := '0';
         lcd_vsync : out std_logic := '0';
         pal50_select_out : out std_logic := '0';
         vga_blank : out std_logic := '0';
         
         vgared : out  UNSIGNED (7 downto 0) := x"00";
         vgagreen : out  UNSIGNED (7 downto 0) := x"00";
         vgablue : out  UNSIGNED (7 downto 0) := x"00";

         panelred : out  UNSIGNED (7 downto 0) := x"00";
         panelgreen : out  UNSIGNED (7 downto 0) := x"00";
         panelblue : out  UNSIGNED (7 downto 0) := x"00";
         lcd_dataenable : out std_logic := '0';
         hdmi_dataenable : out std_logic := '0';

         hdmi_int : in std_logic := '1';
         hdmi_hsync : out  STD_LOGIC := '1';
         hdmi_scl : inout std_logic := '1';
         hdmi_sda : inout std_logic := '1';
         hpd_a : inout std_logic := '1';

         porto_out : out unsigned(7 downto 0) := x"00";
         portp_out : out unsigned(7 downto 0) := x"00";

         kbd_datestamp : in unsigned(13 downto 0);
         kbd_commit : in unsigned(31 downto 0);

         max10_fpga_date : in unsigned(15 downto 0) := to_unsigned(0,16);
         max10_fpga_commit : in unsigned(31 downto 0) := to_unsigned(0,32);
         
         -------------------------------------------------------------------------
         -- CIA1 ports for keyboard and joysticks
         -------------------------------------------------------------------------
         porta_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
         portb_pins : in  std_logic_vector(7 downto 0);
         keyleft : in std_logic;
         keyup : in std_logic;
         keyboard_column8 : out std_logic := '1';
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
         pot_drain : buffer std_logic := '1';
         pot_via_iec : buffer std_logic := '1';

        i2c_joya_fire : out std_logic := '1';
        i2c_joya_up : out std_logic := '1';
        i2c_joya_down : out std_logic := '1';
        i2c_joya_left : out std_logic := '1';
        i2c_joya_right : out std_logic := '1';
        i2c_joyb_fire : out std_logic := '1';
        i2c_joyb_up : out std_logic := '1';
        i2c_joyb_down : out std_logic := '1';
        i2c_joyb_left : out std_logic := '1';
        i2c_joyb_right : out std_logic := '1';
        i2c_button2 : out std_logic := '1';
        i2c_button3 : out std_logic := '1';
        i2c_button4 : out std_logic := '1';
        i2c_black2 : out std_logic := '1';
        i2c_black3 : out std_logic := '1';
        i2c_black4 : out std_logic := '1';
         
         ----------------------------------------------------------------------
         -- CBM floppy serial port
         ----------------------------------------------------------------------
         iec_clk_en : out std_logic := '1';
         iec_data_en : out std_logic := '1';
         iec_srq_en : out std_logic := '1';
         iec_data_o : out std_logic := '1';
         iec_reset : out std_logic := '1';
         iec_clk_o : out std_logic := '1';
         iec_atn_o : out std_logic := '1';
         iec_srq_o : out std_logic := '1';
         iec_srq_external : in std_logic;
         iec_data_external : in std_logic;
         iec_clk_external : in std_logic;
         
         -------------------------------------------------------------------------
         -- Lines for the SDcard interfaces (internal and external (2))
         -------------------------------------------------------------------------
         cs_bo : out std_logic := '1';
         sclk_o : out std_logic := '1';
         mosi_o : out std_logic := '1';
         miso_i : in  std_logic;
         cs2_bo : out std_logic := '1';
         sclk2_o : out std_logic := '1';
         mosi2_o : out std_logic := '1';
         miso2_i : in  std_logic;

         ----------------------------------------------------------------------
         -- Floppy drive interface
         ----------------------------------------------------------------------
         f_density : out std_logic := '1';
         f_motora : out std_logic := '1';
         f_selecta : out std_logic := '1';
         f_motorb : out std_logic := '1';
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

         
         ---------------------------------------------------------------------------
         -- Lines for other devices that we handle here
         ---------------------------------------------------------------------------
         aclMISO : in std_logic;
         aclMOSI : out std_logic := '1';
         aclSS : out std_logic := '1';
         aclSCK : out std_logic := '1';
         aclInt1 : in std_logic;
         aclInt2 : in std_logic;

         ampPWM_l : out std_logic := '1';
         ampPWM_r : out std_logic := '1';
         pcspeaker_left : out std_logic := '1';
         ampSD : out std_logic := '0';
         audio_left : out std_logic_vector(19 downto 0) := (others => '1');
         audio_right : out std_logic_vector(19 downto 0) := (others => '1');

         micData0 : in std_logic;
         micData1 : in std_logic;
         micClk : out std_logic := '1';
         micLRSel : out std_logic := '1';
         headphone_mic : in std_logic := '1';

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
         pcm_bluetooth_data_in : in std_logic := '0';
         pcm_bluetooth_data_out : out std_logic := '0';    
         pcm_bluetooth_clk_in : in std_logic := '0';
         pcm_bluetooth_sync_in : in std_logic := '0';
         
         tmpSDA : inout std_logic := '1';
         tmpSCL : inout std_logic := '1';
         tmpInt : in std_logic;
         tmpCT : in std_logic;

         i2c1SDA : inout std_logic := '1';
         i2c1SCL : inout std_logic := '1';

         lcdpwm : out std_logic := '1';
         touchSDA : inout std_logic := 'H';
         touchSCL : inout std_logic := '1';
         
         ---------------------------------------------------------------------------
         -- IO lines to the ethernet controller
         ---------------------------------------------------------------------------
         eth_mdio : inout std_logic;
         eth_mdc : out std_logic := '1';
         eth_reset : out std_logic := '1';
         eth_rxd : in unsigned(1 downto 0);
         eth_txd : out unsigned(1 downto 0) := "00"; 
         eth_txen : out std_logic := '0';
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
         uart_tx : out std_logic := '1';
         
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

         ---------------------------------------------------------------------------
         -- Direct interface to HyperRAM for fetching 256 colour glyph data etc
         ---------------------------------------------------------------------------
         hyper_addr : out unsigned(18 downto 3) := (others => '0');
         hyper_request_toggle : out std_logic := '0';
         hyper_data : in unsigned(7 downto 0) := x"00";
         hyper_data_strobe : in std_logic := '0';
         
         ----------------------------------------------------------------------
         -- Debug interfaces on Nexys4 board
         ----------------------------------------------------------------------
         led : out std_logic_vector(15 downto 0) := (others => '0');
         dipsw : in std_logic_vector(4 downto 0) := (others => '0');
         sw : in std_logic_vector(15 downto 0);
         btn : in std_logic_vector(4 downto 0);

         UART_TXD : out std_logic := '1';
         RsRx : in std_logic;
         
         sseg_ca : out std_logic_vector(7 downto 0) := (others => '0');
         sseg_an : out std_logic_vector(7 downto 0) := (others => '0')
         );
end machine_container;

architecture Behavioral of machine_container is

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

  signal fastio_addr : std_logic_vector(19 downto 0) := (others => '0');
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

  signal phi_1mhz : std_logic := '0';
  signal phi_2mhz : std_logic := '0';
  signal phi_3mhz : std_logic := '0';

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
  signal pixel_frame_toggle : std_logic;
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
  signal hdmi_dataenable_internal : std_logic := '0';

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

  signal viciv_frame_indicate : std_logic;

  signal cpu_pcm_left : signed(15 downto 0) := x"FFFF";
  signal cpu_pcm_right : signed(15 downto 0) := x"FFFF";
  signal cpu_pcm_enable : std_logic := '0';
  signal cpu_pcm_bypass : std_logic := '0';
  signal pwm_mode_select : std_logic := '0';

  signal accessible_row : integer range 0 to 255;
  signal accessible_key : unsigned(6 downto 0);
  signal dim_shift : std_logic;

  signal dd00_bits : unsigned(1 downto 0);
  
begin

  lcd_dataenable <= lcd_dataenable_internal;
  hdmi_dataenable <= hdmi_dataenable_internal;
  
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
    -- Dip switches on the MEGA65R2/R3 or Nexys4 boards can be used to inhibit
    -- IRQs and NMIs
    combinedirq <= (irq and io_irq and vic_irq) or sw(15);
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
    
    report "reset_combined = " & std_logic'image(reset_combined) severity note;
  end process;
  
  process(pixelclock,cpuclock)
    variable digit : std_logic_vector(3 downto 0);
  begin
    if rising_edge(pixelclock) then
      report "external_pixel_strobe = " & std_logic'image(external_pixel_strobe);
    end if;
    if rising_edge(cpuclock) then
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

      -- Xray mode allows debugging raster time on VIC-IV
      xray_mode <= sw(12);
      
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


  pixel0: entity work.pixel_driver
    port map (
               clock81 => pixelclock, -- 80MHz
               clock27 => clock27,

               cpuclock => cpuclock,

               phi_1mhz_out => phi_1mhz,
               phi_2mhz_out => phi_2mhz,
               phi_3mhz_out => phi_3mhz,

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
      vga_blank => vga_blank,

      -- And the variations on those signals for the LCD display
      lcd_hsync => lcd_hsync,               
      lcd_vsync => lcd_vsync,
      fullwidth_dataenable => lcd_dataenable_internal,
      narrow_dataenable => hdmi_dataenable_internal,
      lcd_inletterbox => lcd_inletterbox,
      vga_inletterbox => vga_inletterbox

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

    matrix_mode_enable => protected_hardware_sig(6),
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

      -- Accessibility inputs for showing on visual keyboard
      selected_row => accessible_row,
      accessible_key => accessible_key,
      dim_shift => dim_shift,
      
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
      clk => cpuclock,

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
  

  process (cpuclock) is
  begin
    if rising_edge(cpuclock) then

      report "tick";
      
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

