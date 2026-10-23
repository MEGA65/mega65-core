-- SHITE's microcode engine (docs/shite/MICROCODE.md)
--
-- One micro-op a cycle from a ROM in block RAM (shite_ucode_pkg, made by
-- tools/shite_uasm.py from shite_ucode.asm).  128 registers of 64 bits in
-- LUT RAM, with two read ports; r0 reads 0, and some start with constants.
-- One ALU; a branch on that same op's result; call and return (16 deep);
-- a jump to a register.  Memory is one 8-byte group at a time, through
-- shite's memory states: a request and an acknowledge, as toggles.  The
-- last group read is kept, so loads from it take one cycle.  A data RAM
-- (2048 x 64, block RAM) holds lists and tables.
--
-- Runs on sclock (40.5 MHz on the boards).  The register read, the ALU, the
-- branch's choice and the ROM's next address are one cycle.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.shite_ucode_pkg.all;

entity shite_useq is
  port (
    clock : in std_logic;
    start : in std_logic;                         -- a pulse: run from address 0
    -- the instruction
    i_op : in unsigned(7 downto 0);
    i_a, i_b, i_c, i_d, i_z : in unsigned(31 downto 0);
    i_x : in unsigned(27 downto 0);
    abort : in std_logic;
    -- the end (a pulse), with the error and the result
    done  : out std_logic := '0';
    err   : out unsigned(7 downto 0) := (others => '0');
    wr    : out std_logic := '0';
    result : out unsigned(31 downto 0) := (others => '0');
    -- memory: a request (req_t changes) held until ack_t changes; m_rd
    -- holds the group read from then until the next request
    req_t   : out std_logic := '0';
    m_write : out std_logic := '0';
    m_addr  : out unsigned(27 downto 0) := (others => '0');
    m_wd    : out unsigned(63 downto 0) := (others => '0');
    m_be    : out std_logic_vector(7 downto 0) := (others => '0');
    ack_t   : in std_logic;
    m_rd    : in unsigned(63 downto 0)
    );
end shite_useq;

architecture rtl of shite_useq is

  -- the micro-op's fields (docs/shite/MICROCODE.md)
  signal ir : std_logic_vector(71 downto 0) := (others => '0');
  signal upc : unsigned(10 downto 0) := (others => '0');
  alias f_op : std_logic_vector(5 downto 0) is ir(71 downto 66);
  alias f_rd : std_logic_vector(6 downto 0) is ir(65 downto 59);
  alias f_ra : std_logic_vector(6 downto 0) is ir(58 downto 52);
  alias f_rb : std_logic_vector(6 downto 0) is ir(51 downto 45);
  alias f_bimm : std_logic is ir(44);
  alias f_cond : std_logic_vector(3 downto 0) is ir(43 downto 40);
  alias f_target : std_logic_vector(10 downto 0) is ir(39 downto 29);
  alias f_imm : std_logic_vector(28 downto 0) is ir(28 downto 0);

  signal rf : uc_regs_t := UC_REGS_INIT;
  -- (LUT RAM: its read asynchronous)
  attribute ram_style : string;
  attribute ram_style of rf : signal is "distributed";
  signal va, vb, imm : unsigned(63 downto 0);

  type stack_t is array (0 to 15) of unsigned(10 downto 0);
  signal stk : stack_t := (others => (others => '0'));
  signal sp : unsigned(3 downto 0) := (others => '0');

  signal dm : uc_data_t := (others => (others => '0'));
  attribute ram_style of dm : signal is "block";
  signal dm_q : unsigned(63 downto 0) := (others => '0');
  signal dm_a : natural range 0 to UC_DATA_WORDS - 1;
  signal dm_we : std_logic;

  signal run : std_logic := '0';
  signal mwait, dwait : std_logic := '0';
  signal ack_seen, req_r : std_logic := '0';
  -- the last group read (or written over it)
  signal c_valid : std_logic := '0';
  signal c_tag : unsigned(24 downto 0) := (others => '0');
  signal c_data : unsigned(63 downto 0) := (others => '0');
  signal abt : std_logic := '0';

  -- the cycle's decisions
  signal res : unsigned(63 downto 0);
  signal adv : std_logic;                         -- the op completes this cycle
  signal nxt : unsigned(10 downto 0);
  signal maddr : unsigned(27 downto 0);

  -- bits 0..n-1 set (n 0-64; past 64: all): a thermometer, not a shifter
  function below(n : unsigned(6 downto 0)) return unsigned is
    variable r : unsigned(63 downto 0);
  begin
    for i in 0 to 63 loop
      if i < to_integer(n) then r(i) := '1'; else r(i) := '0'; end if;
    end loop;
    return r;
  end function;

  function bytes_of(op : std_logic_vector(5 downto 0)) return unsigned is
  begin
    case op(1 downto 0) is
      when "00" => return x"01";
      when "01" => return x"03";
      when "10" => return x"0F";
      when others => return x"FF";
    end case;
  end function;

