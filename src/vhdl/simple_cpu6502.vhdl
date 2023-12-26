
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.victypes.all;

entity cpu6502 is 
  port (
    address : buffer unsigned(15 downto 0);
    address_next : out unsigned(15 downto 0);
    clk : in std_logic;
    cpu_int : out std_logic;
    cpu_state_o : out unsigned(7 downto 0);
    data_i : in unsigned(7 downto 0);
    data_o : out unsigned(7 downto 0);
    data_o_next : out unsigned(7 downto 0);
    irq : in std_logic;
    nmi : in std_logic;
    ready : in std_logic;
    reset : in std_logic;
    sync : buffer std_logic;
    t : out unsigned(2 downto 0);
    write_n : out std_logic;
    write_next : buffer std_logic
    );
end entity cpu6502;

architecture vapourware of cpu6502 is

  constant instruction_lut : ilut8bit := (

    -- 6502 personality
    -- MAP is not available here. To MAP from 6502 mode, you have to first
    -- enable 4502 mode by switching VIC-III/IV IO mode from VIC-II.
    I_BRK,I_ORA,I_KIL,I_SLO,I_NOP,I_ORA,I_ASL,I_SLO,I_PHP,I_ORA,I_ASL,I_ANC,I_NOP,I_ORA,I_ASL,I_SLO,
    I_BPL,I_ORA,I_KIL,I_SLO,I_NOP,I_ORA,I_ASL,I_SLO,I_CLC,I_ORA,I_NOP,I_SLO,I_NOP,I_ORA,I_ASL,I_SLO,
    I_JSR,I_AND,I_KIL,I_RLA,I_BIT,I_AND,I_ROL,I_RLA,I_PLP,I_AND,I_ROL,I_ANC,I_BIT,I_AND,I_ROL,I_RLA,
    I_BMI,I_AND,I_KIL,I_RLA,I_NOP,I_AND,I_ROL,I_RLA,I_SEC,I_AND,I_NOP,I_RLA,I_NOP,I_AND,I_ROL,I_RLA,
    I_RTI,I_EOR,I_KIL,I_SRE,I_NOP,I_EOR,I_LSR,I_SRE,I_PHA,I_EOR,I_LSR,I_ALR,I_JMP,I_EOR,I_LSR,I_SRE,
    I_BVC,I_EOR,I_KIL,I_SRE,I_NOP,I_EOR,I_LSR,I_SRE,I_CLI,I_EOR,I_NOP,I_SRE,I_NOP,I_EOR,I_LSR,I_SRE,
    I_RTS,I_ADC,I_KIL,I_RRA,I_NOP,I_ADC,I_ROR,I_RRA,I_PLA,I_ADC,I_ROR,I_ARR,I_JMP,I_ADC,I_ROR,I_RRA,
    I_BVS,I_ADC,I_KIL,I_RRA,I_NOP,I_ADC,I_ROR,I_RRA,I_SEI,I_ADC,I_NOP,I_RRA,I_NOP,I_ADC,I_ROR,I_RRA,
    I_NOP,I_STA,I_NOP,I_SAX,I_STY,I_STA,I_STX,I_SAX,I_DEY,I_NOP,I_TXA,I_XAA,I_STY,I_STA,I_STX,I_SAX,
    I_BCC,I_STA,I_KIL,I_AHX,I_STY,I_STA,I_STX,I_SAX,I_TYA,I_STA,I_TXS,I_TAS,I_SHY,I_STA,I_SHX,I_AHX,
    I_LDY,I_LDA,I_LDX,I_LAX,I_LDY,I_LDA,I_LDX,I_LAX,I_TAY,I_LDA,I_TAX,I_LAX,I_LDY,I_LDA,I_LDX,I_LAX,
    I_BCS,I_LDA,I_KIL,I_LAX,I_LDY,I_LDA,I_LDX,I_LAX,I_CLV,I_LDA,I_TSX,I_LAS,I_LDY,I_LDA,I_LDX,I_LAX,
    I_CPY,I_CMP,I_NOP,I_DCP,I_CPY,I_CMP,I_DEC,I_DCP,I_INY,I_CMP,I_DEX,I_AXS,I_CPY,I_CMP,I_DEC,I_DCP,
    I_BNE,I_CMP,I_KIL,I_DCP,I_NOP,I_CMP,I_DEC,I_DCP,I_CLD,I_CMP,I_NOP,I_DCP,I_NOP,I_CMP,I_DEC,I_DCP,
    I_CPX,I_SBC,I_NOP,I_ISC,I_CPX,I_SBC,I_INC,I_ISC,I_INX,I_SBC,I_NOP,I_SBC,I_CPX,I_SBC,I_INC,I_ISC,
    I_BEQ,I_SBC,I_KIL,I_ISC,I_NOP,I_SBC,I_INC,I_ISC,I_SED,I_SBC,I_NOP,I_ISC,I_NOP,I_SBC,I_INC,I_ISC
    );

  type mlut8bit is array(0 to 255) of addressingmode;
  constant mode_lut : mlut8bit := (
    -- 6502 personality
    M_impl,  M_InnX,  M_impl,  M_InnX,  M_nn,    M_nn,    M_nn,    M_nn,
    M_impl,  M_immnn, M_impl,  M_immnn, M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,
    M_rr,    M_InnY,  M_impl,  M_InnY,  M_nnX,   M_nnX,   M_nnX,   M_nnX,
    M_impl,  M_nnnnY, M_impl,  M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX,
    M_nnnn,  M_InnX,  M_impl,  M_InnX,  M_nn,    M_nn,    M_nn,    M_nn,
    M_impl,  M_immnn, M_impl,  M_immnn, M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,
    M_rr,    M_InnY,  M_impl,  M_InnY,  M_nnX,   M_nnX,   M_nnX,   M_nnX,
    M_impl,  M_nnnnY, M_impl,  M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX,
    M_impl,  M_InnX,  M_impl,  M_InnX,  M_nn,    M_nn,    M_nn,    M_nn,
    M_impl,  M_immnn, M_impl,  M_immnn, M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,
    M_rr,    M_InnY,  M_impl,  M_InnY,  M_nnX,   M_nnX,   M_nnX,   M_nnX,
    M_impl,  M_nnnnY, M_impl,  M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX,
    M_impl,  M_InnX,  M_impl,  M_InnX,  M_nn,    M_nn,    M_nn,    M_nn,
    M_impl,  M_immnn, M_impl,  M_immnn, M_Innnn, M_nnnn,  M_nnnn,  M_nnnn,
    M_rr,    M_InnY,  M_impl,  M_InnY,  M_nnX,   M_nnX,   M_nnX,   M_nnX,
    M_impl,  M_nnnnY, M_impl,  M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX,
    M_immnn, M_InnX,  M_immnn, M_InnX,  M_nn,    M_nn,    M_nn,    M_nn,
    M_impl,  M_immnn, M_impl,  M_immnn, M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,
    M_rr,    M_InnY,  M_impl,  M_InnY,  M_nnX,   M_nnX,   M_nnY,   M_nnY,
    M_impl,  M_nnnnY, M_impl,  M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnY, M_nnnnY,
    M_immnn, M_InnX,  M_immnn, M_InnX,  M_nn,    M_nn,    M_nn,    M_nn,
    M_impl,  M_immnn, M_impl,  M_immnn, M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,
    M_rr,    M_InnY,  M_impl,  M_InnY,  M_nnX,   M_nnX,   M_nnY,   M_nnY,
    M_impl,  M_nnnnY, M_impl,  M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnY, M_nnnnY,
    M_immnn, M_InnX,  M_immnn, M_InnX,  M_nn,    M_nn,    M_nn,    M_nn,
    M_impl,  M_immnn, M_impl,  M_immnn, M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,
    M_rr,    M_InnY,  M_impl,  M_InnY,  M_nnX,   M_nnX,   M_nnX,   M_nnX,
    M_impl,  M_nnnnY, M_impl,  M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX,
    M_immnn, M_InnX,  M_immnn, M_InnX,  M_nn,    M_nn,    M_nn,    M_nn,
    M_impl,  M_immnn, M_impl,  M_immnn, M_nnnn,  M_nnnn,  M_nnnn,  M_nnnn,
    M_rr,    M_InnY,  M_impl,  M_InnY,  M_nnX,   M_nnX,   M_nnX,   M_nnX,
    M_impl,  M_nnnnY, M_impl,  M_nnnnY, M_nnnnX, M_nnnnX, M_nnnnX, M_nnnnX);    

  type cpu_state_t is (
    poreset,
    interrupt,
    interrupt_push_pcl,
    interrupt_push_p,
    interrupt_vector_fetch,
    vector0,
    vector1,
    opcode_fetch,
    idecode,
    byte2_fetch,
    byte3_fetch,
    jmp_vector,
    jmp_vector2,
    load,
    store,
    jsrhi,
    rmw_commit,
    rti,
    rti2,
    rti3,
    rts,
    rts2,
    izp,
    izp2,
    pull
    );

  signal cpu_state : cpu_state_t := poreset;
  
  signal reg_pc : unsigned(15 downto 0) := x"FFFC";
  signal reg_a : unsigned(7 downto 0) := x"00";
  signal reg_x : unsigned(7 downto 0) := x"00";
  signal reg_y : unsigned(7 downto 0) := x"00";
  signal reg_sp : unsigned(7 downto 0) := x"00";
  signal flag_z : std_logic := '0';
  signal flag_d : std_logic := '0';
  signal flag_c : std_logic := '0';
  signal flag_i : std_logic := '0';
  signal flag_v : std_logic := '0';    
  signal flag_n : std_logic := '0';    

  signal nmi_pending : std_logic := '0';
  signal last_nmi : std_logic := '1';
  signal reg_mode : addressingmode := M_IMPL;
  signal reg_opcode : unsigned(7 downto 0) := x"00";
  signal reg_instruction : instruction := I_NOP;

  signal reg_addr : unsigned(15 downto 0) := to_unsigned(0,16);
  signal reg_x_dec : unsigned(7 downto 0);
  signal reg_y_dec : unsigned(7 downto 0);
  signal reg_x_inc : unsigned(7 downto 0);
  signal reg_y_inc : unsigned(7 downto 0);
  signal reg_addr_x : unsigned(8 downto 0);
  signal reg_addr_y : unsigned(8 downto 0);

  signal reg_data : unsigned(7 downto 0) := x"00";

  signal instruction_counter : integer := 0;

