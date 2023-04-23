-- Accelerated 6502-like CPU for the C65GS
--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
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

-- @IO:C65 $D0A0-$D0FF - Reserved for C65 RAM Expansion Controller.

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
    cpufrequency : integer := 50 );
  port (
    Clock : in std_logic;
    mathclock : in std_logic;
    phi0 : out std_logic := '1'; -- XXX CIAs won't tick
    ioclock : in std_logic;
    reset : in std_logic;
    reset_out : out std_logic := '0';
    irq : in std_logic;
    nmi : in std_logic;
    exrom : in std_logic;
    game : in std_logic;

    all_pause : in std_logic;

    chipselect_enables : out std_logic_vector(7 downto 0) := (others => '1');
    dat_offset : in unsigned(15 downto 0);
    dat_bitplane_addresses : in sprite_vector_eight;    
    
    hyper_trap : in std_logic;
    cpu_hypervisor_mode : out std_logic := '0';
    matrix_trap_in : in std_logic;
    hyper_trap_f011_read : in std_logic;
    hyper_trap_f011_write : in std_logic;
    protected_hardware : out unsigned(7 downto 0) := "00000000"; -- matrix mode
                                                                 -- + secure
                                                                 -- mode enabled
	 --Protected Hardware Bits
         --Bit 0: TBD
         --Bit 1: TBD
	 --Bit 2: TBD
	 --Bit 3: TBD
	 --Bit 4: TBD
	 --Bit 5: TBD
	 --Bit 6: Matrix Mode
	 --Bit 7: Secure Mode enable 
    virtualised_hardware : out unsigned(7 downto 0) := "00000000";
         --Bit 0: Trap on F011 FDC read/write

    secure_mode_out : out std_logic := '0';
    matrix_rain_seed : out unsigned(15 downto 0) := (others => '0');
    
    iomode_set : out std_logic_vector(1 downto 0) := "11";
    iomode_set_toggle : out std_logic := '0';

    cpuis6502 : out std_logic := '0';
    cpuspeed : out unsigned(7 downto 0) := x"50";

    irq_hypervisor : in std_logic_vector(2 downto 0) := "000";    -- JBM

    no_hyppo : in std_logic;

    reg_isr_out : in unsigned(7 downto 0);
    imask_ta_out : in std_logic;

    monitor_char : out unsigned(7 downto 0);
    monitor_char_toggle : out std_logic;
    monitor_char_busy : in std_logic;
    
      monitor_proceed : out std_logic;
      monitor_waitstates : out unsigned(7 downto 0);
      monitor_request_reflected : out std_logic;
      monitor_hypervisor_mode : out std_logic;
      monitor_pc : out unsigned(15 downto 0) := x"DEAD";
      monitor_state : out unsigned(15 downto 0) := x"FFFF";
      monitor_instruction : out unsigned(7 downto 0) := x"FF";
      monitor_watch : in unsigned(27 downto 0);
      monitor_watch_match : out std_logic := '0';
      monitor_instructionpc : out unsigned(15 downto 0) := x"DEAD";
      monitor_opcode : out unsigned(7 downto 0) := x"EA";
      monitor_ibytes : out std_logic_vector(3 downto 0) := "0000";
      monitor_arg1 : out unsigned(7 downto 0) := x"FF";
      monitor_arg2 : out unsigned(7 downto 0) := x"FF";
      monitor_a : out unsigned(7 downto 0) := x"FF";
      monitor_b : out unsigned(7 downto 0) := x"FF";
      monitor_x : out unsigned(7 downto 0) := x"FF";
      monitor_y : out unsigned(7 downto 0) := x"FF";
      monitor_z : out unsigned(7 downto 0) := x"FF";
      monitor_sp : out unsigned(15 downto 0) := x"FFFF";
      monitor_p : out unsigned(7 downto 0) := x"FF";
      monitor_map_offset_low : out unsigned(11 downto 0) := x"FFF";
      monitor_map_offset_high : out unsigned(11 downto 0) := x"FFF";
      monitor_map_enables_low : out std_logic_vector(3 downto 0) := "1111";
      monitor_map_enables_high : out std_logic_vector(3 downto 0) := "1111";
      monitor_interrupt_inhibit : out std_logic := '0';
      monitor_memory_access_address : out unsigned(31 downto 0);

      ---------------------------------------------------------------------------
      -- Memory access interface used by monitor
      ---------------------------------------------------------------------------
      monitor_mem_address : in unsigned(27 downto 0);
      monitor_mem_rdata : out unsigned(7 downto 0) := x"FF";
      monitor_mem_wdata : in unsigned(7 downto 0);
      monitor_mem_read : in std_logic;
      monitor_mem_write : in std_logic;
      monitor_mem_setpc : in std_logic;
      monitor_mem_attention_request : in std_logic;
      monitor_mem_attention_granted : out std_logic := '0';
      monitor_irq_inhibit : in std_logic;
      monitor_mem_trace_mode : in std_logic;
      monitor_mem_stage_trace_mode : in std_logic;
      monitor_mem_trace_toggle : in std_logic;
    
    ---------------------------------------------------------------------------
    -- Interface to ChipRAM in video controller (just 128KB for now)
    ---------------------------------------------------------------------------
    chipram_we : OUT STD_LOGIC := '0';

    chipram_clk : IN std_logic;
    chipram_address : IN unsigned(19 DOWNTO 0) := to_unsigned(0,20);
    chipram_dataout : OUT unsigned(7 DOWNTO 0);

    cpu_leds : out std_logic_vector(3 downto 0) := "1111";

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
    
    support_f018b : inout std_logic := '0';

    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : inout std_logic_vector(19 downto 0);
    fastio_addr_fast : inout std_logic_vector(19 downto 0);
    fastio_read : out std_logic := '0';
    fastio_write : out std_logic := '0';
    fastio_wdata : out std_logic_vector(7 downto 0);
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
    slow_access_wdata : out unsigned(7 downto 0) := x"FF";
    slow_access_rdata : in unsigned(7 downto 0);
    
    ---------------------------------------------------------------------------
    -- VIC-III memory banking control
    ---------------------------------------------------------------------------
    viciii_iomode : in std_logic_vector(1 downto 0);

    colourram_at_dc00 : in std_logic;
    rom_at_e000 : in std_logic;
    rom_at_c000 : in std_logic;
    rom_at_a000 : in std_logic;
    rom_at_8000 : in std_logic;

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
    -- IO port to far call stack
    ---------------------------------------------------------------------------
    farcallstack_we : out std_logic := '0';
    farcallstack_addr : out std_logic_vector(8 downto 0) := (others => '0');
    farcallstack_din : out std_logic_vector(63 downto 0) := (others => '0');
    farcallstack_dout : in std_logic_vector(63 downto 0) := (others => '0')

    );
