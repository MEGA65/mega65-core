-- Accelerated 6502-like CPU for the C65GS
--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2018
--
-- * ADC/SBC algorithm derived from  6510core.c - VICE MOS6510 emulation core.
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

-- @IO:C65 $D0A0-$D0FF SUMMARY:REC Reserved for C65 RAM Expansion Controller.

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.victypes.all;

entity gs4510 is
  generic(
    math_unit_enable : boolean := false;
    chipram_1mb : std_logic := '0';
    cpufrequency : integer := 50;
    chipram_size : integer := 393216;
    target : mega65_target_t := mega65r2);
  port (
    mathclock : in std_logic;
    Clock : in std_logic;
    phi0 : out std_logic;
    phi_in : in std_logic;
    ioclock : in std_logic;
    reset : in std_logic;
    reset_out : out std_logic;
    irq : in std_logic;
    nmi : in std_logic;
    exrom : in std_logic;
    game : in std_logic;

    all_pause : in std_logic;
    
    hyper_trap : in std_logic;
    cpu_hypervisor_mode : out std_logic := '0';
    matrix_trap_in : in std_logic;
    hyper_trap_f011_read : in std_logic;
    hyper_trap_f011_write : in std_logic;    
    --Protected Hardware Bits
    --Bit 0: TBD
    --Bit 1: TBD
    --Bit 2: TBD
    --Bit 3: TBD
    --Bit 4: TBD
    --Bit 5: TBD
    --Bit 6: Matrix Mode
    --Bit 7: Secure Mode enable 
    protected_hardware : out unsigned(7 downto 0);	
    --Bit 0: Trap on F011 FDC read/write
    virtualised_hardware : out unsigned(7 downto 0);
    -- Enable disabling of various IO devices, including for secure mode
    chipselect_enables : buffer std_logic_vector(7 downto 0) := x"EF";
    
    iomode_set : out std_logic_vector(1 downto 0) := "11";
    iomode_set_toggle : out std_logic := '0';

    dat_offset : in unsigned(15 downto 0);
    dat_even : in std_logic;
    dat_bitplane_addresses : in sprite_vector_eight;
    
    cpuis6502 : out std_logic := '0';
    cpuspeed : out unsigned(7 downto 0);

    power_down : out std_logic := '1';
    
    irq_hypervisor : in std_logic_vector(2 downto 0) := "000";    -- JBM

    -- Asserted when CPU is in secure mode: Activates secure mode matrix mode interface
    secure_mode_out : out std_logic := '0';
    -- Input from uart monitor to indicate if we should be in secure or normal
    -- mode (CPU halts if in wrong mode, i.e., until monitor releases it to resume)
    secure_mode_from_monitor : in std_logic;
    -- This signal allows the monitor to cancel matrix mode after we ACCEPT or
    -- REJECT a secure session.
    clear_matrix_mode_toggle : in std_logic;
    
    matrix_rain_seed : out unsigned(15 downto 0) := (others => '0');

    -- Active low key that forces CPU to 40MHz
    fast_key : in std_logic;
  
    no_hyppo : in std_logic;

    reg_isr_out : in unsigned(7 downto 0);
    imask_ta_out : in std_logic;

    request_monitor_halt : out std_logic := '0';
    
    monitor_char : out unsigned(7 downto 0);
    monitor_char_toggle : out std_logic;
    monitor_char_busy : in std_logic;
    
    monitor_proceed : out std_logic;
    monitor_waitstates : out unsigned(7 downto 0);
    monitor_request_reflected : out std_logic;
    monitor_hypervisor_mode : out std_logic;
    monitor_instruction_strobe : out std_logic := '0';
    monitor_pc : out unsigned(15 downto 0);
    monitor_state : out unsigned(15 downto 0);
    monitor_instruction : out unsigned(7 downto 0);
    monitor_watch : in unsigned(27 downto 0);
    monitor_watch_match : out std_logic;
    monitor_instructionpc : out unsigned(15 downto 0);
    monitor_opcode : out unsigned(7 downto 0);
    monitor_ibytes : out unsigned(3 downto 0);
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
    monitor_map_enables_low : out unsigned(3 downto 0);
    monitor_map_enables_high : out unsigned(3 downto 0);
    monitor_interrupt_inhibit : out std_logic;
    monitor_memory_access_address : out unsigned(31 downto 0);
    monitor_cpuport : out unsigned(2 downto 0);

    -- Used to pause CPU when ethernet dumping of instruction stream is active.
    ethernet_cpu_arrest : in std_logic;
    
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
    monitor_irq_inhibit : in std_logic;
    monitor_mem_trace_mode : in std_logic;
    monitor_mem_stage_trace_mode : in std_logic;
    monitor_mem_trace_toggle : in std_logic;
    
    -- Debugging
    debug_address_w_dbg_out : out std_logic_vector(16 downto 0);
    debug_address_r_dbg_out : out std_logic_vector(16 downto 0);
    debug_rdata_dbg_out : out std_logic_vector(7 downto 0);
    debug_wdata_dbg_out : out std_logic_vector(7 downto 0);
    debug_write_dbg_out : out std_logic;
    debug_read_dbg_out : out std_logic;
    debug4_state_out : out std_logic_vector(3 downto 0);
    
    proceed_dbg_out : out std_logic;
    
    ---------------------------------------------------------------------------
    -- Interface to ChipRAM in video controller (just 128KB for now)
    ---------------------------------------------------------------------------
    chipram_we : OUT STD_LOGIC := '0';

    chipram_clk : IN std_logic;
    chipram_address : IN unsigned(19 DOWNTO 0) := to_unsigned(0,20);
    chipram_dataout : OUT unsigned(7 DOWNTO 0);

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
    -- When badline_toggle toggles, we need to act as though 40-43 clock cycles
    -- are being stolen from us (we should vary this based on sprite activity,
    -- but this should be enough for fixing many programs).
    badline_toggle : in std_logic;
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : inout std_logic_vector(19 downto 0);
    fastio_addr_fast : out std_logic_vector(19 downto 0);
    fastio_read : inout std_logic := '0';
    fastio_write : inout std_logic := '0';
    fastio_wdata : inout std_logic_vector(7 downto 0);
    fastio_rdata : in std_logic_vector(7 downto 0);
    hyppo_rdata : in std_logic_vector(7 downto 0);
    hyppo_address_out : out std_logic_vector(13 downto 0);
    
    sector_buffer_mapped : in std_logic;
    fastio_vic_rdata : in std_logic_vector(7 downto 0);
    fastio_colour_ram_rdata : in std_logic_vector(7 downto 0);
    colour_ram_cs : out std_logic := '0';
    charrom_write_cs : out std_logic := '0';

    ---------------------------------------------------------------------------
    -- Slow device access 4GB address space
    ---------------------------------------------------------------------------
    slow_access_request_toggle : out std_logic := '0';
    slow_access_ready_toggle : in std_logic;

    slow_access_address : out unsigned(27 downto 0) := (others => '1');
    slow_access_write : out std_logic := '0';
    slow_access_wdata : out unsigned(7 downto 0);
    slow_access_rdata : in unsigned(7 downto 0);
    
    ---------------------------------------------------------------------------
    -- VIC-III memory banking control
    ---------------------------------------------------------------------------
    viciii_iomode : in std_logic_vector(1 downto 0);

    colourram_at_dc00 : in std_logic;
    rom_at_e000 : in std_logic;
    rom_at_c000 : in std_logic;
    rom_at_a000 : in std_logic;
    rom_at_8000 : in std_logic

    );
end entity gs4510;