begin
  process (clk) is

    variable virt_flags : unsigned(7 downto 0);
    variable branch_addr : unsigned(15 downto 0);
    variable alu_and : unsigned(7 downto 0);
    variable alu_ora : unsigned(7 downto 0);
    variable alu_eor : unsigned(7 downto 0);
    variable sp_dec : unsigned(7 downto 0);
    variable sp_inc : unsigned(7 downto 0);
    variable add_result : unsigned(11 downto 0);
    
    procedure set_nz(d : unsigned(7 downto 0)) is
    begin
      flag_n <= d(7);
      if d = x"00" then
        flag_z <= '1';
      else
        flag_z <= '0';
      end if;
    end procedure;

    procedure take_branch is
    begin
      report "Taking branch to $" & to_hexstring(branch_addr);
      reg_pc <= branch_addr;
      cpu_state <= opcode_fetch;
    end procedure;

    procedure alu_op_cmp (
      i1 : in unsigned(7 downto 0);
      i2 : in unsigned(7 downto 0)) is
      variable result : unsigned(8 downto 0) := to_unsigned(0,9);
    begin
      result := ("0"&i1) - ("0"&i2);
      flag_z <= '0'; flag_c <= '0';
      if result(7 downto 0)=x"00" then
        flag_z <= '1';
      end if;
      if result(8)='0' then
        flag_c <= '1';
      end if;
      flag_n <= result(7);
    end alu_op_cmp;

    impure function alu_op_add (
      i1 : in unsigned(7 downto 0);
      i2 : in unsigned(7 downto 0)) return unsigned is
      -- Result is NVZC<8bit result>
      variable tmp : unsigned(11 downto 0) := x"000";
    begin
      if flag_d='1' then
        tmp(8) := '0';
        tmp(7 downto 0) := (i1 and x"0f") + (i2 and x"0f") + ("0000000" & flag_c);
        
        if tmp(7 downto 0) > x"09" then
          tmp(7 downto 0) := tmp(7 downto 0) + x"06";
        end if;
        if tmp(7 downto 0) < x"10" then
          tmp(8 downto 0) := '0'&(tmp(7 downto 0) and x"0f")
                             + to_integer(i1 and x"f0") + to_integer(i2 and x"f0");
        else
          tmp(8 downto 0) := '0'&(tmp(7 downto 0) and x"0f")
                             + to_integer(i1 and x"f0") + to_integer(i2 and x"f0")
                             + 16;
        end if;
        if (i1 + i2 + ( "0000000" & flag_c )) = x"00" then
          report "add result SET Z";
          tmp(9) := '1'; -- Z flag
        else
          report "add result CLEAR Z (result=$"
            & to_hexstring((i1 + i2 + ( "0000000" & flag_c )));
          tmp(9) := '0'; -- Z flag
        end if;
        tmp(11) := tmp(7); -- N flag
        tmp(10) := (i1(7) xor tmp(7)) and (not (i1(7) xor i2(7))); -- V flag
        if tmp(8 downto 4) > "01001" then
          tmp(7 downto 0) := tmp(7 downto 0) + x"60";
          tmp(8) := '1'; -- C flag
        end if;
      -- flag_c <= tmp(8);
      else
        tmp(8 downto 0) := ("0"&i2)
                           + ("0"&i1)
                           + ("00000000"&flag_c);
        tmp(7 downto 0) := tmp(7 downto 0);
        tmp(11) := tmp(7); -- N flag
        if (tmp(7 downto 0) = x"00") then
          tmp(9) := '1';
        else tmp(9) := '0'; -- Z flag
        end if;
        tmp(10) := (not (i1(7) xor i2(7))) and (i1(7) xor tmp(7)); -- V flag
      -- flag_c <= tmp(8);
      end if;

      -- Return final value
      --report "add result of "
      --  & "$" & to_hexstring(std_logic_vector(i1)) 
      --  & " + "
      --  & "$" & to_hexstring(std_logic_vector(i2)) 
      --  & " + "
      --  & "$" & std_logic'image(flag_c)
      --  & " = " & to_hexstring(std_logic_vector(tmp(7 downto 0))) severity note;
      return tmp;
    end function alu_op_add;

    impure function alu_op_sub (
      i1 : in unsigned(7 downto 0);
      i2 : in unsigned(7 downto 0)) return unsigned is
      variable tmp : unsigned(11 downto 0) := x"000"; -- NVZC+8bit result
      variable tmpd : unsigned(8 downto 0) := "000000000";
    begin
      tmp(8 downto 0) := ("0"&i1) - ("0"&i2)
                         - "000000001" + ("00000000"&flag_c);
      tmp(8) := not tmp(8); -- Carry flag
      tmp(10) := (i1(7) xor tmp(7)) and (i1(7) xor i2(7)); -- Overflowflag
      tmp(7 downto 0) := tmp(7 downto 0);
      tmp(11) := tmp(7); -- Negative flag
      if tmp(7 downto 0) = x"00" then
        tmp(9) := '1';
      else
        tmp(9) := '0';  -- Zero flag
      end if;
      if flag_d='1' then
        tmpd := (("00000"&i1(3 downto 0)) - ("00000"&i2(3 downto 0)))
                - "000000001" + ("00000000" & flag_c);

        if tmpd(4)='1' then
          tmpd(3 downto 0) := tmpd(3 downto 0)-x"6";
          tmpd(8 downto 4) := ("0"&i1(7 downto 4)) - ("0"&i2(7 downto 4)) - "00001";
        else
          tmpd(8 downto 4) := ("0"&i1(7 downto 4)) - ("0"&i2(7 downto 4));
        end if;
        if tmpd(8)='1' then
          tmpd(8 downto 0) := tmpd(8 downto 0) - ("0"&x"60");
        end if;
        tmp(7 downto 0) := tmpd(7 downto 0);
      end if;
                                        -- Return final value
                                        --report "subtraction result of "
                                        --  & "$" & to_hexstring(std_logic_vector(i1)) 
                                        --  & " - "
                                        --  & "$" & to_hexstring(std_logic_vector(i2)) 
                                        --  & " - 1 + "
                                        --  & "$" & std_logic'image(flag_c)
                                        --  & " = " & to_hexstring(std_logic_vector(tmp(7 downto 0))) severity note;
      return tmp(11 downto 0);
    end function alu_op_sub;

    
  begin

    if rising_edge(clk) then

      -- report "data_i = $" & to_hexstring(data_i);
      
      if data_i(7)='0' then
        branch_addr := reg_pc + to_integer(data_i);
      else
        branch_addr := reg_pc - 256 + to_integer(data_i);
        -- report "Calculated branch addr as $" & to_hexstring(branch_addr) &" = $" & to_hexstring(reg_pc) & " - 256 + " & integer'image(to_integer(data_i));
      end if;

      alu_and := reg_a and data_i;
      alu_ora := reg_a or data_i;
      alu_eor := reg_a xor data_i;
      
      virt_flags(7) := flag_n;
      virt_flags(6) := flag_v;
      virt_flags(5) := '1';
      virt_flags(4) := '0';
      virt_flags(3) := flag_d;
      virt_flags(2) := flag_i;
      virt_flags(1) := flag_z;
      virt_flags(0) := flag_c;

      reg_x_inc <= reg_x + 1;
      reg_x_dec <= reg_x - 1;
      reg_y_inc <= reg_y + 1;
      reg_y_dec <= reg_y - 1;
      reg_addr_x <= to_unsigned(to_integer(reg_addr(7 downto 0)) + to_integer(reg_x),9);
      reg_addr_y <= to_unsigned(to_integer(reg_addr(7 downto 0)) + to_integer(reg_y),9);
      sp_inc := reg_sp + 1;
      sp_dec := reg_sp - 1;
      
      last_nmi <= nmi;
      if nmi='0' and last_nmi='1' then
        nmi_pending <= '1';
      end if;    

      -- Export debug status of CPU
      cpu_state_o <= to_unsigned(cpu_state_t'pos(cpu_state),8);
      address_next <= reg_pc;

      -- Disassert /write line, i.e., read by default
      write_n <= '1';

      if ready='1' then
        -- report("1541CPU: Clock ticks, state=" & cpu_state_t'image(cpu_state)
        --        & ", data_i = $" & to_hexstring(data_i)
        --        & ", addr read=$" & to_hexstring(address)
        --        & ", PC=$" & to_hexstring(reg_pc));        

        -- By default, fetch next instruction byte
        address <= reg_pc;              
        
        case cpu_state is
          when poreset =>
            address <= x"FFFC";
            report "1541CPU: Power-on RESET commenced";
            cpu_state <= vector0;
          when interrupt =>
            -- Push PCH
            reg_addr <= reg_pc;
            write_n <= '0';
            address(15 downto 8) <= x"01"; -- stack
            address(7 downto 0) <= reg_sp;
            data_o <= reg_pc(15 downto 8);
            reg_sp <= sp_dec;
            cpu_state <= interrupt_push_pcl;
            reg_pc <= reg_pc;
          when interrupt_push_pcl =>
            -- Push PCL
            reg_addr <= reg_pc;
            write_n <= '0';
            address(15 downto 8) <= x"01"; -- stack
            address(7 downto 0) <= reg_sp;
            data_o <= reg_pc(7 downto 0);
            reg_sp <= sp_dec;
            cpu_state <= interrupt_push_p;
          when interrupt_push_p =>
            -- Push processor flags
            write_n <= '0';
            address(15 downto 8) <= x"01"; -- stack
            address(7 downto 0) <= reg_sp;
            data_o(7) <= flag_n;
            data_o(6) <= flag_v;
            data_o(5) <= '1';
            data_o(4) <= '0'; -- BRK flag
            data_o(3) <= flag_d;
            data_o(2) <= flag_i;
            data_o(1) <= flag_z;
            data_o(0) <= flag_c;
            reg_sp <= sp_dec;
            cpu_state <= interrupt_vector_fetch;
          when interrupt_vector_fetch =>
            address <= x"FFF8";
            if reset='0' then
              address(3 downto 0) <= x"c";
              report "1541CPU: RESET commenced";
            elsif nmi_pending='1' then
              address(3 downto 0) <= x"a";
              report "1541CPU: NMI commenced";
              nmi_pending <= '0';
            else
              address(3 downto 0) <= x"e";
              report "1541CPU: IRQ commenced";
            end if;
            cpu_state <= vector0;
            -- XXX Push flags and return address to stack
            flag_i <= '1';
          when vector0 =>
            report "1541CPU: Reading interrupt vector from $" & to_hexstring(address);
            reg_pc(7 downto 0) <= data_i;
            address <= address;
            address(0) <= '1';
            cpu_state <= vector1;
          when vector1 =>
            reg_pc(15 downto 8) <= data_i;
            address <= address;
            address(0) <= '1';
            cpu_state <= opcode_fetch;
            report "1541CPU: Read interrupt vector. Jumping to $" & to_hexstring(data_i) & to_hexstring(reg_pc(7 downto 0));
          when opcode_fetch =>
            if (irq='0' and flag_i='0') or nmi_pending='1' or reset='0' then
              cpu_state <= interrupt;
            else
              reg_pc <= reg_pc + 1;
              cpu_state <= idecode;
            end if;

          when idecode =>
            cpu_state <= byte2_fetch;
            reg_opcode <= data_i;
            reg_instruction <= instruction_lut(to_integer(data_i));
            reg_mode <= mode_lut(to_integer(data_i));
            instruction_counter <= instruction_counter + 1;
            report "Instr#:" & integer'image(instruction_counter) & " PC: $" & to_hexstring(to_unsigned(to_integer(reg_pc)-1,16)) & ", A:" & to_hexstring(reg_a) & ", X:" & to_hexstring(reg_x)
              & ", Y:" & to_hexstring(reg_y) & ", SP:" & to_hexstring(reg_sp)
              & " NVxBDIZC=" & to_string(std_logic_vector(virt_flags)) & ", " &
              " Decoding " & instruction'image(instruction_lut(to_integer(data_i)))
              & ", mode = " & addressingmode'image(mode_lut(to_integer(data_i)));
            case mode_lut(to_integer(data_i)) is
              when M_IMPL =>
                cpu_state <= opcode_fetch;
                case instruction_lut(to_integer(data_i)) is
                  when I_CLC => flag_c <= '0';
                  when I_CLD => flag_d <= '0';
                  when I_CLI => flag_i <= '0';
                  when I_DEX => reg_x <= reg_x_dec; set_nz(reg_x_dec);
                  when I_DEY => reg_y <= reg_y_dec; set_nz(reg_y_dec);
                  when I_INX => reg_x <= reg_x_inc; set_nz(reg_x_inc);
                  when I_INY => reg_y <= reg_y_inc; set_nz(reg_y_inc);
                  when I_NOP => null;
                  when I_PHA => address(15 downto 8) <= x"01";
                                address(7 downto 0) <= reg_sp;
                                write_n <= '0';
                                data_o <= reg_a;
                                reg_sp <= sp_dec;
                                cpu_state <= opcode_fetch;
                  when I_PHP => address(15 downto 8) <= x"01";
                                address(7 downto 0) <= reg_sp;
                                write_n <= '0';
                                data_o <= virt_flags;
                                reg_sp <= sp_dec;
                                cpu_state <= opcode_fetch;
                  when I_PLA => address(15 downto 8) <= x"01";
                                address(7 downto 0) <= sp_inc;
                                reg_sp <= sp_inc;
                                cpu_state <= pull;
                  when I_PLP => address(15 downto 8) <= x"01";
                                address(7 downto 0) <= sp_inc;
                                reg_sp <= sp_inc;
                                cpu_state <= pull;

                  when I_RTI => address(15 downto 8) <= x"01";
                                address(7 downto 0) <= sp_inc;
                                reg_sp <= sp_inc;
                                cpu_state <= rti;
                  when I_RTS => address(15 downto 8) <= x"01";
                                address(7 downto 0) <= sp_inc;
                                reg_sp <= sp_inc;
                                cpu_state <= rts;
                  when I_SEC => flag_c <= '1';
                  when I_SED => flag_d <= '1';
                  when I_SEI => flag_i <= '1';
                  when I_TAX => reg_x <= reg_a; set_nz(reg_a);
                  when I_TAY => reg_y <= reg_a; set_nz(reg_a);
                  when I_TSX => reg_x <= reg_sp; set_nz(reg_sp);
                  when I_TXA => reg_a <= reg_x; set_nz(reg_x);
                  when I_TXS => reg_sp <= reg_x;
                  when I_TYA => reg_a <= reg_y; set_nz(reg_y);
                  when I_ROR =>  reg_a(6 downto 0) <= reg_a(7 downto 1);
                                 reg_a(7) <= flag_c;
                                 flag_c <= reg_a(0);
                                 set_nz(reg_a(6 downto 0) & "0");
                  when I_ROL =>  reg_a(7 downto 1) <= reg_a(6 downto 0);
                                 reg_a(0) <= flag_c;
                                 flag_c <= reg_a(7);
                  when I_LSR =>  reg_a(6 downto 0) <= reg_a(7 downto 1);
                                 reg_a(7) <= '0';
                                 flag_c <= reg_a(0);
                  when I_ASL =>  reg_a(7 downto 1) <= reg_a(6 downto 0);
                                 reg_a(0) <= '0';
                                 flag_c <= reg_a(7);
                                
                  when others =>
                    assert false report "Unimplemented implied mode instruction " & instruction'image(instruction_lut(to_integer(data_i)));
                end case;
              when others =>
                reg_pc <= reg_pc + 1;
                -- report "PC <= PC + 1 from $" & to_hexstring(reg_pc);
            end case;
          when byte2_fetch =>
            reg_addr(7 downto 0) <= data_i;
            cpu_state <= byte3_fetch;
            case reg_mode is
              when M_IMMNN =>
                reg_pc <= reg_pc + 1;
                cpu_state <= idecode;                 
                case reg_instruction is
                  when I_LDA => reg_a <= data_i; set_nz(data_i);
                  when I_LDX => reg_x <= data_i; set_nz(data_i);
                  when I_LDY => reg_y <= data_i; set_nz(data_i);
                  when I_AND => reg_a <= alu_and; set_nz(alu_and);
                  when I_ORA => reg_a <= alu_ora; set_nz(alu_ora);
                  when I_EOR => reg_a <= alu_eor; set_nz(alu_eor);
                  when I_ADC =>
                    add_result := alu_op_add(reg_a,data_i);
                    reg_a <= add_result(7 downto 0);
                    flag_c <= add_result(8);  flag_z <= add_result(9);
                    flag_v <= add_result(10); flag_n <= add_result(11);
                  when I_SBC => 
                    add_result := alu_op_sub(reg_a,data_i);
                    reg_a <= add_result(7 downto 0);
                    flag_c <= add_result(8);  flag_z <= add_result(9);
                    flag_v <= add_result(10); flag_n <= add_result(11);
                  when I_CMP => alu_op_cmp(reg_a,data_i);
                                report "CMP: Comparing A=$" & to_hexstring(reg_a) & " with data_i=$" & to_hexstring(data_i);
                  when I_CPX => alu_op_cmp(reg_x,data_i);
                  when I_CPY => alu_op_cmp(reg_y,data_i);
                  when others =>
                    assert false report "Unimplemented immediate mode instruction " & instruction'image(reg_instruction);
                end case;
              when M_NN | M_NNX | M_NNY =>
                address(15 downto 8) <= x"00"; -- Accessing zero-page
                case reg_mode is
                  when M_NN => address(7 downto 0) <= to_unsigned(0 + to_integer(data_i),8);
                  when M_NNX => address(7 downto 0) <= to_unsigned(0 + to_integer(reg_x) + to_integer(data_i),8);
                  when M_NNY => address(7 downto 0) <= to_unsigned(0 + to_integer(reg_y) + to_integer(data_i),8);
                  when others => null;
                end case;
                case reg_instruction is
                  when I_ADC | I_SBC | I_CMP | I_CPX | I_CPY | I_ORA | I_EOR | I_AND 
                    | I_LDA | I_LDX | I_LDY 
                    | I_ROL | I_ROR | I_ASL | I_LSR | I_INC | I_DEC
                    | I_BIT
                    =>
                    cpu_state <= load;
                  when I_STA => data_o <= reg_a; write_n <= '0'; cpu_state <= opcode_fetch;
                  when I_STX => data_o <= reg_x; write_n <= '0'; cpu_state <= opcode_fetch;
                                report "STXZP: Writing $" & to_hexstring(reg_x);
                  when I_STY => data_o <= reg_y; write_n <= '0'; cpu_state <= opcode_fetch;
                  when others =>
                    assert false report "Unimplemented zeropage mode instruction " & instruction'image(reg_instruction);
                end case;
              when M_INNX =>
                reg_addr(15 downto 8) <= x"00";
                reg_addr(7 downto 0) <= data_i + to_integer(reg_x);
                address(15 downto 8) <= x"00";
                address(7 downto 0) <= data_i + to_integer(reg_x);
                cpu_state <= izp;
              when M_INNY =>
                reg_addr(15 downto 8) <= x"00";
                reg_addr(7 downto 0) <= data_i;
                address(15 downto 8) <= x"00";
                address(7 downto 0) <= data_i;
                cpu_state <= izp;
              when M_RR =>
                -- XXX Doesn't charge extra cycle for crossing page boundary
                cpu_state <= idecode;
                reg_pc <= reg_pc + 1;
                case reg_instruction is
                  when I_BNE => if flag_z='0' then take_branch; end if;
                  when I_BEQ => if flag_z='1' then take_branch; end if;
                  when I_BCC => if flag_c='0' then take_branch; end if;
                  when I_BCS => if flag_c='1' then take_branch; end if;
                  when I_BMI => if flag_n='1' then take_branch; end if;
                  when I_BPL => if flag_n='0' then take_branch; end if;
                  when I_BVS => if flag_v='1' then take_branch; end if;
                  when I_BVC => if flag_v='0' then take_branch; end if;
                  when others =>
                    assert false report "Unimplemented branch instruction " & instruction'image(reg_instruction);
                end case;
              when M_NNNN | M_INNNN | M_NNNNX | M_NNNNY =>
                cpu_state <= byte3_fetch;
                -- Make sure PC is still pointing to last byte of JSR
                -- instruction when we start pushing things onto the stack
                if reg_instruction /= I_JSR then reg_pc <= reg_pc + 1; end if;
              when others =>
                assert false report "Hit unimplemented addressing mode " & addressingmode'image(reg_mode);
                null;
            end case;    

          when byte3_fetch =>
            reg_addr(15 downto 8) <= data_i;
            case reg_mode is
              when M_INNNN =>
                case reg_instruction is
                  when I_JMP =>                               
                    address(15 downto 8) <= data_i;
                    address(7 downto 0) <= reg_addr(7 downto 0);
                    reg_addr(15 downto 8) <= data_i;
                    cpu_state <= jmp_vector;
                  when others =>
                    assert false report "Unimplemented ($nnnn) instruction " & instruction'image(reg_instruction);
                end case;
                

              when M_NNNN | M_NNNNX | M_NNNNY =>

                -- Default to absolute unindexed addressing mode
                address(15 downto 8) <= data_i;
                address(7 downto 0) <= reg_addr(7 downto 0);

                -- XXX Does not charge an extra cycle for page crossing
                case reg_mode is
                  when M_NNNNX => address(7 downto 0) <= reg_addr_x(7 downto 0);
                                  if reg_addr_x(8)='1' then address(15 downto 8) <= to_unsigned(to_integer(data_i) + 1,8); end if;
                  when M_NNNNY => address(7 downto 0) <= reg_addr_y(7 downto 0);
                                  if reg_addr_y(8)='1' then address(15 downto 8) <= to_unsigned(to_integer(data_i) + 1,8); end if;
                  when others => null;
                end case;
                
                case reg_instruction is
                  when I_JMP | I_JSR =>
                    reg_pc(7 downto 0) <= reg_addr(7 downto 0);
                    reg_pc(15 downto 8) <= data_i;
                    if reg_instruction = I_JSR then
                      reg_addr <= reg_pc;
                      cpu_state <= jsrhi;
                      write_n <= '0';
                      address(15 downto 8) <= x"01"; -- stack
                      address(7 downto 0) <= reg_sp;
                      data_o <= reg_pc(7 downto 0);
                      reg_sp <= sp_dec;
                    else
                      cpu_state <= opcode_fetch;
                    end if;
                  when I_ADC | I_SBC | I_CMP | I_CPX | I_CPY | I_ORA | I_EOR | I_AND
                    | I_LDA | I_LDX | I_LDY
                    | I_ROL | I_ROR | I_ASL | I_LSR | I_INC | I_DEC
                    | I_BIT
                    =>
                    cpu_state <= load;
                  when I_STA => data_o <= reg_a; write_n <= '0'; cpu_state <= opcode_fetch;
                  when I_STX => data_o <= reg_x; write_n <= '0'; cpu_state <= opcode_fetch;
                  when I_STY => data_o <= reg_y; write_n <= '0'; cpu_state <= opcode_fetch;
                  when others =>
                    assert false report "Unimplemented absolute mode instruction " & instruction'image(reg_instruction);
                end case;                
              when others =>
                assert false report "Hit unimplemented addressing mode " & addressingmode'image(reg_mode);
                null;
            end case;          

          when jmp_vector =>
            reg_pc(7 downto 0) <= data_i;
            address <= reg_addr + 1;
            cpu_state <= jmp_vector2;
          when jmp_vector2 =>
            reg_pc(7 downto 0) <= reg_pc(7 downto 0);
            reg_pc(15 downto 8) <= data_i;
            cpu_state <= opcode_fetch;
            
          when load =>

            cpu_state <= idecode;
            reg_pc <= reg_pc + 1;
            
            case reg_instruction is
              when I_CMP => alu_op_cmp(reg_a,data_i);
                            report "CMP: Comparing A=$" & to_hexstring(reg_a) & " with data_i=$" & to_hexstring(data_i);
              when I_CPX => alu_op_cmp(reg_x,data_i);
              when I_CPY => alu_op_cmp(reg_y,data_i);
              when I_LDA => reg_a <= data_i; set_nz(data_i);
              when I_LDX => reg_x <= data_i; set_nz(data_i);
              when I_LDY => reg_y <= data_i; set_nz(data_i);
              when I_AND => reg_a <= alu_and; set_nz(alu_and);
              when I_ORA => reg_a <= alu_ora; set_nz(alu_ora);
              when I_EOR => reg_a <= alu_eor; set_nz(alu_eor);
              when I_BIT => set_nz(data_i); flag_v <= data_i(6);
              when I_INC | I_DEC | I_ROL | I_ROR | I_LSR | I_ASL =>
                -- Read-modify-write instruction
                -- These write back the original value, before writing back the
                -- updated value
                write_n <= '0';
                address <= address;
                data_o <= data_i;
                cpu_state <= rmw_commit;
                -- Don't update PC yet, because we aren't finished yet.
                reg_pc <= reg_pc;
                case reg_instruction is
                  when I_INC =>  reg_data <= data_i + 1;
                                 set_nz(data_i + 1);
                  when I_DEC =>  reg_data <= data_i - 1;
                                 set_nz(data_i - 1);
                  when I_ROR =>  reg_data(6 downto 0) <= data_i(7 downto 1);
                                 reg_data(7) <= flag_c;
                                 flag_c <= reg_data(0);
                  when I_ROL =>  reg_data(7 downto 1) <= data_i(6 downto 0);
                                 reg_data(0) <= flag_c;
                                 flag_c <= reg_data(7);
                  when I_LSR =>  reg_data(6 downto 0) <= data_i(7 downto 1);
                                 reg_data(7) <= '0';
                                 flag_c <= reg_data(0);
                  when I_ASL =>  reg_data(7 downto 1) <= data_i(6 downto 0);
                                 reg_data(0) <= '0';
                                 flag_c <= reg_data(7);
                  when others =>
                    assert false report "Unimplemented RMW instruction " & instruction'image(reg_instruction);
                end case;
              when others =>
                assert false report "Unimplemented load instruction " & instruction'image(reg_instruction);
            end case;
          when jsrhi =>
            write_n <= '0';
            address(15 downto 8) <= x"01"; -- stack
            address(7 downto 0) <= reg_sp;
            data_o <= reg_addr(15 downto 8);
            reg_sp <= sp_dec;
            cpu_state <= opcode_fetch;
          when rmw_commit =>
            write_n <= '0';
            address <= address;
            data_o <= reg_data;
            cpu_state <= opcode_fetch;

          when rti =>
            flag_n <= data_i(7);
            flag_v <= data_i(6);
            flag_d <= data_i(3);
            flag_i <= data_i(2);
            flag_z <= data_i(1);
            flag_c <= data_i(0);

            address(15 downto 8) <= x"01";
            address(7 downto 0) <= sp_inc;
            reg_sp <= sp_inc;
            
            report "1541CPU: Restored flags $" & to_hexstring(data_i);
            cpu_state <= rti2;
          when rti2 =>
            report "1541CPU: Restored PCL $" & to_hexstring(data_i);
            reg_pc(7 downto 0) <= data_i;
            address(15 downto 8) <= x"01";
            address(7 downto 0) <= reg_sp + 1;
            reg_sp <= sp_inc;
            cpu_state <= rti3;
          when rti3 =>
            report "1541CPU: Restored PCH $" & to_hexstring(data_i);
            reg_pc <= reg_pc;
            reg_pc(15 downto 8) <= data_i;
            cpu_state <= opcode_fetch;
            
          when rts =>
            reg_pc(15 downto 8) <= data_i;
            address(15 downto 8) <= x"01";
            address(7 downto 0) <= reg_sp + 1;
            reg_sp <= sp_inc;
            cpu_state <= rts2;
          when rts2 =>
            reg_pc(7 downto 0) <= data_i + 1;
            if data_i=x"ff" then
              reg_pc(15 downto 8) <= reg_pc(15 downto 8) + 1;
            end if;
            cpu_state <= opcode_fetch;
          when izp =>
            report "IZP: Reading low byte of vector = $" & to_hexstring(data_i) & " from $" & to_hexstring(reg_addr);
            reg_addr(7 downto 0) <= data_i;
            -- Prevent address from being stomped with the automatic reading of
            -- address PC+1 
            address(15 downto 8) <= address(15 downto 8);
            -- And advance the lower byte of the address to read the 2nd half
            -- of the pointer.
            address(7 downto 0) <= address(7 downto 0) + 1;
            cpu_state <= izp2;
          when izp2 =>
            -- We now have the vector, so generate the load address
            reg_addr(15 downto 8) <= data_i;
            report "IZP: Dereferencing pointer at $" & to_hexstring(data_i) & to_hexstring(reg_addr(7 downto 0));
            if reg_mode = M_InnX then
              address(7 downto 0) <= reg_addr(7 downto 0);
              address(15 downto 8) <= data_i;
              report "IZP: Target address = $" & to_hexstring(data_i) & to_hexstring(reg_addr(7 downto 0));
            else
              address(7 downto 0) <= reg_addr(7 downto 0) + to_integer(reg_y);
              if ( to_integer(reg_addr(7 downto 0)) + to_integer(reg_y) ) > 255 then
                address(15 downto 8) <= data_i + 1;
                reg_addr(15 downto 8) <= data_i + 1;
              else
                address(15 downto 8) <= data_i;
                reg_addr(15 downto 8) <= data_i;
              end if;
            end if;

            case reg_instruction is
              when I_ADC | I_SBC | I_CMP | I_CPX | I_CPY | I_ORA | I_EOR | I_AND 
                | I_LDA | I_LDX | I_LDY 
                | I_ROL | I_ROR | I_ASL | I_LSR | I_INC | I_DEC
                | I_BIT
                =>
                cpu_state <= load;
              when I_STA => data_o <= reg_a; write_n <= '0'; cpu_state <= opcode_fetch;
              when I_STX => data_o <= reg_x; write_n <= '0'; cpu_state <= opcode_fetch;
              when I_STY => data_o <= reg_y; write_n <= '0'; cpu_state <= opcode_fetch;
              when others =>
                assert false report "Unimplemented (zeropage) indexed mode instruction " & instruction'image(reg_instruction);
            end case;

          when pull =>
            case reg_instruction is
              when I_PLA =>
                reg_a <= data_i; set_nz(data_i);
                cpu_state <= opcode_fetch;
              when I_PLP =>
                flag_n <= data_i(7);
                flag_v <= data_i(6);
                flag_d <= data_i(3);
                flag_i <= data_i(2);
                flag_z <= data_i(1);
                flag_c <= data_i(0);
                cpu_state <= opcode_fetch;
              when others =>
                null;
            end case;
            
          when others =>
            assert false report "Hit unimplemented CPU state " & cpu_state_t'image(cpu_state);
        end case;
        
      end if;
    end if;
    
  end process;  
end vapourware;

