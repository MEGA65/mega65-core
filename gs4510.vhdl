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
    ioclock : in std_logic;
    io_wait_states : in unsigned(7 downto 0);
    reset : in std_logic;
    irq : in std_logic;
    nmi : in std_logic;
    monitor_pc : out std_logic_vector(15 downto 0);
    monitor_state : out unsigned(7 downto 0);
    monitor_watch : in std_logic_vector(27 downto 0);
    monitor_watch_match : out std_logic;
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
  signal slowram_waitstates : unsigned(7 downto 0) := x"09";

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
  
  type microcodeops_t is array (0 to 255) of std_logic_vector(63 downto 0);
  signal microcodeops : microcodeops_t := (
    -- Fetch next instruction
    0 => "0000000000000000000000000000000000000000000000000000000000000000",
    1 => "0000000000000000000000000000000000000000000000000000000000000000",
    2 => "0000000000000000000000000000000000000000000000000000000000000000",
    3 => "0000000000000000000000000000000000000000000000000000000000000000",
    4 => "0000000000000000000000000000000000000000000000000000000000000000",
    5 => "0000000000000000000000000000000000000000000000000000000000000000",
    6 => "0000000000000000000000000000000000000000000000000000000000000000",
    7 => "0000000000000000000000000000000000000000000000000000000000000000",
    8 => "0000000000000000000000000000000000000000000000000000000000000000",
    9 => "0000000000000000000000000000000000000000000000000000000000000000",
    others => "0000000000000000000000000000000000000000000000000000000000000000");

  -- 4x CPU personalities x 256 instructions x 16 cycles maximum per instruction =
  -- 16KB
  type instructions_t is array (0 to 16383) of unsigned(7 downto 0);
  signal opcodeops : instructions_t := (
    -- 4510 personality
    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00", --$00 BRK
    
    
    -- In doubt, fetch the next instruction
    others => x"00");

  -- Information about instruction currently being executed
  signal opcode : unsigned(7 downto 0);
  signal arg1 : unsigned(7 downto 0);
  signal arg2 : unsigned(7 downto 0);

  signal bbs_or_bbc : std_logic;
  signal bbs_bit : unsigned(2 downto 0);
    
  -- PC used for JSR is the value of reg_pc after reading only one of
  -- of the argument bytes.  We could subtract one, but it is less logic to
  -- just remember PC after reading one argument byte.
  signal reg_pc_jsr : unsigned(15 downto 0);
  -- Temporary address register (used for indirect modes)
  signal reg_addr : unsigned(15 downto 0);
  -- Temporary instruction register (used for many modes).
  -- (includes CPU personality state, partly so that RESET and interrupts can
  -- be mapped to instructions).
  signal reg_opcode : unsigned(9 downto 0);
  -- CPU personality: 00 = 4510, 01 = 6502/6510, 1x = reserved
  signal reg_personality : unsigned(1 downto 0) := "00";
  -- Temporary value holder (used for RMW instructions)
  signal reg_value : unsigned(7 downto 0);

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

  signal microcode_vector : std_logic_vector(63 downto 0);

  -- Microcode data and ALU routing signals follow:

  signal mem_reading : std_logic := '0';
  signal mem_reading_a : std_logic := '0';
  signal mem_reading_x : std_logic := '0';
  signal mem_reading_y : std_logic := '0';
  signal mem_reading_z : std_logic := '0';
  signal mem_reading_p : std_logic := '0';
  signal mem_reading_pcl : std_logic := '0';
  signal mem_reading_pch : std_logic := '0';
  -- serial monitor is reading data 
  signal monitor_mem_reading : std_logic := '0';

  type processor_state is (
    -- Reset and interrupts
    ResetLow,Interrupt,VectorRead1,VectorRead2,

    -- DMAgic
    DMAgic0,DMAgic1,DMAgic2,DMAgic3,DMAgic4,DMAgic5,DMAgic6,DMAgic7,
    DMAgic8,DMAgic9,DMAgic10,DMAgic11,DMAgic12,DMAgic13,DMAgic14,DMAgic15,

    -- Normal instructions
    InstructionWait,                    -- Wait for PC to become available on
                                        -- interrupt/reset
    InstructionFetch,
    InstructionDecode,
    Operand1Fetch,
    Operand2Fetch,
    ZPDereference,
    AbsDereference,
    MemoryRead,
    MemoryDummyWrite,
    MemoryWrite,
    Push1,
    Push2,
    Pop1,
    Pop2,
    Jump
    );
  signal state : processor_state := ResetLow;

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
  
