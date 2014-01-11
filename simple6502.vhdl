use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity simple6502 is
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
    monitor_sp : out std_logic_vector(7 downto 0);
    monitor_p : out std_logic_vector(7 downto 0);
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : out std_logic_vector(19 downto 0);
    fastio_read : out std_logic;
    fastio_write : out std_logic;
    fastio_wdata : out std_logic_vector(7 downto 0);
    fastio_rdata : in std_logic_vector(7 downto 0)
    );
end entity simple6502;

architecture Behavioural of simple6502 is
-- CPU RAM bank selection registers.
-- Each 4KB (12 address bits) can be made to point to a section of memory.
-- Sections have 16bit addresses, for a total of 28bits (256MB) of address
-- space.  It also makes it possible to multiple 4KB banks point to the same
-- block of RAM.
  type bank_register_set is array (0 to 15) of unsigned(15 downto 0);
  signal ram_bank_registers_read : bank_register_set;
  signal ram_bank_registers_write : bank_register_set;
  signal ram_bank_registers_instructions : bank_register_set;

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

  -- Flags to detect interrupts
  signal nmi_pending : std_logic := '0';
  signal irq_pending : std_logic := '0';
  signal nmi_state : std_logic := '1';
  signal irq_state : std_logic := '1';
  -- Interrupt/reset vector being used
  signal vector : unsigned(15 downto 0);
  
