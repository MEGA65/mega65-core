use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

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
    monitor_state : out std_logic_vector(7 downto 0);

    ---------------------------------------------------------------------------
    -- Memory access interface used by monitor
    ---------------------------------------------------------------------------
    monitor_mem_address : in std_logic_vector(27 downto 0);
    monitor_mem_rdata : out unsigned(7 downto 0);
    monitor_mem_wdata : in unsigned(7 downto 0);
    monitor_mem_read : in std_logic;
    monitor_mem_write : in std_logic;
    monitor_mem_setpc : in std_logic;
    monitor_mem_register : out unsigned(15 downto 0);
    monitor_mem_attention_request : in std_logic;
    monitor_mem_attention_granted : out std_logic := '0';
    monitor_mem_trace_mode : in std_logic;
    monitor_mem_trace_toggle : in std_logic;
    
    ---------------------------------------------------------------------------
    -- Interface to FastRAM in video controller (just 128KB for now)
    ---------------------------------------------------------------------------
    fastram_we : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    fastram_read : OUT STD_LOGIC;
    fastram_write : OUT STD_LOGIC;
    fastram_address : OUT STD_LOGIC_VECTOR(13 DOWNTO 0);
    fastram_datain : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    fastram_dataout : IN STD_LOGIC_VECTOR(63 DOWNTO 0);

    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : inout std_logic_vector(19 downto 0);
    fastio_read : inout std_logic;
    fastio_write : out std_logic;
    fastio_wdata : out std_logic_vector(7 downto 0);
    fastio_rdata : inout std_logic_vector(7 downto 0)
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

  -- For debugging, keep a log of the processor states for the last instruction.
  -- It's a bit of a kluge to use this type of array, but it is convenient.
  signal recent_states : bank_register_set;
  
  signal fastram_byte_number : unsigned(2 DOWNTO 0);
  
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
  
  type processor_state is (
    -- When CPU first powers up, or reset is bought low
    ResetLow,
    -- States for handling interrupts and reset
    Interrupt,VectorRead,VectorRead1,VectorRead2,VectorRead3,
    InstructionFetch,                   -- $06
    InstructionFetch2,InstructionFetch3,InstructionFetch4,  -- $09
    BRK1,BRK2,PLA1,PLP1,RTI1,RTI2,RTI3,  -- $10
    RTS1,RTS2,JSR1,JMP1, -- $14
    JMP2,JMP3,                          -- $16
    IndirectX1,IndirectX2,IndirectX3,   -- $19
    IndirectY1,IndirectY2,IndirectY3,   -- $1c
    ExecuteDirect,RMWCommit,            -- $1e
    Halt,WaitOneCycle,                  -- $20
    MonitorAccessDone,MonitorReadDone,   -- $22
    Interrupt2,Interrupt3
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

  -- PC used for JSR is the value of reg_pc after reading only one of
  -- of the argument bytes.  We could subtract one, but it is less logic to
  -- just remember PC after reading one argument byte.
  signal reg_pc_jsr : unsigned(15 downto 0);
  -- Temporary address register (used for indirect modes)
  signal reg_addr : unsigned(15 downto 0);
  -- Temporary instruction register (used for many modes)
  signal reg_instruction : instruction;
  -- Temporary value holder (used for RMW instructions)
  signal reg_value : unsigned(7 downto 0);
  
-- Indicate source of operand for instructions
-- Note that ROM is actually implemented using
-- power-on initialised RAM in the FPGA mapped via our io interface.
  signal accessing_fastio : std_logic;
  signal accessing_ram : std_logic;
  signal accessing_slowram : std_logic;

  signal monitor_mem_trace_toggle_last : std_logic := '0';

begin
  process(clock)

    procedure reset_cpu_state is
  begin
    -- Default register values
    reg_a <= x"11";
    reg_x <= x"22";
    reg_y <= x"33";
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
    -- Kernel64 ROM at $E000-$FFFF (writes redirect to "underlying" fast RAM)
    ram_bank_registers_read(14) <= x"FFEE";
    ram_bank_registers_write(14) <= x"000E";
    ram_bank_registers_instructions(14) <= x"FFEE";
    ram_bank_registers_read(15) <= x"FFEF";
    ram_bank_registers_write(15) <= x"000F";
    ram_bank_registers_instructions(15) <= x"FFEF";       
    -- BASIC64 ROM at $A000-$BFFF (writes redirect to "underlying" fast RAM)
    ram_bank_registers_read(10) <= x"FFEA";
    ram_bank_registers_write(10) <= x"000A";
    ram_bank_registers_instructions(10) <= x"FFEA";
    ram_bank_registers_read(11) <= x"FFEB";
    ram_bank_registers_write(11) <= x"000B";
    ram_bank_registers_instructions(11) <= x"FFEB";

    -- For simulation: our own rom at $E000 - $FFFF, also mapping to $0000-$0FFF
    -- since fastram doesn't work in simulation with GHDL.
    --ram_bank_registers_read(14) <= x"FFFE";
    --ram_bank_registers_write(14) <= x"000E";
    --ram_bank_registers_instructions(14) <= x"FFFE";
    --ram_bank_registers_read(15) <= x"FFFF";
    --ram_bank_registers_write(15) <= x"000F";
    --ram_bank_registers_instructions(15) <= x"FFFF";       

    --ram_bank_registers_read(0) <= x"FFFE";
    --ram_bank_registers_write(0) <= x"FFFE";
    --ram_bank_registers_instructions(0) <= x"FFFE";
    
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

  procedure read_long_address(
    long_address : in unsigned(27 downto 0);
    next_state : in processor_state) is
  begin
    -- Schedule the memory read from the appropriate source.
    accessing_ram <= '0'; accessing_slowram <= '0'; accessing_fastio <= '0';
    if long_address(27 downto 17)="00000000000" then
      report "Reading from fastram address $" & to_hstring(long_address(19 downto 0))
        & ", word $" & to_hstring(long_address(18 downto 3)) severity note;
      accessing_ram <= '1';
      fastram_address <= std_logic_vector(long_address(16 downto 3));
      fastram_byte_number <= long_address(2 downto 0);
      fastram_read <= '1';
      pending_state <= next_state;
      state <= WaitOneCycle;
      -- No wait states in fastram system, so proceed directly to next state
    elsif long_address(27 downto 24) = x"8" then
      accessing_slowram <= '1';
      -- XXX Need to do actual slow ram access here.
      state <= next_state;
    elsif long_address(27 downto 24) = x"F" then
      accessing_fastio <= '1';
      fastio_addr <= std_logic_vector(long_address(19 downto 0));
      fastio_read <= '1';
      -- No wait states in fastio system, so proceed directly to next state
      state <= next_state;
    else
      -- Don't let unmapped memory jam things up
      state <= next_state;
    end if;
    -- Once read, we then resume processing from the specified state.
    pending_state <= next_state;
  end read_long_address;
  
  -- purpose: read from a 16-bit CPU address
  procedure read_address (
    memmap     : in bank_register_set;
    address    : in unsigned(15 downto 0);
    next_state : in processor_state) is
    variable long_address : unsigned(27 downto 0);
  begin  -- read_address
    long_address := resolve_address_to_long(address,memmap);
    read_long_address(long_address,next_state);
  end read_address;

  procedure write_long_byte(
    long_address       : in unsigned(27 downto 0);
    value              : in unsigned(7 downto 0);
    next_state         : in processor_state) is
  begin
    -- Schedule the memory write to the appropriate destination.
    accessing_ram <= '0'; accessing_slowram <= '0'; accessing_fastio <= '0';
    if long_address(27 downto 17)="00000000000" then
      accessing_ram <= '1';
      fastram_address <= std_logic_vector(long_address(16 downto 3));
      fastram_write <= '1';
      fastram_read <= '0';
      fastram_we <= (others => '0');
      fastram_datain <= (others => '1');
      case long_address(2 downto 0) is
        when "000" => fastram_we <= "00000001"; fastram_datain(7 downto 0) <= std_logic_vector(value);
        when "001" => fastram_we <= "00000010"; fastram_datain(15 downto 8) <= std_logic_vector(value);
        when "010" => fastram_we <= "00000100"; fastram_datain(23 downto 16) <= std_logic_vector(value);
        when "011" => fastram_we <= "00001000"; fastram_datain(31 downto 24) <= std_logic_vector(value);
        when "100" => fastram_we <= "00010000"; fastram_datain(39 downto 32) <= std_logic_vector(value);
        when "101" => fastram_we <= "00100000"; fastram_datain(47 downto 40) <= std_logic_vector(value);
        when "110" => fastram_we <= "01000000"; fastram_datain(55 downto 48) <= std_logic_vector(value);
        when "111" => fastram_we <= "10000000"; fastram_datain(63 downto 56) <= std_logic_vector(value);
        when others =>
          report "dud write to fastram" severity note;
      end case;
      -- report "writing to fastram..." severity note;
      state <= next_state;
    elsif long_address(27 downto 24) = x"8" then
      accessing_slowram <= '1';
    elsif long_address(27 downto 24) = x"F" then
      accessing_fastio <= '1';
      fastio_addr <= std_logic_vector(long_address(19 downto 0));
      fastio_write <= '1';
      fastio_wdata <= std_logic_vector(value);
      -- No wait states on I/O write, so proceed directly to the next state
      state <= next_state;
    else
      -- Don't let unmapped memory jam things up
      state <= next_state;
    end if;
    -- Once read, we then resume processing from the specified state.
    pending_state <= next_state;
  end write_long_byte;
  
  procedure write_byte (
    memmap             : in bank_register_set;
    address            : in unsigned(15 downto 0);
    value              : in unsigned(7 downto 0);
    next_state         : in processor_state) is
    variable long_address : unsigned(27 downto 0);
  begin
    long_address := resolve_address_to_long(address,memmap);
    --report "Writing $" & to_hstring(value) & " @ $" & to_hstring(address)
    --  & " (resolves to $" & to_hstring(long_address) & ")" severity note;
    write_long_byte(long_address,value,next_state);
  end procedure write_byte;

  procedure write_data_byte (
    address            : in unsigned(15 downto 0);
    value              : in unsigned(7 downto 0);
    next_state         : in processor_state) is
  begin
    write_byte(ram_bank_registers_write,address,value,next_state);
  end procedure write_data_byte;
  
  -- purpose: push a byte onto the stack
  procedure push_byte (
    value : in unsigned(7 downto 0);
    next_state : in processor_state) is
  begin  -- push_byte
    reg_sp <= reg_sp - 1;
    write_byte(ram_bank_registers_write,x"01" & reg_sp,value,next_state);
  end push_byte;

  -- purpose: pull a byte from the stack
  procedure pull_byte (
    next_state : in processor_state) is
  begin  -- pull_byte
    reg_sp <= reg_sp + 1;
    read_address(ram_bank_registers_read,x"01" & (reg_sp + 1),next_state);
  end pull_byte;
  
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
    elsif accessing_ram='1' then
      report "Extracting fastram value from 64-bit read $" & to_hstring(fastram_dataout) severity note;
      case fastram_byte_number is
        when "000" => return unsigned(fastram_dataout( 7 downto 0));
        when "001" => return unsigned(fastram_dataout(15 downto 8));
        when "010" => return unsigned(fastram_dataout(23 downto 16));
        when "011" => return unsigned(fastram_dataout(31 downto 24));
        when "100" => return unsigned(fastram_dataout(39 downto 32));
        when "101" => return unsigned(fastram_dataout(47 downto 40));
        when "110" => return unsigned(fastram_dataout(55 downto 48));
        when "111" => return unsigned(fastram_dataout(63 downto 56));
        when others => return x"FF";
      end case;
    else
      return x"FF";
    end if;
  end read_data; 

  -- purpose: set processor flags from a byte (eg for PLP or RTI)
  procedure load_processor_flags (
    value : in unsigned(7 downto 0)) is
  begin  -- load_processor_flags
    flag_n <= value(7);
    flag_v <= value(6);
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

  procedure execute_implied_instruction (
    opcode : in unsigned(7 downto 0)) is
    variable i : instruction := instruction_lut(to_integer(opcode));
    variable mode : addressingmode := mode_lut(to_integer(opcode));
    -- False if handling a special instruction
    variable normal_instruction : boolean := true;
    variable virtual_reg_p : unsigned(7 downto 0);
  begin

    -- report "Executing " & instruction'image(i) & " mode " & addressingmode'image(mode) severity note;

    -- Generate virtual processor status register for BRK
    virtual_reg_p(7) := flag_n;
    virtual_reg_p(6) := flag_v;
    virtual_reg_p(5) := '1';
    virtual_reg_p(4) := '0';
    virtual_reg_p(3) := flag_d;
    virtual_reg_p(2) := flag_i;
    virtual_reg_p(1) := flag_z;
    virtual_reg_p(0) := flag_c;

    -- By default go back to fetching the next instruction.
    state <= InstructionFetch;
    
    if mode=M_implied then
      case i is
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
        when I_DEX => reg_x <= with_nz(reg_x - 1);
        when I_DEY => reg_y <= with_nz(reg_y - 1);
        when I_INX => reg_x <= with_nz(reg_x + 1);
        when I_INY => reg_y <= with_nz(reg_y + 1);
        when I_KIL => state <= Halt; normal_instruction:= false;
        when I_PHA => push_byte(reg_a,InstructionFetch);
        when I_PHP => push_byte(virtual_reg_p,InstructionFetch);
        when I_PLA => pull_byte(PLA1);
        when I_PLP => pull_byte(PLP1);
        when I_RTI => pull_byte(RTI1);
        when I_RTS => pull_byte(RTS1);
        when I_SEC => flag_c <= '1';
        when I_SED => flag_d <= '1';
        when I_SEI => flag_i <= '1';
        when I_TAX => reg_x <= with_nz(reg_a);
        when I_TAY => reg_y <= with_nz(reg_a);
        when I_TSX => reg_x <= with_nz(reg_sp);
        when I_TXA => reg_a <= with_nz(reg_x);
        when I_TXS => reg_sp <= with_nz(reg_x);
        when I_TYA => reg_a <= with_nz(reg_y);
                      
        when I_NOP => null;
        when others => null;
      end case;
    elsif mode=M_accumulator then
      -- We have a separate path for these so that they can be executed in 1
      -- cycle instead of incurring an extra cycle delay if passed through the
      -- normal memory-based instruction path. 
      case i is
        when I_ASL => reg_a <= reg_a(6 downto 0) & '0'; flag_c <= reg_a(7);
        when I_ROL => reg_a <= reg_a(6 downto 0) & flag_c; flag_c <= reg_a(7);
        when I_LSR => reg_a <= '0' & reg_a(7 downto 1); flag_c <= reg_a(0);
        when I_ROR => reg_a <= flag_c & reg_a(7 downto 1); flag_c <= reg_a(0);
        when others => null;
      end case;
    end if;
  end procedure execute_implied_instruction;

  procedure execute_direct_instruction (
    i       : in instruction;
    address : in unsigned(15 downto 0)) is
  begin  -- execute_direct_instruction
    -- Instruction using a direct addressing mode
    if i=I_STA or i=I_STX or i=I_STY then
      -- Store instruction, so just write
      case i is
        when I_STA => write_data_byte(address,reg_a,InstructionFetch);
        when I_STX => write_data_byte(address,reg_x,InstructionFetch);
        when I_STY => write_data_byte(address,reg_y,InstructionFetch);
        when others => state <= InstructionFetch;
      end case;
    else
      -- Instruction requires reading from memory
      report "reading operand from memory" severity note;
      reg_instruction <= i;
      reg_addr <= address; -- remember address for writeback
      read_data_byte(address,ExecuteDirect);
    end if;
  end execute_direct_instruction;

  procedure alu_op_cmp (
    i1 : in unsigned(7 downto 0);
    i2 : in unsigned(7 downto 0)) is
  begin
    if i1=i2 then
      flag_z <= '1';
      flag_n <= '0';
      flag_c <= '1';
    elsif i1<i2 then
      flag_z <= '0';
      flag_n <= '1';
      flag_c <= '0';
    elsif i1>i2 then
      flag_z <= '0';
      flag_n <= '0';
      flag_c <= '1';
    end if;
  end alu_op_cmp;
  
  impure function alu_op_add (
    i1 : in unsigned(7 downto 0);
    i2 : in unsigned(7 downto 0)) return unsigned is
    variable o : unsigned(7 downto 0);
  begin
    -- Whether in decimal mode or not, calculate normal sum,
    -- so that Z can be set correctly (Z in decimal mode =
    -- Z in binary mode).
    -- XXX Why doesn't just i1+i2 work here?
    o := to_unsigned(to_integer(i1) + to_integer(i2),8);
    report "interim result = $" & to_hstring(std_logic_vector(o)) severity note;
    if flag_c='1' then
      o := o + 1;
    end if;  
    o := with_nz(o);

    -- Signed overflow flag
    -- See http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html
    -- "Overflow can be computed simply in C++ from the inputs and the result.
    -- Overflow occurs if (M^result)&(N^result)&0x80 is nonzero. That is, if the
    -- sign of both inputs is different from the sign of the result. (Anding with
    -- 0x80 extracts just the sign bit from the result.) Another C++ formula is
    -- !((M^N) & 0x80) && ((M^result) & 0x80). This means there is overflow if the
    -- inputs do not have different signs and the input sign is different from the
    -- output sign (link)."    
    if i1(7) /= o(7) and i2(7) /= o(7) then
      flag_v <= '1';
    else
      flag_v <= '0';
    end if;

    if unsigned(o)<unsigned(i1) then
      flag_c <= '1';
    else
      flag_c <= '0';
    end if;
    if flag_d='1' then
      -- Decimal mode. Flags are set weirdly.

      -- First, Z is set based on normal addition above.
      
      -- Now do BCD fix up on lower nybl.
      if o(3 downto 0) > x"9" then
        o:= o+6;
      end if;

      -- Then set N & V *before* upper nybl BCD fixup
      flag_n<=o(7);
      if i1(7) /= o(7) and i2(7) /= o(7) then
        flag_v <= '1';
      else
        flag_v <= '0';
      end if;

      -- Now do BCD fixup on upper nybl
      if o(7 downto 4)>x"9" then
        o(7 downto 4):=o(7 downto 4)+x"6";
      end if;

      -- Finally set carry flag based on result
      if o<i1 then
        flag_c <='1';
      else
        flag_c <='0';
      end if;
    end if;
    -- Return final value
    report "add result of "
      & "$" & to_hstring(std_logic_vector(i1)) 
      & " + "
      & "$" & to_hstring(std_logic_vector(i2)) 
      & " + "
      & "$" & std_logic'image(flag_c)
      & " = " & to_hstring(std_logic_vector(o)) severity note;
    return o;
  end function alu_op_add;

  impure function alu_op_sub (
    i1 : in unsigned(7 downto 0);
    i2 : in unsigned(7 downto 0)) return unsigned is
    variable o : unsigned(7 downto 0);
    variable s2 : unsigned(7 downto 0);
  begin
    -- calculate ones-complement.
    s2 := (not i2);
    -- Then do add.
    -- Z and C should get set correctly.
    -- XXX Will this work for decimal mode?
    o := alu_op_add(i1,s2);
    report "$" & to_hstring(i1) & " - $" & to_hstring(i2) & " = $" & to_hstring(o) severity note;
    
    return o;
    
    -- Return final value
    report "sub result of "
      & "$" & to_hstring(std_logic_vector(i1)) 
      & " - "
      & "$" & to_hstring(std_logic_vector(i2)) 
      & " - 1 + "
      & "$" & std_logic'image(flag_c)
      & " = " & to_hstring(std_logic_vector(o)) severity note;
    return o;
  end function alu_op_sub;

  procedure rmw_operand_commit (
    address : in unsigned(15 downto 0);
    first_value : in unsigned(7 downto 0);
    final_value : in unsigned(7 downto 0)) is
  begin
    report "first_value = $" & to_hstring(first_value)
      & ", final_value = $" & to_hstring(final_value)
      severity note;
    reg_addr <= address;
    reg_value <= with_nz(final_value);
    write_data_byte(address,first_value,RMWCommit);
  end procedure rmw_operand_commit;
  
  procedure execute_operand_instruction (
    i       : in instruction;
    operand : in unsigned(7 downto 0);
    address : in unsigned(15 downto 0)) is
    variable bitbucket : unsigned(7 downto 0);
  begin
    -- report "Calculating result for " & instruction'image(i) & " operand=$" & to_hstring(operand) severity note;
    state <= InstructionFetch;
    case i is
      when I_LDA => reg_a <= with_nz(operand);
      when I_LDX => reg_x <= with_nz(operand);
      when I_LDY => reg_y <= with_nz(operand);
      when I_ADC => reg_a <= alu_op_add(reg_a,operand);
      when I_AND => reg_a <= with_nz(reg_a and operand);
      when I_ASL => flag_c <= operand(7); rmw_operand_commit(address,operand,operand(6 downto 0)&'0');
      when I_BIT => bitbucket := with_nz(reg_a and operand);
      when I_CMP => alu_op_cmp(reg_a,operand);
      when I_CPX => alu_op_cmp(reg_x,operand);
      when I_CPY => alu_op_cmp(reg_y,operand);
      when I_DEC => rmw_operand_commit(address,operand,operand-1);
      when I_EOR => reg_a <= with_nz(reg_a xor operand);        
      when I_INC =>
        report "INC of $" & to_hstring(operand) & " to $" & to_hstring(operand+1) severity note;
        rmw_operand_commit(address,operand,(operand+1));
      when I_LSR => flag_c <= operand(0); rmw_operand_commit(address,operand,'0'&operand(7 downto 1));
      when I_ORA => reg_a <= with_nz(reg_a or operand);
      when I_ROL => flag_c <= operand(7); rmw_operand_commit(address,operand,operand(6 downto 0)&flag_c);
      when I_ROR => flag_c <= operand(0); rmw_operand_commit(address,operand,flag_c&operand(7 downto 1));
      when I_SBC => reg_a <= alu_op_sub(reg_a,operand);
      when I_STA => write_data_byte(address,reg_a,InstructionFetch);
      when I_STX => write_data_byte(address,reg_x,InstructionFetch);
      when I_STY => write_data_byte(address,reg_y,InstructionFetch);
      when others => null;
    end case;
  end procedure execute_operand_instruction;

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
  
  procedure execute_instruction (      
    opcode : in unsigned(7 downto 0);
    arg1 : in unsigned(7 downto 0);
    arg2 : in unsigned(7 downto 0)
    ) is
    variable i : instruction := instruction_lut(to_integer(opcode));
    variable mode : addressingmode := mode_lut(to_integer(opcode));
  begin
    -- By default fetch next instruction
    state <= InstructionFetch;

    --report "Executing " & instruction'image(i)
    --  & " mode " & addressingmode'image(mode) severity note;
    
    if mode=M_relative then
      if (i=I_BCC and flag_c='0')
        or (i=I_BCS and flag_c='1')
        or (i=I_BVC and flag_v='0')
        or (i=I_BVS and flag_v='1')
        or (i=I_BPL and flag_n='0')
        or (i=I_BMI and flag_n='1')
        or (i=I_BEQ and flag_z='1')
        or (i=I_BNE and flag_z='0') then
        -- take branch
        if arg1(7)='0' then -- branch forwards.
          reg_pc <= reg_pc + unsigned(arg1(6 downto 0));
        else -- branch backwards.
          reg_pc <= (reg_pc - x"0080") + unsigned(arg1(6 downto 0));
        end if;
      end if;
      -- Treat jump instructions specially, since they are rather different to
      -- the rest.
    elsif i=I_JSR then
      reg_pc <= arg2 & arg1; push_byte(reg_pc_jsr(7 downto 0),JSR1);
    elsif i=I_JMP and mode=M_absolute then
      reg_pc <= arg2 & arg1; state<=InstructionFetch;
    elsif i=I_JMP and mode=M_indirect then
      -- Read first byte of indirect vector
      read_data_byte(arg2 & arg1,JMP1);
      -- Remember address of second byte of indirect vector so that
      -- we can ask for it in JMP1
      reg_addr <= arg2 & (arg1 +1);
    elsif mode=M_indirectX then
      -- Read ZP indirect from data memory map, since ZP is written into that
      -- map.
      reg_instruction <= i;
      reg_addr <= x"00" & (arg1 + reg_x +1);
      read_data_byte(x"00" & (arg1 + reg_x),IndirectX1);
    elsif mode=M_indirectY then
      reg_instruction <= i;
      reg_addr <= x"00" & (arg1 + 1);
      read_data_byte(x"00" & arg1,IndirectY1);
    else
      --report "executing direct instruction" severity note;
      case mode is
        -- Direct modes
        when M_zeropage => execute_direct_instruction(i,arg2&arg1);
        when M_zeropageX => execute_direct_instruction(i,arg2&(arg1+reg_x));
        when M_zeropageY => execute_direct_instruction(i,arg2&(arg1+reg_y));
        when M_absolute => execute_direct_instruction(i,arg2&arg1);
        when M_absoluteX => execute_direct_instruction(i,(arg2&arg1)+reg_x);
        when M_absoluteY => execute_direct_instruction(i,(arg2&arg1)+reg_y);
        when M_immediate => execute_operand_instruction(i,arg1,x"0000");
        when others =>
          assert false report "Uncaught instruction mode" severity failure;
          assert true report "Uncaught instruction mode" severity failure;
      end case;
    end if;
  end procedure execute_instruction;      

  variable virtual_reg_p : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clock) then
      monitor_state <= std_logic_vector(to_unsigned(processor_state'pos(state),8));
      monitor_pc <= std_logic_vector(reg_pc);
      monitor_a <= std_logic_vector(reg_a);
      monitor_x <= std_logic_vector(reg_x);
      monitor_y <= std_logic_vector(reg_y);
      monitor_sp <= std_logic_vector(reg_sp);
      
      -- Clear memory access interfaces
      fastio_addr <= (others => '1');
      fastio_read <= '0';
      fastio_write <= '0';
      fastram_read <= '0';
      fastram_write <= '0';
      fastram_we <= (others => '0');
      fastram_address <= "11111111111111";
      fastram_datain <= x"d0d1d2d3d4d5d6d7";
      
      -- Generate virtual processor status register for convenience
      virtual_reg_p(7) := flag_n;
      virtual_reg_p(6) := flag_v;
      virtual_reg_p(5) := '1';
      virtual_reg_p(4) := '0';
      virtual_reg_p(3) := flag_d;
      virtual_reg_p(2) := flag_i;
      virtual_reg_p(1) := flag_z;
      virtual_reg_p(0) := flag_c;

      monitor_p <= std_logic_vector(virtual_reg_p);

      if reset = '0' or state = ResetLow then
        -- reset cpu
        state <= VectorRead;
        vector <= x"FFFC";
        reset_cpu_state;
      elsif monitor_mem_attention_request='1' and state = InstructionFetch then
        -- Memory access by serial monitor.
        if monitor_mem_write='1' then
          -- Write to specified long address
          write_long_byte(unsigned(monitor_mem_address),monitor_mem_wdata,
                          MonitorAccessDone);
        else
          -- Read from specified long address
          read_long_address(unsigned(monitor_mem_address),MonitorReadDone);
          -- and optionally set PC
          if monitor_mem_setpc='1' then
            reg_pc <= unsigned(monitor_mem_address(15 downto 0));
          end if;
        end if;   
      else
        -- CPU running, so do CPU state machine
        if monitor_mem_attention_request='0' then
          check_for_interrupts;
        end if;

        recent_states(1 to 15) <= recent_states(0 to 14);
        recent_states(0) <= to_unsigned(processor_state'pos(state),16);

        if monitor_mem_stage_trace_mode='0' or
          monitor_mem_trace_toggle /= monitor_mem_trace_toggle_last then
          monitor_mem_trace_toggle_last <= monitor_mem_trace_toggle;
          case state is
            when MonitorReadDone =>            
              monitor_mem_rdata <= read_data;
              state <= MonitorAccessDone;

              -- Don't overwrite recent states record
              recent_states <= recent_states;
            when MonitorAccessDone =>
              fastram_we <= (others => '0');
              monitor_mem_attention_granted <= '1';
              if monitor_mem_attention_request='0' then
                monitor_mem_attention_granted <= '0';
                state <= InstructionFetch;
              end if;
              -- Don't overwrite recent states record
              recent_states <= recent_states;
            when Interrupt => push_byte(reg_pc(15 downto 8),Interrupt2);
            when Interrupt2 => push_byte(reg_pc(7 downto 0),Interrupt3);
            when Interrupt3 => push_byte(unsigned(virtual_reg_p),VectorRead);
            when VectorRead => reg_pc <= vector; read_instruction_byte(vector,VectorRead2);
            when VectorRead2 => reg_pc(7 downto 0) <= read_data; read_instruction_byte(vector+1,VectorRead3);
            when VectorRead3 => reg_pc(15 downto 8) <= read_data; state <= InstructionFetch;
            when InstructionFetch =>

              -- Show CPU state for debugging
              -- report "state = " & processor_state'image(state) severity note;
              -- Use a format very like that of VICE so that we can compare our boot
              -- sequence to theirs, to find errors in our CPU etc.
              report ""
                & ".C:" & to_hstring(std_logic_vector(reg_pc))
                & " - A:" & to_hstring(std_logic_vector(reg_a))
                & " X:" & to_hstring(std_logic_vector(reg_x))
                & " Y:" & to_hstring(std_logic_vector(reg_y))
                & " SP:" & to_hstring(std_logic_vector(reg_sp))
                & " "
                & flag_status("N",".",flag_n)
                & flag_status("V",".",flag_v)
                & "-"
                & "."
                & flag_status("D",".",flag_d)
                & flag_status("I",".",flag_i)
                & flag_status("Z",".",flag_z)
                & flag_status("C",".",flag_c)        
                severity note;        
              
              monitor_mem_attention_granted <= '0';
              if monitor_mem_trace_mode='0' or
                monitor_mem_trace_toggle /= monitor_mem_trace_toggle_last then
                monitor_mem_trace_toggle_last <= monitor_mem_trace_toggle;

                -- XXX Push PC & P before launching interrupt handlers
                if nmi_pending='1' then
                  nmi_pending <= '0';
                  vector <= x"FFFA"; state <=Interrupt;
                elsif irq_pending='1' and flag_i='0' then
                  irq_pending <= '0';
                  vector <= x"FFFE"; state <=Interrupt;  
                else
                  read_instruction_byte(reg_pc,InstructionFetch2);
                  reg_pc <= reg_pc + 1;
                end if;
              else
                -- Hold recent states
                recent_states <= recent_states;
              end if;
            when InstructionFetch2 =>
              -- Keep reading bytes if necessary
              if mode_lut(to_integer(read_data))=M_implied
                or mode_lut(to_integer(read_data))=M_accumulator then
                -- 1-byte instruction, process now
                execute_implied_instruction(read_data);
              else
                opcode <= read_data;
                reg_pc <= reg_pc + 1;
                read_instruction_byte(reg_pc,InstructionFetch3);
              end if;
            when InstructionFetch3 =>
              if mode_bytes_lut(mode_lut(to_integer(opcode)))=2 then
                arg1 <= read_data;
                reg_pc <= reg_pc + 1;
                reg_pc_jsr <= reg_pc;     -- keep PC after one operand for JSR
                read_instruction_byte(reg_pc,InstructionFetch4);
              else
                execute_instruction(opcode,read_data,x"00");
              end if;
            when InstructionFetch4 =>
              execute_instruction(opcode,arg1,read_data);
            when BRK1 => push_byte(reg_pc(7 downto 0),BRK2);
            when BRK2 =>
              virtual_reg_p(5) := '1';    -- set B flag in P before pushing
              push_byte(unsigned(virtual_reg_p),VectorRead);
            when PLA1 => reg_a<=with_nz(read_data); state <= InstructionFetch;
            when PLP1 => load_processor_flags(read_data); state <= InstructionFetch;
            when RTI1 => load_processor_flags(read_data); pull_byte(RTI2);
            when RTI2 => reg_pc(15 downto 8) <= read_data; pull_byte(RTI3);
            when RTI3 => reg_pc <= (reg_pc(15 downto 8) & read_data)+1;
                         state<=InstructionFetch;
            when RTS1 => reg_pc(15 downto 8) <= read_data; pull_byte(RTS2);
            when RTS2 => reg_pc <= (reg_pc(15 downto 8) & read_data)+1;
                         state<=InstructionFetch;
            when JSR1 => push_byte(reg_pc_jsr(15 downto 8),InstructionFetch);
            when JMP1 =>
              -- Add a wait state to see if it fixes our problem with not loading
              -- addresses properly for indirect jump
              reg_pc(7 downto 0)<=read_data;
              state <= JMP2;
            when JMP2 =>
              -- Request reading of high byte of vector
              read_data_byte(reg_addr,JMP3);
              -- Store low byte of vector into PCL
              report "read PCL as $" & to_hstring(read_data) severity note;
            when JMP3 =>
              -- Now assemble complete vector
              report "read PCH as $" & to_hstring(read_data) severity note;
              reg_pc(15 downto 8) <= read_data;
              -- And then continue executing from there
              state<=InstructionFetch;
            when IndirectX1 =>
              reg_addr(7 downto 0) <= read_data;
              report "(ZP,x) - low byte = $" & to_hstring(read_data) severity note;
              read_data_byte(reg_addr,IndirectX2);
            when IndirectX2 =>
              reg_addr(15 downto 8) <= read_data;
              report "(ZP,x) - high byte = $" & to_hstring(read_data) severity note;
              report "(ZP,x) - operand address = $"
                & to_hstring(read_data & reg_addr(7 downto 0))
                severity note;
              read_data_byte(read_data & reg_addr(7 downto 0),IndirectX3);
            when IndirectX3 =>
              execute_operand_instruction(reg_instruction,read_data,reg_addr);
            when IndirectY1 =>
              reg_addr(7 downto 0) <= read_data;
              report "(ZP),y - low byte = $" & to_hstring(read_data) severity note;
              read_data_byte(reg_addr,IndirectY2);
            when IndirectY2 =>
              reg_addr <= (read_data & reg_addr(7 downto 0)) + reg_y;
              report "(ZP),y - high byte = $" & to_hstring(read_data) severity note;
              report "(ZP),y - operand address = $"
                & to_hstring((read_data & reg_addr(7 downto 0)) + reg_y)
                severity note;
              read_data_byte((read_data & reg_addr(7 downto 0)) + reg_y,IndirectY3);
            when IndirectY3 =>
              execute_operand_instruction(reg_instruction,read_data,reg_addr);
            when ExecuteDirect =>
              execute_operand_instruction(reg_instruction,read_data,reg_addr);
            when RMWCommit => write_data_byte(reg_addr,reg_value,InstructionFetch);

            when WaitOneCycle => state <= pending_state;
            when others =>
              -- Don't allow CPU to stay stuck
              state<= InstructionFetch;
          end case;
        end if;
      end if;
    end if;
  end process;

  -- purpose: present MMU registers and other stuff to fastio interface
  -- type   : combinational
  -- inputs : ram_bank_registers_read
  -- outputs: fastio_*
  fastio: process (ram_bank_registers_read,fastio_addr,fastio_read)
    variable address : unsigned(19 downto 0) := unsigned(fastio_addr);
    variable rwx : integer := to_integer(address(7 downto 5));
    variable lohi : std_logic := fastio_addr(0);
    variable value : unsigned(15 downto 0);
    variable reg_num : integer := to_integer(address(4 downto 1));
  begin  -- process fastio
    if fastio_read='1' and address(19 downto 8) = x"FC0" then
      case rwx is
        when 0 => value := ram_bank_registers_read(reg_num);
        when 1 => value := ram_bank_registers_read(reg_num);
        when 2 => value := ram_bank_registers_read(reg_num);
        when 6 => value := x"EEE" & irq & irq_pending & nmi & nmi_pending;
        when 7 => value := recent_states(reg_num);
        when others => value := x"F00D";
      end case;
      if lohi='0' then
        fastio_rdata <= std_logic_vector(value(7 downto 0));
      else
        fastio_rdata <= std_logic_vector(value(15 downto 8));
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;
  end process fastio;
end Behavioural;
