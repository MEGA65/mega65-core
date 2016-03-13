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
  Port ( pixelclock : STD_LOGIC;
         pixelclock2x : STD_LOGIC;
         cpuclock : std_logic;
         clock50mhz : in std_logic;
         ioclock : std_logic;
         uartclock : std_logic;
         btnCpuReset : in  STD_LOGIC;
         irq : in  STD_LOGIC;
         nmi : in  STD_LOGIC;

         no_kickstart : in std_logic;

         ddr_counter : in unsigned(7 downto 0);
         ddr_state : in unsigned(7 downto 0);
         
         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vsync : out  STD_LOGIC;
         hsync : out  STD_LOGIC;
         vgared : out  UNSIGNED (3 downto 0);
         vgagreen : out  UNSIGNED (3 downto 0);
         vgablue : out  UNSIGNED (3 downto 0);

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
         
         ----------------------------------------------------------------------
         -- Flash RAM for holding config
         ----------------------------------------------------------------------
         QspiSCK : out std_logic;
         QspiDB : inout std_logic_vector(3 downto 0);
         QspiCSn : out std_logic;

         fpga_temperature : in std_logic_vector(11 downto 0);
         
         ---------------------------------------------------------------------------
         -- Interface to Slow RAM (128MB DDR2 RAM chip)
         ---------------------------------------------------------------------------
         slowram_addr_reflect : in std_logic_vector(26 downto 0);
         slowram_datain_reflect : in std_logic_vector(7 downto 0);
         slowram_addr : out std_logic_vector(26 downto 0);
         slowram_we : out std_logic;
         slowram_request_toggle : out std_logic;
         slowram_done_toggle : in std_logic;
         slowram_datain : out std_logic_vector(7 downto 0);
         -- simple-dual-port cache RAM interface so that CPU doesn't have to read
         -- data cross-clock
         cache_address        : out std_logic_vector(8 downto 0);
         cache_read_data      : in std_logic_vector(150 downto 0);   

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

  component uart_monitor
    port (
    reset : in std_logic;
    clock : in std_logic;
    tx : out std_logic;
    rx : in  std_logic;
    activity : out std_logic;
    
    key_scancode : out unsigned(15 downto 0);
    key_scancode_toggle : out std_logic;

    force_single_step : in std_logic;
    
    fastio_read : in std_logic;
    fastio_write : in std_logic;

    monitor_char : in unsigned(7 downto 0);
    monitor_char_toggle : in std_logic;
    
    monitor_proceed : in std_logic;
    monitor_waitstates : in unsigned(7 downto 0);
    monitor_request_reflected : in std_logic;
    monitor_pc : in unsigned(15 downto 0);
    monitor_hypervisor_mode : in std_logic;
    monitor_ddr_ram_banking : in std_logic;
    monitor_cpu_state : in unsigned(15 downto 0);
    monitor_instruction : in unsigned(7 downto 0);
    monitor_watch : out unsigned(27 downto 0) := x"7FFFFFF";
    monitor_watch_match : in std_logic;
    monitor_opcode : in unsigned(7 downto 0);
    monitor_ibytes : in std_logic_vector(3 downto 0);
    monitor_arg1 : in unsigned(7 downto 0);
    monitor_arg2 : in unsigned(7 downto 0);
    monitor_a : in unsigned(7 downto 0);
    monitor_x : in unsigned(7 downto 0);
    monitor_y : in unsigned(7 downto 0);
    monitor_z : in unsigned(7 downto 0);
    monitor_b : in unsigned(7 downto 0);
    monitor_sp : in unsigned(15 downto 0);
    monitor_p : in unsigned(7 downto 0);
    monitor_map_offset_low : in unsigned(11 downto 0);
    monitor_map_offset_high : in unsigned(11 downto 0);
    monitor_map_enables_low : in std_logic_vector(3 downto 0);
    monitor_map_enables_high : in std_logic_vector(3 downto 0);
    monitor_interrupt_inhibit : in std_logic;

    monitor_mem_address : out unsigned(27 downto 0);
    monitor_mem_rdata : in unsigned(7 downto 0);
    monitor_mem_wdata : out unsigned(7 downto 0);
    monitor_mem_attention_request : out std_logic := '0';
    monitor_mem_attention_granted : in std_logic;
    monitor_mem_read : out std_logic := '0';
    monitor_mem_write : out std_logic := '0';
    monitor_mem_setpc : out std_logic := '0';
    monitor_mem_stage_trace_mode : out std_logic := '0';
    monitor_mem_trace_mode : out std_logic := '0';
    monitor_mem_trace_toggle : out std_logic := '0'
      );
  end component;

  component gs4510
    port (
      Clock : in std_logic;
      ioclock : in std_logic;
      reset : in std_logic;
      irq : in std_logic;
      nmi : in std_logic;
      hyper_trap : in std_logic;
      cpu_hypervisor_mode : out std_logic;

      cpuis6502 : out std_logic;
      cpuspeed : out unsigned(7 downto 0);
      
      irq_hypervisor : in std_logic_vector(2 downto 0);  -- JBM

      no_kickstart : in std_logic;

      ddr_counter : in unsigned(7 downto 0);
      ddr_state : in unsigned(7 downto 0);
    
      reg_isr_out : in unsigned(7 downto 0);
      imask_ta_out : in std_logic;

      vicii_2mhz : in std_logic;
      viciii_fast : in std_logic;
      viciv_fast : in std_logic;
      speed_gate : in std_logic;
      speed_gate_enable : out std_logic;

      monitor_char : out unsigned(7 downto 0);
      monitor_char_toggle : out std_logic;    

      monitor_proceed : out std_logic;
      monitor_waitstates : out unsigned(7 downto 0);
      monitor_request_reflected : out std_logic;
      monitor_hypervisor_mode : out std_logic;
      monitor_ddr_ram_banking : out std_logic;
      monitor_pc : out unsigned(15 downto 0);
      monitor_state : out unsigned(15 downto 0);
      monitor_instruction : out unsigned(7 downto 0);
      monitor_instructionpc : out unsigned(15 downto 0);
      monitor_watch : in unsigned(27 downto 0);
      monitor_watch_match : out std_logic;
      monitor_opcode : out unsigned(7 downto 0);
      monitor_ibytes : out std_logic_vector(3 downto 0);
      monitor_arg1 : out unsigned(7 downto 0);
      monitor_arg2 : out unsigned(7 downto 0);
      monitor_a : out unsigned(7 downto 0);
      monitor_b : out unsigned(7 downto 0);
      monitor_x : out unsigned(7 downto 0);
      monitor_y : out unsigned(7 downto 0);
      monitor_z : out unsigned(7 downto 0);
      monitor_sp : out unsigned(15 downto 0);
      monitor_p : out unsigned(7 downto 0);
      monitor_map_offset_low : out unsigned(11 downto 0);
      monitor_map_offset_high : out unsigned(11 downto 0);
      monitor_map_enables_low : out std_logic_vector(3 downto 0);
      monitor_map_enables_high : out std_logic_vector(3 downto 0);
      monitor_interrupt_inhibit : out std_logic;

      ---------------------------------------------------------------------------
      -- Memory access interface used by monitor
      ---------------------------------------------------------------------------
      monitor_mem_address : in unsigned(27 downto 0);
      monitor_mem_rdata : out unsigned(7 downto 0);
      monitor_mem_wdata : in unsigned(7 downto 0);
      monitor_mem_read : in std_logic;
      monitor_mem_write : in std_logic;
      monitor_mem_setpc : in std_logic;
      monitor_mem_attention_request : in std_logic;
      monitor_mem_attention_granted : out std_logic;
      monitor_mem_trace_mode : in std_logic;
      monitor_mem_stage_trace_mode : in std_logic;
      monitor_mem_trace_toggle : in std_logic;

      ---------------------------------------------------------------------------
      -- Interface to Slow RAM (128MB DDR2 RAM disguised as SRAM)
      ---------------------------------------------------------------------------
      slowram_addr : out std_logic_vector(26 downto 0);
      slowram_we : out std_logic;
      slowram_addr_reflect : in std_logic_vector(26 downto 0);
      slowram_datain_reflect : in std_logic_vector(7 downto 0);
      slowram_request_toggle : out std_logic;
      slowram_done_toggle : in std_logic;
      slowram_datain : out std_logic_vector(7 downto 0);
      -- simple-dual-port cache RAM interface so that CPU doesn't have to read
      -- data cross-clock
      cache_address        : out std_logic_vector(8 downto 0);
      cache_read_data      : in std_logic_vector(150 downto 0);   
      
      cpu_leds : out std_logic_vector(3 downto 0);              

      ---------------------------------------------------------------------------
      -- Interface to ChipRAM in video controller (just 128KB for now)
      ---------------------------------------------------------------------------
      chipram_we : OUT STD_LOGIC;
      chipram_address : OUT unsigned(16 DOWNTO 0);
      chipram_datain : OUT unsigned(7 DOWNTO 0);
      
      ---------------------------------------------------------------------------
      -- fast IO port (clocked at core clock). 1MB address space
      ---------------------------------------------------------------------------
      fastio_addr : inout std_logic_vector(19 downto 0);
      fastio_read : out std_logic;
      fastio_write : out std_logic;
      fastio_wdata : out std_logic_vector(7 downto 0);
      fastio_rdata : in std_logic_vector(7 downto 0);
      sector_buffer_mapped : in std_logic;
      fastio_vic_rdata : in std_logic_vector(7 downto 0);
      fastio_colour_ram_rdata : in std_logic_vector(7 downto 0);
      colour_ram_cs : out std_logic;
      charrom_write_cs : out std_logic;

      viciii_iomode : in std_logic_vector(1 downto 0);
      iomode_set : out std_logic_vector(1 downto 0);
      iomode_set_toggle : out std_logic;

      colourram_at_dc00 : in std_logic;
      rom_at_e000 : in std_logic;
      rom_at_c000 : in std_logic;
      rom_at_a000 : in std_logic;
      rom_at_8000 : in std_logic;

      ---------------------------------------------------------------------------
      -- IO port to far call stack
      ---------------------------------------------------------------------------
      farcallstack_we : out std_logic;
      farcallstack_addr : out std_logic_vector(8 downto 0);
      farcallstack_din : out std_logic_vector(63 downto 0);
      farcallstack_dout : in std_logic_vector(63 downto 0)

      );
  end component;
  
  component viciv is
    Port (
      pixelclock : in  STD_LOGIC;
      pixelclock2x : in  STD_LOGIC;
      cpuclock : in std_logic;
      ioclock : in std_logic;

      irq : out std_logic;
      reset : in std_logic;

      led : in std_logic;
      motor : in std_logic;
      drive_led_out : out std_logic;

      xray_mode : in std_logic;
      
      ----------------------------------------------------------------------
      -- VGA output
      ----------------------------------------------------------------------
      vsync : out  STD_LOGIC;
      hsync : out  STD_LOGIC;
      vgared : out  UNSIGNED (3 downto 0);
      vgagreen : out  UNSIGNED (3 downto 0);
      vgablue : out  UNSIGNED (3 downto 0);

      pixel_stream_out : out unsigned (7 downto 0);
      pixel_y : out unsigned (11 downto 0);
      pixel_valid : out std_logic;   
      pixel_newframe : out std_logic;
      pixel_newraster : out std_logic;

      ---------------------------------------------------------------------------
      -- CPU Interface to ChipRAM in video controller (just 128KB for now)
      ---------------------------------------------------------------------------
      chipram_we : IN STD_LOGIC;
      chipram_address : IN unsigned(16 DOWNTO 0);
      chipram_datain : IN unsigned(7 DOWNTO 0);

      -----------------------------------------------------------------------------
      -- FastIO interface for accessing video registers
      -----------------------------------------------------------------------------
      fastio_addr : in std_logic_vector(19 downto 0);
      fastio_read : in std_logic;
      fastio_write : in std_logic;
      fastio_wdata : in std_logic_vector(7 downto 0);
      fastio_rdata : out std_logic_vector(7 downto 0);
      colour_ram_fastio_rdata : out std_logic_vector(7 downto 0);
      colour_ram_cs : in std_logic;
      charrom_write_cs : in std_logic;

      viciii_iomode : out std_logic_vector(1 downto 0);
      iomode_set : in std_logic_vector(1 downto 0);
      iomode_set_toggle : in std_logic;

      vicii_2mhz : out std_logic;
      viciii_fast : out std_logic;
      viciv_fast : out std_logic;
      
      colourram_at_dc00 : out std_logic;
      rom_at_e000 : out std_logic;
      rom_at_c000 : out std_logic;
      rom_at_a000 : out std_logic;
      rom_at_8000 : out std_logic
      );
  end component;
  
  component iomapper is
    port (Clk : in std_logic;
          cpuclock : in std_logic;
          pixelclk : in std_logic;
          clock50mhz : in std_logic;
          
          reg_isr_out : out unsigned(7 downto 0);
          imask_ta_out : out std_logic;
          cpu_hypervisor_mode : in std_logic;

          fpga_temperature : in std_logic_vector(11 downto 0);
          
          key_scancode : in unsigned(15 downto 0);
          key_scancode_toggle : in std_logic;

          capslock_state : inout std_logic;
          speed_gate : out std_logic;
          speed_gate_enable : in std_logic;
          
          uartclock : in std_logic;
          phi0 : in std_logic;
          reset : in std_logic;
          reset_out : out std_logic;
          irq : out std_logic;
          nmi : out std_logic;
          hyper_trap : out std_logic;
          restore_nmi : out std_logic;
          address : in std_logic_vector(19 downto 0);
          r : in std_logic;
          w : in std_logic;
          data_i : in std_logic_vector(7 downto 0);
          data_o : out std_logic_vector(7 downto 0);
          sd_data_o : out std_logic_vector(7 downto 0);
          sector_buffer_mapped : out std_logic;
          colourram_at_dc00 : in std_logic;
          viciii_iomode : in std_logic_vector(1 downto 0);

          drive_led : out std_logic;
          motor : out std_logic;
          drive_led_out : in std_logic;

          sw : in std_logic_vector(15 downto 0);
          btn : in std_logic_vector(4 downto 0);
          seg_led : out unsigned(31 downto 0);

          pmod_clock : in std_logic;
          pmod_start_of_sequence : in std_logic;
          pmod_data_in : in std_logic_vector(3 downto 0);
          pmod_data_out : out std_logic_vector(1 downto 0);
          pmoda : inout std_logic_vector(7 downto 0);
          
          pixel_stream_in : in unsigned (7 downto 0);
          pixel_y : in unsigned (11 downto 0);
          pixel_valid : in std_logic;
          pixel_newframe : in std_logic;
          pixel_newraster : in std_logic;   
          
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

          ----------------------------------------------------------------------
          -- Flash RAM for holding config
          ----------------------------------------------------------------------
          QspiSCK : out std_logic;
          QspiDB : inout std_logic_vector(3 downto 0);
          QspiCSn : out std_logic;
          
          -------------------------------------------------------------------------
          -- Lines for the SDcard interface itself
          -------------------------------------------------------------------------
          cs_bo : out std_logic;
          sclk_o : out std_logic;
          mosi_o : out std_logic;
          miso_i : in  std_logic;

          ---------------------------------------------------------------------------
          -- IO port to far call stack
          ---------------------------------------------------------------------------
          farcallstack_we : in std_logic;
          farcallstack_addr : in std_logic_vector(8 downto 0);
          farcallstack_din : in std_logic_vector(63 downto 0);
          farcallstack_dout : out std_logic_vector(63 downto 0);
          
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
          ampSD : out std_logic;

          micData : in std_logic;
          micClk : out std_logic;
          micLRSel : out std_logic;

          tmpSDA : out std_logic;
          tmpSCL : out std_logic;
          tmpInt : in std_logic;
          tmpCT : in std_logic;

          uart_rx : in std_logic;
          uart_tx : out std_logic;

          ps2data : in std_logic;
          ps2clock : in std_logic
          );
  end component;

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
  signal capslock_state : std_logic;
  signal speed_gate : std_logic;
  signal speed_gate_enable : std_logic;
  
  signal drive_led : std_logic;
  signal motor : std_logic;
  signal drive_led_out : std_logic;
  
  signal seg_led_data : unsigned(31 downto 0);

  signal reset_out : std_logic;
  -- Holds reset on for 8 cycles so that reset line entry is used on start up,
  -- instead of implicit startup state.
  signal power_on_reset : std_logic_vector(7 downto 0) := (others => '0');
  signal reset_combined : std_logic;
  
  signal io_irq : std_logic;
  signal io_nmi : std_logic;
  signal vic_irq : std_logic;
  signal combinedirq : std_logic;
  signal combinednmi : std_logic;
  signal restore_nmi : std_logic;
  signal hyper_trap : std_logic;

  signal fastio_addr : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);
  signal fastio_vic_rdata : std_logic_vector(7 downto 0);
  signal colour_ram_fastio_rdata : std_logic_vector(7 downto 0);
  signal sector_buffer_mapped : std_logic;

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
  signal monitor_ddr_ram_banking : std_logic;
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
  constant phi0_divisor : integer := 95;
  signal phi0_counter : integer range 0 to phi0_divisor;

  signal pixel_stream : unsigned (7 downto 0);
  signal pixel_y : unsigned (11 downto 0);
  signal pixel_valid : std_logic;
  signal pixel_newframe : std_logic;
  signal pixel_newraster : std_logic;

  signal farcallstack_we : std_logic;
  signal farcallstack_addr : std_logic_vector(8 downto 0);
  signal farcallstack_din : std_logic_vector(63 downto 0);
  signal farcallstack_dout : std_logic_vector(63 downto 0);

