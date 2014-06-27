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

  type microcodeops is record
    mcIncPC : std_logic;

    -- Incrementer/binary ALU inputs
    mcIncInT : std_logic;
    mcIncInA : std_logic;mcIncInX : std_logic;
    mcIncInY : std_logic;mcIncInZ : std_logic;
    mcIncInSPH : std_logic;mcIncInSPL : std_logic;
    mcIncInMem : std_logic;

    -- Incrementer/binary ALU outputs
    mcIncOutMem : std_logic;
    mcIncOutA : std_logic;mcIncOutX : std_logic;
    mcIncOutY : std_logic;mcIncOutZ : std_logic;
    mcIncOutT : std_logic;
    mcIncOutSPH : std_logic;mcIncOutSPL : std_logic;

    -- Binary and index operations
    mcIncAnd : std_logic;mcIncIor : std_logic;mcIncEor : std_logic;
    mcIncInc : std_logic;mcIncDec : std_logic;mcIncPass : std_logic;
    mcIncNeg : std_logic;
    -- Bit shift operations
    mcIncShiftLeft : std_logic;mcIncShiftRight : std_logic;
    mcIncZeroIn : std_logic;mcIncCarryIn : std_logic;

    mcIncSetNZ : std_logic;

    -- How shall we exit this instruction?
    mcInstructionFetch : std_logic;
    mcInstructionDecode : std_logic;

    mcWriteStack : std_logic;
    mcWriteMem : std_logic;
    mcDecSP : std_logic;
    mcIncSP : std_logic;
    mcDeclareArg1 : std_logic;
    mcDeclareArg2 : std_logic;

    -- Arithmetic ALU operations
    mcAluOutA : std_logic;
    mcAluCarryOut : std_logic;
    
    -- Special instructions
    mcJump : std_logic;
    mcMap : std_logic;
    mcSetFlagI : std_logic;

  end record;

end cputypes;

package body cputypes is


end cputypes;
