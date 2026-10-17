-- SHITE: Spreadsheet Hardware Integrated Technology Engine
--
-- SSNAIL's coprocessor for opcodes $40-$4F (see docs/shite/README.md and
-- the reference model SSNAIL/shite.py).  SSNAIL hands over its LUMP ports
-- for the length of an instruction (ssnail_top multiplexes them).
--
-- Phase 1: FIND_CELL ($42) and REBALANCE_ROW ($41).  Memory is reached one
-- 8-byte group at a time (no cache yet).

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
    -- FIND_CELL
    F_ROW, F_ROW2, F_HDR, F_HDR2, F_CELL, F_CELL2,
    -- REBALANCE_ROW
    B_ROW, B_ROW2, B_HDR0, B_HDR1, B_HCHK, B_WALK, B_WALK2,
    B_SORT, B_SORT1, B_SORT2, B_SORT3, B_SORT4,
    B_TREE, B_TREE2, B_TREE3, B_TREE4, B_TREE5, B_TREE6, B_TREE7, B_RHDR, B_NEXT,
    -- the list RAM's read (one cycle)
    L_WAIT
    );
  signal st, mem_ret, l_ret : state_t := S_IDLE;

  -- the instruction
  signal r_op : unsigned(7 downto 0) := (others => '0');
  signal r_a, r_b : unsigned(15 downto 0) := (others => '0');
  signal desc : unsigned(27 downto 0) := (others => '0');
  -- the descriptor
  signal rowtab : unsigned(27 downto 0) := (others => '0');
  signal nrows : unsigned(15 downto 0) := (others => '0');
  signal bad_row : unsigned(15 downto 0) := (others => '0');

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
  signal row : unsigned(15 downto 0) := (others => '0');
  signal rlast : unsigned(15 downto 0) := (others => '0');
  signal blk : unsigned(27 downto 0) := (others => '0');
  signal rh0, rh1 : unsigned(63 downto 0) := (others => '0');  -- the row header
  signal g, gfree : unsigned(15 downto 0) := (others => '0');
  signal col : unsigned(15 downto 0) := (others => '0');

  -- REBALANCE's list: per cell, column (63:48), granule (47:32), the
  -- header's bytes 2-3 (kind and flags, length: 31:16).  One write port
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
    procedure format_fault(r : unsigned(15 downto 0)) is
    begin
      bad_row <= r; st <= S_FAULT;
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
      if (hr_wdata_req = '1' and m_is_sd = '0') or (sd_wdata_req = '1' and m_is_sd = '1') then
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
            err <= ERR_NONE; wr <= '0';
            r_op <= op; r_a <= ra(15 downto 0); r_b <= rb(15 downto 0); desc <= x;
            mem_read(x, D_RD0);
          end if;

        when S_FINISH =>
          done <= '1';
          st <= S_IDLE;

        -- ERR_FORMAT: the row into the descriptor (bytes 42-43)
        when S_FAULT =>
          mem_write(desc + 40, x"00000000" & bad_row & x"0000", "00001100", S_FAULT2);
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
            format_fault(x"FFFF");
          else
            rowtab <= m_rd(59 downto 32);
            mem_read(desc + 8, D_RD1);
          end if;
        when D_RD1 =>
          nrows <= m_rd(15 downto 0);
          st <= D_CHK;
        when D_CHK =>
          if abort = '1' then
            fault(ERR_ABORTED);
          elsif r_op = x"42" then                   -- FIND_CELL
            if r_a >= nrows then
              result <= (others => '0'); wr <= '1'; st <= S_FINISH;
            else
              mem_read(rowtab + (r_a & "00"), F_ROW);
            end if;
          elsif r_op = x"41" then                   -- REBALANCE_ROW
            row <= r_a; rlast <= r_b;
            st <= B_ROW;
          else
            fault(ERR_OPCODE);
          end if;

        -- --------------------------------------------------------------
        -- FIND_CELL: the row's block, its root, then the tree
        when F_ROW =>
          if r_a(0) = '0' then e := x"00000000" & m_rd(31 downto 0);
          else e := x"00000000" & m_rd(63 downto 32); end if;
          if e(31 downto 0) = x"FFFFFFFF" then
            result <= (others => '0'); wr <= '1'; st <= S_FINISH;
          else
            blk <= e(27 downto 0);
            mem_read(e(27 downto 0), F_HDR);
          end if;
        when F_HDR =>
          g <= m_rd(63 downto 48);                  -- the root
          st <= F_HDR2;
        when F_HDR2 =>
          if g = 0 then
            result <= (others => '0'); wr <= '1'; st <= S_FINISH;
          else
            mem_read(blk + (g & "0000"), F_CELL);
          end if;
        when F_CELL =>
          col <= m_rd(15 downto 0);
          if m_rd(15 downto 0) = r_b then
            result <= x"0" & (blk + (g & "0000")); wr <= '1'; st <= S_FINISH;
          elsif r_b < m_rd(15 downto 0) then
            g <= m_rd(47 downto 32); st <= F_CELL2;
          else
            g <= m_rd(63 downto 48); st <= F_CELL2;
          end if;
        when F_CELL2 =>
          if abort = '1' then fault(ERR_ABORTED);
          else st <= F_HDR2; end if;

        -- --------------------------------------------------------------
        -- REBALANCE_ROW, rows row..rlast
        when B_ROW =>
          if row > rlast or row >= nrows then
            st <= S_FINISH;
          elsif abort = '1' then
            fault(ERR_ABORTED);
          else
            mem_read(rowtab + (row & "00"), B_ROW2);
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
          -- row number, first free granule within the block
          if rh0(15 downto 0) /= row or rh1(15 downto 0) = 0 or rh1(15 downto 0) > rh0(31 downto 16) then
            format_fault(row);
          else
            gfree <= rh1(15 downto 0);
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
          if m_rd(31 downto 24) = 0 or resize(g, 17) + resize(m_rd(31 downto 24), 17) > resize(gfree, 17) then
            format_fault(row);
          elsif m_rd(19 downto 16) /= K_FREE and l_n = max_row_cells then
            format_fault(row);                  -- (more cells than the list holds)
          else
            if m_rd(19 downto 16) /= K_FREE then
              list(l_n) <= m_rd(15 downto 0) & g & m_rd(31 downto 16) & x"0000";
              l_n <= l_n + 1;
            end if;
            g <= g + m_rd(31 downto 24);
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
          if l_rd(63 downto 48) = l_key(63 downto 48) then
            format_fault(row);                  -- two cells in one column
          elsif l_rd(63 downto 48) > l_key(63 downto 48) then
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
          if first_node then g_root <= l_rd(47 downto 32); end if;
          first_node <= false;
          g_left <= (others => '0'); g_right <= (others => '0');
          if t_lo <= t_mid - 1 then
            l_ra <= mid_of(t_lo, t_mid - 1); l_ret <= B_TREE4; st <= L_WAIT;
          else
            st <= B_TREE5;
          end if;
        when B_TREE4 =>                         -- its left child
          g_left <= l_rd(47 downto 32);
          st <= B_TREE5;
        when B_TREE5 =>
          if t_mid + 1 <= t_hi then
            l_ra <= mid_of(t_mid + 1, t_hi); l_ret <= B_TREE6; st <= L_WAIT;
          else
            st <= B_TREE7;
          end if;
        when B_TREE6 =>                         -- its right child
          g_right <= l_rd(47 downto 32);
          st <= B_TREE7;
        when B_TREE7 =>                         -- the node's header
          mem_write(blk + (l_cur(47 downto 32) & "0000"),
                    g_right & g_left & l_cur(31 downto 16) & l_cur(63 downto 48),
                    "11111111", B_TREE2);

        when B_RHDR =>
          -- cell count and root (bytes 4-7)
          rh0(63 downto 32) <= g_root & to_unsigned(l_n, 16);
          mem_write(blk, g_root & to_unsigned(l_n, 16) & rh0(31 downto 0), "11111111", B_NEXT);
        when B_NEXT =>
          -- the stale flag (bytes 12-13) cleared, if it was set
          if rh1(32) = '1' then
            rh1(32) <= '0';
            mem_write(blk + 8, rh1(63 downto 33) & '0' & rh1(31 downto 0), "11111111", B_NEXT);
          else
            row <= row + 1;
            st <= B_ROW;
          end if;

        when others =>
          st <= S_IDLE;
      end case;
    end if;
  end process;

end rtl;
