-- SHITE: Spreadsheet Hardware Integrated Technology Engine
--
-- SSNAIL's coprocessor for opcodes $40-$4F (see docs/shite/README.md and
-- the reference model SSNAIL/shite.py).  SSNAIL hands over its LUMP ports
-- for the length of an instruction (ssnail_top multiplexes them).
--
-- RECALC ($40), REBALANCE_ROW ($41), FIND_CELL ($42), and through the codec
-- units (shite_formula_codec, shite_cell_text and the shared
-- shite_number_text) FORMAT_CELLS ($43), COMPILE ($44), DECOMPILE ($45),
-- RENDER ($46), PARSE ($47).
-- Memory is reached one 8-byte group at a time (no cache yet).
--
-- Runs on sclock (40.5 MHz on the boards): shite_bridge (clock162) takes SSNAIL's coprocessor
-- port and issues the LUMP commands, the events crossing as toggles
-- (start_t, done_t, g_t, g_ack_t) with their data held meanwhile.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lumptypes.all;
use work.shite_codec_pkg.all;

entity shite is
  generic (
    -- Most cells REBALANCE_ROW sorts in one row (its list RAM)
    max_row_cells : natural := 1024
    );
  port (
    clock : in std_logic;                 -- sclock
    -- from SSNAIL's coprocessor port, through shite_bridge: held from
    -- start_t's change until done_t's
    start_t : in  std_logic;
    op     : in  unsigned(7 downto 0);
    ra     : in  unsigned(31 downto 0);
    rb     : in  unsigned(31 downto 0);
    rc     : in  unsigned(31 downto 0);   -- R[c bits 3-0]
    rd     : in  unsigned(31 downto 0);   -- R[c bits 7-4]
    z      : in  unsigned(31 downto 0);   -- the instruction's Z
    x      : in  unsigned(27 downto 0);
    abort  : in  std_logic;
    done_t : out std_logic := '0';
    err    : out unsigned(7 downto 0) := (others => '0');
    wr     : out std_logic := '0';
    result : out unsigned(31 downto 0) := (others => '0');
    map_hr_base, map_hr_size, map_sd_base, map_sd_size : in unsigned(7 downto 0);
    -- memory, one 8-byte group (shite_bridge issues it): the fields held
    -- from g_t's change until g_ack_t's, with the bytes read or the error
    g_t     : out std_logic := '0';
    g_write : out std_logic;
    g_sd    : out std_logic := '0';
    g_addr  : out unsigned(26 downto 0) := (others => '0');
    g_wd    : out unsigned(63 downto 0);
    g_be    : out std_logic_vector(7 downto 0);
    g_ack_t : in  std_logic;
    g_rd    : in  unsigned(63 downto 0);
    g_err   : in  std_logic
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
    E_PUSHV, E_STR, E_HOST, E_RECT1, E_RECT2, E_CELLS, E_CELLS2, E_CALL1, E_CALL2,
    RF_START, RF_B0, VR_START, VR_B0, VR_B1,
    AG_START, AG_ARG, AG_NEXTARG, AG_RROW, AG_RROW2, AG_RROW3, AG_TW, AG_TW2, AG_VISITED,
    AG_LNEXT, AG_LREF, AG_LTAKE, AG_TAKE, AG_SUMR, AG_MMR, AG_FINISH, AG_AVGR, AG_RESULT,
    E_JUMP, E_JZ, E_PCT, E_PCT2,
    SF_START, SF_START2, SF_ARG2, SF_ARG2B, SF_INTDIV, SF_MODI, SF_MODI2, SF_MODI3, SF_MODF, SF_MODF2, SF_MODF3, SF_MODF4,
    SF_FLOOR, SF_DONE, SF_B2, SF_POWI, SF_POWI2, SF_POWF, SF_POWF2, SF_POWF3, SF_POWF4, SF_POWF5,
    SF_RNDI, SF_RNDI2, SF_RNDI3, SF_RNDF, SF_RF_MUL, SF_RF_SH, SF_RF_N, SF_RF_C2, SF_RF_DIV,
    SF_RN_SH, SF_RN_DIV, SF_RN_MUL, SF_RNDF4, SF_POWSQ, SF_SQRT, SQ_STEP,
    E_BIN, E_BINW, BO_START, E_SCALED, E_ARITH, E_MULF, E_DIVM, E_DIVF, E_NEG, E_FIX,
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
    B_TREE, B_TREE1, B_TREE2, B_TREE3, B_TREE4, B_TREE5, B_TREE6, B_TREE7, B_RHDR, B_NEXT,
    -- the list RAM's read (one cycle)
    L_WAIT, EST_WAIT, E_JZ2, E_BIN3, AG_ARG2,
    -- the codec units: a parameter block in, a job, its results out; their
    -- RAM requests served meanwhile (SJ_)
    X_P0, X_P8, X_P16, X_P24, X_D56, X_GO, X_RES, X_RES2, X_RES3,
    SJ_WAIT, SJ_DONE, SJ_GAP,
    -- FORMAT_CELLS
    FC_P32, FC_P40, FC_D0, FC_D8, FC_D56, FC_ROWS, FC_COLS, FC_WID, FC_CELLS, FC_H, FC_G8, FC_G16, FC_G24,
    FC_WFILL, FC_RENDER, FC_DONE1, FC_EXP, FC_EFILL, FC_EXP2, FC_COLR, FC_CLR, FC_NEXT
    );
  signal st, mem_ret, l_ret, lk_ret, fb_ret, imm_ret, cw_ret, mu_ret, dv_ret : state_t := S_IDLE;
  signal sj_ret : state_t := S_IDLE;
  signal fp_ret, fn_ret, cv_ret, bo_ret : state_t := S_IDLE;
  signal vl_ret, rf_ret, vr_ret, tk_ret : state_t := S_IDLE;

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
  -- the crossings' toggles, registered, and the last seen
  signal s_r, s_seen, a_r, a_seen, g_tr, done_tr : std_logic := '0';
  -- (the group's bytes and error, registered with a_r: a crossing from
  -- clock162 has one clock162 period, too short for M_WAIT's choice)
  signal g_rd_r : unsigned(63 downto 0) := (others => '0');
  signal g_err_r : std_logic := '0';
  signal abt : std_logic := '0';
  signal mp_hr_base, mp_hr_size, mp_sd_base, mp_sd_size : unsigned(7 downto 0) := (others => '0');

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
  -- (64 Kbit: block RAM, written at one address per cycle, read registered
  -- into l_rd.  Left to itself Vivado made it LUT RAM, 5686 cells)
  attribute ram_style : string;
  attribute ram_style of list : signal is "block";
  signal l_ra : natural range 0 to max_row_cells - 1 := 0;
  signal l_rd : unsigned(63 downto 0) := (others => '0');
  -- its write port, registered: the write lands a cycle after the state
  -- that asks for it (no read needs it sooner: see the RAM's process)
  signal l_we : std_logic := '0';
  signal l_wa : natural range 0 to max_row_cells - 1 := 0;
  signal l_wd : unsigned(63 downto 0) := (others => '0');
  signal l_n : natural range 0 to max_row_cells := 0;
  signal l_i, l_j : natural range 0 to max_row_cells := 0;
  signal l_key, l_cur : unsigned(63 downto 0) := (others => '0');
  signal g_left, g_right, g_root : unsigned(15 downto 0) := (others => '0');
  signal first_node : boolean := false;
  -- the tree builder: the node (l_i), its range lo..hi and middle
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
  type est_t is array (0 to 31) of unsigned(107 downto 0);  -- aux, kind, ref, k, value
  signal t_aux : unsigned(31 downto 0) := (others => '0');
  signal est : est_t;
  attribute ram_style of est : signal is "block";
  -- its ports: the write registered (the old top, pushed or flushed: lands
  -- a cycle later), the read registered (est_ra, then EST_WAIT, then est_q)
  signal est_we : std_logic := '0';
  signal est_wa, est_ra : natural range 0 to 31 := 0;
  signal est_wd, est_q : unsigned(107 downto 0) := (others => '0');
  signal est_ret : state_t := S_IDLE;
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
  -- the value subroutine's result
  signal vr_kind : unsigned(2 downto 0) := (others => '0');
  signal vr_v : unsigned(63 downto 0) := (others => '0');
  signal vr_k : unsigned(7 downto 0) := (others => '0');
  signal vr_ref : std_logic := '0';
  -- a one- or two-byte count / identifier (VR_START)
  signal vl_n : unsigned(15 downto 0) := (others => '0');
  -- RECT's first corner; CELLS' list
  signal rc_r1, rc_c1 : unsigned(31 downto 0) := (others => '0');
  signal cl_pc, cl_n : unsigned(15 downto 0) := (others => '0');
  -- aggregates: the function, its arguments, the running values
  constant VK_R : unsigned(2 downto 0) := "101";   -- a range
  constant VK_L : unsigned(2 downto 0) := "110";   -- a cell list
  signal ag_fid, ag_argc : unsigned(15 downto 0) := (others => '0');
  signal ag_i : natural range 0 to 32 := 0;
  signal ag_cnt : unsigned(31 downto 0) := (others => '0');
  signal ag_ferr, ag_fromc : boolean := false;
  signal ag_all, ag_any, ag_bad : boolean := false;          -- AND / OR
  -- scalar functions: the arguments (as numbers), the step
  signal sa_kind, sb_kind : unsigned(2 downto 0) := (others => '0');
  signal sa_v, sb_v : unsigned(63 downto 0) := (others => '0');
  signal sa_k, sb_k : unsigned(7 downto 0) := (others => '0');
  signal sf_neg : boolean := false;
  signal jmp_off : unsigned(15 downto 0) := (others => '0');
  -- POW: the exponent's magnitude, the square-and-multiply registers
  signal pw_n : unsigned(63 downto 0) := (others => '0');
  signal pw_r, pw_b : unsigned(63 downto 0) := (others => '0');
  signal pw_neg : boolean := false;
  -- ROUND: n; F64(10^|n|)
  signal rn_n : signed(7 downto 0) := (others => '0');
  signal rn_p : unsigned(63 downto 0) := (others => '0');
  signal rf_p : unsigned(127 downto 0) := (others => '0');      -- |x| x 10^n, or |x|'s integer part
  signal rf_sh : signed(12 downto 0) := (others => '0');        -- right shifts to go
  signal rf_rb : std_logic := '0';                              -- the last bit shifted out
  signal rf_neg : std_logic := '0';
  signal rf_x : unsigned(63 downto 0) := (others => '0');
  signal rf_fp, rf_mag : boolean := false;     -- the result in fp_r; a magnitude (x's sign to add)
  -- the square root: radicand, remainder, root
  signal sq_r : unsigned(127 downto 0) := (others => '0');
  signal sq_rem : unsigned(65 downto 0) := (others => '0');
  signal sq_root : unsigned(63 downto 0) := (others => '0');
  signal sq_i : natural range 0 to 64 := 0;
  signal acc_kind, best_kind : unsigned(2 downto 0) := (others => '0');
  signal acc_v, best_v : unsigned(63 downto 0) := (others => '0');
  signal acc_k, best_k : unsigned(7 downto 0) := (others => '0');
  signal ag_row, ag_rlast, ag_c1, ag_c2 : unsigned(31 downto 0) := (others => '0');
  signal ag_blk : unsigned(27 downto 0) := (others => '0');
  signal ag_pc : unsigned(15 downto 0) := (others => '0');
  signal ag_ln : unsigned(15 downto 0) := (others => '0');
  -- the range walk: an in-order walk of a row's tree, at most 32 deep
  type tw_t is array (0 to 31) of unsigned(53 downto 0);   -- depth, right, column, granule
  signal tws : tw_t;
  signal tw_sp : natural range 0 to 32 := 0;
  signal tw_cur : unsigned(11 downto 0) := (others => '0');
  signal tw_d : unsigned(5 downto 0) := (others => '0');
  signal tw_nxt : unsigned(11 downto 0) := (others => '0');
  signal tw_nd : unsigned(5 downto 0) := (others => '0');
  -- the binary-operator subroutine's operands and result
  signal bo_ka, bo_kb, br_kind : unsigned(2 downto 0) := (others => '0');
  signal bo_va, bo_vb, br_v : unsigned(63 downto 0) := (others => '0');
  signal bo_fa, bo_fb, br_k, bo_op : unsigned(7 downto 0) := (others => '0');
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
  type p10_t is array (0 to 19) of unsigned(63 downto 0);
  function init_p10 return p10_t is
    variable r : p10_t;
    variable v : unsigned(63 downto 0) := to_unsigned(1, 64);
  begin
    for i in 0 to 19 loop
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
  -- F64 rounded toward zero (on the bits: the fraction bits cleared)
  function f_trunc(fv : unsigned(63 downto 0)) return unsigned is
    variable e : integer;
    variable r : unsigned(63 downto 0);
  begin
    e := to_integer(fv(62 downto 52)) - 1023;
    if fv(62 downto 52) = "11111111111" or e >= 52 then return fv;   -- integral, inf, NaN
    elsif e < 0 then return fv(63) & "000" & x"000000000000000";    -- |fv| < 1: a signed zero
    else
      r := fv;
      for i in 0 to 51 loop
        if i < 52 - e then r(i) := '0'; end if;
      end loop;
      return r;
    end if;
  end function;
  -- whether x has a fraction (finite, not integral)
  function f_frac(fv : unsigned(63 downto 0)) return boolean is
    variable e : integer;
  begin
    e := to_integer(fv(62 downto 52)) - 1023;
    if fv(62 downto 52) = "11111111111" or e >= 52 or fv(62 downto 52) = 0 then return false;
    elsif e < 0 then return true;
    else
      for i in 0 to 51 loop
        if i < 52 - e and fv(i) = '1' then return true; end if;
      end loop;
      return false;
    end if;
  end function;
  -- floor: trunc, then a negative with a fraction one further (-1 when |x| < 1)
  function f_floor(fv : unsigned(63 downto 0)) return unsigned is
    variable t : unsigned(63 downto 0);
    variable e : integer;
  begin
    t := f_trunc(fv);
    if fv(63) = '1' and f_frac(fv) then
      e := to_integer(fv(62 downto 52)) - 1023;
      if e < 0 then
        return x"BFF0000000000000";                       -- -1.0
      else
        return '1' & (t(62 downto 0) + shift_left(to_unsigned(1, 63), 52 - e));
      end if;
    end if;
    return t;
  end function;
  -- an F64 rounded half away from zero to an integer, exactly (a zero keeps the sign)
  function f_rnd(fv : unsigned(63 downto 0)) return unsigned is
    variable t : unsigned(63 downto 0);
    variable e : integer;
  begin
    e := to_integer(fv(62 downto 52)) - 1023;
    if fv(62 downto 52) = "11111111111" or e >= 52 then return fv;
    elsif e < -1 then return fv(63) & "000" & x"000000000000000";
    elsif e = -1 then return fv(63) & "011" & x"FF0000000000000";   -- +-1.0
    else
      t := f_trunc(fv);
      if fv(51 - e) = '1' then
        return fv(63) & (t(62 downto 0) + shift_left(to_unsigned(1, 63), 52 - e));
      end if;
      return t;
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

  -- ---------------------------------------------------------------------
  -- The codec units
  signal co_start, ce_start, nu_start_self : std_logic := '0';
  signal co_decompile : std_logic := '0';
  signal co_source, co_dest, co_names : unsigned(27 downto 0) := (others => '0');
  signal co_len, co_cap : unsigned(15 downto 0) := (others => '0');
  signal co_row : unsigned(19 downto 0) := (others => '0');
  signal co_col : unsigned(23 downto 0) := (others => '0');
  signal co_dsep, co_asep : codec_byte := x"2E";
  signal co_busy, co_done, ce_busy, ce_done, nu_busy, nu_done : std_logic;
  signal co_error, ce_error, nu_error, co_hosts : codec_byte;
  signal co_epos, co_rlen, ce_rlen, nu_epos, nu_rlen : unsigned(15 downto 0);
  signal ce_colour : unsigned(3 downto 0);
  -- the cell renderer's job
  signal ce_kind : unsigned(3 downto 0) := (others => '0');
  signal ce_value, ce_format : unsigned(63 downto 0) := (others => '0');
  signal ce_text, ce_scratch, ce_dest : unsigned(27 downto 0) := (others => '0');
  signal ce_tlen, ce_cap : unsigned(15 downto 0) := (others => '0');
  signal ce_width : codec_byte := (others => '0');
  signal ce_upper : std_logic := '0';
  -- the shared number converter: its job from the codec, the renderer or
  -- the execution unit itself (PARSE)
  signal nu_start, nu_format, nu_negative, nu_kind, nu_display : std_logic;
  signal nu_source, nu_dest : unsigned(27 downto 0);
  signal nu_len, nu_cap : unsigned(15 downto 0);
  signal nu_value : unsigned(63 downto 0);
  signal nu_scale, nu_dsep, nu_decimals, nu_width : codec_byte;
  signal nu_style : unsigned(3 downto 0);
  signal nu_rvalue : unsigned(63 downto 0);
  signal nu_rkind : std_logic;
  signal nu_rscale : codec_byte;
  -- the codec's and renderer's requests to the converter
  signal cn_start, cn_format, cn_negative, cn_kind : std_logic;
  signal cn_source, cn_dest : unsigned(27 downto 0);
  signal cn_len, cn_cap : unsigned(15 downto 0);
  signal cn_value : unsigned(63 downto 0);
  signal cn_scale, cn_dsep : codec_byte;
  signal en_start, en_kind : std_logic;
  signal en_value : unsigned(63 downto 0);
  signal en_scale, en_dsep, en_decimals, en_width : codec_byte;
  signal en_dest : unsigned(27 downto 0);
  signal en_style : unsigned(3 downto 0);
  signal sf_source : unsigned(27 downto 0) := (others => '0');   -- PARSE's text
  signal sf_len : unsigned(15 downto 0) := (others => '0');
  -- which client asked the converter: 0 the codec, 1 the renderer, 2 PARSE
  signal nu_client : unsigned(1 downto 0) := "00";
  signal x_job : unsigned(1 downto 0) := "00";      -- 0 codec, 1 renderer, 2 PARSE
  signal x_unit_abort : std_logic := '0';
  -- their RAM requests (held valid until ready)
  signal co_rv, co_rw, ce_rv, ce_rw, nu_rv, nu_rw : std_logic;
  signal co_ra, ce_ra, nu_ra : unsigned(27 downto 0);
  signal co_wd, ce_wd, nu_wd : unsigned(63 downto 0);
  signal co_be, ce_be, nu_be : std_logic_vector(7 downto 0);
  signal co_rdy, ce_rdy, nu_rdy, sj_rerr : std_logic := '0';
  signal sj_rdata : unsigned(63 downto 0) := (others => '0');
  signal sj_who : unsigned(1 downto 0) := "00";     -- 0 codec, 1 renderer, 2 converter
  signal sj_mode : boolean := false;                -- memory faults go to the unit
  signal sj_fault : boolean := false;
  signal sj_seen_done : boolean := false;
  signal xblk : unsigned(27 downto 0) := (others => '0'); -- the parameter block
  signal xp0, xp8, xp16, xp24 : unsigned(63 downto 0) := (others => '0');
  -- FORMAT_CELLS
  signal xp32, xp40 : unsigned(63 downto 0) := (others => '0');
  signal fc_row, fc_col : unsigned(31 downto 0) := (others => '0');
  signal fc_line, fc_cline : unsigned(27 downto 0) := (others => '0');   -- this row's lines
  signal fc_x, fc_cx : unsigned(15 downto 0) := (others => '0');         -- the field's offsets
  signal fc_w : unsigned(7 downto 0) := (others => '0');
  signal fc_hdr : unsigned(63 downto 0) := (others => '0');
  signal fc_cell : unsigned(27 downto 0) := (others => '0');
  signal fc_changed, fc_numfmt : boolean := false;
  signal fc_i : unsigned(8 downto 0) := (others => '0');
  signal fc_tag : unsigned(24 downto 0) := (others => '0');               -- a buffered group
  signal fc_buf : unsigned(63 downto 0) := (others => '0');
  signal fc_bvalid : boolean := false;
  signal fw_tag : unsigned(24 downto 0) := (others => '0');               -- the width list's group
  signal fw_buf : unsigned(63 downto 0) := (others => '0');
  signal fw_valid : boolean := false;

  function mid_of(lo, hi : integer) return integer is
  begin
    return (lo + hi) / 2;
  end function;

begin

  -- The codec units (their RAM through the adapter below, SJ_)
  codec : entity work.shite_formula_codec
    port map (
      clock => clock, reset => '0', start => co_start, decompile => co_decompile,
      abort => x_unit_abort,
      source => co_source, destination => co_dest, names => co_names,
      source_length => co_len, output_capacity => co_cap,
      formula_row => co_row, formula_column => co_col,
      decimal_separator => co_dsep, argument_separator => co_asep,
      busy => co_busy, done => co_done, error => co_error, error_position => co_epos,
      result_length => co_rlen, host_calls => co_hosts,
      ram_valid => co_rv, ram_write => co_rw, ram_address => co_ra, ram_wdata => co_wd,
      ram_byte_enable => co_be, ram_ready => co_rdy, ram_error => sj_rerr, ram_rdata => sj_rdata,
      number_start => cn_start, number_format => cn_format, number_negative => cn_negative,
      number_source => cn_source, number_destination => cn_dest,
      number_length => cn_len, number_capacity => cn_cap,
      number_value => cn_value, number_kind => cn_kind, number_scale => cn_scale,
      number_decimal_separator => cn_dsep,
      number_done => nu_done, number_error => nu_error,
      number_error_position => nu_epos, number_result_length => nu_rlen,
      number_result_value => nu_rvalue, number_result_kind => nu_rkind,
      number_result_scale => nu_rscale);

  renderer : entity work.shite_cell_text
    port map (
      clock => clock, reset => '0', start => ce_start, abort => x_unit_abort,
      kind => ce_kind, value => ce_value, cell_format => ce_format,
      text_source => ce_text, scratch => ce_scratch, destination => ce_dest,
      text_length => ce_tlen, capacity => ce_cap,
      width => ce_width, decimal_separator => co_dsep,
      screen_codes => '1', upper_case => ce_upper,
      busy => ce_busy, done => ce_done, error => ce_error, result_length => ce_rlen,
      colour => ce_colour,
      ram_valid => ce_rv, ram_write => ce_rw, ram_address => ce_ra, ram_wdata => ce_wd,
      ram_byte_enable => ce_be, ram_ready => ce_rdy, ram_error => sj_rerr, ram_rdata => sj_rdata,
      number_start => en_start, number_value => en_value, number_kind => en_kind,
      number_scale => en_scale, number_decimal_separator => en_dsep,
      number_destination => en_dest, number_style => en_style,
      number_decimals => en_decimals, number_width => en_width,
      number_done => nu_done, number_error => nu_error, number_result_length => nu_rlen);

  -- the converter's job: from whichever client is asking (one at a time)
  nu_start <= cn_start or en_start or nu_start_self;
  converter_job : process (nu_client, cn_format, cn_negative, cn_source, cn_dest, cn_len, cn_cap,
                           cn_value, cn_kind, cn_scale, cn_dsep, en_value, en_kind, en_scale, en_dsep,
                           en_dest, en_style, en_decimals, en_width, sf_source, sf_len, co_dsep)
  begin
    -- (the codec's)
    nu_format <= cn_format; nu_negative <= cn_negative; nu_source <= cn_source; nu_dest <= cn_dest;
    nu_len <= cn_len; nu_cap <= cn_cap; nu_value <= cn_value; nu_kind <= cn_kind; nu_scale <= cn_scale;
    nu_dsep <= cn_dsep; nu_display <= '0'; nu_style <= x"0"; nu_decimals <= x"02"; nu_width <= x"FF";
    if nu_client = "01" then                  -- the renderer: display text, 512 bytes of scratch
      nu_format <= '1'; nu_negative <= '0'; nu_source <= (others => '0'); nu_dest <= en_dest;
      nu_len <= (others => '0'); nu_cap <= to_unsigned(512, 16); nu_value <= en_value;
      nu_kind <= en_kind; nu_scale <= en_scale; nu_dsep <= en_dsep; nu_display <= '1';
      nu_style <= en_style; nu_decimals <= en_decimals; nu_width <= en_width;
    elsif nu_client = "10" then               -- PARSE: the literal
      nu_format <= '0'; nu_negative <= '0'; nu_source <= sf_source; nu_dest <= (others => '0');
      nu_len <= sf_len; nu_cap <= (others => '0'); nu_value <= (others => '0'); nu_kind <= '0';
      nu_scale <= (others => '0'); nu_dsep <= co_dsep;
    end if;
  end process;

  converter : entity work.shite_number_text
    port map (
      clock => clock, reset => '0', start => nu_start, format => nu_format, negative => nu_negative,
      source => nu_source, destination => nu_dest, input_length => nu_len, capacity => nu_cap,
      value => nu_value, kind => nu_kind, scale => nu_scale, decimal_separator => nu_dsep,
      display => nu_display, display_style => nu_style, display_decimals => nu_decimals,
      display_width => nu_width,
      busy => nu_busy, done => nu_done, error => nu_error, error_position => nu_epos,
      result_length => nu_rlen, result_value => nu_rvalue, result_kind => nu_rkind,
      result_scale => nu_rscale, abort => x_unit_abort,
      ram_valid => nu_rv, ram_write => nu_rw, ram_address => nu_ra, ram_wdata => nu_wd,
      ram_byte_enable => nu_be, ram_ready => nu_rdy, ram_error => sj_rerr, ram_rdata => sj_rdata);

  g_t <= g_tr;
  done_t <= done_tr;
  g_write <= m_write; g_wd <= m_wd; g_be <= m_be;

  -- RECALC's evaluation stack (below the top, which is in t_*): a simple
  -- dual-port block RAM (two 72-bit wide RAMB36 halves), one write and one
  -- read port, so no 108-bit multiplexer on either side.  A read is used
  -- only through EST_WAIT, never as a write to its address lands (asserted)
  process (clock)
  begin
    if rising_edge(clock) then
      if est_we = '1' then
        est(est_wa) <= est_wd;
      end if;
      est_q <= est(est_ra);
      assert not (st = EST_WAIT and est_we = '1' and est_wa = est_ra)
        report "SHITE: the stack RAM read where a write is landing" severity failure;
    end if;
  end process;

  -- REBALANCE_ROW's list: a simple dual-port block RAM, alone in its
  -- process (in the main one Vivado built it from LUT RAM, ram_style or
  -- not).  A read is used only through L_WAIT, never in the cycle after
  -- its address was written (the write is still landing then: asserted)
  process (clock)
  begin
    if rising_edge(clock) then
      if l_we = '1' then
        list(l_wa) <= l_wd;
      end if;
      l_rd <= list(l_ra);
      assert not (st = L_WAIT and l_we = '1' and l_wa = l_ra)
        report "SHITE: the list RAM read where a write is landing" severity failure;
    end if;
  end process;

  process (clock)
    variable mb : unsigned(7 downto 0);
    variable w : unsigned(15 downto 0);
    variable e : unsigned(63 downto 0);
    variable md : integer;
    variable ad : unsigned(27 downto 0);
    variable ka, kb : unsigned(2 downto 0);
    variable va, vb : unsigned(63 downto 0);
    variable sum : unsigned(64 downto 0);
    variable ent : unsigned(107 downto 0);
    -- the stack RAM's one write, made at the end of the cycle: push() is
    -- expanded wherever it is called, and writing est there made each call
    -- a write port (est as 3456 flip-flops and a full-width multiplexer per
    -- call, too big for the device)
    variable tws_we : boolean;                  -- (the same for the range walk's stack)
    variable tws_wa : natural range 0 to 31;
    variable tws_wd : unsigned(53 downto 0);
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
                   fx : unsigned(7 downto 0); rf : std_logic; nxt : state_t;
                   ax : unsigned(31 downto 0) := x"00000000") is
    begin
      if esp = 32 then
        t_kind <= VK_E; t_v <= x"00000000000000" & E_STACK; esp <= 1; st <= E_STORE;
      else
        if esp > 0 then
          est_we <= '1';                      -- (the old top, to est(esp - 1))
        end if;
        t_kind <= k; t_v <= v; t_k <= fx; t_ref <= rf; t_aux <= ax;
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
    -- the value subroutine's result
    procedure vr_set(k : unsigned(2 downto 0); v : unsigned(63 downto 0); fx : unsigned(7 downto 0)) is
    begin
      vr_kind <= k; vr_v <= v; vr_k <= fx; st <= vl_ret;
    end procedure;
    procedure fetch(nxt : state_t) is
    begin
      fb_ret <= nxt; st <= BF;
    end procedure;
  begin
    if rising_edge(clock) then
      tws_we := false;
      -- the stack RAM's write: always the top at esp - 1, when est_we
      est_we <= '0';
      est_wa <= (esp + 31) mod 32;
      est_wd <= t_aux & t_kind & t_ref & t_k & t_v;
      -- (from clock162: registered before any use)
      s_r <= start_t; a_r <= g_ack_t; abt <= abort;
      g_rd_r <= g_rd; g_err_r <= g_err;
      mp_hr_base <= map_hr_base; mp_hr_size <= map_hr_size;
      mp_sd_base <= map_sd_base; mp_sd_size <= map_sd_size;

      -- the memory map (SSNAIL's), a cycle after m_addr
      mb := m_addr(27 downto 20);
      if mb >= mp_hr_base and resize(mb, 9) < resize(mp_hr_base, 9) + resize(mp_hr_size, 9) then
        m_ok <= '1'; m_is_sd <= '0';
        m_local <= resize(mb - mp_hr_base, 7) & m_addr(19 downto 0);
      elsif mb >= mp_sd_base and resize(mb, 9) < resize(mp_sd_base, 9) + resize(mp_sd_size, 9) then
        m_ok <= '1'; m_is_sd <= '1';
        m_local <= resize(mb - mp_sd_base, 7) & m_addr(19 downto 0);
      else
        m_ok <= '0';
      end if;

      l_we <= '0';                        -- (the list RAM's write port)

      -- the codec units: one-cycle pulses, and their jobs' ends latched
      co_start <= '0'; ce_start <= '0'; nu_start_self <= '0';
      co_rdy <= '0'; ce_rdy <= '0'; nu_rdy <= '0'; sj_rerr <= '0';
      if (x_job = "00" and co_done = '1') or (x_job = "01" and ce_done = '1')
        or (x_job = "10" and nu_done = '1') then
        sj_seen_done <= true;
      end if;
      x_unit_abort <= abt;

      case st is
        when S_IDLE =>
          if s_r /= s_seen then
            s_seen <= s_r;
            err <= ERR_NONE; wr <= '0'; cnt_loaded <= false;
            r_op <= op; r_a <= ra; r_b <= rb; r_c <= rc; r_d <= rd; r_z <= z; desc <= x;
            if op = x"43" or op = x"44" or op = x"45" or op = x"46" or op = x"47" then
              xblk <= x; mem_read(x, X_P0);         -- (X: a parameter block)
            else
              mem_read(x, D_RD0);
            end if;
          end if;

        when S_FINISH =>
          done_tr <= not done_tr;
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
          if m_ok = '0' and sj_mode then
            sj_fault <= true; st <= mem_ret;      -- (to the unit: ram_error)
          elsif m_ok = '0' then
            fault(ERR_ADDRESS);
          else
            g_sd <= m_is_sd; g_addr <= m_local; g_tr <= not g_tr;
            st <= M_WAIT;
          end if;
        when M_WAIT =>
          if a_r /= a_seen then
            a_seen <= a_r;
            if g_err_r = '1' then
              if sj_mode then sj_fault <= true; st <= mem_ret; else fault(ERR_READ); end if;
            else
              m_rd <= g_rd_r;
              st <= mem_ret;
            end if;
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
          if abt = '1' then
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
          if abt = '1' then fault(ERR_ABORTED);
          else st <= LK_HDR2; end if;

        -- FIND_CELL
        when F_DONE =>
          result <= x"0" & q_addr; wr <= '1'; st <= S_FINISH;

        -- --------------------------------------------------------------
        -- REBALANCE_ROW, rows row..rlast
        when B_ROW =>
          if row > rlast or row >= nrows then
            st <= S_FINISH;
          elsif abt = '1' then
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
              l_we <= '1'; l_wa <= l_n; l_wd <= m_rd(23 downto 0) & g & m_rd(39 downto 24) & x"00";
              l_n <= l_n + 1;
            end if;
            g <= g + m_rd(39 downto 32);
            st <= B_WALK;
          end if;

        -- the list RAM's read: l_rd is valid in l_ret
        when L_WAIT =>
          st <= l_ret;
        -- the stack RAM's read: est_q is valid in est_ret
        when EST_WAIT =>
          st <= est_ret;

        -- insertion sort by column (bits 63:48): list(0..l_i-1) is sorted
        when B_SORT =>
          if l_i >= l_n then
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
            l_we <= '1'; l_wa <= l_j; l_wd <= l_rd;
            l_j <= l_j - 1;
            st <= B_SORT2;
          else
            st <= B_SORT4;
          end if;
        when B_SORT4 =>
          l_we <= '1'; l_wa <= l_j; l_wd <= l_key;
          l_i <= l_i + 1;
          st <= B_SORT;

        -- the tree: each node l_i in turn, no stack.  The node at the middle
        -- of lo..hi has the middles of its two halves as its children, so a
        -- node's header needs only its range, found by descending from the
        -- root (0..l_n-1) as a search for l_i would: a cycle per level, at
        -- most 11, against a node's three list reads and one memory write
        when B_TREE =>
          g_root <= (others => '0');
          l_i <= 0;
          if l_n = 0 then
            st <= B_RHDR;
          else
            st <= B_TREE1;
          end if;
        when B_TREE1 =>
          if l_i >= l_n then
            st <= B_RHDR;
          elsif abt = '1' then
            fault(ERR_ABORTED);
          else
            t_lo <= 0; t_hi <= l_n - 1;
            first_node <= true;
            st <= B_TREE2;
          end if;
        when B_TREE2 =>                         -- one level down towards l_i
          md := mid_of(t_lo, t_hi);
          if l_i = md then
            t_mid <= md;
            l_ra <= md; l_ret <= B_TREE3; st <= L_WAIT;
          else
            first_node <= false;                -- (not the root)
            if l_i < md then t_hi <= md - 1; else t_lo <= md + 1; end if;
          end if;
        when B_TREE3 =>                         -- the node
          l_cur <= l_rd;
          if first_node then g_root <= l_rd(39 downto 24); end if;
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
                    "11111111", B_TREE1);
          l_i <= l_i + 1;

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
          if abt = '1' then
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
            rf_ret <= E_RESOLVE; imm_ret <= E_SREF; st <= E_IMM;
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
                rf_ret <= E_RESOLVE; imm_ret <= E_LREF; st <= E_IMM;
              when x"05" =>                       -- STR: skipped (text: later)
                vr_ret <= E_STR; st <= VR_START;
              when x"08" =>                       -- RECT
                rf_ret <= E_RECT1; st <= RF_START;
              when x"09" =>                       -- HOSTCALL: the text skipped
                vr_ret <= E_HOST; st <= VR_START;
              when x"0C" =>                       -- CALL
                vr_ret <= E_CALL1; st <= VR_START;
              when x"0D" =>                       -- CELLS
                vr_ret <= E_CELLS; st <= VR_START;
              when x"14" =>                       -- POW: as POWER(a, b)
                ag_fid <= to_unsigned(29, 16); ag_argc <= to_unsigned(2, 16);
                if esp > 0 then est_we <= '1'; end if;   -- (the top into the RAM: as CALL)
                st <= AG_START;
              when x"17" =>                       -- CONCAT (not yet): two operands
                if esp < 2 then e_abort(E_STACK);
                else esp <= esp - 1; t_kind <= VK_E; t_v <= x"00000000000000" & E_NAME; t_ref <= '0'; st <= E_NEXT; end if;
              when x"16" =>                       -- PCT
                st <= E_PCT;
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
              when x"0A" | x"0B" =>               -- JZ, JMP: a 2-byte forward offset
                imm <= (others => '0'); fb_i <= x"0"; fb_n <= x"2"; fb_be <= false;
                if bf_byte = x"0A" then imm_ret <= E_JZ; else imm_ret <= E_JUMP; end if;
                st <= E_IMM;
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
          -- a deleted reference (both relative, both at their minimum):
          -- past every sheet, so #REF! wherever it is used
          if imm(31 downto 0) = x"A0002000" then rr := x"FFFFFFFF"; end if;
          q_row <= rr; q_col <= cc;
          st <= rf_ret;
        when E_LREF =>
          if imm(47) = '1' then rr := resize(imm(43 downto 24), 32);
          else rr := (row + resize(imm(43 downto 24), 32)) and x"000FFFFF"; end if;
          if imm(46) = '1' then cc := resize(imm(23 downto 0), 32);
          else cc := (resize(hdr(23 downto 0), 32) + resize(imm(23 downto 0), 32)) and x"00FFFFFF"; end if;
          if imm(47 downto 0) = x"080000800000" then rr := x"FFFFFFFF"; end if;
          q_row <= rr; q_col <= cc;
          st <= rf_ret;
        when E_RESOLVE =>
          if q_row >= nrows or q_col >= ncols then
            push(VK_E, x"00000000000000" & E_REF, x"00", '1', E_NEXT);
          else
            vl_ret <= E_PUSHV; lk_ret <= VL_HDR; st <= LK_START;
          end if;
        when E_PUSHV =>                         -- a reference's value, pushed
          push(vr_kind, vr_v, vr_k, '1', E_NEXT);

        -- the referenced cell's value (q_addr; 0: no cell)
        when VL_HDR =>
          if q_addr = 0 then
            vr_set(VK_Z, (others => '0'), x"00");
          else
            mem_read(q_addr, VL_V8);
          end if;
        when VL_V8 =>
          v_hdr <= m_rd;
          case m_rd(27 downto 24) is
            when K_EMPTY =>
              vr_set(VK_Z, (others => '0'), x"00");
            when K_TEXT =>
              vr_set(VK_T, (others => '0'), x"00");
            when K_UNCOMPILED =>
              vr_set(VK_E, x"00000000000000" & E_COMPILE, x"00");
            when K_F64 | K_I64 | K_I32 | K_ERROR | K_FORMULA =>
              mem_read(q_addr + 8, VL_FMT);
            when others =>
              vr_set(VK_Z, (others => '0'), x"00");
          end case;
        when VL_FMT =>                          -- the group at +8
          v_val <= m_rd;
          case v_hdr(27 downto 24) is
            when K_F64 =>
              if m_rd(62 downto 52) = 0 then        -- (subnormals flushed to zero)
                vr_set(VK_F, m_rd(63) & "000" & x"000000000000000", x"00");
              else
                vr_set(VK_F, m_rd, x"00");
              end if;
            when K_ERROR =>
              vr_set(VK_E, x"00000000000000" & m_rd(7 downto 0), x"00");
            when K_I64 | K_I32 =>
              if v_hdr(30) = '1' then               -- HAS_FORMAT: its fixed point
                mem_read(q_addr + 16, VL_F16);
              elsif v_hdr(27 downto 24) = K_I32 then
                vr_set(VK_I, unsigned(resize(signed(m_rd(31 downto 0)), 64)), x"00");
              else
                vr_set(VK_I, m_rd, x"00");
              end if;
            when others =>                        -- FORMULA: its result, kind
              mem_read(q_addr + 24, VL_F24);
          end case;
        when VL_F16 =>                          -- a number's format: byte 2
          if v_hdr(27 downto 24) = K_I32 then
            vr_set(VK_I, unsigned(resize(signed(v_val(31 downto 0)), 64)), m_rd(23 downto 16));
          else
            vr_set(VK_I, v_val, m_rd(23 downto 16));
          end if;
        when VL_F24 =>                          -- a formula's result kind
          case m_rd(3 downto 0) is
            when K_F64 | K_I64 | K_I32 | K_ERROR | K_TEXT =>
              q_addr <= q_addr;                 -- (the result itself next)
              cmp_a <= m_rd;
              mem_read(q_addr + 16, VL_F8);
            when others =>
              vr_set(VK_Z, (others => '0'), x"00");
          end case;
        when VL_F8 =>                           -- (cmp_a: the kind; v_val: the format group)
          case cmp_a(3 downto 0) is
            when K_F64 =>
              if m_rd(62 downto 52) = 0 then
                vr_set(VK_F, m_rd(63) & "000" & x"000000000000000", x"00");
              else
                vr_set(VK_F, m_rd, x"00");
              end if;
            when K_I64 | K_I32 =>
              vr_set(VK_I, m_rd, v_val(23 downto 16));
            when K_ERROR =>
              vr_set(VK_E, x"00000000000000" & m_rd(7 downto 0), x"00");
            when others =>                        -- text
              vr_set(VK_T, (others => '0'), x"00");
          end case;

        -- --------------------------------------------------------------
        -- A reference (short, or REF and the long form) into q_row, q_col,
        -- then rf_ret
        when RF_START =>
          fetch(RF_B0);
        when RF_B0 =>
          if bf_byte(7) = '1' then
            imm <= x"00000000000000" & bf_byte; fb_i <= x"1"; fb_n <= x"4"; fb_be <= true;
            imm_ret <= E_SREF; st <= E_IMM;
          elsif bf_byte = x"07" then
            imm <= (others => '0'); fb_i <= x"0"; fb_n <= x"6"; fb_be <= true;
            imm_ret <= E_LREF; st <= E_IMM;
          else
            e_abort(E_STACK);
          end if;
        -- A count / identifier (one or two bytes) into vl_n, then vr_ret
        when VR_START =>
          fetch(VR_B0);
        when VR_B0 =>
          vl_n <= x"00" & bf_byte;
          if bf_byte(7) = '0' then st <= vr_ret;
          else vl_n(7) <= '0'; fetch(VR_B1); end if;
        when VR_B1 =>
          vl_n(15) <= '0';
          vl_n(14 downto 7) <= bf_byte;
          st <= vr_ret;

        when E_STR =>                           -- (text: not yet) skipped, #NAME?
          pc <= pc + vl_n;
          push(VK_E, x"00000000000000" & E_NAME, x"00", '0', E_NEXT);
        when E_HOST =>                          -- the text skipped; the result cell
          pc <= pc + vl_n;
          imm <= (others => '0'); fb_i <= x"0"; fb_n <= x"6"; fb_be <= true;
          rf_ret <= E_RESOLVE; imm_ret <= E_LREF; st <= E_IMM;
        when E_RECT1 =>
          rc_r1 <= q_row; rc_c1 <= q_col;
          rf_ret <= E_RECT2; st <= RF_START;
        when E_RECT2 =>                         -- the rectangle, normalised
          if rc_r1 >= nrows or q_row >= nrows or rc_c1 >= ncols or q_col >= ncols then
            push(VK_E, x"00000000000000" & E_REF, x"00", '0', E_NEXT);
          else
            if rc_r1 <= q_row then rr := rc_r1; else rr := q_row; end if;
            if rc_c1 <= q_col then cc := rc_c1; else cc := q_col; end if;
            -- (value: r1, c1, r2; aux: c2)
            if rc_r1 <= q_row then e(19 downto 0) := q_row(19 downto 0); else e(19 downto 0) := rc_r1(19 downto 0); end if;
            e(63 downto 44) := rr(19 downto 0);
            e(43 downto 20) := cc(23 downto 0);
            if rc_c1 <= q_col then
              push(VK_R, e, x"00", '0', E_NEXT, x"00" & q_col(23 downto 0));
            else
              push(VK_R, e, x"00", '0', E_NEXT, x"00" & rc_c1(23 downto 0));
            end if;
          end if;
        when E_CELLS =>                         -- the list's references: walked past
          cl_pc <= pc; cl_n <= vl_n; ag_ln <= vl_n;
          st <= E_CELLS2;
        when E_CELLS2 =>
          if ag_ln = 0 then
            push(VK_L, x"00000000" & cl_n & cl_pc, x"00", '0', E_NEXT);
          else
            ag_ln <= ag_ln - 1;
            rf_ret <= E_CELLS2; st <= RF_START;
          end if;
        when E_CALL1 =>
          ag_fid <= vl_n;
          vr_ret <= E_CALL2; st <= VR_START;
        when E_CALL2 =>
          ag_argc <= vl_n;
          -- the top into the stack RAM too (at esp - 1), so the arguments
          -- are all read from it (lands as AG_START runs, before any read)
          if esp > 0 then est_we <= '1'; end if;
          st <= AG_START;

        -- JMP / JZ (IF): forward by imm(15:0)
        when E_JUMP =>
          pc <= pc + imm(15 downto 0);
          st <= E_NEXT;
        when E_JZ =>                            -- pop; zero (blank, I64 0, F64 +-0): jump
          if esp < 1 then
            e_abort(E_STACK);
          elsif t_kind = VK_E then
            e_abort(t_v(7 downto 0));
          elsif t_kind /= VK_Z and t_kind /= VK_I and t_kind /= VK_F then
            e_abort(E_VALUE);
          elsif t_kind = VK_I and bad_k(t_k) then
            e_abort(E_NUM);
          else
            if t_kind = VK_Z or (t_kind = VK_I and t_v = 0) or (t_kind = VK_F and f_zero(t_v)) then
              pc <= pc + imm(15 downto 0);
            end if;
            -- (the pop: the entry below to the top)
            if esp > 1 then
              est_ra <= esp - 2; est_ret <= E_JZ2; st <= EST_WAIT;
            else
              esp <= esp - 1;
              st <= E_NEXT;
            end if;
          end if;
        when E_JZ2 =>
          t_aux <= est_q(107 downto 76); t_kind <= est_q(75 downto 73); t_ref <= est_q(72);
          t_k <= est_q(71 downto 64); t_v <= est_q(63 downto 0);
          esp <= esp - 1;
          st <= E_NEXT;
        -- %: integers two more decimals of fixed point, else F64 / 100
        when E_PCT =>
          st <= E_NEXT;
          t_ref <= '0';
          if esp < 1 then
            e_abort(E_STACK);
          elsif t_kind = VK_Z then
            t_kind <= VK_I; t_v <= (others => '0'); t_k <= x"02";
          elsif t_kind = VK_E then
            null;
          elsif t_kind /= VK_I and t_kind /= VK_F then
            t_kind <= VK_E; t_v <= x"00000000000000" & E_VALUE;
          elsif t_kind = VK_I and bad_k(t_k) then
            t_kind <= VK_E; t_v <= x"00000000000000" & E_NUM;
          elsif t_kind = VK_I and not (t_k(6 downto 0) /= 0 and t_k(7) = '1') and t_k(6 downto 0) <= 16 then
            t_k <= '0' & (t_k(6 downto 0) + 2);
          elsif t_kind = VK_I then
            cv_v <= t_v; cv_k <= t_k; cv_ret <= E_PCT2; cv_step <= 0; st <= CV_START;
          else
            fp_r <= t_v; st <= E_PCT2;
          end if;
        when E_PCT2 =>                          -- F64: x / 100
          fp_a <= fp_r; fp_b <= x"4059000000000000"; fp_op <= FP_DIV; fp_ret <= E_FBR;
          bo_ret <= E_BINW; st <= FP_START;
          -- (E_FBR sets br_*, then E_BINW: the top)

        -- --------------------------------------------------------------
        -- Scalar functions (5.7): ABS INT TRUNC SIGN MOD NOT
        when SF_START =>
          if ((ag_fid = 13 or ag_fid = 10 or ag_fid = 29) and ag_argc /= 2)
            or (ag_fid /= 13 and ag_fid /= 10 and ag_fid /= 29 and ag_argc /= 1) then
            acc_kind <= VK_E; acc_v <= x"00000000000000" & E_VALUE; st <= AG_RESULT;
          else
            est_ra <= ag_i; est_ret <= SF_START2; st <= EST_WAIT;
          end if;
        when SF_START2 =>                       -- the argument (or the first of two)
          ent := est_q;
          -- as a number: blank 0; text, ranges #VALUE!; past-the-limit fixed point #NUM!
          ka := ent(75 downto 73); va := ent(63 downto 0); fa := ent(71 downto 64);
          if ka = VK_Z then ka := VK_I; va := (others => '0'); fa := x"00"; end if;
          sa_kind <= ka; sa_v <= va; sa_k <= fa;
          st <= SF_DONE;
          acc_kind <= VK_I; acc_k <= x"00";
          if ka = VK_E then
            acc_kind <= VK_E; acc_v <= va;
          elsif ka /= VK_I and ka /= VK_F then
            acc_kind <= VK_E; acc_v <= x"00000000000000" & E_VALUE;
          elsif ka = VK_I and bad_k(fa) then
            acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM;
          else
            case ag_fid(4 downto 0) is
              when "10000" =>                   -- NOT
                if (ka = VK_I and va = 0) or (ka = VK_F and f_zero(va)) then acc_v <= b64(true);
                else acc_v <= b64(false); end if;
              when "00111" =>                   -- ABS
                if ka = VK_F then
                  acc_kind <= VK_F; acc_v <= '0' & va(62 downto 0);
                elsif va = x"8000000000000000" then
                  acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM;
                else
                  acc_k <= fa;
                  if va(63) = '1' then acc_v <= unsigned(-signed(va)); else acc_v <= va; end if;
                end if;
              when "01011" =>                   -- SIGN
                if ka = VK_F and f_nan(va) then
                  acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM;
                elsif (ka = VK_I and va = 0) or (ka = VK_F and f_zero(va)) then
                  acc_v <= (others => '0');
                elsif va(63) = '1' then
                  acc_v <= (others => '1');
                else
                  acc_v <= b64(true);
                end if;
              when "01000" | "01001" =>         -- INT, TRUNC
                if ka = VK_F then
                  acc_kind <= VK_F;
                  if ag_fid = 8 then acc_v <= f_floor(va); else acc_v <= f_trunc(va); end if;
                elsif fa(6 downto 0) = 0 then
                  acc_v <= va;
                elsif fa(7) = '1' then          -- binary: a shift
                  if ag_fid = 8 then
                    acc_v <= unsigned(shift_right(signed(va), to_integer(fa(6 downto 0))));
                  elsif va(63) = '1' then
                    acc_v <= unsigned(-signed(shift_right(unsigned(-signed(va)), to_integer(fa(6 downto 0)))));
                  else
                    acc_v <= shift_right(va, to_integer(fa(6 downto 0)));
                  end if;
                else                            -- decimal: |v| / 10^k
                  if va(63) = '1' then dv_n <= x"0000000000000000" & unsigned(-signed(va));
                  else dv_n <= x"0000000000000000" & va; end if;
                  dv_d <= pw(fa(6 downto 0), '0');
                  dv_raw <= true; dv_ret <= SF_INTDIV; st <= DV_START;
                end if;
              when "01100" =>                   -- SQRT: as F64
                if ka = VK_I then cv_v <= va; cv_k <= fa; cv_ret <= SF_SQRT; cv_step <= 0; st <= CV_START;
                else fp_r <= va; st <= SF_SQRT; end if;
              when others =>                    -- MOD, ROUND, POWER: the second argument
                st <= SF_ARG2;
            end case;
          end if;

        when SF_INTDIV =>                       -- INT rounds down, TRUNC toward zero
          st <= SF_DONE;
          if sa_v(63) = '0' then
            acc_v <= dv_q(63 downto 0);
          elsif ag_fid = 8 and dv_r /= 0 then
            acc_v <= unsigned(-signed(dv_q(63 downto 0) + 1));
          else
            acc_v <= unsigned(-signed(dv_q(63 downto 0)));
          end if;
        when SF_ARG2 =>                         -- MOD's b (and ROUND's n, POWER's b)
          est_ra <= ag_i + 1; est_ret <= SF_ARG2B; st <= EST_WAIT;
        when SF_ARG2B =>
          ent := est_q;
          kb := ent(75 downto 73); vb := ent(63 downto 0); fb := ent(71 downto 64);
          if kb = VK_Z then kb := VK_I; vb := (others => '0'); fb := x"00"; end if;
          sb_kind <= kb; sb_v <= vb; sb_k <= fb;
          st <= SF_DONE;
          if kb = VK_E then
            acc_kind <= VK_E; acc_v <= vb;
          elsif kb /= VK_I and kb /= VK_F then
            acc_kind <= VK_E; acc_v <= x"00000000000000" & E_VALUE;
          elsif kb = VK_I and bad_k(fb) then
            acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM;
          elsif ag_fid /= 13 then
            st <= SF_B2;                          -- ROUND, POWER
          elsif (kb = VK_I and vb = 0) or (kb = VK_F and f_zero(vb)) then
            acc_kind <= VK_E; acc_v <= x"00000000000000" & E_DIV0;
          elsif sa_kind = VK_I and kb = VK_I and
            not (sa_k(6 downto 0) /= 0 and fb(6 downto 0) /= 0 and sa_k(7) /= fb(7)) then
            -- integers: aligned through the operators' path (SUB's alignment)
            bo_ka <= sa_kind; bo_va <= sa_v; bo_fa <= sa_k;
            bo_kb <= kb; bo_vb <= vb; bo_fb <= fb;
            bo_op <= x"18"; bo_ret <= SF_MODI; st <= BO_START;   -- (EQ: just the alignment)
          else
            fx_a <= sa_v; fx_b <= vb; fx_ka <= sa_kind; fx_kb <= kb; fx_fa <= sa_k; fx_fb <= fb;
            cv_v <= sa_v; cv_k <= sa_k;
            if sa_kind = VK_I then cv_ret <= SF_MODF; cv_step <= 0; st <= CV_START;
            else fp_r <= sa_v; st <= SF_MODF; end if;
          end if;
        when SF_MODI =>                         -- xa, xb aligned (or #NUM!): |a| mod |b|
          if br_kind = VK_E then
            acc_kind <= VK_E; acc_v <= br_v; st <= SF_DONE;
          else
            if xa(63) = '1' then dv_n <= x"0000000000000000" & unsigned(-signed(xa));
            else dv_n <= x"0000000000000000" & xa; end if;
            if xb(63) = '1' then dv_d <= unsigned(-signed(xb)); else dv_d <= xb; end if;
            dv_raw <= true; dv_ret <= SF_MODI2; st <= DV_START;
          end if;
        when SF_MODI2 =>                        -- floor mod: the divisor's sign
          acc_kind <= VK_I; acc_k <= x_k;
          st <= SF_DONE;
          if dv_r = 0 then
            acc_v <= (others => '0');
          elsif xa(63) = xb(63) then
            if xb(63) = '1' then acc_v <= unsigned(-signed(dv_r(63 downto 0))); else acc_v <= dv_r(63 downto 0); end if;
          else
            if xb(63) = '1' then acc_v <= unsigned(-signed(dv_d - dv_r(63 downto 0)));
            else acc_v <= dv_d - dv_r(63 downto 0); end if;
          end if;
        when SF_MODF =>                         -- F64: a (fp_r), then b
          fx_a <= fp_r;
          if sb_kind = VK_I then
            cv_v <= sb_v; cv_k <= sb_k; cv_ret <= SF_MODF2; cv_step <= 0; st <= CV_START;
          else
            fp_r <= sb_v; st <= SF_MODF2;
          end if;
        when SF_MODF2 =>                        -- q = a / b
          fx_b <= fp_r;
          fp_a <= fx_a; fp_b <= fp_r; fp_op <= FP_DIV; fp_ret <= SF_FLOOR; st <= FP_START;
        when SF_FLOOR =>                        -- floor(q) (inf / NaN: the result NaN), b x it
          if fp_r(62 downto 52) = "11111111111" then
            acc_kind <= VK_F; acc_v <= F64_NAN; st <= SF_DONE;
          else
            fp_a <= fx_b; fp_b <= f_floor(fp_r); fp_op <= FP_MUL; fp_ret <= SF_MODF3; st <= FP_START;
          end if;
        when SF_MODF3 =>                        -- a - b x floor(q)
          fp_a <= fx_a; fp_b <= fp_r; fp_op <= FP_SUB; fp_ret <= SF_MODF4; st <= FP_START;
        when SF_MODF4 =>
          acc_kind <= VK_F; acc_v <= fp_r; acc_k <= x"00";
          st <= SF_DONE;
        -- ROUND and POWER: the second argument, an integer
        when SF_B2 =>
          st <= SF_DONE;
          if ag_fid = 10 then                     -- ROUND(x, n): n in -18..18
            if sb_kind /= VK_I or sb_k(6 downto 0) /= 0 or signed(sb_v) > 18 or signed(sb_v) < -18 then
              acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM;
            else
              rn_n <= signed(sb_v(7 downto 0));
              if sa_kind = VK_I and not (sa_k(6 downto 0) /= 0 and sa_k(7) = '1') then
                st <= SF_RNDI;
              else
                if sa_kind = VK_I then cv_v <= sa_v; cv_k <= sa_k; cv_ret <= SF_RNDF; cv_step <= 0; st <= CV_START;
                else fp_r <= sa_v; st <= SF_RNDF; end if;
              end if;
            end if;
          else                                    -- POWER(a, n)
            if sb_kind /= VK_I or sb_k(6 downto 0) /= 0 then
              acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NAME;   -- (a fractional exponent: later)
            elsif ((sa_kind = VK_I and sa_v = 0) or (sa_kind = VK_F and f_zero(sa_v))) and sb_v = 0 then
              acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM;
            elsif ((sa_kind = VK_I and sa_v = 0) or (sa_kind = VK_F and f_zero(sa_v))) and sb_v(63) = '1' then
              acc_kind <= VK_E; acc_v <= x"00000000000000" & E_DIV0;
            else
              pw_neg <= sb_v(63) = '1';
              if sb_v(63) = '1' then pw_n <= unsigned(-signed(sb_v)); else pw_n <= sb_v; end if;
              -- integers to a non-negative power, exactly, while the fixed point fits
              if sa_kind = VK_I and sb_v(63) = '0' and
                (sa_k(6 downto 0) = 0 or (sb_v < 63 and
                  ((sa_k(7) = '1' and to_integer(sa_k(6 downto 0)) * to_integer(sb_v(5 downto 0)) <= 62) or
                   (sa_k(7) = '0' and to_integer(sa_k(6 downto 0)) * to_integer(sb_v(5 downto 0)) <= 18)))) then
                acc_kind <= VK_I; acc_v <= x"0000000000000001";
                if sa_k(6 downto 0) = 0 or sb_v = 0 then acc_k <= x"00";
                else acc_k <= sa_k(7) & to_unsigned(to_integer(sa_k(6 downto 0)) * to_integer(sb_v(5 downto 0)), 7); end if;
                if sb_v = 0 then
                  null;
                elsif sa_v = 0 or sa_v = 1 then
                  acc_v <= sa_v;
                elsif sa_v = x"FFFFFFFFFFFFFFFF" then
                  if sb_v(0) = '1' then acc_v <= sa_v; end if;
                elsif sb_v > 63 then
                  acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM;
                else
                  st <= SF_POWI;
                end if;
              else
                if sa_kind = VK_I then cv_v <= sa_v; cv_k <= sa_k; cv_ret <= SF_POWF; cv_step <= 0; st <= CV_START;
                else fp_r <= sa_v; st <= SF_POWF; end if;
              end if;
            end if;
          end if;
        -- integer power: acc = acc x a, pw_n times
        when SF_POWI =>
          if pw_n = 0 then
            st <= SF_DONE;
          else
            mu_x <= acc_v; mu_y <= sa_v; mu_ret <= SF_POWI2; st <= MU_START;
          end if;
        when SF_POWI2 =>
          if mu_hi /= 0 or (mu_lo(63) = '1' and not (mu_neg and mu_lo = x"8000000000000000")) then
            acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM; st <= SF_DONE;
          else
            if mu_neg then acc_v <= unsigned(-signed(mu_lo)); else acc_v <= mu_lo; end if;
            pw_n <= pw_n - 1;
            st <= SF_POWI;
          end if;
        -- F64 power: square and multiply from the low bit, then 1 / r for n < 0
        when SF_POWF =>
          pw_b <= fp_r; pw_r <= x"3FF0000000000000";
          st <= SF_POWF2;
        when SF_POWF2 =>
          if pw_n = 0 then
            st <= SF_POWF5;
          elsif pw_n(0) = '1' then
            fp_a <= pw_r; fp_b <= pw_b; fp_op <= FP_MUL; fp_ret <= SF_POWF3; st <= FP_START;
          else
            st <= SF_POWF4;
          end if;
        when SF_POWF3 =>
          pw_r <= fp_r;
          st <= SF_POWF4;
        when SF_POWF4 =>                        -- the next bit; a square only if one remains
          pw_n <= '0' & pw_n(63 downto 1);
          if pw_n(63 downto 1) /= 0 then
            fp_a <= pw_b; fp_b <= pw_b; fp_op <= FP_MUL; fp_ret <= SF_POWSQ; st <= FP_START;
          else
            st <= SF_POWF2;
          end if;
        when SF_POWSQ =>                        -- the square into pw_b
          pw_b <= fp_r;
          st <= SF_POWF2;
        when SF_POWF5 =>
          acc_kind <= VK_F; acc_k <= x"00";
          st <= SF_DONE;
          if not pw_neg then
            acc_v <= pw_r;
          elsif f_zero(pw_r) then                 -- 1 / +-0: +-inf
            acc_v <= pw_r(63) & "11111111111" & x"0000000000000";
          else
            fp_a <= x"3FF0000000000000"; fp_b <= pw_r; fp_op <= FP_DIV; fp_ret <= SF_MODF4; st <= FP_START;
          end if;
        -- ROUND, integers (decimal fixed point k): to n decimals, half away
        when SF_RNDI =>
          if rn_n >= signed(resize(sa_k(6 downto 0), 8)) then
            acc_kind <= VK_I; acc_v <= sa_v; acc_k <= sa_k; st <= SF_DONE;
          elsif to_integer(signed(resize(sa_k(6 downto 0), 8))) - to_integer(rn_n) > 19 then
            acc_kind <= VK_I; acc_v <= (others => '0'); acc_k <= x"00";   -- (rounds to 0)
            if rn_n >= 0 then acc_k <= unsigned(rn_n); end if;
            st <= SF_DONE;
          else
            if sa_v(63) = '1' then dv_n <= x"0000000000000000" & unsigned(-signed(sa_v));
            else dv_n <= x"0000000000000000" & sa_v; end if;
            dv_d <= P10(to_integer(signed(resize(sa_k(6 downto 0), 8))) - to_integer(rn_n));
            dv_neg <= sa_v(63) = '1';
            dv_raw <= false; dv_ret <= SF_RNDI2; st <= DV_START;
          end if;
        when SF_RNDI2 =>                        -- q; n < 0: q x 10^-n
          if dv_neg then e := unsigned(-signed(dv_q(63 downto 0))); else e := dv_q(63 downto 0); end if;
          if rn_n >= 0 then
            acc_kind <= VK_I; acc_v <= e; acc_k <= unsigned(rn_n); st <= SF_DONE;
          else
            acc_kind <= VK_I; acc_k <= x"00";
            mu_x <= e; mu_y <= P10(-to_integer(rn_n)); mu_ret <= SF_RNDI3; st <= MU_START;
          end if;
        when SF_RNDI3 =>                        -- q x 10^-n, unless it overflowed
          st <= SF_DONE;
          if mu_hi /= 0 or (mu_lo(63) = '1' and not (mu_neg and mu_lo = x"8000000000000000")) then
            acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM;
          elsif mu_neg then
            acc_v <= unsigned(-signed(mu_lo));
          else
            acc_v <= mu_lo;
          end if;
        -- ROUND, F64, exactly (5.7).  |x| = m x 2^E.  n >= 0: p = m x 10^n,
        -- N = p / 2^-E rounded half away (unless no digits are below 10^-n,
        -- or |x| x 10^n >= 2^53: x itself), then F64(N) / F64(10^n).  n < 0:
        -- |x|'s integer part, rounded at 10^-n, times 10^-n (|x| >= 2^63: x)
        when SF_RNDF =>
          rf_x <= fp_r; rf_neg <= fp_r(63);
          rf_fp <= false; rf_mag <= false;
          st <= SF_RNDF4;
          acc_kind <= VK_F; acc_k <= x"00";
          if f_zero(fp_r) or fp_r(62 downto 52) = "11111111111" then
            acc_v <= fp_r;
          elsif rn_n >= 0 then
            if fp_r(62 downto 52) >= 1075 then      -- E >= 0: integral, nothing below 10^-n
              acc_v <= fp_r;
            else
              rf_sh <= to_signed(1075, 13) - signed(resize(fp_r(62 downto 52), 13));
              mu_x <= x"00" & "000" & '1' & fp_r(51 downto 0); mu_y <= P10(to_integer(rn_n));
              mu_ret <= SF_RF_MUL; st <= MU_START;
            end if;
          elsif fp_r(62 downto 52) >= 1023 + 63 then  -- |x| >= 2^63
            acc_v <= fp_r;
          else
            -- the integer part: m shifted (E in -1075..10)
            rf_p <= x"0000000000000000" & x"00" & "000" & '1' & fp_r(51 downto 0);
            rf_sh <= to_signed(1075, 13) - signed(resize(fp_r(62 downto 52), 13));
            st <= SF_RN_SH;
          end if;
        when SF_RF_MUL =>                       -- p (128 bits), then the shift
          rf_p <= mu_hi(63 downto 0) & mu_lo; rf_rb <= '0';
          if rf_sh >= 115 then                    -- (p < 2^113: rounds to 0)
            rf_p <= (others => '0'); rf_sh <= (others => '0');
          end if;
          st <= SF_RF_SH;
        when SF_RF_SH =>                        -- one bit a cycle, the last one kept
          if rf_sh = 0 then
            st <= SF_RF_N;
          else
            rf_rb <= rf_p(0);
            rf_p <= '0' & rf_p(127 downto 1);
            rf_sh <= rf_sh - 1;
          end if;
        when SF_RF_N =>                         -- N = floor + the rounding bit
          if rf_p(127 downto 53) /= 0 then        -- |x| x 10^n >= 2^53: x
            acc_v <= rf_x; st <= SF_RNDF4;
          else
            fn_s <= '0'; fn_sig <= rf_p(63 downto 0) + resize(unsigned'("" & rf_rb), 64);
            fn_e <= to_signed(1023 + 63, 14); fn_st <= '0';
            if rf_p(63 downto 0) = 0 and rf_rb = '0' then
              acc_v <= (others => '0'); rf_mag <= true; st <= SF_RNDF4;    -- (rounds to 0)
            else
              fn_ret <= SF_RF_C2; st <= FN_NORM;
            end if;
          end if;
        when SF_RF_C2 =>                        -- F64(N); then F64(10^n)
          cv_t <= fp_r;
          fn_s <= '0'; fn_sig <= P10(to_integer(rn_n)); fn_e <= to_signed(1023 + 63, 14); fn_st <= '0';
          fn_ret <= SF_RF_DIV; st <= FN_NORM;
        when SF_RF_DIV =>
          fp_a <= cv_t; fp_b <= fp_r; fp_op <= FP_DIV; fp_ret <= SF_RNDF4; st <= FP_START;
          rf_fp <= true; rf_mag <= true;
        when SF_RN_SH =>                        -- the integer part of |x|
          if rf_sh <= 0 then
            if rf_sh < 0 then                     -- E > 0: shift left
              rf_p <= rf_p(126 downto 0) & '0'; rf_sh <= rf_sh + 1;
            else
              dv_n <= rf_p; dv_d <= P10(-to_integer(rn_n));
              dv_raw <= true; dv_ret <= SF_RN_DIV; st <= DV_START;
            end if;
          elsif rf_p = 0 then
            rf_sh <= (others => '0');
          else
            rf_p <= '0' & rf_p(127 downto 1); rf_sh <= rf_sh - 1;
          end if;
        when SF_RN_DIV =>                       -- q, r: N = q + (r >= 5 x 10^(k-1))
          if dv_r(63 downto 0) >= resize(P10(-to_integer(rn_n) - 1) * to_unsigned(5, 4), 64) then
            mu_x <= dv_q(63 downto 0) + 1;
          else
            mu_x <= dv_q(63 downto 0);
          end if;
          mu_y <= P10(-to_integer(rn_n)); mu_ret <= SF_RN_MUL; st <= MU_START;
        when SF_RN_MUL =>                       -- N x 10^k (< 2^64), to F64
          rf_mag <= true;
          if mu_lo = 0 then
            acc_v <= (others => '0'); st <= SF_RNDF4;
          else
            fn_s <= '0'; fn_sig <= mu_lo; fn_e <= to_signed(1023 + 63, 14); fn_st <= '0';
            fn_ret <= SF_RNDF4; st <= FN_NORM;
            rf_fp <= true;
          end if;
        when SF_RNDF4 =>                        -- the result, with x's sign on a magnitude
          acc_kind <= VK_F; acc_k <= x"00";
          st <= SF_DONE;
          if rf_fp then e := fp_r; else e := acc_v; end if;
          if rf_mag then e(63) := rf_neg; end if;
          acc_v <= e;
        -- SQRT, F64: negatives #NUM!; NaN, infinity, zeros as they are
        when SF_SQRT =>
          st <= SF_DONE;
          acc_kind <= VK_F; acc_k <= x"00";
          if f_nan(fp_r) or f_zero(fp_r) or (f_inf(fp_r) and fp_r(63) = '0') then
            acc_v <= fp_r;
          elsif fp_r(63) = '1' then
            acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM;
          else
            -- the significand, times 2^74 (or 2^75: an odd exponent)
            if fp_r(52) = '1' then                -- (biased odd: exponent - 1023 even)
              sq_r <= "01" & fp_r(51 downto 0) & x"0000000000000000" & "0000000000";   -- m x 2^74
            else
              sq_r <= '1' & fp_r(51 downto 0) & x"0000000000000000" & "00000000000";   -- m x 2^75
            end if;
            sq_rem <= (others => '0'); sq_root <= (others => '0'); sq_i <= 0;
            fn_e <= to_signed(1023, 14) + shift_right(signed(resize(fp_r(62 downto 52), 14)) - 1023, 1);
            st <= SQ_STEP;
          end if;
        when SQ_STEP =>                         -- one root bit a step (restoring)
          if sq_i = 64 then
            fn_s <= '0'; fn_sig <= sq_root; fn_st <= b2s(sq_rem /= 0);
            fn_ret <= SF_MODF4; st <= FN_NORM;
          else
            e := (others => '0');
            sq_rem <= (sq_rem(63 downto 0) & sq_r(127 downto 126));
            if (sq_rem(63 downto 0) & sq_r(127 downto 126)) >= (sq_root & "01") then
              sq_rem <= (sq_rem(63 downto 0) & sq_r(127 downto 126)) - (sq_root & "01");
              sq_root <= sq_root(62 downto 0) & '1';
            else
              sq_root <= sq_root(62 downto 0) & '0';
            end if;
            sq_r <= sq_r(125 downto 0) & "00";
            sq_i <= sq_i + 1;
          end if;

        when SF_DONE =>
          st <= AG_RESULT;

        -- --------------------------------------------------------------
        -- Aggregates (section 4): the arguments in order, each a range, a
        -- cell list or a value; an error among them ends the formula, a
        -- fold's error is kept as the result
        when AG_START =>
          if resize(ag_argc, 32) > to_unsigned(esp, 32) then
            e_abort(E_STACK);
          else
            ag_i <= esp - to_integer(ag_argc);
            ag_cnt <= (others => '0'); ag_ferr <= false;
            acc_kind <= VK_I; acc_v <= (others => '0'); acc_k <= x"00";
            ag_pc <= pc;
            ag_all <= true; ag_any <= false; ag_bad <= false;
            if ag_fid = 6 then acc_v <= x"0000000000000001"; end if;   -- PRODUCT: from 1
            if ag_fid <= 6 or ag_fid = 14 or ag_fid = 15 then
              st <= AG_ARG;                       -- an aggregate
            elsif ag_fid = 7 or ag_fid = 8 or ag_fid = 9 or ag_fid = 10 or ag_fid = 11 or ag_fid = 12
              or ag_fid = 13 or ag_fid = 16 or ag_fid = 29 then
              st <= SF_START;                     -- a scalar function
            else
              acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NAME;
              st <= AG_RESULT;
            end if;
          end if;
        when AG_ARG =>
          if ag_i = esp then
            st <= AG_FINISH;
          else
            est_ra <= ag_i; est_ret <= AG_ARG2; st <= EST_WAIT;
          end if;
        when AG_ARG2 =>                         -- argument ag_i
          ent := est_q;
          case ent(75 downto 73) is
            when VK_R =>
              ag_row <= x"000" & ent(63 downto 44);
              if ent(19 downto 0) < nrows(19 downto 0) or nrows(31 downto 20) /= 0 then
                ag_rlast <= x"000" & ent(19 downto 0);
              else
                ag_rlast <= nrows - 1;
              end if;
              ag_c1 <= x"00" & ent(43 downto 20);
              ag_c2 <= x"00" & ent(99 downto 76);
              st <= AG_RROW;
            when VK_L =>
              pc <= ent(15 downto 0); ag_ln <= ent(31 downto 16);
              st <= AG_LNEXT;
            when others =>
              vr_kind <= ent(75 downto 73); vr_v <= ent(63 downto 0); vr_k <= ent(71 downto 64);
              ag_fromc <= ent(72) = '1';
              tk_ret <= AG_NEXTARG; st <= AG_TAKE;
          end case;

        when AG_NEXTARG =>
          ag_i <= ag_i + 1;
          st <= AG_ARG;

        -- a range: rows ag_row..ag_rlast, columns ag_c1..ag_c2
        when AG_RROW =>
          if ag_row > ag_rlast then
            st <= AG_NEXTARG;
          else
            mem_read(rowtab + (ag_row(25 downto 0) & "00"), AG_RROW2);
          end if;
        when AG_RROW2 =>
          if ag_row(0) = '0' then e := x"00000000" & m_rd(31 downto 0);
          else e := x"00000000" & m_rd(63 downto 32); end if;
          if e(31 downto 0) = x"FFFFFFFF" then
            ag_row <= ag_row + 1; st <= AG_RROW;
          else
            ag_blk <= e(27 downto 0);
            mem_read(e(27 downto 0) + 8, AG_RROW3);
          end if;
        when AG_RROW3 =>                        -- the root: the walk starts
          tw_cur <= m_rd(11 downto 0); tw_d <= to_unsigned(1, 6); tw_sp <= 0;
          st <= AG_TW;
        when AG_TW =>
          if tw_cur /= 0 then
            if tw_d > 32 then
              format_fault(ag_row);             -- (a tree deeper than 32)
            else
              mem_read(ag_blk + (tw_cur & "0000"), AG_TW2);
            end if;
          elsif tw_sp = 0 then
            ag_row <= ag_row + 1; st <= AG_RROW;   -- (the row's walk is over)
          else
            -- the next node in order: visit it (in the columns), then its right
            tw_sp <= tw_sp - 1;
            e := x"00" & resize(tws(tw_sp - 1), 56);
            if e(35 downto 12) < ag_c2(23 downto 0) then
              tw_nxt <= e(47 downto 36); tw_nd <= e(53 downto 48) + 1;
            else
              tw_nxt <= (others => '0'); tw_nd <= (others => '0');
            end if;
            if resize(e(35 downto 12), 32) >= ag_c1 and resize(e(35 downto 12), 32) <= ag_c2 then
              q_addr <= ag_blk + (e(11 downto 0) & "0000");
              vl_ret <= AG_VISITED; st <= VL_HDR;
            else
              st <= AG_VISITED;
              vr_kind <= "111";                  -- (none: nothing to take)
            end if;
          end if;
        when AG_TW2 =>                          -- a node: kept, then its left (if needed)
          tws_we := true; tws_wa := tw_sp;                 -- (tw_sp < 32 here)
          tws_wd := tw_d & m_rd(63 downto 52) & m_rd(23 downto 0) & tw_cur;
          tw_sp <= tw_sp + 1;
          if resize(m_rd(23 downto 0), 32) > ag_c1 then
            tw_cur <= m_rd(51 downto 40); tw_d <= tw_d + 1;
          else
            tw_cur <= (others => '0');
          end if;
          st <= AG_TW;
        when AG_VISITED =>
          tw_cur <= tw_nxt; tw_d <= tw_nd;
          if vr_kind = "111" then
            st <= AG_TW;
          else
            ag_fromc <= true; tk_ret <= AG_TW; st <= AG_TAKE;
          end if;

        -- a cell list: ag_ln references from pc
        when AG_LNEXT =>
          if ag_ln = 0 then
            pc <= ag_pc; st <= AG_NEXTARG;
          else
            ag_ln <= ag_ln - 1;
            rf_ret <= AG_LREF; st <= RF_START;
          end if;
        when AG_LREF =>
          if q_row >= nrows or q_col >= ncols then
            e_abort(E_REF);
          else
            vl_ret <= AG_LTAKE; lk_ret <= VL_HDR; st <= LK_START;
          end if;
        when AG_LTAKE =>
          ag_fromc <= true; tk_ret <= AG_LNEXT; st <= AG_TAKE;

        -- one value (vr_*; ag_fromc: from cells, whose text and blanks are
        -- skipped) into the aggregate, then tk_ret
        when AG_TAKE =>
          if ag_fid = 5 then                      -- COUNTA: everything but blanks
            if vr_kind /= VK_Z then ag_cnt <= ag_cnt + 1; end if;
            st <= tk_ret;
          elsif vr_kind = VK_E then
            pc <= ag_pc; e_abort(vr_v(7 downto 0));
          elsif vr_kind = VK_I or vr_kind = VK_F then
            ag_cnt <= ag_cnt + 1;
            st <= tk_ret;
            if ag_fid = 0 or ag_fid = 1 or ag_fid = 6 then   -- SUM, AVERAGE (+), PRODUCT (*)
              if not ag_ferr then
                bo_ka <= acc_kind; bo_va <= acc_v; bo_fa <= acc_k;
                bo_kb <= vr_kind; bo_vb <= vr_v; bo_fb <= vr_k;
                if ag_fid = 6 then bo_op <= x"12"; else bo_op <= x"10"; end if;
                bo_ret <= AG_SUMR; st <= BO_START;
              end if;
            elsif ag_fid = 14 or ag_fid = 15 then -- AND, OR
              if vr_kind = VK_I and bad_k(vr_k) then ag_bad <= true; end if;
              if (vr_kind = VK_I and vr_v = 0) or (vr_kind = VK_F and f_zero(vr_v)) then
                ag_all <= false;
              else
                ag_any <= true;
              end if;
            elsif ag_fid = 2 or ag_fid = 3 then   -- MIN, MAX
              if ag_cnt = 0 then
                best_kind <= vr_kind; best_v <= vr_v; best_k <= vr_k;
              elsif not ag_ferr then
                bo_ka <= vr_kind; bo_va <= vr_v; bo_fa <= vr_k;
                bo_kb <= best_kind; bo_vb <= best_v; bo_fb <= best_k;
                if ag_fid = 2 then bo_op <= x"1A"; else bo_op <= x"1C"; end if;
                bo_ret <= AG_MMR; st <= BO_START;
              end if;
            end if;
          elsif (vr_kind = VK_T or vr_kind = VK_Z) and ag_fromc then
            st <= tk_ret;
          else
            pc <= ag_pc; e_abort(E_VALUE);
          end if;
        when AG_SUMR =>
          acc_kind <= br_kind; acc_v <= br_v; acc_k <= br_k;
          if br_kind = VK_E then ag_ferr <= true; end if;
          st <= tk_ret;
        when AG_MMR =>
          if br_kind = VK_E then
            ag_ferr <= true; best_kind <= br_kind; best_v <= br_v; best_k <= br_k;
          elsif br_v(0) = '1' then
            best_kind <= vr_kind; best_v <= vr_v; best_k <= vr_k;
          end if;
          st <= tk_ret;
        when AG_FINISH =>
          st <= AG_RESULT;
          if ag_fid = 14 or ag_fid = 15 then      -- AND, OR
            acc_kind <= VK_I; acc_k <= x"00";
            if ag_cnt = 0 then
              acc_kind <= VK_E; acc_v <= x"00000000000000" & E_VALUE;
            elsif ag_bad then
              acc_kind <= VK_E; acc_v <= x"00000000000000" & E_NUM;
            elsif ag_fid = 14 then
              acc_v <= b64(ag_all);
            else
              acc_v <= b64(ag_any);
            end if;
          else
          case ag_fid(2 downto 0) is
            when "100" | "101" =>                 -- COUNT, COUNTA
              acc_kind <= VK_I; acc_v <= x"00000000" & ag_cnt; acc_k <= x"00";
            when "110" =>                         -- PRODUCT (no numbers: 0)
              if ag_cnt = 0 then acc_kind <= VK_I; acc_v <= (others => '0'); acc_k <= x"00"; end if;
            when "010" | "011" =>                 -- MIN, MAX
              if ag_cnt = 0 then
                acc_kind <= VK_I; acc_v <= (others => '0'); acc_k <= x"00";
              else
                acc_kind <= best_kind; acc_v <= best_v; acc_k <= best_k;
              end if;
            when "001" =>                         -- AVERAGE: SUM / COUNT
              if ag_ferr then
                null;
              elsif ag_cnt = 0 then
                acc_kind <= VK_E; acc_v <= x"00000000000000" & E_DIV0;
              else
                bo_ka <= acc_kind; bo_va <= acc_v; bo_fa <= acc_k;
                bo_kb <= VK_I; bo_vb <= x"00000000" & ag_cnt; bo_fb <= x"00";
                bo_op <= x"13"; bo_ret <= AG_AVGR; st <= BO_START;
              end if;
            when others =>                        -- SUM
              null;
          end case;
          end if;
        when AG_AVGR =>
          acc_kind <= br_kind; acc_v <= br_v; acc_k <= br_k;
          st <= AG_RESULT;
        when AG_RESULT =>                       -- the arguments replaced by the result
          pc <= ag_pc;
          if ag_argc = 0 then
            push(acc_kind, acc_v, acc_k, '0', E_NEXT);
          else
            esp <= esp - to_integer(ag_argc) + 1;
            t_kind <= acc_kind; t_v <= acc_v; t_k <= acc_k; t_ref <= '0'; t_aux <= (others => '0');
            st <= E_NEXT;
          end if;

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
            est_ra <= esp - 2; est_ret <= E_BIN3; st <= EST_WAIT;
          end if;
        when E_BIN3 =>                          -- a: the entry below the top
          bo_ka <= est_q(75 downto 73); bo_va <= est_q(63 downto 0); bo_fa <= est_q(71 downto 64);
          bo_kb <= t_kind; bo_vb <= t_v; bo_fb <= t_k;
          bo_op <= cur_op; bo_ret <= E_BINW;
          esp <= esp - 1;
          st <= BO_START;
        when E_BINW =>
          t_kind <= br_kind; t_v <= br_v; t_k <= br_k; t_ref <= '0';
          st <= E_NEXT;

        -- a binary operator: bo_op on (bo_ka, bo_va, bo_fa), (bo_kb, ...),
        -- the result in br_kind, br_v, br_k, then bo_ret
        when BO_START =>
          if false then
            null;
          else
            ka := bo_ka; va := bo_va; kb := bo_kb; vb := bo_vb; fa := bo_fa; fb := bo_fb;
            -- blank is 0; text is #VALUE!
            if ka = VK_Z then ka := VK_I; va := (others => '0'); fa := x"00"; end if;
            if kb = VK_Z then kb := VK_I; vb := (others => '0'); fb := x"00"; end if;
            br_k <= x"00";
            st <= bo_ret;
            xa <= va; xb <= vb;
            if ka = VK_E then
              br_kind <= VK_E; br_v <= va;
            elsif ka /= VK_I and ka /= VK_F then
              br_kind <= VK_E; br_v <= x"00000000000000" & E_VALUE;
            elsif ka = VK_I and bad_k(fa) then
              br_kind <= VK_E; br_v <= x"00000000000000" & E_NUM;
            elsif kb = VK_E then
              br_kind <= VK_E; br_v <= vb;
            elsif kb /= VK_I and kb /= VK_F then
              br_kind <= VK_E; br_v <= x"00000000000000" & E_VALUE;
            elsif kb = VK_I and bad_k(fb) then
              br_kind <= VK_E; br_v <= x"00000000000000" & E_NUM;
            elsif ka = VK_I and kb = VK_I and
              not (fa(6 downto 0) /= 0 and fb(6 downto 0) /= 0 and fa(7) /= fb(7)) then
              -- integers whose fixed points align (the same base, or one plain)
              if fa(6 downto 0) /= 0 then bin := fa(7); else bin := fb(7); end if;
              case bo_op is
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
                    br_kind <= VK_E; br_v <= x"00000000000000" & E_DIV0;
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
            br_kind <= VK_E; br_v <= x"00000000000000" & E_NUM; st <= bo_ret;
          else
            if mu_neg then e := unsigned(-signed(mu_lo)); else e := mu_lo; end if;
            if sc_b then xb <= e; else xa <= e; end if;
            st <= E_ARITH;
          end if;
        when E_ARITH =>                         -- xa op xb, aligned
          lt := signed(xa) < signed(xb); eq := xa = xb;
          br_kind <= VK_I; br_k <= x"00";
          st <= bo_ret;
          case bo_op is
            when x"10" | x"11" =>
              if bo_op = x"10" then sum := unsigned(resize(signed(xa), 65) + resize(signed(xb), 65));
              else sum := unsigned(resize(signed(xa), 65) - resize(signed(xb), 65)); end if;
              if sum(64) /= sum(63) then br_kind <= VK_E; br_v <= x"00000000000000" & E_NUM;
              else br_v <= sum(63 downto 0); br_k <= x_k; end if;
            when x"18" => br_v <= b64(eq);
            when x"19" => br_v <= b64(not eq);
            when x"1A" => br_v <= b64(lt);
            when x"1B" => br_v <= b64(lt or eq);
            when x"1C" => br_v <= b64(not (lt or eq));
            when others => br_v <= b64(not lt);
          end case;
        when E_MULF =>                          -- the product, signed back
          st <= bo_ret;
          if mu_hi /= 0 or (mu_lo(63) = '1' and not (mu_neg and mu_lo = x"8000000000000000")) then
            br_kind <= VK_E; br_v <= x"00000000000000" & E_NUM;
          else
            br_kind <= VK_I; br_k <= x_k;
            if mu_neg then br_v <= unsigned(-signed(mu_lo)); else br_v <= mu_lo; end if;
          end if;
        when E_DIVM =>                          -- a * 10^k (128 bits) / |b|
          dv_n <= mu_hi(63 downto 0) & mu_lo;
          if xb(63) = '1' then dv_d <= unsigned(-signed(xb)); else dv_d <= xb; end if;
          dv_neg <= mu_neg xor (xb(63) = '1');
          dv_raw <= false; dv_ret <= E_DIVF; st <= DV_START;
        when E_DIVF =>
          st <= bo_ret;
          if dv_q(127 downto 64) /= 0 or (dv_q(63) = '1' and not (dv_neg and dv_q(63 downto 0) = x"8000000000000000")) then
            br_kind <= VK_E; br_v <= x"00000000000000" & E_NUM;
          else
            br_kind <= VK_I; br_k <= x_k;
            if dv_neg then br_v <= unsigned(-signed(dv_q(63 downto 0))); else br_v <= dv_q(63 downto 0); end if;
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
          br_kind <= VK_I; br_k <= x"00";
          st <= bo_ret;
          case bo_op is
            when x"18" => br_v <= b64(f_eq(fx_a, fx_b));
            when x"19" => br_v <= b64(not f_eq(fx_a, fx_b));
            when x"1A" => br_v <= b64(f_lt(fx_a, fx_b));
            when x"1B" => br_v <= b64(f_lt(fx_a, fx_b) or f_eq(fx_a, fx_b));
            when x"1C" => br_v <= b64(f_lt(fx_b, fx_a));
            when x"1D" => br_v <= b64(f_lt(fx_b, fx_a) or f_eq(fx_a, fx_b));
            when x"13" =>
              if f_zero(fx_b) then
                br_kind <= VK_E; br_v <= x"00000000000000" & E_DIV0;
              else
                fp_a <= fx_a; fp_b <= fx_b; fp_op <= FP_DIV; fp_ret <= E_FBR; st <= FP_START;
              end if;
            when x"10" => fp_a <= fx_a; fp_b <= fx_b; fp_op <= FP_ADD; fp_ret <= E_FBR; st <= FP_START;
            when x"11" => fp_a <= fx_a; fp_b <= fx_b; fp_op <= FP_SUB; fp_ret <= E_FBR; st <= FP_START;
            when others => fp_a <= fx_a; fp_b <= fx_b; fp_op <= FP_MUL; fp_ret <= E_FBR; st <= FP_START;
          end case;
        when E_FBR =>
          br_kind <= VK_F; br_v <= fp_r;
          st <= bo_ret;

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

        -- --------------------------------------------------------------
        -- COMPILE, DECOMPILE, RENDER, PARSE (section 10): the parameter
        -- block (32 bytes) and the descriptor's codec settings, the job on
        -- its unit, the results back
        when X_P0 =>
          xp0 <= m_rd; desc <= m_rd(27 downto 0);
          mem_read(xblk + 8, X_P8);
        when X_P8 =>
          xp8 <= m_rd; mem_read(xblk + 16, X_P16);
        when X_P16 =>
          xp16 <= m_rd; mem_read(xblk + 24, X_P24);
        when X_P24 =>
          xp24 <= m_rd;
          if r_op = x"43" then mem_read(xblk + 32, FC_P32);   -- (FORMAT_CELLS: 48 bytes)
          else mem_read(desc + 56, X_D56); end if;
        when X_D56 =>                           -- names, separators (0: "." and ",")
          co_names <= m_rd(27 downto 0);
          if m_rd(39 downto 32) = 0 then co_dsep <= x"2E"; else co_dsep <= m_rd(39 downto 32); end if;
          if m_rd(47 downto 40) = 0 then co_asep <= x"2C"; else co_asep <= m_rd(47 downto 40); end if;
          st <= X_GO;
        when X_GO =>
          sj_seen_done <= false; sj_mode <= true; sj_ret <= X_RES;
          st <= SJ_WAIT;
          case r_op is
            when x"44" | x"45" =>                 -- COMPILE / DECOMPILE
              co_source <= xp0(59 downto 32); co_len <= xp8(15 downto 0); co_cap <= xp8(31 downto 16);
              co_row <= xp8(51 downto 32); co_col <= xp16(23 downto 0); co_dest <= xp16(59 downto 32);
              co_decompile <= r_op(0);
              x_job <= "00"; nu_client <= "00"; co_start <= '1';
            when x"46" =>                         -- RENDER
              ce_kind <= xp0(35 downto 32);
              ce_format <= xp16(63 downto 24) & xp0(47 downto 40) & xp16(15 downto 0);   -- (byte 2: the block's fixed point)
              ce_width <= xp0(55 downto 48); ce_upper <= xp0(63);
              ce_value <= xp8; ce_text <= xp8(27 downto 0); ce_tlen <= xp8(47 downto 32);
              ce_dest <= xp24(27 downto 0); ce_scratch <= xp24(59 downto 32);
              ce_cap <= x"00" & xp0(55 downto 48);
              x_job <= "01"; nu_client <= "01"; ce_start <= '1';
            when others =>                        -- PARSE: the literal (the front end: to come)
              sf_source <= xp0(59 downto 32); sf_len <= xp8(15 downto 0);
              x_job <= "10"; nu_client <= "10"; nu_start_self <= '1';
          end case;
        when X_RES =>
          sj_mode <= false;
          wr <= '1';
          case r_op is
            when x"44" | x"45" =>                 -- length, error, host calls, position (bytes 24-29)
              if co_error = CODEC_OK then result <= x"0000" & co_rlen; else result <= (others => '0'); end if;
              mem_write(xblk + 24, x"0000" & co_epos & co_hosts & co_error & co_rlen, "11111111", X_RES2);
            when x"46" =>                         -- R[a]: the colour; a renderer error in bits 15-8
              result <= x"0000" & ce_error & x"0" & ce_colour;
              st <= X_RES2;
            when others =>                        -- PARSE: the value (bytes 16-23), then its kind
              if nu_error /= CODEC_OK then
                result <= (others => '0');
                mem_write(xblk + 16, (others => '0'), "11111111", X_RES3);
              else
                if nu_rkind = '1' then result <= x"00000003"; else result <= x"00000004"; end if;
                mem_write(xblk + 16, nu_rvalue, "11111111", X_RES3);
              end if;
          end case;
        when X_RES3 =>                          -- PARSE: kind, fixed point, style, prefix (24-27)
          if nu_error /= CODEC_OK then
            mem_write(xblk + 24, (others => '0'), "11111111", X_RES2);
          elsif nu_rkind = '1' then
            mem_write(xblk + 24, x"00000000" & x"0000" & nu_rscale & x"03", "11111111", X_RES2);
          else
            mem_write(xblk + 24, x"00000000" & x"0000" & nu_rscale & x"04", "11111111", X_RES2);
          end if;
        when X_RES2 =>                          -- a unit's memory fault or abort ends the job
          if (r_op /= x"46" and r_op /= x"47" and co_error = CODEC_MEMORY)
            or (r_op = x"46" and ce_error = CODEC_MEMORY) or (r_op = x"47" and nu_error = CODEC_MEMORY) then
            err <= ERR_ADDRESS;
          elsif (r_op /= x"46" and r_op /= x"47" and co_error = CODEC_ABORTED)
            or (r_op = x"46" and ce_error = CODEC_ABORTED) or (r_op = x"47" and nu_error = CODEC_ABORTED) then
            err <= ERR_ABORTED;
          end if;
          st <= S_FINISH;

        -- --------------------------------------------------------------
        -- FORMAT_CELLS (section 6): rows r1..r2, columns c1..c2 (widths from
        -- the list), each field rendered (RENDER's unit), colours, CHANGED
        when FC_P32 =>
          xp32 <= m_rd; mem_read(xblk + 40, FC_P40);
        when FC_P40 =>
          xp40 <= m_rd; mem_read(desc, FC_D0);
        when FC_D0 =>                           -- the descriptor: magic, row table
          if m_rd(31 downto 0) /= x"31544853" then
            format_fault(x"FFFFFFFF");
          else
            rowtab <= m_rd(59 downto 32); mem_read(desc + 8, FC_D8);
          end if;
        when FC_D8 =>
          nrows <= m_rd(31 downto 0); ncols <= m_rd(63 downto 32);
          mem_read(desc + 56, FC_D56);
        when FC_D56 =>
          if m_rd(39 downto 32) = 0 then co_dsep <= x"2E"; else co_dsep <= m_rd(39 downto 32); end if;
          fc_row <= xp0(63 downto 32);
          fc_line <= xp24(27 downto 0); fc_cline <= xp32(27 downto 0);
          fc_bvalid <= false; fw_valid <= false;
          st <= FC_ROWS;
        when FC_ROWS =>
          if fc_row > xp8(31 downto 0) or fc_row >= nrows then
            st <= S_FINISH;
          elsif abt = '1' then
            fault(ERR_ABORTED);
          else
            fc_col <= xp8(63 downto 32); fc_x <= (others => '0'); fc_cx <= (others => '0');
            st <= FC_COLS;
          end if;
        when FC_COLS =>                          -- the column's width (a byte of the list)
          if fc_col > xp16(31 downto 0) then
            fc_row <= fc_row + 1;
            fc_line <= fc_line + xp24(47 downto 32); fc_cline <= fc_cline + xp32(47 downto 32);
            st <= FC_ROWS;
          else
            ad := xp16(59 downto 32) + resize(fc_col - xp8(63 downto 32), 28);
            if fw_valid and ad(27 downto 3) = fw_tag then
              fc_w <= fw_buf(to_integer(ad(2 downto 0)) * 8 + 7 downto to_integer(ad(2 downto 0)) * 8);
              st <= FC_WID;
            else
              fw_tag <= ad(27 downto 3);
              mem_read(ad, FC_WFILL);
            end if;
          end if;
        when FC_WFILL =>
          fw_buf <= m_rd; fw_valid <= true;
          st <= FC_COLS;
        when FC_WID =>
          if fc_w = 0 then
            fc_col <= fc_col + 1; st <= FC_COLS;   -- (a hidden column)
          else
            q_row <= fc_row; q_col <= fc_col; lk_ret <= FC_CELLS; st <= LK_START;
          end if;
        when FC_CELLS =>                         -- the cell (none: blank)
          fc_cell <= q_addr;
          ce_kind <= x"0"; ce_value <= (others => '0'); ce_format <= (others => '0');
          ce_tlen <= (others => '0'); fc_changed <= false; fc_numfmt <= false;
          if q_col >= ncols or q_addr = 0 then
            if xp24(56) = '1' then st <= FC_NEXT; else st <= FC_RENDER; end if;
          else
            mem_read(q_addr, FC_H);
          end if;
        when FC_H =>                            -- its header: kind, CHANGED
          fc_hdr <= m_rd;
          fc_changed <= m_rd(28) = '1';
          if xp24(56) = '1' and m_rd(28) = '0' then
            st <= FC_NEXT;                        -- (only cells with CHANGED)
          else
            mem_read(fc_cell + 8, FC_G8);
          end if;
        when FC_G8 =>                           -- +8: a format, a value, or an error code
          case fc_hdr(27 downto 24) is
            when K_EMPTY =>
              ce_kind <= x"0"; ce_format <= m_rd; st <= FC_RENDER;
            when K_ERROR =>
              ce_kind <= x"6"; ce_value <= m_rd; st <= FC_RENDER;
            when K_F64 | K_I64 | K_I32 =>
              ce_kind <= fc_hdr(27 downto 24); ce_value <= m_rd;
              if fc_hdr(30) = '1' then mem_read(fc_cell + 16, FC_G16); else st <= FC_RENDER; end if;
            when others =>                        -- TEXT, FORMULA, UNCOMPILED: the format, then +16
              ce_format <= m_rd; mem_read(fc_cell + 16, FC_G16);
          end case;
        when FC_G16 =>
          case fc_hdr(27 downto 24) is
            when K_F64 | K_I64 | K_I32 =>         -- its format
              ce_format <= m_rd; fc_numfmt <= true; st <= FC_RENDER;
            when K_TEXT =>                        -- length (16-17), text at +18
              ce_kind <= x"1"; ce_tlen <= m_rd(15 downto 0); ce_text <= fc_cell + 18; st <= FC_RENDER;
            when K_UNCOMPILED =>                  -- length (20-21), text at +24
              ce_kind <= x"7"; ce_tlen <= m_rd(47 downto 32); ce_text <= fc_cell + 24; st <= FC_RENDER;
            when others =>                        -- FORMULA: the result (16-23), then its kind (24)
              ce_value <= m_rd; mem_read(fc_cell + 24, FC_G24);
          end case;
        when FC_G24 =>
          st <= FC_RENDER;
          fc_numfmt <= true;
          case m_rd(3 downto 0) is
            when K_F64 | K_I64 | K_I32 => ce_kind <= m_rd(3 downto 0);
            when K_ERROR => ce_kind <= x"6"; fc_numfmt <= false;
            when K_TEXT =>                        -- its text: after the bytecode
              ce_kind <= x"1"; ce_tlen <= ce_value(15 downto 0); fc_numfmt <= false;
              ce_text <= fc_cell + 32 + resize(m_rd(31 downto 16), 28);
            when others => ce_kind <= x"0"; fc_numfmt <= false;
          end case;
        when FC_RENDER =>                       -- one field (char size 2: into scratch, then expanded)
          ce_width <= fc_w; ce_cap <= x"00" & fc_w; ce_upper <= xp24(58);
          ce_scratch <= xp40(27 downto 0);
          if xp24(49 downto 48) = "10" then
            ce_dest <= xp40(27 downto 0) + 512;
          else
            ce_dest <= fc_line + resize(fc_x, 28);
          end if;
          x_job <= "01"; nu_client <= "01"; ce_start <= '1';
          sj_seen_done <= false; sj_mode <= true; sj_ret <= FC_DONE1;
          st <= SJ_WAIT;
        when FC_DONE1 =>
          sj_mode <= false;
          if ce_error = CODEC_MEMORY then err <= ERR_ADDRESS; st <= S_FINISH;
          elsif ce_error = CODEC_ABORTED then err <= ERR_ABORTED; st <= S_FINISH;
          elsif xp24(49 downto 48) = "10" then
            fc_i <= (others => '0'); fc_bvalid <= false; st <= FC_EXP;
          else
            fc_i <= (others => '0'); st <= FC_COLR;
          end if;
        when FC_EXP =>                          -- 16-bit characters: the code, then 0
          if fc_i = resize(fc_w, 9) then
            fc_i <= (others => '0'); fc_bvalid <= false; st <= FC_COLR;
          else
            ad := xp40(27 downto 0) + 512 + resize(fc_i, 28);
            if fc_bvalid and ad(27 downto 3) = fc_tag then
              e := (others => '0');
              e(7 downto 0) := fc_buf(to_integer(ad(2 downto 0)) * 8 + 7 downto to_integer(ad(2 downto 0)) * 8);
              ad := fc_line + resize(fc_x, 28) + resize(fc_i & '0', 28);
              -- (the two bytes at ad: within one group, ad being even)
              mem_write(ad, shift_left(e, to_integer(ad(2 downto 0)) * 8),
                        std_logic_vector(shift_left(unsigned'(x"03"), to_integer(ad(2 downto 0)))), FC_EXP2);
            else
              fc_tag <= ad(27 downto 3);
              mem_read(ad, FC_EFILL);
            end if;
          end if;
        when FC_EFILL =>
          fc_buf <= m_rd; fc_bvalid <= true;
          st <= FC_EXP;
        when FC_EXP2 =>
          fc_i <= fc_i + 1;
          st <= FC_EXP;
        when FC_COLR =>                         -- the colour plane: one byte a character
          if xp32(27 downto 0) = 0 or fc_i = resize(fc_w, 9) then
            st <= FC_CLR;
          else
            ad := fc_cline + resize(fc_cx, 28) + resize(fc_i, 28);
            e := (others => '0');
            if fc_numfmt and ce_kind /= x"0" and ce_format /= 0 then
              e(7 downto 0) := x"0" & ce_colour;
            else
              e(7 downto 0) := xp32(55 downto 48);
            end if;
            fc_i <= fc_i + 1;
            mem_write(ad, shift_left(e, to_integer(ad(2 downto 0)) * 8),
                      std_logic_vector(shift_left(unsigned'(x"01"), to_integer(ad(2 downto 0)))), FC_COLR);
          end if;
        when FC_CLR =>                          -- CHANGED cleared (flags bit 1)
          if xp24(57) = '1' and fc_changed then
            e := (others => '0');
            e(31 downto 24) := fc_hdr(31 downto 29) & '0' & fc_hdr(27 downto 24);
            mem_write(fc_cell, e, "00001000", FC_NEXT);
          else
            st <= FC_NEXT;
          end if;
        when FC_NEXT =>
          if xp24(49 downto 48) = "10" then fc_x <= fc_x + (fc_w & '0'); else fc_x <= fc_x + fc_w; end if;
          fc_cx <= fc_cx + fc_w;
          fc_col <= fc_col + 1;
          fc_bvalid <= false;
          st <= FC_COLS;

        -- --------------------------------------------------------------
        -- The units' RAM: whichever holds ram_valid (one at a time) gets one
        -- eight-byte transaction; ready (and ram_error) back for one cycle
        when SJ_WAIT =>
          sj_fault <= false;
          if sj_seen_done then
            st <= sj_ret;
          elsif nu_rv = '1' then
            sj_who <= "10";
            if nu_rw = '1' then mem_write(nu_ra, nu_wd, nu_be, SJ_DONE); else mem_read(nu_ra, SJ_DONE); end if;
          elsif co_rv = '1' then
            sj_who <= "00";
            if co_rw = '1' then mem_write(co_ra, co_wd, co_be, SJ_DONE); else mem_read(co_ra, SJ_DONE); end if;
          elsif ce_rv = '1' then
            sj_who <= "01";
            if ce_rw = '1' then mem_write(ce_ra, ce_wd, ce_be, SJ_DONE); else mem_read(ce_ra, SJ_DONE); end if;
          end if;
        when SJ_DONE =>
          sj_rdata <= m_rd;
          if sj_fault then sj_rerr <= '1'; end if;
          case sj_who is
            when "00" => co_rdy <= '1';
            when "01" => ce_rdy <= '1';
            when others => nu_rdy <= '1';
          end case;
          st <= SJ_GAP;
        when SJ_GAP =>                          -- (the unit sees ready now, and moves on)
          st <= SJ_WAIT;

        when others =>
          st <= S_IDLE;
      end case;

      if tws_we then
        tws(tws_wa) <= tws_wd;
      end if;
    end if;
  end process;

end rtl;
