use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity cpu6502 is
 port (
   Clock : in std_logic;
   reset : in std_logic;
   irq : in std_logic;
   nmi : in std_logic;
	monitor_pc : out std_logic_vector(15 downto 0));
  
end cpu6502;

architecture Behavioral of cpu6502 is

-- 512KB RAM as 64K x 64bit
-- The wide databus allows us to read entire instructions in one go,
-- and potentially to write operands to memory while fetching the next
-- instruction if the lower 3 bits don't conflict
type unsigned_array_8 is array(0 to 7) of std_logic_vector(15 downto 0);
type stdlogic_array_8 is array (natural range <>) of std_logic_vector(7 downto 0);
signal ram_address : unsigned_array_8;
signal ram_we : std_logic_vector(0 to 7);
signal ram_data_i : stdlogic_array_8(0 to 7);
signal ram_data_o : stdlogic_array_8(0 to 7);

-- CPU RAM bank selection registers.
-- Each 4KB (12 address bits) can be made to point to a section of memory.
-- Sections have 16bit addresses, for a total of 28bits (256MB) of address
-- space.  It also makes it possible to multiple 4KB banks point to the same
-- block of RAM.
type bank_register_set is array (0 to 15) of std_logic_vector(15 downto 0);
signal ram_bank_registers : bank_register_set;

-- CPU internal state
signal flag_c : std_logic;        -- carry flag
signal flag_z : std_logic;        -- zero flag
signal flag_d : std_logic;        -- decimal mode flag
signal flag_n : std_logic;        -- negative flag
signal flag_v : std_logic;        -- positive flag
signal flag_i : std_logic;        -- interrupt disable flag

signal reg_a : unsigned(7 downto 0);
signal reg_x : unsigned(7 downto 0);
signal reg_y : unsigned(7 downto 0);
signal reg_sp : unsigned(7 downto 0);
signal reg_pc : unsigned(15 downto 0);
-- We also keep copies of the program counter+1 and +2 for reading instruction
-- plus operands in in parallel
signal reg_pcplus1 : unsigned(15 downto 0);
signal reg_pcplus2 : unsigned(15 downto 0);

-- Temporary address used in various states
signal temp_addr : std_logic_vector(15 downto 0);
signal temp_opcode : std_logic_vector(7 downto 0);
signal temp_operand : std_logic_vector(15 downto 0);
-- Other temporary variables
signal op_mem_slot : unsigned(2 downto 0);
signal operand1_mem_slot : unsigned(2 downto 0);
signal operand2_mem_slot : unsigned(2 downto 0);
signal vector : std_logic_vector(15 downto 0);

type processor_state is (
  -- When CPU first powers up, or reset is bought low
  ResetLow,
  -- States for handling interrupts and reset
  VectorPushPC,VectorPushP,VectorRead,VectorLoadPC,
  -- Normal instruction states.  Many states will be skipped
  -- by any given instruction.
  -- When an instruction completes, we move back to InstructionFetch
  InstructionFetch,OperandResolve,MemoryRead,
  Calculate,MemoryWrite,
  -- Special states used for special instructions
  PushP,PushA,PushPC,PushPCPlusOne,
  PullP,PullA,PullPC,TakeBranch);
signal state : processor_state := ResetLow;  -- start processor in reset state

type instruction is (
I_ADC,I_AHX,I_ALR,I_ANC,I_AND,I_ARR,I_ASL,I_AXS,
I_BCC,I_BCS,I_BEQ,I_BIT,I_BMI,I_BNE,I_BPL,I_BRK,
I_BVC,I_BVS,I_CLC,I_CLD,I_CLI,I_CLV,I_CMP,I_CPX,
I_CPY,I_DCP,I_DEC,I_DEX,I_DEY,I_EOR,I_INC,I_INX,
I_INY,I_ISC,I_JMP,I_JSR,I_KIL,I_LAS,I_LAX,I_LDA,
I_LDX,I_LDY,I_LSR,I_NOP,I_ORA,I_PHA,I_PHP,I_PLA,
I_PLP,I_RLA,I_ROL,I_ROR,I_RRA,I_RTI,I_RTS,I_SAX,
I_SBC,I_SEC,I_SED,I_SEI,I_SHX,I_SHY,I_SLO,I_SRE,
I_STA,I_STX,I_STY,I_TAS,I_TAX,I_TAY,I_TSX,I_TXA,
I_TXS,I_TYA,I_XAA);
signal op_instruction : instruction;

