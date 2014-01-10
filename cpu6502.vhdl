use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity cpu6502 is
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
    -- Interface to FastRAM in video controller (just 128KB for now)
    ---------------------------------------------------------------------------
    fastram_we : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    fastram_address : OUT STD_LOGIC_VECTOR(13 DOWNTO 0);
    fastram_datain : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    fastram_dataout : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : out std_logic_vector(19 downto 0);
    fastio_read : out std_logic;
    fastio_write : out std_logic;
    fastio_wdata : out std_logic_vector(7 downto 0);
    fastio_rdata : in std_logic_vector(7 downto 0)
    );
  
end cpu6502;

architecture Behavioral of cpu6502 is
  
  type unsigned_array_8 is array(0 to 7) of std_logic_vector(15 downto 0);
  type stdlogic_array_8 is array (natural range <>) of std_logic_vector(7 downto 0);

  -- FastRAM is now hosted in the video controller.
  
  signal iovalue : std_logic_vector(7 downto 0) := x"00";
  
-- CPU RAM bank selection registers.
-- Each 4KB (12 address bits) can be made to point to a section of memory.
-- Sections have 16bit addresses, for a total of 28bits (256MB) of address
-- space.  It also makes it possible to multiple 4KB banks point to the same
-- block of RAM.
  type bank_register_set is array (0 to 15) of std_logic_vector(15 downto 0);
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

  signal nmi_pending : std_logic := '0';
  signal irq_pending : std_logic := '0';
  signal nmi_state : std_logic := '1';
  signal irq_state : std_logic := '1';
  
-- Keep incremented versions of PC around for fast hopping over instructions
-- (note these are not used for instruction fetching, as that code operates
--  differently).
  signal reg_pcplus1 : unsigned(15 downto 0);
  signal reg_pcplus2 : unsigned(15 downto 0);
  
-- When pulling a value from the stack, remember which of the 8 RAM banks it will
-- come from.
  signal pull_bank : unsigned(2 downto 0);

-- Temporary address used in various states
  signal temp_value : std_logic_vector(7 downto 0);
-- Other temporary variables
  signal op_mem_slot : unsigned(2 downto 0);
  signal operand1_mem_slot : unsigned(2 downto 0);
  signal operand2_mem_slot : unsigned(2 downto 0);
  signal vector : std_logic_vector(15 downto 0);

