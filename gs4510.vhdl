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
    io_wait_states : in unsigned(7 downto 0);
    reset : in std_logic;
    irq : in std_logic;
    nmi : in std_logic;
    monitor_pc : out std_logic_vector(15 downto 0);
    monitor_state : out unsigned(7 downto 0);
    monitor_watch : in std_logic_vector(27 downto 0);
    monitor_watch_match : out std_logic;
    monitor_waitstates : out unsigned(7 downto 0);
    monitor_proceed : out std_logic;
    monitor_request_reflected : out std_logic;
    monitor_opcode : out std_logic_vector(7 downto 0);
    monitor_ibytes : out std_logic_vector(3 downto 0);
    monitor_arg1 : out std_logic_vector(7 downto 0);
    monitor_arg2 : out std_logic_vector(7 downto 0);
    monitor_a : out std_logic_vector(7 downto 0);
    monitor_x : out std_logic_vector(7 downto 0);
    monitor_y : out std_logic_vector(7 downto 0);
    monitor_z : out std_logic_vector(7 downto 0);
    monitor_b : out std_logic_vector(7 downto 0);
    monitor_sp : out std_logic_vector(15 downto 0);
    monitor_p : out std_logic_vector(7 downto 0);
    monitor_interrupt_inhibit : out std_logic;
    monitor_map_offset_low : out std_logic_vector(11 downto 0);
    monitor_map_offset_high : out std_logic_vector(11 downto 0);
    monitor_map_enables_low : out std_logic_vector(3 downto 0);
    monitor_map_enables_high : out std_logic_vector(3 downto 0);   
    
    ---------------------------------------------------------------------------
    -- Memory access interface used by monitor
    ---------------------------------------------------------------------------
    monitor_mem_address : in std_logic_vector(27 downto 0);
    monitor_mem_rdata : out unsigned(7 downto 0);
    monitor_mem_wdata : in unsigned(7 downto 0);
    monitor_mem_read : in std_logic;
    monitor_mem_write : in std_logic;
    monitor_mem_setpc : in std_logic;
    monitor_mem_attention_request : in std_logic;
    monitor_mem_attention_granted : out std_logic := '0';
    monitor_mem_trace_mode : in std_logic;
    monitor_mem_stage_trace_mode : in std_logic;
    monitor_mem_trace_toggle : in std_logic;

    monitor_debug_memory_access : out std_logic_vector(31 downto 0);
    
    ---------------------------------------------------------------------------
    -- Interface to FastRAM in video controller (just 128KB for now)
    ---------------------------------------------------------------------------
    fastramwaitstate : in std_logic;
    fastram_we : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) := x"00";
    fastram_address : OUT STD_LOGIC_VECTOR(13 DOWNTO 0) := "00000000000000";
    fastram_datain : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    fastram_dataout : IN STD_LOGIC_VECTOR(63 DOWNTO 0) := x"0000000000000000";

    ---------------------------------------------------------------------------
    -- Interface to Slow RAM (16MB cellular RAM chip)
    ---------------------------------------------------------------------------
    slowram_addr : out std_logic_vector(22 downto 0);
    slowram_we : out std_logic := '0';
    slowram_ce : out std_logic := '0';
    slowram_oe : out std_logic := '0';
    slowram_lb : out std_logic := '0';
    slowram_ub : out std_logic := '0';
    slowram_data : inout std_logic_vector(15 downto 0);
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : inout std_logic_vector(19 downto 0);
    fastio_read : inout std_logic;
    fastio_write : inout std_logic;
    fastio_wdata : out std_logic_vector(7 downto 0);
    fastio_rdata : in std_logic_vector(7 downto 0);
    fastio_sd_rdata : in std_logic_vector(7 downto 0);
    sector_buffer_mapped : in std_logic;
    fastio_vic_rdata : in std_logic_vector(7 downto 0);
    fastio_colour_ram_rdata : in std_logic_vector(7 downto 0);
    colour_ram_cs : out std_logic;

    viciii_iomode : in std_logic_vector(1 downto 0);

    colourram_at_dc00 : in std_logic;
    rom_at_e000 : in std_logic;
    rom_at_c000 : in std_logic;
    rom_at_a000 : in std_logic;
    rom_at_8000 : in std_logic
    );
end entity gs4510;

architecture Behavioural of gs4510 is

  component microcode is
    port (Clk : in std_logic;
          address : in instruction;
          data_o : out microcodeops
          );
  end component;
  
  component shadowram is
    port (Clk : in std_logic;
          address : in std_logic_vector(17 downto 0);            
          we : in std_logic;
          -- chip select, active low       
          cs : in std_logic;
          data_i : in std_logic_vector(7 downto 0);
          data_o : out std_logic_vector(7 downto 0)
          );
  end component;
  
  signal kickstart_en : std_logic := '1';

--  signal fastram_last_address : std_logic_vector(13 downto 0);

  -- Shadow RAM control
  signal shadow_bank : unsigned(7 downto 0);
  signal shadow_address : unsigned(17 downto 0);
  signal shadow_rdata : unsigned(7 downto 0);
  signal shadow_wdata : unsigned(7 downto 0);
  signal shadow_write : std_logic := '0';
  
  signal last_fastio_addr : std_logic_vector(19 downto 0);

  signal slowram_lohi : std_logic;
  -- SlowRAM has 70ns access time, so need some wait states.
  -- Allow 9 waits for now in case ram part is the 85ns version.
  -- At 64MHz we only need 6 cycles
  signal slowram_waitstates : unsigned(7 downto 0) := x"06";

  -- Number of pending wait states
  signal wait_states : unsigned(7 downto 0) := x"05";
  
  signal fastram_byte_number : unsigned(2 DOWNTO 0);

  signal word_flag : std_logic := '0';

  -- DMAgic registers
  signal reg_dmagic_addr : unsigned(27 downto 0) := x"0000000";
  signal reg_dmagic_withio : std_logic;
  signal reg_dmagic_status : unsigned(7 downto 0) := x"00";
  signal reg_dmacount : unsigned(7 downto 0) := x"00";  -- number of DMA jobs done
  signal dma_pending : std_logic := '0';
  signal dma_checksum : unsigned(23 downto 0) := x"000000";
  signal dmagic_cmd : unsigned(7 downto 0);
  signal dmagic_count : unsigned(15 downto 0);
  signal dmagic_tally : unsigned(15 downto 0);
  signal dmagic_src_addr : unsigned(27 downto 0);
  signal dmagic_src_io : std_logic;
  signal dmagic_src_direction : std_logic;
  signal dmagic_src_modulo : std_logic;
  signal dmagic_src_hold : std_logic;
  signal dmagic_dest_addr : unsigned(27 downto 0);
  signal dmagic_dest_io : std_logic;
  signal dmagic_dest_direction : std_logic;
  signal dmagic_dest_modulo : std_logic;
  signal dmagic_dest_hold : std_logic;
  signal dmagic_modulo : unsigned(15 downto 0);

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

  -- Flags to detect interrupts
  signal map_interrupt_inhibit : std_logic := '0';
  signal nmi_pending : std_logic := '0';
  signal irq_pending : std_logic := '0';
  signal nmi_state : std_logic := '1';
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
  -- Temporary value holder (used for RMW instructions)
  signal reg_t : unsigned(7 downto 0);

  signal instruction_phase : unsigned(3 downto 0);
  
