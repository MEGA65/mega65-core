-- Accelerated 6502-like CPU for the C65GS
--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
--
-- * ADC/SBC algorithm derived from  6510core.c - WICE MOS6510 emulation core.
-- *   Written by
-- *    Ettore Perazzoli <ettore@comm2000.it>
-- *    Andreas Boose <viceteam@t-online.de>
-- *
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

-- @IO:C65 $D0A0-$D0FF - Reserved for C65 RAM Expansion Controller.

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity gs4510 is
  port (
    Clock : in std_logic;
    ioclock : in std_logic;
    reset : in std_logic;
    irq : in std_logic;
    nmi : in std_logic;
    hyper_trap : in std_logic;

    cpu_hypervisor_mode : out std_logic;
    iomode_set : out std_logic_vector(1 downto 0) := "11";
    iomode_set_toggle : out std_logic := '0';

    cpuis6502 : out std_logic;
    cpuspeed : out unsigned(7 downto 0);

    irq_hypervisor : in std_logic_vector(2 downto 0) := "000";    -- JBM

    no_kickstart : in std_logic;

    ddr_counter : in unsigned(7 downto 0);
    ddr_state : in unsigned(7 downto 0);   
    
    reg_isr_out : in unsigned(7 downto 0);
    imask_ta_out : in std_logic;

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
      monitor_watch : in unsigned(27 downto 0);
      monitor_watch_match : out std_logic;
      monitor_instructionpc : out unsigned(15 downto 0);
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
    -- Interface to ChipRAM in video controller (just 128KB for now)
    ---------------------------------------------------------------------------
    chipram_we : OUT STD_LOGIC := '0';
    chipram_address : OUT unsigned(16 DOWNTO 0) := "00000000000000000";
    chipram_datain : OUT unsigned(7 DOWNTO 0);

    ---------------------------------------------------------------------------
    -- Interface to Slow RAM (128MB DDR2 RAM (or 16MB cellular RAM chip on
    -- original non-DDR Nexys4 boards)
    ---------------------------------------------------------------------------
    slowram_addr_reflect : in std_logic_vector(26 downto 0);
    slowram_datain_reflect : in std_logic_vector(7 downto 0);
    slowram_addr : out std_logic_vector(26 downto 0);
    slowram_we : out std_logic := '0';
    slowram_request_toggle : out std_logic := '0';
    slowram_done_toggle : in std_logic;
    slowram_datain : out std_logic_vector(7 downto 0);
    -- simple-dual-port cache RAM interface so that CPU doesn't have to read
    -- data cross-clock
    cache_address        : out std_logic_vector(8 downto 0);
    cache_read_data      : in std_logic_vector(150 downto 0);   

    cpu_leds : out std_logic_vector(3 downto 0);

    ---------------------------------------------------------------------------
    -- Control CPU speed.  Use 
    ---------------------------------------------------------------------------
    --         C128 2MHZ ($D030)  : C65 FAST ($D031) : C65GS FAST ($D054)
    -- ~1MHz   0                  : 0                : X
    -- ~2MHz   1                  : 0                : 0
    -- ~3.5MHz 0                  : 1                : 0
    -- 48MHz   1                  : X                : 1
    -- 48MHz   X                  : 1                : 1
    ---------------------------------------------------------------------------    
    vicii_2mhz : in std_logic;
    viciii_fast : in std_logic;
    viciv_fast : in std_logic;
    speed_gate : in std_logic;
    speed_gate_enable : out std_logic := '1';
    
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

    colourram_at_dc00 : in std_logic;
    rom_at_e000 : in std_logic;
    rom_at_c000 : in std_logic;
    rom_at_a000 : in std_logic;
    rom_at_8000 : in std_logic;

    ---------------------------------------------------------------------------
    -- IO port to far call stack
    ---------------------------------------------------------------------------
    farcallstack_we : out std_logic := '0';
    farcallstack_addr : out std_logic_vector(8 downto 0) := (others => '0');
    farcallstack_din : out std_logic_vector(63 downto 0) := (others => '0');
    farcallstack_dout : in std_logic_vector(63 downto 0) := (others => '0')

    );
end entity gs4510;

architecture Behavioural of gs4510 is
  
component shadowram is
  port (Clk : in std_logic;
        address : in integer range 0 to 131071;
        we : in std_logic;
        data_i : in unsigned(7 downto 0);
        data_o : out unsigned(7 downto 0);
        no_writes : out unsigned(7 downto 0);
        writes : out unsigned(7 downto 0)
        );
end component;

  -- Pre-calculated long addresses for 16 by 4KB sections.
  -- (used to flatten logic depth)
  type address_block_array is array(31 downto 0) of unsigned(31 downto 0);
  signal block_addresses : address_block_array;
  signal block_update_number : integer range 0 to 31 := 0;

  signal reset_drive : std_logic := '0';

  signal force_fast : std_logic := '0';
  signal speed_gate_enable_internal : std_logic := '1';

  signal iomode_set_toggle_internal : std_logic := '0';
  signal rom_from_colour_ram : std_logic := '0';
  signal rom_writeprotect : std_logic := '0';

  -- Instruction log
  signal last_instruction_pc : unsigned(15 downto 0) := x"FFFF";
  signal last_opcode : unsigned(7 downto 0);
  signal last_byte2 : unsigned(7 downto 0);
  signal last_byte3 : unsigned(7 downto 0);
  signal last_bytecount : integer range 0 to 3 := 0;
  signal last_action : character := ' ';
  signal last_address : unsigned(27 downto 0);
  signal last_value : unsigned(7 downto 0);

  -- Shadow RAM control
  signal shadow_bank : unsigned(7 downto 0);
  signal shadow_address : integer range 0 to 131071;
  signal shadow_rdata : unsigned(7 downto 0);
  signal shadow_wdata : unsigned(7 downto 0);
  signal shadow_write_count : unsigned(7 downto 0);
  signal shadow_no_write_count : unsigned(7 downto 0);
  signal shadow_try_write_count : unsigned(7 downto 0) := x"00";
  signal shadow_observed_write_count : unsigned(7 downto 0) := x"00";
  signal shadow_write : std_logic := '0';

  -- ROM RAM control
  signal rom_address : integer range 0 to 131071;
  signal rom_rdata : unsigned(7 downto 0);
  signal rom_wdata : unsigned(7 downto 0);
  signal rom_write_count : unsigned(7 downto 0);
  signal rom_no_write_count : unsigned(7 downto 0);
  signal rom_write : std_logic := '0';

  -- GeoRAM emulation: by default point it somewhere at the DDR RAM
  signal georam_page : unsigned(19 downto 0) := x"e0000";
  signal georam_blockmask : unsigned(7 downto 0) := x"ff";
  signal georam_block : unsigned(7 downto 0) := x"00";
  signal georam_blockpage : unsigned(7 downto 0) := x"00";

  -- REU emulation
  signal reu_reg_status : unsigned(7 downto 0) := x"00"; -- read only
  signal reu_cmd_autoload : std_logic := '0';
  signal reu_cmd_ff00decode : std_logic := '0';
  signal reu_cmd_operation : std_logic_vector(1 downto 0) := "00";
  signal reu_c64_startaddr : unsigned(15 downto 0) := x"0000";
  signal reu_reu_startaddr : unsigned(23 downto 0) := x"000000";
  signal reu_transfer_length : unsigned(15 downto 0) := x"0000";
  signal reu_useless_interrupt_mask : unsigned(7 downto 5) := "000";
  signal reu_hold_c64_address : std_logic := '0';
  signal reu_hold_reu_address : std_logic := '0';
  signal reu_ff00_pending : std_logic := '0';

  signal last_fastio_addr : std_logic_vector(19 downto 0);
  signal last_write_address : unsigned(27 downto 0);
  signal shadow_write_flags : unsigned(3 downto 0) := "0000";
  -- Registers to hold delayed write to hypervisor and related CPU registers
  -- to improve CPU timing closure.
  signal last_write_value : unsigned(7 downto 0);
  signal last_write_pending : std_logic := '0';

  -- On the original Nexys4 board:
  -- SlowRAM has 70ns access time, so need some wait states.
  -- At 48MHz we only need 4 cycles.
  -- (had +2 extra for drive stages)
  -- On the Nexys4DDR board, the DDR2 ram is annoying MUCH slower,
  -- requiring $16 = 22 cycles to be reliable!
  -- We really are going to want to have a slowram cache!
  -- It will be fairly trivial to read 128 bits (16 bytes) of slowram at a time
  -- and cache that, since that is exactly how the DDR RAM module wrapper works
  -- internally.  Thus for sequential memory accesses, we can get 16 bytes every
  -- 22 cycles, and potentially service memory reads with just one wait-state on
  -- average (although the CPU state machine would make this a little interesting
  -- to achieve.  2 wait states on the other hand would be quite achievable, and
  -- would still be 3x the speed of slowram currently.
  -- Shadow RAM has 0 wait states by default
  -- IO has one waitstate for reading, 0 for writing
  -- (Reading incurrs an extra waitstate due to read_data_copy)
  -- XXX An extra wait state seems to be necessary when reading from dual-port
  -- memories like colour ram.
  constant slowram_48mhz : unsigned(7 downto 0) := x"ff";
  constant ioread_48mhz : unsigned(7 downto 0) := x"01";
  constant colourread_48mhz : unsigned(7 downto 0) := x"02";
  constant iowrite_48mhz : unsigned(7 downto 0) := x"00";
  constant shadow_48mhz :  unsigned(7 downto 0) := x"00";

  --constant slowram_3mhz : unsigned(7 downto 0) := x"0d";
  --constant ioread_3mhz : unsigned(7 downto 0) := x"0d";
  --constant colourread_3mhz : unsigned(7 downto 0) := x"0d";
  --constant iowrite_3mhz : unsigned(7 downto 0) := x"0d";
  --constant shadow_3mhz :  unsigned(7 downto 0) := x"0d";

  --constant slowram_2mhz : unsigned(7 downto 0) := x"1b";
  --constant ioread_2mhz : unsigned(7 downto 0) := x"1b";
  --constant colourread_2mhz : unsigned(7 downto 0) := x"1b";
  --constant iowrite_2mhz : unsigned(7 downto 0) := x"1b";
  --constant shadow_2mhz :  unsigned(7 downto 0) := x"1b";

  --constant slowram_1mhz : unsigned(7 downto 0) := x"2f";
  --constant ioread_1mhz : unsigned(7 downto 0) := x"2f";
  --constant colourread_1mhz : unsigned(7 downto 0) := x"2f";
  --constant iowrite_1mhz : unsigned(7 downto 0) := x"2f";
  --constant shadow_1mhz :  unsigned(7 downto 0) := x"2f";

  signal slowram_waitstates : unsigned(7 downto 0) := slowram_48mhz;
  signal shadow_wait_states : unsigned(7 downto 0) := shadow_48mhz;
  signal io_read_wait_states : unsigned(7 downto 0) := ioread_48mhz;
  signal colourram_read_wait_states : unsigned(7 downto 0) := colourread_48mhz;
  signal io_write_wait_states : unsigned(7 downto 0) := iowrite_48mhz;

  signal slowram_request_toggle_drive : std_logic := '0';
  signal slowram_desired_done_toggle : std_logic := '0';
  signal slowram_data_valid : std_logic := '0';
  signal slowram_pending_write : std_logic := '0';

  -- Number of pending wait states
  signal wait_states : unsigned(7 downto 0) := x"05";
  signal wait_states_non_zero : std_logic := '1';
  
  signal word_flag : std_logic := '0';

  -- DMAgic registers
  signal dmagic_list_counter : integer range 0 to 12;
  signal dmagic_first_read : std_logic;
  signal reg_dmagic_addr : unsigned(27 downto 0) := x"0000000";
  signal reg_dmagic_withio : std_logic;
  signal reg_dmagic_status : unsigned(7 downto 0) := x"00";
  signal reg_dmacount : unsigned(7 downto 0) := x"00";  -- number of DMA jobs done
  signal dma_pending : std_logic := '0';
  signal dma_checksum : unsigned(23 downto 0) := x"000000";
  signal dmagic_cmd : unsigned(7 downto 0);
  signal dmagic_count : unsigned(15 downto 0);
  signal dmagic_tally : unsigned(15 downto 0);
  signal reg_dmagic_src_mb : unsigned(7 downto 0);
  signal dmagic_src_addr : unsigned(27 downto 0);
  signal dmagic_src_io : std_logic;
  signal dmagic_src_direction : std_logic;
  signal dmagic_src_modulo : std_logic;
  signal dmagic_src_hold : std_logic;
  signal reg_dmagic_dst_mb : unsigned(7 downto 0);
  signal dmagic_dest_addr : unsigned(27 downto 0);
  signal dmagic_dest_io : std_logic;
  signal dmagic_dest_direction : std_logic;
  signal dmagic_dest_modulo : std_logic;
  signal dmagic_dest_hold : std_logic;
  signal dmagic_modulo : unsigned(15 downto 0);
  -- Temporary registers used while loading DMA list
  signal dmagic_dest_bank_temp : unsigned(7 downto 0);
  signal dmagic_src_bank_temp : unsigned(7 downto 0);


  -- CPU internal state
  signal flag_c : std_logic;        -- carry flag
  signal flag_z : std_logic;        -- zero flag
  signal flag_d : std_logic;        -- decimal mode flag
  signal flag_n : std_logic;        -- negative flag
  signal flag_v : std_logic;        -- positive flag
  signal flag_i : std_logic;        -- interrupt disable flag
  signal flag_e : std_logic;        -- 8-bit stack flag

  signal reg_a : unsigned(7 downto 0);
  signal reg_b : unsigned(7 downto 0);
  signal reg_x : unsigned(7 downto 0);
  signal reg_y : unsigned(7 downto 0);
  signal reg_z : unsigned(7 downto 0);
  signal reg_sp : unsigned(7 downto 0);
  signal reg_sph : unsigned(7 downto 0);
  signal reg_pc : unsigned(15 downto 0);

  -- CPU RAM bank selection registers.
  -- Now C65 style, but extended by 8 bits to give 256MB address space
  signal reg_mb_low : unsigned(7 downto 0);
  signal reg_mb_high : unsigned(7 downto 0);
  signal reg_map_low : std_logic_vector(3 downto 0);
  signal reg_map_high : std_logic_vector(3 downto 0);
  signal reg_offset_low : unsigned(11 downto 0);
  signal reg_offset_high : unsigned(11 downto 0);

  -- Are we in hypervisor mode?
  signal hypervisor_mode : std_logic := '1';
  signal hypervisor_trap_port : unsigned (6 downto 0);
  -- Have we ever replaced the hypervisor with another?
  -- (used to allow once-only update of hypervisor by kick-up file)
  signal hypervisor_upgraded : std_logic := '0';
  
  -- Duplicates of all CPU registers to hold user-space contents when trapping
  -- to hypervisor.
  signal hyper_iomode : unsigned(7 downto 0);
  signal hyper_dmagic_src_mb : unsigned(7 downto 0);
  signal hyper_dmagic_dst_mb : unsigned(7 downto 0);
  signal hyper_dmagic_list_addr : unsigned(27 downto 0);
  signal hyper_p : unsigned(7 downto 0);
  signal hyper_a : unsigned(7 downto 0);
  signal hyper_b : unsigned(7 downto 0);
  signal hyper_x : unsigned(7 downto 0);
  signal hyper_y : unsigned(7 downto 0);
  signal hyper_z : unsigned(7 downto 0);
  signal hyper_sp : unsigned(7 downto 0);
  signal hyper_sph : unsigned(7 downto 0);
  signal hyper_pc : unsigned(15 downto 0);
  signal hyper_mb_low : unsigned(7 downto 0);
  signal hyper_mb_high : unsigned(7 downto 0);
  signal hyper_port_00 : unsigned(7 downto 0);
  signal hyper_port_01 : unsigned(7 downto 0);
  signal hyper_map_low : std_logic_vector(3 downto 0);
  signal hyper_map_high : std_logic_vector(3 downto 0);
  signal hyper_map_offset_low : unsigned(11 downto 0);
  signal hyper_map_offset_high : unsigned(11 downto 0);

  -- Page table for virtual memory
  signal reg_page0_logical : unsigned(15 downto 0);
  signal reg_page0_physical : unsigned(15 downto 0);
  signal reg_page1_logical : unsigned(15 downto 0);
  signal reg_page1_physical : unsigned(15 downto 0);
  signal reg_page2_logical : unsigned(15 downto 0);
  signal reg_page2_physical : unsigned(15 downto 0);
  signal reg_page3_logical : unsigned(15 downto 0);
  signal reg_page3_physical : unsigned(15 downto 0);
  signal reg_pagenumber : unsigned(17 downto 0);
  signal reg_pages_dirty : std_logic_vector(3 downto 0);
  signal reg_pageid : unsigned(1 downto 0);
  signal reg_pageactive : std_logic := '0';

  -- Flags to detect interrupts
  signal map_interrupt_inhibit : std_logic := '0';
  signal nmi_pending : std_logic := '0';
  signal irq_pending : std_logic := '0';
  signal nmi_state : std_logic := '1';
  signal no_interrupt : std_logic := '0';
  signal hyper_trap_pending : std_logic := '0';
  signal hyper_trap_state : std_logic := '1';
  -- Interrupt/reset vector being used
  signal vector : unsigned(3 downto 0);
  
  -- Information about instruction currently being executed
  signal reg_opcode : unsigned(7 downto 0);
  signal reg_arg1 : unsigned(7 downto 0);
  signal reg_arg2 : unsigned(7 downto 0);

  signal bbs_or_bbc : std_logic;
  signal bbs_bit : unsigned(2 downto 0);
  
  -- PC used for JSR is the value of reg_pc after reading only one of
  -- of the argument bytes.  We could subtract one, but it is less logic to
  -- just remember PC after reading one argument byte.
  signal reg_pc_jsr : unsigned(15 downto 0);
  -- Temporary address register (used for indirect modes)
  signal reg_addr : unsigned(15 downto 0);
  -- ... and this one for 32-bit flat addressing modes
  signal reg_addr32 : unsigned(31 downto 0);
  -- ... and this one for pushing 32bit virtual address onto the stack
  signal reg_addr32save : unsigned(31 downto 0);
  -- Upper and lower
  -- 16 bits of temporary address register. Used for 32-bit
  -- absolute addresses
  signal reg_addr_msbs : unsigned(15 downto 0);
  signal reg_addr_lsbs : unsigned(15 downto 0);
  -- Flag that indicates if a ($nn),Z access is using a 32-bit pointer
  signal absolute32_addressing_enabled : std_logic := '0';
  -- Flag that indicates far JMP, JSR or RTS
  -- (set by two CLD's in a row before the instruction)
  signal flat32_address : std_logic := '0';
  signal flat32_address_prime : std_logic := '0';
  signal flat32_enabled : std_logic := '1';
  -- flag for progressive carry calculation when loading a 32-bit pointer
  signal pointer_carry : std_logic;
  -- Temporary value holder (used for RMW instructions)
  signal reg_t : unsigned(7 downto 0);
  signal reg_t_high : unsigned(7 downto 0);

  signal instruction_phase : unsigned(3 downto 0);
  
-- Indicate source of operand for instructions
-- Note that ROM is actually implemented using
-- power-on initialised RAM in the FPGA mapped via our io interface.
  signal accessing_shadow : std_logic;
  signal accessing_rom : std_logic;
  signal accessing_fastio : std_logic;
  signal accessing_vic_fastio : std_logic;
  signal accessing_colour_ram_fastio : std_logic;
--  signal accessing_ram : std_logic;
  signal accessing_slowram : std_logic;
  signal accessing_cpuport : std_logic;
  signal accessing_hypervisor : std_logic;
  signal cpuport_num : unsigned(3 downto 0);
  signal hyperport_num : unsigned(5 downto 0);
  signal cpuport_ddr : unsigned(7 downto 0) := x"FF";
  signal cpuport_value : unsigned(7 downto 0) := x"3F";
  signal the_read_address : unsigned(27 downto 0);
  
  signal monitor_mem_trace_toggle_last : std_logic := '0';

  -- Microcode data and ALU routing signals follow:

  signal mem_reading : std_logic := '0';
  signal pop_a : std_logic := '0';
  signal pop_p : std_logic := '0';
  signal pop_x : std_logic := '0';
  signal pop_y : std_logic := '0';
  signal pop_z : std_logic := '0';
  signal mem_reading_p : std_logic := '0';
  -- serial monitor is reading data 
  signal monitor_mem_reading : std_logic := '0';

  -- Is CPU free to proceed with processing an instruction?
  signal proceed : std_logic := '1';

  signal read_data_copy : unsigned(7 downto 0);
  
  type instruction_property is array(0 to 255) of std_logic;
  signal op_is_single_cycle : instruction_property := (
    16#03# => '1',
    16#0A# => '1',
    16#0B# => '1',
    16#18# => '1',
    16#1A# => '1',
    16#1B# => '1',
    16#2A# => '1',
    16#2B# => '1',
    16#38# => '1',
    16#3A# => '1',
    16#3B# => '1',
    16#42# => '1',
    16#43# => '1',
    16#4A# => '1',
    16#4B# => '1',
    16#5B# => '1',
    16#6A# => '1',
    16#6B# => '1',
    16#78# => '1',
    16#7B# => '1',
    16#88# => '1',
    16#8A# => '1',
    16#98# => '1',
    16#9A# => '1',
    16#A8# => '1',
    16#AA# => '1',
    16#B8# => '1',
    16#BA# => '1',
    16#C8# => '1',
    16#CA# => '1',
    16#D8# => '1',
    16#E8# => '1',
    16#EA# => '1',
    16#F8# => '1',
    others => '0'
    );

  -- Pause 1usec per cycle of instruction for 1MHz operation
  -- This is only approximate, because it doesnt count the time spent
  -- executing the instruction, or the cycle to setup the delay.
  -- Offsetting this is the lack of badlines, so the end result is probably
  -- close enough for now.  It can be improved later to allow for more exact
  -- timing for demos etc.
  constant pause_per_cycle : integer := 48;
  signal pause_cycles : unsigned(8 downto 0) := "000000000";
  signal pause_cycles_counter : unsigned(8 downto 0) := "000000000";
  signal cpu_pause_shift : integer range 0 to 2 := 0;

  signal vector_read_stage : integer range 0 to 15 := 0;

  type memory_source is (
    DMAgicRegister,
    HypervisorRegister,
    CPUPort,
    Shadow,
    ROMRAM,
    FastIO,
    ColourRAM,
    VICIV,
    SlowRAM,
    Unmapped
    );

  signal read_source : memory_source;

  type processor_state is (
    -- Reset and interrupts
    ResetLow,
    ResetReady,
    Interrupt,InterruptPushPCL,InterruptPushP,
    VectorRead,

    -- Hypervisor traps
    TrapToHypervisor,ReturnFromHypervisor,
    
    -- DMAgic
    DMAgicTrigger,DMAgicReadList,DMAgicGetReady,
    DMAgicFill,
    DMAgicCopyRead,DMAgicCopyWrite,
    DMAgicRead,DMAgicWrite,

    -- Normal instructions
    InstructionWait,                    -- Wait for PC to become available on
                                        -- interrupt/reset
    ProcessorHold,
    ProcessorPause,
    ProcessorPausing,
    MonitorMemoryAccess,
    InstructionFetch,
    InstructionDecode,  -- $16
    InstructionDecode6502,
    Cycle2,Cycle3,
    Flat32Got2ndArgument,Flat32Byte3,Flat32Byte4,
    Flat32SaveAddress,
    Flat32SaveAddress1,Flat32SaveAddress2,Flat32SaveAddress3,Flat32SaveAddress4,
    Flat32Dereference0,
    Flat32Dereference1,Flat32Dereference2,Flat32Dereference3,Flat32Dereference4,
    Flat32Translate,Flat32Dispatch,
    Flat32RTS,
    Pull,
    RTI,RTI2,
    RTS,RTS1,RTS2,RTS3,
    B16TakeBranch,
    InnXReadVectorLow,
    InnXReadVectorHigh,
    InnSPYReadVectorLow,
    InnSPYReadVectorHigh,
    InnYReadVectorLow,
    InnYReadVectorHigh,
    InnZReadVectorLow,
    InnZReadVectorHigh,
    InnZReadVectorByte2,
    InnZReadVectorByte3,
    InnZReadVectorByte4,
    CallSubroutine,CallSubroutine2,
    ZPRelReadZP,
    JumpAbsXReadArg2,
    JumpIAbsReadArg2,
    JumpIAbsXReadArg2,
    JumpDereference,
    JumpDereference2,
    JumpDereference3,
    TakeBranch8,
    LoadTarget,
    WriteCommit,DummyWrite,
    WordOpReadHigh,
    WordOpWriteLow,
    WordOpWriteHigh,
    PushWordLow,PushWordHigh,
    Pop,
    MicrocodeInterpret
    );
  signal state : processor_state := ResetLow;
  signal fast_fetch_state : processor_state := InstructionDecode;
  signal normal_fetch_state : processor_state := InstructionFetch;
  
  signal reg_microcode : microcodeops;

  constant mode_bytes_lut : mode_list := (
    M_impl => 0,
    M_InnX => 1,
    M_nn => 1,
    M_immnn => 1,
    M_A => 0,
    M_nnnn => 2,
    M_nnrr => 2,
    M_rr => 1,
    M_InnY => 1,
    M_InnZ => 1,
    M_rrrr => 2,
    M_nnX => 1,
    M_nnnnY => 2,
    M_nnnnX => 2,
    M_Innnn => 2,
    M_InnnnX => 2,
    M_InnSPY => 1,
    M_nnY => 1,
    M_immnnnn => 2);
  
constant instruction_lut : ilut9bit := (
  -- 4502 personality
    I_BRK,I_ORA,I_CLE,I_SEE,I_TSB,I_ORA,I_ASL,I_RMB,I_PHP,I_ORA,I_ASL,I_TSY,I_TSB,I_ORA,I_ASL,I_BBR,
    I_BPL,I_ORA,I_ORA,I_BPL,I_TRB,I_ORA,I_ASL,I_RMB,I_CLC,I_ORA,I_INC,I_INZ,I_TRB,I_ORA,I_ASL,I_BBR,
    I_JSR,I_AND,I_JSR,I_JSR,I_BIT,I_AND,I_ROL,I_RMB,I_PLP,I_AND,I_ROL,I_TYS,I_BIT,I_AND,I_ROL,I_BBR,
    I_BMI,I_AND,I_AND,I_BMI,I_BIT,I_AND,I_ROL,I_RMB,I_SEC,I_AND,I_DEC,I_DEZ,I_BIT,I_AND,I_ROL,I_BBR,
    I_RTI,I_EOR,I_NEG,I_ASR,I_ASR,I_EOR,I_LSR,I_RMB,I_PHA,I_EOR,I_LSR,I_TAZ,I_JMP,I_EOR,I_LSR,I_BBR,
    I_BVC,I_EOR,I_EOR,I_BVC,I_ASR,I_EOR,I_LSR,I_RMB,I_CLI,I_EOR,I_PHY,I_TAB,I_MAP,I_EOR,I_LSR,I_BBR,
    I_RTS,I_ADC,I_RTS,I_BSR,I_STZ,I_ADC,I_ROR,I_RMB,I_PLA,I_ADC,I_ROR,I_TZA,I_JMP,I_ADC,I_ROR,I_BBR,
    I_BVS,I_ADC,I_ADC,I_BVS,I_STZ,I_ADC,I_ROR,I_RMB,I_SEI,I_ADC,I_PLY,I_TBA,I_JMP,I_ADC,I_ROR,I_BBR,
    I_BRA,I_STA,I_STA,I_BRA,I_STY,I_STA,I_STX,I_SMB,I_DEY,I_BIT,I_TXA,I_STY,I_STY,I_STA,I_STX,I_BBS,
    I_BCC,I_STA,I_STA,I_BCC,I_STY,I_STA,I_STX,I_SMB,I_TYA,I_STA,I_TXS,I_STX,I_STZ,I_STA,I_STZ,I_BBS,
    I_LDY,I_LDA,I_LDX,I_LDZ,I_LDY,I_LDA,I_LDX,I_SMB,I_TAY,I_LDA,I_TAX,I_LDZ,I_LDY,I_LDA,I_LDX,I_BBS,
    I_BCS,I_LDA,I_LDA,I_BCS,I_LDY,I_LDA,I_LDX,I_SMB,I_CLV,I_LDA,I_TSX,I_LDZ,I_LDY,I_LDA,I_LDX,I_BBS,
    I_CPY,I_CMP,I_CPZ,I_DEW,I_CPY,I_CMP,I_DEC,I_SMB,I_INY,I_CMP,I_DEX,I_ASW,I_CPY,I_CMP,I_DEC,I_BBS,
    I_BNE,I_CMP,I_CMP,I_BNE,I_CPZ,I_CMP,I_DEC,I_SMB,I_CLD,I_CMP,I_PHX,I_PHZ,I_CPZ,I_CMP,I_DEC,I_BBS,
    I_CPX,I_SBC,I_LDA,I_INW,I_CPX,I_SBC,I_INC,I_SMB,I_INX,I_SBC,I_EOM,I_ROW,I_CPX,I_SBC,I_INC,I_BBS,
    I_BEQ,I_SBC,I_SBC,I_BEQ,I_PHW,I_SBC,I_INC,I_SMB,I_SED,I_SBC,I_PLX,I_PLZ,I_PHW,I_SBC,I_INC,I_BBS,

    -- 6502 personality
    -- XXX Currently just a copy of 4502 personality
    I_BRK,I_ORA,I_KIL,I_SLO,I_NOP,I_ORA,I_ASL,I_SLO,I_PHP,I_ORA,I_ASL,I_ANC,I_NOP,I_ORA,I_ASL,I_SLO,
    I_BPL,I_ORA,I_KIL,I_SLO,I_NOP,I_ORA,I_ASL,I_SLO,I_CLC,I_ORA,I_NOP,I_SLO,I_NOP,I_ORA,I_ASL,I_SLO,
    I_JSR,I_AND,I_KIL,I_RLA,I_BIT,I_AND,I_ROL,I_RLA,I_PLP,I_AND,I_ROL,I_ANC,I_BIT,I_AND,I_ROL,I_RLA,
    I_BMI,I_AND,I_KIL,I_RLA,I_NOP,I_AND,I_ROL,I_RLA,I_SEC,I_AND,I_NOP,I_RLA,I_NOP,I_AND,I_ROL,I_RLA,
    I_RTI,I_EOR,I_KIL,I_SRE,I_NOP,I_EOR,I_LSR,I_SRE,I_PHA,I_EOR,I_LSR,I_ALR,I_JMP,I_EOR,I_LSR,I_SRE,
    I_BVC,I_EOR,I_KIL,I_SRE,I_NOP,I_EOR,I_LSR,I_SRE,I_CLI,I_EOR,I_NOP,I_SRE,I_NOP,I_EOR,I_LSR,I_SRE,
    I_RTS,I_ADC,I_KIL,I_RRA,I_NOP,I_ADC,I_ROR,I_RRA,I_PLA,I_ADC,I_ROR,I_ARR,I_JMP,I_ADC,I_ROR,I_RRA,
    I_BVS,I_ADC,I_KIL,I_RRA,I_NOP,I_ADC,I_ROR,I_RRA,I_SEI,I_ADC,I_NOP,I_RRA,I_NOP,I_ADC,I_ROR,I_RRA,
    I_NOP,I_STA,I_NOP,I_SAX,I_STY,I_STA,I_STX,I_SAX,I_DEY,I_NOP,I_TXA,I_XAA,I_STY,I_STA,I_STX,I_SAX,
    I_BCC,I_STA,I_KIL,I_AHX,I_STY,I_STA,I_STX,I_SAX,I_TYA,I_STA,I_TXS,I_TAS,I_SHY,I_STA,I_SHX,I_AHX,
    I_LDY,I_LDA,I_LDX,I_LAX,I_LDY,I_LDA,I_LDX,I_LAX,I_TAY,I_LDA,I_TAX,I_LAX,I_LDY,I_LDA,I_LDX,I_LAX,
    I_BCS,I_LDA,I_KIL,I_LAX,I_LDY,I_LDA,I_LDX,I_LAX,I_CLV,I_LDA,I_TSX,I_LAS,I_LDY,I_LDA,I_LDX,I_LAX,
    I_CPY,I_CMP,I_NOP,I_DCP,I_CPY,I_CMP,I_DEC,I_DCP,I_INY,I_CMP,I_DEX,I_AXS,I_CPY,I_CMP,I_DEC,I_DCP,
    I_BNE,I_CMP,I_KIL,I_DCP,I_NOP,I_CMP,I_DEC,I_DCP,I_CLD,I_CMP,I_NOP,I_DCP,I_NOP,I_CMP,I_DEC,I_DCP,
    I_CPX,I_SBC,I_NOP,I_ISC,I_CPX,I_SBC,I_INC,I_ISC,I_INX,I_SBC,I_NOP,I_SBC,I_CPX,I_SBC,I_INC,I_ISC,
    I_BEQ,I_SBC,I_KIL,I_ISC,I_NOP,I_SBC,I_INC,I_ISC,I_SED,I_SBC,I_NOP,I_ISC,I_NOP,I_SBC,I_INC,I_ISC
    );

  
  type mlut9bit is array(0 to 511) of addressingmode;
constant mode_lut : mlut9bit := (
  -- 4502 personality first
    M_impl,  M_InnX,  M_impl,  M_impl,  M_nn,    M_nn,    M_nn,    M_nn,    
    M_impl,  M_immnn, M_A,     M_impl,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnrr,  
    M_rr,    M_InnY,  M_InnZ,  M_rrrr,  M_nn,    M_nnX,   M_nnX,   M_nn,    
    M_impl,  M_nnnnY, M_impl,  M_impl,  M_nnnn,  M_nnnnX, M_nnnnX, M_nnrr,  
    M_nnnn,  M_InnX,  M_Innnn, M_InnnnX,M_nn,    M_nn,    M_nn,    M_nn,    
    M_impl,  M_immnn, M_A,     M_impl,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnrr,  
    M_rr,    M_InnY,  M_InnZ,  M_rrrr,  M_nnX,   M_nnX,   M_nnX,   M_nn,    
    M_impl,  M_nnnnY, M_impl,  M_impl,  M_nnnnX, M_nnnnX, M_nnnnX, M_nnrr,  
    M_impl,  M_InnX,  M_impl,  M_impl,  M_nn,    M_nn,    M_nn,    M_nn,    
    M_impl,  M_immnn, M_A,     M_impl,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnrr,  
    M_rr,    M_InnY,  M_InnZ,  M_rrrr,  M_nnX,   M_nnX,   M_nnX,   M_nn,    
    M_impl,  M_nnnnY, M_impl,  M_impl,  M_impl,  M_nnnnX, M_nnnnX, M_nnrr,
    -- $63 BSR $nnnn is 16-bit relative on the 4502.  We treat it as absolute
    -- mode, with microcode being used to select relative addressing.
    M_impl,  M_InnX,  M_immnn, M_nnnn,  M_nn,    M_nn,    M_nn,    M_nn,    
    M_impl,  M_immnn, M_A,     M_impl,  M_Innnn, M_nnnn,  M_nnnn,  M_nnrr,  
    M_rr,    M_InnY,  M_InnZ,  M_rrrr,  M_nnX,   M_nnX,   M_nnX,   M_nn,    
    M_impl,  M_nnnnY, M_impl,  M_impl,  M_InnnnX,M_nnnnX, M_nnnnX, M_nnrr,  
    M_rr,    M_InnX,  M_InnSPY,M_rrrr,  M_nn,    M_nn,    M_nn,    M_nn,    
    M_impl,  M_immnn, M_impl,  M_nnnnX, M_nnnn,  M_nnnn,  M_nnnn,  M_nnrr,  
    M_rr,    M_InnY,  M_InnZ,  M_rrrr,  M_nnX,   M_nnX,   M_nnY,   M_nn,    
    M_impl,  M_nnnnY, M_impl,  M_nnnnY, M_nnnn,  M_nnnnX, M_nnnnX, M_nnrr,  
    M_immnn, M_InnX,  M_immnn, M_immnn, M_nn,    M_nn,    M_nn,    M_nn,    
    M_impl,  M_immnn, M_impl,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnrr,  
    M_rr,    M_InnY,  M_InnZ,  M_rrrr,  M_nnX,   M_nnX,   M_nnY,   M_nn,
    M_impl,  M_nnnnY, M_impl,  M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnY, M_nnrr,  
    M_immnn, M_InnX,  M_immnn, M_nn,    M_nn,    M_nn,    M_nn,    M_nn,    
    M_impl,  M_immnn, M_impl,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnrr,  
    M_rr,    M_InnY,  M_InnZ,  M_rrrr,  M_nn,    M_nnX,   M_nnX,   M_nn,
    M_impl,  M_nnnnY, M_impl,  M_impl,  M_nnnn,  M_nnnnX, M_nnnnX, M_nnrr,  
    M_immnn, M_InnX,  M_InnSPY,M_nn,    M_nn,    M_nn,    M_nn,    M_nn,    
    M_impl,  M_immnn, M_impl,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnrr,  
    M_rr,    M_InnY,  M_InnZ,  M_rrrr,  M_immnnnn,M_nnX,   M_nnX,   M_nn,    
    M_impl,  M_nnnnY, M_impl,  M_impl,  M_nnnn,  M_nnnnX, M_nnnnX, M_nnrr,

    -- 6502 personality
    -- XXX currently just a copy of 4502 personality
    M_impl,M_InnX,M_impl,M_InnX,M_nn,M_nn,M_nn,M_nn,
    M_impl,M_immnn,M_impl,M_immnn,M_nnnn,M_nnnn,M_nnnn,M_nnnn,
    M_rr,M_InnY,M_impl,M_InnY,M_nnX,M_nnX,M_nnX,M_nnX,
    M_impl,M_nnnnY,M_impl,M_nnnnY,M_nnnnX,M_nnnnX,M_nnnnX,M_nnnnX,
    M_nnnn,M_InnX,M_impl,M_InnX,M_nn,M_nn,M_nn,M_nn,
    M_impl,M_immnn,M_impl,M_immnn,M_nnnn,M_nnnn,M_nnnn,M_nnnn,
    M_rr,M_InnY,M_impl,M_InnY,M_nnX,M_nnX,M_nnX,M_nnX,
    M_impl,M_nnnnY,M_impl,M_nnnnY,M_nnnnX,M_nnnnX,M_nnnnX,M_nnnnX,
    M_impl,M_InnX,M_impl,M_InnX,M_nn,M_nn,M_nn,M_nn,
    M_impl,M_immnn,M_impl,M_immnn,M_nnnn,M_nnnn,M_nnnn,M_nnnn,
    M_rr,M_InnY,M_impl,M_InnY,M_nnX,M_nnX,M_nnX,M_nnX,
    M_impl,M_nnnnY,M_impl,M_nnnnY,M_nnnnX,M_nnnnX,M_nnnnX,M_nnnnX,
    M_impl,M_InnX,M_impl,M_InnX,M_nn,M_nn,M_nn,M_nn,
    M_impl,M_immnn,M_impl,M_immnn,M_Innnn,M_nnnn,M_nnnn,M_nnnn,
    M_rr,M_InnY,M_impl,M_InnY,M_nnX,M_nnX,M_nnX,M_nnX,
    M_impl,M_nnnnY,M_impl,M_nnnnY,M_nnnnX,M_nnnnX,M_nnnnX,M_nnnnX,
    M_immnn,M_InnX,M_immnn,M_InnX,M_nn,M_nn,M_nn,M_nn,
    M_impl,M_immnn,M_impl,M_immnn,M_nnnn,M_nnnn,M_nnnn,M_nnnn,
    M_rr,M_InnY,M_impl,M_InnY,M_nnX,M_nnX,M_nnY,M_nnY,
    M_impl,M_nnnnY,M_impl,M_nnnnY,M_nnnnX,M_nnnnX,M_nnnnY,M_nnnnY,
    M_immnn,M_InnX,M_immnn,M_InnX,M_nn,M_nn,M_nn,M_nn,
    M_impl,M_immnn,M_impl,M_immnn,M_nnnn,M_nnnn,M_nnnn,M_nnnn,
    M_rr,M_InnY,M_impl,M_InnY,M_nnX,M_nnX,M_nnY,M_nnY,
    M_impl,M_nnnnY,M_impl,M_nnnnY,M_nnnnX,M_nnnnX,M_nnnnY,M_nnnnY,
    M_immnn,M_InnX,M_immnn,M_InnX,M_nn,M_nn,M_nn,M_nn,
    M_impl,M_immnn,M_impl,M_immnn,M_nnnn,M_nnnn,M_nnnn,M_nnnn,
    M_rr,M_InnY,M_impl,M_InnY,M_nnX,M_nnX,M_nnX,M_nnX,
    M_impl,M_nnnnY,M_impl,M_nnnnY,M_nnnnX,M_nnnnX,M_nnnnX,M_nnnnX,
    M_immnn,M_InnX,M_immnn,M_InnX,M_nn,M_nn,M_nn,M_nn,
    M_impl,M_immnn,M_impl,M_immnn,M_nnnn,M_nnnn,M_nnnn,M_nnnn,
    M_rr,M_InnY,M_impl,M_InnY,M_nnX,M_nnX,M_nnX,M_nnX,
    M_impl,M_nnnnY,M_impl,M_nnnnY,M_nnnnX,M_nnnnX,M_nnnnX,M_nnnnX);


  signal reg_addressingmode : addressingmode;
  signal reg_instruction : instruction;

  signal is_rmw : std_logic;
  signal is_load : std_logic;
  signal is_store : std_logic;
  signal rmw_dummy_write_done : std_logic;
  
  signal a_incremented : unsigned(7 downto 0);
  signal a_decremented : unsigned(7 downto 0);
  signal a_negated : unsigned(7 downto 0);
  signal a_ror : unsigned(7 downto 0);
  signal a_rol : unsigned(7 downto 0);
  signal a_asl : unsigned(7 downto 0);
  signal a_asr : unsigned(7 downto 0);
  signal a_lsr : unsigned(7 downto 0);
  signal a_ior : unsigned(7 downto 0);
  signal a_xor : unsigned(7 downto 0);
  signal a_and : unsigned(7 downto 0);
  signal a_neg : unsigned(7 downto 0);

  signal a_neg_z : std_logic;
  signal a_add : unsigned(11 downto 0); -- has NVZC flags and result
  signal a_sub : unsigned(11 downto 0); -- has NVZC flags and result
  
  signal x_incremented : unsigned(7 downto 0);
  signal x_decremented : unsigned(7 downto 0);
  signal y_incremented : unsigned(7 downto 0);
  signal y_decremented : unsigned(7 downto 0);
  signal z_incremented : unsigned(7 downto 0);
  signal z_decremented : unsigned(7 downto 0);

  signal monitor_mem_attention_request_drive : std_logic;
  signal monitor_mem_read_drive : std_logic;
  signal monitor_mem_write_drive : std_logic;
  signal monitor_mem_setpc_drive : std_logic;
  signal monitor_mem_address_drive : unsigned(27 downto 0);
  signal monitor_mem_wdata_drive : unsigned(7 downto 0);

  signal debugging_single_stepping : std_logic := '0';
  signal debug_count : integer range 0 to 5 := 0;

  signal rmb_mask : unsigned(7 downto 0);
  signal smb_mask : unsigned(7 downto 0);

  signal ddr_ram_banking : std_logic := '0';
  signal ddr_ram_bank : std_logic_vector(2 downto 0);
  signal ddr_reply_counter : unsigned(7 downto 0) := x"00";
  signal ddr_timeout_counter : unsigned(7 downto 0) := x"00";
  signal ddr_cache_load_counter : unsigned(7 downto 0) := x"00";
  signal ddr_write_ready_counter : unsigned(7 downto 0) := x"00";
  signal ddr_got_reply : std_logic := '0';

  signal slowram_addr_drive : std_logic_vector(26 downto 0);
  signal slowram_addr_reflect_drive : std_logic_vector(26 downto 0);
  signal slowram_data_in : std_logic_vector(7 downto 0);
  signal slowram_datain_expected : std_logic_vector(7 downto 0);
  signal slowram_datain_reflect_drive : std_logic_vector(7 downto 0);
  signal slowram_we_drive : std_logic;

  signal watchdog_reset : std_logic := '0';
  signal watchdog_fed : std_logic := '0';
  signal watchdog_countdown : integer range 0 to 65535;

  signal emu6502 : std_logic := '0';
  signal force_4502 : std_logic := '1';

  signal monitor_char_toggle_internal : std_logic := '0';

  type microcode_lut_t is array (instruction)
    of microcodeops;
  signal microcode_lut : microcode_lut_t := (
    I_ADC => (mcADC => '1', mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    I_AND => (mcAND => '1', mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    I_ASL => (mcASL => '1', mcDelayedWrite => '1', others => '0'),
    I_ASR => (mcASR => '1', mcDelayedWrite => '1', others => '0'),
    I_ASW => (mcWordOp => '1', others => '0'),
    -- I_BBR - handled elsewhere
    -- I_BBS - handled elsewhere
    -- I_BCC - handled elsewhere
    -- I_BCS - handled elsewhere
    -- I_BEQ - handled elsewhere
    I_BIT => (mcBIT => '1', mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    -- I_BMI - handled elsewhere
    -- I_BNE - handled elsewhere
    -- I_BPL - handled elsewhere
    -- I_BRA - handled elsewhere
    I_BRK => (mcBRK => '1', others => '0'),
    -- I_BSR - handled elsewhere
    -- I_BVC - handled elsewhere
    -- I_BVS - handled elsewhere
    -- I_CLC - Handled as a single-cycle op elsewhere
    -- I_CLD - handled as a single-cycle op elsewhere
    I_CLE => (mcClearE => '1', mcDecPC => '1', others => '0'),
    I_CLI => (mcClearI => '1', mcDecPC => '1', others => '0'),
    -- I_CLV - handled as a single-cycle op elsewhere
    I_CMP => (mcCMP => '1', mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    I_CPX => (mcCPX => '1', mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    I_CPY => (mcCPY => '1', mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    I_CPZ => (mcCPZ => '1', mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    I_DEC => (mcDEC => '1', mcDelayedWrite => '1', others => '0'),
    I_DEW => (mcWordOp => '1', others => '0'),
    -- I_EOM - handled as a single-cycle op elsewhere
    I_EOR => (mcEOR => '1', mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    I_INC => (mcINC => '1', mcDelayedWrite => '1', others => '0'),
    I_INW => (mcWordOp => '1', others => '0'),
    -- I_INX - handled as a single-cycle op elsewhere
    -- I_INY - handled as a single-cycle op elsewhere
    -- I_INZ - handled as a single-cycle op elsewhere
    I_JMP => (mcJump => '1', others => '0'),
    I_JSR => (mcJump => '1', others => '0'),
    I_LDA => (mcSetA => '1', mcSetNZ => '1', mcIncPC => '1', 
              mcInstructionFetch => '1', others => '0'),
    I_LDX => (mcSetX => '1', mcSetNZ => '1', mcIncPC => '1', 
              mcInstructionFetch => '1', others => '0'),
    I_LDY => (mcSetY => '1', mcSetNZ => '1', mcIncPC => '1', 
              mcInstructionFetch => '1', others => '0'),
    I_LDZ => (mcSetZ => '1', mcSetNZ => '1', mcIncPC => '1', 
              mcInstructionFetch => '1', others => '0'),
    I_LSR => (mcLSR => '1', mcDelayedWrite => '1', others => '0'),
    I_MAP => (mcMap => '1', mcDecPC => '1', others => '0'),
    -- I_NEG - handled as a single-cycle op elsewhere
    I_ORA => (mcORA => '1', mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    I_PHA => (mcStoreA => '1', mcDecPC => '1', others => '0'),
    I_PHP => (mcStoreP => '1', mcDecPC => '1', others => '0'),
    I_PHW => (mcWordOp => '1', others => '0'),
    I_PHX => (mcStoreX => '1', mcDecPC => '1', others => '0'),
    I_PHY => (mcStoreY => '1', mcDecPC => '1', others => '0'),
    I_PHZ => (mcStoreZ => '1', mcDecPC => '1', others => '0'),
    I_PLA => (mcPop => '1', mcStackA => '1', mcDecPC => '1', others => '0'),
    I_PLP => (mcPop => '1', mcStackP => '1', mcDecPC => '1', others => '0'),
    I_PLX => (mcPop => '1', mcStackX => '1', mcDecPC => '1', others => '0'),
    I_PLY => (mcPop => '1', mcStackY => '1', mcDecPC => '1', others => '0'),
    I_PLZ => (mcPop => '1', mcStackZ => '1', mcDecPC => '1', others => '0'),
    I_RMB => (mcRMB => '1', mcDelayedWrite => '1', others => '0'),
    I_ROL => (mcROL => '1', mcDelayedWrite => '1', others => '0'),
    I_ROR => (mcROR => '1', mcDelayedWrite => '1', others => '0'),
    I_ROW => (mcWordOp => '1', others => '0'),
    -- I_RTI - handled directly in gs4510.vhdl
    -- I_RTS - handled directly in gs4510.vhdl
    I_SBC => (mcSBC => '1', mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    -- I_SEC - handled as a single-cycle op elsewhere   
    -- I_SED - handled as a single-cycle op elsewhere   
    -- I_SEE - handled as a single-cycle op elsewhere   
    -- I_SEI - handled as a single-cycle op elsewhere   
    I_SMB => (mcSMB => '1', mcDelayedWrite => '1', others => '0'),
    I_STA => (mcStoreA => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    I_STX => (mcStoreX => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    I_STY => (mcStoreY => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    I_STZ => (mcStoreZ => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    -- I_TAX - handled as a single-cycle op elsewhere   
    -- I_TAY - handled as a single-cycle op elsewhere   
    -- I_TAZ - handled as a single-cycle op elsewhere   
    -- I_TBA - handled as a single-cycle op elsewhere   
    I_TRB => (mcStoreTRB => '1', mcDelayedWrite => '1', mcTestAZ => '1', 
              others => '0'),
    I_TSB => (mcStoreTSB => '1', mcDelayedWrite => '1', mcTestAZ => '1', 
              others => '0'),
    -- I_TSX - handled as a single-cycle op elsewhere   
    -- I_TSY - handled as a single-cycle op elsewhere   
    -- I_TXA - handled as a single-cycle op elsewhere   
    -- I_TXS - handled as a single-cycle op elsewhere   
    -- I_TYA - handled as a single-cycle op elsewhere   
    -- I_TYS - handled as a single-cycle op elsewhere   
    -- I_TZA - handled as a single-cycle op elsewhere   

    -- 6502 illegals
    -- XXX - incomplete: these have only the microcode for the "dominant" action
    -- for the most part so far.
    -- Shift left, then OR accumulator with result of operation
    I_SLO => (mcASL => '1', mcORA => '1',
              mcDelayedWrite => '1', others => '0'),
    -- Rotate left, then AND accumulator with result of operation
    I_RLA => (mcROL => '1', mcAND => '1',
              mcDelayedWrite => '1', others => '0'),
    -- LSR, then EOR accumulator with result of operation
    I_SRE => (mcLSR => '1', mcEOR => '1',
              mcDelayedWrite => '1', others => '0'),
    -- Rotate right, then ADC accumulator with result of operation
    I_RRA => (mcROR => '1', mcADC => '1',
              mcDelayedWrite => '1', others => '0'),
    -- Store AND of A and X: Doesn't touch any flags
    I_SAX => (mcStoreA => '1', mcStoreX => '1',
              mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    -- Load A and X at the same time, one of the more useful results
    I_LAX => (mcSetX => '1', mcSetA => '1',
              mcSetNZ => '1', mcIncPC => '1', 
              mcInstructionFetch => '1', others => '0'),
    -- Decrement, and then compare with accumulator
    I_DCP => (mcDEC => '1', mcCMP => '1',
              mcDelayedWrite => '1', others => '0'),
    -- INC, then subtract result from accumulator
    I_ISC => (mcINC => '1', mcSBC => '1',
              mcDelayedWrite => '1', others => '0'),
    -- Like AND, but pushes bit7 into C.  Here we can simply enable both AND
    -- and ROL in the microcode, and everything will already work.
    I_ANC => (mcAND => '1', mcROL => '1',
              mcInstructionFetch => '1', mcIncPC => '1',
              -- XXX push bit7 to carry
              others => '0'),
    I_ALR => (mcAND => '1', mcLSR => '1',
              mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    I_ARR => (mcROR => '1', mcDelayedWrite => '1', others => '0'),
    I_XAA => (mcAND => '1',
              mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
    I_AXS => (mcAND => '1', mcInstructionFetch => '1', mcIncPC => '1',
              others => '0'),
    I_AHX => (mcStoreA => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    I_SHY => (mcStoreY => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    I_SHX => (mcStoreX => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    I_TAS => (mcStoreA => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    I_LAS => (mcSetA => '1',
              mcSetNZ => '1', mcIncPC => '1', 
              mcInstructionFetch => '1', others => '0'),
    I_NOP => ( others=>'0'),
    -- I_KIL - XXX needs to be handled as Hypervisor trap elsewhere
    
    others => ( mcInstructionFetch => '1', others => '0'));


begin

  shadowram0 : shadowram port map (
    clk     => clock,
    address => shadow_address,
    we      => shadow_write,
    data_i  => shadow_wdata,
    data_o  => shadow_rdata,
    no_writes => shadow_no_write_count,
    writes => shadow_write_count);

  romram0 : shadowram port map (
    clk     => clock,
    address => rom_address,
    we      => rom_write,
    data_i  => rom_wdata,
    data_o  => rom_rdata,
    no_writes => rom_no_write_count,
    writes => rom_write_count);
  
  process(clock,reset,reg_a,reg_x,reg_y,reg_z,flag_c)
    procedure disassemble_last_instruction is
      variable justification : side := RIGHT;
      variable size : width := 0;
      variable s : string(1 to 110) := (others => ' ');
      variable t : string(1 to 100) := (others => ' ');
      variable virtual_reg_p : std_logic_vector(7 downto 0);
    begin
--pragma synthesis_off      
      if last_bytecount > 0 then
        -- Program counter
        s(1) := '$';
        s(2 to 5) := to_hstring(last_instruction_pc)(1 to 4);
        -- opcode and arguments
        s(7 to 8) := to_hstring(last_opcode)(1 to 2);
        if last_bytecount > 1 then
          s(10 to 11) := to_hstring(last_byte2)(1 to 2);
        end if;
        if last_bytecount > 2 then
          s(13 to 14) := to_hstring(last_byte3)(1 to 2);
        end if;
        -- instruction name
        t(1 to 5) := instruction'image(instruction_lut(to_integer(last_opcode)));       
        s(17 to 19) := t(3 to 5);

        -- Draw 0-7 digit on BBS/BBR instructions
        case instruction_lut(to_integer(emu6502&last_opcode)) is
          when I_BBS =>
            s(20 to 20) := to_hstring("0"&last_opcode(6 downto 4))(1 to 1);
          when I_BBR =>
            s(20 to 20) := to_hstring("0"&last_opcode(6 downto 4))(1 to 1);
          when others =>
            null;
        end case;

        -- Draw arguments
        case mode_lut(to_integer(emu6502&last_opcode)) is
          when M_impl => null;
          when M_InnX =>
            s(22 to 23) := "($";
            s(24 to 25) := to_hstring(last_byte2)(1 to 2);
            s(26 to 28) := ",X)";
          when M_nn =>
            s(22) := '$';
            s(23 to 24) := to_hstring(last_byte2)(1 to 2);
          when M_immnn =>
            s(22 to 23) := "#$";
            s(24 to 25) := to_hstring(last_byte2)(1 to 2);
          when M_A => null;
          when M_nnnn =>
            s(22) := '$';
            s(23 to 26) := to_hstring(last_byte3 & last_byte2)(1 to 4);
          when M_nnrr =>
            s(22) := '$';
            s(23 to 24) := to_hstring(last_byte2)(1 to 2);
            s(25 to 26) := ",$";
            s(27 to 30) := to_hstring(last_instruction_pc + 3 + last_byte3)(1 to 4);
          when M_rr =>
            s(22) := '$';
            if last_byte2(7)='0' then
              s(23 to 26) := to_hstring(last_instruction_pc + 2 + last_byte2)(1 to 4);
            else
              s(23 to 26) := to_hstring(last_instruction_pc + 2 - 256 + last_byte2)(1 to 4);
            end if;
          when M_InnY =>
            s(22 to 23) := "($";
            s(24 to 25) := to_hstring(last_byte2)(1 to 2);
            s(26 to 28) := "),Y";
          when M_InnZ =>
            s(22 to 23) := "($";
            s(24 to 25) := to_hstring(last_byte2)(1 to 2);
            s(26 to 28) := "),Z";
          when M_rrrr =>
            s(22) := '$';            
            s(23 to 26) := to_hstring(last_instruction_pc + 2 + (last_byte3 & last_byte2))(1 to 4);
          when M_nnX =>
            s(22) := '$';
            s(23 to 24) := to_hstring(last_byte2)(1 to 2);
            s(25 to 26) := ",X";
          when M_nnnnY =>
            s(22) := '$';
            s(23 to 26) := to_hstring(last_byte3 & last_byte2)(1 to 4);
            s(27 to 28) := ",Y";
          when M_nnnnX =>
            s(22) := '$';
            s(23 to 26) := to_hstring(last_byte3 & last_byte2)(1 to 4);
            s(27 to 28) := ",X";
          when M_Innnn =>
            s(22 to 23) := "($";
            s(24 to 27) := to_hstring(last_byte3 & last_byte2)(1 to 4);
            s(28) := ')';
          when M_InnnnX =>
            s(22 to 23) := "($";
            s(24 to 27) := to_hstring(last_byte3 & last_byte2)(1 to 4);
            s(28 to 30) := ",X)";
          when M_InnSPY =>
            s(22 to 23) := "($";
            s(24 to 25) := to_hstring(last_byte2)(1 to 2);
            s(26 to 31) := ",SP),Y";
          when M_nnY =>
            s(22) := '$';
            s(23 to 24) := to_hstring(last_byte2)(1 to 2);
            s(25 to 26) := ",Y";
          when M_immnnnn =>
            s(22 to 23) := "#$";
            s(24 to 27) := to_hstring(last_byte3 & last_byte2)(1 to 4);
        end case;

        -- Show registers
        s(36 to 96) := "A:xx X:xx Y:xx Z:xx SP:xxxx P:xx $01=xx MAPLO:xxxx MAPHI:xxxx";
        s(38 to 39) := to_hstring(reg_a);
        s(43 to 44) := to_hstring(reg_x);
        s(48 to 49) := to_hstring(reg_y);
        s(53 to 54) := to_hstring(reg_z);
        s(59 to 62) := to_hstring(reg_sph&reg_sp);
        virtual_reg_p(7) := flag_n;
        virtual_reg_p(6) := flag_v;
        virtual_reg_p(5) := flag_e;
        virtual_reg_p(4) := '0';
        virtual_reg_p(3) := flag_d;
        virtual_reg_p(2) := flag_i;
        virtual_reg_p(1) := flag_z;
        virtual_reg_p(0) := flag_c;
        s(66 to 67) := to_hstring(virtual_reg_p);
        s(73 to 74) := to_hstring(cpuport_value or (not cpuport_ddr));
        s(82 to 85) := to_hstring(unsigned(reg_map_low)&reg_offset_low);
        s(93 to 96) := to_hstring(unsigned(reg_map_high)&reg_offset_high);

        s(100 to 107) := "........";
        if flag_n='1' then s(100) := 'N'; end if;
        if flag_v='1' then s(101) := 'V'; end if;
        if flag_e='1' then s(102) := 'E'; end if;
        s(103) := '-';
        if flag_d='1' then s(104) := 'D'; end if;
        if flag_i='1' then s(105) := 'I'; end if;
        if flag_z='1' then s(106) := 'Z'; end if;
        if flag_c='1' then s(107) := 'C'; end if;
        
        -- Display disassembly
        report s severity note;
      end if;
--pragma synthesis_on
    end procedure;

    procedure reset_cpu_state is
    begin
      -- Set microcode state for reset

      -- CPU starts in hypervisor
      hypervisor_mode <= '1';
      
      instruction_phase <= x"0";
      
      -- Default register values
      reg_b <= x"00";
      reg_a <= x"11";    
      reg_x <= x"22";
      reg_y <= x"33";
      reg_z <= x"00";
      reg_sp <= x"ff";
      reg_sph <= x"01";
      -- Reset entry point is now $8100 instead of $8000,
      -- because $8000-$80FF in hypervisor space is reserved
      -- for 64 x 4 byte entry points for hypervisor traps
      -- from writing to $FFD3640-$FFD367F
      hypervisor_trap_port <= "1000000";
      report "Setting PC to $8100 on reset";
      reg_pc <= x"8100";

      -- Clear CPU MMU registers, and bank in kickstart ROM
      -- XXX Need to update this for hypervisor mode
      if no_kickstart='1' then
        -- no kickstart
        reg_offset_high <= x"000";
        reg_map_high <= "0000";
        reg_offset_low <= x"000";
        reg_map_low <= "0000";
        reg_mb_high <= x"00";
        reg_mb_low <= x"00";
      else
        -- with kickstart
        reg_offset_high <= x"F00";
        reg_map_high <= "1000";
        reg_offset_low <= x"000";
        reg_map_low <= "0100";
        reg_mb_high <= x"FF";
        reg_mb_low <= x"80";
      end if;
      
      -- Map shadow RAM to unmapped address space at $C0000 (768KB)
      -- (as well as always-on shadowing of $00000-$1FFFF)
      shadow_bank <= x"0C";
      
      -- Default CPU flags
      flag_c <= '0';
      flag_d <= '0';
      flag_i <= '1';                -- start with IRQ disabled
      flag_z <= '0';
      flag_n <= '0';
      flag_v <= '0';
      flag_e <= '1';

      cpuport_ddr <= x"FF";
      cpuport_value <= x"3F";
      force_fast <= '0';

      -- Stop memory accesses
      colour_ram_cs <= '0';
      shadow_write <= '0';
      shadow_write_flags(0) <= '1';
      fastio_read <= '0';
      fastio_write <= '0';
      chipram_we <= '0';        
      chipram_datain <= x"c0";    
      slowram_we_drive <= '0';

      ddr_ram_banking <= '0';
      ddr_ram_bank <= "000";

      slowram_request_toggle_drive <= slowram_done_toggle;
      slowram_desired_done_toggle <= slowram_done_toggle;
      
      wait_states <= (others => '0');
      wait_states_non_zero <= '0';
      mem_reading <= '0';
      
    end procedure reset_cpu_state;

    procedure check_for_interrupts is
    begin
      -- No interrupts of any sort between MAP and EOM instructions.
      if map_interrupt_inhibit='0' then
        -- NMI is edge triggered.
        if nmi = '0' and nmi_state = '1' then
          nmi_pending <= '1';        
        end if;
        nmi_state <= nmi;
        -- IRQ is level triggered.
        if (irq = '0') and (flag_i='0') then
          irq_pending <= '1';
        else
          irq_pending <= '0';
        end if;
      else
        irq_pending <= '0';
      end if;     
    end procedure check_for_interrupts;

    -- purpose: Convert a 16-bit C64 address to native RAM (or I/O or ROM) address
    impure function resolve_address_to_long(short_address : unsigned(15 downto 0);
                                            writeP : boolean)
      return unsigned is 
      variable temp_address : unsigned(27 downto 0);
      variable blocknum : integer;
      variable lhc : std_logic_vector(2 downto 0);
    begin  -- resolve_long_address

      -- Now apply C64-style $01 lines first, because MAP and $D030 take precedence
      blocknum := to_integer(short_address(15 downto 12));

      lhc := std_logic_vector(cpuport_value(2 downto 0));
      lhc(2) := lhc(2) or (not cpuport_ddr(2));
      lhc(1) := lhc(1) or (not cpuport_ddr(1));
      lhc(0) := lhc(0) or (not cpuport_ddr(0));
      
      -- Examination of the C65 interface ROM reveals that MAP instruction
      -- takes precedence over $01 CPU port when MAP bit is set for a block of RAM.

      -- From https://groups.google.com/forum/#!topic/comp.sys.cbm/C9uWjgleTgc
      -- Port pin (bit)    $A000 to $BFFF       $D000 to $DFFF       $E000 to $FFFF
      -- 2 1 0             Read       Write     Read       Write     Read       Write
      -- --------------    ----------------     ----------------     ----------------
      -- 0 0 0             RAM        RAM       RAM        RAM       RAM        RAM
      -- 0 0 1             RAM        RAM       CHAR-ROM   RAM       RAM        RAM
      -- 0 1 0             RAM        RAM       CHAR-ROM   RAM       KERNAL-ROM RAM
      -- 0 1 1             BASIC-ROM  RAM       CHAR-ROM   RAM       KERNAL-ROM RAM
      -- 1 0 0             RAM        RAM       RAM        RAM       RAM        RAM
      -- 1 0 1             RAM        RAM       I/O        I/O       RAM        RAM
      -- 1 1 0             RAM        RAM       I/O        I/O       KERNAL-ROM RAM
      -- 1 1 1             BASIC-ROM  RAM       I/O        I/O       KERNAL-ROM RAM
      
      -- default is address in = address out
      temp_address(27 downto 16) := (others => '0');
      temp_address(15 downto 0) := short_address;

      -- IO
      if (blocknum=13) then
        temp_address(11 downto 0) := short_address(11 downto 0);
        if writeP then
          case lhc(2 downto 0) is
            when "000" => temp_address(27 downto 12) := x"000D";  -- WRITE RAM
            when "001" => temp_address(27 downto 12) := x"000D";  -- WRITE RAM
            when "010" => temp_address(27 downto 12) := x"000D";  -- WRITE RAM
            when "011" => temp_address(27 downto 12) := x"000D";  -- WRITE RAM
            when "100" => temp_address(27 downto 12) := x"000D";  -- WRITE RAM
            when others =>
              -- All else accesses IO
              -- C64/C65/C65GS I/O is based on which secret knock has been applied
              -- to $D02F
              temp_address(27 downto 12) := x"FFD3";
              temp_address(13 downto 12) := unsigned(viciii_iomode);          
          end case;        
        else
          -- READING
          case lhc(2 downto 0) is
            when "000" => temp_address(27 downto 12) := x"000D";  -- READ RAM
            when "001" => temp_address(27 downto 12) := x"002D";  -- CHARROM
                          if rom_from_colour_ram='1' then temp_address(27 downto 16) := x"001"; end if;
            when "010" => temp_address(27 downto 12) := x"002D";  -- CHARROM
                          if rom_from_colour_ram='1' then temp_address(27 downto 16) := x"001"; end if;       
            when "011" => temp_address(27 downto 12) := x"002D";  -- CHARROM
                          if rom_from_colour_ram='1' then temp_address(27 downto 16) := x"001"; end if;       
            when "100" => temp_address(27 downto 12) := x"000D";  -- READ RAM
            when others =>
              -- All else accesses IO
              -- C64/C65/C65GS I/O is based on which secret knock has been applied
              -- to $D02F
              temp_address(27 downto 12) := x"FFD3";
              temp_address(13 downto 12) := unsigned(viciii_iomode);          
          end case;              end if;
      end if;

      -- C64 KERNEL
      if reg_map_high(3)='0' then
        if (blocknum=14) and (lhc(1)='1') and (writeP=false) then
          temp_address(27 downto 12) := x"002E";      
          if rom_from_colour_ram='1' then
            temp_address(27 downto 12) := x"0018";
          end if;
        end if;
        if (blocknum=15) and (lhc(1)='1') and (writeP=false) then
          temp_address(27 downto 12) := x"002F";      
          if rom_from_colour_ram='1' then
            temp_address(27 downto 12) := x"0019";
          end if;
        end if;
      end if;
      -- C64 BASIC
      if reg_map_high(1)='0' then
        if (blocknum=10) and (lhc(0)='1') and (lhc(1)='1') and (writeP=false) then
          temp_address(27 downto 12) := x"002A";
          if rom_from_colour_ram='1' then
            temp_address(27 downto 12) := x"001A";
          end if;
        end if;
        if (blocknum=11) and (lhc(0)='1') and (lhc(1)='1') and (writeP=false) then
          temp_address(27 downto 12) := x"002B";      
          if rom_from_colour_ram='1' then
            temp_address(27 downto 12) := x"001B";
          end if;
        end if;
      end if;

      -- Lower 8 address bits are never changed
      temp_address(7 downto 0):=short_address(7 downto 0);

      -- Add the map offset if required
      blocknum := to_integer(short_address(14 downto 13));
      if short_address(15)='1' then
        if reg_map_high(blocknum)='1' then
          temp_address(27 downto 20) := reg_mb_high;
          temp_address(19 downto 8) := reg_offset_high+to_integer(short_address(15 downto 8));
          temp_address(7 downto 0) := short_address(7 downto 0);       
        end if;
      else
        if reg_map_low(blocknum)='1' then
          temp_address(27 downto 20) := reg_mb_low;
          temp_address(19 downto 8) := reg_offset_low+to_integer(short_address(15 downto 8));
          temp_address(7 downto 0) := short_address(7 downto 0);
          report "mapped memory address is $" & to_hstring(temp_address) severity note;
        end if;
      end if;
      
      -- $D030 ROM select lines:
      blocknum := to_integer(short_address(15 downto 12));
      if (blocknum=14 or blocknum=15) and rom_at_e000='1' then
        temp_address(27 downto 12) := x"003E";
        if blocknum=15 then temp_address(12):='1'; end if;
      end if;
      if (blocknum=12) and rom_at_c000='1' then
        temp_address(27 downto 12) := x"002C";
        if rom_from_colour_ram='1' then temp_address(27 downto 16) := x"FF8"; end if;
      end if;
      if (blocknum=10 or blocknum=11) and rom_at_a000='1' then
        temp_address(27 downto 12) := x"003A";
        if blocknum=11 then temp_address(12):='1'; end if;
      end if;
      if (blocknum=9) and rom_at_8000='1' then
        temp_address(27 downto 12) := x"0039";
      end if;
      if (blocknum=8) and rom_at_8000='1' then
        temp_address(27 downto 12) := x"0038";
      end if;
            
      return temp_address;
    end resolve_address_to_long;

    procedure read_long_address(
      real_long_address : in unsigned(27 downto 0)) is
      variable long_address : unsigned(27 downto 0);
    begin

      last_action <= 'R'; last_address <= real_long_address;
      
      -- Stop writing when reading.     
      fastio_write <= '0'; shadow_write <= '0';

      -- Remap GeoRAM memory accesses
      if real_long_address(27 downto 16) = x"FFD"
        and real_long_address(11 downto 8) = x"E" then
        long_address := georam_page&real_long_address(7 downto 0);
      end if;
      
      if real_long_address(27 downto 12) = x"001F" and real_long_address(11)='1' then
        -- colour ram access: remap to $FF80000 - $FF807FF
        long_address := x"FF80"&'0'&real_long_address(10 downto 0);
      else
        long_address := real_long_address;
      end if;

      report "Reading from long address $" & to_hstring(long_address) severity note;
      mem_reading <= '1';
      
      -- Schedule the memory read from the appropriate source.
      accessing_fastio <= '0'; accessing_vic_fastio <= '0';
      accessing_cpuport <= '0'; accessing_colour_ram_fastio <= '0';
      accessing_slowram <= '0'; accessing_hypervisor <= '0';
      slowram_pending_write <= '0';
      slowram_we_drive <= '0';
      charrom_write_cs <= '0';

      wait_states <= io_read_wait_states;
      if io_read_wait_states /= x"00" then
        wait_states_non_zero <= '1';
      else
        wait_states_non_zero <= '0';
      end if; 
        
      ddr_got_reply <= '0';

      -- Clear fastio access so that we don't keep reading/writing last IO address
      -- (this is bad when it is $DC0D for example, as it will stop IRQs from
      -- the CIA).
      fastio_addr <= x"FFFFF"; fastio_write <= '0'; fastio_read <= '0';
      
      the_read_address <= long_address;
      if (long_address(27 downto 8) = x"FFD17") or (long_address(27 downto 8) = x"FFD37") then
        read_source <= DMAgicRegister;
      end if;      

      -- Get the shadow RAM or ROM address on the bus fast to improve timing.
      shadow_write <= '0';
      shadow_write_flags(1) <= '1';
      shadow_address <= to_integer(long_address(16 downto 0));
      rom_address <= to_integer(long_address(16 downto 0));
      rom_write <= '0';

      report "MEMORY long_address = $" & to_hstring(long_address);
      -- @IO:C64 $0000000 6510/45GS10 CPU port DDR
      -- @IO:C64 $0000001 6510/45GS10 CPU port data
      if long_address(27 downto 6)&"00" = x"FFD364" and hypervisor_mode='1' then
        read_source <= HypervisorRegister;
        accessing_hypervisor <= '1';
        -- One cycle wait-state on hypervisor registers to remove the register
        -- decode from the critical path of memory access.
        wait_states <= x"01";
        wait_states_non_zero <= '1';
        proceed <= '0';
        hyperport_num <= real_long_address(5 downto 0);
      end if;
      if (long_address = x"0000000") or (long_address = x"0000001") then
        accessing_cpuport <= '1';
        read_source <= CPUPort;
        -- One cycle wait-state on hypervisor registers to remove the register
        -- decode from the critical path of memory access.
        wait_states <= x"01";
        wait_states_non_zero <= '1';
        proceed <= '0';
        cpuport_num <= real_long_address(3 downto 0);
      elsif long_address(27 downto 4) = x"400000" then
        -- More CPU ports for debugging.
        -- (this was added to debug CIA IRQ bugs where reading/writing from
        -- fastio space would prevent the bug from manifesting)
        read_source <= CPUPort;
        accessing_cpuport <= '1';
        -- One cycle wait-state on hypervisor registers to remove the register
        -- decode from the critical path of memory access.
        wait_states <= x"01";
        wait_states_non_zero <= '1';
        proceed <= '0';
        cpuport_num <= real_long_address(3 downto 0);
      elsif long_address(27 downto 16)="0000"&shadow_bank then
        -- Reading from 256KB shadow ram (which includes 128KB fixed shadowing of
        -- chipram).  This is the only memory running at the CPU's native clock.
        -- Think of it as a kind of direct-mapped L1 cache.
        read_source <= Shadow;
        accessing_shadow <= '1';
        wait_states <= shadow_wait_states;
        if shadow_wait_states=x"00" then
          wait_states_non_zero <= '0';
          proceed <= '1';
        else
          wait_states_non_zero <= '1';
          proceed <= '0';
        end if;
        report "Reading from shadow ram address $" & to_hstring(long_address(17 downto 0))
          & ", word $" & to_hstring(long_address(18 downto 3)) severity note;
      elsif long_address(27 downto 17)="00000000000" then
        -- Reading from chipram, so read from the bottom 128KB of the shadow RAM
        -- instead.
        read_source <= Shadow;
        accessing_shadow <= '1';
        accessing_rom <= '0';
        wait_states <= shadow_wait_states;
        if shadow_wait_states=x"00" then
          wait_states_non_zero <= '0';
          proceed <= '1';
        else
          wait_states_non_zero <= '1';
          proceed <= '0';
        end if;
        report "Reading from shadowed chipram address $"
          & to_hstring(long_address(19 downto 0)) severity note;
      elsif long_address(27 downto 17)="00000000001" then
        -- Reading from 128KB ROM
        read_source <= ROMRAM;
        accessing_shadow <= '0';
        accessing_rom <= '1';
        wait_states <= shadow_wait_states;
        if shadow_wait_states=x"00" then
          wait_states_non_zero <= '0';
          proceed <= '1';
        else
          wait_states_non_zero <= '1';
          proceed <= '0';
        end if;
        report "Reading from ROM address $"
          & to_hstring(long_address(19 downto 0)) severity note;
      elsif long_address(27 downto 20) = x"FF" then
        read_source <= FastIO;
        accessing_shadow <= '0';
        accessing_rom <= '0';
        accessing_fastio <= '1';
        accessing_vic_fastio <= '0';
        accessing_colour_ram_fastio <= '0';
        -- XXX Some fastio (that referencing ioclocked registers) does require
        -- io_wait_states, while some can use fewer waitstates because the
        -- memories involved can be clocked at the CPU clock, and have just 1
        -- wait state due to the dual-port memories.
        -- But for now, just apply the wait state to all fastio addresses.
        wait_states <= io_read_wait_states;
        if io_read_wait_states /= x"00" then
          wait_states_non_zero <= '1';
        else
          wait_states_non_zero <= '0';
        end if;
        
        -- If reading IO page from $D{0,1,2,3}0{0-7}X, then the access is from
        -- the VIC-IV.
        -- If reading IO page from $D{0,1,2,3}{1,2,3}XX, then the access is from
        -- the VIC-IV.
        -- If reading IO page from $D{0,1,2,3}{8,9,a,b}XX, then the access is from
        -- the VIC-IV.
        -- If reading IO page from $D{0,1,2,3}{c,d,e,f}XX, and colourram_at_dc00='1',
        -- then the access is from the VIC-IV.
        -- If reading IO page from $8XXXX, then the access is from the VIC-IV.
        -- We make the distinction to separate reading of VIC-IV
        -- registers from all other IO registers, partly to work around some bugs,
        -- and partly because the banking of the VIC registers is the fiddliest part.

        if long_address(19 downto 16) = x"8" then
          report "VIC 64KB colour RAM access from VIC fastio" severity note;
          accessing_colour_ram_fastio <= '1';
          read_source <= ColourRAM;
          colour_ram_cs <= '1';
          wait_states <= colourram_read_wait_states;
          if colourram_read_wait_states /= x"00" then
            wait_states_non_zero <= '1';
          else
            wait_states_non_zero <= '0';
          end if;
        end if;
        if long_address(19 downto 16) = x"D" then
          if long_address(15 downto 14) = "00" then    --   $D{0,1,2,3}XXX
            if long_address(11 downto 10) = "00" then  --   $D{0,1,2,3}{0,1,2,3}XX
              if long_address(11 downto 7) /= "00001" then  -- ! $D.0{8-F}X (FDC, RAM EX)
                report "VIC register from VIC fastio" severity note;
                accessing_vic_fastio <= '1';
                read_source <= VICIV;
              end if;            
            end if;
            -- Colour RAM at $D800-$DBFF and optionally $DC00-$DFFF
            if long_address(11)='1' then
              if (long_address(10)='0') or (colourram_at_dc00='1') then
                report "RAM: D800-DBFF/DC00-DFFF colour ram access from VIC fastio" severity note;
                accessing_colour_ram_fastio <= '1';
                read_source <= ColourRAM;
                colour_ram_cs <= '1';
                wait_states <= colourram_read_wait_states;
                if colourram_read_wait_states /= x"00" then
                  wait_states_non_zero <= '1';
                else
                  wait_states_non_zero <= '0';
                end if;
              end if;
            end if;
          end if;                         -- $D{0,1,2,3}XXX
        end if;                           -- $DXXXX
        fastio_addr <= std_logic_vector(long_address(19 downto 0));
        last_fastio_addr <= std_logic_vector(long_address(19 downto 0));
        fastio_read <= '1';
        proceed <= '0';
      elsif long_address(27) = '1' then
        -- @IO:GS $8000000 - $FEFFFFF Slow RAM (127MB)
        -- Slow RAM maps to $8000000-$FEFFFFF, and also $0020000 - $003FFFF for
        -- C65 ROM emulation.
        read_source <= SlowRAM;
        accessing_shadow <= '0';
        accessing_rom <= '0';
        accessing_slowram <= '1';
        slowram_data_valid <= '0';
        if ddr_ram_banking='1' then
          slowram_addr_drive <= std_logic_vector(long_address(23 downto 1))&ddr_ram_bank&std_logic(long_address(0));
        else
          slowram_addr_drive <= std_logic_vector(long_address(26 downto 0));
        end if;
        slowram_we_drive <= '0';
        -- With the cache, we only request the cache be updated if we the wrong
        -- cache line is loaded.  This happen while waiting for the memory to load.
--        slowram_request_toggle <= not slowram_done_toggle;
--        slowram_desired_done_toggle <= not slowram_done_toggle;        
        wait_states <= slowram_waitstates;
        wait_states_non_zero <= '1';
        proceed <= '0';
      else
        -- Don't let unmapped memory jam things up
        report "hit unmapped memory -- clearing wait_states" severity note;
        read_source <= Unmapped;
        accessing_shadow <= '0';
        accessing_rom <= '0';
        wait_states <= shadow_wait_states;
        if shadow_wait_states /= x"00" then
          wait_states_non_zero <= '1';
        else
          wait_states_non_zero <= '0';
        end if;
        proceed <= '1';
      end if;

    end read_long_address;
    
    impure function read_data
      return unsigned is
    begin  -- read_data
      case read_source is
        when Shadow => return shadow_rdata;
        when ROMRAM => return rom_rdata;
        when others =>
          -- report "reading from somewhere other than shadowram" severity note;
          return read_data_copy;
      end case;
    end read_data;

    -- purpose: obtain the byte of memory that has been read
    impure function read_data_complex
      return unsigned is
    begin  -- read_data
      -- CPU hosted IO registers
      case read_source is
        when DMAgicRegister =>
          -- Actually, this is all of $D700-$D7FF decoded by the CPU at present
          case the_read_address(7 downto 0) is
            when x"03" => return reg_dmagic_status;
            when others => return x"ff";
          end case;
        when HypervisorRegister =>
          report "HYPERPORT: Reading hypervisor register";
          case hyperport_num is
            when "000000" => return hyper_a;
            when "000001" => return hyper_x;
            when "000010" => return hyper_y;
            when "000011" => return hyper_z;
            when "000100" => return hyper_b;
            when "000101" => return hyper_p;
            when "000110" => return hyper_sp;
            when "000111" => return hyper_sph;
            when "001000" => return hyper_pc(7 downto 0);
            when "001001" => return hyper_pc(15 downto 8);                           
            when "001010" =>
              return unsigned(std_logic_vector(hyper_map_low)
                              & std_logic_vector(hyper_map_offset_low(11 downto 8)));
            when "001011" => return hyper_map_offset_low(7 downto 0);
            when "001100" =>
              return unsigned(std_logic_vector(hyper_map_high)
                              & std_logic_vector(hyper_map_offset_high(11 downto 8)));
            when "001101" => return hyper_map_offset_high(7 downto 0);
            when "001110" => return hyper_mb_low;
            when "001111" => return hyper_mb_high;
            when "010000" => return hyper_port_00;
            when "010001" => return hyper_port_01;
            when "010010" => return hyper_iomode;
            when "010011" => return hyper_dmagic_src_mb;
            when "010100" => return hyper_dmagic_dst_mb;
            when "010101" => return hyper_dmagic_list_addr(7 downto 0);
            when "010110" => return hyper_dmagic_list_addr(15 downto 8);
            when "010111" => return hyper_dmagic_list_addr(23 downto 16);
            when "011000" =>
              return to_unsigned(0,4)&hyper_dmagic_list_addr(27 downto 24);
            when "011001" =>
              return unsigned(ddr_ram_banking&std_logic_vector(to_unsigned(0,4))
                              &ddr_ram_bank(2 downto 0));
            -- Virtual memory page registers here
            when "011101" =>
              return unsigned(std_logic_vector(reg_pagenumber(1 downto 0))
                              &"0"
                              &reg_pageactive
                              &reg_pages_dirty);
            when "011110" => return reg_pagenumber(9 downto 2);
            when "011111" => return reg_pagenumber(17 downto 10);
            when "100000" => return reg_page0_logical(7 downto 0);
            when "100001" => return reg_page0_logical(15 downto 8);
            when "100010" => return reg_page0_physical(7 downto 0);
            when "100011" => return reg_page0_physical(15 downto 8);
            when "100100" => return reg_page1_logical(7 downto 0);
            when "100101" => return reg_page1_logical(15 downto 8);
            when "100110" => return reg_page1_physical(7 downto 0);
            when "100111" => return reg_page1_physical(15 downto 8);
            when "101000" => return reg_page2_logical(7 downto 0);
            when "101001" => return reg_page2_logical(15 downto 8);
            when "101010" => return reg_page2_physical(7 downto 0);
            when "101011" => return reg_page2_physical(15 downto 8);
            when "101100" => return reg_page3_logical(7 downto 0);
            when "101101" => return reg_page3_logical(15 downto 8);
            when "101110" => return reg_page3_physical(7 downto 0);
            when "101111" => return reg_page3_physical(15 downto 8);
            when "111100" =>
              return "11" & force_4502 & force_fast
                & speed_gate_enable_internal & rom_writeprotect
                & flat32_enabled & rom_from_colour_ram;
            when "111101" =>
              return "11111" & rom_writeprotect
                & flat32_enabled & rom_from_colour_ram;
            when "111110" =>
              if hypervisor_upgraded='1' then
                return x"FF";
              else
                return x"00";
              end if;
            when "111111" => return x"48"; -- 'H' for Hypermode
            when others => return x"FF";
          end case;
        when CPUPort =>
          report "reading from CPU port" severity note;
          case cpuport_num is
            when x"0" => return cpuport_ddr;
            when x"1" => return cpuport_value;
            when x"4" => return ddr_state;
            when x"5" => return ddr_counter;
            when x"6" => return ddr_reply_counter;
            when x"7" => return ddr_timeout_counter;
            when x"8" => return ddr_cache_load_counter;
            when x"9" => return slowram_desired_done_toggle
                           &slowram_done_toggle
                           &accessing_slowram
                           &slowram_we_drive
                           &slowram_pending_write
                           &slowram_data_valid
                           &"00";
            when x"a" => return ddr_write_ready_counter;
            when x"b" => return unsigned(slowram_datain_reflect_drive);
            when x"c" => return unsigned(slowram_addr_reflect_drive(7 downto 0));
            when x"d" => return unsigned(slowram_addr_reflect_drive(15 downto 8));
            when x"e" => return unsigned(slowram_addr_reflect_drive(23 downto 16));
            when x"f" => return "00000"&unsigned(slowram_addr_reflect_drive(26 downto 24));
            when others => return x"ff";
          end case;
        when Shadow =>
          report "reading from shadow RAM" severity note;
          return shadow_rdata;
        when ROMRAM =>
          report "reading from ROM RAM" severity note;
          return rom_rdata;
        when ColourRAM =>
          report "reading colour RAM fastio byte $" & to_hstring(fastio_vic_rdata) severity note;
          return unsigned(fastio_colour_ram_rdata);
        when VICIV =>
          report "reading VIC fastio byte $" & to_hstring(fastio_vic_rdata) severity note;
          return unsigned(fastio_vic_rdata);
        when FastIO =>
          report "reading normal fastio byte $" & to_hstring(fastio_rdata) severity note;
          return unsigned(fastio_rdata);
        when SlowRAM =>
          report "reading slow RAM data. Word is $" & to_hstring(slowram_data_in) severity note;
          return unsigned(slowram_data_in);
        when Unmapped =>
          report "accessing unmapped memory" severity note;
          return x"A0";                     -- make unmmapped memory obvious
      end case;
    end read_data_complex; 

    procedure write_long_byte(
      real_long_address       : in unsigned(27 downto 0);
      value              : in unsigned(7 downto 0)) is
      variable long_address : unsigned(27 downto 0);
    begin
      -- Schedule the memory write to the appropriate destination.

      last_action <= 'W'; last_value <= value; last_address <= real_long_address;
      
      accessing_fastio <= '0'; accessing_vic_fastio <= '0';
      accessing_cpuport <= '0'; accessing_colour_ram_fastio <= '0';
      accessing_shadow <= '0';
      accessing_rom <= '0';
      accessing_slowram <= '0';
      slowram_pending_write <= '0';
      ddr_got_reply <= '0';
      charrom_write_cs <= '0';

      -- Get the shadow RAM or ROM address on the bus fast to improve timing.
      shadow_write <= '0';
      shadow_write_flags(1) <= '1';
      shadow_address <= to_integer(long_address(16 downto 0));
      rom_address <= to_integer(long_address(16 downto 0));
      rom_write <= '0';
      
      shadow_write_flags(0) <= '1';
      shadow_write_flags(1) <= '1';
      
      wait_states <= shadow_wait_states;
      if shadow_wait_states /= x"00" then
        wait_states_non_zero <= '1';
      else
        wait_states_non_zero <= '0';
      end if;

      -- Remap GeoRAM memory accesses
      if real_long_address(27 downto 16) = x"FFD"
        and real_long_address(11 downto 8)= x"E" then
        long_address := georam_page&real_long_address(7 downto 0);
      end if;

      -- Set GeoRAM page (gets munged later with GeoRAM base and mask values
      -- provided by the hypervisor)
      if real_long_address(27 downto 16) = x"ffd" then
        if real_long_address(11 downto 0) = x"fff" then
          georam_block <= value;
        elsif real_long_address(11 downto 0) = x"ffe" then
          georam_blockpage <= value;
        end if;
      end if;

      -- And REU registers
      if real_long_address(15 downto 0) = x"ff00" then
        if reu_ff00_pending = '1' then
          -- XXX Start REU job
        end if;
      end if;
      if real_long_address(27 downto 16) = x"ffd" then
        if real_long_address(11 downto 0) = x"f01" then
          reu_cmd_autoload <= value(5);
          reu_cmd_ff00decode <= value(4);
          reu_cmd_operation <= std_logic_vector(value(1 downto 0));
          if value(7)='1' and value(4)='0' then
            -- XXX Start REU job by copying REU registers to DMAgic registers,
            -- setting REU job flag and starting the job.
          elsif value(7)='1' and value(4)='1' then
            -- XXX Defer starting REU job until $FF00 is written
            reu_ff00_pending <= '1';
          end if;
        elsif real_long_address(11 downto 0) = x"f02" then
          reu_c64_startaddr(7 downto 0) <= value;
        elsif real_long_address(11 downto 0) = x"f03" then
          reu_c64_startaddr(15 downto 8) <= value;
        elsif real_long_address(11 downto 0) = x"f04" then
          reu_c64_startaddr(7 downto 0) <= value;
        elsif real_long_address(11 downto 0) = x"f05" then
          reu_reu_startaddr(15 downto 8) <= value;
        elsif real_long_address(11 downto 0) = x"f06" then
          reu_reu_startaddr(23 downto 16) <= value;
        elsif real_long_address(11 downto 0) = x"f07" then
          reu_transfer_length(7 downto 0) <= value;
        elsif real_long_address(11 downto 0) = x"f08" then
          reu_transfer_length(15 downto 8) <= value;
        elsif real_long_address(11 downto 0) = x"f09" then
          reu_useless_interrupt_mask(7 downto 5) <= value(7 downto 5);
        elsif real_long_address(11 downto 0) = x"f0a" then
          reu_hold_c64_address <= value(7);
          reu_hold_reu_address <= value(6);
        end if;        
      end if;

      
      if real_long_address(27 downto 12) = x"001F" and real_long_address(11)='1' then
        -- colour ram access: remap to $FF80000 - $FF807FF
        long_address := x"FF80"&'0'&real_long_address(10 downto 0);
      else
        long_address := real_long_address;
      end if;

      last_write_address <= real_long_address;

      -- Write to CPU port
      if (long_address = x"0000000") then
        report "MEMORY: Writing to CPU DDR register" severity note;
        if value = x"40" then
          force_fast <= '0';
        elsif value = x"41" then
          force_fast <= '1';
        else
          cpuport_ddr <= value;
        end if;
      elsif (long_address = x"0000001") then
        report "MEMORY: Writing to CPU PORT register" severity note;
        cpuport_value <= value;
      -- Write to DMAgic registers if required
      elsif (long_address = x"FFD3700") or (long_address = x"FFD1700") then        
        -- Set low order bits of DMA list address
        reg_dmagic_addr(7 downto 0) <= value;
        -- DMA gets triggered when we write here. That actually happens through
        -- memory_access_write.
      elsif (long_address = x"FFD370E") or (long_address = x"FFD170E") then
        -- Set low order bits of DMA list address, without starting
        reg_dmagic_addr(7 downto 0) <= value;
      elsif (long_address = x"FFD3701") or (long_address = x"FFD1701") then
        reg_dmagic_addr(15 downto 8) <= value;
      elsif (long_address = x"FFD3702") or (long_address = x"FFD1702") then
        reg_dmagic_addr(22 downto 16) <= value(6 downto 0);
        reg_dmagic_addr(27 downto 23) <= (others => '0');
        reg_dmagic_withio <= value(7);
      elsif (long_address = x"FFD3704") or (long_address = x"FFD1704") then
        reg_dmagic_addr(27 downto 20) <= value;
      elsif (long_address = x"FFD3705") or (long_address = x"FFD1705") then
        reg_dmagic_src_mb <= value;
      elsif (long_address = x"FFD3706") or (long_address = x"FFD1706") then
        reg_dmagic_dst_mb <= value;
      elsif (long_address = x"FFD37FE") or (long_address = x"FFD17FE") then
        shadow_bank <= value;
      elsif (long_address = x"FFD37ff") or (long_address = x"FFD17ff") then
        -- re-enable kickstart ROM.  This is only to allow for easier development
        -- of kickstart ROMs.
        if value = x"4B" then
          reg_offset_high <= x"F00";
          reg_map_high <= "1000";
          reg_offset_low <= x"000";
          reg_map_low <= "0000";
          reg_mb_high <= x"FF";
          reg_mb_low <= x"00";
        end if;
      end if;
      
      -- Always write to shadow ram if in scope, even if we also write elsewhere.
      -- This ensures that shadow ram is consistent with the shadowed address space
      -- when the CPU reads from shadow ram.
      -- Get the shadow RAM address on the bus fast to improve timing.
      shadow_address <= to_integer(long_address(16 downto 0));
      shadow_wdata <= value;
      rom_address <= to_integer(long_address(16 downto 0));
      rom_wdata <= value;
      if long_address(27 downto 16)="0000"&shadow_bank then
        report "writing to shadow RAM via shadow_bank" severity note;
        shadow_write <= '1';
        rom_write <= '0';
        shadow_write_flags(3) <= '1';
      end if;
      if long_address(27 downto 17)="00000000000" then
        report "writing to shadow RAM via chipram shadowing. addr=$" & to_hstring(long_address) severity note;
        shadow_write <= '1';
        rom_write <= '0';
        fastio_write <= '0';
        -- shadow_try_write_count <= shadow_try_write_count + 1;
        shadow_write_flags(3) <= '1';
        chipram_address <= long_address(16 downto 0);
        chipram_we <= '1';
        chipram_datain <= value;
        report "writing to chipram..." severity note;
        wait_states <= io_write_wait_states;
        if io_write_wait_states /= x"00" then
          wait_states_non_zero <= '1';
        else
          wait_states_non_zero <= '0';
        end if;
      elsif long_address(27 downto 17)="00000000001" then
        report "writing to ROM. addr=$" & to_hstring(long_address) severity note;
        shadow_write <= '0';
        rom_write <= not rom_writeprotect;
        fastio_write <= '0';        
      elsif long_address(27 downto 24) = x"F" then
        accessing_fastio <= '1';
        shadow_write <= '0';
        rom_write <= '0';
        shadow_write_flags(2) <= '1';
        fastio_addr <= std_logic_vector(long_address(19 downto 0));
        last_fastio_addr <= std_logic_vector(long_address(19 downto 0));
        fastio_write <= '1'; fastio_read <= '0';
        report "raising fastio_write" severity note;
        fastio_wdata <= std_logic_vector(value);

        -- Setup delayed write to hypervisor registers
        -- (this removes the fan-out to 64 more registers from being on the
        -- critical path.  The side-effect is that writing to hypervisor
        -- registers (except $D67F) has the effect delayed by one cycle. Should
        -- only matter if you run self-modifying code in these registers from the
        -- hypervisor. If you do that, then you probably deserve to see problems.
        last_write_value <= value;
        last_write_pending <= '1';
        
        -- @IO:GS $FF7Exxx VIC-IV CHARROM write area
        if long_address(19 downto 12) = x"7E" then
          charrom_write_cs <= '1';
        end if;
        
        if long_address(19 downto 16) = x"8" then
          colour_ram_cs <= '1';
        end if;
        if long_address(19 downto 16) = x"D" then
          if long_address(15 downto 14) = "00" then    --   $D{0,1,2,3}XXX
            -- Colour RAM at $D800-$DBFF and optionally $DC00-$DFFF
            if long_address(11)='1' then
              if (long_address(10)='0') or (colourram_at_dc00='1') then
                report "D800-DBFF/DC00-DFFF colour ram access from VIC fastio" severity note;
                colour_ram_cs <= '1';
              end if;
            end if;
          end if;                         -- $D{0,1,2,3}XXX
        end if;                           -- $DXXXX
        wait_states <= io_write_wait_states;
        if io_write_wait_states /= x"00" then
          wait_states_non_zero <= '1';
        else
          wait_states_non_zero <= '0';
        end if;
      elsif long_address(27) = '1' then
        report "writing to slowram..." severity note;
        accessing_slowram <= '1';
        ddr_got_reply <= '0';
        shadow_write <= '0';
        rom_write <= '0';
        fastio_write <= '0';
        shadow_write_flags(2) <= '1';
        if ddr_ram_banking='1' then
          slowram_addr_drive <= std_logic_vector(long_address(23 downto 1))&ddr_ram_bank&std_logic(long_address(0));
        else
          slowram_addr_drive <= std_logic_vector(long_address(26 downto 0));
        end if;
        slowram_we_drive <= '1';
        slowram_datain <= std_logic_vector(value);
        slowram_datain_expected <= std_logic_vector(value);
        slowram_pending_write <= '1';
        wait_states <= slowram_waitstates;
        if slowram_waitstates /= x"00" then
          wait_states_non_zero <= '1';
        else
          wait_states_non_zero <= '0';
        end if;
        proceed <= '0';
      else
        -- Don't let unmapped memory jam things up
        shadow_write <= '0';
        null;
      end if;
    end write_long_byte;
        
    -- purpose: set processor flags from a byte (eg for PLP or RTI)
    procedure load_processor_flags (
      value : in unsigned(7 downto 0)) is
    begin  -- load_processor_flags
      flag_n <= value(7);
      flag_v <= value(6);
      -- C65/4502 specifications says that E is not set by PLP, only by SEE/CLE
      flag_d <= value(3);
      flag_i <= value(2);
      flag_z <= value(1);
      flag_c <= value(0);
    end procedure load_processor_flags;

    procedure set_nz (
      value : unsigned(7 downto 0)) is
    begin
      report "calculating N & Z flags on result $" & to_hstring(value) severity note;
      flag_n <= value(7);
      if value(7 downto 0) = x"00" then
        flag_z <= '1';
      else
        flag_z <= '0';
      end if;
    end set_nz;        

    impure function with_nz (
      value : unsigned(7 downto 0))
      return unsigned is
    begin  -- with_nz
      set_nz(value);
      return value;
    end with_nz;
    
    -- purpose: change memory map, C65-style
    procedure c65_map_instruction is
      variable offset : unsigned(15 downto 0);
    begin  -- c65_map_instruction
      -- This is how this instruction works:
      --                            Mapper Register Data
      --    7       6       5       4       3       2       1       0    BIT
      --+-------+-------+-------+-------+-------+-------+-------+-------+
      --| LOWER | LOWER | LOWER | LOWER | LOWER | LOWER | LOWER | LOWER | A
      --| OFF15 | OFF14 | OFF13 | OFF12 | OFF11 | OFF10 | OFF9  | OFF8  |
      --+-------+-------+-------+-------+-------+-------+-------+-------+
      --| MAP   | MAP   | MAP   | MAP   | LOWER | LOWER | LOWER | LOWER | X
      --| BLK3  | BLK2  | BLK1  | BLK0  | OFF19 | OFF18 | OFF17 | OFF16 |
      --+-------+-------+-------+-------+-------+-------+-------+-------+
      --| UPPER | UPPER | UPPER | UPPER | UPPER | UPPER | UPPER | UPPER | Y
      --| OFF15 | OFF14 | OFF13 | OFF12 | OFF11 | OFF10 | OFF9  | OFF8  |
      --+-------+-------+-------+-------+-------+-------+-------+-------+
      --| MAP   | MAP   | MAP   | MAP   | UPPER | UPPER | UPPER | UPPER | Z
      --| BLK7  | BLK6  | BLK5  | BLK4  | OFF19 | OFF18 | OFF17 | OFF16 |
      --+-------+-------+-------+-------+-------+-------+-------+-------+
      --
      
      -- C65GS extension: Set the MegaByte register for low and high mobies
      -- so that we can address all 256MB of RAM.
      if reg_x = x"0f" then
        reg_mb_low <= reg_a;
      end if;
      if reg_z = x"0f" then
        reg_mb_high <= reg_y;
      end if;
      reg_offset_low <= reg_x(3 downto 0) & reg_a;
      reg_map_low <= std_logic_vector(reg_x(7 downto 4));
      reg_offset_high <= reg_z(3 downto 0) & reg_y;
      reg_map_high <= std_logic_vector(reg_z(7 downto 4));

      -- Inhibit all interrupts until EOM (opcode $EA, which used to be NOP)
      -- is executed.
      map_interrupt_inhibit <= '1';
    end c65_map_instruction;

    procedure alu_op_cmp (
      i1 : in unsigned(7 downto 0);
      i2 : in unsigned(7 downto 0)) is
      variable result : unsigned(8 downto 0);
    begin
      result := ("0"&i1) - ("0"&i2);
      flag_z <= '0'; flag_c <= '0';
      if result(7 downto 0)=x"00" then
        flag_z <= '1';
      end if;
      if result(8)='0' then
        flag_c <= '1';
      end if;
      flag_n <= result(7);
    end alu_op_cmp;
    
    impure function alu_op_add (
      i1 : in unsigned(7 downto 0);
      i2 : in unsigned(7 downto 0)) return unsigned is
      -- Result is NVZC<8bit result>
      variable tmp : unsigned(11 downto 0);
    begin
      if flag_d='1' then
        tmp(8) := '0';
        tmp(7 downto 0) := (i1 and x"0f") + (i2 and x"0f") + ("0000000" & flag_c);
        
        if tmp(7 downto 0) > x"09" then
          tmp(7 downto 0) := tmp(7 downto 0) + x"06";
        end if;
        if tmp(7 downto 0) < x"10" then
          tmp(8 downto 0) := '0'&(tmp(7 downto 0) and x"0f")
                             + to_integer(i1 and x"f0") + to_integer(i2 and x"f0");
        else
          tmp(8 downto 0) := '0'&(tmp(7 downto 0) and x"0f")
                             + to_integer(i1 and x"f0") + to_integer(i2 and x"f0")
                             + 16;
        end if;
        if (i1 + i2 + ( "0000000" & flag_c )) = x"00" then
          report "add result SET Z";
          tmp(9) := '1'; -- Z flag
        else
          report "add result CLEAR Z (result=$"
            & to_hstring((i1 + i2 + ( "0000000" & flag_c )));
          tmp(9) := '0'; -- Z flag
        end if;
        tmp(11) := tmp(7); -- N flag
        tmp(10) := (i1(7) xor tmp(7)) and (not (i1(7) xor i2(7))); -- V flag
        if tmp(8 downto 4) > "01001" then
          tmp(7 downto 0) := tmp(7 downto 0) + x"60";
          tmp(8) := '1'; -- C flag
        end if;
        -- flag_c <= tmp(8);
      else
        tmp(8 downto 0) := ("0"&i2)
                           + ("0"&i1)
                           + ("00000000"&flag_c);
        tmp(7 downto 0) := tmp(7 downto 0);
        tmp(11) := tmp(7); -- N flag
        if (tmp(7 downto 0) = x"00") then
          tmp(9) := '1'; else tmp(9) := '0'; -- Z flag
        end if;
        tmp(10) := (not (i1(7) xor i2(7))) and (i1(7) xor tmp(7)); -- V flag
        -- flag_c <= tmp(8);
      end if;

      -- Return final value
      --report "add result of "
      --  & "$" & to_hstring(std_logic_vector(i1)) 
      --  & " + "
      --  & "$" & to_hstring(std_logic_vector(i2)) 
      --  & " + "
      --  & "$" & std_logic'image(flag_c)
      --  & " = " & to_hstring(std_logic_vector(tmp(7 downto 0))) severity note;
      return tmp;
    end function alu_op_add;

    impure function alu_op_sub (
      i1 : in unsigned(7 downto 0);
      i2 : in unsigned(7 downto 0)) return unsigned is
      variable tmp : unsigned(11 downto 0); -- NVZC+8bit result
      variable tmpd : unsigned(8 downto 0);
    begin
      tmp(8 downto 0) := ("0"&i1) - ("0"&i2)
             - "000000001" + ("00000000"&flag_c);
      tmp(8) := not tmp(8); -- Carry flag
      tmp(10) := (i1(7) xor tmp(7)) and (i1(7) xor i2(7)); -- Overflowflag
      tmp(7 downto 0) := tmp(7 downto 0);
      tmp(11) := tmp(7); -- Negative flag
      if tmp(7 downto 0) = x"00" then
        tmp(9) := '1'; else tmp(9) := '0';  -- Zero flag
      end if;
      if flag_d='1' then
        tmpd := (("00000"&i1(3 downto 0)) - ("00000"&i2(3 downto 0)))
                - "000000001" + ("00000000" & flag_c);

        if tmpd(4)='1' then
          tmpd(3 downto 0) := tmpd(3 downto 0)-x"6";
          tmpd(8 downto 4) := ("0"&i1(7 downto 4)) - ("0"&i2(7 downto 4)) - "00001";
        else
          tmpd(8 downto 4) := ("0"&i1(7 downto 4)) - ("0"&i2(7 downto 4));
        end if;
        if tmpd(8)='1' then
          tmpd(8 downto 0) := tmpd(8 downto 0) - ("0"&x"60");
        end if;
        tmp(7 downto 0) := tmpd(7 downto 0);
      end if;
      -- Return final value
      --report "subtraction result of "
      --  & "$" & to_hstring(std_logic_vector(i1)) 
      --  & " - "
      --  & "$" & to_hstring(std_logic_vector(i2)) 
      --  & " - 1 + "
      --  & "$" & std_logic'image(flag_c)
      --  & " = " & to_hstring(std_logic_vector(tmp(7 downto 0))) severity note;
      return tmp(11 downto 0);
    end function alu_op_sub;
    
    variable virtual_reg_p : std_logic_vector(7 downto 0);
    variable temp_pc : unsigned(15 downto 0);
    variable temp_value : unsigned(7 downto 0);
    variable nybl : unsigned(3 downto 0);

    variable execute_now : std_logic := '0';
    variable execute_opcode : unsigned(7 downto 0);
    variable execute_arg1 : unsigned(7 downto 0);
    variable execute_arg2 : unsigned(7 downto 0);

    variable memory_read_value : unsigned(7 downto 0);

    variable memory_access_address : unsigned(27 downto 0) := x"FFFFFFF";
    variable memory_access_read : std_logic := '0';
    variable memory_access_write : std_logic := '0';
    variable memory_access_resolve_address : std_logic := '0';
    variable memory_access_wdata : unsigned(7 downto 0) := x"FF";

    variable pc_inc : std_logic;
    variable pc_dec : std_logic;
    variable dec_sp : std_logic;
    variable stack_pop : std_logic;
    variable stack_push : std_logic;
    variable push_value : unsigned(7 downto 0);

    variable temp_addr : unsigned(15 downto 0);    

    variable temp17 : unsigned(16 downto 0);    
    variable temp9 : unsigned(8 downto 0);    

    variable cpu_speed : std_logic_vector(2 downto 0);
    
  begin
    
    -- Begin calculating results for operations immediately to help timing.
    -- The trade-off is consuming a bit of extra silicon.
    a_incremented <= reg_a + 1;
    a_decremented <= reg_a - 1;
    a_negated <= (not reg_a) + 1;
    a_ror <= flag_c & reg_a(7 downto 1);
    a_rol <= reg_a(6 downto 0) & flag_c;    
    a_asr <= reg_a(7) & reg_a(7 downto 1);
    a_lsr <= '0' & reg_a(7 downto 1);
    a_ior <= reg_a or read_data;
    a_xor <= reg_a xor read_data;
    a_and <= reg_a and read_data;
    a_asl <= reg_a(6 downto 0)&'0';      
    a_neg <= (not reg_a) + 1;
    if (reg_a = x"00") then 
      a_neg_z <= '1'; else a_neg_z <= '0';
    end if;
    a_add <= alu_op_add(reg_a,read_data);
    a_sub <= alu_op_sub(reg_a,read_data);

    x_incremented <= reg_x + 1;
    x_decremented <= reg_x - 1;
    y_incremented <= reg_y + 1;
    y_decremented <= reg_y - 1;
    z_incremented <= reg_z + 1;
    z_decremented <= reg_z - 1;
    
    -- BEGINNING OF MAIN PROCESS FOR CPU
    if rising_edge(clock) then

      -- Continuously update the address resolution for each 4KB block
      -- This allows us to relocate most of the complex calculation of addresses
      -- from the critical path in each cycle to a separate process.
      if block_update_number < 16 then
        block_addresses(block_update_number)
          <= "0000"&resolve_address_to_long(to_unsigned(block_update_number,4)&"000000000000",false);
      else
        block_addresses(block_update_number)
          <= "0000"&resolve_address_to_long(to_unsigned(block_update_number,4)&"000000000000",true);
      end if;
      if block_update_number = 31 then
        block_update_number <= 0;
      else
        block_update_number <= block_update_number + 1;
      end if;
  
      -- Select CPU personality based on IO mode, but hypervisor can override to
      -- for 4502 mode, and the hypervisor itself always runs in 4502 mode.
      if (viciii_iomode="00") and (force_4502='0') and (hypervisor_mode='0') then
        -- Use 6502 mode when IO mode is in C64/VIC-II mode, since no C64 program
        -- should enable VIC-III IO map and expect 6502 CPU.  However, the one
        -- catch to this is that the C64 mode kernal on a C65 uses new
        -- instructions when checking the drive number to decide whether to use
        -- the new DOS or IEC serial.  Thus we need code in the Kernal to run
        -- in 4502 mode.  XXX The check here is not completely perfect, but
        -- should cover all likely situations, since only the use of MAP could
        -- upset it.
        if (reg_pc(15 downto 11) = "111")
          and ((cpuport_value(1) or (not cpuport_ddr(1)))='1')
          and (reg_map_high(3) = '0') then
          emu6502 <= '0';
        else 
          emu6502 <= '1';
        end if;
      else
        emu6502 <= '0';
      end if;
      cpuis6502 <= emu6502;
      
      -- Work out actual georam page
      georam_page(5 downto 0) <= georam_blockpage(5 downto 0);
      georam_page(13 downto 6) <= georam_block and georam_blockmask;

      -- Write to hypervisor registers if requested
      -- (This is separated out from the previous cycle to reduce the logic depth,
      -- and thus help achieve timing closure.)
      if last_write_pending = '1' then
        last_write_pending <= '0';

        -- @IO:GS $FFC00A0 45GS10 slowram wait-states (write-only)
        if last_write_address = x"FFC00A0" then
          slowram_waitstates <= last_value;
        end if;

        -- @IO:GS $D640 - Hypervisor A register storage
        if last_write_address = x"FFD3640" and hypervisor_mode='1' then
          hyper_a <= last_value;
        end if;
        -- @IO:GS $D641 - Hypervisor X register storage
        if last_write_address = x"FFD3641" and hypervisor_mode='1' then
          hyper_x <= last_value;
        end if;
        -- @IO:GS $D642 - Hypervisor Y register storage
        if last_write_address = x"FFD3642" and hypervisor_mode='1' then
          hyper_y <= last_value;
        end if;
        -- @IO:GS $D643 - Hypervisor Z register storage
        if last_write_address = x"FFD3643" and hypervisor_mode='1' then
          hyper_z <= last_value;
        end if;
        -- @IO:GS $D644 - Hypervisor B register storage
        if last_write_address = x"FFD3644" and hypervisor_mode='1' then
          hyper_b <= last_value;
        end if;
        -- @IO:GS $D645 - Hypervisor SPL register storage
        if last_write_address = x"FFD3645" and hypervisor_mode='1' then
          hyper_sp <= last_value;
        end if;
        -- @IO:GS $D646 - Hypervisor SPH register storage
        if last_write_address = x"FFD3646" and hypervisor_mode='1' then
          hyper_sph <= last_value;
        end if;
        -- @IO:GS $D647 - Hypervisor P register storage
        if last_write_address = x"FFD3647" and hypervisor_mode='1' then
          hyper_p <= last_value;
        end if;
        -- @IO:GS $D648 - Hypervisor PC-low register storage
        if last_write_address = x"FFD3648" and hypervisor_mode='1' then
          hyper_pc(7 downto 0) <= last_value;
        end if;
        -- @IO:GS $D649 - Hypervisor PC-high register storage
        if last_write_address = x"FFD3649" and hypervisor_mode='1' then
          hyper_pc(15 downto 8) <= last_value;
        end if;
        -- @IO:GS $D64A - Hypervisor MAPLO register storage (high bits)
        if last_write_address = x"FFD364A" and hypervisor_mode='1' then
          hyper_map_low <= std_logic_vector(last_value(7 downto 4));
          hyper_map_offset_low(11 downto 8) <= last_value(3 downto 0);
        end if;
        -- @IO:GS $D64B - Hypervisor MAPLO register storage (low bits)
        if last_write_address = x"FFD364B" and hypervisor_mode='1' then
          hyper_map_offset_low(7 downto 0) <= last_value;
        end if;
        -- @IO:GS $D64C - Hypervisor MAPHI register storage (high bits)
        if last_write_address = x"FFD364C" and hypervisor_mode='1' then
          hyper_map_high <= std_logic_vector(last_value(7 downto 4));
          hyper_map_offset_high(11 downto 8) <= last_value(3 downto 0);
        end if;
        -- @IO:GS $D64D - Hypervisor MAPHI register storage (low bits)
        if last_write_address = x"FFD364D" and hypervisor_mode='1' then
          hyper_map_offset_high(7 downto 0) <= last_value;
        end if;
        -- @IO:GS $D64E - Hypervisor MAPLO mega-byte number register storage
        if last_write_address = x"FFD364E" and hypervisor_mode='1' then
          hyper_mb_low <= last_value;
        end if;
        -- @IO:GS $D64F - Hypervisor MAPHI mega-byte number register storage
        if last_write_address = x"FFD364F" and hypervisor_mode='1' then
          hyper_mb_high <= last_value;
        end if;
        -- @IO:GS $D650 - Hypervisor CPU port $00 value
        if last_write_address = x"FFD3650" and hypervisor_mode='1' then
          hyper_port_00 <= last_value;
        end if;
        -- @IO:GS $D651 - Hypervisor CPU port $01 value
        if last_write_address = x"FFD3651" and hypervisor_mode='1' then
          hyper_port_01 <= last_value;
        end if;
        -- @IO:GS $D652 - Hypervisor VIC-IV IO mode
        if last_write_address = x"FFD3652" and hypervisor_mode='1' then
          hyper_iomode <= last_value;
        end if;
        -- @IO:GS $D653 - Hypervisor DMAgic source MB
        if last_write_address = x"FFD3653" and hypervisor_mode='1' then
          hyper_dmagic_src_mb <= last_value;
        end if;
        -- @IO:GS $D654 - Hypervisor DMAgic destination MB
        if last_write_address = x"FFD3654" and hypervisor_mode='1' then
          hyper_dmagic_dst_mb <= last_value;
        end if;
        -- @IO:GS $D655 - Hypervisor DMAGic list address bits 0-7
        if last_write_address = x"FFD3655" and hypervisor_mode='1' then
          hyper_dmagic_list_addr(7 downto 0) <= last_value;
        end if;
        -- @IO:GS $D656 - Hypervisor DMAGic list address bits 15-8
        if last_write_address = x"FFD3656" and hypervisor_mode='1' then
          hyper_dmagic_list_addr(15 downto 8) <= last_value;
        end if;
        -- @IO:GS $D657 - Hypervisor DMAGic list address bits 23-16
        if last_write_address = x"FFD3657" and hypervisor_mode='1' then
          hyper_dmagic_list_addr(23 downto 16) <= last_value;
        end if;
        -- @IO:GS $D658 - Hypervisor DMAGic list address bits 27-24
        if last_write_address = x"FFD3658" and hypervisor_mode='1' then
          hyper_dmagic_list_addr(27 downto 24) <= last_value(3 downto 0);
        end if;
        -- @IO:GS $D659 - Hypervisor DDR RAM banking control
        -- @IO:GS $D659.7 - Enable DDR RAM banking
        -- @IO:GS $D659.0-2 - Select which 16MB DDR RAM bank to make visible
        if last_write_address = x"FFD3659" and hypervisor_mode='1' then
          ddr_ram_banking <= last_value(7);
          ddr_ram_bank <= std_logic_vector(last_value(2 downto 0));
        end if;

        -- @IO:GS $D65D - Hypervisor current virtual page number (low byte)
        if last_write_address = x"FFD365D" and hypervisor_mode='1' then
          reg_pagenumber(1 downto 0) <= last_value(7 downto 6);
          reg_pageactive <= last_value(4);
          reg_pages_dirty <= std_logic_vector(last_value(3 downto 0));
        end if;
        -- @IO:GS $D65E - Hypervisor current virtual page number (mid byte)
        if last_write_address = x"FFD365E" and hypervisor_mode='1' then
          reg_pagenumber(9 downto 2) <= last_value;
        end if;
        -- @IO:GS $D65F - Hypervisor current virtual page number (high byte)
        if last_write_address = x"FFD365F" and hypervisor_mode='1' then
          reg_pagenumber(17 downto 10) <= last_value;
        end if;
        -- @IO:GS $D660 - Hypervisor virtual memory page 0 logical page low byte
        -- @IO:GS $D661 - Hypervisor virtual memory page 0 logical page high byte
        -- @IO:GS $D662 - Hypervisor virtual memory page 0 physical page low byte
        -- @IO:GS $D663 - Hypervisor virtual memory page 0 physical page high byte
        if last_write_address = x"FFD3660" and hypervisor_mode='1' then
          reg_page0_logical(7 downto 0) <= last_value;
        end if;
        if last_write_address = x"FFD3661" and hypervisor_mode='1' then
          reg_page0_logical(15 downto 8) <= last_value;
        end if;
        if last_write_address = x"FFD3662" and hypervisor_mode='1' then
          reg_page0_physical(7 downto 0) <= last_value;
        end if;
        if last_write_address = x"FFD3663" and hypervisor_mode='1' then
          reg_page0_physical(15 downto 8) <= last_value;
        end if;
        -- @IO:GS $D664 - Hypervisor virtual memory page 1 logical page low byte
        -- @IO:GS $D665 - Hypervisor virtual memory page 1 logical page high byte
        -- @IO:GS $D666 - Hypervisor virtual memory page 1 physical page low byte
        -- @IO:GS $D667 - Hypervisor virtual memory page 1 physical page high byte
        if last_write_address = x"FFD3664" and hypervisor_mode='1' then
          reg_page1_logical(7 downto 0) <= last_value;
        end if;
        if last_write_address = x"FFD3665" and hypervisor_mode='1' then
          reg_page1_logical(15 downto 8) <= last_value;
        end if;
        if last_write_address = x"FFD3666" and hypervisor_mode='1' then
          reg_page1_physical(7 downto 0) <= last_value;
        end if;
        if last_write_address = x"FFD3667" and hypervisor_mode='1' then
          reg_page1_physical(15 downto 8) <= last_value;
        end if;

        -- @IO:GS $D668 - Hypervisor virtual memory page 2 logical page low byte
        -- @IO:GS $D669 - Hypervisor virtual memory page 2 logical page high byte
        -- @IO:GS $D66A - Hypervisor virtual memory page 2 physical page low byte
        -- @IO:GS $D66B - Hypervisor virtual memory page 2 physical page high byte
        if last_write_address = x"FFD3668" and hypervisor_mode='1' then
          reg_page2_logical(7 downto 0) <= last_value;
        end if;
        if last_write_address = x"FFD3669" and hypervisor_mode='1' then
          reg_page2_logical(15 downto 8) <= last_value;
        end if;
        if last_write_address = x"FFD366A" and hypervisor_mode='1' then
          reg_page2_physical(7 downto 0) <= last_value;
        end if;
        if last_write_address = x"FFD366B" and hypervisor_mode='1' then
          reg_page2_physical(15 downto 8) <= last_value;
        end if;
        -- @IO:GS $D66C - Hypervisor virtual memory page 3 logical page low byte
        -- @IO:GS $D66D - Hypervisor virtual memory page 3 logical page high byte
        -- @IO:GS $D66E - Hypervisor virtual memory page 3 physical page low byte
        -- @IO:GS $D66F - Hypervisor virtual memory page 3 physical page high byte
        if last_write_address = x"FFD366C" and hypervisor_mode='1' then
          reg_page3_logical(7 downto 0) <= last_value;
        end if;
        if last_write_address = x"FFD366D" and hypervisor_mode='1' then
          reg_page3_logical(15 downto 8) <= last_value;
        end if;
        if last_write_address = x"FFD366E" and hypervisor_mode='1' then
          reg_page3_physical(7 downto 0) <= last_value;
        end if;
        if last_write_address = x"FFD366F" and hypervisor_mode='1' then
          reg_page3_physical(15 downto 8) <= last_value;
        end if;

        -- @IO:GS $D670 - Hypervisor GeoRAM base address (x MB) (write-only for
        -- now)
        if last_write_address = x"FFD3670" and hypervisor_mode='1' then
          georam_page(19 downto 12) <= last_value;
        end if;
        -- @IO:GS $D671 - Hypervisor GeoRAM address mask (applied to GeoRAM block
        -- register) (write-only for now)
        if last_write_address = x"FFD3671" and hypervisor_mode='1' then
          georam_blockmask <= last_value;
        end if;        

        -- @IO:GS $D67C - Hypervisor write serial output to UART monitor (must wait atleast approx 4,000 cycles between writes to allow char to flush)
        if last_write_address = x"FFD367C" and hypervisor_mode='1' then
          monitor_char <= last_value;
          monitor_char_toggle <= monitor_char_toggle_internal;
          monitor_char_toggle_internal <= not monitor_char_toggle_internal;
        end if;
        -- @IO:GS $D67D.0 - Hypervisor C64 ROM source select (0=DDR,1=64KB colour RAM)
        -- @IO:GS $D67D.1 - Hypervisor enable 32-bit JMP/JSR etc
        -- @IO:GS $D67D.2 - Hypervisor write protect C65 ROM $20000-$3FFFF
        -- @IO:GS $D67D.3 - Hypervisor enable ASC/DIN CAPS LOCK key to enable/disable CPU slow-down in C64/C128/C65 modes
        -- @IO:GS $D67D.4 - Hypervisor force CPU to 48MHz for userland (userland can override via POKE0)
        -- @IO:GS $D67D.5 - Hypervisor force CPU to 4502 personality, even in C64 IO mode.
        -- @IO:GS $D67D - Hypervisor watchdog register: writing any value clears the watch dog
        if last_write_address = x"FFD367D" and hypervisor_mode='1' then
          rom_from_colour_ram <= last_value(0);
          flat32_enabled <= last_value(1);
          rom_writeprotect <= last_value(2);
          speed_gate_enable <= last_value(3);
          speed_gate_enable_internal <= last_value(3);
          force_fast <= last_value(4);
          force_4502 <= last_value(5);
          watchdog_fed <= '1';
        end if;
        -- @IO:GS $D67E - Hypervisor already-upgraded bit (sets permanently)
        if last_write_address = x"FFD367E" and hypervisor_mode='1' then
          hypervisor_upgraded <= '1';
        end if;

      end if;

      
      if hyper_trap = '0' and hyper_trap_state = '1' then
        hyper_trap_pending <= '1';        
      end if;
      hyper_trap_state <= hyper_trap;
      
      slowram_request_toggle <= slowram_request_toggle_drive;
      slowram_addr_reflect_drive <= slowram_addr_reflect;
      slowram_datain_reflect_drive <= slowram_datain_reflect;
      
      cpu_hypervisor_mode <= hypervisor_mode;
      
      slowram_addr <= slowram_addr_drive;
      slowram_we <= slowram_we_drive;
      cache_address <= slowram_addr_drive(12 downto 4);
      if (slowram_addr_drive(26 downto 4) = cache_read_data(150 downto 128)) then
        slowram_data_valid <= '1';
        case slowram_addr_drive(3 downto 0) is
          when "0000" => slowram_data_in <= cache_read_data(7 downto 0);
          when "0001" => slowram_data_in <= cache_read_data(15 downto 8);
          when "0010" => slowram_data_in <= cache_read_data(23 downto 16);
          when "0011" => slowram_data_in <= cache_read_data(31 downto 24);
          when "0100" => slowram_data_in <= cache_read_data(39 downto 32);
          when "0101" => slowram_data_in <= cache_read_data(47 downto 40);
          when "0110" => slowram_data_in <= cache_read_data(55 downto 48);
          when "0111" => slowram_data_in <= cache_read_data(63 downto 56);
          when "1000" => slowram_data_in <= cache_read_data(71 downto 64);
          when "1001" => slowram_data_in <= cache_read_data(79 downto 72);
          when "1010" => slowram_data_in <= cache_read_data(87 downto 80);
          when "1011" => slowram_data_in <= cache_read_data(95 downto 88);
          when "1100" => slowram_data_in <= cache_read_data(103 downto 96);
          when "1101" => slowram_data_in <= cache_read_data(111 downto 104);
          when "1110" => slowram_data_in <= cache_read_data(119 downto 112);
          when "1111" => slowram_data_in <= cache_read_data(127 downto 120);
          when others => slowram_data_in <= x"dd";
        end case;
      else
        slowram_data_valid <= '0';
        slowram_data_in <= x"CF";
      end if;
      
      check_for_interrupts;
      
      if wait_states = x"00" then
        if last_action = 'R' then
          report "MEMORY reading $" & to_hstring(last_address)
            & " = $" & to_hstring(read_data) severity note;
        end if;
        if last_action = 'W' then
          report "MEMORY writing $" & to_hstring(last_address)
            & " <= $" & to_hstring(last_value) severity note;
        end if;
      end if;
            
      cpu_leds <= std_logic_vector(shadow_write_flags);
      
      if shadow_write='1' then
        shadow_observed_write_count <= shadow_observed_write_count + 1;
      end if;
      
      monitor_mem_attention_request_drive <= monitor_mem_attention_request;
      monitor_mem_read_drive <= monitor_mem_read;
      monitor_mem_write_drive <= monitor_mem_write;
      monitor_mem_setpc_drive <= monitor_mem_setpc;
      monitor_mem_address_drive <= monitor_mem_address;
      monitor_mem_wdata_drive <= monitor_mem_wdata;
      
      --monitor_debug_memory_access(31) <= accessing_shadow;
      --monitor_debug_memory_access(30) <= accessing_fastio;
      --monitor_debug_memory_access(29) <= accessing_slowram;
      --monitor_debug_memory_access(27) <= accessing_colour_ram_fastio;
      --monitor_debug_memory_access(26) <= accessing_vic_fastio;
      --monitor_debug_memory_access(25) <= accessing_cpuport;
      --monitor_debug_memory_access(24) <= '0';

      --monitor_debug_memory_access(23 downto 16) <= std_logic_vector(read_data_copy);
      --monitor_debug_memory_access(15 downto 8) <= std_logic_vector(read_data);
      --monitor_debug_memory_access(7 downto 0) <= std_logic_vector(read_data_complex);
      
      -- Copy read memory location to simplify reading from memory.
      -- Penalty is +1 wait state for memory other than shadowram.
      read_data_copy <= read_data_complex;
      
      -- By default we are doing nothing new.
      pc_inc := '0'; pc_dec := '0'; dec_sp := '0';
      stack_pop := '0'; stack_push := '0';
      
      memory_access_read := '0';
      memory_access_write := '0';
      memory_access_resolve_address := '0';
      
      monitor_watch_match <= '0';       -- set if writing to watched address
      monitor_state <= to_unsigned(processor_state'pos(state),8)&read_data;
      monitor_hypervisor_mode <= hypervisor_mode;
      monitor_ddr_ram_banking <= ddr_ram_banking;
      monitor_pc <= reg_pc;
      monitor_a <= reg_a;
      monitor_x <= reg_x;
      monitor_y <= reg_y;
      monitor_z <= reg_z;
      monitor_sp <= reg_sph&reg_sp;
      monitor_b <= reg_b;
      monitor_interrupt_inhibit <= map_interrupt_inhibit;
      monitor_map_offset_low <= reg_offset_low;
      monitor_map_offset_high <= reg_offset_high; 
      monitor_map_enables_low <= std_logic_vector(reg_map_low); 
      monitor_map_enables_high <= std_logic_vector(reg_map_high); 
      
      -- Generate virtual processor status register for convenience
      virtual_reg_p(7) := flag_n;
      virtual_reg_p(6) := flag_v;
      virtual_reg_p(5) := flag_e;
      virtual_reg_p(4) := '0';
      virtual_reg_p(3) := flag_d;
      virtual_reg_p(2) := flag_i;
      virtual_reg_p(1) := flag_z;
      virtual_reg_p(0) := flag_c;

      monitor_p <= unsigned(virtual_reg_p);

      -------------------------------------------------------------------------
      -- Real CPU work begins here.
      -------------------------------------------------------------------------

      monitor_waitstates <= wait_states;

      -- Catch the CPU when it goes to the next instruction if single stepping.
      if (monitor_mem_trace_mode='0' or
          monitor_mem_trace_toggle_last /= monitor_mem_trace_toggle)
        and (monitor_mem_attention_request_drive='0') then
        monitor_mem_trace_toggle_last <= monitor_mem_trace_toggle;
        normal_fetch_state <= InstructionFetch;

        -- Or select slower CPU mode if required.
        -- Test goes here so that it doesn't break the monitor interface.
        -- But the hypervisor always runs at full speed.
        fast_fetch_state <= InstructionDecode;
              cpu_speed := vicii_2mhz&viciii_fast&viciv_fast;
        if hypervisor_mode='0' and ((speed_gate='1') and (force_fast='0')) then
          case cpu_speed is
            when "100" => -- 1mhz
              normal_fetch_state <= ProcessorPause;
              fast_fetch_state <= ProcessorPause;
              cpu_pause_shift <= 0;
              cpuspeed <= x"01";
            when "101" => -- 1mhz
              normal_fetch_state <= ProcessorPause;
              fast_fetch_state <= ProcessorPause;          
              cpu_pause_shift <= 0;
              cpuspeed <= x"01";
            when "110" => -- 3.5mhz
              normal_fetch_state <= ProcessorPause;
              fast_fetch_state <= ProcessorPause;          
              cpu_pause_shift <= 2;
              cpuspeed <= x"04";
            when "111" => -- 48mhz
              cpuspeed <= x"48";
              null;
            when "000" => -- 2mhz
              normal_fetch_state <= ProcessorPause;
              fast_fetch_state <= ProcessorPause;          
              cpu_pause_shift <= 1;
              cpuspeed <= x"02";
            when "001" => -- 48mhz
              cpuspeed <= x"48";
              null;
            when "010" => -- 3.5mhz
              normal_fetch_state <= ProcessorPause;
              fast_fetch_state <= ProcessorPause;          
              cpu_pause_shift <= 2;
              cpuspeed <= x"04";
            when "011" => -- 48mhz
              cpuspeed <= x"48";
              null;
            when others =>
              null;
          end case;
        else
          cpuspeed <= x"48";
        end if;
      else
        normal_fetch_state <= ProcessorHold;
        fast_fetch_state <= ProcessorHold;
      end if;

      -- Force single step while I debug it.
      if debugging_single_stepping='1' then
        normal_fetch_state <= ProcessorHold;
        fast_fetch_state <= ProcessorHold;
      end if;
      
      if mem_reading='1' then
        memory_read_value := read_data;
      end if;

      -- Count down reset watchdog, and trigger reset if required.
      watchdog_reset <= '0';
      if (watchdog_fed='0') and
        ((monitor_mem_attention_request_drive='0')
         and (monitor_mem_trace_mode='0')) then
        if watchdog_countdown = 0 then
          -- Watchdog reset triggered
          watchdog_reset <= '1';
          watchdog_countdown <= 65535;
        else
          watchdog_countdown <= watchdog_countdown - 1;
        end if;
      end if;
      
      -- report "reset = " & std_logic'image(reset) severity note;
      reset_drive <= reset;
      if reset_drive='0' or watchdog_reset='1' then
        state <= ResetLow;
        proceed <= '0';
        wait_states <= x"00";
        wait_states_non_zero <= '0';
        watchdog_fed <= '0';
        watchdog_countdown <= 65535;
        reset_cpu_state;
      else
        -- Honour wait states on memory accesses
        -- Clear memory access lines unless we are in a memory wait state
        -- XXX replace with single bit test flag for wait_states = 0 to reduce
        -- logic depth        
        if wait_states_non_zero = '1' then
          report "  $" & to_hstring(wait_states)
            &" memory waitstates remaining.  Fastio_rdata = $"
            & to_hstring(fastio_rdata)
            & ", mem_reading=" & std_logic'image(mem_reading)
            & ", fastio_addr=$" & to_hstring(fastio_addr)
            severity note;
          wait_states <= wait_states - 1;
          if wait_states = x"01" then
            -- Next cycle we can do stuff, provided that the serial monitor
            -- isn't asking us to do anything.
            proceed <= '1';
            -- timeout DDR memory if it isn't responding
            if (ddr_got_reply = '0') and (accessing_slowram='1') then
              ddr_timeout_counter <= ddr_timeout_counter + 1;
              slowram_request_toggle_drive <= slowram_done_toggle;
              slowram_desired_done_toggle <= slowram_done_toggle;
              slowram_pending_write <='0';
              slowram_we_drive <= '0';
            end if;
            wait_states_non_zero <= '0';
          else
            wait_states_non_zero <= '1';            
          end if;
          -- Stop waiting on slow ram as soon as we have the result.
          -- We know we have the result when the RAM is no longer busy, and the
          -- cache has the correct memory line.
          if (accessing_slowram='1') and (slowram_we_drive='0')
            and (slowram_data_valid='1') and (proceed='0') then
            ddr_reply_counter <= ddr_reply_counter + 1;
            ddr_got_reply <= '1';
            wait_states <= x"00";
            wait_states_non_zero <= '0';
            proceed <= '1';
          end if;
          -- Similarly, when writing to slowram, we return only once we have verified
          -- that the value has been written.
          if (accessing_slowram='1') and (slowram_we_drive='1')
            and (slowram_data_valid='1') and (proceed='0')
            and (slowram_datain_expected = slowram_data_in) then
            ddr_write_ready_counter <= ddr_write_ready_counter + 1;
            slowram_pending_write <= '0';
            slowram_we_drive <= '0';
            ddr_got_reply <= '1';
            wait_states <= x"00";
            wait_states_non_zero <= '0';
            proceed <= '1';
          end if;
          
          -- If the DDR memory is idle, and he cache has the wrong memory line,
          -- so ask the DDR controller to load the cache line.
          if (accessing_slowram='1') and (slowram_we_drive='0')
            and (slowram_addr_drive(26 downto 4) /= cache_read_data(150 downto 128))
            and (slowram_desired_done_toggle = slowram_done_toggle) then
            -- The address & WE has already been set in read_long_address()
            slowram_request_toggle_drive <= not slowram_done_toggle;
            slowram_desired_done_toggle <= not slowram_done_toggle;
            ddr_cache_load_counter <= ddr_cache_load_counter + 1;
          end if;

          -- Now that the slowram signals have all been set for a write and
          -- had a cycle to settle, toggle the request line, so that the DDR
          -- can get the write request without missing it.
          if (slowram_pending_write='1')
            and (slowram_desired_done_toggle = slowram_done_toggle)
            and (slowram_addr_reflect_drive = slowram_addr_drive)
            and (slowram_datain_reflect_drive = slowram_datain_expected) then
            slowram_desired_done_toggle <= not slowram_done_toggle;
            slowram_request_toggle_drive <= not slowram_done_toggle;
          end if;

        else
          -- End of wait states, so clear memory writing and reading

          colour_ram_cs <= '0';
          fastio_write <= '0';
--          fastio_read <= '0';
          chipram_we <= '0';
          slowram_we_drive <= '0';

          if mem_reading='1' then
--            report "resetting mem_reading (read $" & to_hstring(memory_read_value) & ")" severity note;
            mem_reading <= '0';
            monitor_mem_reading <= '0';
          end if;

          proceed <= '1';
        end if;

        monitor_proceed <= proceed;
        monitor_request_reflected <= monitor_mem_attention_request_drive;
        
        if proceed='1' then
          -- Main state machine for CPU
          report "CPU state = " & processor_state'image(state) & ", PC=$" & to_hstring(reg_pc) severity note;

          pop_a <= '0'; pop_x <= '0'; pop_y <= '0'; pop_z <= '0';
          pop_p <= '0';
          
          -- By default read next byte in instruction stream.
          memory_access_read := '1';
          memory_access_address := x"000"&reg_pc;
          memory_access_resolve_address := '1';

          case state is
            when ResetLow =>
              -- Reset now maps kickstart at $8000-$BFFF, and enters through $8000
              -- by triggering the hypervisor.
              -- XXX indicate source of hypervisor entry
              reset_cpu_state;
              state <= TrapToHypervisor;
            when VectorRead =>
              if hypervisor_mode='1' then
                -- Vectors move in hypervisor mode to be inside the hypervisor
                -- ROM at $81Fx
                memory_access_address := x"FF801F"&vector;
              else
                memory_access_address := x"000FFF"&vector;
              end if;
              vector <= vector + 1;
              state <= VectorRead;
              vector_read_stage <= vector_read_stage + 1;
              case vector_read_stage is
                when 0 =>
                  -- First cycle, we just wait for the address to load
                  null;
                when 1 =>
                  -- 2nd cycle, store low byte of PC
                  reg_pc(7 downto 0) <= memory_read_value;
                when 2 =>
                  -- 3rd cycle, store high byte of PC, and dispatch instruction
                  reg_pc(15 downto 8) <= memory_read_value;
                  state <= normal_fetch_state;
                when others =>
                  null;
              end case;
            when Interrupt =>
              -- BRK or IRQ
              -- Push P and PC
              if nmi_pending='1' then
                vector <= x"a";
                nmi_pending <= '0';
              else
                vector <= x"e";
              end if;
              flag_i <= '1';
              reg_t <= unsigned(virtual_reg_p);
              if reg_instruction = I_BRK then
                -- set B flag when pushing P
                reg_t(4) <= '1';
              else
                -- clear B flag when pushing P
                reg_t(4) <= '0';
              end if;
              stack_push := '1';
              memory_access_wdata := reg_pc(15 downto 8);
              state <= InterruptPushPCL;
            when InterruptPushPCL =>
              stack_push := '1';
              memory_access_wdata := reg_pc(7 downto 0);
              state <= InterruptPushP;    
            when InterruptPushP =>
              -- Push flags to stack (already put in reg_t a few cycles earlier)
              stack_push := '1';
              memory_access_wdata := reg_t;
              state <= VectorRead;
              vector_read_stage <= 0;
            when RTI =>
              stack_pop := '1';
              state <= RTI2;
            when RTI2 =>
              load_processor_flags(memory_read_value);
              stack_pop := '1';
              state <= RTS1;
            when RTS =>
              stack_pop := '1';
              state <= RTS1;
            when RTS1 =>
              report "Setting PC-low during RTS";
              reg_pc(7 downto 0) <= memory_read_value;
              report "RTS: high byte = $" & to_hstring(memory_read_value) severity note;
              stack_pop := '1';
              state <= RTS2;
            when RTS2 =>
              -- Finish RTS as fast as possible, potentially just 4 cycles
              -- instead of 6 on a real 6502.  This does complicate the logic a
              -- little if we want the monitor interface to be able to
              -- interrupt the CPU immediately following an RTS.
              -- (we may also later introduce a stack cache that would allow RTS
              -- to execute in 1 cycle in certain circumstances)
              report "Setting PC: RTS: low byte = $" & to_hstring(memory_read_value) severity note;
              if reg_instruction = I_RTS then
                reg_pc <= (memory_read_value&reg_pc(7 downto 0))+1;
              else
                reg_pc <= (memory_read_value&reg_pc(7 downto 0));
              end if;
              state <= RTS3;
            when RTS3 =>
              -- Read the instruction byte following
              memory_access_address := x"000"&reg_pc;
              memory_access_read := '1';
              -- And set PC to the byte following, unless we are held, in which
              -- case the increment will happen in InstructionFetch
              if fast_fetch_state = InstructionDecode then
                reg_pc <= reg_pc+1;
                report "Pre-incrementing PC for immediate dispatch" severity note;
              end if;
              state <= fast_fetch_state;
            when ProcessorPause =>
              -- Pause CPU before next instruction to simulate 1MHz, 2MHz or 3.5MHz
              -- operation.
              pc_inc := '0';
              if cpu_pause_shift=1 then
                pause_cycles_counter <= '0'&pause_cycles(8 downto 1);
              elsif cpu_pause_shift=2 then
                pause_cycles_counter <= "00"&pause_cycles(8 downto 2);
              else
                pause_cycles_counter <= pause_cycles;
              end if;
              state <= ProcessorPausing;
            when ProcessorPausing =>
              pc_inc := '0';
              if pause_cycles_counter /=0 then
                pause_cycles_counter <= pause_cycles_counter - 1;
              else
                state <= InstructionFetch;
              end if;
            when ProcessorHold =>
              -- Hold CPU while blocked by monitor

              -- Automatically resume CPU when monitor memory request/single stepping
              -- pause is done, unless something else needs to be done.
              state <= normal_fetch_state;
              if debugging_single_stepping='1' then
                if debug_count = 5 then
                  debug_count <= 0;
                  report "DEBUGGING SINGLE STEP: Releasing CPU for an instruction." severity note;
                  state <= InstructionFetch;
                else
                  debug_count <= debug_count + 1;
                end if;
              end if;
              
              if monitor_mem_attention_request_drive='1' then
                -- Memory access by serial monitor.
                if monitor_mem_address_drive(27 downto 16) = x"777" then
                  -- M777xxxx in serial monitor reads memory from CPU's perspective
                  memory_access_resolve_address := '1';
                else
                  memory_access_resolve_address := '0';
                end if;
                if monitor_mem_write_drive='1' then
                  -- Write to specified long address (or short if address is $777xxxx)
                  memory_access_address := unsigned(monitor_mem_address_drive);
                  memory_access_write := '1';
                  memory_access_wdata := monitor_mem_wdata_drive;
                  state <= MonitorMemoryAccess;
                -- Don't allow a read to occur while a write is completing.
                elsif monitor_mem_read='1' then
                  -- and optionally set PC
                  if monitor_mem_setpc='1' then
                    -- Abort any instruction currently being executed.
                    -- Then set PC from InstructionWait state to make sure that we
                    -- don't write it here, only for it to get stomped.
                    state <= MonitorMemoryAccess;
                    report "Setting PC (monitor)";
                    reg_pc <= unsigned(monitor_mem_address_drive(15 downto 0));
                    mem_reading <= '0';
                  else
                    -- otherwise just read from memory
                    memory_access_address := unsigned(monitor_mem_address_drive);
                    memory_access_read := '1';
                    -- Read from specified long address
                    monitor_mem_reading <= '1';
                    mem_reading <= '1';
                    proceed <= '0';
                    state <= MonitorMemoryAccess;
                  end if;
                end if;
              else
                -- Don't do anything while the processor is held.
                memory_access_write := '0';
                memory_access_read := '0';
              end if;
            when MonitorMemoryAccess =>
              monitor_mem_rdata <= memory_read_value;
              if monitor_mem_attention_request_drive='1' then 
                monitor_mem_attention_granted <= '1';
              else
                monitor_mem_attention_granted <= '0';
                state <= ProcessorHold;
              end if;
            when TrapToHypervisor =>
              -- Save all registers
              hyper_iomode(1 downto 0) <= unsigned(viciii_iomode);
              hyper_dmagic_list_addr <= reg_dmagic_addr;
              hyper_dmagic_src_mb <= reg_dmagic_src_mb;
              hyper_dmagic_dst_mb <= reg_dmagic_dst_mb;
              hyper_a <= reg_a; hyper_x <= reg_x;
              hyper_y <= reg_y; hyper_z <= reg_z;
              hyper_b <= reg_b; hyper_sp <= reg_sp;
              hyper_sph <= reg_sph; hyper_pc <= reg_pc;
              hyper_mb_low <= reg_mb_low; hyper_mb_high <= reg_mb_high;
              hyper_map_low <= reg_map_low; hyper_map_high <= reg_map_high;
              hyper_map_offset_low <= reg_offset_low;
              hyper_map_offset_high <= reg_offset_high;
              hyper_port_00 <= cpuport_ddr; hyper_port_01 <= cpuport_value;
              hyper_p <= unsigned(virtual_reg_p);
              -- Set registers for hypervisor mode.

              -- Full hardware features available on entry to hypervisor
              iomode_set <= "11";
              iomode_set_toggle <= not iomode_set_toggle_internal;
              iomode_set_toggle_internal <= not iomode_set_toggle_internal;

              -- Hypervisor lives in a 16KB memory that gets mapped at $8000-$BFFF.
              -- (it can of course map other stuff if it wants).
              -- stack and ZP are mapped to this space also (the memory is writable,
              -- but only from hypervisor mode).
              -- (preserve A,X,Y,Z and lower 32KB mapping for convenience for
              --  trap calls).
              -- 8-bit stack @ $BE00
              reg_sp <= x"ff"; reg_sph <= x"BE"; flag_e <= '1'; flag_i<='1';
              -- ZP at $BF00-$BFFF
              reg_b <= x"BF";
              -- PC at $8000 (hypervisor code spans $8000 - $BFFF)
              report "Setting PC to $80xx/8100 on hypervisor entry";
              reg_pc <= x"8000";
              -- Actually, set PC based on address written to, so that
              -- writing to the 64 hypervisor registers act similar to the INT
              -- instruction on x86 machines.
              reg_pc(8 downto 2) <= hypervisor_trap_port;              
              -- map hypervisor ROM in upper moby
              -- ROM is at $FFF8000-$FFFBFFF
              reg_map_high <= "0011";
              reg_offset_high <= x"f00"; -- add $F0000
              reg_mb_high <= x"ff";
              -- IO, but no C64 ROMS
              cpuport_ddr <= x"3f"; cpuport_value <= x"35";

              -- enable hypervisor mode flag
              hypervisor_mode <= '1';
              -- start fetching next instruction
              state <= normal_fetch_state;
            when ReturnFromHypervisor =>
              -- Copy all registers back into place,
              iomode_set <= std_logic_vector(hyper_iomode(1 downto 0));
              iomode_set_toggle <= not iomode_set_toggle_internal;
              iomode_set_toggle_internal <= not iomode_set_toggle_internal;
              reg_dmagic_addr <= hyper_dmagic_list_addr;
              reg_dmagic_src_mb <= hyper_dmagic_src_mb;
              reg_dmagic_dst_mb <= hyper_dmagic_dst_mb;
              reg_a <= hyper_a; reg_x <= hyper_x; reg_y <= hyper_y;
              reg_z <= hyper_z; reg_b <= hyper_b; reg_sp <= hyper_sp;
              reg_sph <= hyper_sph; reg_pc <= hyper_pc;
              report "Setting PC on hypervisor exit";
              reg_mb_low <= hyper_mb_low; reg_mb_high <= hyper_mb_high;
              reg_map_low <= hyper_map_low; reg_map_high <= hyper_map_high;
              reg_offset_low <= hyper_map_offset_low;
              reg_offset_high <= hyper_map_offset_high;
              cpuport_ddr <= hyper_port_00; cpuport_value <= hyper_port_01;
              flag_n <= hyper_p(7); flag_v <= hyper_p(6);
              flag_e <= hyper_p(5); flag_d <= hyper_p(3);
              flag_i <= hyper_p(2); flag_z <= hyper_p(1);
              flag_c <= hyper_p(0);
              
              -- clear hypervisor mode flag
              hypervisor_mode <= '0';
              -- start fetching next instruction
              state <= normal_fetch_state;
            when DMAgicTrigger =>
              -- Clear DMA pending flag
              report "DMAgic: Processing DMA request";
              dma_pending <= '0';
              -- Begin to load DMA registers
              -- We load them from the 20 bit address stored $D700 - $D702
              -- plus the 8-bit MB value in $D704
              memory_access_address := reg_dmagic_addr;
              reg_dmagic_addr <= reg_dmagic_addr + 1;
              memory_access_resolve_address := '0';
              memory_access_read := '1';
              state <= DMAgicReadList;
              dmagic_list_counter <= 0;
            when DMAgicReadList =>
              report "DMAgic: Reading DMA list (setting dmagic_cmd to $" & to_hstring(dmagic_count(7 downto 0))
                &", memory_read_value = $"&to_hstring(memory_read_value)&")";
              -- ask for next byte from DMA list
              memory_access_address := reg_dmagic_addr;
              memory_access_resolve_address := '0';
              memory_access_read := '1';
              -- shift read byte into DMA registers and shift everything around
              dmagic_modulo(15 downto 8) <= memory_read_value;
              dmagic_modulo(7 downto 0) <= dmagic_modulo(15 downto 8);
              dmagic_dest_bank_temp <= dmagic_modulo(7 downto 0);
              dmagic_dest_addr(15 downto 8) <= dmagic_dest_bank_temp;
              dmagic_dest_addr(7 downto 0) <= dmagic_dest_addr(15 downto 8);
              dmagic_src_bank_temp <= dmagic_dest_addr(7 downto 0);
              dmagic_src_addr(15 downto 8) <= dmagic_src_bank_temp;
              dmagic_src_addr(7 downto 0) <= dmagic_src_addr(15 downto 8);
              dmagic_count(15 downto 8) <= dmagic_src_addr(7 downto 0);
              dmagic_count(7 downto 0) <= dmagic_count(15 downto 8);
              dmagic_cmd <= dmagic_count(7 downto 0);
              if dmagic_list_counter = 10 then
                state <= DMAgicGetReady;
              else
                dmagic_list_counter <= dmagic_list_counter + 1;
                reg_dmagic_addr <= reg_dmagic_addr + 1;
              end if;
              report "DMAgic: Reading DMA list (end of cycle)";
            when DMAgicGetReady =>
              report "DMAgic: got list: cmd=$"
                & to_hstring(dmagic_cmd)
                & "src=$"
                & to_hstring(dmagic_src_addr(15 downto 0))
                & "dest=$" & to_hstring(dmagic_dest_addr(15 downto 0));
              dmagic_src_addr(27 downto 20) <= reg_dmagic_src_mb;
              dmagic_src_addr(19 downto 16) <= dmagic_src_bank_temp(3 downto 0);
              dmagic_dest_addr(27 downto 20) <= reg_dmagic_dst_mb;
              dmagic_dest_addr(19 downto 16) <= dmagic_dest_bank_temp(3 downto 0);
              dmagic_src_io <= dmagic_src_bank_temp(7);
              dmagic_src_direction <= dmagic_src_bank_temp(6);
              dmagic_src_modulo <= dmagic_src_bank_temp(5);
              dmagic_src_hold <= dmagic_src_bank_temp(4);
              dmagic_dest_io <= dmagic_dest_bank_temp(7);
              dmagic_dest_direction <= dmagic_dest_bank_temp(6);
              dmagic_dest_modulo <= dmagic_dest_bank_temp(5);
              dmagic_dest_hold <= dmagic_dest_bank_temp(4);
              case dmagic_cmd(1 downto 0) is                
                when "11" => -- fill
                  state <= DMAgicFill;
                when "00" => -- copy
                  dmagic_first_read <= '1';
                  state <= DMagicCopyRead;
                when others =>
                  -- swap and mix not yet implemented
                  state <= normal_fetch_state;
              end case;
            when DMAgicFill =>
              -- Fill memory at dmagic_dest_addr with dmagic_src_addr(7 downto
              -- 0)

              -- Do memory write
              memory_access_write := '1';
              memory_access_wdata := dmagic_src_addr(7 downto 0);
              memory_access_resolve_address := '0';
              memory_access_address := dmagic_dest_addr;

              -- redirect memory write to IO block if required
              if dmagic_dest_addr(15 downto 12) = x"d" and dmagic_dest_io='1' then
                memory_access_address(27 downto 12) := x"FFD3";
              end if;
              
              -- Update address and check for end of job.
              -- XXX Ignores modulus, whose behaviour is insufficiently defined
              -- in the C65 specifications document
              if dmagic_dest_hold='0' then
                if dmagic_dest_direction='0' then
                  dmagic_dest_addr <= dmagic_dest_addr + 1;
                else
                  dmagic_dest_addr <= dmagic_dest_addr - 1;
                end if;
              end if;
              -- XXX we compare count with 1 before decrementing.
              -- This means a count of zero is really a count of 64KB, which is
              -- probably different to on a real C65, but this is untested.
              if dmagic_count = 1 then
                -- DMA done
                report "DMAgic: DMA complete";
                if dmagic_cmd(2) = '0' then
                  -- Last DMA job in chain, go back to executing instructions
                  state <= normal_fetch_state;
                else
                  -- Chain to next DMA job
                  state <= DMAgicTrigger;
                end if;
              else
                dmagic_count <= dmagic_count - 1;
              end if;
            when DMAgicCopyRead =>
              -- We can't write a value the immediate cycle we read it, so
              -- we need to read one byte ahead, so that we have a 1 byte buffer
              -- and can read or write on every cycle.
              -- so we need to read the first byte now.

              -- Do memory read
              memory_access_read := '1';
              memory_access_resolve_address := '0';
              memory_access_address := dmagic_src_addr;

              -- redirect memory write to IO block if required
              if dmagic_src_addr(15 downto 12) = x"d" and dmagic_src_io='1' then
                memory_access_address(27 downto 12) := x"FFD3";
              end if;
              
              -- Update source address.
              -- XXX Ignores modulus, whose behaviour is insufficiently defined
              -- in the C65 specifications document
              if dmagic_src_hold='0' then
                if dmagic_src_direction='0' then
                  dmagic_src_addr <= dmagic_src_addr + 1;
                else
                  dmagic_src_addr <= dmagic_src_addr - 1;
                end if;
              end if;
              state <= DMAgicCopyWrite;
            when DMAgicCopyWrite =>
              -- Remember value just read
              dmagic_first_read <= '0';
              reg_t <= memory_read_value;

              state <= DMAgicCopyRead;

              if dmagic_first_read = '0' then
                -- Do memory write
                memory_access_write := '1';
                memory_access_wdata := reg_t;
                memory_access_resolve_address := '0';
                memory_access_address := dmagic_dest_addr;

                -- redirect memory write to IO block if required
                if dmagic_dest_addr(15 downto 12) = x"d" and dmagic_dest_io='1' then
                  memory_access_address(27 downto 12) := x"FFD3";
                end if;
              
                -- Update address and check for end of job.
                -- XXX Ignores modulus, whose behaviour is insufficiently defined
                -- in the C65 specifications document
                if dmagic_dest_hold='0' then
                  if dmagic_dest_direction='0' then
                    dmagic_dest_addr <= dmagic_dest_addr + 1;
                  else
                    dmagic_dest_addr <= dmagic_dest_addr - 1;
                  end if;
                end if;
                -- XXX we compare count with 1 before decrementing.
                -- This means a count of zero is really a count of 64KB, which is
                -- probably different to on a real C65, but this is untested.
                if dmagic_count = 1 then
                  -- DMA done
                  report "DMAgic: DMA complete";
                  if dmagic_cmd(2) = '0' then
                    -- Last DMA job in chain, go back to executing instructions
                    state <= normal_fetch_state;
                  else
                    -- Chain to next DMA job
                    state <= DMAgicTrigger;
                  end if;
                else
                  dmagic_count <= dmagic_count - 1;
                end if;
              end if;
            when InstructionWait =>
              state <= InstructionFetch;
            when InstructionFetch =>
              if (hypervisor_mode='0' or irq_hypervisor(0)='0')    -- JBM
                and ((irq_pending='1' and flag_i='0') or nmi_pending='1') then
                -- An interrupt has occurred
                state <= Interrupt;
                -- Make sure reg_instruction /= I_BRK, so that B flag is not
                -- erroneously set.
                reg_instruction <= I_SEI;
              elsif (hyper_trap_pending = '1' and hypervisor_mode='0') then
                -- Trap to hypervisor
                hyper_trap_pending <= '0';
                state <= TrapToHypervisor;
                -- Trap #66 ($42) = RESTORE key double-tap
                hypervisor_trap_port <= "1000010";                     
              else
                -- Normal instruction execution
                state <= InstructionDecode;
                pc_inc := '1';
              end if;
            when InstructionDecode =>
              -- Show previous instruction
              disassemble_last_instruction;
              -- Start recording this instruction
              last_instruction_pc <= reg_pc - 1;
              last_opcode <= memory_read_value;
              last_bytecount <= 1;
 
              -- Prepare microcode vector in case we need it next cycles
              reg_microcode <=
                microcode_lut(instruction_lut(to_integer(emu6502&memory_read_value)));
              reg_addressingmode <= mode_lut(to_integer(emu6502&memory_read_value));
              reg_instruction <= instruction_lut(to_integer(emu6502&memory_read_value));
              
              -- 4502 doesn't allow interrupts immediately following a
              -- single-cycle instruction
              if (hypervisor_mode='0' or irq_hypervisor(1)='0') and (    -- JBM
                (no_interrupt = '0')
                and ((irq_pending='1' and flag_i='0') or nmi_pending='1')) then
                -- An interrupt has occurred
                report "Interrupt detected, decrementing PC";
                state <= Interrupt;
                reg_pc <= reg_pc - 1;
              else
                reg_opcode <= memory_read_value;
                -- Present instruction to serial monitor;
                monitor_opcode <= memory_read_value;
                monitor_ibytes <= "0000";
                monitor_instructionpc <= reg_pc - 1;              
              
                -- Always read the next instruction byte after reading opcode
                -- (this means we can't interrupt the CPU in between single-cycle
                -- instructions -- this is actually correct behaviour for the 4502)
                pc_inc := '1';

                report "Executing instruction " & instruction'image(instruction_lut(to_integer(emu6502&memory_read_value)))
                  severity note;                

                -- See if this is a single cycle instruction.
                -- Note that CLI and CLE take 2 cycles so that any
                -- pending interrupt can happen immediately (interrupts cannot
                -- happen immediately after a single cycle instruction, because
                -- interrupts are only checked in InstructionFetch, not
                -- InstructionDecode).
                absolute32_addressing_enabled <= '0';
                flat32_address <= '0';
                flat32_address_prime <= '0';
                
                case memory_read_value is
                  when x"03" => flag_e <= '1'; -- SEE
                  when x"0A" => reg_a <= a_asl; set_nz(a_asl); flag_c <= reg_a(7); -- ASL A
                  when x"0B" => reg_y <= reg_sph; set_nz(reg_sph); -- TSY
                  when x"18" => flag_c <= '0';  -- CLC
                  when x"1A" => reg_a <= a_incremented; set_nz(a_incremented); -- INC A
                  when x"1B" => reg_z <= z_incremented; set_nz(z_incremented); -- INZ
                  when x"2A" => reg_a <= a_rol; set_nz(a_rol); flag_c <= reg_a(7); -- ROL A
                  when x"2B" => reg_sph <= reg_y; -- TYS
                  when x"38" => flag_c <= '1';  -- SEC
                  when x"3A" => reg_a <= a_decremented; set_nz(a_decremented); -- DEC A
                  when x"3B" => reg_z <= z_decremented; set_nz(z_decremented); -- DEZ
                  when x"42" => reg_a <= a_negated; set_nz(a_negated); -- NEG A
                  when x"43" => reg_a <= a_asr; set_nz(a_asr); -- ASR A
                  when x"4A" => reg_a <= a_lsr; set_nz(a_lsr); flag_c <= reg_a(0); -- LSR A
                  when x"4B" => reg_z <= reg_a; set_nz(reg_a); -- TAZ
                  when x"5B" => reg_b <= reg_a; -- TAB
                  when x"6A" => reg_a <= a_ror; set_nz(a_ror); flag_c <= reg_a(0); -- ROR A
                  when x"6B" => reg_a <= reg_z; set_nz(reg_z); -- TZA
                  when x"78" => flag_i <= '1';  -- SEI
                  when x"7B" => reg_a <= reg_b; set_nz(reg_b); -- TBA
                  when x"88" => reg_y <= y_decremented; set_nz(y_decremented); -- DEY
                  when x"8A" => reg_a <= reg_x; set_nz(reg_x); -- TXA
                  when x"98" => reg_a <= reg_y; set_nz(reg_y); -- TYA
                  when x"9A" => reg_sp <= reg_x; -- TXS
                  when x"A8" => reg_y <= reg_a; set_nz(reg_a); -- TAY
                  when x"AA" => reg_x <= reg_a; set_nz(reg_a); -- TAX
                  when x"B8" => flag_v <= '0';  -- CLV
                  when x"BA" => reg_x <= reg_sp; set_nz(reg_sp); -- TSX
                  when x"C8" => reg_y <= y_incremented; set_nz(y_incremented); -- INY
                  when x"CA" => reg_x <= x_decremented; set_nz(x_decremented); -- DEX
                  when x"D8" => flag_d <= '0';  -- CLD
                                flat32_address_prime <= '1';
                                flat32_address <= flat32_address_prime;
                  when x"E8" => reg_x <= x_incremented; set_nz(x_incremented); -- INX
                  when x"EA" => map_interrupt_inhibit <= '0'; -- EOM
                                -- Enable 32-bit pointer for ($nn),Z addressing
                                -- mode
                                absolute32_addressing_enabled <= '1';
                  when x"F8" => flag_d <= '1';  -- SED
                  when others => null;
                end case;
                                 
                -- Preserve absolute32_addressing_enabled value if the current
                -- instruction is ($nn),Z, so that we can use a 32-bit pointer
                -- for that instruction.  Fortunately these all have the same
                -- bottom five bits, being $x2, where x is odd.
                if memory_read_value(4 downto 0) = "10010" then
                  absolute32_addressing_enabled <= absolute32_addressing_enabled;
                end if;
                -- Preset flat32_address value if the current instruction is
                -- JMP, JSR or RTS
                -- This is opcodes JMP absolute ($4C), JMP indirect ($6C),
                -- JMP (absolute,X) ($7C), JSR absolute ($20), JSR (absolute) ($22)
                -- JSR (absolute,X) ($23), RTS ($60), RTS immediate ($62)
                case memory_read_value is
                  when x"20" => flat32_address <= flat32_address;
                  when x"22" => flat32_address <= flat32_address;
                  when x"23" => flat32_address <= flat32_address;
                  when x"4C" => flat32_address <= flat32_address;
                  when x"60" => flat32_address <= flat32_address;
                  when x"62" => flat32_address <= flat32_address;
                  when x"6C" => flat32_address <= flat32_address;
                  when others => null;
                end case;
                
                if op_is_single_cycle(to_integer(emu6502&memory_read_value)) = '0' then
                  if (mode_lut(to_integer(emu6502&memory_read_value)) = M_immnn)
                    or (mode_lut(to_integer(emu6502&memory_read_value)) = M_impl)
                    or (mode_lut(to_integer(emu6502&memory_read_value)) = M_A)
                  then
                    no_interrupt <= '0';
                    if memory_read_value=x"60" then
                      -- Fast-track RTS
                      if flat32_address = '0' then
                        -- Normal 16-bit RTS
                        state <= RTS;
                      else
                        -- 32-bit RTS, including virtual memory address resolution
                        report "Far-RTS";
                        state <= Flat32RTS;
                      end if;
                    elsif memory_read_value=x"40" then
                      -- Fast-track RTI
                      state <= RTI;
                    else
                      report "Skipping straight to microcode interpret from fetch";
                      state <= MicrocodeInterpret;
                    end if;
                  else
                    state <= Cycle2;
                  end if;
                  case mode_lut(to_integer(emu6502&memory_read_value)) is
                    when M_IMPL =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 2,9);
                    when M_nn =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 3,9);
                    when M_immnn =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 2,9);
                    when M_A =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 2,9);
                    when M_nnnn =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 4,9);
                    when M_nnrr =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 4,9);
                    when M_rr =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 3,9);
                    when M_InnY =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 5,9);
                    when M_InnZ =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 5,9);
                    when M_rrrr =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 4,9);
                    when M_nnX =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 3,9);
                    when M_nnnnY =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 4,9);
                    when M_nnnnX =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 4,9);
                    when M_Innnn =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 5,9);
                    when M_InnnnX =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 5,9);
                    when M_InnSPY =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 6,9);
                    when M_nnY =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 3,9);
                    when M_immnnnn =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 7,9);
                    when others =>
                  end case;
                else
                  pause_cycles <= to_unsigned(pause_per_cycle,9);
                  no_interrupt <= '1';
                  -- Allow monitor to trace through single-cycle instructions
                  if monitor_mem_trace_mode='1' or debugging_single_stepping='1' then
                    state <= normal_fetch_state;
                    pc_inc := '0';
                  end if;
                end if;
                
                monitor_instruction <= to_unsigned(instruction'pos(instruction_lut(to_integer(emu6502&memory_read_value))),8);
                is_rmw <= '0'; is_load <= '0'; is_store <= '0';
                rmw_dummy_write_done <= '0';
                case instruction_lut(to_integer(emu6502&memory_read_value)) is
                  -- Note if instruction is RMW
                  when I_INC => is_rmw <= '1';
                  when I_DEC => is_rmw <= '1';
                  when I_ROL => is_rmw <= '1';
                  when I_ROR => is_rmw <= '1';
                  when I_ASL => is_rmw <= '1';
                  when I_ASR => is_rmw <= '1';
                  when I_LSR => is_rmw <= '1';
                  when I_TSB => is_rmw <= '1';
                  when I_TRB => is_rmw <= '1';
                  when I_RMB => is_rmw <= '1';
                  when I_SMB => is_rmw <= '1';
                  -- There are a few 16-bit RMWs as well
                  when I_INW => is_rmw <= '1';
                  when I_DEW => is_rmw <= '1';
                  when I_ASW => is_rmw <= '1';
                  when I_PHW => is_rmw <= '1';
                  when I_ROW => is_rmw <= '1';
                  -- Note if instruction LOADs value from memory
                  when I_BIT => is_load <= '1';
                  when I_AND => is_load <= '1';
                  when I_ORA => is_load <= '1';
                  when I_EOR => is_load <= '1';
                  when I_ADC => is_load <= '1';
                  when I_SBC => is_load <= '1';
                  when I_CMP => is_load <= '1';
                  when I_CPX => is_load <= '1';
                  when I_CPY => is_load <= '1';
                  when I_CPZ => is_load <= '1';
                  when I_LDA => is_load <= '1';
                  when I_LDX => is_load <= '1';
                  when I_LDY => is_load <= '1';
                  when I_LDZ => is_load <= '1';
                  -- Note if instruction is STORE
                  when I_STA => is_store <= '1';
                  when I_STX => is_store <= '1';
                  when I_STY => is_store <= '1';
                  when I_STZ => is_store <= '1';
                                
                  -- Nothing special for other instructions
                  when others => null;
                end case;
              end if;
            when InstructionDecode6502 =>
              -- Show previous instruction
              disassemble_last_instruction;
              -- Start recording this instruction
              last_instruction_pc <= reg_pc - 1;
              last_opcode <= memory_read_value;
              last_bytecount <= 1;

              -- Prepare microcode vector in case we need it next cycles
              reg_microcode <=
                microcode_lut(instruction_lut(to_integer(emu6502&memory_read_value)));
              reg_addressingmode <= mode_lut(to_integer(emu6502&memory_read_value));
              reg_instruction <= instruction_lut(to_integer(emu6502&memory_read_value));
              
              if (hypervisor_mode='0' or irq_hypervisor(2)='0')    -- JBM
                and ((irq_pending='1' and flag_i='0') or nmi_pending='1') then
                -- An interrupt has occurred 
                report "Interrupt detected in 6502 mode, decrementing PC";
                state <= Interrupt;
                reg_pc <= reg_pc - 1;
              else
                reg_opcode <= memory_read_value;
                -- Present instruction to serial monitor;
                monitor_opcode <= memory_read_value;
                monitor_ibytes <= "0000";
                monitor_instructionpc <= reg_pc - 1;              

                -- In 6502 mode, we don't advance the PC 
                pc_inc := '0';
                
                report "Executing instruction " & instruction'image(instruction_lut(to_integer(emu6502&memory_read_value)))
                  severity note;                

                -- See if this is a single cycle instruction in 4502 mode.
                -- We take 2 cycles for these, and allow interrupts following
                -- them, however.
                absolute32_addressing_enabled <= '0';
                flat32_address <= '0';
                flat32_address_prime <= '0';
                
                case memory_read_value is
                  when x"0A" => reg_a <= a_asl; set_nz(a_asl); flag_c <= reg_a(7); -- ASL A
                  when x"18" => flag_c <= '0';  -- CLC
                  when x"2A" => reg_a <= a_rol; set_nz(a_rol); flag_c <= reg_a(7); -- ROL A
                  when x"38" => flag_c <= '1';  -- SEC
                  when x"3A" => reg_a <= a_decremented; set_nz(a_decremented); -- DEC A
                  when x"43" => reg_a <= a_asr; set_nz(a_asr); -- ASR A
                  when x"4A" => reg_a <= a_lsr; set_nz(a_lsr); flag_c <= reg_a(0); -- LSR A
                  when x"5B" => reg_b <= reg_a; -- TAB
                  when x"6A" => reg_a <= a_ror; set_nz(a_ror); flag_c <= reg_a(0); -- ROR A
                  when x"78" => flag_i <= '1';  -- SEI
                  when x"88" => reg_y <= y_decremented; set_nz(y_decremented); -- DEY
                  when x"8A" => reg_a <= reg_x; set_nz(reg_x); -- TXA
                  when x"98" => reg_a <= reg_y; set_nz(reg_y); -- TYA
                  when x"9A" => reg_sp <= reg_x; -- TXS
                  when x"A8" => reg_y <= reg_a; set_nz(reg_a); -- TAY
                  when x"AA" => reg_x <= reg_a; set_nz(reg_a); -- TAX
                  when x"B8" => flag_v <= '0';  -- CLV
                  when x"BA" => reg_x <= reg_sp; set_nz(reg_sp); -- TSX
                  when x"C8" => reg_y <= y_incremented; set_nz(y_incremented); -- INY
                  when x"CA" => reg_x <= x_decremented; set_nz(x_decremented); -- DEX
                  when x"D8" => flag_d <= '0';  -- CLD
                                flat32_address_prime <= '1';
                                flat32_address <= flat32_address_prime;
                  when x"E8" => reg_x <= x_incremented; set_nz(x_incremented); -- INX
                  when x"EA" => map_interrupt_inhibit <= '0'; -- EOM
                                -- Enable 32-bit pointer for ($nn),Z addressing
                                -- mode
                                absolute32_addressing_enabled <= '1';
                  when x"F8" => flag_d <= '1';  -- SED
                  when others => null;
                end case;
                                                 
                if op_is_single_cycle(to_integer(emu6502&memory_read_value)) = '0' then
                  if (mode_lut(to_integer(emu6502&memory_read_value)) = M_immnn)
                    or (mode_lut(to_integer(emu6502&memory_read_value)) = M_impl)
                    or (mode_lut(to_integer(emu6502&memory_read_value)) = M_A)
                  then
                    no_interrupt <= '0';
                    if memory_read_value=x"60" then
                      -- Fast-track RTS
                      if flat32_address = '0' then
                        -- Normal 16-bit RTS
                        state <= RTS;
                      else
                        -- 32-bit RTS, including virtual memory address resolution
                        report "Far-RTS";
                        state <= Flat32RTS;
                      end if;
                    elsif memory_read_value=x"40" then
                      -- Fast-track RTI
                      state <= RTI;
                    else
                      report "Skipping straight to microcode interpret from fetch";
                      state <= MicrocodeInterpret;
                    end if;
                  else
                    state <= Cycle2;
                  end if;
                  case mode_lut(to_integer(emu6502&memory_read_value)) is
                    when M_IMPL =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 2,9);
                    when M_nn =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 3,9);
                    when M_immnn =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 2,9);
                    when M_A =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 2,9);
                    when M_nnnn =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 4,9);
                    when M_nnrr =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 4,9);
                    when M_rr =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 3,9);
                    when M_InnY =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 5,9);
                    when M_InnZ =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 5,9);
                    when M_rrrr =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 4,9);
                    when M_nnX =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 3,9);
                    when M_nnnnY =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 4,9);
                    when M_nnnnX =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 4,9);
                    when M_Innnn =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 5,9);
                    when M_InnnnX =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 5,9);
                    when M_InnSPY =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 6,9);
                    when M_nnY =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 3,9);
                    when M_immnnnn =>
                      pause_cycles <= to_unsigned(pause_per_cycle * 7,9);
                    when others =>
                  end case;
                else
                  pause_cycles <= to_unsigned(pause_per_cycle,9);
                  no_interrupt <= '1';
                  -- Allow monitor to trace through single-cycle instructions
                  if monitor_mem_trace_mode='1' or debugging_single_stepping='1' then
                    state <= normal_fetch_state;
                    pc_inc := '0';
                  end if;
                end if;
                
                monitor_instruction <= to_unsigned(instruction'pos(instruction_lut(to_integer(emu6502&memory_read_value))),8);
                is_rmw <= '0'; is_load <= '0'; is_store <= '0';
                rmw_dummy_write_done <= '0';
                case instruction_lut(to_integer(emu6502&memory_read_value)) is
                  -- Note if instruction is RMW
                  when I_INC => is_rmw <= '1';
                  when I_DEC => is_rmw <= '1';
                  when I_ROL => is_rmw <= '1';
                  when I_ROR => is_rmw <= '1';
                  when I_ASL => is_rmw <= '1';
                  when I_ASR => is_rmw <= '1';
                  when I_LSR => is_rmw <= '1';
                  when I_TSB => is_rmw <= '1';
                  when I_TRB => is_rmw <= '1';
                  when I_RMB => is_rmw <= '1';
                  when I_SMB => is_rmw <= '1';
                  -- There are a few 16-bit RMWs as well
                  when I_INW => is_rmw <= '1';
                  when I_DEW => is_rmw <= '1';
                  when I_ASW => is_rmw <= '1';
                  when I_PHW => is_rmw <= '1';
                  when I_ROW => is_rmw <= '1';
                  -- Note if instruction LOADs value from memory
                  when I_BIT => is_load <= '1';
                  when I_AND => is_load <= '1';
                  when I_ORA => is_load <= '1';
                  when I_EOR => is_load <= '1';
                  when I_ADC => is_load <= '1';
                  when I_SBC => is_load <= '1';
                  when I_CMP => is_load <= '1';
                  when I_CPX => is_load <= '1';
                  when I_CPY => is_load <= '1';
                  when I_CPZ => is_load <= '1';
                  when I_LDA => is_load <= '1';
                  when I_LDX => is_load <= '1';
                  when I_LDY => is_load <= '1';
                  when I_LDZ => is_load <= '1';
                  -- Note if instruction is STORE
                  when I_STA => is_store <= '1';
                  when I_STX => is_store <= '1';
                  when I_STY => is_store <= '1';
                  when I_STZ => is_store <= '1';

                  -- 6502 illegal opcodes
                                
                                
                  -- Nothing special for other instructions
                  when others => null;
                end case;
              end if;
            when Cycle2 =>
              -- To improve timing we copy first argument of instruction, and
              -- proceed to read the next byte.
              -- But all processing is done in the next cycle.
              -- XXX - This is at the cost of 1 cycle on most 2 or 3 byte, which
              -- is really bad. ZP is practically pointless as a result.  See below
              -- for optimising this away for most instructions.

              reg_pc_jsr <= reg_pc;
              
              -- Store and announce arg1
              last_byte2 <= memory_read_value;
              last_bytecount <= 2;
              monitor_arg1 <= memory_read_value;
              monitor_ibytes(1) <= '1';
              reg_arg1 <= memory_read_value;
              reg_addr(7 downto 0) <= memory_read_value;
              
              -- Work out relevant bit mask for RMB/SMB
              case reg_opcode(6 downto 4) is
                when "000" => rmb_mask <= "11111110"; smb_mask <= "00000001";
                when "001" => rmb_mask <= "11111101"; smb_mask <= "00000010";
                when "010" => rmb_mask <= "11111011"; smb_mask <= "00000100";
                when "011" => rmb_mask <= "11110111"; smb_mask <= "00001000";
                when "100" => rmb_mask <= "11101111"; smb_mask <= "00010000";
                when "101" => rmb_mask <= "11011111"; smb_mask <= "00100000";
                when "110" => rmb_mask <= "10111111"; smb_mask <= "01000000";
                when "111" => rmb_mask <= "01111111"; smb_mask <= "10000000";
                when others => null;
              end case;
              
              -- Process instruction next cycle
              if flat32_address='1' and flat32_enabled='1' then
                -- 32bit absolute jsr/jmp
                report "Far-JSR/JMP - got 2nd arg";
                state <= Flat32Got2ndArgument;
              else
                -- normal instruction
                state <= Cycle3;
              end if;

              -- Fetch arg2 if required (only for 3 byte addressing modes)
              -- Also begin processing operations that don't need any more data
              -- to start, so that we don't waste a cycle on every 2-byte instruction.
              -- (We have this block last, so that it can override the destination
              -- state).
              case reg_addressingmode is
                when M_impl => null;
                when M_InnX => null;
                when M_nn =>
                  temp_addr := reg_b & memory_read_value;
                  reg_addr <= temp_addr;
                  if is_load='1' or is_rmw='1' then
                    state <= LoadTarget;
                  else
                    -- (reading next instruction argument byte as default action)
                    state <= MicrocodeInterpret;
                  end if;
                when M_immnn => null;
                                -- handled in MicrocodeInterpret
                when M_A => null;
                            -- handled in MicrocodeInterpret
                when M_rr =>
                  -- XXX For non-taken branches, we can just proceed directly to fetching
                  -- the next instruction: this makes non-taken branches need only
                  -- 2 cycles, like on real 6502.  If a branch is taken, then it
                  -- takes one extra cycle (see Cycle3)
                  if (reg_instruction=I_BEQ and flag_z='0') or
                    (reg_instruction=I_BNE and flag_z='1') or
                    (reg_instruction=I_BCS and flag_c='0') or
                    (reg_instruction=I_BCC and flag_c='1') or
                    (reg_instruction=I_BVS and flag_v='0') or
                    (reg_instruction=I_BVC and flag_v='1') or
                    (reg_instruction=I_BMI and flag_n='0') or
                    (reg_instruction=I_BPL and flag_n='1') then
                    state <= fast_fetch_state;
                    if fast_fetch_state = InstructionDecode then pc_inc := '1'; end if;
                  end if;
                when M_InnY => null;
                when M_InnZ => null;
                when M_nnX =>
                  temp_addr := reg_b & (memory_read_value + reg_X);
                  reg_addr <= temp_addr;
                  if is_load='1' or is_rmw='1' then
                    state <= LoadTarget;
                  else
                    -- (reading next instruction argument byte as default action)
                    state <= MicrocodeInterpret;
                  end if;
                when M_InnSPY => null;
                when M_nnY =>
                  temp_addr := reg_b & (memory_read_value + reg_Y);
                  reg_addr <= temp_addr;
                  if is_load='1' or is_rmw='1' then
                    state <= LoadTarget;
                  else
                    -- (reading next instruction argument byte as default action)
                    state <= MicrocodeInterpret;
                  end if;
                when others =>
                  pc_inc := '1';
                  null;
              end case;              
            when Flat32Got2ndArgument =>
              -- Flat 32bit JMP/JSR instructions require 4 address bytes.
              -- At this point, we have the 2nd byte.  If the addressing mode
              -- is absolute, then we can keep the 2 bytes already read, and just
              -- read the last two address bytes.  If indirect, or indirectX, then
              -- we need to begin reading from the 1st byte at the prescribed
              -- address. IndirectX mode for flat 32 bit addressing will
              -- multiply X by 4, so that it allows referencing of 256 unique
              -- non-overlapping addresses, unlike JSR/JMP ($nnnn,X) on the
              -- 65CE02/4502 where X is not scaled, resulting in only 128
              -- non-overlapping addresses.
              if reg_addressingmode = M_nnnn then
                -- Store and read last two bytes
                reg_addr32(15 downto 8) <= memory_read_value;
                reg_addr32(7 downto 0) <= reg_addr(7 downto 0);
                pc_inc := '1';
                state <= Flat32Byte3;
              elsif reg_addressingmode = M_Innnn then
                -- Dereference, and read all four bytes
                reg_addr(15 downto 8) <= memory_read_value;
                state <= Flat32Dereference0;
              elsif reg_addressingmode = M_InnnnX then
                -- Add (X*4), dereference, and read all four bytes
                reg_addr(15 downto 2) <= (memory_read_value & reg_addr(7 downto 2))
                                         + to_integer(reg_x);
                state <= Flat32Dereference1;
              else
                -- unknown mode
                state <= normal_fetch_state;
              end if;
            when Flat32Byte3 =>
              pc_inc := '1';
              reg_addr32(23 downto 16) <= memory_read_value;
              state <= Flat32Byte4;              
            when Flat32Byte4 =>
              pc_inc := '1';
              reg_addr32(31 downto 24) <= memory_read_value;
              if (reg_instruction = I_JMP) then
                state <= Flat32Translate;
              else
                state <= Flat32SaveAddress;
              end if;
            when Flat32SaveAddress =>
              -- Convert address back to virtual memory form, so that RTS page-fault
              -- and reload the page if necessary.
              -- We do this easily by just remembering the page number when we
              -- far JMP/JSR somewhere (or when the hypervisor sets it during a
              -- page fault).
              -- This also means that we can distinguish between physical pages
              -- and virtual addressed pages.
              reg_addr32save(31 downto 14) <= reg_pagenumber;
              reg_addr32save(13 downto 0) <= reg_pc(13 downto 0);
              pc_inc := '0';
              stack_push := '1';
              memory_access_wdata := reg_pagenumber(17 downto 10);
              state <= Flat32SaveAddress2;
            when Flat32SaveAddress2 =>
              pc_inc := '0';
              stack_push := '1';
              memory_access_wdata := reg_addr32save(23 downto 16);
              state <= Flat32SaveAddress3;
            when Flat32SaveAddress3 =>
              pc_inc := '0';
              stack_push := '1';
              memory_access_wdata := reg_addr32save(15 downto 8);
              state <= Flat32SaveAddress4;
            when Flat32SaveAddress4 =>
              pc_inc := '0';
              stack_push := '1';
              memory_access_wdata := reg_addr32save(7 downto 0);
              state <= Flat32Translate;
            when Flat32RTS =>
              -- Pull 32-bit address off the stack.
              -- To save CPU complexity here, we will require the stack to have
              -- the values LSB first, and then use the Flat32Dereference sequence
              -- to pull the values in.
              pc_inc := '0';
              reg_addr <= ((reg_sph&reg_sp)+1);              
              reg_sp <= reg_sp + 4;
              if flag_e='0' and reg_sp(7 downto 2)="111111" then
                reg_sph <= reg_sph + 1;
              end if;
              state <= Flat32Dereference0;
            when Flat32Dereference0 =>
              report "Far return: pulling return address from stack at $"
                & to_hstring(reg_addr);
              pc_inc := '0';
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';                
              reg_addr <= reg_addr + 1;
              state <= Flat32Dereference1;
            when Flat32Dereference1 =>
              pc_inc := '0';
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';                
              reg_addr <= reg_addr + 1;
              reg_addr32(7 downto 0) <= memory_read_value;
              state <= Flat32Dereference2;
            when Flat32Dereference2 =>
              pc_inc := '0';
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';                
              reg_addr <= reg_addr + 1;
              reg_addr32(15 downto 8) <= memory_read_value;
              state <= Flat32Dereference3;
            when Flat32Dereference3 =>
              pc_inc := '0';
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';                
              reg_addr <= reg_addr + 1;
              reg_addr32(23 downto 16) <= memory_read_value;
              state <= Flat32Dereference4;
            when Flat32Dereference4 =>
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';                
              reg_addr32(31 downto 24) <= memory_read_value;
              state <= Flat32Translate;
            when Flat32Translate =>
              -- We have the 32-bit address for a far JMP or JSR.
              -- See if this 16KB page is loaded anywhere, and if so,
              -- map it in and jump there.  Else trap to hypervisor so that it
              -- can be mapped.
              -- We only allow a very few pages of VM to be loaded at a time.
              -- VM addresses are indicated by bit 31 being set.  The bottom 14
              -- bits are within a page, so the page number is indicated by bits
              -- (30 downto 14) = 17 bits. How annoying. So for now we will allow
              -- only 1GB of virtual address space, and look at bits 29 downto
              -- 14.
              -- If bit31 is clear, then we assume it is direct addressed.

              -- Remember page number for far RTS
              reg_pagenumber <= reg_addr32(31 downto 14);

              report "Far translate: input address = $" & to_hstring(reg_addr32);
              
              pc_inc := '0';
              state <= Flat32Dispatch;
              if (reg_addr32(31)='0') then
                -- Not virtal address, so map and jump
                report "Far-JMP/JSR: Long address is physical, so not translating.";
                null;
              else
                -- Is virtual address, so see if it is in the page table.
                report "Far JMP/JSR: Long address is virtual, so translate it";
                state <= Flat32Dispatch;
                if reg_addr32(29 downto 14) = reg_page0_logical then
                  report "Far JMP/JSR: $" & to_hstring(reg_addr32)
                    & " matches reg_page0_logical ( = page $"
                    & to_hstring(reg_page0_logical)
                    & "), so translating to physical page $"
                    & to_hstring(reg_page0_physical);
                  reg_addr32(29 downto 14) <= reg_page0_physical;
                  reg_addr32(31 downto 30) <= "00";
                  reg_pageactive <= '1';
                  reg_pageid <= "00";
                elsif reg_addr32(29 downto 14) = reg_page1_logical then
                  reg_addr32(29 downto 14) <= reg_page1_physical;
                  reg_addr32(31 downto 30) <= "00";
                  reg_pageactive <= '1';
                  reg_pageid <= "01";
                elsif reg_addr32(29 downto 14) = reg_page2_logical then
                  reg_addr32(29 downto 14) <= reg_page2_physical;
                  reg_addr32(31 downto 30) <= "00";
                  reg_pageactive <= '1';
                  reg_pageid <= "10";
                elsif reg_addr32(29 downto 14) = reg_page3_logical then
                  reg_addr32(29 downto 14) <= reg_page3_physical;
                  reg_addr32(31 downto 30) <= "00";
                  reg_pageactive <= '1';
                  reg_pageid <= "11";
                else
                  -- Page fault!
                  report "Far-JMP/JSR/RTS: Page fault! Trapping to hypervisor";
                  report "Request is for virtual address $" & to_hstring(reg_addr32);
                  state <= TrapToHypervisor;
                  -- Trap #65 ($41) = Page fault.
                  hypervisor_trap_port <= "1000001";
                end if;
              end if;
            when Flat32Dispatch =>
              report "Far dispatch: physical address is $" & to_hstring(reg_addr32)
                & " + $4000";
              -- MAP the appropriate 16KB block in to $4000-$7FFF,
              -- then set PC to $4000 + (reg_addr32 & #$3FFF).
              -- NOTE: To avoid complexity in the CPU, the $4000 offset is NOT
              -- applied to the MAPping.  It is the hypervisor's job to
              -- subtract $4000 from the address before storing in reg_pageX_physical
              pc_inc := '0';
              reg_pc(15 downto 14) <= "01";
              reg_pc(13 downto 0) <= reg_addr32(13 downto 0);
              -- Offsets are x 256 bytes.  16KB = 64 x 256 bytes, so the bottom
              -- six bits of the offset will always be zero.
              reg_offset_low(5 downto 0) <= "000000";
              -- Then the upper 6 bits will be bits (19 downto 14) of reg_addr32
              reg_offset_low(11 downto 6) <= reg_addr32(19 downto 14);
              -- Finally, set the upper address bits into the MB register for
              -- the lower map.
              reg_mb_low <= reg_addr32(27 downto 20);
              -- MAP upper 16KB of lower 32KB of address space
              reg_map_low <= "1100";
              -- Now we can start fetching the instruction.
              state <= normal_fetch_state;
            when Cycle3 =>
              -- Show serial monitor what we are doing.
              if (reg_addressingmode /= M_A) then
                monitor_arg1 <= reg_arg1;
                monitor_ibytes(1) <= '1';
              else
                -- For RTS we use arg1 for the optional immediate argument.
                -- So for implied mode, we set this to zero to provide the
                -- normal behaviour.
                monitor_arg1 <= x"00";
              end if;

              if reg_instruction = I_RTS or reg_instruction = I_RTI then
                -- Special case RTS and RTI so that we don't waste clock cycles
                if reg_instruction = I_RTI then
                  state <= RTI;
                else
                  state <= RTS1;
                end if;
                -- Read first byte from stack
                stack_pop := '1';
              else
                case reg_addressingmode is
                  when M_impl =>  -- Handled in MicrocodeInterpret
                  when M_A =>     -- Handled in MicrocodeInterpret
                  when M_InnX =>                    
                    temp_addr := reg_b & (reg_arg1+reg_X);
                    reg_addr <= temp_addr + 1;
                    memory_access_read := '1';
                    memory_access_address := x"000"&temp_addr;
                    memory_access_resolve_address := '1';
                    state <= InnXReadVectorLow;
                  when M_nn =>
                    temp_addr := reg_b & reg_arg1;
                    reg_addr <= temp_addr;
                    if is_load='1' or is_rmw='1' then
                      state <= LoadTarget;
                    else
                      -- (reading next instruction argument byte as default action)
                      state <= MicrocodeInterpret;
                    end if;
                  when M_immnn => -- Handled in MicrocodeInterpret
                  when M_nnnn =>
                    last_byte3 <= memory_read_value;
                    last_bytecount <= 3;
                    monitor_arg2 <= memory_read_value;
                    monitor_ibytes(0) <= '1';

                    reg_addr(15 downto 8) <= memory_read_value;

                    -- If it is a branch, write the low bits of the programme
                    -- counter now.  We will read the 2nd argument next cycle
                    if reg_instruction = I_JSR or reg_instruction = I_BSR then
                      memory_access_read := '0';
                      memory_access_write := '1';
                      memory_access_address := x"000"&reg_sph&reg_sp;
                      memory_access_resolve_address := '1';
                      memory_access_wdata := reg_pc_jsr(15 downto 8);
                      dec_sp := '1';
                      state <= CallSubroutine;
                    else
                      if is_load='1' or is_rmw='1' then
                        state <= LoadTarget;
                      else
                        -- (reading next instruction argument byte as default action)
                        state <= MicrocodeInterpret;
                      end if;
                    end if;
                  when M_nnrr =>
                    last_byte3 <= memory_read_value;
                    last_bytecount <= 3;
                    monitor_arg2 <= memory_read_value;
                    monitor_ibytes(0) <= '1';

                    reg_t <= memory_read_value;
                    memory_access_read := '1';
                    memory_access_address := x"000"&reg_b&reg_arg1;
                    memory_access_resolve_address := '1';
                    state <= ZPRelReadZP;
                  when M_InnY =>
                    temp_addr := reg_b&reg_arg1;
                    memory_access_read := '1';
                    memory_access_address := x"000"&temp_addr;
                    memory_access_resolve_address := '1';
                    reg_addr <= temp_addr + 1;
                    state <= InnYReadVectorLow;
                  when M_InnZ =>
                    temp_addr := reg_b&reg_arg1;
                    memory_access_read := '1';
                    memory_access_address := x"000"&temp_addr;
                    memory_access_resolve_address := '1';
                    reg_addr <= temp_addr + 1;
                    state <= InnZReadVectorLow;
                  when M_rr =>
                    if (reg_instruction=I_BRA) or
                      (reg_instruction=I_BSR) or
                      (reg_instruction=I_BEQ and flag_z='1') or
                      (reg_instruction=I_BNE and flag_z='0') or
                      (reg_instruction=I_BCS and flag_c='1') or
                      (reg_instruction=I_BCC and flag_c='0') or
                      (reg_instruction=I_BVS and flag_v='1') or
                      (reg_instruction=I_BVC and flag_v='0') or
                      (reg_instruction=I_BMI and flag_n='1') or
                      (reg_instruction=I_BPL and flag_n='0') then
                      -- Branch will be taken. Calculate destination address by
                      -- sign-extending the 8-bit offset.
                      report "Taking 8-bit branch" severity note;
                      temp_addr := reg_pc +
                                   to_integer(reg_arg1(7)&reg_arg1(7)&reg_arg1(7)&reg_arg1(7)&
                                              reg_arg1(7)&reg_arg1(7)&reg_arg1(7)&reg_arg1(7)&
                                              reg_arg1);
                      report "Setting PC (8-bit branch)";
                      reg_pc <= temp_addr;
                      -- Take an extra cycle when taking a branch.  This avoids
                      -- poor timing due to memory-to-memory activity in a
                      -- single cycle.
                      -- XXX consider using the disabled faster (fewer cycles) option
                      -- below, if the timing will tolerate it.  But disabled
                      -- for now, since it increases synthesis time.
                      state <= normal_fetch_state;

                      -- memory_access_read := '1';
                      -- memory_access_address := x"000"&temp_addr;
                      -- memory_access_resolve_address := '1';
                      -- -- Read next instruction now to save a cycle, i.e.,
                      -- -- 8-bit branches will take 2 cycles, whether taken or not.
                      -- state <= fast_fetch_state;
                      -- if fast_fetch_state = InstructionDecode then
                      --  reg_pc <= temp_addr + 1;
                      -- end if;
                    else
                      report "NOT Taking 8-bit branch" severity note;
                      -- Branch will not be taken.
                      -- fetch next instruction now to save a cycle
                      state <= fast_fetch_state;
                      if fast_fetch_state = InstructionDecode then pc_inc := '1'; end if;
                    end if;   
                  when M_rrrr =>
                    last_byte3 <= memory_read_value;
                    last_bytecount <= 3;
                    monitor_arg2 <= memory_read_value;
                    monitor_ibytes(0) <= '1';

                    reg_addr(15 downto 8) <= memory_read_value;
                    -- Now work out if the branch will be taken
                    if (reg_instruction=I_BRA) or
                      (reg_instruction=I_BSR) or
                      (reg_instruction=I_BEQ and flag_z='1') or
                      (reg_instruction=I_BNE and flag_z='0') or
                      (reg_instruction=I_BCS and flag_c='1') or
                      (reg_instruction=I_BCC and flag_c='0') or
                      (reg_instruction=I_BVS and flag_v='1') or
                      (reg_instruction=I_BVC and flag_v='0') or
                      (reg_instruction=I_BMI and flag_n='1') or
                      (reg_instruction=I_BPL and flag_n='0') then
                      -- Branch will be taken, so finish reading address
                      state <= B16TakeBranch;
                    else
                      -- Branch will not be taken.
                      -- Skip second byte and proceed directly to
                      -- fetching next instruction
                      state <= normal_fetch_state;
                    end if;
                  when M_nnX =>
                    temp_addr := reg_b & (reg_arg1 + reg_X);
                    reg_addr <= temp_addr;
                    if is_load='1' or is_rmw='1' then
                      state <= LoadTarget;
                    else
                      -- (reading next instruction argument byte as default action)
                      state <= MicrocodeInterpret;
                    end if;
                  when M_nnY =>
                    temp_addr := reg_b & (reg_arg1 + reg_Y);
                    reg_addr <= temp_addr;
                    if is_load='1' or is_rmw='1' then
                      state <= LoadTarget;
                    else
                      -- (reading next instruction argument byte as default action)
                      state <= MicrocodeInterpret;
                    end if;
                  when M_nnnnY =>
                    last_byte3 <= memory_read_value;
                    last_bytecount <= 3;
                    monitor_arg2 <= memory_read_value;
                    monitor_ibytes(0) <= '1';
                    reg_addr <= x"00"&reg_y + to_integer(memory_read_value&reg_addr(7 downto 0));
                    if is_load='1' or is_rmw='1' then
                      state <= LoadTarget;
                    else
                      -- (reading next instruction argument byte as default action)
                      state <= MicrocodeInterpret;
                    end if;
                  when M_nnnnX =>
                    last_byte3 <= memory_read_value;
                    last_bytecount <= 3;
                    monitor_arg2 <= memory_read_value;
                    monitor_ibytes(0) <= '1';
                    reg_addr <= x"00"&reg_x + to_integer(memory_read_value&reg_addr(7 downto 0));
                    if is_load='1' or is_rmw='1' then
                      state <= LoadTarget;
                    else
                      -- (reading next instruction argument byte as default action)
                      state <= MicrocodeInterpret;
                    end if;
                  when M_Innnn =>
                    -- Only JMP and JSR have this mode
                    last_byte3 <= memory_read_value;
                    last_bytecount <= 3;
                    monitor_arg2 <= memory_read_value;
                    monitor_ibytes(0) <= '1';
                    reg_addr(15 downto 8) <= memory_read_value;
                    state <= JumpDereference;
                  when M_InnnnX =>
                    -- Only JMP and JSR have this mode
                    last_byte3 <= memory_read_value;
                    last_bytecount <= 3;
                    monitor_arg2 <= memory_read_value;
                    monitor_ibytes(0) <= '1';
                    reg_addr <= to_unsigned(
                                  to_integer(memory_read_value&reg_addr(7 downto 0))
                                  + to_integer(reg_x),16);
                    state <= JumpDereference;
                  when M_InnSPY =>
                    temp_addr :=  to_unsigned(to_integer(reg_b&reg_arg1)
                                              +to_integer(reg_sph&reg_sp),16);
                    reg_addr <= temp_addr + 1;
                    memory_access_read := '1';
                    memory_access_address := x"000"&temp_addr;
                    memory_access_resolve_address := '1';
                    state <= InnSPYReadVectorLow;
                  when M_immnnnn =>                
                    reg_t <= reg_arg1;
                    reg_t_high <= memory_read_value;
                    state <= PushWordLow;
                end case;
              end if;
            when CallSubroutine =>
              if reg_instruction = I_BSR then
                -- Convert destination address to relative
                reg_addr <= reg_pc + reg_addr - 1;
              end if;
              
              -- Push PCH
              memory_access_read := '0';
              memory_access_write := '1';
              memory_access_address := x"000"&reg_sph&reg_sp;
              memory_access_resolve_address := '1';
              memory_access_wdata := reg_pc_jsr(7 downto 0);
              dec_sp := '1';
              pc_inc := '0';
              state <= CallSubroutine2;
            when CallSubroutine2 =>
              -- Finish determining subroutine address
              pc_inc := '0';

              report "Jumping to $" & to_hstring(reg_addr)
                severity note;
              -- Immediately start reading the next instruction
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';
              if fast_fetch_state = InstructionDecode then
                -- Fast dispatch, so bump PC ready for next cycle
                report "Setting PC in JSR/BSR (fast dispatch)";
                reg_pc <= reg_addr + 1;
              else
                -- Normal dispatch
                report "Setting PC in JSR/BSR (normal dispatch)";
                reg_pc <= reg_addr;
              end if;
              state <= fast_fetch_state;
            when JumpAbsXReadArg2 =>
              last_byte3 <= memory_read_value;
              last_bytecount <= 3;
              monitor_arg2 <= memory_read_value;
              monitor_ibytes(0) <= '1';
              reg_addr <= x"00"&reg_x + to_integer(memory_read_value&reg_addr(7 downto 0));
              state <= MicrocodeInterpret;
            when TakeBranch8 =>
              -- Branch will be taken (for ZP bit fiddle instructions only)
              report "Setting PC: 8-bit branch will be taken";
              reg_pc <= reg_pc +
                          to_integer(reg_t(7)&reg_t(7)&reg_t(7)&reg_t(7)&
                                     reg_t(7)&reg_t(7)&reg_t(7)&reg_t(7)&
                                     reg_t);
              state <= normal_fetch_state;
            when Pull =>
              -- Also used for immediate mode loading
              set_nz(memory_read_value);
              report "pop_a = " & std_logic'image(pop_a) severity note;
              if pop_a='1' then reg_a <= memory_read_value; end if;
              if pop_x='1' then reg_x <= memory_read_value; end if;
              if pop_y='1' then reg_y <= memory_read_value; end if;
              if pop_z='1' then reg_z <= memory_read_value; end if;
              if pop_p='1' then
                load_processor_flags(memory_read_value);
              end if;

              -- ... and fetch next instruction
              state <= fast_fetch_state;
              if fast_fetch_state = InstructionDecode then pc_inc := '1'; end if;
            when B16TakeBranch =>
              report "Setting PC: 16-bit branch will be taken";
              reg_pc <= reg_pc + to_integer(reg_addr) - 1;
              state <= normal_fetch_state;
            when InnXReadVectorLow =>
              reg_addr(7 downto 0) <= memory_read_value;
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';
              state <= InnXReadVectorHigh;
            when InnXReadVectorHigh =>
              reg_addr <=
                to_unsigned(to_integer(memory_read_value&reg_addr(7 downto 0)),16);
              if is_load='1' or is_rmw='1' then
                state <= LoadTarget;
              else
                -- (reading next instruction argument byte as default action)
                state <= MicrocodeInterpret;
              end if;
            when InnSPYReadVectorLow =>
              reg_addr(7 downto 0) <= memory_read_value;
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';
              state <= InnSPYReadVectorHigh;
            when InnSPYReadVectorHigh =>
              reg_addr <=
                to_unsigned(to_integer(memory_read_value&reg_addr(7 downto 0))
                            + to_integer(reg_y),16);
              if is_load='1' or is_rmw='1' then
                state <= LoadTarget;
              else
                -- (reading next instruction argument byte as default action)
                state <= MicrocodeInterpret;
              end if;
            when InnYReadVectorLow =>
              reg_addr(7 downto 0) <= memory_read_value;
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';
              state <= InnYReadVectorHigh;
            when InnYReadVectorHigh =>
              reg_addr <=
                to_unsigned(to_integer(memory_read_value&reg_addr(7 downto 0))
                            + to_integer(reg_y),16);
              if is_load='1' or is_rmw='1' then
                state <= LoadTarget;
              else
                -- (reading next instruction argument byte as default action)
                state <= MicrocodeInterpret;
              end if;
            when InnZReadVectorLow =>
              reg_addr_lsbs(7 downto 0) <= memory_read_value;
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';
              if absolute32_addressing_enabled='1' then
                state <= InnZReadVectorByte2;
                reg_addr <= reg_addr + 1;
              else
                reg_addr(7 downto 0) <= memory_read_value;
                state <= InnZReadVectorHigh;
              end if;
            when InnZReadVectorByte2 =>
              -- Do addition of Z register as we go along, so that we don't have
              -- a 32-bit carry.
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';
              reg_addr <= reg_addr + 1;
              report "ABS32: Adding " & integer'image(to_integer(memory_read_value&reg_addr_lsbs(7 downto 0)) )& " to " & integer'image(to_integer(reg_z));
              
              temp17 :=
                to_unsigned(to_integer(memory_read_value&reg_addr_lsbs(7 downto 0))
                            + to_integer(reg_z),17);
              reg_addr_lsbs <= temp17(15 downto 0);
              pointer_carry <= temp17(16);
              state <= InnZReadVectorByte3;
            when InnZReadVectorByte3 =>
              -- Do addition of Z register as we go along, so that we don't have
              -- a 32-bit carry.
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';
              if pointer_carry='1' then
                temp9 := to_unsigned(to_integer(memory_read_value)+1,9);
              else 
                temp9 := to_unsigned(to_integer(memory_read_value)+0,9);
              end if;
              reg_addr_msbs(7 downto 0) <= temp9(7 downto 0);
              pointer_carry <= temp9(8);
              state <= InnZReadVectorByte4;
            when InnZReadVectorByte4 =>
              -- Do addition of Z register as we go along, so that we don't have
              -- a 32-bit carry.
              if pointer_carry='1' then
                temp9 := to_unsigned(to_integer(memory_read_value)+1,9);
              else 
                temp9 := to_unsigned(to_integer(memory_read_value)+0,9);
              end if;
              reg_addr_msbs(15 downto 8) <= temp9(7 downto 0);
              reg_addr(15 downto 0) <= reg_addr_lsbs;
              report "ABS32: final address is $"
                & to_hstring(temp9(3 downto 0))
                & to_hstring(reg_addr_msbs(7 downto 0))
                & to_hstring(reg_addr_lsbs);
              if is_load='1' or is_rmw='1' then
                state <= LoadTarget;
              else
                -- (reading next instruction argument byte as default action)
                state <= MicrocodeInterpret;
              end if;
            when InnZReadVectorHigh =>
              reg_addr <=
                to_unsigned(to_integer(memory_read_value&reg_addr(7 downto 0))
                            + to_integer(reg_z),16);
              if is_load='1' or is_rmw='1' then
                state <= LoadTarget;
              else
                -- (reading next instruction argument byte as default action)
                state <= MicrocodeInterpret;
              end if;
            when ZPRelReadZP =>
              -- Here we are reading the ZP memory location
              -- Check if the appropriate bit is set/clear
              if memory_read_value(to_integer(reg_opcode(6 downto 4)))
                =reg_opcode(7) then
                -- Take branch, so read next byte with relative offset
                -- (default action is reading next instruction byte, so no need
                -- to do it here).
                state <= TakeBranch8;
              else
                                        -- Don't take branch, so just skip over branch byte
                state <= normal_fetch_state;
              end if;
            when JumpDereference =>
              -- reg_addr holds the address we want to load a 16 bit address
              -- from for a JMP or JSR.
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';
              -- XXX should this only step the bottom 8 bits for ($nn,X)
              -- dereferencing?
              reg_addr(7 downto 0) <= reg_addr(7 downto 0) + 1;
              state <= JumpDereference2;
            when JumpDereference2 =>
              reg_t <= memory_read_value;
              memory_access_read := '1';
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';
              state <= JumpDereference3;
            when JumpDereference3 =>
              -- Finished dereferencing, set PC
              reg_addr <= memory_read_value&reg_t;
              report "Setting PC: Finished dereferencing JMP";
              reg_pc <= memory_read_value&reg_t;
              if reg_instruction=I_JMP then
                state <= normal_fetch_state;
              else
                report "MAP: Doing JSR ($nnnn) to $"&to_hstring(memory_read_value&reg_t);
                memory_access_read := '0';
                memory_access_write := '1';
                memory_access_address := x"000"&reg_sph&reg_sp;
                memory_access_resolve_address := '1';
                memory_access_wdata := reg_pc_jsr(15 downto 8);
                dec_sp := '1';
                state <= CallSubroutine;
              end if;
            when DummyWrite =>
              memory_access_address := x"000"&reg_addr;
              memory_access_resolve_address := '1';
              memory_access_write := '1';
              memory_access_read := '0';
              memory_access_wdata := reg_t_high;
              state <= WriteCommit;
            when WriteCommit =>
              memory_access_write := '1';
              memory_access_address(15 downto 0) := reg_addr;
              memory_access_resolve_address := not absolute32_addressing_enabled;
              if absolute32_addressing_enabled='1' then
                memory_access_address(27 downto 16) := reg_addr_msbs(11 downto 0);
              else
                memory_access_address(27 downto 16) := x"000";
              end if;
              memory_access_wdata := reg_t;
              state <= normal_fetch_state;
            when LoadTarget =>
              -- For some addressing modes we load the target in a separate
              -- cycle to improve timing.
              memory_access_read := '1';
              memory_access_address(15 downto 0) := reg_addr;
              memory_access_resolve_address := not absolute32_addressing_enabled;
              if absolute32_addressing_enabled='1' then
                memory_access_address(27 downto 16) := reg_addr_msbs(11 downto 0);
              else
                memory_access_address(27 downto 16) := x"000";
              end if;
              state <= MicrocodeInterpret;
            when MicrocodeInterpret =>
              -- By this stage we have the address of the operand in
              -- reg_addr, and if it is a load instruction then the contents
              -- will be in memory_read_value
              -- Branches (except JMP) have been taken care of elsewhere, as
              -- have a lot of the other fancy instructions.  That just leaves
              -- us with loads, stores and reaad/modify/write instructions

              -- Go to next instruction by default
              if fast_fetch_state = InstructionDecode then
                pc_inc := reg_microcode.mcIncPC;
              else
                report "not setting pc_inc, because fast_fetch_state /= InstructionDecode";
                pc_inc := '0';
              end if;
              pc_dec := reg_microcode.mcDecPC;
              if reg_microcode.mcInstructionFetch='1' then
                report "Fast dispatch for next instruction by order of microcode";
                state <= fast_fetch_state;
              else
                -- (this gets overriden below for RMW and other instruction types)
                state <= normal_fetch_state;
              end if;
              
              if reg_addressingmode = M_immnn then
                last_byte2 <= memory_read_value;
                last_bytecount <= 2;
                monitor_arg1 <= memory_read_value;
                monitor_ibytes(1) <= '1';
              end if;

              if reg_microcode.mcBRK='1' then                
                state <= Interrupt;
              end if;
              
              if reg_microcode.mcJump='1' then
                report "Setting PC: mcJump=1";
                reg_pc <= reg_addr;
              end if;

              if reg_microcode.mcSetNZ='1' then set_nz(memory_read_value); end if;
              if reg_microcode.mcSetA='1' then
                reg_a <= memory_read_value;
              end if;
              if reg_microcode.mcSetX='1' then reg_x <= memory_read_value; end if;
              if reg_microcode.mcSetY='1' then reg_y <= memory_read_value; end if;
              if reg_microcode.mcSetZ='1' then reg_z <= memory_read_value; end if;

              if reg_microcode.mcBIT='1' then
                set_nz(reg_a and memory_read_value);
                flag_n <= memory_read_value(7);
                flag_v <= memory_read_value(6);
              end if;
              if reg_microcode.mcCMP='1' and (is_rmw='0') then
                alu_op_cmp(reg_a,memory_read_value);
              end if;
              if reg_microcode.mcCPX='1' then
                alu_op_cmp(reg_x,memory_read_value);
              end if;
              if reg_microcode.mcCPY='1' then
                alu_op_cmp(reg_y,memory_read_value);
              end if;
              if reg_microcode.mcCPZ='1' then
                alu_op_cmp(reg_z,memory_read_value);
              end if;
              if reg_microcode.mcADC='1' and (is_rmw='0') then
                reg_a <= a_add(7 downto 0);
                flag_c <= a_add(8);  flag_z <= a_add(9);
                flag_v <= a_add(10); flag_n <= a_add(11);
              end if;
              if reg_microcode.mcSBC='1' and (is_rmw='0') then
                reg_a <= a_sub(7 downto 0);
                flag_c <= a_sub(8);  flag_z <= a_sub(9);
                flag_v <= a_sub(10); flag_n <= a_sub(11);
              end if;
              if reg_microcode.mcAND='1' and (is_rmw='0') then
                reg_a <= with_nz(reg_a and memory_read_value);
              end if;
              if reg_microcode.mcORA='1' and (is_rmw='0') then
                reg_a <= with_nz(reg_a or memory_read_value);
              end if;
              if reg_microcode.mcEOR='1' and (is_rmw='0') then
                reg_a <= with_nz(reg_a xor memory_read_value);
              end if;
              if reg_microcode.mcDEC='1' then
                temp_value := memory_read_value - 1;
                reg_t <= temp_value;                
                flag_n <= temp_value(7);
                if memory_read_value = x"01" then
                  flag_z <= '1'; else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcINC='1' then
                temp_value := memory_read_value + 1;
                reg_t <= temp_value;                
                flag_n <= temp_value(7);
                if memory_read_value = x"ff" then
                  flag_z <= '1'; else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcASR='1' then
                temp_value := memory_read_value(7)&memory_read_value(7 downto 1);
                reg_t <= temp_value;
                flag_c <= memory_read_value(0);
                flag_n <= temp_value(7);
                if temp_value = x"00" then
                  flag_z <= '1'; else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcLSR='1' then
                temp_value := '0'&memory_read_value(7 downto 1);
                reg_t <= temp_value;
                flag_c <= memory_read_value(0);
                flag_n <= temp_value(7);
                if temp_value = x"00" then
                  flag_z <= '1'; else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcROR='1' then
                temp_value := flag_c&memory_read_value(7 downto 1);
                reg_t <= temp_value;
                flag_c <= memory_read_value(0);
                flag_n <= temp_value(7);
                if temp_value = x"00" then
                  flag_z <= '1'; else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcASL='1' then
                temp_value := memory_read_value(6 downto 0)&'0';
                reg_t <= temp_value;
                flag_c <= memory_read_value(7);
                flag_n <= temp_value(7);
                if temp_value = x"00" then
                  flag_z <= '1'; else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcROL='1' then
                temp_value := memory_read_value(6 downto 0)&flag_c;
                reg_t <= temp_value;
                flag_c <= memory_read_value(7);
                flag_n <= temp_value(7);
                if temp_value = x"00" then
                  flag_z <= '1'; else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcRMB='1' then
                -- Clear bit based on opcode
                reg_t <= memory_read_value and rmb_mask;
              end if;
              if reg_microcode.mcSMB='1' then
                -- Set bit based on opcode
                reg_t <= memory_read_value or smb_mask;
              end if;
              
              if reg_microcode.mcClearE='1' then flag_e <= '0'; end if;
              if reg_microcode.mcClearI='1' then flag_i <= '0'; end if;
              if reg_microcode.mcMap='1' then c65_map_instruction; end if;

              if reg_microcode.mcStoreA='1' then memory_access_wdata := reg_a; end if;
              if reg_microcode.mcStoreX='1' then memory_access_wdata := reg_x; end if;
              if reg_microcode.mcStoreY='1' then memory_access_wdata := reg_y; end if;
              if reg_microcode.mcStoreZ='1' then memory_access_wdata := reg_z; end if;              
              if reg_microcode.mcStoreP='1' then
                 memory_access_wdata := unsigned(virtual_reg_p);
                 memory_access_wdata(4) := '1';  -- B always set when pushed
              end if;              
              if reg_microcode.mcWriteRegAddr='1' then
                memory_access_address := x"000"&reg_addr;
                memory_access_resolve_address := '1';
              end if;
              -- XXX Timing closure issue:
              -- There are only 5 push instructions, but we currently read the
              -- push indication from microcode, which is pushing timing
              -- closure out for the CPU.  So we should instead just do a case
              -- statement on the opcode
              -- stack_push := reg_microcode.mcPush;
              case reg_instruction is
                when I_PHA => stack_push := '1';
                when I_PHP => stack_push := '1';
                when I_PHX => stack_push := '1';
                when I_PHY => stack_push := '1';
                when I_PHZ => stack_push := '1';
                when others => stack_push := '0';
              end case;              
              stack_pop := reg_microcode.mcPop;
              if reg_microcode.mcPop='1' then
                state <= Pop;
              end if;
              if reg_microcode.mcStoreTRB='1' then
                reg_t <= (reg_a xor x"FF") and memory_read_value;
              end if;
              if reg_microcode.mcStoreTSB='1' then
                report "memory_read_value = $" & to_hstring(memory_read_value) & ", A = $" & to_hstring(reg_a) severity note;
                reg_t <= reg_a or memory_read_value;
              end if;
              if reg_microcode.mcTestAZ = '1' then
                if (reg_a and memory_read_value) = x"00" then
                  flag_z <= '1';
                else
                  flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcDelayedWrite='1' then
                -- Do dummy write for RMW instructions if touching $D019
                reg_t_high <= memory_read_value;

                if reg_addr = x"D019" then
                  report "memory: DUMMY WRITE for RMW on $D019" severity note;
                  state <= DummyWrite;
                else
                  -- Otherwise just the commit new value immediately
                  state <= WriteCommit;
                end if;
                
              end if;
              if reg_microcode.mcWordOp='1' then
                reg_t <= memory_read_value;
                memory_access_address := x"000"&(reg_addr+1);
                memory_access_resolve_address := '1';
                memory_access_read := '1';
                state <= WordOpReadHigh;
              end if;
              memory_access_write := reg_microcode.mcWriteMem;
              if reg_microcode.mcWriteMem='1' then
                memory_access_address(15 downto 0) := reg_addr;
                memory_access_resolve_address := not absolute32_addressing_enabled;
                if absolute32_addressing_enabled='1' then
                memory_access_address(27 downto 16) := reg_addr_msbs(11 downto 0);
                else
                  memory_access_address(27 downto 16) := x"000";
                end if;
              end if;
            when WordOpReadHigh =>
              state <= WordOpWriteLow;
              case reg_instruction is
                when I_ASW =>
                  temp_addr := memory_read_value(6 downto 0)&reg_t&'0';
                  flag_n <= memory_read_value(6);
                  if temp_addr = x"0000" then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  reg_t_high <= temp_addr(15 downto 8);
                  reg_t <= temp_addr(7 downto 0);
                when I_DEW =>
                  temp_addr := (memory_read_value&reg_t) - 1;
                  if temp_addr = x"0000" then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  reg_t_high <= temp_addr(15 downto 8);
                  reg_t <= temp_addr(7 downto 0);
                when I_INW =>
                  temp_addr := (memory_read_value&reg_t) + 1;
                  if temp_addr = x"0000" then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  reg_t_high <= temp_addr(15 downto 8);
                  reg_t <= temp_addr(7 downto 0);
                when I_PHW =>
                  reg_t_high <= memory_read_value;
                  state <= PushWordLow;
                when I_ROW =>
                  temp_addr := memory_read_value(6 downto 0)&reg_t&flag_c;
                  flag_n <= memory_read_value(6);
                  if temp_addr = x"0000" then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_c <= memory_read_value(7);
                  reg_t_high <= temp_addr(15 downto 8);
                  reg_t <= temp_addr(7 downto 0);
                when others =>
                  state <= normal_fetch_state;
              end case;
            when PushWordLow =>
              -- Push reg_t
              stack_push := '1';
              memory_access_wdata := reg_t;
              state <= PushWordHigh;
            when PushWordHigh =>
              -- Push reg_t_high
              stack_push := '1';
              memory_access_wdata := reg_t_high;
              state <= normal_fetch_state;
            when WordOpWriteLow =>
              memory_access_address := x"000"&(reg_addr);
              memory_access_resolve_address := '1';
              memory_access_write := '1';
              memory_access_wdata := reg_t;
              reg_addr <= reg_addr + 1;
              state <= WordOpWriteHigh;
            when WordOpWriteHigh =>
              memory_access_address := x"000"&(reg_addr);
              memory_access_resolve_address := '1';
              memory_access_write := '1';
              memory_access_wdata := reg_t_high;
              state <= normal_fetch_state;
            when Pop =>
              report "Pop" severity note;
              if reg_microcode.mcStackA='1' then reg_a <= memory_read_value; end if;
              if reg_microcode.mcStackX='1' then reg_x <= memory_read_value; end if;
              if reg_microcode.mcStackY='1' then reg_y <= memory_read_value; end if;
              if reg_microcode.mcStackZ='1' then reg_z <= memory_read_value; end if;
              if reg_microcode.mcStackP='1' then
                flag_n <= memory_read_value(7);
                flag_v <= memory_read_value(6);
                -- E cannot be set with PLP
                flag_d <= memory_read_value(3);
                flag_i <= memory_read_value(2);
                flag_z <= memory_read_value(1);
                flag_c <= memory_read_value(0);
              else
                set_nz(memory_read_value);
              end if;
              state <= normal_fetch_state;
            when others =>
              state <= normal_fetch_state;
          end case;
        end if;

        report "pc_inc = " & std_logic'image(pc_inc)
          & ", cpu_state = " & processor_state'image(state)
          & " ($" & to_hstring(to_unsigned(processor_state'pos(state),8)) & ")"
          & ", reg_addr=$" & to_hstring(reg_addr)
          & ", memory_read_value=$" & to_hstring(read_data)
          severity note;
        report "PC:" & to_hstring(reg_pc)
            & " A:" & to_hstring(reg_a) & " X:" & to_hstring(reg_x)
            & " Y:" & to_hstring(reg_y) & " Z:" & to_hstring(reg_z)
            & " SP:" & to_hstring(reg_sph&reg_sp)
            severity note;
        
        if pc_inc = '1' then
          report "Incrementing PC to $" & to_hstring(reg_pc+1) severity note;
          reg_pc <= reg_pc + 1;
        end if;
        if pc_dec = '1' then
          report "Decrementing PC to $" & to_hstring(reg_pc-1) severity note;
          reg_pc <= reg_pc - 1;
        end if;
        if dec_sp = '1' then
          reg_sp <= reg_sp - 1;
          if flag_e='0' and reg_sp=x"00" then
            reg_sph <= reg_sph - 1;
          end if;
        end if;

        if stack_push='1' then

          memory_access_write := '1';
          memory_access_address := x"000"&reg_sph&reg_sp;
          memory_access_resolve_address := '1';
          
          reg_sp <= reg_sp - 1;
          if flag_e='0' and reg_sp=x"00" then
            reg_sph <= reg_sph - 1;
          end if;
        end if;
        if stack_pop='1' then
          -- Pop
          memory_access_read := '1';
          if flag_e='0' then
            -- stack pointer can roam full 64KB
            memory_access_address := x"000"&((reg_sph&reg_sp)+1);
          else
            -- constrain stack pointer to single page if E flag is set
            memory_access_address := x"000"&reg_sph&(reg_sp+1);
          end if;
          memory_access_resolve_address := '1';

          reg_sp <= reg_sp + 1;
          if flag_e='0' and reg_sp=x"ff" then
            reg_sph <= reg_sph + 1;
          end if;
        end if;
        
        -- Effect memory accesses.
        -- Note that we cannot combine address resolution for read and write,
        -- because the resolution of some addresses is dependent on whether
        -- the operation is read or write.  ROM accesses are a good example.
        -- We delay the memory write until the next cycle to minimise logic depth

        -- Mark pages dirty as necessary
        if memory_access_write='1' then
          if (reg_pageactive = '1' ) then
            if (memory_access_address(15 downto 14) = "01") then
              case reg_pageid is
                when "00" => reg_pages_dirty(0) <= '1'; 
                when "01" => reg_pages_dirty(1) <= '1'; 
                when "10" => reg_pages_dirty(2) <= '1'; 
                when "11" => reg_pages_dirty(3) <= '1';
                when others => null;
              end case;
            end if;
          end if;

          if memory_access_resolve_address = '1' then
            memory_access_address := resolve_address_to_long(memory_access_address(15 downto 0),true);
          end if;

          -- Get the shadow RAM or ROM address on the bus fast to improve timing.
          shadow_write <= '0';
          shadow_write_flags(1) <= '1';
          shadow_address <= to_integer(memory_access_address(16 downto 0));
          rom_address <= to_integer(memory_access_address(16 downto 0));
          rom_write <= '0';
          
          if memory_access_address = x"FFD3700"
            or memory_access_address = x"FFD1700" then
            report "DMAgic: DMA pending";
            dma_pending <= '1';
            state <= DMAgicTrigger;

            -- Don't increment PC if we were otherwise going to shortcut to
            -- InstructionDecode next cycle
            report "Setting PC to self (DMAgic entry)";
            reg_pc <= reg_pc;
          end if;
          -- @IO:GS $D67F - Trigger trap to hypervisor
          if memory_access_address(27 downto 6)&"111111" = x"FFD367F" then
            hypervisor_trap_port(5 downto 0) <= memory_access_address(5 downto 0);
            hypervisor_trap_port(6) <= '0';
            if hypervisor_mode = '0' then
              report "HYPERTRAP: Hypervisor trap triggered by write to $D640-$D67F";
              state <= TrapToHypervisor;
            end if;
            if hypervisor_mode = '1'
              and memory_access_address(5 downto 0) = "111111" then
              report "HYPERTRAP: Hypervisor return triggered by write to $D67F";
              state <= ReturnFromHypervisor;
            end if;
            -- Don't increment PC if we were otherwise going to shortcut to
            -- InstructionDecode next cycle
            -- report "Setting PC to self (CPU port access)";
            -- reg_pc <= reg_pc;
          end if;
          write_long_byte(memory_access_address,memory_access_wdata);
        elsif memory_access_read='1' then 
          report "memory_access_read=1, addres=$"&to_hstring(memory_access_address) severity note;
          if memory_access_resolve_address = '1' then
            memory_access_address := resolve_address_to_long(memory_access_address(15 downto 0),false); 
          end if;
          read_long_address(memory_access_address);
        end if;
      end if; -- if not reseting
    end if;                         -- if rising edge of clock
  end process;
end Behavioural;
