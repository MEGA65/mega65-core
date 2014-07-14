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
    I_ADC => (mcADC => '1', mcInstructionFetch => '1', others => '0'),
    -- I_AND
    -- I_ASL
    -- I_ASR
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
    -- I_CMP
    -- I_CPX
    -- I_CPY
    -- I_CPZ
    -- I_DEC
    -- I_DEW
    -- I_EOM - handled as a single-cycle op elsewhere
    -- I_EOR
    -- I_INC
    -- I_INW
    -- I_INX - handled as a single-cycle op elsewhere
    -- I_INY - handled as a single-cycle op elsewhere
    -- I_INZ - handled as a single-cycle op elsewhere
    I_JMP => (mcJump => '1', others => '0'),
    I_JSR => (mcJump => '1', others => '0'),
    -- I_LSR
    I_LDA => (mcSetA => '1', mcSetNZ => '1', mcIncPC => '1', 
              mcInstructionFetch => '1', others => '0'),
    I_LDX => (mcSetX => '1', mcSetNZ => '1', mcIncPC => '1', 
              mcInstructionFetch => '1', others => '0'),
    I_LDY => (mcSetY => '1', mcSetNZ => '1', mcIncPC => '1', 
              mcInstructionFetch => '1', others => '0'),
    I_LDZ => (mcSetZ => '1', mcSetNZ => '1', mcIncPC => '1', 
              mcInstructionFetch => '1', others => '0'),
    -- I_LSR
    I_MAP => (mcMap => '1', others => '0'),
    -- I_NEG - handled as a single-cycle op elsewhere
    -- I_ORA
    I_PHA => (mcPush => '1', mcStoreA => '1', others => '0'),
    I_PHP => (mcPush => '1', mcStoreP => '1', others => '0'),
    I_PHX => (mcPush => '1', mcStoreX => '1', others => '0'),
    I_PHY => (mcPush => '1', mcStoreY => '1', others => '0'),
    I_PHZ => (mcPush => '1', mcStoreZ => '1', others => '0'),
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
    I_SBC => (mcSBC => '1', mcInstructionFetch => '1', others => '0'),
    -- I_SEC - handled as a single-cycle op elsewhere   
    -- I_SED - handled as a single-cycle op elsewhere   
    -- I_SEE - handled as a single-cycle op elsewhere   
    -- I_SEI - handled as a single-cycle op elsewhere   
    -- I_SMB
    I_STA => (mcStoreA => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    I_STX => (mcStoreX => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    I_STY => (mcStoreY => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
    I_STZ => (mcStoreZ => '1', mcWriteMem => '1', mcInstructionFetch => '1', 
              mcWriteRegAddr => '1',mcIncPC => '1',  others => '0'),
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
    data_o <= ram(address);
  END PROCESS;

end Behavioral;