-- Indicate source of operand for instructions
-- Note that ROM is actually implemented using
-- power-on initialised RAM in the FPGA mapped via our io interface.
  signal accessing_shadow : std_logic;
  signal accessing_fastio : std_logic;
  signal accessing_sb_fastio : std_logic;
  signal accessing_vic_fastio : std_logic;
  signal accessing_colour_ram_fastio : std_logic;
--  signal accessing_ram : std_logic;
  signal accessing_slowram : std_logic;
  signal accessing_cpuport : std_logic;
  signal cpuport_num : std_logic;
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
  signal mem_reading_pcl : std_logic := '0';
  signal mem_reading_pch : std_logic := '0';
  -- serial monitor is reading data 
  signal monitor_mem_reading : std_logic := '0';

  -- Is CPU free to proceed with processing an instruction?
  signal proceed : std_logic := '1';

  signal read_data_copy : unsigned(7 downto 0);
  
  type instruction_property is array(0 to 255) of std_logic;
  signal op_is_single_cycle : instruction_property := (
    16#03# => '1',
    16#0B# => '1',
    16#18# => '1',
    16#1A# => '1',
    16#1B# => '1',
    16#2B# => '1',
    16#38# => '1',
    16#3A# => '1',
    16#3B# => '1',
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
    16#CA# => '1',
    16#D8# => '1',
    16#E8# => '1',
    16#EA# => '1',
    16#F8# => '1',
    others => '0'
    );
  
  type processor_state is (
    -- Reset and interrupts
    ResetLow,
    ResetReady,
    Interrupt,
    VectorRead1,
    VectorRead2,

    -- DMAgic
    DMAgicTrigger,DMAgicReadList,DMAgicRead,DMAgicWrite,

    -- Normal instructions
    InstructionWait,                    -- Wait for PC to become available on
                                        -- interrupt/reset
    ProcessorHold,
    MonitorMemoryAccess,
    InstructionFetch,
    InstructionDecode,
    Cycle2,
    Push,Pull,
    RTI,RTS1,RTS2,
    B16TakeBranch,
    InnYReadVectorLow,
    InnZReadVectorLow,
    CallSubroutine0,CallSubroutine,CallSubroutine2,
    ZPRelReadZP,
    AbsReadArg2,
    AbsXReadArg2,
    AbsYReadArg2,
    IAbsReadArg2,
    IAbsXReadArg2,
    Imm16ReadArg2,
    TakeBranch8,
    ActionCycle,
    DelayedWrite
    );
  signal state : processor_state := ResetLow;
  signal fast_fetch_state : processor_state := InstructionDecode;
  signal normal_fetch_state : processor_state := InstructionFetch;
  
  signal reg_microcode : microcodeops;
  signal reg_microcode_address : instruction;

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
  
  constant instruction_lut : ilut8bit := (
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
    I_BEQ,I_SBC,I_SBC,I_BEQ,I_PHW,I_SBC,I_INC,I_SMB,I_SED,I_SBC,I_PLX,I_PLZ,I_PHW,I_SBC,I_INC,I_BBS);

  
  type mlut8bit is array(0 to 255) of addressingmode;
  constant mode_lut : mlut8bit := (
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
    M_rr,    M_InnY,  M_InnY,  M_rrrr,  M_nnX,   M_nnX,   M_nnY,   M_nn,    
    M_impl,  M_nnnnY, M_impl,  M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnY, M_nnrr,  
    M_immnn, M_InnX,  M_immnn, M_nn,    M_nn,    M_nn,    M_nn,    M_nn,    
    M_impl,  M_immnn, M_impl,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnrr,  
    M_rr,    M_InnY,  M_InnZ,  M_rrrr,  M_nn,    M_nnX,   M_nnX,   M_nn,    
    M_impl,  M_nnnnY, M_impl,  M_impl,  M_nnnn,  M_nnnnX, M_nnnnX, M_nnrr,  
    M_immnn, M_InnX,  M_InnSPY,M_nn,    M_nn,    M_nn,    M_nn,    M_nn,    
    M_impl,  M_immnn, M_impl,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,  M_nnrr,  
    M_rr,    M_InnY,  M_InnZ,  M_rrrr,  M_immnnnn,M_nnX,   M_nnX,   M_nn,    
    M_impl,  M_nnnnY, M_impl,  M_impl,  M_nnnn,  M_nnnnX, M_nnnnX, M_nnrr);

  signal reg_addressingmode : addressingmode;
  signal reg_instruction : instruction;

  signal is_rmw : std_logic;
  signal is_load : std_logic;
  signal is_store : std_logic;
  signal rmw_dummy_write_done : std_logic;
  
  signal delayed_write_resolve : std_logic;
  signal delayed_write_address : unsigned(27 downto 0);
  signal delayed_write_wdata : unsigned(7 downto 0);

  signal a_incremented : unsigned(7 downto 0);
  signal a_decremented : unsigned(7 downto 0);
  signal a_negated : unsigned(7 downto 0);
  signal a_ror : unsigned(7 downto 0);
  signal a_rol : unsigned(7 downto 0);
  signal a_asl : unsigned(7 downto 0);
  signal a_asr : unsigned(7 downto 0);
  signal a_lsr : unsigned(7 downto 0);
  
  signal x_incremented : unsigned(7 downto 0);
  signal x_decremented : unsigned(7 downto 0);
  signal y_incremented : unsigned(7 downto 0);
  signal y_decremented : unsigned(7 downto 0);
  signal z_incremented : unsigned(7 downto 0);
  signal z_decremented : unsigned(7 downto 0);
  
