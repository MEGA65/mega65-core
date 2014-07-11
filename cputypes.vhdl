library ieee;
use Std.TextIO.all;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package cputypes is

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
    I_TYA,I_TYS,I_TZA);

  type ilut8bit is array(0 to 255) of instruction;

  type microcodeops is record
    -- Do we increment PC?
    mcIncPC : std_logic;

    -- How shall we exit this instruction?
    mcInstructionFetch : std_logic;
    mcInstructionDecode : std_logic;

    -- Mark instruction RMW
    mcRMW : std_logic;

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
    
    mcWriteMem : std_logic;
    mcWriteRegAddr : std_logic;
    mcPush : std_logic;
    mcPop : std_logic;
    mcBreakFlag : std_logic;
    
    -- Special instructions
    mcJump : std_logic;
    mcRelativeJump : std_logic;
    mcMap : std_logic;
    mcClearI : std_logic;
    mcClearE : std_logic;

    mcStackA : std_logic;
    mcStackP : std_logic;
    mcStackX : std_logic;
    mcStackY : std_logic;
    mcStackZ : std_logic;
    
  end record;

end cputypes;

package body cputypes is


end cputypes;