begin

  ----------------------------------------------------------------------------
  -- IRQ & NMI: If either the hardware buttons on the FPGA board or an IO
  -- device via the IOmapper pull an interrupt line down, then trigger an
  -- interrupt.
  -----------------------------------------------------------------------------
  process(irq,nmi,restore_nmi,io_irq,vic_irq,io_nmi,sw,reset_out,btnCpuReset,
          power_on_reset)
  begin
    -- XXX Allow switch 0 to mask IRQs
    combinedirq <= ((irq and io_irq and vic_irq) or sw(0));
    combinednmi <= (nmi and io_nmi and restore_nmi) or sw(14);
    if btnCpuReset='0' then reset_combined <= '0';
    elsif reset_out='0' then reset_combined <= '0';
    elsif power_on_reset(0)='0' then reset_combined <= '0';
    else
      reset_combined <= '1';
    end if;
    -- report "btnCpuReset = " & std_logic'image(btnCpuReset) & ", reset_out = " & std_logic'image(reset_out) & ", sw(15) = " & std_logic'image(sw(15)) severity note;
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
      led(9 downto 6) <= (others => '0');
      led(10) <= cpu_hypervisor_mode;           -- JBM
      led(11) <= monitor_hypervisor_mode;       -- JBM
      led(12) <= '0';                           -- JBM
      led(15) <= speed_gate_enable;
      led(14) <= speed_gate;
      led(13) <= capslock_state;

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
        --digit := std_logic_vector(seg_led_data(19 downto 16));
        digit := (others => '0');
      elsif segled_counter(17 downto 15)=5 then
        --digit := std_logic_vector(seg_led_data(23 downto 20));
        digit := (others => '0');
      elsif segled_counter(17 downto 15)=6 then
        digit := std_logic_vector(seg_led_data(27 downto 24));
      elsif segled_counter(17 downto 15)=7 then
        digit := std_logic_vector(seg_led_data(31 downto 28));
      end if;
      
      if cpuis6502 = '1' then
        seg_led_data(15 downto 0) <= x"6510";
      else
        seg_led_data(15 downto 0) <= x"4502";
      end if;
      seg_led_data(31 downto 24) <= cpuspeed;
      
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
  
  cpu0: gs4510 port map(
    clock => cpuclock,
    ioclock => ioclock,
    reset =>reset_combined,
    irq => combinedirq,
    nmi => combinednmi,
    hyper_trap => hyper_trap,
    speed_gate => speed_gate,
    speed_gate_enable => speed_gate_enable,
    cpuis6502 => cpuis6502,
    cpuspeed => cpuspeed,

    irq_hypervisor => sw(4 downto 2),    -- JBM
    
    ddr_state => ddr_state,
    ddr_counter => ddr_counter,

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
    monitor_proceed => monitor_proceed,
--    monitor_debug_memory_access => monitor_debug_memory_access,
    monitor_waitstates => monitor_waitstates,
    monitor_request_reflected => monitor_request_reflected,
    monitor_hypervisor_mode => monitor_hypervisor_mode,
    monitor_ddr_ram_banking => monitor_ddr_ram_banking,
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

    slowram_addr => slowram_addr,
    slowram_we => slowram_we,
    slowram_request_toggle => slowram_request_toggle,
    slowram_done_toggle => slowram_done_toggle,
    slowram_datain => slowram_datain,
    slowram_addr_reflect => slowram_addr_reflect,
    slowram_datain_reflect => slowram_datain_reflect,
    cache_address => cache_address,
    cache_read_data => cache_read_data,
    
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

  viciv0: viciv
    port map (
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
      vgared          => vgared,
      vgagreen        => vgagreen,
      vgablue         => vgablue,

      pixel_stream_out => pixel_stream,
      pixel_y => pixel_y,
      pixel_valid => pixel_valid,
      pixel_newframe => pixel_newframe,
      pixel_newraster => pixel_newraster,
      
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
  
  iomapper0: iomapper port map (
    clk => ioclock,
    cpuclock => cpuclock,
    pixelclk => pixelclock,
    clock50mhz => clock50mhz,
    cpu_hypervisor_mode => cpu_hypervisor_mode,
    capslock_state => capslock_state,
    speed_gate => speed_gate,
    speed_gate_enable => speed_gate_enable,
    
    fpga_temperature => fpga_temperature,
    
    reg_isr_out => reg_isr_out,
    imask_ta_out => imask_ta_out,    

    key_scancode => key_scancode,
    key_scancode_toggle => key_scancode_toggle,
    
    uartclock => uartclock,
    phi0 => phi0,
    reset => reset_combined,
    reset_out => reset_out,
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

    pixel_stream_in => pixel_stream,
    pixel_y => pixel_y,
    pixel_valid => pixel_valid,
    pixel_newframe => pixel_newframe,
    pixel_newraster => pixel_newraster,

    pmod_clock => pmodb_in_buffer(0),
    pmod_start_of_sequence => pmodb_in_buffer(1),
    pmod_data_in => pmodb_in_buffer(5 downto 2),
    pmod_data_out => pmodb_out_buffer(1 downto 0),
    
    pmoda => pmoda,

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
    
    QspiSCK => QspiSCK,
    QspiDB => QspiDB,
    QspiCSn => QspiCSn,
    
    aclMISO => aclMISO,
    aclMOSI => aclMOSI,
    aclSS => aclSS,
    aclSCK => aclSCK,
    aclInt1 => aclInt1,
    aclInt2 => aclInt2,
    
    ampPWM => ampPWM,
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
    ps2clock => ps2clock
    );

  -----------------------------------------------------------------------------
  -- UART interface for monitor debugging and loading data
  -----------------------------------------------------------------------------
  monitor0 : uart_monitor port map (
    reset => reset_combined,
    clock => uartclock,
    tx       => UART_TXD,
    rx       => RsRx,

    force_single_step => sw(11),
    
    fastio_read => fastio_read,
    fastio_write => fastio_write,

    key_scancode => key_scancode,
    key_scancode_toggle => key_scancode_toggle,

    monitor_char => monitor_char,
    monitor_char_toggle => monitor_char_toggle,
--    monitor_debug_memory_access => monitor_debug_memory_access,
--    monitor_debug_memory_access => (others => '1'),
    monitor_proceed => monitor_proceed,
    monitor_waitstates => monitor_waitstates,
    monitor_request_reflected => monitor_request_reflected,
    monitor_hypervisor_mode => monitor_hypervisor_mode,
    monitor_ddr_ram_banking => monitor_ddr_ram_banking,
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
    end if;
  end process;
  
end Behavioral;