type ilut8bit is array(0 to 255) of instruction;
constant instruction_lut : ilut8bit := (
I_BRK,  I_ORA,  I_KIL,  I_SLO,  I_NOP,  I_ORA,  I_ASL,  I_SLO,  I_PHP,  I_ORA,  I_ASL,  I_ANC,  I_NOP,  I_ORA,  I_ASL,  I_SLO, 
I_BPL,  I_ORA,  I_KIL,  I_SLO,  I_NOP,  I_ORA,  I_ASL,  I_SLO,  I_CLC,  I_ORA,  I_NOP,  I_SLO,  I_NOP,  I_ORA,  I_ASL,  I_SLO, 
I_JSR,  I_AND,  I_KIL,  I_RLA,  I_BIT,  I_AND,  I_ROL,  I_RLA,  I_PLP,  I_AND,  I_ROL,  I_ANC,  I_BIT,  I_AND,  I_ROL,  I_RLA, 
I_BMI,  I_AND,  I_KIL,  I_RLA,  I_NOP,  I_AND,  I_ROL,  I_RLA,  I_SEC,  I_AND,  I_NOP,  I_RLA,  I_NOP,  I_AND,  I_ROL,  I_RLA, 
I_RTI,  I_EOR,  I_KIL,  I_SRE,  I_NOP,  I_EOR,  I_LSR,  I_SRE,  I_PHA,  I_EOR,  I_LSR,  I_ALR,  I_JMP,  I_EOR,  I_LSR,  I_SRE, 
I_BVC,  I_EOR,  I_KIL,  I_SRE,  I_NOP,  I_EOR,  I_LSR,  I_SRE,  I_CLI,  I_EOR,  I_NOP,  I_SRE,  I_NOP,  I_EOR,  I_LSR,  I_SRE, 
I_RTS,  I_ADC,  I_KIL,  I_RRA,  I_NOP,  I_ADC,  I_ROR,  I_RRA,  I_PLA,  I_ADC,  I_ROR,  I_ARR,  I_JMP,  I_ADC,  I_ROR,  I_RRA, 
I_BVS,  I_ADC,  I_KIL,  I_RRA,  I_NOP,  I_ADC,  I_ROR,  I_RRA,  I_SEI,  I_ADC,  I_NOP,  I_RRA,  I_NOP,  I_ADC,  I_ROR,  I_RRA, 
I_NOP,  I_STA,  I_KIL,  I_SAX,  I_STY,  I_STA,  I_STX,  I_SAX,  I_DEY,  I_NOP,  I_TXA,  I_XAA,  I_STY,  I_STA,  I_STX,  I_SAX, 
I_BCC,  I_STA,  I_NOP,  I_AHX,  I_STY,  I_STA,  I_STX,  I_SAX,  I_TYA,  I_STA,  I_TXS,  I_TAS,  I_SHY,  I_STA,  I_SHX,  I_AHX, 
I_LDY,  I_LDA,  I_LDX,  I_LAX,  I_LDY,  I_LDA,  I_LDX,  I_LAX,  I_TAY,  I_LDA,  I_TAX,  I_LAX,  I_LDY,  I_LDA,  I_LDX,  I_LAX, 
I_BCS,  I_LDA,  I_NOP,  I_LAX,  I_LDY,  I_LDA,  I_LDX,  I_LAX,  I_CLV,  I_LDA,  I_TSX,  I_LAS,  I_LDY,  I_LDA,  I_LDX,  I_LAX, 
I_CPY,  I_CMP,  I_KIL,  I_DCP,  I_CPY,  I_CMP,  I_DEC,  I_DCP,  I_INY,  I_CMP,  I_DEX,  I_AXS,  I_CPY,  I_CMP,  I_DEC,  I_DCP, 
I_BNE,  I_CMP,  I_NOP,  I_DCP,  I_NOP,  I_CMP,  I_DEC,  I_DCP,  I_CLD,  I_CMP,  I_NOP,  I_DCP,  I_NOP,  I_CMP,  I_DEC,  I_DCP, 
I_CPX,  I_SBC,  I_KIL,  I_ISC,  I_CPX,  I_SBC,  I_INC,  I_ISC,  I_INX,  I_SBC,  I_NOP,  I_SBC,  I_CPX,  I_SBC,  I_INC,  I_ISC, 
I_BEQ,  I_SBC,  I_NOP,  I_ISC,  I_NOP,  I_SBC,  I_INC,  I_ISC,  I_SED,  I_SBC,  I_NOP,  I_ISC,  I_NOP,  I_SBC,  I_INC,  I_ISC);

