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
type unsigned_array_32 is array(0 to 31) of std_logic_vector(10 downto 0);
type stdlogic_array_8 is array (natural range <>) of std_logic_vector(7 downto 0);
signal ram_address : unsigned_array_32;
signal ram_we : std_logic_vector(0 to 31);
signal ram_data_i : stdlogic_array_8(0 to 31);
signal ram_data_o : stdlogic_array_8(0 to 31);

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
signal op_mem_slot : unsigned(4 downto 0);
signal operand1_mem_slot : unsigned(4 downto 0);
signal operand2_mem_slot : unsigned(4 downto 0);
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

type addressing_mode is (
  Relative,Accumulator,Implied,Immediate,
  ZeroPage,ZeroPageX,ZeroPageY,IZeroPageX,IZeroPageY,
  Absolute,AbsoluteX,AbsoluteY,Indirect);
signal op_mode : addressing_mode;
type instruction is (
  I_ADC,I_AND,I_ASL,
  I_BCC,I_BCS,I_BNE,I_BEQ,I_BMI,I_BPL,I_BVC,I_BVS,
  I_BIT,I_BRK,I_CLC,I_CLD,I_CLI,I_CLV,
  I_CMP,I_CPX,I_CPY,I_DEC,I_DEX,I_DEY,I_EOR,I_INC,I_INX,I_INY,
  I_JMP,I_JSR,I_LDA,I_LDX,I_LDY,I_LSR,I_NOP,I_ORA,I_PHA,I_PHP,
  I_PLA,I_PLP,I_ROL,I_ROR,I_RTI,I_RTS,I_SBC,I_SEC,I_SED,I_SEI,
  I_STA,I_STX,I_STY,I_TAX,I_TAY,I_TSX,I_TXA,I_TXS,I_TYA,
  I_ILL
  );
type lut8bit is array(0 to 255) of instruction;
constant instruction_lut : lut8bit := (
I_BRK,  I_ORA,  I_ILL,  I_ILL,  I_ILL,  I_ORA,  I_ASL,  I_ILL, 
I_PHP,  I_ORA,  I_ASL,  I_ILL,  I_ILL,  I_ORA,  I_ASL,  I_ILL, 
I_BPL,  I_ORA,  I_ILL,  I_ILL,  I_ILL,  I_ORA,  I_ASL,  I_ILL, 
I_CLC,  I_ORA,  I_ILL,  I_ILL,  I_ILL,  I_ORA,  I_ASL,  I_ILL, 
I_JSR,  I_AND,  I_ILL,  I_ILL,  I_BIT,  I_AND,  I_ROL,  I_ILL, 
I_ILL,  I_AND,  I_ROL,  I_ILL,  I_BIT,  I_AND,  I_ROL,  I_ILL, 
I_BMI,  I_AND,  I_ILL,  I_ILL,  I_ILL,  I_AND,  I_ROL,  I_ILL, 
I_SEC,  I_AND,  I_ILL,  I_ILL,  I_ILL,  I_AND,  I_ROL,  I_ILL, 
I_RTI,  I_EOR,  I_ILL,  I_ILL,  I_ILL,  I_EOR,  I_LSR,  I_ILL, 
I_PHA,  I_EOR,  I_LSR,  I_ILL,  I_JMP,  I_EOR,  I_LSR,  I_ILL, 
I_BVC,  I_EOR,  I_ILL,  I_ILL,  I_ILL,  I_EOR,  I_LSR,  I_ILL, 
I_CLI,  I_EOR,  I_ILL,  I_ILL,  I_ILL,  I_EOR,  I_LSR,  I_ILL, 
I_RTS,  I_ADC,  I_ILL,  I_ILL,  I_ILL,  I_ADC,  I_ROR,  I_ILL, 
I_PLA,  I_ADC,  I_ROR,  I_ILL,  I_JMP,  I_ADC,  I_ROR,  I_ILL, 
I_ILL,  I_ADC,  I_ILL,  I_ILL,  I_ILL,  I_ADC,  I_ROR,  I_ILL, 
I_SEI,  I_ADC,  I_ILL,  I_ILL,  I_ILL,  I_ADC,  I_ROR,  I_ILL, 
I_ILL,  I_STA,  I_ILL,  I_ILL,  I_STY,  I_STA,  I_STX,  I_ILL, 
I_ILL,  I_ILL,  I_TXA,  I_ILL,  I_STY,  I_STA,  I_STX,  I_ILL, 
I_BCC,  I_STA,  I_ILL,  I_ILL,  I_STY,  I_STA,  I_STX,  I_ILL, 
I_TYA,  I_STA,  I_TXS,  I_ILL,  I_ILL,  I_STA,  I_ILL,  I_ILL, 
I_LDY,  I_LDA,  I_LDX,  I_ILL,  I_LDY,  I_LDA,  I_LDX,  I_ILL, 
I_TAY,  I_LDA,  I_TAX,  I_ILL,  I_LDY,  I_LDA,  I_LDX,  I_ILL, 
I_BCS,  I_LDA,  I_ILL,  I_ILL,  I_LDY,  I_LDA,  I_LDX,  I_ILL, 
I_CLV,  I_LDA,  I_TSX,  I_ILL,  I_LDY,  I_LDA,  I_LDX,  I_ILL, 
I_CPY,  I_CMP,  I_ILL,  I_ILL,  I_CPY,  I_CMP,  I_DEC,  I_ILL, 
I_INY,  I_CMP,  I_ILL,  I_ILL,  I_CPY,  I_CMP,  I_DEC,  I_ILL, 
I_BNE,  I_CMP,  I_ILL,  I_ILL,  I_ILL,  I_CMP,  I_DEC,  I_ILL, 
I_CLD,  I_CMP,  I_ILL,  I_ILL,  I_ILL,  I_CMP,  I_DEC,  I_ILL, 
I_CPX,  I_SBC,  I_ILL,  I_ILL,  I_CPX,  I_SBC,  I_INC,  I_ILL, 
I_INX,  I_SBC,  I_NOP,  I_ILL,  I_CPX,  I_SBC,  I_INC,  I_ILL, 
I_BEQ,  I_SBC,  I_ILL,  I_ILL,  I_ILL,  I_SBC,  I_INC,  I_ILL, 
I_SED,  I_SBC,  I_ILL,  I_ILL,  I_ILL,  I_SBC,  I_INC,  I_ILL);

