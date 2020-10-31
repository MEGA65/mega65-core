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
  -- *  This program   is free software; you can redistribute it and/or modify
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
      math_unit_enable : boolean   := false;
      chipram_1mb      : std_logic := '0';

      cpufrequency : integer         := 40;
      chipram_size : integer         := 393216;
      target       : mega65_target_t := mega65r2);
    port (
      mathclock : in  std_logic;
      Clock     : in  std_logic;
      phi_1mhz  : in  std_logic;
      phi_2mhz  : in  std_logic;
      phi_3mhz  : in  std_logic;
      reset     : in  std_logic;
      reset_out : out std_logic;
      irq       : in  std_logic;
      nmi       : in  std_logic;
      exrom     : in  std_logic;
      game      : in  std_logic;

      all_pause : in std_logic;

      hyper_trap            : in  std_logic;
      cpu_hypervisor_mode   : out std_logic := '0';
      privileged_access     : out std_logic := '0';
      matrix_trap_in        : in  std_logic;
      hyper_trap_f011_read  : in  std_logic;
      hyper_trap_f011_write : in  std_logic;
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

      iomode_set        : out std_logic_vector(1 downto 0) := "11";
      iomode_set_toggle : out std_logic                    := '0';

      dat_offset             : in unsigned(15 downto 0);
      dat_even               : in std_logic;
      dat_bitplane_addresses : in sprite_vector_eight;
      pixel_frame_toggle     : in std_logic;

      cpuis6502 : out std_logic            := '0';
      cpuspeed  : out unsigned(7 downto 0) := x"01";

      power_down : out std_logic := '1';

      irq_hypervisor : in std_logic_vector(2 downto 0) := "000"; -- JBM

      -- Asserted when CPU is in secure mode: Activates secure mode matrix mode interface
      secure_mode_out : out std_logic := '0';
      -- Input from uart monitor to indicate if we should be in secure or normal
      -- mode (CPU halts if in wrong mode, i.e., until monitor releases it to resume)
      secure_mode_from_monitor : in std_logic;
      -- This signal allows the monitor to cancel matrix mode after we ACCEPT or
      -- REJECT a secure session.
      clear_matrix_mode_toggle : in std_logic;

      matrix_rain_seed : out unsigned(15 downto 0) := (others => '0');

      cpu_pcm_left    : out signed(15 downto 0) := x"0000";
      cpu_pcm_right   : out signed(15 downto 0) := x"0000";
      cpu_pcm_enable  : out std_logic           := '0';
      cpu_pcm_bypass  : out std_logic           := '0';
      pwm_mode_select : out std_logic           := '1';

      -- Active low key that forces CPU to 40MHz
      fast_key : in std_logic;

      no_hyppo : in std_logic;

      reg_isr_out  : in unsigned(7 downto 0);
      imask_ta_out : in std_logic;

      monitor_char        : out unsigned(7 downto 0);
      monitor_char_toggle : out std_logic;
      monitor_char_busy   : in  std_logic;

      monitor_proceed               : out std_logic;
      monitor_waitstates            : out unsigned(7 downto 0);
      monitor_request_reflected     : out std_logic;
      monitor_hypervisor_mode       : out std_logic;
      monitor_instruction_strobe    : out std_logic := '0';
      monitor_pc                    : out unsigned(15 downto 0);
      monitor_state                 : out unsigned(15 downto 0);
      monitor_watch                 : in  unsigned(27 downto 0);
      monitor_watch_match           : out std_logic;
      monitor_instructionpc         : out unsigned(15 downto 0);
      monitor_ibytes                : out unsigned(23 downto 0);
      monitor_a                     : out unsigned(7 downto 0);
      monitor_b                     : out unsigned(7 downto 0);
      monitor_x                     : out unsigned(7 downto 0);
      monitor_y                     : out unsigned(7 downto 0);
      monitor_z                     : out unsigned(7 downto 0);
      monitor_sp                    : out unsigned(15 downto 0);
      monitor_p                     : out unsigned(7 downto 0);
      monitor_map_offset_low        : out unsigned(11 downto 0);
      monitor_map_offset_high       : out unsigned(11 downto 0);
      monitor_map_enables_low       : out unsigned(3 downto 0);
      monitor_map_enables_high      : out unsigned(3 downto 0);
      monitor_interrupt_inhibit     : out std_logic;
      monitor_memory_access_address : out unsigned(31 downto 0);
      monitor_cpuport               : out unsigned(2 downto 0);

      -- Used to pause CPU when ethernet dumping of instruction stream is active.
      ethernet_cpu_arrest : in std_logic;

      ---------------------------------------------------------------------------
      -- Memory access interface used by monitor
      ---------------------------------------------------------------------------
      monitor_mem_address           : in  unsigned(27 downto 0);
      monitor_mem_rdata             : out unsigned(7 downto 0);
      monitor_mem_wdata             : in  unsigned(7 downto 0);
      monitor_mem_read              : in  std_logic;
      monitor_mem_write             : in  std_logic;
      monitor_mem_setpc             : in  std_logic;
      monitor_mem_attention_request : in  std_logic;
      monitor_mem_attention_granted : out std_logic;
      monitor_irq_inhibit           : in  std_logic;
      monitor_mem_trace_mode        : in  std_logic;
      monitor_mem_stage_trace_mode  : in  std_logic;
      monitor_mem_trace_toggle      : in  std_logic;

      -- Debugging
      debug_address_w_dbg_out : out std_logic_vector(16 downto 0);
      debug_address_r_dbg_out : out std_logic_vector(16 downto 0);
      debug_rdata_dbg_out     : out std_logic_vector(7 downto 0);
      debug_wdata_dbg_out     : out std_logic_vector(7 downto 0);
      debug_write_dbg_out     : out std_logic;
      debug_read_dbg_out      : out std_logic;
      debug4_state_out        : out std_logic_vector(3 downto 0);

      proceed_dbg_out : out std_logic;

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
      vicii_2mhz        : in  std_logic;
      viciii_fast       : in  std_logic;
      viciv_fast        : in  std_logic;
      iec_bus_active    : in  std_logic;
      speed_gate        : in  std_logic;
      speed_gate_enable : out std_logic := '1';
      -- When badline_toggle toggles, we need to act as though 40-43 clock cycles
      -- are being stolen from us (we should vary this based on sprite activity,
      -- but this should be enough for fixing many programs).
      badline_toggle : in std_logic;

      sector_buffer_mapped : in std_logic;

      --------------------------------------------------------------------------
      -- Loop-backed fastio interface to CPU's memory mapped registers
      --------------------------------------------------------------------------
      fastio_addr : in unsigned(19 downto 0);
      fastio_read : in std_logic;
      fastio_write : in std_logic;
      fastio_wdata : in unsigned(7 downto 0);
      fastio_rdata : out unsigned(7 downto 0) := (others => 'Z');

      --------------------------------------------------------------------------
      -- Interface to memory
      --------------------------------------------------------------------------
      transaction_request_toggle : out std_logic := '0';
      transaction_complete_toggle : in std_logic;
      transaction_length : out integer range 0 to 6 := 0;
      transaction_address : out unsigned(27 downto 0) := to_unsigned(0,28);
      transaction_write : out std_logic := '0';
      transaction_wdata : out unsigned(31 downto 0) := (others => '0');
      transaction_rdata : in unsigned(47 downto 0);
      instruction_fetch_request_toggle : inout std_logic;
      instruction_fetch_address_in : out integer := 0;
      instruction_fetched_address_out : in integer;
      instruction_fetch_rdata : in unsigned(47 downto 0) := (others => '1');

      ---------------------------------------------------------------------------
      -- VIC-III memory banking control
      ---------------------------------------------------------------------------
      viciii_iomode : in std_logic_vector(1 downto 0);

      colourram_at_dc00 : in std_logic;
      rom_at_e000       : in std_logic;
      rom_at_c000       : in std_logic;
      rom_at_a000       : in std_logic;
      rom_at_8000       : in std_logic

    );
  end entity gs4510;

  architecture Behavioural of gs4510 is

    signal iec_bus_slowdown : std_logic                := '0';
    signal iec_bus_cooldown : integer range 0 to 65535 := 0;

    -- DMAgic settings
    signal support_f018b    : std_logic := '0';
    signal job_is_f018b     : std_logic := '0';
    signal job_uses_options : std_logic := '0';

    signal cpuspeed_internal : unsigned(7 downto 0) := (others => '0');
    signal cpuspeed_external : unsigned(7 downto 0) := (others => '0');

    signal reset_drive      : std_logic := '0';
    signal cartridge_enable : std_logic := '0';
    signal gated_exrom      : std_logic := '1';
    signal gated_game       : std_logic := '1';
    signal force_exrom      : std_logic := '1';
    signal force_game       : std_logic := '1';

    signal force_fast                 : std_logic := '0';
    signal speed_gate_enable_internal : std_logic := '1';
    signal speed_gate_drive           : std_logic := '1';

    signal last_badline_toggle : std_logic := '0';

    signal iomode_set_toggle_internal : std_logic := '0';
    signal rom_writeprotect           : std_logic := '0';

    signal virtualise_sd0 : std_logic := '0';
    signal virtualise_sd1 : std_logic := '0';

    signal d700_triggered : std_logic := '0';
    signal d705_triggered : std_logic := '0';

    signal dat_bitplane_addresses_drive : sprite_vector_eight := (
        others => to_unsigned(0,8));
    signal dat_offset_drive         : unsigned(15 downto 0) := to_unsigned(0,16);
    signal dat_even_drive           : std_logic             := '1';
    signal pixel_frame_toggle_drive : std_logic             := '0';
    signal last_pixel_frame_toggle  : std_logic             := '0';


    -- Instruction log
    signal last_instruction_pc : unsigned(15 downto 0) := x"FFFF";
    signal last_opcode         : unsigned(7 downto 0)  := (others => '0');
    signal last_byte2          : unsigned(7 downto 0)  := (others => '0');
    signal last_byte3          : unsigned(7 downto 0)  := (others => '0');
    signal last_bytecount      : integer range 0 to 3  := 3;
    signal last_action         : character             := ' ';
    signal last_address        : unsigned(27 downto 0) := (others => '0');
    signal last_value          : unsigned(7 downto 0)  := (others => '0');

    -- Shadow RAM control
    signal shadow_address      : integer range 0 to 1048575 := 0;
    signal debug_address_w_dbg : integer range 0 to 1048575 := 0;
    signal debug_address_r_dbg : integer range 0 to 1048575 := 0;
    signal shadow_address_next : integer range 0 to 1048575 := 0;

    signal shadow_rdata                : unsigned(7 downto 0) := (others => '0');
    signal shadow_wdata                : unsigned(7 downto 0) := (others => '0');
    signal shadow_wdata_next           : unsigned(7 downto 0) := (others => '0');
    signal shadow_write_count          : unsigned(7 downto 0) := (others => '0');
    signal shadow_no_write_count       : unsigned(7 downto 0) := (others => '0');
    signal shadow_try_write_count      : unsigned(7 downto 0) := x"00";
    signal shadow_observed_write_count : unsigned(7 downto 0) := x"00";
    signal shadow_write                : std_logic            := '0';
    signal shadow_write_next           : std_logic            := '0';

    signal hyppo_address      : std_logic_vector(13 downto 0) := std_logic_vector(to_unsigned(0,14));
    signal hyppo_address_next : std_logic_vector(13 downto 0) := std_logic_vector(to_unsigned(0,14));

    signal fastio_addr_next : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(0,20));

    signal read_data : unsigned(7 downto 0) := (others => '0');

    signal long_address_read  : unsigned(27 downto 0) := (others => '0');
    signal long_address_write : unsigned(27 downto 0) := (others => '0');

    -- Mixed digital audio channels for writing to $D6F8-B
    signal audio_dma_left           : signed(15 downto 0)   := to_signed(0,16);
    signal audio_dma_right          : signed(15 downto 0)   := to_signed(0,16);
    signal audio_dma_write_sequence : integer range 0 to 3  := 0;
    signal audio_dma_tick_counter   : unsigned(31 downto 0) := to_unsigned(0,32);
    signal audio_dma_write_counter  : unsigned(31 downto 0) := to_unsigned(0,32);
    signal audio_dma_enable         : std_logic             := '0';
    signal audio_dma_disable_writes : std_logic             := '1';
    signal audio_dma_write_blocked  : std_logic             := '1';

    type u24_0to3 is array (0 to 3) of unsigned(24 downto 0);
    type s24_0to3 is array (0 to 3) of signed(24 downto 0);
    type s23_0to3 is array (0 to 3) of signed(23 downto 0);
    type u23_0to3 is array (0 to 3) of unsigned(23 downto 0);
    type u15_0to3 is array (0 to 3) of unsigned(15 downto 0);
    type s15_0to3 is array (0 to 3) of signed(15 downto 0);
    type u7_0to3 is array (0 to 3) of unsigned(7 downto 0);
    type u1_0to3 is array (0 to 3) of unsigned(1 downto 0);
    type s7_0to31 is array (0 to 31) of signed(7 downto 0);
    signal sine_table : s7_0to31 := (
        signed(to_unsigned(128-128,8)),signed(to_unsigned(152-128,8)),
        signed(to_unsigned(176-128,8)),signed(to_unsigned(198-128,8)),
        signed(to_unsigned(217-128,8)),signed(to_unsigned(233-128,8)),
        signed(to_unsigned(245-128,8)),signed(to_unsigned(252-128,8)),
        signed(to_unsigned(255-128,8)),signed(to_unsigned(252-128,8)),
        signed(to_unsigned(245-128,8)),signed(to_unsigned(233-128,8)),
        signed(to_unsigned(217-128,8)),signed(to_unsigned(198-128,8)),
        signed(to_unsigned(176-128,8)),signed(to_unsigned(152-128,8)),
        signed(to_unsigned(128-128,8)),signed(to_unsigned(103+128,8)),
        signed(to_unsigned(79+128,8)),signed(to_unsigned(57+128,8)),
        signed(to_unsigned(38+128,8)),signed(to_unsigned(22+128,8)),
        signed(to_unsigned(10+128,8)),signed(to_unsigned(3+128,8)),
        signed(to_unsigned(1+128,8)),signed(to_unsigned(3+128,8)),
        signed(to_unsigned(10+128,8)),signed(to_unsigned(22+128,8)),
        signed(to_unsigned(38+128,8)),signed(to_unsigned(57+128,8)),
        signed(to_unsigned(79+128,8)),signed(to_unsigned(103+128,8))
    );

    signal audio_dma_base_addr    : u23_0to3                 := (others => x"050000"); -- to_unsigned(0,24));
    signal audio_dma_time_base    : u23_0to3                 := (others => to_unsigned(0,24));
    signal audio_dma_top_addr     : u15_0to3                 := (others => to_unsigned(0,16));
    signal audio_dma_volume       : u7_0to3                  := (others => to_unsigned(0,8));
    signal audio_dma_pan_volume   : u7_0to3                  := (others => to_unsigned(0,8));
    signal audio_dma_enables      : std_logic_vector(0 to 3) := (others => '0');
    signal audio_dma_repeat       : std_logic_vector(0 to 3) := (others => '0');
    signal audio_dma_stop         : std_logic_vector(0 to 3) := (others => '0');
    signal audio_dma_signed       : std_logic_vector(0 to 3) := (others => '0');
    signal audio_dma_sample_width : u1_0to3                  := (others => "00");
    signal audio_dma_sine_wave    : std_logic_vector(0 to 3) := (others => '0');

    signal audio_dma_pending                      : std_logic_vector(0 to 3) := (others => '0');
    signal audio_dma_pending_msb                  : std_logic_vector(0 to 3) := (others => '0');
    signal audio_dma_current_addr                 : u23_0to3                 := (others => x"050000"); -- to_unsigned(0,24));
    signal audio_dma_current_addr_set             : u23_0to3                 := (others => to_unsigned(0,24));
    signal audio_dma_current_addr_set_flag        : std_logic_vector(0 to 3) := (others => '0');
    signal audio_dma_last_current_addr_set_flag   : std_logic_vector(0 to 3) := (others => '0');
    signal audio_dma_timing_counter               : u24_0to3                 := (others => to_unsigned(0,25));
    signal audio_dma_timing_counter_set           : u24_0to3                 := (others => to_unsigned(0,25));
    signal audio_dma_timing_counter_set_flag      : std_logic_vector(0 to 3) := (others => '0');
    signal audio_dma_last_timing_counter_set_flag : std_logic_vector(0 to 3) := (others => '0');

    signal audio_dma_sample_valid      : std_logic_vector(0 to 3) := (others => '0');
    signal audio_dma_current_value     : s15_0to3                 := (others => to_signed(0,16));
    signal audio_dma_latched_sample    : s15_0to3                 := (others => to_signed(0,16));
    signal audio_dma_multed            : s23_0to3                 := (others => to_signed(0,24));
    signal audio_dma_pan_multed        : s23_0to3                 := (others => to_signed(0,24));
    signal audio_dma_wait_state        : std_logic                := '1';
    signal audio_dma_left_saturated    : std_logic                := '0';
    signal audio_dma_right_saturated   : std_logic                := '0';
    signal audio_dma_saturation_enable : std_logic                := '1';
    signal audio_dma_swap              : std_logic                := '0';

    signal pending_dma_busy                         : std_logic             := '0';
    signal pending_dma_address                      : unsigned(27 downto 0) := to_unsigned(2,28);
    -- 0 = no target set
    -- 1 = audio dma channel 0
    -- ...
    -- 4 = audio dma channel 3
    signal pending_dma_target       : integer range 0 to 4 := 0;

    signal cpu_pcm_bypass_int  : std_logic := '0';
    signal pwm_mode_select_int : std_logic := '0';


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
    signal georam_block     : unsigned(7 downto 0) := x"00";
    signal georam_blockpage : unsigned(7 downto 0) := x"00";

    -- REU emulation
    signal reu_reg_status             : unsigned(7 downto 0)         := x"00"; -- read only
    signal reu_cmd_autoload           : std_logic                    := '0';
    signal reu_cmd_ff00decode         : std_logic                    := '0';
    signal reu_cmd_operation          : std_logic_vector(1 downto 0) := "00";
    signal reu_c64_startaddr          : unsigned(15 downto 0)        := x"0000";
    signal reu_reu_startaddr          : unsigned(23 downto 0)        := x"000000";
    signal reu_transfer_length        : unsigned(15 downto 0)        := x"0000";
    signal reu_useless_interrupt_mask : unsigned(7 downto 5)         := "000";
    signal reu_hold_c64_address       : std_logic                    := '0';
    signal reu_hold_reu_address       : std_logic                    := '0';
    signal reu_ff00_pending           : std_logic                    := '0';

    signal last_fastio_addr   : std_logic_vector(19 downto 0) := (others => '0');
    signal last_write_address : unsigned(27 downto 0)         := (others => '0');
    signal shadow_write_flags : unsigned(3 downto 0)          := "0000";
    -- Registers to hold delayed write to hypervisor and related CPU registers
    -- to improve CPU timing closure.
    signal last_write_value   : unsigned(7 downto 0) := (others => '0');
    signal last_write_pending : std_logic            := '0';
    -- Flag used to ensure monitor serial character out busy flag gets asserted
    -- immediately on writing a character, without having to wait for the uart
    -- monitor to have a serial port tick (which is when it checks on that side)
    signal immediate_monitor_char_busy : std_logic := '0';

    signal last_clear_matrix_mode_toggle : std_logic := '0';

    signal phi_internal              : std_logic              := '0';
    signal phi_pause                 : std_logic              := '0';
    signal phi_backlog               : integer range 0 to 127 := 0;
    signal phi_add_backlog           : std_logic              := '0';
    signal charge_for_branches_taken : std_logic              := '1';
    signal phi_new_backlog           : integer range 0 to 127 := 0;
    signal last_phi16                : std_logic              := '0';
    signal last_phi_in               : std_logic              := '0';

    signal word_flag : std_logic := '0';

    -- DMAgic registers
    signal dmagic_list_counter              : integer range 0 to 12;
    signal dmagic_first_read                : std_logic             := '0';
    signal reg_dmagic_addr                  : unsigned(27 downto 0) := x"0000000";
    signal reg_dmagic_withio                : std_logic             := '0';
    signal reg_dmagic_status                : unsigned(7 downto 0)  := x"00";
    signal reg_dmacount                     : unsigned(7 downto 0)  := x"00"; -- number of DMA jobs done
    signal dma_pending                      : std_logic             := '0';
    signal dma_checksum                     : unsigned(23 downto 0) := x"000000";
    signal dmagic_cmd                       : unsigned(7 downto 0)  := (others => '0');
    signal dmagic_subcmd                    : unsigned(7 downto 0)  := (others => '0'); -- F018A/B extention
    signal dmagic_count                     : unsigned(15 downto 0) := (others => '0');
    signal dmagic_tally                     : unsigned(15 downto 0) := (others => '0');
    signal reg_dmagic_src_mb                : unsigned(7 downto 0)  := (others => '0');
    signal dmagic_src_addr                  : unsigned(35 downto 0) := (others => '0'); -- in 256ths of bytes
    signal reg_dmagic_use_transparent_value : std_logic             := '0';
    signal reg_dmagic_transparent_value     : unsigned(7 downto 0)  := x"00";
    signal reg_dmagic_x8_offset             : unsigned(15 downto 0) := x"0000";
    signal reg_dmagic_y8_offset             : unsigned(15 downto 0) := x"0000";
    signal reg_dmagic_slope                 : unsigned(15 downto 0) := x"0000";
    signal reg_dmagic_slope_fraction_start  : unsigned(16 downto 0) := to_unsigned(0,17);
    signal dmagic_slope_overflow_toggle     : std_logic             := '0';
    signal reg_dmagic_line_mode             : std_logic             := '0';
    signal reg_dmagic_line_x_or_y           : std_logic             := '0';
    signal reg_dmagic_line_slope_negative   : std_logic             := '0';
    signal dmagic_option_id                 : unsigned(7 downto 0)  := x"00";

    signal dmagic_src_io         : std_logic             := '0';
    signal dmagic_src_direction  : std_logic             := '0';
    signal dmagic_src_modulo     : std_logic             := '0';
    signal dmagic_src_hold       : std_logic             := '0';
    signal reg_dmagic_dst_mb     : unsigned(7 downto 0)  := (others => '0');
    signal dmagic_dest_addr      : unsigned(35 downto 0) := (others => '0'); -- in 256ths of bytes
    signal dmagic_dest_io        : std_logic             := '0';
    signal dmagic_dest_direction : std_logic             := '0';
    signal dmagic_dest_modulo    : std_logic             := '0';
    signal dmagic_dest_hold      : std_logic             := '0';
    signal dmagic_modulo         : unsigned(15 downto 0) := (others => '0');

    -- Allow source and destination address advance to range from 1/256th of a
    -- byte (i.e., 1 byte every 256 operations) through to 255 + 255/256ths per
    -- operation. This was added to accelerate texture copying for Doom-style 3D
    -- drawing.
    signal reg_dmagic_src_skip : unsigned(15 downto 0) := x"0100";
    signal reg_dmagic_dst_skip : unsigned(15 downto 0) := x"0100";

    -- Temporary registers used while loading DMA list
    signal dmagic_dest_bank_temp : unsigned(7 downto 0) := (others => '0');
    signal dmagic_src_bank_temp  : unsigned(7 downto 0) := (others => '0');
    -- Temporary store for CPU port bits to bank IO/ROMs in/out during DMA
    signal pre_dma_cpuport_bits : unsigned(2 downto 0) := (others => '1');

    -- CPU internal state
    signal flag_c : std_logic := '0'; -- carry flag
    signal flag_z : std_logic := '0'; -- zero flag
    signal flag_d : std_logic := '0'; -- decimal mode flag
    signal flag_n : std_logic := '0'; -- negative flag
    signal flag_v : std_logic := '0'; -- positive flag
    signal flag_i : std_logic := '0'; -- interrupt disable flag
    signal flag_e : std_logic := '0'; -- 8-bit stack flag

    signal reg_a   : unsigned(7 downto 0)  := (others => '0');
    signal reg_b   : unsigned(7 downto 0)  := (others => '0');
    signal reg_x   : unsigned(7 downto 0)  := (others => '0');
    signal reg_y   : unsigned(7 downto 0)  := (others => '0');
    signal reg_z   : unsigned(7 downto 0)  := (others => '0');
    signal reg_sp  : unsigned(7 downto 0)  := (others => '0');
    signal reg_sph : unsigned(7 downto 0)  := (others => '0');
    signal reg_pc  : unsigned(15 downto 0) := (others => '0');

    -- CPU RAM bank selection registers.
    -- Now C65 style, but extended by 8 bits to give 256MB address space
    signal reg_mb_low      : unsigned(7 downto 0)         := (others => '0');
    signal reg_mb_high     : unsigned(7 downto 0)         := (others => '0');
    signal reg_map_low     : std_logic_vector(3 downto 0) := (others => '0');
    signal reg_map_high    : std_logic_vector(3 downto 0) := (others => '0');
    signal reg_offset_low  : unsigned(11 downto 0)        := (others => '0');
    signal reg_offset_high : unsigned(11 downto 0)        := (others => '0');

    -- Are we in hypervisor mode?
    signal hypervisor_mode      : std_logic             := '1';
    signal hypervisor_trap_port : unsigned (6 downto 0) := (others => '0');
    -- Have we ever replaced the hypervisor with another?
    -- (used to allow once-only update of hypervisor by hick-up file)
    signal hypervisor_upgraded : std_logic := '0';

    -- Duplicates of all CPU registers to hold user-space contents when trapping
    -- to hypervisor.
    signal hyper_iomode             : unsigned(7 downto 0)         := (others => '0');
    signal hyper_dmagic_src_mb      : unsigned(7 downto 0)         := (others => '0');
    signal hyper_dmagic_dst_mb      : unsigned(7 downto 0)         := (others => '0');
    signal hyper_dmagic_list_addr   : unsigned(27 downto 0)        := (others => '0');
    signal hyper_p                  : unsigned(7 downto 0)         := (others => '0');
    signal hyper_a                  : unsigned(7 downto 0)         := (others => '0');
    signal hyper_b                  : unsigned(7 downto 0)         := (others => '0');
    signal hyper_x                  : unsigned(7 downto 0)         := (others => '0');
    signal hyper_y                  : unsigned(7 downto 0)         := (others => '0');
    signal hyper_z                  : unsigned(7 downto 0)         := (others => '0');
    signal hyper_sp                 : unsigned(7 downto 0)         := (others => '0');
    signal hyper_sph                : unsigned(7 downto 0)         := (others => '0');
    signal hyper_pc                 : unsigned(15 downto 0)        := (others => '0');
    signal hyper_mb_low             : unsigned(7 downto 0)         := (others => '0');
    signal hyper_mb_high            : unsigned(7 downto 0)         := (others => '0');
    signal hyper_port_00            : unsigned(7 downto 0)         := (others => '0');
    signal hyper_port_01            : unsigned(7 downto 0)         := (others => '0');
    signal hyper_map_low            : std_logic_vector(3 downto 0) := (others => '0');
    signal hyper_map_high           : std_logic_vector(3 downto 0) := (others => '0');
    signal hyper_map_offset_low     : unsigned(11 downto 0)        := (others => '0');
    signal hyper_map_offset_high    : unsigned(11 downto 0)        := (others => '0');
    signal hyper_protected_hardware : unsigned(7 downto 0)         := (others => '0');

    -- Page table for virtual memory
    signal reg_page0_logical    : unsigned(15 downto 0)        := (others => '0');
    signal reg_page0_physical   : unsigned(15 downto 0)        := (others => '0');
    signal reg_page1_logical    : unsigned(15 downto 0)        := (others => '0');
    signal reg_page1_physical   : unsigned(15 downto 0)        := (others => '0');
    signal reg_page2_logical    : unsigned(15 downto 0)        := (others => '0');
    signal reg_page2_physical   : unsigned(15 downto 0)        := (others => '0');
    signal reg_page3_logical    : unsigned(15 downto 0)        := (others => '0');
    signal reg_page3_physical   : unsigned(15 downto 0)        := (others => '0');
    signal reg_pagenumber       : unsigned(17 downto 0)        := (others => '0');
    signal reg_pages_dirty      : std_logic_vector(3 downto 0) := (others => '0');
    signal reg_pages_dirty_next : std_logic_vector(3 downto 0) := (others => '0');
    signal reg_pageid           : unsigned(1 downto 0)         := (others => '0');
    signal reg_pageactive       : std_logic                    := '0';


    -- Flags to detect interrupts
    signal map_interrupt_inhibit   : std_logic := '0';
    signal nmi_pending             : std_logic := '0';
    signal irq_pending             : std_logic := '0';
    signal nmi_state               : std_logic := '1';
    signal hyper_trap_last         : std_logic := '0';
    signal hyper_trap_edge         : std_logic := '0';
    signal hyper_trap_pending      : std_logic := '0';
    signal hyper_trap_state        : std_logic := '1';
    signal matrix_trap_pending     : std_logic := '0';
    signal f011_read_trap_pending  : std_logic := '0';
    signal f011_write_trap_pending : std_logic := '0';
    -- To defer interrupts in the hypervisor, we have a special mechanism for this.
    signal irq_defer_request : std_logic                := '0';
    signal irq_defer_counter : integer range 0 to 65535 := 0;
    signal irq_defer_active  : std_logic                := '0';

    -- Interrupt/reset vector being used
    signal vector : unsigned(3 downto 0) := (others => '0');

    -- Information about instruction currently being executed
    signal reg_opcode : unsigned(7 downto 0) := (others => '0');
    signal reg_arg1   : unsigned(7 downto 0) := (others => '0');
    signal reg_arg2   : unsigned(7 downto 0) := (others => '0');

    signal bbs_or_bbc : std_logic            := '0';
    signal bbs_bit    : unsigned(2 downto 0) := (others => '0');

    -- PC used for JSR is the value of reg_pc after reading only one of
    -- of the argument bytes.  We could subtract one, but it is less logic to
    -- just remember PC after reading one argument byte.
    signal reg_pc_jsr : unsigned(15 downto 0) := (others => '0');
    -- Temporary address register (used for indirect modes)
    signal reg_addr : unsigned(15 downto 0) := (others => '0');
    -- ... and this one for 32-bit flat addressing modes
    signal reg_addr32 : unsigned(31 downto 0) := (others => '0');
    -- ... and this one for pushing 32bit virtual address onto the stack
    signal reg_addr32save : unsigned(31 downto 0) := (others => '0');
    -- Upper and lower
    -- 16 bits of temporary address register. Used for 32-bit
    -- absolute addresses
    signal reg_addr_msbs : unsigned(15 downto 0) := (others => '0');
    signal reg_addr_lsbs : unsigned(15 downto 0) := (others => '0');
    -- Flag that indicates if a ($nn),Z access is using a 32-bit pointer
    signal zp32bit_pointer_enabled : std_logic := '0';
    -- Flag that indicates far JMP, JSR or RTS
    -- (set by two CLD's in a row before the instruction)
    signal flat32_addressmode       : std_logic := '0';
    signal flat32_enabled       : std_logic := '1';
    -- flag for progressive carry calculation when loading a 32-bit pointer
    signal pointer_carry : std_logic := '0';
    -- Temporary value holder (used for RMW instructions)
    signal reg_t      : unsigned(7 downto 0) := (others => '0');
    signal reg_t_high : unsigned(7 downto 0) := (others => '0');

    signal reg_val32                  : unsigned(31 downto 0) := to_unsigned(0,32);
    signal is_axyz32_instruction      : std_logic             := '0';
    signal value32_enabled            : std_logic             := '0';
    signal axyz_phase                 : integer range 0 to 4  := 0;

    signal instruction_phase : unsigned(3 downto 0) := (others => '0');

    signal ocean_cart_mode : std_logic := '0';
    -- Banks are 8KB each.  For efficiency the bank here must include
    -- the M65 RAM bank in bits 3-5.  Default is to present
    -- $40000 in lo, and $40000 in hi
    -- $40000 / $2000 = $20
    signal ocean_cart_lo_bank : unsigned(7 downto 0) := x"20";
    signal ocean_cart_hi_bank : unsigned(7 downto 0) := x"20";

    -- Indicate source of operand for instructions
    -- Note that ROM is actually implemented using
    -- power-on initialised RAM in the FPGA mapped via our io interface.
    signal accessing_shadow            : std_logic;
    signal accessing_rom               : std_logic;
    signal accessing_fastio            : std_logic;
    signal accessing_vic_fastio        : std_logic;
    signal accessing_hyppo_fastio      : std_logic;
    signal accessing_colour_ram_fastio : std_logic;
    --  signal accessing_ram : std_logic;
    signal accessing_slowram    : std_logic;
    signal accessing_cpuport    : std_logic;
    signal accessing_hypervisor : std_logic;
    signal cpuport_num          : unsigned(3 downto 0);
    signal hyperport_num        : unsigned(5 downto 0);
    signal cpuport_ddr          : unsigned(7 downto 0) := x"FF";
    signal cpuport_value        : unsigned(7 downto 0) := x"3F";
    signal the_read_address     : unsigned(27 downto 0);

    signal monitor_mem_trace_toggle_last : std_logic := '0';

    -- Microcode data and ALU routing signals follow:

    signal mem_reading   : std_logic := '0';
    signal pop_a         : std_logic := '0';
    signal pop_p         : std_logic := '0';
    signal pop_x         : std_logic := '0';
    signal pop_y         : std_logic := '0';
    signal pop_z         : std_logic := '0';
    signal mem_reading_p : std_logic := '0';
    -- serial monitor is reading data
    signal monitor_mem_reading : std_logic := '0';

    -- Is CPU free to proceed with processing an instruction?
    signal io_settle_delay        : std_logic            := '0';
    signal io_settle_counter      : unsigned(7 downto 0) := x"00";
    signal io_settle_trigger      : std_logic            := '0';
    signal io_settle_trigger_last : std_logic            := '0';

    signal read_data_copy : unsigned(7 downto 0) := x"00";

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
        DMAgicRegister,     -- 0x00
        HypervisorRegister, -- 0x01
        CPUPort,            -- 0x02
        MemController,      -- 0x03
        Unmapped            -- 0x0a
      );

    type processor_state is (
        -- Reset and interrupts
        ResetLow,
        ResetReady,
        Interrupt,InterruptPushPCL,InterruptPushP,
        VectorRead,
        VectorReadDone,

        -- Hypervisor traps
        TrapToHypervisor,ReturnFromHypervisor,

        -- DMAgic
        DMAgicTrigger,
        DMAgicReadOptions,DMAgicReadList,
        DMAgicGetReady,
        DMAgicFill,
        DMAgicCopyRead,DMAgicCopyWrite,

        -- Normal instructions
        InstructionWait,     -- Wait for PC to become available on       0x0f
                             -- interrupt/reset
        ProcessorHold,       -- 0x10
        MonitorMemoryAccess, -- 0x11
        InstructionFetch,    -- 0x12
        InstructionDecode4502,
        InstructionDecode6502,
        IndirectResolved,
        MicrocodeInterpret,

        Flat32RTS,
        Pull,
        RTI,RTI2,
        RTS,RTS1,
        B16TakeBranch,
        TakeBranch8,
        LoadTarget,
        WriteCommit,DummyWrite,

        -- VDC simulation block operations
        VDCRead,
        VDCWrite

      );
    signal state              : processor_state := ResetLow;
    signal fast_fetch_state   : processor_state := InstructionDecode4502;
    signal normal_fetch_state : processor_state := InstructionFetch;

    signal reg_microcode : microcodeops;

    constant mode_bytes_lut : mode_list := (
        M_impl    => 0,
        M_InnX    => 1,
        M_nn      => 1,
        M_immnn   => 1,
        M_A       => 0,
        M_nnnn    => 2,
        M_nnrr    => 2,
        M_rr      => 1,
        M_InnY    => 1,
        M_InnZ    => 1,
        M_rrrr    => 2,
        M_nnX     => 1,
        M_nnnnY   => 2,
        M_nnnnX   => 2,
        M_Innnn   => 2,
        M_InnnnX  => 2,
        M_InnSPY  => 1,
        M_nnY     => 1,
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
        I_NOP,I_STA,I_NOP,I_SAX,I_STY,I_STA,I_STX,I_SAX,I_DEY,I_NOP,I_TXA,I_ANE,I_STY,I_STA,I_STX,I_SAX,
        I_BCC,I_STA,I_KIL,I_SHA,I_STY,I_STA,I_STX,I_SAX,I_TYA,I_STA,I_TXS,I_TAS,I_SHY,I_STA,I_SHX,I_SHA,
        I_LDY,I_LDA,I_LDX,I_LAX,I_LDY,I_LDA,I_LDX,I_LAX,I_TAY,I_LDA,I_TAX,I_LAX,I_LDY,I_LDA,I_LDX,I_LAX,
        I_BCS,I_LDA,I_KIL,I_LAX,I_LDY,I_LDA,I_LDX,I_LAX,I_CLV,I_LDA,I_TSX,I_LAS,I_LDY,I_LDA,I_LDX,I_LAX,
        I_CPY,I_CMP,I_NOP,I_DCP,I_CPY,I_CMP,I_DEC,I_DCP,I_INY,I_CMP,I_DEX,I_SBX,I_CPY,I_CMP,I_DEC,I_DCP,
        I_BNE,I_CMP,I_KIL,I_DCP,I_NOP,I_CMP,I_DEC,I_DCP,I_CLD,I_CMP,I_NOP,I_DCP,I_NOP,I_CMP,I_DEC,I_DCP,
        I_CPX,I_SBC,I_NOP,I_ISC,I_CPX,I_SBC,I_INC,I_ISC,I_INX,I_SBC,I_NOP,I_SBC,I_CPX,I_SBC,I_INC,I_ISC,
        I_BEQ,I_SBC,I_KIL,I_ISC,I_NOP,I_SBC,I_INC,I_ISC,I_SED,I_SBC,I_NOP,I_ISC,I_NOP,I_SBC,I_INC,I_ISC
      );


    type mlut9bit is array(0 to 511) of addressingmode;
    constant mode_lut : mlut9bit := (
        -- 4502 personality first
        M_impl, M_InnX, M_impl, M_impl, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_A, M_impl, M_nnnn, M_nnnn, M_nnnn, M_nnrr,
        M_rr, M_InnY, M_InnZ, M_rrrr, M_nn, M_nnX, M_nnX, M_nn,
        M_impl, M_nnnnY, M_impl, M_impl, M_nnnn, M_nnnnX, M_nnnnX, M_nnrr,
        M_nnnn, M_InnX, M_Innnn, M_InnnnX,M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_A, M_impl, M_nnnn, M_nnnn, M_nnnn, M_nnrr,
        M_rr, M_InnY, M_InnZ, M_rrrr, M_nnX, M_nnX, M_nnX, M_nn,
        M_impl, M_nnnnY, M_impl, M_impl, M_nnnnX, M_nnnnX, M_nnnnX, M_nnrr,
        M_impl, M_InnX, M_impl, M_impl, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_A, M_impl, M_nnnn, M_nnnn, M_nnnn, M_nnrr,
        M_rr, M_InnY, M_InnZ, M_rrrr, M_nnX, M_nnX, M_nnX, M_nn,
        M_impl, M_nnnnY, M_impl, M_impl, M_impl, M_nnnnX, M_nnnnX, M_nnrr,
        -- $63 BSR $nnnn is 16-bit relative on the 4502.  We treat it as absolute
        -- mode, with microcode being used to select relative addressing.
        M_impl, M_InnX, M_immnn, M_nnnn, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_A, M_impl, M_Innnn, M_nnnn, M_nnnn, M_nnrr,
        M_rr, M_InnY, M_InnZ, M_rrrr, M_nnX, M_nnX, M_nnX, M_nn,
        M_impl, M_nnnnY, M_impl, M_impl, M_InnnnX,M_nnnnX, M_nnnnX, M_nnrr,
        M_rr, M_InnX, M_InnSPY,M_rrrr, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_nnnnX, M_nnnn, M_nnnn, M_nnnn, M_nnrr,
        M_rr, M_InnY, M_InnZ, M_rrrr, M_nnX, M_nnX, M_nnY, M_nn,
        M_impl, M_nnnnY, M_impl, M_nnnnY, M_nnnn, M_nnnnX, M_nnnnX, M_nnrr,
        M_immnn, M_InnX, M_immnn, M_immnn, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_nnnn, M_nnnn, M_nnnn, M_nnnn, M_nnrr,
        M_rr, M_InnY, M_InnZ, M_rrrr, M_nnX, M_nnX, M_nnY, M_nn,
        M_impl, M_nnnnY, M_impl, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnY, M_nnrr,
        M_immnn, M_InnX, M_immnn, M_nn, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_nnnn, M_nnnn, M_nnnn, M_nnnn, M_nnrr,
        M_rr, M_InnY, M_InnZ, M_rrrr, M_nn, M_nnX, M_nnX, M_nn,
        M_impl, M_nnnnY, M_impl, M_impl, M_nnnn, M_nnnnX, M_nnnnX, M_nnrr,
        M_immnn, M_InnX, M_InnSPY,M_nn, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_nnnn, M_nnnn, M_nnnn, M_nnnn, M_nnrr,
        M_rr, M_InnY, M_InnZ, M_rrrr, M_immnnnn,M_nnX, M_nnX, M_nn,
        M_impl, M_nnnnY, M_impl, M_impl, M_nnnn, M_nnnnX, M_nnnnX, M_nnrr,

        -- 6502 personality
        M_impl, M_InnX, M_impl, M_InnX, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_immnn, M_nnnn, M_nnnn, M_nnnn, M_nnnn,
        M_rr, M_InnY, M_impl, M_InnY, M_nnX, M_nnX, M_nnX, M_nnX,
        M_impl, M_nnnnY, M_impl, M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX,
        M_nnnn, M_InnX, M_impl, M_InnX, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_immnn, M_nnnn, M_nnnn, M_nnnn, M_nnnn,
        M_rr, M_InnY, M_impl, M_InnY, M_nnX, M_nnX, M_nnX, M_nnX,
        M_impl, M_nnnnY, M_impl, M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX,
        M_impl, M_InnX, M_impl, M_InnX, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_immnn, M_nnnn, M_nnnn, M_nnnn, M_nnnn,
        M_rr, M_InnY, M_impl, M_InnY, M_nnX, M_nnX, M_nnX, M_nnX,
        M_impl, M_nnnnY, M_impl, M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX,
        M_impl, M_InnX, M_impl, M_InnX, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_immnn, M_Innnn, M_nnnn, M_nnnn, M_nnnn,
        M_rr, M_InnY, M_impl, M_InnY, M_nnX, M_nnX, M_nnX, M_nnX,
        M_impl, M_nnnnY, M_impl, M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX,
        M_immnn, M_InnX, M_immnn, M_InnX, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_immnn, M_nnnn, M_nnnn, M_nnnn, M_nnnn,
        M_rr, M_InnY, M_impl, M_InnY, M_nnX, M_nnX, M_nnY, M_nnY,
        M_impl, M_nnnnY, M_impl, M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnY, M_nnnnY,
        M_immnn, M_InnX, M_immnn, M_InnX, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_immnn, M_nnnn, M_nnnn, M_nnnn, M_nnnn,
        M_rr, M_InnY, M_impl, M_InnY, M_nnX, M_nnX, M_nnY, M_nnY,
        M_impl, M_nnnnY, M_impl, M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnY, M_nnnnY,
        M_immnn, M_InnX, M_immnn, M_InnX, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_immnn, M_nnnn, M_nnnn, M_nnnn, M_nnnn,
        M_rr, M_InnY, M_impl, M_InnY, M_nnX, M_nnX, M_nnX, M_nnX,
        M_impl, M_nnnnY, M_impl, M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX,
        M_immnn, M_InnX, M_immnn, M_InnX, M_nn, M_nn, M_nn, M_nn,
        M_impl, M_immnn, M_impl, M_immnn, M_nnnn, M_nnnn, M_nnnn, M_nnnn,
        M_rr, M_InnY, M_impl, M_InnY, M_nnX, M_nnX, M_nnX, M_nnX,
        M_impl, M_nnnnY, M_impl, M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX);

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
    signal reg_instruction    : instruction;

    signal is_rmw               : std_logic;
    signal is_load              : std_logic;
    signal rmw_dummy_write_done : std_logic;

    signal monitor_mem_attention_request_drive : std_logic;
    signal monitor_mem_read_drive              : std_logic;
    signal monitor_mem_write_drive             : std_logic;
    signal monitor_mem_setpc_drive             : std_logic;
    signal monitor_mem_address_drive           : unsigned(27 downto 0);
    signal monitor_mem_wdata_drive             : unsigned(7 downto 0);

    signal debugging_single_stepping : std_logic            := '0';
    signal debug_count               : integer range 0 to 5 := 0;

    signal reg_bitmask : unsigned(7 downto 0);

    signal watchdog_reset     : std_logic := '0';
    signal watchdog_fed       : std_logic := '0';
    signal watchdog_countdown : integer range 0 to 65535;

    signal emu6502    : std_logic := '0';
    signal timing6502 : std_logic := '0';
    signal force_4502 : std_logic := '1';

    signal reg_mult_a : unsigned(31 downto 0) := (others => '0');
    signal reg_mult_b : unsigned(31 downto 0) := (others => '0');
    signal reg_mult_p : unsigned(63 downto 0) := (others => '0');

    signal monitor_char_toggle_internal           : std_logic := '1';
    signal monitor_mem_attention_granted_internal : std_logic := '0';

    -- ZP/stack cache
    signal cache_we            : std_logic := '0';
    signal cache_waddr         : unsigned(9 downto 0);
    signal cache_raddr         : unsigned(9 downto 0);
    signal cache_rdata         : unsigned(35 downto 0);
    signal cache_wdata         : unsigned(35 downto 0);
    signal cache_read_valid    : std_logic            := '0';
    signal cache_flushing      : std_logic            := '1';
    signal cache_flush_counter : unsigned(9 downto 0) := (others => '0');

    signal target_instruction_addr : integer;

    signal instruction_from_transaction : std_logic := '0';
    signal waiting_on_mem_controller : std_logic := '0';
    signal expected_transaction_complete_toggle : std_logic := '0';
    signal transaction_request_toggle_int : std_logic := '0';

    signal cycle_counter           : unsigned(15 downto 0) := (others => '0');
    signal cycles_per_frame        : unsigned(31 downto 0) := (others => '0');
    signal proceeds_per_frame      : unsigned(31 downto 0) := (others => '0');
    signal last_cycles_per_frame   : unsigned(31 downto 0) := (others => '0');
    signal last_proceeds_per_frame : unsigned(31 downto 0) := (others => '0');
    signal frame_counter           : unsigned(15 downto 0) := (others => '0');

    type microcode_lut_t is array (instruction)
      of microcodeops;
    signal microcode_lut : microcode_lut_t := (
        I_ADC => (mcADD => '1', mcALU_in_a => '1', mcALU_set_a => '1', mcRecordCarry => '1', mcAllowBCD => '1', mcRecordV => '1', others => '0'),
        I_AND => (mcAND => '1', mcALU_in_a => '1', mcALU_set_a => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        -- 6502 does shift left by addition
        I_ASL => (mcADD => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcRecordCarry => '1', mcZeroBit0 => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_ASR => (mcLSR => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcCarryFromBit0 => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        -- ASW is left-shift of 16-bit operand
        I_ASW => (mcADD => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcRecordCarry => '1', mcZeroBit0 => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_BIT => (mcAND => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_BRK => (mcBRK => '1', others => '0'),
        I_CMP => (mcADD => '1', mcInvertB => '1', mcALU_in_a => '1', mcAssumeCarrySet => '1', mcRecordCarry => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_CPX => (mcADD => '1', mcInvertB => '1', mcALU_in_x => '1', mcAssumeCarrySet => '1', mcRecordCarry => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_CPY => (mcADD => '1', mcInvertB => '1', mcALU_in_y => '1', mcAssumeCarrySet => '1', mcRecordCarry => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_CPZ => (mcADD => '1', mcInvertB => '1', mcALU_in_z => '1', mcAssumeCarrySet => '1', mcRecordCarry => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_DEC => (mcADD => '1', mcInvertB => '1', mcALU_b_1 => '1', mcALU_set_mem => '1', others => '0'),
        I_DEW => (mcADD => '1', mcInvertB => '1', mcALU_b_1 => '1', mcALU_set_mem => '1', others => '0'),
        I_EOR => (mcEOR => '1', mcALU_in_a => '1', mcALU_set_a => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_INC => (mcADD => '1', mcALU_b_1 => '1', mcALU_set_mem => '1', others => '0'),
        I_INW => (mcADD => '1', mcALU_b_1 => '1', mcALU_set_mem => '1', others => '0'),
        -- Only indirect JMP/JSR are handled by microcode
        -- (Direct addressing modes are handled as single-cycle instructions)
        I_JMP => (mcJump => '1', others => '0'),
        I_JSR => (mcJump => '1', others => '0'),
        I_LDA => (mcPassB => '1', mcALU_set_a => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_LDX => (mcPassB => '1', mcALU_set_x => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_LDY => (mcPassB => '1', mcALU_set_y => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_LDZ => (mcPassB => '1', mcALU_set_z => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_LSR => (mcLSR => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcZeroBit7 => '1', mcCarryFromBit0 => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_ORA => (mcORA => '1', mcALU_in_a => '1', mcALU_set_a => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_PHW => (mcPushW => '1', others => '0'),
        I_PLA => (mcPassB => '1', mcALU_set_a => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_PLP => (mcPassB => '1', mcALU_set_p => '1', others => '0'),
        I_PLX => (mcPassB => '1', mcALU_set_x => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_PLY => (mcPassB => '1', mcALU_set_y => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_PLZ => (mcPassB => '1', mcALU_set_z => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        -- RMB clears a specific bit. We implement this by having reg_bitmask set
        -- with the correct operand, after which we can just use AND.
        -- (SMB works with an inverted bitmask and OR.)
        I_RMB => (mcAND => '1', mcInvertA => '1', mcALU_in_bitmask => '1', mcALU_set_mem => '1', others => '0'),
        I_ROL => (mcADD => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcRecordCarry => '1', mcBit0FromCarry => '1', mcCarryFromBit7 => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_ROR => (mcLSR => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcRecordCarry => '1', mcBit7FromCarry => '1', mcCarryFromBit7 => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_ROW => (mcADD => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcRecordCarry => '1', mcBit0FromCarry => '1', mcCarryFromBit15 => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        I_SBC => (mcADD => '1', mcInvertB => '1', mcALU_in_a => '1', mcALU_set_a => '1', mcRecordCarry => '1', mcAllowBCD => '1', mcRecordV => '1', others => '0'),
        I_SMB => (mcORA => '1', mcALU_in_bitmask => '1', mcALU_set_mem => '1', others => '0'),
        I_STA => (mcALU_in_a => '1', mcALU_set_mem => '1', others => '0'),
        I_STX => (mcALU_in_x => '1', mcALU_set_mem => '1', others => '0'),
        I_STY => (mcALU_in_y => '1', mcALU_set_mem => '1', others => '0'),
        I_STZ => (mcALU_in_z => '1', mcALU_set_mem => '1', others => '0'),
        I_TRB => (mcInvertA => '1', mcAND => '1', mcTRBSetZ => '1', mcALU_in_a => '1', mcALU_set_mem => '1', others => '0'),
        I_TSB => (mcORA => '1', mcTRBSetZ => '1', mcALU_in_a => '1', mcALU_set_mem => '1', others => '0'),

        -- 6502 unintended instructions
        -- XXX These will not be 100% correct yet, as our ALU doesn't (yet) support
        -- all the vaguries of the 6502 ALU when multiple functions are selected
        -- at the same time

        -- Shift left, then OR accumulator with result of operation
        -- This one is a bit tricky, as we need to do the shift before the ORA.
        -- More the point, SLO puts the result of the SHIFT into memory, and the
        -- result of the ORA with that into A.
        I_SLO  => (mcORA => '1', mcALU_in_a => '1', mcALU_set_a => '1', mcRecordN => '1', mcRecordZ => '1',
        mcADD  => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcRecordCarry => '1',
        others => '0'),
        -- Rotate left, then AND accumulator with result of operation
        I_RLA => (mcADD => '1', mcAND => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcRecordCarry => '1', mcBit0FromCarry => '1', mcCarryFromBit7 => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        --    -- LSR, then EOR accumulator with result of operation
        I_SRE => (mcLSR => '1', mcEOR => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcZeroBit7 => '1', mcCarryFromBit0 => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        --    -- Rotate right, then ADC accumulator with result of operation
        I_RRA      => (mcADD => '1', mcLSR => '1', mcALU_in_mem => '1', mcALU_set_mem => '1', mcRecordCarry => '1', mcBit7FromCarry => '1', mcCarryFromBit7 => '1', mcRecordN => '1', mcRecordZ => '1',
                       mcALU_in_a => '1', others => '0'),
        --    -- Store AND of A and X: Doesn't touch any flags
        I_SAX => (mcStoreAX => '1', mcALU_set_mem => '1', others => '0'),
        --    -- Load A and X at the same time, one of the more useful results
        I_LAX => (mcPassB => '1', mcALU_set_a => '1', mcALU_set_x => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        -- Decrement, and then compare with accumulator
        -- DCP we can do, by doing a CMP without adding a fake carry bit, and then
        -- storing the result
        I_DCP         => (mcADD => '1', mcInvertB => '1', mcALU_b_1 => '1', mcALU_set_mem => '1',
                          mcALU_in_a => '1', mcAssumeCarryClear => '1',
                          mcRecordCarry => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        --    -- ISC, then subtract result from accumulator
        I_ISC => (mcADD => '1', mcAssumeCarrySet => '1', mcInvertB => '1', mcALU_in_a => '1', mcALU_set_a => '1', mcRecordCarry => '1', others => '0'),
        --    -- Like AND, but pushes bit7 into C.  Here we can simply enable both AND
        --    -- and ROL in the microcode, and everything will already work.
        -- XXX ANC is only available in immediate mode, and so should be a
        -- single-cycle instruction?
        --    I_ANC => (mcAND => '1', mcALU_in_a => '1', mcALU_set_a => '1', mcCarryFromBit7 => '1', mcRecordN => '1', mcRecordZ => '1', others => '0'),
        -- XXX ALR is only available in immediate mode, and so should be a
        -- single-cycle instruction?
        --    I_ALR => (mcAND => '1', mcLSR => '1',
        --              mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
        -- XXX ARR is only available in immediate mode, and so should be a
        -- single-cycle instruction?
        --    I_ARR => (mcROR => '1', mcDelayedWrite => '1', others => '0'),
        -- XXX ANE is unstable, and we cause a hypervisor trap when encountering it.
        --    I_ANE => (mcAND => '1',
        --              mcInstructionFetch => '1', mcIncPC => '1', others => '0'),
        -- SBX = CMP + DEX
        -- XXX Immediate mode only, so should be a single cycle instruction
        --    I_SBX => ( mcADD => '1', mcInvertB => '1', mcALU_in_a => '1', mcALU_in_x => '1', mcALU_set_x => '1',
        --              mcAssumeCarrySet => '1', mcRecordCarry => '1', mcRecordN => '1', mcRecordZ => '1',
        --              others => '0'),
        -- This one is quite hairy, as well as unrelabile.
        -- We just trigger a trap instead
        --    I_SHA => (mcStoreA => '1', mcWriteMem => '1', mcInstructionFetch => '1',
        --              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
        -- Same with these next three, also:
        --    I_SHY => (mcStoreY => '1', mcWriteMem => '1', mcInstructionFetch => '1',
        --              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
        --    I_SHX => (mcStoreX => '1', mcWriteMem => '1', mcInstructionFetch => '1',
        --              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
        --    I_TAS => (mcStoreA => '1', mcWriteMem => '1', mcInstructionFetch => '1',
        --              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
        -- Ok, this next one is quite weird, but also quite doable
        I_LAS        => (mcAND => '1', mcALU_set_a => '1', mcALU_set_x => '1', mcALU_set_spl => '1',
        mcALU_in_spl => '1', others => '0'),
        --    I_NOP => ( others=>'0'),
        -- I_KIL - XXX needs to be handled as Hypervisor trap elsewhere

        others => ( others => '0'));

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
      source_a    : integer range 0 to 15;
      source_b    : integer range 0 to 15;
      output      : integer range 0 to 15;
      output_low  : std_logic;
      output_high : std_logic;
      latched     : std_logic;
      do_add      : std_logic;
    end record;

    constant math_unit_config_v : math_unit_config :=
      ( source_a => 0, source_b => 0, output => 0,
        output_low => '0', output_high => '0',
        latched    => '0', do_add => '0');

    constant math_unit_count : integer := 16;
    type math_reg_array is array(0 to 15) of unsigned(31 downto 0);
    type math_config_array is array(0 to math_unit_count - 1) of math_unit_config;
    signal reg_math_regs           : math_reg_array       := (others => to_unsigned(0,32));
    signal reg_math_config         : math_config_array    := (others => math_unit_config_v);
    signal reg_math_config_drive   : math_config_array    := (others => math_unit_config_v);
    signal reg_math_latch_counter  : unsigned(7 downto 0) := x"00";
    signal reg_math_latch_interval : unsigned(7 downto 0) := x"00";

    -- We have the output counter out of phase with the input counter, so that we
    -- have time to catch an output, and store it, ready for presenting as an input
    -- very soon after.
    signal math_input_counter       : integer range 0 to 15 := 0;
    signal math_output_counter      : integer range 0 to 15 := 3;
    signal prev_math_output_counter : integer range 0 to 15 := 2;

    signal math_input_number      : integer range 0 to 15 := 0;
    signal math_input_value       : unsigned(31 downto 0) := (others => '0');
    signal math_output_value_low  : unsigned(31 downto 0) := (others => '0');
    signal math_output_value_high : unsigned(31 downto 0) := (others => '0');

    -- Start with input and outputting enabled
    signal math_unit_flags : unsigned(7 downto 0) := x"03";
    -- Each write to the math registers is passed to the math unit to handle
    -- (this is to avoid ISE doing really weird things in synthesis, thinking
    -- that each bit of each register was a clock or something similarly odd.)
    signal reg_math_write             : std_logic             := '0';
    signal reg_math_write_toggle      : std_logic             := '0';
    signal last_reg_math_write_toggle : std_logic             := '0';
    signal reg_math_regnum            : integer range 0 to 15 := 0;
    signal reg_math_regbyte           : integer range 0 to 3  := 0;
    signal reg_math_write_value       : unsigned(7 downto 0)  := x"00";
    -- Count # of math cycles since cycle latch last written to
    signal reg_math_cycle_counter          : unsigned(31 downto 0) := to_unsigned(0,32);
    signal reg_math_cycle_counter_plus_one : unsigned(31 downto 0) := to_unsigned(0,32);
    -- # of math cycles to trigger end of job / math interrupt
    signal reg_math_cycle_compare : unsigned(31 downto 0) := to_unsigned(0,32);

    signal badline_enable : std_logic := '1';
    -- XXX We make bad lines cost 43 cycles, even if there were write cycles in
    -- instructions.  Working out if there are write cycles to subtract is a bit
    -- tricky, but we should do it at some point.
    signal badline_extra_cycles : unsigned(1 downto 0) := "11";
    signal slow_interrupts      : std_logic            := '1';

    -- Simulated VDC access
    signal vdc_reg_num  : unsigned(7 downto 0)  := to_unsigned(0,8);
    signal vdc_mem_addr : unsigned(15 downto 0) := to_unsigned(0,16);
    -- fake VDC status register that claims "always ready"
    signal vdc_status       : unsigned(7 downto 0)  := x"80";
    signal vdc_mem_addr_src : unsigned(15 downto 0) := to_unsigned(0,16);
    signal vdc_word_count   : unsigned(7 downto 0)  := x"00";
    signal vdc_enabled      : std_logic             := '0';

    signal resolved_vdc_to_viciv_address     : unsigned(15 downto 0) := x"0000";
    signal resolved_vdc_to_viciv_src_address : unsigned(15 downto 0) := x"0000";

    signal div_n          : unsigned(31 downto 0);
    signal div_d          : unsigned(31 downto 0);
    signal div_q          : unsigned(63 downto 0);
    signal div_start_over : std_logic := '0';
    signal div_busy       : std_logic := '0';

    signal instruction_bytes : unsigned(47 downto 0) := (others => '0');
    signal is_store : std_logic := '0';
    signal is_16bit_operation : std_logic := '0';

    -- purpose: map VDC linear address to VICII bitmap addressing here
    -- to keep it as simple as possible we assume fix 640x200x2 resolution
    -- for the access
    -- (better would be to align the math here with the actual VICIV
    -- video mode setting, even the bank to be used could be dynamic)
    function resolve_vdc_to_viciv_address(vdc_address : unsigned(15 downto 0))
      return unsigned is

      variable line           : integer;
      variable col            : integer;
      variable viciv_line     : integer;
      variable viciv_line_off : integer;
    begin -- resolve_vdc_to_viciv_address

      line           := to_integer(vdc_address) / 80;
      col            := to_integer(vdc_address) mod 80;
      viciv_line     := line / 8;
      viciv_line_off := (viciv_line * 640) + (line mod 8) + (col * 8);

      return to_unsigned(viciv_line_off, 16);
    end resolve_vdc_to_viciv_address;

  begin

    monitor_cpuport <= cpuport_value(2 downto 0);

    fd0 : entity work.fast_divide
      port map (
        clock      => clock,
        n          => div_n,
        d          => div_d,
        q          => div_q,
        start_over => div_start_over,
        busy       => div_busy
      );


    multipliers : for unit in 0 to 7 generate
        mult_unit : entity work.multiply32 port map (
          clock                      => mathclock,
          unit                       => unit,
          do_add                     => reg_math_config_drive(unit).do_add,
          input_a                    => reg_math_config_drive(unit).source_a,
          input_b                    => reg_math_config_drive(unit).source_b,
          input_value_number         => math_input_number,
          input_value                => math_input_value,
          output_select              => math_output_counter,
          output_value(31 downto 0)  => math_output_value_low,
          output_value(63 downto 32) => math_output_value_high
        );
    end generate;

    shifters : for unit in 8 to 11 generate
        mult_unit : entity work.shifter32 port map (
          clock                      => mathclock,
          unit                       => unit,
          do_add                     => reg_math_config_drive(unit).do_add,
          input_a                    => reg_math_config_drive(unit).source_a,
          input_b                    => reg_math_config_drive(unit).source_b,
          input_value_number         => math_input_number,
          input_value                => math_input_value,
          output_select              => math_output_counter,
          output_value(31 downto 0)  => math_output_value_low,
          output_value(63 downto 32) => math_output_value_high
        );
    end generate;

    dividerrs : for unit in 12 to 15 generate
        mult_unit : entity work.divider32 port map (
          clock                      => mathclock,
          unit                       => unit,
          do_add                     => reg_math_config_drive(unit).do_add,
          input_a                    => reg_math_config_drive(unit).source_a,
          input_b                    => reg_math_config_drive(unit).source_b,
          input_value_number         => math_input_number,
          input_value                => math_input_value,
          output_select              => math_output_counter,
          output_value(31 downto 0)  => math_output_value_low,
          output_value(63 downto 32) => math_output_value_high
        );
    end generate;

    process (clock,reset,reg_a,reg_x,reg_y,reg_z,flag_c,all_pause,read_data)

      variable memory_read_value : unsigned(7 downto 0);

      variable memory_access_address         : unsigned(27 downto 0) := x"FFFFFFF";
      variable memory_access_read            : std_logic             := '0';
      variable memory_access_write           : std_logic             := '0';
      variable memory_access_resolve_address : std_logic             := '0';
      variable memory_access_wdata           : unsigned(31 downto 0)  := x"FFFFFFFF";
      variable memory_access_byte_count      : integer range 0 to 4 := 0;

      variable flat32_addressmode_v : std_logic := '0';
      variable var_addressingmode : addressingmode := M_impl;
      variable var_instruction    : instruction;
      variable prefix_bytes : integer range 0 to 3 := 0;
      variable is_store_v : std_logic := '0';
      variable is_load_v : std_logic := '0';
      variable is_rmw_v : std_logic := '0';
      variable is_indirect_v : std_logic := '0';
      variable is_axyz32_instruction_v : std_logic := '0';
      variable zp32bit_pointer_enabled_v : std_logic := '0';
      variable memory_access_set_address_based_on_addressingmode : std_logic := '0';
      variable fetch_instruction_please : std_logic := '0';
      variable sp_dec : integer range 0 to 255 := 0;
      variable sp_inc : integer range 0 to 255 := 0;
      variable var_microcode : microcodeops;


      -- purpose: obtain the byte of memory that has been read
      impure function read_d7xx_register(the_read_address : unsigned(7 downto 0))
        return unsigned is
        variable value : unsigned(7 downto 0);
      begin
        -- CPU hosted IO registers at $D7xx
        -- Actually, this is all of $D700-$D7FF decoded by the CPU at present
        report "Reading CPU $D7xx register (dedicated path)";
        case the_read_address(7 downto 0) is
          when x"00"|x"05" => return reg_dmagic_addr(7 downto 0);
          when x"01"       => return reg_dmagic_addr(15 downto 8);
          when x"02"       => return reg_dmagic_withio
            & reg_dmagic_addr(22 downto 16);
          when x"03" => return reg_dmagic_status(7 downto 1) & support_f018b;
          when x"04" => return reg_dmagic_addr(27 downto 20);
          when x"10" => return "00" & badline_extra_cycles & charge_for_branches_taken & vdc_enabled & slow_interrupts & badline_enable;
          -- @IO:GS $D711.7 DMA:AUDEN Enable Audio DMA
          -- @IO:GS $D711.6 DMA:BLKD Audio DMA blocked (read only) DEBUG
          -- @IO:GS $D711.5 DMA:AUDWRBLK Audio DMA block writes (samples still get read)
          -- @IO:GS $D711.4 DMA:NOMIX Audio DMA bypasses audio mixer
          -- @IO:GS $D711.3 AUDIO:PWMPDM PWM/PDM audio encoding select
          -- @IO:GS $D711.0-2 DMA:AUDBLKTO Audio DMA block timeout (read only) DEBUG
          when x"11" => return audio_dma_enable & pending_dma_busy & audio_dma_disable_writes
            & cpu_pcm_bypass_int & pwm_mode_select_int & "000";

          -- XXX DEBUG registers for audio DMA
          when x"12" => return audio_dma_left_saturated & audio_dma_right_saturated &
            "0000" & audio_dma_swap & audio_dma_saturation_enable;

          -- @IO:GS $D71C DMA:CH0RVOL Audio DMA channel 0 right channel volume
          -- @IO:GS $D71D DMA:CH1RVOL Audio DMA channel 1 right channel volume
          -- @IO:GS $D71E DMA:CH2LVOL Audio DMA channel 2 left channel volume
          -- @IO:GS $D71F DMA:CH3LVOL Audio DMA channel 3 left channel volume
          when x"1c" => return audio_dma_pan_volume(0)(7 downto 0);
          when x"1d" => return audio_dma_pan_volume(1)(7 downto 0);
          when x"1e" => return audio_dma_pan_volume(2)(7 downto 0);
          when x"1f" =>
            return audio_dma_pan_volume(3)(7 downto 0);

            -- @IO:GS $D720.7 DMA:CH0EN Enable Audio DMA channel 0
            -- @IO:GS $D720.6 DMA:CH0LOOP Enable Audio DMA channel 0 looping
            -- @IO:GS $D720.5 DMA:CH0SGN Enable Audio DMA channel 0 signed samples
            -- @IO:GS $D720.4 DMA:CH0SINE Audio DMA channel 0 play 32-sample sine wave instead of DMA data
            -- @IO:GS $D720.3 DMA:CH0STP Audio DMA channel 0 stop flag
            -- @IO:GS $D720.0-1 DMA:CH0SBITS Audio DMA channel 0 sample bits (11=16, 10=8, 01=upper nybl, 00=lower nybl)
            -- @IO:GS $D721 DMA:CH0BADDR Audio DMA channel 0 base address LSB
            -- @IO:GS $D722 DMA:CH0BADDR Audio DMA channel 0 base address middle byte
            -- @IO:GS $D723 DMA:CH0BADDR Audio DMA channel 0 base address MSB
            -- @IO:GS $D724 DMA:CH0FREQ Audio DMA channel 0 frequency LSB
            -- @IO:GS $D725 DMA:CH0FREQ Audio DMA channel 0 frequency middle byte
            -- @IO:GS $D726 DMA:CH0FREQ Audio DMA channel 0 frequency MSB
            -- @IO:GS $D727 DMA:CH0TADDR Audio DMA channel 0 top address LSB
            -- @IO:GS $D728 DMA:CH0TADDR Audio DMA channel 0 top address middle byte
            -- @IO:GS $D729 DMA:CH0VOLUME Audio DMA channel 0 playback volume
            -- @IO:GS $D72A DMA:CH0FREQ Audio DMA channel 0 current address LSB
            -- @IO:GS $D72B DMA:CH0FREQ Audio DMA channel 0 current address middle byte
            -- @IO:GS $D72C DMA:CH0FREQ Audio DMA channel 0 current address MSB
            -- @IO:GS $D72D DMA:CH0FREQ Audio DMA channel 0 timing counter LSB
            -- @IO:GS $D72E DMA:CH0FREQ Audio DMA channel 0 timing counter middle byte
            -- @IO:GS $D72F DMA:CH0FREQ Audio DMA channel 0 timing counter address MSB

            -- @IO:GS $D730.7 DMA:CH1EN Enable Audio DMA channel 1
            -- @IO:GS $D730.6 DMA:CH1LOOP Enable Audio DMA channel 1 looping
            -- @IO:GS $D730.5 DMA:CH1SGN Enable Audio DMA channel 1 signed samples
            -- @IO:GS $D730.4 DMA:CH1SINE Audio DMA channel 1 play 32-sample sine wave instead of DMA data
            -- @IO:GS $D730.3 DMA:CH1STP Audio DMA channel 1 stop flag
            -- @IO:GS $D730.0-1 DMA:CH1SBITS Audio DMA channel 1 sample bits (11=16, 10=8, 01=upper nybl, 00=lower nybl)
            -- @IO:GS $D731 DMA:CH1BADDR Audio DMA channel 1 base address LSB
            -- @IO:GS $D732 DMA:CH1BADDR Audio DMA channel 1 base address middle byte
            -- @IO:GS $D733 DMA:CH1BADDR Audio DMA channel 1 base address MSB
            -- @IO:GS $D734 DMA:CH1FREQ Audio DMA channel 1 frequency LSB
            -- @IO:GS $D735 DMA:CH1FREQ Audio DMA channel 1 frequency middle byte
            -- @IO:GS $D736 DMA:CH1FREQ Audio DMA channel 1 frequency MSB
            -- @IO:GS $D737 DMA:CH1TADDR Audio DMA channel 1 top address LSB
            -- @IO:GS $D738 DMA:CH1TADDR Audio DMA channel 1 top address middle byte
            -- @IO:GS $D739 DMA:CH1VOLUME Audio DMA channel 1 playback volume
            -- @IO:GS $D73A DMA:CH1FREQ Audio DMA channel 1 current address LSB
            -- @IO:GS $D73B DMA:CH1FREQ Audio DMA channel 1 current address middle byte
            -- @IO:GS $D73C DMA:CH1FREQ Audio DMA channel 1 current address MSB
            -- @IO:GS $D73D DMA:CH1FREQ Audio DMA channel 1 timing counter LSB
            -- @IO:GS $D73E DMA:CH1FREQ Audio DMA channel 1 timing counter middle byte
            -- @IO:GS $D73F DMA:CH1FREQ Audio DMA channel 1 timing counter address MSB

            -- @IO:GS $D740.7 DMA:CH2EN Enable Audio DMA channel 2
            -- @IO:GS $D740.6 DMA:CH2LOOP Enable Audio DMA channel 2 looping
            -- @IO:GS $D740.5 DMA:CH2SGN Enable Audio DMA channel 2 signed samples
            -- @IO:GS $D740.4 DMA:CH2SINE Audio DMA channel 2 play 32-sample sine wave instead of DMA data
            -- @IO:GS $D740.3 DMA:CH2STP Audio DMA channel 2 stop flag
            -- @IO:GS $D740.0-1 DMA:CH1SBITS Audio DMA channel 1 sample bits (11=16, 10=8, 01=upper nybl, 00=lower nybl)
            -- @IO:GS $D741 DMA:CH2BADDR Audio DMA channel 2 base address LSB
            -- @IO:GS $D742 DMA:CH2BADDR Audio DMA channel 2 base address middle byte
            -- @IO:GS $D743 DMA:CH2BADDR Audio DMA channel 2 base address MSB
            -- @IO:GS $D744 DMA:CH2FREQ Audio DMA channel 2 frequency LSB
            -- @IO:GS $D745 DMA:CH2FREQ Audio DMA channel 2 frequency middle byte
            -- @IO:GS $D746 DMA:CH2FREQ Audio DMA channel 2 frequency MSB
            -- @IO:GS $D747 DMA:CH2TADDR Audio DMA channel 2 top address LSB
            -- @IO:GS $D748 DMA:CH2TADDR Audio DMA channel 2 top address middle byte
            -- @IO:GS $D749 DMA:CH2VOLUME Audio DMA channel 2 playback volume
            -- @IO:GS $D74A DMA:CH2FREQ Audio DMA channel 2 current address LSB
            -- @IO:GS $D74B DMA:CH2FREQ Audio DMA channel 2 current address middle byte
            -- @IO:GS $D74C DMA:CH2FREQ Audio DMA channel 2 current address MSB
            -- @IO:GS $D74D DMA:CH2FREQ Audio DMA channel 2 timing counter LSB
            -- @IO:GS $D74E DMA:CH2FREQ Audio DMA channel 2 timing counter middle byte
            -- @IO:GS $D74F DMA:CH2FREQ Audio DMA channel 2 timing counter address MSB

            -- @IO:GS $D750.7 DMA:CH3EN Enable Audio DMA channel 3
            -- @IO:GS $D750.6 DMA:CH3LOOP Enable Audio DMA channel 3 looping
            -- @IO:GS $D750.5 DMA:CH3SGN Enable Audio DMA channel 3 signed samples
            -- @IO:GS $D750.4 DMA:CH3SINE Audio DMA channel 3 play 32-sample sine wave instead of DMA data
            -- @IO:GS $D750.3 DMA:CH3STP Audio DMA channel 3 stop flag
            -- @IO:GS $D750.0-1 DMA:CH3SBITS Audio DMA channel 3 sample bits (11=16, 10=8, 01=upper nybl, 00=lower nybl)
            -- @IO:GS $D751 DMA:CH3BADDR Audio DMA channel 3 base address LSB
            -- @IO:GS $D752 DMA:CH3BADDR Audio DMA channel 3 base address middle byte
            -- @IO:GS $D753 DMA:CH3BADDR Audio DMA channel 3 base address MSB
            -- @IO:GS $D754 DMA:CH3FREQ Audio DMA channel 3 frequency LSB
            -- @IO:GS $D755 DMA:CH3FREQ Audio DMA channel 3 frequency middle byte
            -- @IO:GS $D756 DMA:CH3FREQ Audio DMA channel 3 frequency MSB
            -- @IO:GS $D757 DMA:CH3TADDR Audio DMA channel 3 top address LSB
            -- @IO:GS $D758 DMA:CH3TADDR Audio DMA channel 3 top address middle byte
            -- @IO:GS $D759 DMA:CH3VOLUME Audio DMA channel 3 playback volume
            -- @IO:GS $D75A DMA:CH3FREQ Audio DMA channel 3 current address LSB
            -- @IO:GS $D75B DMA:CH3FREQ Audio DMA channel 3 current address middle byte
            -- @IO:GS $D75C DMA:CH3FREQ Audio DMA channel 3 current address MSB
            -- @IO:GS $D75D DMA:CH3FREQ Audio DMA channel 3 timing counter LSB
            -- @IO:GS $D75E DMA:CH3FREQ Audio DMA channel 3 timing counter middle byte
            -- @IO:GS $D75F DMA:CH3FREQ Audio DMA channel 3 timing counter address MSB


          -- $D720-$D72F - Audio DMA channel 0
          when x"20" => return audio_dma_enables(0) & audio_dma_repeat(0) & audio_dma_signed(0) &
            audio_dma_sine_wave(0) & audio_dma_stop(0) & audio_dma_sample_valid(0) & audio_dma_sample_width(0);
          when x"21" => return audio_dma_base_addr(0)(7 downto 0);
          when x"22" => return audio_dma_base_addr(0)(15 downto 8);
          when x"23" => return audio_dma_base_addr(0)(23 downto 16);
          when x"24" => return audio_dma_time_base(0)(7 downto 0);
          when x"25" => return audio_dma_time_base(0)(15 downto 8);
          when x"26" => return audio_dma_time_base(0)(23 downto 16);
          when x"27" => return audio_dma_top_addr(0)(7 downto 0);
          when x"28" => return audio_dma_top_addr(0)(15 downto 8);
          when x"29" => return audio_dma_volume(0)(7 downto 0);
          when x"2a" => return audio_dma_current_addr(0)(7 downto 0);
          when x"2b" => return audio_dma_current_addr(0)(15 downto 8);
          when x"2c" => return audio_dma_current_addr(0)(23 downto 16);
          when x"2d" => return audio_dma_timing_counter(0)(7 downto 0);
          when x"2e" => return audio_dma_timing_counter(0)(15 downto 8);
          when x"2f" => return audio_dma_timing_counter(0)(23 downto 16);
          -- $D730-$D73F - Audio DMA channel 1
          when x"30" => return audio_dma_enables(1) & audio_dma_repeat(1) & audio_dma_signed(1) &
            audio_dma_sine_wave(1) & audio_dma_stop(1) & audio_dma_sample_valid(1) & audio_dma_sample_width(1);
          when x"31" => return audio_dma_base_addr(1)(7 downto 0);
          when x"32" => return audio_dma_base_addr(1)(15 downto 8);
          when x"33" => return audio_dma_base_addr(1)(23 downto 16);
          when x"34" => return audio_dma_time_base(1)(7 downto 0);
          when x"35" => return audio_dma_time_base(1)(15 downto 8);
          when x"36" => return audio_dma_time_base(1)(23 downto 16);
          when x"37" => return audio_dma_top_addr(1)(7 downto 0);
          when x"38" => return audio_dma_top_addr(1)(15 downto 8);
          when x"39" => return audio_dma_volume(1)(7 downto 0);
          when x"3a" => return audio_dma_current_addr(1)(7 downto 0);
          when x"3b" => return audio_dma_current_addr(1)(15 downto 8);
          when x"3c" => return audio_dma_current_addr(1)(23 downto 16);
          when x"3d" => return audio_dma_timing_counter(1)(7 downto 0);
          when x"3e" => return audio_dma_timing_counter(1)(15 downto 8);
          when x"3f" => return audio_dma_timing_counter(1)(23 downto 16);
          -- $D740-$D74F - Audio DMA channel 2
          when x"40" => return audio_dma_enables(2) & audio_dma_repeat(2) & audio_dma_signed(2) &
            audio_dma_sine_wave(2) & audio_dma_stop(2) & audio_dma_sample_valid(2) & audio_dma_sample_width(2);
          when x"41" => return audio_dma_base_addr(2)(7 downto 0);
          when x"42" => return audio_dma_base_addr(2)(15 downto 8);
          when x"43" => return audio_dma_base_addr(2)(23 downto 16);
          when x"44" => return audio_dma_time_base(2)(7 downto 0);
          when x"45" => return audio_dma_time_base(2)(15 downto 8);
          when x"46" => return audio_dma_time_base(2)(23 downto 16);
          when x"47" => return audio_dma_top_addr(2)(7 downto 0);
          when x"48" => return audio_dma_top_addr(2)(15 downto 8);
          when x"49" => return audio_dma_volume(2)(7 downto 0);
          when x"4a" => return audio_dma_current_addr(2)(7 downto 0);
          when x"4b" => return audio_dma_current_addr(2)(15 downto 8);
          when x"4c" => return audio_dma_current_addr(2)(23 downto 16);
          when x"4d" => return audio_dma_timing_counter(2)(7 downto 0);
          when x"4e" => return audio_dma_timing_counter(2)(15 downto 8);
          when x"4f" => return audio_dma_timing_counter(2)(23 downto 16);
          -- $D750-$D75F - Audio DMA channel 3
          when x"50" => return audio_dma_enables(3) & audio_dma_repeat(3) & audio_dma_signed(3) &
            audio_dma_sine_wave(3) & audio_dma_stop(3) & audio_dma_sample_valid(3) & audio_dma_sample_width(3);
          when x"51" => return audio_dma_base_addr(3)(7 downto 0);
          when x"52" => return audio_dma_base_addr(3)(15 downto 8);
          when x"53" => return audio_dma_base_addr(3)(23 downto 16);
          when x"54" => return audio_dma_time_base(3)(7 downto 0);
          when x"55" => return audio_dma_time_base(3)(15 downto 8);
          when x"56" => return audio_dma_time_base(3)(23 downto 16);
          when x"57" => return audio_dma_top_addr(3)(7 downto 0);
          when x"58" => return audio_dma_top_addr(3)(15 downto 8);
          when x"59" => return audio_dma_volume(3)(7 downto 0);
          when x"5a" => return audio_dma_current_addr(3)(7 downto 0);
          when x"5b" => return audio_dma_current_addr(3)(15 downto 8);
          when x"5c" => return audio_dma_current_addr(3)(23 downto 16);
          when x"5d" => return audio_dma_timing_counter(3)(7 downto 0);
          when x"5e" => return audio_dma_timing_counter(3)(15 downto 8);
          when x"5f" => return audio_dma_timing_counter(3)(23 downto 16);


          -- $D760-$D7DF reserved for math unit functions
          when x"68" => return div_q(7 downto 0);
          when x"69" => return div_q(15 downto 8);
          when x"6a" => return div_q(23 downto 16);
          when x"6b" => return div_q(31 downto 24);
          when x"6c" => return div_q(39 downto 32);
          when x"6d" => return div_q(47 downto 40);
          when x"6e" => return div_q(55 downto 48);
          when x"6f" => return div_q(63 downto 56);
          when x"70" => return reg_mult_a(7 downto 0);
          when x"71" => return reg_mult_a(15 downto 8);
          when x"72" => return reg_mult_a(23 downto 16);
          when x"73" => return reg_mult_a(31 downto 24);
          when x"74" => return reg_mult_b(7 downto 0);
          when x"75" => return reg_mult_b(15 downto 8);
          when x"76" => return reg_mult_b(23 downto 16);
          when x"77" =>
            return reg_mult_b(31 downto 24);
            -- @IO:GS $D768 MATH:MULTOUT 64-bit output of MULTINA $\div$ MULTINB
            -- @IO:GS $D769 MATH:MULTOUT 64-bit output of MULTINA $\div$ MULTINB
            -- @IO:GS $D76A MATH:MULTOUT 64-bit output of MULTINA $\div$ MULTINB
            -- @IO:GS $D76B MATH:MULTOUT 64-bit output of MULTINA $\div$ MULTINB
            -- @IO:GS $D76C MATH:MULTOUT 64-bit output of MULTINA $\div$ MULTINB
            -- @IO:GS $D76D MATH:MULTOUT 64-bit output of MULTINA $\div$ MULTINB
            -- @IO:GS $D76E MATH:MULTOUT 64-bit output of MULTINA $\div$ MULTINB
            -- @IO:GS $D76F MATH:MULTOUT 64-bit output of MULTINA $\div$ MULTINB
            -- @IO:GS $D770 MATH:MULTINA Multiplier input A / Divider numerator (32 bit)
            -- @IO:GS $D771 MATH:MULTINA Multiplier input A / Divider numerator (32 bit)
            -- @IO:GS $D772 MATH:MULTINA Multiplier input A / Divider numerator (32 bit)
            -- @IO:GS $D773 MATH:MULTINA Multiplier input A / Divider numerator (32 bit)
            -- @IO:GS $D774 MATH:MULTINB Multiplier input B / Divider denominator (32 bit)
            -- @IO:GS $D775 MATH:MULTINB Multiplier input B / Divider denominator (32 bit)
            -- @IO:GS $D776 MATH:MULTINB Multiplier input B / Divider denominator (32 bit)
            -- @IO:GS $D777 MATH:MULTINB Multiplier input B / Divider denominator (32 bit)
            -- @IO:GS $D778 MATH:MULTOUT 64-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D779 MATH:MULTOUT 64-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77A MATH:MULTOUT 64-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77B MATH:MULTOUT 64-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77C MATH:MULTOUT 64-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77D MATH:MULTOUT 64-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77E MATH:MULTOUT 64-bit output of MULTINA $\times$ MULTINB
            -- @IO:GS $D77F MATH:MULTOUT 64-bit output of MULTINA $\times$ MULTINB

          when x"78" => return reg_mult_p(7 downto 0);
          when x"79" => return reg_mult_p(15 downto 8);
          when x"7a" => return reg_mult_p(23 downto 16);
          when x"7b" => return reg_mult_p(31 downto 24);
          when x"7c" => return reg_mult_p(39 downto 32);
          when x"7d" => return reg_mult_p(47 downto 40);
          when x"7e" => return reg_mult_p(55 downto 48);
          when x"7f" =>
            return reg_mult_p(63 downto 56);
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
              when "00"   => return reg_math_regs(to_integer(the_read_address(5 downto 2)))(7 downto 0);
              when "01"   => return reg_math_regs(to_integer(the_read_address(5 downto 2)))(15 downto 8);
              when "10"   => return reg_math_regs(to_integer(the_read_address(5 downto 2)))(23 downto 16);
              when "11"   => return reg_math_regs(to_integer(the_read_address(5 downto 2)))(31 downto 24);
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

          --@IO:GS $D7F2 CPU:PHIPERFRAME Count the number of PHI cycles per video frame (LSB)
          --@IO:GS $D7F5 CPU:PHIPERFRAME Count the number of PHI cycles per video frame (MSB)
          when x"f2" => return last_cycles_per_frame(7 downto 0);
          when x"f3" => return last_cycles_per_frame(15 downto 8);
          when x"f4" => return last_cycles_per_frame(23 downto 16);
          when x"f5" => return last_cycles_per_frame(31 downto 24);
          --@IO:GS $D7F6 CPU:CYCPERFRAME Count the number of usable (proceed=1) CPU cycles per video frame (LSB)
          --@IO:GS $D7F9 CPU:CYCPERFRAME Count the number of usable (proceed=1) CPU cycles per video frame (MSB)
          when x"f6" => return last_proceeds_per_frame(7 downto 0);
          when x"f7" => return last_proceeds_per_frame(15 downto 8);
          when x"f8" => return last_proceeds_per_frame(23 downto 16);
          when x"f9" => return last_proceeds_per_frame(31 downto 24);
          -- @IO:GS $D7FA CPU:FRAMECOUNT Count number of elapsed video frames
          when x"fa" => return frame_counter(7 downto 0);
          when x"fb" => return "000000" & cartridge_enable & "0";
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
          when x"fe" =>
            value(0)          := '0';
            value(1)          := ocean_cart_mode;
            value(7 downto 2) := (others => '0');
            return value;
          when others => return x"ff";
        end case;
      end function;

        procedure disassemble_instruction(
            pc : in unsigned(15 downto 0);
            ibytes : in unsigned(23 downto 0)) is
        variable justification : side             := RIGHT;
          variable size          : width            := 0;
        variable s             : string(1 to 119) := (others => ' ');
        variable t             : string(1 to 100) := (others => ' ');
        variable virtual_reg_p : std_logic_vector(7 downto 0);
      begin
        --pragma synthesis_off
        if last_bytecount > 0 then
          -- Program counter
          s(1)      := '$';
          s(2 to 5) := to_hstring(pc)(1 to 4);
          -- opcode and arguments
          s(7 to 8) := to_hstring(ibytes(7 downto 0))(1 to 2);
          if last_bytecount > 1 then
            s(10 to 11) := to_hstring(ibytes(15 downto 8))(1 to 2);
          end if;
          if last_bytecount > 2 then
            s(13 to 14) := to_hstring(ibytes(23 downto 16))(1 to 2);
          end if;
          -- instruction name
          t(1 to 5)   := instruction'image(instruction_lut(to_integer(ibytes(7 downto 0))));
          s(17 to 19) := t(3 to 5);

          -- Draw 0-7 digit on BBS/BBR instructions
          case instruction_lut(to_integer(emu6502&ibytes(7 downto 0))) is
            when I_BBS =>
              s(20 to 20) := to_hstring("0"&ibytes(6 downto 4))(1 to 1);
            when I_BBR =>
              s(20 to 20) := to_hstring("0"&ibytes(6 downto 4))(1 to 1);
            when others =>
              null;
          end case;

          -- Draw arguments
          case mode_lut(to_integer(emu6502&ibytes(7 downto 0))) is
            when M_impl => null;
            when M_InnX =>
              s(22 to 23) := "($";
              s(24 to 25) := to_hstring(ibytes(15 downto 8))(1 to 2);
              s(26 to 28) := ",X)";
            when M_nn =>
              s(22)       := '$';
              s(23 to 24) := to_hstring(ibytes(15 downto 8))(1 to 2);
            when M_immnn =>
              s(22 to 23) := "#$";
              s(24 to 25) := to_hstring(ibytes(15 downto 8))(1 to 2);
            when M_A    => null;
            when M_nnnn =>
              s(22)       := '$';
              s(23 to 26) := to_hstring(ibytes(23 downto 8))(1 to 4);
            when M_nnrr =>
              s(22)       := '$';
              s(23 to 24) := to_hstring(ibytes(15 downto 8))(1 to 2);
              s(25 to 26) := ",$";
              s(27 to 30) := to_hstring(pc + 3 + ibytes(23 downto 16))(1 to 4);
            when M_rr =>
              s(22) := '$';
              if last_byte2(7)='0' then
                s(23 to 26) := to_hstring(pc + 2 + ibytes(15 downto 8))(1 to 4);
              else
                s(23 to 26) := to_hstring(pc + 2 - 256 + ibytes(15 downto 8))(1 to 4);
              end if;
            when M_InnY =>
              s(22 to 23) := "($";
              s(24 to 25) := to_hstring(ibytes(15 downto 8))(1 to 2);
              s(26 to 28) := "),Y";
            when M_InnZ =>
              s(22 to 23) := "($";
              s(24 to 25) := to_hstring(ibytes(15 downto 8))(1 to 2);
              s(26 to 28) := "),Z";
            when M_rrrr =>
              s(22)       := '$';
              s(23 to 26) := to_hstring(pc + 2 + (ibytes(23 downto 8)))(1 to 4);
            when M_nnX =>
              s(22)       := '$';
              s(23 to 24) := to_hstring(ibytes(15 downto 8))(1 to 2);
              s(25 to 26) := ",X";
            when M_nnnnY =>
              s(22)       := '$';
              s(23 to 26) := to_hstring(ibytes(23 downto 8))(1 to 4);
              s(27 to 28) := ",Y";
            when M_nnnnX =>
              s(22)       := '$';
              s(23 to 26) := to_hstring(ibytes(23 downto 8))(1 to 4);
              s(27 to 28) := ",X";
            when M_Innnn =>
              s(22 to 23) := "($";
              s(24 to 27) := to_hstring(ibytes(23 downto 8))(1 to 4);
              s(28 to 28) := ")";
            when M_InnnnX =>
              s(22 to 23) := "($";
              s(24 to 27) := to_hstring(ibytes(23 downto 8))(1 to 4);
              s(28 to 30) := ",X)";
            when M_InnSPY =>
              s(22 to 23) := "($";
              s(24 to 25) := to_hstring(ibytes(15 downto 8))(1 to 2);
              s(26 to 31) := ",SP),Y";
            when M_nnY =>
              s(22)       := '$';
              s(23 to 24) := to_hstring(ibytes(15 downto 8))(1 to 2);
              s(25 to 26) := ",Y";
            when M_immnnnn =>
              s(22 to 23) := "#$";
              s(24 to 27) := to_hstring(ibytes(23 downto 8))(1 to 4);
          end case;

          -- Show registers
          s(36 to 96)      := "A:xx X:xx Y:xx Z:xx SP:xxxx P:xx $01=xx MAPLO:xxxx MAPHI:xxxx";
          s(38 to 39)      := to_hstring(reg_a);
          s(43 to 44)      := to_hstring(reg_x);
          s(48 to 49)      := to_hstring(reg_y);
          s(53 to 54)      := to_hstring(reg_z);
          s(59 to 62)      := to_hstring(reg_sph&reg_sp);
          virtual_reg_p(7) := flag_n;
          virtual_reg_p(6) := flag_v;
          virtual_reg_p(5) := flag_e;
          virtual_reg_p(4) := '0';
          virtual_reg_p(3) := flag_d;
          virtual_reg_p(2) := flag_i;
          virtual_reg_p(1) := flag_z;
          virtual_reg_p(0) := flag_c;
          s(66 to 67)      := to_hstring(virtual_reg_p);
          s(73 to 74)      := to_hstring(cpuport_value or (not cpuport_ddr));
          s(82 to 85)      := to_hstring(unsigned(reg_map_low)&reg_offset_low);
          s(93 to 96)      := to_hstring(unsigned(reg_map_high)&reg_offset_high);

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

        -- Disable all audio DMA channels, so we can recover from
        -- any insane condition with them.
        audio_dma_enables(0) <= '0';
        audio_dma_enables(1) <= '0';
        audio_dma_enables(2) <= '0';
        audio_dma_enables(3) <= '0';

        -- Enable chipselect for all peripherals and memories
        chipselect_enables       <= x"EF";
        cartridge_enable         <= '1';
        hyper_protected_hardware <= x"00";

        -- CPU starts in hypervisor
        hypervisor_mode <= '1';

        instruction_phase <= x"0";

        -- Default register values
        reg_b   <= x"00";
        reg_a   <= x"11";
        reg_x   <= x"22";
        reg_y   <= x"33";
        reg_z   <= x"00";
        reg_sp  <= x"ff";
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
          reg_map_high    <= "0000";
          reg_offset_low  <= x"000";
          reg_map_low     <= "0000";
          reg_mb_high     <= x"00";
          reg_mb_low      <= x"00";
        else
          -- with hyppo
          reg_offset_high <= x"F00";
          reg_map_high    <= "1000";
          reg_offset_low  <= x"000";
          reg_map_low     <= "0100";
          reg_mb_high     <= x"FF";
          reg_mb_low      <= x"80";
        end if;

        -- Default CPU flags
        flag_c <= '0';
        flag_d <= '0';
        flag_i <= '1'; -- start with IRQ disabled
        flag_z <= '0';
        flag_n <= '0';
        flag_v <= '0';
        flag_e <= '1';

        cpuport_ddr   <= x"FF";
        cpuport_value <= x"3F";
        force_fast    <= '0';

        mem_reading          <= '0';
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
            irq_defer_active  <= '1';
            irq_defer_counter <= irq_defer_counter - 1;
          end if;
        end if;
      end procedure check_for_interrupts;

      procedure read_long_address(
          real_long_address : in unsigned(27 downto 0);
          byte_count        : in integer range 0 to 4) is
        variable long_address : unsigned(27 downto 0);
      begin

        last_action  <= 'R'; last_address <= real_long_address;
        long_address := long_address_read;

        report "Reading from long address $" & to_hstring(long_address) severity note;
        mem_reading <= '1';

        the_read_address <= long_address;

        -- Schedule the memory read from the appropriate source.

        report "MEMORY long_address = $" & to_hstring(long_address);

        -- VDC data register can be mapped to memory if the correct register is selected
        if (long_address = x"ffd3601") and (hypervisor_mode='0') and (vdc_enabled='1') then
          if vdc_reg_num = x"1f" then
            report "Preparing to read from Shadow for simulated VDC access";
            long_address := to_unsigned(to_integer(resolved_vdc_to_viciv_address)+(4*65536),28);
            vdc_mem_addr <= vdc_mem_addr + 1;
          end if;
        end if;
        -- CPU IO ports get mapped to fastio area
        if (long_address = x"0000000") or (long_address = x"0000001") then
          long_address(27 downto 20) := x"ff";
        end if;

        report "Preparing to read via memory controller @ $" & to_hstring(long_address);

        memory_access_address     := long_address;
        memory_access_read        := '1';
        memory_access_write       := '0';
        memory_access_byte_count  := 1;
      end read_long_address;

      impure function read_hypervisor_register(hyperport_num : unsigned(5 downto 0))
        return unsigned is
        variable value : unsigned(7 downto 0);
      begin
        -- CPU hosted Hypervisor registers at $D640-$D67F
        report "Reading Hypervisor register (dedicated path)";
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
            return "000000"&virtualise_sd1&virtualise_sd0;

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
            return nmi_pending
            & iec_bus_active
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
          when others   => return x"FF";
        end case;
      end function;

      impure function read_cpuport_register
        return unsigned is
        variable value : unsigned(7 downto 0);
      begin
        report "reading from CPU port" severity note;
        case cpuport_num is
          when x"0" => return cpuport_ddr;
          when x"1" => return cpuport_value;
          when x"2" => return rec_status;
          when x"3" => return vdc_status;
          when x"4" =>
            -- Read other VDC registers.
            return x"ff";
          when x"5"   => return vdc_mem_addr(7 downto 0);
          when x"6"   => return vdc_mem_addr(15 downto 8);
          when x"7"   => return vdc_reg_num(7 downto 0);
          when others => return x"ff";
        end case;
      end function;

      procedure write_long_byte(
          real_long_address : in unsigned(27 downto 0);
          value             : in unsigned(7 downto 0)) is
        variable long_address : unsigned(27 downto 0);
      begin
        -- Schedule the memory write to the appropriate destination.
        -- XXX Add support for multi-byte parallel writes via new memory controller

        last_action <= 'W'; last_value <= value; last_address <= real_long_address;

        long_address := long_address_write;

        last_write_address <= real_long_address;

        -- Start DMAgic jobs?
        if (long_address = x"FFD3700") or (long_address = x"FFD1700") then
          d700_triggered <= '1';
          -- Set low order bits of DMA list address
          reg_dmagic_addr(7 downto 0) <= value;
          reg_dmagic_addr(27 downto 23) <= (others => '0');
        elsif (long_address = x"FFD3705") or (long_address = x"FFD1705") then
          d705_triggered <= '1';
          reg_dmagic_addr(7 downto 0) <= value;
        end if;

        -- Trigger REU DMA via $FF00 ?
        if real_long_address(15 downto 0) = x"ff00" then
          if reu_ff00_pending = '1' then
          -- XXX Start REU job
          end if;
        end if;

        -- Setup memory access
        memory_access_wdata(7 downto 0) := value;
        memory_access_byte_count        := 1;
        memory_access_address           := long_address;

        -- Advance address for VDC access, and translate address
        if (real_long_address = x"FFD3601") and (vdc_reg_num = x"1F") and (hypervisor_mode='0') and (vdc_enabled='1') then
          vdc_mem_addr <= vdc_mem_addr + 1;
          memory_access_address(27 downto 16) := x"004";
          memory_access_address(15 downto 0) := vdc_mem_addr;
        end if;

        if long_address(27 downto 17) /= "00000000001" or rom_writeprotect='0' then
          memory_access_write             := '1';
        end if;
      end write_long_byte;

      -- purpose: Convert a 16-bit C64 address to native RAM (or I/O or ROM) address
      impure function resolve_address_to_long(short_address : unsigned(15 downto 0);
          writeP : boolean)
        return unsigned is
        variable temp_address     : unsigned(27 downto 0);
        variable blocknum         : integer;
        variable lhc              : std_logic_vector(4 downto 0);
        variable char_access_addr : unsigned(15 downto 0);
      begin -- resolve_long_address

        -- Now apply C64-style $01 lines first, because MAP and $D030 take precedence
        blocknum := to_integer(short_address(15 downto 12));

        lhc(4)          := gated_exrom;
        lhc(3)          := gated_game;
        lhc(2 downto 0) := std_logic_vector(cpuport_value(2 downto 0));
        lhc(2)          := lhc(2) or (not cpuport_ddr(2));
        lhc(1)          := lhc(1) or (not cpuport_ddr(1));
        lhc(0)          := lhc(0) or (not cpuport_ddr(0));

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
        temp_address(15 downto 0)  := short_address;

        -- IO
        if (blocknum=13) then
          temp_address(11 downto 0) := short_address(11 downto 0);
          -- IO is always visible in ultimax mode
          if gated_exrom/='1' or gated_game/='0' or hypervisor_mode='1' then
            case lhc(2 downto 0) is
              when "000"  => temp_address(27 downto 12) := x"000D";          -- WRITE RAM
              when "001"  => temp_address(27 downto 12) := char_access_addr; -- WRITE RAM / READ CHARROM
              when "010"  => temp_address(27 downto 12) := char_access_addr; -- WRITE RAM / READ CHARROM
              when "011"  => temp_address(27 downto 12) := char_access_addr; -- WRITE RAM / READ CHARROM
              when "100"  => temp_address(27 downto 12) := x"000D";          -- WRITE RAM
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
                -- IO mode "10" = ethernet buffer at $D800-$DFFF, so no cartridge
                -- IO
                if sector_buffer_mapped='0' and colourram_at_dc00='0' and viciii_iomode/="10" and ocean_cart_mode='0' then
                  -- Map $DE00-$DFFF IO expansion areas to expansion port
                  -- (but only if SD card sector buffer is not mapped, and
                  -- 2nd KB of colour RAM is not mapped, and we aren't pretending
                  -- to be an Ocean caretridge or GeoRAM).
                  if (short_address(11 downto 8) = x"E")
                    or (short_address(11 downto 8) = x"F") then
                    temp_address(27 downto 12) := x"7FFD";
                    if short_address(11 downto 8) = x"E" and georam_blockmask /= x"00" then
                      temp_address(27 downto 8) := georam_page;
                    end if;

                  end if;
                end if;
                -- Map colour RAM at in $Dxxx
                if sector_buffer_mapped='0' and
                  short_address(11 downto 8) >= x"8" and
                  short_address(11 downto 8) <= x"b" then
                  -- Colour RAM at $D800-$DBFF
                  temp_address(27 downto 12) := x"FF80";
                end if;
                if sector_buffer_mapped='0' and colourram_at_dc00='1' and
                  short_address(11 downto 8) >= x"c" then
                  -- Colour RAM at $DC00-$DFFF
                  temp_address(27 downto 12) := x"FF80";
                end if;
                -- VDC RAM access
                if vdc_enabled='1' and short_address(11 downto 0)=x"601" and vdc_reg_num = x"1f" and hypervisor_mode='0' then
                  -- We map VDC RAM always to $40000
                  -- So we re-map this write to $4xxxx
                  temp_address(27 downto 16) := x"004";
                  temp_address(15 downto 0)  := resolved_vdc_to_viciv_address;
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
            if ocean_cart_mode='1' then
              -- Simulate $8000-$9FFF access to an Ocean Type 1 cart
              temp_address(27 downto 21) := (others => '0');
              temp_address(20 downto 13) := ocean_cart_lo_bank;
            else
              temp_address(27 downto 16) := x"7FF";
            end if;
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
            if ocean_cart_mode='1' then
              -- Simulate $8000-$9FFF access to an Ocean Type 1 cart
              temp_address(27 downto 21) := (others => '0');
              temp_address(20 downto 13) := ocean_cart_hi_bank;
            else
              -- ULTIMAX mode or cartridge external ROM
              temp_address(27 downto 16) := x"7FF";
            end if;
          end if;
        end if;

        -- Expose remaining address space to cartridge port in ultimax mode
        if (gated_exrom='1') and (gated_game='0') and (hypervisor_mode='0') then
          if (reg_map_low(0)='0') and (blocknum=1) then
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
        temp_address(7 downto 0) := short_address(7 downto 0);

        -- Add the map offset if required
        blocknum := to_integer(short_address(14 downto 13));
        if short_address(15)='1' then
          if reg_map_high(blocknum)='1' then
            temp_address(27 downto 20) := reg_mb_high;
            temp_address(19 downto 8)  := reg_offset_high+to_integer(short_address(15 downto 8));
            temp_address(7 downto 0)   := short_address(7 downto 0);
          end if;
        else
          if reg_map_low(blocknum)='1' then
            temp_address(27 downto 20) := reg_mb_low;
            temp_address(19 downto 8)  := reg_offset_low+to_integer(short_address(15 downto 8));
            temp_address(7 downto 0)   := short_address(7 downto 0);
            report "mapped memory address is $" & to_hstring(temp_address) severity note;
          end if;
        end if;

        -- $D030 ROM select lines:
        if hypervisor_mode = '0' then
          blocknum := to_integer(short_address(15 downto 12));
          if (blocknum=14 or blocknum=15) and (rom_at_e000='1')
            and (hypervisor_mode='0') then
            temp_address(27 downto 12) := x"003E";
            if blocknum=15 then temp_address(12) := '1'; end if;
          end if;
          if (blocknum=12) and rom_at_c000='1' and (hypervisor_mode='0') then
            temp_address(27 downto 12) := x"002C";
          end if;
          if (blocknum=10 or blocknum=11) and (rom_at_a000='1')
            and (hypervisor_mode='0') then
            temp_address(27 downto 12) := x"003A";
            if blocknum=11 then temp_address(12) := '1'; end if;
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
          temp_address(16)           := temp_address(0); -- odd/even bitplane bank select
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

        -- CPU ports at $0000/$0001: map to fastio interface
        if temp_address = x"0000000" or temp_address = x"0000001" then
          temp_address(27 downto 20) := x"FF";
        end if;

        return temp_address;
      end resolve_address_to_long;

      -- purpose: set processor flags from a byte (eg for PLP or RTI)
      procedure load_processor_flags (
          value : in unsigned(7 downto 0)) is
      begin -- load_processor_flags
        flag_n <= value(7);
        flag_v <= value(6);
        -- C65/4502 specifications says that E is not set by PLP, only by SEE/CLE
        flag_d <= value(3);
        flag_i <= value(2);
        flag_z <= value(1);
        flag_c <= value(0);
      end procedure load_processor_flags;

      -- purpose: change memory map, C65-style
      procedure c65_map_instruction is
        variable offset : unsigned(15 downto 0) := x"0000";
      begin
        -- c65_map_instruction
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
        reg_map_low    <= std_logic_vector(reg_x(7 downto 4));
        -- Lock the upper 32KB memory map when in hypervisor mode, so that nothing
        -- can accidentally de-map it.  This will hopefully also fix using OpenROMs
        -- with megaflash menu during boot (issue #156)
        if hypervisor_mode='0' then
          reg_offset_high <= reg_z(3 downto 0) & reg_y;
          reg_map_high    <= std_logic_vector(reg_z(7 downto 4));
        end if;

        -- Inhibit all interrupts until EOM (opcode $EA, which used to be NOP)
        -- is executed.
        map_interrupt_inhibit <= '1';

        -- Flush ZP/stack cache because memory map may have changed
        cache_flushing      <= '1';
        cache_flush_counter <= (others => '0');
      end c65_map_instruction;

      procedure dmagic_reset_options is
      begin
        reg_dmagic_use_transparent_value <= '0';
        reg_dmagic_src_mb                <= x"00";
        reg_dmagic_dst_mb                <= x"00";
        reg_dmagic_transparent_value     <= x"00";
        reg_dmagic_src_skip              <= x"0100";
        reg_dmagic_dst_skip              <= x"0100";
        reg_dmagic_x8_offset             <= x"0000";
        reg_dmagic_y8_offset             <= x"0000";
        reg_dmagic_slope                 <= x"0000";
        reg_dmagic_slope_fraction_start  <= to_unsigned(0,17);
        reg_dmagic_line_slope_negative   <= '0';
        dmagic_slope_overflow_toggle     <= '0';
        reg_dmagic_line_mode             <= '0';
        reg_dmagic_line_x_or_y           <= '0';
      end procedure;

      impure function alu_op_add (
          i1           : in unsigned(7 downto 0);
          i2           : in unsigned(7 downto 0);
          carry_in     :    std_logic;
          decimal_mode : in std_logic) return unsigned is
        -- Result is NVZC<8bit result>
        variable tmp : unsigned(11 downto 0) := x"000";
      begin
        if decimal_mode='1' then
          tmp(8)          := '0';
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
          if (i1 + i2 + ( "0000000" & carry_in )) = x"00" then
            report "add result SET Z";
            tmp(9) := '1'; -- Z flag
          else
            report "add result CLEAR Z (result=$"
            & to_hstring((i1 + i2 + ( "0000000" & carry_in )));
            tmp(9) := '0'; -- Z flag
          end if;
          tmp(11) := tmp(7);                                         -- N flag
          tmp(10) := (i1(7) xor tmp(7)) and (not (i1(7) xor i2(7))); -- V flag
          if tmp(8 downto 4) > "01001" then
            tmp(7 downto 0) := tmp(7 downto 0) + x"60";
            tmp(8)          := '1'; -- C flag
          end if;
        -- flag_c <= tmp(8);
        else
          tmp(8 downto 0) := ("0"&i2)
            + ("0"&i1)
            + ("00000000"&carry_in);
          tmp(7 downto 0) := tmp(7 downto 0);
          tmp(11)         := tmp(7); -- N flag
          if (tmp(7 downto 0) = x"00") then
            tmp(9)      := '1';
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

      function multiply_by_volume_coefficient( value : signed(15 downto 0);
          volume : unsigned(7 downto 0))
        return signed is
        variable value_unsigned  : unsigned(23 downto 0);
        variable result_unsigned : unsigned(31 downto 0);
        variable result          : signed(31 downto 0);
      begin

        value_unsigned(14 downto 0)  := unsigned(value(14 downto 0));
        value_unsigned(23 downto 15) := (others => value(15));

        result_unsigned := value_unsigned * volume;

        result := signed(result_unsigned);

  --      report "VOLMULT: $" & to_hstring(value) & " x $" & to_hstring(volume) & " = $ " & to_hstring(result);

        return result(23 downto 0);
      end function;

      variable virtual_reg_p : std_logic_vector(7 downto 0);
      variable temp_pc       : unsigned(15 downto 0);
      variable temp_value    : unsigned(7 downto 0);
      variable nybl          : unsigned(3 downto 0);

      variable execute_now    : std_logic := '0';
      variable execute_opcode : unsigned(7 downto 0);
      variable execute_arg1   : unsigned(7 downto 0);
      variable execute_arg2   : unsigned(7 downto 0);

      variable pc_inc     : integer range 0 to 65535 := 0;
      variable pc_set     : std_logic            := '0';
      variable pc_dec1    : std_logic            := '0';
      variable push_value : unsigned(7 downto 0) := (others => '0');

      variable temp_addr   : unsigned(15 downto 0) := (others => '0');
      variable temp_addr32 : unsigned(31 downto 0) := (others => '0');

      variable temp17 : unsigned(16 downto 0) := (others => '0');
      variable temp9  : unsigned(8 downto 0)  := (others => '0');

      variable cpu_speed : std_logic_vector(2 downto 0) := (others => '0');

      variable math_input_a_source : integer               := 0;
      variable math_input_b_source : integer               := 0;
      variable math_output_low     : integer               := 0;
      variable math_output_high    : integer               := 0;
      variable math_result         : unsigned(63 downto 0) := to_unsigned(0,64);
      variable vreg33              : unsigned(32 downto 0) := to_unsigned(0,33);

      variable audio_dma_left_temp  : signed(15 downto 0) := (others => '0');
      variable audio_dma_right_temp : signed(15 downto 0) := (others => '0');

      variable line_x_move          : std_logic := '0';
      variable line_x_move_negative : std_logic := '0';
      variable line_y_move          : std_logic := '0';
      variable line_y_move_negative : std_logic := '0';

      variable long_address : unsigned(27 downto 0);

      variable instruction_bytes_v : unsigned(47 downto 0);
      variable do_branch8 : std_logic := '0';
      variable do_branch16 : std_logic := '0';
      variable is_16bit_operation_v : std_logic := '0';

      variable var_wdata : unsigned(31 downto 0);
      variable var_sp : unsigned(15 downto 0) := x"0000";
      variable var_pc : unsigned(15 downto 0) := x"0000";

      variable var_alu_a : unsigned(7 downto 0);
      variable var_alu_a1 : unsigned(7 downto 0);
      variable var_alu_a2 : unsigned(7 downto 0);
      variable var_alu_a3 : unsigned(7 downto 0);
      variable var_alu_b : unsigned(7 downto 0);
      variable var_alu_b1 : unsigned(7 downto 0);
      variable var_alu_b2 : unsigned(7 downto 0);
      variable var_alu_r1 : unsigned(11 downto 0);
      variable var_alu_r2 : unsigned(11 downto 0);
      variable var_alu_r3 : unsigned(11 downto 0);
      variable var_alu_r4 : unsigned(11 downto 0);
      variable var_c_in : std_logic := '0';

      variable mc : microcodeops := (others => '0');
      variable var_mc : microcodeops := (others => '0');

    begin

      -- Formula Plumbing Unit (FPU), the MEGA65's answer to a traditional
      -- Floating Point Unit (FPU).
      -- The idea is simple: We have a bunch of math units, and a bunch of
      -- inputs and outputs, and a bunch of multiplexors that let you select what
      -- joins where: In short, you can plumb your own formulae directly.
      -- For each unit we have to pick one or more inputs, and set at least one
      -- output.  We will map these all onto the same 64 bytes of registers.

      if rising_edge(clock) then

        cpu_pcm_bypass  <= cpu_pcm_bypass_int;
        pwm_mode_select <= pwm_mode_select_int;

        -- We also have one direct 18x25 multiplier for use by the hypervisor.
        -- This multiplier fits a single DSP48E unit, and does not use the plumbing
        -- facility.
        -- Actually, we now offer 32x32 multiplication, as that should also be
        -- possible in a single cycle
        reg_mult_p(63 downto 0) <= reg_mult_a * reg_mult_b;

        -- We also have four more little multipliers for the audio DMA stuff
        for i in 0 to 3 loop
          if audio_dma_sample_valid(i)='1' then
            audio_dma_latched_sample(i) <= audio_dma_current_value(i);
          end if;
          audio_dma_multed(i)     <= multiply_by_volume_coefficient(audio_dma_current_value(i), audio_dma_volume(i));
          audio_dma_pan_multed(i) <= multiply_by_volume_coefficient(audio_dma_current_value(i), audio_dma_pan_volume(i));
          if audio_dma_enables(i)='0' then
            audio_dma_multed(i) <= (others => '0');
          end if;
        end loop;
        -- And from those, we compose the combined left and right values, with
        -- saturation detection
        audio_dma_left_temp := audio_dma_multed(0)(23 downto 8) + audio_dma_multed(1)(23 downto 8)
          + audio_dma_pan_multed(2)(23 downto 8) + audio_dma_pan_multed(3)(23 downto 8);
        if audio_dma_multed(0)(23) = audio_dma_multed(1)(23) and audio_dma_left_temp(15) /= audio_dma_multed(0)(23) then
          -- overflow: so saturate instead
          if audio_dma_saturation_enable='1' then
            audio_dma_left <= (others => audio_dma_multed(1)(23));
          else
            audio_dma_left <= audio_dma_left_temp;
          end if;
          audio_dma_left_saturated <= '1';
        else
          audio_dma_left           <= audio_dma_left_temp;
          audio_dma_left_saturated <= '0';
        end if;

        audio_dma_right_temp := audio_dma_multed(2)(23 downto 8) + audio_dma_multed(3)(23 downto 8)
          + audio_dma_pan_multed(0)(23 downto 8) + audio_dma_pan_multed(1)(23 downto 8);
        if audio_dma_multed(2)(23) = audio_dma_multed(3)(23) and audio_dma_right_temp(15) /= audio_dma_multed(2)(23) then
          -- overflow: so saturate instead
          if audio_dma_saturation_enable='1' then
            audio_dma_right <= (others => audio_dma_multed(3)(23));
          else
            audio_dma_right <= audio_dma_right_temp;
          end if;
          audio_dma_right_saturated <= '1';
        else
          audio_dma_right           <= audio_dma_right_temp;
          audio_dma_right_saturated <= '0';
        end if;

        resolved_vdc_to_viciv_src_address <= resolve_vdc_to_viciv_address(vdc_mem_addr_src);
        resolved_vdc_to_viciv_address     <= resolve_vdc_to_viciv_address(vdc_mem_addr);

        -- Disable all non-essential IO devices from memory map when in secure mode.
        if hyper_protected_hardware(7)='1' then
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
        math_input_value  <= reg_math_regs(math_input_counter);
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
        if reg_math_write_toggle /= last_reg_math_write_toggle then
          last_reg_math_write_toggle <= reg_math_write_toggle;
          reg_math_write             <= '1';
        end if;
        reg_math_write <= '0';
        if math_unit_flags(0) = '1' then
          if reg_math_write = '1' then
            case reg_math_regbyte is
              when 0      => reg_math_regs(reg_math_regnum)(7 downto 0)   <= reg_math_write_value;
              when 1      => reg_math_regs(reg_math_regnum)(15 downto 8)  <= reg_math_write_value;
              when 2      => reg_math_regs(reg_math_regnum)(23 downto 16) <= reg_math_write_value;
              when 3      => reg_math_regs(reg_math_regnum)(31 downto 24) <= reg_math_write_value;
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

      fastio_rdata <= (others => 'Z');
      if fastio_read = '1' Then
        if fastio_addr = x"00000" Then
          -- @IO:C64 $0000000 CPU:PORTDDR 6510/45GS10 CPU port DDR
          fastio_rdata <= cpuport_ddr;
        elsif fastio_addr = x"00001" Then
          -- @IO:C64 $0000001 CPU:PORT 6510/45GS10 CPU port data
          fastio_rdata <= cpuport_value;
        elsif fastio_addr(19 downto 8) = x"D37" Then
          -- $D7xx registers
          fastio_rdata <= read_d7xx_register(fastio_addr(7 downto 0));
        elsif hypervisor_mode='1'
           and (fastio_addr(19 downto 4) = x"D364"
           or  fastio_addr(19 downto 4) = x"D365"
           or  fastio_addr(19 downto 4) = x"D366"
           or  fastio_addr(19 downto 4) = x"D367") then
           -- $D640-$D67F hypervisor mode registers
           fastio_rdata <= read_hypervisor_register(fastio_addr(5 downto 0));
        elsif fastio_addr(19 downto 4) = x"D10A"
          or fastio_addr(19 downto 4) = x"D30A" Then
          -- CPU RAM expansion controller
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
            fastio_rdata <= x"80"; -- rec_status
         elsif fastio_addr = x"D0600" or fastio_addr = x"D1600" or fastio_addr = x"D3600" Then
           fastio_rdata <= vdc_status;
         elsif fastio_addr = x"D0601" or fastio_addr = x"D1601" or fastio_addr = x"D3601" Then
            -- Read VDC registers EXCEPT register $1F
            -- (which is handled in the address resolver, instead)
            fastio_rdata <= x"ff";
        end if;
      end if;

      -- BEGINNING OF MAIN PROCESS FOR CPU
      if rising_edge(clock) and all_pause='0' then

        var_mc := (others => '0');
        mc := (others => '0');
          
        -- Implement fastio interface for CPU-provided registers
        if fastio_write = '1' Then
          if fastio_addr = x"00000" Then
            cpuport_ddr <= fastio_wdata;
          elsif fastio_addr = x"00001" Then
            cpuport_value <= fastio_wdata;
            -- Set GeoRAM page (gets munged later with GeoRAM base and mask values
            -- provided by the hypervisor)
          elsif fastio_addr = x"d0fff" or fastio_addr = x"d1fff" or fastio_addr = x"d3fff" then
            georam_block <= fastio_wdata;
          elsif fastio_addr = x"d0fff" or fastio_addr = x"d1fff" or fastio_addr = x"d3fff" then
            georam_blockpage <= fastio_wdata;
          elsif fastio_addr = x"d0f01" or fastio_addr = x"d1f01" or fastio_addr = x"d3f01" then
            reu_cmd_autoload   <= fastio_wdata(5);
            reu_cmd_ff00decode <= fastio_wdata(4);
            reu_cmd_operation  <= std_logic_vector(fastio_wdata(1 downto 0));
            if fastio_wdata(7)='1' and fastio_wdata(4)='0' then
              -- XXX Start REU job by copying REU registers to DMAgic registers,
              -- setting REU job flag and starting the job.
            elsif fastio_wdata(7)='1' and fastio_wdata(4)='1' then
              -- XXX Defer starting REU job until $FF00 is written
              reu_ff00_pending <= '1';
            end if;
          elsif fastio_addr = x"d0f02" or fastio_addr = x"d1f02" or fastio_addr = x"d3f02" then
            reu_c64_startaddr(7 downto 0) <= fastio_wdata;
          elsif fastio_addr = x"d0f03" or fastio_addr = x"d1f03" or fastio_addr = x"d3f03" then
            reu_c64_startaddr(15 downto 8) <= fastio_wdata;
          elsif fastio_addr = x"d0f04" or fastio_addr = x"d1f04" or fastio_addr = x"d3f04" then
            reu_c64_startaddr(7 downto 0) <= fastio_wdata;
          elsif fastio_addr = x"d0f05" or fastio_addr = x"d1f05" or fastio_addr = x"d3f05" then
            reu_reu_startaddr(15 downto 8) <= fastio_wdata;
          elsif fastio_addr = x"d0f06" or fastio_addr = x"d1f06" or fastio_addr = x"d3f06" then
            reu_reu_startaddr(23 downto 16) <= fastio_wdata;
          elsif fastio_addr = x"d0f07" or fastio_addr = x"d1f07" or fastio_addr = x"d3f07" then
            reu_transfer_length(7 downto 0) <= fastio_wdata;
          elsif fastio_addr = x"d0f08" or fastio_addr = x"d1f08" or fastio_addr = x"d3f08" then
            reu_transfer_length(15 downto 8) <= fastio_wdata;
          elsif fastio_addr = x"d0f09" or fastio_addr = x"d1f09" or fastio_addr = x"d3f09" then
            reu_useless_interrupt_mask(7 downto 5) <= fastio_wdata(7 downto 5);
          elsif fastio_addr = x"d0f0a" or fastio_addr = x"d1f0a" or fastio_addr = x"d3f0a" then
            reu_hold_c64_address <= fastio_wdata(7);
            reu_hold_reu_address <= fastio_wdata(6);
          elsif fastio_addr(19 downto 8) = x"D37" Then
            -- $D7xx registers
            case fastio_addr(7 downto 0) is
              when x"00" | x"05" =>
                -- @IO:C65 $D700 DMA:ADDRLSBTRIG DMAgic DMA list address LSB, and trigger DMA (when written)
                -- @IO:GS $D705 DMA:ETRIG Set low-order byte of DMA list address, and trigger Enhanced DMA job (uses DMA option list)

                -- DMA gets triggered when we write here. That actually happens through
                -- memory_access_write.
                null;
              when x"01" =>
                -- @IO:C65 $D701 DMA:ADDRMSB DMA list address high byte (address bits 8 -- 15).
                reg_dmagic_addr(15 downto 8) <= fastio_wdata;
              when x"02" =>
                -- @IO:C65 $D702 DMA:ADDRBANK DMA list address bank (address bits 16 -- 22). Writing clears \$D704.
                reg_dmagic_addr(22 downto 16) <= fastio_wdata(6 downto 0);
                reg_dmagic_addr(27 downto 23) <= (others => '0');
                reg_dmagic_withio             <= fastio_wdata(7);
              when x"0e" =>
                -- Set low order bits of DMA list address, without starting
                -- @IO:GS $D70E DMA:ADDRLSB DMA list address low byte (address bits 0 -- 7) WITHOUT STARTING A DMA JOB (used by Hypervisor for unfreezing DMA-using tasks)
                reg_dmagic_addr(7 downto 0) <= fastio_wdata;
              when x"03" =>
                -- @IO:GS $D703.0 DMA:EN018B DMA enable F018B mode (adds sub-command byte)
                support_f018b <= fastio_wdata(0);
              when x"04" =>
                -- @IO:GS $D704 DMA:ADDRMB DMA list address mega-byte
                reg_dmagic_addr(27 downto 20) <= fastio_wdata;
              when x"10" =>
                -- @IO:GS $D710.0 - CPU:BADLEN Enable badline emulation
                -- @IO:GS $D710.1 - CPU:SLIEN Enable 6502-style slow (7 cycle) interrupts
                -- @IO:GS $D710.2 - MISC:VDCSEN Enable VDC inteface simulation
                badline_enable  <= fastio_wdata(0);
                slow_interrupts <= fastio_wdata(1);
                vdc_enabled     <= fastio_wdata(2);
                -- @IO:GS $D710.3 CPU:BRCOST 1=charge extra cycle(s) for branches taken
                charge_for_branches_taken <= fastio_wdata(3);
                -- @IO:GS $D710.4-5 CPU:BADEXTRA Cost of badlines minus 40. ie. 00=40 cycles, 11 = 43 cycles.
                badline_extra_cycles <= fastio_wdata(5 downto 4);
              when x"11" =>
                audio_dma_enable         <= fastio_wdata(7);
                audio_dma_disable_writes <= fastio_wdata(5);
                cpu_pcm_bypass_int       <= fastio_wdata(4);
                pwm_mode_select_int      <= fastio_wdata(3);
              when x"12" =>
                audio_dma_swap              <= fastio_wdata(1);
                audio_dma_saturation_enable <= fastio_wdata(0);
              when x"1C" =>
                audio_dma_pan_volume(0) <= fastio_wdata;
              when x"1D" =>
                audio_dma_pan_volume(1) <= fastio_wdata;
              when x"1E" =>
                audio_dma_pan_volume(2) <= fastio_wdata;
              when x"1F" =>
                audio_dma_pan_volume(3) <= fastio_wdata;
              when x"20" | x"21" | x"22" | x"23" | x"24" | x"25" | x"26" | x"27" |
                   x"28" | x"29" | x"2A" | x"2B" | x"2C" | x"2D" | x"2E" | x"2F" |
                   x"30" | x"31" | x"32" | x"33" | x"34" | x"35" | x"36" | x"37" |
                   x"38" | x"39" | x"3A" | x"3B" | x"3C" | x"3D" | x"3E" | x"3F" |
                   x"40" | x"41" | x"42" | x"43" | x"44" | x"45" | x"46" | x"47" |
                   x"48" | x"49" | x"4A" | x"4B" | x"4C" | x"4D" | x"4E" | x"4F" |
                   x"50" | x"51" | x"52" | x"53" | x"54" | x"55" | x"56" | x"57" |
                   x"58" | x"59" | x"5A" | x"5B" | x"5C" | x"5D" | x"5E" | x"5F" =>
                case fastio_addr(3 downto 0) is
                  -- We put this one first, so that writing linearly will correctly
                  -- initialise things when freezing and unfreezing
                  when x"0" =>
                    audio_dma_enables(to_integer(fastio_addr(7 downto 4)-2)) <= fastio_wdata(7);
                    audio_dma_repeat(to_integer(fastio_addr(7 downto 4)-2))       <= fastio_wdata(6);
                    audio_dma_signed(to_integer(fastio_addr(7 downto 4)-2))       <= fastio_wdata(5);
                    audio_dma_sine_wave(to_integer(fastio_addr(7 downto 4)-2))    <= fastio_wdata(4);
                    audio_dma_stop(to_integer(fastio_addr(7 downto 4)-2))         <= fastio_wdata(3);
                    audio_dma_sample_width(to_integer(fastio_addr(7 downto 4)-2)) <= fastio_wdata(1 downto 0);
                    report "Setting Audio DMA channel "
                    & integer'image(to_integer(fastio_addr(7 downto 4)-2)) &
                    " flags to $" & to_hstring(fastio_wdata);
                  when x"1" => audio_dma_base_addr(to_integer(fastio_addr(7 downto 4)-2))(7 downto 0)   <= fastio_wdata;
                  when x"2" => audio_dma_base_addr(to_integer(fastio_addr(7 downto 4)-2))(15 downto 8)  <= fastio_wdata;
                  when x"3" => audio_dma_base_addr(to_integer(fastio_addr(7 downto 4)-2))(23 downto 16) <= fastio_wdata;
                  when x"4" => audio_dma_time_base(to_integer(fastio_addr(7 downto 4)-2))(7 downto 0)   <= fastio_wdata;
                  when x"5" => audio_dma_time_base(to_integer(fastio_addr(7 downto 4)-2))(15 downto 8)  <= fastio_wdata;
                  when x"6" => audio_dma_time_base(to_integer(fastio_addr(7 downto 4)-2))(23 downto 16) <= fastio_wdata;
                    report "Setting Audio DMA channel " & integer'image(to_integer(fastio_addr(7 downto 4)-2))
                    & " <time_base to $" & to_hstring(fastio_wdata);
                  when x"7" => audio_dma_top_addr(to_integer(fastio_addr(7 downto 4)-2))(7 downto 0)  <= fastio_wdata;
                  when x"8" => audio_dma_top_addr(to_integer(fastio_addr(7 downto 4)-2))(15 downto 8) <= fastio_wdata;
                    report "Setting Audio DMA channel " & integer'image(to_integer(fastio_addr(7 downto 4)-2))
                    & " <top_addr to $" & to_hstring(fastio_wdata);
                  when x"9" => audio_dma_volume(to_integer(fastio_addr(7 downto 4)-2))                         <= fastio_wdata;
                  when x"a" => audio_dma_current_addr_set(to_integer(fastio_addr(7 downto 4)-2))(7 downto 0)   <= fastio_wdata;
                  when x"b" => audio_dma_current_addr_set(to_integer(fastio_addr(7 downto 4)-2))(15 downto 8)  <= fastio_wdata;
                  when x"c" => audio_dma_current_addr_set(to_integer(fastio_addr(7 downto 4)-2))(23 downto 16) <= fastio_wdata;
                    audio_dma_current_addr_set_flag(to_integer(fastio_addr(7 downto 4)-2))
                    <= not audio_dma_current_addr_set_flag(to_integer(fastio_addr(7 downto 4)-2));
                  when x"d" => audio_dma_timing_counter_set(to_integer(fastio_addr(7 downto 4)-2))(7 downto 0)   <= fastio_wdata;
                  when x"e" => audio_dma_timing_counter_set(to_integer(fastio_addr(7 downto 4)-2))(15 downto 8)  <= fastio_wdata;
                  when x"f" => audio_dma_timing_counter_set(to_integer(fastio_addr(7 downto 4)-2))(23 downto 16) <= fastio_wdata;
                    audio_dma_timing_counter_set_flag(to_integer(fastio_addr(7 downto 4)-2))
                    <= not audio_dma_timing_counter_set_flag(to_integer(fastio_addr(7 downto 4)-2));
                  when others => null;
                end case;
              -- @IO:GS $D770-3 32-bit multiplier input A
              when x"70" =>
                reg_mult_a(7 downto 0) <= fastio_wdata;
                div_n(7 downto 0)      <= fastio_wdata;
                div_start_over         <= '1';
              when x"71" =>
                reg_mult_a(15 downto 8) <= fastio_wdata;
                div_n(15 downto 8)      <= fastio_wdata;
                div_start_over          <= '1';
              when x"72" =>
                reg_mult_a(23 downto 16) <= fastio_wdata;
                div_n(23 downto 16)      <= fastio_wdata;
                div_start_over           <= '1';
              when x"73" =>
                reg_mult_a(31 downto 24) <= fastio_wdata;
                div_n(31 downto 24)      <= fastio_wdata;
                div_start_over           <= '1';
              -- @IO:GS $D774-7 32-bit multiplier input B
              when x"74" =>
                reg_mult_b(7 downto 0) <= fastio_wdata;
                div_d(7 downto 0)      <= fastio_wdata;
                div_start_over         <= '1';
              when x"75" =>
                reg_mult_b(15 downto 8) <= fastio_wdata;
                div_d(15 downto 8)      <= fastio_wdata;
                div_start_over          <= '1';
              when x"76" =>
                reg_mult_b(23 downto 16) <= fastio_wdata;
                div_d(23 downto 16)      <= fastio_wdata;
                div_start_over           <= '1';
              when x"77" =>
                reg_mult_b(31 downto 24) <= fastio_wdata;
                div_d(31 downto 24)      <= fastio_wdata;
                div_start_over           <= '1';
              when x"80" | x"81" | x"82" | x"83" | x"84" | x"85" | x"86" | x"87" |
                   x"88" | x"89" | x"8A" | x"8B" | x"8C" | x"8D" | x"8E" | x"8F" |
                   x"90" | x"91" | x"92" | x"93" | x"94" | x"95" | x"96" | x"97" |
                   x"98" | x"99" | x"9A" | x"9B" | x"9C" | x"9D" | x"9E" | x"9F" |
                   x"A0" | x"A1" | x"A2" | x"A3" | x"A4" | x"A5" | x"A6" | x"A7" |
                   x"A8" | x"A9" | x"AA" | x"AB" | x"AC" | x"AD" | x"AE" | x"AF" |
                   x"B0" | x"B1" | x"B2" | x"B3" | x"B4" | x"B5" | x"B6" | x"B7" |
                   x"B8" | x"B9" | x"BA" | x"BB" | x"BC" | x"BD" | x"BE" | x"BF" =>
                -- Math unit register writing
                reg_math_write_toggle <= not reg_math_write_toggle;
                reg_math_regnum       <= to_integer(fastio_addr(5 downto 2));
                reg_math_regbyte      <= to_integer(fastio_addr(1 downto 0));
                reg_math_write_value  <= fastio_wdata;
              when x"C0" | x"C1" | x"C2" | x"C3" | x"C4" | x"C5" | x"C6" | x"C7" |
                   x"C8" | x"C9" | x"CA" | x"CB" | x"CC" | x"CD" | x"CE" | x"CF" =>
                -- Math unit input select registers
                reg_math_config(to_integer(fastio_addr(3 downto 0))).source_a <= to_integer(fastio_wdata(3 downto 0));
                reg_math_config(to_integer(fastio_addr(3 downto 0))).source_b <= to_integer(fastio_wdata(7 downto 4));
              when x"D0" | x"D1" | x"D2" | x"D3" | x"D4" | x"D5" | x"D6" | x"D7" |
                   x"D8" | x"D9" | x"DA" | x"DB" | x"DC" | x"DD" | x"DE" | x"DF" =>
                -- Math unit input select registers
                reg_math_config(to_integer(fastio_addr(3 downto 0))).latched     <= fastio_wdata(7);
                reg_math_config(to_integer(fastio_addr(3 downto 0))).do_add      <= fastio_wdata(6);
                reg_math_config(to_integer(fastio_addr(3 downto 0))).output_high <= fastio_wdata(5);
                reg_math_config(to_integer(fastio_addr(3 downto 0))).output_low  <= fastio_wdata(4);
                reg_math_config(to_integer(fastio_addr(3 downto 0))).output      <= to_integer(fastio_wdata(3 downto 0));
              when x"E0" =>
                -- @IO:GS $D7E0 - Math unit latch interval (only update output of math function units every this many cycles, if they have the latch output flag set)
                reg_math_latch_interval <= fastio_wdata;
              when x"E1" =>
                -- @IO:GS $D7E1 - Math unit general settings (writing also clears math cycle counter)
                -- @IO:GS $D7E1.0 MATH:WREN Enable setting of math registers (must normally be set)
                -- @IO:GS $D7E1.1 MATH:CALCEN Enable committing of output values from math units back to math registers (clearing effectively pauses iterative formulae)
                math_unit_flags        <= fastio_wdata;
                reg_math_cycle_counter <= to_unsigned(0,32);
              when x"E8" =>
                reg_math_cycle_compare(7 downto 0) <= fastio_wdata;
              when x"E9" =>
                reg_math_cycle_compare(15 downto 8) <= fastio_wdata;
              when x"EA" =>
                reg_math_cycle_compare(23 downto 16) <= fastio_wdata;
              when x"EB" =>
                reg_math_cycle_compare(31 downto 24) <= fastio_wdata;
              when x"FB" =>
                -- @IO:GS $D7FB.1 CPU:CARTEN 1= enable cartridges
                cartridge_enable <= fastio_wdata(1);
              when x"FC" =>
                -- @IO:GS $D7FC DEBUG chip-select enables for various devices
                --        chipselect_enables <= std_logic_vector(value);
              when x"FD" =>
                -- @IO:GS $D7FD.7 CPU:NOEXROM Override for /EXROM : Must be 0 to enable /EXROM signal
                -- @IO:GS $D7FD.6 CPU:NOGAME Override for /GAME : Must be 0 to enable /GAME signal
                -- @IO:GS $D7FD.0 CPU:POWEREN Set to zero to power off computer on supported systems. WRITE ONLY.
                force_exrom <= fastio_wdata(7);
                force_game  <= fastio_wdata(6);
                power_down  <= fastio_wdata(0);
              when x"FE" =>
                -- @IO:GS $D7FE.1 CPU:OCEANA Enable Ocean Type A cartridge emulation
                ocean_cart_mode <= fastio_wdata(1);
              when others => null;
            end case;
          elsif hypervisor_mode='1'
            and (fastio_addr(19 downto 4) = x"D364"
            or  fastio_addr(19 downto 4) = x"D365"
            or  fastio_addr(19 downto 4) = x"D366"
            or  fastio_addr(19 downto 4) = x"D367") then
            -- $D640-$D67F hypervisor mode registers
--            write_hypervisor_register(to_integer(fastio_addr(5 downto 0), fastio_wdata));
            case fastio_addr(7 downto 0) is
              -- @IO:GS $D640 HCPU:REGA Hypervisor A register storage
              when x"40" => hyper_a <= last_value;
              -- @IO:GS $D641 HCPU:REGX Hypervisor X register storage
              when x"41" => hyper_x <= last_value;
              -- @IO:GS $D642 HCPU_REGY Hypervisor Y register storage
              when x"42" => hyper_y <= last_value;
              -- @IO:GS $D643 HCPU:REGZ Hypervisor Z register storage
              when x"43" => hyper_z <= last_value;
              -- @IO:GS $D644 HCPU:REGB Hypervisor B register storage
              when x"44" => hyper_b <= last_value;
              -- @IO:GS $D645 HCPU:SPL Hypervisor SPL register storage
              when x"45" => hyper_sp <= last_value;
              -- @IO:GS $D646 HCPU:SPH Hypervisor SPH register storage
              when x"46" => hyper_sph <= last_value;
              -- @IO:GS $D647 HCPU:PFLAGS Hypervisor P register storage
              when x"47" => hyper_p <= last_value;
              -- @IO:GS $D648 HCPU:PCL Hypervisor PC-low register storage
              when x"48" => hyper_pc(7 downto 0) <= last_value;
              -- @IO:GS $D649 HCPU:PCH Hypervisor PC-high register storage
              when x"49" => hyper_pc(15 downto 8) <= last_value;
              -- @IO:GS $D64A HCPU:MAPLO Hypervisor MAPLO register storage (high bits)
              when x"4A" =>
                hyper_map_low                     <= std_logic_vector(last_value(7 downto 4));
                  hyper_map_offset_low(11 downto 8) <= last_value(3 downto 0);
              -- @IO:GS $D64B HCPU:MAPLO Hypervisor MAPLO register storage (low bits)
              when x"4B" => hyper_map_offset_low(7 downto 0) <= last_value;
              -- @IO:GS $D64C HCPU:MAPHI Hypervisor MAPHI register storage (high bits)
              when x"4C" =>
                hyper_map_high                     <= std_logic_vector(last_value(7 downto 4));
                  hyper_map_offset_high(11 downto 8) <= last_value(3 downto 0);
              -- @IO:GS $D64D HCPU:MAPHI Hypervisor MAPHI register storage (low bits)
              when x"4D" => hyper_map_offset_high(7 downto 0) <= last_value;
              -- @IO:GS $D64E HCPU:MAPLOMB Hypervisor MAPLO mega-byte number register storage
              when x"4E" => hyper_mb_low <= last_value;
              -- @IO:GS $D64F HCPU:MAPHIMB Hypervisor MAPHI mega-byte number register storage
              when x"4F" => hyper_mb_high <= last_value;
              -- @IO:GS $D650 HCPU:PORT00 Hypervisor CPU port \$00 value
              when x"50" => hyper_port_00 <= last_value;
              -- @IO:GS $D651 HCPU:PORT01 Hypervisor CPU port \$01 value
              when x"51" => hyper_port_01 <= last_value;
              -- @IO:GS $D652 - Hypervisor VIC-IV IO mode
              -- @IO:GS $D652.0-1 HCPU:VICMODE VIC-II/VIC-III/VIC-IV mode select
              -- @IO:GS $D652.2 HCPU:EXSID 0=Use internal SIDs, 1=Use external(1) SIDs
              when x"52" => hyper_iomode <= last_value;
              -- @IO:GS $D653 HCPU:DMASRCMB Hypervisor DMAgic source MB
              when x"53" => hyper_dmagic_src_mb <= last_value;
              -- @IO:GS $D654 HCPU:DMADSTMB Hypervisor DMAgic destination MB
              when x"54" => hyper_dmagic_dst_mb <= last_value;
              -- @IO:GS $D655 HCPU:DMALADDR Hypervisor DMAGic list address bits 0-7
              when x"55" => hyper_dmagic_list_addr(7 downto 0) <= last_value;
              -- @IO:GS $D656 HCPU:DMALADDR Hypervisor DMAGic list address bits 15-8
              when x"56" => hyper_dmagic_list_addr(15 downto 8) <= last_value;
              -- @IO:GS $D657 HCPU:DMALADDR Hypervisor DMAGic list address bits 23-16
              when x"57" => hyper_dmagic_list_addr(23 downto 16) <= last_value;
              -- @IO:GS $D658 HCPU:DMALADDR Hypervisor DMAGic list address bits 27-24
              when x"58" => hyper_dmagic_list_addr(27 downto 24) <= last_value(3 downto 0);
              -- @IO:GS $D659 - Hypervisor virtualise hardware flags
              -- @IO:GS $D659.0 HCPU:VFLOP 1=Virtualise SD/Floppy0 access (usually for access via serial debugger interface)
              -- @IO:GS $D659.1 HCPU:VFLOP 1=Virtualise SD/Floppy1 access (usually for access via serial debugger interface)
              when x"59" =>
                virtualise_sd0 <= last_value(0);
                virtualise_sd1 <= last_value(1);
              -- @IO:GS $D65D - Hypervisor current virtual page number (low byte)
              when x"5D" =>
                reg_pagenumber(1 downto 0) <= last_value(7 downto 6);
                reg_pageactive             <= last_value(4);
                reg_pages_dirty            <= std_logic_vector(last_value(3 downto 0));
              -- @IO:GS $D65E - Hypervisor current virtual page number (mid byte)
              when x"5E" => reg_pagenumber(9 downto 2) <= last_value;
              -- @IO:GS $D65F - Hypervisor current virtual page number (high byte)
              when x"5F" => reg_pagenumber(17 downto 10) <= last_value;
              -- @IO:GS $D660 - Hypervisor virtual memory page 0 logical page low byte
              -- @IO:GS $D661 - Hypervisor virtual memory page 0 logical page high byte
              -- @IO:GS $D662 - Hypervisor virtual memory page 0 physical page low byte
              -- @IO:GS $D663 - Hypervisor virtual memory page 0 physical page high byte
              when x"60" => reg_page0_logical(7 downto 0) <= last_value;
              when x"61" => reg_page0_logical(15 downto 8) <= last_value;
              when x"62" => reg_page0_physical(7 downto 0) <= last_value;
              when x"63" => reg_page0_physical(15 downto 8) <= last_value;
              -- @IO:GS $D664 - Hypervisor virtual memory page 1 logical page low byte
              -- @IO:GS $D665 - Hypervisor virtual memory page 1 logical page high byte
              -- @IO:GS $D666 - Hypervisor virtual memory page 1 physical page low byte
              -- @IO:GS $D667 - Hypervisor virtual memory page 1 physical page high byte
              when x"64" => reg_page1_logical(7 downto 0) <= last_value;
              when x"65" => reg_page1_logical(15 downto 8) <= last_value;
              when x"66" => reg_page1_physical(7 downto 0) <= last_value;
              when x"67" => reg_page1_physical(15 downto 8) <= last_value;
              -- @IO:GS $D668 - Hypervisor virtual memory page 2 logical page low byte
              -- @IO:GS $D669 - Hypervisor virtual memory page 2 logical page high byte
              -- @IO:GS $D66A - Hypervisor virtual memory page 2 physical page low byte
              -- @IO:GS $D66B - Hypervisor virtual memory page 2 physical page high byte
              when x"68" => reg_page2_logical(7 downto 0) <= last_value;
              when x"69" => reg_page2_logical(15 downto 8) <= last_value;
              when x"6A" => reg_page2_physical(7 downto 0) <= last_value;
              when x"6B" => reg_page2_physical(15 downto 8) <= last_value;
              -- @IO:GS $D66C - Hypervisor virtual memory page 3 logical page low byte
              -- @IO:GS $D66D - Hypervisor virtual memory page 3 logical page high byte
              -- @IO:GS $D66E - Hypervisor virtual memory page 3 physical page low byte
              -- @IO:GS $D66F - Hypervisor virtual memory page 3 physical page high byte
              when x"6C" => reg_page3_logical(7 downto 0) <= last_value;
              when x"6D" => reg_page3_logical(15 downto 8) <= last_value;
              when x"6E" => reg_page3_physical(7 downto 0) <= last_value;
              when x"6F" => reg_page3_physical(15 downto 8) <= last_value;
              -- @IO:GS $D670 HCPU:GEORAMBASE Hypervisor GeoRAM base address (x MB)
              when x"70" => georam_page(19 downto 12) <= last_value;
              -- @IO:GS $D671 HCPU:GEORAMMASK Hypervisor GeoRAM address mask (applied to GeoRAM block register)
              when x"71" => georam_blockmask <= last_value;
              -- @IO:GS $D672 - Protected Hardware configuration
              -- @IO:GS $D672.6 HCPU:MATRIXEN Enable composited Matrix Mode, and disable UART access to serial monitor.
              when x"72" =>
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
              -- @IO:GS $D67C.0-7 HCPU:UARTDATA (write) Hypervisor write serial output to UART monitor
              when x"7C" =>
                monitor_char                 <= last_value;
                monitor_char_toggle          <= monitor_char_toggle_internal;
                monitor_char_toggle_internal <= not monitor_char_toggle_internal;
                -- It can take hundreds of cycles before the serial monitor interface asserts
                -- its busy flag, so we have an internal flag we assert until the monitor
                -- interface asserts its.
                immediate_monitor_char_busy <= '1';
              -- @IO:GS $D67D.0 HCPU:RSVD RESERVED
              -- @IO:GS $D67D.1 HCPU:JMP32EN Hypervisor enable 32-bit JMP/JSR etc
              -- @IO:GS $D67D.2 HCPU:ROMPROT Hypervisor write protect C65 ROM \$20000-\$3FFFF
              -- @IO:GS $D67D.3 HCPU:ASCFAST Hypervisor enable ASC/DIN CAPS LOCK key to enable/disable CPU slow-down in C64/C128/C65 modes
              -- @IO:GS $D67D.4 HCPU:CPUFAST Hypervisor force CPU to 48MHz for userland (userland can override via POKE0)
              -- @IO:GS $D67D.5 HCPU:F4502 Hypervisor force CPU to 4502 personality, even in C64 IO mode.
              -- @IO:GS $D67D.6 HCPU:PIRQ Hypervisor flag to indicate if an IRQ is pending on exit from the hypervisor / set 1 to force IRQ/NMI deferal for 1,024 cycles on exit from hypervisor.
              -- @IO:GS $D67D.7 HCPU:PNMI Hypervisor flag to indicate if an NMI is pending on exit from the hypervisor.
              -- @IO:GS $D67D HCPU:WATCHDOG Hypervisor watchdog register: writing any value clears the watch dog
              when x"7D" =>
                flat32_enabled             <= last_value(1);
                rom_writeprotect           <= last_value(2);
                speed_gate_enable          <= last_value(3);
                speed_gate_enable_internal <= last_value(3);
                force_fast                 <= last_value(4);
                force_4502                 <= last_value(5);
                irq_defer_request          <= last_value(6);
                nmi_pending                <= last_value(7);
                report "irq_pending, nmi_pending <= " & std_logic'image(last_value(6))
                       & "," & std_logic'image(last_value(7));
                watchdog_fed <= '1';
              -- @IO:GS $D67E HCPU:HICKED Hypervisor already-upgraded bit (writing sets permanently)
              when x"7E" =>
                hypervisor_upgraded <= '1';
              when others => null;
            end case;
          elsif fastio_addr(19 downto 4) = x"D10A"
            or fastio_addr(19 downto 4) = x"D30A" Then
            -- CPU RAM expansion controller
            case fastio_addr(3 downto 0) is
              when x"0" => null; -- rec_status;
              when others => null;
            end case;
          elsif fastio_addr = x"D0600" or fastio_addr = x"D1600" or fastio_addr = x"D3600" Then
            vdc_reg_num <= fastio_wdata;
          elsif fastio_addr = x"D0601" or fastio_addr = x"D1601" or fastio_addr = x"D3601" Then
            -- Write VDC registers EXCEPT register $1F
            -- (which is handled in the address resolver, instead)
            case vdc_reg_num is
              when x"12" =>
                vdc_mem_addr(15 downto 8) <= fastio_wdata;
              when x"13" =>
                vdc_mem_addr(7 downto 0) <= fastio_wdata;
              when x"20" =>
                vdc_mem_addr_src(15 downto 8) <= fastio_wdata;
              when x"21" =>
                vdc_mem_addr_src(7 downto 0) <= fastio_wdata;
              when x"1E" =>
                vdc_word_count(7 downto 0) <= fastio_wdata;
              when others =>
                null;
            end case;
          end if;
        end if;

        -- By default no memory access
        memory_access_read       := '0';
        memory_access_write      := '0';
        memory_access_byte_count := 1;
        memory_access_set_address_based_on_addressingmode := '0';
        -- And not requesting an instruction be fetched
        fetch_instruction_please := '0';
          
        -- And no ALU op
        mc  := (others => '0');

        -- Fiddling with IEC lines (either by us, or by a connected device)
        -- cancels POKe0,65 / holding CAPS LOCK to force full CPU speed.
        -- If you set the 40MHz select register, then the slowdown doesn't
        -- apply, as the programmer is assumed to know what they are doing.
        if iec_bus_active='1' then
          iec_bus_slowdown <= '1';
          iec_bus_cooldown <= 40000;
        elsif iec_bus_cooldown /= 0 then
          iec_bus_cooldown <= iec_bus_cooldown - 1;
        else
          iec_bus_slowdown <= '0';
        end if;

        if hyper_protected_hardware(7)='1' then
          cartridge_enable <= '0';
        end if;

        div_start_over <= '0';

        -- By default try to service pending background DMA requests.
        -- Only if the shadow RAM bus is idle, do we actually do the request,
        -- however.
        shadow_write <= '0';

        -- XXX If CPU is not at 40MHz, then we cannot set pending_dma_address here,
        -- or CPU reads background DMA data in place of instruction arguments
        if cpuspeed_internal = x"40" then
          shadow_address        <= to_integer(pending_dma_address);
        else
          shadow_address <= shadow_address_next;
        end if;
        report "BACKGROUNDDMA: pending_dma_address=$" & to_hstring(pending_dma_address);

        if audio_dma_swap='0' then
          cpu_pcm_left  <= audio_dma_left;
          cpu_pcm_right <= audio_dma_right;
        else
          cpu_pcm_left  <= audio_dma_right;
          cpu_pcm_right <= audio_dma_left;
        end if;
        cpu_pcm_enable <= audio_dma_enable;

  --      report "CPU PCM: $" & to_hstring(audio_dma_left) & " + $" & to_hstring(audio_dma_right)
  --      & ", sample valids=" & to_string(audio_dma_sample_valid);

        -- Process result of background DMA
        -- Note: background DMA can ONLY access the shadow RAM, and can happen
        -- while non-shadow RAM accesses are happening, e.g., on the fastio bus.
        -- Thus we have to read shadow_rdata directly.
        report "BACKGROUNDDMA: Read byte $" & to_hstring(shadow_rdata)
        & ", pending_dma_target = " & integer'image(pending_dma_target);

        -- XXX Rework background audio DMA to use new memory transaction model
        -- (We can do 8/16 bit fetches identically, because new memory transaction
        -- model allows multi-byte transactions).
        if pending_dma_target /= 0 then
          report "BACKGROUNDDMA: Read byte $" & to_hstring(shadow_rdata) & " for target " & integer'image(pending_dma_target)
          & " from address $" & to_hstring(pending_dma_address);
          pending_dma_target <= 0 ;
          report "BACKGROUNDDMA: Set target to 0";
          if pending_dma_target /= 0 then
            audio_dma_write_counter <= audio_dma_write_counter + 1;
          end if;

          audio_dma_tick_counter <= audio_dma_tick_counter + 1;

          case pending_dma_target is
            when 0 => -- no pending job
              null;
            when 1 | 2 | 3 | 4 => -- Audio DMA
              case audio_dma_sample_width((pending_dma_target - 1)) is
                when "00" =>
                  -- Lower nybl
                  audio_dma_current_value((pending_dma_target - 1))(14 downto 12) <= signed(transaction_rdata(2 downto 0));
                  audio_dma_current_value((pending_dma_target - 1))(11 downto 0)  <= (others => '0');
                  audio_dma_current_value((pending_dma_target - 1))(15)           <= transaction_rdata(3) xor audio_dma_signed((pending_dma_target - 1));
                when "01" =>
                  -- Upper nybl
                  audio_dma_current_value((pending_dma_target - 1))(14 downto 12) <= signed(transaction_rdata(6 downto 4));
                  audio_dma_current_Value((pending_dma_target - 1))(11 downto 0)  <= (others => '0');
                  audio_dma_current_value((pending_dma_target - 1))(15)           <= transaction_rdata(7) xor audio_dma_signed((pending_dma_target - 1));
                when "10" =>
                  -- 8 or 16 bit sample
                  audio_dma_current_value((pending_dma_target - 1))(14 downto 8) <= signed(transaction_rdata(6 downto 0));
                  audio_dma_current_value((pending_dma_target - 1))(15)          <= transaction_rdata(7) xor audio_dma_signed((pending_dma_target - 1));
                when "11" =>
                  audio_dma_current_value((pending_dma_target - 1))(14 downto 0) <= signed(transaction_rdata(14 downto 0));
                  audio_dma_current_value((pending_dma_target - 1))(15)          <= transaction_rdata(15) xor audio_dma_signed((pending_dma_target - 1));
                when others => null;
              end case;
              audio_dma_sample_valid((pending_dma_target - 1)) <= '1';
              audio_dma_pending((pending_dma_target - 1))      <= '0';
          end case;
          pending_dma_busy <= '0';
        end if;
        if pending_dma_busy='0' then
          for i in 0 to 3 loop
            if audio_dma_pending(i)='1' then
              audio_dma_pending(i) <= '0';
              audio_dma_current_addr(i) <= audio_dma_current_addr(i) + 1;
              report "audio_dma_current_value: scheduling read of $" & to_hstring(audio_dma_current_addr(i));
              pending_dma_busy <= '1';
              report "BACKGROUNDDMA: Set target to 2";
              pending_dma_target <= i + 1;
              pending_dma_address(27 downto 0) <= (others => '0');
              pending_dma_address(23 downto 0) <= audio_dma_current_addr(0);
              exit;
            end if;
          end loop;
        end if;

        for i in 0 to 3 loop
          if audio_dma_enables(i)='0' then
            if false then
              report "Audio DMA channel " & integer'image(i) & " disabled: ";
              report "Audio DMA channel " & integer'image(i)
              & " base=$" & to_hstring(audio_dma_base_addr(i));
              report "Audio DMA channel " & integer'image(i)
              & ", top_addr=$" & to_hstring(audio_dma_top_addr(i));
              report "Audio DMA channel " & integer'image(i)
              & ", timebase=$" & to_hstring(audio_dma_time_base(i));
              report "Audio DMA channel " & integer'image(i)
              & ", current_addr=$" & to_hstring(audio_dma_current_addr(i));
              report "Audio DMA channel " & integer'image(i)
              & ", timing_counter=$" & to_hstring(audio_dma_timing_counter(i))
              ;
              report "Audio DMA channel " & integer'image(i)
              & ", timing_counter bits = "
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(24)))
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(23)))
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(22)))
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(21)))
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(20)))
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(19)))
              ;
            end if;
          else
            if false then
              report "Audio DMA channel " & integer'image(i) & " enabled: ";
              report "Audio DMA channel " & integer'image(i)
              & " pending=$" & std_logic'image(audio_dma_pending(i));
              report "Audio DMA channel " & integer'image(i)
              & " base=$" & to_hstring(audio_dma_base_addr(i));
              report "Audio DMA channel " & integer'image(i)
              & ", top_addr=$" & to_hstring(audio_dma_top_addr(i));
              report "Audio DMA channel " & integer'image(i)
              & ", timebase=$" & to_hstring(audio_dma_time_base(i));
              report "Audio DMA channel " & integer'image(i)
              & ", current_addr=$" & to_hstring(audio_dma_current_addr(i));
              report "Audio DMA channel " & integer'image(i)
              & ", timing_counter=$" & to_hstring(audio_dma_timing_counter(i))
              ;
              report "Audio DMA channel " & integer'image(i)
              & ", timing_counter bits = "
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(24)))
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(23)))
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(22)))
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(21)))
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(20)))
              & std_logic'image(std_logic(audio_dma_timing_counter(i)(19)))
              ;
            end if;

            report "UPDATE timing_counter = " & integer'image(to_integer(audio_dma_timing_counter(i)(23 downto 0)))
            & ", time_base = " & integer'image(to_integer(audio_dma_time_base(i)));
            audio_dma_timing_counter(i) <= to_unsigned(to_integer(audio_dma_timing_counter(i)(23 downto 0)) + to_integer(audio_dma_time_base(i)),25);
            if audio_dma_timing_counter(i)(24) = '1' then
              report "Audio DMA channel " & integer'image(i) & " marking next sample due.";
              if audio_dma_sine_wave(i)='1' then
                -- Play pure sine wave using our 32-sample sine table.
                -- Uses bottom 4 bits of current_addr to pick the sample
                audio_dma_current_value(i)(15 downto 8) <= sine_table(to_integer(audio_dma_current_addr(i)(4 downto 0)));
                audio_dma_current_value(i)(7 downto 0)  <= sine_table(to_integer(audio_dma_current_addr(i)(4 downto 0)));
                audio_dma_sample_valid(i)               <= '1';
                audio_dma_current_addr(i)               <= audio_dma_current_addr(i) + 1;
              else
                -- Play normal sample
                audio_dma_pending(i) <= '1';
                if audio_dma_sample_width(i) = "11" then
                  audio_dma_pending_msb(i) <= '1';
                end if;
              end if;
              audio_dma_timing_counter(i)(24) <= '0';
            else
              report "Audio DMA channel " & integer'image(i) & " next sample not yet due.";
            end if;
          end if;
          if audio_dma_last_timing_counter_set_flag(i) /= audio_dma_timing_counter_set_flag(i) then
            audio_dma_last_timing_counter_set_flag(i) <= audio_dma_timing_counter_set_flag(i);
            audio_dma_timing_counter(i)               <= audio_dma_timing_counter_set(i);
          end if;
          if audio_dma_last_current_addr_set_flag(i) /= audio_dma_current_addr_set_flag(i) then
            audio_dma_last_current_addr_set_flag(i) <= audio_dma_current_addr_set_flag(i);
            audio_dma_current_addr(i)               <= audio_dma_current_addr_set(i);
          end if;
        end loop;

        if reset='1' then
          report "Holding audio_dma";
        else
          report "Resetting audio_dma";
          audio_dma_stop        <= (others => '0');
          audio_dma_pending     <= (others => '0');
          audio_dma_pending_msb <= (others => '0');
          --      audio_dma_current_addr <= (others => to_unsigned(0,24));
          audio_dma_last_current_addr_set_flag   <= (others => '0');
          audio_dma_timing_counter               <= (others => to_unsigned(0,25));
          audio_dma_last_timing_counter_set_flag <= (others => '0');
        end if;

        report "tick";

        report "BACKGROUNDDMA: Audio enables = " & to_string(audio_dma_enables);
        for i in 0 to 3 loop
          if false then
            report "Audio DMA channel " & integer'image(i) & ": "
            & "base=$" & to_hstring(audio_dma_base_addr(i))
            & ", top_addr=$" & to_hstring(audio_dma_top_addr(i))
            & ", timebase=$" & to_hstring(audio_dma_time_base(i))
            & ", current_addr=$" & to_hstring(audio_dma_current_addr(i))
            & ", timing_counter=$" & to_hstring(audio_dma_timing_counter(i))
            & ", dma_pending=" & std_logic'image(audio_dma_pending(i))
            ;
          end if;

          if audio_dma_current_addr(i)(15 downto 0) = audio_dma_top_addr(i) then
            if audio_dma_repeat(i)='1' then
              audio_dma_current_addr(i) <= audio_dma_base_addr(i);
            else
              audio_dma_stop(i) <= '1';
            end if;
          end if;
          if audio_dma_stop(i)='1' then
            audio_dma_enables(i) <= '0';
            if audio_dma_enables(i) = '1' then
              report "Stopping Audio DMA channel #" & integer'image(i);
            end if;
          end if;

          if audio_dma_enables(i)='0' then
            --        report "Audio DMA channel " & integer'image(i) & " disabled.";
            null;
          end if;
        end loop;

        if (clear_matrix_mode_toggle='1' and last_clear_matrix_mode_toggle='0')
          or (clear_matrix_mode_toggle='0' and last_clear_matrix_mode_toggle='1')
        then
          -- Turn off matrix mode once the monitor has accepted or rejected the
          -- transition, since the hypervisor isn't available to do it itself.
          -- This leaves the secure program both running and visible and able to
          -- be interacted with.
          hyper_protected_hardware(6)   <= '0';
          last_clear_matrix_mode_toggle <= clear_matrix_mode_toggle;
          -- Debug what is going wrong here, i.e., why they stay never matching
          hyper_protected_hardware(5) <= clear_matrix_mode_toggle;
          hyper_protected_hardware(4) <= last_clear_matrix_mode_toggle;
        end if;

        dat_bitplane_addresses_drive <= dat_bitplane_addresses;
        dat_offset_drive             <= dat_offset;
        dat_even_drive               <= dat_even;
        pixel_frame_toggle_drive     <= pixel_frame_toggle;
        last_pixel_frame_toggle      <= pixel_frame_toggle_drive;

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
          gated_exrom <= exrom or force_exrom;
          gated_game  <= game or force_game;
        else
          gated_exrom <= force_exrom;
          gated_game  <= force_game;
        end if;

        -- Count slow clock ticks for applying instruction-level 6502/4510 timing
        -- accuracy at 1MHz and 3.5MHz
        -- XXX Add NTSC speed emulation option as well

        phi_add_backlog <= '0';
        phi_new_backlog <= 0;
        case cpuspeed_internal is
          when x"01"  => phi_internal <= phi_1mhz;
          when x"02"  => phi_internal <= phi_2mhz;
          when x"04"  => phi_internal <= phi_3mhz;
          when others => phi_internal <= '1'; -- Full speed = 1 clock tick per cycle
        end case;
        if phi_internal = '1' then
          cycles_per_frame <= cycles_per_frame + 1;
        end if;
        if cpuspeed_internal /= x"40" and monitor_mem_attention_request_drive='0' then
          if (phi_internal='1') then
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
                  phi_pause           <= '1';
                  phi_backlog         <= 40 + to_integer(badline_extra_cycles);
                  last_badline_toggle <= badline_toggle;
                else
                  phi_backlog <= 0;
                  phi_pause   <= '0';
                end if;
              else
                -- We would have finished the back log, but we have new backlog
                -- to process
                phi_backlog <= phi_new_backlog;
                phi_pause   <= '1';
              end if;
            else
              if phi_add_backlog = '0' then
                phi_backlog <= phi_backlog - 1;
                phi_pause   <= '1';
              else
                phi_backlog <= phi_backlog - 1 + phi_new_backlog;
                phi_pause   <= '1';
              end if;
            end if;
          else
            if phi_add_backlog = '1' then
              phi_backlog <= phi_backlog + phi_new_backlog;
              phi_pause   <= '1';
            end if;
          end if;
        else
          -- Full speed - never pause
          phi_backlog <= 0;

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
          elsif io_settle_counter = x"00" then
            io_settle_delay <= '0';
            report "clearing io_settle_delay due to io_settle_counter=$00";
          else
            report "decrementing io_settle_counter from $" & to_hstring(io_settle_counter);
            io_settle_counter <= io_settle_counter - 1;
            io_settle_delay   <= '1';
          end if;
          if io_settle_trigger /= io_settle_trigger_last then
            io_settle_counter      <= x"ff";
            io_settle_trigger_last <= io_settle_trigger;
            io_settle_delay        <= '1';
          end if;

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
          hyper_trap_state   <= '0';
          hyper_trap_pending <= '1';
          if matrix_trap_in='1' then
            matrix_trap_pending <= '1';
          elsif hyper_trap_f011_read='1' then
            f011_read_trap_pending <= '1';
          elsif hyper_trap_f011_write='1' then
            f011_write_trap_pending <= '1';
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
        georam_page(5 downto 0)  <= georam_blockpage(5 downto 0);
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


        -- Allow matrix mode in hypervisor
        protected_hardware               <= hyper_protected_hardware;
        virtualised_hardware(0)          <= virtualise_sd0;
        virtualised_hardware(1)          <= virtualise_sd1;
        virtualised_hardware(7 downto 2) <= (others => '0');
        cpu_hypervisor_mode              <= hypervisor_mode;
        -- Serial monitor interface sees memory as though hypervisor mode is
        -- active, to aid debugging and ease of tool writing
        privileged_access <= monitor_mem_attention_request or hypervisor_mode;


        check_for_interrupts;

        cpu_leds <= std_logic_vector(shadow_write_flags);

        if shadow_write='1' then
          shadow_observed_write_count <= shadow_observed_write_count + 1;
        end if;

        monitor_mem_attention_request_drive <= monitor_mem_attention_request;
        monitor_mem_read_drive              <= monitor_mem_read;
        monitor_mem_write_drive             <= monitor_mem_write;
        monitor_mem_setpc_drive             <= monitor_mem_setpc;
        monitor_mem_address_drive           <= monitor_mem_address;
        monitor_mem_wdata_drive             <= monitor_mem_wdata;

        -- By default we are doing nothing new.

        -- PC remains unchanged
        pc_set := '0'; pc_inc := 0; pc_dec1 := '0';

        -- Stack address unchanged
        sp_dec := 0;
        sp_inc := 0;

        -- No memory access
        memory_access_read            := '0';
        memory_access_write           := '0';
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

        -- Catch the CPU when it goes to the next instruction if single stepping.
        if ((monitor_mem_trace_mode='0' or
            monitor_mem_trace_toggle_last /= monitor_mem_trace_toggle)
            and (monitor_mem_attention_request_drive='0'))
        -- PGS 20190510: Required for simulation to work, but breaks monitor memory
        -- access when synthesised.
        --        or ( monitor_mem_trace_toggle = 'U' or monitor_mem_attention_request_drive = 'U' )
        then
          monitor_mem_trace_toggle_last <= monitor_mem_trace_toggle;
          normal_fetch_state            <= InstructionFetch;

          -- Or select slower CPU mode if required.
          -- Test goes here so that it doesn't break the monitor interface.
          -- But the hypervisor always runs at full speed.
          if emu6502='1' then
            fast_fetch_state <= InstructionDecode6502;
          else
            fast_fetch_state <= InstructionDecode4502;
          end if;

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
          if hypervisor_mode='0' and (((speed_gate_drive='1') and ((force_fast='0')) and (fast_key='1')) or iec_bus_slowdown='1') then
            case cpu_speed is
              when "100" => -- 1mhz
                cpuspeed          <= x"01";
                cpuspeed_internal <= x"01";
              when "101" => -- 1mhz
                cpuspeed          <= x"01";
                cpuspeed_internal <= x"01";
              when "110" => -- 3.5mhz
                cpuspeed          <= x"04";
                cpuspeed_internal <= x"04";
              when "111" => -- full speed
                cpuspeed          <= x"40";
                cpuspeed_internal <= x"40";
              when "000" => -- 2mhz
                cpuspeed          <= x"02";
                cpuspeed_internal <= x"02";
              when "001" => -- full speed
                cpuspeed          <= x"40";
                cpuspeed_internal <= x"40";
              when "010" => -- 3.5mhz
                cpuspeed          <= x"04";
                cpuspeed_internal <= x"04";
              when "011" => -- full speed
                cpuspeed          <= x"40";
                cpuspeed_internal <= x"40";
              when others =>
                null;
            end case;
          else
            cpuspeed          <= x"40";
            cpuspeed_internal <= x"40";
          end if;
        else
          report "Forcing processor hold: trace_mode="
          & std_logic'image(monitor_mem_trace_mode)
          & " toggle_last=" & std_logic'image(monitor_mem_trace_toggle_last)
          & " toggle=" & std_logic'image(monitor_mem_trace_toggle)
          & " attn_req_drive=" & std_logic'image(monitor_mem_attention_request_drive);

          normal_fetch_state <= ProcessorHold;
          fast_fetch_state   <= ProcessorHold;
        end if;

        -- Force single step while I debug it.
        if debugging_single_stepping='1' then
          report "Forcing processor hold due to debugging_single_step";
          normal_fetch_state <= ProcessorHold;
          fast_fetch_state   <= ProcessorHold;
        end if;

        if mem_reading='1' then
          memory_read_value := read_data;
          report "MEMORY read value is $" & to_hstring(read_data);
        end if;

        -- Count down reset watchdog, and trigger reset if required.
        watchdog_reset <= '0';
        if (watchdog_fed='0') and
          ((monitor_mem_attention_request_drive='0')
            and (monitor_mem_trace_mode='0')) then
          if watchdog_countdown = 0 then
            -- Watchdog reset triggered
            watchdog_reset     <= '1';
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
          reset_out            <= '0';
          state                <= ResetLow;
          watchdog_fed         <= '0';
          watchdog_countdown   <= 65535;
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
        else
          -- Honour wait states on memory accesses
          -- Clear memory access lines unless we are in a memory wait state
          -- XXX replace with single bit test flag for wait_states = 0 to reduce
          -- logic depth
          reset_out <= '1';

          if mem_reading='1' then
            --            report "resetting mem_reading (read $" & to_hstring(memory_read_value) & ")" severity note;
            mem_reading         <= '0';
            monitor_mem_reading <= '0';
          end if;

          monitor_proceed           <= '0';
          monitor_request_reflected <= monitor_mem_attention_request_drive;

          report "CPU state (a) : phi_pause=" & std_logic'image(phi_pause);

            report "instruction_from_transaction =" & std_logic'image(instruction_from_transaction)
                & ", target_instruction_addr = " & integer'image(target_instruction_addr)
                & ", instruction_fetched_address_out = " & integer'image(instruction_fetched_address_out);
            report "waiting_on_mem_controller= " & std_logic'image(waiting_on_mem_controller)
                & ", transaction_complete_toggle=" & std_logic'image(transaction_complete_toggle)
                & ". expected_transaction_complete_toggle" & std_logic'image(expected_transaction_complete_toggle);

          -- CPU proceeds if proceed=1, or if we were waiting on the memory
          -- controller, but it has responded.
          if (waiting_on_mem_controller = '0') or (waiting_on_mem_controller='1' and (transaction_complete_toggle = expected_transaction_complete_toggle)) then

            -- Main state machine for CPU
            monitor_proceed           <= '1';

            waiting_on_mem_controller <= '0';

            report "CPU state = " & processor_state'image(state) & ", PC=$" & to_hstring(reg_pc) severity note;

            pop_a <= '0'; pop_x <= '0'; pop_y <= '0'; pop_z <= '0';
            pop_p <= '0';

            proceeds_per_frame <= proceeds_per_frame + 1;

            case state is
              when ResetLow =>
                -- Reset now maps hyppo at $8000-$BFFF, and enters through $8000
                -- by triggering the hypervisor.
                -- XXX indicate source of hypervisor entry
                reset_cpu_state;
                state <= TrapToHypervisor;
              when VectorRead =>
                report "MEMORY Setting memory_access_address interrupt/trap vector";
                if hypervisor_mode='1' then
                  -- Vectors move in hypervisor mode to be inside the hypervisor
                  -- ROM at $81Fx
                  memory_access_address := x"FF801F"&vector;
                else
                  memory_access_address := x"000FFF"&vector;
                end if;
                memory_access_read := '1';
                memory_access_byte_count := 2;
                state <= VectorReadDone;
              when VectorReadDone =>
                -- Assume that the memory controller has completed our request,
                -- and loaded the 16-bit value
                var_pc := transaction_rdata(15 downto 0);
                pc_set := '1';
                -- Then continue normally (the normal fetch logic will load the
                -- required instruction).
                state <= normal_fetch_state;
              when Interrupt =>
                -- BRK or IRQ
                -- Push P and PC
                pc_inc := 0;
                if nmi_pending='1' then
                  vector      <= x"a";
                  nmi_pending <= '0';
                else
                  vector <= x"e";
                end if;
                flag_i <= '1';

                -- 6502 interrupts write PCH, PCL, and flags in that order.
                -- But we are doing the memory write from low to high, so we
                -- write the bytes in the reverse order
                vreg33(23 downto 16) := reg_pc(15 downto 8);
                vreg33(15 downto 8)  := reg_pc(7 downto 0);
                vreg33(7 downto 0)   := unsigned(virtual_reg_p);
                if reg_instruction = I_BRK then
                  -- set B flag when pushing P
                  vreg33(4) := '1';
                else
                  -- clear B flag when pushing P
                  vreg33(4) := '0';
                end if;

                -- SP should be decremented by 3 after operation
                sp_dec := 3;

                -- And work out start address of pushed data = SP - 3
                -- Here we honour the E flag, to know if stack is 8 or 16 bit.
                temp_addr := reg_sph&reg_sp;
                if flag_e='1' then
                  -- 8-bit stack address
                  temp_addr(7 downto 0) := temp_addr(7 downto 0) - 3;
                else
                  temp_addr(15 downto 0) := temp_addr(15 downto 0) - 3;
                end if;

                -- Schedule the complete push in one go
                -- XXX Handle corner cases where stack overflow can occur
                -- XXX Just do a hypervisor trap in that case, and implement it
                -- in software? Or add states to CPU state machine to do writes
                -- byte at a time? Or make memory controller do the wrapping internally?
                memory_access_address(15 downto 0) := temp_addr;
                memory_access_wdata                := vreg33(31 downto 0);
                memory_access_resolve_address      := '1';
                memory_access_byte_count           := 3;
                memory_access_write                := '1';
                memory_access_read                 := '0';

                if cpuspeed_internal(7 downto 4) = "0000" and (slow_interrupts='1') then
                  -- Charge the 7 cycles for the interrupt when CPU is not at
                  -- full speed
                  phi_add_backlog <= '1'; phi_new_backlog <= 7;
                end if;

                state <= VectorRead;
              when RTI =>

                -- SP should be incremented by 3 after operation
                sp_inc := 3;

                -- SP is currently pointing to 1 byte before the 3 we need.
                temp_addr := reg_sph&reg_sp;
                if flag_e='1' then
                  -- 8-bit stack address
                  temp_addr(7 downto 0) := temp_addr(7 downto 0) + 1;
                else
                  temp_addr(15 downto 0) := temp_addr(15 downto 0) + 1;
                end if;

                -- XXX Handle corner cases where stack overflow can occur
                -- XXX Just do a hypervisor trap in that case, and implement it
                -- in software? Or add states to CPU state machine to do writes
                -- byte at a time? Or make memory controller do the wrapping internally?
                memory_access_address(15 downto 0) := reg_sph&reg_sp;
                memory_access_resolve_address      := '1';
                memory_access_byte_count           := 3;
                memory_access_write                := '0';
                memory_access_read                 := '0';

                state <= RTI2;
              when RTI2 =>
                load_processor_flags(transaction_rdata(7 downto 0));
                var_pc := transaction_rdata(23 downto 8);
                pc_set := '1';
                state  <= normal_fetch_state;
              when RTS =>

                -- SP should be incremented by 2 after operation
                sp_inc := 2;

                -- SP is currently pointing to 1 byte before the 2 we need.
                temp_addr := reg_sph&reg_sp;
                if flag_e='1' then
                  -- 8-bit stack address
                  temp_addr(7 downto 0) := temp_addr(7 downto 0) + 1;
                else
                  temp_addr(15 downto 0) := temp_addr(15 downto 0) + 1;
                end if;

                -- XXX Handle corner cases where stack overflow can occur
                -- XXX Just do a hypervisor trap in that case, and implement it
                -- in software? Or add states to CPU state machine to do writes
                -- byte at a time? Or make memory controller do the wrapping internally?
                memory_access_address(15 downto 0) := reg_sph&reg_sp;
                memory_access_resolve_address      := '1';
                memory_access_byte_count           := 2;
                memory_access_write                := '0';
                memory_access_read                 := '0';

                state <= RTS1;
              when RTS1 =>
                var_pc := transaction_rdata(15 downto 0);
                pc_set := '1';
                -- RTS address is target address - 1, so we add the 1 back on
                pc_inc := 1;
                state                      <= fast_fetch_state;
                monitor_instruction_strobe <= '1';
                report "monitor_instruction_strobe assert";
              when ProcessorHold =>
                -- Hold CPU while blocked by monitor

                -- Do no memory access while processor is held

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
                  if monitor_mem_address_drive(27 downto 16) = x"777" then
                    -- M777xxxx in serial monitor reads memory from CPU's perspective
                    memory_access_resolve_address := '1';
                  else
                    -- Else we assume the address is a flat 28-bit address
                    memory_access_resolve_address := '0';
                  end if;
                  memory_access_address    := unsigned(monitor_mem_address_drive);
                  memory_access_read       := '0';
                  memory_access_write      := monitor_mem_write_drive;
                  memory_access_byte_count := 1;
                  memory_access_wdata(7 downto 0) := monitor_mem_wdata_drive;
                  state                    <= MonitorMemoryAccess;
                  if monitor_mem_read='1' then
                    -- and optionally set PC
                    if monitor_mem_setpc='1' then
                      -- Abort any instruction currently being executed.
                      -- Then set PC from InstructionWait state to make sure that we
                      -- don't write it here, only for it to get stomped.
                      state <= MonitorMemoryAccess;
                      report "Setting PC (monitor)";
                      reg_pc      <= unsigned(monitor_mem_address_drive(15 downto 0));
                      mem_reading <= '0';
                    else
                      -- otherwise just read from memory
                      memory_access_read  := '1';
                      monitor_mem_reading <= '1';
                      mem_reading         <= '1';
                      state               <= MonitorMemoryAccess;
                    end if;
                  end if;
                end if;
              when MonitorMemoryAccess =>
                monitor_mem_rdata <= memory_read_value;
                if monitor_mem_attention_request_drive='1' then
                  monitor_mem_attention_granted          <= '1';
                  monitor_mem_attention_granted_internal <= '1';
                else
                  monitor_mem_attention_granted          <= '0';
                  monitor_mem_attention_granted_internal <= '0';
                  report "Holding processor due to monitor memory access";
                  state <= ProcessorHold;
                end if;
              when TrapToHypervisor =>
                -- Save all registers
                hyper_iomode(1 downto 0) <= unsigned(viciii_iomode);
                hyper_dmagic_list_addr   <= reg_dmagic_addr;
                hyper_dmagic_src_mb      <= reg_dmagic_src_mb;
                hyper_dmagic_dst_mb      <= reg_dmagic_dst_mb;
                hyper_a                  <= reg_a; hyper_x <= reg_x;
                hyper_y                  <= reg_y; hyper_z <= reg_z;
                hyper_b                  <= reg_b; hyper_sp <= reg_sp;
                hyper_sph                <= reg_sph; hyper_pc <= reg_pc;
                hyper_mb_low             <= reg_mb_low; hyper_mb_high <= reg_mb_high;
                hyper_map_low            <= reg_map_low; hyper_map_high <= reg_map_high;
                hyper_map_offset_low     <= reg_offset_low;
                hyper_map_offset_high    <= reg_offset_high;
                hyper_port_00            <= cpuport_ddr; hyper_port_01 <= cpuport_value;
                hyper_p                  <= unsigned(virtual_reg_p);

                report "ZPCACHE: Flushing cache due to trap to hypervisor";
                cache_flushing      <= '1';
                cache_flush_counter <= (others => '0');

                -- NEVER leave the @#$%! decimal flag set when entering the hypervisor
                -- (This took MONTHS to realise as the source of a MYRIAD of hypervisor
                -- problems.  Anyone removing this without asking Paul first will
                -- be appropriately punished.)
                flag_d <= '0';

                -- Set registers for hypervisor mode.

                -- Full hardware features available on entry to hypervisor
                iomode_set                 <= "11";
                iomode_set_toggle          <= not iomode_set_toggle_internal;
                iomode_set_toggle_internal <= not iomode_set_toggle_internal;

                -- Hypervisor lives in a 16KB memory that gets mapped at $8000-$BFFF.
                -- (it can of course map other stuff if it wants).
                -- stack and ZP are mapped to this space also (the memory is writable,
                -- but only from hypervisor mode).
                -- (preserve A,X,Y,Z and lower 32KB mapping for convenience for
                --  trap calls).
                -- 8-bit stack @ $BE00
                reg_sp <= x"ff"; reg_sph <= x"BE"; flag_e <= '1'; flag_i <= '1';
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
                reg_map_high    <= "0011";
                reg_offset_high <= x"f00"; -- add $F0000
                reg_mb_high     <= x"ff";
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
                iomode_set                 <= std_logic_vector(hyper_iomode(1 downto 0));
                iomode_set_toggle          <= not iomode_set_toggle_internal;
                iomode_set_toggle_internal <= not iomode_set_toggle_internal;
                reg_dmagic_addr            <= hyper_dmagic_list_addr;
                reg_dmagic_src_mb          <= hyper_dmagic_src_mb;
                reg_dmagic_dst_mb          <= hyper_dmagic_dst_mb;
                reg_a                      <= hyper_a; reg_x <= hyper_x; reg_y <= hyper_y;
                reg_z                      <= hyper_z; reg_b <= hyper_b; reg_sp <= hyper_sp;
                reg_sph                    <= hyper_sph; reg_pc <= hyper_pc;
                report "Setting PC on hypervisor exit";
                reg_mb_low      <= hyper_mb_low; reg_mb_high <= hyper_mb_high;
                reg_map_low     <= hyper_map_low; reg_map_high <= hyper_map_high;
                reg_offset_low  <= hyper_map_offset_low;
                reg_offset_high <= hyper_map_offset_high;
                cpuport_ddr     <= hyper_port_00; cpuport_value <= hyper_port_01;
                flag_n          <= hyper_p(7); flag_v <= hyper_p(6);
                flag_e          <= hyper_p(5); flag_d <= hyper_p(3);
                flag_i          <= hyper_p(2); flag_z <= hyper_p(1);
                flag_c          <= hyper_p(0);

                -- Reset counters so no timing side-channels through hypervisor calls
                frame_counter           <= to_unsigned(0,16);
                last_cycles_per_frame   <= to_unsigned(0,32);
                last_proceeds_per_frame <= to_unsigned(0,32);
                cycles_per_frame        <= to_unsigned(0,32);
                proceeds_per_frame      <= to_unsigned(0,32);

                report "ZPCACHE: Flushing cache due to return from hypervisor";
                cache_flushing      <= '1';
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
                  state               <= DMAgicReadOptions;
                end if;
                dmagic_list_counter <= 0;
                phi_add_backlog     <= '1'; phi_new_backlog <= 1;

                -- Begin to load DMA registers
                -- We load them from the 20 bit address stored $D700 - $D702
                -- plus the 8-bit MB value in $D704
                report "MEMORY Setting memory_access_address to reg_dmagic_addr ($"
                & to_hstring(reg_dmagic_addr) & ").";
                memory_access_address         := reg_dmagic_addr;
                memory_access_resolve_address := '0';
                memory_access_read            := '1';
              when DMAgicReadOptions =>
                -- XXX Use multi-byte memory read transactions to speed this up,
                -- as otherwise with the new memory controller, it will take
                -- several cycles per DMA list option/entry byte.
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
                    -- For hardware line drawing, we need to know about the
                    -- screen layout.  Note that this only works for
                    -- one-byte-per-pixel modes.  Using options $87-$8A the user
                    -- can set how much to add to the destination address when
                    -- crossing an 8-byte boundary in either the X or Y
                    -- direction. Within each 8x8 block the layout is assumed to
                    -- be the VIC-IV 256-colour card layout, i.e., 0 to 7 on the
                    -- first row, 8 to 15 on the second and so on.
                    -- Having described the screen layout as above, we now need a
                    -- way to describe the slope of the line. This can simply be
                    -- expressed as a factional value to add/subtract from the X or Y
                    -- value each pixel, and to know whether we are drawing along
                    -- X or Y, and if the slope is positive or negative.
                    -- Otherwise we just handle line drawing like a simple fill.
                    when x"87" => reg_dmagic_x8_offset(7 downto 0)             <= memory_read_value;
                    when x"88" => reg_dmagic_x8_offset(15 downto 8)            <= memory_read_value;
                    when x"89" => reg_dmagic_y8_offset(7 downto 0)             <= memory_read_value;
                    when x"8a" => reg_dmagic_y8_offset(15 downto 8)            <= memory_read_value;
                    when x"8b" => reg_dmagic_slope(7 downto 0)                 <= memory_read_value;
                    when x"8c" => reg_dmagic_slope(15 downto 8)                <= memory_read_value;
                    when x"8d" => reg_dmagic_slope_fraction_start(7 downto 0)  <= memory_read_value;
                    when x"8e" => reg_dmagic_slope_fraction_start(15 downto 8) <= memory_read_value;
                    when x"8f" => reg_dmagic_line_mode                         <= memory_read_value(7);
                      reg_dmagic_line_x_or_y         <= memory_read_value(6);
                      reg_dmagic_line_slope_negative <= memory_read_value(5);

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
                      when x"0A"  => job_is_f018b <= '0';
                      when x"0B"  => job_is_f018b <= '1';
                      when others => null;
                    end case;
                  end if;
                end if;

                report "MEMORY Setting memory_access_address to reg_dmagic_addr ($"
                & to_hstring(reg_dmagic_addr) & ").";
                memory_access_address         := reg_dmagic_addr;
                memory_access_resolve_address := '0';
                memory_access_read            := '1';
              when DMAgicReadList =>
                report "DMAgic: Reading DMA list (setting dmagic_cmd to $" & to_hstring(dmagic_count(7 downto 0))
                &", memory_read_value = $"&to_hstring(memory_read_value)&")";
                -- ask for next byte from DMA list
                phi_add_backlog <= '1'; phi_new_backlog <= 1;
                -- shift read byte into DMA registers and shift everything around
                dmagic_modulo(15 downto 8) <= memory_read_value;
                dmagic_modulo(7 downto 0)  <= dmagic_modulo(15 downto 8);
                if (job_is_f018b = '1') then
                  dmagic_subcmd         <= dmagic_modulo(7 downto 0);
                  dmagic_dest_bank_temp <= dmagic_subcmd;
                else
                  dmagic_dest_bank_temp <= dmagic_modulo(7 downto 0);
                end if;
                dmagic_dest_addr(23 downto 16) <= dmagic_dest_bank_temp;
                dmagic_dest_addr(15 downto 8)  <= dmagic_dest_addr(23 downto 16);
                dmagic_src_bank_temp           <= dmagic_dest_addr(15 downto 8);
                dmagic_src_addr(23 downto 16)  <= dmagic_src_bank_temp;
                dmagic_src_addr(15 downto 8)   <= dmagic_src_addr(23 downto 16);
                dmagic_count(15 downto 8)      <= dmagic_src_addr(15 downto 8);
                dmagic_count(7 downto 0)       <= dmagic_count(15 downto 8);
                dmagic_cmd                     <= dmagic_count(7 downto 0);
                if (job_is_f018b = '0') and (dmagic_list_counter = 10) then
                  state <= DMAgicGetReady;
                elsif dmagic_list_counter = 11 then
                  state <= DMAgicGetReady;
                else
                  dmagic_list_counter <= dmagic_list_counter + 1;
                  reg_dmagic_addr     <= reg_dmagic_addr + 1;
                end if;
                report "DMAgic: Reading DMA list (end of cycle)";

                report "MEMORY Setting memory_access_address to reg_dmagic_addr ($"
                & to_hstring(reg_dmagic_addr) & ").";
                memory_access_address         := reg_dmagic_addr;
                memory_access_resolve_address := '0';
                memory_access_read            := '1';
              when DMAgicGetReady =>
                report "DMAgic: got list: cmd=$"
                & to_hstring(dmagic_cmd)
                & ", src=$"
                & to_hstring(dmagic_src_addr(23 downto 8))
                & ", dest=$" & to_hstring(dmagic_dest_addr(23 downto 8))
                & ", count=$" & to_hstring(dmagic_count);
                phi_add_backlog <= '1'; phi_new_backlog <= 1;
                if (job_is_f018b = '1') then
                  dmagic_src_addr(35 downto 28)  <= reg_dmagic_src_mb + dmagic_src_bank_temp(6 downto 4);
                  dmagic_src_addr(27 downto 24)  <= dmagic_src_bank_temp(3 downto 0);
                  dmagic_dest_addr(35 downto 28) <= reg_dmagic_dst_mb + dmagic_dest_bank_temp(6 downto 4);
                  dmagic_dest_addr(27 downto 24) <= dmagic_dest_bank_temp(3 downto 0);
                else
                  dmagic_src_addr(35 downto 28)  <= reg_dmagic_src_mb;
                  dmagic_src_addr(27 downto 24)  <= dmagic_src_bank_temp(3 downto 0);
                  dmagic_dest_addr(35 downto 28) <= reg_dmagic_dst_mb;
                  dmagic_dest_addr(27 downto 24) <= dmagic_dest_bank_temp(3 downto 0);
                end if;
                dmagic_src_addr(7 downto 0)  <= (others => '0');
                dmagic_dest_addr(7 downto 0) <= (others => '0');
                dmagic_src_io                <= dmagic_src_bank_temp(7);
                if (job_is_f018b = '1') then
                  dmagic_src_direction <= dmagic_cmd(4);
                  dmagic_src_modulo    <= dmagic_subcmd(0);
                  dmagic_src_hold      <= dmagic_subcmd(1);
                else
                  dmagic_src_direction <= dmagic_src_bank_temp(6);
                  dmagic_src_modulo    <= dmagic_src_bank_temp(5);
                  dmagic_src_hold      <= dmagic_src_bank_temp(4);
                end if;
                dmagic_dest_io <= dmagic_dest_bank_temp(7);
                if (job_is_f018b = '1') then
                  dmagic_dest_direction <= dmagic_cmd(5);
                  dmagic_dest_modulo    <= dmagic_subcmd(2);
                  dmagic_dest_hold      <= dmagic_subcmd(3);
                else
                  dmagic_dest_direction <= dmagic_dest_bank_temp(6);
                  dmagic_dest_modulo    <= dmagic_dest_bank_temp(5);
                  dmagic_dest_hold      <= dmagic_dest_bank_temp(4);
                end if;

                -- Save memory mapping flags, and set memory map to
                -- be all RAM +/- IO area
                pre_dma_cpuport_bits      <= cpuport_value(2 downto 0);
                cpuport_value(2 downto 1) <= "10";

                case dmagic_cmd(1 downto 0) is
                  when "11" => -- fill
                    state <= DMAgicFill;

                    -- And set IO visibility based on destination bank flags
                    -- since we are only writing.
                    cpuport_value(0) <= dmagic_dest_bank_temp(7);

                  when "00" => -- copy
                    dmagic_first_read <= '1';
                    state             <= DMagicCopyRead;
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
                if reg_dmagic_line_mode = '0' then
                  -- Normal fill
                  if dmagic_dest_hold='0' then
                    if dmagic_dest_direction='0' then
                      dmagic_dest_addr(23 downto 0)
                      <= dmagic_dest_addr(23 downto 0) + reg_dmagic_dst_skip;
                    else
                      dmagic_dest_addr(23 downto 0)
                      <= dmagic_dest_addr(23 downto 0) - reg_dmagic_dst_skip;
                    end if;
                  end if;
                else
                  -- We are in line mode.

                  -- Add fractional position
                  reg_dmagic_slope_fraction_start <= reg_dmagic_slope_fraction_start + reg_dmagic_slope;
                  -- Check if we have accumulated a whole pixel of movement?
                  line_x_move          := '0';
                  line_x_move_negative := '0';
                  line_y_move          := '0';
                  line_y_move_negative := '0';
                  if dmagic_slope_overflow_toggle /= reg_dmagic_slope_fraction_start(16) then
                    dmagic_slope_overflow_toggle <= reg_dmagic_slope_fraction_start(16);
                    -- Yes: Advance in minor axis
                    if reg_dmagic_line_x_or_y='0' then
                      line_y_move          := '1';
                      line_y_move_negative := reg_dmagic_line_slope_negative;
                    else
                      line_x_move          := '1';
                      line_x_move_negative := reg_dmagic_line_slope_negative;
                    end if;
                  end if;
                  -- Also move major axis (which is always in the forward direction)
                  if reg_dmagic_line_x_or_y='0' then
                    line_x_move := '1';
                  else
                    line_y_move := '1';
                  end if;
                  if line_x_move='0' and line_y_move='1' and line_y_move_negative='0' then
                    -- Y = Y + 1
                    if dmagic_dest_addr(14 downto 11)="111" then
                      -- Will overflow between Y cards
                      dmagic_dest_addr <= dmagic_dest_addr + (256*8)
                        + (reg_dmagic_y8_offset&"00000000");
                    else
                      -- No overflow, so just add 8 bytes (with 8-bit pixel resolution)
                      dmagic_dest_addr <= dmagic_dest_addr + (256*8);
                    end if;
                  elsif line_x_move='0' and line_y_move='1' and line_y_move_negative='1' then
                    -- Y = Y - 1
                    if dmagic_dest_addr(14 downto 11)="000" then
                      -- Will overflow between X cards
                      dmagic_dest_addr <= dmagic_dest_addr - (256*8)
                        - (reg_dmagic_y8_offset&"00000000");
                    else
                      -- No overflow, so just subtract 8 bytes (with 8-bit pixel resolution)
                      dmagic_dest_addr <= dmagic_dest_addr - (256*8);
                    end if;
                  elsif line_x_move='1' and line_x_move_negative='0' and line_y_move='0' then
                    -- X = X + 1
                    if dmagic_dest_addr(10 downto 8)="111" then
                      -- Will overflow between X cards
                      dmagic_dest_addr <= dmagic_dest_addr + 256
                        + (reg_dmagic_x8_offset&"00000000");
                    else
                      -- No overflow, so just add 1 pixel (with 8-bit pixel resolution)
                      dmagic_dest_addr <= dmagic_dest_addr + 256;
                    end if;
                  elsif line_x_move='1' and line_x_move_negative='1' and line_y_move='0' then
                    -- X = X - 1
                    if dmagic_dest_addr(10 downto 8)="000" then
                      -- Will overflow between X cards
                      dmagic_dest_addr <= dmagic_dest_addr - 256
                        - (reg_dmagic_x8_offset&"00000000");
                    else
                      -- No overflow, so just subtract 1 pixel (with 8-bit pixel resolution)
                      dmagic_dest_addr <= dmagic_dest_addr - 256;
                    end if;
                  elsif line_x_move='1' and line_x_move_negative='0' and line_y_move='1' and line_y_move_negative='0' then
                    -- X = X + 1, Y = Y + 1
                    if dmagic_dest_addr(14 downto 8)="111111" then
                      -- positive overflow on both
                      dmagic_dest_addr <= dmagic_dest_addr + (256*9)
                        + (reg_dmagic_x8_offset&"00000000")
                        + (reg_dmagic_y8_offset&"00000000");
                    elsif dmagic_dest_addr(14 downto 11)="111" then
                      -- positive card overflow on Y only
                      dmagic_dest_addr <= dmagic_dest_addr + (256*9)
                        + (reg_dmagic_y8_offset&"00000000");
                    elsif dmagic_dest_addr(10 downto 8)="111" then
                      -- positive card overflow on X only
                      dmagic_dest_addr <= dmagic_dest_addr + (256*9)
                        + (reg_dmagic_x8_offset&"00000000");
                    else
                      -- no card overflow
                      dmagic_dest_addr <= dmagic_dest_addr + (256*9);
                    end if;
                  elsif line_x_move='1' and line_x_move_negative='0' and line_y_move='1' and line_y_move_negative='1' then
                    -- X = X + 1, Y = Y - 1
                    if dmagic_dest_addr(14 downto 8)="000111" then
                      -- positive card overflow on X, negative on Y
                      dmagic_dest_addr <= dmagic_dest_addr + (256*1) - (256*8)
                        + (reg_dmagic_x8_offset&"00000000")
                        - (reg_dmagic_y8_offset&"00000000");
                    elsif dmagic_dest_addr(14 downto 11)="000" then
                      -- negative card overflow on Y only
                      dmagic_dest_addr <= dmagic_dest_addr + (256*1) - (256*8)
                        - (reg_dmagic_y8_offset&"00000000");
                    elsif dmagic_dest_addr(10 downto 8)="111" then
                      -- positive overflow on X only
                      dmagic_dest_addr <= dmagic_dest_addr + (256*1) - (256*8)
                        + (reg_dmagic_x8_offset&"00000000");
                    else
                      dmagic_dest_addr <= dmagic_dest_addr + (256*1) - (256*8);
                    end if;
                  elsif line_x_move='1' and line_x_move_negative='1' and line_y_move='1' and line_y_move_negative='0' then
                    -- X = X - 1, Y = Y + 1
                    if dmagic_dest_addr(14 downto 8)="111000" then
                      -- negative card overflow on X, positive on Y
                      dmagic_dest_addr <= dmagic_dest_addr - (256*1) + (256*8)
                        - (reg_dmagic_x8_offset&"00000000")
                        + (reg_dmagic_y8_offset&"00000000");
                    elsif dmagic_dest_addr(14 downto 11)="111" then
                      -- positive card overflow on Y only
                      dmagic_dest_addr <= dmagic_dest_addr - (256*1) + (256*8)
                        + (reg_dmagic_y8_offset&"00000000");
                    elsif dmagic_dest_addr(10 downto 8)="000" then
                      -- negative overflow on X only
                      dmagic_dest_addr <= dmagic_dest_addr - (256*1) + (256*8)
                        - (reg_dmagic_x8_offset&"00000000");
                    else
                      dmagic_dest_addr <= dmagic_dest_addr - (256*1) + (256*8);
                    end if;
                  elsif line_x_move='1' and line_x_move_negative='1' and line_y_move='1' and line_y_move_negative='1' then
                    -- X = X - 1, Y = Y - 1
                    if dmagic_dest_addr(14 downto 8)="000000" then
                      -- negative card overflow on X, negative on Y
                      dmagic_dest_addr <= dmagic_dest_addr - (256*1) - (256*8)
                        - (reg_dmagic_x8_offset&"00000000")
                        - (reg_dmagic_y8_offset&"00000000");
                    elsif dmagic_dest_addr(14 downto 11)="000" then
                      -- positive card overflow on Y only
                      dmagic_dest_addr <= dmagic_dest_addr - (256*1) - (256*8)
                        - (reg_dmagic_y8_offset&"00000000");
                    elsif dmagic_dest_addr(10 downto 8)="000" then
                      -- negative overflow on X only
                      dmagic_dest_addr <= dmagic_dest_addr - (256*1) - (256*8)
                        - (reg_dmagic_x8_offset&"00000000");
                    else
                      dmagic_dest_addr <= dmagic_dest_addr - (256*1) - (256*8);
                    end if;
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
                    state                      <= normal_fetch_state;
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

                report "MEMORY Setting memory_access_address to dmagic_dest_addr ($"
                & to_hstring(dmagic_dest_addr) & ").";
                memory_access_read            := '0';
                memory_access_write           := '1';
                memory_access_wdata(7 downto 0) := dmagic_src_addr(15 downto 8);
                memory_access_resolve_address := '0';
                memory_access_address         := dmagic_dest_addr(35 downto 8);

                -- redirect memory write to IO block if required
                -- address is in 256ths of a byte, so must be shifted up 8 bits
                -- hence 23 downto 20 instead of 15 downto 12
                if dmagic_dest_addr(23 downto 20) = x"d" and dmagic_dest_io='1' then
                  report "MEMORY Setting memory_access_address upper bits to IO block";
                  memory_access_address(27 downto 16) := x"FFD";
                  memory_access_address(15 downto 14) := "00";
                  if hypervisor_mode='0' then
                    memory_access_address(13 downto 12) := unsigned(viciii_iomode);
                  else
                    memory_access_address(13 downto 12) := "11";
                  end if;
                end if;
              when VDCRead =>
                -- Implement VDC block copys
                -- XXX Update this to use the new wide memory transaction interface.
                -- XXX Better, make VDC block copies be simulated using DMAgic, so that
                -- we have fewer states in the CPU's state machine
                state            <= VDCWrite;
                vdc_word_count   <= vdc_word_count - 1;
                vdc_mem_addr_src <= vdc_mem_addr_src + 1;

                memory_access_read            := '1';
                memory_access_resolve_address := '0';
                report "MEMORY Setting memory_access_address to resolved_vdc_to_viciv_src_address ($004"
                & to_hstring(resolved_vdc_to_viciv_src_address) & ").";
                memory_access_address(27 downto 16) := x"004";
                memory_access_address(15 downto 0)  := resolved_vdc_to_viciv_src_address;
              when VDCWrite =>
                vdc_mem_addr <= vdc_mem_addr + 1;
                if vdc_word_count = 0 then
                  state <= normal_fetch_state;
                else
                  -- continue Reading
                  state <= VDCRead;
                end if;

                memory_access_read                  := '0';
                memory_access_write                 := '1';
                memory_access_wdata(7 downto 0)     := transaction_rdata(7 downto 0);
                memory_access_resolve_address       := '0';
                memory_access_address(27 downto 16) := x"004";
                report "MEMORY Setting memory_access_address to resolved_vdc_to_viciv_src_address ($004"
                & to_hstring(resolved_vdc_to_viciv_src_address) & ").";
                memory_access_address(15 downto 0) := resolved_vdc_to_viciv_address;
              when DMAgicCopyRead =>
                -- We can't write a value the immediate cycle we read it, so
                -- we need to read one byte ahead, so that we have a 1 byte buffer
                -- and can read or write on every cycle.
                -- so we need to read the first byte now.

                -- XXX We should REALLY use the multi-byte transaction support of
                -- the new memory controller.

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
                state            <= DMAgicCopyWrite;

                -- Do memory read
                memory_access_read            := '1';
                memory_access_resolve_address := '0';
                report "MEMORY Setting memory_access_address to dmagic_src_addr ($"
                & to_hstring(dmagic_src_addr) & ").";
                memory_access_address := dmagic_src_addr(35 downto 8);

                -- redirect memory read to IO block if required
                -- address is in 256ths of a byte, so must be shifted up 8 bits
                -- hence 23 downto 20 instead of 15 downto 12
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
                -- Remember value just read
                report "dmagic_src_addr=$" & to_hstring(dmagic_src_addr(35 downto 8))
                &"."&to_hstring(dmagic_src_addr(7 downto 0))
                & " (reg_dmagic_src_skip=$" & to_hstring(reg_dmagic_src_skip)&")";
                dmagic_first_read <= '0';
                reg_t             <= memory_read_value;

                -- Set IO visibility for source
                cpuport_value(0) <= dmagic_src_io;
                state            <= DMAgicCopyRead;

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
                      state                      <= normal_fetch_state;
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

                if dmagic_first_read = '0' then
                  -- Do memory write
                  if (reg_t /= reg_dmagic_transparent_value)
                    or (reg_dmagic_use_transparent_value='0') then
                    memory_access_read  := '0';
                    memory_access_write := '1';
                  else
                    memory_access_write := '0';
                  end if;
                  memory_access_wdata(7 downto 0) := reg_t;
                  memory_access_resolve_address := '0';
                  report "MEMORY Setting memory_access_address to dmagic_dest_addr ($"
                  & to_hstring(dmagic_dest_addr) & ").";
                  memory_access_address := dmagic_dest_addr(35 downto 8);

                  -- redirect memory write to IO block if required
                  -- address is in 256ths of a byte, so must be shifted up 8 bits
                  -- hence 23 downto 20 instead of 15 downto 12
                  if dmagic_dest_addr(23 downto 20) = x"d" and dmagic_dest_io='1' then
                    memory_access_address(27 downto 16) := x"FFD";
                    memory_access_address(15 downto 14) := "00";
                    if hypervisor_mode='0' then
                      memory_access_address(13 downto 12) := unsigned(viciii_iomode);
                    else
                      memory_access_address(13 downto 12) := "11";
                    end if;
                  end if;
                end if;
              when InstructionWait =>
                state <= InstructionFetch;
              when InstructionFetch =>
                if (hypervisor_mode='0')
                  and ((irq_pending='1' and flag_i='0') or nmi_pending='1')
                  and (monitor_irq_inhibit='0') then
                  -- An interrupt has occurred
                  pc_inc := 0;
                  state  <= Interrupt;
                  -- Make sure reg_instruction /= I_BRK, so that B flag is not
                  -- erroneously set.
                  reg_instruction <= I_SEI;
                elsif (hyper_trap_pending = '1' and hypervisor_mode='0') then
                  -- Trap to hypervisor
                  hyper_trap_pending <= '0';
                  state              <= TrapToHypervisor;
                  if matrix_trap_pending = '1' then
                    -- Trap #67 ($43) = ALT-TAB key press (toggles matrix mode)
                    hypervisor_trap_port <= "1000011";
                    matrix_trap_pending  <= '0';
                  elsif f011_read_trap_pending = '1' then
                    -- Trap #68 ($44) = SD/F011 read sector
                    hypervisor_trap_port   <= "1000100";
                    f011_read_trap_pending <= '0';
                  elsif f011_write_trap_pending = '1' then
                    -- Trap #69 ($45) = SD/F011 write sector
                    hypervisor_trap_port    <= "1000101";
                    f011_write_trap_pending <= '0';
                  else
                    -- Trap #66 ($42) = RESTORE key double-tap
                    hypervisor_trap_port <= "1000010";
                  end if;
                else
                  -- Normal instruction execution
                  if emu6502='1' then
                    state <= InstructionDecode6502;
                  else
                    state <= InstructionDecode4502;
                  end if;
                  fetch_instruction_please := '1';
                  var_pc := reg_pc;
                end if;
              when InstructionDecode4502 =>

                  -- By default the instruction is not affected by any prefixes
                  flat32_addressmode         <= '0';
                  flat32_addressmode_v       := '0';
                  is_axyz32_instruction      <= '0';
                  is_axyz32_instruction_v    := '0';
                  is_16bit_operation         <= '0';
                  is_16bit_operation_v       := '0';
                  zp32bit_pointer_enabled    <= '0';
                  zp32bit_pointer_enabled_v  := '0';
                  do_branch8                 := '0';
                  do_branch16                := '0';
                  prefix_bytes               := 0;

                  -- Always start getting the next instruction ready
                  fetch_instruction_please := '1';
                  -- and setup to match it.
                  -- We have to overwrite this assignment (or clear
                  -- instruction_from_transaction) if the next instruction is not
                  -- at the immediately following memory location.
                  -- XXX Do we really need this here? More the point, can it cause
                  -- false positivies?
                  target_instruction_addr <= target_instruction_addr + 1;

                  -- First, work out if the instruction is ready.
                  if instruction_from_transaction='0' and target_instruction_addr /= instruction_fetched_address_out then
                    -- We are waiting for the instruction to arrive, which means it
                    -- wasn't in the buffer. So toggle the request line to make sure it
                    -- gets fetched.
                    -- XXX We should do this only once, not continuously.
                    instruction_fetch_request_toggle <= not instruction_fetch_request_toggle;
                  else

                    -- We now have 6 bytes of instruction data, regardless of where
                    -- it has come from, so lets get the data from the correct
                    -- source, and munge it as appropriate.
                    if instruction_from_transaction='1' then
                      instruction_bytes_v := transaction_rdata;
                    else
                      instruction_bytes_v := instruction_fetch_rdata;
                    end if;

                    report "I believe I have the data for the next instruction: $"
                     & to_hstring(instruction_bytes_v);


                    -- Now check for prefixes.  This also implicitly skips
                    -- single NOP instructions(!)
                    if instruction_bytes_v(23 downto 0) = x"EA4242"
                      or instruction_bytes_v(23 downto 0) = x"4242EA" then
                      -- NEG / NEG prefix = 32-bit ZP pointers
                      -- NOP prefix = Q 32-bit pseudo register
                      instruction_bytes_v(23 downto 0)  := instruction_bytes_v(47 downto 24);
                      instruction_bytes_v(47 downto 24) := x"EAEAEA";
                      is_axyz32_instruction           <= '1';
                      is_axyz32_instruction_v         := '1';
                      zp32bit_pointer_enabled         <= '1';
                      zp32bit_pointer_enabled_v       := '1';
                      prefix_bytes                    := 3;
                      map_interrupt_inhibit <= '0';  
                    elsif instruction_bytes_v(15 downto 0) = x"4242" then
                      -- NEG / NEG prefix = Q 32-bit pseudo register
                      instruction_bytes_v(31 downto 0)  := instruction_bytes_v(47 downto 16);
                      instruction_bytes_v(47 downto 32) := x"EAEA";
                      is_axyz32_instruction           <= '1';
                      is_axyz32_instruction_v         := '1';
                      prefix_bytes                    := 2;
                    elsif instruction_bytes_v(15 downto 0) = x"D8D8" then
                      -- CLD / CLD prefix = Flat 32-bit jump or branch
                      instruction_bytes_v(31 downto 0)  := instruction_bytes_v(47 downto 16);
                      instruction_bytes_v(47 downto 32) := x"EAEA";
                      flat32_addressmode              <= flat32_enabled;
                      flat32_addressmode_v            := flat32_enabled;
                      prefix_bytes                    := 2;
                    elsif instruction_bytes_v(7 downto 0) = x"EA" then
                      -- NOP prefix = 32-bit ZP pointers
                      instruction_bytes_v(39 downto 0)  := instruction_bytes_v(47 downto 8);
                      instruction_bytes_v(47 downto 40) := x"EA";
                      zp32bit_pointer_enabled         <= '1';
                      zp32bit_pointer_enabled_v       := '1';
                      prefix_bytes                    := 1;
                      map_interrupt_inhibit <= '0';  
                    end if;
                    instruction_bytes <= instruction_bytes_v;

                    -- Show previous instruction
                    disassemble_instruction(reg_pc,instruction_bytes(23 downto 0));
                    -- Start recording this instruction
                    last_instruction_pc <= reg_pc;
                    last_opcode         <= instruction_bytes(7 downto 0);
                    last_byte2         <= instruction_bytes(15 downto 8);
                    last_byte3         <= instruction_bytes(23 downto 16);

                    -- Prepare microcode vector in case we need it next cycle
                    reg_microcode <=
                      microcode_lut(instruction_lut(to_integer(emu6502&instruction_bytes_v(7 downto 0))));
                    reg_addressingmode <= mode_lut(to_integer(emu6502&instruction_bytes_v(7 downto 0)));
                    reg_instruction    <= instruction_lut(to_integer(emu6502&instruction_bytes_v(7 downto 0)));
                    -- And also get it ready for this cycle
                    var_microcode :=
                      microcode_lut(instruction_lut(to_integer(emu6502&instruction_bytes_v(7 downto 0))));
                    var_addressingmode := mode_lut(to_integer(emu6502&instruction_bytes_v(7 downto 0)));
                    var_instruction    := instruction_lut(to_integer(emu6502&instruction_bytes_v(7 downto 0)));
                    phi_add_backlog    <= '1';
                    phi_new_backlog    <= cycle_count_lut(to_integer(timing6502&instruction_bytes_v(7 downto 0)));

                    -- Update PC based on addressing mode, so that we can more
                    -- quickly fetch the instruction bytes for the next instruction
                    -- We remember to also skip the prefix bytes

                    case var_addressingmode is
                      when M_impl | M_A =>
                          pc_inc := prefix_bytes + 1;
                      when M_InnX | M_nn | M_immnn | M_rr | M_InnY | M_InnZ | M_nnX | M_InnSPY | M_nnY =>
                        pc_inc := prefix_bytes + 2;
                      when M_nnnn | M_nnrr | M_rrrr | M_nnnnY | M_nnnnX | M_Innnn | M_InnnnX | M_immnnnn =>
                        pc_inc := prefix_bytes + 3;
                    end case;
                    case var_addressingmode is
                      when M_InnX | M_InnY | M_InnZ | M_Innnn | M_InnSPY | M_InnnnX =>
                        is_indirect_v := '1';
                      when others =>
                        is_indirect_v := '0';
                    end case;

                    is_rmw               <= '0'; is_load <= '0';
                    is_rmw_v             := '0'; is_load_v := '0';
                    rmw_dummy_write_done <= '0';
                    case instruction_lut(to_integer(emu6502&instruction_bytes_v(7 downto 0))) is
                      -- Note if instruction is RMW
                      when I_INC | I_DEC | I_ROL | I_ROR | I_ASL | I_ASR | I_LSR | I_TSB | I_TRB | I_RMB | I_SMB
                        -- There are a few 16-bit RMWs as well
                        -- (PHW $nnnn is a funny one, because we load normally, and
                        -- then store to stack, so we treat it like an RMW, because
                        -- two memory accesses are required.)
                        | I_INW | I_DEW | I_ASW | I_PHW | I_ROW =>
                        is_rmw <= '1'; is_rmw_v := '1';
                      -- Note if instruction LOADs value from memory
                      when I_BIT | I_AND | I_ORA | I_EOR | I_ADC | I_SBC | I_CMP | I_CPX | I_CPY | I_CPZ
                        | I_LDA | I_LDX | I_LDY | I_LDZ =>
                        is_load <= '1'; is_load_v := '1';
                      -- Also if it is a store
                      when I_STA | I_STX | I_STY | I_STZ =>
                        is_store <= '1'; is_store_v := '1';

                      -- And 6502 unintended opcodes
                      when I_SLO                                 => is_rmw <= '1';
                      when I_RLA                                 => is_rmw <= '1';
                      when I_SRE                                 => is_rmw <= '1';
                      when I_SAX                                 => null;
                      when I_LAX                                 => is_load <= '1';
                      when I_RRA                                 => is_rmw  <= '1';
                      when I_DCP                                 => is_rmw  <= '1';
                      when I_ISC                                 => is_rmw  <= '1';
                      when I_ANC                                 => is_load <= '1';
                      when I_ALR                                 => is_load <= '1';
                      when I_ARR                                 => is_load <= '1';
                      when I_SBX                                 => null;
                      when I_LAS                                 => null;
                      when I_ANE | I_SHA | I_SHX | I_SHY | I_TAS =>
                        state <= TrapToHypervisor;
                        -- Trap $46 = 6502 Unstable illegal instruction encountered
                        hypervisor_trap_port <= "1000110";
                      when I_KIL =>
                        state <= TrapToHypervisor;
                        -- Trap $47 = 6502 KIL instruction encountered
                        hypervisor_trap_port <= "1000111";
                      -- Nothing special for other instructions
                      when others => null;
                    end case;

                    -- 4502 doesn't allow interrupts immediately following a
                    -- single-cycle instruction
                    if (hypervisor_mode='0') and ((irq_pending='1' and flag_i='0') or nmi_pending='1') then
                      -- An interrupt has occurred
                      report "Interrupt detected, decrementing PC so we push correct value onto the stack";
                      state   <= Interrupt;
                      pc_dec1 := '1';
                      pc_inc  := 0;
                      -- Make sure reg_instruction /= I_BRK, so that B flag is not
                      -- erroneously set.
                      reg_instruction <= I_SEI;
                    else
                      reg_opcode <= instruction_bytes_v(7 downto 0);
                      -- Present instruction to serial monitor;
                      monitor_ibytes        <= instruction_bytes_v(23 downto 0);
                      monitor_instructionpc <= reg_pc;

                      -- Check for 16-bit operations
                      case instruction_bytes_v(7 downto 0) is
                        when x"C3" | -- DEW $nn
                          x"CB" |    -- ASW $nnnn
                          x"E3" |    -- INW $nnnn
                          x"EB" |    -- ROW $nnnn
                          x"FC" =>   -- PHW $nnnn
                          is_16bit_operation_v := '1';
                          is_16bit_operation   <= '1';
                        when others =>
                          -- We don't treat PHW #$nnnn ($F4) as a 16-bit
                          -- operation, as we actually handle it as a single-cycle
                          -- instructoin.
                          null;
                      end case;

                      report "Executing instruction "
                      & instruction'image(instruction_lut(to_integer(emu6502&instruction_bytes_v(7 downto 0))))
                      severity note;

                      -- On the C65, interrupts cannot happen following
                      -- single-cycle instructions, as part of the optimisation of
                      -- the 65CE02. It served no vital role on the C65, however.
                      -- We previously mirrored this on the MEGA65, partly because
                      -- it meant that we could be sure that no interrupts could
                      -- happen between an instruction prefix and the instruction.
                      -- However now that we fetch an entire instruction in one go,
                      -- including any prefix bytes, we don't need that protection
                      -- any more. This means we can process a great many
                      -- instructions in a single cycle, and generally have simpler
                      -- logic.  Essentially if the instruction ISNT one that we
                      -- can process in a single cycle, then we dispatch the load
                      -- or store that is required next.

                      -- Work out relevant bit mask for RMB/SMB
                      case instruction_bytes_v(6 downto 4) is
                        when "000"  => reg_bitmask <= "00000001";
                        when "001"  => reg_bitmask <= "00000010";
                        when "010"  => reg_bitmask <= "00000100";
                        when "011"  => reg_bitmask <= "00001000";
                        when "100"  => reg_bitmask <= "00010000";
                        when "101"  => reg_bitmask <= "00100000";
                        when "110"  => reg_bitmask <= "01000000";
                        when "111"  => reg_bitmask <= "10000000";
                        when others => null;
                      end case;

                      case instruction_bytes_v(7 downto 0) is
                        -- XXX Also implement PLA/X/Y/Z as single-cycle
                        when x"03" =>
                          flag_e <= '1'; -- SEE
                          report "ZPCACHE: Flushing cache due to setting E flag";
                          cache_flushing      <= '1';
                          cache_flush_counter <= (others => '0');
                        when x"08" =>
                          -- PHP
                          memory_access_write                := '1';
                          memory_access_byte_count           := 1;
                          memory_access_wdata(7 downto 0)    := unsigned(virtual_reg_p);
                          memory_access_resolve_address      := '1';
                          memory_access_address(15 downto 8) := reg_sph;
                          memory_access_address(7 downto 0)  := reg_sp;
                          sp_dec                             := 1;
                        when x"09" =>
                          -- ORA #$nn
                          mc.mcALU_in_a  := '1';
                          mc.mcORA := '1';
                          mc.mcalu_b_ibyte2 := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"0A" =>
                          -- ASL A
                          mc.mcALU_set_a := '1';
                          mc.mcADD := '1';
                          mc.mcALU_in_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                          mc.mcCarryFromBit7 := '0';
                          mc.mcZeroBit0 := '0';
                        when x"0B" =>
                          -- TSY
                          mc.mcALU_in_sph := '1';
                          mc.mcALU_set_y := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"10" =>
                          -- BPL $rr
                          if flag_n = '0' then do_branch8 := '1';
                          end if;
                        when x"13" =>
                          -- BPL $rrrr
                          if flag_n = '0' then do_branch16 := '1';
                          end if;
                        when x"18" => flag_c    <= '0';                -- CLC
                        when x"1A" =>
                          -- INC A
                          mc.mcALU_in_a := '1';
                          mc.mcALU_b_1 := '1';
                          mc.mcADD := '1';
                          mc.mcAssumeCarryClear := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"1B" =>
                          -- INZ
                          mc.mcALU_in_z := '1';
                          mc.mcALU_b_1 := '1';
                          mc.mcADD := '1';
                          mc.mcAssumeCarryClear := '1';
                          mc.mcALU_set_z := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"20" =>
                          -- JSR
                          pc_inc                        := 0;
                          pc_set                        := '1';
                          var_pc                        := instruction_bytes_v(23 downto 8);
                          memory_access_write           := '1';
                          memory_access_byte_count      := 2;
                          memory_access_resolve_address := '1';
                          -- Decrement SP by one first before writing word
                          if flag_e = '0' then
                            var_sp := (reg_sph & reg_sp) - 1;
                          else
                            var_sp(15 downto 8) := reg_sph;
                            var_sp(7 downto 0)  := reg_sp - 1;
                          end if;
                          memory_access_address(15 downto 0) := var_sp;
                          sp_dec                             := 2;
                          -- JSR pushes the address of its 3rd byte to the stack,
                          -- not the address of the next instruction.  This is a
                          -- well known 6502 weirdness
                          memory_access_wdata(15 downto 0) := reg_pc + 2;
                          -- Because we have to first push to the stack, then
                          -- fetch the next instruction, we need to switch states
                          fetch_instruction_please := '0';
                          state <= normal_fetch_state;
                        when x"29" =>
                          -- AND #$nn
                          mc.mcALU_in_a  := '1';
                          mc.mcAND := '1';
                          mc.mcalu_b_ibyte2 := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"2A" =>
                          -- ROL A
                          mc.mcALU_in_a := '1';
                          mc.mcADD := '1';
                          mc.mcCarryFromBit7 := '1';
                          mc.mcBit0FromCarry := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"2B" => reg_sph   <= reg_y;                                     -- TYS
                          report "ZPCACHE: Flushing cache due to setting SPH";
                          cache_flushing      <= '1';
                          cache_flush_counter <= (others => '0');
                        when x"30" => -- BMI $rr
                          if flag_n = '1' then do_branch8 := '1';
                          end if;
                        when x"33" => -- BMI $rrrr
                          if flag_n = '1' then do_branch16 := '1';
                          end if;
                        when x"38" => flag_c    <= '1';                  -- SEC
                        when x"3A" =>
                          -- DEC A
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcALU_b_1 := '1';
                          mc.mcInvertB := '1';
                          mc.mcADD := '1';
                          mc.mcAssumeCarryClear := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"3B" =>
                          -- DEZ
                          mc.mcALU_in_z := '1';
                          mc.mcALU_set_z := '1';
                          mc.mcALU_b_1 := '1';
                          mc.mcInvertB := '1';
                          mc.mcADD := '1';
                          mc.mcAssumeCarryClear := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"40" => state     <= RTI;
                        when x"42" =>
                          -- NEG A
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcALU_b_1 := '1';
                          mc.mcInvertA := '1';
                          mc.mcInvertB := '1';
                          mc.mcADD := '1';
                          mc.mcAssumeCarryClear := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"43" =>
                          -- ASR A
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcLSR := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                          mc.mcCarryFromBit0 := '1';
                        when x"48" =>
                          -- PHA
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_resolve_address      := '1';
                          memory_access_address(15 downto 8) := reg_sph;
                          memory_access_address(7 downto 0)  := reg_sp;
                          sp_dec                             := 1;
                        when x"49" =>
                          -- EOR #$nn
                          mc.mcALU_in_a  := '1';
                          mc.mcEOR := '1';
                          mc.mcalu_b_ibyte2 := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"4A" =>
                          -- LSR A
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcLSR := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                          mc.mcCarryFromBit0 := '1';
                          mc.mcZeroBit7 := '1';
                        when x"4B" =>
                          -- TAZ
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_z := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"4C" =>
                          -- JMP
                          pc_inc    := 0;
                          pc_set := '1';
                          var_pc := instruction_bytes_v(23 downto 8);
                        when x"50" =>
                          -- BVC $rr
                          if flag_v = '0' then do_branch8 := '1'; end if;
                        when x"53" =>
                          -- BVC $rrrr
                          if flag_v = '0' then do_branch16 := '1'; end if;
                        when x"5A" =>
                          -- PHY
                          mc.mcALU_in_y := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_resolve_address      := '1';
                          memory_access_address(15 downto 8) := reg_sph;
                          memory_access_address(7 downto 0)  := reg_sp;
                          sp_dec                             := 1;
                        when x"5B" =>
                          -- TAB
                          reg_b <= reg_a;
                          report "ZPCACHE: Flushing cache due to moving ZP";
                        when x"60" =>
                          -- RTS
                          if flat32_addressmode_v = '0' then
                            state <= RTS;
                          else
                            state <= Flat32RTS;
                          end if;
                        when x"62" =>
                          -- RTS #$nn
                          if flat32_addressmode_v = '0' then
                            state <= RTS;
                          else
                            state <= Flat32RTS;
                          end if;
                          sp_inc := to_integer(instruction_bytes_v(15 downto 8));
                        when x"63" => -- BSR $rrrr
                          do_branch16                   := '1';
                          memory_access_write           := '1';
                          memory_access_byte_count      := 2;
                          memory_access_resolve_address := '1';
                          -- Decrement SP by one first before writing word
                          if flag_e = '0' then
                            var_sp := (reg_sph & reg_sp) - 1;
                          else
                            var_sp(15 downto 8) := reg_sph;
                            var_sp(7 downto 0)  := reg_sp - 1;
                          end if;
                          memory_access_address(15 downto 0) := var_sp;
                          sp_dec                             := 2;
                          -- JSR pushes the address of its 3rd byte to the stack,
                          -- not the address of the next instruction.  This is a
                          -- well known 6502 weirdness
                          memory_access_wdata(15 downto 0) := reg_pc + 2;
                          -- Because we have to first push to the stack, then
                          -- fetch the next instruction, we need to switch states
                          fetch_instruction_please := '0';
                          state <= normal_fetch_state;
                        when x"64" =>
                          -- STZ $nn
                          mc.mcALU_in_z := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"69" =>
                          -- ADC #$nn
                          mc.mcALU_in_a  := '1';
                          mc.mcADD := '1';
                          mc.mcAddCarry := '1';
                          mc.mcalu_b_ibyte2 := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                          mc.mcRecordV := '1';
                          mc.mcRecordCarry := '1';
                        when x"6A" =>
                          -- ROR A
                          mc.mcALU_in_a  := '1';
                          mc.mcLSR := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                          mc.mcBit7FromCarry := '1';
                          mc.mcCarryFromBit0 := '1';
                        when x"6B" =>
                          -- TZA
                          mc.mcALU_in_z := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordZ := '1';
                          mc.mcRecordN := '1';
                        when x"70" =>
                          -- BVS $rr
                          if flag_v = '1' then do_branch8 := '1'; end if;
                        when x"73" =>
                          -- BVS $rrrr
                          if flag_v = '1' then do_branch16 := '1'; end if;
                        when x"74" =>
                          -- STZ $nn,X
                          mc.mcALU_in_z := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"78" =>
                          -- SEI
                          flag_i   <= '1';
                        when x"7B" =>
                          -- TBA
                          mc.mcALU_in_b := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"80" =>                                                          -- BRA $rr
                          do_branch8 := '1';
                        when x"83" => -- BRA $rrrr
                          do_branch16 := '1';
                        when x"84" =>
                          -- STY $nn
                          mc.mcALU_in_y := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"85" =>
                          -- STA $nn
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"86" =>
                          -- STX $nn
                          mc.mcALU_in_x := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"88" =>
                          -- DEY
                          mc.mcALU_in_y := '1';
                          mc.mcALU_set_y := '1';
                          mc.mcALU_b_1 := '1';
                          mc.mcInvertB := '1';
                          mc.mcADD := '1';
                          mc.mcAssumeCarryClear := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"89" =>
                          -- BIT #$nn
                          mc.mcALU_in_a  := '1';
                          mc.mcalu_b_ibyte2 := '1';
                          mc.mcAND := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"8A" =>
                          -- TXA
                          mc.mcALU_in_x := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"8B" =>
                          -- STY $nnnn,X
                          mc.mcALU_in_y := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"8C" =>
                          -- STY $nnnn
                          mc.mcALU_in_y := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"8D" =>
                          -- STA $nnnn
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"8E" =>
                          -- STX $nnnn
                          mc.mcALU_in_x := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"90" =>
                          -- BCC $rr
                          if flag_c = '0' then do_branch8 := '1'; end if;
                        when x"93" =>
                          -- BCC $rrrr
                          if flag_c = '0' then do_branch16 := '1'; end if;
                        when x"94" =>
                          -- STY $nn,X
                          mc.mcALU_in_y := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"95" =>
                          -- STA $nn,X
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"96" =>
                          -- STX $nn,Y
                          mc.mcALU_in_x := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_set_address_based_on_addressingmode := '1';
                        when x"98" =>
                          -- TYA
                          mc.mcALU_in_y := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"9A" =>
                          -- TXS
                          mc.mcALU_in_x := '1';
                          mc.mcALU_set_spl := '1';
                        when x"A0" =>
                          -- LDY #$nn
                          mc.mcPassB := '1';
                          mc.mcalu_b_ibyte2 := '1';
                          mc.mcALU_set_y := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"A2" =>
                          -- LDX #$nn
                          mc.mcPassB := '1';
                          mc.mcalu_b_ibyte2 := '1';
                          mc.mcALU_set_x := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"A3" =>
                          -- LDZ #$nn
                          mc.mcPassB := '1';
                          mc.mcalu_b_ibyte2 := '1';
                          mc.mcALU_set_z := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"A8" =>
                          -- TAY
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_y := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"A9" =>
                          -- LDA #$nn
                          mc.mcPassB := '1';
                          mc.mcALU_b_ibyte2 := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"AA" =>
                          -- TAX
                          mc.mcALU_in_a := '1';
                          mc.mcALU_set_x := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"B0" =>
                          -- BCS $rr
                          if flag_c = '1' then do_branch8 := '1'; end if;
                        when x"B3" =>
                          -- BCS $rrrr
                          if flag_c = '1' then do_branch16 := '1'; end if;
                        when x"B8" =>
                          -- CLV
                          flag_v     <= '0';
                        when x"BA" =>
                          -- TSX
                          mc.mcALU_in_spl := '1';
                          mc.mcALU_set_x := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"C0" =>
                          -- CPY #$nn
                          mc.mcADD := '1';
                          mc.mcInvertB := '1';
                          mc.mcALU_in_y := '1';
                          mc.mcAssumeCarrySet := '1';
                          mc.mcRecordCarry := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"C2" =>
                          -- CPZ #$nn
                          mc.mcADD := '1';
                          mc.mcInvertB := '1';
                          mc.mcALU_in_z := '1';
                          mc.mcAssumeCarrySet := '1';
                          mc.mcRecordCarry := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"C8" =>
                          -- INY
                          mc.mcALU_in_y := '1';
                          mc.mcALU_set_z := '1';
                          mc.mcALU_b_1 := '1';
                          mc.mcInvertB := '0';
                          mc.mcADD := '1';
                          mc.mcAssumeCarryClear := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"C9" =>
                          -- CMP #$nn
                          mc.mcADD := '1';
                          mc.mcInvertB := '1';
                          mc.mcALU_in_a := '1';
                          mc.mcAssumeCarrySet := '1';
                          mc.mcRecordCarry := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"CA" =>
                          -- DEX
                          mc.mcALU_in_z := '1';
                          mc.mcALU_set_z := '1';
                          mc.mcALU_b_1 := '1';
                          mc.mcInvertB := '1';
                          mc.mcADD := '1';
                          mc.mcAssumeCarryClear := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"d0" =>
                          -- BNE $rr
                          if flag_z = '0' then do_branch8 := '1'; end if;
                        when x"d3" =>
                          -- BNE $rrrr
                          if flag_z = '0' then do_branch16 := '1'; end if;
                        when x"D8" =>
                          -- CLD
                          flag_d <= '0';
                        when x"DA" =>
                          -- PHX
                          mc.mcALU_in_x := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_resolve_address      := '1';
                          memory_access_address(15 downto 8) := reg_sph;
                          memory_access_address(7 downto 0)  := reg_sp;
                          sp_dec                             := 1;
                        when x"DB" =>
                          -- PHZ
                          mc.mcALU_in_z := '1';
                          mc.mcALU_set_mem := '1';
                          memory_access_resolve_address      := '1';
                          memory_access_address(15 downto 8) := reg_sph;
                          memory_access_address(7 downto 0)  := reg_sp;
                          sp_dec                             := 1;
                        when x"E0" =>
                          -- CPX #$nn
                          mc.mcADD := '1';
                          mc.mcInvertB := '1';
                          mc.mcALU_in_x := '1';
                          mc.mcAssumeCarrySet := '1';
                          mc.mcRecordCarry := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"E8" =>
                          -- INX
                          mc.mcALU_in_x := '1';
                          mc.mcALU_set_x := '1';
                          mc.mcALU_b_1 := '1';
                          mc.mcInvertB := '0';
                          mc.mcADD := '1';
                          mc.mcAssumeCarryClear := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                        when x"E9" =>
                          -- SBC #$nn
                          mc.mcALU_in_a  := '1';
                          mc.mcADD := '1';
                          mc.mcAddCarry := '1';
                          mc.mcalu_b_ibyte2 := '1';
                          mc.mcInvertB := '1';
                          mc.mcALU_set_a := '1';
                          mc.mcRecordN := '1';
                          mc.mcRecordZ := '1';
                          mc.mcRecordV := '1';
                          mc.mcRecordCarry := '1';
                        when x"EA" =>
                          -- EOM / NOP
                          map_interrupt_inhibit <= '0';
                        when x"F0" =>
                          -- BEQ $rr
                          if flag_z = '1' then do_branch8 := '1'; end if;
                        when x"F3" =>
                           -- BEQ $rrrr
                          if flag_z = '1' then do_branch16 := '1'; end if;
                        when x"F4" =>
                          -- PHW #$nnnn
                          memory_access_write                := '1';
                          memory_access_byte_count           := 2;
                          memory_access_wdata(15 downto 0)   := instruction_bytes_v(23 downto 8);
                          memory_access_resolve_address      := '1';
                          memory_access_address(15 downto 8) := reg_sph;
                          memory_access_address(7 downto 0)  := reg_sp;
                          sp_dec                             := 2;
                        when x"F8"  =>
                          -- SED
                          flag_d <= '1';
                        when others =>
                          -- Instruction requires multi-cycle processing
                          if is_indirect_v = '1' then
                            -- Resolve indirect address
                            memory_access_write           := '0';
                            memory_access_resolve_address := '1';
                            if zp32bit_pointer_enabled_v = '1' then
                              memory_access_byte_count := 4;
                            else
                              memory_access_byte_count := 2;
                            end if;
                            state <= IndirectResolved;
                            case var_addressingmode is
                              -- ... And for the indirect modes, start reading the
                              -- indirect address
                              when M_Innnn =>
                                memory_access_address(15 downto 0) := instruction_bytes_v(23 downto 8);
                              when M_InnnnX =>
                                memory_access_address(15 downto 0) := instruction_bytes_v(23 downto 8) + reg_x;
                              when M_InnSPY =>
                                memory_access_address(15 downto 0) := to_unsigned(to_integer(reg_b&reg_arg1)
                                    +to_integer(reg_sph&reg_sp),16);
                              when M_InnX =>
                                memory_access_address(15 downto 8) := reg_b;
                                memory_access_address(7 downto 0)  := instruction_bytes_v(15 downto 8) + reg_x;
                              when M_InnY | M_InnZ =>
                                memory_access_address(15 downto 8) := reg_b;
                                memory_access_address(7 downto 0)  := instruction_bytes_v(15 downto 8);
                              when others =>
                                report "Unexpected addressing mode encountered in indirect access." severity error;
                            end case;
                          elsif is_load_v = '1' or is_rmw_v = '1' then
                            -- Schedule the load
                            memory_access_write           := '0';
                            memory_access_resolve_address := '1';
                            case var_addressingmode is
                              -- Handle the direct addressing modes, by immediately
                              -- scheduling the memory read ...
                              when M_nn =>
                                memory_access_address(15 downto 8) := reg_b;
                                memory_access_address(7 downto 0)  := instruction_bytes_v(15 downto 8);
                                state                              <= MicrocodeInterpret;
                              when M_nnX =>
                                memory_access_address(15 downto 8) := reg_b;
                                memory_access_address(7 downto 0)  := instruction_bytes_v(15 downto 8) + reg_x;
                                state                              <= MicrocodeInterpret;
                              when M_nnY =>
                                memory_access_address(15 downto 8) := reg_b;
                                memory_access_address(7 downto 0)  := instruction_bytes_v(15 downto 8) + reg_y;
                                state                              <= MicrocodeInterpret;
                              when M_nnnn =>
                                memory_access_address(15 downto 0) := instruction_bytes_v(23 downto 8);
                                state                              <= MicrocodeInterpret;
                              when M_nnnnX =>
                                memory_access_address(15 downto 0) := instruction_bytes_v(23 downto 8) + reg_x;
                                state                              <= MicrocodeInterpret;
                              when M_nnnnY =>
                                memory_access_address(15 downto 0) := instruction_bytes_v(23 downto 8) + reg_y;
                                state                              <= MicrocodeInterpret;
                              when others =>
                                report "Unexpected addressing mode encountered in direct load." severity error;
                            end case;
                          elsif is_store_v = '1' then
                            -- Schedule the store
                            memory_access_write           := '0';
                            memory_access_resolve_address := '1';

                            memory_access_set_address_based_on_addressingmode := '1';
                          end if;
                      end case;

                      -- Adjust PC based on taking branches
                      if do_branch8 = '1' then
                        pc_inc := to_integer(instruction_bytes_v(15) &
                            instruction_bytes_v(15) &
                            instruction_bytes_v(15) &
                            instruction_bytes_v(15) &
                            instruction_bytes_v(15) &
                            instruction_bytes_v(15) &
                            instruction_bytes_v(15) &
                            instruction_bytes_v(15) &
                            instruction_bytes_v(15 downto 8));
                      end if;
                      if do_branch16 = '1' then
                        pc_inc := to_integer(instruction_bytes_v(23 downto 8));
                      end if;

                      -- Allow monitor to trace through single-cycle instructions
                      if monitor_mem_trace_mode='1' or debugging_single_stepping='1' then
                        report "monitor_instruction_strobe assert (4510 single cycle instruction, single-stepped)";
                        state  <= normal_fetch_state;
                        pc_inc := 0;
                      else
                        report "monitor_instruction_strobe assert (4510 single cycle instruction)";
                      end if;
                      monitor_instruction_strobe <= '1';
                    end if; -- have current instruction
                  end if;
                var_mc := mc;
              when IndirectResolved =>
                -- At this point transaction_rdata contains the 16 or 32 bits of
                -- address.
                -- Apply any index register adjustments, and schedule the load or
                -- store.
                if reg_instruction = I_PHW then
                  -- This instruction is a bit weird: We handle it as though it
                  -- were a RMW instruction, but the store happens to the stack
                  -- Decrement SP by one first before writing word
                  if flag_e = '0' then
                    var_sp := (reg_sph & reg_sp) - 1;
                  else
                    var_sp(15 downto 8) := reg_sph;
                    var_sp(7 downto 0)  := reg_sp - 1;
                  end if;
                  memory_access_address(15 downto 0) := var_sp;
                elsif zp32bit_pointer_enabled = '1' then
                  -- Address is 32-bit flat address
                  -- Store the address directly
                  if reg_addressingmode = M_InnZ then
                    memory_access_address := transaction_rdata(27 downto 0) + reg_z;
                    reg_addr32            <= transaction_rdata(31 downto 0) + reg_z;
                  else
                    memory_access_address := transaction_rdata(27 downto 0);
                    reg_addr32            <= transaction_rdata(31 downto 0);
                  end if;
                  memory_access_resolve_address := '0';
                else
                  -- Address is 16-bit CPU-oriented address
                  temp_addr := transaction_rdata(15 downto 0);
                  case reg_addressingmode is
                    when M_InnY => temp_addr := temp_addr + reg_y;
                    when M_InnZ => temp_addr := temp_addr + reg_z;
                    when others => null;
                  end case;
                  memory_access_resolve_address      := '1';
                  memory_access_address(15 downto 0) := temp_addr;
                end if;
                if is_axyz32_instruction = '1' then
                  memory_access_byte_count := 4;
                elsif is_16bit_operation = '1' then
                  memory_access_byte_count := 2;
                else
                  memory_access_byte_count := 1;
                end if;
                if reg_instruction = I_PHW then
                  state <= fast_fetch_state;
                elsif is_load='1' or is_rmw='1' then
                  -- Do the actual load
                  memory_access_write := '0';
                  state               <= MicrocodeInterpret;
                elsif is_store='1' then
                  -- Store only
                  memory_access_write := '1';
                  state               <= fast_fetch_state;
                end if;
              when MicrocodeInterpret =>
                -- transaction_rdata now contains the data we need
                -- So now is the time to actually interpret the instruction's microcode
                  -- At this point, we have the argument available in transaction_rdata,
                  -- and all the single-cycle instructions, branches and jumps have
                  -- been dealt with.
                  -- Here our focus is on doing the ALU operation, and then
                  -- optionally storing the result back if its an RMW or just a
                  -- store operation with a complex addressing mode.

                  memory_access_address  := reg_addr32(27 downto 0);
                    
                  -- Work out the next state for the FSM
                  if reg_microcode.mcBRK='1' then
                    state <= Interrupt;
                  elsif var_mc.mcJump='1' then
                    report "Setting PC: mcJump=1";
                    pc_set := '1';
                    var_pc := reg_addr;
                  else
                    state <= fast_fetch_state;
                  end if;

                  var_mc := reg_microcode;
                    
                when others =>
                report "monitor_instruction_strobe assert (unknown CPU state)";
                monitor_instruction_strobe <= '1';
                state                      <= normal_fetch_state;
            end case;

          end if;

            -- And otherwise, we mostly just set a pile of ALU flags
            -- The ALU consists of three chained stages, in order to achieve
            -- 6502 bug compatibility: right shift, binary operations, addition.
            -- We have a parallel ALU implementation for the 16/32 bit operations.

          -- Load A input to ALU
          var_alu_a := x"00";
          if var_mc.mcALU_in_mem='1' then
            var_alu_a2 := transaction_rdata(7 downto 0);
          end if;
          if var_mc.mcALU_in_bitmask = '1' then
            var_alu_a2 := reg_bitmask;
          end if;
          if var_mc.mcALU_in_a = '1'
              and var_mc.mcALU_in_x = '1' then
            var_alu_a2 := reg_a and reg_x;
          elsif var_mc.mcALU_in_a = '1' then
            var_alu_a2 := reg_a;
          elsif var_mc.mcALU_in_b = '1' then
            var_alu_a2 := reg_b;
          elsif var_mc.mcALU_in_x = '1' then
            var_alu_a2 := reg_x;
          end if;
          if var_mc.mcALU_in_y = '1' then
            var_alu_a2 := reg_y;
          end if;
          if var_mc.mcALU_in_x = '1' then
            var_alu_a2 := reg_y;
          end if;
          if var_mc.mcALU_in_spl = '1' then
            var_alu_a2 := reg_sp;
          end if;
          if var_mc.mcALU_in_sph = '1' then
            var_alu_a2 := reg_sph;
          end if;
          if var_mc.mcInvertA='1' then
            var_alu_a3 := not var_alu_a2;
          else
            var_alu_a3 := var_alu_a2;
          end if;

          -- Load B input to ALU
          if var_mc.mcALU_b_1 = '1' then
            report "ALU B $01";     
            var_alu_b := x"01";
          elsif var_mc.mcalu_b_ibyte2 = '1' then
            report "ALU B ibyte2";     
            var_alu_b := instruction_bytes_v(15 downto 8);
          else      
            report "ALU B trans data";     
            var_alu_b := transaction_rdata(7 downto 0);
          end if;
          if var_mc.mcInvertB='1' then
            var_alu_b2 := not var_alu_b;
          else
            var_alu_b2 := var_alu_b;
          end if;

          -- Now perform the various actions.

          -- First, we do the right shift
          if var_mc.mcLSR = '1' then
            var_alu_r1(7)          := '0';
            var_alu_r1(6 downto 0) := var_alu_a(7 downto 1);
          else
            var_alu_r1(7 downto 0) := var_alu_a;
          end if;

          -- What is the value of carry flag going in?
          if var_mc.mcAssumeCarrySet = '1' then
            var_c_in := '1';
          elsif var_mc.mcAssumeCarryClear = '0' then
            var_c_in := '0';
          else
            var_c_in := flag_c;
          end if;

          -- Second, we do the ADD operation.
          -- This is the most horrible part of the 6502.
          -- We have to deal with BCD mode, among other things.
          -- Return is NVZC<8 bit result>
          if var_mc.mcADD = '1' then
            var_alu_r2 := alu_op_add(var_alu_r1(7 downto 0),var_alu_b2(7 downto 0),
                                     var_c_in,
                                     var_mc.mcAllowBCD and flag_d);
          else
            -- No addition, no fancy flags
            var_alu_r2(11 downto 8) := "0000";
            var_alu_r2(7 downto 0)  := var_alu_r1(7 downto 0);
          end if;
          
          -- Third, we do the binary operations
          if var_mc.mcAND = '1' then
            var_alu_r3(7 downto 0) := var_alu_r2(7 downto 0) and
                                      var_alu_b2;
          elsif var_mc.mcORA = '1' then
            var_alu_r3(7 downto 0) := var_alu_r2(7 downto 0) or
                                      var_alu_b2;
          elsif var_mc.mcEOR = '1' then
            var_alu_r3(7 downto 0) := var_alu_r2(7 downto 0) xor
                                      var_alu_b2;
          end if;
          
          if var_mc.mcPassB = '1' Then
            var_alu_r3(7 downto 0) := var_alu_b2;
          end if;
          if var_mc.mcZeroBit7 = '1' Then
            var_alu_r3(7) := '0';
          end if;
          
          -- Calculate N flag
          var_alu_r3(11) := var_alu_r3(7);
          -- Calculate Z flag
          if var_alu_r3(7 downto 0) /= x"00" then
            var_alu_r3(9) := '0';
          else
            var_alu_r3(9) := '1';
          end if;
          if var_mc.mcTRBSetZ = '1' then
            -- TRB Z flag is simply from the comparison of A and loaded memory
            if (reg_a and transaction_rdata(7 downto 0)) /= x"00" then
              var_alu_r3(9) := '0';
            else
              var_alu_r3(9) := '1';
            end if;
          end if;
          -- Update C flag from bit 0/7 as required
          if var_mc.mcCarryFromBit7 = '1' then
            var_alu_r3(8) := var_alu_a3(7);
          end if;
          if var_mc.mcCarryFromBit0 = '1' then
            var_alu_r3(8) := var_alu_a3(0);
          end if;
          
          -- Set bit 0 / 7 of result from C flag, if required
          var_alu_r4 := var_alu_r3;
          if var_mc.mcBit0FromCarry = '1' then
            var_alu_r4(0) := flag_c;
          end if;
          if var_mc.mcBit7FromCarry = '1' then
            var_alu_r4(7) := flag_c;
          end if;
          
          -- Now work out what to value we are writing to memory, if any
          if var_mc.mcStoreAX = '1' then
            -- Store and of A and X
            var_wdata(7 downto 0) := reg_a and reg_x;
          elsif var_mc.mcADD = '1' then
            -- SLO instruction writes result of ADD (=left shift), not of
            -- the ORA
            var_wdata(7 downto 0) := var_alu_r2(7 downto 0);
          else
            var_wdata(7 downto 0) := var_alu_r4(7 downto 0);
          end if;
          
          -- Do actual write
          if var_mc.mcALU_set_mem = '1' then
            memory_access_write           := '1';
            memory_access_byte_count      := 1;
            memory_access_wdata           := var_wdata;
            memory_access_resolve_address := '1';
            
            -- Address is expected to be already set
          end if;
          
          if var_mc.mcPushW = '1' Then
            memory_access_write           := '1';
            memory_access_byte_count      := 2;
            memory_access_wdata           := var_wdata;
            memory_access_resolve_address := '1';
            
            -- Decrement SP by one first before writing word
            if flag_e = '0' then
              var_sp := (reg_sph & reg_sp) - 1;
            else
              var_sp(15 downto 8) := reg_sph;
              var_sp(7 downto 0)  := reg_sp - 1;
            end if;
            memory_access_address(15 downto 0) := var_sp;
            sp_dec := 2;
          end if;
          
          -- Also commit result to registers, if required
          if var_mc.mcALU_set_a = '1' then
            reg_a <= var_alu_r4(7 downto 0);
          end if;
          if var_mc.mcALU_set_x = '1' then
            reg_x <= var_alu_r4(7 downto 0);
          end if;
          if var_mc.mcALU_set_y = '1' then
            reg_y <= var_alu_r4(7 downto 0);
          end if;
          if var_mc.mcALU_set_z = '1' then
            reg_z <= var_alu_r4(7 downto 0);
          end if;
          if var_mc.mcALU_set_spl = '1' then
            reg_sp <= var_alu_r4(7 downto 0);
          end if;
          if var_mc.mcALU_set_p = '1' then
            load_processor_flags(var_alu_r4(7 downto 0));
          end if;
          
          -- And update processor flags
          if var_mc.mcRecordN = '1' then
            flag_n <= var_alu_r3(11);
          end if;
          if var_mc.mcRecordV = '1' then
            flag_v <= var_alu_r3(10);
          end if;
          if var_mc.mcRecordZ = '1' then
            flag_z <= var_alu_r3(9);
          end if;
          if var_mc.mcRecordCarry = '1' then
            flag_c <= var_alu_r3(8);
          end if;

            report "ALU: set_a=" & std_logic'image(var_mc.mcALU_set_a)
                & ", B=$" & to_hstring(var_alu_b2)
                & ", R=$" & to_hstring(var_alu_r4)
                & ", PassB=" & std_logic'image(var_mc.mcPassB)
                & ", B_ibyte2=" & std_logic'image(mc.mcalu_b_ibyte2)                
                & ", ibyte=$" & to_hstring(instruction_bytes_v(15 downto 8))
                & ", RecN=" & std_logic'image(var_mc.mcRecordN)
                & ", RecZ=" & std_logic'image(var_mc.mcRecordZ);
            

          if memory_access_set_address_based_on_addressingmode = '1' then
            case var_addressingmode is
              -- Handle the direct addressing modes, by immediately
              -- scheduling the memory read ...
              when M_nn =>
                memory_access_address(15 downto 8) := reg_b;
                memory_access_address(7 downto 0)  := instruction_bytes_v(15 downto 8);
              when M_nnX =>
                memory_access_address(15 downto 8) := reg_b;
                memory_access_address(7 downto 0)  := instruction_bytes_v(15 downto 8) + reg_x;
              when M_nnY =>
                memory_access_address(15 downto 8) := reg_b;
                memory_access_address(7 downto 0)  := instruction_bytes_v(15 downto 8) + reg_y;
              when M_nnnn =>
                memory_access_address(15 downto 0) := instruction_bytes_v(23 downto 8);
              when M_nnnnX =>
                memory_access_address(15 downto 0) := instruction_bytes_v(23 downto 8) + reg_x;
              when M_nnnnY =>
                memory_access_address(15 downto 0) := instruction_bytes_v(23 downto 8) + reg_y;
              when others =>
                report "Unexpected addressing mode encountered in direct store." severity error;
            end case;
          end if;


          report "pc_inc = $" & to_hstring(to_unsigned(pc_inc,16))
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

          -- Work out what the PC will be next cycle, including any combination
          -- of setting and incrementing.
          if pc_set = '0' then
            var_pc := reg_pc;
            report "Setting PC to $" & to_hstring(var_pc);
          end if;
          var_pc := var_pc + pc_inc;
          report "Incrementing PC by " & integer'image(pc_inc) & " to $" & to_hstring(var_pc) severity note;
          if pc_dec1='1' then
            var_pc := var_pc - 1;
            report "Decrementing PC by 1";
          end if;
          reg_pc <= var_pc;

          -- This must come AFTER reg_pc has been incremented, so that we have
          -- the incremented / branched address available
          if fetch_instruction_please = '1' then
            vreg33(27 downto 0) := resolve_address_to_long(var_pc, false);
            if to_integer(vreg33) < (chipram_size - 5 ) then
              -- Instruction is in chip/fast RAM
              instruction_fetch_address_in <= to_integer(vreg33(19 downto 0));
              target_instruction_addr      <= to_integer(vreg33(19 downto 0));
              -- Instruction will come from the dedicated ifetch interface
              report "Fetching instruction via ifetch";
              instruction_from_transaction <= '0';
            -- XXX Toggle instruction_fetch_request_toggle is we believe that the
            -- requested address is not in the instruction pre-fetch buffer.
            -- Simplest approach here is to toggle it once when we enter
            -- InstructionDecode state if the instruction is not ready there for us.
            else
                -- Have to fetch instruction via normal memory channel
                if memory_access_read = '0' and memory_access_write = '0'  then
                  transaction_request_toggle <= not transaction_request_toggle_int;
                  transaction_request_toggle_int <= not transaction_request_toggle_int;
                  expected_transaction_complete_toggle <= not transaction_complete_toggle;
                  transaction_address        <= vreg33(27 downto 0);
                  transaction_length         <= 6;
                  transaction_write          <= '0';
                  waiting_on_mem_controller  <= '1';
                  -- instruction bytes will arrive as a normal memory transaction
                  instruction_from_transaction <= '1';
                  report "Fetching instruction via general memory transaction interface. Addr=$"
                      & to_hstring(vreg33(27 downto 0));
                else
                  report "Holding off fetching the next instruction due to bus contention";
                  state <= normal_fetch_state;
                end if;
            end if;
          else
          -- Normal memory access
          end if;

          if sp_dec /= 0 or sp_inc /= 0 then
            var_sp := reg_sph & reg_sp;
            var_sp := var_sp + sp_inc - sp_dec;
            reg_sp <= var_sp(7 downto 0);
            if flag_e='0' then
              reg_sph <= var_sp(15 downto 8);
            end if;
          end if;


          -- Now do ALU.
          -- The ALU is a big of a pain, because of the NMOS bug compatibility
          -- that we need to have.
          -- The ALU control logic can also trigger memory writes, so it needs to
          -- appear before the memory access logic.

          -- Effect memory accesses.
          -- Note that we cannot combine address resolution for read and write,
          -- because the resolution of some addresses is dependent on whether
          -- the operation is read or write.  ROM accesses are a good example.

          if memory_access_address = x"FFD3601" and vdc_reg_num = x"1E" and hypervisor_mode='0' and (vdc_enabled='1') then
            state <= VDCRead;
          end if;

          if memory_access_address = x"FFD0E00"
            or memory_access_address = x"FFD1E00"
            or memory_access_address = x"FFD3E00" then
            -- Ocean cartridge emulation bank register
            -- 16x8KB banks. Lower 128KB at $8000-$9FFF,
            -- Upper 128KB at $A000-$BFFF
            -- For stock MEGA65, we map the lower 128KB to banks 4 & 5
            -- The upper banks should map somewhere, too, but this is trickier
            -- due to only 384KB total.  We can re-use BANK 3 easily enough,
            -- but the last 64KB is a problem, as not all of BANK 1 is really free.
            -- Better point that to HyperRAM, perhaps. But for now, it will just
            -- point to the same 128KB.  So only 128KB carts will work.
            -- The bank bits go to bits 20 -- 13, so for bank 4 we need to set
            -- bit 18 = bit 5 of the bank registers
            ocean_cart_hi_bank <= to_unsigned(32+to_integer(memory_access_wdata(3 downto 0)),8);
            ocean_cart_lo_bank <= to_unsigned(32+to_integer(memory_access_wdata(3 downto 0)),8);
          end if;

          if memory_access_address = x"FFD3700"
            or memory_access_address = x"FFD1700" then
            report "DMAgic: DMA pending";
            dma_pending <= '1';
            state       <= DMAgicTrigger;

            -- Normal DMA, use pre-set F018A/B mode
            job_is_f018b     <= support_f018b;
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
            state       <= DMAgicTrigger;

            -- Normal DMA, use pre-set F018A/B mode
            job_is_f018b     <= support_f018b;
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
            hypervisor_trap_port(6)          <= '0';
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
          end if;

          report "MEMORY address prior to resolution is $" & to_hstring(memory_access_address);

          if memory_access_read = '1' then
            if memory_access_resolve_address = '1' then
              long_address := resolve_address_to_long(memory_access_address(15 downto 0),false);
            else
              long_address := memory_access_address;
            end if;
            report "MEMORY address post read resolution is $" & to_hstring(long_address);

            report "MEMORY: Reading memory @ $" & to_hstring(long_address);
            if long_address(27 downto 20) = x"00" and fetch_instruction_please = '1' then
              -- Fast instruction memory fetch
              -- XXX By default we do nothing now, because we update the ifetch request in
              -- InstructionDecode if the instruction isn't preemptively loaded for us.
            else
              -- Normal memory fetch
              transaction_request_toggle <= not transaction_request_toggle_int;
              transaction_request_toggle_int <= not transaction_request_toggle_int;
              expected_transaction_complete_toggle <= not transaction_complete_toggle;
              transaction_length         <= memory_access_byte_count;
              transaction_address        <= long_address;
              transaction_write          <= '0';
              waiting_on_mem_controller <= '1';
            end if;
          end if;

          if memory_access_write='1' then
            if memory_access_resolve_address = '1' then
              long_address := resolve_address_to_long(memory_access_address(15 downto 0),true);
            else
              long_address := memory_access_address;
            end if;
            report "MEMORY address post write resolution is $" & to_hstring(long_address);

            if long_address(27 downto 17)="00000000001" and rom_writeprotect='1' then
              report "Ignoring write to ROM addr=$" & to_hstring(long_address) severity note;
            else
              report "MEMORY: Writing memory @ $" & to_hstring(long_address);
              transaction_request_toggle <= not transaction_request_toggle_int;
              transaction_request_toggle_int <= not transaction_request_toggle_int;
              expected_transaction_complete_toggle <= not transaction_complete_toggle;
              transaction_length         <= memory_access_byte_count;
              transaction_address        <= long_address;
              transaction_write          <= '1';
              transaction_wdata          <= memory_access_wdata;
              waiting_on_mem_controller <= '1';
            end if;
          end if;

        end if;

        report "final memory access was $" & to_hstring(memory_access_address)
        & ", read=" & std_logic'image(memory_access_read)
        & ", write=" & std_logic'image(memory_access_write);

        if last_pixel_frame_toggle /= pixel_frame_toggle_drive then
          frame_counter           <= frame_counter + 1;
          cycles_per_frame        <= to_unsigned(0,32);
          proceeds_per_frame      <= to_unsigned(0,32);
          last_cycles_per_frame   <= cycles_per_frame;
          last_proceeds_per_frame <= proceeds_per_frame;
        end if;
        reg_math_config_drive <= reg_math_config;

      end if; -- if rising edge of clock

      -- output all monitor values based on current state, not one clock delayed.
      monitor_memory_access_address <= x"0"&memory_access_address;
      monitor_watch_match           <= '0'; -- set if writing to watched address
      monitor_state                 <= to_unsigned(processor_state'pos(state),8)&read_data;
      monitor_hypervisor_mode       <= hypervisor_mode;
      monitor_pc                    <= reg_pc;
      monitor_a                     <= reg_a;
      monitor_x                     <= reg_x;
      monitor_y                     <= reg_y;
      monitor_z                     <= reg_z;
      monitor_sp                    <= reg_sph&reg_sp;
      monitor_b                     <= reg_b;
      monitor_interrupt_inhibit     <= map_interrupt_inhibit;
      monitor_map_offset_low        <= reg_offset_low;
      monitor_map_offset_high       <= reg_offset_high;
      monitor_map_enables_low       <= unsigned(reg_map_low);
      monitor_map_enables_high      <= unsigned(reg_map_high);

  end process;


  end Behavioural;
