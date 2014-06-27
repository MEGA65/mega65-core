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

  constant mcStoreArg1 : integer := 0;
  constant mcReadFromPC : integer := 1;
  constant mcReadZPfast : integer := 2;
  constant mcReadZP : integer := 3;
  constant mcReadAbs : integer := 4;
  constant mcIncPC : integer := 5;
  constant mcIncInA : integer := 6;
  constant mcIncInX : integer := 7;
  constant mcIncInY : integer := 8;
  constant mcIncInZ : integer := 9;
  constant mcIncInSPH : integer := 10;
  constant mcIncInSPL : integer := 11;
  constant mcIncOutA : integer := 12;
  constant mcIncOutX : integer := 13;
  constant mcIncOutY : integer := 14;
  constant mcIncOutZ : integer := 15;
  constant mcIncOutT : integer := 16;
  constant mcIncOutSPH : integer := 17;
  constant mcIncOutSPL : integer := 18;
  constant mcIncInc : integer := 19;
  constant mcIncDec : integer := 20;
  constant mcIncShiftLeft : integer := 21;
  constant mcIncShiftRight : integer := 22;
  constant mcIncZeroIn : integer := 23;
  constant mcIncCarryIn : integer := 24;
  constant mcIncSetNZ : integer := 25;
  constant mcMap : integer := 26;
  constant mcInstructionFetch : integer := 27;
  constant mcInstructionDecode : integer := 28;
  constant mcSetFlagI : integer := 29;
  constant mcWriteP : integer := 30;
  constant mcWritePCL : integer := 31;
  constant mcWritePCH : integer := 32;
  constant mcWriteABS : integer := 33;
  constant mcWriteZP : integer := 34;
  constant mcWriteStack : integer := 35;
  constant mcWriteMem : integer := 36;
  constant mcDecSP : integer := 37;
  constant mcIncSP : integer := 38;
  constant mcBreakFlag : integer := 39;  
  constant mcVectorIRQ : integer := 40;
  constant mcVectorNMI : integer := 41;
  constant mcLoadVector : integer := 42;
  constant mcIncInT : integer := 43;
  constant mcStoreArg2 : integer := 44;
  constant mcDeclareArg1 : integer := 45;
  constant mcDeclareArg2 : integer := 46;
  constant mcIncInMem : integer := 47;
  constant mcIncOutMem : integer := 48;
  constant mcIncAnd : integer := 49;
  constant mcIncIor : integer := 50;
  constant mcIncEor : integer := 51;
  constant mcAluOutA : integer := 52;
  constant mcAluCarryOut : integer := 53;

end cputypes;

package body cputypes is


end cputypes;
