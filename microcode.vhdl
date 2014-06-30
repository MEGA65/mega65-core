--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
--
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
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.cputypes.all;

--
entity microcode is
  port (Clk : in std_logic;
        address : in instruction;
        data_o : out microcodeops
        );
end microcode;

architecture Behavioral of microcode is
  
  type ram_t is array (instruction)
    of microcodeops;
  signal ram : ram_t := (
    I_ADC => (mcAluInA => '1', mcAluAdd => '1', mcAluOutA => '1',
              mcInstructionFetch => '1', others => '0'),
    I_AND => (mcIncInMem => '1', mcIncAnd => '1', mcIncOutA => '1',
              mcIncSetNZ => '1', others => '0'),
    I_ASL => (mcIncInMem => '1', mcIncShiftLeft => '1', mcIncOutMem => '1',
              mcIncCarryIn => '1', mcIncSetNZ => '1', mcWriteMem => '1',
              mcRMW => '1',
              others => '0'),
    I_ASR => (mcIncInMem => '1', mcIncShiftRight => '1', mcIncOutMem => '1',
              mcIncSetNZ => '1', mcWriteMem => '1',  mcRMW => '1',
              others => '0'),
    -- I_ASW
    -- I_BBR - handled elsewhere
    -- I_BBS - handled elsewhere
    -- I_BCC - handled elsewhere
    -- I_BCS - handled elsewhere
    -- I_BEQ - handled elsewhere
    -- I_BIT
    -- I_BMI - handled elsewhere
    -- I_BNE - handled elsewhere
    -- I_BPL - handled elsewhere
    -- I_BRA - handled elsewhere
    -- I_BRK
    I_BSR => (mcRelativeJump => '1', others => '0'),
    -- I_BVC - handled elsewhere
    -- I_BVS - handled elsewhere
    -- I_CLC - Handled as a single-cycle op elsewhere
    -- I_CLD - handled as a single-cycle op elsewhere
    I_CLE => (mcClearE => '1', mcInstructionFetch => '1', others => '0'),
    I_CLI => (mcClearI => '1', mcInstructionFetch => '1', others => '0'),
    -- I_CLV - handled as a single-cycle op elsewhere
    I_CMP => (mcAluInA => '1', mcAluCmp => '1',
              mcInstructionFetch => '1', others => '0'),    
    I_CPX => (mcAluInX => '1', mcAluCmp => '1',
              mcInstructionFetch => '1', others => '0'),    
    I_CPY => (mcAluInY => '1', mcAluCmp => '1',
              mcInstructionFetch => '1', others => '0'),    
    I_CPZ => (mcAluInZ => '1', mcAluCmp => '1',
              mcInstructionFetch => '1', others => '0'),    
    I_DEC => (mcIncInMem => '1', mcIncDec => '1', mcIncOutMem => '1',
              mcIncSetNZ => '1', mcWriteMem => '1', mcRMW => '1',
              others => '0'),
    -- I_DEW
    -- I_EOM - handled as a single-cycle op elsewhere
    I_EOR => (mcIncInMem => '1', mcIncEor => '1', mcIncOutA => '1',
              mcIncSetNZ => '1', others => '0'),
    I_INC => (mcIncInMem => '1', mcIncInc => '1', mcIncOutMem => '1',
              mcIncSetNZ => '1', mcWriteMem => '1', mcRMW => '1',
              others => '0'),
    -- I_INW
    -- I_INX - handled as a single-cycle op elsewhere
    -- I_INY - handled as a single-cycle op elsewhere
    -- I_INZ - handled as a single-cycle op elsewhere
    I_JMP => (mcJump => '1', others => '0'),
    I_JSR => (mcJump => '1', others => '0'),
    I_LSR => (mcIncInMem => '1', mcIncShiftRight => '1', mcIncOutMem => '1',
              mcIncZeroIn => '1', mcIncSetNZ => '1', mcWriteMem => '1',
              mcRMW => '1',
              others => '0'),
    I_LDA => (mcIncInMem => '1', mcIncPass => '1', mcIncOutA => '1',
              mcIncSetNZ => '1', others => '0'),
    I_LDX => (mcIncInMem => '1', mcIncPass => '1', mcIncOutX => '1',
              mcIncSetNZ => '1', others => '0'),
    I_LDY => (mcIncInMem => '1', mcIncPass => '1', mcIncOutY => '1',
              mcIncSetNZ => '1', others => '0'),
    I_LDZ => (mcIncInMem => '1', mcIncPass => '1', mcIncOutZ => '1',
              mcIncSetNZ => '1', others => '0'),
    -- I_LSR
    I_MAP => (mcMap => '1', others => '0'),
    I_NEG => (mcIncInA => '1', mcIncNeg => '1', mcIncOutA => '1',
              mcIncSetNZ => '1', others => '0'),
    I_ORA => (mcIncInMem => '1', mcIncIor => '1', mcIncOutA => '1',
              mcIncSetNZ => '1', others => '0'),
    I_PHA => (mcPush => '1', mcAluInA => '1', others => '0'),
    I_PHP => (mcPush => '1', mcAluInP => '1', others => '0'),
    I_PHX => (mcPush => '1', mcAluInX => '1', others => '0'),
    I_PHY => (mcPush => '1', mcAluInY => '1', others => '0'),
    I_PHZ => (mcPush => '1', mcAluInZ => '1', others => '0'),
    I_PLA => (mcPop => '1', mcStackA => '1', others => '0'),
    I_PLP => (mcPop => '1', mcStackP => '1', others => '0'),
    I_PLX => (mcPop => '1', mcStackX => '1', others => '0'),
    I_PLY => (mcPop => '1', mcStackY => '1', others => '0'),
    I_PLZ => (mcPop => '1', mcStackZ => '1', others => '0'),
    -- I_RMB
    -- I_ROL
    -- I_ROR
    -- I_ROW
    -- I_RTI - XXX in the process of being implemented
    -- I_RTS - XXX in the process of being implemented
    I_SBC => (mcAluInA => '1', mcAluSub => '1', mcAluOutA => '1',
              mcInstructionFetch => '1', others => '0'),
    -- I_SEC - handled as a single-cycle op elsewhere   
    -- I_SED - handled as a single-cycle op elsewhere   
    -- I_SEE - handled as a single-cycle op elsewhere   
    -- I_SEI - handled as a single-cycle op elsewhere   
    -- I_SMB
    I_STA => (mcIncInA => '1', mcIncPass => '1', mcIncOutMem => '1',
              mcWriteMem => '1', others => '0'),
    I_STX => (mcIncInX => '1', mcIncPass => '1', mcIncOutMem => '1',
              mcWriteMem => '1', others => '0'),
    I_STY => (mcIncInY => '1', mcIncPass => '1', mcIncOutMem => '1',
              mcWriteMem => '1', others => '0'),
    I_STZ => (mcIncInZ => '1', mcIncPass => '1', mcIncOutMem => '1',
              mcWriteMem => '1', others => '0'),
    -- I_TAX - handled as a single-cycle op elsewhere   
    -- I_TAY - handled as a single-cycle op elsewhere   
    -- I_TAZ - handled as a single-cycle op elsewhere   
    -- I_TBA - handled as a single-cycle op elsewhere   
    -- I_TRB
    -- I_TSB
    -- I_TSX - handled as a single-cycle op elsewhere   
    -- I_TSY - handled as a single-cycle op elsewhere   
    -- I_TXA - handled as a single-cycle op elsewhere   
    -- I_TXS - handled as a single-cycle op elsewhere   
    -- I_TYA - handled as a single-cycle op elsewhere   
    -- I_TYS - handled as a single-cycle op elsewhere   
    -- I_TZA - handled as a single-cycle op elsewhere   
    
    others => ( mcInstructionFetch => '1', others => '0'));

begin

--process for read and write operation.
  PROCESS(Clk,address)
  BEGIN
    if(rising_edge(Clk)) then 
      data_o <= ram(address);
    end if;
  END PROCESS;

end Behavioral;