type addressingmode is (
M_implied,M_immidiate,M_accumulator,
M_zeropage,M_zeropageX,M_zeropageY,
M_absolute,M_absoluteY,M_absoluteX,
M_relative,M_indirect,M_indirectX,M_indirectY);
signal op_mode : addressingmode;

type mlut8bit is array(0 to 255) of addressingmode;
constant mode_lut : mlut8bit := (
M_implied,  M_indirectX,  M_immidiate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
M_implied,  M_immidiate,  M_accumulator,  M_immidiate,  M_absolute,  M_absolute,  M_absolute,  M_absolute, 
M_relative,  M_indirectY,  M_immidiate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
M_implied,  M_absoluteY,  M_accumulator,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX, 
M_absolute,  M_indirectX,  M_immidiate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
M_implied,  M_immidiate,  M_accumulator,  M_immidiate,  M_absolute,  M_absolute,  M_absolute,  M_absolute, 
M_relative,  M_indirectY,  M_immidiate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
M_implied,  M_absoluteY,  M_accumulator,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX, 
M_implied,  M_indirectX,  M_immidiate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
M_implied,  M_immidiate,  M_accumulator,  M_immidiate,  M_absolute,  M_absolute,  M_absolute,  M_absolute, 
M_relative,  M_indirectY,  M_immidiate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
M_implied,  M_absoluteY,  M_accumulator,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX, 
M_implied,  M_indirectX,  M_immidiate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
M_implied,  M_immidiate,  M_accumulator,  M_immidiate,  M_indirect,  M_absolute,  M_absolute,  M_absolute, 
M_relative,  M_indirectY,  M_immidiate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
M_implied,  M_absoluteY,  M_accumulator,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX, 
M_immidiate,  M_indirectX,  M_immidiate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
M_implied,  M_immidiate,  M_implied,  M_immidiate,  M_absolute,  M_absolute,  M_absolute,  M_absolute, 
M_relative,  M_indirectY,  M_immidiate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageY,  M_zeropageY, 
M_implied,  M_absoluteY,  M_implied,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_implied,  M_absoluteY, 
M_immidiate,  M_indirectX,  M_immidiate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
M_implied,  M_immidiate,  M_implied,  M_immidiate,  M_absolute,  M_absolute,  M_absolute,  M_absolute, 
M_relative,  M_indirectY,  M_immidiate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageY,  M_zeropageY, 
M_implied,  M_absoluteY,  M_implied,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteY,  M_absoluteY, 
M_immidiate,  M_indirectX,  M_immidiate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
M_implied,  M_immidiate,  M_implied,  M_immidiate,  M_absolute,  M_absolute,  M_absolute,  M_absolute, 
M_relative,  M_indirectY,  M_immidiate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
M_implied,  M_absoluteY,  M_implied,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX, 
M_immidiate,  M_indirectX,  M_immidiate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
M_implied,  M_immidiate,  M_implied,  M_immidiate,  M_absolute,  M_absolute,  M_absolute,  M_absolute, 
M_relative,  M_indirectY,  M_immidiate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
M_implied,  M_absoluteY,  M_implied,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX);

