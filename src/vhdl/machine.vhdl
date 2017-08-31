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


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity machine is
  generic (cpufrequency : integer := 50);
  Port ( pixelclock : STD_LOGIC;
         pixelclock2x : STD_LOGIC;
         cpuclock : std_logic;
         clock50mhz : in std_logic;
         ioclock : std_logic;
         uartclock : std_logic;
         btnCpuReset : in  STD_LOGIC;
         reset_out : out std_logic;
         irq : in  STD_LOGIC;
         nmi : in  STD_LOGIC;
         restore_key : in std_logic;
         cpu_exrom : in std_logic;
         cpu_game : in std_logic;

         no_kickstart : in std_logic;

         flopled : out std_logic;
         flopmotor : out std_logic;

         slow_access_request_toggle : out std_logic;
         slow_access_ready_toggle : in std_logic := '0';
         slow_access_write : out std_logic := '0';
         slow_access_address : out unsigned(27 downto 0);
         slow_access_wdata : out unsigned(7 downto 0);
         slow_access_rdata : in unsigned(7 downto 0);

         sector_buffer_mapped : inout std_logic;
         
         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vsync : out  STD_LOGIC;
         hsync : out  STD_LOGIC;
         vgared : out  UNSIGNED (7 downto 0);
         vgagreen : out  UNSIGNED (7 downto 0);
         vgablue : out  UNSIGNED (7 downto 0);
         hdmi_scl : inout std_logic := '1';
         hdmi_sda : inout std_logic := 'Z';

         -------------------------------------------------------------------------
         -- CIA1 ports for keyboard and joysticks
         -------------------------------------------------------------------------
         porta_pins : inout  std_logic_vector(7 downto 0);
         portb_pins : inout  std_logic_vector(7 downto 0);
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
         
         -------------------------------------------------------------------------
         -- Lines for the SDcard interface itself
         -------------------------------------------------------------------------
         cs_bo : out std_logic;
         sclk_o : out std_logic;
         mosi_o : out std_logic;
         miso_i : in  std_logic;

         ---------------------------------------------------------------------------
         -- Lines for other devices that we handle here
         ---------------------------------------------------------------------------
         aclMISO : in std_logic;
         aclMOSI : out std_logic;
         aclSS : out std_logic;
         aclSCK : out std_logic;
         aclInt1 : in std_logic;
         aclInt2 : in std_logic;
         
         ampPWM : out std_logic;
         ampPWM_l : out std_logic;
         ampPWM_r : out std_logic;
         ampSD : out std_logic;

         micData : in std_logic;
         micClk : out std_logic;
         micLRSel : out std_logic;

         tmpSDA : out std_logic;
         tmpSCL : out std_logic;
         tmpInt : in std_logic;
         tmpCT : in std_logic;
         
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
         -- PMOD interface for keyboard, joystick, expansion port etc board.
         ----------------------------------------------------------------------
         pmod_clock : in std_logic;
         pmod_start_of_sequence : in std_logic;
         pmod_data_in : in std_logic_vector(3 downto 0);
         pmod_data_out : out std_logic_vector(1 downto 0);
         pmoda : inout std_logic_vector(7 downto 0);

         uart_rx : in std_logic;
         uart_tx : out std_logic;
         
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

  signal pmodb_in_buffer : std_logic_vector(5 downto 0);
  signal pmodb_out_buffer : std_logic_vector(1 downto 0);
  
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
  
  signal drive_led : std_logic;
  signal motor : std_logic;
  signal drive_led_out : std_logic;
  
  signal seg_led_data : unsigned(31 downto 0);

  signal reset_io : std_logic;
  signal reset_monitor : std_logic;
  -- Holds reset on for 8 cycles so that reset line entry is used on start up,
  -- instead of implicit startup state.
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

  signal fastio_addr : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);
  signal fastio_vic_rdata : std_logic_vector(7 downto 0);
  signal colour_ram_fastio_rdata : std_logic_vector(7 downto 0);

  signal chipram_we : STD_LOGIC;
  signal chipram_address : unsigned(16 DOWNTO 0);
  signal chipram_datain : unsigned(7 DOWNTO 0);
  
  signal rom_at_e000 : std_logic := '0';
  signal rom_at_c000 : std_logic := '0';
  signal rom_at_a000 : std_logic := '0';
  signal rom_at_8000 : std_logic := '0';

  signal colourram_at_dc00 : std_logic := '0';
  signal colour_ram_cs : std_logic := '0';
  signal charrom_write_cs : std_logic := '0';

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
  signal monitor_map_enables_low : std_logic_vector(3 downto 0);
  signal monitor_map_enables_high : std_logic_vector(3 downto 0);   
  signal monitor_mem_read : std_logic;
  signal monitor_mem_write : std_logic;
  signal monitor_mem_setpc : std_logic;
  signal monitor_mem_attention_request : std_logic;
  signal monitor_mem_attention_granted : std_logic;
  signal monitor_mem_stage_trace_mode : std_logic;
  signal monitor_mem_trace_mode : std_logic;
  signal monitor_mem_trace_toggle : std_logic;
  signal monitor_char : unsigned(7 downto 0);
  signal monitor_char_toggle : std_logic;
  signal monitor_char_busy : std_logic;
  
  signal monitor_a : unsigned(7 downto 0);
  signal monitor_b : unsigned(7 downto 0);
  signal monitor_interrupt_inhibit : std_logic;
  signal monitor_x : unsigned(7 downto 0);
  signal monitor_y : unsigned(7 downto 0);
  signal monitor_z : unsigned(7 downto 0);
  signal monitor_sp : unsigned(15 downto 0);
  signal monitor_p : unsigned(7 downto 0);
  signal monitor_opcode : unsigned(7 downto 0);
  signal monitor_ibytes : std_logic_vector(3 downto 0);
  signal monitor_arg1 : unsigned(7 downto 0);
  signal monitor_arg2 : unsigned(7 downto 0);

  signal cpuis6502 : std_logic;
  signal cpuspeed : unsigned(7 downto 0);

  signal segled_counter : unsigned(19 downto 0) := (others => '0');

  -- Clock running as close as possible to 17.734475 MHz / 18 = 985248Hz
  -- Our pixel clock is 192MHz.  195 ticks gives 984615Hz for NTSC.
  -- 188 ticks at 192MHz gives 1021276Hz, which is pretty close for PAL.
  -- But dotclock is really 193.75MHz, so adjust accordingly.
  -- Then divide by 2 again, since the loop toggles phi0.
  signal phi0 : std_logic := '0';
  constant phi0_divisor : integer := 76; -- For 150MHz dotclock, 50MHz CPU
  signal phi0_counter : integer range 0 to phi0_divisor;

  signal pixel_stream : unsigned (7 downto 0);
  signal pixel_y : unsigned (11 downto 0);
  signal pixel_valid : std_logic;
  signal pixel_newframe : std_logic;
  signal pixel_newraster : std_logic;
  signal pixel_x_640 : integer;
  signal pixel_y_scale_200 : unsigned(3 downto 0);
  signal pixel_y_scale_400 : unsigned(3 downto 0);

  signal farcallstack_we : std_logic;
  signal farcallstack_addr : std_logic_vector(8 downto 0);
  signal farcallstack_din : std_logic_vector(63 downto 0);
  signal farcallstack_dout : std_logic_vector(63 downto 0);
  signal uart_tx_buffer : std_logic; 
  signal uart_rx_buffer : std_logic;
  signal protected_hardware_sig : unsigned(7 downto 0);

  -- Matrix Mode signals
  signal scancode_out : std_logic_vector(12 downto 0); 
  signal mm_displayMode : unsigned(1 downto 0):=b"10"; 
  signal bit_rate_divisor : unsigned(13 downto 0);
  signal vgablue_sig : unsigned(7 downto 0);
  signal vgared_sig : unsigned(7 downto 0);
  signal vgagreen_sig : unsigned(7 downto 0);
  signal vgablue_kbd : unsigned(7 downto 0);
  signal vgared_kbd : unsigned(7 downto 0);
  signal vgagreen_kbd : unsigned(7 downto 0);
  signal vgablue_out : unsigned(7 downto 0);
  signal vgared_out : unsigned(7 downto 0);
  signal vgagreen_out : unsigned(7 downto 0);
  signal viciv_outofframe : std_logic := '0';
  signal viciv_outofframe_1 : std_logic := '0';
  signal viciv_outofframe_2 : std_logic := '0';
  signal viciv_outofframe_3 : std_logic := '0';
  
  signal xcounter : unsigned(13 downto 0);
  signal ycounter : unsigned(11 downto 0); 
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

  signal visual_keyboard_enable : std_logic;
  signal keyboard_at_top : std_logic;
  signal osk_x : unsigned(11 downto 0);
  signal osk_y : unsigned(11 downto 0);
  signal osk_key1 : unsigned(7 downto 0);
  signal osk_key2 : unsigned(7 downto 0);
  signal osk_key3 : unsigned(7 downto 0);
  signal osk_key4 : unsigned(7 downto 0);

  signal all_pause : std_logic := '0';
  
