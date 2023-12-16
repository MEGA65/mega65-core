library ieee;
use Std.TextIO.all;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package cputypes is

  type mega65_target_t is (
    simulation,
    mega65r1, mega65r2, mega65r3, mega65r4, mega65r5, mega65r6, mega65r7,
    mega65r8, mega65r9, mega65r10,mega65r11,mega65r12,mega65r13,mega65r14,
    megaphoner1, megaphoner4,
    nexys4, nexys4ddr, nexys4ddr_widget,
    qmtecha100t, qmtecha200t, qmtechk325t,
    wukong
    );
  
  type sample_vector_t is array(0 to 15) of signed(15 downto 0);
  type dc_level_vector_t is array(0 to 7) of signed(19 downto 0);
  type sprite_vector_8 is array(0 to 7) of unsigned(7 downto 0);
  
  type addressingmode is (
    M_impl,M_InnX,M_nn,M_immnn,M_A,M_nnnn,M_nnrr,
    M_rr,M_InnY,M_InnZ,M_rrrr,M_nnX,M_nnnnY,M_nnnnX,M_Innnn,
    M_InnnnX,M_InnSPY,M_nnY,M_immnnnn);

  type mode_list is array(addressingmode'low to addressingmode'high) of integer;
  
  type instruction is (
    -- 4510 opcodes
    I_ADC,I_AND,I_ASL,I_ASR,I_ASW,I_BBR,I_BBS,I_BCC,
    I_BCS,I_BEQ,I_BIT,I_BMI,I_BNE,I_BPL,I_BRA,I_BRK,
    I_BSR,I_BVC,I_BVS,I_CLC,I_CLD,I_CLE,I_CLI,I_CLV,
    I_CMP,I_CPX,I_CPY,I_CPZ,I_DEC,I_DEW,I_DEX,I_DEY,    
    I_DEZ,I_EOM,I_EOR,I_INC,I_INW,I_INX,I_INY,I_INZ,    
    I_JMP,I_JSR,I_LDA,I_LDX,I_LDY,I_LDZ,I_LSR,I_MAP,
    I_NEG,I_ORA,I_PHA,I_PHP,I_PHW,I_PHX,I_PHY,I_PHZ,
    I_PLA,I_PLP,I_PLX,I_PLY,I_PLZ,I_RMB,I_ROL,I_ROR,
    I_ROW,I_RTI,I_RTS,I_SBC,I_SEC,I_SED,I_SEE,I_SEI,    
    I_SMB,I_STA,I_STX,I_STY,I_STZ,I_TAB,I_TAX,I_TAY,
    I_TAZ,I_TBA,I_TRB,I_TSB,I_TSX,I_TSY,I_TXA,I_TXS,
    I_TYA,I_TYS,I_TZA,

    -- 6502 illegals
    I_SLO,I_RLA,I_SRE,I_RRA,I_SAX,I_LAX,I_DCP,I_ISC,
    I_ANC,I_ALR,I_ARR,I_XAA,I_AXS,I_AHX,I_SHY,I_SHX,
    I_TAS,I_LAS,I_NOP,I_KIL
    
    );

  type ilut9bit is array(0 to 511) of instruction;
  type ilut8bit is array(0 to 255) of instruction;
    
  
  type microcodeops is record
    -- Do we increment PC?
    mcIncPC : std_logic;

    -- Decrement PC (to fix PC following stack operations)
    mcDecPC : std_logic;

    -- How shall we exit this instruction?
    mcInstructionFetch : std_logic;
    mcInstructionDecode : std_logic;

    -- Mark instruction RMW
    mcRMW : std_logic;
    -- 16bit operations
    mcWordOp : std_logic;

    mcBRK : std_logic;
    
    -- Set NZ based on currently read memory
    mcSetNZ : std_logic;
    -- And registers
    mcSetA : std_logic;
    mcSetX : std_logic;
    mcSetY : std_logic;
    mcSetZ : std_logic;

    -- Do we write registers to memory?
    mcStoreA : std_logic;
    mcStoreP : std_logic;
    mcStoreX : std_logic;
    mcStoreY : std_logic;
    mcStoreZ : std_logic;
    mcStoreTRB : std_logic;
    mcStoreTSB : std_logic;

    mcTestAZ : std_logic;

    mcDelayedWrite : std_logic;
    mcWriteMem : std_logic;
    mcWriteRegAddr : std_logic;
    mcPop : std_logic;
    mcBreakFlag : std_logic;
    
    -- Special instructions
    mcJump : std_logic;
    mcMap : std_logic;
    mcClearI : std_logic;
    mcClearE : std_logic;

    mcStackA : std_logic;
    mcStackP : std_logic;
    mcStackX : std_logic;
    mcStackY : std_logic;
    mcStackZ : std_logic;

    mcADC : std_logic;
    mcAND : std_logic;
    mcORA : std_logic;
    mcEOR : std_logic;
    mcASL : std_logic;
    mcASR : std_logic;
    mcLSR : std_logic;
    mcBIT : std_logic;
    mcSBC : std_logic;
    mcCMP : std_logic;
    mcCPX : std_logic;
    mcCPY : std_logic;
    mcCPZ : std_logic;
    mcDEC : std_logic;
    mcINC : std_logic;
    mcROL : std_logic;
    mcROR : std_logic;
    mcRMB : std_logic;
    mcSMB : std_logic;
    
  end record;

  type microcoderom_t is array (instruction) of microcodeops;

  -- Used for HyperRAM cache
  type cache_row_t is array (0 to 7) of unsigned(7 downto 0);
  
end cputypes;