end entity gs4510;

architecture Behavioural of gs4510 is
  
  signal last_fastio_addr : std_logic_vector(19 downto 0)  := (others => '0');
  signal last_write_address : unsigned(27 downto 0)  := (others => '0');

  -- For instruction-accurate CPU timing at 1MHz and 3.5MHz
  constant pal1mhz_times_65536 : integer := 64569;
  constant pal2mhz_times_65536 : integer := 64569 * 2;
  constant pal3point5mhz_times_65536 : integer := 225992;
  constant phi_fraction_01pal : unsigned(16 downto 0) :=
    to_unsigned(pal1mhz_times_65536 / cpufrequency,17);
  constant phi_fraction_02pal : unsigned(16 downto 0) :=
    to_unsigned(pal2mhz_times_65536 / cpufrequency,17);
  constant phi_fraction_04pal : unsigned(16 downto 0) :=
    to_unsigned(pal3point5mhz_times_65536 / cpufrequency,17);
  signal phi_counter : unsigned(16 downto 0) := (others => '0');
  signal phi_pause : std_logic := '0';
  signal phi_backlog : integer range 0 to 127 := 0;
  signal phi_add_backlog : std_logic := '0';
  signal phi_new_backlog : integer range 0 to 15 := 0;
  signal last_phi16 : std_logic := '0';

  -- IO has one waitstate for reading, 0 for writing
  -- (Reading incurrs an extra waitstate due to read_data_copy)
  -- XXX An extra wait state seems to be necessary when reading from dual-port
  -- memories like colour ram.
  constant ioread_48mhz : unsigned(7 downto 0) := x"01";
  constant colourread_48mhz : unsigned(7 downto 0) := x"02";
  constant iowrite_48mhz : unsigned(7 downto 0) := x"00";

  signal io_read_wait_states : unsigned(7 downto 0) := ioread_48mhz;
  signal colourram_read_wait_states : unsigned(7 downto 0) := colourread_48mhz;
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
  
  -- Information about instruction currently being executed
  signal reg_opcode : unsigned(7 downto 0)  := (others => '0');
  signal reg_arg1 : unsigned(7 downto 0)  := (others => '0');
  signal reg_arg2 : unsigned(7 downto 0)  := (others => '0');