-- Indicate source of operand for instructions
-- Note that ROM is actually implemented using
-- power-on initialised RAM in the FPGA mapped via our io interface.
  signal accessing_fastio : std_logic;
  signal accessing_ram : std_logic;
  signal accessing_slowram : std_logic;

  type processor_state is (
    -- When CPU first powers up, or reset is bought low
    ResetLow,
    -- States for handling interrupts and reset
    Interrupt,VectorRead,VectorRead1,VectorRead2,VectorRead3,
    InstructionFetch,InstructionFetch2,InstructionFetch3,InstructionFetch4,
    BRK1,BRK2,
    Halt
    );
  signal state : processor_state := ResetLow;  -- start processor in reset state
  -- For memory access we push the processor state to follow once the memory
  -- access is complete.
  signal pending_state : processor_state;
  -- Information about instruction currently being executed
  signal opcode : unsigned(7 downto 0);
  signal arg1 : unsigned(7 downto 0);
  
  type instruction is (
    -- 6502/6510 legal and illegal ops
    I_ADC,I_AHX,I_ALR,I_ANC,I_AND,I_ARR,I_ASL,I_AXS,
    I_BCC,I_BCS,I_BEQ,I_BIT,I_BMI,I_BNE,I_BPL,I_BRK,
    I_BVC,I_BVS,I_CLC,I_CLD,I_CLI,I_CLV,I_CMP,I_CPX,
    I_CPY,I_DCP,I_DEC,I_DEX,I_DEY,I_EOR,I_INC,I_INX,
    I_INY,I_ISC,I_JMP,I_JSR,I_KIL,I_LAS,I_LAX,I_LDA,
    I_LDX,I_LDY,I_LSR,I_NOP,I_ORA,I_PHA,I_PHP,I_PLA,
    I_PLP,I_RLA,I_ROL,I_ROR,I_RRA,I_RTI,I_RTS,I_SAX,
    I_SBC,I_SEC,I_SED,I_SEI,I_SHX,I_SHY,I_SLO,I_SRE,
    I_STA,I_STX,I_STY,I_TAS,I_TAX,I_TAY,I_TSX,I_TXA,
    I_TXS,I_TYA,I_XAA,
    -- 65GS02 special ops
    I_SETMAP
    );

  type ilut8bit is array(0 to 255) of instruction;
  constant instruction_lut : ilut8bit := (
    I_BRK,  I_ORA,  I_SETMAP,  I_SLO,  I_NOP,  I_ORA,  I_ASL,  I_SLO,  I_PHP,  I_ORA,  I_ASL,  I_ANC,  I_NOP,  I_ORA,  I_ASL,  I_SLO, 
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
    M_implied,M_immediate,M_accumulator,
    M_zeropage,M_zeropageX,M_zeropageY,
    M_absolute,M_absoluteY,M_absoluteX,
    M_relative,M_indirect,M_indirectX,M_indirectY);

  -- Number of argument bytes required for each addressing mode
  type mode_list is array(addressingmode'low to addressingmode'high) of integer;
  constant mode_bytes_lut : mode_list := (
    M_implied => 0, M_immediate => 1, M_accumulator => 0,
    M_zeropage => 1, M_zeropageX => 1, M_zeropageY => 1,
    M_absolute => 2, M_absoluteX => 2, M_absoluteY => 2,
    M_relative => 1, M_indirect => 2, M_indirectX => 1, M_indirectY => 1);
  
  type mlut8bit is array(0 to 255) of addressingmode;
  constant mode_lut : mlut8bit := (
    -- 00
    M_implied,  M_indirectX,  M_implied,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage,
    M_implied,  M_immediate,  M_accumulator,  M_immediate,  M_absolute,  M_absolute,  M_absolute,  M_absolute, 
    -- 10
    M_relative,  M_indirectY,  M_immediate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
    M_implied,  M_absoluteY,  M_accumulator,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX,
    -- 20
    M_absolute,  M_indirectX,  M_immediate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
    M_implied,  M_immediate,  M_accumulator,  M_immediate,  M_absolute,  M_absolute,  M_absolute,  M_absolute,
    -- 30
    M_relative,  M_indirectY,  M_immediate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
    M_implied,  M_absoluteY,  M_accumulator,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX, 
    -- 40
    M_implied,  M_indirectX,  M_immediate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
    M_implied,  M_immediate,  M_accumulator,  M_immediate,  M_absolute,  M_absolute,  M_absolute,  M_absolute,
    -- 50
    M_relative,  M_indirectY,  M_immediate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
    M_implied,  M_absoluteY,  M_accumulator,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX, 
    -- 60
    M_implied,  M_indirectX,  M_immediate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
    M_implied,  M_immediate,  M_accumulator,  M_immediate,  M_indirect,  M_absolute,  M_absolute,  M_absolute,
    -- 70
    M_relative,  M_indirectY,  M_immediate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
    M_implied,  M_absoluteY,  M_accumulator,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX,
    -- 80
    M_immediate,  M_indirectX,  M_immediate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
    M_implied,  M_immediate,  M_implied,  M_immediate,  M_absolute,  M_absolute,  M_absolute,  M_absolute,
    -- 90
    M_relative,  M_indirectY,  M_immediate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageY,  M_zeropageY, 
    M_implied,  M_absoluteY,  M_implied,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_implied,  M_absoluteY,
    -- A0
    M_immediate,  M_indirectX,  M_immediate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
    M_implied,  M_immediate,  M_implied,  M_immediate,  M_absolute,  M_absolute,  M_absolute,  M_absolute,
    -- B0
    M_relative,  M_indirectY,  M_immediate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageY,  M_zeropageY, 
    M_implied,  M_absoluteY,  M_implied,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteY,  M_absoluteY,
    -- C0
    M_immediate,  M_indirectX,  M_immediate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
    M_implied,  M_immediate,  M_implied,  M_immediate,  M_absolute,  M_absolute,  M_absolute,  M_absolute,
    -- D0
    M_relative,  M_indirectY,  M_immediate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
    M_implied,  M_absoluteY,  M_implied,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX,
    -- E0
    M_immediate,  M_indirectX,  M_immediate,  M_indirectX,  M_zeropage,  M_zeropage,  M_zeropage,  M_zeropage, 
    M_implied,  M_immediate,  M_implied,  M_immediate,  M_absolute,  M_absolute,  M_absolute,  M_absolute,
    -- F0
    M_relative,  M_indirectY,  M_immediate,  M_indirectY,  M_zeropageX,  M_zeropageX,  M_zeropageX,  M_zeropageX, 
    M_implied,  M_absoluteY,  M_implied,  M_absoluteY,  M_absoluteX,  M_absoluteX,  M_absoluteX,  M_absoluteX);
  
