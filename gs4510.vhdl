-- Accelerated 6502-like CPU for the C65GS
--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>
--
-- * ADC/SBC algorithm derived from  6510core.c - WICE MOS6510 emulation core.
-- *   Written by
-- *    Ettore Perazzoli <ettore@comm2000.it>
-- *    Andreas Boose <viceteam@t-online.de>
-- *
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 2 of the
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

entity gs4510 is
  port (
    Clock : in std_logic;
    reset : in std_logic;
    irq : in std_logic;
    nmi : in std_logic;
    monitor_pc : out std_logic_vector(15 downto 0);
    monitor_opcode : out std_logic_vector(7 downto 0);
    monitor_a : out std_logic_vector(7 downto 0);
    monitor_x : out std_logic_vector(7 downto 0);
    monitor_y : out std_logic_vector(7 downto 0);
    monitor_z : out std_logic_vector(7 downto 0);
    monitor_b : out std_logic_vector(7 downto 0);
    monitor_sp : out std_logic_vector(15 downto 0);
    monitor_p : out std_logic_vector(7 downto 0);
    monitor_state : out std_logic_vector(7 downto 0);
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
    
    ---------------------------------------------------------------------------
    -- Interface to FastRAM in video controller (just 128KB for now)
    ---------------------------------------------------------------------------
    fastram_we : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    fastram_address : OUT STD_LOGIC_VECTOR(13 DOWNTO 0);
    fastram_datain : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    fastram_dataout : IN STD_LOGIC_VECTOR(63 DOWNTO 0);

    ---------------------------------------------------------------------------
    -- Interface to Slow RAM (16MB cellular RAM chip)
    ---------------------------------------------------------------------------
    slowram_addr : out std_logic_vector(22 downto 0);
    slowram_we : out std_logic;
    slowram_ce : out std_logic;
    slowram_oe : out std_logic;
    slowram_lb : out std_logic;
    slowram_ub : out std_logic;
    slowram_data : inout std_logic_vector(15 downto 0);
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : inout std_logic_vector(19 downto 0);
    fastio_read : inout std_logic;
    fastio_write : inout std_logic;
    fastio_wdata : out std_logic_vector(7 downto 0);
    fastio_rdata : inout std_logic_vector(7 downto 0);
    fastio_vic_rdata : in std_logic_vector(7 downto 0);
    fastio_colour_ram_rdata : in std_logic_vector(7 downto 0);
    colour_ram_cs : out std_logic;

    colourram_at_dc00 : in std_logic;
    rom_at_e000 : in std_logic;
    rom_at_9000 : in std_logic;
    rom_at_c000 : in std_logic;
    rom_at_a000 : in std_logic;
    rom_at_8000 : in std_logic
    );
end entity gs4510;

architecture Behavioural of gs4510 is

  signal kickstart_en : std_logic := '1';
  signal colour_ram_cs_last : std_logic := '0';
  
  -- i-cache control lines
  signal icache_delay : std_logic;
  signal accessing_icache : std_logic;

  signal icache_00_address : unsigned(7 downto 0);
  signal icache_00_wdata : unsigned(31 downto 0);
  signal icache_00_write : std_logic;
  signal icache_01_address : unsigned(7 downto 0);
  signal icache_01_wdata : unsigned(31 downto 0);
  signal icache_01_write : std_logic;
  signal icache_10_address : unsigned(7 downto 0);
  signal icache_10_wdata : unsigned(31 downto 0);
  signal icache_10_write : std_logic;
  signal icache_11_address : unsigned(7 downto 0);
  signal icache_11_wdata : unsigned(31 downto 0);
  signal icache_11_write : std_logic;
  
  signal last_fastio_addr : std_logic_vector(19 downto 0);

  signal slowram_lohi : std_logic;
  signal slowram_counter : unsigned(7 downto 0);
  -- SlowRAM has 70ns access time, so need some wait states.
  -- The wait states
  signal slowram_waitstates : unsigned(7 downto 0) := x"05";
  
  signal fastram_byte_number : unsigned(2 DOWNTO 0);

  signal word_flag : std_logic := '0';

  -- DMAgic registers
  signal reg_dmagic_addr : unsigned(23 downto 0) := x"000000";
  signal reg_dmagic_status : unsigned(7 downto 0) := x"00";
  signal dma_pending : std_logic := '0';
  signal dmagic_cmd : unsigned(7 downto 0);
  signal dmagic_count : unsigned(15 downto 0);
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
  signal vector : unsigned(15 downto 0);
  
  type processor_state is (
    -- When CPU first powers up, or reset is bought low
    ResetLow,
    -- States for handling interrupts and reset
    Interrupt,VectorRead,VectorRead1,VectorRead2,VectorRead3,
    InstructionFetch,
    InstructionFetch2,InstructionFetch3,InstructionFetch4,
    BRK1,BRK2,PLA1,PLX1,PLY1,PLZ1,PLP1,RTI1,RTI2,RTI3,
    RTS1,RTS2,
    JSR1,JSRind1,JSRind2,JSRind3,JSRind4,
    JMP1,JMP2,JMP3,
    PHWimm1,
    IndirectX1,IndirectX2,IndirectX3,
    IndirectY1,IndirectY2,IndirectY3,
    IndirectZ1,IndirectZ2,
    ExecuteDirect,RMWCommit,RMWCommit2,RMWCommit3,
    Halt,FastRamWait,
    SlowRamRead1,SlowRamRead2,SlowRamWrite1,SlowRamWrite2,
    BranchOnBit,
    MonitorAccessDone,MonitorReadDone,
    Interrupt2,Interrupt3,FastIOWait
    );
  signal state : processor_state := ResetLow;  -- start processor in reset state
  -- For memory access we push the processor state to follow once the memory
  -- access is complete.
  signal pending_state : processor_state;
  -- Information about instruction currently being executed
  signal opcode : unsigned(7 downto 0);
  signal arg1 : unsigned(7 downto 0);

  signal bbs_or_bbc : std_logic;
  signal bbs_bit : unsigned(2 downto 0);
  
  type addressingmode is (
    M_impl,M_InnX,M_nn,M_immnn,M_A,M_nnnn,M_nnrr,
    M_rr,M_InnY,M_InnZ,M_rrrr,M_nnX,M_nnnnY,M_nnnnX,M_Innnn,
    M_InnnnX,M_InnSPY,M_nnY,M_immnnnn);

  type mode_list is array(addressingmode'low to addressingmode'high) of integer;
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
  
  type instruction is (
    -- 4510 opcodes
    I_BRK,I_ORA,I_CLE,I_SEE,I_TSB,I_ASL,I_RMB,
    I_PHP,I_TSY,I_BBR,I_BPL,I_TRB,I_CLC,I_INC,I_INZ,
    I_JSR,I_AND,I_BIT,I_ROL,I_PLP,I_TYS,I_BMI,I_SEC,
    I_DEC,I_DEZ,I_RTI,I_EOR,I_NEG,I_ASR,I_LSR,I_PHA,
    I_TAZ,I_JMP,I_BVC,I_CLI,I_PHY,I_TAB,I_MAP,I_RTS,
    I_ADC,I_BSR,I_STZ,I_ROR,I_PLA,I_TZA,I_BVS,I_SEI,
    I_PLY,I_TBA,I_BRA,I_STA,I_STY,I_STX,I_SMB,I_DEY,
    I_TXA,I_BBS,I_BCC,I_TYA,I_TXS,I_LDY,I_LDA,I_LDX,
    I_LDZ,I_TAY,I_TAX,I_BCS,I_CLV,I_TSX,I_CPY,I_CMP,
    I_CPZ,I_DEW,I_INY,I_DEX,I_ASW,I_BNE,I_CLD,I_PHX,
    I_PHZ,I_CPX,I_SBC,I_INW,I_INX,I_EOM,I_ROW,I_BEQ,
    I_PHW,I_SED,I_PLX,I_PLZ);

  type ilut8bit is array(0 to 255) of instruction;
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
    M_impl,  M_InnX,  M_immnn, M_rrrr,  M_nn,    M_nn,    M_nn,    M_nn,    
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
  
  -- PC used for JSR is the value of reg_pc after reading only one of
  -- of the argument bytes.  We could subtract one, but it is less logic to
  -- just remember PC after reading one argument byte.
  signal reg_pc_jsr : unsigned(15 downto 0);
  -- Temporary address register (used for indirect modes)
  signal reg_addr : unsigned(15 downto 0);
  -- Temporary instruction register (used for many modes)
  signal reg_instruction : instruction;
  -- Temporary value holder (used for RMW instructions)
  signal reg_value : unsigned(7 downto 0);
  
