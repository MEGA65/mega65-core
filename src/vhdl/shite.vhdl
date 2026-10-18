-- SHITE: Spreadsheet Hardware Integrated Technology Engine
--
-- SSNAIL's coprocessor for opcodes $40-$4F (see docs/shite/README.md and
-- the reference model SSNAIL/shite.py).  SSNAIL hands over its LUMP ports
-- for the length of an instruction (ssnail_top multiplexes them).
--
-- FIND_CELL ($42), REBALANCE_ROW ($41) and RECALC ($40: so far integer
-- formulas: constants, references, ADD SUB MUL NEG and the comparisons).
-- Memory is reached one 8-byte group at a time (no cache yet).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lumptypes.all;

entity shite is
  generic (
    -- Most cells REBALANCE_ROW sorts in one row (its list RAM)
    max_row_cells : natural := 1024
    );
  port (
    clock162 : in std_logic;

    -- from SSNAIL (cop_ ports)
    start  : in  std_logic;
    op     : in  unsigned(7 downto 0);
    ra     : in  unsigned(31 downto 0);
    rb     : in  unsigned(31 downto 0);
    rc     : in  unsigned(31 downto 0);   -- R[c bits 3-0]
    rd     : in  unsigned(31 downto 0);   -- R[c bits 7-4]
    z      : in  unsigned(31 downto 0);   -- the instruction's Z
    x      : in  unsigned(27 downto 0);
    abort  : in  std_logic;
    done   : out std_logic := '0';
    err    : out unsigned(7 downto 0) := (others => '0');
    wr     : out std_logic := '0';
    result : out unsigned(31 downto 0) := (others => '0');
    map_hr_base, map_hr_size, map_sd_base, map_sd_size : in unsigned(7 downto 0);

    -- LUMP masters (valid only while SSNAIL has handed them over)
    hr_cmd_valid   : out std_logic := '0';
    hr_cmd_ready   : in  std_logic;
    hr_cmd_op      : out unsigned(1 downto 0) := "00";
    hr_cmd_addr    : out unsigned(26 downto 0) := (others => '0');
    hr_cmd_len     : out unsigned(8 downto 0) := (others => '0');
    hr_rdata       : in  unsigned(15 downto 0);
    hr_rdata_valid : in  std_logic;
    hr_wdata_req   : in  std_logic;
    hr_wdata       : out unsigned(15 downto 0) := x"0000";
    hr_wdata_be    : out std_logic_vector(1 downto 0) := "11";
    hr_cmd_done    : in  std_logic;
    hr_error       : in  std_logic;
    sd_cmd_valid   : out std_logic := '0';
    sd_cmd_ready   : in  std_logic;
    sd_cmd_op      : out unsigned(1 downto 0) := "00";
    sd_cmd_addr    : out unsigned(26 downto 0) := (others => '0');
    sd_cmd_len     : out unsigned(8 downto 0) := (others => '0');
    sd_rdata       : in  unsigned(15 downto 0);
    sd_rdata_valid : in  std_logic;
    sd_wdata_req   : in  std_logic;
    sd_wdata       : out unsigned(15 downto 0) := x"0000";
    sd_wdata_be    : out std_logic_vector(1 downto 0) := "11";
    sd_cmd_done    : in  std_logic;
    sd_error       : in  std_logic
    );
end shite;