begin

  va <= rf(to_integer(unsigned(f_ra)));
  vb <= rf(to_integer(unsigned(f_rb)));
  imm <= unsigned(resize(signed(f_imm), 64));
  maddr <= resize(va + imm, 28);

  process (ir, upc, va, vb, imm, maddr, i_op, i_a, i_b, i_c, i_d, i_z, i_x, c_valid, c_tag,
           c_data, m_rd, dm_q, mwait, dwait, ack_t, ack_seen, run, start, abt, stk, sp)
    variable b, alu, sh, m, mm, gx, rs, ls : unsigned(63 downto 0);
    variable sum, rs65 : unsigned(64 downto 0);
    variable lo, ramt, lamt : unsigned(5 downto 0);
    variable wf : unsigned(6 downto 0);
    variable o : integer range 0 to 7;
    variable op : integer range 0 to 63;
    variable z, n, v, c, take, done_v, hit : boolean;
  begin
    op := to_integer(unsigned(f_op));
    if f_bimm = '1' then b := imm; else b := vb; end if;
    lo := unsigned(f_imm(5 downto 0));
    wf := '0' & unsigned(f_imm(13 downto 8));       -- a field's width (0: 64)
    if wf = 0 then wf := to_unsigned(64, 7); end if;
    m := below(wf);
    mm := below(('0' & lo) + wf) and not below('0' & lo);

    -- the adder (ADD, SUB: the comparisons)
    if op = UOP_SUB then
      sum := ('0' & va) + ('0' & not b) + 1;
    else
      sum := ('0' & va) + ('0' & b);
    end if;
    c := sum(64) = '1';
    n := sum(63) = '1';
    if op = UOP_SUB then
      v := va(63) /= b(63) and sum(63) /= va(63);
    else
      v := va(63) = b(63) and sum(63) /= va(63);
    end if;

    -- the two shifters: right (SHR, SAR, EXT, EXTS), left (SHL, INS)
    if op = UOP_EXT or op = UOP_EXTS then ramt := lo; else ramt := b(5 downto 0); end if;
    if op = UOP_INS then lamt := lo; else lamt := b(5 downto 0); end if;
    if op = UOP_SAR then rs65 := va(63) & va; else rs65 := '0' & va; end if;
    rs65 := unsigned(shift_right(signed(rs65), to_integer(ramt)));
    rs := rs65(63 downto 0);
    ls := shift_left(va, to_integer(lamt));

    case op is
      when UOP_ADD | UOP_SUB => alu := sum(63 downto 0);
      when UOP_AND => alu := va and b;
      when UOP_OR => alu := va or b;
      when UOP_XOR => alu := va xor b;
      when UOP_ANDN => alu := va and not b;
      when UOP_SHL => alu := ls;
      when UOP_SHR | UOP_SAR => alu := rs;
      when UOP_EXT => alu := rs and m;
      when UOP_EXTS =>
        if rs(to_integer(wf - 1)) = '1' then alu := rs or not m;
        else alu := rs and m; end if;
      when UOP_INS =>                     -- rb with ra's low w bits at lo
        alu := (vb and not mm) or (ls and mm);
      when UOP_HI =>
        alu := b(31 downto 0) & va(31 downto 0);
      when UOP_MOVX =>
        case to_integer(unsigned(f_imm(3 downto 0))) is
          when 0 => alu := resize(i_op, 64);
          when 1 => alu := resize(i_a, 64);
          when 2 => alu := resize(i_b, 64);
          when 3 => alu := resize(i_c, 64);
          when 4 => alu := resize(i_d, 64);
          when 5 => alu := resize(i_z, 64);
          when 6 => alu := resize(i_x, 64);
          when 7 => alu := resize(sp, 64);
          when others => alu := (others => '0');
        end case;
      when others => alu := (others => '0');
    end case;

    -- loads: the group (the one kept, or the one just read), the field
    hit := c_valid = '1' and c_tag = maddr(27 downto 3);
    if hit then gx := c_data; else gx := m_rd; end if;
    o := to_integer(maddr(2 downto 0));
    sh := shift_right(gx, o * 8);
    case op is
      when UOP_LDB => alu := resize(sh(7 downto 0), 64);
      when UOP_LDH => alu := resize(sh(15 downto 0), 64);
      when UOP_LDL => alu := resize(sh(31 downto 0), 64);
      when UOP_LDQ => alu := sh;
      when UOP_LDD => alu := dm_q;
      when others => null;
    end case;
    res <= alu;

    -- done this cycle?  Memory: a load from the group kept, or the
    -- acknowledge; the data RAM: its read's second cycle
    case op is
      when UOP_LDB | UOP_LDH | UOP_LDL | UOP_LDQ =>
        done_v := hit or (mwait = '1' and ack_t /= ack_seen);
      when UOP_STB | UOP_STH | UOP_STL | UOP_STQ =>
        done_v := mwait = '1' and ack_t /= ack_seen;
      when UOP_LDD =>
        done_v := dwait = '1';
      when others =>
        done_v := true;
    end case;
    if run = '1' and start = '0' and done_v then adv <= '1'; else adv <= '0'; end if;

    -- the branch: on this op's result
    z := alu = 0;
    case to_integer(unsigned(f_cond)) is
      when UC_JMP | UC_CALL => take := true;
      when UC_Z => take := z;
      when UC_NZ => take := not z;
      when UC_UGE => take := c;
      when UC_ULT => take := not c;
      when UC_LT => take := n /= v;
      when UC_GE => take := n = v;
      when UC_MI => take := alu(63) = '1';
      when UC_PL => take := alu(63) = '0';
      when UC_ABT => take := abt = '1';
      when UC_NABT => take := abt = '0';
      when others => take := false;
    end case;
    if start = '1' then
      nxt <= (others => '0');
    elsif run = '0' or not done_v then
      nxt <= upc;
    elsif to_integer(unsigned(f_cond)) = UC_RET then
      nxt <= stk(to_integer(sp - 1));
    elsif to_integer(unsigned(f_cond)) = UC_JTAB then
      nxt <= unsigned(f_target) + alu(10 downto 0);
    elsif take then
      nxt <= unsigned(f_target);
    else
      nxt <= upc + 1;
    end if;
  end process;

  -- the data RAM: one port, its address ra + imm
  dm_a <= to_integer(maddr(10 downto 0)) mod UC_DATA_WORDS;
  dm_we <= '1' when run = '1' and to_integer(unsigned(f_op)) = UOP_STD else '0';
  process (clock)
  begin
    if rising_edge(clock) then
      if dm_we = '1' then
        dm(dm_a) <= vb;
      end if;
      dm_q <= dm(dm_a);
    end if;
  end process;

  -- the ROM (block RAM, its read registered: the next op's address)
  process (clock)
  begin
    if rising_edge(clock) then
      if start = '1' or adv = '1' then
        ir <= UCODE(to_integer(nxt));
        upc <= nxt;
      end if;
    end if;
  end process;

  -- the registers' write
  process (clock)
  begin
    if rising_edge(clock) then
      if adv = '1' and unsigned(f_rd) /= 0 then
        rf(to_integer(unsigned(f_rd))) <= res;
      end if;
    end if;
  end process;

  process (clock)
    variable op : integer range 0 to 63;
    variable o : integer range 0 to 7;
    variable be : unsigned(7 downto 0);
    variable d : unsigned(63 downto 0);
  begin
    if rising_edge(clock) then
      abt <= abort;
      done <= '0';
      op := to_integer(unsigned(f_op));
      o := to_integer(maddr(2 downto 0));
      if start = '1' then
        run <= '1'; mwait <= '0'; dwait <= '0'; sp <= (others => '0');
        c_valid <= '0'; ack_seen <= ack_t;
        err <= (others => '0'); wr <= '0';
      elsif run = '1' then
        -- memory: the request, once; the acknowledge
        case op is
          when UOP_LDB | UOP_LDH | UOP_LDL | UOP_LDQ | UOP_STB | UOP_STH | UOP_STL | UOP_STQ =>
            if mwait = '0' and adv = '0' then
              be := shift_left(bytes_of(f_op), o);
              d := shift_left(vb, o * 8);
              m_addr <= maddr(27 downto 3) & "000";
              m_write <= f_op(2);                -- (STx: 20-23)
              m_wd <= d; m_be <= std_logic_vector(be);
              req_r <= not req_r; mwait <= '1';
              if f_op(2) = '1' and c_tag = maddr(27 downto 3) then
                -- (the group kept: written over)
                for i in 0 to 7 loop
                  if be(i) = '1' then c_data(i * 8 + 7 downto i * 8) <= d(i * 8 + 7 downto i * 8); end if;
                end loop;
              end if;
            elsif mwait = '1' and adv = '1' then
              mwait <= '0'; ack_seen <= ack_t;
              if f_op(2) = '0' then
                c_valid <= '1'; c_tag <= maddr(27 downto 3); c_data <= m_rd;
              end if;
            end if;
          when UOP_LDD =>
            dwait <= not dwait;
          when UOP_RES =>
            result <= va(31 downto 0); wr <= '1';
          when UOP_END =>
            if adv = '1' then
              err <= unsigned(f_imm(7 downto 0)); done <= '1'; run <= '0';
            end if;
          when others => null;
        end case;
        -- the call stack: call, return, or set (SETSP: back out of calls)
        if adv = '1' and op = UOP_SETSP then
          sp <= va(3 downto 0);
        elsif adv = '1' and to_integer(unsigned(f_cond)) = UC_CALL then
          stk(to_integer(sp)) <= upc + 1; sp <= sp + 1;
        elsif adv = '1' and to_integer(unsigned(f_cond)) = UC_RET then
          sp <= sp - 1;
        end if;
      end if;
    end if;
  end process;
  req_t <= req_r;

end rtl;