begin

  shadowram0 : shadowram port map (
    clk     => clock,
    address => std_logic_vector(shadow_address),
    we      => shadow_write,
    cs      => '1',
    data_i  => std_logic_vector(shadow_wdata),
    unsigned(data_o)  => shadow_rdata);

  microcode0: microcode port map (
    clk => clock,
    address => reg_microcode_address,
    data_o => reg_microcode);
  
  process(clock,reset)
    procedure reset_cpu_state is
    begin
      -- Set microcode state for reset
      -- This is a little bit fun because we need to basically make an opcode for
      -- reset.  $FF in CPU personality 3 will do the trick.

      instruction_phase <= x"0";
      
      -- Default register values
      reg_b <= x"00";
      reg_a <= x"11";    
      reg_x <= x"22";
      reg_y <= x"33";
      reg_z <= x"00";
      reg_sp <= x"ff";
      reg_sph <= x"01";
      reg_pc <= x"8765";

      -- Clear CPU MMU registers
      reg_mb_low <= x"00";
      reg_mb_high <= x"00";
      reg_map_low <= "0000";
      reg_map_high <= "0000";
      reg_offset_low <= x"000";
      reg_offset_high <= x"000";

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

      -- Stop memory accesses
      colour_ram_cs <= '0';
      shadow_write <= '0';   
      fastio_read <= '0';
      fastio_write <= '0';
      fastram_we <= (others => '0');        
      fastram_datain <= x"d0d1d2d3d4d5d6d7";    
      slowram_we <= '1';
      slowram_ce <= '1';
      slowram_oe <= '1';
      
      wait_states <= (others => '0');
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
        if irq = '0' then
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
            when "010" => temp_address(27 downto 12) := x"002D";  -- CHARROM
            when "011" => temp_address(27 downto 12) := x"002D";  -- CHARROM
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
        end if;
        if (blocknum=15) and (lhc(1)='1') and (writeP=false) then
          temp_address(27 downto 12) := x"002F";      
        end if;
      end if;
      -- C64 BASIC
      if reg_map_high(1)='0' then
        if (blocknum=10) and (lhc(0)='1') and (lhc(1)='1') and (writeP=false) then
          temp_address(27 downto 12) := x"002A";      
        end if;
        if (blocknum=11) and (lhc(0)='1') and (lhc(1)='1') and (writeP=false) then
          temp_address(27 downto 12) := x"002B";      
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
      
      -- Kickstart ROM (takes precedence over all else if enabled)
      if (blocknum=14) and (kickstart_en='1') and (writeP=false) then
        temp_address(27 downto 12) := x"FFFE";      
      end if;
      if (blocknum=15) and (kickstart_en='1') and (writeP=false) then
        temp_address(27 downto 12) := x"002F";      
        temp_address(27 downto 12) := x"FFFF";      
      end if;
      
      return temp_address;
    end resolve_address_to_long;

    procedure read_long_address(
      real_long_address : in unsigned(27 downto 0)) is
      variable long_address : unsigned(27 downto 0);
    begin
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
      accessing_sb_fastio <= '0'; accessing_shadow <= '0';
      accessing_slowram <= '0';
      wait_states <= io_wait_states;
      
      the_read_address <= long_address;

      -- Get the shadow RAM address on the bus fast to improve timing.
      shadow_write <= '0';
      shadow_address <= long_address(17 downto 0);
      
      if long_address(27 downto 16)="0000"&shadow_bank then
        -- Reading from 256KB shadow ram (which includes 128KB fixed shadowing of
        -- chipram).  This is the only memory running at the CPU's native clock.
        -- Think of it as a kind of direct-mapped L1 cache.
        accessing_shadow <= '1';
        wait_states <= x"00";
        proceed <= '1';
        report "Reading from shadow ram address $" & to_hstring(long_address(17 downto 0))
          & ", word $" & to_hstring(long_address(18 downto 3)) severity note;
      elsif long_address(27 downto 17)="00000000000" then
        -- Reading from chipram, so read from the bottom 128KB of the shadow RAM
        -- instead.
        accessing_shadow <= '1';
        -- shadow_address <= '0'&long_address(16 downto 0);
        shadow_write <= '0';
        proceed <= '1';        
        report "Reading from shadowed fastram address $" & to_hstring(long_address(19 downto 0))
          & ", word $" & to_hstring(long_address(18 downto 3)) severity note;
      elsif long_address(27 downto 24) = x"8"
        or long_address(27 downto 17)&'0' = x"002" then
        -- Slow RAM maps to $8xxxxxx, and also $0020000 - $003FFFF for C65 ROM
        -- emulation.
        accessing_slowram <= '1';
        slowram_addr <= std_logic_vector(long_address(23 downto 1));
        slowram_data <= (others => 'Z');  -- tristate data lines
        slowram_we <= '1';
        slowram_ce <= '0';
        slowram_oe <= '0';
        slowram_lb <= '0';
        slowram_ub <= '0';
        slowram_lohi <= long_address(0);
        wait_states <= slowram_waitstates;
        proceed <= '0';
      elsif long_address(27 downto 20) = x"FF" then
        accessing_fastio <= '1';
        accessing_vic_fastio <= '0';
        accessing_sb_fastio <= '0';
        accessing_colour_ram_fastio <= '0';
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
          colour_ram_cs <= '1';
        end if;
        if long_address(19 downto 8) = x"30E" or long_address(19
                                                              downto 8) = x"30F" then
          accessing_sb_fastio <= '1';
        end if;
        if long_address(19 downto 8) = x"D3E" or long_address(19
                                                              downto 8) = x"D3F" then
          accessing_sb_fastio <= sector_buffer_mapped and (not colourram_at_dc00);
          report "considering accessing_sb_fastio = " & std_logic'image(sector_buffer_mapped and (not colourram_at_dc00)) severity note;
          report "sector_buffer_mapped = " & std_logic'image(sector_buffer_mapped) severity note;
          report "colourram_at_dc00 = " & std_logic'image(colourram_at_dc00) severity note;
        end if;
        if long_address(19 downto 16) = x"D" then
          if long_address(15 downto 14) = "00" then    --   $D{0,1,2,3}XXX
            if long_address(11 downto 10) = "00" then  --   $D{0,1,2,3}{0,1,2,3}XX
              if long_address(11 downto 7) /= "00001" then  -- ! $D.0{8-F}X (FDC, RAM EX)
                report "VIC register from VIC fastio" severity note;
                accessing_vic_fastio <= '1';
              end if;            
            end if;
            -- Colour RAM at $D800-$DBFF and optionally $DC00-$DFFF
            if long_address(11)='1' then
              if (long_address(10)='0') or (colourram_at_dc00='1') then
                report "D800-DBFF/DC00-DFFF colour ram access from VIC fastio" severity note;
                accessing_colour_ram_fastio <= '1';            
                colour_ram_cs <= '1';
              end if;
            end if;
          end if;                         -- $D{0,1,2,3}XXX
        end if;                           -- $DXXXX
        fastio_addr <= std_logic_vector(long_address(19 downto 0));
        last_fastio_addr <= std_logic_vector(long_address(19 downto 0));
        fastio_read <= '1';
        -- XXX Some fastio (that referencing ioclocked registers) does require
        -- io_wait_states, while some can use fewer waitstates because the
        -- memories involved can be clocked at the CPU clock, and have just 1
        -- wait state due to the dual-port memories.
        -- But for now, just apply the wait state to all fastio addresses.
        wait_states <= io_wait_states;
        proceed <= '0';
      else
        -- Don't let unmapped memory jam things up
        wait_states <= x"00";
        proceed <= '1';
      end if;
    end read_long_address;
    
    procedure read_address (
      address    : in unsigned(15 downto 0)) is
      variable long_address : unsigned(27 downto 0);
    begin  -- read_address
      long_address := resolve_address_to_long(address,false);
      if (long_address = x"0000000") or (long_address = x"0000001") then
        accessing_cpuport <= '1';
        cpuport_num <= address(0);
      else
        read_long_address(long_address);
      end if;
    end read_address;

    impure function read_data
      return unsigned is
    begin  -- read_data
      if accessing_shadow='1' then
        report "reading from shadow RAM" severity note;
        return shadow_rdata;
      else
        return read_data_copy;
      end if;
    end read_data;

    -- purpose: obtain the byte of memory that has been read
    impure function read_data_complex
      return unsigned is
    begin  -- read_data
      -- CPU hosted IO registers
--    if the_read_address = x"FFC00A0" then
--      return slowram_waitstates;
      if (the_read_address = x"FFD3703") or (the_read_address = x"FFD1703") then
        return reg_dmagic_status;