-- Indicate source of operand for instructions
-- Note that ROM is actually implemented using
-- power-on initialised RAM in the FPGA mapped via our io interface.
  signal accessing_fastio : std_logic;
  signal accessing_vic_fastio : std_logic;
  signal accessing_colour_ram_fastio : std_logic;
  signal accessing_ram : std_logic;
  signal accessing_slowram : std_logic;
  signal accessing_cpuport : std_logic;
  signal cpuport_num : std_logic;
  signal cpuport_ddr : unsigned(7 downto 0) := x"FF";
  signal cpuport_value : unsigned(7 downto 0) := x"3F";

  signal monitor_mem_trace_toggle_last : std_logic := '0';

begin
  process(clock)

    procedure reset_cpu_state is
  begin
    -- Default register values
    reg_b <= x"00";
    reg_a <= x"11";    
    reg_x <= x"22";
    reg_y <= x"33";
    reg_z <= x"00";
    reg_sp <= x"ff";
    reg_sph <= x"01";

    -- Clear CPU MMU registers
    reg_mb_low <= x"00";
    reg_mb_high <= x"00";
    reg_map_low <= "0000";
    reg_map_high <= "0000";
    reg_offset_low <= x"000";
    reg_offset_high <= x"000";

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

    -- default is address in = address out
    temp_address(27 downto 16) := (others => '0');
    temp_address(15 downto 0) := short_address;

    -- IO
    if (blocknum=13) and ((lhc(0)='1') or (lhc(1)='1')) and (lhc(2)='1') then
      temp_address(27 downto 12) := x"FFD3";
      temp_addresS(11 downto 0) := short_address(11 downto 0);
    end if;
    -- CHARROM
    if (blocknum=13) and (lhc(2)='0') and (writeP=false) then
      temp_address(27 downto 12) := x"002D";
      temp_addresS(11 downto 0) := short_address(11 downto 0);
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
      if (blocknum=10) and (lhc(0)='1') and (writeP=false) then
        temp_address(27 downto 12) := x"002A";      
      end if;
      if (blocknum=11) and (lhc(0)='1') and (writeP=false) then
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
    if (blocknum=9) and rom_at_9000='1' then
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

  -- purpose: prepare for next instruction, looking in i-cache when possible
  procedure ready_for_next_instruction (
    next_pc : in unsigned(15 downto 0)) is
  begin  -- ready_for_next_instruction
    state <= InstructionFetch;
    -- XXX Resolve PC to long address.
    -- XXX Schedule reading from all four i-cache files
    -- (uses less logic than picking only one)
    -- XXX i-cache not implemented.
    accessing_icache <= '0';
  end ready_for_next_instruction;

  -- purpose: invalidate cache lines corresponding to a memory write
  procedure icache_invalidate (
    long_address : in unsigned(27 downto 0)) is
  begin  -- icache_invalidate
    case long_address(1 downto 0) is
      when "00" => icache_00_address <= long_address(9 downto 2);
                   icache_00_wdata <= (others => '0');
                   icache_00_write <= '1';
      when "01" => icache_01_address <= long_address(9 downto 2);
                   icache_01_wdata <= (others => '0');
                   icache_01_write <= '1';
      when "10" => icache_10_address <= long_address(9 downto 2);
                   icache_10_wdata <= (others => '0');
                   icache_10_write <= '1';
      when "11" => icache_11_address <= long_address(9 downto 2);
                   icache_11_wdata <= (others => '0');
                   icache_11_write <= '1';
      when others => null;
    end case;
  end icache_invalidate;
  
  procedure read_long_address(
    long_address : in unsigned(27 downto 0);
    next_state : in processor_state) is
  begin
    -- Schedule the memory read from the appropriate source.
    accessing_ram <= '0'; accessing_slowram <= '0';
    accessing_fastio <= '0'; accessing_vic_fastio <= '0';
    accessing_cpuport <= '0'; accessing_colour_ram_fastio <= '0';
    if long_address(27 downto 17)="00000000000" then
      report "Reading from fastram address $" & to_hstring(long_address(19 downto 0))
        & ", word $" & to_hstring(long_address(18 downto 3)) severity note;
      accessing_ram <= '1';
      fastram_address <= std_logic_vector(long_address(16 downto 3));
      fastram_byte_number <= long_address(2 downto 0);
      -- By moving fastram to pixel clock instead of CPU clock, a read can happen
      -- easily in one cpu cycle, thus avoiding the wait state. Now to see if it
      -- can synthesise...
      --state <= next_state;
      --pending_state <= next_state;
      state <= FastRamWait;
    -- Slow RAM maps to $8xxxxxx, and also $0020000 - $003FFFF for C65 ROM
    -- emulation.
    elsif long_address(27 downto 24) = x"8"
      or long_address(27 downto 17)&'0' = x"002" then
      accessing_slowram <= '1';
      slowram_addr <= std_logic_vector(long_address(23 downto 1));
      slowram_data <= (others => 'Z');  -- tristate data lines
      slowram_we <= '1';
      slowram_ce <= '1';
      slowram_oe <= '1';
      slowram_lb <= '1';
      slowram_ub <= '1';
      slowram_lohi <= long_address(0);
      pending_state <= next_state;
      state <= SlowRamRead1;
    elsif long_address(27 downto 20) = x"FF" then
      accessing_fastio <= '1';
      accessing_vic_fastio <= '0';
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
        colour_ram_cs_last <= '1';
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
              colour_ram_cs_last <= '1';
            end if;
          end if;
        end if;                         -- $D{0,1,2,3}XXX
      end if;                           -- $DXXXX
      fastio_addr <= std_logic_vector(long_address(19 downto 0));
      last_fastio_addr <= std_logic_vector(long_address(19 downto 0));
      fastio_read <= '1';
      -- XXX Some fastio (that referencing dual-port block rams) does require
      -- a wait state.  For now, just apply the wait state to all fastio
      -- addresses.
      -- Eventually can narrow down to colour ram, palette and some of the other
      -- IO features that use dual-port rams to provide access.
      -- Probably easier just to make the single-port ROM portion of fastio fast,
      -- and assume all else is slow, as there are many pieces of fastio that need
      -- a wait state.
      -- So let's just make the top 128KB of fastio fast, and assume the rest needs
      -- the wait state.  Also the CIAs as interrupts are acknowledged and cleared
      -- by reading registers, so reading twice would lose the ability to see
      -- the interrupt source.
      if long_address(19 downto 17)="111"
        --or long_address(19 downto 8)=x"D0C" or long_address(19 downto 8)=x"D0D"
        --or long_address(19 downto 8)=x"D1C" or long_address(19 downto 8)=x"D1D"
        --or long_address(19 downto 8)=x"D2C" or long_address(19 downto 8)=x"D2D"
        --or long_address(19 downto 8)=x"D3C" or long_address(19 downto 8)=x"D3D"
        -- F011 FDC @ $D080-$D09F requires a wait state, but only appears in the
        -- enhanced image pages.
        or long_address(19 downto 8)=x"D00" or long_address(19 downto 7)=x"D10"&'0'
        or long_address(19 downto 8)=x"D20" or long_address(19 downto 7)=x"D30"&'0'
      then 
        if next_state = InstructionFetch then
          ready_for_next_instruction(reg_pc);
        else
          state <= next_state;
        end if;
      else
        pending_state <= next_state;
        state <= FastIOWait;
      end if;
    else
      -- Don't let unmapped memory jam things up
      if next_state = InstructionFetch then
        ready_for_next_instruction(reg_pc);
      else
        state <= next_state;
      end if;
    end if;
    -- Once read, we then resume processing from the specified state.
    pending_state <= next_state;
  end read_long_address;
  
  -- purpose: read from a 16-bit CPU address
  procedure read_address (
    address    : in unsigned(15 downto 0);
    next_state : in processor_state) is
    variable long_address : unsigned(27 downto 0);
  begin  -- read_address
    long_address := resolve_address_to_long(address,false);
    if (long_address = x"0000000") or (long_address = x"0000001") then
      accessing_cpuport <= '1';
      cpuport_num <= address(0);
      if next_state = InstructionFetch then
        ready_for_next_instruction(reg_pc);
      else
        state <= next_state;
      end if;
    else
      read_long_address(long_address,next_state);
    end if;
  end read_address;

  procedure write_long_byte(
    long_address       : in unsigned(27 downto 0);
    value              : in unsigned(7 downto 0);
    next_state         : in processor_state) is
  begin
    -- Schedule the memory write to the appropriate destination.

    -- Tell i-cache that memory map is changing if we touch $D030
    -- (VIC-III ROM banking register)
    if (long_address = x"FFD0030") or (long_address = x"FFD1030") or
      (long_address = x"FFD2030") or (long_address = x"FFD3030") then
      icache_delay <= '1';
    end if;

    -- Invalidate i-cache lines corresponding to the address we are writing to.
    -- As cache lines hold bytes n,n+1 and n+2, we need to erase the cache lines
    -- corresponding to long_address-2 through long_address inclusive
    icache_invalidate(long_address);
    icache_invalidate(long_address-1);
    icache_invalidate(long_address-2);
    
    accessing_ram <= '0'; accessing_slowram <= '0';
    accessing_fastio <= '0'; accessing_cpuport <= '0';
    if long_address(27 downto 17)="00000000000" then
      accessing_ram <= '1';
      fastram_address <= std_logic_vector(long_address(16 downto 3));
      fastram_we <= (others => '0');
      fastram_datain <= (others => '1');
      case long_address(2 downto 0) is
        when "000" => fastram_we <= "00000001"; fastram_datain(7 downto 0) <= std_logic_vector(value);
        when "001" => fastram_we <= "00000010"; fastram_datain(15 downto 8) <= std_logic_vector(value);
        when "010" => fastram_we <= "00000100"; fastram_datain(23 downto 16) <= std_logic_vector(value);
        when "011" => fastram_we <= "00001000"; fastram_datain(31 downto 24) <= std_logic_vector(value);
        when "100" => fastram_we <= "00010000"; fastram_datain(39 downto 32) <= std_logic_vector(value);
        when "101" => fastram_we <= "00100000"; fastram_datain(47 downto 40) <= std_logic_vector(value);
        when "110" => fastram_we <= "01000000"; fastram_datain(55 downto 48) <= std_logic_vector(value);
        when "111" => fastram_we <= "10000000"; fastram_datain(63 downto 56) <= std_logic_vector(value);
        when others =>
          report "dud write to fastram" severity note;
      end case;
      -- report "writing to fastram..." severity note;
      if next_state = InstructionFetch then
        ready_for_next_instruction(reg_pc);
      else
        if next_state = InstructionFetch then
          ready_for_next_instruction(reg_pc);
        else
          state <= next_state;
        end if;
      end if;
    elsif long_address(27 downto 24) = x"8" then
      accessing_slowram <= '1';
      slowram_addr <= std_logic_vector(long_address(23 downto 1));
      slowram_we <= '1';
      slowram_ce <= '1';
      slowram_oe <= '1';
      slowram_lohi <= long_address(0);
      slowram_lb <= std_logic(long_address(0));
      slowram_ub <= std_logic(not long_address(0));
      slowram_data <= std_logic_vector(value) & std_logic_vector(value);
      pending_state <= next_state;
      state <= SlowRamWrite1;
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
        colour_ram_cs_last <= '1';
      end if;
      if long_address(19 downto 16) = x"D" then
        if long_address(15 downto 14) = "00" then    --   $D{0,1,2,3}XXX
          -- Colour RAM at $D800-$DBFF and optionally $DC00-$DFFF
          if long_address(11)='1' then
            if (long_address(10)='0') or (colourram_at_dc00='1') then
              report "D800-DBFF/DC00-DFFF colour ram access from VIC fastio" severity note;
              colour_ram_cs <= '1';
              colour_ram_cs_last <= '1';
            end if;
          end if;
        end if;                         -- $D{0,1,2,3}XXX
      end if;                           -- $DXXXX
      -- No wait states on I/O write, so proceed directly to the next state
      if next_state = InstructionFetch then
        ready_for_next_instruction(reg_pc);
      else
        state <= next_state;
      end if;
    else
      -- Don't let unmapped memory jam things up
      if next_state = InstructionFetch then
        ready_for_next_instruction(reg_pc);
      else
        state <= next_state;
      end if;
    end if;
    -- Once read, we then resume processing from the specified state.
    pending_state <= next_state;
  end write_long_byte;
  
  procedure write_byte (
    address            : in unsigned(15 downto 0);
    value              : in unsigned(7 downto 0);
    next_state         : in processor_state) is
    variable long_address : unsigned(27 downto 0);
  begin
    long_address := resolve_address_to_long(address,true);
    if long_address=x"0000000" then
      -- Setting the CPU DDR is simple, and has no real side effects.
      -- All 8 bits can be written to.
      cpuport_ddr <= value;
      icache_delay <= '1';
      if next_state = InstructionFetch then
        ready_for_next_instruction(reg_pc);
      else
        state <= next_state;
      end if;
    elsif long_address=x"0000001" then
      -- For CPU port, things get more interesting.
      -- Bits 6 & 7 cannot be altered, and always read 0.
      cpuport_value(5 downto 0) <= value(5 downto 0);
      icache_delay <= '1';
      -- writing to $01 ends kickstart mode
      kickstart_en <= '0';
      if next_state = InstructionFetch then
        ready_for_next_instruction(reg_pc);
      else
        state <= next_state;
      end if;
    else
      --report "Writing $" & to_hstring(value) & " @ $" & to_hstring(address)
      --  & " (resolves to $" & to_hstring(long_address) & ")" severity note;
      write_long_byte(long_address,value,next_state);
    end if;
  end procedure write_byte;

  procedure write_data_byte (
    address            : in unsigned(15 downto 0);
    value              : in unsigned(7 downto 0);
    next_state         : in processor_state) is
  begin
    write_byte(address,value,next_state);
  end procedure write_data_byte;
  
  -- purpose: push a byte onto the stack
  procedure push_byte (
    value : in unsigned(7 downto 0);
    next_state : in processor_state) is
  begin  -- push_byte
    reg_sp <= reg_sp - 1;
    write_byte(reg_sph & reg_sp,value,next_state);
  end push_byte;

  -- purpose: pull a byte from the stack
  procedure pull_byte (
    next_state : in processor_state) is
  begin  -- pull_byte
    reg_sp <= reg_sp + 1;
    read_address(reg_sph & (reg_sp + 1),next_state);
  end pull_byte;
  
  procedure read_instruction_byte (
    address : in unsigned(15 downto 0);
    next_state : in processor_state) is
  begin
    read_address(address,next_state);
  end read_instruction_byte;

  procedure read_data_byte (
    address : in unsigned(15 downto 0);
    next_state : in processor_state) is
  begin
    read_address(address,next_state);
  end read_data_byte;

  -- purpose: obtain the byte of memory that has been read
  impure function read_data
    return unsigned is
  begin  -- read_data
    if accessing_cpuport='1' then
      if cpuport_num='0' then
        -- DDR
        return cpuport_ddr;
      else
        -- CPU port
        return cpuport_value;
      end if;
    elsif accessing_colour_ram_fastio='1' then 
      report "reading colour RAM fastio byte $" & to_hstring(fastio_vic_rdata) severity note;
      return unsigned(fastio_colour_ram_rdata);
    elsif accessing_vic_fastio='1' then 
      report "reading VIC fastio byte $" & to_hstring(fastio_vic_rdata) severity note;
      return unsigned(fastio_vic_rdata);
    elsif accessing_fastio='1' then
      report "reading fastio byte $" & to_hstring(fastio_rdata) severity note;
      return unsigned(fastio_rdata);
    elsif accessing_ram='1' then
      report "Extracting fastram value from 64-bit read $" & to_hstring(fastram_dataout) severity note;
      report "Fastram_byte_number = " & integer'image(to_integer(fastram_byte_number)) severity note;
      case fastram_byte_number is
        when "000" => return unsigned(fastram_dataout( 7 downto 0));
        when "001" => return unsigned(fastram_dataout(15 downto 8));
        when "010" => return unsigned(fastram_dataout(23 downto 16));
        when "011" => return unsigned(fastram_dataout(31 downto 24));
        when "100" => return unsigned(fastram_dataout(39 downto 32));
        when "101" => return unsigned(fastram_dataout(47 downto 40));
        when "110" => return unsigned(fastram_dataout(55 downto 48));
        when "111" => return unsigned(fastram_dataout(63 downto 56));
        when others => return x"FF";
      end case;
    elsif accessing_slowram='1' then
      report "reading slow RAM data. Word is $" & to_hstring(slowram_data) severity note;
      slowram_ce <= '1'; -- Release after reading so that refresh can occur
      slowram_data <= (others => 'Z');  -- tristate data lines as well
      case slowram_lohi is
        when '0' => return unsigned(slowram_data(7 downto 0));
        when '1' => return unsigned(slowram_data(15 downto 8));
        when others => return x"FF";
      end case;
    else
      return x"FF";
    end if;
  end read_data; 

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

  impure function with_nz (
    value : unsigned(7 downto 0)) return unsigned is
  begin
    -- report "calculating N & Z flags on result $" & to_hstring(value) severity note;
    flag_n <= value(7);
    if value(7 downto 0) = x"00" then
      flag_z <= '1';
    else
      flag_z <= '0';
    end if;
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

  procedure execute_implied_instruction (
    opcode : in unsigned(7 downto 0)) is
    variable i : instruction := instruction_lut(to_integer(opcode));
    variable mode : addressingmode := mode_lut(to_integer(opcode));
    -- False if handling a special instruction
    variable virtual_reg_p : unsigned(7 downto 0);
    variable temp_pc : unsigned(15 downto 0);
  begin

    -- report "Executing " & instruction'image(i) & " mode " & addressingmode'image(mode) severity note;

    -- Generate virtual processor status register for BRK
    virtual_reg_p(7) := flag_n;
    virtual_reg_p(6) := flag_v;
    virtual_reg_p(5) := flag_e;
    virtual_reg_p(4) := '0';
    virtual_reg_p(3) := flag_d;
    virtual_reg_p(2) := flag_i;
    virtual_reg_p(1) := flag_z;
    virtual_reg_p(0) := flag_c;

    -- By default go back to fetching the next instruction.
    ready_for_next_instruction(reg_pc);
    
    if mode=M_impl then
      case i is
        --when I_SETMAP =>
        --  -- load RAM map register
        --  -- Sets map register $YY to $AAXX
        --  -- Registers are:
        --  -- $00 - $0F for instruction fetch
        --  -- $10 - $1F for memory read
        --  -- $20 - $2F for memory write
        --  if reg_y(7 downto 4) = x"0" then
        --    ram_bank_registers_instructions(to_integer(reg_y(3 downto 0)))
        --      <= reg_a & reg_x;
        --  elsif reg_y(7 downto 4) = x"1" then
        --    ram_bank_registers_read(to_integer(reg_y(3 downto 0)))
        --      <= reg_a & reg_x;
        --  elsif reg_y(7 downto 4) = x"2" then
        --    ram_bank_registers_write(to_integer(reg_y(3 downto 0)))
        --      <= reg_a & reg_x;
        --  end if;
        when I_BRK =>
          -- break instruction. Push state and jump to the appropriate
          -- vector.
          vector <= x"FFFE";    -- BRK follows the IRQ vector
          -- Add one to match what a real 6502 does with virtual operand
          temp_pc := reg_pc + 1;
          reg_pc <= temp_pc;
          push_byte(temp_pc(15 downto 8),BRK1);
        when I_CLC => flag_c <= '0';
        when I_CLD => flag_d <= '0';
        when I_CLE => flag_e <= '0';
        when I_CLI => flag_i <= '0';
        when I_CLV => flag_v <= '0';
        when I_DEC => reg_a <= with_nz(reg_a - 1);
        when I_DEX => reg_x <= with_nz(reg_x - 1);
        when I_DEY => reg_y <= with_nz(reg_y - 1);
        when I_DEZ => reg_z <= with_nz(reg_z - 1);
        when I_INC => reg_a <= with_nz(reg_a + 1);
        when I_INX => reg_x <= with_nz(reg_x + 1);
        when I_INY => reg_y <= with_nz(reg_y + 1);
        when I_INZ => reg_z <= with_nz(reg_z + 1);
        when I_MAP => 
          -- XXX Implement MAP instruction
          c65_map_instruction;
          map_interrupt_inhibit <= '1';
          icache_delay <= '1';
        when I_NEG => reg_a <= with_nz((not reg_a) + 1);
        when I_PHA => push_byte(reg_a,InstructionFetch);
        when I_PHX => push_byte(reg_x,InstructionFetch);
        when I_PHY => push_byte(reg_y,InstructionFetch);
        when I_PHZ => push_byte(reg_z,InstructionFetch);
        when I_PHP =>
          virtual_reg_p(4) := '1';      -- PHP sets BRK flag.
          push_byte(virtual_reg_p,InstructionFetch);
        when I_PLA => pull_byte(PLA1);
        when I_PLX => pull_byte(PLX1);
        when I_PLY => pull_byte(PLY1);
        when I_PLZ => pull_byte(PLZ1);
        when I_PLP => pull_byte(PLP1);
        when I_RTI => pull_byte(RTI1);
        when I_RTS => pull_byte(RTS1);
        when I_SEC => flag_c <= '1';
        when I_SED => flag_d <= '1';
        when I_SEE => flag_e <= '1';
        when I_SEI => flag_i <= '1';
        when I_TAB => reg_b <= with_nz(reg_a);
        when I_TAX => reg_x <= with_nz(reg_a);
        when I_TAY => reg_y <= with_nz(reg_a);
        when I_TAZ => reg_z <= with_nz(reg_a);
        when I_TSX => reg_x <= with_nz(reg_sp);
        when I_TSY => reg_y <= with_nz(reg_sph);
        when I_TBA => reg_a <= with_nz(reg_b);
        when I_TXA => reg_a <= with_nz(reg_x);
        when I_TXS => reg_sp <= reg_x;
        when I_TYA => reg_a <= with_nz(reg_y);                      
        when I_TYS => reg_sph <= reg_y;
        when I_TZA => reg_a <= with_nz(reg_z);                      
        when I_EOM =>
          -- Does double duty as NOP.
          map_interrupt_inhibit <= '0';          
        when others => null;
      end case;
    elsif mode=M_a then
      -- We have a separate path for these so that they can be executed in 1
      -- cycle instead of incurring an extra cycle delay if passed through the
      -- normal memory-based instruction path. 
      case i is
        when I_ASL => reg_a <= with_nz(reg_a(6 downto 0) & '0'); flag_c <= reg_a(7);
        when I_ASR => reg_a <= with_nz(reg_a(7)&reg_a(7 downto 1)); flag_c <= reg_a(0);
        when I_ROL => reg_a <= with_nz(reg_a(6 downto 0) & flag_c); flag_c <= reg_a(7);
        when I_LSR => reg_a <= with_nz('0' & reg_a(7 downto 1)); flag_c <= reg_a(0);
        when I_ROR => reg_a <= with_nz(flag_c & reg_a(7 downto 1)); flag_c <= reg_a(0);
        when others => null;
      end case;
    end if;
  end procedure execute_implied_instruction;

  procedure execute_direct_instruction (
    i       : in instruction;
    address : in unsigned(15 downto 0)) is
  begin  -- execute_direct_instruction
    -- Instruction using a direct addressing mode
    if i=I_STA or i=I_STX or i=I_STY or i=I_STZ then
      -- Store instruction, so just write
      case i is
        when I_STA => write_data_byte(address,reg_a,InstructionFetch);
        when I_STX => write_data_byte(address,reg_x,InstructionFetch);
        when I_STY => write_data_byte(address,reg_y,InstructionFetch);
        when I_STZ => write_data_byte(address,reg_z,InstructionFetch);
        when others => ready_for_next_instruction(reg_pc);
      end case;
    else
      -- Instruction requires reading from memory
      report "reading operand from memory" severity note;
      reg_instruction <= i;
      reg_addr <= address; -- remember address for writeback
      read_data_byte(address,ExecuteDirect);
    end if;
  end execute_direct_instruction;

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
  
  procedure rmw_operand_commit (
    address : in unsigned(15 downto 0);
    first_value : in unsigned(7 downto 0);
    final_value : in unsigned(7 downto 0)) is
  begin
    report "first_value = $" & to_hstring(first_value)
      & ", final_value = $" & to_hstring(final_value)
      severity note;
    reg_addr <= address;
    reg_value <= with_nz(final_value);
    write_data_byte(address,first_value,RMWCommit);
  end procedure rmw_operand_commit;
  
  procedure execute_operand_instruction (
    i       : in instruction;
    operand : in unsigned(7 downto 0);
    address : in unsigned(15 downto 0)) is
    variable bitbucket : unsigned(7 downto 0);
  begin
    -- report "Calculating result for " & instruction'image(i) & " operand=$" & to_hstring(operand) severity note;
    ready_for_next_instruction(reg_pc);
    case i is
      when I_LDA => reg_a <= with_nz(operand);
      when I_LDX => reg_x <= with_nz(operand);
      when I_LDY => reg_y <= with_nz(operand);
      when I_LDZ => reg_z <= with_nz(operand);
      when I_ADC => reg_a <= alu_op_add(reg_a,operand);
      when I_AND => reg_a <= with_nz(reg_a and operand);
      when I_ASL => flag_c <= operand(7); rmw_operand_commit(address,operand,operand(6 downto 0)&'0');
      when I_ASW => flag_c <= operand(7); word_flag<='1';
                    rmw_operand_commit(address,operand,operand(6 downto 0)&'0');
      when I_ASR => flag_c <= operand(0); rmw_operand_commit(address,operand,operand(7)&operand(7 downto 1));
      when I_BIT => bitbucket := with_nz(reg_a and operand); flag_n <= operand(7); flag_v <= operand(6);
      when I_CMP => alu_op_cmp(reg_a,operand);
      when I_CPX => alu_op_cmp(reg_x,operand);
      when I_CPY => alu_op_cmp(reg_y,operand);
      when I_CPZ => alu_op_cmp(reg_z,operand);
      when I_DEC => rmw_operand_commit(address,operand,operand-1);
      when I_DEW =>
        if operand=x"00" then
          word_flag <= '1';
        end if;
        rmw_operand_commit(address,operand,operand-1);
      when I_EOR => reg_a <= with_nz(reg_a xor operand);    
      when I_INC =>
        report "INC of $" & to_hstring(operand) & " to $" & to_hstring(operand+1) severity note;
        rmw_operand_commit(address,operand,(operand+1));
      when I_INW =>
        if operand=x"FF" then
          word_flag <= '1';
        end if;
        rmw_operand_commit(address,operand,(operand+1));
      when I_LSR => flag_c <= operand(0); rmw_operand_commit(address,operand,'0'&operand(7 downto 1));
      when I_ORA => reg_a <= with_nz(reg_a or operand);
      when I_ROL => flag_c <= operand(7); rmw_operand_commit(address,operand,operand(6 downto 0)&flag_c);
      when I_ROR => flag_c <= operand(0); rmw_operand_commit(address,operand,flag_c&operand(7 downto 1));
      when I_ROW => flag_c <= operand(7); word_flag<='1';
                    rmw_operand_commit(address,operand,operand(6 downto 0)&flag_c);
      when I_SBC => reg_a <= alu_op_sub(reg_a,operand);
      when I_STA => write_data_byte(address,reg_a,InstructionFetch);
      when I_STX => write_data_byte(address,reg_x,InstructionFetch);
      when I_STY => write_data_byte(address,reg_y,InstructionFetch);
      when I_STZ => write_data_byte(address,reg_z,InstructionFetch);
      when I_TSB =>
        if (operand and reg_a) = x"00" then
          flag_z <= '1';
        else
          flag_z <= '0';
        end if;
        write_data_byte(address,reg_a or operand,InstructionFetch);
      when I_TRB =>
        if (operand and reg_a) = x"00" then
          flag_z <= '1';
        else
          flag_z <= '0';
        end if;
        write_data_byte(address,(not reg_a) and operand,InstructionFetch);
      when others => null;
    end case;
  end procedure execute_operand_instruction;

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
  
  procedure execute_instruction (      
    opcode : in unsigned(7 downto 0);
    arg1 : in unsigned(7 downto 0);
    arg2 : in unsigned(7 downto 0)
    ) is
    variable i : instruction := instruction_lut(to_integer(opcode));
    variable mode : addressingmode := mode_lut(to_integer(opcode));
  begin
    -- By default fetch next instruction
    ready_for_next_instruction(reg_pc);

    --report "Executing " & instruction'image(i)
    --  & " mode " & addressingmode'image(mode) severity note;
    
    if mode=M_rr or mode=M_rrrr then
      if (i=I_BCC and flag_c='0')
        or (i=I_BCS and flag_c='1')
        or (i=I_BVC and flag_v='0')
        or (i=I_BVS and flag_v='1')
        or (i=I_BPL and flag_n='0')
        or (i=I_BMI and flag_n='1')
        or (i=I_BEQ and flag_z='1')
        or (i=I_BNE and flag_z='0')
        or (i=I_BRA)
      then
        -- take branch
        if mode=M_rr then
          -- 8-bit branch
          if arg1(7)='0' then -- branch forwards.
            reg_pc <= reg_pc + unsigned(arg1(6 downto 0));
          else -- branch backwards.
            reg_pc <= (reg_pc - x"0080") + unsigned(arg1(6 downto 0));
          end if;
        else
          -- 16-bit branch
          if arg2(7)='0' then -- branch forwards.
            reg_pc <= reg_pc + unsigned(std_logic_vector(arg2(6 downto 0)) & std_logic_vector(arg1)) - 1;
          else -- branch backwards.
            reg_pc <= (reg_pc - x"8001") + unsigned(std_logic_vector(arg2(6 downto 0)) & std_logic_vector(arg1));
          end if;
        end if;
      end if;
    elsif mode=M_nnrr then
      -- Check if appropriate bit set/clear in operand, and then branch.
      report "opcode=$" & to_hstring(opcode);
      bbs_or_bbc <= opcode(7);
      bbs_bit <= opcode(6 downto 4);
      reg_value <= arg2;
      read_data_byte(reg_b & arg1,BranchOnBit); 
    elsif i=I_BSR then
      if arg2(7)='0' then -- branch forwards.
        reg_pc <= reg_pc + unsigned(std_logic_vector(arg2(6 downto 0)) & std_logic_vector(arg1)) - 1;
      else -- branch backwards.
        reg_pc <= (reg_pc - x"8001") + unsigned(std_logic_vector(arg2(6 downto 0)) & std_logic_vector(arg1));
      end if;
      push_byte(reg_pc_jsr(15 downto 8),JSR1);      
    elsif i=I_JSR and mode=M_nnnn then
      reg_pc <= arg2 & arg1; push_byte(reg_pc_jsr(15 downto 8),JSR1);
    elsif i=I_JSR and mode=M_Innnn then
      reg_addr <= arg2 & arg1;
      push_byte(reg_pc_jsr(15 downto 8),JSRind1);
    elsif i=I_JSR and mode=M_InnnnX then
      reg_addr <= (arg2 & arg1) + reg_x;
      push_byte(reg_pc_jsr(15 downto 8),JSRind1);
    elsif i=I_JMP and mode=M_nnnn then
      reg_pc <= arg2 & arg1; state<=InstructionFetch;
    elsif i=I_JMP and mode=M_Innnn then
      -- Read first byte of indirect vector
      read_data_byte(arg2 & arg1,JMP1);
      -- Remember address of second byte of indirect vector so that
      -- we can ask for it in JMP1
      reg_addr <= arg2 & (arg1 +1);
    elsif i=I_JMP and mode=M_InnnnX then
      -- Read first byte of indirect vector
      read_data_byte((arg2 & arg1) + reg_x,JMP1);
      -- Remember address of second byte of indirect vector so that
      -- we can ask for it in JMP1
      reg_addr <= (arg2 & arg1) + reg_x +1;
    elsif mode=M_InnX then
      -- Read ZP indirect from data memory map, since ZP is written into that
      -- map.
      reg_instruction <= i;
      reg_addr <= x"00" & (arg1 + reg_x +1);
      read_data_byte(x"00" & (arg1 + reg_x),IndirectX1);
    elsif mode=M_InnY then
      reg_instruction <= i;
      reg_addr <= x"00" & (arg1 + 1);
      read_data_byte(x"00" & arg1,IndirectY1);
    elsif mode=M_InnSPY then
      -- Whacked out 4510 addressing mode pre-indexed by SP, post-indexed by Y
      -- (presumably used for accessing stack variables)
      -- Address is (reg_sph & reg_sp + operand) post-indexed by Y
      reg_instruction <= i;
      reg_addr <= ((reg_sph & reg_sp) + arg1 + 1);
      read_data_byte(((reg_sph & reg_sp) + arg1),IndirectY1);
    elsif mode=M_InnZ then
      reg_instruction <= i;
      reg_addr <= x"00" & (arg1 + 1);
      read_data_byte(x"00" & arg1,IndirectZ1);
    else
      --report "executing direct instruction" severity note;
      case mode is
        -- Direct modes
        when M_nn => execute_direct_instruction(i,arg2&arg1);
        when M_nnX => execute_direct_instruction(i,arg2&(arg1+reg_x));
        when M_nnY => execute_direct_instruction(i,arg2&(arg1+reg_y));
        when M_nnnn => execute_direct_instruction(i,arg2&arg1);
        when M_nnnnX => execute_direct_instruction(i,(arg2&arg1)+reg_x);
        when M_nnnnY => execute_direct_instruction(i,(arg2&arg1)+reg_y);
        when M_immnn => execute_operand_instruction(i,arg1,x"0000");
        when M_immnnnn =>
          -- PHW #$nnnn is the only instruction with this mode
          reg_value <= arg2;
          push_byte(arg1,PHWimm1);
        when others =>
          report "mode = " & addressingmode'image(mode) severity note;
          assert false report "Uncaught instruction mode" severity failure;
      end case;
    end if;
  end procedure execute_instruction;      

  variable virtual_reg_p : std_logic_vector(7 downto 0);
  variable temp_pc : unsigned(15 downto 0);
  variable temp_value : unsigned(7 downto 0);
  begin

    -- BEGINNING OF MAIN PROCESS FOR CPU
    if rising_edge(clock) then
      -- clear memory access states
      colour_ram_cs <= '0';
      colour_ram_cs_last <= '0';
      accessing_ram <= '0'; accessing_slowram <= '0';
      accessing_fastio <= '0'; accessing_vic_fastio <= '0';
      accessing_cpuport <= '0';

      monitor_state <= std_logic_vector(to_unsigned(processor_state'pos(state),8));
      monitor_pc <= std_logic_vector(reg_pc);
      monitor_a <= std_logic_vector(reg_a);
      monitor_x <= std_logic_vector(reg_x);
      monitor_y <= std_logic_vector(reg_y);
      monitor_z <= std_logic_vector(reg_z);
      monitor_sp <= std_logic_vector(reg_sph) & std_logic_vector(reg_sp);
      monitor_b <= std_logic_vector(reg_b);
      monitor_map_offset_low <= std_logic_vector(reg_offset_low);
      monitor_map_offset_high <= std_logic_vector(reg_offset_high); 
      monitor_map_enables_low <= std_logic_vector(reg_map_low); 
      monitor_map_enables_high <= std_logic_vector(reg_map_high); 
      
      -- Clear memory access interfaces
      -- Allow fastio to continue reading to support 1 cycle wait state
      -- for those fastio addresses that require it.
      -- XXX This can have problems for reading from registers that have
      -- special side effects.
      accessing_fastio <= '0';
      accessing_vic_fastio <= '0';
      if accessing_fastio='0' then
        fastio_addr <= (others => '1');
        fastio_read <= '0';
      else
        fastio_addr <= last_fastio_addr;
      end if;
      fastio_write <= '0';
      fastram_we <= (others => '0');
      fastram_address <= "11111111111111";
      fastram_datain <= x"d0d1d2d3d4d5d6d7";

      -- By default don't wait an extra cycle before reading the cache
      icache_delay <= '0';
      -- By default we are not reading from the cache
      accessing_icache <= '0';
      
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


      if reset = '0' or state = ResetLow then

        -- reset cpu
        kickstart_en <= '1';
        state <= VectorRead;
        vector <= x"FFFC";
        reset_cpu_state;
      elsif monitor_mem_attention_request='1' and state = InstructionFetch then
        -- Memory access by serial monitor.
        if monitor_mem_write='1' then
          -- Write to specified long address
          write_long_byte(unsigned(monitor_mem_address),monitor_mem_wdata,
                          MonitorAccessDone);
        elsif monitor_mem_read='1' then          
          -- Read from specified long address
          if monitor_mem_address(27 downto 16) = x"777" then
            -- M777xxxx in serial monitor reads memory from CPU's perspective
            read_long_address(resolve_address_to_long(unsigned(monitor_mem_address(15 downto 0)),false),MonitorReadDone);
          else
            read_long_address(unsigned(monitor_mem_address),MonitorReadDone);
          end if;
          -- and optionally set PC
          if monitor_mem_setpc='1' then
            report "PC set by monitor interface" severity note;
            reg_pc <= unsigned(monitor_mem_address(15 downto 0));
          end if;
        end if;   
      else

        -- CPU running, so do CPU state machine
        if monitor_mem_attention_request='0' then
          check_for_interrupts;
        end if;

        if monitor_mem_stage_trace_mode='0' or
          monitor_mem_trace_toggle /= monitor_mem_trace_toggle_last then
          monitor_mem_trace_toggle_last <= monitor_mem_trace_toggle;
          case state is
            when MonitorReadDone =>            
              monitor_mem_rdata <= read_data;
              state <= MonitorAccessDone;
            when MonitorAccessDone =>
              fastram_we <= (others => '0');
              monitor_mem_attention_granted <= '1';
              if monitor_mem_attention_request='0' then
                monitor_mem_attention_granted <= '0';
                ready_for_next_instruction(reg_pc);
              end if;
            when Interrupt =>
              push_byte(reg_pc(15 downto 8),Interrupt2);
            when Interrupt2 => push_byte(reg_pc(7 downto 0),Interrupt3);
            when Interrupt3 => push_byte(unsigned(virtual_reg_p),VectorRead); flag_i <= '1';
            when VectorRead => reg_pc <= vector; read_instruction_byte(vector,VectorRead2);
            when VectorRead2 => reg_pc(7 downto 0) <= read_data; read_instruction_byte(vector+1,VectorRead3);
            when VectorRead3 =>
              reg_pc(15 downto 8) <= read_data;
              ready_for_next_instruction(read_data & reg_pc(7 downto 0));
            when InstructionFetch =>

              -- Show CPU state for debugging
              -- report "state = " & processor_state'image(state) severity note;
              -- Use a format very like that of VICE so that we can compare our boot
              -- sequence to theirs, to find errors in our CPU etc.

              report ""
                & ".C:" & to_hstring(std_logic_vector(reg_pc))
                & " - A:" & to_hstring(std_logic_vector(reg_a))
                & " X:" & to_hstring(std_logic_vector(reg_x))
                & " Y:" & to_hstring(std_logic_vector(reg_y))
                & " SP:" & to_hstring(std_logic_vector(reg_sp))
                & " "
                & flag_status("N",".",flag_n)
                & flag_status("V",".",flag_v)
                & "-"
                & "."
                & flag_status("D",".",flag_d)
                & flag_status("I",".",flag_i)
                & flag_status("Z",".",flag_z)
                & flag_status("C",".",flag_c)        
                severity note;        
              
              monitor_mem_attention_granted <= '0';
              if monitor_mem_trace_mode='0' or
                monitor_mem_trace_toggle /= monitor_mem_trace_toggle_last then
                monitor_mem_trace_toggle_last <= monitor_mem_trace_toggle;

                -- XXX Push PC & P before launching interrupt handlers
                if nmi_pending='1' then
                  nmi_pending <= '0';
                  vector <= x"FFFA"; state <=Interrupt;
                elsif irq_pending='1' and flag_i='0' then
                  irq_pending <= '0';
                  vector <= x"FFFE"; state <=Interrupt;  
                else
                  read_instruction_byte(reg_pc,InstructionFetch2);
                  reg_pc <= reg_pc + 1;
                  report "reg_pc bump from $" & to_hstring(reg_pc) severity note;
                end if;
              end if;
            when InstructionFetch2 =>
              -- Keep reading bytes if necessary
              if mode_lut(to_integer(read_data))=M_impl
                or mode_lut(to_integer(read_data))=M_a then
                -- 1-byte instruction, process now
                execute_implied_instruction(read_data);
              else
                report "opcode: read_data = %" & to_string(std_logic_vector(read_data)) severity note;
                opcode <= read_data;
                monitor_opcode <= std_logic_vector(read_data);
                reg_pc <= reg_pc + 1;
                report "reg_pc bump from $" & to_hstring(reg_pc) severity note;
                read_instruction_byte(reg_pc,InstructionFetch3);
              end if;
            when InstructionFetch3 =>
              if mode_bytes_lut(mode_lut(to_integer(opcode)))=2 then
                arg1 <= read_data;
                reg_pc <= reg_pc + 1;
                reg_pc_jsr <= reg_pc;     -- keep PC after one operand for JSR
                report "reg_pc bump from $" & to_hstring(reg_pc) severity note;
                read_instruction_byte(reg_pc,InstructionFetch4);
              else
                execute_instruction(opcode,read_data,x"00");
              end if;
            when InstructionFetch4 =>
              report "reg_pc is $" & to_hstring(reg_pc) severity note;
              execute_instruction(opcode,arg1,read_data);
            when BRK1 => push_byte(reg_pc(7 downto 0),BRK2);
            when BRK2 =>
              -- set B flag in P before pushing
              push_byte(unsigned(virtual_reg_p(7 downto 5)
                                 & '1' & virtual_reg_p(3 downto 0)),VectorRead);
              flag_i <= '1';            -- disable interrupts while servicing BRK
            when PLA1 => reg_a<=with_nz(read_data); ready_for_next_instruction(reg_pc);
            when PLX1 => reg_x<=with_nz(read_data); ready_for_next_instruction(reg_pc);
            when PLY1 => reg_y<=with_nz(read_data); ready_for_next_instruction(reg_pc);
            when PLZ1 => reg_z<=with_nz(read_data); ready_for_next_instruction(reg_pc);
            when PLP1 => load_processor_flags(read_data);
                         ready_for_next_instruction(reg_pc);
            when RTI1 => load_processor_flags(read_data); pull_byte(RTI2);
            when RTI2 => reg_pc(7 downto 0) <= read_data; pull_byte(RTI3);
            when RTI3 => temp_pc := read_data & reg_pc(7 downto 0);
                         reg_pc <= temp_pc; ready_for_next_instruction(temp_pc);
            when RTS1 => reg_pc(7 downto 0) <= read_data; pull_byte(RTS2);
            when RTS2 => temp_pc := (read_data & reg_pc(7 downto 0))+1;
                         reg_pc <= temp_pc; ready_for_next_instruction(temp_pc);
            when JSR1 => push_byte(reg_pc_jsr(7 downto 0),InstructionFetch);
            when JSRind1 => push_byte(reg_pc_jsr(7 downto 0),JSRind2);
            when JSRind2 =>
              read_data_byte(reg_addr,JSRind3);
              reg_addr <= reg_addr + 1;
            when JSRind3 =>
              reg_pc(7 downto 0) <= read_data;
              read_data_byte(reg_addr,JSRind4);
            when JSRind4 =>
              reg_pc(15 downto 8) <= read_data;
              ready_for_next_instruction(read_data & reg_pc(7 downto 0));
            when PHWimm1 => push_byte(reg_value,InstructionFetch);
            when JMP1 =>
              -- Add a wait state to see if it fixes our problem with not loading
              -- addresses properly for indirect jump
              reg_pc(7 downto 0)<=read_data;
              state <= JMP2;
            when JMP2 =>
              -- Request reading of high byte of vector
              read_data_byte(reg_addr,JMP3);
              -- Store low byte of vector into PCL
              report "read PCL as $" & to_hstring(read_data) severity note;
            when JMP3 =>
              -- Now assemble complete vector
              report "read PCH as $" & to_hstring(read_data) severity note;
              reg_pc(15 downto 8) <= read_data;
              -- And then continue executing from there
              ready_for_next_instruction(read_data & reg_pc(7 downto 0));
            when IndirectX1 =>
              reg_addr(7 downto 0) <= read_data;
              report "(ZP,x) - low byte = $" & to_hstring(read_data) severity note;
              read_data_byte(reg_addr,IndirectX2);
            when IndirectX2 =>
              reg_addr(15 downto 8) <= read_data;
              report "(ZP,x) - high byte = $" & to_hstring(read_data) severity note;
              report "(ZP,x) - operand address = $"
                & to_hstring(read_data & reg_addr(7 downto 0))
                severity note;
              read_data_byte(read_data & reg_addr(7 downto 0),IndirectX3);
            when IndirectX3 =>
              execute_operand_instruction(reg_instruction,read_data,reg_addr);
            when IndirectY1 =>
              reg_addr(7 downto 0) <= read_data;
              report "(ZP),y or (d,SP),Y - low byte = $" & to_hstring(read_data) severity note;
              read_data_byte(reg_addr,IndirectY2);
            when IndirectY2 =>
              reg_addr <= (read_data & reg_addr(7 downto 0)) + reg_y;
              report "(ZP),y or (d,SP),Y - high byte = $" & to_hstring(read_data) severity note;
              report "(ZP),y or (d,SP),Y - operand address = $"
                & to_hstring((read_data & reg_addr(7 downto 0)) + reg_y)
                severity note;
              read_data_byte((read_data & reg_addr(7 downto 0)) + reg_y,IndirectY3);
            when IndirectY3 =>
              execute_operand_instruction(reg_instruction,read_data,reg_addr);
            when IndirectZ1 =>
              reg_addr(7 downto 0) <= read_data;
              report "(ZP),z - low byte = $" & to_hstring(read_data) severity note;
              read_data_byte(reg_addr,IndirectZ2);
            when IndirectZ2 =>
              reg_addr <= (read_data & reg_addr(7 downto 0)) + reg_z;
              report "(ZP),z - high byte = $" & to_hstring(read_data) severity note;
              report "(ZP),z - operand address = $"
                & to_hstring((read_data & reg_addr(7 downto 0)) + reg_z)
                severity note;
              read_data_byte((read_data & reg_addr(7 downto 0)) + reg_z,IndirectY3);
            when ExecuteDirect =>
              execute_operand_instruction(reg_instruction,read_data,reg_addr);
            when RMWCommit =>
              word_flag <= '0';
              if word_flag='0' then
                write_data_byte(reg_addr,reg_value,InstructionFetch);
              else                
                write_data_byte(reg_addr,reg_value,RMWCommit2);
                reg_addr <= reg_addr + 1;
              end if;
            when RMWCommit2 =>
              -- INW or DEW
              -- prepare to inc/dec high byte
              read_data_byte(reg_addr,RMWCommit3);
            when RMWCommit3 =>
              if reg_instruction=I_INW then
                write_data_byte(reg_addr,with_nz(read_data+1),InstructionFetch);
              elsif reg_instruction=I_DEW then
                write_data_byte(reg_addr,with_nz(read_data-1),InstructionFetch);
              elsif reg_instruction=I_ASW then
                flag_c <= read_data(7);
                write_data_byte(reg_addr,with_nz(read_data(6 downto 0)&flag_c),InstructionFetch);
              elsif reg_instruction=I_ROW then
                flag_c <= read_data(7);
                write_data_byte(reg_addr,with_nz(read_data(6 downto 0)&flag_c),InstructionFetch);
              end if;
            when FastRamWait =>
              accessing_ram <= '1';
              if pending_state = InstructionFetch then
                ready_for_next_instruction(reg_pc);
              else
                state <= pending_state;
              end if;
            when FastIOWait =>
              -- hold colour ram access for the extra cycle necessary
              -- (we clear it at the start of the process)
              colour_ram_cs <= colour_ram_cs_last;
              accessing_fastio <= accessing_fastio;
              accessing_vic_fastio <= accessing_vic_fastio;

              state <= pending_state; accessing_fastio <= '1';
            when SlowRamRead1 =>
              slowram_ce <= '0';
              slowram_oe <= '0';
              slowram_lb <= '0';
              slowram_ub <= '0';
              slowram_counter <= x"00";
              accessing_slowram <= '1';
              state <= SlowRamRead2;
            when SlowRamRead2 =>
              accessing_slowram <= '1';
              if slowram_counter=slowram_waitstates then
                if pending_state = InstructionFetch then
                  ready_for_next_instruction(reg_pc);
                else
                  state <= pending_state;
                end if;
              else
                slowram_counter <= slowram_counter + 1;
              end if;
            when SlowRamWrite1 =>
              slowram_ce <= '0';
              slowram_oe <= '0';
              slowram_we <= '0';
              slowram_lb <= slowram_lohi;
              slowram_ub <= not slowram_lohi;
              slowram_counter <= x"00";
              state <= SlowRamWrite2;
            when SlowRamWrite2 =>
              if slowram_counter=slowram_waitstates then
                if pending_state = InstructionFetch then
                  ready_for_next_instruction(reg_pc);
                else
                  state <= pending_state;
                end if;
                slowram_ce <= '1';
                slowram_oe <= '1';
                slowram_we <= '1';
                slowram_data <= (others => 'Z');  -- tristate data lines
              else
                slowram_counter <= slowram_counter + 1;
              end if;
            when BranchOnBit =>
              report "BBS/BBR: bbs_bit=" & integer'image(to_integer(bbs_bit)) severity note;
              report "read_data = %" & to_string(std_logic_vector(read_data)) severity note;
              temp_value := read_data;
              if temp_value(to_integer(bbs_bit))
                = bbs_or_bbc then
                report "taking branch" severity note;
                -- 8-bit branch
                if reg_value(7)='0' then -- branch forwards.
                  reg_pc <= reg_pc + unsigned(reg_value(6 downto 0));
                else -- branch backwards.
                  reg_pc <= (reg_pc - x"0080") + unsigned(reg_value(6 downto 0));
                end if;
              else
                -- branch not taken.
              end if;
              ready_for_next_instruction(reg_pc);
            when others =>
              -- Don't allow CPU to stay stuck
              ready_for_next_instruction(reg_pc);
          end case;
        end if;
      end if;
    end if;
  end process;

  -- purpose: present MMU registers and other stuff to fastio interface
  -- type   : combinational
  -- inputs : ram_bank_registers_read
  -- outputs: fastio_*
  fastio: process (fastio_addr,fastio_read,nmi_pending,
                   irq,irq_pending,clock,slowram_waitstates,nmi)
    variable address : unsigned(19 downto 0);
    variable rwx : integer;
    variable lohi : std_logic;
    variable value : unsigned(15 downto 0);
    variable reg_num : integer;
  begin  -- process fastio
    if rising_edge(clock) and fastio_read='1' then
      if (address = x"D3703") or (address = x"D1703") then
         -- Side-effects of reading from DMAgic status register
         -- NOT IMPLEMENTED
        null;
      end if;
    end if;
    if rising_edge(clock) and fastio_write='1' then
      if (address = x"D3700") or (address = x"D1700") then
        -- Set low order bits of DMA list address
        reg_dmagic_addr(7 downto 0) <= unsigned(fastio_rdata);
        -- Remember that after this instruction we want to perform the
        -- DMA.
        dma_pending <= '1';
        -- NOTE: DMAgic in C65 prototypes might not use the same list format as
        -- in the C65 specifications manual (as the manual warns).
        -- So need to double check how it is used in the C65 ROM.
        -- From the ROMs, it appears that the list format is:
        -- list+$03 = source address bit7-0
        -- list+$04 = source address bit15-8
        -- list+$05 = source address bank
        -- list+$06 = dest address bit7-0
        -- list+$07 = dest address bit15-8
        -- list+$08 = dest address bank
      elsif (address = x"D3701") or (address = x"D1701") then
        reg_dmagic_addr(15 downto 8) <= unsigned(fastio_rdata);
      elsif (address = x"D3702") or (address = x"D1702") then
        reg_dmagic_addr(23 downto 16) <= unsigned(fastio_rdata);
      end if;
    end if;
    if fastio_read='1' then
      if (address = x"D3700") or (address = x"D1700") then
        fastio_rdata <= std_logic_vector(reg_dmagic_addr(7 downto 0));
      elsif (address = x"D3701") or (address = x"D1701") then
        fastio_rdata <= std_logic_vector(reg_dmagic_addr(15 downto 8));
      elsif (address = x"D3702") or (address = x"D1702") then
        fastio_rdata <= std_logic_vector(reg_dmagic_addr(23 downto 16));
      elsif (address = x"D3703") or (address = x"D1703") then        
        fastio_rdata <= std_logic_vector(reg_dmagic_status);
      end if;
    end if;
    if fastio_read='1' and address(19 downto 8) = x"FC0" then
      address := unsigned(fastio_addr);
      rwx := to_integer(address(7 downto 5));
      lohi := fastio_addr(0);
      reg_num := to_integer(address(4 downto 1));
      
      case rwx is
--        when 0 => value := ram_bank_registers_read(reg_num);
--        when 1 => value := ram_bank_registers_read(reg_num);
--        when 2 => value := ram_bank_registers_read(reg_num);
        when 5 => value := x"FF" & slowram_waitstates;
        when 6 => value := x"EEE" & irq & irq_pending & nmi & nmi_pending;
--        when 7 => value := recent_states(reg_num);
        when others => value := x"F00D";
      end case;
      if lohi='0' then
        fastio_rdata <= std_logic_vector(value(7 downto 0));
      else
        fastio_rdata <= std_logic_vector(value(15 downto 8));
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;
  end process fastio;
end Behavioural;