architecture rtl of shite is

  -- SSNAIL's error codes
  constant ERR_NONE      : unsigned(7 downto 0) := x"00";
  constant ERR_OPCODE    : unsigned(7 downto 0) := x"01";
  constant ERR_ADDRESS   : unsigned(7 downto 0) := x"02";
  constant ERR_READ      : unsigned(7 downto 0) := x"04";
  constant ERR_ABORTED   : unsigned(7 downto 0) := x"05";
  constant ERR_FORMAT    : unsigned(7 downto 0) := x"06";

  constant K_FREE : unsigned(3 downto 0) := x"F";

  type state_t is (
    S_IDLE, S_FINISH, S_FAULT, S_FAULT2,
    -- memory primitives: one 8-byte group
    M_DEC, M_ISSUE, M_WAIT,
    -- the descriptor (both instructions)
    D_RD0, D_RD1, D_CHK,
    -- FIND_CELL, and the cell lookup it shares with RECALC's references
    F_DONE, LK_START, LK_ROW, LK_HDR, LK_HDR2, LK_CELL, LK_CELL2,
    -- RECALC: the descriptor's counters, rows, cells
    RC_D16, RC_D24, RC_D32, RC_D40, RC_D48,
    RC_ROW, RC_ROW2, RC_HDR0, RC_HDR1, RC_HCHK, RC_WALK, RC_WALK2, RC_RCHG,
    RC_FMT, RC_RES, RC_INFO,
    RC_CW1, RC_CW2, RC_END, RC_CMP, RC_CMP2, RC_CMP3, RC_SW1, RC_SW2, RC_SW3, RC_PREV, RC_FIN,
    -- formula evaluation: the byte reader, operands, operators, the result
    BF, BF_FILL, E_NEXT, E_OP, E_IMM, E_IMM2, E_I8, E_I32, E_I64, E_SREF, E_LREF, E_RESOLVE,
    VL_HDR, VL_V8, VL_FMT, VL_F8, VL_F16, VL_F24,
    E_BIN, E_SCALED, E_ARITH, E_MULF, E_DIVM, E_DIVF, E_NEG, E_FIX,
    E_STORE, E_ST_SC, E_ST_DONE, E_W1, E_W2, E_W3, E_W4, E_NEXTCELL,
    -- the shared multiplier and divider
    MU_START, MU_STEP, DV_START, DV_STEP, DV_ROUND,
    -- F64: operands converted, the operation, conversions, rounding
    E_F64, E_FB1, E_FB2, E_FB3, E_FBR, E_STF,
    CV_START, CV_I2F, CV_SCALE, CV_DIV,
    FP_START, FA_ALIGN, FA_SHIFT, FA_SUM, FM_PROD, FD_QUOT,
    FN_NORM, FN_DEN, FN_RND, FN_PACK,
    -- REBALANCE_ROW
    B_ROW, B_ROW2, B_HDR0, B_HDR1, B_HCHK, B_WALK, B_WALK2,
    B_SORT, B_SORT1, B_SORT2, B_SORT3, B_SORT4,
    B_TREE, B_TREE2, B_TREE3, B_TREE4, B_TREE5, B_TREE6, B_TREE7, B_RHDR, B_NEXT,
    -- the list RAM's read (one cycle)
    L_WAIT
    );
  signal st, mem_ret, l_ret, lk_ret, fb_ret, imm_ret, cw_ret, mu_ret, dv_ret : state_t := S_IDLE;
  signal fp_ret, fn_ret, cv_ret : state_t := S_IDLE;

  -- the instruction
  signal r_op : unsigned(7 downto 0) := (others => '0');
  signal r_a, r_b, r_c, r_d, r_z : unsigned(31 downto 0) := (others => '0');
  signal desc : unsigned(27 downto 0) := (others => '0');
  -- the descriptor
  signal rowtab : unsigned(27 downto 0) := (others => '0');
  signal nrows, ncols : unsigned(31 downto 0) := (others => '0');
  signal bad_row : unsigned(31 downto 0) := (others => '0');

  -- memory primitive: m_addr (8-aligned), m_write; m_rd / m_wd; m_be (bytes)
  signal m_addr : unsigned(27 downto 0) := (others => '0');
  signal m_write : std_logic := '0';
  signal m_rd, m_wd : unsigned(63 downto 0) := (others => '0');
  signal m_be : std_logic_vector(7 downto 0) := (others => '1');
  signal m_is_sd, m_ok : std_logic := '0';
  signal m_local : unsigned(26 downto 0) := (others => '0');
  signal m_words : unsigned(2 downto 0) := (others => '0');   -- words received
  signal m_wk : unsigned(2 downto 0) := (others => '0');      -- words sent
  signal m_done_seen : std_logic := '0';
  signal hr_v, sd_v : std_logic := '0';

  -- row walk
  signal row : unsigned(31 downto 0) := (others => '0');
  signal rlast : unsigned(31 downto 0) := (others => '0');
  signal blk : unsigned(27 downto 0) := (others => '0');
  signal rh0, rh1 : unsigned(63 downto 0) := (others => '0');  -- the row header
  signal g, gfree : unsigned(15 downto 0) := (others => '0');
  signal col : unsigned(23 downto 0) := (others => '0');

  -- REBALANCE's list: per cell, column (63:40), granule (39:24), the
  -- header's bytes 3-4 (kind and flags, length: 23:8).  One write port
  -- and one registered read port (block RAM)
  type list_t is array (0 to max_row_cells - 1) of unsigned(63 downto 0);
  signal list : list_t;
  signal l_ra : natural range 0 to max_row_cells - 1 := 0;
  signal l_rd : unsigned(63 downto 0) := (others => '0');
  signal l_n : natural range 0 to max_row_cells := 0;
  signal l_i, l_j : natural range 0 to max_row_cells := 0;
  signal l_key, l_cur : unsigned(63 downto 0) := (others => '0');
  signal g_left, g_right, g_root : unsigned(15 downto 0) := (others => '0');
  signal first_node : boolean := false;
  -- the tree builder's stack of ranges lo..hi
  type stk_t is array (0 to 31) of unsigned(21 downto 0);
  signal stk : stk_t;
  signal sp : natural range 0 to 32 := 0;
  signal t_lo, t_hi, t_mid : integer range -1 to max_row_cells := 0;

  -- ---------------------------------------------------------------------
  -- RECALC
  -- value kinds on the stack
  constant VK_Z : unsigned(2 downto 0) := "000";  -- blank
  constant VK_I : unsigned(2 downto 0) := "001";  -- I64 (fixed point in its k)
  constant VK_F : unsigned(2 downto 0) := "010";  -- F64
  constant VK_T : unsigned(2 downto 0) := "011";  -- text
  constant VK_E : unsigned(2 downto 0) := "100";  -- error
  -- cell kinds
  constant K_EMPTY : unsigned(3 downto 0) := x"0";
  constant K_TEXT  : unsigned(3 downto 0) := x"1";
  constant K_FORMULA : unsigned(3 downto 0) := x"2";
  constant K_F64   : unsigned(3 downto 0) := x"3";
  constant K_I64   : unsigned(3 downto 0) := x"4";
  constant K_I32   : unsigned(3 downto 0) := x"5";
  constant K_ERROR : unsigned(3 downto 0) := x"6";
  constant K_UNCOMPILED : unsigned(3 downto 0) := x"7";
  -- formula errors
  constant E_DIV0 : unsigned(7 downto 0) := x"01";
  constant E_VALUE : unsigned(7 downto 0) := x"02";
  constant E_REF : unsigned(7 downto 0) := x"03";
  constant E_NUM : unsigned(7 downto 0) := x"04";
  constant E_STACK : unsigned(7 downto 0) := x"07";
  constant E_NAME : unsigned(7 downto 0) := x"08";
  constant E_COMPILE : unsigned(7 downto 0) := x"09";

  -- the descriptor's fields, kept here during a RECALC and written back at
  -- its end (or on a format fault)
  signal cl, cap, pcl, round_n, n_chg, n_evals, n_errs, prev_chg : unsigned(31 downto 0) := (others => '0');
  signal d44, d48 : unsigned(31 downto 0) := (others => '0');   -- bytes 44-47 (flags), 48-51
  signal cnt_loaded : boolean := false;
  signal call_chg : unsigned(31 downto 0) := (others => '0');
  signal row_chg : unsigned(15 downto 0) := (others => '0');
  signal same : boolean := false;
  signal cmp_i : unsigned(31 downto 0) := (others => '0');
  signal cmp_a : unsigned(63 downto 0) := (others => '0');
  -- the formula cell
  signal cell : unsigned(27 downto 0) := (others => '0');
  signal hdr : unsigned(63 downto 0) := (others => '0');
  signal fk, old_rk : unsigned(7 downto 0) := (others => '0');
  signal old_v : unsigned(63 downto 0) := (others => '0');
  signal bclen, pc : unsigned(15 downto 0) := (others => '0');
  -- the byte reader: one group buffered
  signal bf_tag : unsigned(24 downto 0) := (others => '0');
  signal bf_data : unsigned(63 downto 0) := (others => '0');
  signal bf_valid : boolean := false;
  signal bf_byte : unsigned(7 downto 0) := (others => '0');
  -- multi-byte operands
  signal imm : unsigned(63 downto 0) := (others => '0');
  signal fb_i, fb_n : unsigned(3 downto 0) := (others => '0');
  signal fb_be : boolean := false;
  -- the stack: its top in registers, the rest in a RAM
  signal t_kind : unsigned(2 downto 0) := VK_Z;
  signal t_v : unsigned(63 downto 0) := (others => '0');
  signal t_k : unsigned(7 downto 0) := (others => '0');
  signal t_ref : std_logic := '0';
  type est_t is array (0 to 31) of unsigned(75 downto 0);   -- kind, ref, k, value
  signal est : est_t;
  signal esp : natural range 0 to 32 := 0;
  -- a reference being looked up, and the value it gives
  signal q_row, q_col : unsigned(31 downto 0) := (others => '0');
  signal q_addr : unsigned(27 downto 0) := (others => '0');
  signal lk_blk : unsigned(27 downto 0) := (others => '0');   -- the lookup's own
  signal lk_g : unsigned(15 downto 0) := (others => '0');
  signal cur_op : unsigned(7 downto 0) := (others => '0');
  signal swap : boolean := false;
  signal v_hdr : unsigned(63 downto 0) := (others => '0');
  signal v_val : unsigned(63 downto 0) := (others => '0');
  -- the multiplier: mu_x * mu_y (signed) by shift and add on the
  -- magnitudes, 64 steps: the 128-bit magnitude mu_hi:mu_lo, its sign mu_neg
  signal mu_x, mu_y : unsigned(63 downto 0) := (others => '0');
  signal mu_a, mu_b, mu_lo : unsigned(63 downto 0) := (others => '0');
  signal mu_hi : unsigned(64 downto 0) := (others => '0');
  signal mu_n : natural range 0 to 64 := 0;
  signal mu_neg : boolean := false;
  -- the divider: dv_n (128-bit magnitude) / dv_d (64-bit magnitude),
  -- restoring, 128 steps, rounded half away from zero; dv_neg the sign
  signal dv_n, dv_q : unsigned(127 downto 0) := (others => '0');
  signal dv_d : unsigned(63 downto 0) := (others => '0');
  signal dv_r : unsigned(64 downto 0) := (others => '0');
  signal dv_i : natural range 0 to 128 := 0;
  signal dv_neg : boolean := false;
  -- the operands of a binary operator, aligned
  signal xa, xb : unsigned(63 downto 0) := (others => '0');
  signal x_k : unsigned(7 downto 0) := (others => '0');      -- the result's fixed point
  signal sc_b : boolean := false;                             -- scaling b (else a)
  signal dv_raw : boolean := false;                           -- the divider: no rounding

  -- F64 (IEEE 754 double, round to nearest even, subnormals flushed to
  -- zero after rounding).  fp_op on fp_a, fp_b gives fp_r.
  constant FP_ADD : unsigned(1 downto 0) := "00";
  constant FP_SUB : unsigned(1 downto 0) := "01";
  constant FP_MUL : unsigned(1 downto 0) := "10";
  constant FP_DIV : unsigned(1 downto 0) := "11";
  constant F64_NAN : unsigned(63 downto 0) := x"FFF8000000000000";
  signal fp_op : unsigned(1 downto 0) := FP_ADD;
  signal fp_a, fp_b, fp_r : unsigned(63 downto 0) := (others => '0');
  -- add: the larger operand's significand, the smaller's, the shift
  signal fa_s, fb_s : std_logic := '0';
  signal fa_sig, fb_sig : unsigned(63 downto 0) := (others => '0');
  signal fa_e, fb_e : signed(13 downto 0) := (others => '0');
  signal fa_d : signed(13 downto 0) := (others => '0');
  -- the normaliser / rounder: value = fn_sig / 2^63 * 2^(fn_e - 1023)
  signal fn_s : std_logic := '0';
  signal fn_e : signed(13 downto 0) := (others => '0');
  signal fn_sig : unsigned(63 downto 0) := (others => '0');
  signal fn_st : std_logic := '0';
  signal fn_sub : boolean := false;
  -- conversions: cv_v (an integer, fixed point cv_k) to F64
  signal cv_v : unsigned(63 downto 0) := (others => '0');
  signal cv_k : unsigned(7 downto 0) := (others => '0');
  signal cv_t : unsigned(63 downto 0) := (others => '0');
  signal cv_step : natural range 0 to 3 := 0;
  -- a binary operator's F64 operands
  signal fx_a, fx_b : unsigned(63 downto 0) := (others => '0');
  signal fx_ka, fx_kb : unsigned(2 downto 0) := (others => '0');
  signal fx_fa, fx_fb : unsigned(7 downto 0) := (others => '0');
  -- the result to store
  signal new_rk : unsigned(7 downto 0) := (others => '0');
  signal new_v : unsigned(63 downto 0) := (others => '0');

  -- 10^d, d = 0..18
  type p10_t is array (0 to 18) of unsigned(63 downto 0);
  function init_p10 return p10_t is
    variable r : p10_t;
    variable v : unsigned(63 downto 0) := to_unsigned(1, 64);
  begin
    for i in 0 to 18 loop
      r(i) := v;
      v := resize(v * to_unsigned(10, 4), 64);
    end loop;
    return r;
  end function;
  constant P10 : p10_t := init_p10;
  -- 10^d or 2^d (binary)
  function pw(d : unsigned(6 downto 0); binary : std_logic) return unsigned is
  begin
    if binary = '1' then
      return shift_left(to_unsigned(1, 64), to_integer(d));
    elsif d > 18 then
      return x"0000000000000000";
    else
      return P10(to_integer(d));
    end if;
  end function;
  -- a fixed point past its limits (decimal 18, binary 62): #NUM!
  function bad_k(k : unsigned(7 downto 0)) return boolean is
  begin
    if k(7) = '1' then return k(6 downto 0) > 62; else return k(6 downto 0) > 18; end if;
  end function;
  -- F64 helpers (inputs are never subnormal: they are flushed on the way in)
  function f_zero(b : unsigned(63 downto 0)) return boolean is
  begin
    return b(62 downto 52) = 0;
  end function;
  function f_inf(b : unsigned(63 downto 0)) return boolean is
  begin
    return b(62 downto 52) = "11111111111" and b(51 downto 0) = 0;
  end function;
  function f_nan(b : unsigned(63 downto 0)) return boolean is
  begin
    return b(62 downto 52) = "11111111111" and b(51 downto 0) /= 0;
  end function;
  function ftz(b : unsigned(63 downto 0)) return unsigned is
  begin
    if b(62 downto 52) = 0 then return b(63) & "000" & x"000000000000000"; else return b; end if;
  end function;
  -- a < b, a = b on F64 bits (NaN unordered: both false), +0 = -0
  function f_lt(a, b : unsigned(63 downto 0)) return boolean is
  begin
    if f_nan(a) or f_nan(b) or (f_zero(a) and f_zero(b)) then return false;
    elsif a(63) /= b(63) then return a(63) = '1';
    elsif a(63) = '0' then return a(62 downto 0) < b(62 downto 0);
    else return a(62 downto 0) > b(62 downto 0);
    end if;
  end function;
  function f_eq(a, b : unsigned(63 downto 0)) return boolean is
  begin
    if f_nan(a) or f_nan(b) then return false;
    elsif f_zero(a) and f_zero(b) then return true;
    else return a = b;
    end if;
  end function;
  function b2s(c : boolean) return std_logic is
  begin
    if c then return '1'; else return '0'; end if;
  end function;
  function b64(c : boolean) return unsigned is
  begin
    if c then return x"0000000000000001"; else return x"0000000000000000"; end if;
  end function;
  function sext15(v : unsigned(14 downto 0)) return unsigned is
  begin
    return unsigned(resize(signed(v), 32));
  end function;
  function sext14(v : unsigned(13 downto 0)) return unsigned is
  begin
    return unsigned(resize(signed(v), 32));
  end function;

  function mid_of(lo, hi : integer) return integer is
  begin
    return (lo + hi) / 2;
  end function;