--    elsif (the_read_address = x"FFD370B") then
--      return reg_dmagic_addr(7 downto 0);
--    elsif (the_read_address = x"FFD370C") then
--      return reg_dmagic_addr(15 downto 8);
--    elsif (the_read_address = x"FFD370D") then
--      return reg_dmagic_addr(23 downto 16);
--    elsif (the_read_address = x"FFD370E") then
--      return x"0" & reg_dmagic_addr(27 downto 24);
      elsif (the_read_address = x"FFD37FE") or (the_read_address = x"FFD17FE") then
        return shadow_bank;
      end if;

      if accessing_cpuport='1' then
        if cpuport_num='0' then
          -- DDR
          return cpuport_ddr;
        else
          -- CPU port
          return cpuport_value;
        end if;
      elsif accessing_shadow='1' then
        report "reading from shadow RAM" severity note;
        return shadow_rdata;
      elsif accessing_sb_fastio='1' then
        report "reading sector buffer RAM fastio byte $" & to_hstring(fastio_sd_rdata) severity note;
        return unsigned(fastio_sd_rdata);
      elsif accessing_colour_ram_fastio='1' then 
        report "reading colour RAM fastio byte $" & to_hstring(fastio_vic_rdata) severity note;
        return unsigned(fastio_colour_ram_rdata);
      elsif accessing_vic_fastio='1' then 
--        report "reading VIC fastio byte $" & to_hstring(fastio_vic_rdata) severity note;
        return unsigned(fastio_vic_rdata);
      elsif accessing_fastio='1' then
--        report "reading normal fastio byte $" & to_hstring(fastio_rdata) severity note;
        return unsigned(fastio_rdata);
      elsif accessing_slowram='1' then
--        report "reading slow RAM data. Word is $" & to_hstring(slowram_data) severity note;
        case slowram_lohi is
          when '0' => return unsigned(slowram_data(7 downto 0));
          when '1' => return unsigned(slowram_data(15 downto 8));
          when others => return x"FE";
        end case;
      else
        report "accessing unmapped memory" severity note;
        return x"A0";                     -- make unmmapped memory obvious
      end if;
    end read_data_complex; 

    procedure write_long_byte(
      real_long_address       : in unsigned(27 downto 0);
      value              : in unsigned(7 downto 0)) is
      variable long_address : unsigned(27 downto 0);
    begin
      -- Schedule the memory write to the appropriate destination.

      accessing_fastio <= '0'; accessing_vic_fastio <= '0';
      accessing_cpuport <= '0'; accessing_colour_ram_fastio <= '0';
      accessing_sb_fastio <= '0'; accessing_shadow <= '0';
      accessing_slowram <= '0';
      
      wait_states <= x"00";
      
      if real_long_address(27 downto 12) = x"001F" and real_long_address(11)='1' then
        -- colour ram access: remap to $FF80000 - $FF807FF
        long_address := x"FF80"&'0'&real_long_address(10 downto 0);
      else
        long_address := real_long_address;
      end if;

      -- Write to DMAgic registers if required
      if (long_address = x"FFD3700") or (long_address = x"FFD1700") then
        -- Set low order bits of DMA list address
        reg_dmagic_addr(7 downto 0) <= value;
        -- Remember that after this instruction we want to perform the
        -- DMA.
        dma_pending <= '1';
        dma_checksum <= x"000000";
        reg_dmacount <= reg_dmacount + 1;
      -- NOTE: DMAgic in C65 prototypes might not use the same list format as
      -- in the C65 specifications manual (as the manual warns).
      -- So need to double check how it is used in the C65 ROM.
      -- From the ROMs, it appears that the list format is:
      -- list+$00 = command
      -- list+$01 = count bit7-0
      -- list+$02 = count bit15-8
      -- list+$03 = source address bit7-0
      -- list+$04 = source address bit15-8
      -- list+$05 = source address bank
      -- list+$06 = dest address bit7-0
      -- list+$07 = dest address bit15-8
      -- list+$08 = dest address bank
      -- list+$09 = modulo bit7-0
      -- list+$0a = modulo bit15-8
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
      elsif (long_address = x"FFD37FE") or (long_address = x"FFD17FE") then
        shadow_bank <= value;
      elsif (long_address = x"FFD37ff") or (long_address = x"FFD17ff") then
        -- re-enable kickstart ROM.  This is only to allow for easier development
        -- of kickstart ROMs.
        if value = x"4B" then
          kickstart_en <= '1';        
        end if;
      end if;
      
      -- Always write to shadow ram if in scope, even if we also write elsewhere.
      -- This ensures that shadow ram is consistent with the shadowed address space
      -- when the CPU reads from shadow ram.
      -- Get the shadow RAM address on the bus fast to improve timing.
      shadow_address <= long_address(17 downto 0);
      if long_address(27 downto 16)="0000"&shadow_bank then
        report "writing to shadow RAM via shadow_bank" severity note;
        shadow_write <= '1';
--        shadow_address <= long_address(17 downto 0);
        shadow_wdata <= value;
      end if;
      if long_address(27 downto 17)="00000000000" then
        report "writing to shadow RAM via chipram shadowing. addr=$" & to_hstring(long_address) severity note;
        shadow_write <= '1';