begin

  ----------------------------------------------------------------------------
  -- IRQ & NMI: If either the hardware buttons on the FPGA board or an IO
  -- device via the IOmapper pull an interrupt line down, then trigger an
  -- interrupt.
  -----------------------------------------------------------------------------
  process(irq,nmi,restore_nmi,io_irq,vic_irq,io_nmi,sw,reset_io,btnCpuReset,
          power_on_reset,reset_monitor)
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
      report "reset asserted via reset_monitor";
      reset_combined <= '0';
    else
      reset_combined <= '1';
    end if;

    hyper_trap_combined <= hyper_trap and monitor_hyper_trap;
    
  -- report "btnCpuReset = " & std_logic'image(btnCpuReset) & ", reset_io = " & std_logic'image(reset_io) & ", sw(15) = " & std_logic'image(sw(15)) severity note;
  -- report "reset_combined = " & std_logic'image(reset_combined) severity note;
  end process;
  
  process(pixelclock,ioclock)
    variable digit : std_logic_vector(3 downto 0);
  begin
    if rising_edge(ioclock) then
      -- Hold reset low for a while when we first turn on
--      report "power_on_reset(0) = " & std_logic'image(power_on_reset(0)) severity note;
      power_on_reset(7) <= '1';
      power_on_reset(6 downto 0) <= power_on_reset(7 downto 1);

      led(0) <= irq;
      led(1) <= nmi;
      led(2) <= combinedirq;
      led(3) <= combinednmi;
      led(4) <= io_irq;
      led(5) <= io_nmi;
      led(7 downto 6) <= (others => '0');
      led(8) <= motor;
      led(9) <= drive_led_out;
      led(10) <= cpu_hypervisor_mode;
      led(11) <= hyper_trap;
      led(12) <= hyper_trap_combined;
      led(13) <= monitor_hyper_trap;
      led(14) <= speed_gate;
      led(15) <= speed_gate_enable;

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
      
      -- Work out phi0 frequency for CIA timers
      if phi0_counter=phi0_divisor then
        phi0 <= not phi0;
        phi0_counter <= 0;
      else
        phi0_counter <= phi0_counter + 1;
      end if;
      
    end if;
  end process;
  
  cpu0: entity work.gs4510
    generic map(
      cpufrequency => cpufrequency)
    port map(
      all_pause => all_pause,
      matrix_trap_in=>matrix_trap,
      protected_hardware => protected_hardware_sig,
      clock => cpuclock,
      ioclock => ioclock,
      reset =>reset_combined,
      reset_out => reset_out,
      irq => combinedirq,
      nmi => combinednmi,
      exrom => cpu_exrom,
      game => cpu_game,
      hyper_trap => hyper_trap_combined,
      hyper_trap_f011_read => hyper_trap_f011_read,
      hyper_trap_f011_write => hyper_trap_f011_write,    
      speed_gate => speed_gate,
      speed_gate_enable => speed_gate_enable,
      cpuis6502 => cpuis6502,
      cpuspeed => cpuspeed,

      irq_hypervisor => sw(4 downto 2),    -- JBM
      
      -- Hypervisor signals: we need to tell kickstart memory whether
      -- to map or not, and we also need to be able to set the VIC-III
      -- IO mode.
      cpu_hypervisor_mode => cpu_hypervisor_mode,
      iomode_set => iomode_set,
      iomode_set_toggle => iomode_set_toggle,
      
      no_kickstart => no_kickstart,
      
      reg_isr_out => reg_isr_out,
      imask_ta_out => imask_ta_out,
      
      vicii_2mhz => vicii_2mhz,
      viciii_fast => viciii_fast,
      viciv_fast => viciv_fast,

      monitor_char => monitor_char,
      monitor_char_toggle => monitor_char_toggle,
      monitor_char_busy => monitor_char_busy,

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

      monitor_mem_address => monitor_mem_address,
      monitor_mem_rdata => monitor_mem_rdata,
      monitor_mem_wdata => monitor_mem_wdata,
      monitor_mem_read => monitor_mem_read,
      monitor_mem_write => monitor_mem_write,
      monitor_mem_setpc => monitor_mem_setpc,
      monitor_mem_attention_request => monitor_mem_attention_request,
      monitor_mem_attention_granted => monitor_mem_attention_granted,
      monitor_mem_trace_mode => monitor_mem_trace_mode,
      monitor_mem_stage_trace_mode => monitor_mem_stage_trace_mode,
      monitor_mem_trace_toggle => monitor_mem_trace_toggle,

      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,    
      slow_access_address => slow_access_address,
      slow_access_write => slow_access_write,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,
      
      chipram_we => chipram_we,
      chipram_address => chipram_address,
      chipram_datain => chipram_datain,

      cpu_leds => cpu_leds,
      
      fastio_addr => fastio_addr,
      fastio_read => fastio_read,
      fastio_write => fastio_write,
      fastio_wdata => fastio_wdata,
      fastio_rdata => fastio_rdata,
      sector_buffer_mapped => sector_buffer_mapped,
      fastio_vic_rdata => fastio_vic_rdata,
      fastio_colour_ram_rdata => colour_ram_fastio_rdata,
      colour_ram_cs => colour_ram_cs,
      charrom_write_cs => charrom_write_cs,

      viciii_iomode => viciii_iomode,
      
      colourram_at_dc00 => colourram_at_dc00,
      rom_at_e000 => rom_at_e000,
      rom_at_c000 => rom_at_c000,
      rom_at_a000 => rom_at_a000,
      rom_at_8000 => rom_at_8000,

      ---------------------------------------------------------------------------
      -- IO port to far call stack
      ---------------------------------------------------------------------------
      farcallstack_we => farcallstack_we,
      farcallstack_addr => farcallstack_addr,
      farcallstack_din => farcallstack_din,
      farcallstack_dout => farcallstack_dout

      );

  viciv0: entity work.viciv
    port map (

      all_pause => all_pause,
      
      xcounter_out => xcounter,
      ycounter_out => ycounter,
      pixelclock      => pixelclock,
      pixelclock2x      => pixelclock2x,
      cpuclock        => cpuclock,
      ioclock        => ioclock,

      irq             => vic_irq,
      reset           => reset_combined,

      led => drive_led,
      motor => motor,
      drive_led_out => drive_led_out,

      xray_mode => xray_mode,
      
      vsync           => vsync,
      hsync           => hsync,
      vgared          => vgared_sig,
      vgagreen        => vgagreen_sig,
      vgablue         => vgablue_sig,
      viciv_outofframe => viciv_outofframe,

      pixel_stream_out => pixel_stream,
      pixel_y => pixel_y,
      pixel_valid => pixel_valid,
      pixel_newframe => pixel_newframe,
      pixel_newraster => pixel_newraster,
      pixel_x_640 => pixel_x_640,
      pixel_y_scale_200 => pixel_y_scale_200,
      pixel_y_scale_400 => pixel_y_scale_400,
      
      chipram_we => chipram_we,
      chipram_address => chipram_address,
      chipram_datain => chipram_datain,
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
      
      colourram_at_dc00 => colourram_at_dc00,
      rom_at_e000 => rom_at_e000,
      rom_at_c000 => rom_at_c000,
      rom_at_a000 => rom_at_a000,
      rom_at_8000 => rom_at_8000      
      );
  
  iomapper0: entity work.iomapper
    port map (
      clk => ioclock,
      protected_hardware_in => protected_hardware_sig,
      matrix_mode_trap => matrix_trap,
      hyper_trap => hyper_trap,
      hyper_trap_f011_read => hyper_trap_f011_read,
      hyper_trap_f011_write => hyper_trap_f011_write,
      cpuclock => cpuclock,
      pixelclk => pixelclock,
      clock50mhz => clock50mhz,
      cpu_hypervisor_mode => cpu_hypervisor_mode,
      speed_gate => speed_gate,
      speed_gate_enable => speed_gate_enable,

      visual_keyboard_enable => visual_keyboard_enable,
      keyboard_at_top => keyboard_at_top,
      osk_x => osk_x,
      osk_y => osk_y,
      osk_key1 => osk_key1,
      osk_key2 => osk_key2,
      osk_key3 => osk_key3,
            
      uart_char => uart_char,
      uart_char_valid => uart_char_valid,
      
      -- ASCII key from keyboard_complex for feeding UART monitor interface
      -- when using local keyboard
      uart_monitor_char => uart_monitor_char,
      uart_monitor_char_valid => uart_monitor_char_valid,
      mm_displayMode_out => mm_displayMode,
      display_shift_out => display_shift,
      shift_ready_out => shift_ready,
      shift_ack_in => shift_ack,     
      
      fpga_temperature => fpga_temperature,

      restore_key => restore_key,
      
      reg_isr_out => reg_isr_out,
      imask_ta_out => imask_ta_out,    

      key_scancode => key_scancode,
      key_scancode_toggle => key_scancode_toggle,
      
      uartclock => uartclock,
      phi0 => phi0,
      reset => reset_combined,
      reset_out => reset_io,
      irq => io_irq, -- (but we might like to AND this with the hardware IRQ button)
      nmi => io_nmi, -- (but we might like to AND this with the hardware IRQ button)
      restore_nmi => restore_nmi,
      address => fastio_addr,
      r => fastio_read, w => fastio_write,
      data_i => fastio_wdata, data_o => fastio_rdata,
      colourram_at_dc00 => colourram_at_dc00,
      drive_led => drive_led,
      motor => motor,
      drive_led_out => drive_led_out,
      sw => sw,
      btn => btn,
--    seg_led => seg_led_data,
      viciii_iomode => viciii_iomode,
      sector_buffer_mapped => sector_buffer_mapped,

      ----------------------------------------------------------------------
      -- CBM floppy  std_logic_vectorerial port
      ----------------------------------------------------------------------
      iec_clk_en => iec_clk_en,
      iec_data_en => iec_data_en,
      iec_data_o => iec_data_o,
      iec_reset => iec_reset,
      iec_clk_o => iec_clk_o,
      iec_data_i => iec_data_i,
      iec_clk_i => iec_clk_i,
      iec_atn => iec_atn,
      
      porta_pins => porta_pins,
      portb_pins => portb_pins,
      capslock_key => caps_lock_key,
      keyboard_column8_out => keyboard_column8,
      key_left => keyleft,
      key_up => keyup,

      fa_fire => fa_fire,
      fa_up => fa_up,
      fa_left => fa_left,
      fa_down => fa_down,
      fa_right => fa_right,
      
      fb_fire => fb_fire,
      fb_up => fb_up,
      fb_left => fb_left,
      fb_down => fb_down,
      fb_right => fb_right,
      
      pixel_stream_in => pixel_stream,
      pixel_y => pixel_y,
      pixel_valid => pixel_valid,
      pixel_newframe => pixel_newframe,
      pixel_newraster => pixel_newraster,
      pixel_x_640 => pixel_x_640,

      pmod_clock => pmodb_in_buffer(0),
      pmod_start_of_sequence => pmodb_in_buffer(1),
      pmod_data_in => pmodb_in_buffer(5 downto 2),
      pmod_data_out => pmodb_out_buffer(1 downto 0),
      
      pmoda => pmoda,

      hdmi_sda => hdmi_sda,
      hdmi_scl => hdmi_scl,    

      uart_rx => uart_rx,
      uart_tx => uart_tx,
      
      farcallstack_we => farcallstack_we,
      farcallstack_addr => farcallstack_addr,
      farcallstack_din => farcallstack_din,
      farcallstack_dout => farcallstack_dout,
      
      cs_bo => cs_bo,
      sclk_o => sclk_o,
      mosi_o => mosi_o,
      miso_i => miso_i,
      
      aclMISO => aclMISO,
      aclMOSI => aclMOSI,
      aclSS => aclSS,
      aclSCK => aclSCK,
      aclInt1 => aclInt1,
      aclInt2 => aclInt2,
      
      ampPWM => ampPWM,
      ampPWM_l => ampPWM_l,
      ampPWM_r => ampPWM_r,
      ampSD => ampSD,
      
      micData => micData,
      micClk => micClk,
      micLRSel => micLRSel,
      
      tmpSDA => tmpSDA,
      tmpSCL => tmpSCL,
      tmpInt => tmpInt,
      tmpCT => tmpCT,

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

  matrix_compositor0 : entity work.matrix_compositor port map(
    display_shift_in=>display_shift,
    shift_ready_in => shift_ready,
    shift_ack_out => shift_ack,
    mm_displayMode_in => mm_displayMode,
    monitor_char_in => monitor_char_out,
    monitor_char_valid => monitor_char_out_valid,
    terminal_emulator_ready => terminal_emulator_ready,
    pixel_x_640 => pixel_x_640,
    pixel_y_scale_200 => pixel_y_scale_200,
    pixel_y_scale_400 => pixel_y_scale_400,
    ycounter_in => ycounter,	
    clk => uartclock,
    pixelclock => pixelclock,
    matrix_mode_enable => protected_hardware_sig(6),--sw(5), 					
    vgared_in => vgared_sig,
    vgagreen_in => vgagreen_sig,
    vgablue_in => vgablue_sig,
    vgared_out => vgared_kbd,
    vgagreen_out => vgagreen_kbd,
    vgablue_out => vgablue_kbd
    );

    visual_keyboard0 : entity work.visual_keyboard port map(
    pixel_x_640_in => pixel_x_640,
    pixel_y_scale_200 => pixel_y_scale_200,
    pixel_y_scale_400 => pixel_y_scale_400,
    ycounter_in => ycounter,
    y_start => osk_y,
    x_start => osk_x,
    pixelclock => pixelclock,
    vgared_in => vgared_kbd,
    vgagreen_in => vgagreen_kbd,
    visual_keyboard_enable => visual_keyboard_enable,
    keyboard_at_top => keyboard_at_top,
    key1 => osk_key1,
    key2 => osk_key2,
    key3 => osk_key3,
    key4 => osk_key4,
    vgablue_in => vgablue_kbd,
    vgared_out => vgared_out,
    vgagreen_out => vgagreen_out,
    vgablue_out => vgablue_out
    );
  
  -----------------------------------------------------------------------------
  -- UART interface for monitor debugging and loading data
  -----------------------------------------------------------------------------
  monitor0 : entity work.uart_monitor port map (
    reset => reset_combined,
    reset_out => reset_monitor,

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
    
    force_single_step => sw(11),
    
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
    monitor_interrupt_inhibit => monitor_interrupt_inhibit,
    monitor_map_offset_low => monitor_map_offset_low,
    monitor_map_offset_high => monitor_map_offset_high,
    monitor_map_enables_low => monitor_map_enables_low,
    monitor_map_enables_high => monitor_map_enables_high,
    
    monitor_mem_address => monitor_mem_address,
    monitor_mem_rdata => monitor_mem_rdata,
    monitor_mem_wdata => monitor_mem_wdata,
    monitor_mem_read => monitor_mem_read,
    monitor_mem_write => monitor_mem_write,
    monitor_mem_setpc => monitor_mem_setpc,
    monitor_mem_attention_request => monitor_mem_attention_request,
    monitor_mem_attention_granted => monitor_mem_attention_granted,
    monitor_mem_trace_mode => monitor_mem_trace_mode,
    monitor_mem_stage_trace_mode => monitor_mem_stage_trace_mode,
    monitor_mem_trace_toggle => monitor_mem_trace_toggle
    );

  process (cpuclock) is
  begin
    if rising_edge(cpuclock) then
      pmodb_in_buffer(0) <= pmod_clock;
      pmodb_in_buffer(1) <= pmod_start_of_sequence;
      pmodb_in_buffer(5 downto 2) <= pmod_data_in;
      pmod_data_out <= pmodb_out_buffer;
      flopled <= drive_led_out;
      flopmotor <= motor;
    end if;
  end process;

  process (pixelclock) is
  begin
    if rising_edge(pixelclock) then
      -- Enforce black output outside of frame, so that
      -- compositors can't mess the frame up
      viciv_outofframe_3 <= viciv_outofframe_2;
      viciv_outofframe_2 <= viciv_outofframe_1;
      viciv_outofframe_1 <= viciv_outofframe;
      if viciv_outofframe_3 = '1' then
        vgared <= (others => '0');
        vgagreen <= (others => '0');
        vgablue <= (others => '0');
      else
        vgared <= vgared_out;
        vgagreen <= vgagreen_out;
        vgablue <= vgablue_out;
      end if;
    end if;
  end process;
  
  UART_TXD<=uart_txd_sig; 
  
end Behavioral;