architecture Behavioural of gs4510 is

  -- CPU breakpoint support
  -- (This is the new internal-to-cpu method, rather than the old external
  -- monitor method.)
  signal breakpoint_hyperrupt : std_logic := '1';
  signal breakpoint0_enable : std_logic := '0';
  signal breakpoint1_enable : std_logic := '0';
  signal breakpoint2_enable : std_logic := '0';
  signal breakpoint3_enable : std_logic := '0';
  signal breakpoint0_pc : unsigned(15 downto 0) := x"FCE2";
  signal breakpoint1_pc : unsigned(15 downto 0) := x"FCE2";
  signal breakpoint2_pc : unsigned(15 downto 0) := x"FCE2";
  signal breakpoint3_pc : unsigned(15 downto 0) := x"FCE2";
  
  -- DMAgic settings
  signal support_f018b : std_logic := '0';
  signal job_is_f018b : std_logic := '0';
  signal job_uses_options : std_logic := '0';

  signal cpuspeed_internal : unsigned(7 downto 0) := (others => '0');
  signal cpuspeed_external : unsigned(7 downto 0) := (others => '0');

  signal reset_drive : std_logic := '0';
  signal cartridge_enable : std_logic := '0';
  signal gated_exrom : std_logic := '1'; 
  signal gated_game : std_logic := '1';
  signal force_exrom : std_logic := '1'; 
  signal force_game : std_logic := '1';

  signal force_fast : std_logic := '0';
  signal speed_gate_enable_internal : std_logic := '1';
  signal speed_gate_drive : std_logic := '1';

  signal last_badline_toggle : std_logic := '0';
  
  signal iomode_set_toggle_internal : std_logic := '0';
  signal rom_writeprotect : std_logic := '0';

  signal virtualise_sd : std_logic := '0';

  signal dat_bitplane_addresses_drive : sprite_vector_eight;
  signal dat_offset_drive : unsigned(15 downto 0) := to_unsigned(0,16);
  signal dat_even_drive : std_logic := '1';

  -- Instruction log
  signal last_instruction_pc : unsigned(15 downto 0) := x"FFFF";
  signal last_opcode : unsigned(7 downto 0)  := (others => '0');
  signal last_byte2 : unsigned(7 downto 0)  := (others => '0');
  signal last_byte3 : unsigned(7 downto 0)  := (others => '0');
  signal last_bytecount : integer range 0 to 3 := 0;
  signal last_action : character := ' ';
  signal last_address : unsigned(27 downto 0)  := (others => '0');
  signal last_value : unsigned(7 downto 0)  := (others => '0');

  -- Shadow RAM control
  signal shadow_address : integer range 0 to 1048575 := 0;
  signal debug_address_w_dbg : integer range 0 to 1048575 := 0;
  signal debug_address_r_dbg : integer range 0 to 1048575 := 0;
  signal shadow_address_next : integer range 0 to 1048575 := 0;
  
  signal shadow_rdata : unsigned(7 downto 0)  := (others => '0');
  signal shadow_wdata : unsigned(7 downto 0)  := (others => '0');
  signal shadow_wdata_next : unsigned(7 downto 0)  := (others => '0');
  signal shadow_write_count : unsigned(7 downto 0)  := (others => '0');
  signal shadow_no_write_count : unsigned(7 downto 0)  := (others => '0');
  signal shadow_try_write_count : unsigned(7 downto 0) := x"00";
  signal shadow_observed_write_count : unsigned(7 downto 0) := x"00";
  signal shadow_write : std_logic := '0';
  signal shadow_write_next : std_logic := '0';

  signal hyppo_address : std_logic_vector(13 downto 0);
  signal hyppo_address_next : std_logic_vector(13 downto 0);
  
  signal fastio_addr_next : std_logic_vector(19 downto 0);
  
  signal read_data : unsigned(7 downto 0)  := (others => '0');
  
  signal long_address_read : unsigned(27 downto 0)  := (others => '0');
  signal long_address_write : unsigned(27 downto 0)  := (others => '0');

  -- C65 RAM Expansion Controller
  -- bit 7 = indicate error status?
  signal rec_status : unsigned(7 downto 0) := x"80";
  
  -- GeoRAM emulation: by default point it the 128KB of extra memory at the
  -- 256KB mark
  -- georam_page is the address x 256, so 256KB = page $400
  signal georam_page : unsigned(19 downto 0) := x"00400";
  -- GeoRAM is organised in 16KB blocks.  The block mask is thus in units of 16KB.
  -- Note that a 128KB GeoRAM is not standard, and some software may think it
  -- is 512KB, which will of course cause problems.
  signal georam_blockmask : unsigned(7 downto 0) := to_unsigned(128/16,8);
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

  signal last_fastio_addr : std_logic_vector(19 downto 0)  := (others => '0');
  signal last_write_address : unsigned(27 downto 0)  := (others => '0');
  signal shadow_write_flags : unsigned(3 downto 0) := "0000";
  -- Registers to hold delayed write to hypervisor and related CPU registers
  -- to improve CPU timing closure.
  signal last_write_value : unsigned(7 downto 0)  := (others => '0');
  signal last_write_pending : std_logic := '0';
  -- Flag used to ensure monitor serial character out busy flag gets asserted
  -- immediately on writing a character, without having to wait for the uart
  -- monitor to have a serial port tick (which is when it checks on that side)
  signal immediate_monitor_char_busy : std_logic := '0';

  signal last_clear_matrix_mode_toggle : std_logic := '0';

  -- For instruction-accurate CPU timing at 1MHz and 3.5MHz
  -- Actually only used for 3.5MHz, as at 1MHz we used the cycle impulses
  -- from the video frame generator, which also handles PAL/NTSC differences
  -- XXX Doesn't differentiate between PAL and NTSC at 3.5MHz
  -- XXX 2MHz / 3.5MHz thus also uses somewhat different time base to 1MHz
  constant pal1mhz_times_65536 : integer := 64569;
  constant pal2mhz_times_65536 : integer := 64569 * 2;
  constant pal3point5mhz_times_65536 : integer := 225992;
  constant phi_fraction_01pal : unsigned(16 downto 0) :=
    to_unsigned(pal1mhz_times_65536 / cpufrequency,17);
  constant phi_fraction_02pal : unsigned(16 downto 0) :=
    to_unsigned(pal2mhz_times_65536 / cpufrequency,17);
  constant phi_fraction_04pal : unsigned(16 downto 0) :=
    to_unsigned(pal3point5mhz_times_65536 / cpufrequency,17);
  signal phi_export_counter : unsigned(16 downto 0) := (others => '0');
  signal phi_counter : unsigned(16 downto 0) := (others => '0');
  signal phi_pause : std_logic := '0';
  signal phi_backlog : integer range 0 to 127 := 0;
  signal phi_add_backlog : std_logic := '0';
  signal charge_for_branches_taken : std_logic := '1';
  signal phi_new_backlog : integer range 0 to 127 := 0;
  signal last_phi16 : std_logic := '0';
  signal phi0_export : std_logic := '0';
  signal last_phi_in : std_logic := '0';

  -- IO has one waitstate for reading, 0 for writing
  -- (Reading incurrs an extra waitstate due to read_data_copy)
  -- XXX An extra wait state seems to be necessary when reading from dual-port
  -- memories like colour ram.
  -- XXX The palette RAMs take even longer, because the access is first latched
  -- by the VIC-IV before being passed out.
  constant ioread_48mhz : unsigned(7 downto 0) := x"01";
  constant colourread_48mhz : unsigned(7 downto 0) := x"02";
  -- XXX Try outrageously many waitstates on palette
  constant palette_48mhz : unsigned(7 downto 0) := x"03";
  constant iowrite_48mhz : unsigned(7 downto 0) := x"00";
  constant shadow_48mhz :  unsigned(7 downto 0) := x"00";

  signal shadow_wait_states : unsigned(7 downto 0) := shadow_48mhz;
  signal io_read_wait_states : unsigned(7 downto 0) := ioread_48mhz;
  signal colourram_read_wait_states : unsigned(7 downto 0) := colourread_48mhz;
  signal palette_read_wait_states : unsigned(7 downto 0) := palette_48mhz;
  signal io_write_wait_states : unsigned(7 downto 0) := iowrite_48mhz;

  -- Interface to slow device address space
  signal slow_access_request_toggle_drive : std_logic := '0';
  signal slow_access_write_drive : std_logic := '0';
  signal slow_access_address_drive : unsigned(27 downto 0) := (others => '1');
  signal slow_access_wdata_drive : unsigned(7 downto 0) := (others => '1');
  signal slow_access_desired_ready_toggle : std_logic := '0';
  signal slow_access_ready_toggle_buffer : std_logic := '0';
  signal slow_access_pending_write : std_logic := '0';
  signal slow_access_data_ready : std_logic := '0';

  -- Number of pending wait states
  signal wait_states : unsigned(7 downto 0) := x"05";
  signal wait_states_non_zero : std_logic := '1';
  
  signal word_flag : std_logic := '0';

  -- DMAgic registers
  signal dmagic_list_counter : integer range 0 to 12;
  signal dmagic_first_read : std_logic := '0';
  signal reg_dmagic_addr : unsigned(27 downto 0) := x"0000000";
  signal reg_dmagic_withio : std_logic := '0';
  signal reg_dmagic_status : unsigned(7 downto 0) := x"00";
  signal reg_dmacount : unsigned(7 downto 0) := x"00";  -- number of DMA jobs done
  signal dma_pending : std_logic := '0';
  signal dma_checksum : unsigned(23 downto 0) := x"000000";
  signal dmagic_cmd : unsigned(7 downto 0)  := (others => '0');
  signal dmagic_subcmd : unsigned(7 downto 0)  := (others => '0');	-- F018A/B extention
  signal dmagic_count : unsigned(15 downto 0)  := (others => '0');
  signal dmagic_tally : unsigned(15 downto 0)  := (others => '0');
  signal reg_dmagic_src_mb : unsigned(7 downto 0)  := (others => '0');
  signal dmagic_src_addr : unsigned(35 downto 0)  := (others => '0'); -- in 256ths of bytes
  signal reg_dmagic_use_transparent_value : std_logic := '0';
  signal reg_dmagic_transparent_value : unsigned(7 downto 0) := x"00";
  signal dmagic_option_id : unsigned(7 downto 0) := x"00";

  signal dmagic_src_io : std_logic := '0';
  signal dmagic_src_direction : std_logic := '0';
  signal dmagic_src_modulo : std_logic := '0';
  signal dmagic_src_hold : std_logic := '0';
  signal reg_dmagic_dst_mb : unsigned(7 downto 0)  := (others => '0');
  signal dmagic_dest_addr : unsigned(35 downto 0)  := (others => '0'); -- in 256ths of bytes
  signal dmagic_dest_io : std_logic := '0';
  signal dmagic_dest_direction : std_logic := '0';
  signal dmagic_dest_modulo : std_logic := '0';
  signal dmagic_dest_hold : std_logic := '0';
  signal dmagic_modulo : unsigned(15 downto 0)  := (others => '0');

  -- Allow source and destination address advance to range from 1/256th of a
  -- byte (i.e., 1 byte every 256 operations) through to 255 + 255/256ths per
  -- operation. This was added to accelerate texture copying for Doom-style 3D
  -- drawing.
  signal reg_dmagic_src_skip : unsigned(15 downto 0) := x"0100";
  signal reg_dmagic_dst_skip : unsigned(15 downto 0) := x"0100";

  -- Temporary registers used while loading DMA list
  signal dmagic_dest_bank_temp : unsigned(7 downto 0)  := (others => '0');
  signal dmagic_src_bank_temp : unsigned(7 downto 0)  := (others => '0');
  -- Temporary store for CPU port bits to bank IO/ROMs in/out during DMA
  signal pre_dma_cpuport_bits : unsigned(2 downto 0) := (others => '1');

  -- CPU internal state
  signal flag_c : std_logic := '0';        -- carry flag
  signal flag_z : std_logic := '0';        -- zero flag
  signal flag_d : std_logic := '0';        -- decimal mode flag
  signal flag_n : std_logic := '0';        -- negative flag
  signal flag_v : std_logic := '0';        -- positive flag
  signal flag_i : std_logic := '0';        -- interrupt disable flag
  signal flag_e : std_logic := '0';        -- 8-bit stack flag

  signal reg_a : unsigned(7 downto 0)  := (others => '0');
  signal reg_b : unsigned(7 downto 0)  := (others => '0');
  signal reg_x : unsigned(7 downto 0)  := (others => '0');
  signal reg_y : unsigned(7 downto 0)  := (others => '0');
  signal reg_z : unsigned(7 downto 0)  := (others => '0');
  signal reg_sp : unsigned(7 downto 0)  := (others => '0');
  signal reg_sph : unsigned(7 downto 0)  := (others => '0');
  signal reg_pc : unsigned(15 downto 0)  := (others => '0');

  -- CPU RAM bank selection registers.
  -- Now C65 style, but extended by 8 bits to give 256MB address space
  signal reg_mb_low : unsigned(7 downto 0)  := (others => '0');
  signal reg_mb_high : unsigned(7 downto 0)  := (others => '0');
  signal reg_map_low : std_logic_vector(3 downto 0)  := (others => '0');
  signal reg_map_high : std_logic_vector(3 downto 0)  := (others => '0');
  signal reg_offset_low : unsigned(11 downto 0)  := (others => '0');
  signal reg_offset_high : unsigned(11 downto 0)  := (others => '0');

  -- Are we in hypervisor mode?
  signal hypervisor_mode : std_logic := '1';
  signal hypervisor_trap_port : unsigned (6 downto 0)  := (others => '0');
  -- Have we ever replaced the hypervisor with another?
  -- (used to allow once-only update of hypervisor by hick-up file)
  signal hypervisor_upgraded : std_logic := '0';

  -- Duplicates of all CPU registers to hold user-space contents when trapping
  -- to hypervisor.
  signal hyper_iomode : unsigned(7 downto 0)  := (others => '0');
  signal hyper_dmagic_src_mb : unsigned(7 downto 0)  := (others => '0');
  signal hyper_dmagic_dst_mb : unsigned(7 downto 0)  := (others => '0');
  signal hyper_dmagic_list_addr : unsigned(27 downto 0)  := (others => '0');
  signal hyper_p : unsigned(7 downto 0)  := (others => '0');
  signal hyper_a : unsigned(7 downto 0)  := (others => '0');
  signal hyper_b : unsigned(7 downto 0)  := (others => '0');
  signal hyper_x : unsigned(7 downto 0)  := (others => '0');
  signal hyper_y : unsigned(7 downto 0)  := (others => '0');
  signal hyper_z : unsigned(7 downto 0)  := (others => '0');
  signal hyper_sp : unsigned(7 downto 0)  := (others => '0');
  signal hyper_sph : unsigned(7 downto 0)  := (others => '0');
  signal hyper_pc : unsigned(15 downto 0)  := (others => '0');
  signal hyper_mb_low : unsigned(7 downto 0)  := (others => '0');
  signal hyper_mb_high : unsigned(7 downto 0)  := (others => '0');
  signal hyper_port_00 : unsigned(7 downto 0)  := (others => '0');
  signal hyper_port_01 : unsigned(7 downto 0)  := (others => '0');
  signal hyper_map_low : std_logic_vector(3 downto 0)  := (others => '0');
  signal hyper_map_high : std_logic_vector(3 downto 0)  := (others => '0');
  signal hyper_map_offset_low : unsigned(11 downto 0)  := (others => '0');
  signal hyper_map_offset_high : unsigned(11 downto 0)  := (others => '0');
  signal hyper_protected_hardware : unsigned(7 downto 0)  := (others => '0');
  
  -- Page table for virtual memory
  signal reg_page0_logical : unsigned(15 downto 0)  := (others => '0');
  signal reg_page0_physical : unsigned(15 downto 0)  := (others => '0');
  signal reg_page1_logical : unsigned(15 downto 0)  := (others => '0');
  signal reg_page1_physical : unsigned(15 downto 0)  := (others => '0');
  signal reg_page2_logical : unsigned(15 downto 0)  := (others => '0');
  signal reg_page2_physical : unsigned(15 downto 0)  := (others => '0');
  signal reg_page3_logical : unsigned(15 downto 0)  := (others => '0');
  signal reg_page3_physical : unsigned(15 downto 0)  := (others => '0');
  signal reg_pagenumber : unsigned(17 downto 0)  := (others => '0');
  signal reg_pages_dirty : std_logic_vector(3 downto 0)  := (others => '0');
  signal reg_pages_dirty_next : std_logic_vector(3 downto 0)  := (others => '0');
  signal reg_pageid : unsigned(1 downto 0)  := (others => '0');
  signal reg_pageactive : std_logic := '0';
  

  -- Flags to detect interrupts
  signal map_interrupt_inhibit : std_logic := '0';
  signal nmi_pending : std_logic := '0';
  signal irq_pending : std_logic := '0';
  signal nmi_state : std_logic := '1';
  signal no_interrupt : std_logic := '0';
  signal hyper_trap_last : std_logic := '0';
  signal hyper_trap_edge : std_logic := '0';
  signal hyper_trap_pending : std_logic := '0';
  signal hyper_trap_state : std_logic := '1';
  signal matrix_trap_pending : std_logic := '0';
  signal f011_read_trap_pending : std_logic := '0';
  signal f011_write_trap_pending : std_logic := '0';
  -- To defer interrupts in the hypervisor, we have a special mechanism for this.
  signal irq_defer_request : std_logic := '0';
  signal irq_defer_counter : integer range 0 to 65535 := 0;
  signal irq_defer_active : std_logic := '0';

  -- Interrupt/reset vector being used
  signal vector : unsigned(3 downto 0)  := (others => '0');
  
  -- Information about instruction currently being executed
  signal reg_opcode : unsigned(7 downto 0)  := (others => '0');
  signal reg_arg1 : unsigned(7 downto 0)  := (others => '0');
  signal reg_arg2 : unsigned(7 downto 0)  := (others => '0');

  signal bbs_or_bbc : std_logic := '0';
  signal bbs_bit : unsigned(2 downto 0)  := (others => '0');
  
  -- PC used for JSR is the value of reg_pc after reading only one of
  -- of the argument bytes.  We could subtract one, but it is less logic to
  -- just remember PC after reading one argument byte.
  signal reg_pc_jsr : unsigned(15 downto 0)  := (others => '0');
  -- Temporary address register (used for indirect modes)
  signal reg_addr : unsigned(15 downto 0)  := (others => '0');
  -- ... and this one for 32-bit flat addressing modes
  signal reg_addr32 : unsigned(31 downto 0)  := (others => '0');
  -- ... and this one for pushing 32bit virtual address onto the stack
  signal reg_addr32save : unsigned(31 downto 0)  := (others => '0');
  -- Upper and lower
  -- 16 bits of temporary address register. Used for 32-bit
  -- absolute addresses
  signal reg_addr_msbs : unsigned(15 downto 0)  := (others => '0');
  signal reg_addr_lsbs : unsigned(15 downto 0)  := (others => '0');
  -- Flag that indicates if a ($nn),Z access is using a 32-bit pointer
  signal absolute32_addressing_enabled : std_logic := '0';
  -- Flag that indicates far JMP, JSR or RTS
  -- (set by two CLD's in a row before the instruction)
  signal flat32_address : std_logic := '0';
  signal flat32_address_prime : std_logic := '0';
  signal flat32_enabled : std_logic := '1';
  -- flag for progressive carry calculation when loading a 32-bit pointer
  signal pointer_carry : std_logic := '0';
  -- Temporary value holder (used for RMW instructions)
  signal reg_t : unsigned(7 downto 0)  := (others => '0');
  signal reg_t_high : unsigned(7 downto 0)  := (others => '0');

  signal reg_val32 : unsigned(31 downto 0) := to_unsigned(0,32);
  signal next_is_axyz32_instruction : std_logic := '0';
  signal value32_enabled : std_logic := '0';
  signal axyz_phase : integer range 0 to 4 := 0;
  
  signal instruction_phase : unsigned(3 downto 0)  := (others => '0');
  
-- Indicate source of operand for instructions
-- Note that ROM is actually implemented using
-- power-on initialised RAM in the FPGA mapped via our io interface.
  signal accessing_shadow : std_logic;
  signal accessing_rom : std_logic;
  signal accessing_fastio : std_logic;
  signal accessing_vic_fastio : std_logic;
  signal accessing_hyppo_fastio : std_logic;
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
  signal io_settle_delay : std_logic := '0';
  signal io_settle_counter : unsigned(7 downto 0) := x"00";
  signal io_settle_trigger : std_logic := '0';
  signal io_settle_trigger_last : std_logic := '0';  
  
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

  signal vector_read_stage : integer range 0 to 15 := 0;

  type memory_source is (
    DMAgicRegister,         -- 0x00
    HypervisorRegister,     -- 0x01
    CPUPort,                -- 0x02
    Shadow,                 -- 0x03
    FastIO,                 -- 0x04
    ColourRAM,              -- 0x05
    VICIV,                  -- 0x06
    Hyppo,              -- 0x07
    SlowRAM,                -- 0x08
    Unmapped                -- 0x09
    );

  signal read_source : memory_source;

  type processor_state is (
    -- Reset and interrupts
    ResetLow,                                     -- 0x00
    ResetReady,                                   -- 0x01
    Interrupt,InterruptPushPCL,InterruptPushP,    -- 0x02, 0x03, 0x04
    VectorRead,                                   -- 0x05

    -- Hypervisor traps
    TrapToHypervisor,ReturnFromHypervisor,        -- 0x06, 0x07
    
    -- DMAgic
    DMAgicTrigger,                                -- 0x08
    DMAgicReadOptions,DMAgicReadList,             -- 0x09, 0x0a
    DMAgicGetReady,                               -- 0x0b
    DMAgicFill,                                   -- 0x0c
    DMAgicCopyRead,DMAgicCopyWrite,               -- 0x0d, 0x0e

    -- Normal instructions
    InstructionWait,                    -- Wait for PC to become available on       0x0f
                                        -- interrupt/reset
    ProcessorHold,                      -- 0x10
    MonitorMemoryAccess,                -- 0x11
    InstructionFetch,                   -- 0x12
    InstructionDecode,  -- $16          -- 0x13
    InstructionDecode6502,              -- 0x14
    Cycle2,Cycle3,                      -- 0x15, 0x16
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
    MicrocodeInterpret,
    LoadTarget32,
    Execute32,
    StoreTarget32
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
    -- MAP is not available here. To MAP from 6502 mode, you have to first
    -- enable 4502 mode by switching VIC-III/IV IO mode from VIC-II.
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

  type clut9bit is array(0 to 511) of integer range 0 to 15;
  constant cycle_count_lut : clut9bit := (
    -- 4502 timing
    -- from http://archive.6502.org/datasheets/mos_65ce02_mpu.pdf
    7,5,2,2,4,3,4,4, 3,2,1,1,5,4,5,4,
    2,5,5,3,4,3,4,4, 1,4,1,1,5,4,5,4,
    2,5,7,7,4,3,4,4, 3,2,1,1,5,4,4,4,
    2,5,5,3,4,3,4,4, 1,4,1,1,5,4,5,4,
    
    5,5,2,2,4,3,4,4, 3,2,1,1,3,4,5,4,
    2,5,5,3,4,3,4,4, 1,4,3,3,4,4,5,4,
    4,5,7,5,3,3,4,4, 3,2,1,1,5,4,5,4,
    2,5,5,3,3,3,4,4, 2,4,3,1,5,4,5,4,
    
    2,5,6,3,3,3,3,4, 1,2,1,4,4,4,4,4,
    2,5,5,3,3,3,3,4, 1,4,1,4,4,4,4,4,
    2,5,2,2,3,3,3,4, 1,2,1,4,4,4,4,4,
    2,5,5,3,3,3,3,4, 1,4,1,4,4,4,4,4,
    
    2,5,2,6,3,3,4,4, 1,2,1,7,4,4,5,4,
    2,5,5,3,3,3,4,4, 1,4,3,3,4,4,5,4,
    2,5,6,6,3,3,4,4, 1,2,1,6,4,4,5,4,
    2,5,5,3,5,3,4,4, 1,4,3,3,7,4,5,4,

    -- 6502 timings from  "Graham's table" (Oxyron)
    7,6,0,8,3,3,5,5,3,2,2,2,4,4,6,6,
    2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,
    6,6,0,8,3,3,5,5,4,2,2,2,4,4,6,6,
    2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,

    6,6,0,8,3,3,5,5,3,2,2,2,3,4,6,6,
    2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,
    6,6,0,8,3,3,5,5,4,2,2,2,5,4,6,6,
    2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,

    2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,
    2,6,0,6,4,4,4,4,2,5,2,5,5,5,5,5,
    2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,
    2,5,0,5,4,4,4,4,2,4,2,4,4,4,4,4,

    2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,
    2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,
    2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,
    2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7
    );


  signal reg_addressingmode : addressingmode;
  signal reg_instruction : instruction;

  signal is_rmw : std_logic;
  signal is_load : std_logic;
  signal rmw_dummy_write_done : std_logic;
  
  signal a_incremented : unsigned(7 downto 0);
  signal a_decremented : unsigned(7 downto 0);
  signal a_negated : unsigned(7 downto 0);
  signal a_ror : unsigned(7 downto 0);
  signal a_rol : unsigned(7 downto 0);
  signal a_asl : unsigned(7 downto 0);
  signal a_asr : unsigned(7 downto 0);
  signal a_lsr : unsigned(7 downto 0);
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

  signal watchdog_reset : std_logic := '0';
  signal watchdog_fed : std_logic := '0';
  signal watchdog_countdown : integer range 0 to 65535;

  signal emu6502 : std_logic := '0';
  signal timing6502 : std_logic := '0';
  signal force_4502 : std_logic := '1';

  signal reg_mult_a : unsigned(24 downto 0) := (others => '0');
  signal reg_mult_b : unsigned(17 downto 0) := (others => '0');
  signal reg_mult_p : unsigned(47 downto 0) := (others => '0');

  signal monitor_char_toggle_internal : std_logic := '1';
  signal monitor_mem_attention_granted_internal : std_logic := '0';

  -- ZP/stack cache
  signal cache_we : std_logic := '0';
  signal cache_waddr : unsigned(9 downto 0);
  signal cache_raddr : unsigned(9 downto 0);
  signal cache_rdata : unsigned(35 downto 0);
  signal cache_wdata : unsigned(35 downto 0);
  signal cache_read_valid : std_logic := '0';
  signal cache_flushing : std_logic := '1';
  signal cache_flush_counter : unsigned(9 downto 0) := (others => '0');

  signal memory_access_address_next : unsigned(27 downto 0);
  signal memory_access_read_next : std_logic;
  signal memory_access_write_next : std_logic;
  signal memory_access_resolve_address_next : std_logic;
  signal memory_access_wdata_next : unsigned(7 downto 0);

  signal cycle_counter : unsigned(15 downto 0) := (others => '0');

  signal cpu_speed_bias : integer := 128;

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

-- Each math unit takes two inputs and gives one output.
-- The second input may be ignored for some math units.
-- Also, each math unit has the ability to be a 32 bit
  -- adder instead of its special function.
  -- Finally, each unit can be made to latch, and only output
  -- its value periodically, so that iterative functions can
  -- be executed.
  -- XXX Eventually we will add ability to trigger interrupts
  -- and suspend calculation based on the contents of at least
  -- one of the math registers
  type math_unit_config is record
    source_a : integer range 0 to 15;
    source_b : integer range 0 to 15;
    output : integer range 0 to 15;
    output_low : std_logic;
    output_high : std_logic;
    latched : std_logic;
    do_add : std_logic;
  end record;

  constant math_unit_count : integer := 16;  
  type math_reg_array is array(0 to 15) of unsigned(31 downto 0);   
  type math_config_array is array(0 to math_unit_count - 1) of math_unit_config;
  signal reg_math_regs : math_reg_array;
  signal reg_math_config : math_config_array;
  signal reg_math_config_drive : math_config_array;
  signal reg_math_latch_counter : unsigned(7 downto 0) := x"00";
  signal reg_math_latch_interval : unsigned(7 downto 0) := x"00";

  -- We have the output counter out of phase with the input counter, so that we
  -- have time to catch an output, and store it, ready for presenting as an input
  -- very soon after.
  signal math_input_counter : integer range 0 to 15 := 0;
  signal math_output_counter : integer range 0 to 15 := 3;
  signal prev_math_output_counter : integer range 0 to 15 := 2;

  signal math_input_number : integer range 0 to 15 := 0;
  signal math_input_value : unsigned(31 downto 0) := (others => '0');
  signal math_output_value_low : unsigned(31 downto 0) := (others => '0');
  signal math_output_value_high : unsigned(31 downto 0) := (others => '0');

  -- Start with input and outputting enabled
  signal math_unit_flags : unsigned(7 downto 0) := x"03";
  -- Each write to the math registers is passed to the math unit to handle
  -- (this is to avoid ISE doing really weird things in synthesis, thinking
  -- that each bit of each register was a clock or something similarly odd.)
  signal reg_math_write : std_logic := '0';
  signal reg_math_regnum : integer range 0 to 15 := 0;
  signal reg_math_regbyte : integer range 0 to 3 := 0;
  signal reg_math_write_value : unsigned(7 downto 0) := x"00";
  -- Count # of math cycles since cycle latch last written to
  signal reg_math_cycle_counter : unsigned(31 downto 0) := to_unsigned(0,32);
  signal reg_math_cycle_counter_plus_one : unsigned(31 downto 0) := to_unsigned(0,32);
  -- # of math cycles to trigger end of job / math interrupt
  signal reg_math_cycle_compare : unsigned(31 downto 0) := to_unsigned(0,32);

  signal badline_enable : std_logic := '1';
  signal slow_interrupts : std_logic := '1';

  signal request_monitor_halt_trigger : std_logic := '0';

  -- Simulated VDC access
  signal vdc_reg_num : unsigned(7 downto 0) := to_unsigned(0,8);
  signal vdc_mem_addr : unsigned(15 downto 0) := to_unsigned(0,16);
  -- fake VDC status register that claims "always ready"
  signal vdc_status : unsigned(7 downto 0) := x"80";
  
begin

  monitor_cpuport <= cpuport_value(2 downto 0);

  multipliers: for unit in 0 to 7 generate
    mult_unit : entity work.multiply32 port map (
      clock => mathclock,
      unit => unit,
      do_add => reg_math_config_drive(unit).do_add,
      input_a => reg_math_config_drive(unit).source_a,
      input_b => reg_math_config_drive(unit).source_b,
      input_value_number => math_input_number,
      input_value => math_input_value,
      output_select => math_output_counter,
      output_value(31 downto 0) => math_output_value_low,
      output_value(63 downto 32) => math_output_value_high
      );
  end generate;

  shifters: for unit in 8 to 11 generate
    mult_unit : entity work.shifter32 port map (
      clock => mathclock,
      unit => unit,
      do_add => reg_math_config_drive(unit).do_add,
      input_a => reg_math_config_drive(unit).source_a,
      input_b => reg_math_config_drive(unit).source_b,
      input_value_number => math_input_number,
      input_value => math_input_value,
      output_select => math_output_counter,
      output_value(31 downto 0) => math_output_value_low,
      output_value(63 downto 32) => math_output_value_high
      );
  end generate;

  dividerrs: for unit in 12 to 15 generate
    mult_unit : entity work.divider32 port map (
      clock => mathclock,
      unit => unit,
      do_add => reg_math_config_drive(unit).do_add,
      input_a => reg_math_config_drive(unit).source_a,
      input_b => reg_math_config_drive(unit).source_b,
      input_value_number => math_input_number,
      input_value => math_input_value,
      output_select => math_output_counter,
      output_value(31 downto 0) => math_output_value_low,
      output_value(63 downto 32) => math_output_value_high
      );
  end generate;
  
  shadowram0 : entity work.shadowram port map (
    clkA      => clock,
    addressa  => shadow_address_next,
    wea       => shadow_write_next,
    dia       => memory_access_wdata_next,
    no_writes => shadow_no_write_count,
    writes    => shadow_write_count,
    doa       => shadow_rdata,
    clkB      => chipram_clk,
    addressb  => chipram_address,
    dob       => chipram_dataout
    );

  zpcache0: entity work.ram36x1k port map (
    clkl => clock,
    clkr => clock,
    wel(0) => cache_we,
    addrl => std_logic_vector(cache_waddr),
    addrr => std_logic_vector(cache_raddr),
    unsigned(doutr) => cache_rdata,
    dinl => std_logic_vector(cache_wdata)
    );    
  
  process(clock,reset,reg_a,reg_x,reg_y,reg_z,flag_c,phi0_export,all_pause)
    procedure disassemble_last_instruction is
      variable justification : side := RIGHT;
      variable size : width := 0;
      variable s : string(1 to 119) := (others => ' ');
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

        -- Show hypervisor/user mode flag
        if hypervisor_mode='1' then
          s(109) := 'H';
        else
          s(109) := 'U';
        end if;

        -- Show current CPU speed
        s(111 to 113) := "000";
        if vicii_2mhz='1' then s(111) := '1'; end if;
        if viciii_fast='1' then s(112) := '1'; end if;
        if viciv_fast='1' then s(113) := '1'; end if;
        s(115 to 116) := to_hstring(cpuspeed_internal);
        s(117 to 119) := "MHz";
        
        -- Display disassembly
        report s severity note;
      end if;
--pragma synthesis_on
    end procedure;

    procedure reset_cpu_state is
    begin
      -- Set microcode state for reset

      -- Enable chipselect for all peripherals and memories
      chipselect_enables <= x"EF";
--      cartridge_enable <= '0';
      hyper_protected_hardware <= x"00";
      
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

      -- Clear CPU MMU registers, and bank in hyppo ROM
      -- XXX Need to update this for hypervisor mode
      if no_hyppo='1' then
        -- no hyppo
        reg_offset_high <= x"000";
        reg_map_high <= "0000";
        reg_offset_low <= x"000";
        reg_map_low <= "0000";
        reg_mb_high <= x"00";
        reg_mb_low <= x"00";
      else
        -- with hyppo
        reg_offset_high <= x"F00";
        reg_map_high <= "1000";
        reg_offset_low <= x"000";
        reg_map_low <= "0100";
        reg_mb_high <= x"FF";
        reg_mb_low <= x"80";
      end if;
      
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
      --chipram_we <= '0';        
      --chipram_datain <= x"c0";    

      slow_access_request_toggle_drive <= slow_access_ready_toggle_buffer;
      slow_access_write_drive <= '0';
      slow_access_address_drive <= (others => '1');
      slow_access_wdata_drive <= (others => '1');
      slow_access_desired_ready_toggle <= slow_access_ready_toggle;
      
      wait_states <= (others => '0');
      wait_states_non_zero <= '0';
      mem_reading <= '0';
      
    end procedure reset_cpu_state;

    procedure check_for_interrupts is
    begin
      -- No interrupts of any sort between MAP and EOM instructions.
      if map_interrupt_inhibit='0' then
        -- NMI is edge triggered.
        if (nmi = '0' and nmi_state = '1') and (irq_defer_active='0') then
          nmi_pending <= '1';        
        end if;
        nmi_state <= nmi;
        -- IRQ is level triggered.
        if ((irq = '0') and (flag_i='0')) and (irq_defer_active='0') then
          irq_pending <= '1';
        else
          irq_pending <= '0';
        end if;
      else
        irq_pending <= '0';
      end if;

      -- Allow hypervisor to ban interrupts for 65,535 48MHz CPU cycles,
      -- i.e., ~1,365 1MHz CPU cycles, i.e., ~1.37ms.  This is intended mainly
      -- to be used by the hypervisor when passing control to the C64/C65 ROM
      -- on boot, so that the IRQ/NMI vectors can be setup, before any
      -- interrupt can occur.  The CIA and VIC chips now also properly clear
      -- interrupts on reset, so hopefully this won't be needed, but it is a
      -- good insurance policy in any case, including if some dill hits RESTORE
      -- too fast during boot, which is also a hazard on a real C64/C65.
      if irq_defer_request = '1' then
        irq_defer_counter <= 65535;
      else
        if irq_defer_counter = 0 then
          irq_defer_active <= '0';
        else
          irq_defer_active <= '1';
          irq_defer_counter <= irq_defer_counter - 1;
        end if;
      end if;
      
    end procedure check_for_interrupts;

    procedure read_long_address(
      real_long_address : in unsigned(27 downto 0)) is
      variable long_address : unsigned(27 downto 0);
    begin

      last_action <= 'R'; last_address <= real_long_address;
      
      -- Stop writing when reading.     
      fastio_write <= '0'; shadow_write <= '0';

      long_address := long_address_read;
      
      report "Reading from long address $" & to_hstring(long_address) severity note;
      mem_reading <= '1';
      
      -- Schedule the memory read from the appropriate source.
      accessing_fastio <= '0'; accessing_vic_fastio <= '0';
      accessing_cpuport <= '0'; accessing_colour_ram_fastio <= '0';
      accessing_slowram <= '0'; accessing_hypervisor <= '0';
      slow_access_pending_write <= '0';
      slow_access_write_drive <= '0';
      charrom_write_cs <= '0';

      wait_states <= io_read_wait_states;
      if io_read_wait_states /= x"00" then
        wait_states_non_zero <= '1';
      else
        wait_states_non_zero <= '0';
      end if; 
      
      -- Clear fastio access so that we don't keep reading/writing last IO address
      -- (this is bad when it is $DC0D for example, as it will stop IRQs from
      -- the CIA).
      fastio_addr <= x"FFFFF"; fastio_write <= '0'; fastio_read <= '0';
      
      the_read_address <= long_address;

      -- Get the shadow RAM or ROM address on the bus fast to improve timing.
      shadow_write <= '0';
      shadow_write_flags(1) <= '1';

      report "MEMORY long_address = $" & to_hstring(long_address);
      -- @IO:C64 $0000000 CPU:PORTDDR 6510/45GS10 CPU port DDR
      -- @IO:C64 $0000001 CPU:PORT 6510/45GS10 CPU port data
      if long_address(27 downto 6)&"00" = x"FFD364" and hypervisor_mode='1' then
        report "Preparing for reading hypervisor register";
        read_source <= HypervisorRegister;
        accessing_hypervisor <= '1';
        -- One cycle wait-state on hypervisor registers to remove the register
        -- decode from the critical path of memory access.
        wait_states <= x"01";
        wait_states_non_zero <= '1';
        proceed <= '0';
        hyperport_num <= real_long_address(5 downto 0);
      elsif (long_address = x"ffd0600") then
        -- Read VDC status #141
        -- Lie and always claim that VDC is ready
        read_source <= CPUPort;
        wait_states <= x"01";
        wait_states_non_zero <= '1';
        proceed <= '0';
        cpuport_num <= x"3";
      elsif (long_address = x"ffd0601") then
        if vdc_reg_num = x"1f" then
          report "Preparing to read from Shadow for simulated VDC access";
          shadow_address <= to_integer(vdc_mem_addr)+(4*65536);
          vdc_mem_addr <= vdc_mem_addr + 1;
          read_source <= Shadow;
          accessing_shadow <= '1';
          accessing_rom <= '0';
          -- XXX Allow time for access to shadow RAM to complete
          wait_states <= x"01";
          wait_states_non_zero <= '1';
          proceed <= '0';
        else
          -- Read simulated VDC registers
          read_source <= CPUPort;
          wait_states <= x"01";
          wait_states_non_zero <= '1';
          proceed <= '0';
          cpuport_num <= x"4";
        end if;
      elsif (long_address(27 downto 4) = x"ffd060") then
        -- Debug VDC and other CPU port things
        read_source <= CPUPort;
        wait_states <= x"01";
        wait_states_non_zero <= '1';
        proceed <= '0';
        cpuport_num <= long_address(3 downto 0);        
      elsif (long_address = x"0000000") or (long_address = x"0000001") then
        accessing_cpuport <= '1';
        report "Preparing to read from a CPUPort";
        read_source <= CPUPort;
        -- One cycle wait-state on hypervisor registers to remove the register
        -- decode from the critical path of memory access.
        wait_states <= x"01";
        wait_states_non_zero <= '1';
        proceed <= '0';
        cpuport_num <= real_long_address(3 downto 0);
      elsif (long_address = x"ffd30a0") or (long_address = x"ffd10a0") then
        accessing_cpuport <= '1';
        report "Preparing to read from CPU memory expansion controller port";
        read_source <= CPUPort;
        -- One cycle wait-state on hypervisor registers to remove the register
        -- decode from the critical path of memory access.
        wait_states <= x"01";
        wait_states_non_zero <= '1';
        proceed <= '0';
        cpuport_num <= "0010";        
      elsif long_address(27 downto 4) = x"400000" then
        -- More CPU ports for debugging.
        -- (this was added to debug CIA IRQ bugs where reading/writing from
        -- fastio space would prevent the bug from manifesting)
        report "Preparing to read from a CPUPort";
        read_source <= CPUPort;
        accessing_cpuport <= '1';
        -- One cycle wait-state on hypervisor registers to remove the register
        -- decode from the critical path of memory access.
        wait_states <= x"01";
        wait_states_non_zero <= '1';
        proceed <= '0';
        cpuport_num <= real_long_address(3 downto 0);
      elsif long_address(27 downto 20)=x"00" and ((not long_address(19)) or chipram_1mb)='1' then
        -- Reading from chipram
        -- @ IO:C64 $0000002-$000FFFF - 64KB RAM
        -- @ IO:C65 $0010000-$001FFFF - 64KB RAM
        -- @ IO:C65 $0020000-$003FFFF - 128KB ROM (can be used as RAM in M65 mode)
        -- @ IO:C65 $002A000-$002BFFF - 8KB C64 BASIC ROM
        -- @ IO:C65 $002D000-$002DFFF - 4KB C64 CHARACTER ROM
        -- @ IO:C65 $002E000-$002FFFF - 8KB C64 KERNAL ROM
        -- @ IO:C65 $003E000-$003FFFF - 8KB C65 KERNAL ROM
        -- @ IO:C65 $003C000-$003CFFF - 4KB C65 KERNAL/INTERFACE ROM
        -- @ IO:C65 $0038000-$003BFFF - 8KB C65 BASIC GRAPHICS ROM
        -- @ IO:C65 $0032000-$0035FFF - 8KB C65 BASIC ROM
        -- @ IO:C65 $0030000-$0031FFF - 16KB C65 DOS ROM
        -- @ IO:M65 $0040000-$005FFFF - 128KB RAM (in place of C65 cartridge support)
        report "Preparing to read from Shadow";
        shadow_address <= shadow_address_next;
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
                                        --Also mapped to 7F2 0000 - 7F3 FFFF
      elsif long_address(27 downto 20) = x"FF" then
        report "Preparing to read from FastIO";
        read_source <= FastIO;
        accessing_shadow <= '0';
        accessing_rom <= '0';
        accessing_fastio <= '1';
        accessing_vic_fastio <= '0';
        accessing_colour_ram_fastio <= '0';
        accessing_hyppo_fastio <= '0';

        fastio_addr <= fastio_addr_next;
        last_fastio_addr <= fastio_addr_next;
        fastio_read <= '1';
        proceed <= '0';
        
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

        report "Checking if address requires vfpga waitstates: $" & to_hstring(long_address);

        
        -- @IO:GS $FF80000-$FF87FFF SUMMARY:COLOURRAM Colour RAM (32KB or 64KB)
        if long_address(19 downto 16) = x"8" then
          report "VIC 64KB colour RAM access from VIC fastio" severity note;
          accessing_colour_ram_fastio <= '1';
          report "Preparing to read from ColourRAM";
          read_source <= ColourRAM;
          colour_ram_cs <= '1';
          wait_states <= colourram_read_wait_states;
          if colourram_read_wait_states /= x"00" then
            wait_states_non_zero <= '1';
          else
            wait_states_non_zero <= '0';
          end if;
        end if;
        -- @IO:GS $FFF8000-$FFFBFFF SUMMARY:HYPERVISOR 16KB Hyppo/Hypervisor ROM
        if long_address(19 downto 14)&"00" = x"F8" then
          accessing_fastio <= '0';
          fastio_read <= '0';
          accessing_hyppo_fastio <= '1';
          read_source <= Hyppo;
          hyppo_address <= hyppo_address_next;          
        end if;
        if long_address(19 downto 16) = x"D" then
          if long_address(15 downto 14) = "00" then    --   $D{0,1,2,3}XXX
            if long_address(11 downto 10) = "00" then  --   $D{0,1,2,3}{0,1,2,3}XX
              if long_address(11 downto 7) /= "00001" then  -- ! $D.0{8-F}X (FDC, RAM EX)
                report "VIC register from VIC fastio" severity note;
                accessing_vic_fastio <= '1';
                report "Preparing to read from VICIV";
                read_source <= VICIV;
              end if;            
            end if;

            -- Palette RAM access (requires extra wait state, just like colour
            -- RAM, because it comes from a BRAM)
            if (long_address(11 downto 8) = x"1")
              or (long_address(11 downto 8) = x"2")
              or (long_address(11 downto 8) = x"3") then
              wait_states <= palette_read_wait_states;
              if palette_read_wait_states /= x"00" then
                wait_states_non_zero <= '1';
              else
                wait_states_non_zero <= '0';
              end if;
            end if;
            
            -- Colour RAM at $D800-$DBFF and optionally $DC00-$DFFF
            if long_address(11)='1' then
              if (long_address(10)='0') or (colourram_at_dc00='1') then
                report "RAM: D800-DBFF/DC00-DFFF colour ram access from VIC fastio" severity note;
                accessing_colour_ram_fastio <= '1';
                report "Preparing to read from ColourRAM";
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
          elsif long_address(19 downto 12) = x"DF" then
            -- VFPGA interface
            report "Adding wait-states for vfpga interface";
            wait_states <= colourram_read_wait_states;
            if colourram_read_wait_states /= x"00" then
              wait_states_non_zero <= '1';
            else
              wait_states_non_zero <= '0';
            end if;
          end if;
        end if;                           -- $DXXXX
      elsif (long_address(27) = '1' or long_address(26)='1') and hyper_protected_hardware(7)='0' then
        -- @IO:GS $4000000 - $7FFFFFF SUMMARY:SLOWDEV Slow Device memory (64MB)
        -- @IO:GS $8000000 - $FEFFFFF SUMMARY:SLOWDEV Slow Device memory (127MB)
        -- (But not accessible in secure compartment)
        report "Preparing to read from SlowRAM";
        read_source <= SlowRAM;
        accessing_shadow <= '0';
        accessing_rom <= '0';
        accessing_slowram <= '1';
        slow_access_data_ready <= '0';
        slow_access_address_drive <= long_address(27 downto 0);
        slow_access_write_drive <= '0';
        slow_access_request_toggle_drive <= not slow_access_request_toggle_drive;
        slow_access_desired_ready_toggle <= not slow_access_desired_ready_toggle;
        wait_states <= x"FF";
        wait_states_non_zero <= '1';
        proceed <= '0';
      else
        -- Don't let unmapped memory jam things up
        report "hit unmapped memory -- clearing wait_states" severity note;
        report "Preparing to read from Unmapped";
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
      if (long_address(27 downto 8) = x"FFD17") or (long_address(27 downto 8) = x"FFD37") then
        report "Preparing to read from a DMAgicRegister";
        read_source <= DMAgicRegister;
      end if;      

    end read_long_address;
    
    -- purpose: obtain the byte of memory that has been read
    impure function read_data_complex
      return unsigned is
      variable value : unsigned(7 downto 0);
    begin  -- read_data
      -- CPU hosted IO registers
      report "Read source is " & memory_source'image(read_source);
      case read_source is
        when DMAgicRegister =>
          -- Actually, this is all of $D700-$D7FF decoded by the CPU at present
          report "Reading CPU register (DMAgicRegister path)";
          case the_read_address(7 downto 0) is
            when x"00"|x"05" => return reg_dmagic_addr(7 downto 0);
            when x"01" => return reg_dmagic_addr(15 downto 8);
            when x"02" => return reg_dmagic_withio
                            & reg_dmagic_addr(22 downto 16);
            when x"03" => return reg_dmagic_status(7 downto 1) & support_f018b;
            when x"04" => return reg_dmagic_addr(27 downto 20);

            -- $D770-$D7DF reserved for math unit functions
            when x"70" => return reg_mult_a(7 downto 0);
            when x"71" => return reg_mult_a(15 downto 8);
            when x"72" => return reg_mult_a(23 downto 16);
            when x"73" => return to_unsigned(to_integer(reg_mult_a(24 downto 24)),8);
            when x"74" => return reg_mult_b(7 downto 0);
            when x"75" => return reg_mult_b(15 downto 8);
            when x"76" => return to_unsigned(to_integer(reg_mult_b(17 downto 16)),8);
            when x"77" => return x"00";
            -- @IO:GS $D770 MATH:MULTINA Multiplier input A (25 bit)
            -- @IO:GS $D771 MATH:MULTINA Multiplier input A (25 bit)
            -- @IO:GS $D772 MATH:MULTINA Multiplier input A (25 bit)
            -- @IO:GS $D773.0 MATH:MULTINA Multiplier input A (25 bit)
            -- @IO:GS $D774 MATH:MULTINB Multiplier input A (18 bit)
            -- @IO:GS $D775 MATH:MULTINB Multiplier input A (18 bit)
            -- @IO:GS $D776.0-1 MATH:MULTINB Multiplier input A (18 bit)
            -- @IO:GS $D778 MATH:MULTOUT 48-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D779 MATH:MULTOUT 48-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77A MATH:MULTOUT 48-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77B MATH:MULTOUT 48-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77C MATH:MULTOUT 48-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77D MATH:MULTOUT 48-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77E MATH:MULTOUT 48-bit output of MULTINA $\times$ MULTINB

            when x"78" => return reg_mult_p(7 downto 0);
            when x"79" => return reg_mult_p(15 downto 8);
            when x"7a" => return reg_mult_p(23 downto 16);
            when x"7b" => return reg_mult_p(31 downto 24);
            when x"7c" => return reg_mult_p(39 downto 32);
            when x"7d" => return reg_mult_p(47 downto 40);
            when x"7e" => return x"00";
            when x"7f" => return x"00";
            -- @IO:GS $D780-$D7BF - 16 x 32 bit Math Unit values
            -- @IO:GS $D780 MATH:MATHIN0 Math unit 32-bit input 0
            -- @IO:GS $D781 MATH:MATHIN0 Math unit 32-bit input 0
            -- @IO:GS $D782 MATH:MATHIN0 Math unit 32-bit input 0
            -- @IO:GS $D783 MATH:MATHIN0 Math unit 32-bit input 0
            -- @IO:GS $D784 MATH:MATHIN1 Math unit 32-bit input 1
            -- @IO:GS $D785 MATH:MATHIN1 Math unit 32-bit input 1
            -- @IO:GS $D786 MATH:MATHIN1 Math unit 32-bit input 1
            -- @IO:GS $D787 MATH:MATHIN1 Math unit 32-bit input 1
            -- @IO:GS $D788 MATH:MATHIN2 Math unit 32-bit input 2
            -- @IO:GS $D789 MATH:MATHIN2 Math unit 32-bit input 2
            -- @IO:GS $D78A MATH:MATHIN2 Math unit 32-bit input 2
            -- @IO:GS $D78B MATH:MATHIN2 Math unit 32-bit input 2
            -- @IO:GS $D78C MATH:MATHIN3 Math unit 32-bit input 3
            -- @IO:GS $D78D MATH:MATHIN3 Math unit 32-bit input 3
            -- @IO:GS $D78E MATH:MATHIN3 Math unit 32-bit input 3
            -- @IO:GS $D78F MATH:MATHIN3 Math unit 32-bit input 3
            -- @IO:GS $D790 MATH:MATHIN4 Math unit 32-bit input 4
            -- @IO:GS $D791 MATH:MATHIN4 Math unit 32-bit input 4
            -- @IO:GS $D792 MATH:MATHIN4 Math unit 32-bit input 4
            -- @IO:GS $D793 MATH:MATHIN4 Math unit 32-bit input 4
            -- @IO:GS $D794 MATH:MATHIN5 Math unit 32-bit input 5
            -- @IO:GS $D795 MATH:MATHIN5 Math unit 32-bit input 5
            -- @IO:GS $D796 MATH:MATHIN5 Math unit 32-bit input 5
            -- @IO:GS $D797 MATH:MATHIN5 Math unit 32-bit input 5
            -- @IO:GS $D798 MATH:MATHIN6 Math unit 32-bit input 6
            -- @IO:GS $D799 MATH:MATHIN6 Math unit 32-bit input 6
            -- @IO:GS $D79A MATH:MATHIN6 Math unit 32-bit input 6
            -- @IO:GS $D79B MATH:MATHIN6 Math unit 32-bit input 6
            -- @IO:GS $D79C MATH:MATHIN7 Math unit 32-bit input 7
            -- @IO:GS $D79D MATH:MATHIN7 Math unit 32-bit input 7
            -- @IO:GS $D79E MATH:MATHIN7 Math unit 32-bit input 7
            -- @IO:GS $D79F MATH:MATHIN7 Math unit 32-bit input 7
            -- @IO:GS $D7A0 MATH:MATHIN8 Math unit 32-bit input 8
            -- @IO:GS $D7A1 MATH:MATHIN8 Math unit 32-bit input 8
            -- @IO:GS $D7A2 MATH:MATHIN8 Math unit 32-bit input 8
            -- @IO:GS $D7A3 MATH:MATHIN8 Math unit 32-bit input 8
            -- @IO:GS $D7A4 MATH:MATHIN9 Math unit 32-bit input 9
            -- @IO:GS $D7A5 MATH:MATHIN9 Math unit 32-bit input 9
            -- @IO:GS $D7A6 MATH:MATHIN9 Math unit 32-bit input 9
            -- @IO:GS $D7A7 MATH:MATHIN9 Math unit 32-bit input 9
            -- @IO:GS $D7A8 MATH:MATHIN10 Math unit 32-bit input 10
            -- @IO:GS $D7A9 MATH:MATHIN10 Math unit 32-bit input 10
            -- @IO:GS $D7AA MATH:MATHIN10 Math unit 32-bit input 10
            -- @IO:GS $D7AB MATH:MATHIN10 Math unit 32-bit input 10
            -- @IO:GS $D7AC MATH:MATHIN11 Math unit 32-bit input 11
            -- @IO:GS $D7AD MATH:MATHIN11 Math unit 32-bit input 11
            -- @IO:GS $D7AE MATH:MATHIN11 Math unit 32-bit input 11
            -- @IO:GS $D7AF MATH:MATHIN11 Math unit 32-bit input 11
            -- @IO:GS $D7B0 MATH:MATHIN12 Math unit 32-bit input 12
            -- @IO:GS $D7B1 MATH:MATHIN12 Math unit 32-bit input 12
            -- @IO:GS $D7B2 MATH:MATHIN12 Math unit 32-bit input 12
            -- @IO:GS $D7B3 MATH:MATHIN12 Math unit 32-bit input 12
            -- @IO:GS $D7B4 MATH:MATHIN13 Math unit 32-bit input 13
            -- @IO:GS $D7B5 MATH:MATHIN13 Math unit 32-bit input 13
            -- @IO:GS $D7B6 MATH:MATHIN13 Math unit 32-bit input 13
            -- @IO:GS $D7B7 MATH:MATHIN13 Math unit 32-bit input 13
            -- @IO:GS $D7B8 MATH:MATHIN14 Math unit 32-bit input 14
            -- @IO:GS $D7B9 MATH:MATHIN14 Math unit 32-bit input 14
            -- @IO:GS $D7BA MATH:MATHIN14 Math unit 32-bit input 14
            -- @IO:GS $D7BB MATH:MATHIN14 Math unit 32-bit input 14
            -- @IO:GS $D7BC MATH:MATHIN15 Math unit 32-bit input 15
            -- @IO:GS $D7BD MATH:MATHIN15 Math unit 32-bit input 15
            -- @IO:GS $D7BE MATH:MATHIN15 Math unit 32-bit input 15
            -- @IO:GS $D7BF MATH:MATHIN15 Math unit 32-bit input 15
            when
              x"80"|x"81"|x"82"|x"83"|x"84"|x"85"|x"86"|x"87"|
              x"88"|x"89"|x"8A"|x"8B"|x"8C"|x"8D"|x"8E"|x"8F"|
              x"90"|x"91"|x"92"|x"93"|x"94"|x"95"|x"96"|x"97"|
              x"98"|x"99"|x"9A"|x"9B"|x"9C"|x"9D"|x"9E"|x"9F"|
              x"A0"|x"A1"|x"A2"|x"A3"|x"A4"|x"A5"|x"A6"|x"A7"|
              x"A8"|x"A9"|x"AA"|x"AB"|x"AC"|x"AD"|x"AE"|x"AF"|
              x"B0"|x"B1"|x"B2"|x"B3"|x"B4"|x"B5"|x"B6"|x"B7"|
              x"B8"|x"B9"|x"BA"|x"BB"|x"BC"|x"BD"|x"BE"|x"BF" =>
              case the_read_address(1 downto 0) is
                when "00" => return reg_math_regs(to_integer(the_read_address(5 downto 2)))(7 downto 0);              
                when "01" => return reg_math_regs(to_integer(the_read_address(5 downto 2)))(15 downto 8);
                when "10" => return reg_math_regs(to_integer(the_read_address(5 downto 2)))(23 downto 16);
                when "11" => return reg_math_regs(to_integer(the_read_address(5 downto 2)))(31 downto 24);
                when others => return x"59";
              end case;
            when
              --@IO:GS $D7C0-$D7CF - 16 Math function unit input A (3-0) and input B (7-4) selects
              -- @IO:GS $D7C0.0-3 MATH:UNIT0INA Select which of the 16 32-bit math registers is input A for Math Function Unit 0.
              -- @IO:GS $D7C0.4-7 MATH:UNIT0INB Select which of the 16 32-bit math registers is input B for Math Function Unit 0.
              -- @IO:GS $D7C1.0-3 MATH:UNIT1INA Select which of the 16 32-bit math registers is input A for Math Function Unit 1.
              -- @IO:GS $D7C1.4-7 MATH:UNIT1INB Select which of the 16 32-bit math registers is input B for Math Function Unit 1.
              -- @IO:GS $D7C2.0-3 MATH:UNIT2INA Select which of the 16 32-bit math registers is input A for Math Function Unit 2.
              -- @IO:GS $D7C2.4-7 MATH:UNIT2INB Select which of the 16 32-bit math registers is input B for Math Function Unit 2.
              -- @IO:GS $D7C3.0-3 MATH:UNIT3INA Select which of the 16 32-bit math registers is input A for Math Function Unit 3.
              -- @IO:GS $D7C3.4-7 MATH:UNIT3INB Select which of the 16 32-bit math registers is input B for Math Function Unit 3.
              -- @IO:GS $D7C4.0-3 MATH:UNIT4INA Select which of the 16 32-bit math registers is input A for Math Function Unit 4.
              -- @IO:GS $D7C4.4-7 MATH:UNIT4INB Select which of the 16 32-bit math registers is input B for Math Function Unit 4.
              -- @IO:GS $D7C5.0-3 MATH:UNIT5INA Select which of the 16 32-bit math registers is input A for Math Function Unit 5.
              -- @IO:GS $D7C5.4-7 MATH:UNIT5INB Select which of the 16 32-bit math registers is input B for Math Function Unit 5.
              -- @IO:GS $D7C6.0-3 MATH:UNIT6INA Select which of the 16 32-bit math registers is input A for Math Function Unit 6.
              -- @IO:GS $D7C6.4-7 MATH:UNIT6INB Select which of the 16 32-bit math registers is input B for Math Function Unit 6.
              -- @IO:GS $D7C7.0-3 MATH:UNIT7INA Select which of the 16 32-bit math registers is input A for Math Function Unit 7.
              -- @IO:GS $D7C7.4-7 MATH:UNIT7INB Select which of the 16 32-bit math registers is input B for Math Function Unit 7.
              -- @IO:GS $D7C8.0-3 MATH:UNIT8INA Select which of the 16 32-bit math registers is input A for Math Function Unit 8.
              -- @IO:GS $D7C8.4-7 MATH:UNIT8INB Select which of the 16 32-bit math registers is input B for Math Function Unit 8.
              -- @IO:GS $D7C9.0-3 MATH:UNIT9INA Select which of the 16 32-bit math registers is input A for Math Function Unit 9.
              -- @IO:GS $D7C9.4-7 MATH:UNIT9INB Select which of the 16 32-bit math registers is input B for Math Function Unit 9.
              -- @IO:GS $D7CA.0-3 MATH:UNIT10INA Select which of the 16 32-bit math registers is input A for Math Function Unit 10.
              -- @IO:GS $D7CA.4-7 MATH:UNIT10INB Select which of the 16 32-bit math registers is input B for Math Function Unit 10.
              -- @IO:GS $D7CB.0-3 MATH:UNIT11INA Select which of the 16 32-bit math registers is input A for Math Function Unit 11.
              -- @IO:GS $D7CB.4-7 MATH:UNIT11INB Select which of the 16 32-bit math registers is input B for Math Function Unit 11.
              -- @IO:GS $D7CC.0-3 MATH:UNIT12INA Select which of the 16 32-bit math registers is input A for Math Function Unit 12.
              -- @IO:GS $D7CC.4-7 MATH:UNIT12INB Select which of the 16 32-bit math registers is input B for Math Function Unit 12.
              -- @IO:GS $D7CD.0-3 MATH:UNIT13INA Select which of the 16 32-bit math registers is input A for Math Function Unit 13.
              -- @IO:GS $D7CD.4-7 MATH:UNIT13INB Select which of the 16 32-bit math registers is input B for Math Function Unit 13.
              -- @IO:GS $D7CE.0-3 MATH:UNIT14INA Select which of the 16 32-bit math registers is input A for Math Function Unit 14.
              -- @IO:GS $D7CE.4-7 MATH:UNIT14INB Select which of the 16 32-bit math registers is input B for Math Function Unit 14.
              -- @IO:GS $D7CF.0-3 MATH:UNIT15INA Select which of the 16 32-bit math registers is input A for Math Function Unit 15.
              -- @IO:GS $D7CF.4-7 MATH:UNIT15INB Select which of the 16 32-bit math registers is input B for Math Function Unit 15.
              x"C0"|x"C1"|x"C2"|x"C3"|x"C4"|x"C5"|x"C6"|x"C7"|
              x"C8"|x"C9"|x"CA"|x"CB"|x"CC"|x"CD"|x"CE"|x"CF" =>
              return
                to_unsigned(reg_math_config(to_integer(the_read_address(3 downto 0))).source_b,4)
                &to_unsigned(reg_math_config(to_integer(the_read_address(3 downto 0))).source_a,4);
            when
              -- @IO:GS $D7D0.0-3 MATH:UNIT0OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit 0
              -- @IO:GS $D7D0.4 - MATH:U0LOWOUT If set, the low-half of the output of Math Function Unit 0 is written to math register UNIT0OUT.
              -- @IO:GS $D7D0.5 - MATH:U0HIOUT If set, the high-half of the output of Math Function Unit 0 is written to math register UNIT0OUT.
              -- @IO:GS $D7D0.6 - MATH:U0ADD If set, Math Function Unit 0 acts as a 32-bit adder instead of 32-bit multiplier.
              -- @IO:GS $D7D0.7 - MATH:U0LATCH If set, Math Function Unit 0's output is latched.
              
              -- @IO:GS $D7D1.0-3 MATH:UNIT1OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit 1
              -- @IO:GS $D7D1.4 - MATH:U1LOWOUT If set, the low-half of the output of Math Function Unit 1 is written to math register UNIT1OUT.
              -- @IO:GS $D7D1.5 - MATH:U1HIOUT If set, the high-half of the output of Math Function Unit 1 is written to math register UNIT1OUT.
              -- @IO:GS $D7D1.6 - MATH:U1ADD If set, Math Function Unit 1 acts as a 32-bit adder instead of 32-bit multiplier.
              -- @IO:GS $D7D1.7 - MATH:U1LATCH If set, Math Function Unit 1's output is latched.
              
              -- @IO:GS $D7D2.0-3 MATH:UNIT2OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit 2
              -- @IO:GS $D7D2.4 - MATH:U2LOWOUT If set, the low-half of the output of Math Function Unit 2 is written to math register UNIT2OUT.
              -- @IO:GS $D7D2.5 - MATH:U2HIOUT If set, the high-half of the output of Math Function Unit 2 is written to math register UNIT2OUT.
              -- @IO:GS $D7D2.6 - MATH:U2ADD If set, Math Function Unit 2 acts as a 32-bit adder instead of 32-bit multiplier.
              -- @IO:GS $D7D2.7 - MATH:U2LATCH If set, Math Function Unit 2's output is latched.
              
              -- @IO:GS $D7D3.0-3 MATH:UNIT3OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit 3
              -- @IO:GS $D7D3.4 - MATH:U3LOWOUT If set, the low-half of the output of Math Function Unit 3 is written to math register UNIT3OUT.
              -- @IO:GS $D7D3.5 - MATH:U3HIOUT If set, the high-half of the output of Math Function Unit 3 is written to math register UNIT3OUT.
              -- @IO:GS $D7D3.6 - MATH:U3ADD If set, Math Function Unit 3 acts as a 32-bit adder instead of 32-bit multiplier.
              -- @IO:GS $D7D3.7 - MATH:U3LATCH If set, Math Function Unit 3's output is latched.
              
              -- @IO:GS $D7D4.0-3 MATH:UNIT4OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit 4
              -- @IO:GS $D7D4.4 - MATH:U4LOWOUT If set, the low-half of the output of Math Function Unit 4 is written to math register UNIT4OUT.
              -- @IO:GS $D7D4.5 - MATH:U4HIOUT If set, the high-half of the output of Math Function Unit 4 is written to math register UNIT4OUT.
              -- @IO:GS $D7D4.6 - MATH:U4ADD If set, Math Function Unit 4 acts as a 32-bit adder instead of 32-bit multiplier.
              -- @IO:GS $D7D4.7 - MATH:U4LATCH If set, Math Function Unit 4's output is latched.
              
              -- @IO:GS $D7D5.0-3 MATH:UNIT5OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit 5
              -- @IO:GS $D7D5.4 - MATH:U5LOWOUT If set, the low-half of the output of Math Function Unit 5 is written to math register UNIT5OUT.
              -- @IO:GS $D7D5.5 - MATH:U5HIOUT If set, the high-half of the output of Math Function Unit 5 is written to math register UNIT5OUT.
              -- @IO:GS $D7D5.6 - MATH:U5ADD If set, Math Function Unit 5 acts as a 32-bit adder instead of 32-bit multiplier.
              -- @IO:GS $D7D5.7 - MATH:U5LATCH If set, Math Function Unit 5's output is latched.
              
              -- @IO:GS $D7D6.0-3 MATH:UNIT6OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit 6
              -- @IO:GS $D7D6.4 - MATH:U6LOWOUT If set, the low-half of the output of Math Function Unit 6 is written to math register UNIT6OUT.
              -- @IO:GS $D7D6.5 - MATH:U6HIOUT If set, the high-half of the output of Math Function Unit 6 is written to math register UNIT6OUT.
              -- @IO:GS $D7D6.6 - MATH:U6ADD If set, Math Function Unit 6 acts as a 32-bit adder instead of 32-bit multiplier.
              -- @IO:GS $D7D6.7 - MATH:U6LATCH If set, Math Function Unit 6's output is latched.
              
              -- @IO:GS $D7D7.0-3 MATH:UNIT7OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit 7
              -- @IO:GS $D7D7.4 - MATH:U7LOWOUT If set, the low-half of the output of Math Function Unit 7 is written to math register UNIT7OUT.
              -- @IO:GS $D7D7.5 - MATH:U7HIOUT If set, the high-half of the output of Math Function Unit 7 is written to math register UNIT7OUT.
              -- @IO:GS $D7D7.6 - MATH:U7ADD If set, Math Function Unit 7 acts as a 32-bit adder instead of 32-bit multiplier.
              -- @IO:GS $D7D7.7 - MATH:U7LATCH If set, Math Function Unit 7's output is latched.
              
              -- @IO:GS $D7D8.0-3 MATH:UNIT8OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit 8
              -- @IO:GS $D7D8.4 - MATH:U8LOWOUT If set, the low-half of the output of Math Function Unit 8 is written to math register UNIT8OUT.
              -- @IO:GS $D7D8.5 - MATH:U8HIOUT If set, the high-half of the output of Math Function Unit 8 is written to math register UNIT8OUT.
              -- @IO:GS $D7D8.6 - MATH:U8ADD If set, Math Function Unit 8 acts as a 32-bit adder instead of 32-bit barrel-shifter.
              -- @IO:GS $D7D8.7 - MATH:U8LATCH If set, Math Function Unit 8's output is latched.
              
              -- @IO:GS $D7D9.0-3 MATH:UNIT9OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit 9
              -- @IO:GS $D7D9.4 - MATH:U9LOWOUT If set, the low-half of the output of Math Function Unit 9 is written to math register UNIT9OUT.
              -- @IO:GS $D7D9.5 - MATH:U9HIOUT If set, the high-half of the output of Math Function Unit 9 is written to math register UNIT9OUT.
              -- @IO:GS $D7D9.6 - MATH:U9ADD If set, Math Function Unit 9 acts as a 32-bit adder instead of 32-bit barrel-shifter.
              -- @IO:GS $D7D9.7 - MATH:U9LATCH If set, Math Function Unit 9's output is latched.
              
              -- @IO:GS $D7DA.0-3 MATH:UNIT10OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit A
              -- @IO:GS $D7DA.4 - MATH:UALOWOUT If set, the low-half of the output of Math Function Unit A is written to math register UNIT10OUT.
              -- @IO:GS $D7DA.5 - MATH:UAHIOUT If set, the high-half of the output of Math Function Unit A is written to math register UNIT10OUT.
              -- @IO:GS $D7DA.6 - MATH:UAADD If set, Math Function Unit A acts as a 32-bit adder instead of 32-bit barrel-shifter.
              -- @IO:GS $D7DA.7 - MATH:UALATCH If set, Math Function Unit A's output is latched.
              
              -- @IO:GS $D7DB.0-3 MATH:UNIT11OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit B
              -- @IO:GS $D7DB.4 - MATH:UBLOWOUT If set, the low-half of the output of Math Function Unit B is written to math register UNIT11OUT.
              -- @IO:GS $D7DB.5 - MATH:UBHIOUT If set, the high-half of the output of Math Function Unit B is written to math register UNIT11OUT.
              -- @IO:GS $D7DB.6 - MATH:UBADD If set, Math Function Unit B acts as a 32-bit adder instead of 32-bit barrel-shifter.
              -- @IO:GS $D7DB.7 - MATH:UBLATCH If set, Math Function Unit B's output is latched.
              
              -- @IO:GS $D7DC.0-3 MATH:UNIT12OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit C
              -- @IO:GS $D7DC.4 - MATH:UCLOWOUT If set, the low-half of the output of Math Function Unit C is written to math register UNIT12OUT.
              -- @IO:GS $D7DC.5 - MATH:UCHIOUT If set, the high-half of the output of Math Function Unit C is written to math register UNIT12OUT.
              -- @IO:GS $D7DC.6 - MATH:UCADD If set, Math Function Unit C acts as a 32-bit adder instead of 32-bit divider.
              -- @IO:GS $D7DC.7 - MATH:UCLATCH If set, Math Function Unit C's output is latched.
              
              -- @IO:GS $D7DD.0-3 MATH:UNIT13OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit D
              -- @IO:GS $D7DD.4 - MATH:UDLOWOUT If set, the low-half of the output of Math Function Unit D is written to math register UNIT13OUT.
              -- @IO:GS $D7DD.5 - MATH:UDHIOUT If set, the high-half of the output of Math Function Unit D is written to math register UNIT13OUT.
              -- @IO:GS $D7DD.6 - MATH:UDADD If set, Math Function Unit D acts as a 32-bit adder instead of 32-bit divider.
              -- @IO:GS $D7DD.7 - MATH:UDLATCH If set, Math Function Unit D's output is latched.
              
              -- @IO:GS $D7DE.0-3 MATH:UNIT14OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit E
              -- @IO:GS $D7DE.4 - MATH:UELOWOUT If set, the low-half of the output of Math Function Unit E is written to math register UNIT14OUT.
              -- @IO:GS $D7DE.5 - MATH:UEHIOUT If set, the high-half of the output of Math Function Unit E is written to math register UNIT14OUT.
              -- @IO:GS $D7DE.6 - MATH:UEADD If set, Math Function Unit E acts as a 32-bit adder instead of 32-bit divider.
              -- @IO:GS $D7DE.7 - MATH:UELATCH If set, Math Function Unit E's output is latched.
              
              -- @IO:GS $D7DF.0-3 MATH:UNIT15OUT Select which of the 16 32-bit math registers receives the output of Math Function Unit F
              -- @IO:GS $D7DF.4 - MATH:UFLOWOUT If set, the low-half of the output of Math Function Unit F is written to math register UNIT15OUT.
              -- @IO:GS $D7DF.5 - MATH:UFHIOUT If set, the high-half of the output of Math Function Unit F is written to math register UNIT15OUT.
              -- @IO:GS $D7DF.6 - MATH:UFADD If set, Math Function Unit F acts as a 32-bit adder instead of 32-bit divider.
              -- @IO:GS $D7DF.7 - MATH:UFLATCH If set, Math Function Unit F's output is latched.
              
              x"D0"|x"D1"|x"D2"|x"D3"|x"D4"|x"D5"|x"D6"|x"D7"|
              x"D8"|x"D9"|x"DA"|x"DB"|x"DC"|x"DD"|x"DE"|x"DF" =>
              return
                reg_math_config(to_integer(the_read_address(3 downto 0))).latched
                &reg_math_config(to_integer(the_read_address(3 downto 0))).do_add
                &reg_math_config(to_integer(the_read_address(3 downto 0))).output_high
                &reg_math_config(to_integer(the_read_address(3 downto 0))).output_low
                &to_unsigned(reg_math_config(to_integer(the_read_address(3 downto 0))).output,4);
              -- @IO:GS $D7E0 MATH:LATCHINT Latch interval for latched outputs (in CPU cycles)
              -- $D7E1 is documented higher up
            when x"E0" => return reg_math_latch_interval;
            when x"E1" => return math_unit_flags;
            -- @IO:GS $D7E2 MATH:RESERVED Reserved
            -- @IO:GS $D7E3 MATH:RESERVED Reserved
            --@IO:GS $D7E4 MATH:ITERCNT Iteration Counter (32 bit)
            --@IO:GS $D7E5 MATH:ITERCNT Iteration Counter (32 bit)
            --@IO:GS $D7E6 MATH:ITERCNT Iteration Counter (32 bit)
            --@IO:GS $D7E7 MATH:ITERCNT Iteration Counter (32 bit)
            when x"e4" => return reg_math_cycle_counter(7 downto 0);
            when x"e5" => return reg_math_cycle_counter(15 downto 8);
            when x"e6" => return reg_math_cycle_counter(23 downto 16);
            when x"e7" => return reg_math_cycle_counter(31 downto 24);
            --@IO:GS $D7E8 MATH:ITERCMP Math iteration counter comparator (32 bit)
            --@IO:GS $D7E9 MATH:ITERCMP Math iteration counter comparator (32 bit)
            --@IO:GS $D7EA MATH:ITERCMP Math iteration counter comparator (32 bit)
            --@IO:GS $D7EB MATH:ITERCMP Math iteration counter comparator (32 bit)
            when x"e8" => return reg_math_cycle_compare(7 downto 0);
            when x"e9" => return reg_math_cycle_compare(15 downto 8);
            when x"ea" => return reg_math_cycle_compare(23 downto 16);
            when x"eb" => return reg_math_cycle_compare(31 downto 24);

            --@IO:GS $D7F0 CPU:BPT0PCL Breakpoint 0 PC LSB
            when x"f0" => return breakpoint0_pc(7 downto 0);
            --@IO:GS $D7F1 CPU:BPT0PCH Breakpoint 0 PC MSB
            when x"f1" => return breakpoint0_pc(15 downto 8);
            --@IO:GS $D7F CPU:BPT1PCL Breakpoint 0 PC LSB
            when x"f2" => return breakpoint1_pc(7 downto 0);
            --@IO:GS $D7F3 CPU:BPT1PCH Breakpoint 1 PC MSB
            when x"f3" => return breakpoint1_pc(15 downto 8);
            --@IO:GS $D7F4 CPU:BPT2PCL Breakpoint 2 PC LSB
            when x"f4" => return breakpoint2_pc(7 downto 0);
            --@IO:GS $D7F5 CPU:BPT2PCH Breakpoint 2 PC MSB
            when x"f5" => return breakpoint2_pc(15 downto 8);
            --@IO:GS $D7F6 CPU:BPT3PCL Breakpoint 3 PC LSB
            when x"f6" => return breakpoint3_pc(7 downto 0);
            --@IO:GS $D7F7 CPU:BPT3PCH Breakpoint 3 PC MSB
            when x"f7" => return breakpoint3_pc(15 downto 8);
            --@IO:GS $D7F9.0 CPU:BPTEN Enable CPU breakpoint
            --@IO:GS $D7F9.7 CPU:BPTHYPR CPU breakpoint triggers Hypervisor Trap \$46 if set, or UART monitor halt if clear
            when x"f9" => return breakpoint_hyperrupt & "000" & breakpoint3_enable & breakpoint2_enable & breakpoint1_enable & breakpoint0_enable;
                          
            when x"fa" => return to_unsigned(cpu_speed_bias,8);
            when x"fb" => return "000000" & cartridge_enable & charge_for_branches_taken;
            when x"fc" => return unsigned(chipselect_enables);
            when x"fd" =>
              report "Reading $D7FD";
              value(7) := force_exrom;
              value(6) := force_game;
              value(5) := gated_exrom;
              value(4) := gated_game;
              value(3) := exrom;
              value(2) := game;
              value(1) := cartridge_enable;              
              value(0) := '1'; -- Set if power is on, clear if power is off
              return value;
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
            when "000101" => return hyper_sp;
            when "000110" => return hyper_sph;
            when "000111" => return hyper_p;
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
              return "0000000"&virtualise_sd;
              
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
            when "110000" => return georam_page(19 downto 12);
            when "110001" => return georam_blockmask;
            --$D672 - Protected Hardware
            when "110010" => return hyper_protected_hardware;
                             
            when "111100" => -- $D640+$3C
              -- @IO:GS $D67C.6 - (read) Hypervisor internal immediate UART monitor busy flag (can write when 0)
              -- @IO:GS $D67C.7 - (read) Hypervisor serial output from UART monitor busy flag (can write when 0)
              -- so we have an immediate busy flag that we manage separately.
              return "000000"
                & immediate_monitor_char_busy
                & monitor_char_busy;

            when "111101" =>
              -- this section $D67D
              return "11"
                & force_4502
                & force_fast
                & speed_gate_enable_internal
                & rom_writeprotect
                & flat32_enabled
                & cartridge_enable;                        
            when "111110" =>
              -- @IO:GS $D67E.7 (read) Hypervisor upgraded flag. Writing any value here sets this bit until next power on (i.e., it surives reset).
              -- @IO:GS $D67E.6 (read) Hypervisor read /EXROM signal from cartridge.
              -- @IO:GS $D67E.5 (read) Hypervisor read /GAME signal from cartridge.
              return hypervisor_upgraded
                & exrom
                & game
                & "00000";
            when "111111" => return x"48"; -- 'H' for Hypermode
            when others => return x"FF";
          end case;

        when CPUPort =>
          report "reading from CPU port" severity note;
          case cpuport_num is
            when x"0" => return cpuport_ddr;
            when x"1" => return cpuport_value;
            when x"2" => return rec_status;
            when x"3" => return vdc_status;
            when x"4" =>
              -- Read other VDC registers.
              return x"ff";
            when x"5" => return vdc_mem_addr(7 downto 0);
            when x"6" => return vdc_mem_addr(15 downto 8);
            when x"7" => return vdc_reg_num(7 downto 0);
            when others => return x"ff";
          end case;
        when Shadow =>
          report "reading from shadow RAM" severity note;
          return shadow_rdata;
        when ColourRAM =>
          report "reading colour RAM fastio byte $" & to_hstring(fastio_vic_rdata) severity note;
          return unsigned(fastio_colour_ram_rdata);
        when VICIV =>
          report "reading VIC fastio byte $" & to_hstring(fastio_vic_rdata) severity note;
          return unsigned(fastio_vic_rdata);
        when FastIO =>
          report "reading normal fastio byte $" & to_hstring(fastio_rdata) severity note;
          return unsigned(fastio_rdata);
        when Hyppo =>
          report "reading hyppo fastio byte $" & to_hstring(hyppo_rdata) severity note;
          return unsigned(hyppo_rdata);
        when SlowRAM =>
          report "reading slow RAM data. Word is $" & to_hstring(slow_access_rdata) severity note;
          return unsigned(slow_access_rdata);
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
      accessing_shadow <= '0'; accessing_hyppo_fastio <= '0';
      accessing_rom <= '0';
      accessing_slowram <= '0';
      slow_access_write_drive <= '0';
      charrom_write_cs <= '0';

      -- Get the shadow RAM or ROM address on the bus fast to improve timing.
      shadow_write <= '0';
      shadow_write_flags(1) <= '1';
      
      shadow_write_flags(0) <= '1';
      shadow_write_flags(1) <= '1';
      
      wait_states <= shadow_wait_states;
      if shadow_wait_states /= x"00" then
        wait_states_non_zero <= '1';
      else
        wait_states_non_zero <= '0';
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

      long_address := long_address_write;
      
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
        report "ZPCACHE: Flushing cache due to write to $01";
        cache_flushing <= '1';
        cache_flush_counter <= (others => '0');
      elsif (long_address = x"0000001") then
        report "MEMORY: Writing to CPU PORT register" severity note;
        cpuport_value <= value;
        report "ZPCACHE: Flushing cache due to write to $01";
        cache_flushing <= '1';
        cache_flush_counter <= (others => '0');
      -- Write to DMAgic registers if required
      elsif (long_address = x"FFD30A0") or (long_address = x"FFD10A0") then
        -- @ IO:C65 $D0A0 - C65 RAM Expansion controller
        -- The specifications of this interface is VERY under-documented.
        -- There are two versions: 512KB and 1MB - 8MB

        -- 512KB version is relatively simple:
        -- Bit 3 - CPU sees expansion bank 0 or 1
        -- Bit 2 - VIC uses expansion (1) or internal (0) RAM
        -- Bit 1 - VIC address range (0=$C0000-$DFFFF, 1=$E0000-$FFFFF)
        -- Bit 0 - VIC sees expansion bank 0 or 1
        -- Writing %xxxxx0xx -> VIC sees internal 128KB
        -- Writing %xxxxx100 -> VIC sees expansion RAM bank 0, $C0000-$DFFFF
        -- Writing %xxxxx110 -> VIC sees expansion RAM bank 0, $E0000-$FFFFF
        -- Writing %xxxxx101 -> VIC sees expansion RAM bank 1, $C0000-$DFFFF
        -- Writing %xxxxx111 -> VIC sees expansion RAM bank 1, $E0000-$FFFFF
        -- Writing %xxxx0xxx -> CPU sees expansion bank 0 (presumably at $80000-$FFFFF)
        -- Writing %xxxx1xxx -> CPU sees expansiob bank 1 (presumably at $80000-$FFFFF)

        -- 1MB-8MB version lacks documentation that I can find.
        -- Bit x - CART - presumably enable cartridge memory visibility?
        -- On read:
        -- Bit 7 - Indicate error condition?
        -- DMAgic sees expanded RAM from BANK $40 onwards?
        -- Presumably something controls what we see in the 1MB address space

        -- For now, just always report an error condition.
        rec_status <= x"80";
      elsif (long_address = x"FFD0600") then
        -- @IO:64 $D600 VDC:REGSEL VDC Register Select
        -- VDC register select #141
        vdc_reg_num <= value;
      elsif (long_address = x"FFD0601") then
        -- @IO:64 $D601 VDC:DATA VDC Data Access Register
        case vdc_reg_num is
          when x"12" =>
            vdc_mem_addr(15 downto 8) <= value;
          when x"13" =>
            vdc_mem_addr(7 downto 0) <= value;
          when x"1F" =>
            -- Write to VDC RAM.
            -- We advance memory pointer here, but real write happens elsewhere
            -- (search for x"ffd0601")
            vdc_mem_addr <= vdc_mem_addr + 1;
          when others =>
            null;
        end case;
      elsif (long_address = x"FFD3700") or (long_address = x"FFD1700") then        
        -- Set low order bits of DMA list address
        reg_dmagic_addr(7 downto 0) <= value;
        -- @IO:C65 $D700 DMA:ADDRLSBTRIG DMAgic DMA list address LSB, and trigger DMA (when written)
        -- DMA gets triggered when we write here. That actually happens through
        -- memory_access_write.
        -- We also clear out the upper address bits in case an enhanced job had
        -- set them.
        reg_dmagic_addr(27 downto 23) <= (others => '0');        
      elsif (long_address = x"FFD370E") or (long_address = x"FFD170E") then
        -- Set low order bits of DMA list address, without starting
        -- @IO:GS $D70E DMA:ADDRLSB DMA list address low byte (address bits 0 -- 7) WITHOUT STARTING A DMA JOB (used by Hypervisor for unfreezing DMA-using tasks)
        reg_dmagic_addr(7 downto 0) <= value;
      elsif (long_address = x"FFD3701") or (long_address = x"FFD1701") then
        -- @IO:C65 $D701 DMA:ADDRMSB DMA list address high byte (address bits 8 -- 15).
        reg_dmagic_addr(15 downto 8) <= value;
      elsif (long_address = x"FFD3702") or (long_address = x"FFD1702") then
        -- @IO:C65 $D702 DMA:ADDRBANK DMA list address bank (address bits 16 -- 22). Writing clears \$D704.
        reg_dmagic_addr(22 downto 16) <= value(6 downto 0);
        reg_dmagic_addr(27 downto 23) <= (others => '0');
        reg_dmagic_withio <= value(7);
      elsif (long_address = x"FFD3703") or (long_address = x"FFD1703") then
        -- @IO:GS $D703.0 DMA:EN018B DMA enable F018B mode (adds sub-command byte)
        support_f018b <= value(0);	-- setable dmagic mode
      elsif (long_address = x"FFD3704") or (long_address = x"FFD1704") then
        -- @IO:GS $D704 DMA:ADDRMB DMA list address mega-byte
        reg_dmagic_addr(27 downto 20) <= value;
      elsif (long_address = x"FFD3705") or (long_address = x"FFD1705") then
        -- @IO:GS $D705 DMA:ETRIG Set low-order byte of DMA list address, and trigger Enhanced DMA job (uses DMA option list)
        reg_dmagic_addr(7 downto 0) <= value;
      elsif (long_address = x"FFD3710") or (long_address = x"FFD1710") then
        -- @IO:GS $D710.0 - MISC:BADLEN Enable badline emulation
        -- @IO:GS $D710.1 - MISC:SLIEN Enable 6502-style slow (7 cycle) interrupts
        badline_enable <= value(0);
        slow_interrupts <= value(1);
      -- @IO:GS $D770-3 25-bit multiplier input A
      elsif (long_address = x"FFD3770") or (long_address = x"FFD1770") then
        reg_mult_a(7 downto 0) <= value;
      elsif (long_address = x"FFD3771") or (long_address = x"FFD1771") then
        reg_mult_a(15 downto 8) <= value;
      elsif (long_address = x"FFD3772") or (long_address = x"FFD1772") then
        reg_mult_a(23 downto 16) <= value;
      elsif (long_address = x"FFD3773") or (long_address = x"FFD1773") then
        reg_mult_a(24) <= value(0);
      -- @IO:GS $D774-7 18-bit multiplier input B
      elsif (long_address = x"FFD3774") or (long_address = x"FFD1774") then
        reg_mult_b(7 downto 0) <= value;
      elsif (long_address = x"FFD3775") or (long_address = x"FFD1775") then
        reg_mult_b(15 downto 8) <= value;
      elsif (long_address = x"FFD3776") or (long_address = x"FFD1776") then
        reg_mult_b(17 downto 16) <= value(1 downto 0);
      elsif (long_address(27 downto 6)&"00"=x"FFD378")
        or  (long_address(27 downto 6)&"00"=x"FFD178") then
        -- Math unit register writing
        reg_math_write <= '1';
        reg_math_regnum <= to_integer(long_address(5 downto 2));
        reg_math_regbyte <= to_integer(long_address(1 downto 0));
        reg_math_write_value <= value;
      elsif (long_address(27 downto 4)=x"FFD37C") or  (long_address(27 downto 4)=x"FFD17C") then
        -- Math unit input select registers
        reg_math_config(to_integer(long_address(3 downto 0))).source_a <= to_integer(value(3 downto 0));
        reg_math_config(to_integer(long_address(3 downto 0))).source_b <= to_integer(value(7 downto 4));
      elsif (long_address(27 downto 4)=x"FFD37D") or  (long_address(27 downto 4)=x"FFD17D") then
        -- Math unit input select registers
        reg_math_config(to_integer(long_address(3 downto 0))).latched <= value(7);
        reg_math_config(to_integer(long_address(3 downto 0))).do_add <= value(6);
        reg_math_config(to_integer(long_address(3 downto 0))).output_high <= value(5);
        reg_math_config(to_integer(long_address(3 downto 0))).output_low <= value(4);
        reg_math_config(to_integer(long_address(3 downto 0))).output <= to_integer(value(3 downto 0));
      elsif (long_address = x"FFD37E0") or (long_address = x"FFD17E0") then
        -- @IO:GS $D7E0 - Math unit latch interval (only update output of math function units every this many cycles, if they have the latch output flag set)
        reg_math_latch_interval <= value;
      elsif (long_address = x"FFD37E1") or (long_address = x"FFD17E1") then
        -- @IO:GS $D7E1 - Math unit general settings (writing also clears math cycle counter)
        -- @IO:GS $D7E1.0 MATH:WREN Enable setting of math registers (must normally be set)
        -- @IO:GS $D7E1.1 MATH:CALCEN Enable committing of output values from math units back to math registers (clearing effectively pauses iterative formulae)
        math_unit_flags <= value;
        reg_math_cycle_counter <= to_unsigned(0,32);        
      elsif (long_address = x"FFD37E8") or (long_address = x"FFD17E8") then
        reg_math_cycle_compare(7 downto 0) <= value;
      elsif (long_address = x"FFD37E9") or (long_address = x"FFD17E9") then
        reg_math_cycle_compare(15 downto 8) <= value;
      elsif (long_address = x"FFD37EA") or (long_address = x"FFD17EA") then
        reg_math_cycle_compare(23 downto 16) <= value;
      elsif (long_address = x"FFD37EB") or (long_address = x"FFD17EB") then
        reg_math_cycle_compare(31 downto 24) <= value;
      elsif (long_address = x"FFD37F0") then
        breakpoint0_pc(7 downto 0) <= unsigned(fastio_wdata);
      elsif (long_address = x"FFD37F1") then
        breakpoint0_pc(15 downto 8) <= unsigned(fastio_wdata);
      elsif (long_address = x"FFD37F2") then
        breakpoint1_pc(7 downto 0) <= unsigned(fastio_wdata);
      elsif (long_address = x"FFD37F3") then
        breakpoint1_pc(15 downto 8) <= unsigned(fastio_wdata);
      elsif (long_address = x"FFD37F4") then
        breakpoint2_pc(7 downto 0) <= unsigned(fastio_wdata);
      elsif (long_address = x"FFD37F5") then
        breakpoint2_pc(15 downto 8) <= unsigned(fastio_wdata);
      elsif (long_address = x"FFD37F6") then
        breakpoint3_pc(7 downto 0) <= unsigned(fastio_wdata);
      elsif (long_address = x"FFD37F7") then
        breakpoint3_pc(15 downto 8) <= unsigned(fastio_wdata);
      elsif (long_address = x"FFD37F9") then
        breakpoint_hyperrupt <= fastio_wdata(7);
        breakpoint0_enable <= fastio_wdata(0);
      elsif (long_address = x"FFD37FA") then
        -- @IO:GS $D7FA CPU:SPEEDBIAS 1/2/3.5MHz CPU speed fine adjustment
        cpu_speed_bias <= to_integer(value);
      elsif (long_address = x"FFD37FB") then
        -- @IO:GS $D7FB.0 CPU:BRCOST 1=charge extra cycle(s) for branches taken
        -- @IO:GS $D7FB.1 CPU:CARTEN 1= enable cartridges
        charge_for_branches_taken <= value(0);
        cartridge_enable <= '1';
      elsif (long_address = x"FFD37FC") then
      -- @IO:GS $D7FC DEBUG chip-select enables for various devices
--        chipselect_enables <= std_logic_vector(value);
      elsif (long_address = x"FFD37FD") then
        -- @IO:GS $D7FD.7 CPU:NOEXROM Override for /EXROM : Must be 0 to enable /EXROM signal
        -- @IO:GS $D7FD.6 CPU:NOGAME Override for /GAME : Must be 0 to enable /GAME signal
        -- @IO:GS $D7FD.6 CPU:POWEREN Set to zero to power off computer on supported systems. WRITE ONLY.
        force_exrom <= value(7);
        force_game <= value(6);
        power_down <= value(0);
      elsif (long_address = x"FFD37ff") or (long_address = x"FFD17ff") then
        null;
      end if;
      
      -- Always write to shadow ram if in scope, even if we also write elsewhere.
      -- This ensures that shadow ram is consistent with the shadowed address space
      -- when the CPU reads from shadow ram.
      -- Get the shadow RAM address on the bus fast to improve timing.
      shadow_wdata <= value;
      
      if long_address(27 downto 20)=x"00" and ((not long_address(19)) or chipram_1mb)='1' then
        report "writing to chip RAM addr=$" & to_hstring(long_address) severity note;
        shadow_address <= shadow_address_next;
        -- Enforce write protect of 2nd 128KB of memory, if being used as ROM
        if long_address(19 downto 17)="001" then
          shadow_write <= not rom_writeprotect;
        else
          shadow_write <= '1';
        end if;
        fastio_write <= '0';
        -- shadow_try_write_count <= shadow_try_write_count + 1;
        shadow_write_flags(3) <= '1';
        --chipram_address <= long_address(16 downto 0);
        --chipram_we <= '1';
        --chipram_datain <= value;
        --report "writing to chipram..." severity note;
        wait_states <= io_write_wait_states;
        if io_write_wait_states /= x"00" then
          wait_states_non_zero <= '1';
        else
          wait_states_non_zero <= '0';
        end if;

        -- C65 uses $1F800-FFF as colour RAM, so we need to write there, too,
        -- when writing here.
        if long_address(27 downto 12) = x"001F" and long_address(11) = '1' then
          report "writing to colour RAM via $001F8xx" severity note;

          -- And also to colour RAM
          colour_ram_cs <= '1';
          fastio_write <= '1';
          fastio_wdata <= std_logic_vector(value);
          fastio_addr(19 downto 16) <= x"8";
          fastio_addr(15 downto 11) <= (others => '0');
          fastio_addr(10 downto 0) <= std_logic_vector(long_address(10 downto 0));
        end if;
      elsif long_address(27 downto 24) = x"F" then --
        accessing_fastio <= '1';
        shadow_write <= '0';
        shadow_write_flags(2) <= '1';
        fastio_addr <= fastio_addr_next;
        last_fastio_addr <= fastio_addr_next;
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
        
        -- @IO:GS $FF7E000-$FF7EFFF SUMMARY:CHARWRITE VIC-IV CHARROM write area
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

                -- Write also to CHIP RAM, so that $1F800-FFF works as chipRAM
                -- as well as colour RAM, when accessed via $D800+ portal
                --chipram_address(16 downto 11) <= "111111"; -- $1F8xx
                --chipram_address(10 downto 0) <= long_address(10 downto 0);
                --chipram_we <= '1';
                --chipram_datain <= value;
                --report "writing to chipram..." severity note;
                
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
      elsif (long_address(27) = '1' or long_address(26)='1') and hyper_protected_hardware(7)='0' then
        report "writing to slow device memory..." severity note;
        -- (But not accessible in secure compartment)
        accessing_slowram <= '1';
        shadow_write <= '0';
        fastio_write <= '0';
        shadow_write_flags(2) <= '1';
        -- We dispatch the write, and then wait for the slow access controller
        -- to acknowledge the write.  The slow access controller is free to
        -- buffer the writes as it wishes to hide latency -- we don't need to worry
        -- about there here, as it only changes the latency for receiving the
        -- write acknowledgement (a similar process can be used for caching reads
        -- from appropriate slow devices, e.g., for expansion memory).
        slow_access_address_drive <= long_address(27 downto 0);
        slow_access_write_drive <= '1';
        slow_access_wdata_drive <= value;
        slow_access_pending_write <= '1';
        slow_access_data_ready <= '0';

        -- Tell CPU to wait for response
        slow_access_request_toggle_drive <= not slow_access_request_toggle_drive;
        slow_access_desired_ready_toggle <= not slow_access_desired_ready_toggle;
        wait_states_non_zero <= '1';
        wait_states <= x"FF";
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

      -- Flush ZP/stack cache because memory map may have changed
      cache_flushing <= '1';
      cache_flush_counter <= (others => '0');      
      
    end c65_map_instruction;

    procedure dmagic_reset_options is
    begin
      reg_dmagic_use_transparent_value <= '0';
      reg_dmagic_src_mb <= x"00";
      reg_dmagic_dst_mb <= x"00";
      reg_dmagic_transparent_value <= x"00";
      reg_dmagic_src_skip <= x"0100";
      reg_dmagic_dst_skip <= x"0100";
    end procedure;
    
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
          tmp(9) := '1';
        else tmp(9) := '0'; -- Z flag
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
        tmp(9) := '1';
      else
        tmp(9) := '0';  -- Zero flag
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

    variable math_input_a_source : integer := 0;
    variable math_input_b_source : integer := 0;
    variable math_output_low : integer := 0;
    variable math_output_high : integer := 0;
    variable math_result : unsigned(63 downto 0) := to_unsigned(0,64);
    variable vreg33 : unsigned(32 downto 0) := to_unsigned(0,33);
    
  begin    
                                        -- Export phi0 for the rest of the machine (scales with CPU speed)
    phi0 <= phi0_export;
    
                                        -- Begin calculating results for operations immediately to help timing.
                                        -- The trade-off is consuming a bit of extra silicon.
    a_incremented <= reg_a + 1;
    a_decremented <= reg_a - 1;
    a_negated <= (not reg_a) + 1;
    a_ror <= flag_c & reg_a(7 downto 1);
    a_rol <= reg_a(6 downto 0) & flag_c;    
    a_asr <= reg_a(7) & reg_a(7 downto 1);
    a_lsr <= '0' & reg_a(7 downto 1);
    a_xor <= reg_a xor read_data;
    a_and <= reg_a and read_data;
    a_asl <= reg_a(6 downto 0)&'0';      
    a_neg <= (not reg_a) + 1;
    if (reg_a = x"00") then 
      a_neg_z <= '1';
    else
      a_neg_z <= '0';
    end if;
    a_add <= alu_op_add(reg_a,read_data);
    a_sub <= alu_op_sub(reg_a,read_data);

    x_incremented <= reg_x + 1;
    x_decremented <= reg_x - 1;
    y_incremented <= reg_y + 1;
    y_decremented <= reg_y - 1;
    z_incremented <= reg_z + 1;
    z_decremented <= reg_z - 1;


    -- Formula Plumbing Unit (FPU), the MEGA65's answer to a traditional
    -- Floating Point Unit (FPU).
    -- The idea is simple: We have a bunch of math units, and a bunch of
    -- inputs and outputs, and a bunch of multiplexors that let you select what
    -- joins where: In short, you can plumb your own formulae directly.
    -- For each unit we have to pick one or more inputs, and set at least one
    -- output.  We will map these all onto the same 64 bytes of registers.

    if rising_edge(clock) then
      -- We also have one direct 18x25 multiplier for use by the hypervisor.
      -- This multiplier fits a single DSP48E unit, and does not use the plumbing
      -- facility.
      reg_mult_p <= to_unsigned(to_integer(reg_mult_a) * to_integer(reg_mult_b),48);

      -- Disable all non-essential IO devices from memory map when in secure mode.
      if hyper_protected_hardware(7)='1' then
--        cartridge_enable <= '0';
        chipselect_enables <= x"84"; -- SD card/multi IO controller and SIDs
      -- (we disable the undesirable parts of the SD card interface separately)
      else
        chipselect_enables <= x"EF";
      end if;
      
      if math_unit_enable then
        -- We also provide some flags (which will later trigger interrupts) based
        -- on the equality of math registers 14 and 15
        if reg_math_regs(14) = reg_math_regs(15) then
          math_unit_flags(6) <= '1';
          if math_unit_flags(3 downto 2) = "00" then
            math_unit_flags(7) <= '1' ;
          end if;
        else
          math_unit_flags(6) <= '0';
          if math_unit_flags(3 downto 2) = "11" then
            math_unit_flags(7) <= '1' ;
          end if;
        end if;
        if reg_math_regs(14) < reg_math_regs(15) then
          math_unit_flags(5) <= '1';
          if math_unit_flags(3 downto 2) = "10" then
            math_unit_flags(7) <= '1' ;
          end if;
        else
          math_unit_flags(5) <= '0';
        end if;
        if reg_math_regs(14) > reg_math_regs(15) then
          math_unit_flags(4) <= '1';
          if math_unit_flags(3 downto 2) = "01" then
            math_unit_flags(7) <= '1' ;
          end if;
        else
          math_unit_flags(4) <= '0';
        end if;
      end if;
      
    end if;

    if rising_edge(mathclock) and math_unit_enable then
      -- For the plumbed math units, we want to avoid having two huge 16x32x32
      -- MUXes to pick the inputs and outputs to and from the register file.
      -- The interim solution is to have counters that present each of the
      -- inputs and outputs in turn, and based on the configuration of the plumbing,
      -- latch or store the appropriate results in the appropriate places.
      -- This does mean that there can be 16 cycles of latency on the input and
      -- output of the plumbing, depending on the phase of the counters.
      -- Later we can try to reduce this latency, by clocking this piece of
      -- logic at 2x or 4x CPU speed (as it is really a simple set of latches and
      -- interconnect), and possibly widening it to present 2 of the 16 values
      -- at a time, instead of just one.  On both input and output sides, it could
      -- be possible to set the range over which it iterates the counters, to further
      -- reduce the latency.  But for now, it will simply have the 16 phase
      -- counters at the CPU speed.

      -- Present input value to all math units
      if math_input_counter /= 15 then
        math_input_counter <= math_input_counter + 1;
      else
        math_input_counter <= 0;
      end if;
      math_input_number <= math_input_counter;
      math_input_value <= reg_math_regs(math_input_counter);
      report "MATH: Presenting math reg #" & integer'image(math_input_counter)
        &" = $" & to_hstring(reg_math_regs(math_input_counter));

      -- Update output counter being shown to math units
      if math_output_counter /= 15 then
        math_output_counter <= math_output_counter + 1;
      else
        math_output_counter <= 0;
      end if;
      prev_math_output_counter <= math_output_counter;
      -- Based on the configuration for the previously selected unit,
      -- stash the results in the appropriate place
      if true then
        report "MATH: output flags for unit #" & integer'image(prev_math_output_counter)
          & " = "
          & std_logic'image(reg_math_config(prev_math_output_counter).output_low) & ", "
          & std_logic'image(reg_math_config(prev_math_output_counter).output_high) & ", "
          & integer'image(reg_math_config(prev_math_output_counter).output) & ", "
          & std_logic'image(reg_math_config(prev_math_output_counter).latched) & ".";
      end if;

      if math_unit_flags(1) = '1' then
        if (reg_math_config_drive(prev_math_output_counter).latched='0') or (reg_math_latch_counter = x"00") then
          if reg_math_config_drive(prev_math_output_counter).output_high = '0' then
            if reg_math_config_drive(prev_math_output_counter).output_low = '0' then
              -- No output being kept, so nothing to do.
              null;
            else
              -- Only low output being kept
              report "MATH: Setting reg_math_regs(" & integer'image(reg_math_config(prev_math_output_counter).output)
                & ") from output of math unit #" & integer'image(prev_math_output_counter)
                & " ( = $" & to_hstring(math_output_value_low) & ")";
              reg_math_regs(reg_math_config(prev_math_output_counter).output) <= math_output_value_low;
            end if;
          else
            if reg_math_config_drive(prev_math_output_counter).output_low = '0' then          
              -- Only high half of output is being kept, so stash it
              report "MATH: Setting reg_math_regs(" & integer'image(reg_math_config(prev_math_output_counter).output)
                & ") from output of math unit #" & integer'image(prev_math_output_counter);
              reg_math_regs(reg_math_config(prev_math_output_counter).output) <= math_output_value_high;
            else
              -- Both are being stashed, so store in consecutive slots
              report "MATH: Setting reg_math_regs(" & integer'image(reg_math_config(prev_math_output_counter).output)
                & ") (and next) from output of math unit #" & integer'image(prev_math_output_counter);
              reg_math_regs(reg_math_config(prev_math_output_counter).output) <= math_output_value_low;
              if reg_math_config_drive(prev_math_output_counter).output /= 15 then
                reg_math_regs(reg_math_config_drive(prev_math_output_counter).output + 1) <= math_output_value_high;
              else
                reg_math_regs(0) <= math_output_value_high;
              end if;
            end if;
          end if;
        end if;
      end if;

      -- Implement writing to math registers
      reg_math_write <= '0';
      if math_unit_flags(0) = '1' then
        if reg_math_write = '1' then
          case reg_math_regbyte is
            when 0 => reg_math_regs(reg_math_regnum)(7 downto 0) <= reg_math_write_value;
            when 1 => reg_math_regs(reg_math_regnum)(15 downto 8) <= reg_math_write_value;
            when 2 => reg_math_regs(reg_math_regnum)(23 downto 16) <= reg_math_write_value;
            when 3 => reg_math_regs(reg_math_regnum)(31 downto 24) <= reg_math_write_value;
            when others =>
          end case;
        end if;
      end if;

      -- Latch counter counts "math cycles", which is the time it takes for an
      -- output to appear on the inputs again, i.e., once per lap of the input
      -- and output propagation.
      reg_math_cycle_counter_plus_one <= reg_math_cycle_counter + 1;
      if math_output_counter = 1 then
        -- Decrement latch counter
        if reg_math_latch_counter = x"00" then
          reg_math_latch_counter <= reg_math_latch_interval;
          -- And update math cycle counter, if math unit is active
          if math_unit_flags(1) = '1' then
            reg_math_cycle_counter <= reg_math_cycle_counter_plus_one;
          end if;
        else
          reg_math_latch_counter <= reg_math_latch_counter - 1;
        end if;
      end if;
    end if;    
                                        -- BEGINNING OF MAIN PROCESS FOR CPU
    if rising_edge(clock) and all_pause='0' then

      if (clear_matrix_mode_toggle='1' and last_clear_matrix_mode_toggle='0')
        or (clear_matrix_mode_toggle='0' and last_clear_matrix_mode_toggle='1')
      then
        -- Turn off matrix mode once the monitor has accepted or rejected the
        -- transition, since the hypervisor isn't available to do it itself.
        -- This leaves the secure program both running and visible and able to
        -- be interacted with.
        hyper_protected_hardware(6) <= '0';
        last_clear_matrix_mode_toggle <= clear_matrix_mode_toggle;
        -- Debug what is going wrong here, i.e., why they stay never matching
        hyper_protected_hardware(5) <= clear_matrix_mode_toggle;
        hyper_protected_hardware(4) <= last_clear_matrix_mode_toggle;
      end if;
      
      dat_bitplane_addresses_drive <= dat_bitplane_addresses;
      dat_offset_drive <= dat_offset;
      dat_even_drive <= dat_even;
      
      cycle_counter <= cycle_counter + 1;
      
      if cache_flushing = '1' then
        cache_waddr <= cache_flush_counter;
        cache_wdata <= (others => '1');
        if cache_flush_counter /= "1111111111" then
          cache_flush_counter <= cache_flush_counter + 1;
        else
          cache_flushing <= '0';
          report "ZPCACHE: Flush complete.";
        end if;
      end if;
      
      speed_gate_drive <= speed_gate;
      
      if cartridge_enable='1' then
        gated_exrom <= exrom and force_exrom;
        gated_game <= game and force_game;
      else
        gated_exrom <= force_exrom;
        gated_game <= force_game;
      end if;

                                        -- Count slow clock ticks for CIAs and other peripherals (never goes >3.5MHz)
                                        -- Actually, the C65 always counts timers etc at 1MHz, which simplifies
                                        -- things a little. We only deviate for C128 2MHz mode emulation, where we
                                        -- do double it.
                                        -- Actually, CIAs must run at 1MHz still in 2MHz mode, because SynthMark
                                        -- depends  on it.
      case cpuspeed_external is
--        when x"02" =>          
--          phi_export_counter <= phi_export_counter + phi_fraction_02pal;
        when others =>          
          phi_export_counter <= phi_export_counter + phi_fraction_01pal;
      end case;
      phi0_export <= phi_export_counter(16);
      
      
                                        -- Count slow clock ticks for applying instruction-level 6502/4510 timing
                                        -- accuracy at 1MHz and 3.5MHz
                                        -- XXX Add NTSC speed emulation option as well

      phi_add_backlog <= '0';
      phi_new_backlog <= 0;
      last_phi_in <= phi_in;
      last_phi16 <= phi_counter(16);
      case cpuspeed_internal is
        when x"01" =>          
          phi_counter <= phi_counter + phi_fraction_01pal + cpu_speed_bias*16 - (128*16);
        when x"02" =>          
          phi_counter <= phi_counter + phi_fraction_02pal + cpu_speed_bias*16 - (128*16);
        when x"04" =>
          phi_counter <= phi_counter + phi_fraction_04pal + cpu_speed_bias*16 - (128*16);
        when others =>
                                        -- Full speed = 1 clock tick per cycle
          phi_counter(16) <= phi_counter(16) xor '1';
      end case;
      if cpuspeed_internal /= x"40" and monitor_mem_attention_request_drive='0' then
        if ((last_phi16 /= phi_counter(16)) and (cpuspeed_internal /= x"01"))
           or ((cpuspeed_internal = x"01") and (last_phi_in='0' and phi_in='1')) then
          -- phi2 cycle has passed
          if phi_backlog = 1 or phi_backlog=0 then
            if phi_add_backlog = '0' then
              -- We have just finished our backlog, allow CPU to proceed,
              -- unless there is a pending VIC-II badline.
              -- By applying the badlines here, we approximate the behaviour
              -- of the 6502 in a C64, but only approximate it, as we allow
              -- whatever instruction was running to complete, rather than stopping
              -- as soon as there is a read operation.
              if (badline_toggle /= last_badline_toggle) and (monitor_mem_attention_request_drive='0') and (badline_enable='1') then
                phi_pause <= '1';
                phi_backlog <= 40;
                last_badline_toggle <= badline_toggle;
              else
                phi_backlog <= 0;
                phi_pause <= '0';
              end if;
            else
              -- We would have finished the back log, but we have new backlog
              -- to process
              phi_backlog <= phi_new_backlog;
              phi_pause <= '1';
            end if;            
          else
            if phi_add_backlog = '0' then
              phi_backlog <= phi_backlog - 1;
              phi_pause <= '1';
            else
              phi_backlog <= phi_backlog - 1 + phi_new_backlog;
              phi_pause <= '1';
            end if;
          end if;
        else
          if phi_add_backlog = '1' then
            phi_backlog <= phi_backlog + phi_new_backlog;
            phi_pause <= '1';
          end if;
        end if;
      else
                                        -- Full speed - never pause
        phi_backlog <= 0;

        -- Enforce 16 clock delay after writing to certain IO locations
        -- (Also used to stop CPU for secure mode triage, thus the check
        -- to allow the CPU to continue if the monitor is asking for a memory access
        if (io_settle_delay = '1')
          and (monitor_mem_attention_request_drive='0')
          and (monitor_mem_attention_granted_internal='0') then
          phi_pause <= '1';
          report "phi_pause due to io_settle_delay=1 (io_settle_counter = $" & to_hstring(io_settle_counter) & ")";
        else
          phi_pause <= '0';
        end if;
      end if;
      
                                        --Check for system-generated traps (matrix mode, and double tap restore)
      if hyper_trap = '0' and hyper_trap_last = '1' then
        hyper_trap_edge <= '1';
      else
        hyper_trap_edge <= '0';
      end if;
      hyper_trap_last <= hyper_trap;
      if (hyper_trap_edge = '1' or matrix_trap_in ='1' or hyper_trap_f011_read = '1' or hyper_trap_f011_write = '1')
        and hyper_trap_state = '1' then
        hyper_trap_state <= '0';
        hyper_trap_pending <= '1'; 
        if matrix_trap_in='1' then 
          matrix_trap_pending <='1';
        elsif hyper_trap_f011_read='1' then 
          f011_read_trap_pending <='1';
        elsif hyper_trap_f011_write='1' then 
          f011_write_trap_pending <='1';
        end if;
      else
        hyper_trap_state <= '1';
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

                                        -- Instruction cycle times are 6502 whenever we are at 1 or 2
                                        -- MHz, for C64 compatibility, and 4502 at 3.5MHz and when
                                        -- full speed. This is even if the CPU is forced to 4502 mode.
      if cpuspeed_internal = x"01"
        or cpuspeed_internal = x"02" then
        timing6502 <= '1';
      else
        timing6502 <= '0';
      end if;
      
                                        -- Work out actual georam page
      georam_page(5 downto 0) <= georam_blockpage(5 downto 0);
      georam_page(13 downto 6) <= georam_block and georam_blockmask;

                                        -- If the serial monitor interface has received the character, we can clear
                                        -- our temporary busy flag, then rely upon the serial monitor to deassert
                                        -- the "monitor_char_busy" signal when it has finished sending the char,
      if monitor_char_busy = '1' then
        immediate_monitor_char_busy <= '0';
      end if;

                                        -- Write to hypervisor registers if requested
                                        -- (This is separated out from the previous cycle to reduce the logic depth,
                                        -- and thus help achieve timing closure.)
      if last_write_pending = '1' then
        last_write_pending <= '0';
        
                                        -- @IO:GS $D640 HCPU:REGA Hypervisor A register storage
        if last_write_address = x"FFD3640" and hypervisor_mode='1' then
          hyper_a <= last_value;
        end if;
                                        -- @IO:GS $D641 HCPU:REGX Hypervisor X register storage
        if last_write_address = x"FFD3641" and hypervisor_mode='1' then
          hyper_x <= last_value;
        end if;
                                        -- @IO:GS $D642 HCPU_REGY Hypervisor Y register storage
        if last_write_address = x"FFD3642" and hypervisor_mode='1' then
          hyper_y <= last_value;
        end if;
                                        -- @IO:GS $D643 HCPU:REGZ Hypervisor Z register storage
        if last_write_address = x"FFD3643" and hypervisor_mode='1' then
          hyper_z <= last_value;
        end if;
                                        -- @IO:GS $D644 HCPU:REGB Hypervisor B register storage
        if last_write_address = x"FFD3644" and hypervisor_mode='1' then
          hyper_b <= last_value;
        end if;
                                        -- @IO:GS $D645 HCPU:SPL Hypervisor SPL register storage
        if last_write_address = x"FFD3645" and hypervisor_mode='1' then
          hyper_sp <= last_value;
        end if;
                                        -- @IO:GS $D646 HCPU:SPH Hypervisor SPH register storage
        if last_write_address = x"FFD3646" and hypervisor_mode='1' then
          hyper_sph <= last_value;
        end if;
                                        -- @IO:GS $D647 HCPU:PFLAGS Hypervisor P register storage
        if last_write_address = x"FFD3647" and hypervisor_mode='1' then
          hyper_p <= last_value;
        end if;
                                        -- @IO:GS $D648 HCPU:PCL Hypervisor PC-low register storage
        if last_write_address = x"FFD3648" and hypervisor_mode='1' then
          hyper_pc(7 downto 0) <= last_value;
        end if;
                                        -- @IO:GS $D649 HCPU:PCH Hypervisor PC-high register storage
        if last_write_address = x"FFD3649" and hypervisor_mode='1' then
          hyper_pc(15 downto 8) <= last_value;
        end if;
                                        -- @IO:GS $D64A HCPU:MAPLO Hypervisor MAPLO register storage (high bits)
        if last_write_address = x"FFD364A" and hypervisor_mode='1' then
          hyper_map_low <= std_logic_vector(last_value(7 downto 4));
          hyper_map_offset_low(11 downto 8) <= last_value(3 downto 0);
        end if;
                                        -- @IO:GS $D64B HCPU:MAPLO Hypervisor MAPLO register storage (low bits)
        if last_write_address = x"FFD364B" and hypervisor_mode='1' then
          hyper_map_offset_low(7 downto 0) <= last_value;
        end if;
                                        -- @IO:GS $D64C HCPU:MAPHI Hypervisor MAPHI register storage (high bits)
        if last_write_address = x"FFD364C" and hypervisor_mode='1' then
          hyper_map_high <= std_logic_vector(last_value(7 downto 4));
          hyper_map_offset_high(11 downto 8) <= last_value(3 downto 0);
        end if;
                                        -- @IO:GS $D64D HCPU:MAPHI Hypervisor MAPHI register storage (low bits)
        if last_write_address = x"FFD364D" and hypervisor_mode='1' then
          hyper_map_offset_high(7 downto 0) <= last_value;
        end if;
                                        -- @IO:GS $D64E HCPU:MAPLOMB Hypervisor MAPLO mega-byte number register storage
        if last_write_address = x"FFD364E" and hypervisor_mode='1' then
          hyper_mb_low <= last_value;
        end if;
                                        -- @IO:GS $D64F HCPU:MAPHIMB Hypervisor MAPHI mega-byte number register storage
        if last_write_address = x"FFD364F" and hypervisor_mode='1' then
          hyper_mb_high <= last_value;
        end if;
                                        -- @IO:GS $D650 HCPU:PORT00 Hypervisor CPU port \$00 value
        if last_write_address = x"FFD3650" and hypervisor_mode='1' then
          hyper_port_00 <= last_value;
        end if;
                                        -- @IO:GS $D651 HCPU:PORT01 Hypervisor CPU port \$01 value
        if last_write_address = x"FFD3651" and hypervisor_mode='1' then
          hyper_port_01 <= last_value;
        end if;
                                        -- @IO:GS $D652 - Hypervisor VIC-IV IO mode
                                        -- @IO:GS $D652.0-1 HCPU:VICMODE VIC-II/VIC-III/VIC-IV mode select
                                        -- @IO:GS $D652.2 HCPU:EXSID 0=Use internal SIDs, 1=Use external(1) SIDs
        if last_write_address = x"FFD3652" and hypervisor_mode='1' then
          hyper_iomode <= last_value;
        end if;
                                        -- @IO:GS $D653 HCPU:DMASRCMB Hypervisor DMAgic source MB
        if last_write_address = x"FFD3653" and hypervisor_mode='1' then
          hyper_dmagic_src_mb <= last_value;
        end if;
                                        -- @IO:GS $D654 HCPU:DMADSTMB Hypervisor DMAgic destination MB
        if last_write_address = x"FFD3654" and hypervisor_mode='1' then
          hyper_dmagic_dst_mb <= last_value;
        end if;
                                        -- @IO:GS $D655 HCPU:DMALADDR Hypervisor DMAGic list address bits 0-7
        if last_write_address = x"FFD3655" and hypervisor_mode='1' then
          hyper_dmagic_list_addr(7 downto 0) <= last_value;
        end if;
                                        -- @IO:GS $D656 HCPU:DMALADDR Hypervisor DMAGic list address bits 15-8
        if last_write_address = x"FFD3656" and hypervisor_mode='1' then
          hyper_dmagic_list_addr(15 downto 8) <= last_value;
        end if;
                                        -- @IO:GS $D657 HCPU:DMALADDR Hypervisor DMAGic list address bits 23-16
        if last_write_address = x"FFD3657" and hypervisor_mode='1' then
          hyper_dmagic_list_addr(23 downto 16) <= last_value;
        end if;
                                        -- @IO:GS $D658 HCPU:DMALADDR Hypervisor DMAGic list address bits 27-24
        if last_write_address = x"FFD3658" and hypervisor_mode='1' then
          hyper_dmagic_list_addr(27 downto 24) <= last_value(3 downto 0);
        end if;
                                        -- @IO:GS $D659 - Hypervisor virtualise hardware flags
                                        -- @IO:GS $D659.0 HCPU:VFLOP 1=Virtualise SD/Floppy access (usually for access via serial debugger interface)
        if last_write_address = x"FFD3659" and hypervisor_mode='1' then
          virtualise_sd <= last_value(0);
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

                                        -- @IO:GS $D670 HCPU:GEORAMBASE Hypervisor GeoRAM base address (x MB)
        if last_write_address = x"FFD3670" and hypervisor_mode='1' then
          georam_page(19 downto 12) <= last_value;
        end if;
                                        -- @IO:GS $D671 HCPU:GEORAMMASK Hypervisor GeoRAM address mask (applied to GeoRAM block register)
        if last_write_address = x"FFD3671" and hypervisor_mode='1' then
          georam_blockmask <= last_value;
        end if;   
        
                                        -- @IO:GS $D672 - Protected Hardware configuration
                                        -- @IO:GS $D672.6 HCPU:MATRIXEN Enable composited Matrix Mode, and disable UART access to serial monitor.
        if last_write_address = x"FFD3672" and hypervisor_mode='1' then
          hyper_protected_hardware <= last_value;
          if last_value(7)='1' then
            -- If we attempt to enter secure mode, then we are forced out of
            -- the hypervisor, to make sure that the hypervisor cannot do
            -- naughty things to the secure container, like re-enable IO
            -- devices.             
            state <= ReturnFromHypervisor;
          end if;
          if last_value(6)='1' then
            matrix_rain_seed <= cycle_counter(15 downto 0);
          end if;
        end if; 

                                        -- @IO:GS $D67C.0-7 HCPU:UARTDATA (write) Hypervisor write serial output to UART monitor
        if last_write_address = x"FFD367C" and hypervisor_mode='1' then
          monitor_char <= last_value;
          monitor_char_toggle <= monitor_char_toggle_internal;
          monitor_char_toggle_internal <= not monitor_char_toggle_internal;
                                        -- It can take hundreds of cycles before the serial monitor interface asserts
                                        -- its busy flag, so we have an internal flag we assert until the monitor
                                        -- interface asserts its.
          immediate_monitor_char_busy <= '1';
        end if;

                                        -- @IO:GS $D67D.0 HCPU:CARTEN Hypervisor enable /EXROM and /GAME from cartridge
                                        -- @IO:GS $D67D.1 HCPU:JMP32EN Hypervisor enable 32-bit JMP/JSR etc
                                        -- @IO:GS $D67D.2 HCPU:ROMPROT Hypervisor write protect C65 ROM \$20000-\$3FFFF
                                        -- @IO:GS $D67D.3 HCPU:ASCFAST Hypervisor enable ASC/DIN CAPS LOCK key to enable/disable CPU slow-down in C64/C128/C65 modes
                                        -- @IO:GS $D67D.4 HCPU:CPUFAST Hypervisor force CPU to 48MHz for userland (userland can override via POKE0)
                                        -- @IO:GS $D67D.5 HCPU:F4502 Hypervisor force CPU to 4502 personality, even in C64 IO mode.
                                        -- @IO:GS $D67D.6 HCPU:PIRQ Hypervisor flag to indicate if an IRQ is pending on exit from the hypervisor / set 1 to force IRQ/NMI deferal for 1,024 cycles on exit from hypervisor.
                                        -- @IO:GS $D67D.7 HCPU:PNMI Hypervisor flag to indicate if an NMI is pending on exit from the hypervisor.
        
                                        -- @IO:GS $D67D HCPU:WATCHDOG Hypervisor watchdog register: writing any value clears the watch dog
        if last_write_address = x"FFD367D" and hypervisor_mode='1' then
          cartridge_enable <= last_value(0);
          flat32_enabled <= last_value(1);
          rom_writeprotect <= last_value(2);
          speed_gate_enable <= last_value(3);
          speed_gate_enable_internal <= last_value(3);
          force_fast <= last_value(4);
          force_4502 <= last_value(5);
          irq_defer_request <= last_value(6);
          
          report "irq_pending, nmi_pending <= " & std_logic'image(last_value(6))
            & "," & std_logic'image(last_value(7));
          watchdog_fed <= '1';
        end if;
                                        -- @IO:GS $D67E HCPU:HICKED Hypervisor already-upgraded bit (writing sets permanently)
        if last_write_address = x"FFD367E" and hypervisor_mode='1' then
          hypervisor_upgraded <= '1';
        end if;

      end if;

                                        -- Propagate slow device access interface signals
      slow_access_request_toggle <= slow_access_request_toggle_drive;
      slow_access_address <= slow_access_address_drive;
      slow_access_write <= slow_access_write_drive;
      slow_access_wdata <= slow_access_wdata_drive;
      slow_access_ready_toggle_buffer <= slow_access_ready_toggle;

                                        -- Allow matrix mode in hypervisor
      protected_hardware <= hyper_protected_hardware;
      virtualised_hardware(0) <= virtualise_sd;
      virtualised_hardware(7 downto 1) <= (others => '0');
      cpu_hypervisor_mode <= hypervisor_mode;
      
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
      
                                        -- Copy read memory location to simplify reading from memory.
                                        -- Penalty is +1 wait state for memory other than shadowram.
      read_data_copy <= read_data_complex;
      
                                        -- By default we are doing nothing new.
      pc_inc := '0'; pc_dec := '0'; dec_sp := '0';
      stack_pop := '0'; stack_push := '0';
      
      memory_access_read := '0';
      memory_access_write := '0';
      memory_access_resolve_address := '0';
      
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
      if ((monitor_mem_trace_mode='0' or
           monitor_mem_trace_toggle_last /= monitor_mem_trace_toggle)
          and (monitor_mem_attention_request_drive='0'))
-- PGS 20190510: Required for simulation to work, but breaks monitor memory
-- access when synthesised.
--        or ( monitor_mem_trace_toggle = 'U' or monitor_mem_attention_request_drive = 'U' )
      then
        monitor_mem_trace_toggle_last <= monitor_mem_trace_toggle;
        normal_fetch_state <= InstructionFetch;

                                        -- Or select slower CPU mode if required.
                                        -- Test goes here so that it doesn't break the monitor interface.
                                        -- But the hypervisor always runs at full speed.
        fast_fetch_state <= InstructionDecode;
        cpu_speed := vicii_2mhz&viciii_fast&viciv_fast;
        case cpu_speed is
          when "100" => -- 1mhz
            cpuspeed_external <= x"01";
          when "101" =>
            cpuspeed_external <= x"01";
          when "000" =>
            cpuspeed_external <= x"02";
          when "001" =>
            cpuspeed_external <= x"02";
          when others =>
            cpuspeed_external <= x"04";
        end case;
        if hypervisor_mode='0' and ((speed_gate_drive='1') and (force_fast='0')) and (fast_key='1') then
          case cpu_speed is
            when "100" => -- 1mhz
              cpuspeed <= x"01";
              cpuspeed_internal <= x"01";
            when "101" => -- 1mhz
              cpuspeed <= x"01";
              cpuspeed_internal <= x"01";
            when "110" => -- 3.5mhz
              cpuspeed <= x"04";
              cpuspeed_internal <= x"04";
            when "111" => -- full speed
              cpuspeed <= x"40";
              cpuspeed_internal <= x"40";
            when "000" => -- 2mhz
              cpuspeed <= x"02";
              cpuspeed_internal <= x"02";
            when "001" => -- full speed
              cpuspeed <= x"40";
              cpuspeed_internal <= x"40";
            when "010" => -- 3.5mhz
              cpuspeed <= x"04";
              cpuspeed_internal <= x"04";
            when "011" => -- full speed
              cpuspeed <= x"40";
              cpuspeed_internal <= x"40";
            when others =>
              null;
          end case;
        else
          cpuspeed <= x"40";
          cpuspeed_internal <= x"40";
        end if;
      else
        report "Forcing processor hold: trace_mode="
          & std_logic'image(monitor_mem_trace_mode)
          & " toggle_last=" & std_logic'image(monitor_mem_trace_toggle_last)
          & " toggle=" & std_logic'image(monitor_mem_trace_toggle)
          & " attn_req_drive=" & std_logic'image(monitor_mem_attention_request_drive);
        
        normal_fetch_state <= ProcessorHold;
        fast_fetch_state <= ProcessorHold;
      end if;

                                        -- Force single step while I debug it.
      if debugging_single_stepping='1' then
        report "Forcing processor hold due to debugging_single_step";
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

      monitor_instruction_strobe <= '0';
--      report "monitor_instruction_strobe CLEARED";    

                                        -- report "reset = " & std_logic'image(reset) severity note;
      reset_drive <= reset;
      if reset_drive='0' or watchdog_reset='1' then
        reset_out <= '0';
        state <= ResetLow;
        proceed <= '0';
        wait_states <= x"00";
        wait_states_non_zero <= '0';
        watchdog_fed <= '0';
        watchdog_countdown <= 65535;
        report "resetting cpu: reset_drive = " & std_logic'image(reset_drive)
          & ", watchdog_reset=" & std_logic'image(watchdog_reset);
        reset_cpu_state;
      elsif phi_pause = '1' then
                                        -- Wait for time to catch up with CPU instructions when running at low
                                        -- speed (CPU actually runs at full speed, and just gets held here if it
                                        -- gets too far ahead.  This gives us quite accurate timing at an instruction
                                        -- level, with a jitter of ~1 instruction at any point in time, which should
                                        -- be sufficient even for most fast loaders.
        report "PHI pause : " & integer'image(phi_backlog) & " CPU cycles remaining.";
        proceed <= '0';
      else
                                        -- Honour wait states on memory accesses
                                        -- Clear memory access lines unless we are in a memory wait state
                                        -- XXX replace with single bit test flag for wait_states = 0 to reduce
                                        -- logic depth
        reset_out <= '1';
        if wait_states_non_zero = '1' then
          report "  $" & to_hstring(wait_states)
            &" memory waitstates remaining.  Fastio_rdata = $"
            & to_hstring(fastio_rdata)
            & ", mem_reading=" & std_logic'image(mem_reading)
            & ", fastio_addr=$" & to_hstring(fastio_addr)
            severity note;
          if (accessing_slowram='1') then
            if slow_access_ready_toggle = slow_access_desired_ready_toggle then
                                        -- Next cycle we can do stuff, provided that the serial monitor
                                        -- isn't asking us to do anything.
              proceed <= '1';
              slow_access_write_drive <= '0';
            else
                                        -- Otherwise keep waiting for slow memory interface
              null;
            end if;           
          else
            if wait_states /= x"01" then
              wait_states <= wait_states - 1;
              wait_states_non_zero <= '1';
            else
              wait_states_non_zero <= '0';
              proceed <= '1';
            end if;
          end if;          
        else
                                        -- End of wait states, so clear memory writing and reading

          colour_ram_cs <= '0';
          fastio_write <= '0';
--          fastio_read <= '0';
          --chipram_we <= '0';
          slow_access_write_drive <= '0';

          if mem_reading='1' then
--            report "resetting mem_reading (read $" & to_hstring(memory_read_value) & ")" severity note;
            mem_reading <= '0';
            monitor_mem_reading <= '0';
          end if;

          proceed <= '1';
        end if;

        monitor_proceed <= proceed;
        monitor_request_reflected <= monitor_mem_attention_request_drive;

        report "CPU state : proceed=" & std_logic'image(proceed);
        if proceed='0' then

          -- Make bus idle while waiting
          memory_access_address := (others => '1');
          memory_access_read := '0';
          memory_access_write := '0';
          memory_access_resolve_address := '0';
          memory_access_wdata := (others => '1');
          
        else
                                        -- Main state machine for CPU
          report "CPU state = " & processor_state'image(state) & ", PC=$" & to_hstring(reg_pc) severity note;

          pop_a <= '0'; pop_x <= '0'; pop_y <= '0'; pop_z <= '0';
          pop_p <= '0';

          request_monitor_halt_trigger <= '0';

          case state is
            when ResetLow =>
                                        -- Reset now maps hyppo at $8000-$BFFF, and enters through $8000
                                        -- by triggering the hypervisor.
                                        -- XXX indicate source of hypervisor entry
              reset_cpu_state;
              state <= TrapToHypervisor;
            when VectorRead =>
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
              pc_inc := '0';
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
              state <= InterruptPushPCL;

            when InterruptPushPCL =>
              pc_inc := '0';
              stack_push := '1';
              state <= InterruptPushP;

              if cpuspeed_internal(7 downto 4) = "0000" and (slow_interrupts='1') then
                -- Charge the 7 cycles for the interrupt when CPU is not at
                -- full speed
                phi_add_backlog <= '1'; phi_new_backlog <= 7;          
              end if;
              
            when InterruptPushP =>
                                        -- Push flags to stack (already put in reg_t a few cycles earlier)
              stack_push := '1';
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
                                        -- And set PC to the byte following, unless we are held, in which
                                        -- case the increment will happen in InstructionFetch
              if fast_fetch_state = InstructionDecode then
                reg_pc <= reg_pc+1;
                report "Pre-incrementing PC for immediate dispatch" severity note;
              end if;
              state <= fast_fetch_state;
              monitor_instruction_strobe <= '1';
              report "monitor_instruction_strobe assert";
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
                if monitor_mem_write_drive='1' then
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
                    monitor_mem_reading <= '1';
                    mem_reading <= '1';
                    proceed <= '0';
                    state <= MonitorMemoryAccess;
                  end if;
                end if;
              end if;
            when MonitorMemoryAccess =>
              monitor_mem_rdata <= memory_read_value;
              if monitor_mem_attention_request_drive='1' then 
                monitor_mem_attention_granted <= '1';
                monitor_mem_attention_granted_internal <= '1';
              else
                monitor_mem_attention_granted <= '0';
                monitor_mem_attention_granted_internal <= '0';
                report "Holding processor due to monitor memory access";
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

              report "ZPCACHE: Flushing cache due to trap to hypervisor";
              cache_flushing <= '1';
              cache_flush_counter <= (others => '0');
              
                                        -- NEVER leave the @#$%! decimal flag set when entering the hypervisor
                                        -- (This took MONTHS to realise as the source of a MYRIAD of hypervisor
                                        -- problems.  Anyone removing this without asking Paul first will
                                        -- be appropriately punished.)
              flag_d <= '0';

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
              if hyper_protected_hardware(7)='0' then
                reg_pc(8 downto 2) <= hypervisor_trap_port;
              else
                -- Any hypervisor trap from in secure mode instead calls one
                -- specific trap, and automatically generates a signal to the
                -- monitor interface to say that the user wishes to exit the
                -- secure compartment.
                -- Trap $11 is enter secure mode, and trap $12 is exit.
                -- $12 x 4 = $48
                reg_pc(15 downto 0) <= x"8048";
                -- But we also clear the secure mode flag on the CPU, and
                -- reactivate matrix mode, so that the monitor can triage the exit
                -- before the hypervisor gets activated again.
                -- (this will implicitly cause the processor to stop, because the
                -- monitor will be indicating secure mode to us, until such time
                -- as it receives and ACCEPT or REJECT command.
                hyper_protected_hardware(7 downto 6) <= "01";
              end if;
                                        -- map hypervisor ROM in upper moby
                                        -- ROM is at $FFF8000-$FFFBFFF
              reg_map_high <= "0011";
              reg_offset_high <= x"f00"; -- add $F0000
              reg_mb_high <= x"ff";
                                        -- Make sure that a naughty person can't trick the hypervisor
                                        -- into modifying itself, by having the Hypervisor address space
                                        -- mapped in the bottom 32KB of address space.
              if reg_mb_low = x"ff" then
                reg_mb_low <= x"00";
              end if;
                                        -- IO, but no C64 ROMS
              cpuport_ddr <= x"3f"; cpuport_value <= x"35";

                                        -- enable hypervisor mode flag
              hypervisor_mode <= '1';
                                        -- start fetching next instruction
              state <= normal_fetch_state;
              report "monitor_instruction_strobe assert (TrapToHypervisor)";
              monitor_instruction_strobe <= '1';
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

              report "ZPCACHE: Flushing cache due to return from hypervisor";
              cache_flushing <= '1';
              cache_flush_counter <= (others => '0');
              
                                        -- clear hypervisor mode flag
              hypervisor_mode <= '0';
                                        -- start fetching next instruction
              state <= normal_fetch_state;
              report "monitor_instruction_strobe assert (ReturnFromHypervisor)";
              monitor_instruction_strobe <= '1';
            when DMAgicTrigger =>
                                        -- Clear DMA pending flag
              report "DMAgic: Processing DMA request";
              dma_pending <= '0';
                                        -- Begin to load DMA registers
                                        -- We load them from the 20 bit address stored $D700 - $D702
                                        -- plus the 8-bit MB value in $D704
              reg_dmagic_addr <= reg_dmagic_addr + 1;
              if job_uses_options='0' then              
                state <= DMAgicReadList;
              else
                dmagic_option_id(7) <= '0';
                state <= DMAgicReadOptions;
              end if;
              dmagic_list_counter <= 0;
              phi_add_backlog <= '1'; phi_new_backlog <= 1;
            when DMAgicReadOptions =>
              reg_dmagic_addr <= reg_dmagic_addr + 1;

              report "Parsing DMA options: option_id=$" & to_hstring(dmagic_option_id)
                & ", new byte=$" & to_hstring(memory_read_value);
              
              if dmagic_option_id(7)='1' then
                                        -- This is the value for this option
                report "Processing DMA option $" & to_hstring(dmagic_option_id)
                  & " $" & to_hstring(memory_read_value);
                dmagic_option_id <= (others => '0');
                case dmagic_option_id is
                  -- XXX - Convert this information to an info block?
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $80 $xx = Set MB of source address
                  
                  when x"80" => reg_dmagic_src_mb <= memory_read_value;
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $81 $xx = Set MB of destination address
                  when x"81" => reg_dmagic_dst_mb <= memory_read_value;
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $82 $xx = Set source skip rate (/256ths of bytes)
                  when x"82" => reg_dmagic_src_skip(7 downto 0) <= memory_read_value;
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $83 $xx = Set source skip rate (whole bytes)
                  when x"83" => reg_dmagic_src_skip(15 downto 8) <= memory_read_value;
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $84 $xx = Set destination skip rate (/256ths of bytes)
                  when x"84" => reg_dmagic_dst_skip(7 downto 0) <= memory_read_value;
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $85 $xx = Set destination skip rate (whole bytes)
                  when x"85" => reg_dmagic_dst_skip(15 downto 8) <= memory_read_value;
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $86 $xx = Don't write to destination if byte value = $xx, and option $06 enabled
                  when x"86" => reg_dmagic_transparent_value <= memory_read_value;
                  when others => null;
                end case;
              else
                if memory_read_value(7)='1' then
                                        -- Options with 1 byte argument, so remember
                                        -- this option ID byte, and process next byte.
                  dmagic_option_id <= memory_read_value;
                  report "Saw DMA option $" & to_hstring(memory_read_value)
                    & ", will read parameter value";
                else
                                        -- Options without arguments
                  report "Processing single-byte DMA option";
                  case memory_read_value is
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $00 = End of options
                    when x"00" =>
                      report "End of Enhanced DMA option list.";
                      state <= DMAgicReadList;
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $06 = Use $86 $xx transparency value (don't write source bytes to destination, if byte value matches $xx)
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $07 = Disable $86 $xx transparency value.
                      
                    when x"06" => reg_dmagic_use_transparent_value <= '0';               
                    when x"07" => reg_dmagic_use_transparent_value <= '1';               
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $0A = Use F018A list format
                                        -- @ IO:GS $D705 - Enhanced DMAgic job option $0B = Use F018B list format
                    when x"0A" => job_is_f018b <= '0';
                    when x"0B" => job_is_f018b <= '1';
                    when others => null;
                  end case;
                end if;
              end if;
            when DMAgicReadList =>
              report "DMAgic: Reading DMA list (setting dmagic_cmd to $" & to_hstring(dmagic_count(7 downto 0))
                &", memory_read_value = $"&to_hstring(memory_read_value)&")";
                                        -- ask for next byte from DMA list
              phi_add_backlog <= '1'; phi_new_backlog <= 1;
                                        -- shift read byte into DMA registers and shift everything around
              dmagic_modulo(15 downto 8) <= memory_read_value;
              dmagic_modulo(7 downto 0) <= dmagic_modulo(15 downto 8);
              if (job_is_f018b = '1') then
                dmagic_subcmd <= dmagic_modulo(7 downto 0);
                dmagic_dest_bank_temp <= dmagic_subcmd;
              else
                dmagic_dest_bank_temp <= dmagic_modulo(7 downto 0);
              end if;
              dmagic_dest_addr(23 downto 16) <= dmagic_dest_bank_temp;
              dmagic_dest_addr(15 downto 8) <= dmagic_dest_addr(23 downto 16);
              dmagic_src_bank_temp <= dmagic_dest_addr(15 downto 8);
              dmagic_src_addr(23 downto 16) <= dmagic_src_bank_temp;
              dmagic_src_addr(15 downto 8) <= dmagic_src_addr(23 downto 16);
              dmagic_count(15 downto 8) <= dmagic_src_addr(15 downto 8);
              dmagic_count(7 downto 0) <= dmagic_count(15 downto 8);
              dmagic_cmd <= dmagic_count(7 downto 0);
              if (job_is_f018b = '0') and (dmagic_list_counter = 10) then
                state <= DMAgicGetReady;
              elsif dmagic_list_counter = 11 then
                state <= DMAgicGetReady;
              else
                dmagic_list_counter <= dmagic_list_counter + 1;
                reg_dmagic_addr <= reg_dmagic_addr + 1;
              end if;
              report "DMAgic: Reading DMA list (end of cycle)";
            when DMAgicGetReady =>
              report "DMAgic: got list: cmd=$"
                & to_hstring(dmagic_cmd)
                & ", src=$"
                & to_hstring(dmagic_src_addr(23 downto 8))
                & ", dest=$" & to_hstring(dmagic_dest_addr(23 downto 8))
                & ", count=$" & to_hstring(dmagic_count);
              phi_add_backlog <= '1'; phi_new_backlog <= 1;
              if (job_is_f018b = '1') then
                dmagic_src_addr(35 downto 28) <= reg_dmagic_src_mb + dmagic_src_bank_temp(6 downto 4);
                dmagic_src_addr(27 downto 24) <= dmagic_src_bank_temp(3 downto 0);
                dmagic_dest_addr(35 downto 28) <= reg_dmagic_dst_mb + dmagic_dest_bank_temp(6 downto 4);
                dmagic_dest_addr(27 downto 24) <= dmagic_dest_bank_temp(3 downto 0);
              else
                dmagic_src_addr(35 downto 28) <= reg_dmagic_src_mb;
                dmagic_src_addr(27 downto 24) <= dmagic_src_bank_temp(3 downto 0);
                dmagic_dest_addr(35 downto 28) <= reg_dmagic_dst_mb;
                dmagic_dest_addr(27 downto 24) <= dmagic_dest_bank_temp(3 downto 0);
              end if;               
              dmagic_src_addr(7 downto 0) <= (others => '0');
              dmagic_dest_addr(7 downto 0) <= (others => '0');
              dmagic_src_io <= dmagic_src_bank_temp(7);
              if (job_is_f018b = '1') then
                dmagic_src_direction <= dmagic_cmd(4);
                dmagic_src_modulo <= dmagic_subcmd(0);
                dmagic_src_hold <= dmagic_subcmd(1);
              else
                dmagic_src_direction <= dmagic_src_bank_temp(6);
                dmagic_src_modulo <= dmagic_src_bank_temp(5);
                dmagic_src_hold <= dmagic_src_bank_temp(4);
              end if;
              dmagic_dest_io <= dmagic_dest_bank_temp(7);
              if (job_is_f018b = '1') then
                dmagic_dest_direction <= dmagic_cmd(5);
                dmagic_dest_modulo <= dmagic_subcmd(2);
                dmagic_dest_hold <= dmagic_subcmd(3);
              else
                dmagic_dest_direction <= dmagic_dest_bank_temp(6);
                dmagic_dest_modulo <= dmagic_dest_bank_temp(5);
                dmagic_dest_hold <= dmagic_dest_bank_temp(4);
              end if;

                                        -- Save memory mapping flags, and set memory map to
                                        -- be all RAM +/- IO area
              pre_dma_cpuport_bits <= cpuport_value(2 downto 0);
              cpuport_value(2 downto 1) <= "10";
              
              case dmagic_cmd(1 downto 0) is                
                when "11" => -- fill                  
                  state <= DMAgicFill;

                                        -- And set IO visibility based on destination bank flags
                                        -- since we are only writing.
                  cpuport_value(0) <= dmagic_dest_bank_temp(7);
                  
                when "00" => -- copy
                  dmagic_first_read <= '1';
                  state <= DMagicCopyRead;
                                        -- Set IO visibility based on source bank flags
                  cpuport_value(0) <= dmagic_src_bank_temp(7);
                when others =>
                                        -- swap and mix not yet implemented
                  state <= normal_fetch_state;
                  report "monitor_instruction_strobe assert (DMA swap/mix unimplemented function abort)";
                  monitor_instruction_strobe <= '1';
              end case;
                                        -- XXX Potential security issue: Ideally we should not allow a DMA to
                                        -- write to Hypervisor memory, so as to make it harder to overwrite
                                        -- hypervisor memory.  However, we currently use it to do exactly
                                        -- that in the hickup routine.  Thus before we implement such
                                        -- protection, we need to change hickup to use a simple copy
                                        -- routine. We then need to get a bit creative about how we
                                        -- implement the restriction, as the hypervisor memory doesnt
                                        -- exist in its own 1MB off address space, so we can't easily
                                        -- quarantine it by blockinig DMA to that section off address
                                        -- space. It does live in its own 64KB of address space, however.
                                        -- that would involve adding a wrap-around check on the bottom 16
                                        -- bits of the address.
                                        -- One question is: Does it make sense to try to protect against
                                        -- this, since the hypervisor memory is only accessible from
                                        -- hypervisor mode, and any exploit via DMA requires another
                                        -- exploit first.  Perhaps the only additional issue is if a DMA
                                        -- chained request went feral, but even that requires at least a
                                        -- significant bug in the hypervisor.  We could just disable
                                        -- chained DMA in the hypevisor as a simple safety catch, as this
                                        -- will provide the main value, without a burdonsome change. But
                                        -- even that gets used in hyppo when clearing the screen on
                                        -- boot.
            when DMAgicFill =>
                                        -- Fill memory at dmagic_dest_addr with dmagic_src_addr(7 downto
                                        -- 0)

                                        -- Do memory write
              phi_add_backlog <= '1'; phi_new_backlog <= 1;
                                        -- Update address and check for end of job.
                                        -- XXX Ignores modulus, whose behaviour is insufficiently defined
                                        -- in the C65 specifications document
              if dmagic_dest_hold='0' then
                if dmagic_dest_direction='0' then
                  dmagic_dest_addr(23 downto 0)
                    <= dmagic_dest_addr(23 downto 0) + reg_dmagic_dst_skip;
                else
                  dmagic_dest_addr(23 downto 0)
                    <= dmagic_dest_addr(23 downto 0) - reg_dmagic_dst_skip;
                end if;
              end if;
                                        -- XXX we compare count with 1 before decrementing.
                                        -- This means a count of zero is really a count of 64KB, which is
                                        -- probably different to on a real C65, but this is untested.
              if dmagic_count = 1 then
                                        -- DMA done
                report "DMAgic: DMA fill complete";
                cpuport_value(2 downto 0) <= pre_dma_cpuport_bits;
                if dmagic_cmd(2) = '0' then
                                        -- Last DMA job in chain, go back to executing instructions
                  report "monitor_instruction_strobe assert (end of DMA job)";
                  monitor_instruction_strobe <= '1';
                  state <= normal_fetch_state;
                                        -- Reset DMAgic options to normal at the end of the last DMA job
                                        -- in a chain.
                  dmagic_reset_options;
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
              phi_add_backlog <= '1'; phi_new_backlog <= 1;
              
                                        -- Update source address.
                                        -- XXX Ignores modulus, whose behaviour is insufficiently defined
                                        -- in the C65 specifications document
              report "dmagic_src_addr=$" & to_hstring(dmagic_src_addr(35 downto 8))
                &"."&to_hstring(dmagic_src_addr(7 downto 0))
                & " (reg_dmagic_src_skip=$" & to_hstring(reg_dmagic_src_skip)&")";
              if dmagic_src_hold='0' then
                if dmagic_src_direction='0' then
                  dmagic_src_addr(23 downto 0)
                    <= dmagic_src_addr(23 downto 0) + reg_dmagic_src_skip;
                else
                  dmagic_src_addr(23 downto 0)
                    <= dmagic_src_addr(23 downto 0) - reg_dmagic_src_skip;
                end if;
              end if;
                                        -- Set IO visibility for destination
              cpuport_value(0) <= dmagic_dest_io;
              state <= DMAgicCopyWrite;
            when DMAgicCopyWrite =>
                                        -- Remember value just read
              report "dmagic_src_addr=$" & to_hstring(dmagic_src_addr(35 downto 8))
                &"."&to_hstring(dmagic_src_addr(7 downto 0))
                & " (reg_dmagic_src_skip=$" & to_hstring(reg_dmagic_src_skip)&")";
              dmagic_first_read <= '0';
              reg_t <= memory_read_value;

                                        -- Set IO visibility for source
              cpuport_value(0) <= dmagic_src_io;              
              state <= DMAgicCopyRead;

              phi_add_backlog <= '1'; phi_new_backlog <= 1;
              
              if dmagic_first_read = '0' then
                                        -- Update address and check for end of job.
                                        -- XXX Ignores modulus, whose behaviour is insufficiently defined
                                        -- in the C65 specifications document
                if dmagic_dest_hold='0' then
                  if dmagic_dest_direction='0' then
                    dmagic_dest_addr(23 downto 0)
                      <= dmagic_dest_addr(23 downto 0) + reg_dmagic_dst_skip;
                  else
                    dmagic_dest_addr(23 downto 0)
                      <= dmagic_dest_addr(23 downto 0) - reg_dmagic_dst_skip;
                  end if;
                end if;
                                        -- XXX we compare count with 1 before decrementing.
                                        -- This means a count of zero is really a count of 64KB, which is
                                        -- probably different to on a real C65, but this is untested.
                if dmagic_count = 1 then
                                        -- DMA done
                  report "DMAgic: DMA copy complete";
                  cpuport_value(2 downto 0) <= pre_dma_cpuport_bits;
                  if dmagic_cmd(2) = '0' then
                                        -- Last DMA job in chain, go back to executing instructions
                    report "monitor_instruction_strobe assert (end of DMA job)";
                    monitor_instruction_strobe <= '1';
                    state <= normal_fetch_state;
                                        -- Reset DMAgic options to normal at the end of the last DMA job
                                        -- in a chain.
                    dmagic_reset_options;
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
              if (breakpoint0_pc = reg_pc and breakpoint0_enable='1')
                or (breakpoint1_pc = reg_pc and breakpoint1_enable='1')
                or (breakpoint2_pc = reg_pc and breakpoint2_enable='1')
                or (breakpoint3_pc = reg_pc and breakpoint3_enable='1')
              then
                -- We have hit a breakpoint.
                if breakpoint_hyperrupt='1' then
                  -- Hyperrupt on breakpoint (can trigger freeze menu, for example)
                  hypervisor_trap_port <= "1000110";
                  state <= TrapToHypervisor;
                else
                  -- Alternatively, do a UART monitor halt.
                  -- But to do this, we need to signal the monitor, and give it
                  -- time to stop the CPU, so we assert the flag saying we want
                  -- to be halted, and then go into the IO settle state for a while,
                  -- to give the UART monitor time to notice our request.
                  request_monitor_halt_trigger <= '1';
                end if;
             elsif (hypervisor_mode='0')
                and ((irq_pending='1' and flag_i='0') or nmi_pending='1')
                and (monitor_irq_inhibit='0') then
                                        -- An interrupt has occurred
                pc_inc := '0';
                state <= Interrupt;
                                        -- Make sure reg_instruction /= I_BRK, so that B flag is not
                                        -- erroneously set.
                reg_instruction <= I_SEI;
              elsif (hyper_trap_pending = '1' and hypervisor_mode='0') then
                                        -- Trap to hypervisor
                hyper_trap_pending <= '0';					 
                state <= TrapToHypervisor;                
                if matrix_trap_pending = '1' then
                                        -- Trap #67 ($43) = ALT-TAB key press (toggles matrix mode)
                  hypervisor_trap_port <= "1000011";                     
                  matrix_trap_pending <= '0';
                elsif f011_read_trap_pending = '1' then
                                        -- Trap #68 ($44) = SD/F011 read sector
                  hypervisor_trap_port <= "1000100";
                  f011_read_trap_pending <= '0';
                elsif f011_write_trap_pending = '1' then
                                        -- Trap #69 ($45) = SD/F011 write sector
                  hypervisor_trap_port <= "1000101";
                  f011_write_trap_pending <= '0';
                else
                                        -- Trap #66 ($42) = RESTORE key double-tap
                  hypervisor_trap_port <= "1000010";                     
                end if;	
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
              phi_add_backlog <= '1';
              phi_new_backlog <= cycle_count_lut(to_integer(timing6502&memory_read_value));
              
                                        -- 4502 doesn't allow interrupts immediately following a
                                        -- single-cycle instruction
              if (hypervisor_mode='0') and (
                (no_interrupt = '0')
                and ((irq_pending='1' and flag_i='0') or nmi_pending='1')) then
                                        -- An interrupt has occurred
                report "Interrupt detected, decrementing PC";
                state <= Interrupt;
                reg_pc <= reg_pc - 1;
                pc_inc := '0';
                                        -- Make sure reg_instruction /= I_BRK, so that B flag is not
                                        -- erroneously set.
                reg_instruction <= I_SEI;
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
                value32_enabled <= '0';
                next_is_axyz32_instruction <= '0';

                report "VAL32: next_is_axyz32_instruction=" & std_logic'image(next_is_axyz32_instruction)
                  & ", value32_enabled = " & std_logic'image(value32_enabled);
                
                case memory_read_value is
                  when x"03" =>
                    flag_e <= '1'; -- SEE
                    report "ZPCACHE: Flushing cache due to setting E flag";
                    cache_flushing <= '1';
                    cache_flush_counter <= (others => '0');
                  when x"0A" => reg_a <= a_asl; set_nz(a_asl); flag_c <= reg_a(7); -- ASL A
                  when x"0B" => reg_y <= reg_sph; set_nz(reg_sph); -- TSY
                  when x"18" => flag_c <= '0';  -- CLC
                  when x"1A" => reg_a <= a_incremented; set_nz(a_incremented); -- INC A
                  when x"1B" => reg_z <= z_incremented; set_nz(z_incremented); -- INZ
                  when x"2A" => reg_a <= a_rol; set_nz(a_rol); flag_c <= reg_a(7); -- ROL A
                  when x"2B" =>
                    reg_sph <= reg_y; -- TYS
                    report "ZPCACHE: Flushing cache due to setting SPH";
                    cache_flushing <= '1';
                    cache_flush_counter <= (others => '0');                    
                  when x"38" => flag_c <= '1';  -- SEC
                  when x"3A" => reg_a <= a_decremented; set_nz(a_decremented); -- DEC A
                  when x"3B" => reg_z <= z_decremented; set_nz(z_decremented); -- DEZ
                  when x"42" =>
                    reg_a <= a_negated; set_nz(a_negated); -- NEG A
                    -- NEG / NEG / INSTRUCTION is used to indicate using AXYZ
                    -- regs as single 32-bit pseudo register.
                    -- This prefix can be used together with the NOP / NOP prefix
                    -- for the 32-bit ZP-indirect instructions. In that case,
                    -- this prefix must come first, i.e., NEG / NEG / NOP / NOP
                    -- / LDA or STA ($xx), Z
                    if value32_enabled = '0' then
                      value32_enabled <= '1';
                    else
                      next_is_axyz32_instruction <= '1';
                    end if;
                  when x"43" => reg_a <= a_asr; set_nz(a_asr); -- ASR A
                  when x"4A" => reg_a <= a_lsr; set_nz(a_lsr); flag_c <= reg_a(0); -- LSR A
                  when x"4B" => reg_z <= reg_a; set_nz(reg_a); -- TAZ
                  when x"5B" =>
                    reg_b <= reg_a; -- TAB
                    report "ZPCACHE: Flushing cache due to moving ZP";
                    cache_flushing <= '1';
                    cache_flush_counter <= (others => '0');
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
                                -- Preserve NEG / NEG prefix status for AXYZ
                                -- 32-bit pseudo register usage.
                                next_is_axyz32_instruction <= next_is_axyz32_instruction;
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
                    next_is_axyz32_instruction <= next_is_axyz32_instruction;
                    state <= Cycle2;
                  end if;
                else
                  no_interrupt <= '1';
                                        -- Allow monitor to trace through single-cycle instructions
                  if monitor_mem_trace_mode='1' or debugging_single_stepping='1' then
                    report "monitor_instruction_strobe assert (4510 single cycle instruction, single-stepped)";
                    state <= normal_fetch_state;
                    pc_inc := '0';
                  else
                    report "monitor_instruction_strobe assert (4510 single cycle instruction)";                    
                  end if;
                  monitor_instruction_strobe <= '1';
                end if;
                
                monitor_instruction <= to_unsigned(instruction'pos(instruction_lut(to_integer(emu6502&memory_read_value))),8);
                is_rmw <= '0'; is_load <= '0';
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
                  when I_STA => null;
                  when I_STX => null;
                  when I_STY => null;
                  when I_STZ => null;

                                        -- And 6502 illegal opcodes
                  when I_SLO => is_rmw <= '1';
                  when I_RLA => is_rmw <= '1';
                  when I_SRE => is_rmw <= '1';
                  when I_SAX => null;
                  when I_LAX => is_load <= '1';
                  when I_RRA => is_rmw <= '1';
                  when I_DCP => is_rmw <= '1';
                  when I_ISC => is_rmw <= '1';
                  when I_ANC => is_load <= '1';
                  when I_ALR => null;
                  when I_ARR => null;
                  when I_XAA => null;
                  when I_AXS => null;
                  when I_AHX => null;
                  when I_SHY => null;
                  when I_SHX => null;
                  when I_TAS => null;
                  when I_LAS => null;
                  when I_KIL =>
                    state <= TrapToHypervisor;
                                        -- Trap $7F = 6502 KIL instruction encountered
                    hypervisor_trap_port <= "1111111";                     
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
              
              if (hypervisor_mode='0')
                and ((irq_pending='1' and flag_i='0') or nmi_pending='1') then
                                        -- An interrupt has occurred 
                report "Interrupt detected in 6502 mode, decrementing PC";
                state <= Interrupt;
                reg_pc <= reg_pc - 1;
                pc_inc := '0';
                                        -- Make sure reg_instruction /= I_BRK, so that B flag is not
                                        -- erroneously set.
                reg_instruction <= I_SEI;
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

                -- See if this is a single cycle instruction in 6502 mode.
                flat32_address <= '0';
                flat32_address_prime <= '0';
                absolute32_addressing_enabled <= '0';
                
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
                else
                  no_interrupt <= '1';
                  -- Allow monitor to trace through single-cycle instructions
                  if monitor_mem_trace_mode='1' or debugging_single_stepping='1' then
                    report "monitor_instruction_strobe assert (6502 single cycle instruction, single stepped)";
                    state <= normal_fetch_state;
                    pc_inc := '0';
                  else
                    report "monitor_instruction_strobe assert (6502 single cycle instruction)";
                  end if;
                  monitor_instruction_strobe <= '1';
                end if;
                
                monitor_instruction <= to_unsigned(instruction'pos(instruction_lut(to_integer(emu6502&memory_read_value))),8);
                is_rmw <= '0'; is_load <= '0';
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
                  when I_STA => null;
                  when I_STX => null;
                  when I_STY => null;
                  when I_STZ => null;

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
              report "VAL32: next_is_axyz32_instruction = " & std_logic'image(next_is_axyz32_instruction);
              reg_pc_jsr <= reg_pc;
              
                                        -- Store and announce arg1
              last_byte2 <= memory_read_value;
              last_bytecount <= 2;
              monitor_arg1 <= memory_read_value;
              monitor_ibytes(1) <= '1';
              reg_arg1 <= memory_read_value;
              reg_addr(7 downto 0) <= memory_read_value;

                                        -- Request ZP/stack cache read
                                        -- Cache lines are 4 bytes wide
                                        -- ZP cache is bottom 64 lines
              cache_raddr(9 downto 6) <= "0000";
              if reg_addressingmode = M_InnX then
                                        -- Pre-increment address ZP by X
                temp_value := memory_read_value + reg_x;
                cache_raddr(5 downto 0) <= temp_value(7 downto 2);
              else
                cache_raddr(5 downto 0) <= memory_read_value(7 downto 2);
              end if;
              if cache_flushing = '1' or reg_addressingmode = M_InnSPY then
                                        -- Don't use cache if flushing or for the stack-relative instructions
                                        -- (at least until we work out the correct formula for the
                                        -- InnSPY access -- it should be quite possibe)
                cache_read_valid <= '0';
              else
                cache_read_valid <= '1';
                report "ZPCACHE: Reading ZP cache entry $" & to_hstring(memory_read_value(7 downto 2));
              end if;
              
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
                    report "VAL32: ZP LoadTarget";
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
                    report "monitor_instruction_strobe assert (8-bit branch not taken)";
                    monitor_instruction_strobe <= '1';
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
                report "monitor_instruction_strobe assert (unknown mode in 32-bit flat addressed instruction)";
                monitor_instruction_strobe <= '1';
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
              state <= Flat32SaveAddress2;
            when Flat32SaveAddress2 =>
              pc_inc := '0';
              stack_push := '1';
              state <= Flat32SaveAddress3;
            when Flat32SaveAddress3 =>
              pc_inc := '0';
              stack_push := '1';
              state <= Flat32SaveAddress4;
            when Flat32SaveAddress4 =>
              pc_inc := '0';
              stack_push := '1';
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
              reg_addr <= reg_addr + 1;
              state <= Flat32Dereference1;
            when Flat32Dereference1 =>
              pc_inc := '0';
              reg_addr <= reg_addr + 1;
              reg_addr32(7 downto 0) <= memory_read_value;
              state <= Flat32Dereference2;
            when Flat32Dereference2 =>
              pc_inc := '0';
              reg_addr <= reg_addr + 1;
              reg_addr32(15 downto 8) <= memory_read_value;
              state <= Flat32Dereference3;
            when Flat32Dereference3 =>
              pc_inc := '0';
              reg_addr <= reg_addr + 1;
              reg_addr32(23 downto 16) <= memory_read_value;
              state <= Flat32Dereference4;
            when Flat32Dereference4 =>
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
              report "monitor_instruction_strobe assert (Flat32 dispatch)";
              monitor_instruction_strobe <= '1';
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
                    state <= ZPRelReadZP;
                  when M_InnY =>
                    temp_addr := reg_b&reg_arg1;
                    reg_addr <= temp_addr + 1;
                    state <= InnYReadVectorLow;
                  when M_InnZ =>
                    temp_addr := reg_b&reg_arg1;
                    reg_addr <= temp_addr + 1;
                    report "VAL32: InnZReadVectorLow read address set to $"& to_hstring(memory_access_address);
                    state <= InnZReadVectorLow;
                  when M_rr =>
                    temp_addr := reg_pc +
                                 to_integer(reg_arg1(7)&reg_arg1(7)&reg_arg1(7)&reg_arg1(7)&
                                            reg_arg1(7)&reg_arg1(7)&reg_arg1(7)&reg_arg1(7)&
                                            reg_arg1);
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
                      report "Setting PC (8-bit branch)";
                      
                                        -- Charge one cycle for branches that are taken
                      if temp_addr(15 downto 8) /= reg_pc(15 downto 8) then
                                        -- 1 cycle for branch taken, + 1 cycle extra for page crossing
                        phi_new_backlog <= 2;
                      else
                        phi_new_backlog <= 1;
                      end if;
                      phi_add_backlog <= charge_for_branches_taken;

                      pc_inc := '0';
                      reg_pc <= temp_addr;
                                        -- Take an extra cycle when taking a branch.  This avoids
                                        -- poor timing due to memory-to-memory activity in a
                                        -- single cycle.

                      report "monitor_instruction_strobe assert (8-bit branch taken)";
                      monitor_instruction_strobe <= '1';
                      state <= normal_fetch_state;

                    else
                      report "NOT Taking 8-bit branch" severity note;
                                        -- Branch will not be taken.
                                        -- fetch next instruction now to save a cycle
                      report "monitor_instruction_strobe assert (8-bit branch not taken)";
                      monitor_instruction_strobe <= '1';
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
                      report "monitor_instruction_strobe assert (16-bit branch not taken)";
                      monitor_instruction_strobe <= '1';
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
              dec_sp := '1';
              pc_inc := '0';
              state <= CallSubroutine2;
            when CallSubroutine2 =>
                                        -- Finish determining subroutine address
              pc_inc := '0';

              report "Jumping to $" & to_hstring(reg_addr)
                severity note;
                                        -- Immediately start reading the next instruction
              if fast_fetch_state = InstructionDecode then
                                        -- Fast dispatch, so bump PC ready for next cycle
                report "Setting PC in JSR/BSR (fast dispatch)";
                reg_pc <= reg_addr + 1;
              else
                                        -- Normal dispatch
                report "Setting PC in JSR/BSR (normal dispatch)";
                reg_pc <= reg_addr;
              end if;
              report "monitor_instruction_strobe assert (JSR/BSR)";
              monitor_instruction_strobe <= '1';
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
              report "monitor_instruction_strobe assert (TakeBranch8)";
              monitor_instruction_strobe <= '1';
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
              report "monitor_instruction_strobe assert (Stack pull instruction)";
              monitor_instruction_strobe <= '1';
              state <= fast_fetch_state;
              if fast_fetch_state = InstructionDecode then pc_inc := '1'; end if;
            when B16TakeBranch =>
              report "Setting PC: 16-bit branch will be taken";
              reg_pc <= reg_pc + to_integer(reg_addr) - 1;
                                        -- Charge one cycle for branches that are taken
              phi_new_backlog <= 1;
              phi_add_backlog <= charge_for_branches_taken;
              report "monitor_instruction_strobe assert (take 16-bit branch)";
              monitor_instruction_strobe <= '1';
              state <= normal_fetch_state;
            when InnXReadVectorLow =>
              reg_addr(7 downto 0) <= memory_read_value;
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
              report "VAL32: InnZReadVectorLow value read as $" & to_hstring(memory_read_value)
                & ", memory_access_address was $" & to_hstring(memory_access_address);
              reg_addr_lsbs(7 downto 0) <= memory_read_value;
              if absolute32_addressing_enabled='1' then
                report "VAL32: absolute32_addressing_enabled=1, so proceeding to InnZReadVectorByte2";
                state <= InnZReadVectorByte2;
                reg_addr <= reg_addr + 1;
              else
                reg_addr(7 downto 0) <= memory_read_value;
                state <= InnZReadVectorHigh;
              end if;
            when InnZReadVectorByte2 =>
                                        -- Do addition of Z register as we go along, so that we don't have
                                        -- a 32-bit carry.
              reg_addr <= reg_addr + 1;
              if (reg_instruction = I_STA) and (next_is_axyz32_instruction='1') then
                report "VAL32/ABS32: not adding value of Z for 32-bit STA ($nn),Z because it is using 32-bit AXYZ register";
                
                temp17 :=
                  to_unsigned(to_integer(memory_read_value&reg_addr_lsbs(7 downto 0))
                              + 0,17);
              else
                report "VAL32/ABS32: Adding "
                  & integer'image(to_integer(memory_read_value&reg_addr_lsbs(7 downto 0)) )
                  & " to " & integer'image(to_integer(reg_z));

                temp17 :=
                  to_unsigned(to_integer(memory_read_value&reg_addr_lsbs(7 downto 0))
                              + to_integer(reg_z),17);
              end if;
              reg_addr_lsbs <= temp17(15 downto 0);
              pointer_carry <= temp17(16);
              state <= InnZReadVectorByte3;
            when InnZReadVectorByte3 =>
                                        -- Do addition of Z register as we go along, so that we don't have
                                        -- a 32-bit carry.
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
              report "VAL32/ABS32: final address is $"
                & to_hstring(temp9(3 downto 0))
                & to_hstring(reg_addr_msbs(7 downto 0))
                & to_hstring(reg_addr_lsbs);
              if is_load='1' or is_rmw='1' then
                report "VAL32: (ZP),Z LoadTarget";
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
                report "monitor_instruction_strobe assert (don't take ZP bit check branch)";
                monitor_instruction_strobe <= '1';
                state <= normal_fetch_state;
              end if;
            when JumpDereference =>
                                        -- reg_addr holds the address we want to load a 16 bit address
                                        -- from for a JMP or JSR.
                                        -- XXX should this only step the bottom 8 bits for ($nn,X)
                                        -- dereferencing?
              if emu6502='1' then
                reg_addr(7 downto 0) <= reg_addr(7 downto 0) + 1;
              else
                reg_addr <= reg_addr + 1;
              end if;
              state <= JumpDereference2;
            when JumpDereference2 =>
              reg_t <= memory_read_value;
              state <= JumpDereference3;
            when JumpDereference3 =>
                                        -- Finished dereferencing, set PC
              reg_addr <= memory_read_value&reg_t;
              report "Setting PC: Finished dereferencing JMP";
              reg_pc <= memory_read_value&reg_t;
              if reg_instruction=I_JMP then
                report "monitor_instruction_strobe assert (JMP indirect)";
                monitor_instruction_strobe <= '1';
                state <= normal_fetch_state;
              else
                report "MAP: Doing JSR ($nnnn) to $"&to_hstring(memory_read_value&reg_t);
                dec_sp := '1';
                state <= CallSubroutine;
              end if;
            when DummyWrite =>
              state <= WriteCommit;
            when WriteCommit =>
              report "monitor_instruction_strobe assert (WriteCommit)";
              monitor_instruction_strobe <= '1';
              state <= normal_fetch_state;
            when LoadTarget =>
              -- If an instruction was preceeded with NEG / NEG, then the load
              -- is into all four registers, AXYZ, as a pseudo register.
              -- We only support this for certain instructions:
              -- LDA, STA, CMP, ADC, SBC, ORA, EOR, AND,
              -- INC, DEC, ROL, ROR, ASL, LSR.
              -- (All addressing modes are supported, however)
              report "VAL32: next_is_axyz32_instruction = " & std_logic'image(next_is_axyz32_instruction)
                & ", reg_instruction = " & instruction'image(reg_instruction) & ", reg_addr=$" & to_hstring(reg_addr);
              if next_is_axyz32_instruction = '1' then
                case reg_instruction is
                  when I_LDA | I_CMP | I_ADC | I_SBC | I_ORA | I_EOR | I_AND | I_INC | I_DEC
                    | I_ROL | I_ROR | I_ASL | I_LSR =>
                    report "VAL32: Proceeding to LoadTarget32";
                    state <= LoadTarget32;
                    axyz_phase <= 1;
                  when others =>
                    -- Process other instructions normally
                    report "VAL32: Ignoring unsupported instruction " & instruction'image(reg_instruction);
                    state <= MicrocodeInterpret;
                end case;
              else
                state <= MicrocodeInterpret;
              end if;
            when LoadTarget32 =>
              reg_val32(31 downto 24) <= memory_read_value;
              reg_val32(23 downto 0) <= reg_val32(31 downto 8);
              report "VAL32: reg_val32 = $" & to_hstring(reg_val32) & ", at axyz_phase = " & integer'image(axyz_phase);
              if axyz_phase /= 4 then
                -- More bytes to read, so schedule next byte to read                
                report "VAL32: memory_access_address=$" & to_hstring(memory_access_address);
                axyz_phase <= axyz_phase + 1;
              else
                -- Already got the four bytes, so now trigger the execution
                state <= Execute32;                    
              end if;
            when Execute32 =>
              report "VAL32: reg_val32 = $" & to_hstring(reg_val32) & ", reg_instruction = " & instruction'image(reg_instruction);
              case reg_instruction is
                when I_LDA =>
                  reg_a <= reg_val32(7 downto 0);
                  reg_x <= reg_val32(15 downto 8);
                  reg_y <= reg_val32(23 downto 16);
                  reg_z <= reg_val32(31 downto 24);
                  if reg_val32 = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_n <= reg_val32(31);
                when I_CMP =>
                  vreg33 := '0' & reg_z & reg_y & reg_x & reg_a;
                  vreg33 := vreg33 - reg_val32;
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_c <= not vreg33(32);
                  flag_n <= vreg33(31);
                when I_SBC =>
                  vreg33 := '0' & reg_z & reg_y & reg_x & reg_a;
                  if flag_c='0' then
                    vreg33 := vreg33 - reg_val32 - 1;
                  else
                    vreg33 := vreg33 - reg_val32;
                  end if;
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_c <= not vreg33(32);
                  flag_n <= vreg33(31);
                  reg_a <= vreg33(7 downto 0);
                  reg_x <= vreg33(15 downto 8);
                  reg_y <= vreg33(23 downto 16);
                  reg_z <= vreg33(31 downto 24);
                when I_ADC =>
                  -- Note: No decimal mode for 32-bit add!
                  vreg33 := '0' & reg_z & reg_y & reg_x & reg_a;
                  if flag_c='0' then
                    vreg33 := vreg33 + reg_val32;
                  else
                    vreg33 := vreg33 + reg_val32 + 1;
                  end if;
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_c <= not vreg33(32);
                  flag_n <= vreg33(31);
                  reg_a <= vreg33(7 downto 0);
                  reg_x <= vreg33(15 downto 8);
                  reg_y <= vreg33(23 downto 16);
                  reg_z <= vreg33(31 downto 24);
                when I_ORA =>
                  vreg33 := '0' & reg_z & reg_y & reg_x & reg_a;
                  vreg33(31 downto 0) := vreg33(31 downto 0) or reg_val32;
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_n <= vreg33(31);
                  reg_a <= vreg33(7 downto 0);
                  reg_x <= vreg33(15 downto 8);
                  reg_y <= vreg33(23 downto 16);
                  reg_z <= vreg33(31 downto 24);
                when I_EOR =>
                  vreg33 := '0' & reg_z & reg_y & reg_x & reg_a;
                  vreg33(31 downto 0) := vreg33(31 downto 0) xor reg_val32;
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_n <= vreg33(31);
                  reg_a <= vreg33(7 downto 0);
                  reg_x <= vreg33(15 downto 8);
                  reg_y <= vreg33(23 downto 16);
                  reg_z <= vreg33(31 downto 24);
                when I_AND =>
                  vreg33 := '0' & reg_z & reg_y & reg_x & reg_a;
                  vreg33(31 downto 0) := vreg33(31 downto 0) and reg_val32;
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_n <= vreg33(31);
                  reg_a <= vreg33(7 downto 0);
                  reg_x <= vreg33(15 downto 8);
                  reg_y <= vreg33(23 downto 16);
                  reg_z <= vreg33(31 downto 24);
                when I_INC =>
                  vreg33 := '0' & reg_val32;
                  vreg33 := vreg33 + 1;
                  reg_val32 <= vreg33(31 downto 0);
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_n <= vreg33(31);
                  axyz_phase <= 0;
                  state <= StoreTarget32;
                when I_DEC =>
                  vreg33 := '0' & reg_val32;
                  vreg33 := vreg33 - 1;
                  reg_val32 <= vreg33(31 downto 0);
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_n <= vreg33(31);
                  axyz_phase <= 0;
                  state <= StoreTarget32;
                when I_ASL =>
                  vreg33 := '0' & reg_val32;
                  vreg33(32 downto 1) := vreg33(31 downto 0);
                  vreg33(0) := vreg33(32);
                  reg_val32 <= vreg33(31 downto 0);
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_n <= vreg33(31);
                  axyz_phase <= 0;
                  state <= StoreTarget32;
                when I_ROL =>
                  vreg33 := flag_c & reg_val32;
                  vreg33(32 downto 1) := vreg33(31 downto 0);
                  vreg33(0) := vreg33(32);
                  reg_val32 <= vreg33(31 downto 0);
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_n <= vreg33(31);
                  axyz_phase <= 0;
                  state <= StoreTarget32;
                when I_LSR =>
                  vreg33 := '0' & reg_val32;
                  vreg33(31 downto 0) := vreg33(32 downto 1);
                  vreg33(32) := vreg33(0);
                  reg_val32 <= vreg33(31 downto 0);
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_n <= vreg33(31);
                  axyz_phase <= 0;
                  state <= StoreTarget32;
                when I_ROR =>
                  vreg33 := flag_c & reg_val32;
                  vreg33(31 downto 0) := vreg33(32 downto 1);
                  vreg33(32) := vreg33(0);
                  reg_val32 <= vreg33(31 downto 0);
                  if vreg33(31 downto 0) = to_unsigned(0,32) then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  flag_n <= vreg33(31);
                  axyz_phase <= 0;
                  state <= StoreTarget32;
                when others =>
                  -- XXX: Don't lock CPU up if we get something odd here
                  report "monitor_instruction_strobe assert (unknown instruction in Execute32)";
                  monitor_instruction_strobe <= '1';
                  state <= normal_fetch_state;
              end case;
              if is_rmw = '0' then
                -- Go to next instruction by default
                if fast_fetch_state = InstructionDecode then
                  pc_inc := reg_microcode.mcIncPC;
                else
                  report "not setting pc_inc, because fast_fetch_state /= InstructionDecode";
                  pc_inc := '0';
                end if;
                pc_dec := reg_microcode.mcDecPC;
                report "monitor_instruction_strobe assert (Execute32 non-RMW)";
                monitor_instruction_strobe <= '1';
                if reg_microcode.mcInstructionFetch='1' then
                  report "Fast dispatch for next instruction by order of microcode";
                  state <= fast_fetch_state;
                else
                  state <= normal_fetch_state;
                end if;
              end if;
            when StoreTarget32 =>
              if axyz_phase /= 4 then
                reg_val32(23 downto 0) <= reg_val32(31 downto 8);
                axyz_phase <= axyz_phase + 1;
              end if;              
              if axyz_phase = 4 then
                -- Go to next instruction by default
                if fast_fetch_state = InstructionDecode then
                  pc_inc := reg_microcode.mcIncPC;
                else
                  report "not setting pc_inc, because fast_fetch_state /= InstructionDecode";
                  pc_inc := '0';
                end if;
                pc_dec := reg_microcode.mcDecPC;
                report "monitor_instruction_strobe assert (StoreTarget32)";
                monitor_instruction_strobe <= '1';
                if reg_microcode.mcInstructionFetch='1' then
                  report "Fast dispatch for next instruction by order of microcode";
                  state <= fast_fetch_state;
                else
                  state <= normal_fetch_state;
                end if;
              end if;
            when MicrocodeInterpret =>
                                        -- By this stage we have the address of the operand in
                                        -- reg_addr, and if it is a load instruction then the contents
                                        -- will be in memory_read_value
                                        -- Branches (except JMP) have been taken care of elsewhere, as
                                        -- have a lot of the other fancy instructions.  That just leaves
                                        -- us with loads, stores and reaad/modify/write instructions

                                        -- Go to next instruction by default
              if next_is_axyz32_instruction = '1' and reg_instruction = I_STA then
                -- 32-bit store begins here, and the other 3 bytes get written
                -- in common with the 32-bit RMW instructions
                axyz_phase <= 1;
                reg_val32(23 downto 0) <= reg_val32(31 downto 8);
                state <= StoreTarget32;
              else
                if fast_fetch_state = InstructionDecode then
                  pc_inc := reg_microcode.mcIncPC;
                else
                  report "not setting pc_inc, because fast_fetch_state /= InstructionDecode";
                  pc_inc := '0';
                end if;
                pc_dec := reg_microcode.mcDecPC;
                if reg_microcode.mcInstructionFetch='1' then
                  report "monitor_instruction_strobe assert (MicrocodeInterpret mcInstructionFetch=1)";
                  monitor_instruction_strobe <= '1';
                  report "Fast dispatch for next instruction by order of microcode";
                  state <= fast_fetch_state;
                else
                                        -- (this gets overriden below for RMW and other instruction types)
                  state <= normal_fetch_state;
                end if;
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
                  flag_z <= '1';
                else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcINC='1' then
                temp_value := memory_read_value + 1;
                reg_t <= temp_value;                
                flag_n <= temp_value(7);
                if memory_read_value = x"ff" then
                  flag_z <= '1';
                else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcASR='1' then
                temp_value := memory_read_value(7)&memory_read_value(7 downto 1);
                reg_t <= temp_value;
                flag_c <= memory_read_value(0);
                flag_n <= temp_value(7);
                if temp_value = x"00" then
                  flag_z <= '1';
                else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcLSR='1' then
                temp_value := '0'&memory_read_value(7 downto 1);
                reg_t <= temp_value;
                flag_c <= memory_read_value(0);
                flag_n <= temp_value(7);
                if temp_value = x"00" then
                  flag_z <= '1';
                else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcROR='1' then
                temp_value := flag_c&memory_read_value(7 downto 1);
                reg_t <= temp_value;
                flag_c <= memory_read_value(0);
                flag_n <= temp_value(7);
                if temp_value = x"00" then
                  flag_z <= '1';
                else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcASL='1' then
                temp_value := memory_read_value(6 downto 0)&'0';
                reg_t <= temp_value;
                flag_c <= memory_read_value(7);
                flag_n <= temp_value(7);
                if temp_value = x"00" then
                  flag_z <= '1';
                else flag_z <= '0';
                end if;
              end if;
              if reg_microcode.mcROL='1' then
                temp_value := memory_read_value(6 downto 0)&flag_c;
                reg_t <= temp_value;
                flag_c <= memory_read_value(7);
                flag_n <= temp_value(7);
                if temp_value = x"00" then
                  flag_z <= '1';
                else
                  flag_z <= '0';
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
              
              if reg_microcode.mcClearE='1' then
                flag_e <= '0';
                report "ZPCACHE: Flushing cache due to clearing E flag";
                cache_flushing <= '1';
                cache_flush_counter <= (others => '0');
              end if;
              if reg_microcode.mcClearI='1' then flag_i <= '0'; end if;
              if reg_microcode.mcMap='1' then c65_map_instruction; end if;

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
                state <= WordOpReadHigh;
              end if;
              if (reg_microcode.mcWordOp or reg_microcode.mcDelayedWrite or
                  reg_microcode.mcPop or reg_microcode.mcBRK) = '0' then
                report "monitor_instruction_strobe assert (MicrocodeInterpret -- no special)";
                monitor_instruction_strobe <= '1';
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
                  report "monitor_instruction_strobe assert (invalid WordOp instruction)";
                  monitor_instruction_strobe <= '1';
                  state <= normal_fetch_state;
              end case;
            when PushWordLow =>
                                        -- Push reg_t
              stack_push := '1';
              state <= PushWordHigh;
            when PushWordHigh =>
                                        -- Push reg_t_high
              stack_push := '1';
              report "monitor_instruction_strobe assert (PushWordHigh)";
              monitor_instruction_strobe <= '1';
              state <= normal_fetch_state;
            when WordOpWriteLow =>
              reg_addr <= reg_addr + 1;
              state <= WordOpWriteHigh;
            when WordOpWriteHigh =>
              report "monitor_instruction_strobe assert (WordOpWriteHigh)";
              monitor_instruction_strobe <= '1';
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
              report "monitor_instruction_strobe assert (Pop)";
              monitor_instruction_strobe <= '1';
              state <= normal_fetch_state;
            when others =>
              report "monitor_instruction_strobe assert (unknown CPU state)";
              monitor_instruction_strobe <= '1';
              state <= normal_fetch_state;
          end case;

          -- Temporarily pick up memory access signals from combinatorial code
          memory_access_address :=  memory_access_address_next;
          memory_access_read := memory_access_read_next;
          memory_access_write := memory_access_write_next;
          memory_access_resolve_address := memory_access_resolve_address_next;
          memory_access_wdata := memory_access_wdata_next;

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
          reg_sp <= reg_sp - 1;
          if flag_e='0' and reg_sp=x"00" then
            reg_sph <= reg_sph - 1;
          end if;
        end if;
        if stack_pop='1' then
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

                                        -- XXX - Try to fast-route low address lines to shadowram and other memory
                                        -- blocks.
        
                                        -- Mark pages dirty as necessary        
        if memory_access_write='1' then

          -- Mark pages dirty as necessary        
          if(reg_pages_dirty_next(0) = '1') then
            reg_pages_dirty(0) <= '1';
          end if;
          if(reg_pages_dirty_next(1) = '1') then
            reg_pages_dirty(1) <= '1';
          end if;
          if(reg_pages_dirty_next(2) = '1') then
            reg_pages_dirty(2) <= '1';
          end if;
          if(reg_pages_dirty_next(3) = '1') then
            reg_pages_dirty(3) <= '1';
          end if;

                                        -- Get the shadow RAM or ROM address on the bus fast to improve timing.
          shadow_write <= '0';
          shadow_write_flags(1) <= '1';
          
          if memory_access_address = x"FFD3700"
            or memory_access_address = x"FFD1700" then
            report "DMAgic: DMA pending";
            dma_pending <= '1';
            state <= DMAgicTrigger;

                                        -- Normal DMA, use pre-set F018A/B mode
            job_is_f018b <= support_f018b;
            job_uses_options <= '0';

            phi_add_backlog <= '1'; phi_new_backlog <= 1;
            
                                        -- Don't increment PC if we were otherwise going to shortcut to
                                        -- InstructionDecode next cycle
            report "Setting PC to self (DMAgic entry)";
            reg_pc <= reg_pc;
          end if;
          if memory_access_address = x"FFD3705"
            or memory_access_address = x"FFD1705" then
            report "DMAgic: Enhanced DMA pending";
            dma_pending <= '1';
            state <= DMAgicTrigger;

                                        -- Normal DMA, use pre-set F018A/B mode
            job_is_f018b <= support_f018b;
            job_uses_options <= '1';

            phi_add_backlog <= '1'; phi_new_backlog <= 1;
            
                                        -- Don't increment PC if we were otherwise going to shortcut to
                                        -- InstructionDecode next cycle
            report "Setting PC to self (DMAgic entry)";
            reg_pc <= reg_pc;
          end if;

          -- @IO:GS $D640 CPU:HTRAP00 Writing triggers hypervisor trap \$00
          -- @IO:GS $D641 CPU:HTRAP01 Writing triggers hypervisor trap \$01
          -- @IO:GS $D642 CPU:HTRAP02 Writing triggers hypervisor trap \$02
          -- @IO:GS $D643 CPU:HTRAP03 Writing triggers hypervisor trap \$03
          -- @IO:GS $D644 CPU:HTRAP04 Writing triggers hypervisor trap \$04
          -- @IO:GS $D645 CPU:HTRAP05 Writing triggers hypervisor trap \$05
          -- @IO:GS $D646 CPU:HTRAP06 Writing triggers hypervisor trap \$06
          -- @IO:GS $D647 CPU:HTRAP07 Writing triggers hypervisor trap \$07
          -- @IO:GS $D648 CPU:HTRAP08 Writing triggers hypervisor trap \$08
          -- @IO:GS $D649 CPU:HTRAP09 Writing triggers hypervisor trap \$09
          -- @IO:GS $D64A CPU:HTRAP0A Writing triggers hypervisor trap \$0A
          -- @IO:GS $D64B CPU:HTRAP0B Writing triggers hypervisor trap \$0B
          -- @IO:GS $D64C CPU:HTRAP0C Writing triggers hypervisor trap \$0C
          -- @IO:GS $D64D CPU:HTRAP0D Writing triggers hypervisor trap \$0D
          -- @IO:GS $D64E CPU:HTRAP0E Writing triggers hypervisor trap \$0E
          -- @IO:GS $D64F CPU:HTRAP0F Writing triggers hypervisor trap \$0F

          -- @IO:GS $D650 CPU:HTRAP10 Writing triggers hypervisor trap \$10
          -- @IO:GS $D651 CPU:HTRAP11 Writing triggers hypervisor trap \$11
          -- @IO:GS $D652 CPU:HTRAP12 Writing triggers hypervisor trap \$12
          -- @IO:GS $D653 CPU:HTRAP13 Writing triggers hypervisor trap \$13
          -- @IO:GS $D654 CPU:HTRAP14 Writing triggers hypervisor trap \$14
          -- @IO:GS $D655 CPU:HTRAP15 Writing triggers hypervisor trap \$15
          -- @IO:GS $D656 CPU:HTRAP16 Writing triggers hypervisor trap \$16
          -- @IO:GS $D657 CPU:HTRAP17 Writing triggers hypervisor trap \$17
          -- @IO:GS $D658 CPU:HTRAP18 Writing triggers hypervisor trap \$18
          -- @IO:GS $D659 CPU:HTRAP19 Writing triggers hypervisor trap \$19
          -- @IO:GS $D65A CPU:HTRAP1A Writing triggers hypervisor trap \$1A
          -- @IO:GS $D65B CPU:HTRAP1B Writing triggers hypervisor trap \$1B
          -- @IO:GS $D65C CPU:HTRAP1C Writing triggers hypervisor trap \$1C
          -- @IO:GS $D65D CPU:HTRAP1D Writing triggers hypervisor trap \$1D
          -- @IO:GS $D65E CPU:HTRAP1E Writing triggers hypervisor trap \$1E
          -- @IO:GS $D65F CPU:HTRAP1F Writing triggers hypervisor trap \$1F

          -- @IO:GS $D660 CPU:HTRAP20 Writing triggers hypervisor trap \$20
          -- @IO:GS $D661 CPU:HTRAP21 Writing triggers hypervisor trap \$21
          -- @IO:GS $D662 CPU:HTRAP22 Writing triggers hypervisor trap \$22
          -- @IO:GS $D663 CPU:HTRAP23 Writing triggers hypervisor trap \$23
          -- @IO:GS $D664 CPU:HTRAP24 Writing triggers hypervisor trap \$24
          -- @IO:GS $D665 CPU:HTRAP25 Writing triggers hypervisor trap \$25
          -- @IO:GS $D666 CPU:HTRAP26 Writing triggers hypervisor trap \$26
          -- @IO:GS $D667 CPU:HTRAP27 Writing triggers hypervisor trap \$27
          -- @IO:GS $D668 CPU:HTRAP28 Writing triggers hypervisor trap \$28
          -- @IO:GS $D669 CPU:HTRAP29 Writing triggers hypervisor trap \$29
          -- @IO:GS $D66A CPU:HTRAP2A Writing triggers hypervisor trap \$2A
          -- @IO:GS $D66B CPU:HTRAP2B Writing triggers hypervisor trap \$2B
          -- @IO:GS $D66C CPU:HTRAP2C Writing triggers hypervisor trap \$2C
          -- @IO:GS $D66D CPU:HTRAP2D Writing triggers hypervisor trap \$2D
          -- @IO:GS $D66E CPU:HTRAP2E Writing triggers hypervisor trap \$2E
          -- @IO:GS $D66F CPU:HTRAP2F Writing triggers hypervisor trap \$2F

          -- @IO:GS $D670 CPU:HTRAP30 Writing triggers hypervisor trap \$30
          -- @IO:GS $D671 CPU:HTRAP31 Writing triggers hypervisor trap \$31
          -- @IO:GS $D672 CPU:HTRAP32 Writing triggers hypervisor trap \$32
          -- @IO:GS $D673 CPU:HTRAP33 Writing triggers hypervisor trap \$33
          -- @IO:GS $D674 CPU:HTRAP34 Writing triggers hypervisor trap \$34
          -- @IO:GS $D675 CPU:HTRAP35 Writing triggers hypervisor trap \$35
          -- @IO:GS $D676 CPU:HTRAP36 Writing triggers hypervisor trap \$36
          -- @IO:GS $D677 CPU:HTRAP37 Writing triggers hypervisor trap \$37
          -- @IO:GS $D678 CPU:HTRAP38 Writing triggers hypervisor trap \$38
          -- @IO:GS $D679 CPU:HTRAP39 Writing triggers hypervisor trap \$39
          -- @IO:GS $D67A CPU:HTRAP3A Writing triggers hypervisor trap \$3A
          -- @IO:GS $D67B CPU:HTRAP3B Writing triggers hypervisor trap \$3B
          -- @IO:GS $D67C CPU:HTRAP3C Writing triggers hypervisor trap \$3C
          -- @IO:GS $D67D CPU:HTRAP3D Writing triggers hypervisor trap \$3D
          -- @IO:GS $D67E CPU:HTRAP3E Writing triggers hypervisor trap \$3E
          -- @IO:GS $D67F CPU:HTRAP3F Writing triggers hypervisor trap \$3F
          
          -- @IO:GS $D67F HCPU:ENTEREXIT Writing trigger return from hypervisor
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
              report "           irq_pending = " & std_logic'image(irq_pending);
              report "           nmi_pending = " & std_logic'image(nmi_pending);
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
          read_long_address(memory_access_address);
        end if;
      end if; -- if not reseting
    end if;                         -- if rising edge of clock
  end process;
  
  -- output all monitor values based on current state, not one clock delayed.
  monitor_memory_access_address <= x"0"&memory_access_address_next;
  monitor_watch_match <= '0';       -- set if writing to watched address
  monitor_state <= to_unsigned(processor_state'pos(state),8)&read_data;
  monitor_hypervisor_mode <= hypervisor_mode;
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
  monitor_map_enables_low <= unsigned(reg_map_low); 
  monitor_map_enables_high <= unsigned(reg_map_high); 
  
  -- alternate (new) combinatorial core memory address generation.
  process (state,reg_pc,vector,reg_t,hypervisor_mode,monitor_mem_attention_request_drive,monitor_mem_address_drive,
           reg_dmagic_addr,mem_reading,flag_n,flag_v,flag_e,flag_d,flag_i,flag_z,flag_c,monitor_mem_write_drive,monitor_mem_wdata_drive,
           monitor_mem_read,monitor_mem_setpc,dmagic_src_addr,dmagic_dest_addr,viciii_iomode,reg_dmagic_transparent_value,
           reg_dmagic_use_transparent_value,reg_addressingmode,is_load,reg_pagenumber,reg_addr32save,reg_addr,reg_instruction,
           reg_sph,reg_pc_jsr,reg_b,absolute32_addressing_enabled,reg_microcode,reg_t_high,dmagic_dest_io,dmagic_src_io,
           dmagic_first_read,is_rmw,reg_arg1,reg_sp,reg_addr_msbs,reg_a,reg_x,reg_y,reg_z,reg_pageactive,shadow_rdata,proceed,
           reg_mult_a,read_data,shadow_wdata,shadow_address,hyppo_address,
           reg_pageid,rom_writeprotect,georam_page,
           hyppo_address_next,clock,fastio_rdata
           )
    variable memory_access_address : unsigned(27 downto 0) := x"FFFFFFF";
    variable memory_access_read : std_logic := '0';
    variable memory_access_write : std_logic := '0';
    variable memory_access_resolve_address : std_logic := '0';
    variable memory_access_wdata : unsigned(7 downto 0) := x"FF";
    
    variable shadow_address_var : integer range 0 to 1048575 := 0;
    variable shadow_write_var : std_logic := '0';
    variable shadow_read_var : std_logic := '0';
    variable shadow_wdata_var : unsigned(7 downto 0) := x"FF";

    variable hyppo_address_var : std_logic_vector(13 downto 0);
    variable fastio_addr_var : std_logic_vector(19 downto 0);

    variable long_address_read_var : unsigned(27 downto 0) := x"FFFFFFF";
    variable long_address_write_var : unsigned(27 downto 0) := x"FFFFFFF";

    variable temp_addr : unsigned(15 downto 0);    
    variable stack_pop : std_logic;
    variable stack_push : std_logic;
    variable virtual_reg_p : std_logic_vector(7 downto 0);
    variable reg_pages_dirty_var : std_logic_vector(3 downto 0)  := (others => '0');
    
    -- temp hack as I work to move this code around...
    variable real_long_address : unsigned(27 downto 0);
    variable long_address : unsigned(27 downto 0);
    
    -- purpose: Convert a 16-bit C64 address to native RAM (or I/O or ROM) address
    impure function resolve_address_to_long(short_address : unsigned(15 downto 0);
                                            writeP : boolean)
      return unsigned is 
      variable temp_address : unsigned(27 downto 0);
      variable blocknum : integer;
      variable lhc : std_logic_vector(4 downto 0);
      variable char_access_addr : unsigned(15 downto 0);
      
    begin  -- resolve_long_address

      -- Now apply C64-style $01 lines first, because MAP and $D030 take precedence
      blocknum := to_integer(short_address(15 downto 12));

      lhc(4) := gated_exrom;
      lhc(3) := gated_game;
      lhc(2 downto 0) := std_logic_vector(cpuport_value(2 downto 0));
      lhc(2) := lhc(2) or (not cpuport_ddr(2));
      lhc(1) := lhc(1) or (not cpuport_ddr(1));
      lhc(0) := lhc(0) or (not cpuport_ddr(0));
      
      if(writeP) then
        char_access_addr := x"000D";
      else
        char_access_addr := x"002D";
      end if;
      
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
        -- IO is always visible in ultimax mode
        if gated_exrom/='1' or gated_game/='0' or hypervisor_mode='1' then
          case lhc(2 downto 0) is
            when "000" => temp_address(27 downto 12) := x"000D";  -- WRITE RAM
            when "001" => temp_address(27 downto 12) := char_access_addr;  -- WRITE RAM / READ CHARROM
            when "010" => temp_address(27 downto 12) := char_access_addr;  -- WRITE RAM / READ CHARROM
            when "011" => temp_address(27 downto 12) := char_access_addr;  -- WRITE RAM / READ CHARROM
            when "100" => temp_address(27 downto 12) := x"000D";  -- WRITE RAM
            when others =>
              -- All else accesses IO
              -- C64/C65/C65GS I/O is based on which secret knock has been applied
              -- to $D02F
              temp_address(27 downto 12) := x"FFD3";
              if hypervisor_mode='0' then
                temp_address(13 downto 12) := unsigned(viciii_iomode);
              else
                temp_address(13 downto 12) := "11";
              end if;
              -- Optionally map SIDs to expansion port
              if (short_address(11 downto 8) = x"4") and hyper_iomode(2)='1' then
                temp_address(27 downto 12) := x"7FFD";
              end if;
              if sector_buffer_mapped='0' and colourram_at_dc00='0' then
                -- Map $DE00-$DFFF IO expansion areas to expansion port
                -- (but only if SD card sector buffer is not mapped, and
                -- 2nd KB of colour RAM is not mapped).
                if (short_address(11 downto 8) = x"E")
                  or (short_address(11 downto 8) = x"F") then
                  temp_address(27 downto 12) := x"7FFD";
                end if;
              end if;
          end case;
        else
          temp_address(27 downto 12) := x"FFD3";
          if hypervisor_mode='0' then
            temp_address(13 downto 12) := unsigned(viciii_iomode);
          else
            temp_address(13 downto 12) := "11";
          end if;
          if sector_buffer_mapped='0' and colourram_at_dc00='0' then
            -- Map $DE00-$DFFF IO expansion areas to expansion port
            -- (but only if SD card sector buffer is not mapped, and
            -- 2nd KB of colour RAM is not mapped).
            if (short_address(11 downto 8) = x"E")
              or (short_address(11 downto 8) = x"F") then
              temp_address(27 downto 12) := x"7FFD";
            end if;
          end if;
        end if;
      end if;

      -- C64 KERNEL
      if reg_map_high(3)='0' then
        if ((blocknum=14) or (blocknum=15)) and ((gated_exrom='1') and (gated_game='0')) then
          -- ULTIMAX mode external ROM
          temp_address(27 downto 16) := x"7FF";
        else
          if (blocknum=14) and (lhc(1)='1') and (writeP=false) then
            temp_address(27 downto 12) := x"002E";
          end if;        
          if (blocknum=15) and (lhc(1)='1') and (writeP=false) then
            temp_address(27 downto 12) := x"002F";      
          end if;
        end if;        
      end if;      
      -- C64 BASIC or cartridge ROM LO
      if reg_map_high(0)='0' then
        if ((blocknum=8) or (blocknum=9)) and
          (
            (
              ((gated_exrom='1') and (gated_game='0'))
              or
              ((gated_exrom='0') and (lhc(1 downto 0)="11"))
              )
            and
            (writeP=false)
            )
        then
          -- ULTIMAX mode or cartridge external ROM
          temp_address(27 downto 16) := x"7FF";
        end if;
        if (blocknum=10) and (lhc(0)='1') and (lhc(1)='1') and (writeP=false) then
          
          temp_address(27 downto 12) := x"002A";
        end if;
        if (blocknum=11) and (lhc(0)='1') and (lhc(1)='1') and (writeP=false) then
          temp_address(27 downto 12) := x"002B";      
        end if;
      end if;
      if reg_map_high(1)='0' then
        if (((blocknum=10) or (blocknum=11)) -- $A000-$BFFF cartridge ROM
            and ((gated_exrom='0') and (gated_game='0'))) and (writeP=false)
        then
          -- ULTIMAX mode or cartridge external ROM
          temp_address(27 downto 16) := x"7FF";          
        end if;
      end if;

      -- Expose remaining address space to cartridge port in ultimax mode
      if (gated_exrom='1') and (gated_game='0') and (hypervisor_mode='0') then
        if (reg_map_low(0)='0') and  (blocknum=1) then
          -- $1000 - $1FFF Ultimax mode
          temp_address(27 downto 16) := x"7FF";
        end if;
        if (reg_map_low(1)='0') and (blocknum=2 ) then
          -- $2000 - $2FFF Ultimax mode
          -- XXX $3000-$3FFf is a copy of $F000-$FFFF from the cartridge so
          -- that the VIC-II can see it. On the M65, the Hypervisor has to copy
          -- it down. Not yet implemented, and won't be perfectly compatible.
          temp_address(27 downto 16) := x"7FF";
        end if;
        if (reg_map_low(2)='0') and ((blocknum=4) or (blocknum=5)) then
          -- $4000 - $5FFF Ultimax mode
          temp_address(27 downto 16) := x"7FF";
        end if;
        if (reg_map_low(3)='0') and ((blocknum=6) or (blocknum=7)) then
          -- $6000 - $7FFF Ultimax mode
          temp_address(27 downto 16) := x"7FF";
        end if;
        if (reg_map_high(2)='0') and (blocknum=12) then
          -- $C000 - $CFFF Ultimax mode
          temp_address(27 downto 16) := x"7FF";
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
      if hypervisor_mode = '0' then
        blocknum := to_integer(short_address(15 downto 12));
        if (blocknum=14 or blocknum=15) and (rom_at_e000='1')
          and (hypervisor_mode='0') then
          temp_address(27 downto 12) := x"003E";
          if blocknum=15 then temp_address(12):='1'; end if;
        end if;
        if (blocknum=12) and rom_at_c000='1' and (hypervisor_mode='0') then
          temp_address(27 downto 12) := x"002C";
        end if;
        if (blocknum=10 or blocknum=11) and (rom_at_a000='1')
          and (hypervisor_mode='0') then
          temp_address(27 downto 12) := x"003A";
          if blocknum=11 then temp_address(12):='1'; end if;
        end if;
        if (blocknum=9) and (rom_at_8000='1') and (hypervisor_mode='0') then
          temp_address(27 downto 12) := x"0039";
        end if;
        if (blocknum=8) and (rom_at_8000='1') and (hypervisor_mode='0') then
          temp_address(27 downto 12) := x"0038";
        end if;
      end if;

      -- C65 DAT
      report "C65 VIC-III DAT: Address before translation is $" & to_hstring(temp_address);
      if temp_address(27 downto 3) & "000" = x"FFD1040"
        or temp_address(27 downto 3) & "000" = x"FFD3040" then
        temp_address(27 downto 17) := (others => '0');
        temp_address(16) := temp_address(0); -- odd/even bitplane bank select
        -- Bit plane address
        -- (VIC-III tells us if it is an odd or even frame if using V400+INT bits)
        if dat_even='1' then
          temp_address(15 downto 13) :=
            dat_bitplane_addresses(to_integer(temp_address(2 downto 0)))(7 downto 5);
        else
          temp_address(15 downto 13) :=
            dat_bitplane_addresses(to_integer(temp_address(2 downto 0)))(3 downto 1);
        end if;
        -- Bitplane offset
        temp_address(12 downto 0) := dat_offset_drive(12 downto 0);
        report "C65 VIC-III DAT: Address translated to $" & to_hstring(temp_address);
      end if;
      
      return temp_address;
    end resolve_address_to_long;
    
  begin

    stack_pop := '0'; stack_push := '0';
    
    -- Generate virtual processor status register for convenience
    virtual_reg_p(7) := flag_n;
    virtual_reg_p(6) := flag_v;
    virtual_reg_p(5) := flag_e;
    virtual_reg_p(4) := '0';
    virtual_reg_p(3) := flag_d;
    virtual_reg_p(2) := flag_i;
    virtual_reg_p(1) := flag_z;
    virtual_reg_p(0) := flag_c;
    
    -- Don't do anything by default...
    memory_access_read := '0';
    memory_access_write := '0';
    memory_access_resolve_address := '0';

    -- By default, shadow/rom addresses hold previous values
    
    -- These always reset after each cycle though (no feedback loop)
    shadow_write_var := '0';
    shadow_read_var := '0';
    
    fastio_addr_var := fastio_addr;
    fastio_addr_next <= fastio_addr;
    
    -- By default these hold their old value while CPU is halted
    shadow_wdata_var := shadow_wdata;
    shadow_address_next <= shadow_address;
    shadow_wdata_next <= shadow_wdata;
    hyppo_address_next <= hyppo_address;

    shadow_address_var := shadow_address;

    long_address_write_var := x"FFFFFFF";
    long_address_read_var := x"FFFFFFF";

    hyppo_address_var := hyppo_address;

    memory_access_address := x"0000000";
    memory_access_wdata := x"00";

    reg_pages_dirty_var(0) := '0';
    reg_pages_dirty_var(1) := '0';
    reg_pages_dirty_var(2) := '0';
    reg_pages_dirty_var(3) := '0';

    if rising_edge(clock) then

      report "fastio_rdata = $" & to_hstring(fastio_rdata);
      
      reg_math_config_drive <= reg_math_config;
      
      -- We this awkward comparison because GHDL seems to think secure_mode_from_monitor='U'
      -- initially, even though it gets initialised to '0' explicitly
      if (hyper_protected_hardware(7)='1' and secure_mode_from_monitor='0')
        or (hyper_protected_hardware(7)='0' and secure_mode_from_monitor='1')
        or (ethernet_cpu_arrest='1')
      then
        -- Hold CPU completely paused if CPU and monitor disagree on whether we
        -- are in secure mode or not.  This is how the CPU is held when switching
        -- to and from secure mode.
        -- We use the same approach for also holding the CPU when dumping
        -- instruction stream in real-time via ethernet.
        report "SECUREMODE: Holding CPU paused because cpusecure=" & std_logic'image(hyper_protected_hardware(7))
          & ", but monitorsecure=" & std_logic'image(secure_mode_from_monitor);
        io_settle_delay <= '1';
        -- Stop any active memory writes, so that we don't, for example, keep
        -- writing to the $D02F key register if we happen to pausse on opening
        -- VIC-III/IV IO
        memory_access_write := '0';
        request_monitor_halt <= '0';
      elsif request_monitor_halt_trigger = '1' then
        request_monitor_halt <= '1';
        io_settle_delay <= '1';
        io_settle_counter <= x"ff";
      elsif io_settle_counter = x"00" then
        io_settle_delay <= '0';
        report "clearing io_settle_delay due to io_settle_counter=$00";
        -- Also clear any request for the monitor interface to halt the cpu due
        -- to a break point.
        request_monitor_halt <= '0';
      else
        report "decrementing io_settle_counter from $" & to_hstring(io_settle_counter);
        io_settle_counter <= io_settle_counter - 1;
        io_settle_delay <= '1';
      end if;
      if io_settle_trigger /= io_settle_trigger_last then
        io_settle_counter <= x"ff";
        io_settle_trigger_last <= io_settle_trigger;
        io_settle_delay <= '1';
      end if;
    end if;
    
    if proceed = '0' or phi_pause='1' then

      -- Do nothing while CPU is held
      memory_access_read := '0';
      memory_access_write := '0';
      memory_access_address := x"000"&reg_pc;
      memory_access_resolve_address := '1';

    else
      
      -- By default read next byte in instruction stream.
      memory_access_read := '1';
      memory_access_write := '0';
      memory_access_address := x"000"&reg_pc;
      memory_access_resolve_address := '1';

      fastio_addr_var := x"FFFFF";
      
      case state is
        when VectorRead =>
          if hypervisor_mode='1' then
            -- Vectors move in hypervisor mode to be inside the hypervisor
            -- ROM at $81Fx
            memory_access_address := x"FF801F"&vector;
          else
            memory_access_address := x"000FFF"&vector;
          end if;
        when Interrupt =>
          stack_push := '1';
          memory_access_wdata := reg_pc(15 downto 8);
        -- Interrupts take 7 cycles
        when InterruptPushPCL =>
          stack_push := '1';
          memory_access_wdata := reg_pc(7 downto 0);
        when InterruptPushP =>
          stack_push := '1';
          memory_access_wdata := reg_t;
        when RTI =>
          stack_pop := '1';
        when RTI2 =>
          stack_pop := '1';
        when RTS =>
          stack_pop := '1';
        when RTS1 =>
          stack_pop := '1';
        when RTS3 =>
          -- Read the instruction byte following
          memory_access_address := x"000"&reg_pc;
          memory_access_read := '1';
        when ProcessorHold =>
          -- Hold CPU while blocked by monitor

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
            elsif monitor_mem_read='1' then
              -- and optionally set PC
              if monitor_mem_setpc='0' then
                -- otherwise just read from memory
                memory_access_address := unsigned(monitor_mem_address_drive);
                memory_access_read := '1';
              end if;
            end if;
          else
            -- Don't do anything while the processor is held.
            memory_access_write := '0';
            memory_access_read := '0';
          end if;
        when DMAgicTrigger =>
          -- Begin to load DMA registers
          -- We load them from the 20 bit address stored $D700 - $D702
          -- plus the 8-bit MB value in $D704
          memory_access_address := reg_dmagic_addr;
          memory_access_resolve_address := '0';
          memory_access_read := '1';
        when DMAgicReadOptions =>
          memory_access_address := reg_dmagic_addr;
          memory_access_resolve_address := '0';
          memory_access_read := '1';
        when DMAgicReadList =>
          memory_access_address := reg_dmagic_addr;
          memory_access_resolve_address := '0';
          memory_access_read := '1';
        when DMAgicFill =>
          memory_access_write := '1';
          memory_access_wdata := dmagic_src_addr(15 downto 8);
          memory_access_resolve_address := '0';
          memory_access_address := dmagic_dest_addr(35 downto 8);

          -- redirect memory write to IO block if required
          if dmagic_dest_addr(23 downto 20) = x"d" and dmagic_dest_io='1' then
            memory_access_address(27 downto 16) := x"FFD";
            memory_access_address(15 downto 14) := "00";
            if hypervisor_mode='0' then
              memory_access_address(13 downto 12) := unsigned(viciii_iomode);
            else
              memory_access_address(13 downto 12) := "11";
            end if;
          end if;
          
        when DMAgicCopyRead =>
          -- Do memory read
          memory_access_read := '1';
          memory_access_resolve_address := '0';
          memory_access_address := dmagic_src_addr(35 downto 8);

          -- redirect memory write to IO block if required
          if dmagic_src_addr(23 downto 20) = x"d" and dmagic_src_io='1' then
            memory_access_address(27 downto 16) := x"FFD";
            memory_access_address(15 downto 14) := "00";
            if hypervisor_mode='0' then
              memory_access_address(13 downto 12) := unsigned(viciii_iomode);
            else
              memory_access_address(13 downto 12) := "11";
            end if;
          end if;
          
        when DMAgicCopyWrite =>
          
          if dmagic_first_read = '0' then
            -- Do memory write
            if (reg_t /= reg_dmagic_transparent_value)
              or (reg_dmagic_use_transparent_value='0') then
              memory_access_write := '1';
            else
              memory_access_write := '0';
            end if;
            memory_access_wdata := reg_t;
            memory_access_resolve_address := '0';
            memory_access_address := dmagic_dest_addr(35 downto 8);

            -- redirect memory write to IO block if required
            if dmagic_dest_addr(15 downto 12) = x"d" and dmagic_dest_io='1' then
              memory_access_address(27 downto 16) := x"FFD";
              memory_access_address(15 downto 14) := "00";
              if hypervisor_mode='0' then
                memory_access_address(13 downto 12) := unsigned(viciii_iomode);
              else
                memory_access_address(13 downto 12) := "11";
              end if;
            end if;
          end if;
        when Cycle2 =>
          -- Fetch arg2 if required (only for 3 byte addressing modes)
          -- Also begin processing operations that don't need any more data
          -- to start, so that we don't waste a cycle on every 2-byte instruction.
          -- (We have this block last, so that it can override the destination
          -- state).
          case reg_addressingmode is
            when M_nn =>
              if is_load='1' or is_rmw='1' then
                -- On memory read wait-state, read from RAM, so that FastIO
                -- lines clear
                memory_access_read := '1';
                memory_access_address := x"0000002";
                memory_access_resolve_address := '0';
              end if;
            when M_nnX =>
              if is_load='1' or is_rmw='1' then
                -- On memory read wait-state, read from RAM, so that FastIO
                -- lines clear
                memory_access_read := '1';
                memory_access_address := x"0000002";
                memory_access_resolve_address := '0';
              end if;
            when M_nnY =>
              if is_load='1' or is_rmw='1' then
                -- On memory read wait-state, read from RAM, so that FastIO
                -- lines clear
                memory_access_read := '1';
                memory_access_address := x"0000002";
                memory_access_resolve_address := '0';
              end if;
            when others =>
              null;
          end case;              
          memory_access_wdata := reg_pagenumber(17 downto 10);
        when Flat32SaveAddress2 =>
          stack_push := '1';
          memory_access_wdata := reg_addr32save(23 downto 16);
        when Flat32SaveAddress3 =>
          stack_push := '1';
          memory_access_wdata := reg_addr32save(15 downto 8);
        when Flat32SaveAddress4 =>
          stack_push := '1';
          memory_access_wdata := reg_addr32save(7 downto 0);
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';                
        when Flat32Dereference1 =>
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';                
        when Flat32Dereference2 =>
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';                
        when Flat32Dereference3 =>
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';                
        when Flat32Dereference4 =>
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';                
        when Cycle3 =>

          if reg_instruction = I_RTS or reg_instruction = I_RTI then
            stack_pop := '1';
          else
            case reg_addressingmode is
              when M_impl =>  -- Handled in MicrocodeInterpret
              when M_A =>     -- Handled in MicrocodeInterpret
              when M_InnX =>                    
                temp_addr := reg_b & (reg_arg1+reg_X);
                memory_access_read := '1';
                memory_access_address := x"000"&temp_addr;
                memory_access_resolve_address := '1';
              when M_nn =>
                if is_load='1' or is_rmw='1' then
                  -- On memory read wait-state, read from RAM, so that FastIO
                  -- lines clear
                  memory_access_read := '1';
                  memory_access_address := x"0000002";
                  memory_access_resolve_address := '0';
                end if;
              when M_immnn => -- Handled in MicrocodeInterpret
              when M_nnnn =>
                -- If it is a branch, write the low bits of the programme
                -- counter now.  We will read the 2nd argument next cycle
                if reg_instruction = I_JSR or reg_instruction = I_BSR then
                  memory_access_read := '0';
                  memory_access_write := '1';
                  memory_access_address := x"000"&reg_sph&reg_sp;
                  memory_access_resolve_address := '1';
                  memory_access_wdata := reg_pc_jsr(15 downto 8);
                else
                  if is_load='1' or is_rmw='1' then
                    -- On memory read wait-state, read from RAM, so that FastIO
                    -- lines clear
                    memory_access_read := '1';
                    memory_access_address := x"0000002";
                    memory_access_resolve_address := '0';
                  end if;
                end if;
              when M_nnrr =>
                memory_access_read := '1';
                memory_access_address := x"000"&reg_b&reg_arg1;
                memory_access_resolve_address := '1';
              when M_InnY =>
                temp_addr := reg_b&reg_arg1;
                memory_access_read := '1';
                memory_access_address := x"000"&temp_addr;
                memory_access_resolve_address := '1';
              when M_InnZ =>
                temp_addr := reg_b&reg_arg1;
                memory_access_read := '1';
                memory_access_address := x"000"&temp_addr;
                memory_access_resolve_address := '1';
              when M_nnX =>
                temp_addr := reg_b & (reg_arg1 + reg_X);
                if is_load='1' or is_rmw='1' then
                  -- On memory read wait-state, read from RAM, so that FastIO
                  -- lines clear
                  memory_access_read := '1';
                  memory_access_address := x"0000002";
                  memory_access_resolve_address := '0';
                end if;
              when M_nnY =>
                temp_addr := reg_b & (reg_arg1 + reg_Y);
                if is_load='1' or is_rmw='1' then
                  -- On memory read wait-state, read from RAM, so that FastIO
                  -- lines clear
                  memory_access_read := '1';
                  memory_access_address := x"0000002";
                  memory_access_resolve_address := '0';
                end if;
              when M_nnnnY =>
                if is_load='1' or is_rmw='1' then
                  -- On memory read wait-state, read from RAM, so that FastIO
                  -- lines clear
                  memory_access_read := '1';
                  memory_access_address := x"0000002";
                  memory_access_resolve_address := '0';
                end if;
              when M_nnnnX =>
                if is_load='1' or is_rmw='1' then
                  -- On memory read wait-state, read from RAM, so that FastIO
                  -- lines clear
                  memory_access_read := '1';
                  memory_access_address := x"0000002";
                  memory_access_resolve_address := '0';
                end if;
              when M_InnSPY =>
                temp_addr :=  to_unsigned(to_integer(reg_b&reg_arg1)
                                          +to_integer(reg_sph&reg_sp),16);
                memory_access_read := '1';
                memory_access_address := x"000"&temp_addr;
                memory_access_resolve_address := '1';
              when others =>
                null;
            end case;
          end if;
        when CallSubroutine =>
          -- Push PCH
          memory_access_read := '0';
          memory_access_write := '1';
          memory_access_address := x"000"&reg_sph&reg_sp;
          memory_access_resolve_address := '1';
          memory_access_wdata := reg_pc_jsr(7 downto 0);
        when CallSubroutine2 =>
          -- Immediately start reading the next instruction
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';
        when InnXReadVectorLow =>
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';
        when InnXReadVectorHigh =>
          if is_load='1' or is_rmw='1' then
            -- On memory read wait-state, read from RAM, so that FastIO
            -- lines clear
            memory_access_read := '1';
            memory_access_address := x"0000002";
            memory_access_resolve_address := '0';
          end if;
        when InnSPYReadVectorLow =>
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';
        when InnSPYReadVectorHigh =>
          if is_load='1' or is_rmw='1' then
            -- On memory read wait-state, read from RAM, so that FastIO
            -- lines clear
            memory_access_read := '1';
            memory_access_address := x"0000002";
            memory_access_resolve_address := '0';
          end if;
        when InnYReadVectorLow =>
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';
        when InnYReadVectorHigh =>
          if is_load='1' or is_rmw='1' then
            -- On memory read wait-state, read from RAM, so that FastIO
            -- lines clear
            memory_access_read := '1';
            memory_access_address := x"0000002";
            memory_access_resolve_address := '0';
          end if;
        when InnZReadVectorLow =>
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';
        when InnZReadVectorByte2 =>
          -- Do addition of Z register as we go along, so that we don't have
          -- a 32-bit carry.
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';
        when InnZReadVectorByte3 =>
          -- Do addition of Z register as we go along, so that we don't have
          -- a 32-bit carry.
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';
        when InnZReadVectorByte4 =>
          if is_load='1' or is_rmw='1' then
            -- On memory read wait-state, read from RAM, so that FastIO
            -- lines clear
            memory_access_read := '1';
            memory_access_address := x"0000002";
            memory_access_resolve_address := '0';
          end if;
        when InnZReadVectorHigh =>
          if is_load='1' or is_rmw='1' then
            -- On memory read wait-state, read from RAM, so that FastIO
            -- lines clear
            memory_access_read := '1';
            memory_access_address := x"0000002";
            memory_access_resolve_address := '0';
          end if;
        when JumpDereference =>
          -- reg_addr holds the address we want to load a 16 bit address
          -- from for a JMP or JSR.
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';
        when JumpDereference2 =>
          memory_access_read := '1';
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';
        when JumpDereference3 =>
          if reg_instruction=I_JMP then
            null;
          else
            memory_access_read := '0';
            memory_access_write := '1';
            memory_access_address := x"000"&reg_sph&reg_sp;
            memory_access_resolve_address := '1';
            memory_access_wdata := reg_pc_jsr(15 downto 8);
          end if;        
        when DummyWrite =>
          memory_access_address := x"000"&reg_addr;
          memory_access_resolve_address := '1';
          memory_access_write := '1';
          memory_access_read := '0';
          memory_access_wdata := reg_t_high;
        when WriteCommit =>
          memory_access_write := '1';
          memory_access_address(15 downto 0) := reg_addr;
          memory_access_resolve_address := not absolute32_addressing_enabled;
          if absolute32_addressing_enabled='1' then
            memory_access_address(27 downto 16) := reg_addr_msbs(11 downto 0);
          else
            memory_access_address(27 downto 16) := x"000";
          end if;
          report "io_settle: reg_addr = $" & to_hstring(reg_addr(15 downto 2)&"00");
          memory_access_wdata := reg_t;
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
        when LoadTarget32 =>
          if axyz_phase /= 4 then
            -- More bytes to read, so schedule next byte to read                
            report "VAL32: memory_access_address=$" & to_hstring(memory_access_address);
            memory_access_read := '1';
            memory_access_address(15 downto 0) := to_unsigned(to_integer(reg_addr) + axyz_phase,16);
            memory_access_resolve_address := not absolute32_addressing_enabled;
            report "VAL32: memory_access_address=$" & to_hstring(memory_access_address);
          end if;
        when StoreTarget32 =>
          report "VAL32: StoreTarget32 memory_access_address=$" & to_hstring(memory_access_address) & ", reg_val32=$" & to_hstring(reg_val32);
          if axyz_phase /= 4 then
            memory_access_write := '1';
            memory_access_wdata := reg_val32(7 downto 0);
            memory_access_address(15 downto 0) := to_unsigned(to_integer(reg_addr) + axyz_phase,16);
            memory_access_resolve_address := not absolute32_addressing_enabled;
            report "VAL32: memory_access_address=$" & to_hstring(memory_access_address);
          end if;              
        when MicrocodeInterpret =>

          if reg_microcode.mcStoreA='1' then memory_access_wdata := reg_a; end if;
          if reg_microcode.mcStoreX='1' then memory_access_wdata := reg_x; end if;
          if reg_microcode.mcStoreY='1' then memory_access_wdata := reg_y; end if;
          if reg_microcode.mcStoreZ='1' then memory_access_wdata := reg_z; end if;              
          if reg_microcode.mcStoreP='1' then
            memory_access_wdata := unsigned(virtual_reg_p);
            memory_access_wdata(4) := '1';  -- B always set when pushed
            memory_access_wdata(5) := '1';  -- E always set when pushed
          end if;              
          if reg_microcode.mcWriteRegAddr='1' then
            memory_access_address := x"000"&reg_addr;
            memory_access_resolve_address := '1';
          end if;
          case reg_instruction is
            when I_PHA => stack_push := '1';
            when I_PHP => stack_push := '1';
            when I_PHX => stack_push := '1';
            when I_PHY => stack_push := '1';
            when I_PHZ => stack_push := '1';
            when others => stack_push := '0';
          end case;              
          stack_pop := reg_microcode.mcPop;
          if reg_microcode.mcWordOp='1' then
            memory_access_address := x"000"&(reg_addr+1);
            memory_access_resolve_address := '1';
            memory_access_read := '1';
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

            if reg_addr(15 downto 2)&"00" = x"DC00" then
              -- Writing to keyboard/joystick CIA data ports.
              -- When we are at 50MHz, the M65's keyboard virtualiser can take up
              -- to 16 cycles to update the view.  So whenever we do something
              -- that might change that view, we enforce a brief pause of the CPU.
              -- XXX Should no longer be necessary, now that we reconstruct and
              -- de-glitch the keyboard matrix in keymapper.vhdl
--              io_settle_trigger <= not io_settle_trigger;
              
            end if;
            
          end if;
        when PushWordLow =>
          stack_push := '1';
          memory_access_wdata := reg_t;
        when PushWordHigh =>
          stack_push := '1';
          memory_access_wdata := reg_t_high;
        when WordOpWriteLow =>
          memory_access_address := x"000"&(reg_addr);
          memory_access_resolve_address := '1';
          memory_access_write := '1';
          memory_access_wdata := reg_t;
        when WordOpWriteHigh =>
          memory_access_address := x"000"&(reg_addr);
          memory_access_resolve_address := '1';
          memory_access_write := '1';
          memory_access_wdata := reg_t_high;
        when others =>
          null;
      end case;            

      if stack_push='1' then
        memory_access_write := '1';
        memory_access_address := x"000"&reg_sph&reg_sp;
        memory_access_resolve_address := '1';      
      end if;

      if stack_pop='1' then
        memory_access_read := '1';
        if flag_e='0' then
          -- stack pointer can roam full 64KB
          memory_access_address := x"000"&((reg_sph&reg_sp)+1);
        else
          -- constrain stack pointer to single page if E flag is set
          memory_access_address := x"000"&reg_sph&(reg_sp+1);
        end if;
        memory_access_resolve_address := '1';
      end if;

      if (reg_pageactive = '1' ) then
        if (memory_access_address(15 downto 14) = "01") then
          case reg_pageid is
            when "00" => reg_pages_dirty_var(0) := '1'; 
            when "01" => reg_pages_dirty_var(1) := '1'; 
            when "10" => reg_pages_dirty_var(2) := '1'; 
            when "11" => reg_pages_dirty_var(3) := '1';
            when others => null;
          end case;
        end if;
      end if;

      --shadow_address_var := memory_access_address(long_address(16 downto 0));
      shadow_wdata_var := memory_access_wdata;

      if memory_access_write='1' then
        if memory_access_resolve_address = '1' then
          memory_access_address := resolve_address_to_long(memory_access_address(15 downto 0),true);
        end if;

        real_long_address := memory_access_address;

        -- Remap GeoRAM memory accesses
        if real_long_address(27 downto 16) = x"FFD"
          and real_long_address(11 downto 8)= x"E"
          and georam_blockmask /= x"00" then
          long_address := georam_page&real_long_address(7 downto 0);
        end if;

        if real_long_address = x"ffd0601" and vdc_reg_num = x"1f" then
          -- We map VDC RAM always to $40000
          -- So we re-map this write to $4xxxx
          long_address(27 downto 16) := x"004";
          long_address(15 downto 0) := vdc_mem_addr;
        end if;
        
        -- shadow_address_var := to_integer(long_address(16 downto 0));
        
        if
          -- FF80000-FF807FF = 2KB colour RAM at times, which overlaps chip RAM
          -- XXX - We don't handle the 2nd KB colour RAM at $DC00 when mapped
          (real_long_address(27 downto 12) = x"FF80" and real_long_address(11) = '0')
          or
          -- FFD[0-3]800-BFF
          (real_long_address(27 downto 16) = x"FFD"
           and real_long_address(15 downto 14) = "00"
           and real_long_address(11 downto 10) = "10")        
        then
          report "Writing to colour RAM";
          -- Write to shadow RAM
          -- shadow_write <= '0';

          -- Then remap to colour ram access: remap to $FF80000 - $FF807FF
          long_address := x"FF80"&'0'&real_long_address(10 downto 0);

        -- XXX What the heck is this remapping of $7F4xxxx -> colour RAM for?
        -- Is this for creating a linear memory map for quick task swapping, or
        -- something else? (PGS)
        elsif real_long_address(27 downto 16) = x"7F4" then
          long_address := x"FF80"&'0'&real_long_address(10 downto 0);
        else
          long_address := real_long_address;
        end if;
        
        long_address_write_var := long_address;
        
        if long_address(27 downto 17)="00000000001" then
          report "writing to ROM. addr=$" & to_hstring(long_address) severity note;
          shadow_write_var := not rom_writeprotect;
          shadow_address_var := to_integer(long_address(19 downto 0));
        elsif long_address(27 downto 20)=x"00" and ((not long_address(19)) or chipram_1mb)='1' then
          report "writing to shadow RAM via chipram shadowing. addr=$" & to_hstring(long_address) severity note;
          shadow_write_var := '1';
          shadow_address_var := to_integer(long_address(19 downto 0));

          -- C65 uses $1F800-FFF as colour RAM, so we need to write there, too,
          -- when writing here.
          if long_address(27 downto 12) = x"001F" and long_address(11) = '1' then
            report "writing to colour RAM via $001F8xx" severity note;

            -- And also to colour RAM
            fastio_addr_var(19 downto 16) := x"8";
            fastio_addr_var(15 downto 11) := (others => '0');
            fastio_addr_var(10 downto 0) := std_logic_vector(long_address(10 downto 0));
          end if;
        end if;
        
        if long_address(27 downto 24) = x"F" then --
          fastio_addr_var := std_logic_vector(long_address(19 downto 0));
        end if;
        
      elsif memory_access_read='1' then
        
        if memory_access_resolve_address = '1' then
          memory_access_address := resolve_address_to_long(memory_access_address(15 downto 0),false);
        end if;

        real_long_address := memory_access_address;
        
        -- Remap GeoRAM memory accesses
        if real_long_address(27 downto 16) = x"FFD"
          and real_long_address(11 downto 8) = x"E"
          and georam_blockmask /= x"00" then
          long_address := georam_page&real_long_address(7 downto 0);
        end if;

        if real_long_address = x"ffd0601" and vdc_reg_num = x"1f" then
          -- We map VDC RAM always to $40000
          -- So we re-map this write to $4xxxx
          long_address(27 downto 16) := x"004";
          long_address(15 downto 0) := vdc_mem_addr;          
        end if;
        
        if real_long_address(27 downto 12) = x"001F" and real_long_address(11)='1' then
          -- colour ram access: remap to $FF80000 - $FF807FF
          long_address := x"FF80"&'0'&real_long_address(10 downto 0);
        -- also remap to $7F40000 - $7F407FF
        elsif real_long_address(27 downto 16) = x"7F4" then
          long_address := x"FF80"&'0'&real_long_address(10 downto 0);
        else
          long_address := real_long_address;
        end if;
        
        long_address_read_var := long_address;
        
        if long_address(27 downto 20)=x"00" and ((not long_address(19)) or chipram_1mb)='1' then
          shadow_read_var := '1';
          shadow_address_var := to_integer(long_address(19 downto 0));
        end if;
        
        if long_address(19 downto 14)&"00" = x"F8" then
          hyppo_address_var := std_logic_vector(long_address(13 downto 0));
        end if;
        
        if long_address(27 downto 20) = x"FF" then
          fastio_addr_var := std_logic_vector(long_address(19 downto 0));
        end if;
        
      end if;

      if shadow_address_var >= chipram_size then
        shadow_address_var := 0;
        shadow_write_var := '0';
      end if;

      shadow_address_next <= shadow_address_var;
      hyppo_address_next <= hyppo_address_var;
      
    end if;

    fastio_addr_next <= fastio_addr_var;

    -- Assign outputs to signals that clocked side can see and use...
    memory_access_address_next <= memory_access_address;
    memory_access_read_next <= memory_access_read;
    memory_access_write_next <= memory_access_write;
    memory_access_resolve_address_next <= memory_access_resolve_address;
    memory_access_wdata_next <= memory_access_wdata;
    reg_pages_dirty_next <= reg_pages_dirty_var;
    
    shadow_write_next <= shadow_write_var;
    
    long_address_read <= long_address_read_var;
    long_address_write <= long_address_write_var;

    debug_read_dbg_out <= memory_access_read;
    debug_write_dbg_out <= memory_access_write;

    debug_wdata_dbg_out <= std_logic_vector(memory_access_wdata);
    debug_rdata_dbg_out <= std_logic_vector(read_data);

    debug_address_w_dbg_out <= std_logic_vector(to_unsigned(shadow_address,17));
    debug_address_r_dbg_out <= std_logic_vector(to_unsigned(shadow_address_next,17));
    debug4_state_out <= std_logic_vector(to_unsigned(memory_source'pos(read_source),4));
    
    proceed_dbg_out <= proceed;

    hyppo_address_out <= hyppo_address_next;
    fastio_addr_fast <= fastio_addr_next;
    
  end process;

  -- read_data input mux
  process (read_source, shadow_rdata, read_data_copy)
  begin
    if(read_source = Shadow) then
      read_data <= shadow_rdata;
    else
      read_data <= read_data_copy;
    end if;  
  end process;
  
end Behavioural;