begin

  hr_cmd_valid <= hr_v;
  sd_cmd_valid <= sd_v;

  process (clock162)
    variable mb : unsigned(7 downto 0);
    variable w : unsigned(15 downto 0);
    variable e : unsigned(63 downto 0);
    variable lo, hi, md : integer;
    variable ad : unsigned(27 downto 0);
    variable ka, kb : unsigned(2 downto 0);
    variable va, vb : unsigned(63 downto 0);
    variable sum : unsigned(64 downto 0);
    variable ent : unsigned(75 downto 0);
    variable lt, eq : boolean;
    variable fa, fb : unsigned(7 downto 0);
    variable kk : unsigned(6 downto 0);
    variable bin : std_logic;
    variable rr, cc : unsigned(31 downto 0);

    procedure mem_read(a : unsigned(27 downto 0); ret : state_t) is
    begin
      m_addr <= a(27 downto 3) & "000"; m_write <= '0'; mem_ret <= ret; st <= M_DEC;
    end procedure;
    procedure mem_write(a : unsigned(27 downto 0); d : unsigned(63 downto 0);
                        be : std_logic_vector(7 downto 0); ret : state_t) is
    begin
      m_addr <= a(27 downto 3) & "000"; m_write <= '1'; m_wd <= d; m_be <= be;
      mem_ret <= ret; st <= M_DEC;
    end procedure;
    procedure fault(code : unsigned(7 downto 0)) is
    begin
      err <= code; st <= S_FINISH;
    end procedure;
    procedure format_fault(r : unsigned(31 downto 0)) is
    begin
      bad_row <= r; st <= S_FAULT;
    end procedure;
    -- RECALC's stack
    procedure push(k : unsigned(2 downto 0); v : unsigned(63 downto 0);
                   fx : unsigned(7 downto 0); rf : std_logic; nxt : state_t) is
    begin
      if esp = 32 then
        t_kind <= VK_E; t_v <= x"00000000000000" & E_STACK; esp <= 1; st <= E_STORE;
      else
        if esp > 0 then
          est(esp - 1) <= t_kind & t_ref & t_k & t_v;
        end if;
        t_kind <= k; t_v <= v; t_k <= fx; t_ref <= rf;
        esp <= esp + 1;
        st <= nxt;
      end if;
    end procedure;
    -- the formula's result is an error, at once
    procedure e_abort(code : unsigned(7 downto 0)) is
    begin
      t_kind <= VK_E; t_v <= x"00000000000000" & code; esp <= 1; st <= E_STORE;
    end procedure;
    -- one byte of bytecode (bf_byte), then nxt
    procedure fetch(nxt : state_t) is
    begin
      fb_ret <= nxt; st <= BF;
    end procedure;
  begin
    if rising_edge(clock162) then
      done <= '0';
      if hr_cmd_ready = '1' then hr_v <= '0'; end if;
      if sd_cmd_ready = '1' then sd_v <= '0'; end if;

      -- the memory map (SSNAIL's), a cycle after m_addr
      mb := m_addr(27 downto 20);
      if mb >= map_hr_base and resize(mb, 9) < resize(map_hr_base, 9) + resize(map_hr_size, 9) then
        m_ok <= '1'; m_is_sd <= '0';
        m_local <= resize(mb - map_hr_base, 7) & m_addr(19 downto 0);
      elsif mb >= map_sd_base and resize(mb, 9) < resize(map_sd_base, 9) + resize(map_sd_size, 9) then
        m_ok <= '1'; m_is_sd <= '1';
        m_local <= resize(mb - map_sd_base, 7) & m_addr(19 downto 0);
      else
        m_ok <= '0';
      end if;

      -- write data: each request is answered the next cycle
      if st = M_WAIT and m_write = '1' and m_wk /= 4
        and ((hr_wdata_req = '1' and m_is_sd = '0') or (sd_wdata_req = '1' and m_is_sd = '1')) then
        w := m_wd(to_integer(m_wk) * 16 + 15 downto to_integer(m_wk) * 16);
        hr_wdata <= w; sd_wdata <= w;
        hr_wdata_be <= m_be(to_integer(m_wk) * 2 + 1) & m_be(to_integer(m_wk) * 2);
        sd_wdata_be <= m_be(to_integer(m_wk) * 2 + 1) & m_be(to_integer(m_wk) * 2);
        m_wk <= m_wk + 1;
      end if;

      l_rd <= list(l_ra);                 -- (the list RAM's read port)

      case st is
        when S_IDLE =>
          if start = '1' then
            err <= ERR_NONE; wr <= '0'; cnt_loaded <= false;
            r_op <= op; r_a <= ra; r_b <= rb; r_c <= rc; r_d <= rd; r_z <= z; desc <= x;
            mem_read(x, D_RD0);
          end if;

        when S_FINISH =>
          done <= '1';
          st <= S_IDLE;

        -- ERR_FORMAT: the row into the descriptor (bytes 48-51)
        when S_FAULT =>
          if cnt_loaded then                      -- (RECALC's counters first)
            cnt_loaded <= false; cw_ret <= S_FAULT; st <= RC_CW1;
          else
            mem_write(desc + 48, x"00000000" & bad_row, "00001111", S_FAULT2);
          end if;
        when S_FAULT2 =>
          fault(ERR_FORMAT);

        -- --------------------------------------------------------------
        -- One 8-byte group at m_addr
        when M_DEC =>
          st <= M_ISSUE;                    -- (the map decodes m_addr now)
        when M_ISSUE =>
          if m_ok = '0' then
            fault(ERR_ADDRESS);
          else
            m_words <= (others => '0'); m_wk <= (others => '0'); m_done_seen <= '0';
            if m_write = '1' then
              hr_cmd_op <= LUMP_OP_WRITE; sd_cmd_op <= LUMP_OP_WRITE;
            else
              hr_cmd_op <= LUMP_OP_READ; sd_cmd_op <= LUMP_OP_READ;
            end if;
            hr_cmd_addr <= m_local; sd_cmd_addr <= m_local;
            hr_cmd_len <= to_unsigned(8, 9); sd_cmd_len <= to_unsigned(8, 9);
            if m_is_sd = '1' then sd_v <= '1'; else hr_v <= '1'; end if;
            st <= M_WAIT;
          end if;
        when M_WAIT =>
          if m_is_sd = '1' then
            if sd_rdata_valid = '1' and m_write = '0' then
              m_rd <= sd_rdata & m_rd(63 downto 16);
              m_words <= m_words + 1;
            end if;
            if sd_cmd_done = '1' then m_done_seen <= '1'; end if;
            if sd_error = '1' then fault(ERR_READ); end if;
          else
            if hr_rdata_valid = '1' and m_write = '0' then
              m_rd <= hr_rdata & m_rd(63 downto 16);
              m_words <= m_words + 1;
            end if;
            if hr_cmd_done = '1' then m_done_seen <= '1'; end if;
            if hr_error = '1' then fault(ERR_READ); end if;
          end if;
          if m_done_seen = '1' and (m_write = '1' or m_words = 4) then
            st <= mem_ret;
          end if;

        -- --------------------------------------------------------------
        -- The descriptor: magic and row table, then the rows
        when D_RD0 =>
          if m_rd(31 downto 0) /= x"31544853" then         -- "SHT1"
            format_fault(x"FFFFFFFF");
          else
            rowtab <= m_rd(59 downto 32);
            mem_read(desc + 8, D_RD1);
          end if;
        when D_RD1 =>
          nrows <= m_rd(31 downto 0);
          ncols <= m_rd(63 downto 32);
          st <= D_CHK;
        when D_CHK =>
          if abort = '1' then
            fault(ERR_ABORTED);
          elsif r_op = x"42" then                   -- FIND_CELL
            q_row <= r_a; q_col <= r_b; lk_ret <= F_DONE; st <= LK_START;
          elsif r_op = x"40" then                   -- RECALC
            mem_read(desc + 16, RC_D16);
          elsif r_op = x"41" then                   -- REBALANCE_ROW
            row <= r_a; rlast <= r_b;
            st <= B_ROW;
          else
            fault(ERR_OPCODE);
          end if;

        -- --------------------------------------------------------------
        -- The cell lookup (q_row, q_col -> q_addr, 0: none): the row's
        -- block, its root, then the tree.  Returns to lk_ret.
        when LK_START =>
          if q_row >= nrows then
            q_addr <= (others => '0'); st <= lk_ret;
          else
            mem_read(rowtab + (q_row(25 downto 0) & "00"), LK_ROW);
          end if;
        when LK_ROW =>
          if q_row(0) = '0' then e := x"00000000" & m_rd(31 downto 0);
          else e := x"00000000" & m_rd(63 downto 32); end if;
          if e(31 downto 0) = x"FFFFFFFF" then
            q_addr <= (others => '0'); st <= lk_ret;
          else
            lk_blk <= e(27 downto 0);
            mem_read(e(27 downto 0) + 8, LK_HDR);
          end if;
        when LK_HDR =>
          lk_g <= m_rd(15 downto 0);                   -- the root (bytes 8-9)
          st <= LK_HDR2;
        when LK_HDR2 =>
          if lk_g = 0 then
            q_addr <= (others => '0'); st <= lk_ret;
          else
            mem_read(lk_blk + (lk_g & "0000"), LK_CELL);
          end if;
        when LK_CELL =>
          if q_col = resize(m_rd(23 downto 0), 32) then
            q_addr <= lk_blk + (lk_g & "0000"); st <= lk_ret;
          elsif q_col < resize(m_rd(23 downto 0), 32) then
            lk_g <= x"0" & m_rd(51 downto 40); st <= LK_CELL2;     -- left
          else
            lk_g <= x"0" & m_rd(63 downto 52); st <= LK_CELL2;     -- right
          end if;
        when LK_CELL2 =>
          if abort = '1' then fault(ERR_ABORTED);
          else st <= LK_HDR2; end if;

        -- FIND_CELL
        when F_DONE =>
          result <= x"0" & q_addr; wr <= '1'; st <= S_FINISH;

        -- --------------------------------------------------------------
        -- REBALANCE_ROW, rows row..rlast
        when B_ROW =>
          if row > rlast or row >= nrows then
            st <= S_FINISH;
          elsif abort = '1' then
            fault(ERR_ABORTED);
          else
            mem_read(rowtab + (row(25 downto 0) & "00"), B_ROW2);
          end if;
        when B_ROW2 =>
          if row(0) = '0' then e := x"00000000" & m_rd(31 downto 0);
          else e := x"00000000" & m_rd(63 downto 32); end if;
          if e(31 downto 0) = x"FFFFFFFF" then
            row <= row + 1;
            st <= B_ROW;
          else
            blk <= e(27 downto 0);
            mem_read(e(27 downto 0), B_HDR0);
          end if;
        when B_HDR0 =>
          rh0 <= m_rd;
          mem_read(blk + 8, B_HDR1);
        when B_HDR1 =>
          rh1 <= m_rd;
          st <= B_HCHK;
        when B_HCHK =>
          -- row number, first free granule within the block (<= 4096)
          if rh0(31 downto 0) /= row or rh1(31 downto 16) = 0 or rh1(31 downto 16) > rh0(47 downto 32)
            or rh0(47 downto 32) > 4096 then
            format_fault(row);
          else
            gfree <= rh1(31 downto 16);
            g <= to_unsigned(1, 16);
            l_n <= 0;
            st <= B_WALK;
          end if;
        when B_WALK =>
          if g >= gfree then
            l_i <= 1;
            st <= B_SORT;
          else
            mem_read(blk + (g & "0000"), B_WALK2);
          end if;
        when B_WALK2 =>
          if m_rd(39 downto 32) = 0 or resize(g, 17) + resize(m_rd(39 downto 32), 17) > resize(gfree, 17) then
            format_fault(row);
          elsif m_rd(27 downto 24) /= K_FREE and l_n = max_row_cells then
            format_fault(row);                  -- (more cells than the list holds)
          else
            if m_rd(27 downto 24) /= K_FREE then
              list(l_n) <= m_rd(23 downto 0) & g & m_rd(39 downto 24) & x"00";
              l_n <= l_n + 1;
            end if;
            g <= g + m_rd(39 downto 32);
            st <= B_WALK;
          end if;

        -- the list RAM's read: l_rd is valid in l_ret
        when L_WAIT =>
          st <= l_ret;

        -- insertion sort by column (bits 63:48): list(0..l_i-1) is sorted
        when B_SORT =>
          if l_i >= l_n then
            sp <= 0;
            st <= B_TREE;
          else
            l_ra <= l_i; l_ret <= B_SORT1; st <= L_WAIT;
          end if;
        when B_SORT1 =>
          l_key <= l_rd;
          l_j <= l_i;
          st <= B_SORT2;
        when B_SORT2 =>                         -- compare with list(l_j - 1)
          if l_j = 0 then
            st <= B_SORT4;
          else
            l_ra <= l_j - 1; l_ret <= B_SORT3; st <= L_WAIT;
          end if;
        when B_SORT3 =>
          if l_rd(63 downto 40) = l_key(63 downto 40) then
            format_fault(row);                  -- two cells in one column
          elsif l_rd(63 downto 40) > l_key(63 downto 40) then
            list(l_j) <= l_rd;
            l_j <= l_j - 1;
            st <= B_SORT2;
          else
            st <= B_SORT4;
          end if;
        when B_SORT4 =>
          list(l_j) <= l_key;
          l_i <= l_i + 1;
          st <= B_SORT;

        -- the tree: ranges from the stack; each node's children are the
        -- middles of its two halves, so its header is written at once
        when B_TREE =>
          g_root <= (others => '0');
          first_node <= true;
          if l_n = 0 then
            st <= B_RHDR;
          else
            stk(0) <= to_unsigned(0, 11) & to_unsigned(l_n - 1, 11);
            sp <= 1;
            st <= B_TREE2;
          end if;
        when B_TREE2 =>
          if sp = 0 then
            st <= B_RHDR;
          elsif abort = '1' then
            fault(ERR_ABORTED);
          else
            lo := to_integer(stk(sp - 1)(21 downto 11));
            hi := to_integer(stk(sp - 1)(10 downto 0));
            md := mid_of(lo, hi);
            t_lo <= lo; t_hi <= hi; t_mid <= md;
            -- the halves onto the stack in its place (right first: left pops first)
            if md + 1 <= hi and lo <= md - 1 then
              stk(sp - 1) <= to_unsigned(md + 1, 11) & to_unsigned(hi, 11);
              stk(sp) <= to_unsigned(lo, 11) & to_unsigned(md - 1, 11);
              sp <= sp + 1;
            elsif md + 1 <= hi then
              stk(sp - 1) <= to_unsigned(md + 1, 11) & to_unsigned(hi, 11);
            elsif lo <= md - 1 then
              stk(sp - 1) <= to_unsigned(lo, 11) & to_unsigned(md - 1, 11);
            else
              sp <= sp - 1;
            end if;
            l_ra <= md; l_ret <= B_TREE3; st <= L_WAIT;
          end if;
        when B_TREE3 =>                         -- the node
          l_cur <= l_rd;
          if first_node then g_root <= l_rd(39 downto 24); end if;
          first_node <= false;
          g_left <= (others => '0'); g_right <= (others => '0');
          if t_lo <= t_mid - 1 then
            l_ra <= mid_of(t_lo, t_mid - 1); l_ret <= B_TREE4; st <= L_WAIT;
          else
            st <= B_TREE5;
          end if;
        when B_TREE4 =>                         -- its left child
          g_left <= l_rd(39 downto 24);
          st <= B_TREE5;
        when B_TREE5 =>
          if t_mid + 1 <= t_hi then
            l_ra <= mid_of(t_mid + 1, t_hi); l_ret <= B_TREE6; st <= L_WAIT;
          else
            st <= B_TREE7;
          end if;
        when B_TREE6 =>                         -- its right child
          g_right <= l_rd(39 downto 24);
          st <= B_TREE7;
        when B_TREE7 =>                         -- the node's header
          mem_write(blk + (l_cur(39 downto 24) & "0000"),
                    g_right(11 downto 0) & g_left(11 downto 0) & l_cur(23 downto 8) & l_cur(63 downto 40),
                    "11111111", B_TREE2);

        when B_RHDR =>
          -- the cell count (bytes 6-7)
          mem_write(blk, to_unsigned(l_n, 16) & rh0(47 downto 0), "11111111", B_NEXT);
        when B_NEXT =>
          -- the root (bytes 8-9), the stale flag (bytes 14-15) cleared
          mem_write(blk + 8, rh1(63 downto 49) & '0' & rh1(47 downto 16) & g_root, "11111111", B_ROW);
          row <= row + 1;

        -- --------------------------------------------------------------
        -- RECALC: the descriptor's counters
        when RC_D16 =>
          cl <= m_rd(31 downto 0); cap <= m_rd(63 downto 32);
          mem_read(desc + 24, RC_D24);
        when RC_D24 =>
          pcl <= m_rd(31 downto 0); round_n <= m_rd(63 downto 32);
          mem_read(desc + 32, RC_D32);
        when RC_D32 =>
          n_chg <= m_rd(31 downto 0); n_evals <= m_rd(63 downto 32);
          mem_read(desc + 40, RC_D40);
        when RC_D40 =>
          n_errs <= m_rd(31 downto 0); d44 <= m_rd(63 downto 32);
          mem_read(desc + 48, RC_D48);
        when RC_D48 =>
          d48 <= m_rd(31 downto 0); prev_chg <= m_rd(63 downto 32);
          if r_z(0) = '1' then                      -- BEGIN
            n_chg <= (others => '0'); n_evals <= (others => '0'); n_errs <= (others => '0');
            d44(1 downto 0) <= "00";
          end if;
          cnt_loaded <= true;
          call_chg <= (others => '0');
          row <= r_a;
          st <= RC_ROW;

        -- rows r_a..r_b
        when RC_ROW =>
          if row > r_b or row >= nrows then
            st <= RC_CW1; cw_ret <= RC_END;
          else
            mem_read(rowtab + (row(25 downto 0) & "00"), RC_ROW2);
          end if;
        when RC_ROW2 =>
          if row(0) = '0' then e := x"00000000" & m_rd(31 downto 0);
          else e := x"00000000" & m_rd(63 downto 32); end if;
          if e(31 downto 0) = x"FFFFFFFF" then
            row <= row + 1;
            st <= RC_ROW;
          else
            blk <= e(27 downto 0);
            mem_read(e(27 downto 0), RC_HDR0);
          end if;
        when RC_HDR0 =>
          rh0 <= m_rd;
          mem_read(blk + 8, RC_HDR1);
        when RC_HDR1 =>
          rh1 <= m_rd;
          st <= RC_HCHK;
        when RC_HCHK =>
          if rh0(31 downto 0) /= row or rh1(31 downto 16) = 0 or rh1(31 downto 16) > rh0(47 downto 32)
            or rh0(47 downto 32) > 4096 then
            format_fault(row);
          else
            gfree <= rh1(31 downto 16);
            g <= to_unsigned(1, 16);
            row_chg <= (others => '0');
            st <= RC_WALK;
          end if;
        -- the row's cells in memory order
        when RC_WALK =>
          if abort = '1' then
            fault(ERR_ABORTED);
          elsif g >= gfree then
            -- the row's changed count (bytes 12-13)
            mem_write(blk + 8, x"0000" & row_chg & x"00000000", "00110000", RC_RCHG);
          else
            mem_read(blk + (g & "0000"), RC_WALK2);
          end if;
        when RC_RCHG =>
          row <= row + 1;
          st <= RC_ROW;
        when RC_WALK2 =>
          hdr <= m_rd;
          cell <= blk + (g & "0000");
          if m_rd(39 downto 32) = 0 or resize(g, 17) + resize(m_rd(39 downto 32), 17) > resize(gfree, 17) then
            format_fault(row);
          elsif m_rd(27 downto 24) = K_FORMULA and resize(m_rd(23 downto 0), 32) >= r_c
            and resize(m_rd(23 downto 0), 32) <= r_d then
            mem_read(blk + (g & "0000") + 8, RC_FMT);
          else
            st <= E_NEXTCELL;
          end if;
        when RC_FMT =>                          -- the format (its byte 2: fixed point)
          fk <= m_rd(23 downto 16);
          mem_read(cell + 16, RC_RES);
        when RC_RES =>                          -- the result as stored
          old_v <= m_rd;
          mem_read(cell + 24, RC_INFO);
        when RC_INFO =>                         -- its kind, the bytecode's length
          old_rk <= m_rd(7 downto 0);
          bclen <= m_rd(31 downto 16);
          pc <= (others => '0');
          esp <= 0;
          bf_valid <= false;
          st <= E_NEXT;
        when E_NEXTCELL =>
          g <= g + hdr(39 downto 32);
          st <= RC_WALK;

        -- the counters back into the descriptor, then cw_ret
        when RC_CW1 =>
          mem_write(desc + 32, n_evals & n_chg, "11111111", RC_CW2);
        when RC_CW2 =>
          mem_write(desc + 40, d44 & n_errs, "11111111", cw_ret);

        -- END: compare with the previous round's list, swap the lists,
        -- the round counter, this round's count as the previous one
        when RC_END =>
          if r_z(1) = '0' then
            st <= RC_FIN;
          elsif pcl = 0 then
            swap <= false;
            st <= RC_SW2;
          else
            swap <= true;
            same <= n_chg = prev_chg and n_chg <= cap;
            cmp_i <= (others => '0');
            st <= RC_CMP;
          end if;
        when RC_CMP =>
          if not same or cmp_i >= n_chg then
            if same then d44(1) <= '1'; else d44(1) <= '0'; end if;
            st <= RC_SW1;
          else
            mem_read(cl(27 downto 0) + (cmp_i(24 downto 0) & "000"), RC_CMP2);
          end if;
        when RC_CMP2 =>
          cmp_a <= m_rd;
          mem_read(pcl(27 downto 0) + (cmp_i(24 downto 0) & "000"), RC_CMP3);
        when RC_CMP3 =>
          if m_rd /= cmp_a then same <= false; end if;
          cmp_i <= cmp_i + 1;
          st <= RC_CMP;
        when RC_SW1 =>                          -- the flags again
          mem_write(desc + 40, d44 & n_errs, "11111111", RC_SW3);
        when RC_SW3 =>                          -- the list address: the previous one's
          mem_write(desc + 16, cap & pcl, "00001111", RC_SW2);
        when RC_SW2 =>                          -- the round counter, and the previous list
          if swap then
            mem_write(desc + 24, (round_n + 1) & cl, "11111111", RC_PREV);
          else
            mem_write(desc + 24, (round_n + 1) & pcl, "11110000", RC_PREV);
          end if;
        when RC_PREV =>                         -- the previous round's count (bytes 52-55)
          mem_write(desc + 48, n_chg & d48, "11110000", RC_FIN);
        when RC_FIN =>
          result <= call_chg; wr <= '1';
          cnt_loaded <= false;
          st <= S_FINISH;

        -- --------------------------------------------------------------
        -- The byte reader: bytecode byte pc of the cell (at cell + 32)
        when BF =>
          if pc >= bclen then
            e_abort(E_STACK);
          else
            ad := cell + 32 + pc;
            if bf_valid and ad(27 downto 3) = bf_tag then
              bf_byte <= bf_data(to_integer(ad(2 downto 0)) * 8 + 7 downto to_integer(ad(2 downto 0)) * 8);
              pc <= pc + 1;
              st <= fb_ret;
            else
              mem_read(ad, BF_FILL);
            end if;
          end if;
        when BF_FILL =>
          ad := cell + 32 + pc;
          bf_data <= m_rd; bf_tag <= ad(27 downto 3); bf_valid <= true;
          st <= BF;

        -- multi-byte operands: fb_n bytes into imm (little-endian, or
        -- big-endian: references), then imm_ret
        when E_IMM =>
          if fb_i = fb_n then
            st <= imm_ret;
          else
            fetch(E_IMM2);
          end if;
        when E_IMM2 =>
          if fb_be then
            imm <= imm(55 downto 0) & bf_byte;
          else
            imm(to_integer(fb_i) * 8 + 7 downto to_integer(fb_i) * 8) <= bf_byte;
          end if;
          fb_i <= fb_i + 1;
          st <= E_IMM;

        -- the next item
        when E_NEXT =>
          fetch(E_OP);
        when E_OP =>
          cur_op <= bf_byte;
          if bf_byte(7) = '1' then                -- a short reference
            imm <= x"00000000000000" & bf_byte; fb_i <= x"1"; fb_n <= x"4"; fb_be <= true;
            imm_ret <= E_SREF; st <= E_IMM;
          else
            case bf_byte is
              when x"00" =>                       -- END
                if esp /= 1 then e_abort(E_STACK); else st <= E_STORE; end if;
              when x"01" =>                       -- I8
                imm <= (others => '0'); fb_i <= x"0"; fb_n <= x"1"; fb_be <= false;
                imm_ret <= E_I8; st <= E_IMM;
              when x"02" =>                       -- I32
                imm <= (others => '0'); fb_i <= x"0"; fb_n <= x"4"; fb_be <= false;
                imm_ret <= E_I32; st <= E_IMM;
              when x"03" =>                       -- I64
                imm <= (others => '0'); fb_i <= x"0"; fb_n <= x"8"; fb_be <= false;
                imm_ret <= E_I64; st <= E_IMM;
              when x"07" =>                       -- REF (the long form)
                imm <= (others => '0'); fb_i <= x"0"; fb_n <= x"6"; fb_be <= true;
                imm_ret <= E_LREF; st <= E_IMM;
              when x"10" | x"11" | x"12" | x"18" | x"19" | x"1A" | x"1B" | x"1C" | x"1D" =>
                st <= E_BIN;
              when x"15" =>
                st <= E_NEG;
              when x"06" =>                       -- FIX: one byte
                fetch(E_FIX);
              -- (not in hardware yet: the rest of section 5.4)
              when x"13" =>
                st <= E_BIN;
              when x"04" =>                       -- F64
                imm <= (others => '0'); fb_i <= x"0"; fb_n <= x"8"; fb_be <= false;
                imm_ret <= E_STF; st <= E_IMM;
              when x"05" | x"08" | x"09" | x"0A" | x"0B" | x"0C" | x"0D"
                 | x"14" | x"16" | x"17" =>
                e_abort(E_NAME);
              when others =>
                e_abort(E_STACK);
            end case;
          end if;
        when E_I8 =>
          push(VK_I, unsigned(resize(signed(imm(7 downto 0)), 64)), x"00", '0', E_NEXT);
        when E_I32 =>
          push(VK_I, unsigned(resize(signed(imm(31 downto 0)), 64)), x"00", '0', E_NEXT);
        when E_I64 =>
          push(VK_I, imm, x"00", '0', E_NEXT);

        -- references: the cell, relative to the formula's own (row, col)
        when E_SREF =>
          if imm(30) = '1' then rr := resize(imm(29 downto 15), 32);
          else rr := (row + sext15(imm(29 downto 15))) and x"000FFFFF"; end if;
          if imm(14) = '1' then cc := resize(imm(13 downto 0), 32);
          else cc := (resize(hdr(23 downto 0), 32) + sext14(imm(13 downto 0))) and x"00FFFFFF"; end if;
          q_row <= rr; q_col <= cc;
          st <= E_RESOLVE;
        when E_LREF =>
          if imm(47) = '1' then rr := resize(imm(43 downto 24), 32);
          else rr := (row + resize(imm(43 downto 24), 32)) and x"000FFFFF"; end if;
          if imm(46) = '1' then cc := resize(imm(23 downto 0), 32);
          else cc := (resize(hdr(23 downto 0), 32) + resize(imm(23 downto 0), 32)) and x"00FFFFFF"; end if;
          q_row <= rr; q_col <= cc;
          st <= E_RESOLVE;
        when E_RESOLVE =>
          if q_row >= nrows or q_col >= ncols then
            push(VK_E, x"00000000000000" & E_REF, x"00", '1', E_NEXT);
          else
            lk_ret <= VL_HDR; st <= LK_START;
          end if;

        -- the referenced cell's value (q_addr; 0: no cell)
        when VL_HDR =>
          if q_addr = 0 then
            push(VK_Z, (others => '0'), x"00", '1', E_NEXT);
          else
            mem_read(q_addr, VL_V8);
          end if;
        when VL_V8 =>
          v_hdr <= m_rd;
          case m_rd(27 downto 24) is
            when K_EMPTY =>
              push(VK_Z, (others => '0'), x"00", '1', E_NEXT);
            when K_TEXT =>
              push(VK_T, (others => '0'), x"00", '1', E_NEXT);
            when K_UNCOMPILED =>
              push(VK_E, x"00000000000000" & E_COMPILE, x"00", '1', E_NEXT);
            when K_F64 | K_I64 | K_I32 | K_ERROR | K_FORMULA =>
              mem_read(q_addr + 8, VL_FMT);
            when others =>
              push(VK_Z, (others => '0'), x"00", '1', E_NEXT);
          end case;
        when VL_FMT =>                          -- the group at +8
          v_val <= m_rd;
          case v_hdr(27 downto 24) is
            when K_F64 =>
              if m_rd(62 downto 52) = 0 then        -- (subnormals flushed to zero)
                push(VK_F, m_rd(63) & "000" & x"000000000000000", x"00", '1', E_NEXT);
              else
                push(VK_F, m_rd, x"00", '1', E_NEXT);
              end if;
            when K_ERROR =>
              push(VK_E, x"00000000000000" & m_rd(7 downto 0), x"00", '1', E_NEXT);
            when K_I64 | K_I32 =>
              if v_hdr(30) = '1' then               -- HAS_FORMAT: its fixed point
                mem_read(q_addr + 16, VL_F16);
              elsif v_hdr(27 downto 24) = K_I32 then
                push(VK_I, unsigned(resize(signed(m_rd(31 downto 0)), 64)), x"00", '1', E_NEXT);
              else
                push(VK_I, m_rd, x"00", '1', E_NEXT);
              end if;
            when others =>                        -- FORMULA: its result, kind
              mem_read(q_addr + 24, VL_F24);
          end case;
        when VL_F16 =>                          -- a number's format: byte 2
          if v_hdr(27 downto 24) = K_I32 then
            push(VK_I, unsigned(resize(signed(v_val(31 downto 0)), 64)), m_rd(23 downto 16), '1', E_NEXT);
          else
            push(VK_I, v_val, m_rd(23 downto 16), '1', E_NEXT);
          end if;
        when VL_F24 =>                          -- a formula's result kind
          case m_rd(3 downto 0) is
            when K_F64 | K_I64 | K_I32 | K_ERROR | K_TEXT =>
              q_addr <= q_addr;                 -- (the result itself next)
              cmp_a <= m_rd;
              mem_read(q_addr + 16, VL_F8);
            when others =>
              push(VK_Z, (others => '0'), x"00", '1', E_NEXT);
          end case;
        when VL_F8 =>                           -- (cmp_a: the kind; v_val: the format group)
          case cmp_a(3 downto 0) is
            when K_F64 =>
              if m_rd(62 downto 52) = 0 then
                push(VK_F, m_rd(63) & "000" & x"000000000000000", x"00", '1', E_NEXT);
              else
                push(VK_F, m_rd, x"00", '1', E_NEXT);
              end if;
            when K_I64 | K_I32 =>
              push(VK_I, m_rd, v_val(23 downto 16), '1', E_NEXT);
            when K_ERROR =>
              push(VK_E, x"00000000000000" & m_rd(7 downto 0), x"00", '1', E_NEXT);
            when others =>                        -- text
              push(VK_T, (others => '0'), x"00", '1', E_NEXT);
          end case;

        -- --------------------------------------------------------------
        -- The multiplier: mu_x * mu_y, then mu_ret
        when MU_START =>
          if mu_x(63) = '1' then mu_a <= unsigned(-signed(mu_x)); else mu_a <= mu_x; end if;
          if mu_y(63) = '1' then mu_b <= unsigned(-signed(mu_y)); else mu_b <= mu_y; end if;
          mu_neg <= (mu_x(63) xor mu_y(63)) = '1';
          mu_hi <= (others => '0'); mu_lo <= (others => '0'); mu_n <= 0;
          st <= MU_STEP;
        when MU_STEP =>
          if mu_n = 64 then
            st <= mu_ret;
          else
            if mu_b(0) = '1' then sum := mu_hi + ('0' & mu_a); else sum := mu_hi; end if;
            mu_hi <= '0' & sum(64 downto 1);
            mu_lo <= sum(0) & mu_lo(63 downto 1);
            mu_b <= '0' & mu_b(63 downto 1);
            mu_n <= mu_n + 1;
          end if;
        -- The divider: dv_n / dv_d, the quotient rounded half away, then dv_ret
        when DV_START =>
          dv_r <= (others => '0'); dv_q <= (others => '0'); dv_i <= 0;
          st <= DV_STEP;
        when DV_STEP =>
          if dv_i = 128 then
            st <= DV_ROUND;
          else
            sum := dv_r(63 downto 0) & dv_n(127);
            if sum >= ('0' & dv_d) then
              dv_r <= sum - ('0' & dv_d); dv_q <= dv_q(126 downto 0) & '1';
            else
              dv_r <= sum; dv_q <= dv_q(126 downto 0) & '0';
            end if;
            dv_n <= dv_n(126 downto 0) & '0';
            dv_i <= dv_i + 1;
          end if;
        when DV_ROUND =>                        -- 2r >= d: away from zero
          if not dv_raw and (dv_r(63 downto 0) & '0') >= ('0' & dv_d) then dv_q <= dv_q + 1; end if;
          st <= dv_ret;

        -- --------------------------------------------------------------
        -- binary operators: a (below the top) op b (the top)
        when E_BIN =>
          if esp < 2 then
            e_abort(E_STACK);
          else
            ent := est(esp - 2);
            ka := ent(75 downto 73); va := ent(63 downto 0);
            kb := t_kind; vb := t_v;
            fa := ent(71 downto 64); fb := t_k;
            -- blank is 0; text is #VALUE!
            if ka = VK_Z then ka := VK_I; va := (others => '0'); fa := x"00"; end if;
            if kb = VK_Z then kb := VK_I; vb := (others => '0'); fb := x"00"; end if;
            esp <= esp - 1;
            t_ref <= '0'; t_k <= x"00";
            st <= E_NEXT;
            xa <= va; xb <= vb;
            if ka = VK_E then
              t_kind <= VK_E; t_v <= va;
            elsif ka /= VK_I and ka /= VK_F then
              t_kind <= VK_E; t_v <= x"00000000000000" & E_VALUE;
            elsif ka = VK_I and bad_k(fa) then
              t_kind <= VK_E; t_v <= x"00000000000000" & E_NUM;
            elsif kb = VK_E then
              t_kind <= VK_E; t_v <= vb;
            elsif kb /= VK_I and kb /= VK_F then
              t_kind <= VK_E; t_v <= x"00000000000000" & E_VALUE;
            elsif kb = VK_I and bad_k(fb) then
              t_kind <= VK_E; t_v <= x"00000000000000" & E_NUM;
            elsif ka = VK_I and kb = VK_I and
              not (fa(6 downto 0) /= 0 and fb(6 downto 0) /= 0 and fa(7) /= fb(7)) then
              -- integers whose fixed points align (the same base, or one plain)
              if fa(6 downto 0) /= 0 then bin := fa(7); else bin := fb(7); end if;
              case cur_op is
                when x"10" | x"11" | x"18" | x"19" | x"1A" | x"1B" | x"1C" | x"1D" =>
                  -- align to the larger fixed point (exactly), then add / compare
                  if fa(6 downto 0) >= fb(6 downto 0) then kk := fa(6 downto 0);
                  else kk := fb(6 downto 0); end if;
                  if kk /= 0 then x_k <= bin & kk; else x_k <= x"00"; end if;
                  if fa(6 downto 0) = fb(6 downto 0) then
                    st <= E_ARITH;
                  elsif fa(6 downto 0) < fb(6 downto 0) then
                    mu_x <= va; mu_y <= pw(fb(6 downto 0) - fa(6 downto 0), bin);
                    sc_b <= false; mu_ret <= E_SCALED; st <= MU_START;
                  else
                    mu_x <= vb; mu_y <= pw(fa(6 downto 0) - fb(6 downto 0), bin);
                    sc_b <= true; mu_ret <= E_SCALED; st <= MU_START;
                  end if;
                when x"12" =>                     -- multiply: the fixed points add
                  kk := fa(6 downto 0) + fb(6 downto 0);
                  if (bin = '1' and kk > 62) or (bin = '0' and kk > 18) then
                    st <= E_F64;                  -- (past the limits: F64)
                  else
                    if kk /= 0 then x_k <= bin & kk; else x_k <= x"00"; end if;
                    mu_x <= va; mu_y <= vb; mu_ret <= E_MULF; st <= MU_START;
                  end if;
                when others =>                    -- x"13": divide
                  if vb = 0 then
                    t_kind <= VK_E; t_v <= x"00000000000000" & E_DIV0;
                  elsif fa(6 downto 0) /= 0 and fa = fb and bin = '0' then
                    -- the same decimal fixed point: (a * 10^k) / b, rounded
                    x_k <= fa;
                    mu_x <= va; mu_y <= pw(fa(6 downto 0), '0'); mu_ret <= E_DIVM; st <= MU_START;
                  else
                    st <= E_F64;
                  end if;
              end case;
            else
              st <= E_F64;                        -- F64 (or mixed): both to F64
            end if;
            fx_a <= va; fx_b <= vb; fx_ka <= ka; fx_kb <= kb; fx_fa <= fa; fx_fb <= fb;
          end if;
        when E_SCALED =>                        -- the scaled operand, unless it overflowed
          if mu_hi /= 0 or (mu_lo(63) = '1' and not (mu_neg and mu_lo = x"8000000000000000")) then
            t_kind <= VK_E; t_v <= x"00000000000000" & E_NUM; st <= E_NEXT;
          else
            if mu_neg then e := unsigned(-signed(mu_lo)); else e := mu_lo; end if;
            if sc_b then xb <= e; else xa <= e; end if;
            st <= E_ARITH;
          end if;
        when E_ARITH =>                         -- xa op xb, aligned
          lt := signed(xa) < signed(xb); eq := xa = xb;
          t_kind <= VK_I; t_k <= x"00";
          st <= E_NEXT;
          case cur_op is
            when x"10" | x"11" =>
              if cur_op = x"10" then sum := unsigned(resize(signed(xa), 65) + resize(signed(xb), 65));
              else sum := unsigned(resize(signed(xa), 65) - resize(signed(xb), 65)); end if;
              if sum(64) /= sum(63) then t_kind <= VK_E; t_v <= x"00000000000000" & E_NUM;
              else t_v <= sum(63 downto 0); t_k <= x_k; end if;
            when x"18" => t_v <= b64(eq);
            when x"19" => t_v <= b64(not eq);
            when x"1A" => t_v <= b64(lt);
            when x"1B" => t_v <= b64(lt or eq);
            when x"1C" => t_v <= b64(not (lt or eq));
            when others => t_v <= b64(not lt);
          end case;
        when E_MULF =>                          -- the product, signed back
          st <= E_NEXT;
          if mu_hi /= 0 or (mu_lo(63) = '1' and not (mu_neg and mu_lo = x"8000000000000000")) then
            t_kind <= VK_E; t_v <= x"00000000000000" & E_NUM;
          else
            t_kind <= VK_I; t_k <= x_k;
            if mu_neg then t_v <= unsigned(-signed(mu_lo)); else t_v <= mu_lo; end if;
          end if;
        when E_DIVM =>                          -- a * 10^k (128 bits) / |b|
          dv_n <= mu_hi(63 downto 0) & mu_lo;
          if xb(63) = '1' then dv_d <= unsigned(-signed(xb)); else dv_d <= xb; end if;
          dv_neg <= mu_neg xor (xb(63) = '1');
          dv_raw <= false; dv_ret <= E_DIVF; st <= DV_START;
        when E_DIVF =>
          st <= E_NEXT;
          if dv_q(127 downto 64) /= 0 or (dv_q(63) = '1' and not (dv_neg and dv_q(63 downto 0) = x"8000000000000000")) then
            t_kind <= VK_E; t_v <= x"00000000000000" & E_NUM;
          else
            t_kind <= VK_I; t_k <= x_k;
            if dv_neg then t_v <= unsigned(-signed(dv_q(63 downto 0))); else t_v <= dv_q(63 downto 0); end if;
          end if;
        when E_FIX =>                           -- the top, an integer, is fixed point
          st <= E_NEXT;
          if esp < 1 then
            e_abort(E_STACK);
          elsif t_kind = VK_I then
            t_k <= bf_byte; t_ref <= '0';
          elsif t_kind /= VK_E then
            t_kind <= VK_E; t_v <= x"00000000000000" & E_VALUE; t_ref <= '0';
          else
            t_ref <= '0';
          end if;
        when E_NEG =>
          st <= E_NEXT;
          if esp < 1 then
            e_abort(E_STACK);
          elsif t_kind = VK_Z then
            t_kind <= VK_I; t_v <= (others => '0'); t_ref <= '0';
          elsif t_kind = VK_I then
            if t_v = x"8000000000000000" or bad_k(t_k) then t_kind <= VK_E; t_v <= x"00000000000000" & E_NUM;
            else t_v <= unsigned(-signed(t_v)); end if;
            t_ref <= '0';
          elsif t_kind = VK_F then
            t_v(63) <= not t_v(63); t_ref <= '0';
          elsif t_kind /= VK_E then
            t_kind <= VK_E; t_v <= x"00000000000000" & E_VALUE;
          end if;

        -- --------------------------------------------------------------
        -- --------------------------------------------------------------
        -- F64 arithmetic: a and b (fx_*) to F64, then fp_op (or a compare)
        when E_STF =>                           -- the F64 constant
          push(VK_F, ftz(imm), x"00", '0', E_NEXT);
        when E_F64 =>
          if fx_ka = VK_I then
            cv_v <= fx_a; cv_k <= fx_fa; cv_ret <= E_FB1; cv_step <= 0; st <= CV_START;
          else
            fp_r <= fx_a; st <= E_FB1;
          end if;
        when E_FB1 =>
          fx_a <= fp_r;
          if fx_kb = VK_I then
            cv_v <= fx_b; cv_k <= fx_fb; cv_ret <= E_FB2; cv_step <= 0; st <= CV_START;
          else
            fp_r <= fx_b; st <= E_FB2;
          end if;
        when E_FB2 =>
          fx_b <= fp_r;
          st <= E_FB3;
        when E_FB3 =>
          t_kind <= VK_I; t_k <= x"00"; t_ref <= '0';
          st <= E_NEXT;
          case cur_op is
            when x"18" => t_v <= b64(f_eq(fx_a, fx_b));
            when x"19" => t_v <= b64(not f_eq(fx_a, fx_b));
            when x"1A" => t_v <= b64(f_lt(fx_a, fx_b));
            when x"1B" => t_v <= b64(f_lt(fx_a, fx_b) or f_eq(fx_a, fx_b));
            when x"1C" => t_v <= b64(f_lt(fx_b, fx_a));
            when x"1D" => t_v <= b64(f_lt(fx_b, fx_a) or f_eq(fx_a, fx_b));
            when x"13" =>
              if f_zero(fx_b) then
                t_kind <= VK_E; t_v <= x"00000000000000" & E_DIV0;
              else
                fp_a <= fx_a; fp_b <= fx_b; fp_op <= FP_DIV; fp_ret <= E_FBR; st <= FP_START;
              end if;
            when x"10" => fp_a <= fx_a; fp_b <= fx_b; fp_op <= FP_ADD; fp_ret <= E_FBR; st <= FP_START;
            when x"11" => fp_a <= fx_a; fp_b <= fx_b; fp_op <= FP_SUB; fp_ret <= E_FBR; st <= FP_START;
            when others => fp_a <= fx_a; fp_b <= fx_b; fp_op <= FP_MUL; fp_ret <= E_FBR; st <= FP_START;
          end case;
        when E_FBR =>
          t_kind <= VK_F; t_v <= fp_r;
          st <= E_NEXT;

        -- conversions: cv_v (fixed point cv_k) to F64 in fp_r, then cv_ret:
        -- F64(v), then / F64(10^k) (decimal) or scaled by 2^-k (binary)
        when CV_START =>
          if cv_v = 0 then
            fp_r <= (others => '0');
            st <= cv_ret;
          else
            fn_s <= cv_v(63);
            if cv_v(63) = '1' then fn_sig <= unsigned(-signed(cv_v)); else fn_sig <= cv_v; end if;
            fn_e <= to_signed(1023 + 63, 14); fn_st <= '0';
            fn_ret <= CV_I2F; st <= FN_NORM;
          end if;
        when CV_I2F =>
          if cv_k(6 downto 0) = 0 then
            st <= cv_ret;
          elsif cv_k(7) = '1' then                -- binary: the exponent, rounded again
            fn_s <= fp_r(63);
            fn_sig <= '1' & fp_r(51 downto 0) & "00000000000";
            fn_e <= signed(resize(fp_r(62 downto 52), 14)) - signed(resize(cv_k(6 downto 0), 14));
            fn_st <= '0';
            fn_ret <= CV_SCALE; st <= FN_NORM;
          else                                    -- decimal: / F64(10^k)
            cv_t <= fp_r;
            fn_s <= '0'; fn_sig <= P10(to_integer(cv_k(6 downto 0)));
            fn_e <= to_signed(1023 + 63, 14); fn_st <= '0';
            fn_ret <= CV_DIV; st <= FN_NORM;
          end if;
        when CV_SCALE =>
          st <= cv_ret;
        when CV_DIV =>
          fp_a <= cv_t; fp_b <= fp_r; fp_op <= FP_DIV; fp_ret <= cv_ret; st <= FP_START;

        -- the operation fp_op on fp_a, fp_b (no zero divisor), then fp_ret
        when FP_START =>
          case fp_op is
            when FP_ADD | FP_SUB =>
              fa_s <= fp_a(63);
              if fp_op = FP_SUB then fb_s <= not fp_b(63); else fb_s <= fp_b(63); end if;
              st <= FA_ALIGN;
              if f_nan(fp_a) or f_nan(fp_b) then
                fp_r <= F64_NAN; st <= fp_ret;
              elsif f_inf(fp_a) and f_inf(fp_b) then
                if (fp_a(63) = fp_b(63)) = (fp_op = FP_ADD) then fp_r <= fp_a; else fp_r <= F64_NAN; end if;
                st <= fp_ret;
              elsif f_inf(fp_a) then
                fp_r <= fp_a; st <= fp_ret;
              elsif f_inf(fp_b) then
                if fp_op = FP_SUB then fp_r <= (not fp_b(63)) & fp_b(62 downto 0); else fp_r <= fp_b; end if;
                st <= fp_ret;
              end if;
            when FP_MUL =>
              if f_nan(fp_a) or f_nan(fp_b) or (f_inf(fp_a) and f_zero(fp_b)) or (f_zero(fp_a) and f_inf(fp_b)) then
                fp_r <= F64_NAN; st <= fp_ret;
              elsif f_inf(fp_a) or f_inf(fp_b) then
                fp_r <= (fp_a(63) xor fp_b(63)) & "11111111111" & x"0000000000000"; st <= fp_ret;
              elsif f_zero(fp_a) or f_zero(fp_b) then
                fp_r <= (fp_a(63) xor fp_b(63)) & "000" & x"000000000000000"; st <= fp_ret;
              else
                mu_x <= x"00" & "000" & '1' & fp_a(51 downto 0);
                mu_y <= x"00" & "000" & '1' & fp_b(51 downto 0);
                mu_ret <= FM_PROD; st <= MU_START;
              end if;
            when others =>                        -- FP_DIV
              if f_nan(fp_a) or f_nan(fp_b) or (f_inf(fp_a) and f_inf(fp_b)) then
                fp_r <= F64_NAN; st <= fp_ret;
              elsif f_inf(fp_a) then
                fp_r <= (fp_a(63) xor fp_b(63)) & "11111111111" & x"0000000000000"; st <= fp_ret;
              elsif f_inf(fp_b) or f_zero(fp_a) then
                fp_r <= (fp_a(63) xor fp_b(63)) & "000" & x"000000000000000"; st <= fp_ret;
              else
                dv_n <= x"000" & '1' & fp_a(51 downto 0) & "000" & x"000000000000000";   -- ma * 2^63
                dv_d <= x"00" & "000" & '1' & fp_b(51 downto 0);
                dv_raw <= true; dv_ret <= FD_QUOT; st <= DV_START;
              end if;
          end case;

        -- add: zeros, then the larger first, the smaller aligned to it
        when FA_ALIGN =>
          if f_zero(fp_a) and f_zero(fp_b) then
            fp_r <= (fa_s and fb_s) & "000" & x"000000000000000"; st <= fp_ret;
          elsif f_zero(fp_b) then
            fp_r <= fp_a; st <= fp_ret;
          elsif f_zero(fp_a) then
            fp_r <= fb_s & fp_b(62 downto 0); st <= fp_ret;
          else
            if fp_a(62 downto 0) >= fp_b(62 downto 0) then
              fa_sig <= '1' & fp_a(51 downto 0) & "00000000000"; fa_e <= signed(resize(fp_a(62 downto 52), 14));
              fb_sig <= '1' & fp_b(51 downto 0) & "00000000000"; fb_e <= signed(resize(fp_b(62 downto 52), 14));
              fa_d <= signed(resize(fp_a(62 downto 52), 14)) - signed(resize(fp_b(62 downto 52), 14));
            else
              fa_sig <= '1' & fp_b(51 downto 0) & "00000000000"; fa_e <= signed(resize(fp_b(62 downto 52), 14));
              fb_sig <= '1' & fp_a(51 downto 0) & "00000000000"; fb_e <= signed(resize(fp_a(62 downto 52), 14));
              fa_d <= signed(resize(fp_b(62 downto 52), 14)) - signed(resize(fp_a(62 downto 52), 14));
              fa_s <= fb_s; fb_s <= fa_s;
            end if;
            fn_st <= '0';
            st <= FA_SHIFT;
          end if;
        when FA_SHIFT =>                        -- one bit a cycle, the lost bits sticky
          if fa_d = 0 then
            st <= FA_SUM;
          elsif fa_d > 64 then
            fn_st <= '1'; fb_sig <= (others => '0'); fa_d <= (others => '0');
          else
            fn_st <= fn_st or fb_sig(0);
            fb_sig <= '0' & fb_sig(63 downto 1);
            fa_d <= fa_d - 1;
          end if;
        when FA_SUM =>
          fn_s <= fa_s; fn_e <= fa_e; fn_ret <= fp_ret;
          if fa_s = fb_s then
            sum := ('0' & fa_sig) + ('0' & fb_sig);
            if sum(64) = '1' then
              fn_sig <= sum(64 downto 1); fn_st <= fn_st or sum(0); fn_e <= fa_e + 1;
            else
              fn_sig <= sum(63 downto 0);
            end if;
            st <= FN_NORM;
          else
            -- with one bit more: the lost bits (sticky) make the difference
            -- odd there, so it is never mistaken for a tie
            sum := (fa_sig & '0') - (fb_sig & fn_st);
            fn_sig <= sum(64 downto 1); fn_st <= sum(0);
            if sum = 0 then
              fp_r <= (others => '0'); st <= fp_ret;    -- x - x = +0
            else
              st <= FN_NORM;
            end if;
          end if;
        -- multiply: the 106-bit product of the significands
        when FM_PROD =>
          fn_s <= fp_a(63) xor fp_b(63); fn_ret <= fp_ret;
          if mu_hi(41) = '1' then                 -- (product bit 105)
            fn_sig <= mu_hi(41 downto 0) & mu_lo(63 downto 42);
            if mu_lo(41 downto 0) /= 0 then fn_st <= '1'; else fn_st <= '0'; end if;
            fn_e <= signed(resize(fp_a(62 downto 52), 14)) + signed(resize(fp_b(62 downto 52), 14)) - 1022;
          else
            fn_sig <= mu_hi(40 downto 0) & mu_lo(63 downto 41);
            if mu_lo(40 downto 0) /= 0 then fn_st <= '1'; else fn_st <= '0'; end if;
            fn_e <= signed(resize(fp_a(62 downto 52), 14)) + signed(resize(fp_b(62 downto 52), 14)) - 1023;
          end if;
          st <= FN_NORM;
        -- divide: the quotient of the significands (times 2^63), its remainder sticky
        when FD_QUOT =>
          fn_s <= fp_a(63) xor fp_b(63); fn_ret <= fp_ret;
          if dv_r /= 0 then fn_st <= '1'; else fn_st <= '0'; end if;
          if dv_q(63) = '1' then
            fn_sig <= dv_q(63 downto 0);
            fn_e <= signed(resize(fp_a(62 downto 52), 14)) - signed(resize(fp_b(62 downto 52), 14)) + 1023;
          else
            fn_sig <= dv_q(62 downto 0) & '0';
            fn_e <= signed(resize(fp_a(62 downto 52), 14)) - signed(resize(fp_b(62 downto 52), 14)) + 1022;
          end if;
          st <= FN_NORM;

        -- normalise (the leading 1 to bit 63), round to nearest even,
        -- subnormal results rounded as IEEE then flushed: fp_r, then fn_ret
        when FN_NORM =>
          if fn_sig = 0 then                      -- (a zero: never, but safe)
            fp_r <= fn_s & "000" & x"000000000000000"; st <= fn_ret;
          elsif fn_sig(63) = '0' then
            fn_sig <= fn_sig(62 downto 0) & '0';
            fn_e <= fn_e - 1;
          else
            fn_sub <= fn_e < 1;
            st <= FN_DEN;
          end if;
        when FN_DEN =>                          -- below the normal range: to exponent 1
          if fn_e < 1 then
            if fn_e < -64 then
              fn_st <= fn_st or b2s(fn_sig /= 0); fn_sig <= (others => '0'); fn_e <= to_signed(1, 14);
            else
              fn_st <= fn_st or fn_sig(0);
              fn_sig <= '0' & fn_sig(63 downto 1);
              fn_e <= fn_e + 1;
            end if;
          else
            st <= FN_RND;
          end if;
        when FN_RND =>                          -- 53 bits: lsb 11, guard 10, sticky below
          if fn_sig(10) = '1' and (fn_sig(11) = '1' or fn_sig(9 downto 0) /= 0 or fn_st = '1') then
            sum := ('0' & fn_sig) + to_unsigned(2048, 65);
            if sum(64) = '1' then
              fn_sig <= x"8000000000000000"; fn_e <= fn_e + 1;
            else
              fn_sig <= sum(63 downto 0);
            end if;
          end if;
          st <= FN_PACK;
        when FN_PACK =>
          st <= fn_ret;
          if fn_sub and fn_sig(63) = '0' then     -- a subnormal: flushed
            fp_r <= fn_s & "000" & x"000000000000000";
          elsif fn_e >= 2047 then
            fp_r <= fn_s & "11111111111" & x"0000000000000";
          else
            fp_r <= fn_s & unsigned(fn_e(10 downto 0)) & fn_sig(62 downto 11);
          end if;

        -- the result (the top) as stored: (new_rk, new_v); an integer
        -- rescaled to the cell's own fixed point fk (section 4)
        when E_STORE =>
          n_evals <= n_evals + 1;
          st <= E_W1;
          case t_kind is
            when VK_Z =>
              new_rk <= x"04"; new_v <= (others => '0');
            when VK_I =>
              new_rk <= x"04"; new_v <= t_v;
              if bad_k(t_k) or bad_k(fk) then
                new_rk <= x"06"; new_v <= x"00000000000000" & E_NUM;
              elsif t_k(6 downto 0) /= 0 and fk(6 downto 0) /= 0 and t_k(7) = fk(7) then
                if fk(6 downto 0) >= t_k(6 downto 0) then        -- exactly up
                  mu_x <= t_v; mu_y <= pw(fk(6 downto 0) - t_k(6 downto 0), fk(7));
                  mu_ret <= E_ST_SC; st <= MU_START;
                else                                              -- down, rounded
                  if t_v(63) = '1' then dv_n <= x"0000000000000000" & unsigned(-signed(t_v));
                  else dv_n <= x"0000000000000000" & t_v; end if;
                  dv_d <= pw(t_k(6 downto 0) - fk(6 downto 0), fk(7));
                  dv_neg <= t_v(63) = '1';
                  dv_raw <= false; dv_ret <= E_ST_DONE; st <= DV_START;
                end if;
              elsif t_k(6 downto 0) = 0 and fk(6 downto 0) /= 0 then
                mu_x <= t_v; mu_y <= pw(fk(6 downto 0), fk(7));
                mu_ret <= E_ST_SC; st <= MU_START;
              elsif t_k(6 downto 0) /= 0 then
                -- no matching fixed point in the cell: as F64
                cv_v <= t_v; cv_k <= t_k; cv_ret <= E_ST_SC; cv_step <= 3; st <= CV_START;
              end if;
            when VK_F =>
              if t_v(62 downto 52) = "11111111111" then
                new_rk <= x"06"; new_v <= x"00000000000000" & E_NUM;
              else
                new_rk <= x"03"; new_v <= t_v;
              end if;
            when VK_E =>
              new_rk <= x"06"; new_v <= x"00000000000000" & t_v(7 downto 0);
            when others =>
              new_rk <= x"06"; new_v <= x"00000000000000" & E_VALUE;
          end case;
        when E_ST_SC =>                         -- scaled up, unless it overflowed
          st <= E_W1;
          if cv_step = 3 then                   -- (or converted to F64)
            cv_step <= 0;
            new_rk <= x"03"; new_v <= fp_r;
          elsif mu_hi /= 0 or (mu_lo(63) = '1' and not (mu_neg and mu_lo = x"8000000000000000")) then
            new_rk <= x"06"; new_v <= x"00000000000000" & E_NUM;
          elsif mu_neg then
            new_v <= unsigned(-signed(mu_lo));
          else
            new_v <= mu_lo;
          end if;
        when E_ST_DONE =>                       -- scaled down
          st <= E_W1;
          if dv_neg then new_v <= unsigned(-signed(dv_q(63 downto 0)));
          else new_v <= dv_q(63 downto 0); end if;
        when E_W1 =>
          if new_rk = x"06" then n_errs <= n_errs + 1; end if;
          if new_rk = old_rk and new_v = old_v then
            st <= E_NEXTCELL;                     -- unchanged
          else
            mem_write(cell + 16, new_v, "11111111", E_W2);
          end if;
        when E_W2 =>
          mem_write(cell + 24, x"00000000000000" & new_rk, "00000001", E_W3);
        when E_W3 =>                            -- the header's flags: CHANGED, ERROR
          e := (others => '0');
          e(31 downto 24) := hdr(31 downto 30) & '0' & '1' & hdr(27 downto 24);
          if new_rk = x"06" then e(29) := '1'; end if;
          mem_write(cell, e, "00001000", E_W4);
          row_chg <= row_chg + 1;
          call_chg <= call_chg + 1;
        when E_W4 =>                            -- the change list
          n_chg <= n_chg + 1;
          if n_chg < cap then
            mem_write(cl(27 downto 0) + (n_chg(24 downto 0) & "000"), resize(hdr(23 downto 0), 32) & row,
                      "11111111", E_NEXTCELL);
          else
            d44(0) <= '1';
            st <= E_NEXTCELL;
          end if;

        when others =>
          st <= S_IDLE;
      end case;
    end if;
  end process;

end rtl;