begin

  shadowram0 : shadowram port map (
    clk     => clock,
    address => std_logic_vector(shadow_address),
    we      => shadow_write,
    cs      => '1',
    data_i  => std_logic_vector(shadow_wdata),
    unsigned(data_o)  => shadow_rdata);
  
  process(clock)

    procedure reset_cpu_state is
  begin
    -- Set microcode state for reset
    -- This is a little bit fun because we need to basically make an opcode for
    -- reset.  $FF in CPU personality 3 will do the trick.

    instruction_phase <= x"0";
    reg_opcode <= (others => '1');
    microcode_vector <= (0 => '1', 1 => '1',
                         others => '0');
    
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

    -- On boot up, don't shadow chipram.
    -- Instead shadow unmapped address space at $C0000 (768KB)
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
    if long_address(27 downto 16)="0000"&shadow_bank then
      -- Reading from 256KB shadow ram (which includes 128KB fixed shadowing of
      -- chipram).  This is the only memory running at the CPU's native clock.
      -- Think of it as a kind of direct-mapped L1 cache.
      accessing_shadow <= '1';
      wait_states <= x"00";
      shadow_address <= long_address(17 downto 0);
      shadow_write <= '0';
      report "Reading from shadow ram address $" & to_hstring(long_address(17 downto 0))
        & ", word $" & to_hstring(long_address(18 downto 3)) severity note;
    elsif long_address(27 downto 17)="00000000000" then
      -- Reading from chipram, so read from the bottom 128KB of the shadow RAM
      -- instead.
      accessing_shadow <= '1';
      shadow_address <= '0'&long_address(16 downto 0);
      shadow_write <= '0';
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
      -- XXX kickstart ROM has trouble reading instruction arguments @ 48MHz with
      -- 0 wait states on the kickstart ROM.  This may be related to the existing
      -- known glitching of the kickstart ROM, which is why we copy it to chipram
      -- before running it.  So removing the following exemption from wait state
      -- may allow correct 48MHz operation.
      if -- long_address(19 downto 17)="111"
        --or long_address(19 downto 8)=x"D0C" or long_address(19 downto 8)=x"D0D"
        --or long_address(19 downto 8)=x"D1C" or long_address(19 downto 8)=x"D1D"
        --or long_address(19 downto 8)=x"D2C" or long_address(19 downto 8)=x"D2D"
        --or long_address(19 downto 8)=x"D3C" or long_address(19 downto 8)=x"D3D"
        -- F011 FDC @ $D080-$D09F requires a wait state, but only appears in the
        -- enhanced image pages.
        long_address(19 downto 8)=x"D00" or long_address(19 downto 7)=x"D10"&'0'
        or long_address(19 downto 8)=x"D20" or long_address(19 downto 7)=x"D30"&'0'
      then 
        null;
      else
        wait_states <= io_wait_states;
      end if;
    else
      -- Don't let unmapped memory jam things up
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

  -- purpose: obtain the byte of memory that has been read
  impure function read_data
    return unsigned is
  begin  -- read_data
    -- CPU hosted IO registers
    if the_read_address = x"FFC00A0" then
      return slowram_waitstates;
    elsif (the_read_address = x"FFD3703") or (the_read_address = x"FFD1703") then
      return reg_dmagic_status;
    elsif (the_read_address = x"FFD370B") then
      return reg_dmagic_addr(7 downto 0);
    elsif (the_read_address = x"FFD370C") then
      return reg_dmagic_addr(15 downto 8);
    elsif (the_read_address = x"FFD370D") then
      return reg_dmagic_addr(23 downto 16);
    elsif (the_read_address = x"FFD370E") then
      return x"0" & reg_dmagic_addr(27 downto 24);
    elsif (the_read_address = x"FFD370F") or (the_read_address = x"FFD170F") then
      return reg_dmacount;
    elsif (the_read_address = x"FFD3710") or (the_read_address = x"FFD1710") then
      return dma_checksum(7 downto 0);
    elsif (the_read_address = x"FFD3711") or (the_read_address = x"FFD1711") then
      return dma_checksum(15 downto 8);
    elsif (the_read_address = x"FFD3712") or (the_read_address = x"FFD1712") then
      return dma_checksum(23 downto 16);
    elsif (the_read_address = x"FFD3720") or (the_read_address = x"FFD1720") then
      return dmagic_count(7 downto 0);
    elsif (the_read_address = x"FFD3721") or (the_read_address = x"FFD1721") then
      return dmagic_count(15 downto 8);
    elsif (the_read_address = x"FFD3722") or (the_read_address = x"FFD1722") then
      return dmagic_tally(7 downto 0);
    elsif (the_read_address = x"FFD3723") or (the_read_address = x"FFD1723") then
      return dmagic_tally(15 downto 8);
    elsif (the_read_address = x"FFD3728") or (the_read_address = x"FFD1728") then
      return dmagic_src_addr(7 downto 0);
    elsif (the_read_address = x"FFD3729") or (the_read_address = x"FFD1729") then
      return dmagic_src_addr(15 downto 8);
    elsif (the_read_address = x"FFD372a") or (the_read_address = x"FFD172a") then
      return dmagic_src_addr(23 downto 16);
    elsif (the_read_address = x"FFD372b") or (the_read_address = x"FFD172b") then
      return "0000"&dmagic_src_addr(27 downto 24);
    elsif (the_read_address = x"FFD372c") or (the_read_address = x"FFD172c") then
      return dmagic_dest_addr(7 downto 0);
    elsif (the_read_address = x"FFD372d") or (the_read_address = x"FFD172d") then
      return dmagic_dest_addr(15 downto 8);
    elsif (the_read_address = x"FFD372e") or (the_read_address = x"FFD172e") then
      return dmagic_dest_addr(23 downto 16);
    elsif (the_read_address = x"FFD372f") or (the_read_address = x"FFD172f") then
      return "0000"&dmagic_dest_addr(27 downto 24);
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
      report "reading VIC fastio byte $" & to_hstring(fastio_vic_rdata) severity note;
      return unsigned(fastio_vic_rdata);
    elsif accessing_fastio='1' then
      report "reading normal fastio byte $" & to_hstring(fastio_rdata) severity note;
      return unsigned(fastio_rdata);
    elsif accessing_slowram='1' then
      report "reading slow RAM data. Word is $" & to_hstring(slowram_data) severity note;
      slowram_ce <= '1'; -- Release after reading so that refresh can occur
      slowram_data <= (others => 'Z');  -- tristate data lines as well
      case slowram_lohi is
        when '0' => return unsigned(slowram_data(7 downto 0));
        when '1' => return unsigned(slowram_data(15 downto 8));
        when others => return x"FE";
      end case;
    else
      report "accessing unmapped memory" severity note;
      return x"A0";                     -- make unmmapped memory obvious
    end if;
  end read_data; 

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
    if long_address(27 downto 16)="0000"&shadow_bank then
      report "writing to shadow RAM via shadow_bank" severity note;
      shadow_write <= '1';
      shadow_address <= long_address(17 downto 0);
      shadow_wdata <= value;
    end if;
    if long_address(27 downto 17)="00000000000" then
      report "writing to shadow RAM via chipram shadowing. addr=$" & to_hstring(long_address) severity note;
      shadow_write <= '1';
      shadow_address <= long_address(17 downto 0);
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

  variable pc_inc : std_logic := '0';
  
  begin

    -- BEGINNING OF MAIN PROCESS FOR CPU
    if rising_edge(clock) then


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
      
      if reset='0' then
        reset_cpu_state;
        state <= ResetLow;
      else
        -- Honour wait states on memory accesses
      -- Clear memory access lines unless we are in a memory wait state
        if wait_states /= x"00" then
          report "  $" & to_hstring(wait_states) &" memory waitstates remaining.  Fastio_rdata = $" & to_hstring(fastio_rdata) & ", mem_reading=" & std_logic'image(mem_reading) severity note;
          wait_states <= wait_states - 1;
        else
          -- End of wait states, so clear memory writing and reading
          colour_ram_cs <= '0';
          shadow_write <= '0';       
          fastio_write <= '0';
          fastio_read <= '0';
          fastram_we <= (others => '0');        
          slowram_we <= '1';
          slowram_ce <= '1';
          slowram_oe <= '1';

          if mem_reading='1' then
            memory_read_value := read_data;
            report "resetting mem_reading" severity note;
            mem_reading <= '0';
            mem_reading_pcl <= '0';
            mem_reading_pch <= '0';
            monitor_mem_reading <= '0';
          end if;          
  
          if monitor_mem_attention_request='1' then
            -- Memory access by serial monitor.
            if monitor_mem_write='1' then
              -- Write to specified long address (or short if address is $777xxxx)
              monitor_mem_attention_granted <= '1';
              memory_access_address := unsigned(monitor_mem_address);
              memory_access_write := '1';
              memory_access_wdata := monitor_mem_wdata;
              if monitor_mem_address(27 downto 16) = x"777" then
                -- M777xxxx in serial monitor reads memory from CPU's perspective
                memory_access_resolve_address := '1';
              end if;
            elsif monitor_mem_read='1' then          
              memory_access_address := unsigned(monitor_mem_address);
              memory_access_read := '1';
              -- Read from specified long address
              if monitor_mem_address(27 downto 16) = x"777" then
                -- M777xxxx in serial monitor reads memory from CPU's perspective
                memory_access_resolve_address := '1';
              end if;
              monitor_mem_reading <= '1';
              mem_reading <= '1';
            end if;
            -- and optionally set PC
            if monitor_mem_setpc='1' then
              report "PC set by monitor interface" severity note;
              reg_pc <= unsigned(monitor_mem_address(15 downto 0));
            end if;
          else
            monitor_mem_attention_granted <= '0';

            if monitor_mem_trace_mode='0' or
              monitor_mem_trace_toggle_last /= monitor_mem_trace_toggle then
              monitor_mem_trace_toggle_last <= monitor_mem_trace_toggle;
              
              -- Main state machine for CPU
              report "CPU state = " & processor_state'image(state) & ", PC=$" & to_hstring(reg_pc) severity note;
              case state is
                when ResetLow =>
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
                  -- XXX Really do stuff
                  state <= InstructionFetch;
                when others => null;
              end case;
            end if;
          end if;

          if pc_inc = '1' then
            reg_pc <= reg_pc + 1;
          end if;
          
          -- Route memory read value as required
          if mem_reading='1' then
            report "memory read value is $" & to_hstring(memory_read_value) severity note;
            if monitor_mem_reading='1' then
              monitor_mem_attention_granted <= '1';
              monitor_mem_rdata <= memory_read_value;
            end if;
            if mem_reading_a='1' then reg_a <= memory_read_value; end if;
            if mem_reading_x='1' then reg_x <= memory_read_value; end if;
            if mem_reading_y='1' then reg_y <= memory_read_value; end if;
            if mem_reading_z='1' then reg_z <= memory_read_value; end if;
            if mem_reading_p='1' then load_processor_flags(memory_read_value); end if;
            if mem_reading_pcl='1' then reg_pc(7 downto 0) <= memory_read_value; end if;
            if mem_reading_pch='1' then reg_pc(15 downto 8) <= memory_read_value; end if;
          end if;

          -- Effect memory accesses.
          -- Note that we cannot combine address resolution for read and write,
          -- because the resolution of some addresses is dependent on whether
          -- the operation is read or write.  ROM accesses are a good example.
          if memory_access_write='1' then
            if memory_access_resolve_address = '1' then
              memory_access_address := resolve_address_to_long(memory_access_address(15 downto 0),true);
            end if;
            write_long_byte(memory_access_address,memory_access_wdata);
          end if;
          if memory_access_read='1' then
            if memory_access_resolve_address = '1' then
              memory_access_address := resolve_address_to_long(memory_access_address(15 downto 0),false);
            end if;
            read_long_address(memory_access_address);
          end if;
        end if;                         -- if not in a wait state        
      end if;                           -- if not resetting
    end if;
  end process;

end Behavioural;