-- Indicate source of operand for instructions
-- Note that ROM is actually implemented using
-- power-on initialised RAM in the FPGA mapped via our io interface.
  signal accessing_fastio : std_logic;
  signal accessing_vic_fastio : std_logic;
  signal accessing_colour_ram_fastio : std_logic;
--  signal accessing_ram : std_logic;
  signal accessing_slowram : std_logic;
  signal accessing_shadow : std_logic;
  signal accessing_hyppo_fastio : std_logic;
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
  signal mem_reading_p : std_logic := '0';
  -- serial monitor is reading data 
  signal monitor_mem_reading : std_logic := '0';

  -- Is CPU free to proceed with processing an instruction?
  signal proceed : std_logic := '1';

  signal read_data_copy : unsigned(7 downto 0);
  
  type memory_source is (
    DMAgicRegister,
    HypervisorRegister,
    CPUPort,
    Shadow,
    ROMRAM,
    FastIO,
    Hyppo,
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

    -- Normal instructions
    InstructionWait,                    -- Wait for PC to become available on
                                        -- interrupt/reset
    ProcessorHold,
    MonitorMemoryAccess,
    Pause
    );
  signal state : processor_state := ResetLow;
  
  signal monitor_mem_attention_request_drive : std_logic;
  signal monitor_mem_read_drive : std_logic;
  signal monitor_mem_write_drive : std_logic;
  signal monitor_mem_setpc_drive : std_logic;
  signal monitor_mem_address_drive : unsigned(27 downto 0);
  signal monitor_mem_wdata_drive : unsigned(7 downto 0);

  signal monitor_char_toggle_internal : std_logic := '1';

  signal gated_exrom : std_logic := '0';
  signal gated_game : std_logic := '0';
  signal cartridge_enable : std_logic := '0';
  