begin
  -- Each block portram is 2Kx8bits, so we need 32 of them
  -- to make 64KB.
  gen_ram: for i in 0 to 31 generate
    ramx: entity spartan6blockram
    port map (
      Clk   => clock,
      address => ram_address(i),
      we      => ram_we(i),
      data_i  => ram_data_i(i),
      data_o  => ram_data_o(i));
  end generate;

  process(clock)
    begin
      report "foo" severity note;
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
          for i  in 0 to 31 loop
            ram_address(i)<="00000000000";
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
              for i in 0 to 31 loop
                ram_we(i) <= '0';
              end loop;  -- i
              for i in 26 to 31 loop
                ram_address(i)<=std_logic_vector(to_unsigned(ram_address(i)'high,11));
              end loop;  -- i              
              state<=VectorLoadPC;
            when VectorLoadPC =>
                case vector is
                  when x"FFFA" =>
                    temp_addr(7 downto 0) <=  ram_data_o(26);
                    temp_addr(15 downto 8) <= ram_data_o(27);
                  when x"FFFC" =>
                    temp_addr(7 downto 0) <=  ram_data_o(28);
                    temp_addr(15 downto 8) <= ram_data_o(29);
                  when x"FFFE" =>
                    temp_addr(7 downto 0) <=  ram_data_o(30);
                    temp_addr(15 downto 8) <= ram_data_o(31);
                  when others =>
                    -- unknown vector, so use reset vector
                    temp_addr(7 downto 0) <=  ram_data_o(28);
                    temp_addr(15 downto 8) <= ram_data_o(29);
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
                for i in 0 to 31 loop
                  ram_we(i)<='0';
                  if reg_pc(4 downto 0)=i then
                    ram_address(i)<=std_logic_vector(reg_pc(15 downto 5));
                    op_mem_slot<=to_unsigned(i,5);
                  elsif reg_pcplus1(4 downto 0)=i then
                    ram_address(i)<=std_logic_vector(reg_pcplus1(15 downto 5));
                    operand1_mem_slot<=to_unsigned(i,5);
                  elsif reg_pcplus2(4 downto 0)=i then
                    ram_address(i)<=std_logic_vector(reg_pcplus2(15 downto 5));
                    operand2_mem_slot<=to_unsigned(i,5);
                  end if;
                end loop;  -- i
                state<=OperandResolve;
            when OperandResolve =>
              -- Get opcode and operands
              temp_opcode <= ram_data_o(to_integer(op_mem_slot));
              temp_operand(15 downto 8) <= ram_data_o(to_integer(operand2_mem_slot));
              temp_operand(7 downto 0) <= ram_data_o(to_integer(operand1_mem_slot));
              -- Lookup instruction and addressing mode
              
            when others => null;
          end case;
        end if;
      end if;
    end process;
end Behavioral;