-- Indicate source of operand for instructions
-- Note that ROM is actually implemented using
-- power-on initialised RAM in the FPGA mapped via our io interface.
  signal operand_from_io : std_logic;
  signal operand_from_ram : std_logic;
  signal operand_from_slowram : std_logic;

  -- Small instruction buffer because pulling bytes in from fast ram is
  -- actually not that fast. Well, it is fast in terms of maximum clock
  -- speed, but the combinational logic to arrange and interpret the output
  -- as an instruction.
  -- We won't have to pay the penalty cycle every
  -- instruction because we can buffer several bytes.  We can also top the
  -- buffer up in the background when no other memory access is required.
  -- We can also effectively cache the result of resolving MMU remapping.
  type ibuf is array (0 to 7) of std_logic_vector(7 downto 0);
  signal instruction_buffer : ibuf;
  signal instruction_buffer_count : unsigned(3 downto 0) := x"0";  -- number of bytes loaded in instruction buffer
  signal instruction_fetch_top : unsigned(3 downto 0);  -- number of instruction bytes being fetched this cycle minus 1 (for fastram and slowram that can do multi-byte reads)
  
  type processor_state is (
    -- When CPU first powers up, or reset is bought low
    ResetLow,
    -- States for handling interrupts and reset
    Interrupt,VectorRead,VectorReadIO,VectorLoadPC,
    -- Normal instruction states.  Many states will be skipped
    -- by any given instruction.
    -- When an instruction completes, we move back to InstructionFetch
    InstructionFetch,InstructionFetchFastRam,
    InstructionFetchIO,
    OperandResolve,Calculate,IOWrite,
    -- Special states used for special instructions
    PullA,                                -- PLA
    PullP,                                -- PLP
    RTIPullP,                             -- RTI
    RTSPullPCL,RTSPullPCH,                -- RTS
    JMPIndirectFetch,                     -- JMP absolute indirect
    Halt                                  -- KIL
    );
  signal state : processor_state := ResetLow;  -- start processor in reset state
  signal lohi : std_logic;
  
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
    variable normal_instruction : boolean;

    variable ram_bank : unsigned(2 downto 0);
    variable temp_address : std_logic_vector(15 downto 0);
    variable temp_bank_block : std_logic_vector(15 downto 0);
    variable temp_operand : std_logic_vector(7 downto 0);
    variable temp_operand_address : std_logic_vector(15 downto 0);
    variable long_address : std_logic_vector(27 downto 0);

    variable next_pc : unsigned(15 downto 0);
    
    -- Memory read and write routines assume that they are contention free.
    -- This way, multiple refernces to write_to_long_address() can be made in a single
    -- cycle, provided that they map to different RAM units.

    procedure HWRITE(L:inout LINE; VALUE:in BIT_VECTOR;
    JUSTIFIED:in SIDE := RIGHT; FIELD:in WIDTH := 0) is      
      variable quad: bit_vector(0 to 3);
      constant ne:   integer := value'length/4;
      variable bv:   bit_vector(0 to value'length-1) := value;
      variable s:    string(1 to ne);
    begin
      if value'length mod 4 /= 0 then
        assert FALSE report 
          "HWRITE Error: Trying to read vector " &
          "with an odd (non multiple of 4) length";
        return;
      end if;
      
      for i in 0 to ne-1 loop
        quad := bv(4*i to 4*i+3);
        case quad is
          when x"0" => s(i+1) := '0';
          when x"1" => s(i+1) := '1';
          when x"2" => s(i+1) := '2';
          when x"3" => s(i+1) := '3';
          when x"4" => s(i+1) := '4';
          when x"5" => s(i+1) := '5';
          when x"6" => s(i+1) := '6';
          when x"7" => s(i+1) := '7';
          when x"8" => s(i+1) := '8';
          when x"9" => s(i+1) := '9';
          when x"A" => s(i+1) := 'A';
          when x"B" => s(i+1) := 'B';
          when x"C" => s(i+1) := 'C';
          when x"D" => s(i+1) := 'D';
          when x"E" => s(i+1) := 'E';
          when x"F" => s(i+1) := 'F';
        end case;
      end loop;
      write(L, s, JUSTIFIED, FIELD);
    end HWRITE; 
    
    function to_string(sv: Std_Logic_Vector) return string is
      use Std.TextIO.all;
      
      variable bv: bit_vector(sv'range) := to_bitvector(sv);
      variable lp: line;
    begin
      write(lp, bv);
      return lp.all;
    end;

    function to_hstring(sv: Std_Logic_Vector) return string is
      use Std.TextIO.all;
      
      variable bv: bit_vector(sv'range) := to_bitvector(sv);
      variable lp: line;
    begin
      hwrite(lp, bv);
      return lp.all;
    end;

    impure function fastram_byte (
      n : unsigned(2 downto 0))
      return unsigned is
    begin
      case n is
        when "111" => return unsigned(fastram_dataout(63 downto 56));
        when "110" => return unsigned(fastram_dataout(55 downto 48));
        when "101" => return unsigned(fastram_dataout(47 downto 40));
        when "100" => return unsigned(fastram_dataout(39 downto 32));
        when "011" => return unsigned(fastram_dataout(31 downto 24));
        when "010" => return unsigned(fastram_dataout(23 downto 16));
        when "001" => return unsigned(fastram_dataout(15 downto  8));
        when "000" => return unsigned(fastram_dataout( 7 downto  0));
        when others => return x"FF";
      end case;
    end function fastram_byte;
    
    -- purpose: Convert a 16-bit C64 address to native RAM (or I/O or ROM) address
    function resolve_address_to_long(short_address : std_logic_vector(15 downto 0); ram_bank_registers : bank_register_set)
      return std_logic_vector is 
      variable temp_address : std_logic_vector(27 downto 0);
      variable temp_bank_block : std_logic_vector(15 downto 0);
    begin  -- resolve_long_address
      temp_bank_block :=ram_bank_registers(to_integer(unsigned(short_address(15 downto 12))));
      temp_address(27 downto 12):= temp_bank_block;
      temp_address(11 downto 0):=std_logic_vector(short_address(11 downto 0));

      return temp_address;
    end resolve_address_to_long;
    
    procedure request_read_long_address_from_fastram(long_address : std_logic_vector(27 downto 0)) is
      variable ram_bank : std_logic_vector(2 downto 0);
    begin
      ram_bank := long_address(2 downto 0);
      fastram_address(13 downto 0) <= long_address(16 downto 3);
      -- Clear all read/write lines
      fastram_we <= (others => '0');
    end request_read_long_address_from_fastram;
    
    procedure write_to_long_address(long_address : std_logic_vector(27 downto 0);
                                    value : in std_logic_vector(7 downto 0)) is
      variable ram_bank : std_logic_vector(2 downto 0);
    begin
      if long_address(27 downto 17)="00000000000" then
        -- Write to 128KB FastRAM
        ram_bank := long_address(2 downto 0);
        fastram_address(13 downto 0) <= long_address(16 downto 3);        
        fastram_we <= (others => '0');
        fastram_we(to_integer(unsigned(ram_bank))) <= '1';
      elsif long_address(27 downto 24) = x"F" then
        -- Write to 16MB FastIO space
        null;
      elsif long_address(27 downto 24) = x"8" then
        -- Write to 16MB of SlowRAM
        null;
      end if;
    end procedure write_to_long_address;

    procedure write_to_short_address(short_address : std_logic_vector(15 downto 0);
                                     value : in std_logic_vector(7 downto 0);
                                     ram_bank_registers : bank_register_set) is
      variable long_address : std_logic_vector(27 downto 0);
    begin
      long_address := resolve_address_to_long(short_address,ram_bank_registers);
      write_to_long_address(long_address,value);
    end procedure;
    
    procedure push_byte(value : in std_logic_vector(7 downto 0)) is
      variable push_long_address : std_logic_vector(27 downto 0);
    begin
      -- Stack is page 1, which is in the first 4KB bank of RAM
      push_long_address(27 downto 12) := ram_bank_registers_write(0);
      push_long_address(11 downto 8) := "0001";
      -- Now append stack pointer
      push_long_address(7 downto 0) := std_logic_vector(reg_sp);
      write_to_long_address(push_long_address,value);
      -- decrement stack pointer
      reg_sp <= reg_sp - 1;
    end procedure push_byte;        
    
    procedure pull_byte is
      variable long_address : std_logic_vector(27 downto 0);
    begin
      -- pre-increment SP before using
      -- Stack is page 1, which is in the first 4KB bank of RAM
      -- XXX We should allow the stack to be in slowRAM or fastIO
      long_address(27 downto 12) := ram_bank_registers_read(0);
      long_address(11 downto 8) := "0001";
      -- Now append stack pointer
      long_address(7 downto 0) := std_logic_vector(reg_sp+1);

      request_read_long_address_from_fastram(long_address);
      -- increment SP
      reg_sp <= reg_sp + 1;
      pull_bank <= unsigned(long_address(2 downto 0));
    end procedure pull_byte;
    
    procedure set_cpu_flags_inc (value : in unsigned(7 downto 0)) is
    begin
      if value=x"00" then
        flag_z <='1';
      else
        flag_z <='0';
      end if;
      flag_n <= value(7);
    end procedure set_cpu_flags_inc;

    procedure shift_instruction_buffer_by_count (
      count : in unsigned(6 downto 0)) is
      variable index : integer;
    begin
      if count>=instruction_buffer_count then
        -- We don't have enough bytes to accommodate this shift, so invalidate
        -- buffer entirely.
        instruction_buffer_count <= (others => '0');
        report "invalidating instruction buffer" severity note;
      else
        -- calculate new count of bytes remaining
        instruction_buffer_count <= instruction_buffer_count - count(2 downto 0);
        -- Shift instruction bytes down in buffer
        for i in 0 to 7 loop
          index := i+to_integer(count(2 downto 0));
          if index<8 then
            instruction_buffer(i) <= instruction_buffer(index); 
          end if;
        end loop;  -- i
        report "instruction buffer contents after shift:"
          & " " & to_hstring(instruction_buffer(0))
          & " " & to_hstring(instruction_buffer(1))
          & " " & to_hstring(instruction_buffer(2))
          & " " & to_hstring(instruction_buffer(3))
          & " " & to_hstring(instruction_buffer(4))
          & " " & to_hstring(instruction_buffer(5))
          & " " & to_hstring(instruction_buffer(6))
          & " " & to_hstring(instruction_buffer(7))
          & " (count = " &  integer'image(to_integer(instruction_buffer_count-count(2 downto 0)))
          & ")"
          severity note;
      end if;
    end procedure shift_instruction_buffer_by_count;
    
    procedure advance_pc(value : integer) is
    begin
      next_pc := reg_pc + value;
      report "next pc set to $" & to_hstring(std_logic_vector(next_pc)) severity note;
      reg_pc <= next_pc;
      reg_pcplus1 <= next_pc + 1;
      reg_pcplus2 <= next_pc + 2;
      
      -- Advance instruction buffer
      shift_instruction_buffer_by_count(to_unsigned(value,7));
    end procedure advance_pc;

    procedure set_pc(addr : unsigned(15 downto 0)) is
    begin
      -- Set PC and related meta-registers
      reg_pc <= addr;
      reg_pcplus1 <= addr + 1;
      reg_pcplus2 <= addr + 2;
      next_pc := addr;

      -- Invalidate instruction buffer
      instruction_buffer_count <= "0000";
      
      report "next pc set to $" & to_hstring(std_logic_vector(next_pc)) severity note;
    end procedure set_pc;

    procedure read_indirect_operand (
      address           : std_logic_vector(7 downto 0);
      ram_bank_registers : bank_register_set) is
      variable long_addr : std_logic_vector(27 downto 0);
      variable addr_lo : std_logic_vector(15 downto 0);
      variable addr_hi : std_logic_vector(15 downto 0);
    begin
      -- XXX Disabled indirect operands until reimplmented
      return;
      -- Read indirect zero page operand and leave state so that
      -- instruction executation can continue as though the operand
      -- were direct.  The caller will have already change op_mode
      -- to the appropriate absolute or absolute indexed mode, and
      -- adjusted the address passed in here for any pre-indexing.
      -- XXX Should support ZP being in sources other than fast RAM.
      
--      addr_lo(15 downto 8) := x"00";
--      addr_lo(7 downto 0) := address;
--      long_addr := resolve_address_to_long(addr_lo,ram_bank_registers);
--      operand1_mem_slot <= unsigned(long_addr(2 downto 0));
--      request_read_long_address_from_fastram(long_addr);
      
--      addr_hi(15 downto 8) := x"00";
--      addr_hi(7 downto 0) := std_logic_vector(unsigned(address) + 1);
--      long_addr := resolve_address_to_long(addr_hi,ram_bank_registers);
--      operand2_mem_slot <= unsigned(long_addr(2 downto 0));
--      request_read_long_address_from_fastram(long_addr);        

    end procedure read_indirect_operand;
    
    procedure fetch_next_instruction(pc : unsigned(15 downto 0)) is 
      variable long_pc : std_logic_vector(27 downto 0);
      variable long_pc1 : std_logic_vector(27 downto 0);
      variable long_pc2 : std_logic_vector(27 downto 0);
      variable temp_pc : std_logic_vector(15 downto 0);
      variable fetch_count : unsigned(3 downto 0);
    begin
      if instruction_buffer_count >2 then
        -- We already have enough instructions in the buffer, so nothing more
        -- to do.
        state <= OperandResolve;
      else
        -- Read bytes into the instruction buffer as fast as possible.
        -- For fast ram we can read 8 bytes at once.
        -- For I/O and slow RAM the process is slower, and so we just read
        -- enough bytes for now.
        long_pc := resolve_address_to_long(std_logic_vector(pc+instruction_buffer_count),ram_bank_registers_instructions);
        report "fetch next instruction from long address $" & to_hstring(long_pc) severity note;
      
        if long_pc(27 downto 24) = x"F" then
          -- Fetch is from fast I/O (which is also how ROMs are implemented)
          fastio_addr <= long_pc(19 downto 0);
          fastio_read <= '1';
          fastio_write <= '0';

          -- When executing from IO, we should only read the current instruction,
          -- since the current instruction could cause changes to the IO registers.
          fetch_count := to_unsigned(3-to_integer(instruction_buffer_count),4);
          -- Make sure we don't fetch over an MMU page boundary.
          -- XXX For now just play it safe and only fetch one byte in this
          -- situation.
          if long_pc(11 downto 0)>x"ffd" then
            fetch_count := "0001";
          end if;
          -- reduce by one to make it the top of the range to fetch
          fetch_count := instruction_buffer_count+fetch_count-1;
          instruction_fetch_top <= fetch_count(3 downto 0);
          
          report "fetching instruction bytes from IO" severity note;
        
          state <= InstructionFetchIO;
        elsif long_pc(27 downto 24) > x"7" then
          -- Fetch is from slow RAM
          report "fetching instruction byte from slow RAM unimplemented" severity failure;
        else
          -- If not from elsewhere, fetch from fast RAM.
          -- Fetch only to the end of page, so work out now many bytes
          -- we can read.
          fetch_count := to_unsigned(8,4);
          if long_pc(11 downto 0)>x"ff8" then
            fetch_count := fetch_count - unsigned('0' & long_pc(2 downto 0));
          end if;
          -- XXX But only read upto 8 bytes, so that we can copy into instruction
          -- buffer in phase. If we allowed copying 8 extra bytes it would
          -- complicate the decode logic.          
          if fetch_count>8 then
            fetch_count := x"8";
          end if;
          -- reduce by one to make it the top of the range to fetch
          fetch_count := fetch_count - 1;
          instruction_fetch_top <= fetch_count;
          request_read_long_address_from_fastram(long_pc);
          state <= InstructionFetchFastRam;        

          report "fetching "
            & integer'image(to_integer(fetch_count))
            & "instruction bytes from fast RAM" severity note;
        end if;
      end if;
    end procedure fetch_next_instruction;

    procedure try_prefetch_next_instruction(pc : unsigned(15 downto 0);
                                            last_address_column : unsigned(2 downto 0)) is
      variable column : unsigned(2 downto 0);
    begin
      column := pc(2 downto 0);
      if column = last_address_column 
        or (column+1) = last_address_column
        or (column+2) = last_address_column then
        -- cannot prefetch
        state <= InstructionFetch;
      else
        -- can prefetch
        fetch_next_instruction(pc);
      end if;
    end procedure try_prefetch_next_instruction;
    
    procedure do_direct_operand (
      address           : std_logic_vector(15 downto 0);
      instruction : instruction) is
      variable long_addr : std_logic_vector(27 downto 0);
      variable writeP : boolean;
      variable write_value : std_logic_vector(7 downto 0);
    begin
      -- Fetch the byte at the specified address, and remember the slot it
      -- will be fetched into.
      -- Or, for write instructions, write to the address.

      case instruction is
        when I_STA => writeP:=true; write_value:=std_logic_vector(reg_a);
        when I_STX => writeP:=true; write_value:=std_logic_vector(reg_x);
        when I_STY => writeP:=true; write_value:=std_logic_vector(reg_y);                   
        when others => writeP:=false;
      end case;

      -- In any case, first work out the actual address in question.
      if writeP then
        long_addr := resolve_address_to_long(address,ram_bank_registers_write);
      else
        long_addr := resolve_address_to_long(address,ram_bank_registers_read);
      end if;

      if long_addr(27 downto 24) = x"F" then
        -- To/From fast I/O block
        -- (also used for 8-bit wide ROMs)
        operand_from_io <= '1';
        operand_from_ram <= '0';
        operand_from_slowram <= '0';

        fastio_addr <= long_addr(19 downto 0);
        if writeP then
          fastio_write <= '1';
          fastio_read <= '0';
          fastio_wdata <= write_value;
          -- Can always prefetch here if PC does not map to fastio,
          -- but never if PC does map to fastio
          -- XXX implement PC fastIO check so that we can save a cycle here
          state <= InstructionFetch;
        else
          fastio_write <= '0';
          fastio_read <= '1';
          state <= Calculate;
        end if;

        -- clear any access to fast ram
        fastram_we <= (others => '0');
      elsif long_addr(27 downto 12) > x"8000"
        and long_addr(27 downto 12) < x"9000" then
        -- To/From slow 16MB cellular RAM
        operand_from_io <= '0';
        operand_from_ram <= '0';
        operand_from_slowram <= '1';
      elsif long_addr(27 downto 12) < x"0020" then
        -- To/From from fast RAM
        report "read/write fast RAM at $" & to_hstring(address) severity note;
        operand_from_io <= '0';
        operand_from_ram <= '1';
        operand_from_slowram <= '0';
        operand1_mem_slot <= unsigned(address(2 downto 0));
        if writeP then
          write_to_long_address(long_addr,write_value);
          try_prefetch_next_instruction(next_pc,unsigned(long_addr(2 downto 0)));
        else
          request_read_long_address_from_fastram(long_addr);
          state <= Calculate;
        end if;
        -- Clear any previous access to IO space
        fastio_write <= '0';
        fastio_read <= '0';
      else
        -- Reading from unmapped address space
        -- XXX Trigger a page-fault?
        operand_from_io <= '0';
        operand_from_ram <= '0';
        operand_from_slowram <= '0';
      end if;
    end procedure do_direct_operand;

    -- operand1_mem_slot must already be set before calling
    procedure rmw_operand_commit(
      temp_operand : std_logic_vector(7 downto 0)) is
    begin
      if operand_from_io = '1' then
        -- Operand is from I/O, so need to write back original value
        -- .. then schedule writing of the final result next cycle
        fastio_read <= '0';
        fastio_write <= '1';
        fastio_wdata <= fastio_rdata;
        iovalue <= temp_operand;          
        state <= IOWrite;
      elsif operand_from_ram = '1' then
        -- operand is for fast ram
        fastram_datain <= (others => '0');
        case operand1_mem_slot is
          when "111" => fastram_datain(63 downto 56) <= temp_operand;
          when "110" => fastram_datain(55 downto 48) <= temp_operand;
          when "101" => fastram_datain(47 downto 40) <= temp_operand;
          when "100" => fastram_datain(39 downto 32) <= temp_operand;
          when "011" => fastram_datain(31 downto 24) <= temp_operand;
          when "010" => fastram_datain(23 downto 16) <= temp_operand;
          when "001" => fastram_datain(15 downto  8) <= temp_operand;
          when "000" => fastram_datain( 7 downto  0) <= temp_operand;
          when others => fastram_datain( 7 downto  0) <= temp_operand;
        end case;
        fastram_we <= (others => '0');
        fastram_we(to_integer(operand1_mem_slot)) <= '1';
        state <= InstructionFetch;
      elsif operand_from_slowram = '1' then
        -- Commit to slow ram.
        -- XXX not currently implemented
        state <= InstructionFetch;
      else
        -- commit to unknown memory type/unmapped memory.
        -- Just move along to next instruction
        state <= InstructionFetch;
      end if;
    end procedure rmw_operand_commit;
    
    procedure set_nz (
      value : unsigned(7 downto 0)) is
    begin  -- set_nz
      flag_n <= value(7);
      if value(7 downto 0) = x"00" then
        flag_z <= '1';
      else
        flag_z <= '0';
      end if;
    end set_nz;

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
      set_nz(o);
      if unsigned(o)<unsigned(i1) then
        flag_v <= '1';
        flag_c <= '1';
      else
        flag_v <= '0';
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
        if o<i1 then
          flag_v<='1';
        else
          flag_v<='0';
        end if;

        -- Now do BCD fixup on upper nybl
        if o(7 downto 4)>x"9" then
          o(7 downto 4):=o(7 downto 4)+x"6";
        end if;

        -- Finally set carry flag based on result
        if o<i1 then
          flag_c<='1';
        else
          flag_c<='0';
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
      -- calculate ones-complement
      s2 := not i1;
      -- Then do add.
      -- Z and C should get set correctly.
      -- XXX Will this work for decimal mode?
      o := alu_op_add(i1,s2);
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

    impure function alu_op_and (
      i1 : unsigned(7 downto 0);
      i2 : unsigned(7 downto 0))
      return unsigned is
      variable o : unsigned(7 downto 0);  
    begin  -- alu_op_and
      o := i1 and i2;
      set_nz(o);
      return o;
    end alu_op_and;
    
    impure function alu_op_or (
      i1 : unsigned(7 downto 0);
      i2 : unsigned(7 downto 0))
      return unsigned is
      variable o : unsigned(7 downto 0);  
    begin
      o := i1 or i2;
      set_nz(o);
      return o;
    end alu_op_or;
    
    impure function alu_op_xor (
      i1 : unsigned(7 downto 0);
      i2 : unsigned(7 downto 0))
      return unsigned is
      variable o : unsigned(7 downto 0);  
    begin
      o := i1 xor i2;
      set_nz(o);
      return o;
    end alu_op_xor;
    

    procedure execute_normal_instruction(op_instruction : instruction;
                                         temp_operand : std_logic_vector(7 downto 0)) is
      variable new_value : unsigned(7 downto 0);
    begin
      report "execute instruction with operand $" & to_hstring(temp_operand) severity note;
      case op_instruction is
        when I_ADC =>
          reg_a<=alu_op_add(reg_a,unsigned(temp_operand));
          fetch_next_instruction(next_pc);
        when I_AND => 
          reg_a<=alu_op_and(unsigned(temp_operand),reg_a);
          fetch_next_instruction(next_pc);
        when I_ASL =>
          -- Modify and write back.
          flag_c <= temp_operand(7);
          new_value(7 downto 1) := unsigned(temp_operand(6 downto 0)); 
          new_value(0) := '0';
          set_nz(new_value);
          rmw_operand_commit(std_logic_vector(new_value));
        when I_BIT =>
          set_nz(alu_op_and(unsigned(temp_operand),reg_a));
          flag_n <= temp_operand(7);
          flag_v <= temp_operand(6);
          fetch_next_instruction(next_pc);                
        when I_CMP =>
          set_nz(alu_op_sub(reg_a,unsigned(temp_operand)));
          fetch_next_instruction(next_pc);
        when I_CPX =>
          set_nz(alu_op_sub(reg_x,unsigned(temp_operand)));
          fetch_next_instruction(next_pc);
        when I_CPY =>
          set_nz(alu_op_sub(reg_y,unsigned(temp_operand)));
          fetch_next_instruction(next_pc);
        when I_DEC =>
          -- Modify and write back.
          new_value(7 downto 0) := unsigned(temp_operand(7 downto 0))-1;
          new_value(7) := '0';
          set_nz(new_value);
          rmw_operand_commit(std_logic_vector(new_value));
        when I_EOR =>
          reg_a<=alu_op_xor(reg_a,unsigned(temp_operand));
          fetch_next_instruction(next_pc);
        when I_INC =>
          -- Modify and write back.
          new_value(7 downto 0) := unsigned(temp_operand(7 downto 0))+1;
          new_value(7) := '0';
          set_nz(new_value);
          rmw_operand_commit(std_logic_vector(new_value));
        when I_LDA =>
          reg_a <= unsigned(temp_operand);
          report "set accumulator to $" & to_hstring(temp_operand) severity note;
          set_nz(unsigned(temp_operand));
          fetch_next_instruction(next_pc); 
        when I_LDX =>
          reg_x <= unsigned(temp_operand);
          set_nz(unsigned(temp_operand));
          fetch_next_instruction(next_pc);
        when I_LDY =>
          reg_y <= unsigned(temp_operand);
          set_nz(unsigned(temp_operand));
          fetch_next_instruction(next_pc);
        when I_LSR =>
          -- Modify and write back.
          flag_c <= temp_operand(0);
          new_value(6 downto 0) := unsigned(temp_operand(7 downto 1));
          new_value(7) := '0';
          set_nz(new_value);
          rmw_operand_commit(std_logic_vector(new_value));
        when I_ORA =>
          reg_a<=alu_op_or(reg_a,unsigned(temp_operand));
          fetch_next_instruction(next_pc);
        when I_ROL =>
          -- Modify and write back.
          flag_c <= temp_operand(7);
          new_value(7 downto 1) := unsigned(temp_operand(6 downto 0)); 
          new_value(0) := flag_c;
          set_nz(new_value);
          rmw_operand_commit(std_logic_vector(new_value));
        when I_ROR =>
          -- Modify and write back.
          flag_c <= temp_operand(0);
          new_value(6 downto 0) := unsigned(temp_operand(7 downto 1)); 
          new_value(7) := flag_c;
          set_nz(new_value);          
          rmw_operand_commit(std_logic_vector(new_value));
        when I_SBC =>
          reg_a<=alu_op_sub(reg_a,unsigned(temp_operand));
          fetch_next_instruction(next_pc);
        when others =>
          -- unimplemented/illegal ops do nothing
          fetch_next_instruction(next_pc);
      end case;
    end procedure execute_normal_instruction;
    
    variable temp_sp_addr : std_logic_vector(15 downto 0);
    variable op_instruction : instruction;
    variable op_mode : addressingmode;
    variable opcode_now : std_logic_vector(7 downto 0);

    variable virtual_reg_p : std_logic_vector(7 downto 0);

  begin
    if rising_edge(clock) then
      -- Try to prevent latches on fastio
      fastio_addr <= x"00000";
      fastio_read <= '0';
      fastio_write <= '0';
      fastio_wdata <= x"00";
      
      -- Check for interrupts
      if nmi = '0' and nmi_state = '1' then
        nmi_pending <= '1';        
      end if;
      nmi_state <= nmi;
      if irq = '0' and irq_state = '1' then
        irq_pending <= '1';        
      end if;
      irq_state <= irq;

      -- Generate virtual processor status register for convenience
      virtual_reg_p(7) := flag_n;
      virtual_reg_p(6) := flag_v;
      virtual_reg_p(5) := '1';
      virtual_reg_p(4) := '0';
      virtual_reg_p(3) := flag_d;
      virtual_reg_p(2) := flag_i;
      virtual_reg_p(1) := flag_z;
      virtual_reg_p(0) := flag_c;

      -- Show CPU state for debugging
      -- report "state = " & processor_state'image(state) severity note;
      report ""
        & "  pc=$" & to_hstring(std_logic_vector(reg_pc))
        & ", a=$" & to_hstring(std_logic_vector(reg_a))
        & ", x=$" & to_hstring(std_logic_vector(reg_x))
        & ", y=$" & to_hstring(std_logic_vector(reg_y))
        & ", sp=$" & to_hstring(std_logic_vector(reg_sp))
        & ", p=%" & to_string(std_logic_vector(virtual_reg_p))
        severity note;

      -- Output debug signals
      monitor_opcode <= std_logic_vector(instruction_buffer(0));
      monitor_pc <= std_logic_vector(reg_pc);
      monitor_sp <= std_logic_vector(reg_sp);
      monitor_a <= std_logic_vector(reg_a);
      monitor_x <= std_logic_vector(reg_x);
      monitor_y <= std_logic_vector(reg_y);
      monitor_p <= virtual_reg_p;

      if reset = '0' or state = ResetLow then
        state <= VectorRead;
        vector <= x"FFFC";
        -- reset cpu
        reg_a <= x"AA";
        reg_x <= x"11";
        reg_y <= x"22";
        reg_sp <= x"ff";
        flag_c <= '0';
        flag_d <= '0';
        flag_i <= '1';                -- start with IRQ disabled
        flag_z <= '0';
        flag_n <= '0';
        flag_v <= '0';
        -- Read nothingness from RAM
        fastram_address <= (others => '0');
        fastram_we <= (others => '0');
        -- Reset memory bank registers.
        -- Map first bank of fast RAM at $0000 - $CFFF
        for i in 0 to 12 loop
          ram_bank_registers_read(i)<=std_logic_vector(to_unsigned(i,16));
          ram_bank_registers_write(i)<=std_logic_vector(to_unsigned(i,16));
          ram_bank_registers_instructions(i)<=std_logic_vector(to_unsigned(i,16));
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
      else
        -- act based on state
        case state is
          when Interrupt =>
            -- break instruction. Push state and jump to the appropriate
            -- vector.
            -- XXX requires ZP & stack to be in fast ram.
            temp_sp_addr(15 downto 8) := x"01";
            temp_sp_addr(7 downto 0) := std_logic_vector(reg_sp);
            write_to_short_address(temp_sp_addr,
                                   std_logic_vector(reg_pcplus2(15 downto 8)),
                                   ram_bank_registers_write);
            temp_sp_addr(7 downto 0) := std_logic_vector(reg_sp -1);
            write_to_short_address(temp_sp_addr,
                                   std_logic_vector(reg_pcplus2(7 downto 0)),
                                   ram_bank_registers_write);
            temp_operand(7) := flag_n;
            temp_operand(6) := flag_v;
            temp_operand(5) := '1';  -- unused bit
            temp_operand(4) := '0';  -- BRK flag
            temp_operand(3) := flag_d;
            temp_operand(2) := flag_i;
            temp_operand(1) := flag_z;
            temp_operand(0) := flag_c;
            temp_sp_addr(7 downto 0) := std_logic_vector(reg_sp -2);
            write_to_short_address(temp_sp_addr,
                                   std_logic_vector(temp_operand),
                                   ram_bank_registers_write);
            reg_sp <= reg_sp - 3;
            state <= VectorRead;
          when VectorRead =>
            -- Read PC from vector,vector+1
            -- Reading memory is a bit interesting because we have
            -- to work out which of the 32 memories to read from
            -- However, since we only support the CPU vectors from FFFA-FFFF
            -- we can do this fairly easily by setting all six relevant
            -- memories to read their last cell, and then pick the right one
            -- out in processor_state'VectorLoadPC
            -- The vectors always live in the natural memory locations
            -- 0x000FFFA - 0x000FFF, and ignore bank switching
            if ram_bank_registers_instructions(15)(15 downto 12) = x"F" then
              -- vector is in fast IO (eg ROM)
              report "reading vector from $" & to_hstring(vector) severity note;
              fastio_addr(19 downto 12) <= ram_bank_registers_instructions(15)(15 downto 8);
              fastio_addr(11 downto 1) <= vector(11 downto 1);
              fastio_addr(0) <= '0';
              lohi <= '0';
              fastio_write <= '0';
              fastio_read <= '1';
              state <= VectorReadIO;
            else
              -- Ask for the 64-bits of RAM beginning at $0FFF
              -- (Vectors always load from that PHYSICAL RAM address)
              fastram_address <= "01111111111111";
              fastram_we <= (others => '0');
              state<=VectorLoadPC;
            end if;
          when VectorReadIO =>
            report "read value $" & to_hstring(fastio_rdata) severity note;
            if lohi = '0' then              
              reg_pc(7 downto 0) <= unsigned(fastio_rdata);
              reg_pcplus1(7 downto 0) <= (unsigned(fastio_rdata) +1);
              reg_pcplus2(7 downto 0) <= (unsigned(fastio_rdata) +2);
              lohi <= '1';
              fastio_addr(19 downto 12) <= ram_bank_registers_instructions(15)(15 downto 8);
              fastio_addr(11 downto 1) <= vector(11 downto 1);
              fastio_addr(0) <= '1';
              fastio_read <= '1';
              state <= VectorReadIO;
            else
              reg_pc(15 downto 8) <= unsigned(fastio_rdata);
              if reg_pc(7 downto 0) = x"FF" then
                reg_pcplus1(15 downto 8) <= (unsigned(fastio_rdata) +1);
                reg_pcplus2(15 downto 8) <= (unsigned(fastio_rdata) +1);
              elsif reg_pc(7 downto 0) = x"FE" then
                reg_pcplus1(15 downto 8) <= unsigned(fastio_rdata);
                reg_pcplus2(15 downto 8) <= (unsigned(fastio_rdata) +1);
              else
                reg_pcplus1(15 downto 8) <= unsigned(fastio_rdata);
                reg_pcplus2(15 downto 8) <= unsigned(fastio_rdata);
              end if;
              state <= InstructionFetch;
            end if;
          when VectorLoadPC =>
            case vector is
              when x"FFFA" => temp_address :=  fastram_dataout(31 downto 16);
              when x"FFFC" => temp_address :=  fastram_dataout(47 downto 32);
              when x"FFFE" => temp_address :=  fastram_dataout(63 downto 48);
              when others =>
                -- unknown vector, so use reset vector
                temp_address :=  fastram_dataout(63 downto 48);
            end case;
            reg_pc<=unsigned(temp_address);
            reg_pcplus1<=unsigned(temp_address)+1;
            reg_pcplus2<=unsigned(temp_address)+2;
            -- We have loaded the program counter (and operand addresses
            -- derived from that), so now we can proceed to instruction fetch.
            -- We save one cycle for every interrupt here by doing
            -- the instruction fetch here, and then passing into OperandResolve
            -- next cycle.
            -- Saving a cylce here costs ~16MHz in clock speed:
            -- fetch_next_instruction(unsigned(temp_address));
            -- state <= OperandResolve;
            -- So instead, let's wear the extra cycle and allow for a faster clock:
            state <= InstructionFetch;
          when InstructionFetch =>
            -- Work out which three bytes to fetch.
            -- Probably easiest to do a parallel calculation based on lower
            -- bits of reg_pc, reg_pcplus1, reg_pcplus2
            fetch_next_instruction(reg_pc);
          when InstructionFetchFastRam =>
            -- Reading one or more instruction bytes from fastram into instruction
            -- buffer.
            -- We can't short-cut to instruction execution here, because the whole
            -- point is that reading from the 8x8bit memory system requires a lot
            -- of combinational logic (and routing delay because we are using
            -- almost all of the block RAMs).
            -- instruction_fetch_count indicates the number of bytes we can read
            -- from the program counter onwards.  We may have some bytes in
            -- the buffer already, which we should not overwrite in case they were
            -- fetched from IO.  Now that FastRAM is fixed on a single address
            -- for the 64-bits read, this is no longer an issue, as MMU pages
            -- are 4K aligned, and thus are always 64-bit aligned.
            for i in 0 to 7 loop
              if i>= to_integer(instruction_buffer_count(2 downto 0))
                and i<=to_integer(instruction_fetch_top) then
                ram_bank := reg_pc(2 downto 0) + i;
                instruction_buffer(i)
                  <= fastram_dataout((to_integer(ram_bank)*8+7)
                                     downto to_integer(ram_bank)*8);
              end if;
            end loop;  -- i
            -- Update number of instructions we have fetched
            instruction_buffer_count <= instruction_fetch_top + 1;
            if instruction_fetch_top>2 then
              -- We have enough bytes to execute the next instruction
              state <= OperandResolve;
            else
              -- We don't have enough bytes yet, so fetch some more.
              state <= InstructionFetch;
            end if;
          when InstructionFetchIO =>
            report "instruction from I/O is $" & to_hstring(fastio_rdata) severity note;
            instruction_buffer(to_integer(instruction_buffer_count))
              <= fastio_rdata;
            if ((instruction_buffer_count+1)<3) then
              -- If after this fetch we still don't have enough bytes, then read
              -- the next byte next cycle.
              long_address := resolve_address_to_long(std_logic_vector(reg_pc+instruction_buffer_count+1),ram_bank_registers_instructions);
              fastio_addr <= long_address(19 downto 0);
              fastio_read <= '1';
              fastio_write <= '0';
              state <= InstructionFetchIO;
            else
              -- If on the other hand we have enough bytes, then proceed
              -- to executing the instruction.
              state <= InstructionFetch;
            end if;
            instruction_buffer_count <= instruction_buffer_count +1;
          when OperandResolve =>
            -- Get opcode and operands, or initiate an interrupt
            -- IRQ is level triggered
            if nmi_pending = '1' then
              state <= Interrupt;
              vector <= x"FFFA";
              nmi_pending <= '0';
            elsif irq_pending = '1' and flag_i = '0' then
              flag_i <= '1';
              state <= Interrupt;
              vector <= x"FFFE";
              irq_pending <= '0';
            elsif instruction_buffer_count < x"3" then
              -- Sometimes we need an extra cycle for the instruction buffer
              -- state to propagate, and we miss doing the fetch.  In that
              -- case, we get here, but need to go back to InstructionFetch                                                       
              state <= InstructionFetch;
            else
              -- Now that we are using the instruction buffer, we can simply
              -- grab the first byes of the instruction buffer, and make
              -- instruction execution agnostic of the memory source.
              report "instruction buffer contents after load:"
                & " " & to_hstring(instruction_buffer(0))
                & " " & to_hstring(instruction_buffer(1))
                & " " & to_hstring(instruction_buffer(2))
                & " " & to_hstring(instruction_buffer(3))
                & " " & to_hstring(instruction_buffer(4))
                & " " & to_hstring(instruction_buffer(5))
                & " " & to_hstring(instruction_buffer(6))
                & " " & to_hstring(instruction_buffer(7))
                & " (count = " &  integer'image(to_integer(instruction_fetch_top)+1)
                & ")"
                severity note;

              opcode_now := instruction_buffer(0);
              temp_operand_address(15 downto 8) := instruction_buffer(2);
              temp_operand_address(7 downto 0) := instruction_buffer(1);
              
              -- Lookup instruction and addressing mode
              op_instruction := instruction_lut(to_integer(unsigned(opcode_now)));
              op_mode := mode_lut(to_integer(unsigned(opcode_now)));

              report "op mode=" & addressingmode'image(op_mode) & ", op_address=$" & to_hstring(temp_operand_address) severity note;

              if op_mode=M_implied then
                -- implied mode, handle instruction now, add one to PC, and
                -- go to fetch next instruction
                normal_instruction := true;
                case op_instruction is
                  when I_SETMAP =>
                    -- load RAM map register
                    -- Sets map register $YY to $AAXX
                    -- Registers are:
                    -- $00 - $0F for instruction fetch
                    -- $10 - $1F for memory read
                    -- $20 - $2F for memory write
                    temp_bank_block(15 downto 8) := std_logic_vector(reg_a);
                    temp_bank_block(7 downto 0) := std_logic_vector(reg_x);
                    if reg_y(7 downto 4) = x"0" then
                      ram_bank_registers_instructions(to_integer(reg_y(3 downto 0)))
                        <= temp_bank_block;
                    elsif reg_y(7 downto 4) = x"1" then
                      ram_bank_registers_read(to_integer(reg_y(3 downto 0)))
                        <= temp_bank_block;
                    elsif reg_y(7 downto 4) = x"2" then
                      ram_bank_registers_write(to_integer(reg_y(3 downto 0)))
                        <= temp_bank_block;
                    end if;
                  when I_BRK =>
                    -- break instruction. Push state and jump to the appropriate
                    -- vector.
                    temp_sp_addr(15 downto 8) := x"01";
                    temp_sp_addr(7 downto 0) := std_logic_vector(reg_sp);
                    write_to_short_address(temp_sp_addr,
                                           std_logic_vector(reg_pcplus2(15 downto 8)),
                                           ram_bank_registers_write);
                    temp_sp_addr(7 downto 0) := std_logic_vector(reg_sp -1);
                    write_to_short_address(temp_sp_addr,
                                           std_logic_vector(reg_pcplus2(7 downto 0)),
                                           ram_bank_registers_write);
                    temp_operand(7) := flag_n;
                    temp_operand(6) := flag_v;
                    temp_operand(5) := '1';  -- unused bit
                    temp_operand(4) := '1';  -- BRK flag
                    temp_operand(3) := flag_d;
                    temp_operand(2) := flag_i;
                    temp_operand(1) := flag_z;
                    temp_operand(0) := flag_c;
                    temp_sp_addr(7 downto 0) := std_logic_vector(reg_sp -2);
                    write_to_short_address(temp_sp_addr,
                                           std_logic_vector(temp_operand),
                                           ram_bank_registers_write);
                    reg_sp <= reg_sp - 3;
                    vector <= x"FFFE";    -- BRK follows the IRQ vector
                    flag_i <= '1';      -- Disable further IRQs while the
                                        -- interrupt is being handled.
                    state <= VectorRead;
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
                  when I_NOP => null;
                  when I_PHA =>
                    push_byte(std_logic_vector(reg_a));
                    advance_pc(1);
                    normal_instruction := false;
                    state <= InstructionFetch;
                  when I_PHP =>
                    temp_operand(7) := flag_n;
                    temp_operand(6) := flag_v;
                    temp_operand(5) := '1';  -- unused bit
                    temp_operand(4) := '0';  -- BRK flag
                    temp_operand(3) := flag_d;
                    temp_operand(2) := flag_i;
                    temp_operand(1) := flag_z;
                    temp_operand(0) := flag_c;
                    push_byte(temp_operand);
                    advance_pc(1);
                    normal_instruction := false;
                    state <= InstructionFetch;
                  when I_PLA =>
                    pull_byte;
                    state <= PullA;
                    advance_pc(1);
                    normal_instruction := false;
                  when I_PLP =>
                    pull_byte;
                    state <= PullP;
                    advance_pc(1);
                    normal_instruction := false;
                  when I_RTI =>
                    pull_byte;
                    state <= RTIPullP;
                    normal_instruction := false;
                  when I_RTS =>
                    pull_byte;
                    reg_sp <= reg_sp + 2;
                    state <= RTSPullPCL;
                    normal_instruction := false;
                  when I_SEC => flag_c <= '1';
                  when I_SED => flag_d <= '1';
                  when I_SEI => flag_i <= '1';
                  when I_TAX => reg_x <= reg_a;
                  when I_TAY => reg_y <= reg_a;
                  when I_TSX => reg_x <= reg_sp;
                  when I_TXA => reg_a <= reg_x;
                  when I_TXS => reg_sp <= reg_x;
                  when I_TYA => reg_a <= reg_a;
                  when others => null;
                                 -- unsupported instruction, just advance PC
                end case;
                if normal_instruction=true then
                  -- advance PC to next instruction, and fetch it.
                  -- We can actually pre-fetch the instruction and
                  -- bypass going through InstructionFetch.
                  -- This will result in implied mode instructions that don't
                  -- touch the stack taking only one cycle.
                  fetch_next_instruction(reg_pcplus1);
                end if;
              elsif op_mode=M_relative then
                -- a relative branch, work out whether to take the branch
                -- and act accordingly. We don't need to do anything further
                if (op_instruction=I_BCC and flag_c='0')
                  or (op_instruction=I_BCS and flag_c='1')
                  or (op_instruction=I_BVC and flag_v='0')
                  or (op_instruction=I_BVS and flag_v='1')
                  or (op_instruction=I_BEQ and flag_z='0')
                  or (op_instruction=I_BNE and flag_z='1') then
                  -- take branch
                  if temp_operand_address(7)='0' then
                    -- branch forwards. Add two to address because this is a two
                    -- byte instruction
                    reg_pc <= reg_pcplus2 + unsigned(temp_operand_address(6 downto 0));
                    -- Shift instruction buffer accordingly.
                    -- (For short forward branches we might be able to keep a few
                    -- instruction bytes. But don't forget to add 2 bytes for the
                    -- instruction length).
                    shift_instruction_buffer_by_count("0010"+unsigned(temp_operand_address(6 downto 0)));
                  else
                    -- branch backwards.
                    reg_pc <= reg_pcplus2 - 128 + unsigned(not temp_operand_address(6 downto 0));
                    -- Invalidate instruction buffer
                    -- (When branching backwards we have no way to preserve bytes
                    -- in the instruction buffer yet).
                    instruction_buffer_count <= (others => '0');
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
                -- JMP and JSR require special treatment
              elsif op_instruction=I_JSR then
                -- Push both operands, bump SP and set PC all in one
                -- cycle.
                -- We push (pc+2) since we have not yet incremented it, but
                -- not (pc+3) because RTS adds one to the popped value.
                -- (actually this means that JSR and BRK can use the same logic for
                -- pushing the programme counter
                temp_sp_addr(15 downto 8) := x"01";
                temp_sp_addr(7 downto 0) := std_logic_vector(reg_sp);
                write_to_short_address(temp_sp_addr,
                                       std_logic_vector(reg_pcplus2(15 downto 8)),
                                       ram_bank_registers_write);
                temp_sp_addr(7 downto 0) := std_logic_vector(reg_sp -1);
                write_to_short_address(temp_sp_addr,
                                       std_logic_vector(reg_pcplus2(7 downto 0)),
                                       ram_bank_registers_write);
                reg_sp <= reg_sp - 2;
                set_pc(unsigned(temp_operand_address));
                fetch_next_instruction(unsigned(temp_operand_address));
              elsif op_instruction=I_JMP and op_mode=M_absolute then
                -- JMP absolute mode: very simple, just overwrite the
                -- programme counter.
                set_pc(unsigned(temp_operand_address));
                fetch_next_instruction(unsigned(temp_operand_address));
              elsif op_instruction=I_JMP and op_mode=M_indirect then
                -- JMP indirect absolute.
                -- Fetch the two bytes, and then do the jump next cycle
                -- We can use fetch_next_instruction to do this for us
                -- (although it will read the byte before as a pretend
                --  opcode).
                -- XXX Will not work from I/O or slow RAM
                report "JMP (indirect) needs to be modified to work with I/O & slow RAM" severity failure;
                fetch_next_instruction(unsigned(temp_operand_address)-1);
                state <= JMPIndirectFetch;
              elsif op_mode=M_accumulator then
                -- accumulator mode, so no need to read from memory
                -- There are only four accumulator mode instructions that do anything.
                -- They are all bit shifting operations.
                -- There are also four NOPs
                -- We handle the accumulator mode instructions as a special case
                -- basically because we can execute them faster (in 1 cycle) that
                -- way.  The memory based versions will take 3 cycles since they
                -- need to read and write a memory location.
                if op_instruction = I_ASL or op_instruction = I_ROL then
                  -- shift left
                  temp_operand(7 downto 1) := std_logic_vector(reg_a(6 downto 0));
                  if op_instruction = I_ROL then
                    temp_operand(0) := flag_c;
                  else
                    temp_operand(0) := '0';
                  end if;
                  flag_c <= reg_a(7);
                end if;
                if op_instruction = I_LSR or op_instruction = I_ROR then
                  -- shift right
                  temp_operand(6 downto 0) := std_logic_vector(reg_a(7 downto 1));
                  if op_instruction = I_ROR then
                    temp_operand(7) := flag_c;
                  else
                    temp_operand(7) := '0';
                  end if;
                  flag_c <= reg_a(0);
                end if;
                if op_instruction = I_NOP then
                  null;
                else
                  flag_n <= temp_operand(7);
                  if temp_operand = x"00" then
                    flag_z <= '1';
                  else
                    flag_z <= '0';
                  end if;
                  reg_a <= unsigned(temp_operand);
                  flag_n <= temp_operand(6);
                end if;
                fetch_next_instruction(reg_pcplus1);
                state <= OperandResolve;
              elsif op_mode=M_immediate then
                advance_pc(2);
                report "calculating result of "
                  & instruction'image(op_instruction) & " "
                  & addressingmode'image(op_mode)
                  & " $" & to_hstring(temp_operand_address)
                  severity note;
                execute_normal_instruction(op_instruction,temp_operand_address(7 downto 0));
              elsif op_mode=M_zeropage then
                temp_address(7 downto 0) := temp_operand_address(7 downto 0);
                temp_address(15 downto 8) := "00000000";
                advance_pc(2);
                do_direct_operand(temp_address,op_instruction);
              elsif op_mode=M_zeropageX then
                temp_address(7 downto 0) := std_logic_vector(unsigned(temp_operand_address(7 downto 0)) + unsigned(reg_x));
                temp_address(15 downto 8) := "00000000";
                advance_pc(2);
                do_direct_operand(temp_address,op_instruction);
              elsif op_mode=M_zeropageY then
                temp_address(7 downto 0) := std_logic_vector(unsigned(temp_operand_address(7 downto 0)) + unsigned(reg_y));
                temp_address(15 downto 8) := "00000000";
                advance_pc(2);
                do_direct_operand(temp_address,op_instruction);
              elsif op_mode=M_absolute then
                temp_address(15 downto 0) := temp_operand_address;
                advance_pc(3);
                do_direct_operand(temp_address,op_instruction);
              elsif op_mode=M_absoluteX then
                temp_address(15 downto 0) := std_logic_vector(unsigned(temp_operand_address) + unsigned(reg_x));
                advance_pc(3);
                do_direct_operand(temp_address,op_instruction);
              elsif op_mode=M_absoluteY then
                temp_address(15 downto 0) := std_logic_vector(unsigned(temp_operand_address) + unsigned(reg_y));
                advance_pc(3);
                do_direct_operand(temp_address,op_instruction);
              elsif op_mode=M_indirectX then
                -- Pre-indexed ZP indirect, wrapping from $FF to $00, not $100
                -- if operand+X=$FF
                temp_address(7 downto 0) := std_logic_vector(unsigned(temp_operand_address(7 downto 0)) + reg_x);
                advance_pc(2);
                read_indirect_operand(temp_address(7 downto 0),ram_bank_registers_read);
                -- turn (indirect,X) into absolute addressing mode
                -- XXX Relies on addressing mode structure of 6502 opcode table
                instruction_buffer(0)(3 downto 0) <= x"d";
                state <= OperandResolve;
              elsif op_mode=M_indirectY then
                -- Post-indexed ZP indirect, wrapping from $FF to $00, not $100
                -- if operand=$FF
                temp_address(7 downto 0) := temp_operand_address(7 downto 0);
                advance_pc(2);
                read_indirect_operand(temp_address(7 downto 0),ram_bank_registers_read);
                -- turn (indirect),Y into absolute,Y addressing mode
                -- XXX Relies on addressing mode structure of 6502 opcode table
                instruction_buffer(0)(3) <= '1';
                state <= OperandResolve;
              end if;
            end if;
          when Calculate =>
            -- This is an instruction that operates on a byte fetched from memory.
            -- We do need to grab the byte from the appropriate memory type.
            assert not (op_mode = M_immediate) report "Immediate mode should not get passed here" severity failure;
            if operand_from_io = '1' then
              -- XXX I/O currently not wired in, so just read all ones for now
              report "read operand from io as $" & to_hstring(temp_value) severity note;
              temp_operand := temp_value;
            elsif operand_from_slowram = '1' then
              -- Memory read from slow RAM.  We assume here that the slow RAM has
              -- finished the read cycle before we get here.  This means that
              -- do_direct_operand() has to manage the state machine so that the
              -- processor stalls while reading from slow RAM.
              -- XXX Not yet implemented.
              temp_operand := x"FF";
            elsif operand_from_ram = '1' then
              -- Memory read from fast RAM.
              temp_operand := fastram_dataout(to_integer(operand1_mem_slot)*8+7
                                              downto to_integer(operand1_mem_slot)*8);
            else
              -- Read is from somewhere else, possibly an unmapped address
              temp_operand := x"FF";
              report "read operand value from unmapped memory" severity warning;
            end if;
            -- Use ALU and progress instruction
            report "calculating result of "
              & instruction'image(op_instruction) & " "
              & addressingmode'image(op_mode)
              & " $" & to_hstring(temp_operand_address)
              severity note;
            execute_normal_instruction(op_instruction,temp_operand);
          when IOWrite =>
            -- Write back value, then fetch instruction next cycle.
            -- NOTE: Assumes fastio_addr has already been set. Only used in
            -- Calculate state for Read-Modify-Write instructions for writing
            -- back the final value.
            -- XXX We could feasibly prefetch here, but then it would be
            -- harder to clear fastio_write immediately, and would also
            -- make life trickier when the instruction will be fetched from
            -- IO/ROM space.
            fastio_wdata <= iovalue;
            fastio_write <= '1';
            fastio_read <= '0';
            state <= InstructionFetch;
          when JMPIndirectFetch =>
            -- Fetched indirect address, so copy it into the programme counter
            set_pc(unsigned(temp_operand_address));
            fetch_next_instruction(unsigned(temp_operand_address));
            state <= OperandResolve;
          when PullA =>
            -- PLA - Pull Accumulator from the stack
            -- In the previous cycle we asked for the byte to be read from
            -- the stack.
            reg_a <= fastram_byte(pull_bank);
            fetch_next_instruction(reg_pcplus1);
            state <= OperandResolve;
          when PullP =>
            -- PLA - Pull Accumulator from the stack
            -- In the previous cycle we asked for the byte to be read from
            -- the stack.
            temp_operand := std_logic_vector(fastram_byte(pull_bank));
            flag_n <= temp_operand(7);
            flag_v <= temp_operand(6);
            flag_d <= temp_operand(3);
            flag_i <= temp_operand(2);
            flag_z <= temp_operand(1);
            flag_c <= temp_operand(0);
            fetch_next_instruction(reg_pcplus1);
            state <= OperandResolve;
          when RTIPullP =>
            -- All values needed have been read in one go
            temp_operand := std_logic_vector(fastram_byte(pull_bank));
            flag_n <= temp_operand(7);
            flag_v <= temp_operand(6);
            flag_d <= temp_operand(3);
            flag_i <= temp_operand(2);
            flag_z <= temp_operand(1);
            flag_c <= temp_operand(0);
            pull_byte;
            state <= RTSPullPCL;
          when RTSPullPCL =>
            temp_operand := std_logic_vector(fastram_byte(pull_bank));
            reg_pc(7 downto 0) <= unsigned(temp_operand)+1;
            pull_byte;            
            state <= RTSPullPCH;
          when RTSPullPCH =>
            -- All values needed have been read in one go
            temp_operand := std_logic_vector(fastram_byte(pull_bank));
            if reg_pc(7 downto 0) = x"00" then
              reg_pc(15 downto 8) <= unsigned(temp_operand)+1;
            else
              reg_pc(15 downto 8) <= unsigned(temp_operand);              
            end if;
            state <= InstructionFetch;
          when others => null;
        end case;
      end if;
    end if;
  end process;
end Behavioral;