begin

  
  process(clock,reset,reg_a,reg_x,reg_y,reg_z,flag_c)

    procedure reset_cpu_state is
    begin
      colour_ram_cs <= '0';
      fastio_read <= '0';
      fastio_write <= '0';
      chipram_we <= '0';        

      slow_access_request_toggle_drive <= slow_access_ready_toggle_buffer;
      slow_access_write_drive <= '0';
      slow_access_address_drive <= (others => '1');
      slow_access_wdata_drive <= (others => '1');
      slow_access_desired_ready_toggle <= slow_access_ready_toggle;
      
      wait_states <= (others => '0');
      wait_states_non_zero <= '0';
      mem_reading <= '0';
      
    end procedure reset_cpu_state;

    -- purpose: Convert a 16-bit C64 address to native RAM (or I/O or ROM) address
    impure function resolve_address_to_long(short_address : unsigned(15 downto 0);
                                            writeP : boolean)
      return unsigned is 
      variable temp_address : unsigned(27 downto 0);
      variable blocknum : integer;
      variable lhc : std_logic_vector(4 downto 0);
    begin  -- resolve_long_address

      -- Now apply C64-style $01 lines first, because MAP and $D030 take precedence
      blocknum := to_integer(short_address(15 downto 12));

      lhc(4) := gated_exrom;
      lhc(3) := gated_game;
      lhc(2 downto 0) := std_logic_vector(cpuport_value(2 downto 0));
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
          -- IO is always visible in ultimax mode
          if gated_exrom/='1' or gated_game/='0' then
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
                -- Optionally map SIDs to expansion port
                -- if (short_address(11 downto 8) = x"4") and hyper_iomode(2)='1' then
                -- temp_address(27 downto 12) := x"7FFD";
                -- end if;
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
            temp_address(13 downto 12) := unsigned(viciii_iomode);          
          end if;
        else
          -- READING
          -- IO is always visible in ultimax mode
          if gated_exrom/='1' or gated_game/='0' then
            case lhc(2 downto 0) is
              when "000" => temp_address(27 downto 12) := x"000D";  -- READ RAM
              when "001" => temp_address(27 downto 12) := x"002D";  -- CHARROM
              when "010" => temp_address(27 downto 12) := x"002D";  -- CHARROM
              when "011" => temp_address(27 downto 12) := x"002D";  -- CHARROM
              when "100" => temp_address(27 downto 12) := x"000D";  -- READ RAM
              when others =>
                -- All else accesses IO
                -- C64/C65/C65GS I/O is based on which secret knock has been applied
                -- to $D02F
                temp_address(27 downto 12) := x"FFD3";
                temp_address(13 downto 12) := unsigned(viciii_iomode);          
                -- Optionally map SIDs to expansion port
                -- if (short_address(11 downto 8) = x"4") and hyper_iomode(2)='1' then
                -- temp_address(27 downto 12) := x"7FFD";
                -- end if;
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
            temp_address(13 downto 12) := unsigned(viciii_iomode);          
          end if;
        end if;
      end if;

      -- C64 KERNEL
      if reg_map_high(3)='0' then
        if ((blocknum=14) or (blocknum=13)) and ((gated_exrom='1') and (gated_game='0')) then
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
            ((gated_exrom='1') and (gated_game='0'))
            or ((gated_exrom='0') and (lhc(1 downto 0)="11"))
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
        if ((blocknum=10) or (blocknum=11))
          and ((gated_exrom='0') and (gated_game='0'))            
        then
          -- ULTIMAX mode or cartridge external ROM
          temp_address(27 downto 16) := x"7FF";          
        end if;
      end if;

      -- Expose remaining address space to cartridge port in ultimax mode
      if (gated_exrom='1') and (gated_game='0') then
        if (reg_map_low(0)='0') and  blocknum=1 then
          -- $1000 - $1FFF Ultimax mode
          temp_address(27 downto 16) := x"7FF";
        end if;
        if (reg_map_low(1)='0') and (blocknum=2 or blocknum=3) then
          -- $2000 - $3FFF Ultimax mode
          temp_address(27 downto 16) := x"7FF";
        end if;
        if (reg_map_low(2)='0') and (blocknum=4 or blocknum=5) then
          -- $4000 - $5FFF Ultimax mode
        temp_address(27 downto 16) := x"7FF";
        end if;
        if (reg_map_low(3)='0') and (blocknum=6 or blocknum=7) then
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
            
      return temp_address;
    end resolve_address_to_long;

    procedure read_long_address(
      real_long_address : in unsigned(27 downto 0)) is
      variable long_address : unsigned(27 downto 0);
    begin

      -- Stop writing when reading.     
      fastio_write <= '0';

      if real_long_address(27 downto 12) = x"001F" and real_long_address(11)='1' then
        -- colour ram access: remap to $FF80000 - $FF807FF
        long_address := x"FF80"&'0'&real_long_address(10 downto 0);
		  -- also remap to $7F40000 - $7F407FF
      elsif real_long_address(27 downto 16) = x"7F4" then
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
      if (long_address(27 downto 8) = x"FFD17") or (long_address(27 downto 8) = x"FFD27") or (long_address(27 downto 8) = x"FFD37") then
        report "Preparing to read from a DMAgicRegister";
        read_source <= DMAgicRegister;
      end if;      

      report "MEMORY long_address = $" & to_hstring(long_address);
      -- @IO:C64 $0000000 6510/45GS10 CPU port DDR
      -- @IO:C64 $0000001 6510/45GS10 CPU port data
      if (long_address(27 downto 6)&"00" = x"FFD364" or long_address(27 downto 6)&"00" = x"FFD264") and hypervisor_mode='1' then
        report "Preparing for reading hypervisor register";
        read_source <= HypervisorRegister;
        accessing_hypervisor <= '1';
        -- One cycle wait-state on hypervisor registers to remove the register
        -- decode from the critical path of memory access.
        wait_states <= x"01";
        wait_states_non_zero <= '1';
        proceed <= '0';
        hyperport_num <= real_long_address(5 downto 0);
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
      elsif long_address(27 downto 20) = x"FF" then
        report "Preparing to read from FastIO";
        read_source <= FastIO;
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

        -- @IO:GS $FF8xxxx - Colour RAM (32KB or 64KB)
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
        -- @IO:GS $FFF8000-$FFFBFFF 16KB Hyppo/Hypervisor ROM
        if long_address(19 downto 14)&"00" = x"F8" then
          accessing_fastio <= '0';
          fastio_read <= '0';
          accessing_hyppo_fastio <= '1';
          read_source <= Hyppo;
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
          end if;                         -- $D{0,1,2,3}XXX
        end if;                           -- $DXXXX
        fastio_addr <= std_logic_vector(long_address(19 downto 0));
        last_fastio_addr <= std_logic_vector(long_address(19 downto 0));
        fastio_read <= '1';
        proceed <= '0';
      elsif long_address(27) = '1' or long_address(26)='1' then
        -- @IO:GS $4000000 - $7FFFFFF Slow Device memory (64MB)
        -- @IO:GS $8000000 - $FEFFFFF Slow Device memory (127MB)
        report "Preparing to read from SlowRAM";
        read_source <= SlowRAM;
        accessing_slowram <= '1';
        accessing_shadow <= '0';
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
        wait_states <= x"00";
        wait_states_non_zero <= '0';
        proceed <= '1';
      end if;

    end read_long_address;
    
    impure function read_data
      return unsigned is
    begin  -- read_data
      case read_source is
        when Shadow => return x"53";
        when ROMRAM => return x"52";
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
            when others => return x"ff";
          end case;
        when HypervisorRegister =>
          report "HYPERPORT: Reading hypervisor register";
          return x"FF";
        when CPUPort =>
          report "reading from CPU port" severity note;
          case cpuport_num is
            when x"0" => return cpuport_ddr;
            when x"1" => return cpuport_value;
            when others => return x"ff";
          end case;
        when Shadow =>
          report "reading from shadow RAM" severity note;