begin
  -- Each block portram is 64KBx8bits, so we need 8 of them
  -- to make 512KB, approximately the total available on this FPGA.
  gen_ram: for i in 0 to 7 generate
    ramx: entity spartan6blockram
    port map (
      Clk   => clock,
      address => ram_address(i),
      we      => ram_we(i),
      data_i  => ram_data_i(i),
      data_o  => ram_data_o(i));
  end generate;

  process(clock)
      variable operand_is_from_ram : boolean;
      variable temp_address : std_logic_vector(15 downto 0);
      variable temp_bank_block : std_logic_vector(15 downto 0);
    begin
      if rising_edge(clock) then
		  monitor_pc <= std_logic_vector(reg_pc);
        report "tick" severity note;
        if reset = '0' or state = ResetLow then
          state <= VectorRead;
          vector <= x"FFFC";
          -- reset cpu
          reg_a <= x"00";
          reg_x <= x"00";
          reg_y <= x"00";
          reg_sp <= x"ff";
          flag_c <= '0';
          flag_d <= '0';
          flag_i <= '1';                -- start with IRQ disabled
          flag_z <= '0';
          flag_n <= '0';
          flag_v <= '0';
          -- Read nothingness from RAM
          for i  in 0 to 7 loop
            ram_address(i)<="0000000000000000";
            ram_we(i) <= '0';
          end loop;  -- i
          -- Reset memory bank to first 64KB
          -- bank at 0x0000-0x0FFF points to 0x0000000-0x0000FFF = block 0x0000
          -- bank at 0x1000-0x1FFF points to 0x0001000-0x0001FFF = block 0x0001
          -- and so on.          
          for i in 0 to 15 loop
            ram_bank_registers(i)<=std_logic_vector(to_unsigned(i,16));
          end loop;  -- i
        else
          -- act based on state
          case state is
            when VectorRead =>
              report "state=VectorRead" severity note;
              -- Read PC from vector,vector+1
              -- Reading memory is a bit interesting because we have
              -- to work out which of the 32 memories to read from
              -- However, since we only support the CPU vectors from FFFA-FFFF
              -- we can do this fairly easily by setting all six relevant
              -- memories to read their last cell, and then pick the right one
              -- out in processor_state'VectorLoadPC
              -- The vectors always live in the natural memory locations
              -- 0x000FFFA - 0x000FFF, and ignore bank switching
              for i in 0 to 7 loop
                ram_we(i) <= '0';
              end loop;  -- i
              -- Memory banks are 8x64KB.
              -- So we want addresses shifted down log2(8)=3 bits
              -- which for all of them corresponds to addres 0x1FFF
              for i in 2 to 7 loop
                ram_address(i)<=x"1FFF";
              end loop;  -- i              
              state<=VectorLoadPC;
            when VectorLoadPC =>
                case vector is
                  when x"FFFA" =>
                    temp_addr(7 downto 0) <=  ram_data_o(2);
                    temp_addr(15 downto 8) <= ram_data_o(3);
                  when x"FFFC" =>
                    temp_addr(7 downto 0) <=  ram_data_o(4);
                    temp_addr(15 downto 8) <= ram_data_o(5);
                  when x"FFFE" =>
                    temp_addr(7 downto 0) <=  ram_data_o(6);
                    temp_addr(15 downto 8) <= ram_data_o(7);
                  when others =>
                    -- unknown vector, so use reset vector
                    temp_addr(7 downto 0) <=  ram_data_o(6);
                    temp_addr(15 downto 8) <= ram_data_o(7);
                end case;
                reg_pc<=unsigned(temp_addr);
                reg_pcplus1<=unsigned(temp_addr)+1;
                reg_pcplus2<=unsigned(temp_addr)+2;
                -- We have loaded the program counter (and operand addresses
                -- derived from that), so now we can proceed to instruction fetch.
                -- (XXX We could save one cycle for every interrupt here by doing
                -- the instruction fetch here, and then passing into OperandResolve
                -- next cycle.
                state<=InstructionFetch;
            when InstructionFetch =>
                -- Work out which three bytes to fetch.
                -- Probably easiest to do a parallel calculation based on lower
                -- bits of reg_pc, reg_pcplus1, reg_pcplus2
                for i in 0 to 7 loop
                  ram_we(i)<='0';
                  if reg_pc(2 downto 0)=i then
                    temp_bank_block :=ram_bank_registers(to_integer(unsigned(reg_pc(15 downto 12))));
                    temp_address(15 downto 13 ):=temp_bank_block(2 downto 0);
                    temp_address(12 downto 0):=std_logic_vector(reg_pc(15 downto 3));
                    ram_address(i) <= temp_address;
                    op_mem_slot<=to_unsigned(i,3);
                  elsif reg_pcplus1(2 downto 0)=i then
                    temp_bank_block :=ram_bank_registers(to_integer(unsigned(reg_pcplus1(15 downto 12))));
                    temp_address(15 downto 13 ):=temp_bank_block(2 downto 0);
                    temp_address(12 downto 0):=std_logic_vector(reg_pcplus1(15 downto 3));
                    ram_address(i) <= temp_address;
                    operand1_mem_slot<=to_unsigned(i,3);
                  elsif reg_pcplus2(2 downto 0)=i then
                    temp_bank_block :=ram_bank_registers(to_integer(unsigned(reg_pcplus2(15 downto 12))));
                    temp_address(15 downto 13 ):=temp_bank_block(2 downto 0);
                    temp_address(12 downto 0):=std_logic_vector(reg_pcplus2(15 downto 3));
                    ram_address(i) <= temp_address;
                    operand2_mem_slot<=to_unsigned(i,3);
                  end if;
                end loop;  -- i
                state<=OperandResolve;
            when OperandResolve =>
              -- Get opcode and operands
              temp_opcode <= ram_data_o(to_integer(op_mem_slot));
              temp_operand(15 downto 8) <= ram_data_o(to_integer(operand2_mem_slot));
              temp_operand(7 downto 0) <= ram_data_o(to_integer(operand1_mem_slot));

              -- Lookup instruction and addressing mode
              op_instruction <= instruction_lut(to_integer(unsigned(temp_opcode)));
              op_mode <= mode_lut(to_integer(unsigned(temp_opcode)));

              if op_mode=M_implied then
                -- implied mode, handle instruction now, add one to PC, and
                -- go to fetch next instruction
                operand_is_from_ram := false;
              elsif op_mode=M_accumulator then
                -- accumulator mode, so no need to read from memory
                operand_is_from_ram := false;
              elsif op_mode=M_relative then
                -- a relative branch, work out whether to take the branch
                -- and act accordingly
                if (op_instruction=I_BCC and flag_c='0')
                   or (op_instruction=I_BCS and flag_c='1')
                   or (op_instruction=I_BVC and flag_v='0')
                   or (op_instruction=I_BVS and flag_v='1')
                   or (op_instruction=I_BEQ and flag_z='0')
                   or (op_instruction=I_BNE and flag_z='1') then
                  -- take branch
                  if temp_operand(7)='0' then
                    -- branch forwards. Add two to address because this is a two
                    -- byte instruction
                    reg_pc <= reg_pcplus2 + unsigned(temp_operand(6 downto 0));
                  else
                    -- branch backwards.
                    reg_pc <= reg_pcplus2 - 128 + unsigned(not temp_operand(6 downto 0));
                  end if;
                  reg_pcplus1 <= reg_pc + 1;
                  reg_pcplus2 <= reg_pc + 2;
                else
                  -- don't take branch, just advance program counter
                  reg_pc <= reg_pc + 2;
                  reg_pcplus1 <= reg_pc + 3;
                  reg_pcplus2 <= reg_pc + 4;
                end if;
                state <= InstructionFetch;
                operand_is_from_ram := false;
              elsif op_mode=M_zeropage then
                temp_addr(7 downto 0) <= temp_operand(7 downto 0);
                temp_addr(15 downto 8) <= "00000000";
                operand_is_from_ram := true;
              elsif op_mode=M_zeropageX then
                temp_addr(7 downto 0) <= std_logic_vector(unsigned(temp_operand(7 downto 0)) + unsigned(reg_x));
                temp_addr(15 downto 8) <= "00000000";
                operand_is_from_ram := true;
              elsif op_mode=M_zeropageY then
                temp_addr(7 downto 0) <= std_logic_vector(unsigned(temp_operand(7 downto 0)) + unsigned(reg_y));
                temp_addr(15 downto 8) <= "00000000";
                operand_is_from_ram := true;
              elsif op_mode=M_absolute then
                temp_addr(15 downto 0) <= temp_operand;
              elsif op_mode=M_absoluteX then
                temp_addr(15 downto 0) <= std_logic_vector(unsigned(temp_operand) + unsigned(reg_x));
              elsif op_mode=M_absoluteY then
                temp_addr(15 downto 0) <= std_logic_vector(unsigned(temp_operand) + unsigned(reg_y));
                operand_is_from_ram := true;
              end if;
              
            when others => null;
          end case;
        end if;
      end if;
    end process;
end Behavioral;