begin
  process(clock)

    procedure reset_cpu_state is
  begin
    -- Default register values
    reg_a <= x"AA";
    reg_x <= x"11";
    reg_y <= x"22";
    reg_sp <= x"ff";

    -- Default CPU flags
    flag_c <= '0';
    flag_d <= '0';
    flag_i <= '1';                -- start with IRQ disabled
    flag_z <= '0';
    flag_n <= '0';
    flag_v <= '0';

    -- Default memory map (C64 like, but with enhanced IO and kernel)
    -- Map first bank of fast RAM at $0000 - $CFFF
    for i in 0 to 12 loop
      ram_bank_registers_read(i)<=to_unsigned(i,16);
      ram_bank_registers_write(i)<=to_unsigned(i,16);
      ram_bank_registers_instructions(i)<=to_unsigned(i,16);
    end loop;  -- i
    -- enhanced IO at $D000-$DFFF
    ram_bank_registers_read(13) <= x"FFD3";  
    ram_bank_registers_write(13) <= x"FFD3";
    ram_bank_registers_instructions(13) <= x"FFD3";
    -- Kernel65 ROM at $E000-$FFFF (writes redirect to "underlying" fast RAM)
    ram_bank_registers_read(14) <= x"FFFE";
    ram_bank_registers_write(14) <= x"000E";
    ram_bank_registers_instructions(14) <= x"FFFE";
    ram_bank_registers_read(15) <= x"FFFF";
    ram_bank_registers_write(15) <= x"000F";
    ram_bank_registers_instructions(15) <= x"FFFF";       
  end procedure reset_cpu_state;

  procedure check_for_interrupts is
  begin
    if nmi = '0' and nmi_state = '1' then
      nmi_pending <= '1';        
    end if;
    nmi_state <= nmi;
    if irq = '0' and irq_state = '1' then
      irq_pending <= '1';        
    end if;
    irq_state <= irq;
  end procedure check_for_interrupts;

  -- purpose: Convert a 16-bit C64 address to native RAM (or I/O or ROM) address
  function resolve_address_to_long(short_address : unsigned(15 downto 0); ram_bank_registers : bank_register_set)
    return unsigned is 
    variable temp_address : unsigned(27 downto 0);
    variable temp_bank_block : unsigned(15 downto 0);
  begin  -- resolve_long_address
    temp_bank_block :=ram_bank_registers(to_integer(short_address(15 downto 12)));
    temp_address(27 downto 12):= temp_bank_block;
    temp_address(11 downto 0):=short_address(11 downto 0);

    return temp_address;
  end resolve_address_to_long;
  
  -- purpose: read from a 16-bit CPU address
  procedure read_address (
    memmap     : in bank_register_set;
    address    : in unsigned(15 downto 0);    
    next_state : in processor_state) is
    variable long_address : unsigned(27 downto 0);
  begin  -- read_address
    -- Schedule the memory read from the appropriate source.
    accessing_ram <= '0'; accessing_slowram <= '0'; accessing_fastio <= '0';
    long_address := resolve_address_to_long(address,memmap);
    if long_address(27 downto 17)="00000000000" then
      accessing_ram <= '1';
    elsif long_address(27 downto 24) = x"8" then
      accessing_slowram <= '1';
    elsif long_address(27 downto 24) = x"F" then
      accessing_fastio <= '1';
      fastio_addr <= std_logic_vector(long_address(19 downto 0));
      fastio_read <= '1';
    end if;
    -- Once read, we then resume processing from the specified state.
    pending_state <= next_state;
  end read_address;

  procedure write_byte (
    memmap             : in bank_register_set;
    address            : in unsigned(15 downto 0);
    value              : in unsigned(7 downto 0);
    next_state         : in processor_state) is
    variable long_address : unsigned(27 downto 0);
  begin
    -- Schedule the memory write to the appropriate destination.
    accessing_ram <= '0'; accessing_slowram <= '0'; accessing_fastio <= '0';
    long_address := resolve_address_to_long(address,memmap);
    if long_address(27 downto 17)="00000000000" then
      accessing_ram <= '1';
    elsif long_address(27 downto 24) = x"8" then
      accessing_slowram <= '1';
    elsif long_address(27 downto 24) = x"F" then
      accessing_fastio <= '1';
      fastio_addr <= std_logic_vector(long_address(19 downto 0));
      fastio_write <= '1';
      fastio_wdata <= std_logic_vector(value);
      -- No wait states on I/O write, so proceed directly to the next state
      state <= next_state;
    end if;
    -- Once read, we then resume processing from the specified state.
    pending_state <= next_state;
  end procedure write_byte;

  -- purpose: push a byte onto the stack
  procedure push_byte (
    value : in unsigned(7 downto 0);
    next_state : in processor_state) is
  begin  -- push_byte
    reg_sp <= reg_sp - 1;
    write_byte(ram_bank_registers_write,x"01" & reg_sp,value,next_state);
  end push_byte;
  
  procedure read_instruction_byte (
    address : in unsigned(15 downto 0);
    next_state : in processor_state) is
  begin
    read_address(ram_bank_registers_instructions,address,next_state);
  end read_instruction_byte;

  procedure read_data_byte (
    address : in unsigned(15 downto 0);
    next_state : in processor_state) is
  begin
    read_address(ram_bank_registers_read,address,next_state);
  end read_data_byte;

  -- purpose: obtain the byte of memory that has been read
  impure function read_data
    return unsigned is
  begin  -- read_data
    if accessing_fastio='1' then
      return unsigned(fastio_rdata);
    else
      return x"FF";
    end if;
  end read_data; 
  
  procedure set_cpu_flags_inc (value : in unsigned(7 downto 0)) is
  begin
    if value=x"00" then
      flag_z <='1';
    else
      flag_z <='0';
    end if;
    flag_n <= value(7);
  end procedure set_cpu_flags_inc;

  procedure execute_implied_instruction (
    opcode : in unsigned(7 downto 0)) is
    variable instruction : instruction := instruction_lut(to_integer(opcode));
    variable mode : addressingmode := mode_lut(to_integer(opcode));
    -- False if handling a special instruction
    variable normal_instruction : boolean := true;
  begin
    if mode=M_implied then
      case instruction is
        when I_SETMAP =>
          -- load RAM map register
          -- Sets map register $YY to $AAXX
          -- Registers are:
          -- $00 - $0F for instruction fetch
          -- $10 - $1F for memory read
          -- $20 - $2F for memory write
          if reg_y(7 downto 4) = x"0" then
            ram_bank_registers_instructions(to_integer(reg_y(3 downto 0)))
              <= reg_a & reg_x;
          elsif reg_y(7 downto 4) = x"1" then
            ram_bank_registers_read(to_integer(reg_y(3 downto 0)))
              <= reg_a & reg_x;
          elsif reg_y(7 downto 4) = x"2" then
            ram_bank_registers_write(to_integer(reg_y(3 downto 0)))
              <= reg_a & reg_x;
          end if;
        when I_BRK =>
          -- break instruction. Push state and jump to the appropriate
          -- vector.
          vector <= x"FFFE";    -- BRK follows the IRQ vector
          flag_i <= '1';      -- Disable further IRQs while the
                                        -- interrupt is being handled.
          push_byte(reg_pc(15 downto 8),BRK1);
          normal_instruction := false;
        when I_CLC => flag_c <= '0';
        when I_CLD => flag_d <= '0';
        when I_CLI => flag_i <= '0';
        when I_CLV => flag_v <= '0';
        when I_DEX => reg_x <= reg_x - 1; set_cpu_flags_inc(reg_x);
        when I_DEY => reg_y <= reg_y - 1; set_cpu_flags_inc(reg_y);
        when I_INX => reg_x <= reg_x + 1; set_cpu_flags_inc(reg_x);
        when I_INY => reg_y <= reg_y + 1; set_cpu_flags_inc(reg_y);
        when I_KIL => state <= Halt; normal_instruction:= false;

        when I_SEC => flag_c <= '1';
        when I_SED => flag_d <= '1';
        when I_SEI => flag_i <= '1';
        when I_TAX => reg_x <= reg_a;
        when I_TAY => reg_y <= reg_a;
        when I_TSX => reg_x <= reg_sp;
        when I_TXA => reg_a <= reg_x;
        when I_TXS => reg_sp <= reg_x;
        when I_TYA => reg_a <= reg_a;
                      
        when I_NOP => null;
        when others => null;
      end case;
      if normal_instruction=true then
        -- XXX Can pre-fetch now like on 4510
        state <= InstructionFetch;
      end if;
    end if;
  end procedure execute_implied_instruction;      

  procedure execute_instruction (
    opcode : in unsigned(7 downto 0);
    arg1 : in unsigned(7 downto 0);
    arg2 : in unsigned(7 downto 0)
    ) is
  begin
    null;
  end procedure execute_instruction;      

  variable virtual_reg_p : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clock) then
      monitor_pc <= std_logic_vector(reg_pc);
      
      -- Clear memory access interfaces
      fastio_addr <= (others => '1');
      fastio_read <= '0';
      fastio_write <= '0';
      
      -- Generate virtual processor status register for convenience
      virtual_reg_p(7) := flag_n;
      virtual_reg_p(6) := flag_v;
      virtual_reg_p(5) := '1';
      virtual_reg_p(4) := '0';
      virtual_reg_p(3) := flag_d;
      virtual_reg_p(2) := flag_i;
      virtual_reg_p(1) := flag_z;
      virtual_reg_p(0) := flag_c;

      if reset = '0' or state = ResetLow then
        -- reset cpu
        state <= VectorRead;
        vector <= x"FFFC";
        reset_cpu_state;
      else
        -- CPU running, so do CPU state machine
        check_for_interrupts;
        case state is
          when VectorRead => read_instruction_byte(vector,VectorRead2);
          when VectorRead2 => reg_pc(7 downto 0) <= read_data; read_instruction_byte(vector+1,VectorRead3);
          when VectorRead3 => reg_pc(15 downto 8) <= read_data; state <= InstructionFetch;
          when InstructionFetch =>
            read_instruction_byte(reg_pc,InstructionFetch2);
            reg_pc <= reg_pc + 1;
          when InstructionFetch2 =>
            -- Keep reading bytes if necessary
            if mode_lut(to_integer(read_data))=M_implied
              or mode_lut(to_integer(read_data))=M_accumulator then
              -- 1-byte instruction, process now
              execute_implied_instruction(read_data);
            else
              opcode <= read_data;
              read_instruction_byte(reg_pc,InstructionFetch3);
            end if;
          when InstructionFetch3 =>
            reg_pc <= reg_pc + 1;
            if mode_bytes_lut(mode_lut(to_integer(opcode)))=2 then
              arg1 <= read_data;
              read_instruction_byte(reg_pc,InstructionFetch4);
            else
              execute_instruction(opcode,read_data,x"FF");
            end if;
          when InstructionFetch4 =>
            reg_pc <= reg_pc + 1;
            execute_instruction(opcode,arg1,read_data);
          when BRK1 =>
            push_byte(reg_pc(7 downto 0),BRK2);
          when BRK2 =>
            virtual_reg_p(5) := '1';    -- set B flag in P before pushing
            push_byte(unsigned(virtual_reg_p),VectorRead);
          when others => null;
        end case;
      end if;
    end if;
  end process;
end Behavioural;