--          return shadow_rdata;
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
        when others =>
          report "accessing unmapped memory" severity note;
          return x"AA";                     -- make unmmapped memory obvious
      end case;
    end read_data_complex; 

    procedure write_long_byte(
      real_long_address       : in unsigned(27 downto 0);
      value              : in unsigned(7 downto 0)) is
      variable long_address : unsigned(27 downto 0);
    begin
      -- Schedule the memory write to the appropriate destination.

      accessing_fastio <= '0'; accessing_vic_fastio <= '0';
      accessing_cpuport <= '0'; accessing_colour_ram_fastio <= '0';
      accessing_shadow <= '0'; accessing_hyppo_fastio <= '0';
      accessing_slowram <= '0';
      slow_access_write_drive <= '0';
      charrom_write_cs <= '0';

      wait_states <= x"00";
      wait_states_non_zero <= '0';

      report "real_long_address for write = $" & to_hstring(real_long_address);
      if
        -- FF80000-FF807FF = 2KB colour RAM at times, which overlaps chip RAM
        -- XXX - We don't handle the 2nd KB colour RAM at $DC00 when mapped
        (real_long_address(27 downto 12) = x"FF80" and real_long_address(11) = '0')
        or
        -- FFD[0-3]800-BFF
        (real_long_address(27 downto 16) = x"FFD"
         and real_long_address(15 downto 14) = "11"
         and real_long_address(11 downto 10) = "10")        
      then
        report "Writing to colour RAM";

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

      last_write_address <= real_long_address;

      -- Write to CPU port
      if (long_address = x"0000000") then
        report "MEMORY: Writing to CPU DDR register" severity note;
        cpuport_ddr <= value;
      elsif (long_address = x"0000001") then
        report "MEMORY: Writing to CPU PORT register" severity note;
        cpuport_value <= value;
      elsif (long_address = x"0000002") then
        report "MEMORY: Writing to CPU PORT register" severity note;
        protected_hardware <= value;
      end if;
      
      if long_address(27 downto 17)="00000000000" or (long_address(27 downto 17)="01111111000" and hypervisor_mode='1') then
        report "writing to shadow RAM via chipram shadowing. addr=$" & to_hstring(long_address) severity note;
        fastio_write <= '0';
        report "writing to chipram..." severity note;
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


      --Also mapped to 7F20000-7F3FFFF (is this for 1MB linear address space
      --for task switching?)
      elsif long_address(27 downto 17)="00000000001" or long_address(27 downto 17)="01111111001" then
        report "writing to ROM. addr=$" & to_hstring(long_address) severity note;
        -- rom_write <= not rom_writeprotect;
        fastio_write <= '0';        
      elsif long_address(27 downto 24) = x"F" then --
        accessing_fastio <= '1';
        fastio_addr <= std_logic_vector(long_address(19 downto 0));
        last_fastio_addr <= std_logic_vector(long_address(19 downto 0));
        fastio_write <= '1'; fastio_read <= '0';
        report "raising fastio_write" severity note;
        fastio_wdata <= std_logic_vector(value);

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

                -- Write also to CHIP RAM, so that $1F800-FFF works as chipRAM
                -- as well as colour RAM, when accessed via $D800+ portal
                report "writing to chipram..." severity note;
                
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
      elsif long_address(27) = '1' or long_address(26)='1' then
        report "writing to slow device memory..." severity note;
        accessing_slowram <= '1';
        fastio_write <= '0';
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
        null;
      end if;
    end write_long_byte;
        
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
    
    -- BEGINNING OF MAIN PROCESS FOR CPU
    if rising_edge(clock) and all_pause='0' then

      if cartridge_enable='1' then
        gated_exrom <= exrom;
        gated_game <= game;
      else
        gated_exrom <= '1';
        gated_game <= '1';
      end if;
      
      -- Count slow clock ticks for applying instruction-level 6502/4510 timing
      -- accuracy at 1MHz and 3.5MHz
      -- XXX Add NTSC speed emulation option as well
      phi_add_backlog <= '0';
      phi_new_backlog <= 0;
      last_phi16 <= phi_counter(16);

      -- Full speed = 1 clock tick per cycle
      phi_counter(16) <= phi_counter(16) xor '1';
      phi_backlog <= 0;
      phi_pause <= '0';

      -- Full speed - never pause
      phi_backlog <= 0;
      phi_pause <= '0';
          
      -- If the serial monitor interface has received the character, we can clear
      -- our temporary busy flag, then rely upon the serial monitor to deassert
      -- the "monitor_char_busy" signal when it has finished sending the char,
      if monitor_char_busy = '1' then
        -- immediate_monitor_char_busy <= '0';
      end if;

      -- Propagate slow device access interface signals
      slow_access_request_toggle <= slow_access_request_toggle_drive;
      slow_access_address <= slow_access_address_drive;
      slow_access_write <= slow_access_write_drive;
      slow_access_wdata <= slow_access_wdata_drive;
      slow_access_ready_toggle_buffer <= slow_access_ready_toggle;

      -- virtualised_hardware(0) <= virtualise_sd;
      virtualised_hardware(7 downto 0) <= (others => '0');
      cpu_hypervisor_mode <= hypervisor_mode;
            
      monitor_mem_attention_request_drive <= monitor_mem_attention_request;
      monitor_mem_read_drive <= monitor_mem_read;
      monitor_mem_write_drive <= monitor_mem_write;
      monitor_mem_setpc_drive <= monitor_mem_setpc;
      monitor_mem_address_drive <= monitor_mem_address;
      monitor_mem_wdata_drive <= monitor_mem_wdata;
            
      -- Copy read memory location to simplify reading from memory.
      -- Penalty is +1 wait state for memory other than shadowram.
      read_data_copy <= read_data_complex;
      
      memory_access_read := '0';
      memory_access_write := '0';
      memory_access_resolve_address := '0';
      
      monitor_watch_match <= '0';       -- set if writing to watched address
      monitor_state <= to_unsigned(processor_state'pos(state),8)&read_data;
      
      -------------------------------------------------------------------------
      -- Real CPU work begins here.
      -------------------------------------------------------------------------

      monitor_waitstates <= wait_states;

      -- Catch the CPU when it goes to the next instruction if single stepping.
      if (monitor_mem_trace_mode='0' or
          monitor_mem_trace_toggle_last /= monitor_mem_trace_toggle)
        and (monitor_mem_attention_request_drive='0') then
        monitor_mem_trace_toggle_last <= monitor_mem_trace_toggle;
      end if;

      if mem_reading='1' then
        memory_read_value := read_data;
      end if;

      if phi_pause = '0' then
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
          chipram_we <= '0';
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
        
        if proceed='1' then
          -- Main state machine for CPU
          report "CPU state = " & processor_state'image(state) & ", PC=$" & to_hstring(reg_pc) severity note;

          -- By default read next byte in instruction stream.
          memory_access_read := '1';
          memory_access_address := x"000"&reg_pc;
          memory_access_resolve_address := '1';

          case state is
            when ResetLow =>
              -- Reset now maps hyppo at $8000-$BFFF, and enters through $8000
              -- by triggering the hypervisor.
              -- XXX indicate source of hypervisor entry
              reset_cpu_state;
              state <= ProcessorHold;
            when ProcessorHold =>
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
            when others =>
              state <= ProcessorHold;
          end case;
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

          if memory_access_resolve_address = '1' then
            memory_access_address := resolve_address_to_long(memory_access_address(15 downto 0),true);
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