--        shadow_address <= long_address(17 downto 0);
        shadow_wdata <= value;
        
        fastram_address <= std_logic_vector(long_address(16 downto 3));
        fastram_we <= (others => '0');
        fastram_datain <= (others => '1');
        fastram_datain(7 downto 0) <= std_logic_vector(value);
        fastram_datain(15 downto 8) <= std_logic_vector(value);
        fastram_datain(23 downto 16) <= std_logic_vector(value);
        fastram_datain(31 downto 24) <= std_logic_vector(value);
        fastram_datain(39 downto 32) <= std_logic_vector(value);
        fastram_datain(47 downto 40) <= std_logic_vector(value);
        fastram_datain(55 downto 48) <= std_logic_vector(value);
        fastram_datain(63 downto 56) <= std_logic_vector(value);
        case long_address(2 downto 0) is
          when "000" => fastram_we <= "00000001";
          when "001" => fastram_we <= "00000010"; 
          when "010" => fastram_we <= "00000100";
          when "011" => fastram_we <= "00001000";
          when "100" => fastram_we <= "00010000";
          when "101" => fastram_we <= "00100000";
          when "110" => fastram_we <= "01000000";
          when "111" => fastram_we <= "10000000";
          when others =>
            report "dud write to chipram" severity note;
        end case;
        report "writing to chipram..." severity note;
        wait_states <= io_wait_states;
      elsif long_address(27 downto 24) = x"8" then
        report "writing to slowram..." severity note;
        accessing_slowram <= '1';
        slowram_addr <= std_logic_vector(long_address(23 downto 1));
        slowram_we <= '0';
        slowram_ce <= '0';
        slowram_oe <= '0';
        slowram_lohi <= long_address(0);
        slowram_lb <= std_logic(long_address(0));
        slowram_ub <= std_logic(not long_address(0));
        slowram_data <= std_logic_vector(value) & std_logic_vector(value);
        wait_states <= slowram_waitstates;
      elsif long_address(27 downto 24) = x"F" then
        accessing_fastio <= '1';
        fastio_addr <= std_logic_vector(long_address(19 downto 0));
        last_fastio_addr <= std_logic_vector(long_address(19 downto 0));
        fastio_write <= '1'; fastio_read <= '0';
        fastio_wdata <= std_logic_vector(value);
        if long_address = x"FFC00A0" then
          slowram_waitstates <= value;
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
        wait_states <= io_wait_states;
      else
        -- Don't let unmapped memory jam things up
        null;
      end if;
    end write_long_byte;
    
    procedure write_data (
      address            : in unsigned(15 downto 0);
      value              : in unsigned(7 downto 0)) is
      variable long_address : unsigned(27 downto 0);
    begin    
      wait_states <= x"00";

      long_address := resolve_address_to_long(address,true);
      if long_address=unsigned(monitor_watch) then
        monitor_watch_match <= '1';
      end if;
      if long_address=x"0000000" then
        -- Setting the CPU DDR is simple, and has no real side effects.
        -- All 8 bits can be written to.
        cpuport_ddr <= value;
      elsif long_address=x"0000001" then
        -- For CPU port, things get more interesting.
        -- Bits 6 & 7 cannot be altered, and always read 0.
        cpuport_value(5 downto 0) <= value(5 downto 0);
        -- writing to $01 ends kickstart mode
        kickstart_en <= '0';
      else
        report "Writing $" & to_hstring(value) & " @ $" & to_hstring(address)
          & " (resolves to $" & to_hstring(long_address) & ")" severity note;
        write_long_byte(long_address,value);
      end if;
    end procedure write_data;

    
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
      -- report "calculating N & Z flags on result $" & to_hstring(value) severity note;
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
      variable tmp : unsigned(8 downto 0);
    begin
      if flag_d='1' then
        tmp(8) := '0';
        tmp(7 downto 0) := (i1 and x"0f") + (i2 and x"0f") + ("0000000" & flag_c);
        
        if tmp > x"09" then
          tmp := tmp + x"06";                                                                         
        end if;
        if tmp < x"10" then
          tmp := (tmp and x"0f") + (i1 and x"f0") + (i2 and x"f0");
        else
          tmp := (tmp and x"0f") + (i1 and x"f0") + (i2 and x"f0") + x"10";
        end if;
        if (i1 + i2 + ( "0000000" & flag_c )) = x"00" then
          flag_z <= '1';
        else
          flag_z <= '0';
        end if;
        flag_n <= tmp(7);
        flag_v <= (i1(7) xor tmp(7)) and (not (i1(7) xor i2(7)));
        if tmp(8 downto 4) > "01001" then
          tmp(7 downto 0) := tmp(7 downto 0) + x"60";
          tmp(8) := '1';
        end if;
        flag_c <= tmp(8);
      else
        tmp := ("0"&i2)
               + ("0"&i1)
               + ("00000000"&flag_c);
        tmp(7 downto 0) := with_nz(tmp(7 downto 0));
        flag_v <= (not (i1(7) xor i2(7))) and (i1(7) xor tmp(7));
        flag_c <= tmp(8);
      end if;
      -- Return final value
      report "add result of "
        & "$" & to_hstring(std_logic_vector(i1)) 
        & " + "
        & "$" & to_hstring(std_logic_vector(i2)) 
        & " + "
        & "$" & std_logic'image(flag_c)
        & " = " & to_hstring(std_logic_vector(tmp(7 downto 0))) severity note;
      return tmp(7 downto 0);
    end function alu_op_add;

    impure function alu_op_sub (
      i1 : in unsigned(7 downto 0);
      i2 : in unsigned(7 downto 0)) return unsigned is
      variable tmp : unsigned(8 downto 0);
      variable tmpd : unsigned(8 downto 0);
    begin
      tmp := ("0"&i1) - ("0"&i2)
             - "000000001" + ("00000000"&flag_c);
      flag_c <= not tmp(8);
      flag_v <= (i1(7) xor tmp(7)) and (i1(7) xor i2(7));
      tmp(7 downto 0) := with_nz(tmp(7 downto 0));
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
          tmpd := tmpd - ("0"&x"60");
        end if;
        tmp := tmpd;
      end if;
      -- Return final value
      report "subtraction result of "
        & "$" & to_hstring(std_logic_vector(i1)) 
        & " - "
        & "$" & to_hstring(std_logic_vector(i2)) 
        & " - 1 + "
        & "$" & std_logic'image(flag_c)
        & " = " & to_hstring(std_logic_vector(tmp(7 downto 0))) severity note;
      return tmp(7 downto 0);
    end function alu_op_sub;
    
    function flag_status (
      yes : in string;
      no : in string;
      condition : in std_logic) return string is
    begin
      if condition='1' then
        return yes;
      else
        return no;
      end if;
    end function flag_status;
    
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
    variable dec_sp : std_logic;
    variable stack_pop : std_logic;

    variable temp_addr : unsigned(15 downto 0);
    
  begin

    a_incremented <= reg_a + 1;
    a_decremented <= reg_a - 1;
    a_ror <= flag_c & reg_a(7 downto 1);
    a_rol <= reg_a(6 downto 0) & flag_c;    
    a_asr <= reg_a(7) & reg_a(7 downto 1);
    a_lsr <= '0' & reg_a(7 downto 1);    
    
    x_incremented <= reg_x + 1;
    x_decremented <= reg_x - 1;
    y_incremented <= reg_y + 1;
    y_decremented <= reg_y - 1;
    z_incremented <= reg_z + 1;
    z_decremented <= reg_z - 1;
    
    -- BEGINNING OF MAIN PROCESS FOR CPU
    if rising_edge(clock) then

      pop_a <= '0'; pop_x <= '0'; pop_y <= '0'; pop_z <= '0';
      pop_p <= '0';
      
      monitor_debug_memory_access(31) <= accessing_shadow;
      monitor_debug_memory_access(30) <= accessing_fastio;
      monitor_debug_memory_access(29) <= accessing_slowram;
      monitor_debug_memory_access(28) <= accessing_sb_fastio;
      monitor_debug_memory_access(27) <= accessing_colour_ram_fastio;
      monitor_debug_memory_access(26) <= accessing_vic_fastio;
      monitor_debug_memory_access(25) <= accessing_cpuport;
      monitor_debug_memory_access(24) <= '0';

      monitor_debug_memory_access(23 downto 16) <= std_logic_vector(read_data_copy);
      monitor_debug_memory_access(15 downto 8) <= std_logic_vector(read_data);
      monitor_debug_memory_access(7 downto 0) <= std_logic_vector(read_data_complex);
      
      -- Copy read memory location to simplify reading from memory.
      -- Penalty is +1 wait state for memory other than shadowram.
      read_data_copy <= read_data_complex;
      
      -- By default we are doing nothing new.
      pc_inc := '0'; dec_sp := '0'; 
      
      memory_access_read := '0';
      memory_access_write := '0';
      memory_access_resolve_address := '0';
      
      monitor_watch_match <= '0';       -- set if writing to watched address
      monitor_state <= to_unsigned(processor_state'pos(state),8);
      monitor_pc <= std_logic_vector(reg_pc);
      monitor_a <= std_logic_vector(reg_a);
      monitor_x <= std_logic_vector(reg_x);
      monitor_y <= std_logic_vector(reg_y);
      monitor_z <= std_logic_vector(reg_z);
      monitor_sp <= std_logic_vector(reg_sph) & std_logic_vector(reg_sp);
      monitor_b <= std_logic_vector(reg_b);
      monitor_interrupt_inhibit <= map_interrupt_inhibit;
      monitor_map_offset_low <= std_logic_vector(reg_offset_low);
      monitor_map_offset_high <= std_logic_vector(reg_offset_high); 
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

      monitor_p <= std_logic_vector(virtual_reg_p);

      -------------------------------------------------------------------------
      -- Real CPU work begins here.
      -------------------------------------------------------------------------

      monitor_waitstates <= wait_states;
      shadow_write <= '0';

      -- Catch the CPU when it goes to the next instruction if single stepping.
      if (monitor_mem_trace_mode='0' or
          monitor_mem_trace_toggle_last /= monitor_mem_trace_toggle)
        and (monitor_mem_attention_request='0') then
        monitor_mem_trace_toggle_last <= monitor_mem_trace_toggle;
        normal_fetch_state <= InstructionFetch;
        fast_fetch_state <= InstructionDecode;
      else
        normal_fetch_state <= ProcessorHold;
        fast_fetch_state <= ProcessorHold;
      end if;
      
      memory_read_value := read_data;
      
      -- report "reset = " & std_logic'image(reset) severity note;
      if reset='0' then
        state <= ResetLow;
        proceed <= '0';
        wait_states <= x"00";
        reset_cpu_state;
      else
        -- Honour wait states on memory accesses
        -- Clear memory access lines unless we are in a memory wait state
        if wait_states /= x"00" then
          report "  $" & to_hstring(wait_states) &" memory waitstates remaining.  Fastio_rdata = $" & to_hstring(fastio_rdata) & ", mem_reading=" & std_logic'image(mem_reading) severity note;
          wait_states <= wait_states - 1;
          if wait_states = x"01" then
            -- Next cycle we can do stuff, provided that the serial monitor
            -- isn't asking us to do anything.
            proceed <= '1';
          end if;
        else
          -- End of wait states, so clear memory writing and reading

          colour_ram_cs <= '0';
          shadow_write <= '0';       
          fastio_write <= '0';
--          fastio_read <= '0';
          fastram_we <= (others => '0');        
          slowram_we <= '1';
          slowram_ce <= '1';
          slowram_oe <= '1';

          if mem_reading='1' then
            report "resetting mem_reading (read $" & to_hstring(memory_read_value) & ")" severity note;
            mem_reading <= '0';
            mem_reading_pcl <= '0';
            mem_reading_pch <= '0';
            monitor_mem_reading <= '0';
          end if;          

          proceed <= '1';
        end if;
        -- Do memory writes in their own clock cycle to keep logic depth down.
        -- The trade-off is one cycle delay on all memory writes.
        -- Memory writes are only perhaps 20% of all cycles,
        -- so 4/5*1 + 1/5 * 2 = 6/5 of the time, so 5/6 the speed, about
        -- 83% of maximum speed.  This is much better than cutting the
        -- clock speed by 1/3, which is the only other real option.
        --if delayed_memory_write='1' then
        --delayed_memory_write <= '0';
        --if delayed_memory_write_resolve_address = '1' then
        --  write_data(delayed_memory_write_address(15 downto 0),delayed_memory_write_data);
        --else 
        --  write_long_byte(delayed_memory_write_address,delayed_memory_write_data);
        --end if;
        --end if;

        monitor_proceed <= proceed;
        monitor_request_reflected <= monitor_mem_attention_request;
        
        if proceed='1' then
          -- Main state machine for CPU
          report "CPU state = " & processor_state'image(state) & ", PC=$" & to_hstring(reg_pc) severity note;
          case state is
            when ResetLow =>
              reset_cpu_state;
              vector <= x"e";
              state <= VectorRead1;
            when VectorRead1 =>
              mem_reading_pcl <= '1';
              read_address(x"FFF"&vector);
              vector <= vector + 1;
              state <= VectorRead2;
            when VectorRead2 =>
              mem_reading_pch <= '1';
              read_address(x"FFF"&vector);
              state <= InstructionWait;
            when InstructionWait =>
              state <= InstructionFetch;
            when InstructionFetch =>
              memory_access_read := '1';
              memory_access_address := x"000"&reg_pc;
              memory_access_resolve_address := '1';
              state <= InstructionDecode;
              pc_inc := '1';
            when InstructionDecode =>
              reg_opcode <= memory_read_value;
              -- Present instruction to serial monitor;
              monitor_opcode <= std_logic_vector(memory_read_value);
              monitor_ibytes <= "0000";

              -- Always read the next instruction byte after reading opcode
              -- (unless later overriden)            
              memory_access_read := '1';
              memory_access_address := x"000"&reg_pc;
              memory_access_resolve_address := '1';
              pc_inc := '1';

              -- See if this is a single cycle instruction.
              -- Note that CLI and CLE take 2 cycles so that any
              -- pending interrupt can happen immediately (interrupts cannot
              -- happen immediately after a single cycle instruction, because
              -- interrupts are only checked in InstructionFetch, not
              -- InstructionDecode).
              case reg_opcode is
                when x"03" => flag_e <= '1';  -- SEE
                when x"0B" => reg_y <= reg_sph; -- TSY
                when x"18" => flag_c <= '0';  -- CLC
                when x"1A" => reg_a <= a_incremented; set_nz(a_incremented); -- INC A
                when x"1B" => reg_z <= z_incremented; set_nz(z_incremented); -- INZ
                when x"2B" => reg_sph <= reg_y; -- TYS
                when x"38" => flag_c <= '1';  -- SEC
                when x"3A" => reg_a <= a_decremented; set_nz(a_decremented); -- DEC A
                when x"3B" => reg_z <= z_decremented; set_nz(z_decremented); -- DEZ
                when x"42" => reg_a <= a_negated; set_nz(a_negated); -- NEG A
                when x"43" => reg_a <= a_asr; set_nz(a_asr); -- ASR A
                when x"4A" => reg_a <= a_lsr; set_nz(a_lsr); -- LSR A
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
                when x"BA" => reg_x <= reg_sp; -- TSX
                when x"CA" => reg_x <= x_decremented; set_nz(x_decremented); -- DEX
                when x"D8" => flag_d <= '0';  -- CLD
                when x"E8" => reg_x <= x_incremented; set_nz(x_incremented); -- INX
                when x"EA" => map_interrupt_inhibit <= '0'; -- EOM
                when x"F8" => flag_d <= '1';  -- CLD                            
                when others => null;
              end case;
              
              if op_is_single_cycle(to_integer(memory_read_value)) = '0' then
                if (mode_lut(to_integer(memory_read_value)) = M_immnn)
                  or (mode_lut(to_integer(memory_read_value)) = M_impl)
                  or (mode_lut(to_integer(memory_read_value)) = M_A)
                then
                  state <= ActionCycle;
                else
                  state <= Cycle2;
                end if;
              else
                -- Allow monitor to trace through single-cycle instructions
                if monitor_mem_trace_mode='1' then
                  state <= normal_fetch_state;
                  pc_inc := '0';
                end if;
              end if;

              -- Prepare microcode vector in case we need it next cycle
              reg_addressingmode <= mode_lut(to_integer(memory_read_value));
              reg_instruction <= instruction_lut(to_integer(memory_read_value));
              is_rmw <= '0'; is_load <= '0'; is_store <= '0';
              rmw_dummy_write_done <= '0';
              case instruction_lut(to_integer(memory_read_value)) is
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
                -- There are a few 16-bit RMWs as well
                when I_INW => is_rmw <= '1';
                when I_DEW => is_rmw <= '1';
                when I_ASW => is_rmw <= '1';                              
                -- Note if instruction is LOAD
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
              reg_microcode_address <=
                instruction_lut(to_integer(memory_read_value));
            when Cycle2 =>     
              -- Show serial monitor_mem_trace_modeitor what we are doing.
              if (reg_addressingmode /= M_A) then
                monitor_arg1 <= std_logic_vector(memory_read_value);
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
                  when M_impl =>  -- Handled in ActionCycle
                  when M_A =>     -- Handled in ActionCycle
                  when M_InnX =>
                    
                    temp_addr := reg_b & (memory_read_value+reg_X);
                    reg_addr <= temp_addr;
                    memory_access_read := '1';
                    memory_access_address := x"000"&temp_addr;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= ActionCycle;
                  when M_nn =>
                    temp_addr := reg_b & (memory_read_value);
                    reg_addr <= temp_addr;
                    memory_access_read := '1';
                    memory_access_address := x"000"&temp_addr;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= ActionCycle;
                  when M_immnn => -- Handled in ActionCycle              
                  when M_nnnn =>
                    reg_addr(7 downto 0) <= memory_read_value;
                    -- If it is a branch, write the low bits of the programme
                    -- counter now.  We will read the 2nd argument next cycle
                    if reg_instruction = I_JSR or reg_instruction = I_BSR then
                      --memory_access_write := '1';
                      --memory_access_address := x"000"&reg_sph&reg_sp;
                      --memory_access_resolve_address := '1';
                      --memory_access_wdata := reg_pc(7 downto 0);
                      --dec_sp := '1';
                      pc_inc := '0';
                      state <= CallSubroutine0;
                    else
                      pc_inc := '1';
                      memory_access_read := '1';
                      memory_access_address := x"000"&reg_pc;
                      memory_access_resolve_address := '1';
                      state <= AbsReadArg2;
                    end if;
                  when M_nnrr =>
                    reg_t <= memory_read_value;
                    memory_access_read := '1';
                    memory_access_address := x"000"&reg_b&memory_read_value;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= ZPRelReadZP;
                  when M_InnY =>
                    temp_addr := reg_b&memory_read_value;
                    memory_access_read := '1';
                    memory_access_address := x"000"&temp_addr;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= InnYReadVectorLow;
                  when M_InnZ =>
                    temp_addr := reg_b&memory_read_value;
                    memory_access_read := '1';
                    memory_access_address := x"000"&temp_addr;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
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
                      -- Branch will be taken
                      temp_addr := reg_pc +
                                   1+to_integer(memory_read_value(7)&memory_read_value(7)&memory_read_value(7)&memory_read_value(7)&
                                                memory_read_value(7)&memory_read_value(7)&memory_read_value(7)&memory_read_value(7)&
                                                memory_read_value);
                      memory_access_read := '1';
                      memory_access_address := x"000"&temp_addr;
                      memory_access_resolve_address := '1';
                      reg_pc <= temp_addr;
                      state <= fast_fetch_state;
                      if fast_fetch_state = InstructionDecode then pc_inc := '1'; end if;
                    else
                      -- Branch will not be taken.
                      -- fetch next instruction now to save a cycle
                      reg_pc <= reg_pc + 1;
                      memory_access_read := '1';
                      memory_access_address := x"000"&reg_pc;
                      memory_access_resolve_address := '1';
                      state <= fast_fetch_state;
                      if fast_fetch_state = InstructionDecode then pc_inc := '1'; end if;
                    end if;   
                  when M_rrrr =>
                    -- Store low 8 bits of branch value even if we don't use it
                    -- because the logic is shallowe that way
                    reg_addr(7 downto 0) <= memory_read_value;
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
                      reg_pc <= reg_pc + 1;
                      state <= normal_fetch_state;
                    end if;
                  when M_nnX =>
                    temp_addr := reg_b & (memory_read_value + reg_X);
                    reg_addr <= temp_addr;
                    memory_access_read := '1';
                    memory_access_address := x"000"&temp_addr;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= ActionCycle;
                  when M_nnY =>
                    temp_addr := reg_b & (memory_read_value + reg_X);
                    reg_addr <= temp_addr;
                    memory_access_read := '1';
                    memory_access_address := x"000"&temp_addr;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= ActionCycle;
                  when M_nnnnY =>
                    reg_addr(7 downto 0) <= memory_read_value;
                    memory_access_read := '1';
                    memory_access_address := x"000"&reg_pc;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= AbsYReadArg2;
                  when M_nnnnX =>
                    reg_addr(7 downto 0) <= memory_read_value;
                    memory_access_read := '1';
                    memory_access_address := x"000"&reg_pc;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= AbsXReadArg2;
                  when M_Innnn =>
                    reg_addr(7 downto 0) <= memory_read_value;
                    memory_access_read := '1';
                    memory_access_address := x"000"&reg_pc;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= IAbsReadArg2;
                  when M_InnnnX =>
                    reg_addr(7 downto 0) <= memory_read_value;
                    memory_access_read := '1';
                    memory_access_address := x"000"&reg_pc;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= IAbsXReadArg2;
                  when M_InnSPY =>
                    state <= normal_fetch_state;
                  when M_immnnnn =>                
                    reg_addr(7 downto 0) <= memory_read_value;
                    memory_access_read := '1';
                    memory_access_address := x"000"&reg_pc;
                    memory_access_resolve_address := '1';
                    pc_inc := '1';
                    state <= Imm16ReadArg2;
                end case;
              end if;
            when CallSubroutine0 =>
              -- Push PCL
              memory_access_write := '1';
              memory_access_address := x"000"&reg_sph&reg_sp;
              memory_access_resolve_address := '1';
              memory_access_wdata := reg_pc(7 downto 0);
              dec_sp := '1';
              state <= CallSubroutine;
            when CallSubroutine =>
              -- Push PCH
              memory_access_write := '1';
              memory_access_address := x"000"&reg_sph&reg_sp;
              memory_access_resolve_address := '1';
              memory_access_wdata := reg_pc(15 downto 8);
              dec_sp := '1';
              pc_inc := '0';
              state <= CallSubroutine2;
            when CallSubroutine2 =>
              -- Finish determining subroutine address
              pc_inc := '0';
              memory_access_read := '1';
              memory_access_address := x"000"&reg_pc;
              memory_access_resolve_address := '1';
              case reg_addressingmode is
                -- Note, we treat BSR as absolute mode, with microcode
                -- controlling the calculation of the address as relative.
                when M_nnnn => state <= AbsReadArg2;
                when M_innnn => state <= IAbsReadArg2;
                when M_innnnX => state <= AbsXReadArg2;
                when others => state <= normal_fetch_state;
              end case;
            when AbsReadArg2 =>
              monitor_arg2 <= std_logic_vector(memory_read_value);
              monitor_ibytes(0) <= '1';
              reg_addr(15 downto 8) <= memory_read_value;
              state <= ActionCycle;
            when AbsXReadArg2 =>
              monitor_arg2 <= std_logic_vector(memory_read_value);
              monitor_ibytes(0) <= '1';
              reg_addr <= x"00"&reg_x + to_integer(memory_read_value&reg_addr(7 downto 0));
              state <= ActionCycle;
            when AbsYReadArg2 =>
              monitor_arg2 <= std_logic_vector(memory_read_value);
              monitor_ibytes(0) <= '1';
              reg_addr <= x"00"&reg_y + to_integer(memory_read_value&reg_addr(7 downto 0));
              state <= ActionCycle;
            when TakeBranch8 =>
              -- Branch will be taken
              temp_addr := reg_pc +
                           to_integer(memory_read_value(7)&memory_read_value(7)&memory_read_value(7)&memory_read_value(7)&
                                      memory_read_value(7)&memory_read_value(7)&memory_read_value(7)&memory_read_value(7)&
                                      memory_read_value);
              -- Prefetch instruction byte
              memory_access_read := '1';
              memory_access_address := x"000"&temp_addr;
              memory_access_resolve_address := '1';
              reg_pc <= temp_addr;
              state <= fast_fetch_state;
              if fast_fetch_state = InstructionDecode then pc_inc := '1'; end if;
            when Push =>
              -- Nothing more to do
              -- Prefetch instruction byte
              memory_access_read := '1';
              memory_access_address := x"000"&temp_addr;
              memory_access_resolve_address := '1';
              reg_pc <= temp_addr;
              state <= fast_fetch_state;
              if fast_fetch_state = InstructionDecode then pc_inc := '1'; end if;
            when Pull =>
              set_nz(memory_read_value);
              if pop_a='1' then reg_a <= memory_read_value; end if;
              if pop_x='1' then reg_x <= memory_read_value; end if;
              if pop_y='1' then reg_y <= memory_read_value; end if;
              if pop_z='1' then reg_z <= memory_read_value; end if;
              if pop_p='1' then
                load_processor_flags(memory_read_value);
              end if;
              
              -- Prefetch instruction byte (special case since PC is being changed)
              memory_access_read := '1';
              memory_access_address := x"000"&temp_addr;
              memory_access_resolve_address := '1';
              reg_pc <= temp_addr;
              state <= fast_fetch_state;
              if fast_fetch_state = InstructionDecode then pc_inc := '1'; end if;
            when B16TakeBranch =>
              monitor_arg2 <= std_logic_vector(memory_read_value);
              monitor_ibytes(0) <= '1';
              reg_pc <= reg_pc + to_integer(memory_read_value & reg_addr(7 downto 0));
              state <= normal_fetch_state;

                                        -- Dummy/incomplete states for now.
            when InnYReadVectorLow =>
              reg_addr(7 downto 0) <= memory_read_value;
              state <= normal_fetch_state;
            when InnZReadVectorLow =>
              reg_addr(7 downto 0) <= memory_read_value;
              state <= normal_fetch_state;
            when ZPRelReadZP =>
              monitor_arg1 <= std_logic_vector(memory_read_value);
              monitor_ibytes(1) <= '1';
                                        -- Here we are reading the ZP memory location
                                        -- Check if the appropriate bit is set/clear
              if memory_read_value(to_integer(reg_opcode(6 downto 4)))
                =reg_opcode(7) then
                                        -- Take branch, so read next byte with relative offset
                memory_access_read := '1';
                memory_access_address := x"000"&reg_pc;
                memory_access_resolve_address := '1';
                state <= TakeBranch8;
              else
                                        -- Don't take branch, so just skip over branch byte
                state <= normal_fetch_state;
              end if;
            when IAbsReadArg2 =>
              monitor_arg2 <= std_logic_vector(memory_read_value);
              monitor_ibytes(0) <= '1';
              state <= normal_fetch_state;
            when IAbsXReadArg2 =>
              monitor_arg2 <= std_logic_vector(memory_read_value);
              monitor_ibytes(0) <= '1';
              state <= normal_fetch_state;
            when Imm16ReadArg2 => 
              monitor_arg2 <= std_logic_vector(memory_read_value);
              monitor_ibytes(0) <= '1';
              state <= normal_fetch_state;
            when ActionCycle =>
              -- By this stage we have the address of the operand in
              -- reg_addr, and if it is a load instruction then the contents
              -- will be in memory_read_value
              -- Branches (except JMP) have been taken care of elsewhere, as
              -- have a lot of the other fancy instructions.  That just leaves
              -- us with loads, stores and reaad/modify/write instructions

              if reg_addressingmode = M_immnn then
                monitor_arg1 <= std_logic_vector(memory_read_value);
                monitor_ibytes(1) <= '1';
              end if;
              
              if reg_microcode.mcClearE='1' then flag_e <= '0'; end if;
              if reg_microcode.mcClearI='1' then flag_i <= '0'; end if;             
              
              if reg_microcode.mcMap='1' then
                c65_map_instruction;
              end if;
            when DelayedWrite =>
              if delayed_write_resolve = '1' then
                write_data(delayed_write_address(15 downto 0),delayed_write_wdata);
              else 
                write_long_byte(delayed_write_address,delayed_write_wdata);
              end if;
            when others =>
              state <= normal_fetch_state;
          end case;
        end if;

--        report "pc_inc = " & std_logic'image(pc_inc) & ", cpu_state = " & processor_state'image(state) severity note;
        if pc_inc = '1' then
          reg_pc <= reg_pc + 1;
        end if;
        if dec_sp = '1' then
          reg_sp <= reg_sp - 1;
          if flag_e='0' and reg_sp=x"00" then
            reg_sph <= reg_sph - 1;
          end if;
        end if;

        -- Effect memory accesses.
        -- Note that we cannot combine address resolution for read and write,
        -- because the resolution of some addresses is dependent on whether
        -- the operation is read or write.  ROM accesses are a good example.
        -- We delay the memory write until the next cycle to minimise logic depth
        if memory_access_write='1' then
          --delayed_memory_write <= '1';
          --delayed_memory_write_resolve_address <= memory_access_resolve_address;
          --delayed_memory_write_address <= memory_access_address;
          --delayed_memory_write_data <= memory_access_wdata;
          if memory_access_resolve_address = '1' then
            write_data(memory_access_address(15 downto 0),memory_access_wdata);
          else 
            write_long_byte(memory_access_address,memory_access_wdata);
          end if;
        end if;

                                        -- We make sure that there is no write being committed before pushing the
                                        -- read through.
        if memory_access_read='1' then -- and delayed_memory_write='0' then
          if memory_access_resolve_address = '1' then
            memory_access_address := resolve_address_to_long(memory_access_address(15 downto 0),false);
          end if;
          read_long_address(memory_access_address);
        end if;
      end if; -- if not reseting
    end if;                         -- if rising edge of clock
  end process;

end Behavioural;
